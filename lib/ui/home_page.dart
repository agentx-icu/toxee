import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import '../runtime/session_runtime_coordinator.dart';
import '../runtime/tim_sdk_initializer.dart';
import 'package:tencent_cloud_chat_common/external/chat_data_provider.dart';
import '../sdk_fake/fake_msg_provider.dart';
import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/tuicore/tencent_cloud_chat_core.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_controller.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation.dart' as conv_pkg;
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message.dart' as msg_pkg;
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/tencent_cloud_chat_message_input.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_widgets/tencent_cloud_chat_message_item_builders.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact.dart' as contact_pkg;
import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact.dart';
import 'contact/contact_builder_override.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_user_profile.dart';
import 'package:tencent_cloud_chat_intl/tencent_cloud_chat_intl.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import '../i18n/app_localizations.dart';
import '../util/logger.dart';
import 'package:tencent_cloud_chat_common/components/component_event_handlers/tencent_cloud_chat_contact_event_handlers.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_config.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_layout/special_case/tencent_cloud_chat_message_no_chat.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_header/tencent_cloud_chat_message_header.dart' as msg_header;
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_utils.dart' as tcc_utils;
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_models.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_common/data/conversation/tencent_cloud_chat_conversation_data.dart';
import 'package:tencent_cloud_chat_common/data/contact/tencent_cloud_chat_contact_data.dart';
import 'package:tencent_cloud_chat_common/data/basic/tencent_cloud_chat_basic_data.dart';
import 'package:tencent_cloud_chat_common/data/group_profile/tencent_cloud_chat_group_profile_data.dart';
import 'group/group_member_list_wrapper.dart';
import 'package:tencent_cloud_chat_common/eventbus/tencent_cloud_chat_eventbus.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_change_info.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_filter_enum.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_router.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_route_names.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_user_profile_options.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_sticker/tencent_cloud_chat_sticker.dart';
import 'package:tencent_cloud_chat_sticker/tencent_cloud_chat_sticker_init_data.dart';
import 'package:tencent_cloud_chat_text_translate/tencent_cloud_chat_text_translate.dart';
import 'package:tencent_cloud_chat_sound_to_text/tencent_cloud_chat_sound_to_text.dart';
import 'search/custom_search.dart' as search_pkg;
import 'package:tencent_cloud_chat_sdk/enum/conversation_type.dart';
import 'package:tencent_cloud_chat_sdk/native_im/adapter/tim_message_manager.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';
import 'package:tim2tox_dart/utils/binary_replacement_history_hook.dart';
import 'settings/settings_page.dart';
import 'settings/sidebar.dart';
import 'applications/applications_page.dart';
import 'home/home_utils.dart';
import '../util/app_theme_config.dart';
import '../util/app_tray.dart';
import '../util/lan_bootstrap_service.dart';
import '../util/platform_utils.dart';
import 'add_friend_dialog.dart';
import 'add_group_dialog.dart';
import 'home/home_session_controller.dart';
import 'home/home_widgets.dart';
import '../util/irc_app_manager.dart';
import 'applications/irc_channel_dialog.dart';
import '../util/responsive_layout.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_tatal_unread_count.dart';
import 'widgets/app_page_route.dart';
import 'widgets/app_snackbar.dart';
import 'package:window_manager/window_manager.dart';

part 'home_page_persistence.dart';
part 'home_page_plugins.dart';
part 'home_page_bootstrap.dart';

enum _MediaPickType { image, video }

class HomePage extends StatefulWidget {
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
  List<({String userId, String nickName, bool online, String status})> _friends = [];
  Timer? _refreshTimer;
  Set<String> _localFriends = {};
  bool _autoAcceptFriends = false;
  bool _autoAcceptGroupInvites = false;
  List<V2TimFriendApplication> _pendingFriendApps = [];
  bool _stickerPluginRegistered = false;
  // Set the instant we enqueue a sticker-plugin postFrame callback, so back-
  // to-back rebuilds before the callback fires don't queue duplicates.
  bool _stickerPluginRegistrationScheduled = false;
  bool _textTranslatePluginRegistered = false;
  bool _soundToTextPluginRegistered = false;
  StreamSubscription? _msgSub;
  StreamSubscription? _progressUpdatesSub;
  StreamSubscription<bool>? _connectionStatusSub;
  StreamSubscription<TencentCloudChatConversationData<dynamic>>? _conversationDataSub;
  StreamSubscription<TencentCloudChatContactData<dynamic>>? _contactDataSub;
  StreamSubscription<TencentCloudChatGroupProfileData<dynamic>>? _groupProfileDataSub;
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
  StreamSubscription<bool>? _persistenceHookSub;
  bool _persistenceHookInstalled = false;
  bool _disposed = false;
  ContactBuilderOverrideHandle? _contactBuilderOverride;
  late final HomeSessionController _sessionController;
  // Tracks the last computed `shouldShowMasterDetail` so we only schedule the
  // UIKit `setConfigs(forceDesktopLayout: ...)` post-frame callback when the
  // breakpoint actually crosses, instead of on every rebuild.
  bool? _lastShouldShowMasterDetail;

