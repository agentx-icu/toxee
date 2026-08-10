import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/tencent_cloud_chat_intl.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../util/app_paths.dart';
import '../../util/ffi_chat_service_account_key.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'dart:async';
import 'dart:math';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';
import '../../util/imported_account_rollback.dart';
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
import '../../util/mobile_export_policy.dart';
import '../../util/account_switcher.dart';
import '../../util/feature_flags.dart';

import '../../util/account_service.dart';
import '../../util/tox_utils.dart';
import '../../util/logger.dart';
import '../../util/responsive_layout.dart';
import '../../util/safe_diagnostics.dart';
import '../login_page.dart';
import 'bootstrap_settings_section.dart';
import 'global_settings_section.dart';
import 'sidebar.dart' show showSelfProfile;
import '../pairing/pairing_host_page.dart';
import '../testing/l3_debug_tools.dart';

part 'settings_page_widgets.dart';
part 'settings_page_mobile_widgets.dart';
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

typedef SettingsPickImportFileFn = Future<String?> Function();

typedef SettingsImportAccountDataFn =
    Future<Map<String, dynamic>> Function({
      required String filePath,
      String? password,
    });

typedef EncryptProfileFileFn =
    Future<bool> Function(String profileFilePath, String password);

typedef SettingsAddImportedAccountFn =
    Future<void> Function({
      required String toxId,
      required String nickname,
      required String statusMessage,
      required bool autoLogin,
      required bool autoAcceptFriends,
      required bool notificationSoundEnabled,
    });

typedef SettingsSetImportedAccountPasswordFn =
    Future<bool> Function(String toxId, String password);

Future<String?> _pickSettingsImportFile() async {
  return (await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['tox', 'zip'],
  ))?.files.single.path;
}

Future<void> _addSettingsImportedAccount({
  required String toxId,
  required String nickname,
  required String statusMessage,
  required bool autoLogin,
  required bool autoAcceptFriends,
  required bool notificationSoundEnabled,
}) {
  return Prefs.addAccount(
    toxId: toxId,
    nickname: nickname,
    statusMessage: statusMessage,
    autoLogin: autoLogin,
    autoAcceptFriends: autoAcceptFriends,
    notificationSoundEnabled: notificationSoundEnabled,
  );
}

