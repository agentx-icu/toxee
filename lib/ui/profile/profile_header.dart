import 'package:flutter/material.dart';

import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';
import 'profile_avatar.dart';
import 'profile_edit_fields.dart';

/// Top-of-page composition: avatar on the left, nickname + status on the
/// right, and (in editable mode) the expandable edit fields below.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.displayName,
    required this.displayInitial,
    required this.statusText,
    required this.isEditable,
    required this.editMode,
    required this.isConnected,
    required this.primaryColor,
    required this.onPrimary,
    required this.primaryTextColor,
    required this.secondaryTextColor,
    required this.avatarPath,
    required this.avatarFileExists,
    required this.avatarVersion,
    required this.onAvatarTap,
    required this.onToggleEdit,
    required this.editFields,
    required this.onlineLabel,
    required this.offlineLabel,
    required this.editTooltip,
    required this.cancelTooltip,
  });

  final String displayName;
  final String displayInitial;
  final String statusText;
  final bool isEditable;
  final bool editMode;
  final bool isConnected;
  final Color primaryColor;
  final Color onPrimary;
  final Color primaryTextColor;
  final Color secondaryTextColor;
  final String? avatarPath;
  final bool avatarFileExists;
  final int avatarVersion;
  final VoidCallback onAvatarTap;
  final VoidCallback onToggleEdit;
  final Widget? editFields;
  final String onlineLabel;
  final String offlineLabel;
  final String editTooltip;
  final String cancelTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileAvatar(
          size: 96,
          primaryColor: primaryColor,
          onPrimary: onPrimary,
          displayInitial: displayInitial,
          avatarPath: avatarPath,
          avatarFileExists: avatarFileExists,
          avatarVersion: avatarVersion,
          isEditable: isEditable,
          showOnlineDot: true,
          isConnected: isConnected,
          onTap: onAvatarTap,
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        AppSpacing.verticalXs,
                        Text(
                          statusText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isEditable)
                    IconButton(
                      icon: Icon(editMode ? Icons.close : Icons.edit, size: 20),
                      tooltip: editMode ? cancelTooltip : editTooltip,
                      onPressed: onToggleEdit,
                    ),
                ],
              ),
              AnimatedSize(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : AppDurations.medium,
                curve: AppCurves.standard,
                alignment: Alignment.topCenter,
                child: editMode && editFields != null
                    ? editFields!
                    : const SizedBox(width: double.infinity),
              ),
              ProfileConnectionStatus(
                isConnected: isConnected,
                onlineLabel: onlineLabel,
                offlineLabel: offlineLabel,
                primaryTextColor: primaryTextColor,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

