import 'dart:async';

// ignore: directives_ordering
import 'widgets/safe_dialog_pop.dart';
import 'widgets/mac_title_bar_inset.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../util/app_spacing.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../util/disposable_bag.dart';
import '../util/prefs.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import '../util/locale_controller.dart';
import '../util/tox_utils.dart';
import '../util/theme_controller.dart';
import '../sdk_fake/fake_uikit_core.dart';
import '../sdk_fake/fake_models.dart';
import '../sdk_fake/fake_im.dart';
import '../sdk_fake/fake_provider.dart';
import '../sdk_fake/uikit_data_facade.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import '../runtime/session_runtime_coordinator.dart';
import '../runtime/tim_sdk_initializer.dart';
import 'package:tencent_cloud_chat_common/external/chat_data_provider.dart';
import '../sdk_fake/fake_msg_provider.dart';
import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_navigator.dart'
    show navigateToMessage;
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_callbacks.dart';
import 'package:tencent_cloud_chat_common/tuicore/tencent_cloud_chat_core.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_controller.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation.dart'
    as conv_pkg;
import 'package:tencent_cloud_chat_conversation/widgets/tencent_cloud_chat_conversation_item.dart';
import 'package:tencent_cloud_chat_conversation/widgets/tencent_cloud_chat_conversation_app_bar.dart'
    show TencentCloudChatConversationAppBarName;
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message.dart'
    as msg_pkg;
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/tencent_cloud_chat_message_input.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_widgets/tencent_cloud_chat_message_item_builders.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact.dart'
    as contact_pkg;
import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_item.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_app_bar.dart'
    show TencentCloudChatContactAppBarName;
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_group_list.dart';
import 'contact/contact_builder_override.dart';
import 'contact/contact_application_item_content_override.dart';
import 'contact/friend_request_display_name.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_user_profile.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_user_profile_body.dart';
import 'package:tencent_cloud_chat_intl/tencent_cloud_chat_intl.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import '../i18n/app_localizations.dart';
import '../util/logger.dart';
import 'package:tencent_cloud_chat_common/components/component_event_handlers/tencent_cloud_chat_contact_event_handlers.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_config.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_layout/special_case/tencent_cloud_chat_message_no_chat.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_header/tencent_cloud_chat_message_header.dart'
    as msg_header;
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_utils.dart'
    as tcc_utils;
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_models.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_common/data/conversation/tencent_cloud_chat_conversation_data.dart';
import 'package:tencent_cloud_chat_common/data/contact/tencent_cloud_chat_contact_data.dart';
import 'package:tencent_cloud_chat_common/data/group_profile/tencent_cloud_chat_group_profile_data.dart';
import 'group/group_builder_override.dart';
import 'group/group_member_list_wrapper.dart';
import 'package:tencent_cloud_chat_common/eventbus/tencent_cloud_chat_eventbus.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_change_info.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_filter_enum.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_router.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_route_names.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_navigator.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_user_profile_options.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_group_add_member_options.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_group_member_list_options.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_group_profile_options.dart';
import 'package:tencent_cloud_chat_sticker/tencent_cloud_chat_sticker.dart';
import 'package:tencent_cloud_chat_sticker/tencent_cloud_chat_sticker_init_data.dart';
import 'package:tencent_cloud_chat_text_translate/tencent_cloud_chat_text_translate.dart';
import 'package:tencent_cloud_chat_sound_to_text/tencent_cloud_chat_sound_to_text.dart';
import 'search/custom_search.dart' as search_pkg;
import 'package:tencent_cloud_chat_sdk/enum/conversation_type.dart';
import 'settings/settings_page.dart';
import 'settings/sidebar.dart';
import 'applications/applications_page.dart';
import 'home/home_utils.dart';
import 'home/toxee_message_header_info.dart';
import 'home/auto_accept_apply.dart';
import '../util/app_theme_config.dart';
import '../util/design_tokens.dart';
import '../util/app_tray.dart';
import '../util/bootstrap_node_ensurer.dart';
import '../util/bootstrap_nodes.dart';
import '../util/lan_bootstrap_service.dart';
import '../util/send_failure_notifier.dart';
import '../util/platform_utils.dart';
import 'add_friend_dialog.dart';
import 'add_group_dialog.dart';
import 'home/home_group_controller.dart';
import 'home/home_session_controller.dart';
import 'home/home_widgets.dart';
import '../util/ffi_chat_service_account_key.dart';
import '../util/irc_app_manager.dart';
import 'applications/irc_channel_dialog.dart';
import '../util/responsive_layout.dart';
import '../call/permission_helper.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_tatal_unread_count.dart';
import 'widgets/app_page_route.dart';
import 'widgets/app_snackbar.dart';
import 'package:window_manager/window_manager.dart';
import '../notifications/notification_message_listener.dart';
import '../notifications/notification_service.dart';
import 'testing/ui_keys.dart';
import 'testing/l3_debug_tools.dart';

part 'home_page_plugins.dart';
part 'home_page_bootstrap.dart';

enum _MediaPickType { file, image, video }

