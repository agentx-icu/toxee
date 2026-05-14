import 'package:flutter/material.dart';
import '../../util/app_spacing.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import '../../util/app_theme_config.dart';
import '../../util/qr_card_generator.dart';

/// Generate composite contact card (avatar + nickname + QR + caption)
Future<String> generateContactCardImage({
  required String userId,
  required String displayName,
  required Locale locale,
  required String bottomText,
  Color primaryColor = AppThemeConfig.primaryColor,
  Color textColor = AppThemeConfig.primaryTextColorLight,
  String? avatarPath,
}) {
  return ContactQrCardGenerator.generateTempCard(
    userId: userId,
    displayName: displayName,
    locale: locale,
    bottomText: bottomText,
    primaryColor: primaryColor,
    textColor: textColor,
    avatarPath: avatarPath,
  );
}

/// Prompt user for text input
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String? actionLabel,
}) async {
  final controller = TextEditingController();
  String? result;
  await showDialog<String>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
        ),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textAlignVertical: TextAlignVertical.center,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
              borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
              borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
              borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
          ),
          minLines: 1,
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              TencentCloudChatLocalizations.of(context)?.cancel ?? 'Cancel',
            ),
          ),
          AppSpacing.horizontalSm,
          ElevatedButton(
            onPressed: () {
              result = controller.text;
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
              ),
            ),
            child: Text(
              actionLabel ?? (TencentCloudChatLocalizations.of(context)?.tuiEmojiOk ?? 'OK'),
            ),
          ),
        ],
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.md,
        ),
      );
    },
  );
  return result;
}