Future<bool> _encryptSettingsProfileFile(
  String profileFilePath,
  String password,
) async {
  await AccountExportService.encryptProfileFile(profileFilePath, password);
  return true;
}

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
    this.pickImportFileFn,
    this.importAccountDataFn,
    this.encryptProfileFileFn,
    this.addImportedAccountFn,
    this.setImportedAccountPasswordFn,
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

  final SettingsPickImportFileFn? pickImportFileFn;
  final SettingsImportAccountDataFn? importAccountDataFn;
  final EncryptProfileFileFn? encryptProfileFileFn;
  final SettingsAddImportedAccountFn? addImportedAccountFn;
  final SettingsSetImportedAccountPasswordFn? setImportedAccountPasswordFn;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _autoLogin = true; // Auto-login setting
  final ValueNotifier<bool> _autoLoginNotifier = ValueNotifier<bool>(true);
  int _autoLoginGeneration = 0;
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
  late final SettingsPickImportFileFn _pickImportFileFn;
  late final SettingsImportAccountDataFn _importAccountDataFn;
  late final EncryptProfileFileFn _encryptProfileFileFn;
  late final SettingsAddImportedAccountFn _addImportedAccountFn;
  late final SettingsSetImportedAccountPasswordFn _setImportedAccountPasswordFn;
  bool _importInProgress = false;
  bool _accountSwitchInProgress = false;

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
    _pickImportFileFn = widget.pickImportFileFn ?? _pickSettingsImportFile;
    _importAccountDataFn =
        widget.importAccountDataFn ?? AccountExportService.importAccountData;
    _encryptProfileFileFn =
        widget.encryptProfileFileFn ?? _encryptSettingsProfileFile;
    _addImportedAccountFn =
        widget.addImportedAccountFn ?? _addSettingsImportedAccount;
    _setImportedAccountPasswordFn =
        widget.setImportedAccountPasswordFn ?? Prefs.setAccountPassword;
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
    _autoLoginNotifier.dispose();
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
    final generation = _autoLoginGeneration;
    final toxId =
        _currentAccountToxId ??
        await Prefs.getCurrentAccountToxId() ??
        widget.service.accountKey;
    if (toxId.isNotEmpty) {
      final enabled = await Prefs.getAutoLogin(toxId);
      if (mounted && generation == _autoLoginGeneration) {
        setState(() {
          _autoLogin = enabled;
          _autoLoginNotifier.value = enabled;
        });
      }
    }
  }

  Future<void> _setAutoLogin(bool value) async {
    final generation = ++_autoLoginGeneration;
    final toxId =
        _currentAccountToxId ??
        await Prefs.getCurrentAccountToxId() ??
        widget.service.accountKey;
    if (toxId.isNotEmpty) {
      await Prefs.setAutoLogin(value, toxId);
      if (mounted && generation == _autoLoginGeneration) {
        setState(() {
          _autoLogin = value;
          _autoLoginNotifier.value = value;
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

    if (_accountSwitchInProgress) return;
    _accountSwitchInProgress = true;

    try {
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
          SafeDiagnostics.logFailure('[SettingsPage] Account switch failed', e);
          if (mounted) {
            final l10n = AppLocalizations.of(context)!;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  e is InvalidAccountSwitchPasswordException
                      ? l10n.invalidPassword
                      : l10n.failedToSwitchAccount(
                          SafeDiagnostics.describeError(e),
                        ),
                ),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        }
      }
    } finally {
      _accountSwitchInProgress = false;
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

  void _showAccountExportOutcome({
    required String exportedPath,
    MobileExportSaveResult? mobileSaveResult,
  }) {
    if (!mounted) return;
    final cancelled =
        mobileSaveResult?.disposition == MobileExportSaveDisposition.cancelled;
    final message = cancelled
        ? AppLocalizations.of(context)!.importCancelled
        : AppLocalizations.of(
            context,
          )!.accountExportedSuccessfully(exportedPath);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: cancelled
            ? null
            : Theme.of(context).colorScheme.primary,
      ),
    );
  }

  /// Export a full .zip backup including profile, chat history, and metadata.
  Future<void> _exportFullBackup() async {
    final l10n = AppLocalizations.of(context)!;
    final toxId = widget.service.accountKey;
    if (toxId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.noAccountToExport),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    try {
      final exportPassword = await _showConfirmPasswordDialog(
        l10n.enterPasswordToExport,
      );
      if (exportPassword == null) return;
      if (exportPassword.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.invalidPassword),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }

      String? outputPath;
      final isDesktopPlatform = isDesktopExportPlatform();
      final defaultFileName = buildFullBackupExportFileName();
      if (isDesktopPlatform) {
        outputPath = await runL3AwareExportSaveFilePicker(
          dialogTitle: l10n.exportAccount,
          fileName: defaultFileName,
          saveFile: (dialogTitle, fileName) => FilePicker.platform.saveFile(
            dialogTitle: dialogTitle,
            fileName: fileName,
          ),
        );
      }

      if (!shouldContinueAccountExport(
        isDesktopPlatform: isDesktopPlatform,
        outputPath: outputPath,
      )) {
        return;
      }

      late final String filePath;
      MobileExportSaveResult? mobileSaveResult;
      if (isDesktopPlatform) {
        filePath = await AccountExportService.exportFullBackup(
          toxId: toxId,
          password: exportPassword,
          filePath: outputPath,
        );
      } else {
        mobileSaveResult = await createAndSaveMobileExportCopy(
          createInternalExport: () => AccountExportService.exportFullBackup(
            toxId: toxId,
            password: exportPassword,
          ),
          dialogTitle: l10n.exportAccount,
          fileName: defaultFileName,
          saveFile:
              ({
                required String dialogTitle,
                required String fileName,
                required Uint8List bytes,
              }) => FilePicker.platform.saveFile(
                dialogTitle: dialogTitle,
                fileName: fileName,
                bytes: bytes,
              ),
        );
        filePath =
            mobileSaveResult.userSelectedPath ??
            mobileSaveResult.internalFilePath;
      }
      _showAccountExportOutcome(
        exportedPath: filePath,
        mobileSaveResult: mobileSaveResult,
      );
    } catch (e) {
      SafeDiagnostics.logFailure('Full backup export error', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              )!.failedToExportAccount(SafeDiagnostics.describeError(e)),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _exportAccount() async {
    final l10n = AppLocalizations.of(context)!;
    final toxId = widget.service.accountKey;
    if (toxId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.noAccountToExport),
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
      password = await _showConfirmPasswordDialog(l10n.enterPasswordToExport);
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
      final isDesktopPlatform = isDesktopExportPlatform();
      final account = await Prefs.getAccountByToxId(toxId);
      final nickname = account?['nickname'] ?? 'account';
      final defaultFileName = buildAccountExportFileName(
        toxId: toxId,
        nickname: nickname,
        suffix: '.tox',
      );
      if (isDesktopPlatform) {
        outputPath = await runL3AwareExportSaveFilePicker(
          dialogTitle: l10n.exportAccount,
          fileName: defaultFileName,
          saveFile: (dialogTitle, fileName) => FilePicker.platform.saveFile(
            dialogTitle: dialogTitle,
            fileName: fileName,
          ),
        );
      }

      if (!shouldContinueAccountExport(
        isDesktopPlatform: isDesktopPlatform,
        outputPath: outputPath,
      )) {
        return;
      }

      late final String filePath;
      MobileExportSaveResult? mobileSaveResult;
      if (isDesktopPlatform) {
        filePath = await AccountExportService.exportAccountData(
          toxId: toxId,
          password: password,
          filePath: outputPath,
        );
      } else {
        mobileSaveResult = await createAndSaveMobileExportCopy(
          createInternalExport: () => AccountExportService.exportAccountData(
            toxId: toxId,
            password: password,
          ),
          dialogTitle: l10n.exportAccount,
          fileName: defaultFileName,
          saveFile:
              ({
                required String dialogTitle,
                required String fileName,
                required Uint8List bytes,
              }) => FilePicker.platform.saveFile(
                dialogTitle: dialogTitle,
                fileName: fileName,
                bytes: bytes,
              ),
        );
        filePath =
            mobileSaveResult.userSelectedPath ??
            mobileSaveResult.internalFilePath;
      }
      _showAccountExportOutcome(
        exportedPath: filePath,
        mobileSaveResult: mobileSaveResult,
      );
    } catch (e) {
      SafeDiagnostics.logFailure('Export account error', e);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              )!.failedToExportAccount(SafeDiagnostics.describeError(e)),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _importAccount() async {
    if (_importInProgress) return;
    setState(() => _importInProgress = true);
    String? rollbackToxId;
    var rollbackFullBackup = false;
    var rollbackImportedAccount = false;
    final l10n = AppLocalizations.of(context)!;
    try {
      // Show file picker for .tox and .zip files
      final filePath = await _pickImportFileFn();
      if (filePath == null) return;
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
        SafeDiagnostics.logFailure(
          '[SettingsPage] pre-import file size probe failed; import will retry',
          e,
        );
      }

      // Import account data (will check encryption and prompt for password if needed)
      Map<String, dynamic> accountData;

      if (isZip) {
        // ZIP: check account collision before any disk writes (importFullBackup writes profile/history/avatars/prefs).
        Map<String, String> metadata;
        try {
          metadata = await AccountExportService.readFullBackupMetadata(
            filePath,
            password: password,
          );
        } on PasswordRequiredException {
          if (!mounted) return;
          password = await _showPasswordDialog(l10n.enterPasswordToImport);
          if (password == null || !mounted) return;
          if (password.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.invalidPassword),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
            return;
          }
          metadata = await AccountExportService.readFullBackupMetadata(
            filePath,
            password: password,
          );
        }
        final metaToxId = metadata['toxId']!;
        rollbackToxId = metaToxId;
        rollbackFullBackup = true;
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
                title: Text(l10n.importAccount),
                content: Text(l10n.accountAlreadyExists),
                actions: [
                  TextButton(
                    onPressed: () => popDialogIfCurrent(context),
                    child: Text(l10n.ok),
                  ),
                ],
              ),
            );
          }
          return;
        }
        accountData = await AccountExportService.importFullBackup(
          filePath: filePath,
          password: password,
        );
      } else {
        try {
          accountData = await _importAccountDataFn(
            filePath: filePath,
            password: password,
          );
        } on PasswordRequiredException {
          if (!mounted) return;
          password = await _showPasswordDialog(l10n.enterPasswordToImport);
          if (password == null || !mounted) return;
          try {
            accountData = await _importAccountDataFn(
              filePath: filePath,
              password: password,
            );
          } catch (e) {
            SafeDiagnostics.logFailure(
              '[SettingsPage] Import password rejected',
              e,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.invalidPassword),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
            }
            return;
          }
        }
      }

      final toxId = accountData['toxId'] as String;
      rollbackToxId = toxId;
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
                title: Text(l10n.importAccount),
                content: Text(l10n.accountAlreadyExists),
                actions: [
                  TextButton(
                    onPressed: () => popDialogIfCurrent(context),
                    child: Text(l10n.ok),
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
        rollbackImportedAccount = true;
        final parentDir = Directory(profileDir);
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }
        final toxProfileFile = File(profileFilePath);
        await toxProfileFile.writeAsBytes(toxProfile);
        if (password != null && password.isNotEmpty) {
          final encrypted = await _encryptProfileFileFn(
            profileFilePath,
            password,
          );
          if (!encrypted) {
            throw StateError('Failed to encrypt imported account profile');
          }
        }
      }

      // Add/update account (.zip may contain nickname, .tox does not)
      final displayNickname = importedNickname.isNotEmpty
          ? importedNickname
          : l10n.importedAccount;
      if (!isZip) rollbackImportedAccount = true;
      await _addImportedAccountFn(
        toxId: toxId,
        nickname: displayNickname,
        statusMessage: '', // .tox files don't contain status message
        autoLogin: false,
        autoAcceptFriends: false,
        notificationSoundEnabled: true,
      );
      if (isZip) {
        await AccountExportService.finalizeFullBackupImport(toxId: toxId);
      }

      // Only .tox import passwords are account passwords. Full-backup .zip
      // passwords decrypt the archive and must not silently become the
      // restored account's login password.
      if (!isZip && password != null && password.isNotEmpty) {
        final persisted = await _setImportedAccountPasswordFn(toxId, password);
        if (!persisted) {
          throw StateError('Failed to persist imported account password');
        }
      }

      // Reload account list
      await _loadAccountList();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.accountImportedSuccessfully),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } on InvalidBackupPasswordException catch (e) {
      SafeDiagnostics.logFailure(
        '[SettingsPage] Full-backup password rejected',
        e,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.invalidPassword),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (rollbackToxId != null &&
          (rollbackFullBackup || rollbackImportedAccount)) {
        try {
          if (rollbackFullBackup) {
            await AccountExportService.rollbackPendingFullBackupRestore(
              toxId: rollbackToxId,
            );
          } else {
            await ImportedAccountRollback.run(
              toxId: rollbackToxId,
              logContext: 'SettingsPage',
            );
          }
        } catch (rollbackError) {
          SafeDiagnostics.logFailure(
            '[SettingsPage] Import rollback failed',
            rollbackError,
          );
        }
      }
      SafeDiagnostics.logFailure('[SettingsPage] Import account failed', e);
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.importAccount),
            content: Text(
              l10n.failedToImportAccount(SafeDiagnostics.describeError(e)),
            ),
            actions: [
              TextButton(
                onPressed: () => popDialogIfCurrent(context),
                child: Text(l10n.ok),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _importInProgress = false);
      } else {
        _importInProgress = false;
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
      SafeDiagnostics.logFailure('[SettingsPage] Set password failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              )!.failedToSetPassword(SafeDiagnostics.describeError(e)),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<String?> _showPasswordDialog(String title) async {
    final passwordController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: passwordController,
          autofocus: true,
          obscureText: true,
          textAlignVertical: TextAlignVertical.center,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.password,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                AppThemeConfig.inputBorderRadius,
              ),
            ),
          ),
          onSubmitted: (value) => popDialogIfCurrent(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => popDialogIfCurrent<String>(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () =>
                popDialogIfCurrent(context, passwordController.text),
            child: Text(AppLocalizations.of(context)!.ok),
          ),
        ],
      ),
    );
  }

  /// Password + confirmation dialog for exports; returns the password on match.
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
    final homeRoute = ModalRoute.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
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
      if (homeRoute != null) {
        navigator.popUntil(
          (route) => route.isFirst || identical(route, homeRoute),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      await _teardownSession(service: widget.service);
      await Prefs.setCurrentAccountToxId(null);

      if (!mounted) return;
      await navigator.pushAndRemoveUntil(
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

  Widget _buildMobileSettingsIndex(BuildContext context, dynamic colorTheme) {
    final appL10n = AppLocalizations.of(context)!;
    final tL10n = TencentCloudChatLocalizations.of(context);
    final outlineVariant = Theme.of(context).colorScheme.outlineVariant;

    Widget sectionTile({
      required Key key,
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
          key: key,
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
            key: UiKeys.settingsMobileProfileTile,
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
          key: UiKeys.settingsMobileAccountInfoSection,
          icon: Icons.badge_outlined,
          title: appL10n.accountInfo,
          onTap: () => _pushMobileSettingsSection(
            appL10n.accountInfo,
            _buildMobileAccountInfoCard(context, colorTheme),
          ),
        ),
        sectionTile(
          key: UiKeys.settingsMobileAccountManagementSection,
          icon: Icons.manage_accounts_outlined,
          title: appL10n.accountManagement,
          onTap: () => _pushMobileSettingsSection(
            appL10n.accountManagement,
            _buildMobileAccountManagementCard(context, colorTheme),
          ),
        ),
        sectionTile(
          key: UiKeys.settingsMobileAppearanceSection,
          icon: Icons.palette_outlined,
          title: tL10n?.appearance ?? appL10n.appearance,
          onTap: () => _pushMobileSettingsSection(
            tL10n?.appearance ?? appL10n.appearance,
            GlobalSettingsSection(
              colorTheme: colorTheme,
              toxId: widget.service.accountKey,
              view: GlobalSettingsView.appearance,
              onDownloadsConfigChanged: () {
                AppLogger.debug('[Settings] downloads config changed');
              },
            ),
          ),
        ),
        // "General" holds notification sound, downloads directory, and
        // auto-download size limit — moved off the Appearance page (which now
        // only carries theme + language) so each page stays focused on mobile.
        sectionTile(
          key: UiKeys.settingsMobileGeneralSection,
          icon: Icons.tune,
          title: appL10n.general,
          onTap: () => _pushMobileSettingsSection(
            appL10n.general,
            GlobalSettingsSection(
              colorTheme: colorTheme,
              toxId: widget.service.accountKey,
              view: GlobalSettingsView.general,
              onDownloadsConfigChanged: () {
                AppLogger.debug('[Settings] downloads config changed');
              },
            ),
          ),
        ),
        sectionTile(
          key: UiKeys.settingsMobileBootstrapSection,
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
            _buildAccountActionButtons(context),
            AppSpacing.verticalLg,
            Divider(height: 1, color: outlineVariant),
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
              onPressed: _importInProgress ? null : _importAccount,
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
      SafeDiagnostics.logFailure('[SettingsPage] Delete account failed', e);
      // Close loading dialog
      if (!mounted) return;
      Navigator.of(context).pop();

      // Show error message
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            )!.deleteAccountFailed(SafeDiagnostics.describeError(e)),
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
