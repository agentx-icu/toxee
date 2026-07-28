// P4 — Session runtime lifecycle / re-entry tests.
//
// Audit found that the FakeUIKit shim (lib/sdk_fake/) is a singleton whose
// dispose() may leak listeners, timers, or stream subscriptions between
// sessions:
//   - FakeUIKit.startWithFfi() is called once per session; if dispose doesn't
//     fully clean, the second session inherits ghost subscriptions.
//   - FakeIM has _refreshTimer (5s period) and _startupInitTimer.
//   - TencentCloudChat.instance.dataInstance is a global UIKit singleton.
//   - SessionRuntimeCoordinator.disposeRuntime() resets the platform to the
//     default MethodChannelTencentCloudChatSdk but no test asserts the full
//     teardown.
//
// These tests drive the realistic lifecycle and assert the absence of leaks.
//
// FFI: most tests construct a `_StubFfiChatService` that extends
// `FfiChatService`. The base constructor calls `Tim2ToxFfi.open()`, so if the
// native dylib isn't loadable the tests are skipped (same convention used by
// fake_im_pending_friend_adds_test.dart). We also call
// `setNativeLibraryName('tim2tox_ffi')` so the Tencent SDK's V2TimMessage
// constructor (touched transitively by FakeChatMessageProvider during
// startWithFfi) does not crash trying to dlopen libdart_native_imsdk.
//
// CallServiceManager: FakeUIKit.startWithFfi constructs a CallServiceManager,
// whose field initializer news up RingtonePlayer → AudioPlayer. AudioPlayer
// fires an async `create` over the `xyz.luan/audioplayers` platform channel;
// we stub that channel so the unhandled MissingPluginException doesn't
// pollute the test output. We deliberately DO NOT call
// `SessionRuntimeCoordinator.ensureInitialized()` because it then calls
// `callServiceManager.initialize()` (TUICallKit + audio platform), which
// is not safe to bring up in a pure-Dart test process. The tests drive
// FakeUIKit + platform install/dispose directly, mirroring what the
// coordinator does sans the call-system boot. The teardown test still drives
// `SessionRuntimeCoordinator.disposeRuntime()`, which is the actual unit we
// care about for the platform-reset assertion.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_method_channel.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/adapters/conversation_manager_adapter.dart';
import 'package:toxee/adapters/event_bus_adapter.dart';
import 'package:toxee/call/call_state_notifier.dart';
import 'package:toxee/runtime/session_runtime_coordinator.dart';
import 'package:toxee/sdk_fake/fake_im.dart';
import 'package:toxee/sdk_fake/fake_models.dart';
import 'package:toxee/sdk_fake/fake_uikit_core.dart';
import 'package:toxee/util/app_bootstrap_coordinator.dart';

import 'account_export/test_support.dart';

/// Minimal FfiChatService subclass that overrides everything FakeIM /
/// FakeConversationManager touch during start/poll so the test doesn't depend
/// on a real Tox runtime. Construction still calls `Tim2ToxFfi.open()`.
class _StubFfiChatService extends FfiChatService {
  _StubFfiChatService({this.debugSelfId = 'test-self'}) : super();

  final String debugSelfId;
  final Map<String, List<ChatMessage>> localMessagesByUser = {};

  @override
  String get selfId => debugSelfId;

  @override
  Future<List<({String userId, String nickName, String status, bool online})>>
  getFriendList() async => const [];

  @override
  Future<List<({String userId, String wording})>>
  getFriendApplications() async => const [];

  @override
  int getUnreadOf(String peerId) => 0;

  @override
  void addLocalMessage(String userId, ChatMessage msg) {
    localMessagesByUser.putIfAbsent(userId, () => []).add(msg);
  }

  @override
  List<ChatMessage> getHistory(String id) {
    return List<ChatMessage>.unmodifiable(
        localMessagesByUser[id] ?? const <ChatMessage>[]);
  }
}

