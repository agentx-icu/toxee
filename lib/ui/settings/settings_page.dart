import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/tencent_cloud_chat_intl.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import '../../util/app_paths.dart';
import '../../util/ffi_chat_service_account_key.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'dart:async';
import 'dart:math';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';
import '../../util/locale_controller.dart';
import '../../util/prefs.dart';
import '../widgets/app_page_route.dart';
import '../widgets/bottom_sheet_handle.dart';
import '../widgets/safe_dialog_pop.dart';
import '../widgets/section_header.dart';
import '../widgets/stagger_list_item.dart';
import '../testing/ui_keys.dart';
import '_hoverable_settings_row.dart';
import '../../i18n/app_localizations.dart';
import '../../util/account_export_service.dart';
import '../../util/account_switcher.dart';
import '../../util/feature_flags.dart';

import '../../util/account_service.dart';
import '../../util/tox_utils.dart';
import '../../util/logger.dart';
import '../../util/responsive_layout.dart';
import '../login_page.dart';
import 'bootstrap_settings_section.dart';
import 'global_settings_section.dart';
import 'sidebar.dart' show showSelfProfile;
import '../pairing/pairing_host_page.dart';
import '../testing/l3_debug_tools.dart';

part 'settings_page_widgets.dart';
part 'settings_page_build.dart';

/// Test seam for the logout teardown step. Production binds this to
/// [AccountService.teardownCurrentSession]; widget tests inject a recording
/// stub so `_logout` can be driven to completion (confirm → teardown →
/// navigate) without disposing a real FFI session. Mirrors the
/// `teardownSession` seam on `LoginPage` (login_page.dart).
typedef SettingsTeardownSessionFn =
    Future<void> Function({
      required FfiChatService service,
      bool reEncryptProfile,
    });

/// Test seam for the account-switch step. Production binds this to
/// [AccountSwitcher.switchAccount]; widget tests inject a recording stub so
/// the confirm/cancel dialog can be driven and the switch handler observed
/// (fired after Confirm, NOT fired after Cancel) without booting the target
/// account's FFI session.
typedef SettingsSwitchAccountFn =
    Future<void> Function({
      required BuildContext context,
      required String targetToxId,
      FfiChatService? currentService,
    });

