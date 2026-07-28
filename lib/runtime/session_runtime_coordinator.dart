import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_method_channel.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/utils/binary_replacement_history_hook.dart';

import '../adapters/conversation_manager_adapter.dart';
import '../adapters/event_bus_adapter.dart';
import '../adapters/logger_adapter.dart';
import '../call/bg_refresh_bridge.dart';
import '../call/call_media_capabilities.dart';
import '../notifications/badge_service.dart';
import '../notifications/notification_message_listener.dart';
import '../notifications/notification_service.dart';
import '../sdk_fake/fake_uikit_core.dart';
import '../sdk_fake/uikit_data_facade.dart';
import '../util/logger.dart';
import '../util/safe_diagnostics.dart';
import 'runtime_foreground_service.dart';

part 'session_runtime_teardown.dart';

enum SessionRuntimeState {
  notStarted,
  starting,
  started,
  tearingDown,
  teardownFailed,
  disposed,
}

/// Coordinates session-level runtime: FakeUIKit, TencentCloudChatSdkPlatform,
/// and CallServiceManager. [ensureInitialized] is idempotent; [disposeRuntime]
/// is called on teardown (e.g. from AccountService).
class SessionRuntimeCoordinator {
  SessionRuntimeCoordinator({required this.service});

  final FfiChatService service;

  static SessionRuntimeState _state = SessionRuntimeState.notStarted;
  static Future<void>? _initializing;

  /// Non-null for the ENTIRE duration of a [disposeRuntime] (including its
  /// async teardown tail), until teardown either succeeds or fails closed.
  /// [ensureInitialized] awaits this before claiming the critical section, so
  /// a re-init started mid-teardown can't run its body interleaved with the
  /// teardown (and get clobbered by the teardown tail). Concurrent
  /// [disposeRuntime] calls coalesce onto it.
  static Future<void>? _disposing;

  /// Retained so later initialization attempts fail with the original
  /// teardown error until a retry finishes every cleanup stage.
  static Object? _teardownError;
  static StackTrace? _teardownStackTrace;

  /// Monotonic token bumped by [disposeRuntime]. [ensureInitialized] captures
  /// it after claiming the critical section and refuses to publish the
  /// `started` state if a concurrent dispose superseded it — so a logout /
  /// account-switch that lands mid-init can't be clobbered back to `started`.
  static int _generation = 0;

  /// Whether the [BinaryReplacementHistoryHook] has been installed by this
  /// coordinator for the current session. Reset by [disposeRuntime] so a
  /// post-logout re-init reinstalls the hook against the new selfId.
  static bool _hookInstalled = false;

  /// Pending one-shot subscription that waits for selfId to become available
  /// (post-login) before installing the hook. Cancelled by [disposeRuntime].
  static StreamSubscription<bool>? _pendingHookSelfIdSub;

  static SessionRuntimeState get state => _state;

  @visibleForTesting
  static bool get debugHookInstalled => _hookInstalled;

  @visibleForTesting
  static void debugMarkHookInstalled() => _hookInstalled = true;

  /// Test seam: when non-null, [ensureInitialized] runs this instead of the
  /// real init body ([_performInit]) — the FakeUIKit / platform /
  /// callServiceManager / badge installs that aren't safe to bring up in a
  /// pure-Dart test process. The surrounding serialization logic (the
  /// loop, [_disposing] gating, generation guard, `started` commit) still
  /// runs for real, which is what concurrency tests exercise. Null in
  /// production.
  @visibleForTesting
  static Future<void> Function(FfiChatService service)? debugInitBodyOverride;

  /// Test seam: when non-null, [_runTeardown] runs this instead of the real
  /// teardown work (hook uninstall, BadgeService/FakeUIKit dispose, platform
  /// swap, …) after the generation bump and `await _initializing`. Lifecycle
  /// state and hook-guard commits still run for real. Null in production.
  @visibleForTesting
  static Future<void> Function()? debugTeardownBodyOverride;

  /// Test seam for the post-TIM history-hook install. The lifecycle and
  /// idempotency guards still run for real; only the SDK listener registration
  /// is replaced. Null in production.
  @visibleForTesting
  static void Function(FfiChatService service)? debugHistoryHookInstallOverride;