  @override
  void initState() {
    super.initState();
    _sessionController = HomeSessionController(service: widget.service);
    WidgetsBinding.instance.addObserver(this);
    _bag.add(() => WidgetsBinding.instance.removeObserver(this));
    // HYBRID MODE: Using both binary replacement (for most operations) and Platform interface (for history queries)
    // This allows:
    // - Most operations to use binary replacement (TIMManager.instance -> NativeLibraryManager -> Dart* functions)
    // - History queries to use Platform interface (Tim2ToxSdkPlatform -> FfiChatService -> MessageHistoryPersistence)
    // This ensures history messages are loaded from persistence service instead of returning empty list from C++ layer

    // Session runtime (FakeUIKit, platform, CallServiceManager) via coordinator
    unawaited(_initAfterSessionReady());
    // React to locale changes once, instead of scheduling a post-frame
    // setLocale in every `build()`. Listener fires only on value change.
    AppLocale.locale.addListener(_handleAppLocaleChanged);
    _bag.add(() => AppLocale.locale.removeListener(_handleAppLocaleChanged));
    // Register conversation right-click handler — deferred to next frame so
    // UIKit's conversation event handlers singleton is wired up first (the
    // `setEventHandlers(onTapConversationItem: ...)` call lives in
    // `home_page_bootstrap.dart::_buildHomePage`, which runs during build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        conv_pkg.TencentCloudChatConversationManager.eventHandlers
            .uiEventHandlers
            .setEventHandlers(
          onSecondaryTapConversationItem: ({
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
            conv_pkg.TencentCloudChatConversationManager.eventHandlers
                .uiEventHandlers
                .setEventHandlers(
              onSecondaryTapConversationItem: ({
                required V2TimConversation conversation,
                required Offset position,
              }) async => false,
            );
          } catch (_) {}
        });
      } catch (e, st) {
        AppLogger.logError(
          '[HomePage] Failed to register onSecondaryTapConversationItem',
          e,
          st,
        );
      }
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
                  color: colorTheme.contactAddContactFriendInfoStateButtonBackgroundColor,
                ),
                padding: EdgeInsets.symmetric(
                  vertical: TencentCloudChatScreenAdapter.getHeight(10),
                  horizontal: TencentCloudChatScreenAdapter.getWidth(16),
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
    final requestMessage = AppLocalizations.of(context)?.defaultFriendRequestMessage ?? 'Hello';
    try {
      await widget.service.addFriend(userID, requestMessage: requestMessage);
      // Show success message
      if (mounted) {
        AppSnackBar.show(
          context,
          AppLocalizations.of(context)!.friendRequestSent,
        );
        // Refresh contacts to update UI
        FakeUIKit.instance.im?.refreshContacts();
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
      final info = await LanBootstrapServiceManager.instance.getBootstrapServiceInfo();
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
    // Save tox profile when app goes to background to reduce data loss on kill/crash
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      widget.service.saveToxProfileNow();
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
    });
    _selectConversation(peerId: peerId, groupId: groupId);
    unawaited(_updateTray());
  }

  Future<void> _sendMedia(BuildContext context, {String? userId, String? groupId, required _MediaPickType type}) async {
    final appL10n = AppLocalizations.of(context)!;
    final label = type == _MediaPickType.image ? appL10n.photo : appL10n.video;
    if (groupId != null && groupId.isNotEmpty) {
      _showSnackBar(appL10n.sendingToGroupsNotSupported(label));
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: type == _MediaPickType.image ? FileType.image : FileType.video,
      );
      final path = result?.files.single.path;
      if (path == null || path.isEmpty) {
        _showSnackBar(appL10n.noLabelSelected(label));
        return;
      }
      if (userId != null) {
        // Check if friend is online before sending
        final friends = await widget.service.getFriendList();
        final friend = friends.firstWhere(
          (f) => f.userId == userId,
          orElse: () => (userId: userId, nickName: '', online: false, status: ''),
        );
        if (!friend.online) {
          // Send a text message to chat window indicating failure (two lines: error + file path)
          final failureMsg = type == _MediaPickType.image 
              ? appL10n.friendOfflineSendImageFailed 
              : appL10n.friendOfflineSendVideoFailed;
          final twoLineMsg = '$failureMsg\n$path';
          final mgr = FakeUIKit.instance.messageManager;
          if (mgr != null) {
            await mgr.sendText('c2c_$userId', twoLineMsg);
          }
          return;
        }
        await widget.service.sendFile(userId, path);
        _showSnackBar('$label sent');
      }
    } catch (e) {
      final appL10n = AppLocalizations.of(context)!;
      final errorMsg = e.toString();
      String userMsg;
      if (errorMsg.contains('offline') || errorMsg.contains('not connected')) {
        // Send a text message to chat window indicating failure (two lines: error + file path)
        // Note: path variable is not available in catch block, so we skip file path in error message
        if (userId != null) {
          final failureMsg = type == _MediaPickType.image 
              ? appL10n.friendOfflineSendImageFailed 
              : appL10n.friendOfflineSendVideoFailed;
          final mgr = FakeUIKit.instance.messageManager;
          if (mgr != null) {
            await mgr.sendText('c2c_$userId', failureMsg);
          }
        }
        userMsg = appL10n.friendOfflineCannotSendFile;
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
    final displayName = (nick != null && nick.trim().isNotEmpty) ? nick.trim() : widget.service.selfId;
    final locale = AppLocale.locale.value;
    final appL10n = AppLocalizations.of(context);
    return generateContactCardImage(
      userId: widget.service.selfId,
      displayName: displayName,
      locale: locale,
      bottomText: appL10n?.scanQrCodeToAddContact ?? 'Scan QR code to add me as contact',
      primaryColor: AppThemeConfig.primaryColor,
      avatarPath: avatarPath,
    );
  }

  List<TencentCloudChatMessageGeneralOptionItem> _buildDesktopInputOptions(BuildContext context, {String? userID, String? groupID}) {
    final appL10n = AppLocalizations.of(context)!;
    final photoLabel = appL10n.photo;
    final videoLabel = appL10n.video;
    final personalCardLabel = appL10n.personalCard;
    final personalCardGroupLabel = appL10n.sendPersonalCardToGroup;
    final sentSnack = appL10n.personalCardSent;
    final sentGroupSnack = appL10n.sentPersonalCardToGroup;
    final options = <TencentCloudChatMessageGeneralOptionItem>[
      TencentCloudChatMessageGeneralOptionItem(
        icon: Icons.photo_outlined,
        label: photoLabel,
        onTap: ({Offset? offset}) async {
          await _sendMedia(context, userId: userID, groupId: groupID, type: _MediaPickType.image);
        },
      ),
      TencentCloudChatMessageGeneralOptionItem(
        icon: Icons.videocam_outlined,
        label: videoLabel,
        onTap: ({Offset? offset}) async {
          await _sendMedia(context, userId: userID, groupId: groupID, type: _MediaPickType.video);
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
                orElse: () => (userId: userID, nickName: '', online: false, status: ''),
              );
              if (!friend.online) {
                final appL10n = AppLocalizations.of(context)!;
                // Send a text message to chat window indicating failure (two lines: error + file path)
                final qrPath = await _createSelfQrCardImage();
                final twoLineMsg = '${appL10n.friendOfflineSendCardFailed}\n$qrPath';
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
              if (errorMsg.contains('offline') || errorMsg.contains('not connected')) {
                // Send a text message to chat window indicating failure (two lines: error + file path)
                // Try to get the file path from the error or use a default message
                try {
                  final qrPath = await _createSelfQrCardImage();
                  final twoLineMsg = '${appL10n.friendOfflineSendCardFailed}\n$qrPath';
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
                    await mgr.sendText('c2c_$userID', appL10n.friendOfflineSendCardFailed);
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
                    final afterColon = errorText.substring(colonIndex + 1).trim();
                    // Check if after colon looks like a file path
                    if (afterColon.startsWith('/') || afterColon.contains('\\')) {
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
            final text = '${appL10n.myId}: ${widget.service.selfId}';
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
    final uikitUnreadCount = TencentCloudChat.instance.dataInstance.conversation.totalUnreadCount;
    // Get friend application unread count
    final applicationUnreadCount = TencentCloudChat.instance.dataInstance.contact.applicationUnreadCount;
    // Total count = conversation unread + friend applications
    final totalCount = uikitUnreadCount + applicationUnreadCount;
    await AppTray.instance.update(count: totalCount, online: widget.service.isConnected);
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
        TencentCloudChat.instance.dataInstance.contact.contactEventHandlers = TencentCloudChatContactEventHandlers(
          uiEventHandlers: TencentCloudChatContactUIEventHandlers(
            onTapContactItem: ({String? userID, String? groupID}) async {
              // Handle navigation from contact list and profile page "Send Message" button
              if (userID != null) {
                // Check if we're already in a profile page (Navigator can pop)
                // If yes, this is a "Send Message" click, so navigate to chat
                // If no, this is a contact list click, so show profile
                final canPop = Navigator.of(context).canPop();
                if (canPop) {
                  // We're in a profile page, close it and navigate to chat
                  Navigator.of(context).pop();
                  // Switch to chats tab and open 1:1 chat
                  setState(() {
                    _index = 0;
                  });
                  _selectConversation(peerId: userID);
                  return true; // Handled, prevent default navigation
                } else {
                  // We're in contact list, show profile page on the right side
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
      } catch (e) {
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
            final useBottomNav =
                ResponsiveLayout.shouldShowBottomNav(context);
            final useSidebar = !useBottomNav;
            final showMasterDetail =
                ResponsiveLayout.shouldShowMasterDetail(context);

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
                  TencentCloudChat.instance.dataInstance.conversation
                      .conversationConfig
                      .setConfigs(forceDesktopLayout: showMasterDetail);
                } catch (_) {
                  // Config object may not exist yet on the very first frame
                  // (UIKit init is async); next layout pass will pick it up.
                }
              });
            }

            Widget content = PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                // If not on the Chats tab, go back to Chats
                if (_index != 0) {
                  setState(() { _index = 0; });
                  return;
                }
                // On Chats tab: double-press back to exit
                final now = DateTime.now();
                if (_lastBackPressTime != null &&
                    now.difference(_lastBackPressTime!) < const Duration(seconds: 2)) {
                  SystemNavigator.pop();
                  return;
                }
                _lastBackPressTime = now;
                AppSnackBar.show(_scaffoldMessengerContext ?? context, AppLocalizations.of(context)!.pressBackAgainToExit);
              },
              child: Scaffold(
              drawer: useBottomNav ? _buildMobileDrawer() : null,
              body: SafeArea(
                child: Stack(
                children: [
                  Row(
                    children: [
                      if (useSidebar) ...[
                        SizedBox(
                          width: ResponsiveLayout.responsiveSidebarWidth(context),
                          child: Column(
                            children: [
                              // macOS traffic-light reservation — without this
                              // the avatar at the top of the sidebar sits under
                              // the window control dots.
                              if (PlatformUtils.isMacOS)
                                const SizedBox(
                                  height: ResponsiveLayout
                                      .macTitleBarReservedHeight,
                                ),
                              Expanded(child: _uikitSidebar()),
                            ],
                          ),
                        ),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ],
                      Expanded(
                        child: _buildMainPane(context),
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
                        reverseDuration: MediaQuery.disableAnimationsOf(context)
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
                        child: (_lanBootstrapServiceRunning && _lanBootstrapServiceIP != null && _lanBootstrapServicePort != null)
                            ? Material(
                                key: const ValueKey('lan-bootstrap-banner'),
                                elevation: 0,
                                color: AppThemeConfig.successColor.withValues(alpha: 0.08),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: AppThemeConfig.successColor.withValues(alpha: 0.25),
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
                                          AppLocalizations.of(context)!.bootstrapServiceRunning(
                                            _lanBootstrapServiceIP!,
                                            _lanBootstrapServicePort!,
                                          ),
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: Theme.of(context).colorScheme.onSurface,
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 18),
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        // 44x44 minimum tap area for mobile (Apple HIG / Material 48dp).
                                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                                        padding: EdgeInsets.zero,
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          setState(() {
                                            _lanBootstrapServiceRunning = false;
                                          });
                                        },
                                        tooltip: AppLocalizations.of(context)!.hide,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(key: ValueKey('lan-bootstrap-banner-hidden')),
                      ),
                    ),
                ],
              ),
              ),
              bottomNavigationBar: useBottomNav ? _buildBottomNavigationBar() : null,
            ),
            );
            // Desktop keyboard shortcuts — meta+/ctrl+ comma/N/W/F.
            // Setting both `meta` and `control` on the SingleActivator
            // works for macOS and Win/Linux without a per-platform branch.
            if (PlatformUtils.isDesktop) {
              content = Shortcuts(
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.comma,
                      meta: true, control: true): _OpenSettingsIntent(),
                  SingleActivator(LogicalKeyboardKey.keyN,
                      meta: true, control: true): _NewConversationIntent(),
                  SingleActivator(LogicalKeyboardKey.keyW,
                      meta: true, control: true): _CloseWindowIntent(),
                  SingleActivator(LogicalKeyboardKey.keyF,
                      meta: true, control: true): _OpenSearchIntent(),
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
                        // `userID`/`groupID` left null so the overlay runs in
                        // global mode (search all conversations).
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

  Widget? _buildMobileDrawer() {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      // 280 — Material Drawer guidance for phones; close to the spec width.
      width: 280,
      elevation: 0,
      backgroundColor: scheme.surface,
      // Default Material Drawer shape (top-right + bottom-right rounded
      // trailing edge) is fine for mobile — let Material handle it.
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MobileDrawerHeader(
              service: widget.service,
              connectionStatusStream: widget.service.connectionStatusStream,
            ),
            Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
            const SizedBox(height: AppSpacing.sm),
            _MobileDrawerItem(
              selected: _index == 0,
              icon: Icons.chat_bubble_outline,
              selectedIcon: Icons.chat_bubble,
              label: l10n.chats,
              showUnreadBadge: true,
              onTap: () {
                setState(() => _index = 0);
                Navigator.of(context).pop();
              },
            ),
            _MobileDrawerItem(
              selected: _index == 1,
              icon: Icons.contacts_outlined,
              selectedIcon: Icons.contacts,
              label: l10n.contacts,
              onTap: () {
                setState(() => _index = 1);
                Navigator.of(context).pop();
              },
            ),
            const Spacer(),
            _MobileDrawerItem(
              selected: _index == 3,
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: l10n.settings,
              onTap: () {
                setState(() => _index = 3);
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Widget? _buildBottomNavigationBar() {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
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
                  TencentCloudChatConversationController.instance
                      .scrollToTop(),
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
          selectedItemColor: scheme.primary,
          unselectedItemColor: scheme.onSurfaceVariant,
          backgroundColor: theme.scaffoldBackgroundColor,
          iconSize: 24,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          selectedLabelStyle: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
          unselectedLabelStyle: theme.textTheme.labelSmall,
          items: [
            BottomNavigationBarItem(
              icon: Stack(
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
                          final displayText = totalUnreadCount > 99 ? "99+" : "$totalUnreadCount";
                          final isLargeText = displayText.length > 2;
                          return Semantics(
                            label: AppLocalizations.of(context)!.unreadMessagesSemantics(totalUnreadCount),
                            container: true,
                            child: UnconstrainedBox(
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 16),
                                height: 16,
                                padding: EdgeInsets.symmetric(horizontal: isLargeText ? 5 : 4),
                                decoration: BoxDecoration(
                                  color: AppThemeConfig.errorColor,
                                  borderRadius: BorderRadius.circular(AppThemeConfig.badgeBorderRadius),
                                  border: Border.all(
                                    color: theme.scaffoldBackgroundColor,
                                    width: 1.5,
                                  ),
                                ),
                                child: Center(
                                  child: ExcludeSemantics(
                                    child: Text(
                                      displayText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                            color: scheme.onError,
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
              icon: const Icon(Icons.contacts_outlined),
              activeIcon: const Icon(Icons.contacts),
              label: l10n.contacts,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.apps_outlined),
              activeIcon: const Icon(Icons.apps),
              label: l10n.applications,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.settings_outlined),
              activeIcon: const Icon(Icons.settings),
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
    return IndexedStack(
      index: _index,
      children: _buildTabChildren(),
    );
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
          );
        },
      ),
      ValueListenableBuilder<Locale>(
        valueListenable: AppLocale.locale,
        builder: (context, locale, _) {
          return ValueListenableBuilder<ThemeMode>(
            valueListenable: AppTheme.mode,
            builder: (context, themeMode, __) {
              return Stack(
                children: [
                  TencentCloudChatThemeWidget(
                    build: (context, themeColors, textStyles) {
                      return TencentCloudChatContact(
                        key: ValueKey(
                            'uikit-contact-${locale.languageCode}-${themeMode.name}'),
                      );
                    },
                  ),
                  Positioned(
                    top: AppSpacing.lg,
                    right: AppSpacing.xl,
                    // Right-edge SafeArea only — guards Dynamic Island /
                    // right rounded corners on phones in landscape.
                    child: SafeArea(
                      left: false,
                      top: false,
                      bottom: false,
                      child: NewEntryButton(
                        onAddFriend: _showAddFriendDialog,
                        onCreateGroup: _showAddGroupDialog,
                        onJoinIrcChannel: _ircAppInstalled
                            ? _showJoinIrcChannelDialog
                            : null,
                      ),
                    ),
                  ),
                ],
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
      SettingsPage(
        service: widget.service,
        connectionStatusStream: widget.service.connectionStatusStream,
        autoAcceptFriends: _autoAcceptFriends,
        onAutoAcceptFriendsChanged: _setAutoAcceptFriends,
        autoAcceptGroupInvites: _autoAcceptGroupInvites,
        onAutoAcceptGroupInvitesChanged: _setAutoAcceptGroupInvites,
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
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
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
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: 18,
                color: scheme.error,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(l10n.delete, style: TextStyle(color: scheme.error)),
            ],
          ),
        ),
      ],
    );
    if (!mounted || selected == null) return;

    final convId = conv.conversationID;
    switch (selected) {
      case 'pin':
        try {
          await TencentImSDKPlugin.v2TIMManager
              .getConversationManager()
              .pinConversation(
                conversationID: convId,
                isPinned: !isPinned,
              );
        } catch (e, st) {
          AppLogger.logError(
              '[HomePage] pinConversation failed for $convId', e, st);
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
              st);
        }
        break;
      case 'delete':
        final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialogCtx) => AlertDialog(
                title: Text(l10n.deleteConversationTitle),
                content: Text(
                  l10n.deleteConversationBody(conv.showName ?? convId),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(false),
                    child: Text(l10n.cancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(true),
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
                    child: Text(l10n.delete),
                  ),
                ],
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
              '[HomePage] deleteConversation failed for $convId', e, st);
        }
        break;
    }
  }

  /// Show user profile page - uses router which handles desktop/mobile modes
  void _showUserProfileOnRight(BuildContext context, String userID) {
    TencentCloudChatRouter().navigateTo(
      context: context,
      routeName: TencentCloudChatRouteNames.userProfile,
      options: TencentCloudChatUserProfileOptions(userID: userID),
    );
  }

  void _selectConversation({String? peerId, String? groupId}) {
    final convData = TencentCloudChat.instance.dataInstance.conversation;
    final bool hasPeer = peerId != null && peerId.isNotEmpty;
    final bool hasGroup = groupId != null && groupId.isNotEmpty;
    if (!hasPeer && !hasGroup) {
      widget.service.setActivePeer(null);
      return;
    }
    final String targetConvId = hasGroup ? 'group_$groupId' : 'c2c_${peerId!}';

    V2TimConversation? target;
    for (final conv in convData.conversationList) {
      if (conv.conversationID == targetConvId) {
        target = conv;
        break;
      }
    }
    if (target == null) {
      target = V2TimConversation(
        conversationID: targetConvId,
        type: hasGroup ? ConversationType.V2TIM_GROUP : ConversationType.V2TIM_C2C,
        userID: hasGroup ? null : peerId,
        groupID: hasGroup ? groupId : null,
        showName: hasGroup ? groupId : peerId,
        unreadCount: 0,
      );
    }
    convData.currentConversation = target;
  }

  Future<void> _setAutoAcceptFriends(bool value) async {
    if (_autoAcceptFriends == value) return;
    setState(() => _autoAcceptFriends = value);
    final toxId = widget.service.selfId;
    if (toxId.isNotEmpty) {
      await Prefs.setAutoAcceptFriends(value, toxId);
    }
    if (value && _pendingFriendApps.isNotEmpty) {
      await _acceptFriendApplications(List<V2TimFriendApplication>.from(_pendingFriendApps));
    }
  }

  Future<void> _setAutoAcceptGroupInvites(bool value) async {
    if (_autoAcceptGroupInvites == value) return;
    setState(() => _autoAcceptGroupInvites = value);
    final toxId = widget.service.selfId;
    if (toxId.isNotEmpty) {
      await Prefs.setAutoAcceptGroupInvites(value, toxId);
    }
    // Update FFI setting so C++ can read it
    widget.service.setAutoAcceptGroupInvites(value);
  }

  Future<void> _acceptFriendApplications(List<V2TimFriendApplication> apps) async {
    for (final app in apps) {
      final uid = app.userID;
      if (uid.isEmpty) continue;
      try {
        await widget.service.acceptFriendRequest(uid);
      } catch (e) {
      }
    }
    _pendingFriendApps = [];
    if (mounted) setState(() {});
    await FakeUIKit.instance.im?.refreshContacts();
    await _load();
      _showSnackBar(AppLocalizations.of(context)!.autoAcceptedNewFriendRequest);
    await _updateTray();
  }

  Future<void> _handleFriendAdded(String friendId) async {
    final trimmed = friendId.trim();
    if (trimmed.isEmpty) return;
    // Don't write to Prefs here — FakeIM._emitContactsWithFriendsImpl is the
    // single authority for Prefs.localFriends. It will persist the Tox friend list
    // on the next refresh cycle. Writing here risks re-adding stale friends from
    // _localFriends.
    await FakeUIKit.instance.im?.refreshContacts();
    await _load();
  }

  /// Load persisted groups into UIKit on app startup
  /// This ensures groups are visible in the group list even if contacts haven't been refreshed yet
  Future<void> _loadPersistedGroupsIntoUIKit() async {
    try {
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Loading persisted groups');
      
      // Load groups directly from Prefs instead of relying on service.knownGroups
      // This ensures we get groups even if service.init() hasn't completed yet
      final savedGroups = await Prefs.getGroups();
      final quitGroups = await Prefs.getQuitGroups();
      // Only load groups that are not in quit list
      final activeGroups = savedGroups.where((g) => !quitGroups.contains(g)).toSet();
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Loaded ${activeGroups.length} groups from Prefs (savedGroups=${savedGroups.length}, quitGroups=${quitGroups.length})');
      
      // Also try to get groups from service (in case init() has completed)
      final knownGroups = widget.service.knownGroups;
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: knownGroups from service: ${knownGroups.length} groups');
      
      // Merge both sources to ensure we have all groups
      final allGroups = {...activeGroups, ...knownGroups};
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Total groups to load: ${allGroups.length}');
      
      // Load group info for each group and add to UIKit
      for (final gid in allGroups) {
        final savedName = await Prefs.getGroupName(gid);
        final savedAvatar = await Prefs.getGroupAvatar(gid);
        final groupInfo = V2TimGroupInfo(
          groupID: gid,
          groupType: "work",
          groupName: savedName,
          faceUrl: savedAvatar,
        );
        // addGroupInfoToJoinedGroupList will check if group already exists and update it if needed
        TencentCloudChat.instance.dataInstance.contact.addGroupInfoToJoinedGroupList(groupInfo);
      }
      
      // Also call getGroupList() to refresh the list from SDK
      // However, we need to preserve existing groups because SDK may not know about historical groups
      // Save existing groups before calling getGroupList()
      final groupsBeforeSDK = List<V2TimGroupInfo>.from(TencentCloudChat.instance.dataInstance.contact.groupList);
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Groups before getGroupList(): ${groupsBeforeSDK.length}, groupIds=${groupsBeforeSDK.map((g) => '${g.groupID}(${g.groupName})').toList()}');
      
      await TencentCloudChat.instance.chatSDKInstance.contactSDK.getGroupList();
      
      final sdkGroupList = TencentCloudChat.instance.dataInstance.contact.groupList;
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: SDK returned ${sdkGroupList.length} groups: ${sdkGroupList.map((g) => '${g.groupID}(${g.groupName})').toList()}');
      
      // Use quitGroups that was already loaded earlier (line 1836)
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Quit groups: ${quitGroups.toList()}');
      
      // Merge SDK groups with existing groups to preserve historical groups.
      // When our source of truth (Prefs + service) has no groups (e.g. new account after logout),
      // do not merge in groupsBeforeSDK — they are stale from the previous account.
      final groupsMap = <String, V2TimGroupInfo>{};
      if (allGroups.isNotEmpty) {
        // First add existing groups from UIKit (filter out quit groups and empty groupIDs)
        for (final group in groupsBeforeSDK) {
          if (group.groupID.isEmpty) continue; // Skip entries with empty groupID
          if (!quitGroups.contains(group.groupID)) {
            groupsMap[group.groupID] = group;
          } else {
            if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Filtering out quit group: ${group.groupID}');
          }
        }
      }
      // Then add/update with SDK groups (SDK groups take precedence, but filter out quit groups and empty groupIDs)
      for (final group in sdkGroupList) {
        if (group.groupID.isEmpty) continue; // Skip entries with empty groupID
        if (!quitGroups.contains(group.groupID)) {
          groupsMap[group.groupID] = group;
        } else {
          if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Filtering out quit group from SDK list: ${group.groupID}');
        }
      }

      final mergedGroups = groupsMap.values.toList();
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Merged ${mergedGroups.length} groups: ${mergedGroups.map((g) => '${g.groupID}(${g.groupName})').toList()}');
      
      // Update with merged groups
      TencentCloudChat.instance.dataInstance.contact.buildGroupList(mergedGroups, '_loadPersistedGroupsIntoUIKit_merge');
      
      final finalGroupList = TencentCloudChat.instance.dataInstance.contact.groupList;
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Final groupList length=${finalGroupList.length}, groupIds=${finalGroupList.map((g) => g.groupID).toList()}');
      
      // Refresh conversations to ensure conversation list is in sync with group list
      // This is critical for startup scenario to ensure data consistency
      if (kDebugMode) debugPrint('[HomePage] _loadPersistedGroupsIntoUIKit: Refreshing conversations to sync with group list');
      await FakeUIKit.instance.im?.refreshConversations();
    } catch (e, stackTrace) {
      AppLogger.logError('[HomePage] _loadPersistedGroupsIntoUIKit: Error loading groups', e, stackTrace);
    }
  }

  Future<void> _handleGroupChanged(String groupId, {String? displayName}) async {
    if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: groupId=$groupId, displayName=$displayName');
    if (displayName != null && displayName.isNotEmpty) {
      await Prefs.setGroupName(groupId, displayName);
    }
    
    // Clear UIKit's in-memory message list for this group ID.
    // When a group ID is reused (e.g., quit tox_7 then create new tox_7),
    // UIKit's _messageListMap may still hold old messages from the previous group.
    TencentCloudChat.instance.dataInstance.messageData.clearMessageList(groupID: groupId);

    // CRITICAL: Save existing groups before calling getGroupList()
    // This is necessary because buildGroupList() clears the entire list and only keeps SDK-returned groups
    // SDK may not know about historical groups, so we need to preserve them
    final existingGroups = List<V2TimGroupInfo>.from(TencentCloudChat.instance.dataInstance.contact.groupList);
    if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: Saved ${existingGroups.length} existing groups before getGroupList: ${existingGroups.map((g) => '${g.groupID}(${g.groupName})').toList()}');

    // Delete old group info from UIKit first to ensure clean state
    // This is important when group ID is reused (e.g., numeric IDs)
    TencentCloudChat.instance.dataInstance.contact.deleteGroupInfoFromJoinedGroupList(groupId);
    
    // Refresh group list in UIKit first to ensure we have the latest list from SDK
    // However, we need to merge SDK groups with existing groups to preserve historical groups
    try {
      if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: Calling getGroupList()');
      await TencentCloudChat.instance.chatSDKInstance.contactSDK.getGroupList();
      final sdkGroupList = TencentCloudChat.instance.dataInstance.contact.groupList;
      if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: After getGroupList(), SDK returned ${sdkGroupList.length} groups: ${sdkGroupList.map((g) => '${g.groupID}(${g.groupName})').toList()}');
      
      // Merge SDK groups with existing groups (excluding the group being updated)
      // This preserves historical groups that SDK doesn't know about
      final existingGroupsMap = <String, V2TimGroupInfo>{};
      for (final group in existingGroups) {
        if (group.groupID.isEmpty) continue; // Skip entries with empty groupID
        if (group.groupID != groupId) { // Exclude the group being updated
          existingGroupsMap[group.groupID] = group;
        }
      }

      // Add SDK groups to the map (they will override existing groups with same ID)
      for (final group in sdkGroupList) {
        if (group.groupID.isEmpty) continue; // Skip entries with empty groupID
        existingGroupsMap[group.groupID] = group;
      }
      
      // Rebuild the merged list
      final mergedGroups = existingGroupsMap.values.toList();
      if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: Merged ${mergedGroups.length} groups (${existingGroups.length} existing + ${sdkGroupList.length} SDK): ${mergedGroups.map((g) => '${g.groupID}(${g.groupName})').toList()}');
      
      // Update the group list with merged groups
      TencentCloudChat.instance.dataInstance.contact.buildGroupList(mergedGroups, '_handleGroupChanged_merge');
    } catch (e) {
      if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: getGroupList() failed: $e');
    }
    // Update group info in UIKit to ensure it has the latest data (including cleared avatar)
    // This is called after getGroupList() to ensure the new group is added even if getGroupList
    // didn't include it (e.g., due to timing issues)
    final savedName = await Prefs.getGroupName(groupId);
    final savedAvatar = await Prefs.getGroupAvatar(groupId);
    final groupInfo = V2TimGroupInfo(
      groupID: groupId,
      groupType: "work",
      groupName: savedName,
      faceUrl: savedAvatar, // This will be null if cleared, ensuring UIKit doesn't use old avatar
    );
    if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: Adding groupInfo: groupID=${groupInfo.groupID}, groupName=${groupInfo.groupName}');
    TencentCloudChat.instance.dataInstance.contact.addGroupInfoToJoinedGroupList(groupInfo);
    final afterAddGroupList = TencentCloudChat.instance.dataInstance.contact.groupList;
    if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: After addGroupInfoToJoinedGroupList(), groupList length=${afterAddGroupList.length}, groupIds=${afterAddGroupList.map((g) => g.groupID).toList()}');
    
    // Ensure group is in knownGroups and persisted before refreshing conversations
    // This ensures refreshConversations() can find the new group
    if (!widget.service.knownGroups.contains(groupId)) {
      if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: Group $groupId not in knownGroups, ensuring it is added');
      // The group should already be in knownGroups from createGroup, but double-check
      // If not, we need to ensure it's added (though this shouldn't happen)
    }
    
    // Ensure group is persisted to Prefs before refreshing conversations
    final currentPersistedGroups = await Prefs.getGroups();
    if (!currentPersistedGroups.contains(groupId)) {
      if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: Group $groupId not in persisted groups, adding it');
      currentPersistedGroups.add(groupId);
      await Prefs.setGroups(currentPersistedGroups);
    }
    
    // Small delay to ensure persistence is complete
    await Future.delayed(const Duration(milliseconds: 50));

    // CRITICAL: Unblock the conversation in FakeChatDataProvider.
    // deleteGroupInfoFromJoinedGroupList (above) fires a quitGroup event which adds
    // this conversation to _sdkDeletedConvIds, preventing it from being rebuilt with
    // proper showName. Remove it so refreshConversations can re-create it correctly.
    final provider = ChatDataProviderRegistry.provider;
    if (provider is FakeChatDataProvider) {
      provider.unblockConversation('group_$groupId');
    }

    // Refresh conversations to update conversation list
    if (kDebugMode) debugPrint('[HomePage] _handleGroupChanged: Refreshing conversations to add group $groupId to conversation list');
    await FakeUIKit.instance.im?.refreshConversations();
    await _updateTray();
  }

  Future<void> _showAddFriendDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: AddFriendDialog(
          service: widget.service,
          onFriendAdded: (id) async {
            await _handleFriendAdded(id);
          },
          onShowSnackBar: _showSnackBar,
        ),
      ),
    );
  }

  Future<void> _showAddGroupDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: AddGroupDialog(
          service: widget.service,
          onGroupChanged: (gid, {String? displayName}) async {
            await _handleGroupChanged(gid, displayName: displayName);
          },
          onShowSnackBar: _showSnackBar,
        ),
      ),
    );
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

    final result = await showDialog<({String channel, String? password})>(
      context: context,
      builder: (ctx) => const IrcChannelDialog(),
    );

    if (result == null || result.channel.isEmpty) return;

    try {
      final groupId = await ircAppManager.addChannel(
        result.channel,
        widget.service,
        password: result.password,
      );
      if (groupId != null) {
        await _handleGroupChanged(groupId, displayName: 'IRC: ${result.channel}');
        final appL10n = AppLocalizations.of(context)!;
        _showSnackBar(appL10n.ircChannelAdded(result.channel));
      } else {
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

  Future<void> _showMessageReceiversDialog(BuildContext context, String msgID, String groupID) async {
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
        title: Text(AppLocalizations.of(context)!.messageReceivers(receivers.length.toString())),
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
                    nickname.isNotEmpty ? nickname.substring(0, 1).toUpperCase() : '?',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                title: Text(
                  nickname.isNotEmpty ? nickname : userId,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
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
            onPressed: () => Navigator.of(ctx).pop(),
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

/// Top section of the mobile drawer — avatar + nickname + connection status.
///
/// Mirrors the desktop sidebar's `_UserAvatar` pattern but laid out
/// vertically with `AppSpacing.lg` padding for a touch-first feel.
class _MobileDrawerHeader extends StatefulWidget {
  const _MobileDrawerHeader({
    required this.service,
    required this.connectionStatusStream,
  });

  final FfiChatService service;
  final Stream<bool> connectionStatusStream;

  @override
  State<_MobileDrawerHeader> createState() => _MobileDrawerHeaderState();
}

class _MobileDrawerHeaderState extends State<_MobileDrawerHeader> {
  String? _nickname;
  String? _avatarPath;
  int _avatarVersion = 0;
  StreamSubscription<String>? _avatarUpdatedSub;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _avatarUpdatedSub = widget.service.avatarUpdated.listen((updatedUserId) {
      final selfId = widget.service.selfId;
      if (selfId.isEmpty) return;
      final normalizedSelf =
          selfId.length > 64 ? selfId.substring(0, 64) : selfId;
      final normalizedUpdated = updatedUserId.length > 64
          ? updatedUserId.substring(0, 64)
          : updatedUserId;
      if (updatedUserId == selfId ||
          updatedUserId == normalizedSelf ||
          normalizedUpdated == normalizedSelf) {
        _loadProfile();
      }
    });
  }

  @override
  void dispose() {
    _avatarUpdatedSub?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final nick = await Prefs.getNickname();
    final avatar = await Prefs.getAvatarPath();
    if (mounted) {
      setState(() {
        _nickname = nick;
        _avatarPath = avatar;
        _avatarVersion++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: StreamBuilder<bool>(
        stream: widget.connectionStatusStream,
        initialData: widget.service.isConnected,
        builder: (context, snapshot) {
          final isConnected = snapshot.data ?? widget.service.isConnected;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: scheme.primary,
                    child: _avatarPath != null &&
                            _avatarPath!.isNotEmpty &&
                            File(_avatarPath!).existsSync()
                        ? ClipOval(
                            child: Image.file(
                              File(_avatarPath!),
                              key: ValueKey(
                                  'mobile-drawer-avatar-${_avatarPath!}-$_avatarVersion'),
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            ),
                          )
                        : ClipOval(
                            child: Image.asset(
                              'images/default_user_icon.png',
                              package: 'tencent_cloud_chat_common',
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            ),
                          ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isConnected
                            ? AppThemeConfig.successColor
                            : scheme.onSurfaceVariant,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.surface,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              AppSpacing.verticalMd,
              if (_nickname != null && _nickname!.isNotEmpty)
                Text(
                  _nickname!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              AppSpacing.verticalXs,
              Text(
                isConnected
                    ? (AppLocalizations.of(context)?.statusOnline ?? 'Online')
                    : (AppLocalizations.of(context)?.statusOffline ?? 'Offline'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isConnected
                      ? AppThemeConfig.successColor
                      : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Mobile drawer nav row — 56px tap target, icon-left + label-right,
/// 3px primary accent on the left edge when selected (mirrors the
/// desktop sidebar's selection treatment for visual continuity).
class _MobileDrawerItem extends StatelessWidget {
  const _MobileDrawerItem({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
    this.showUnreadBadge = false,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;
  final bool showUnreadBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.10)
        : Colors.transparent;
    return _HomePressableScale(
      pressedScale: 0.98,
      child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              left: BorderSide(
                color: selected ? scheme.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(selected ? selectedIcon : icon, size: 24, color: color),
                  if (showUnreadBadge)
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
                                ? '99+'
                                : '$totalUnreadCount';
                            final isLargeText = displayText.length > 2;
                            return UnconstrainedBox(
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 16),
                                height: 16,
                                padding: EdgeInsets.symmetric(
                                    horizontal: isLargeText ? 5 : 4),
                                decoration: BoxDecoration(
                                  color: AppThemeConfig.errorColor,
                                  borderRadius: BorderRadius.circular(
                                      AppThemeConfig.badgeBorderRadius),
                                ),
                                child: Center(
                                  child: Text(
                                    displayText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.onError,
                                      fontWeight: FontWeight.w600,
                                      height: 1.0,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                    textAlign: TextAlign.center,
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
              AppSpacing.horizontalLg,
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Subtle scale-down on press for tappable rows in home_page.
/// Scales to [pressedScale] (default 0.97) on pointer-down and back to 1.0
/// over 120ms. Respects `MediaQuery.disableAnimations`.
class _HomePressableScale extends StatefulWidget {
  const _HomePressableScale({
    required this.child,
    this.pressedScale = 0.97,
    this.duration = const Duration(milliseconds: 120),
  });

  final Widget child;
  final double pressedScale;
  final Duration duration;

  @override
  State<_HomePressableScale> createState() => _HomePressableScaleState();
}

class _HomePressableScaleState extends State<_HomePressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