/// English words shown for confirmation when deleting account without password.
const _kDeleteConfirmWords = <String>[
  'delete',
  'confirm',
  'remove',
  'account',
  'permanent',
  'cancel',
  'proceed',
  'warning',
  'caution',
  'irreversible',
  'data',
  'erase',
  'type',
  'word',
  'verify',
  'submit',
  'final',
  'accept',
  'continue',
];

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.service,
    required this.connectionStatusStream,
    required this.autoAcceptFriends,
    required this.onAutoAcceptFriendsChanged,
    required this.autoAcceptGroupInvites,
    required this.onAutoAcceptGroupInvitesChanged,
    this.teardownSession,
    this.switchAccountFn,
  });
  final FfiChatService service;
  final Stream<bool>
  connectionStatusStream; // Kept for API compatibility but not used
  final bool autoAcceptFriends;
  final ValueChanged<bool> onAutoAcceptFriendsChanged;
  final bool autoAcceptGroupInvites;
  final ValueChanged<bool> onAutoAcceptGroupInvitesChanged;

  /// Test seam for logout teardown; defaults to
  /// [AccountService.teardownCurrentSession]. See [SettingsTeardownSessionFn].
  final SettingsTeardownSessionFn? teardownSession;

  /// Test seam for account switching; defaults to
  /// [AccountSwitcher.switchAccount]. See [SettingsSwitchAccountFn].
  final SettingsSwitchAccountFn? switchAccountFn;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _autoLogin = true; // Auto-login setting
  String? _currentNickname; // Current user nickname
  String? _avatarPath; // Current user avatar path
  StreamSubscription<String>? _avatarUpdatedSubscription;

  // Account management
  List<Map<String, String>> _accountList = [];
  String?
  _currentAccountToxId; // Real Tox ID from Prefs (service.selfId is UIKit placeholder)
  bool _accountListExpanded = false;
  static const int _accountListPreviewCount = 3;
  Timer? _lastLoginTimeUpdateTimer;

  // Resolved test seams: the injected override, else the production binding.
  late final SettingsTeardownSessionFn _teardownSession;
  late final SettingsSwitchAccountFn _switchAccountFn;

  @override
  void initState() {
    super.initState();
    _teardownSession =
        widget.teardownSession ??
        ({required FfiChatService service, bool reEncryptProfile = true}) =>
            AccountService.teardownCurrentSession(
              service: service,
              reEncryptProfile: reEncryptProfile,
            );
    _switchAccountFn =
        widget.switchAccountFn ??
        ({
          required BuildContext context,
          required String targetToxId,
          FfiChatService? currentService,
        }) => AccountSwitcher.switchAccount(
          context: context,
          targetToxId: targetToxId,
          currentService: currentService,
        );
    _loadAutoLogin();
    _loadCurrentNickname();
    _loadAvatarPath();
    _loadAccountList();
    _startLastLoginTimeUpdateTimer();
    _avatarUpdatedSubscription = widget.service.avatarUpdated.listen((
      updatedUserId,
    ) {
      final selfId = widget.service.selfId;
      if (selfId.isEmpty) return;
      final normalizedSelf = selfId.length > 64
          ? selfId.substring(0, 64)
          : selfId;
      final normalizedUpdated = updatedUserId.length > 64
          ? updatedUserId.substring(0, 64)
          : updatedUserId;
      if (updatedUserId == selfId ||
          updatedUserId == normalizedSelf ||
          normalizedUpdated == normalizedSelf) {
        if (_avatarPath != null && _avatarPath!.isNotEmpty) {
          FileImage(File(_avatarPath!)).evict();
        }
        _loadAvatarPath();
      }
    });
  }

  @override
  void dispose() {
    _avatarUpdatedSubscription?.cancel();
    _lastLoginTimeUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAvatarPath() async {
    final avatar = await Prefs.getAvatarPath();
    if (mounted) {
      setState(() {
        _avatarPath = avatar;
      });
    }
  }

  Future<void> _loadAutoLogin() async {
    final toxId =
        _currentAccountToxId ??
        await Prefs.getCurrentAccountToxId() ??
        widget.service.accountKey;
    if (toxId.isNotEmpty) {
      final enabled = await Prefs.getAutoLogin(toxId);
      if (mounted) {
        setState(() {
          _autoLogin = enabled;
        });
      }
    }
  }

  Future<void> _setAutoLogin(bool value) async {
    final toxId =
        _currentAccountToxId ??
        await Prefs.getCurrentAccountToxId() ??
        widget.service.accountKey;
    if (toxId.isNotEmpty) {
      await Prefs.setAutoLogin(value, toxId);
      if (mounted) {
        setState(() {
          _autoLogin = value;
        });
      }
    }
  }

  Future<void> _loadCurrentNickname() async {
    final nick = await Prefs.getNickname();
    if (mounted) {
      setState(() {
        _currentNickname = nick;
      });
    }
  }

  Future<void> _loadAccountList() async {
    final accounts = await Prefs.getAccountList();
    final currentToxId = await Prefs.getCurrentAccountToxId();
    if (mounted) {
      setState(() {
        _currentAccountToxId = currentToxId;
        _accountList = List<Map<String, String>>.from(accounts)
          ..sort((a, b) {
            final currentId = _currentAccountToxId ?? widget.service.accountKey;
            final aIsCurrent = compareToxIds(a['toxId'] ?? '', currentId);
            final bIsCurrent = compareToxIds(b['toxId'] ?? '', currentId);
            if (aIsCurrent) return -1;
            if (bIsCurrent) return 1;
            return 0;
          });
      });
    }
  }

  void _startLastLoginTimeUpdateTimer() {
    // Update current account's lastLoginTime every 5 minutes
    _lastLoginTimeUpdateTimer?.cancel();
    _lastLoginTimeUpdateTimer = Timer.periodic(const Duration(minutes: 5), (
      timer,
    ) async {
      final toxId = widget.service.accountKey;
      if (toxId.isNotEmpty && mounted) {
        final account = await Prefs.getAccountByToxId(toxId);
        if (account != null) {
          await Prefs.addAccount(
            toxId: toxId,
            nickname: account['nickname'],
            statusMessage: account['statusMessage'],
          );
          await _loadAccountList();
        }
      }
    });
  }

  String _formatLastLoginTime(String? isoString, BuildContext context) {
    if (isoString == null || isoString.isEmpty)
      return AppLocalizations.of(context)!.never;
    try {
      final dateTime = DateTime.parse(isoString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 0) {
        return AppLocalizations.of(
          context,
        )!.daysAgo(difference.inDays, difference.inDays > 1 ? 's' : '');
      } else if (difference.inHours > 0) {
        return AppLocalizations.of(
          context,
        )!.hoursAgo(difference.inHours, difference.inHours > 1 ? 's' : '');
      } else if (difference.inMinutes > 0) {
        return AppLocalizations.of(context)!.minutesAgo(
          difference.inMinutes,
          difference.inMinutes > 1 ? 's' : '',
        );
      } else {
        return AppLocalizations.of(context)!.justNow;
      }
    } catch (e) {
      return AppLocalizations.of(context)!.unknown;
    }
  }

  Future<void> _switchAccount(Map<String, String> account) async {
    final toxId = account['toxId'];
    if (toxId == null || toxId.isEmpty) return;

    final currentToxId = _currentAccountToxId ?? widget.service.accountKey;
    if (compareToxIds(toxId, currentToxId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.thisAccountIsAlreadyLoggedIn,
            ),
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.switchAccount),
        content: Text(
          AppLocalizations.of(
            context,
          )!.switchAccountConfirm(account['nickname'] ?? ''),
        ),
        actions: [
          TextButton(
            key: UiKeys.settingsAccountSwitchCancelButton,
            onPressed: () => popDialogIfCurrent(context, false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            key: UiKeys.settingsAccountSwitchConfirmButton,
            onPressed: () => popDialogIfCurrent(context, true),
            child: Text(AppLocalizations.of(context)!.switchAccount),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _switchAccountFn(
          context: context,
          targetToxId: toxId,
          currentService: widget.service,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(
                  context,
                )!.failedToSwitchAccount(e.toString()),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  /// Show export format chooser, then export.
  ///
  /// On mobile we keep the bottom sheet (thumb-friendly, standard mobile
  /// pattern). On tablet/desktop we present the same options as a centered
  /// dialog so the chooser doesn't slide up off-canvas on wide screens.
  Future<void> _showExportOptions() async {
    Widget buildOptions(BuildContext ctx, {required bool isSheet}) {
      final children = <Widget>[
        if (isSheet) const BottomSheetHandle(),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            AppLocalizations.of(ctx)!.exportAccount,
            style: Theme.of(ctx).textTheme.titleMedium,
          ),
        ),
        const Divider(height: 1),
        ListTile(
          key: UiKeys.settingsExportProfileToxOption,
          leading: const Icon(Icons.description),
          title: Text(AppLocalizations.of(ctx)!.exportOptionProfileTox),
          subtitle: Text(
            AppLocalizations.of(ctx)!.exportOptionProfileToxSubtitle,
          ),
          onTap: () => popDialogIfCurrent(ctx, 'tox'),
        ),
        ListTile(
          key: UiKeys.settingsExportFullBackupOption,
          leading: const Icon(Icons.archive),
          title: Text(AppLocalizations.of(ctx)!.exportOptionFullBackup),
          subtitle: Text(
            AppLocalizations.of(ctx)!.exportOptionFullBackupSubtitle,
          ),
          onTap: () => popDialogIfCurrent(ctx, 'zip'),
        ),
        const SizedBox(height: AppSpacing.sm),
      ];
      final content = Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
      return isSheet ? SafeArea(top: false, child: content) : content;
    }

    String? choice;
    if (ResponsiveLayout.isMobile(context)) {
      choice = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppThemeConfig.formCardBorderRadius),
          ),
        ),
        builder: (ctx) => buildOptions(ctx, isSheet: true),
      );
    } else {
      choice = await showDialog<String>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              AppThemeConfig.cardBorderRadius,
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: buildOptions(ctx, isSheet: false),
          ),
        ),
      );
    }

    if (choice == 'tox') {
      await _exportAccount();
    } else if (choice == 'zip') {
      await _exportFullBackup();
    }
  }

  /// Export a full .zip backup including profile, chat history, and metadata.
  Future<void> _exportFullBackup() async {
    final toxId = widget.service.accountKey;
    if (toxId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.noAccountToExport),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    try {
      String? outputPath;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final account = await Prefs.getAccountByToxId(toxId);
        final nickname = account?['nickname'] ?? 'account';
        final toxIdPrefix = toxId.length >= 8 ? toxId.substring(0, 8) : toxId;
        final safeNickname = nickname.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
        final defaultFileName = '${safeNickname}_${toxIdPrefix}_backup.zip';

        outputPath = await runL3AwareExportSaveFilePicker(
          dialogTitle: AppLocalizations.of(context)!.exportAccount,
          fileName: defaultFileName,
          saveFile: (dialogTitle, fileName) => FilePicker.platform.saveFile(
            dialogTitle: dialogTitle,
            fileName: fileName,
          ),
        );
      }

      if (outputPath == null) return;

      final filePath = await AccountExportService.exportFullBackup(
        toxId: toxId,
        filePath: outputPath,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              )!.accountExportedSuccessfully(filePath),
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.logError('Full backup export error', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.failedToExportAccount(e.toString()),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _exportAccount() async {
    final toxId = widget.service.accountKey;
    if (toxId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.noAccountToExport),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    // Check if account has password
    final hasPassword = await Prefs.hasAccountPassword(toxId);
    String? password;

    if (hasPassword) {
      password = await _showConfirmPasswordDialog(
        AppLocalizations.of(context)!.enterPasswordToExport,
      );
      if (password == null) return;

      final isValid = await Prefs.verifyAccountPassword(toxId, password);
      if (!isValid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.invalidPassword),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }
    }

    try {
      // Show file picker to select save location
      String? outputPath;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // Generate default filename
        final account = await Prefs.getAccountByToxId(toxId);
        final nickname = account?['nickname'] ?? 'account';
        final toxIdPrefix = toxId.length >= 8 ? toxId.substring(0, 8) : toxId;
        final safeNickname = nickname.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
        final defaultFileName = '${safeNickname}_$toxIdPrefix.tox';

        outputPath = await runL3AwareExportSaveFilePicker(
          dialogTitle: AppLocalizations.of(context)!.exportAccount,
          fileName: defaultFileName,
          saveFile: (dialogTitle, fileName) => FilePicker.platform.saveFile(
            dialogTitle: dialogTitle,
            fileName: fileName,
          ),
        );
      }

      if (outputPath == null) return;

      final filePath = await AccountExportService.exportAccountData(
        toxId: toxId,
        password: password,
        filePath: outputPath,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              )!.accountExportedSuccessfully(filePath),
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e, stackTrace) {
      // Log detailed error for debugging
      AppLogger.logError('Export account error', e, stackTrace);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.failedToExportAccount(e.toString()),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _importAccount() async {
    try {
      // Show file picker for .tox and .zip files
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tox', 'zip'],
      );

      if (result == null || result.files.single.path == null) return;

      final filePath = result.files.single.path!;
      final isZip = filePath.toLowerCase().endsWith('.zip');

      // Check if file is encrypted by reading first bytes and checking magic number
      String? password;
      try {
        final file = File(filePath);
        final fileData = await file.readAsBytes();
        if (fileData.length >= 80) {
          // Import will check encryption, but we need to prompt for password first if encrypted
          // For now, we'll let importAccountData/importFullBackup handle the encryption check
          // If it throws an error about password, we'll catch and prompt
        }
      } catch (e) {
        AppLogger.warn(
          '[SettingsPage] pre-import file size probe failed (import will retry and surface the real error): $e',
        );
      }

      // Import account data (will check encryption and prompt for password if needed)
      Map<String, dynamic> accountData;

      if (isZip) {
        // ZIP: check account collision before any disk writes (importFullBackup writes profile/history/avatars/prefs).
        final metadata = await AccountExportService.readFullBackupMetadata(
          filePath,
        );
        final metaToxId = metadata['toxId']!;
        final existingAccount = await Prefs.getAccountByToxId(metaToxId);
        final profileDir = await AppPaths.getProfileDirectoryForToxId(
          metaToxId,
        );
        final profileFilePath = AppPaths.profileFileInDirectory(profileDir);
        if (existingAccount != null || await File(profileFilePath).exists()) {
          if (mounted) {
            await showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(AppLocalizations.of(context)!.importAccount),
                content: Text(
                  AppLocalizations.of(context)!.accountAlreadyExists,
                ),
                actions: [
                  TextButton(
                    onPressed: () => popDialogIfCurrent(context),
                    child: Text(AppLocalizations.of(context)!.ok),
                  ),
                ],
              ),
            );
          }
          return;
        }
        try {
          accountData = await AccountExportService.importFullBackup(
            filePath: filePath,
            password: password,
          );
        } catch (e) {
          if (e.toString().contains('Password required') ||
              e.toString().contains('password')) {
            if (mounted) {
              password = await _showConfirmPasswordDialog(
                AppLocalizations.of(context)!.enterPasswordToImport,
              );
              if (password == null) return;
              accountData = await AccountExportService.importFullBackup(
                filePath: filePath,
                password: password,
              );
            } else {
              rethrow;
            }
          } else {
            rethrow;
          }
        }
      } else {
        try {
          accountData = await AccountExportService.importAccountData(
            filePath: filePath,
            password: password,
          );
        } catch (e) {
          if (e.toString().contains('Password required') ||
              e.toString().contains('password')) {
            if (mounted) {
              password = await _showConfirmPasswordDialog(
                AppLocalizations.of(context)!.enterPasswordToImport,
              );
              if (password == null) return;
              accountData = await AccountExportService.importAccountData(
                filePath: filePath,
                password: password,
              );
            } else {
              rethrow;
            }
          } else {
            rethrow;
          }
        }
      }

      final toxId = accountData['toxId'] as String;
      final toxProfile = accountData['toxProfile'] as Uint8List?;
      final importedNickname = (accountData['nickname'] as String?) ?? '';
      final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
      final profileFilePath = AppPaths.profileFileInDirectory(profileDir);

      // Collision check for .tox path only (ZIP already checked above)
      if (!isZip) {
        final existingAccount = await Prefs.getAccountByToxId(toxId);
        if (existingAccount != null || await File(profileFilePath).exists()) {
          if (mounted) {
            await showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(AppLocalizations.of(context)!.importAccount),
                content: Text(
                  AppLocalizations.of(context)!.accountAlreadyExists,
                ),
                actions: [
                  TextButton(
                    onPressed: () => popDialogIfCurrent(context),
                    child: Text(AppLocalizations.of(context)!.ok),
                  ),
                ],
              ),
            );
          }
          return;
        }
      }

      // For .tox imports, write profile; .zip imports already wrote it in importFullBackup
      if (!isZip && toxProfile != null) {
        final parentDir = Directory(profileDir);
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }
        final toxProfileFile = File(profileFilePath);
        await toxProfileFile.writeAsBytes(toxProfile);
      }

      // Add/update account (.zip may contain nickname, .tox does not)
      final displayNickname = importedNickname.isNotEmpty
          ? importedNickname
          : AppLocalizations.of(context)!.importedAccount;
      await Prefs.addAccount(
        toxId: toxId,
        nickname: displayNickname,
        statusMessage: '', // .tox files don't contain status message
        autoLogin: false,
        autoAcceptFriends: false,
        notificationSoundEnabled: true,
      );

      // If password was used for import, set it for the account
      if (password != null && password.isNotEmpty) {
        await Prefs.setAccountPassword(toxId, password);
      }

      // Reload account list
      await _loadAccountList();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.accountImportedSuccessfully,
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.logError(
        '[SettingsPage] Import account failed: $e',
        e,
        stackTrace,
      );
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.importAccount),
            content: Text(
              AppLocalizations.of(context)!.failedToImportAccount(e.toString()),
            ),
            actions: [
              TextButton(
                onPressed: () => popDialogIfCurrent(context),
                child: Text(AppLocalizations.of(context)!.ok),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _setAccountPassword() async {
    final toxId = widget.service.accountKey;
    if (toxId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.noAccountSelected),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    // Read the has-password state under the canonical Tox ID (getSelfToxId),
    // matching the write path below — accountKey can be a placeholder when the
    // FFI hasn't resolved the address, which would mis-title the dialog.
    final hasPassword = await Prefs.hasAccountPassword(
      widget.service.getSelfToxId() ?? toxId,
    );

    // Show password input dialog
    final password = await _showSetPasswordDialog(hasPassword);
    if (password == null) return;

    try {
      if (password.isEmpty) {
        // Remove password — routes through AccountService so the in-memory
        // session password is cleared too (else logout re-encrypts the
        // now-unprotected profile → silent next-launch failure).
        final ok = await AccountService.removeAccountPassword(widget.service);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ok
                    ? AppLocalizations.of(context)!.passwordRemoved
                    : AppLocalizations.of(
                        context,
                      )!.failedToSetPassword('could not remove password'),
              ),
              backgroundColor: ok
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
          );
        }
      } else {
        // Set/change password — routes through AccountService so the in-memory
        // session password is updated too (else logout encrypts with the stale
        // login password, corrupting the profile vs the new verifier). A false
        // return means nothing was persisted — must NOT report success.
        final ok = await AccountService.setAccountPassword(
          widget.service,
          password,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ok
                    ? AppLocalizations.of(context)!.passwordSetSuccessfully
                    : AppLocalizations.of(
                        context,
                      )!.failedToSetPassword('could not save password'),
              ),
              backgroundColor: ok
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.failedToSetPassword(e.toString()),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Password + confirm password dialog for export/import; returns password if both match.
  Future<String?> _showConfirmPasswordDialog(String title) async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passwordController,
              obscureText: true,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.password,
                hintText: AppLocalizations.of(context)!.ircChannelPasswordHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    AppThemeConfig.inputBorderRadius,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              obscureText: true,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.confirmPassword,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    AppThemeConfig.inputBorderRadius,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => popDialogIfCurrent<String>(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              final pwd = passwordController.text;
              if (pwd != confirmController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(context)!.passwordsDoNotMatch,
                    ),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
                return;
              }
              popDialogIfCurrent(context, pwd);
            },
            child: Text(AppLocalizations.of(context)!.ok),
          ),
        ],
      ),
    );
  }

  Future<String?> _showSetPasswordDialog(bool hasPassword) async {
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          hasPassword
              ? AppLocalizations.of(context)!.changePassword
              : AppLocalizations.of(context)!.setPassword,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              // Stable automation anchor for the set/change-password "new
              // password" field (the dialog opened by _setAccountPassword).
              key: const Key('settings_set_password_new_field'),
              controller: passwordController,
              obscureText: true,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.newPassword,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    AppThemeConfig.inputBorderRadius,
                  ),
                ),
                hintText: AppLocalizations.of(
                  context,
                )!.leaveEmptyToRemovePassword,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              // Stable automation anchor for the set/change-password "confirm
              // password" field.
              key: const Key('settings_set_password_confirm_field'),
              controller: confirmPasswordController,
              obscureText: true,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.confirmPassword,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    AppThemeConfig.inputBorderRadius,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            // Stable automation anchor for the set-password dialog Cancel.
            key: const Key('settings_set_password_cancel_button'),
            onPressed: () => popDialogIfCurrent<String>(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            // Stable automation anchor for the set-password dialog Save/OK.
            key: const Key('settings_set_password_save_button'),
            onPressed: () {
              final password = passwordController.text;
              final confirm = confirmPasswordController.text;

              if (password != confirm) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(context)!.passwordsDoNotMatch,
                    ),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
                return;
              }

              popDialogIfCurrent(context, password);
            },
            child: Text(AppLocalizations.of(context)!.ok),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.logOut),
        content: Text(AppLocalizations.of(context)!.logOutConfirm),
        actions: [
          TextButton(
            key: UiKeys.settingsLogoutCancelButton,
            onPressed: () => popDialogIfCurrent(context, false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            key: UiKeys.settingsLogoutConfirmButton,
            onPressed: () => popDialogIfCurrent(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(AppLocalizations.of(context)!.logOut),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      unawaited(HapticFeedback.heavyImpact());
      await _teardownSession(service: widget.service);
      await Prefs.setCurrentAccountToxId(null);

      if (!mounted) return;
      await Navigator.of(context).pushAndRemoveUntil(
        AppPageRoute<void>(page: const LoginPage()),
        (route) => false,
      );
    }
  }

  /// Used by settings_page_build.dart extension to call setState (avoids invalid_use_of_protected_member).
  void _settingsSetState(VoidCallback fn) {
    setState(fn);
  }

  /// Launch the QR pairing host page for the currently active account.
  /// Gated on [FeatureFlags.enableQRPairing].
  Future<void> _startPairingAsHost() async {
    final toxId = widget.service.accountKey;
    if (toxId.isEmpty) return;
    await Navigator.of(
      context,
    ).push<void>(AppPageRoute<void>(page: PairingHostPage(toxId: toxId)));
  }

  Future<void> _openMobileProfile() async {
    await showSelfProfile(
      context,
      widget.service,
      widget.connectionStatusStream,
      nickName: _currentNickname,
      onProfileSaved: (_, __) async {
        await _loadCurrentNickname();
        await _loadAccountList();
      },
      onAvatarChanged: (_) => _loadAvatarPath(),
    );
    if (!mounted) return;
    await _loadCurrentNickname();
    await _loadAvatarPath();
  }

  void _pushMobileSettingsSection(String title, Widget child) {
    Navigator.of(context).push<void>(
      AppPageRoute<void>(
        page: Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [child],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileSettingsIndex(BuildContext context, dynamic colorTheme) {
    final appL10n = AppLocalizations.of(context)!;
    final tL10n = TencentCloudChatLocalizations.of(context);
    final outlineVariant = Theme.of(context).colorScheme.outlineVariant;

    Widget sectionTile({
      required IconData icon,
      required String title,
      String? subtitle,
      required VoidCallback onTap,
    }) {
      return Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: outlineVariant),
          borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
        ),
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
    }

    Widget avatar() {
      final nickname = _currentNickname ?? '';
      return CircleAvatar(
        radius: 28,
        backgroundColor: colorTheme.primaryColor,
        child:
            _avatarPath != null &&
                _avatarPath!.isNotEmpty &&
                File(_avatarPath!).existsSync()
            ? ClipOval(
                child: Image.file(
                  File(_avatarPath!),
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              )
            : Text(
                (nickname.isNotEmpty ? nickname[0] : 'U').toUpperCase(),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorTheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
      );
    }

    return ListView(
      key: UiKeys.settingsScrollView,
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: outlineVariant),
            borderRadius: BorderRadius.circular(
              AppThemeConfig.cardBorderRadius,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(AppSpacing.md),
            leading: avatar(),
            title: Text(_currentNickname ?? appL10n.profile),
            subtitle: Text(appL10n.profile),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _openMobileProfile,
          ),
        ),
        AppSpacing.verticalMd,
        sectionTile(
          icon: Icons.badge_outlined,
          title: appL10n.accountInfo,
          onTap: () => _pushMobileSettingsSection(
            appL10n.accountInfo,
            _buildMobileAccountInfoCard(context, colorTheme),
          ),
        ),
        sectionTile(
          icon: Icons.manage_accounts_outlined,
          title: appL10n.accountManagement,
          onTap: () => _pushMobileSettingsSection(
            appL10n.accountManagement,
            _buildMobileAccountManagementCard(context, colorTheme),
          ),
        ),
        sectionTile(
          icon: Icons.palette_outlined,
          title: tL10n?.appearance ?? appL10n.appearance,
          onTap: () => _pushMobileSettingsSection(
            tL10n?.appearance ?? appL10n.appearance,
            GlobalSettingsSection(
              colorTheme: colorTheme,
              toxId: widget.service.accountKey,
              onDownloadsConfigChanged: () {
                AppLogger.debug('[Settings] downloads config changed');
              },
            ),
          ),
        ),
        sectionTile(
          icon: Icons.hub_outlined,
          title: appL10n.bootstrapNodes,
          onTap: () => _pushMobileSettingsSection(
            appL10n.bootstrapNodes,
            BootstrapSettingsSection(
              service: widget.service,
              colorTheme: colorTheme,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileAccountInfoCard(BuildContext context, dynamic colorTheme) {
    final outlineVariant = Theme.of(context).colorScheme.outlineVariant;
    final toxId = _currentAccountToxId ?? widget.service.accountKey;
    Future<void> copyToxId() async {
      await Clipboard.setData(ClipboardData(text: toxId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.idCopiedToClipboard),
        ),
      );
    }

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: outlineVariant),
        borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: AppLocalizations.of(context)!.accountInfo),
            AppSpacing.verticalMd,
            Text(
              AppLocalizations.of(context)!.userId,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorTheme.secondaryTextColor,
              ),
            ),
            AppSpacing.verticalXs,
            GestureDetector(
              onLongPress: copyToxId,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: SelectableText(
                  toxId,
                  key: UiKeys.settingsCopyToxIdButton,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            AppSpacing.verticalMd,
            _HoverableSettingsRow(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.autoLogin,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        AppSpacing.verticalXs,
                        Text(
                          AppLocalizations.of(context)!.autoLoginDesc,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorTheme.secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    key: UiKeys.settingsAutoLoginSwitch,
                    value: _autoLogin,
                    onChanged: (value) => _setAutoLogin(value),
                  ),
                ],
              ),
            ),
            const Divider(height: AppSpacing.xl),
            _HoverableSettingsRow(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(
                            context,
                          )!.autoAcceptFriendRequests,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        AppSpacing.verticalXs,
                        Text(
                          AppLocalizations.of(
                            context,
                          )!.autoAcceptFriendRequestsDesc,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorTheme.secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: widget.autoAcceptFriends,
                    onChanged: widget.onAutoAcceptFriendsChanged,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileAccountManagementCard(
    BuildContext context,
    dynamic colorTheme,
  ) {
    final outlineVariant = Theme.of(context).colorScheme.outlineVariant;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: outlineVariant),
        borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: AppLocalizations.of(context)!.accountManagement,
            ),
            AppSpacing.verticalMd,
            ..._accountList.map((account) {
              final accountToxId = account['toxId'] ?? '';
              final currentId =
                  _currentAccountToxId ?? widget.service.accountKey;
              final isCurrentAccount = compareToxIds(accountToxId, currentId);
              return _AccountCardItem(
                account: account,
                isCurrentAccount: isCurrentAccount,
                colorTheme: colorTheme,
                onSwitch: () => _switchAccount(account),
                currentChip: Chip(
                  label: Text(AppLocalizations.of(context)!.current),
                  backgroundColor: colorTheme.primaryColor,
                  labelStyle: TextStyle(color: colorTheme.onPrimary),
                ),
                subtitle: Text(
                  '${AppLocalizations.of(context)!.lastLogin}: ${_formatLastLoginTime(account['lastLoginTime'], context)}',
                ),
              );
            }),
            AppSpacing.verticalMd,
            OutlinedButton.icon(
              icon: const Icon(Icons.download, size: 18),
              label: Text(AppLocalizations.of(context)!.importAccount),
              onPressed: _importAccount,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Sync UIKit locale with app locale after this frame to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        TencentCloudChatIntl().setLocale(AppLocale.locale.value);
      } catch (e) {
        // Per-frame: log at warn so a real failure isn't invisible, but accept
        // that this fires every build. setLocale itself rarely throws.
        AppLogger.warn(
          '[SettingsPage] TencentCloudChatIntl.setLocale failed: $e',
        );
      }
    });
    return ValueListenableBuilder<Locale>(
      valueListenable: AppLocale.locale,
      builder: (context, locale, _) {
        final tL10n = TencentCloudChatLocalizations.of(context);
        if (tL10n == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return TencentCloudChatThemeWidget(
          build: (context, colorTheme, textStyle) => SafeArea(
            child: ResponsiveLayout.isMobile(context)
                ? _buildMobileSettingsIndex(context, colorTheme)
                : ListView(
                    // Stable scroll anchor for real-UI automation (wheel-scroll to the
                    // below-the-fold Global / Bootstrap sections). See
                    // UiKeys.settingsScrollView.
                    key: UiKeys.settingsScrollView,
                    padding: ResponsiveLayout.responsivePadding(context),
                    children: _buildSettingsChildren(context, colorTheme),
                  ),
          ),
        );
      },
    );
  }

  Future<void> _showDeleteAccountConfirmation(BuildContext context) async {
    final toxId = widget.service.accountKey;
    if (toxId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.noAccountSelected),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    final hasPassword = await Prefs.hasAccountPassword(toxId);
    final confirmWord = hasPassword
        ? null
        : _kDeleteConfirmWords[Random().nextInt(_kDeleteConfirmWords.length)];

    if (!mounted) return;
    // The confirm-input controller is owned by [_DeleteAccountDialog]'s State
    // (disposed in its dispose()). Creating it here and disposing it right
    // after this await crashes in debug ("A TextEditingController was used
    // after being disposed"): showDialog completes at pop time, but the
    // dialog's TextField keeps rebuilding through the route's exit transition,
    // so the disposed controller is used one more frame. Shared Dart → mobile
    // covered.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteAccountDialog(
        toxId: toxId,
        hasPassword: hasPassword,
        confirmWord: confirmWord,
      ),
    );

    if (confirmed == true && mounted) {
      unawaited(HapticFeedback.heavyImpact());
      await _deleteAccount(context);
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    // Show loading indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Get current account toxId before clearing state
      final toxId = await Prefs.getCurrentAccountToxId();

      // Comprehensive account deletion via AccountService
      if (toxId != null && toxId.isNotEmpty) {
        await AccountService.deleteAccountCompletely(
          service: widget.service,
          toxId: toxId,
        );
      } else {
        // Fallback: just teardown session
        await AccountService.teardownCurrentSession(
          service: widget.service,
          reEncryptProfile: false,
        );
      }

      // Close loading dialog
      if (!mounted) return;
      Navigator.of(context).pop();

      // Navigate to login page and clear navigation stack
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        AppPageRoute<void>(page: const LoginPage()),
        (route) => false,
      );
    } catch (e) {
      // Close loading dialog
      if (!mounted) return;
      Navigator.of(context).pop();

      // Show error message
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.deleteAccountFailed(e.toString()),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

/// Confirmation body for the destructive "delete account" flow.
///
/// Extracted into a [StatefulWidget] so the confirm-input
/// [TextEditingController] is owned by an element whose lifetime matches the
/// dialog. Disposing the controller in the caller right after `showDialog`
/// returns crashes in debug — the dialog's [TextField] still rebuilds during
/// the route's exit transition (visible in the crash's debugCreator chain as
/// the transition `AnimatedBuilder`), and that frame touches the disposed
/// controller, cascading into `_dependents.isEmpty` / duplicate-GlobalKey
/// teardown errors. Shared Dart → covers mobile.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({
    required this.toxId,
    required this.hasPassword,
    required this.confirmWord,
  });

  final String toxId;
  final bool hasPassword;

  /// Required (non-null) when [hasPassword] is false; null otherwise.
  final String? confirmWord;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final TextEditingController _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _onConfirm() async {
    if (widget.hasPassword) {
      final isValid = await Prefs.verifyAccountPassword(
        widget.toxId,
        _inputController.text,
      );
      if (!isValid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.invalidPassword),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }
    } else {
      final input = _inputController.text.trim().toLowerCase();
      if (input != widget.confirmWord!.toLowerCase()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)!.deleteAccountWrongWord,
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }
    }
    if (!mounted) return;
    popDialogIfCurrent(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.deleteAccount),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context)!.deleteAccountConfirmMessage),
            const SizedBox(height: 16),
            if (widget.hasPassword) ...[
              Text(
                AppLocalizations.of(
                  context,
                )!.deleteAccountEnterPasswordToConfirm,
              ),
              const SizedBox(height: 8),
              TextField(
                key: UiKeys.settingsDeleteAccountConfirmInput,
                controller: _inputController,
                obscureText: true,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.password,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppThemeConfig.inputBorderRadius,
                    ),
                  ),
                ),
              ),
            ] else ...[
              Text(
                AppLocalizations.of(context)!.deleteAccountTypeWordToConfirm,
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(
                  context,
                )!.deleteAccountConfirmWordPrompt(widget.confirmWord!),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              SelectableText(
                widget.confirmWord!,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                // Same key as the password branch — the two branches are
                // mutually exclusive (hasPassword), so exactly one keyed input
                // renders.
                key: UiKeys.settingsDeleteAccountConfirmInput,
                controller: _inputController,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppThemeConfig.inputBorderRadius,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => popDialogIfCurrent(context, false),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        TextButton(
          key: UiKeys.settingsDeleteAccountConfirmButton,
          onPressed: _onConfirm,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(AppLocalizations.of(context)!.delete),
        ),
      ],
    );
  }
}
