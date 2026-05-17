import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';

/// Calculate text length where Chinese characters count as 1, and
/// letters/numbers count as 0.5.
double profileTextLength(String text) {
  double length = 0;
  for (int i = 0; i < text.length; i++) {
    final char = text[i];
    if (char.codeUnitAt(0) >= 0x4E00 && char.codeUnitAt(0) <= 0x9FFF) {
      length += 1.0;
    } else if (RegExp(r'[a-zA-Z0-9]').hasMatch(char)) {
      length += 0.5;
    } else {
      length += 0.5;
    }
  }
  return length;
}

/// Editable nickname + status fields with a save button. Used inline inside
/// the profile page when the user toggles edit mode.
class ProfileEditFields extends StatelessWidget {
  const ProfileEditFields({
    super.key,
    required this.nickController,
    required this.statusController,
    required this.isSaving,
    required this.primaryColor,
    required this.onPrimary,
    required this.nicknameLabel,
    required this.statusLabel,
    required this.saveLabel,
    required this.cancelLabel,
    required this.nicknameTooLong,
    required this.statusTooLong,
    required this.onCancel,
    required this.onSave,
    required this.onAnyFieldChanged,
  });

  final TextEditingController nickController;
  final TextEditingController statusController;
  final bool isSaving;
  final Color primaryColor;
  final Color onPrimary;
  final String nicknameLabel;
  final String statusLabel;
  final String saveLabel;
  final String cancelLabel;
  final String nicknameTooLong;
  final String statusTooLong;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final VoidCallback onAnyFieldChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nickOver = profileTextLength(nickController.text) > 12;
    final statusOver = profileTextLength(statusController.text) > 24;
    final saveDisabled = isSaving || nickOver || statusOver;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSpacing.verticalMd,
        TextField(
          controller: nickController,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            labelText: nicknameLabel,
            errorText: nickOver ? nicknameTooLong : null,
          ),
          maxLength: 24,
          onChanged: (_) => onAnyFieldChanged(),
        ),
        AppSpacing.verticalMd,
        TextField(
          controller: statusController,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            labelText: statusLabel,
            errorText: statusOver ? statusTooLong : null,
          ),
          minLines: 1,
          maxLines: 3,
          maxLength: 48,
          onChanged: (_) => onAnyFieldChanged(),
        ),
        AppSpacing.verticalMd,
        Row(
          children: [
            TextButton(
              onPressed: isSaving ? null : onCancel,
              child: Text(cancelLabel),
            ),
            AppSpacing.horizontalSm,
            Expanded(
              child: SizedBox(
                height: 44,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: onPrimary,
                    disabledBackgroundColor:
                        primaryColor.withValues(alpha: 0.4),
                    disabledForegroundColor: onPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.button),
                    ),
                    textStyle: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  onPressed: saveDisabled ? null : onSave,
                  child: isSaving
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(onPrimary),
                          ),
                        )
                      : Text(saveLabel),
                ),
              ),
            ),
          ],
        ),
        AppSpacing.verticalSm,
      ],
    );
  }
}

/// Inline card-text input + "view-mode pill" used for the QR card's bottom
/// caption. Click the pill to enter edit mode; submit/enter saves.
class ProfileCardTextField extends StatelessWidget {
  const ProfileCardTextField({
    super.key,
    required this.controller,
    required this.editMode,
    required this.primaryColor,
    required this.onPrimary,
    required this.secondaryTextColor,
    required this.primaryTextColor,
    required this.onEnterEditMode,
    required this.onSave,
    required this.placeholderText,
    required this.labelText,
    required this.generateLabel,
  });

  final TextEditingController controller;
  final bool editMode;
  final Color primaryColor;
  final Color onPrimary;
  final Color secondaryTextColor;
  final Color primaryTextColor;
  final VoidCallback onEnterEditMode;
  final VoidCallback onSave;
  final String placeholderText;
  final String labelText;
  final String generateLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (editMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              labelText: labelText,
              hintText: placeholderText,
            ),
            maxLines: 2,
            autofocus: true,
            onSubmitted: (_) => onSave(),
            onEditingComplete: onSave,
          ),
          AppSpacing.verticalSm,
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: onPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.button),
                ),
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(generateLabel),
              onPressed: onSave,
            ),
          ),
        ],
      );
    }
    final showsPlaceholder = controller.text.trim().isEmpty;
    final text = showsPlaceholder ? placeholderText : controller.text.trim();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.input),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.input),
          onTap: onEnterEditMode,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(AppRadii.input),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: showsPlaceholder
                          ? secondaryTextColor
                          : primaryTextColor,
                      fontStyle: showsPlaceholder
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ),
                Icon(Icons.edit_outlined, size: 16, color: secondaryTextColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tox-ID display row + monospace SelectableText panel + copy button.
class ProfileToxIdSection extends StatelessWidget {
  const ProfileToxIdSection({
    super.key,
    required this.userId,
    required this.label,
    required this.copyLabel,
    required this.primaryColor,
    required this.secondaryTextColor,
    required this.primaryTextColor,
    required this.onCopy,
  });

  final String userId;
  final String label;
  final String copyLabel;
  final Color primaryColor;
  final Color secondaryTextColor;
  final Color primaryTextColor;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: secondaryTextColor,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: primaryColor,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.button),
                ),
              ),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: Text(copyLabel),
              onPressed: onCopy,
            ),
          ],
        ),
        AppSpacing.verticalXs,
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.4),
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppRadii.input),
          ),
          // Pin LTR so RTL locales don't visually reorder the hex Tox ID.
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(
              userId,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                color: primaryTextColor,
                letterSpacing: 0.2,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Connection-status dot + label (Online / Offline).
class ProfileConnectionStatus extends StatelessWidget {
  const ProfileConnectionStatus({
    super.key,
    required this.isConnected,
    required this.onlineLabel,
    required this.offlineLabel,
    required this.primaryTextColor,
  });

  final bool isConnected;
  final String onlineLabel;
  final String offlineLabel;
  final Color primaryTextColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isConnected
                ? AppThemeConfig.successColor
                : (theme.brightness == Brightness.dark
                    ? AppThemeConfig.secondaryTextColorDark
                    : AppThemeConfig.secondaryTextColorLight),
            shape: BoxShape.circle,
          ),
        ),
        AppSpacing.horizontalSm,
        Text(
          isConnected ? onlineLabel : offlineLabel,
          style: theme.textTheme.labelMedium?.copyWith(
            color: primaryTextColor,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

/// Prominent "Send message / Start chat" action used on peer (non-editable)
/// profile pages. Full-width on mobile, max 280 on wide layouts via parent
/// constraints.
class ProfileChatButton extends StatelessWidget {
  const ProfileChatButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    final button = FilledButton.icon(
      icon: const Icon(Icons.chat_bubble_outline, size: 18),
      label: Text(label),
      onPressed: onPressed,
    );
    if (isWide) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: SizedBox(width: 280, height: 44, child: button),
      );
    }
    return SizedBox(width: double.infinity, height: 44, child: button);
  }
}

/// Convenience re-export so callers only import this file.
AppLocalizations? profileL10n(BuildContext context) =>
    AppLocalizations.of(context);