@visibleForTesting
List<PopupMenuEntry<String>> buildConversationContextMenuItems({
  required AppLocalizations l10n,
  required ColorScheme scheme,
  required bool isPinned,
  required bool hasUnread,
}) {
  return <PopupMenuEntry<String>>[
    PopupMenuItem<String>(
      key: isPinned
          ? UiKeys.conversationContextMenuUnpinItem
          : UiKeys.conversationContextMenuPinItem,
      value: 'pin',
      child: Row(
        children: [
          Icon(
            isPinned ? Icons.push_pin_outlined : Icons.push_pin,
            size: 18,
            color: scheme.onSurface,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(isPinned ? l10n.unpinConversation : l10n.pinConversation),
        ],
      ),
    ),
    PopupMenuItem<String>(
      key: UiKeys.conversationContextMenuMarkReadItem,
      value: 'mark_read',
      enabled: hasUnread,
      child: Row(
        children: [
          Icon(
            Icons.mark_email_read_outlined,
            size: 18,
            color: hasUnread ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(l10n.markConversationAsRead),
        ],
      ),
    ),
    const PopupMenuDivider(),
    PopupMenuItem<String>(
      key: UiKeys.conversationContextMenuDeleteItem,
      value: 'delete',
      child: Row(
        children: [
          Icon(Icons.delete_outline, size: 18, color: scheme.error),
          const SizedBox(width: AppSpacing.sm),
          Text(l10n.delete, style: TextStyle(color: scheme.error)),
        ],
      ),
    ),
  ];
}

@visibleForTesting
AlertDialog buildDeleteConversationDialog({
  required BuildContext dialogCtx,
  required AppLocalizations l10n,
  required ColorScheme scheme,
  required String conversationLabel,
}) {
  // Pop ONLY while this dialog is still the topmost route. Without this guard a
  // double-invocation of the button — a fast real double-click, or a test
  // harness that both dispatches a synthetic pointer AND directly calls
  // `onPressed` — fires `pop` twice: the first closes the dialog, the second
  // unwinds the root HomePage route, emptying the Navigator and blanking the
  // whole window. `ModalRoute.isCurrent` flips to false synchronously inside
  // the first `pop`, so the second call is a no-op. This dialog is shown
  // directly over HomePage (the only route), which is exactly the case where
  // the extra pop has nothing left to land on.
  void dismiss(bool result) {
    final route = ModalRoute.of(dialogCtx);
    if (route != null && route.isCurrent) {
      Navigator.of(dialogCtx).pop(result);
    }
  }

  return AlertDialog(
    title: Text(l10n.deleteConversationTitle),
    content: Text(l10n.deleteConversationBody(conversationLabel)),
    actions: [
      TextButton(
        key: UiKeys.deleteConversationCancelButton,
        onPressed: () => dismiss(false),
        child: Text(l10n.cancel),
      ),
      TextButton(
        key: UiKeys.deleteConversationConfirmButton,
        onPressed: () => dismiss(true),
        style: TextButton.styleFrom(foregroundColor: scheme.error),
        child: Text(l10n.delete),
      ),
    ],
  );
}

class HomePage extends StatefulWidget {
  // NOTE: an `initAfterSessionReadyOverride` constructor seam used to live
  // here. It only skipped `_initAfterSessionReady()` but `build()` still
  // bound UIKit globals via `initGlobalAdapterInBuildPhase()` and built
  // `TencentCloudChatConversation` / `Contact` / `SettingsPage` inside the
  // IndexedStack — so callers couldn't actually hermetic-pump HomePage,
  // they'd just hit the UIKit globals via a different path. Removed
  // 2026-05-28 per HYBRID_ARCHITECTURE Layer 2/3 split (see
  // doc/architecture/UI_TEST_LAYERING.en.md): tests that need HomePage
  // belong in `integration_test/` against a host bundle, not in `test/`
  // pumped against a fake binding. If you need finer per-piece control,
  // use `SessionRuntimeCoordinator.debugInitBodyOverride`.
  const HomePage({super.key, required this.service});
  final FfiChatService service;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _index = 0;
  bool _globalAdapterInited = false;
  StreamSubscription? _friendsSub;
  StreamSubscription? _appsSub;
  List<({String userId, String nickName, bool online, String status})>
  _friends = [];
  Timer? _refreshTimer;
  Set<String> _localFriends = {};
  bool _autoAcceptFriends = false;
  bool _autoAcceptGroupInvites = false;
  List<V2TimFriendApplication> _pendingFriendApps = [];
  // P1-D3: tracks which friend-request userIDs we have already fired a
  // system notification for in this session. Without this, every poll cycle
  // that re-emits the same pending application list would re-banner.
  // Cleared in dispose; survives only the in-memory session.
  final Set<String> _notifiedFriendReqUserIds = <String>{};
  bool _stickerPluginRegistered = false;
  // Set the instant we enqueue a sticker-plugin postFrame callback, so back-
  // to-back rebuilds before the callback fires don't queue duplicates.
  bool _stickerPluginRegistrationScheduled = false;
  bool _textTranslatePluginRegistered = false;
  bool _soundToTextPluginRegistered = false;
  StreamSubscription? _msgSub;
  StreamSubscription? _progressUpdatesSub;
  StreamSubscription<bool>? _connectionStatusSub;
  // P1-C3: timer that fires a banner if we stay offline 30s after a
  // disconnect (or never connect on cold start). Cancelled on
  // conn:success.
  Timer? _noConnectionBannerTimer;
  StreamSubscription<TencentCloudChatConversationData<dynamic>>?
  _conversationDataSub;
  StreamSubscription<TencentCloudChatContactData<dynamic>>? _contactDataSub;
  StreamSubscription<TencentCloudChatGroupProfileData<dynamic>>?
  _groupProfileDataSub;
  StreamSubscription<List<V2TimConversation>>? _convProviderSub;
  StreamSubscription<int>? _unreadProviderSub;
  // Track last membersChange event time per groupID to prevent loops
  final Map<String, DateTime> _lastMembersChangeTime = {};
  static const Duration _minMembersChangeInterval = Duration(seconds: 2);
  BuildContext? _scaffoldMessengerContext;
  DateTime? _lastBackPressTime;
  bool _ircAppInstalled = false;
  // Track UniqueKey per conversation to ensure proper widget lifecycle
  final Map<String, UniqueKey> _messageWidgetKeys = {};
  // Track current conversation to force widget rebuild on change
  String? _currentConversationID;
  // Track if we need to skip building widget on next frame to ensure old widget is disposed
  // Removed _skipNextBuild - it was preventing message widget from being built
  // The desktop mode component will rebuild when currentConversation changes
  // Counter to ensure unique keys across conversation switches
  int _messageWidgetKeyCounter = 0;

  // LAN bootstrap service state
  bool _lanBootstrapServiceRunning = false;
  String? _lanBootstrapServiceIP;
  int? _lanBootstrapServicePort;
  Timer? _bootstrapServiceStatusTimer;
  final _bag = DisposableBag();
  bool _disposed = false;
  ContactBuilderOverrideHandle? _contactBuilderOverride;
  GroupProfileBuilderOverrideHandle? _groupBuilderOverride;
  String? _initErrorMessage;
  late final HomeSessionController _sessionController;
  late final HomeGroupController _groupController;
  // Tracks the last computed `shouldShowMasterDetail` so we only schedule the
  // UIKit `setConfigs(forceDesktopLayout: ...)` post-frame callback when the
  // breakpoint actually crosses, instead of on every rebuild.
  bool? _lastShouldShowMasterDetail;
  // True while the contact-profile route is on screen. Drives `_onTapContactItem`
  // to decide whether a contact tap means "open profile" (false) vs "Send
  // Message from inside profile" (true). Replaces the old `Navigator.canPop()`
  // heuristic which mis-fired whenever any other route (search, settings push)
  // happened to be on the stack.
  bool _inContactProfileContext = false;

  // Set true when the contact profile opens, cleared shortly after.
  // `_showUserProfileOnRight` sets `_inContactProfileContext` true, so a
  // near-instant second `onTapContactItem` (a synthetic double-tap, or an
  // automation harness firing onTap twice — the two fires land within
  // milliseconds) would be misread as the profile's "Send Message" action and
  // pop straight back out to the chat. The genuine Send Message tap happens far
  // later (after the profile has rendered and the user acts), well outside this
  // guard, so it is unaffected. The two double-fire invocations can straddle a
  // frame boundary (synthetic pointer vs direct callback), so a short timer is
  // used rather than a single post-frame flag.
  bool _profileJustOpened = false;
  Timer? _profileJustOpenedTimer;

  @override
  void initState() {
    super.initState();
    _sessionController = HomeSessionController(service: widget.service);
    _groupController = HomeGroupController(
      ops: GroupSyncOps.real(
        getKnownGroups: () => widget.service.knownGroups,
        onUpdateTray: _updateTray,
      ),
    );
    WidgetsBinding.instance.addObserver(this);
    _bag.add(() => WidgetsBinding.instance.removeObserver(this));
    // HYBRID MODE: Using both binary replacement (for most operations) and Platform interface (for history queries)
    // This allows:
    // - Most operations to use binary replacement (TIMManager.instance -> NativeLibraryManager -> Dart* functions)
    // - History queries to use Platform interface (Tim2ToxSdkPlatform -> FfiChatService -> MessageHistoryPersistence)
    // This ensures history messages are loaded from persistence service instead of returning empty list from C++ layer

    // Chats-tab "+" affordance: install the Tox-aware NewEntryButton hook
    // synchronously here (before the first build) so the conversation app bar
    // never renders UIKit's built-in "New Chat / Create Group Chat" menu (which
    // routes to blank Tox pickers). _initAfterSessionReady re-applies it for the
    // restored-account path, but that runs after the app bar has already built
    // with no rebuild to pick up a late static-hook assignment.
    // Capture this HomePage's hook in a stable instance so dispose can clear
    // it ONLY if it's still ours (ownership guard). On account-switch/re-login
    // the app swaps HomePages via pushReplacement/pushAndRemoveUntil: the NEXT
    // page installs its hook in initState BEFORE this one disposes, so an
    // unconditional clear would null the new page's builder and revert the
    // chats-tab "+" to UIKit's default "New Chat / Create Group Chat" menu.
    // Bound to a variable (not a local function declaration) so both the
    // install and the dispose-time `identical` guard reference the exact same
    // closure instance.
    // ignore: prefer_function_declarations_over_variables
    final Widget Function(BuildContext) newEntryHook = (context) =>
        NewEntryButton(
          onAddFriend: _showAddFriendDialog,
          onCreateGroup: _showAddGroupDialog,
          onJoinIrcChannel: _showJoinIrcChannelDialog,
          canJoinIrc: () => IrcAppManager().isInstalled,
        );
    // Install the SAME Tox-aware NewEntryButton on both the Chats-tab
    // conversation app bar and the Contacts-tab app bar so the two "+" menus are
    // identical (Add Contact / Create Group Chat / Join IRC) and neither falls
    // back to a UIKit native menu/panel. The Contacts hook is the robust
    // fallback for whenever the `contactAppBarNameBuilder` override is unset.
    TencentCloudChatConversationAppBarName.trailingBuilder = newEntryHook;
    TencentCloudChatContactAppBarName.trailingBuilder = newEntryHook;
    _bag.add(() {
      if (identical(
          TencentCloudChatConversationAppBarName.trailingBuilder, newEntryHook)) {
        TencentCloudChatConversationAppBarName.trailingBuilder = null;
      }
      if (identical(
          TencentCloudChatContactAppBarName.trailingBuilder, newEntryHook)) {
        TencentCloudChatContactAppBarName.trailingBuilder = null;
      }
    });
    // Session runtime (FakeUIKit, platform, CallServiceManager) via coordinator.
    unawaited(_initAfterSessionReady());
    // React to locale changes once, instead of scheduling a post-frame
    // setLocale in every `build()`. Listener fires only on value change.
    AppLocale.locale.addListener(_handleAppLocaleChanged);
    _bag.add(() => AppLocale.locale.removeListener(_handleAppLocaleChanged));
    // Register conversation secondary-tap / long-press handlers — deferred to
    // next frame so
    // UIKit's conversation event handlers singleton is wired up first (the
    // `setEventHandlers(onTapConversationItem: ...)` call lives in
    // `home_page_bootstrap.dart::_buildHomePage`, which runs during build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        conv_pkg
            .TencentCloudChatConversationManager
            .eventHandlers
            .uiEventHandlers
            .setEventHandlers(
              onSecondaryTapConversationItem:
                  ({
                    required V2TimConversation conversation,
                    required Offset position,
                  }) async {
                    if (!mounted) return false;
                    await _showConversationContextMenu(conversation, position);
                    return true;
                  },
              onLongPressConversationItem:
                  ({
                    required V2TimConversation conversation,
                    required Offset position,
                  }) async {
                    if (!mounted) return false;
                    await _showConversationContextMenu(conversation, position);
                    return true;
                  },
            );
        _bag.add(() {
          // Tear down the handler closure on dispose so it can't fire
          // against a stale State context. There's no "clear" API, so set
          // it back to a no-op that returns false (default behavior).
          try {
            conv_pkg
                .TencentCloudChatConversationManager
                .eventHandlers
                .uiEventHandlers
                .setEventHandlers(
                  onSecondaryTapConversationItem:
                      ({
                        required V2TimConversation conversation,
                        required Offset position,
                      }) async => false,
                  onLongPressConversationItem:
                      ({
                        required V2TimConversation conversation,
                        required Offset position,
                      }) async => false,
                );
          } catch (e) {
            AppLogger.warn(
              '[HomePage] failed to restore onSecondaryTapConversationItem no-op: $e',
            );
          }
        });
      } catch (e, st) {
        AppLogger.logError(
          '[HomePage] Failed to register conversation context-menu handlers',
          e,
          st,
        );
      }
      unawaited(_maybePrewarmCallPermissions());
    });
  }

  /// Used by home_page_bootstrap.dart extension to call setState (avoids invalid_use_of_protected_member).
  void _bootstrapSetState(VoidCallback fn) {
    setState(fn);
  }

  /// Fires when `AppLocale.locale` actually changes — pushes the new locale
  /// into UIKit's intl cache. Replaces the previous per-build post-frame
  /// scheduling pattern in `build()`.
  void _handleAppLocaleChanged() {
    if (!mounted) return;
    try {
      TencentCloudChatIntl().setLocale(AppLocale.locale.value);
    } catch (e, st) {
      AppLogger.logError('[HomePage] Failed to update chat locale', e, st);
    }
  }

  // Build "Add Friend" button widget for non-friends
  Widget _buildAddFriendButton(V2TimUserFullInfo userFullInfo) {
    return Builder(
      builder: (context) {
        return TencentCloudChatThemeWidget(
          build: (context, colorTheme, textStyle) => MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              // Whole-bar hit target so the entire row is tappable (min 44pt
              // height enforced below for mobile ergonomics).
              behavior: HitTestBehavior.opaque,
              onTap: () => _onAddFriend(context, userFullInfo.userID ?? ''),
              child: Container(
                // Fill the parent — using `MediaQuery.size.width` made the
                // button stretch to the full screen even when embedded inside
                // a constrained pane (master-detail / dialog).
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 44),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 1,
                      color: colorTheme.backgroundColor,
                    ),
                  ),
                  color: colorTheme
                      .contactAddContactFriendInfoStateButtonBackgroundColor,
                ),
                // Toxee-owned widget — use literal symmetric insets rather
                // than UIKit's screen adapter so this row doesn't reach into
                // tencent_cloud_chat_common for sizing.
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),
                alignment: Alignment.centerLeft,
                child: Text(
                  AppLocalizations.of(context)!.addFriend,
                  style: TextStyle(
                    color: colorTheme.primaryColor,
                    fontSize: textStyle.fontsize_16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Handle add friend action (e.g. from user profile in group/contact)
  Future<void> _onAddFriend(BuildContext context, String userID) async {
    final requestMessage =
        AppLocalizations.of(context)?.defaultFriendRequestMessage ?? 'Hello';
    try {
      final result = await widget.service.addFriend(
        userID,
        requestMessage: requestMessage,
      );
      if (!mounted) return;
      if (result.isSuccess) {
        AppSnackBar.show(
          context,
          AppLocalizations.of(context)!.friendRequestSent,
        );
        // Refresh contacts to update UI
        FakeUIKit.instance.im?.refreshContacts();
      } else {
        // Async-failure path (e.g. result_code=6770 "Friend add requires full
        // Tox address"). Surface the V2TIM detail so users see the actual
        // reason instead of a silent close.
        final detail = result.resultInfo.isNotEmpty
            ? result.resultInfo
            : 'result_code=${result.resultCode}';
        AppSnackBar.showError(
          context,
          AppLocalizations.of(context)!.failedToSendFriendRequest(detail),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          AppLocalizations.of(context)!.failedToSendFriendRequest(e.toString()),
        );
      }
    }
  }

  Future<void> _loadBootstrapServiceStatus() async {
    if (!mounted) return;

    final running = await Prefs.getLanBootstrapServiceRunning();
    if (running) {
      final info = await LanBootstrapServiceManager.instance
          .getBootstrapServiceInfo();
      if (!mounted) return;
      // Only call setState if anything actually changed — this method is
      // driven by a 2-second periodic timer; without the equality gate we
      // were forcing a full HomePage rebuild every tick.
      final newIp = info?.ip;
      final newPort = info?.port;
      if (running != _lanBootstrapServiceRunning ||
          newIp != _lanBootstrapServiceIP ||
          newPort != _lanBootstrapServicePort) {
        setState(() {
          _lanBootstrapServiceRunning = running;
          if (info != null) {
            _lanBootstrapServiceIP = info.ip;
            _lanBootstrapServicePort = info.port;
          }
        });
      }
    } else {
      if (!mounted) return;
      if (_lanBootstrapServiceRunning != false ||
          _lanBootstrapServiceIP != null ||
          _lanBootstrapServicePort != null) {
        setState(() {
          _lanBootstrapServiceRunning = false;
          _lanBootstrapServiceIP = null;
          _lanBootstrapServicePort = null;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Save tox profile when the app actually goes to background. We used to
    // include `AppLifecycleState.inactive` here, but that fires for every
    // system permission popup / control-center pull / call interruption — far
    // too often for a disk write. Stick to `paused` and `detached`.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      widget.service.saveToxProfileNow();
    }
    // Best-effort resume kick: if the app thawed back to foreground and Tox is
    // still offline, re-add the currently selected bootstrap node to nudge the
    // DHT back toward a live peer set. This is intentionally conservative —
    // full mobile background reliability still needs the bigger foreground-
    // service / PushKit architecture.
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshBootstrapOnResume());
    }
  }

  Future<void> _maybePrewarmCallPermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      final alreadyPrewarmed = await Prefs.getCallPermissionsPrewarmed();
      if (alreadyPrewarmed) return;
      await CallPermissionHelper.prewarmCallPermissions();
      await Prefs.setCallPermissionsPrewarmed(true);
    } catch (e, st) {
      AppLogger.logError(
        '[HomePage] Failed to prewarm call permissions (non-fatal)',
        e,
        st,
      );
    }
  }

  Future<void> _refreshBootstrapOnResume() async {
    try {
      // In auto mode this re-fetches the live node list and applies several
      // fresh online nodes, so a saved node that has gone offline since launch
      // doesn't strand the session; in manual/LAN mode it re-applies the saved
      // node. No-op when already connected. (Best-effort, non-fatal.)
      await BootstrapNodeEnsurer.refreshIfDisconnected(widget.service);
    } catch (e, st) {
      AppLogger.logError(
        '[HomePage] Resume bootstrap refresh failed (non-fatal)',
        e,
        st,
      );
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      super.dispose();
      return;
    }
    _disposed = true;

    _refreshTimer?.cancel();
    _refreshTimer = null;

    _profileJustOpenedTimer?.cancel();
    _profileJustOpenedTimer = null;

    _bootstrapServiceStatusTimer?.cancel();
    _bootstrapServiceStatusTimer = null;

    _msgSub?.cancel();
    _msgSub = null;

    _progressUpdatesSub?.cancel();
    _progressUpdatesSub = null;

    _connectionStatusSub?.cancel();
    _connectionStatusSub = null;

    _conversationDataSub?.cancel();
    _conversationDataSub = null;

    _contactDataSub?.cancel();
    _contactDataSub = null;

    _groupProfileDataSub?.cancel();
    _groupProfileDataSub = null;

    _friendsSub?.cancel();
    _friendsSub = null;

    _appsSub?.cancel();
    _appsSub = null;

    // Defensive: _initAfterSessionReady() registers a cleanup callback on
    // `_bag` asynchronously. If dispose() races ahead of that registration,
    // DisposableBag.add() throws (it does not silently drop). Cancel the
    // timer explicitly here so the lifecycle is correct even if the bag
    // never received the cleanup callback.
    _noConnectionBannerTimer?.cancel();
    _noConnectionBannerTimer = null;

    _bag.dispose();
    super.dispose();
  }

  Future<void> _loadLocalFriends() async {
    final friends = await Prefs.getLocalFriends();
    if (!mounted) return;
    setState(() {
      _localFriends = friends;
    });
  }

  Future<void> _load() async {
    final r = await _sessionController.loadContacts();
    if (!mounted) return;
    setState(() {
      _friends = r.friends;
      _localFriends = r.localFriends;
    });
    await _updateTray();
  }

  /// Sync persisted friends to Tox: re-add friends that are in local persistence but not in Tox.
  Future<void> _syncPersistedFriendsToTox() async {
    await _sessionController.syncPersistedFriendsToTox();
  }

  void _openChat({String? peerId, String? groupId}) {
    setState(() {
      _index = 0; // Ensure Chats tab is visible
      _inContactProfileContext = false;
    });
    // On a COMPACT (phone) layout there is no master-detail right pane, so
    // `_selectConversation` (which only binds `currentConversation`) is a NO-OP:
    // the chat never opens. This silently broke opening a chat with a friend
    // that has no conversation row yet — a just-accepted friend, or the
    // contact-profile "Send a message" tile, or the notification/l3 open seam.
    // Push the UIKit mobile message route instead (the SAME path the
    // conversation-list tap and global-search use). Wide layouts keep the
    // right-pane bind.
    if (!ResponsiveLayout.shouldShowMasterDetail(context)) {
      final hasGroup = groupId != null && groupId.isNotEmpty;
      navigateToMessage(
        context: context,
        options: TencentCloudChatMessageOptions(
          userID: hasGroup ? null : peerId,
          groupID: hasGroup ? groupId : null,
        ),
      );
      unawaited(_updateTray());
      return;
    }
    _selectConversation(peerId: peerId, groupId: groupId);
    unawaited(_updateTray());
  }

  Future<void> _sendMedia(
    BuildContext context, {
    String? userId,
    String? groupId,
    required _MediaPickType type,
  }) async {
    final appL10n = AppLocalizations.of(context)!;
    final label = switch (type) {
      _MediaPickType.file => appL10n.file,
      _MediaPickType.image => appL10n.photo,
      _MediaPickType.video => appL10n.video,
    };
    // The desktop attachment toolbar option's onTap captures `userID` at BUILD
    // time from the fork message-input's data provider, which can lag a
    // master-detail conversation switch (observed: a freshly-opened chat sends
    // with userID == null, so the `if (userId != null)` guard below silently
    // dropped the send). Fall back to the CURRENTLY-bound conversation — the
    // single source of truth set by _selectConversation — so the real button tap
    // always targets the open chat. Harmless when the captured id is already set.
    if ((userId == null || userId.isEmpty) &&
        (groupId == null || groupId.isEmpty)) {
      final cur = UikitDataFacade.currentConversation;
      userId = cur?.userID;
      groupId = cur?.groupID;
    }
    String? pickedPath;
    if (groupId != null && groupId.isNotEmpty) {
      _showSnackBar(appL10n.sendingToGroupsNotSupported(label));
      return;
    }
    try {
      final path = await runL3AwareAttachmentPicker(
        pickFile: () async => (await FilePicker.platform.pickFiles(
          type: switch (type) {
            _MediaPickType.file => FileType.any,
            _MediaPickType.image => FileType.image,
            _MediaPickType.video => FileType.video,
          },
        ))?.files.single.path,
      );
      if (path == null || path.isEmpty) {
        _showSnackBar(appL10n.noLabelSelected(label));
        return;
      }
      pickedPath = path;
      if (userId != null) {
        await widget.service.sendFile(userId, pickedPath);
        _showSnackBar('$label sent');
      }
    } catch (e) {
      final errorMsg = e.toString();
      String userMsg;
      if (errorMsg.contains('offline') || errorMsg.contains('not connected')) {
        // Send a text message to chat window indicating failure (two lines: error + file path)
        // If a picker path was available, keep it in the failure bubble so the
        // user can see which media item failed.
        if (userId != null) {
          final failureMsg = switch (type) {
            _MediaPickType.file => appL10n.friendOfflineCannotSendFile,
            _MediaPickType.image => appL10n.friendOfflineSendImageFailed,
            _MediaPickType.video => appL10n.friendOfflineSendVideoFailed,
          };
          final mgr = FakeUIKit.instance.messageManager;
          if (mgr != null) {
            final text = pickedPath == null
                ? failureMsg
                : '$failureMsg\n$pickedPath';
            await mgr.sendText('c2c_$userId', text);
          }
        }
        userMsg = appL10n.friendOfflineCannotSendFile;
      } else {
        // Extract error message without file path
        String errorText = e.toString();
        // Remove file path from error message if present
        if (errorText.contains('File does not exist')) {
          errorText = appL10n.fileDoesNotExist;
        } else if (errorText.contains('File is empty')) {
          errorText = appL10n.fileIsEmpty;
        } else if (errorText.contains(':')) {
          // Remove path after colon (e.g., "Exception: /path/to/file")
          final colonIndex = errorText.indexOf(':');
          if (colonIndex > 0) {
            final beforeColon = errorText.substring(0, colonIndex);
            final afterColon = errorText.substring(colonIndex + 1).trim();
            // Check if after colon looks like a file path
            if (afterColon.startsWith('/') || afterColon.contains('\\')) {
              errorText = beforeColon;
            }
          }
        }
        userMsg = appL10n.failedToSendFile(label, errorText);
      }
      _showSnackBar(userMsg);
    }
  }

  Future<String> _createSelfQrCardImage() async {
    final nick = await Prefs.getNickname();
    final avatarPath = await Prefs.getAvatarPath();
    // The visible/encoded User ID must be the real Tox ID, NOT the V2TIM
    // login placeholder that `service.selfId` returns. Prefer the stored
    // value; if Prefs hasn't been populated yet (login race) fall back to
    // `accountKey` which itself resolves to the real Tox address via FFI.
    final storedToxId = await Prefs.getCurrentAccountToxId();
    final resolvedSelfId = (storedToxId != null && storedToxId.isNotEmpty)
        ? storedToxId
        : widget.service.accountKey;
    final displayName = (nick != null && nick.trim().isNotEmpty)
        ? nick.trim()
        : resolvedSelfId;
    final locale = AppLocale.locale.value;
    final appL10n = AppLocalizations.of(context);
    return generateContactCardImage(
      userId: resolvedSelfId,
      displayName: displayName,
      locale: locale,
      bottomText:
          appL10n?.scanQrCodeToAddContact ??
          'Scan QR code to add me as contact',
      primaryColor: AppThemeConfig.primaryColor,
      avatarPath: avatarPath,
    );
  }

  List<TencentCloudChatMessageGeneralOptionItem> _buildDesktopInputOptions(
    BuildContext context, {
    String? userID,
    String? groupID,
  }) {
    final appL10n = AppLocalizations.of(context)!;
    final fileLabel = appL10n.file;
    final personalCardLabel = appL10n.personalCard;
    final personalCardGroupLabel = appL10n.sendPersonalCardToGroup;
    final sentSnack = appL10n.personalCardSent;
    final sentGroupSnack = appL10n.sentPersonalCardToGroup;
    // toxee: desktop composer merges File / Photo / Video into a single "file"
    // button. `_sendMedia(type: file)` opens the OS picker with FileType.any, so
    // it already sends images, videos and every other file type — the separate
    // photo/video buttons were removed to declutter the desktop toolbar. Mobile
    // keeps its own photo/video attachment options (see home_page_bootstrap).
    final options = <TencentCloudChatMessageGeneralOptionItem>[
      TencentCloudChatMessageGeneralOptionItem(
        icon: Icons.attach_file,
        label: fileLabel,
        onTap: ({Offset? offset}) async {
          await _sendMedia(
            context,
            userId: userID,
            groupId: groupID,
            type: _MediaPickType.file,
          );
        },
      ),
    ];
    if (userID != null) {
      options.add(
        TencentCloudChatMessageGeneralOptionItem(
          icon: Icons.qr_code_2,
          label: personalCardLabel,
          onTap: ({Offset? offset}) async {
            try {
              // Check if friend is online before sending
              final friends = await widget.service.getFriendList();
              final friend = friends.firstWhere(
                (f) => f.userId == userID,
                orElse: () =>
                    (userId: userID, nickName: '', online: false, status: ''),
              );
              if (!friend.online) {
                final appL10n = AppLocalizations.of(context)!;
                // Send a text message to chat window indicating failure (two lines: error + file path)
                final qrPath = await _createSelfQrCardImage();
                final twoLineMsg =
                    '${appL10n.friendOfflineSendCardFailed}\n$qrPath';
                final mgr = FakeUIKit.instance.messageManager;
                if (mgr != null) {
                  await mgr.sendText('c2c_$userID', twoLineMsg);
                }
                return;
              }
              final qrPath = await _createSelfQrCardImage();
              await widget.service.sendFile(userID, qrPath);
              _showSnackBar(sentSnack);
            } catch (e, stackTrace) {
              // Provide more user-friendly error messages
              final appL10n = AppLocalizations.of(context)!;
              final errorMsg = e.toString();
              String userMsg;
              if (errorMsg.contains('offline') ||
                  errorMsg.contains('not connected')) {
                // Send a text message to chat window indicating failure (two lines: error + file path)
                // Try to get the file path from the error or use a default message
                try {
                  final qrPath = await _createSelfQrCardImage();
                  final twoLineMsg =
                      '${appL10n.friendOfflineSendCardFailed}\n$qrPath';
                  final mgr = FakeUIKit.instance.messageManager;
                  if (mgr != null) {
                    await mgr.sendText('c2c_$userID', twoLineMsg);
                  }
                } catch (e, st) {
                  AppLogger.logError(
                    '[HomePage] Failed to create self QR card image for offline fallback',
                    e,
                    st,
                  );
                  final mgr = FakeUIKit.instance.messageManager;
                  if (mgr != null) {
                    await mgr.sendText(
                      'c2c_$userID',
                      appL10n.friendOfflineSendCardFailed,
                    );
                  }
                }
                userMsg = appL10n.friendOfflineCannotSendFile;
              } else if (errorMsg.contains('not in your friend list')) {
                userMsg = appL10n.userNotInFriendList;
              } else {
                // Extract error message without file path
                String errorText = e.toString();
                final appL10n = AppLocalizations.of(context)!;
                // Remove file path from error message if present
                if (errorText.contains('File does not exist')) {
                  errorText = appL10n.fileDoesNotExist;
                } else if (errorText.contains('File is empty')) {
                  errorText = appL10n.fileIsEmpty;
                } else if (errorText.contains(':')) {
                  // Remove path after colon (e.g., "Exception: /path/to/file")
                  final colonIndex = errorText.indexOf(':');
                  if (colonIndex > 0) {
                    final beforeColon = errorText.substring(0, colonIndex);
                    final afterColon = errorText
                        .substring(colonIndex + 1)
                        .trim();
                    // Check if after colon looks like a file path
                    if (afterColon.startsWith('/') ||
                        afterColon.contains('\\')) {
                      errorText = beforeColon;
                    }
                  }
                }
                userMsg = appL10n.sendFailed(errorText);
              }
              _showSnackBar(userMsg);
            }
          },
        ),
      );
    } else if (groupID != null) {
      options.add(
        TencentCloudChatMessageGeneralOptionItem(
          icon: Icons.qr_code,
          label: personalCardGroupLabel,
          onTap: ({Offset? offset}) async {
            final appL10n = AppLocalizations.of(context)!;
            final text = '${appL10n.myId}: ${widget.service.accountKey}';
            await widget.service.sendGroupText(groupID, text);
            _showSnackBar(sentGroupSnack);
          },
        ),
      );
    }
    return options;
  }

  Future<void> _updateTray() async {
    if (!AppTray.instance.isSupported) return;
    // Get total unread count from UIKit (includes all conversations and groups)
    final uikitUnreadCount = UikitDataFacade.totalUnreadCount;
    // Get friend application unread count
    final applicationUnreadCount = UikitDataFacade.applicationUnreadCount;
    // Total count = conversation unread + friend applications
    final totalCount = uikitUnreadCount + applicationUnreadCount;
    await AppTray.instance.update(
      count: totalCount,
      online: widget.service.isConnected,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep UIKit intl in sync with app locale. `setLocale` itself is driven
    // by `_handleAppLocaleChanged` (registered in initState) so it only fires
    // on actual locale-value changes — not every build.
    try {
      TencentCloudChatIntl().init(context);
    } catch (e, st) {
      AppLogger.logError('[HomePage] Global adapter init failed', e, st);
    }
    if (!_globalAdapterInited) {
      try {
        // Set contact event handlers for navigation
        // Note: onNavigateToChat is an alias for onTapContactItem (getter that returns _onTapContactItem)
        UikitDataFacade
            .contactEventHandlers = TencentCloudChatContactEventHandlers(
          uiEventHandlers: TencentCloudChatContactUIEventHandlers(
            onTapContactItem: ({String? userID, String? groupID}) async {
              // Handle navigation from contact list and profile page "Send Message" button.
              if (userID != null) {
                // Explicit state field replaces the old `Navigator.canPop()`
                // heuristic: the latter mis-fired whenever any other route
                // (search, settings push, etc.) happened to be on the stack
                // and would pop the wrong page on a contact-list tap.
                if (_inContactProfileContext) {
                  // Swallow a near-instant re-entry: a synthetic double-tap (or
                  // a harness firing onTap twice) would otherwise pop the profile
                  // we JUST opened straight back to the chat. A genuine "Send
                  // Message" tap from inside the profile lands far later.
                  if (_profileJustOpened) {
                    return true; // swallow the immediate second fire
                  }
                  // We're inside a profile page — this is "Send Message".
                  // Close the profile, switch to chats tab, open 1:1 chat.
                  Navigator.of(context).pop();
                  setState(() {
                    _index = 0;
                    _inContactProfileContext = false;
                  });
                  _selectConversation(peerId: userID);
                  return true; // Handled, prevent default navigation
                } else {
                  // Contact list tap → show profile on the right side.
                  _showUserProfileOnRight(context, userID);
                  return true; // Handled, prevent default navigation
                }
              } else if (groupID != null) {
                // For groups, still switch to chats tab and open group chat
                setState(() {
                  _index = 0;
                });
                _selectConversation(groupId: groupID);
                return true; // Handled, prevent default navigation
              }
              return false;
            },
          ),
        );

        TencentCloudChat.controller.initGlobalAdapterInBuildPhase(context);
        _globalAdapterInited = true;
      } catch (e, st) {
        AppLogger.logError(
          '[HomePage] initGlobalAdapterInBuildPhase failed',
          e,
          st,
        );
      }
    }
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) {
        return Builder(
          builder: (scaffoldCtx) {
            _scaffoldMessengerContext = scaffoldCtx;
            // `useBottomNav` is the single source of truth for "phone-y"
            // layouts (< 720pt) — replaces the old `isMobile` gate so
            // landscape phones (600-720pt) keep the bottom nav instead of
            // jumping to a sidebar. `useSidebar` is its inverse.
            final useBottomNav = ResponsiveLayout.shouldShowBottomNav(context);
            final useSidebar = !useBottomNav;
            final showMasterDetail = ResponsiveLayout.shouldShowMasterDetail(
              context,
            );

            // Drive UIKit's master-detail layout from toxee's responsive
            // breakpoint. UIKit only renders desktop-mode automatically on
            // "desktop platform"; `forceDesktopLayout` lets us opt wide
            // touch devices (e.g. iPad landscape) into the same split.
            //
            // Only schedule the post-frame callback when the value actually
            // crosses the breakpoint — `build` runs on every `setState`, but
            // `setConfigs` only needs to be called on threshold transitions.
            if (showMasterDetail != _lastShouldShowMasterDetail) {
              _lastShouldShowMasterDetail = showMasterDetail;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                try {
                  UikitDataFacade.setConversationConfig(
                    forceDesktopLayout: showMasterDetail,
                  );
                } catch (_) {
                  // Config object may not exist yet on the very first frame
                  // (UIKit init is async); next layout pass will pick it up.
                }
              });
            }

            // Intercept Android back only when we're truly at the root of the
            // navigator stack AND on a non-Chats tab (so back returns to
            // Chats), OR on the Chats tab with no pushed routes (so we can
            // implement double-back-to-exit). When a route is pushed (UIKit
            // chat-detail on phone, search overlay, profile page), let the
            // normal pop happen — the old unconditional `canPop: false` was
            // snapping users back to the Chats tab and breaking UIKit's
            // internal navigation stack.
            //
            // `Navigator.canPop()` is re-evaluated every `build()`; pushes
            // and pops on the root navigator trigger an ancestor rebuild
            // (`Route.didChangeNext` / `didChangePrevious`), so this value
            // stays in sync with the live stack.
            final rootNavigatorCanPop = Navigator.of(context).canPop();
            Widget content = PopScope(
              canPop: rootNavigatorCanPop,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                // At the root of the navigator stack: handle tab/exit logic.
                if (_index != 0) {
                  setState(() {
                    _index = 0;
                  });
                  return;
                }
                // On Chats tab at root: double-press back to exit.
                final now = DateTime.now();
                if (_lastBackPressTime != null &&
                    now.difference(_lastBackPressTime!) <
                        const Duration(seconds: 2)) {
                  SystemNavigator.pop();
                  return;
                }
                _lastBackPressTime = now;
                AppSnackBar.show(
                  _scaffoldMessengerContext ?? context,
                  AppLocalizations.of(context)!.pressBackAgainToExit,
                );
              },
              child: Scaffold(
                // Drawer removed: there was no AppBar and no `openDrawer()`
                // call site, so it was unreachable. Bottom nav covers all
                // entries on phone.
                body: SafeArea(
                  // Frameless macOS window: fill to the top edge — the rail
                  // reserves the traffic-light zone itself, so we opt out of
                  // the global top inset injected in main.dart. Other platforms
                  // keep the normal top inset.
                  top: !(PlatformUtils.isDesktop && PlatformUtils.isMacOS),
                  child: Stack(
                    children: [
                      Row(
                        children: [
                          if (useSidebar) ...[
                            SizedBox(
                              width: ResponsiveLayout.responsiveSidebarWidth(
                                context,
                              ),
                              // Frameless window: the rail reserves space for
                              // the macOS traffic lights INSIDE its coloured
                              // container (see buildSidebar), so the rail
                              // background fills the top edge with no seam.
                              child: _uikitSidebar(),
                            ),
                            VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ],
                          // Inset the main pane so its panel headers line up
                          // with the rail avatar under the macOS lights. Strip
                          // any ambient top padding first so no tab double-insets;
                          // on Windows/Linux the body SafeArea already reserved
                          // the caption-button strip, so this collapses to zero.
                          Expanded(
                            child: Builder(
                              builder: (ctx) => MediaQuery.removePadding(
                                context: ctx,
                                removeTop: true,
                                child: Column(
                                  children: [
                                    const MacTitleBarInset(),
                                    Expanded(child: _buildMainPane(context)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Bootstrap service status banner — show on native desktop
                      // and on wide tablet/desktop-class viewports (e.g. iPad in
                      // landscape) so the LAN status surface isn't hidden on
                      // bigger touch devices that can act as the LAN host.
                      if (PlatformUtils.isDesktop ||
                          ResponsiveLayout.isDesktop(context))
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          // Asymmetric enter/exit: snappy 250ms in (easeOut) so the
                          // banner shows up quickly when the LAN service comes
                          // online, faster 150ms out (easeIn) so dismissing feels
                          // responsive and doesn't linger.
                          child: AnimatedSwitcher(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 250),
                            reverseDuration:
                                MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 150),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) {
                              final slide = Tween<Offset>(
                                begin: const Offset(0, -1),
                                end: Offset.zero,
                              ).animate(animation);
                              return SlideTransition(
                                position: slide,
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              );
                            },
                            child:
                                (_lanBootstrapServiceRunning &&
                                    _lanBootstrapServiceIP != null &&
                                    _lanBootstrapServicePort != null)
                                ? Material(
                                    key: const ValueKey('lan-bootstrap-banner'),
                                    elevation: 0,
                                    color: AppThemeConfig.successColor
                                        .withValues(alpha: 0.08),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.lg,
                                        vertical: AppSpacing.sm,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: AppThemeConfig.successColor
                                                .withValues(alpha: 0.25),
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.cloud_done_outlined,
                                            color: AppThemeConfig.successColor,
                                            size: 18,
                                          ),
                                          const SizedBox(width: AppSpacing.sm),
                                          Expanded(
                                            child: Text(
                                              AppLocalizations.of(
                                                context,
                                              )!.bootstrapServiceRunning(
                                                _lanBootstrapServiceIP!,
                                                _lanBootstrapServicePort!,
                                              ),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.close,
                                              size: 18,
                                            ),
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            // 44x44 minimum tap area for mobile (Apple HIG / Material 48dp).
                                            constraints: const BoxConstraints(
                                              minWidth: 44,
                                              minHeight: 44,
                                            ),
                                            padding: EdgeInsets.zero,
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () {
                                              setState(() {
                                                _lanBootstrapServiceRunning =
                                                    false;
                                              });
                                            },
                                            tooltip: AppLocalizations.of(
                                              context,
                                            )!.hide,
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(
                                    key: ValueKey(
                                      'lan-bootstrap-banner-hidden',
                                    ),
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
                bottomNavigationBar: useBottomNav
                    ? _buildBottomNavigationBar()
                    : null,
              ),
            );
            // Desktop keyboard shortcuts — meta+/ctrl+ comma/N/W/F.
            // Setting both `meta` and `control` on the SingleActivator
            // works for macOS and Win/Linux without a per-platform branch.
            if (PlatformUtils.isDesktop) {
              content = Shortcuts(
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(
                    LogicalKeyboardKey.comma,
                    meta: true,
                    control: true,
                  ): _OpenSettingsIntent(),
                  SingleActivator(
                    LogicalKeyboardKey.keyN,
                    meta: true,
                    control: true,
                  ): _NewConversationIntent(),
                  SingleActivator(
                    LogicalKeyboardKey.keyW,
                    meta: true,
                    control: true,
                  ): _CloseWindowIntent(),
                  SingleActivator(
                    LogicalKeyboardKey.keyF,
                    meta: true,
                    control: true,
                  ): _OpenSearchIntent(),
                },
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    _OpenSettingsIntent: CallbackAction<_OpenSettingsIntent>(
                      onInvoke: (_) {
                        setState(() => _index = 3);
                        return null;
                      },
                    ),
                    _NewConversationIntent:
                        CallbackAction<_NewConversationIntent>(
                          onInvoke: (_) {
                            unawaited(_showAddFriendDialog());
                            return null;
                          },
                        ),
                    _CloseWindowIntent: CallbackAction<_CloseWindowIntent>(
                      onInvoke: (_) {
                        if (PlatformUtils.isDesktop) {
                          unawaited(windowManager.close());
                        }
                        return null;
                      },
                    ),
                    _OpenSearchIntent: CallbackAction<_OpenSearchIntent>(
                      onInvoke: (_) {
                        // Cmd/Ctrl+F → push toxee's global search overlay.
                        _openGlobalSearchOverlay();
                        return null;
                      },
                    ),
                  },
                  child: Focus(autofocus: true, child: content),
                ),
              );
            }
            return content;
          },
        );
      },
    );
  }

  /// Push toxee's global search overlay (`CustomSearch` in global mode —
  /// `userID`/`groupID` left null so it searches all conversations). Shared by
  /// the Cmd/Ctrl+F `_OpenSearchIntent` shortcut and the `l3_open_global_search`
  /// navigation-stability seam, so the real-UI harness opens search
  /// deterministically instead of through a flaky synthetic keystroke.
  void _openGlobalSearchOverlay() {
    final rootCtx = _scaffoldMessengerContext ?? context;
    Navigator.of(rootCtx).push(
      AppPageRoute(
        page: Builder(
          builder: (innerCtx) => search_pkg.CustomSearch(
            closeFunc: () => Navigator.of(innerCtx).pop(),
          ),
        ),
      ),
    );
  }

  Widget? _buildBottomNavigationBar() {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Reference-design bottom nav: flat surface, 1px top hairline, active
    // tab in brand blue, inactive in the tertiary text tone.
    final inactiveColor = isDark
        ? DesignTokens.textTertiaryDark
        : DesignTokens.textTertiaryLight;
    final hairlineColor = isDark
        ? DesignTokens.dividerDark
        : DesignTokens.dividerLight;
    return DecoratedBox(
      // Automation anchor: this bottom nav renders ONLY in the bottom-nav
      // (mobile) layout tier (`useBottomNav`/`shouldShowBottomNav`, a pure
      // width check), so its presence is the responsive layout-swap signal a
      // real-UI test asserts after narrowing the window past 720pt.
      key: UiKeys.homeBottomNav,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: hairlineColor, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) {
            if (i == _index) {
              // Re-tap on the active tab — iOS/Android convention: scroll
              // the active list back to the top. UIKit exposes the
              // conversation list scroll controller via the controller
              // singleton; other tabs (contacts/applications/settings) don't
              // expose theirs yet — leave them as TODO.
              if (i == 0) {
                unawaited(
                  TencentCloudChatConversationController.instance.scrollToTop(),
                );
              }
              // TODO: scroll-to-top for tabs 1 (contacts), 2 (applications),
              // 3 (settings) — needs controller hooks from those widgets.
              return;
            }
            setState(() {
              _index = i;
            });
            // Refresh IRC app status when switching to Applications page
            if (i == 2) {
              _checkIrcAppStatus();
            }
          },
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          selectedItemColor: DesignTokens.primary,
          unselectedItemColor: inactiveColor,
          backgroundColor: theme.scaffoldBackgroundColor,
          iconSize: 24,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          selectedLabelStyle: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: theme.textTheme.labelSmall,
          items: [
            BottomNavigationBarItem(
              icon: Stack(
                key: UiKeys.bottomNavChats,
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.chat_bubble_outline),
                  Positioned(
                    top: -5,
                    right: -6,
                    child: UnconstrainedBox(
                      child: TencentCloudChatConversationTotalUnreadCount(
                        builder: (BuildContext _, int totalUnreadCount) {
                          if (totalUnreadCount == 0) {
                            return const SizedBox.shrink();
                          }
                          final displayText = totalUnreadCount > 99
                              ? "99+"
                              : "$totalUnreadCount";
                          final isLargeText = displayText.length > 2;
                          return Semantics(
                            label: AppLocalizations.of(
                              context,
                            )!.unreadMessagesSemantics(totalUnreadCount),
                            container: true,
                            child: UnconstrainedBox(
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 16),
                                height: 16,
                                padding: EdgeInsets.symmetric(
                                  horizontal: isLargeText ? 5 : 4,
                                ),
                                decoration: BoxDecoration(
                                  color: DesignTokens.unreadBadge,
                                  borderRadius: BorderRadius.circular(
                                    AppThemeConfig.badgeBorderRadius,
                                  ),
                                  border: Border.all(
                                    color: theme.scaffoldBackgroundColor,
                                    width: 1.5,
                                  ),
                                ),
                                child: Center(
                                  child: ExcludeSemantics(
                                    child: Text(
                                      displayText,
                                      // Automation-only: the mobile bottom-nav
                                      // twin of sidebar_chats_unread_badge.
                                      key: UiKeys.homeChatsUnreadBadge,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: DesignTokens.onUnreadBadge,
                                            fontWeight: FontWeight.w600,
                                            height: 1.0,
                                            fontSize: 10,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
              activeIcon: const Icon(Icons.chat_bubble),
              label: l10n.chats,
            ),
            BottomNavigationBarItem(
              icon: const Icon(
                Icons.contacts_outlined,
                key: UiKeys.bottomNavContacts,
              ),
              activeIcon: const Icon(
                Icons.contacts,
                key: UiKeys.bottomNavContacts,
              ),
              label: l10n.contacts,
            ),
            BottomNavigationBarItem(
              icon: const Icon(
                Icons.apps_outlined,
                key: UiKeys.bottomNavApplications,
              ),
              activeIcon: const Icon(
                Icons.apps,
                key: UiKeys.bottomNavApplications,
              ),
              label: l10n.applications,
            ),
            BottomNavigationBarItem(
              icon: const Icon(
                Icons.settings_outlined,
                key: UiKeys.bottomNavSettings,
              ),
              activeIcon: const Icon(
                Icons.settings,
                key: UiKeys.bottomNavSettings,
              ),
              label: l10n.settings,
            ),
          ],
        ),
      ),
    );
  }

  /// Build the central pane of the home page.
  ///
  /// UIKit's `TencentCloudChatConversation` widget owns its own master-detail
  /// layout (driven by `TencentCloudChatConversationConfig.forceDesktopLayout`)
  /// — see `build` where we set that config from `shouldShowMasterDetail` on
  /// every frame. Wrapping the IndexedStack in another Row here would create
  /// nested master-detail; collapse to the simple stack and let UIKit decide.
  Widget _buildMainPane(BuildContext context) {
    return IndexedStack(index: _index, children: _buildTabChildren());
  }

  /// The IndexedStack children corresponding to the bottom-nav / sidebar
  /// tabs. Extracted from the inline `build` because the master-detail
  /// layout needs to reuse it inside a sized container.
  List<Widget> _buildTabChildren() {
    return [
      ValueListenableBuilder<Locale>(
        valueListenable: AppLocale.locale,
        builder: (context, locale, _) {
          // `setLocale` is driven by the global locale listener installed in
          // `initState` — no per-build scheduling needed here.
          return TencentCloudChatConversation(
            key: ValueKey('uikit-conversation-${locale.languageCode}'),
            builders: conv_pkg.TencentCloudChatConversationManager.builder,
          );
        },
      ),
      ValueListenableBuilder<Locale>(
        valueListenable: AppLocale.locale,
        builder: (context, locale, _) {
          return ValueListenableBuilder<ThemeMode>(
            valueListenable: AppTheme.mode,
            builder: (context, themeMode, __) {
              // `NewEntryButton` is now mounted inside the UIKit contacts
              // AppBar via `ContactAppBarNameOverride.trailing` (see
              // `home_page_bootstrap.dart`), so the previous floating
              // `Positioned` overlay is gone. That overlay anchored the pill
              // at the same screen position as the popup menu, making the
              // pill disappear behind the menu the moment it opened (the
              // "New Chat button ate itself" symptom from sc_01.png).
              return TencentCloudChatThemeWidget(
                build: (context, themeColors, textStyles) {
                  // Pass the global builder singleton explicitly so UIKit's
                  // `_updateGlobalData()` keeps our overrides instead of
                  // wiping them. The widget's else branch resets
                  // `contactBuilder` to a fresh empty instance whenever
                  // `widget.builders` is null, which deletes the
                  // `contactAppBarNameBuilder` we wired up in
                  // `home_page_bootstrap.dart`. Passing the manager's
                  // singleton (already populated by setBuilders) routes
                  // through the if branch, preserving the override.
                  return TencentCloudChatContact(
                    key: ValueKey(
                      'uikit-contact-${locale.languageCode}-${themeMode.name}',
                    ),
                    builders:
                        contact_pkg.TencentCloudChatContactManager.builder,
                  );
                },
              );
            },
          );
        },
      ),
      ValueListenableBuilder<Locale>(
        valueListenable: AppLocale.locale,
        builder: (context, locale, _) => ApplicationsPage(
          key: ValueKey('applications-${locale.languageCode}'),
          service: widget.service,
        ),
      ),
      // Settings tab gets a proper top header bar (title "Settings") so its
      // content doesn't run into the top window edge, plus the macOS
      // traffic-light inset so it lines up with the rail.
      Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 52,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(
                    bottom: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
                child: Text(
                  TencentCloudChatLocalizations.of(context)?.settings ??
                      'Settings',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Expanded(
                child: SettingsPage(
                  service: widget.service,
                  connectionStatusStream: widget.service.connectionStatusStream,
                  autoAcceptFriends: _autoAcceptFriends,
                  onAutoAcceptFriendsChanged: _setAutoAcceptFriends,
                  autoAcceptGroupInvites: _autoAcceptGroupInvites,
                  onAutoAcceptGroupInvitesChanged: _setAutoAcceptGroupInvites,
                ),
              ),
            ],
          );
        },
      ),
    ];
  }

  Widget _uikitSidebar() {
    return buildSidebar(
      context: context,
      selectedIndex: _index,
      onTap: (i) {
        setState(() {
          _index = i;
        });
        // Refresh IRC app status when switching to Applications page
        if (i == 2) {
          _checkIrcAppStatus();
        }
      },
      service: widget.service,
      connectionStatusStream: widget.service.connectionStatusStream,
    );
  }

  /// Desktop-style right-click menu for a conversation row.
  ///
  /// Anchored at the global cursor `position` reported by UIKit. Keeps the
  /// item list short (4 actions max — Pin/Unpin, Mark as read, Delete) to
  /// match the popup-menu density convention.
  Future<void> _showConversationContextMenu(
    V2TimConversation conv,
    Offset position,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final isPinned = conv.isPinned ?? false;
    final hasUnread = (conv.unreadCount ?? 0) > 0;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: buildConversationContextMenuItems(
        l10n: l10n,
        scheme: scheme,
        isPinned: isPinned,
        hasUnread: hasUnread,
      ),
    );
    if (!mounted || selected == null) return;
    await _dispatchConversationMenuAction(conv, selected);
  }

  /// Run a conversation-context-menu action (`pin` / `mark_read` / `delete`)
  /// through the SAME production conversation-manager handlers the menu's
  /// `showMenu` result dispatches. Extracted from [_showConversationContextMenu]
  /// so the L3 harness can invoke an action deterministically without tapping
  /// the `PopupMenuItem` (flutter_skill double-fires `InkWell`-backed items,
  /// which turns the `pin` toggle into a net no-op). The menu path and the
  /// harness path now execute byte-identical code; `delete` still raises the
  /// real confirm dialog (`delete_conversation_confirm_button`).
  Future<void> _dispatchConversationMenuAction(
    V2TimConversation conv,
    String action,
  ) async {
    final convId = conv.conversationID;
    final isPinned = conv.isPinned ?? false;
    switch (action) {
      case 'pin':
        try {
          await TencentImSDKPlugin.v2TIMManager
              .getConversationManager()
              .pinConversation(conversationID: convId, isPinned: !isPinned);
        } catch (e, st) {
          AppLogger.logError(
            '[HomePage] pinConversation failed for $convId',
            e,
            st,
          );
        }
        break;
      case 'mark_read':
        try {
          // `cleanConversationUnreadMessageCount` is the non-deprecated entry
          // point that works for both C2C and group conversations. Passing
          // 0/0 marks everything currently in the conversation as read.
          await TencentImSDKPlugin.v2TIMManager
              .getConversationManager()
              .cleanConversationUnreadMessageCount(
                conversationID: convId,
                cleanTimestamp: 0,
                cleanSequence: 0,
              );
        } catch (e, st) {
          AppLogger.logError(
            '[HomePage] cleanConversationUnreadMessageCount failed for $convId',
            e,
            st,
          );
        }
        break;
      case 'delete':
        if (!mounted) return;
        final l10n = AppLocalizations.of(context)!;
        final scheme = Theme.of(context).colorScheme;
        final confirmed =
            await showDialog<bool>(
              context: context,
              builder: (dialogCtx) => buildDeleteConversationDialog(
                dialogCtx: dialogCtx,
                l10n: l10n,
                scheme: scheme,
                conversationLabel: conv.showName ?? convId,
              ),
            ) ??
            false;
        if (!mounted || !confirmed) return;
        try {
          await TencentImSDKPlugin.v2TIMManager
              .getConversationManager()
              .deleteConversation(conversationID: convId);
        } catch (e, st) {
          AppLogger.logError(
            '[HomePage] deleteConversation failed for $convId',
            e,
            st,
          );
        }
        break;
    }
  }

  /// Show user profile page - uses router which handles desktop/mobile modes.
  ///
  /// Sets `_inContactProfileContext = true` while the profile route is on
  /// screen so `_onTapContactItem` can distinguish a Send Message tap from
  /// inside the profile from a contact-list tap on the underlying tab.
  /// The flag is cleared after the route returns; `_onTapContactItem` also
  /// clears it on the Send-Message path (it pops the profile itself).
  void _showUserProfileOnRight(BuildContext context, String userID) {
    _inContactProfileContext = true;
    // Guard briefly against the double-fire's second onTapContactItem; clear
    // well before any genuine "Send Message" tap could plausibly arrive.
    _profileJustOpened = true;
    _profileJustOpenedTimer?.cancel();
    _profileJustOpenedTimer = Timer(const Duration(milliseconds: 250), () {
      _profileJustOpened = false;
    });
    final future = TencentCloudChatRouter().navigateTo(
      context: context,
      routeName: TencentCloudChatRouteNames.userProfile,
      options: TencentCloudChatUserProfileOptions(userID: userID),
    );
    // navigateTo returns dynamic; coerce to Future so we can clear the flag
    // when the user dismisses the profile via normal back navigation.
    if (future is Future) {
      unawaited(
        future.whenComplete(() {
          if (mounted) {
            _inContactProfileContext = false;
          }
        }),
      );
    }
  }

  void _selectConversation({String? peerId, String? groupId}) {
    final bool hasPeer = peerId != null && peerId.isNotEmpty;
    final bool hasGroup = groupId != null && groupId.isNotEmpty;
    if (!hasPeer && !hasGroup) {
      widget.service.setActivePeer(null);
      return;
    }
    final String targetConvId = hasGroup ? 'group_$groupId' : 'c2c_${peerId!}';

    V2TimConversation? target;
    for (final conv in UikitDataFacade.conversationList) {
      if (conv.conversationID == targetConvId) {
        target = conv;
        break;
      }
    }
    final normalizedTarget = target == null
        ? V2TimConversation(
            conversationID: targetConvId,
            type: hasGroup
                ? ConversationType.V2TIM_GROUP
                : ConversationType.V2TIM_C2C,
            userID: hasGroup ? null : peerId,
            groupID: hasGroup ? groupId : null,
            showName: hasGroup ? groupId : peerId,
            unreadCount: 0,
          )
        : V2TimConversation(
            conversationID: target.conversationID,
            type:
                target.type ??
                (hasGroup
                    ? ConversationType.V2TIM_GROUP
                    : ConversationType.V2TIM_C2C),
            userID: hasGroup ? null : peerId,
            groupID: hasGroup ? groupId : null,
            showName:
                target.showName ??
                (hasGroup ? groupId : peerId) ??
                targetConvId,
            faceUrl: target.faceUrl,
            groupType: target.groupType,
            unreadCount: target.unreadCount ?? 0,
            lastMessage: target.lastMessage,
            draftText: target.draftText,
            draftTimestamp: target.draftTimestamp,
            isPinned: target.isPinned,
            recvOpt: target.recvOpt,
            orderkey: target.orderkey,
            markList: target.markList,
            customData: target.customData,
            conversationGroupList: target.conversationGroupList,
            c2cReadTimestamp: target.c2cReadTimestamp,
            groupReadSequence: target.groupReadSequence,
            groupAtInfoList: target.groupAtInfoList,
          );
    // Selecting a chat means the profile/detail shell is no longer the active
    // interaction surface. Clear this flag here as a final backstop so desktop
    // contact-profile "Send Message" transitions cannot leave the HomePage in a
    // stale "inside profile" mode after the chat has already opened.
    _inContactProfileContext = false;
    UikitDataFacade.currentConversation = normalizedTarget;
  }

  Future<void> _setAutoAcceptFriends(bool value) async {
    if (_autoAcceptFriends == value) return;
    setState(() => _autoAcceptFriends = value);
    final toxId = widget.service.accountKey;
    if (toxId.isNotEmpty) {
      await Prefs.setAutoAcceptFriends(value, toxId);
    }
    if (value && _pendingFriendApps.isNotEmpty) {
      await _acceptFriendApplications(
        List<V2TimFriendApplication>.from(_pendingFriendApps),
      );
    }
  }

  Future<void> _setAutoAcceptGroupInvites(bool value) async {
    if (_autoAcceptGroupInvites == value) return;
    setState(() => _autoAcceptGroupInvites = value);
    final toxId = widget.service.accountKey;
    if (toxId.isNotEmpty) {
      await Prefs.setAutoAcceptGroupInvites(value, toxId);
    }
    // Update FFI setting so C++ can read it
    widget.service.setAutoAcceptGroupInvites(value);
  }

  Future<void> _acceptFriendApplications(
    List<V2TimFriendApplication> apps,
  ) async {
    for (final app in apps) {
      final uid = app.userID;
      if (uid.isEmpty) continue;
      try {
        await widget.service.acceptFriendRequest(uid);
      } catch (e, st) {
        AppLogger.logError(
          '[HomePage] acceptFriendRequest failed for $uid',
          e,
          st,
        );
      }
    }
    _pendingFriendApps = [];
    if (mounted) setState(() {});
    await FakeUIKit.instance.im?.refreshContacts();
    await _load();
    _showSnackBar(AppLocalizations.of(context)!.autoAcceptedNewFriendRequest);
    await _updateTray();
  }

  /// Load persisted groups into UIKit on app startup
  /// This ensures groups are visible in the group list even if contacts haven't been refreshed yet
  Future<void> _loadPersistedGroupsIntoUIKit() =>
      _groupController.loadPersistedGroupsIntoUIKit();

  Future<void> _handleGroupChanged(String groupId, {String? displayName}) =>
      _groupController.handleGroupChanged(groupId, displayName: displayName);

  Future<void> _showAddFriendDialog() async {
    // AddFriendDialog builds its own AppDialog (a Dialog with title bar +
    // responsive inset/maxWidth). Do NOT wrap it in another Dialog — that
    // nests two Dialogs and the outer surface shows as an empty background
    // frame around the inner card (seen on iPad).
    await showDialog(
      context: context,
      builder: (ctx) => AddFriendDialog(
        service: widget.service,
        onShowSnackBar: _showSnackBar,
      ),
    );
  }

  Future<void> _showAddGroupDialog() async {
    // See _showAddFriendDialog: AddGroupDialog is itself an AppDialog, so it
    // is presented directly (no outer Dialog wrapper).
    await showDialog(
      context: context,
      builder: (ctx) => AddGroupDialog(
        service: widget.service,
        onGroupChanged: (gid, {String? displayName}) async {
          await _handleGroupChanged(gid, displayName: displayName);
        },
        onShowSnackBar: _showSnackBar,
      ),
    );
  }

  /// Deep-link entry for the L3 harness: push the REAL group add-member screen
  /// for [groupId] so the campaign can invite a member without traversing the
  /// brittle chat→header-avatar→group-profile→add-member navigation hops. The
  /// invite itself is still performed through the real add-member UI. Returns
  /// false if the session/context is gone; otherwise pushes the screen and
  /// returns true (fire-and-forget — see the invoker registration note).
  Future<bool> _openGroupAddMember(String groupId) async {
    if (!mounted) return false;
    var gid = groupId.trim();
    if (gid.startsWith('group_')) gid = gid.substring(6);
    if (gid.isEmpty) return false;

    // Resolve the group info: prefer the live UIKit cache, fall back to the
    // joined-group list, then to a minimal record. The add-member screen only
    // needs the groupID for the invite; name/avatar are cosmetic.
    V2TimGroupInfo groupInfo = UikitDataFacade.getGroupInfo(gid);
    if (groupInfo.groupID.isEmpty) {
      groupInfo = UikitDataFacade.groupList.firstWhere(
        (g) => g.groupID == gid,
        orElse: () => V2TimGroupInfo(groupID: gid, groupType: 'Work'),
      );
    }

    final memberList = UikitDataFacade.getGroupMemberList(
      gid,
    ).whereType<V2TimGroupMemberFullInfo>().toList();
    final contactList = List<V2TimFriendInfo>.from(UikitDataFacade.contactList);

    // No await between the `mounted` guard and this context use, so the
    // BuildContext is still valid (use_build_context_synchronously is satisfied).
    navigateToAddGroupMember(
      context: context,
      options: TencentCloudChatGroupAddMemberOptions(
        groupInfo: groupInfo,
        memberList: memberList,
        contactList: contactList,
      ),
    );
    return true;
  }

  /// Deep-link to the REAL group member-list page for [groupId]. Mirrors
  /// `_openGroupAddMember`: a navigation-stability harness hook for the real-UI
  /// sweep (the member-list page is then driven through real widgets — the keyed
  /// member rows / desktop kick menu / scroll). Resolves the same group info +
  /// member list the group profile's "Group Members" entry would pass to
  /// `navigateToGroupMemberList`, so it pushes the identical production page.
  Future<bool> _openGroupMemberList(String groupId) async {
    if (!mounted) return false;
    var gid = groupId.trim();
    if (gid.startsWith('group_')) gid = gid.substring(6);
    if (gid.isEmpty) return false;
    _popOverlayRoutes();

    V2TimGroupInfo groupInfo = UikitDataFacade.getGroupInfo(gid);
    if (groupInfo.groupID.isEmpty) {
      groupInfo = UikitDataFacade.groupList.firstWhere(
        (g) => g.groupID == gid,
        orElse: () => V2TimGroupInfo(groupID: gid, groupType: 'Work'),
      );
    }

    // Fetch the member list FRESH (await) instead of reading the SYNC cache,
    // which is empty for a group's first member-list view (no prior load) and
    // left the page blank. Snapshot the sync cache BEFORE the await: the fresh
    // load can itself cache an empty result, so a valid pre-existing cache must
    // be captured first; on an empty/failed fresh load we fall back to the
    // snapshot. Re-check mounted after the await before using context.
    final cachedSnapshot = UikitDataFacade.getGroupMemberList(
      gid,
    ).whereType<V2TimGroupMemberFullInfo>().toList();
    List<V2TimGroupMemberFullInfo> freshList = const [];
    try {
      freshList = (await UikitDataFacade.loadGroupMemberList(
        groupID: gid,
        loadGroupAdminAndOwnerOnly: false,
      )).whereType<V2TimGroupMemberFullInfo>().toList();
    } on Object {
      // A thrown native/FFI load error falls back to the snapshot below.
    }
    if (!mounted) return false;
    final memberList = freshList.isNotEmpty ? freshList : cachedSnapshot;

    // mounted re-checked above after the await, so the BuildContext use below
    // is valid (use_build_context_synchronously is satisfied).
    // unawaited(): navigateToGroupMemberList returns the pushed page's pop
    // Future, which this fire-and-forget invoker intentionally does not await
    // (return as soon as the page is on screen).
    unawaited(
      navigateToGroupMemberList<void>(
            context: context,
            options: TencentCloudChatGroupMemberListOptions(
              groupInfo: groupInfo,
              memberInfoList: memberList,
            ),
          ) ??
          Future<void>.value(),
    );
    return true;
  }

  /// Open the real group PROFILE page deterministically for [groupId], popping
  /// any stale pushed routes first so the profile is the clean, on-top,
  /// full-width route. The avatar-tap open path leaves stale nested
  /// profile/member-list routes across real-UI cases; the element-tree resolver
  /// then lands on a covered, half-width profile (clear/leave below the fold at
  /// the wrong x, the mute switch un-tappable). This mirrors `_openGroupMemberList`
  /// and is the navigation-stability seam for the rename / mute / clear / leave
  /// real-UI cases — the profile widgets themselves are still driven through the
  /// real UI.
  /// Pop stale pushed overlay routes (group profile / member-list pages from
  /// prior real-UI cases) so a freshly-opened one is the sole, on-top route and
  /// the element-tree resolver can't land on a buried duplicate (which left the
  /// leave/clear/mute widgets resolving to a covered, off-screen profile and
  /// the cases failing late in a sweep). SAFE: the overlay pages are pushed as
  /// `MaterialPageRoute` (via `navigateToGroup*`), whereas HomePage is an
  /// `AppPageRoute` (a `PageRouteBuilder`), so this pops only the MaterialPage
  /// overlays and STOPS at the active HomePage — it never disposes HomePage
  /// (which would unregister the L3 invokers) the way a blanket `isFirst`
  /// popUntil did.
  void _popOverlayRoutes() {
    final navigator = Navigator.maybeOf(context, rootNavigator: true);
    if (navigator == null) return;
    navigator.popUntil((route) => route is! MaterialPageRoute || route.isFirst);
  }

  Future<bool> _openGroupProfile(String groupId) async {
    if (!mounted) return false;
    var gid = groupId.trim();
    if (gid.startsWith('group_')) gid = gid.substring(6);
    if (gid.isEmpty) return false;
    _popOverlayRoutes();

    // Pass ONLY the groupID — the profile route loads its own group info fresh
    // via getGroupsInfo(groupID) (which returns groupID == the local gid, the
    // key the rename writes Prefs.setGroupName under). Deliberately do NOT pass
    // an explicit `groupInfo`: the route treats `options.groupInfo` as
    // authoritative over the freshly-loaded data, so a cold/stale
    // UikitDataFacade snapshot could render stale role/mute/name (codex). This
    // keeps the deep-link identical to the real avatar-tap open. unawaited():
    // return as soon as the page is on screen (member-list contract).
    unawaited(
      navigateToGroupProfile<void>(
            context: context,
            options: TencentCloudChatGroupProfileOptions(groupID: gid),
          ) ??
          Future<void>.value(),
    );
    return true;
  }

  Future<void> _checkIrcAppStatus() async {
    final ircAppManager = IrcAppManager();
    await ircAppManager.init();
    if (mounted) {
      setState(() {
        _ircAppInstalled = ircAppManager.isInstalled;
      });
    }
  }

  Future<void> _showJoinIrcChannelDialog() async {
    final ircAppManager = IrcAppManager();
    await ircAppManager.init();

    // Check if app is installed
    if (!ircAppManager.isInstalled) {
      final appL10n = AppLocalizations.of(context)!;
      _showErrorSnackBar(appL10n.ircAppNotInstalled);
      return;
    }

    // The record shape MUST match what IrcChannelDialog actually pops
    // (channel + password + nickname). A 2-field type here threw a runtime
    // _CastError on submit — record types are matched exactly, and the analyzer
    // can't see across the showDialog/Navigator.pop boundary.
    final result =
        await showDialog<
          ({String channel, String? password, String? nickname})
        >(context: context, builder: (ctx) => const IrcChannelDialog());

    if (result == null || result.channel.isEmpty) return;

    try {
      final addResult = await ircAppManager.addChannel(
        result.channel,
        widget.service,
        password: result.password,
        customNickname: result.nickname,
      );
      // Honest outcome: mirror the Applications-page mapping so the two
      // add-channel entry points report identically. Only claim full success
      // when the live IRC connection actually came up; otherwise say
      // added-but-not-connected (e.g. IRC unavailable on this platform).
      switch (classifyIrcAddChannelResult(addResult)) {
        case IrcAddChannelUiOutcome.addedConnected:
        case IrcAddChannelUiOutcome.addedNotConnected:
          await _handleGroupChanged(
            addResult.groupId!,
            displayName: 'IRC: ${result.channel}',
          );
          final appL10n = AppLocalizations.of(context)!;
          _showSnackBar(
            classifyIrcAddChannelResult(addResult) ==
                    IrcAddChannelUiOutcome.addedConnected
                ? appL10n.ircChannelAdded(result.channel)
                : appL10n.ircChannelAddedNotConnected(result.channel),
          );
        case IrcAddChannelUiOutcome.failed:
          final appL10n = AppLocalizations.of(context)!;
          _showErrorSnackBar(appL10n.ircChannelAddFailed);
      }
    } catch (e) {
      final appL10n = AppLocalizations.of(context);
      _showErrorSnackBar('${appL10n?.failed ?? 'Failed'}: $e');
    }
  }

  void _showSnackBar(String message) {
    final ctx = _scaffoldMessengerContext;
    if (ctx == null) return;
    AppSnackBar.show(ctx, message);
  }

  /// Error-styled snackbar variant for failure paths (friend request
  /// failed, IRC join failed, etc). Backed by the same AppSnackBar helper
  /// so it picks up the central error color + 4s duration.
  void _showErrorSnackBar(String message) {
    final ctx = _scaffoldMessengerContext;
    if (ctx == null) return;
    AppSnackBar.showError(ctx, message);
  }

  Future<void> _showMessageReceiversDialog(
    BuildContext context,
    String msgID,
    String groupID,
  ) async {
    final manager = FakeUIKit.instance.messageManager;
    if (manager == null) return;

    final receivers = manager.getMessageReceivers(msgID);
    if (receivers.isEmpty) {
      _showSnackBar(AppLocalizations.of(context)!.noReceivers);
      return;
    }

    // Get friend list to get nicknames
    final friends = await widget.service.getFriendList();
    final friendMap = {for (var f in friends) f.userId: f.nickName};

    // Show dialog with receiver list
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
        ),
        title: Text(
          AppLocalizations.of(
            context,
          )!.messageReceivers(receivers.length.toString()),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: receivers.length,
            itemBuilder: (context, index) {
              final userId = receivers[index];
              final nickname = friendMap[userId] ?? userId;
              final scheme = Theme.of(context).colorScheme;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  foregroundColor: scheme.primary,
                  child: Text(
                    nickname.isNotEmpty
                        ? nickname.substring(0, 1).toUpperCase()
                        : '?',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                title: Text(
                  nickname.isNotEmpty ? nickname : userId,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  userId,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => popDialogIfCurrent(ctx),
            child: Text(AppLocalizations.of(context)!.close),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop keyboard shortcut intents
// ---------------------------------------------------------------------------
// Each intent is a marker type — the matching `CallbackAction` lives inline
// in `HomePage.build` so it can close over local state (`setState`,
// `_showAddFriendDialog`, etc.).
class _OpenSettingsIntent extends Intent {
  const _OpenSettingsIntent();
}

class _NewConversationIntent extends Intent {
  const _NewConversationIntent();
}

class _CloseWindowIntent extends Intent {
  const _CloseWindowIntent();
}

class _OpenSearchIntent extends Intent {
  const _OpenSearchIntent();
}