  /// Test seam: reset all static lifecycle state to its initial values so each
  /// test starts from a clean slate without depending on the real teardown
  /// (which touches singletons). Does NOT touch FakeUIKit / the platform —
  /// callers that installed those should reset them separately.
  @visibleForTesting
  static void debugReset() {
    _state = SessionRuntimeState.notStarted;
    _initializing = null;
    _disposing = null;
    _teardownError = null;
    _teardownStackTrace = null;
    _generation = 0;
    _hookInstalled = false;
    _pendingHookSelfIdSub = null;
    debugInitBodyOverride = null;
    debugTeardownBodyOverride = null;
    debugHistoryHookInstallOverride = null;
  }

  /// Initializes session runtime if not already started. Idempotent.
  /// Concurrent callers await the same in-flight initialization.
  /// After [disposeRuntime] (e.g. logout/account switch), calling this again
  /// re-initializes the runtime for the new session.
  Future<void> ensureInitialized() async {
    // Serialize against init/dispose interleavings on the shared static state.
    // The whole method is a loop because any await can change the world out
    // from under us:
    //   - an in-flight disposeRuntime() (which holds [_disposing] for its
    //     ENTIRE teardown) must fully finish before we run our init body, or
    //     its teardown tail (FakeUIKit.dispose / platform swap) clobbers what
    //     we install (#4);
    //   - an init — whether one we JOINED or our OWN — can be superseded by a
    //     concurrent dispose and bail at the generation guard without
    //     publishing `started`; rather than return a false success against a
    //     disposed runtime (#3), we re-evaluate from the top (which first
    //     waits out the dispose) and re-init.
    while (true) {
      final disposing = _disposing;
      if (disposing != null) {
        await disposing;
        continue;
      }
      if (_state == SessionRuntimeState.teardownFailed) {
        final error = _teardownError;
        if (error != null) {
          Error.throwWithStackTrace(
            error,
            _teardownStackTrace ?? StackTrace.current,
          );
        }
        throw StateError('Session runtime teardown is incomplete');
      }
      if (_state == SessionRuntimeState.started) return;
      final inFlight = _initializing;
      if (inFlight != null) {
        // A throw here (the joined init errored) propagates to this caller,
        // matching the previous behavior; a normal completion means the init
        // finished — loop to see whether it actually reached `started`.
        await inFlight;
        continue;
      }

      // notStarted or disposed, and nothing in flight → we own the next init.
      if (_state == SessionRuntimeState.disposed) {
        AppLogger.debug(
          '[SessionRuntimeCoordinator] Re-initializing after teardown',
        );
      }

      // Claim the critical section: assign _initializing BEFORE flipping
      // _state to starting. The claim is synchronous (no await between the
      // loop checks above and here), so concurrent observers see either
      // notStarted/disposed (proceed) or starting + non-null _initializing
      // (join in-flight) — never starting + null _initializing.
      final completer = Completer<void>();
      _initializing = completer.future;
      _state = SessionRuntimeState.starting;
      final myGeneration = _generation;

      try {
        final initOverride = debugInitBodyOverride;
        if (initOverride != null) {
          await initOverride(service);
        } else {
          await _performInit();
        }

        // CR-02: a concurrent disposeRuntime() (logout / account switch)
        // bumped the generation while we were initializing. Do NOT publish
        // `started`. Complete the completer (so dispose, which awaits it, can
        // proceed to tear down), then loop: the top of the loop will wait out
        // the dispose via [_disposing] and re-init cleanly afterwards (#3).
        if (_generation != myGeneration ||
            _state != SessionRuntimeState.starting) {
          completer.complete();
          continue;
        }
        _state = SessionRuntimeState.started;
        completer.complete();
        return;
      } catch (e, st) {
        _state = SessionRuntimeState.notStarted;
        completer.completeError(e, st);
        rethrow;
      } finally {
        _initializing = null;
      }
      // callSystemReady is set by FakeUIKit.startWithFfi() via
      // addPostFrameCallback to avoid "setState()/markNeedsBuild() during
      // build".
    }
  }

