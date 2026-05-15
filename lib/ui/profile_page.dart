import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../util/app_spacing.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import '../util/app_paths.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:image_clipboard/image_clipboard.dart';
import '../util/prefs.dart';
import '../util/app_theme_config.dart';
import '../util/qr_card_generator.dart';
import '../util/locale_controller.dart';
import '../i18n/app_localizations.dart';

/// Calculate text length where Chinese characters count as 1, and letters/numbers count as 0.5
double _calculateTextLength(String text) {
  double length = 0;
  for (int i = 0; i < text.length; i++) {
    final char = text[i];
    // Check if character is Chinese (CJK Unified Ideographs range)
    if (char.codeUnitAt(0) >= 0x4E00 && char.codeUnitAt(0) <= 0x9FFF) {
      length += 1.0;
    } else if (RegExp(r'[a-zA-Z0-9]').hasMatch(char)) {
      length += 0.5;
    } else {
      // Other characters (punctuation, spaces, etc.) count as 0.5
      length += 0.5;
    }
  }
  return length;
}

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
  final VoidCallback?
      onChat; // Callback when chat button is clicked (for peer profiles)
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
  bool _cardTextEditMode = false; // Track if card text is in edit mode
  bool _hasUnsavedChanges =
      false; // Track if nickname/status/card text has been modified
  Future<String>? _qrCardFuture;
  String? _qrKey;
  String? _avatarPath;
  int _avatarVersion = 0;
  int _qrCardVersion = 0; // Version counter to force regeneration on refresh
  Locale? _lastLocale; // Track last locale to detect changes
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  String? _savedNickName; // Track saved nickname
  String? _savedStatusMessage; // Track saved status message
  String? _savedCardText; // Track saved card text

  @override
  void initState() {
    super.initState();
    _nickController = TextEditingController(text: widget.nickName ?? '');
    _statusController = TextEditingController(text: widget.statusMessage ?? '');
    // Initialize card text controller empty; default text set in didChangeDependencies
    _cardTextController = TextEditingController(text: '');
    // Listen to changes to track unsaved modifications
    _nickController.addListener(_handleEditableFieldChanged);
    _statusController.addListener(_handleEditableFieldChanged);
    _cardTextController.addListener(_handleEditableFieldChanged);
    // Initialize saved values
    _savedNickName = widget.nickName;
    _savedStatusMessage = widget.statusMessage;
    if (widget.isEditable) {
      Future<String?> loadPath() async {
        if (widget.userId.isNotEmpty) {
          final account = await Prefs.getAccountByToxId(widget.userId);
          final path = account?['avatarPath'];
          if (path != null && path.isNotEmpty && await File(path).exists()) {
            return path;
          }
        }
        return Prefs.getAvatarPath();
      }

      loadPath().then((value) {
        if (mounted) {
          setState(() {
            _avatarPath = value;
          });
        }
      });
      // Load saved card text first, before didChangeDependencies sets default
      Prefs.getCardText().then((value) {
        if (mounted) {
          if (value != null && value.isNotEmpty) {
            _cardTextController.text = value;
            _savedCardText = value;
          } else {
            // Only set default if no saved value exists
            final appL10n = AppLocalizations.of(context);
            if (appL10n != null) {
              final defaultText = appL10n.scanQrCodeToAddContact;
              _cardTextController.text = defaultText;
              _savedCardText = defaultText;
            }
          }
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set localized default for card text when empty (Prefs.getCardText() may override later)
    final appL10n = AppLocalizations.of(context);
    if (appL10n != null &&
        widget.isEditable &&
        _cardTextController.text.isEmpty) {
      _cardTextController.text = appL10n.scanQrCodeToAddContact;
    }
  }

  @override
  void dispose() {
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
    // Check if any field has been modified
    final nickChanged = _nickController.text.trim() != (_savedNickName ?? '');
    final statusChanged =
        _statusController.text.trim() != (_savedStatusMessage ?? '');
    final cardTextChanged =
        _cardTextController.text.trim() != (_savedCardText ?? '');
    final hasChanges = nickChanged || statusChanged || cardTextChanged;

    // Auto-regenerate QR card when nickname or status changes (but not card text)
    // Card text changes require explicit "Generate Card" button click
    if (nickChanged || statusChanged) {
      // Auto-invalidate QR card when nickname or status changes
      _invalidateQrCard();
    }

    if (hasChanges != _hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = hasChanges;
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
      // Save card text to preferences
      final cardText = _cardTextController.text.trim();
      if (cardText.isNotEmpty) {
        await Prefs.setCardText(cardText);
      } else {
        await Prefs.setCardText(null);
      }
      // Update saved values
      _savedNickName = _nickController.text.trim();
      _savedStatusMessage = _statusController.text.trim();
      _savedCardText = cardText.isNotEmpty ? cardText : null;
      // Invalidate QR card after saving to force regeneration with new data
      _invalidateQrCard();
      if (!mounted) return;
      setState(() {
        _editMode = false;
        _hasUnsavedChanges = false;
      });
      final tL10n = TencentCloudChatLocalizations.of(context);
      _showSnack(tL10n?.saveContact ?? AppLocalizations.of(context)!.saved);
    } catch (e) {
      if (!mounted) return;
      final appL10n = AppLocalizations.of(context)!;
      _showSnack(appL10n.failedToSave(e.toString()));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _handleSaveCardText() async {
    if (!widget.isEditable) return;
    // Save card text to preferences
    final cardText = _cardTextController.text.trim();
    if (cardText.isNotEmpty) {
      await Prefs.setCardText(cardText);
    } else {
      await Prefs.setCardText(null);
    }
    // Update saved value
    _savedCardText = cardText.isNotEmpty ? cardText : null;
    // Invalidate QR card to force regeneration
    _invalidateQrCard();
    if (!mounted) return;
    setState(() {
      _cardTextEditMode = false;
      _hasUnsavedChanges =
          _nickController.text.trim() != (_savedNickName ?? '') ||
              _statusController.text.trim() != (_savedStatusMessage ?? '');
    });
  }

  String get _effectiveDisplayName {
    final current = _nickController.text.trim();
    if (current.isNotEmpty) return current;
    final widgetNick = widget.nickName?.trim();
    if (widgetNick != null && widgetNick.isNotEmpty) return widgetNick;
    return widget.userId;
  }

  void _invalidateQrCard() {
    // Increment version to force regeneration and FutureBuilder rebuild
    _qrCardVersion++;
    _qrKey = null;
    _qrCardFuture = null;
    // Force immediate rebuild if mounted
    if (mounted) {
      setState(() {});
    }
  }

  Future<String> _getQrCardPath({
    required Color primaryColor,
    required Color textColor,
    required Locale locale,
  }) {
    // Always use current controller values to ensure latest nickname and card text are used
    // This ensures that after saving, the QR card reflects the updated values
    final displayName = _effectiveDisplayName;
    final avatarKey =
        (_avatarPath ?? '').isNotEmpty ? _avatarPath! : 'no-avatar';
    // Use current card text from controller
    final cardText = _cardTextController.text.trim().isNotEmpty
        ? _cardTextController.text.trim()
        : (AppLocalizations.of(context)?.scanQrCodeToAddContact ?? '');
    final key =
        '$displayName|${locale.languageCode}|${_colorKey(primaryColor)}|${_colorKey(textColor)}|$avatarKey|$_avatarVersion|$cardText|$_qrCardVersion';
    // Always regenerate if key changed or if future is null
    // This ensures that after refresh, the QR card uses the latest values
    // Also check if the version changed to force regeneration even if other values are the same
    if (_qrCardFuture == null || _qrKey != key) {
      _qrKey = key;
      // Always create a new future to ensure fresh generation with latest values
      // Create a completely new future object to force FutureBuilder to rebuild
      _qrCardFuture = ContactQrCardGenerator.generateTempCard(
        userId: widget.userId,
        displayName: displayName,
        locale: locale,
        bottomText: cardText,
        primaryColor: primaryColor,
        textColor: textColor,
        avatarPath: _avatarPath,
      );
    } else {}
    return _qrCardFuture!;
  }

  String _colorKey(Color color) =>
      '${color.alpha}-${color.red}-${color.green}-${color.blue}';

  Future<void> _handleSaveQr({
    required Color primaryColor,
    required Color textColor,
    required Locale locale,
  }) async {
    final tL10n = TencentCloudChatLocalizations.of(context);
    final appL10n = AppLocalizations.of(context)!;
    try {
      final directoryPath = await FilePicker.platform.getDirectoryPath();
      if (directoryPath == null) return;
      final cardText = _cardTextController.text.trim().isNotEmpty
          ? _cardTextController.text.trim()
          : appL10n.scanQrCodeToAddContact;
      final savedPath = await ContactQrCardGenerator.saveToDirectory(
        directory: Directory(directoryPath),
        userId: widget.userId,
        displayName: _effectiveDisplayName,
        locale: locale,
        bottomText: cardText,
        primaryColor: primaryColor,
        textColor: textColor,
        avatarPath: _avatarPath,
      );
      if (!mounted) return;
      _showSnack('${tL10n?.saveFileSuccess ?? appL10n.saved}: $savedPath');
    } catch (e) {
      if (!mounted) return;
      final appL10n = AppLocalizations.of(context)!;
      _showSnack(appL10n.failedToSave(e.toString()));
    }
  }

  void _handleRefreshCard() async {
    // Always save all current values to ensure they're persisted
    final currentNick = _nickController.text.trim();
    final currentStatus = _statusController.text.trim();
    final cardText = _cardTextController.text.trim();

    // Save nickname and status if widget.onSave is available
    if (widget.onSave != null &&
        (currentNick != (_savedNickName ?? '') ||
            currentStatus != (_savedStatusMessage ?? ''))) {
      await widget.onSave!(
        currentNick,
        currentStatus,
      );
      _savedNickName = currentNick;
      _savedStatusMessage = currentStatus;
    }

    // Save card text
    if (cardText.isNotEmpty) {
      await Prefs.setCardText(cardText);
    } else {
      await Prefs.setCardText(null);
    }
    _savedCardText = cardText.isNotEmpty ? cardText : null;

    // Invalidate QR card to force regeneration with latest values
    // Increment version to ensure key changes and QR card regenerates
    _qrCardVersion++;
    _qrKey = null; // Clear key so it will be recalculated with new version
    _qrCardFuture = null; // Clear future to force regeneration

    // Force immediate rebuild to ensure FutureBuilder gets new future
    if (!mounted) return;
    setState(() {
      _hasUnsavedChanges = false;
      _editMode = false;
      _cardTextEditMode = false;
    });

    // After setState, ensure the future is recreated by calling _getQrCardPath
    // This ensures that when build() is called again, a new future is available
    // We need to get the current theme and locale from context, but we can't access it here
    // So we'll rely on the build() method to call _getQrCardPath() which will create the new future
  }

  Future<void> _copyQrImage(String path) async {
    final appL10n = AppLocalizations.of(context)!;
    try {
      final imageClipboard = ImageClipboard();
      await imageClipboard.copyImage(path);
      if (!mounted) return;
      _showSnack(appL10n.idCopiedToClipboard);
    } catch (e) {
      if (!mounted) return;
      final appL10n = AppLocalizations.of(context)!;
      _showSnack(appL10n.copyFailed(e.toString()));
    }
  }

  Future<void> _pickAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      final pickedPath = result?.files.single.path;
      if (pickedPath == null) return;
      // Use per-account avatars directory if current account is known
      final currentToxId = await Prefs.getCurrentAccountToxId();
      String avatarsDirPath;
      if (currentToxId != null && currentToxId.isNotEmpty) {
        avatarsDirPath = await AppPaths.getAccountAvatarsPath(currentToxId);
      } else {
        avatarsDirPath = (await AppPaths.avatars).path;
      }
      final avatarsDir = Directory(avatarsDirPath);
      if (!await avatarsDir.exists()) {
        await avatarsDir.create(recursive: true);
      }
      final ext = p.extension(pickedPath);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final baseName = widget.isEditable && widget.userId.isNotEmpty
          ? 'avatar_${widget.userId}'
          : 'self_avatar';
      final fileName = '${baseName}_$ts$ext';
      final destPath = p.join(avatarsDirPath, fileName);

      // Remove previous self-avatar files so stale versions don't accumulate.
      try {
        final dir = Directory(avatarsDirPath);
        if (await dir.exists()) {
          await for (final entity in dir.list()) {
            if (entity is File &&
                p.basename(entity.path).startsWith(baseName)) {
              try {
                await entity.delete();
              } catch (_) {}
            }
          }
        }
      } catch (_) {}

      await File(pickedPath).copy(destPath);
      await Prefs.setAvatarPath(destPath);
      if (widget.isEditable && widget.userId.isNotEmpty) {
        await Prefs.setAccountAvatarPath(widget.userId, destPath);
      }
      if (mounted) {
        setState(() {
          _avatarPath = destPath;
          _avatarVersion++;
        });
      }
      widget.onAvatarChanged?.call(destPath);
      // Auto-regenerate QR card when avatar changes
      _invalidateQrCard();
    } catch (e) {
      if (!mounted) return;
      final appL10n = AppLocalizations.of(context)!;
      _showSnack(appL10n.failedToUpdateAvatar(e.toString()));
    }
  }

  Widget _buildAvatar({
    required Color primaryColor,
    required Color onPrimary,
    required String displayInitial,
    bool showOnlineDot = false,
    bool isConnected = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    const double size = 88;
    final bool hasCustomAvatar = _avatarPath != null &&
        _avatarPath!.isNotEmpty &&
        File(_avatarPath!).existsSync();

    Widget avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hasCustomAvatar ? Colors.transparent : primaryColor,
        border: Border.all(
          color: scheme.outlineVariant,
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: hasCustomAvatar
          ? ClipOval(
              child: Image.file(
                File(_avatarPath!),
                key: ValueKey('avatar-$_avatarVersion'),
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            )
          : Text(
              displayInitial,
              style: TextStyle(
                fontSize: 32,
                color: onPrimary,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
    );

    final List<Widget> stackChildren = [
      if (widget.isEditable)
        GestureDetector(
          onTap: _pickAvatar,
          child: avatar,
        )
      else
        avatar,
    ];

    if (showOnlineDot) {
      stackChildren.add(Positioned(
        right: 2,
        bottom: 2,
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: isConnected
                ? AppThemeConfig.successColor
                : scheme.outlineVariant,
            shape: BoxShape.circle,
            border: Border.all(color: scheme.surface, width: 2),
          ),
        ),
      ));
    }

    if (widget.isEditable) {
      stackChildren.add(Positioned(
        right: 0,
        bottom: 0,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _pickAvatar,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: primaryColor,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 2),
              ),
              child: Icon(Icons.camera_alt, size: 14, color: onPrimary),
            ),
          ),
        ),
      ));
    }

    if (stackChildren.length == 1) {
      return avatar;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: stackChildren,
    );
  }

  void _showSnack(String message) {
    _messengerKey.currentState?.hideCurrentSnackBar();
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tL10n = TencentCloudChatLocalizations.of(context);
    return ScaffoldMessenger(
      key: _messengerKey,
      child: ValueListenableBuilder<Locale>(
        valueListenable: AppLocale.locale,
        builder: (context, locale, _) {
          // Invalidate QR card when locale changes
          if (_lastLocale != null &&
              _lastLocale!.languageCode != locale.languageCode) {
            // Immediately invalidate and clear the future
            _invalidateQrCard();
          }
          _lastLocale = locale;
          return TencentCloudChatThemeWidget(
            build: (context, colorTheme, textStyle) {
              // Determine connection status: use stream for self, use online flag for peer
              if (widget.isEditable && widget.connectionStatusStream != null) {
                // For self profile, use StreamBuilder with initial data from service
                // Note: We can't access service directly here, so we rely on the stream
                // The stream should emit the current status when subscribed
                return StreamBuilder<bool>(
                  stream: widget.connectionStatusStream,
                  initialData: widget
                      .online, // Use widget.online as initial value to show correct status immediately
                  builder: (context, snapshot) {
                    final isConnected = snapshot.data ?? widget.online;
                    if (snapshot.hasError) {}
                    return _wrapContentScaffold(_buildContent(
                        context, colorTheme, tL10n, isConnected, locale));
                  },
                );
              } else {
                // For peer profile, use online flag
                final isConnected = widget.online;
                return _wrapContentScaffold(_buildContent(
                    context, colorTheme, tL10n, isConnected, locale));
              }
            },
          );
        },
      ),
    );
  }

  Widget _wrapContentScaffold(Widget child) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: child,
    );
  }

  Widget _buildContent(BuildContext context, colorTheme, tL10n,
      bool isConnected, Locale locale) {
    final displayName = widget.isEditable
        ? _effectiveDisplayName
        : (widget.nickName?.isNotEmpty == true
            ? widget.nickName!.trim()
            : widget.userId);
    final appStatusLabel = AppLocalizations.of(context)!.statusMessage;
    final statusText = widget.isEditable
        ? (_statusController.text.trim().isNotEmpty
            ? _statusController.text.trim()
            : (widget.statusMessage?.trim().isNotEmpty == true
                ? widget.statusMessage!.trim()
                : appStatusLabel))
        : (widget.statusMessage?.trim().isNotEmpty == true
            ? widget.statusMessage!.trim()
            : appStatusLabel);
    final displayInitial =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final qrFuture = _getQrCardPath(
      primaryColor: colorTheme.primaryColor,
      textColor: colorTheme.primaryTextColor,
      locale: locale,
    );
    final appL10n = AppLocalizations.of(context)!;
    final copySuccessText = appL10n.idCopiedToClipboard;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final contentWidth =
        (screenWidth > 0 && screenWidth < 440) ? screenWidth - 32 : 440.0;

    // Use optimal width for profile content; on narrow screens use available width.
    // Wide screens use a two-column layout (info + QR side-by-side) to avoid scrolling.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : contentWidth;
        final isWide = width >= 640;

        // Main column children (everything except the QR section).
        final mainColumnChildren = <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAvatar(
                        primaryColor: colorTheme.primaryColor,
                        onPrimary: colorTheme.onPrimary,
                        displayInitial: displayInitial,
                        showOnlineDot: true,
                        isConnected: isConnected,
                      ),
                      AppSpacing.horizontalLg,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        displayName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.4,
                                            ),
                                      ),
                                      AppSpacing.verticalXs,
                                      Text(
                                        statusText,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                                color: colorTheme
                                                    .secondaryTextColor),
                                      ),
                                    ],
                                  ),
                                ),
                                if (widget.isEditable)
                                  IconButton(
                                    icon: Icon(
                                        _editMode ? Icons.close : Icons.edit,
                                        size: 20),
                                    tooltip: _editMode
                                        ? (tL10n?.cancel ?? appL10n.cancel)
                                        : (tL10n?.edit ?? 'Edit'),
                                    onPressed: () =>
                                        setState(() => _editMode = !_editMode),
                                  ),
                              ],
                            ),
                            if (_editMode) ...[
                              AppSpacing.verticalMd,
                              TextField(
                                controller: _nickController,
                                textAlignVertical: TextAlignVertical.center,
                                decoration: InputDecoration(
                                  labelText:
                                      tL10n?.setNickname ?? appL10n.nickname,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppThemeConfig.inputBorderRadius),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppThemeConfig.inputBorderRadius),
                                    borderSide: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppThemeConfig.inputBorderRadius),
                                    borderSide: BorderSide(
                                      color: colorTheme.primaryColor,
                                      width: 1.5,
                                    ),
                                  ),
                                  errorText: _calculateTextLength(
                                              _nickController.text) >
                                          12
                                      ? AppLocalizations.of(context)!
                                          .nicknameTooLong
                                      : null,
                                ),
                                maxLength:
                                    24, // Allow up to 24 characters for input
                                onChanged: (value) {
                                  setState(
                                      () {}); // Rebuild to update error text
                                },
                              ),
                              AppSpacing.verticalMd,
                              TextField(
                                controller: _statusController,
                                textAlignVertical: TextAlignVertical.center,
                                decoration: InputDecoration(
                                  labelText: tL10n?.setSignature ??
                                      appL10n.statusMessage,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppThemeConfig.inputBorderRadius),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppThemeConfig.inputBorderRadius),
                                    borderSide: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppThemeConfig.inputBorderRadius),
                                    borderSide: BorderSide(
                                      color: colorTheme.primaryColor,
                                      width: 1.5,
                                    ),
                                  ),
                                  errorText: _calculateTextLength(
                                              _statusController.text) >
                                          24
                                      ? AppLocalizations.of(context)!
                                              .statusMessageTooLong
                                      : null,
                                ),
                                minLines: 1,
                                maxLines: 3,
                                maxLength:
                                    48, // Allow up to 48 characters for input
                                onChanged: (value) {
                                  setState(
                                      () {}); // Rebuild to update error text
                                },
                              ),
                              AppSpacing.verticalMd,
                              SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: colorTheme.primaryColor,
                                    foregroundColor: colorTheme.onPrimary,
                                    disabledBackgroundColor: colorTheme
                                        .primaryColor
                                        .withValues(alpha: 0.4),
                                    disabledForegroundColor:
                                        colorTheme.onPrimary,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppThemeConfig.buttonBorderRadius),
                                    ),
                                    textStyle: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  onPressed: (_isSaving ||
                                          _calculateTextLength(
                                                  _nickController.text) >
                                              12 ||
                                          _calculateTextLength(
                                                  _statusController.text) >
                                              24)
                                      ? null
                                      : _handleSave,
                                  child: _isSaving
                                      ? SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    colorTheme.onPrimary),
                                          ),
                                        )
                                      : Text(tL10n?.saveContact ?? appL10n.save),
                                ),
                              ),
                              AppSpacing.verticalSm,
                            ],
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: isConnected
                                        ? AppThemeConfig.successColor
                                        : colorTheme.secondaryTextColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                AppSpacing.horizontalXs,
                                const SizedBox(width: 2),
                                Text(
                                  isConnected
                                      ? (tL10n?.online ?? appL10n.online)
                                      : (tL10n?.offline ?? appL10n.offline),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: isConnected
                                            ? AppThemeConfig.successColor
                                            : colorTheme.secondaryTextColor,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.2,
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (!widget.isEditable || !_editMode)
                    AppSpacing.verticalLg,
                  // Chat Button (only for non-editable peer profiles)
                  if (!widget.isEditable && widget.onChat != null) ...[
                    AppSpacing.verticalMd,
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorTheme.primaryColor,
                          foregroundColor: colorTheme.onPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                AppThemeConfig.buttonBorderRadius),
                          ),
                          textStyle: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        icon: const Icon(Icons.message_rounded, size: 18),
                        label: Text(tL10n?.sendMsg ?? appL10n.startChat),
                        onPressed: widget.onChat,
                      ),
                    ),
                    AppSpacing.verticalLg,
                  ],
                  // User ID
                  Row(
                    children: [
                      Text(
                        tL10n?.userID ?? 'User ID:',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(
                              color: colorTheme.secondaryTextColor,
                              letterSpacing: 0.3,
                            ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: colorTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                AppThemeConfig.buttonBorderRadius),
                          ),
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: Text(tL10n?.copy ?? appL10n.copy),
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: widget.userId));
                          if (!mounted) return;
                          _showSnack(copySuccessText);
                        },
                      ),
                    ],
                  ),
                  AppSpacing.verticalXs,
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(
                          AppThemeConfig.inputBorderRadius),
                    ),
                    child: SelectableText(
                      widget.userId,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            fontFamily: 'monospace',
                            color: colorTheme.primaryTextColor,
                            letterSpacing: 0.2,
                            height: 1.4,
                          ),
                    ),
                  ),
                  AppSpacing.verticalMd,
                  // Custom card text input (clickable to edit, Enter to save, with generate button)
                  if (widget.isEditable) ...[
                    _cardTextEditMode
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _cardTextController,
                                textAlignVertical: TextAlignVertical.center,
                                decoration: InputDecoration(
                                  labelText: appL10n.customCardText,
                                  hintText: appL10n.scanQrCodeToAddContact,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppThemeConfig.inputBorderRadius),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppThemeConfig.inputBorderRadius),
                                    borderSide: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppThemeConfig.inputBorderRadius),
                                    borderSide: BorderSide(
                                      color: colorTheme.primaryColor,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                maxLines: 2,
                                autofocus: true,
                                onSubmitted: (_) => _handleSaveCardText(),
                                onEditingComplete: _handleSaveCardText,
                              ),
                              AppSpacing.verticalSm,
                              SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: colorTheme.primaryColor,
                                    foregroundColor: colorTheme.onPrimary,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppThemeConfig.buttonBorderRadius),
                                    ),
                                    textStyle: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: Text(appL10n.generateCard),
                                  onPressed: _handleSaveCardText,
                                ),
                              ),
                            ],
                          )
                        : Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(
                                AppThemeConfig.inputBorderRadius),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                  AppThemeConfig.inputBorderRadius),
                              onTap: () {
                                setState(() {
                                  _cardTextEditMode = true;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.md),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant),
                                  borderRadius: BorderRadius.circular(
                                      AppThemeConfig.inputBorderRadius),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _cardTextController.text
                                                .trim()
                                                .isNotEmpty
                                            ? _cardTextController.text.trim()
                                            : appL10n.scanQrCodeToAddContact,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: _cardTextController.text
                                                      .trim()
                                                      .isNotEmpty
                                                  ? colorTheme.primaryTextColor
                                                  : colorTheme
                                                      .secondaryTextColor,
                                              fontStyle: _cardTextController
                                                      .text
                                                      .trim()
                                                      .isEmpty
                                                  ? FontStyle.italic
                                                  : FontStyle.normal,
                                            ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.edit_outlined,
                                      size: 16,
                                      color: colorTheme.secondaryTextColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                    AppSpacing.verticalMd,
                  ],
        ];

        // QR section, rendered standalone so it can be placed either on the
        // right (wide) or appended at the bottom of the column (narrow).
        final qrSection = Center(
                    child: LayoutBuilder(
                      builder: (context, qrConstraints) {
                        // Compute responsive QR dimensions preserving card aspect ratio (640:860)
                        final availWidth = qrConstraints.maxWidth.isFinite
                            ? qrConstraints.maxWidth
                            : 300.0;
                        final qrWidth =
                            (availWidth * (isWide ? 0.85 : 0.6)).clamp(160.0, 260.0);
                        final qrHeight =
                            qrWidth * (860.0 / 640.0); // aspect ratio ~1.344

                        return FutureBuilder<String>(
                          // Use version in key to force FutureBuilder to rebuild when version changes
                          // This ensures that even if the future object is the same, the FutureBuilder will rebuild
                          key: ValueKey(
                              'qr_${locale.languageCode}_v$_qrCardVersion'), // Force rebuild when locale or version changes
                          future: qrFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return SizedBox(
                                height: qrHeight,
                                width: qrWidth,
                                child: const Center(
                                    child: CircularProgressIndicator()),
                              );
                            }
                            if (!snapshot.hasData || snapshot.hasError) {
                              return SizedBox(
                                height: qrHeight,
                                width: qrWidth,
                                child: Center(
                                  child: Text(
                                    AppLocalizations.of(context)!
                                        .failedToLoadQr,
                                    style: TextStyle(color: colorTheme.error),
                                  ),
                                ),
                              );
                            }
                            final qrPath = snapshot.data!;
                            final outlinedStyle = OutlinedButton.styleFrom(
                              foregroundColor: colorTheme.primaryColor,
                              side: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    AppThemeConfig.buttonBorderRadius),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.lg,
                                  vertical: AppSpacing.sm),
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w500),
                            );
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surface,
                                    border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant),
                                    borderRadius: BorderRadius.circular(
                                        AppThemeConfig.cardBorderRadius),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                        AppThemeConfig.cardBorderRadius - 2),
                                    child: Image.file(
                                      File(qrPath),
                                      width: qrWidth,
                                      height: qrHeight,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                AppSpacing.verticalMd,
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    OutlinedButton.icon(
                                      style: outlinedStyle,
                                      icon: const Icon(Icons.download_rounded,
                                          size: 16),
                                      label: Text(appL10n.saveImage),
                                      onPressed: () => _handleSaveQr(
                                        primaryColor: colorTheme.primaryColor,
                                        textColor: colorTheme.primaryTextColor,
                                        locale: locale,
                                      ),
                                    ),
                                    AppSpacing.horizontalSm,
                                    OutlinedButton.icon(
                                      style: outlinedStyle,
                                      icon: const Icon(Icons.copy_rounded,
                                          size: 16),
                                      label: Text(appL10n.copy),
                                      onPressed: () => _copyQrImage(qrPath),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  );

        if (isWide) {
          return SizedBox(
            width: width,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: mainColumnChildren,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 280, child: qrSection),
              ],
            ),
          );
        }

        return SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (660.0)
                    .clamp(400.0, MediaQuery.sizeOf(context).height - 120),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [...mainColumnChildren, qrSection],
              ),
            ),
          ),
        );
      },
    );
  }
}
