import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:image_clipboard/image_clipboard.dart';

import '../i18n/app_localizations.dart';
import '../util/app_spacing.dart';
import '../util/locale_controller.dart';
import '../util/logger.dart';
import '../util/prefs.dart';
import 'profile/profile_avatar_picker.dart';
import 'profile/profile_edit_fields.dart';
import 'profile/profile_header.dart';
import 'profile/profile_layout.dart';
import 'profile/profile_qr_controller.dart';
import 'profile/profile_qr_section.dart';
import 'widgets/app_snackbar.dart';

/// A reusable profile page widget that can be used for both self and peer profiles.
///
/// When [isEditable] is true, it shows editable nickname and status message fields
/// with a save button. When false, it shows read-only information.
class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.userId,
    this.nickName,
    this.statusMessage,
    this.online = false,
    this.isEditable = false,
    this.connectionStatusStream,
    this.onSave,
    this.onChat,
    this.onAvatarChanged,
  });

  final String userId;
  final String? nickName;
  final String? statusMessage;
  final bool online;
  final bool isEditable;
  final Stream<bool>? connectionStatusStream;
  final Future<void> Function(String nickname, String statusMessage)? onSave;
  final VoidCallback? onChat;
  final ValueChanged<String?>? onAvatarChanged;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final TextEditingController _nickController;
  late final TextEditingController _statusController;
  late final TextEditingController _cardTextController;
  bool _isSaving = false;
  bool _editMode = false;
  bool _cardTextEditMode = false;
  final QrCardCache _qrCache = QrCardCache();
  String? _avatarPath;
  // Cached `File(_avatarPath).existsSync()` result. Re-checking on every build
  // hits the filesystem; we only need to verify when the path actually changes.
  bool _avatarFileExists = false;
  int _avatarVersion = 0;
  int _qrCardVersion = 0;
  Locale? _lastLocale;
  String? _savedNickName;
  String? _savedStatusMessage;
  bool _cardTextLoaded = false;
  Timer? _qrDebounce;

  @override
  void initState() {
    super.initState();
    _nickController = TextEditingController(text: widget.nickName ?? '');
    _statusController = TextEditingController(text: widget.statusMessage ?? '');
    _cardTextController = TextEditingController(text: '');
    _nickController.addListener(_handleEditableFieldChanged);
    _statusController.addListener(_handleEditableFieldChanged);
    _cardTextController.addListener(_handleEditableFieldChanged);
    _savedNickName = widget.nickName;
    _savedStatusMessage = widget.statusMessage;
    if (widget.isEditable) {
      _loadAvatar();
      _loadCardText();
    }
  }

  Future<void> _loadAvatar() async {
    String? path;
    if (widget.userId.isNotEmpty) {
      final account = await Prefs.getAccountByToxId(widget.userId);
      final accountPath = account?['avatarPath'];
      if (accountPath != null &&
          accountPath.isNotEmpty &&
          await File(accountPath).exists()) {
        path = accountPath;
      }
    }
    path ??= await Prefs.getAvatarPath();
    final exists = path != null && path.isNotEmpty && await File(path).exists();
    if (mounted) {
      setState(() {
        _avatarPath = path;
        _avatarFileExists = exists;
      });
    }
  }

  void _loadCardText() {
    Prefs.getCardText().then((value) {
      if (!mounted) return;
      // Wrap in setState so `_qrInputs()` (which reads `_cardTextController
      // .text`) picks up the loaded value on the next frame. Without this,
      // when prefs resolution wins the race against the first `build`/
      // `didChangeDependencies`, the QR card is generated with an empty
      // bottomText and only refreshed on a later unrelated rebuild.
      setState(() {
        _cardTextLoaded = true;
        if (value != null && value.isNotEmpty) {
          _cardTextController.text = value;
        } else {
          final appL10n = AppLocalizations.of(context);
          if (appL10n != null) {
            _cardTextController.text = appL10n.scanQrCodeToAddContact;
          }
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appL10n = AppLocalizations.of(context);
    if (appL10n != null &&
        widget.isEditable &&
        !_cardTextLoaded &&
        _cardTextController.text.isEmpty) {
      _cardTextController.text = appL10n.scanQrCodeToAddContact;
    }
    final currentLocale = Localizations.localeOf(context);
    if (_lastLocale != null &&
        _lastLocale!.languageCode != currentLocale.languageCode) {
      _invalidateQrCard();
    }
    _lastLocale = currentLocale;
  }

  @override
  void dispose() {
    _qrDebounce?.cancel();
    _nickController.removeListener(_handleEditableFieldChanged);
    _statusController.removeListener(_handleEditableFieldChanged);
    _cardTextController.removeListener(_handleEditableFieldChanged);
    _nickController.dispose();
    _statusController.dispose();
    _cardTextController.dispose();
    super.dispose();
  }

  void _handleEditableFieldChanged() {
    if (!widget.isEditable || !mounted) return;
    // Auto-invalidate QR card when nickname or status changes (but not card
    // text — that requires explicit "Generate Card").
    final nickChanged = _nickController.text.trim() != (_savedNickName ?? '');
    final statusChanged =
        _statusController.text.trim() != (_savedStatusMessage ?? '');
    if (nickChanged || statusChanged) {
      _qrDebounce?.cancel();
      _qrDebounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted) _invalidateQrCard();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editMode) {
      if (widget.nickName != oldWidget.nickName) {
        _nickController.text = widget.nickName ?? '';
        _savedNickName = widget.nickName;
        _invalidateQrCard();
      }
      if (widget.statusMessage != oldWidget.statusMessage) {
        _statusController.text = widget.statusMessage ?? '';
        _savedStatusMessage = widget.statusMessage;
      }
    }
  }

  Future<void> _handleSave() async {
    if (widget.onSave == null || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      await widget.onSave!(
        _nickController.text.trim(),
        _statusController.text.trim(),
      );
      final cardText = _cardTextController.text.trim();
      await Prefs.setCardText(cardText.isNotEmpty ? cardText : null);
      _savedNickName = _nickController.text.trim();
      _savedStatusMessage = _statusController.text.trim();
      _invalidateQrCard();
      if (!mounted) return;
      setState(() => _editMode = false);
      final tL10n = TencentCloudChatLocalizations.of(context);
      AppSnackBar.showSuccess(
        context,
        tL10n?.saveContact ?? AppLocalizations.of(context)!.saved,
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(
        context,
        AppLocalizations.of(context)!.failedToSave(e.toString()),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleSaveCardText() async {
    if (!widget.isEditable) return;
    final cardText = _cardTextController.text.trim();
    await Prefs.setCardText(cardText.isNotEmpty ? cardText : null);
    _invalidateQrCard();
    if (!mounted) return;
    setState(() => _cardTextEditMode = false);
  }

  String get _effectiveDisplayName {
    final current = _nickController.text.trim();
    if (current.isNotEmpty) return current;
    final widgetNick = widget.nickName?.trim();
    if (widgetNick != null && widgetNick.isNotEmpty) return widgetNick;
    return widget.userId;
  }

  void _invalidateQrCard() {
    _qrCardVersion++;
    _qrCache.invalidate();
    if (mounted) setState(() {});
  }

  QrCardRenderInputs _qrInputs({
    required Color primaryColor,
    required Color textColor,
    required Locale locale,
  }) {
    final cardText = _cardTextController.text.trim().isNotEmpty
        ? _cardTextController.text.trim()
        : (AppLocalizations.of(context)?.scanQrCodeToAddContact ?? '');
    return QrCardRenderInputs(
      userId: widget.userId,
      displayName: _effectiveDisplayName,
      locale: locale,
      bottomText: cardText,
      primaryColor: primaryColor,
      textColor: textColor,
      avatarPath: _avatarPath,
      avatarVersion: _avatarVersion,
      qrCardVersion: _qrCardVersion,
    );
  }

  Future<void> _handleSaveQr({
    required Color primaryColor,
    required Color textColor,
    required Locale locale,
  }) async {
    final tL10n = TencentCloudChatLocalizations.of(context);
    final appL10n = AppLocalizations.of(context)!;
    try {
      final inputs = _qrInputs(
        primaryColor: primaryColor,
        textColor: textColor,
        locale: locale,
      );
      if (Platform.isAndroid || Platform.isIOS) {
        final qrPath = await _qrCache.getOrGenerate(inputs);
        final savedPath = await saveQrToGallery(qrPath);
        if (!mounted) return;
        AppSnackBar.showSuccess(
          context,
          savedPath == null
              ? appL10n.saved
              : '${tL10n?.saveFileSuccess ?? appL10n.saved}: $savedPath',
        );
        return;
      }
      final savedPath = await pickDirectoryAndSaveQr(inputs);
      if (savedPath == null) return;
      if (!mounted) return;
      AppSnackBar.showSuccess(
        context,
        '${tL10n?.saveFileSuccess ?? appL10n.saved}: $savedPath',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(
        context,
        AppLocalizations.of(context)!.failedToSave(e.toString()),
      );
    }
  }

  Future<void> _copyQrImage(String path) async {
    final appL10n = AppLocalizations.of(context)!;
    try {
      await ImageClipboard().copyImage(path);
      if (!mounted) return;
      AppSnackBar.showSuccess(context, appL10n.idCopiedToClipboard);
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(
        context,
        AppLocalizations.of(context)!.copyFailed(e.toString()),
      );
    }
  }

  Future<void> _copyToxId() async {
    final appL10n = AppLocalizations.of(context)!;
    try {
      await Clipboard.setData(ClipboardData(text: widget.userId));
      if (!mounted) return;
      AppSnackBar.showSuccess(context, appL10n.idCopiedToClipboard);
    } catch (e, st) {
      AppLogger.logError(
        '[ProfilePage] Failed to copy Tox ID to clipboard',
        e,
        st,
      );
      if (!mounted) return;
      AppSnackBar.showError(context, appL10n.copyFailed(e.toString()));
    }
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await pickAndPersistAvatar(
        isEditable: widget.isEditable,
        userId: widget.userId,
      );
      if (picked == null) return;
      if (mounted) {
        setState(() {
          _avatarPath = picked.destPath;
          _avatarFileExists = true;
          _avatarVersion++;
        });
      }
      widget.onAvatarChanged?.call(picked.destPath);
      _invalidateQrCard();
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(
        context,
        AppLocalizations.of(context)!.failedToUpdateAvatar(e.toString()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tL10n = TencentCloudChatLocalizations.of(context);
    // No `Scaffold` here: it would force this widget to expand to the
    // parent's max height (the dialog cap), leaving a tall empty area
    // below the form. `Material(type: transparency)` provides ink/ripple
    // semantics without imposing a height. SnackBars from inside this
    // widget bubble up to `MaterialApp`'s root `ScaffoldMessenger`, which
    // has the host page's `Scaffold` registered — `AppSnackBar` uses
    // `ScaffoldMessenger.of(context)` which resolves to that root, so
    // copy/avatar-pick toasts continue to surface (via `Overlay` they
    // render above the modal dialog anyway).
    return ValueListenableBuilder<Locale>(
      valueListenable: AppLocale.locale,
      builder: (context, locale, _) {
        return TencentCloudChatThemeWidget(
          build: (context, colorTheme, textStyle) => Material(
            type: MaterialType.transparency,
            child: _buildConnectionAware(context, colorTheme, tL10n, locale),
          ),
        );
      },
    );
  }

  Widget _buildConnectionAware(
    BuildContext context,
    colorTheme,
    tL10n,
    Locale locale,
  ) {
    final stream = widget.connectionStatusStream;
    if (widget.isEditable && stream != null) {
      return StreamBuilder<bool>(
        stream: stream,
        initialData: widget.online,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            AppLogger.logError(
              '[ProfilePage] connection status stream error',
              snapshot.error,
            );
          }
          return _buildContent(
            context,
            colorTheme,
            tL10n,
            snapshot.data ?? widget.online,
            locale,
          );
        },
      );
    }
    return _buildContent(context, colorTheme, tL10n, widget.online, locale);
  }

  Widget _buildContent(
    BuildContext context,
    colorTheme,
    tL10n,
    bool isConnected,
    Locale locale,
  ) {
    final appL10n = AppLocalizations.of(context)!;
    final displayName = widget.isEditable
        ? _effectiveDisplayName
        : (widget.nickName?.isNotEmpty == true
              ? widget.nickName!.trim()
              : widget.userId);
    final statusText = _resolveStatusText(appL10n);
    final displayInitial = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : '?';
    final qrFuture = _qrCache.getOrGenerate(
      _qrInputs(
        primaryColor: colorTheme.primaryColor,
        textColor: colorTheme.primaryTextColor,
        locale: locale,
      ),
    );
    final screenWidth = MediaQuery.sizeOf(context).width;
    final fallbackContentWidth = (screenWidth > 0 && screenWidth < 440)
        ? screenWidth - 32
        : 440.0;

    final header = ProfileHeader(
      displayName: displayName,
      displayInitial: displayInitial,
      statusText: statusText,
      isEditable: widget.isEditable,
      editMode: _editMode,
      isConnected: isConnected,
      primaryColor: colorTheme.primaryColor,
      onPrimary: colorTheme.onPrimary,
      primaryTextColor: colorTheme.primaryTextColor,
      secondaryTextColor: colorTheme.secondaryTextColor,
      avatarPath: _avatarPath,
      avatarFileExists: _avatarFileExists,
      avatarVersion: _avatarVersion,
      onAvatarTap: _pickAvatar,
      onToggleEdit: () => setState(() => _editMode = !_editMode),
      onlineLabel: appL10n.statusOnline,
      offlineLabel: appL10n.statusOffline,
      editTooltip: tL10n?.edit ?? 'Edit',
      cancelTooltip: tL10n?.cancel ?? appL10n.cancel,
      editFields: _editMode
          ? ProfileEditFields(
              nickController: _nickController,
              statusController: _statusController,
              isSaving: _isSaving,
              primaryColor: colorTheme.primaryColor,
              onPrimary: colorTheme.onPrimary,
              nicknameLabel: tL10n?.setNickname ?? appL10n.nickname,
              statusLabel: tL10n?.setSignature ?? appL10n.statusMessage,
              saveLabel: tL10n?.saveContact ?? appL10n.save,
              cancelLabel: tL10n?.cancel ?? appL10n.cancel,
              nicknameTooLong: appL10n.nicknameTooLong,
              statusTooLong: appL10n.statusMessageTooLong,
              onCancel: () => setState(() => _editMode = false),
              onSave: _handleSave,
              onAnyFieldChanged: () => setState(() {}),
            )
          : null,
    );

    final mainColumnChildren = <Widget>[
      header,
      if (!widget.isEditable || !_editMode) AppSpacing.verticalLg,
      if (!widget.isEditable && widget.onChat != null) ...[
        AppSpacing.verticalMd,
        ProfileChatButton(
          label: tL10n?.sendMsg ?? appL10n.startChat,
          onPressed: widget.onChat!,
        ),
        AppSpacing.verticalLg,
      ],
      ProfileToxIdSection(
        userId: widget.userId,
        label: tL10n?.userID ?? 'User ID:',
        copyLabel: tL10n?.copy ?? appL10n.copy,
        primaryColor: colorTheme.primaryColor,
        secondaryTextColor: colorTheme.secondaryTextColor,
        primaryTextColor: colorTheme.primaryTextColor,
        onCopy: _copyToxId,
      ),
      AppSpacing.verticalMd,
      if (widget.isEditable) ...[
        ProfileCardTextField(
          controller: _cardTextController,
          editMode: _cardTextEditMode,
          primaryColor: colorTheme.primaryColor,
          onPrimary: colorTheme.onPrimary,
          secondaryTextColor: colorTheme.secondaryTextColor,
          primaryTextColor: colorTheme.primaryTextColor,
          onEnterEditMode: () => setState(() => _cardTextEditMode = true),
          onSave: _handleSaveCardText,
          placeholderText: appL10n.scanQrCodeToAddContact,
          labelText: appL10n.customCardText,
          generateLabel: appL10n.generateCard,
        ),
        AppSpacing.verticalMd,
      ],
    ];

    return ProfileLayout(
      mainColumnChildren: mainColumnChildren,
      qrSectionBuilder: (isWide) => ProfileQrSection(
        qrFuture: qrFuture,
        versionKey: '${locale.languageCode}_v$_qrCardVersion',
        isWide: isWide,
        primaryColor: colorTheme.primaryColor,
        onSave: () => _handleSaveQr(
          primaryColor: colorTheme.primaryColor,
          textColor: colorTheme.primaryTextColor,
          locale: locale,
        ),
        onCopy: _copyQrImage,
        enableCopy: !(Platform.isAndroid || Platform.isIOS || Platform.isLinux),
      ),
      fallbackContentWidth: fallbackContentWidth,
    );
  }

  String _resolveStatusText(AppLocalizations appL10n) {
    if (widget.isEditable) {
      final current = _statusController.text.trim();
      if (current.isNotEmpty) return current;
    }
    final widgetStatus = widget.statusMessage?.trim();
    if (widgetStatus != null && widgetStatus.isNotEmpty) return widgetStatus;
    return appL10n.statusMessage;
  }
}