  /// The real init body: start FakeUIKit, install the Tim2Tox platform, bring
  /// up the call service, and start the badge. The history hook is installed
  /// separately by [installHistoryHookAfterTimSdkInitialized], only after
  /// TIMManager initialization succeeds.
  /// Factored out of [ensureInitialized] so [debugInitBodyOverride] can replace
  /// it in tests; the serialization logic around it stays in
  /// [ensureInitialized].
  Future<void> _performInit() async {
    if (!FakeUIKit.instance.isStarted) {
      // Async since A7: awaits initial pinned-conversation read so the
      // platform bridge installed below never sees an empty pinned set.
      await FakeUIKit.instance.startWithFfi(service);
    }

    if (TencentCloudChatSdkPlatform.instance is! Tim2ToxSdkPlatform) {
      final eventBusAdapter = EventBusAdapter(
        FakeUIKit.instance.eventBusInstance,
      );
      final conversationManagerAdapter = ConversationManagerAdapter(
        FakeUIKit.instance.conversationManager!,
      );
      final platform = Tim2ToxSdkPlatform(
        ffiService: service,
        eventBusProvider: eventBusAdapter,
        conversationManagerProvider: conversationManagerAdapter,
      );
      TencentCloudChatSdkPlatform.instance = platform;
      platform.onGroupMessageReceivedForUnread = (groupId) {
        if (groupId != null && groupId.isNotEmpty) {
          service.incrementGroupUnread(groupId);
        }
        FakeUIKit.instance.im?.refreshConversations();
        FakeUIKit.instance.im?.refreshUnreadTotal();
      };
      // The platform listener above now OWNS group-unread accrual: every group
      // message (native OR Dart poll / l3-inject) re-enters
      // `ffiService.messages.listen` and bumps via incrementGroupUnread. Tell
      // FfiChatService so its `ingestInboundGroupText` does NOT also bump
      // directly — otherwise Dart-path group messages count twice (observed
      // live: a single group inject inflated the sidebar unread to 2).
      service.groupUnreadHandledExternally = true;
      // After a conversation is marked read via the "mark as read" menu item
      // (cleanConversationUnreadMessageCount → markConversationRead), refresh
      // the conversation list + unread badge so the cleared count surfaces in
      // the sidebar without the user opening the conversation. The unread
      // ground truth (ffi.getUnreadOf) is already zeroed by markConversationRead.
      platform.onConversationUnreadCleared = (_) {
        FakeUIKit.instance.im?.refreshConversations();
        FakeUIKit.instance.im?.refreshUnreadTotal();
      };
      AppLogger.debug(
        '[SessionRuntimeCoordinator] Set TencentCloudChatSdkPlatform to Tim2ToxSdkPlatform',
      );
    }

    await FakeUIKit.instance.callServiceManager?.initialize();
    // Only surface call buttons when the native library actually contains a
    // ToxAV backend — a stub build (BUILD_TOXAV off) no-ops every call API,
    // so offering the UI would be a silent failure.
    final callingAvailable =
        FakeUIKit.instance.callServiceManager?.isCallingAvailable ?? false;
    UikitDataFacade.setUseCallKit(callingAvailable);
    // Video entry points additionally require a camera capture backend
    // (absent on Windows/Linux) — voice-only there, not a dead video button.
    UikitDataFacade.setUseVideoCall(
      callingAvailable && CallMediaCapabilities.supportsVideoCapture(),
    );
    if (!callingAvailable) {
      AppLogger.warn(
        '[SessionRuntimeCoordinator] calling disabled: native library has '
        'no ToxAV backend',
      );
    }

    // OS-level dock/launcher unread badge. Subscribes to the same bus topic
    // UIKit's conversation listener uses (FakeIM.topicUnread) and debounces
    // writes so a burst of poll-driven emits collapses to one platform-channel
    // call. Idempotent — see BadgeService.start.
    final im = FakeUIKit.instance.im;
    if (im != null) {
      BadgeService.instance.start(
        bus: FakeUIKit.instance.eventBusInstance,
        im: im,
      );
    }
  }

