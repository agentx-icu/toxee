import 'dart:io';
import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';

/// Renders the generated QR card image with save / copy actions below.
///
/// All theme / locale-derived inputs are passed in by [ProfilePage] so the
/// widget itself stays stateless and parent-driven.
class ProfileQrSection extends StatelessWidget {
  const ProfileQrSection({
    super.key,
    required this.qrFuture,
    required this.versionKey,
    required this.isWide,
    required this.primaryColor,
    required this.onSave,
    required this.onCopy,
  });

  final Future<String> qrFuture;
  final String versionKey;
  final bool isWide;
  final Color primaryColor;
  final VoidCallback onSave;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appL10n = AppLocalizations.of(context)!;
    return Center(
      child: LayoutBuilder(
        builder: (context, qrConstraints) {
          // Responsive QR dimensions preserving card aspect ratio (640:860).
          final availWidth = qrConstraints.maxWidth.isFinite
              ? qrConstraints.maxWidth
              : 300.0;
          final qrWidth =
              (availWidth * (isWide ? 0.85 : 0.6)).clamp(160.0, 260.0);
          final qrHeight = qrWidth * (860.0 / 640.0); // aspect ratio ~1.344

          return FutureBuilder<String>(
            key: ValueKey('qr_$versionKey'),
            future: qrFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return SizedBox(
                  height: qrHeight,
                  width: qrWidth,
                  child: const Center(child: CircularProgressIndicator()),
                );
              }
              if (!snapshot.hasData || snapshot.hasError) {
                return SizedBox(
                  height: qrHeight,
                  width: qrWidth,
                  child: Center(
                    child: Text(
                      appL10n.failedToLoadQr,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                );
              }
              final qrPath = snapshot.data!;
              final outlinedStyle = OutlinedButton.styleFrom(
                foregroundColor: primaryColor,
                side: BorderSide(color: theme.colorScheme.outlineVariant),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.button),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                textStyle: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w500),
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(AppRadii.card),
                    ),
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(AppRadii.card - 2),
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
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: Text(appL10n.saveImage),
                        onPressed: onSave,
                      ),
                      AppSpacing.horizontalSm,
                      OutlinedButton.icon(
                        style: outlinedStyle,
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: Text(appL10n.copy),
                        onPressed: () => onCopy(qrPath),
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
  }
}