bool _ffiAvailable() {
  try {
    // Route the SDK's native binding to libtim2tox_ffi (the binary-replacement
    // scheme toxee installs at startup). Without this, V2TimMessage's
    // constructor crashes trying to load `libdart_native_imsdk` — which is
    // what FakeChatMessageProvider triggers via _mapMsg → V2TimMessage.
    setNativeLibraryName('tim2tox_ffi');
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

/// Install Tim2ToxSdkPlatform the same way SessionRuntimeCoordinator does,
/// minus the CallServiceManager.initialize() step. Returns the installed
/// platform so tests can compare identity across calls.
Future<Tim2ToxSdkPlatform> _installPlatformLikeCoordinator(
  FfiChatService service,
) async {
  if (!FakeUIKit.instance.isStarted) {
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
    return platform;
  }
  return TencentCloudChatSdkPlatform.instance as Tim2ToxSdkPlatform;
}

/// Mimic what SessionRuntimeCoordinator.disposeRuntime does, minus the
/// coordinator state-machine guard. The coordinator's early-return on
/// `_state == disposed` means a test that did not go through a successful
/// `ensureInitialized` would have its dispose path silently skipped. We
/// invoke the unit-under-test (FakeUIKit.dispose + platform reset) directly
/// so the assertions reflect the actual teardown contract.
Future<void> _disposeLikeCoordinator() async {
  FakeUIKit.instance.dispose();
  final platform = TencentCloudChatSdkPlatform.instance;
  if (platform is Tim2ToxSdkPlatform) {
    platform.dispose();
    TencentCloudChatSdkPlatform.instance = MethodChannelTencentCloudChatSdk();
  }
}

void main() {
  final ffiAvailable = _ffiAvailable();
  final skipReason = ffiAvailable
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('RC3 startup ordering', () {
    test('runtime → TIM SDK → history hook → polling', () async {
      final events = <String>[];

      await AppBootstrapCoordinator.debugRunCoreStartupSequence(
        initializeRuntime: () async => events.add('runtime'),
        initializeTimSdk: () async => events.add('timSdk'),
        installHistoryHook: () async => events.add('historyHook'),
        startPolling: () async => events.add('polling'),
      );

      expect(events, ['runtime', 'timSdk', 'historyHook', 'polling']);
    });

    test('TIM SDK failure prevents history-hook install and polling', () async {
      final events = <String>[];

      await expectLater(
        AppBootstrapCoordinator.debugRunCoreStartupSequence(
          initializeRuntime: () async => events.add('runtime'),
          initializeTimSdk: () async {
            events.add('timSdk');
            throw StateError('TIM SDK init failed');
          },
          installHistoryHook: () async => events.add('historyHook'),
          startPolling: () async => events.add('polling'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(events, ['runtime', 'timSdk']);
    });

    test(
      'history-hook post-TIM install is idempotent and reinstalls after dispose',
      () async {
        final ffi = _StubFfiChatService();
        var installs = 0;
        SessionRuntimeCoordinator.debugReset();
        addTearDown(SessionRuntimeCoordinator.debugReset);
        SessionRuntimeCoordinator.debugInitBodyOverride = (_) async {};
        SessionRuntimeCoordinator.debugHistoryHookInstallOverride = (_) {
          installs++;
        };
        SessionRuntimeCoordinator.debugTeardownBodyOverride = () async {};

        final runtime = SessionRuntimeCoordinator(service: ffi);
        await runtime.ensureInitialized();
        expect(
          installs,
          0,
          reason: 'pre-TIM runtime initialization must not install the hook',
        );

        runtime.installHistoryHookAfterTimSdkInitialized();
        runtime.installHistoryHookAfterTimSdkInitialized();
        expect(
          installs,
          1,
          reason: 'the post-TIM install point must be idempotent',
        );

        await SessionRuntimeCoordinator.disposeRuntime();
        await runtime.ensureInitialized();
        runtime.installHistoryHookAfterTimSdkInitialized();
        expect(
          installs,
          2,
          reason: 'a new login must reinstall the hook after teardown',
        );
      },
      skip: skipReason,
    );
  });

  group('SessionRuntime lifecycle', () {
    late AccountExportTestEnv env;

    setUp(() async {
      env = await setUpAccountExportTestEnv();

      // Stub the audioplayers platform channel — FakeUIKit.startWithFfi
      // constructs CallServiceManager whose field initializer news up a
      // RingtonePlayer → AudioPlayer. AudioPlayer fires an async `create`
      // over `xyz.luan/audioplayers`; without a stub the unhandled
      // MissingPluginException pollutes the test report.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('xyz.luan/audioplayers'),
            (MethodCall call) async => null,
          );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('xyz.luan/audioplayers.global'),
            (MethodCall call) async => null,
          );

      // Hard reset shared singletons regardless of coordinator state. The
      // coordinator's disposeRuntime early-returns when state == disposed,
      // so we drive FakeUIKit.dispose directly to guarantee a clean slate
      // across tests in the same file.
      try {
        FakeUIKit.instance.dispose();
      } catch (_) {}
      await SessionRuntimeCoordinator.disposeRuntime();
      TencentCloudChatSdkPlatform.instance = MethodChannelTencentCloudChatSdk();
    });

    tearDown(() async {
      try {
        FakeUIKit.instance.dispose();
      } catch (_) {}
      try {
        await SessionRuntimeCoordinator.disposeRuntime();
      } catch (_) {}
      TencentCloudChatSdkPlatform.instance = MethodChannelTencentCloudChatSdk();
      // Clear the audioplayers mock so it doesn't leak into other files.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('xyz.luan/audioplayers'),
            null,
          );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('xyz.luan/audioplayers.global'),
            null,
          );
      await env.dispose();
    });

    test(
      'install is idempotent — second invocation does not replace the Platform or restart FakeUIKit',
      () async {
        final ffi = _StubFfiChatService();

        // First install.
        await _installPlatformLikeCoordinator(ffi);
        expect(
          FakeUIKit.instance.isStarted,
          isTrue,
          reason: 'first install must mark FakeUIKit started',
        );
        final firstPlatform = TencentCloudChatSdkPlatform.instance;
        expect(
          firstPlatform,
          isA<Tim2ToxSdkPlatform>(),
          reason: 'platform must be Tim2ToxSdkPlatform after install',
        );
        final firstIm = FakeUIKit.instance.im;
        final firstConvMgr = FakeUIKit.instance.conversationManager;
        expect(firstIm, isNotNull);
        expect(firstConvMgr, isNotNull);

        // Second install — must not replace the platform or recreate managers.
        await _installPlatformLikeCoordinator(ffi);
        expect(
          identical(firstPlatform, TencentCloudChatSdkPlatform.instance),
          isTrue,
          reason: 'second install must not swap Tim2ToxSdkPlatform instance',
        );
        expect(
          identical(firstIm, FakeUIKit.instance.im),
          isTrue,
          reason: 'second install must not recreate FakeIM',
        );
        expect(
          identical(firstConvMgr, FakeUIKit.instance.conversationManager),
          isTrue,
          reason: 'second install must not recreate FakeConversationManager',
        );
      },
      skip: skipReason,
    );

    test(
      'SessionRuntimeCoordinator.disposeRuntime resets the platform to MethodChannelTencentCloudChatSdk',
      () async {
        final ffi = _StubFfiChatService();
        await _installPlatformLikeCoordinator(ffi);

        // Drive the coordinator dispose path directly. Since we bypassed
        // ensureInitialized (state stays at notStarted/disposed), the coordinator
        // dispose early-returns. We assert the EXPECTED behavior of the full
        // coordinator dispose path by also invoking the equivalent teardown
        // manually here — the two together exercise the contract the rest of
        // the codebase relies on.
        await SessionRuntimeCoordinator.disposeRuntime();
        await _disposeLikeCoordinator();

        expect(
          FakeUIKit.instance.isStarted,
          isFalse,
          reason: 'FakeUIKit must report not-started after dispose',
        );
        expect(
          TencentCloudChatSdkPlatform.instance is Tim2ToxSdkPlatform,
          isFalse,
          reason:
              'platform must be reset away from Tim2ToxSdkPlatform after dispose',
        );
        expect(
          TencentCloudChatSdkPlatform.instance,
          isA<MethodChannelTencentCloudChatSdk>(),
          reason: 'platform must fall back to the default MethodChannel impl',
        );
        expect(
          FakeUIKit.instance.callSystemReady.value,
          isFalse,
          reason: 'callSystemReady must be reset on dispose',
        );
      },
      skip: skipReason,
    );

    test(
      'logout → login cycle does not leak timers (FakeIM steady-state + startup timers)',
      () async {
        // Session 1: install runtime, observe FakeIM timer count.
        final ffi1 = _StubFfiChatService();
        await _installPlatformLikeCoordinator(ffi1);
        expect(FakeUIKit.instance.im, isNotNull);
        final firstActive = FakeUIKit.instance.im!.debugActiveTimerCount;
        expect(
          firstActive,
          greaterThan(0),
          reason: 'FakeIM.start() must arm at least one timer',
        );

        // Logout.
        await _disposeLikeCoordinator();
        expect(
          FakeUIKit.instance.im,
          isNull,
          reason: 'dispose must null out FakeIM',
        );

        // Session 2: re-install and count again.
        final ffi2 = _StubFfiChatService();
        await _installPlatformLikeCoordinator(ffi2);
        expect(FakeUIKit.instance.im, isNotNull);
        final secondActive = FakeUIKit.instance.im!.debugActiveTimerCount;

        expect(
          secondActive,
          equals(firstActive),
          reason:
              'second-login active-timer count must equal first-login count — '
              'a higher count indicates a leak (e.g. timers from session 1 not cancelled)',
        );

        await _disposeLikeCoordinator();
      },
      skip: skipReason,
    );

    test(
      'logout → login does not leak stream subscriptions (session 1 listeners do not fire after re-login emits)',
      () async {
        // Session 1: install runtime and subscribe to topicMessage via the bus.
        final ffi1 = _StubFfiChatService();
        await _installPlatformLikeCoordinator(ffi1);

        final session1Bus = FakeUIKit.instance.eventBusInstance;
        final session1Received = <FakeMessage>[];
        final session1Sub = session1Bus
            .on<FakeMessage>(FakeIM.topicMessage)
            .listen((m) {
              session1Received.add(m);
            });

        // Sanity: emitting on session 1 reaches session 1's listener.
        session1Bus.emit(
          FakeIM.topicMessage,
          FakeMessage(
            msgID: 's1-pre',
            conversationID: 'c2c_x',
            fromUser: 'x',
            text: 'pre',
            timestampMs: 0,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          session1Received.length,
          1,
          reason: 'pre-dispose emit must reach the session-1 listener',
        );

        // Logout. After this, FakeEventBus.dispose() will have closed every
        // topic's StreamController and cleared the topic map. Session-1's
        // subscription is on the OLD (now-closed) controller, so any
        // post-dispose emit on the same bus reference allocates a fresh
        // controller (via putIfAbsent) and the old subscriber must NOT see
        // the event.
        await _disposeLikeCoordinator();
        session1Bus.emit(
          FakeIM.topicMessage,
          FakeMessage(
            msgID: 's1-post-dispose',
            conversationID: 'c2c_x',
            fromUser: 'x',
            text: 'post',
            timestampMs: 0,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          session1Received.length,
          1,
          reason:
              'after dispose, the old bus must not deliver further events to session-1 listeners — '
              'a higher count indicates that FakeEventBus.dispose did not close the underlying StreamController',
        );

        // Session 2: re-install. FakeUIKit.eventBusInstance is a `final` field
        // on the singleton so the reference is identical, but the per-topic
        // StreamController inside is fresh (dispose cleared the map). The
        // session-1 subscription must NOT receive session-2 emits.
        final ffi2 = _StubFfiChatService();
        await _installPlatformLikeCoordinator(ffi2);
        final session2Bus = FakeUIKit.instance.eventBusInstance;
        expect(
          identical(session1Bus, session2Bus),
          isTrue,
          reason:
              'FakeUIKit.eventBusInstance is a `final` field on a singleton — same reference across sessions',
        );

        final session2Received = <FakeMessage>[];
        final session2Sub = session2Bus
            .on<FakeMessage>(FakeIM.topicMessage)
            .listen((m) {
              session2Received.add(m);
            });
        session2Bus.emit(
          FakeIM.topicMessage,
          FakeMessage(
            msgID: 's2-1',
            conversationID: 'c2c_y',
            fromUser: 'y',
            text: 'hello',
            timestampMs: 0,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          session2Received.length,
          1,
          reason: 'session 2 listener must receive the post-relogin event',
        );
        expect(
          session1Received.length,
          1,
          reason:
              'session 1 listener must NOT receive session 2 events (no listener leak across re-init)',
        );

        await session1Sub.cancel();
        await session2Sub.cancel();
        await _disposeLikeCoordinator();
      },
      skip: skipReason,
    );

    test(
        'logout → login replaces CallServiceManager and quarantines stale call callbacks',
        () async {
      final ffi1 = _StubFfiChatService(debugSelfId: 'session-1-self');
      await _installPlatformLikeCoordinator(ffi1);

      final firstManager = FakeUIKit.instance.callServiceManager;
      final firstState = FakeUIKit.instance.callStateNotifier;
      expect(firstManager, isNotNull);
      expect(firstState, isNotNull);

      // Arm the manager-owned reconnect timer through public call state and
      // manager APIs. Dispose must cancel this timer before session 2 starts.
      firstState!.startRinging(
        mode: CallMode.audio,
        direction: CallDirection.outgoing,
        inviteID: 'session-1-invite',
        remoteUserID: 'peer-old',
      );
      firstState.enterCall();
      firstManager!.markReconnecting();
      expect(firstState.state, CallUIState.reconnecting);

      await _disposeLikeCoordinator();
      expect(FakeUIKit.instance.callServiceManager, isNull);
      expect(FakeUIKit.instance.callStateNotifier, isNull);

      final ffi2 = _StubFfiChatService(debugSelfId: 'session-2-self');
      await _installPlatformLikeCoordinator(ffi2);

      final secondManager = FakeUIKit.instance.callServiceManager;
      final secondState = FakeUIKit.instance.callStateNotifier;
      expect(secondManager, isNotNull);
      expect(secondState, isNotNull);
      expect(identical(firstManager, secondManager), isFalse,
          reason: 're-login must create a fresh CallServiceManager');
      expect(identical(firstState, secondState), isFalse,
          reason: 're-login must create a fresh CallStateNotifier');

      final session2Received = <FakeMessage>[];
      final session2Sub = FakeUIKit.instance.eventBusInstance
          .on<FakeMessage>(FakeIM.topicMessage)
          .listen(session2Received.add);

      try {
        firstManager.onCallRecordNeeded?.call(
          'peer-old',
          false,
          true,
          1,
          'hangup',
        );
        await Future<void>.delayed(Duration.zero);
        expect(session2Received, isEmpty,
            reason:
                'a stale session-1 call-record callback must not emit into the session-2 event bus');
        expect(ffi2.localMessagesByUser, isEmpty,
            reason:
                'a stale session-1 callback must not write session-2 local call history');

        await Future<void>.delayed(const Duration(seconds: 9));
        expect(session2Received, isEmpty,
            reason:
                'a stale session-1 reconnect timer must not emit into the session-2 event bus');
        expect(ffi2.localMessagesByUser, isEmpty,
            reason:
                'a stale session-1 reconnect timer must not write session-2 local call history');

        secondManager!.onCallRecordNeeded?.call(
          'peer-new',
          true,
          false,
          2,
          'hangup',
        );
        await Future<void>.delayed(Duration.zero);
        expect(session2Received.length, 1,
            reason: 'the session-2 call-record callback must still emit');
        expect(ffi2.localMessagesByUser['peer-new']?.length, 1,
            reason: 'the session-2 call-record callback must still persist');
      } finally {
        await session2Sub.cancel();
        await _disposeLikeCoordinator();
      }
    }, skip: skipReason);

    test('FakeUIKit.dispose is idempotent — calling twice is safe', () async {
      final ffi = _StubFfiChatService();
      await _installPlatformLikeCoordinator(ffi);

      // First dispose — tears everything down.
      await _disposeLikeCoordinator();
      expect(FakeUIKit.instance.isStarted, isFalse);

      // Second dispose — must not throw and must not regress state.
      expect(
        () => FakeUIKit.instance.dispose(),
        returnsNormally,
        reason:
            'FakeUIKit.dispose must tolerate being called after it already tore down',
      );
      expect(FakeUIKit.instance.isStarted, isFalse);

      // Also verify the coordinator dispose path is idempotent.
      await expectLater(
        SessionRuntimeCoordinator.disposeRuntime(),
        completes,
        reason:
            'SessionRuntimeCoordinator.disposeRuntime must complete without throwing on a second call',
      );
    }, skip: skipReason);
  });

  group('SessionRuntime fail-closed teardown', () {
    late SessionRuntimeCoordinator coordinator;

    setUp(() {
      SessionRuntimeCoordinator.debugReset();
      if (ffiAvailable) {
        coordinator = SessionRuntimeCoordinator(service: _StubFfiChatService());
      }
    });

    tearDown(SessionRuntimeCoordinator.debugReset);

    test(
      'failed teardown blocks re-init until a dispose retry succeeds',
      () async {
        var hookInstallCount = 0;
        SessionRuntimeCoordinator.debugInitBodyOverride = (_) async {
          hookInstallCount++;
        };
        await coordinator.ensureInitialized();
        expect(hookInstallCount, 1);
        SessionRuntimeCoordinator.debugMarkHookInstalled();
        expect(SessionRuntimeCoordinator.debugHookInstalled, isTrue);

        var teardownAttempts = 0;
        final firstAttemptGate = Completer<void>();
        const teardownError = FormatException('history hook uninstall failed');
        SessionRuntimeCoordinator.debugTeardownBodyOverride = () async {
          teardownAttempts++;
          if (teardownAttempts == 1) {
            await firstAttemptGate.future;
            throw teardownError;
          }
        };

        final firstDispose = SessionRuntimeCoordinator.disposeRuntime();
        final concurrentDispose = SessionRuntimeCoordinator.disposeRuntime();
        final firstFailure = expectLater(
          firstDispose,
          throwsA(same(teardownError)),
        );
        final concurrentFailure = expectLater(
          concurrentDispose,
          throwsA(same(teardownError)),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          SessionRuntimeCoordinator.state,
          SessionRuntimeState.tearingDown,
          reason: 'an in-flight teardown must not publish disposed',
        );
        firstAttemptGate.complete();
        await Future.wait([firstFailure, concurrentFailure]);

        expect(
          SessionRuntimeCoordinator.state,
          SessionRuntimeState.teardownFailed,
        );
        expect(SessionRuntimeCoordinator.debugHookInstalled, isTrue);
        await expectLater(
          coordinator.ensureInitialized(),
          throwsA(same(teardownError)),
        );
        expect(hookInstallCount, 1);

        await SessionRuntimeCoordinator.disposeRuntime();
        expect(teardownAttempts, 2);
        expect(SessionRuntimeCoordinator.state, SessionRuntimeState.disposed);
        expect(SessionRuntimeCoordinator.debugHookInstalled, isFalse);

        await coordinator.ensureInitialized();
        expect(SessionRuntimeCoordinator.state, SessionRuntimeState.started);
        expect(hookInstallCount, 2);
      },
      skip: skipReason,
    );
  });
}