  /// Call on session teardown (e.g. logout). Resets runtime state.
  ///
  /// Holds [_disposing] for the ENTIRE teardown so a concurrent
  /// [ensureInitialized] blocks at its top until teardown finishes instead of
  /// re-installing platform/badge/hook midway and having the teardown tail
  /// clobber them (#4). Concurrent dispose calls coalesce onto the in-flight
  /// one.
  static Future<void> disposeRuntime() {
    final inFlightDispose = _disposing;
    if (inFlightDispose != null) return inFlightDispose;
    if (_state == SessionRuntimeState.disposed) return Future<void>.value();

    final disposeCompleter = Completer<void>();
    final disposeFuture = disposeCompleter.future;
    _disposing = disposeFuture;
    unawaited(() async {
      try {
        await _runSessionRuntimeTeardown();
        disposeCompleter.complete();
      } catch (error, stackTrace) {
        disposeCompleter.completeError(error, stackTrace);
      } finally {
        if (identical(_disposing, disposeFuture)) {
          _disposing = null;
        }
      }
    }());
    return disposeFuture;
  }

  /// Installs the history listener after TIMManager initialization succeeds.
  /// Idempotent within a session; [disposeRuntime] clears the guard so the next
  /// login installs a listener bound to its own service and selfId.
  void installHistoryHookAfterTimSdkInitialized() {
    if (_state != SessionRuntimeState.started) {
      throw StateError(
        'Session runtime must be started before installing the history hook',
      );
    }
    _installBinaryReplacementHistoryHook();
  }

  /// Installs the binary-replacement history hook as a standalone, independent
  /// V2TimAdvancedMsgListener that persists every received/modified message
  /// exactly once. This listener does NOT wrap or replace any UIKit listener,
  /// so every other registered listener continues to receive callbacks
  /// unmolested. (Pre-H1 the coordinator wrapped `currentListeners.first` — a
  /// race-prone path that silenced any listener registered before the hook
  /// installed and silently let later listeners persist nothing.)
  ///
  /// M6: installation happens immediately, even if `selfId` is still empty,
  /// so no binary-replacement event can arrive before persistence coverage is
  /// in place. When selfId becomes known via the connection event, we call
  /// [BinaryReplacementHistoryHook.updateSelfId] to plug it in. Idempotent
  /// within a session via [_hookInstalled]; reset by [disposeRuntime].
  void _installBinaryReplacementHistoryHook() {
    if (_hookInstalled) return;
    try {
      final installOverride = debugHistoryHookInstallOverride;
      if (installOverride != null) {
        installOverride(service);
        _hookInstalled = true;
        return;
      }
      // Always install immediately — passes a placeholder if selfId is not
      // yet known. The saveMessage path guards against an empty selfId
      // already (no isSelf can be resolved), so worst case is a single early
      // message gets dropped instead of mis-attributed.
      final selfId = service.selfId;
      BinaryReplacementHistoryHook.installStandalone(
        service.messageHistoryPersistence,
        selfId,
        logger: AppLoggerAdapter(),
      );
      // S29: wire the block predicate so the binary-replacement persist path
      // also drops inbound C2C from a blocked sender (the same guard lives in
      // FfiChatService._appendHistory, which this direct-persist path bypasses).
      BinaryReplacementHistoryHook.isBlockedPredicate = service.isBlocked;
      _hookInstalled = true;
      AppLogger.debug(
        '[SessionRuntimeCoordinator] BinaryReplacementHistoryHook installed (standalone, selfId=${selfId.isEmpty ? "<deferred>" : "<set>"})',
      );

      if (selfId.isEmpty) {
        // Plug in the real selfId as soon as the first connected event with
        // a non-empty selfId arrives. We don't re-install the listener.
        _pendingHookSelfIdSub?.cancel();
        _pendingHookSelfIdSub = service.connectionStatusStream
            .where((connected) => connected && service.selfId.isNotEmpty)
            .take(1)
            .listen((_) {
              BinaryReplacementHistoryHook.updateSelfId(service.selfId);
              AppLogger.debug(
                '[SessionRuntimeCoordinator] BinaryReplacementHistoryHook selfId updated',
              );
            });
      }
    } catch (e, st) {
      // CR-03: history persistence on the binary-replacement path is a
      // single source of truth and required startup work. A silent
      // failure here would leave the app "ready" while messages silently
      // fail to persist. Fail the whole init so the caller tears down and
      // surfaces the error instead.
      AppLogger.logError(
        '[SessionRuntimeCoordinator] history hook install failed — failing runtime init',
        e,
        st,
      );
      rethrow;
    }
  }
}
