import 'package:flutter/material.dart';

import '../../util/app_theme_config.dart';
import '../testing/ui_keys.dart';
import '../widgets/user_avatar_circle.dart';

/// Circular avatar with optional online dot + camera-edit affordance.
///
/// Pure presentation — parent owns the avatar path lifecycle and supplies
/// callbacks for tapping the photo / camera button.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.size,
    required this.primaryColor,
    required this.onPrimary,
    required this.displayInitial,
    required this.avatarPath,
    required this.avatarFileExists,
    required this.avatarVersion,
    this.isEditable = false,
    this.showOnlineDot = false,
    this.isConnected = false,
    this.onTap,
  });

  final double size;
  final Color primaryColor;
  final Color onPrimary;
  final String displayInitial;
  final String? avatarPath;
  final bool avatarFileExists;
  final int avatarVersion;
  final bool isEditable;
  final bool showOnlineDot;
  final bool isConnected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The circle itself is the shared self-avatar widget, so this page can
    // never drift from the sidebar / settings / login fallback again.
    final Widget avatar = UserAvatarCircle(
      size: size,
      initial: displayInitial,
      backgroundColor: primaryColor,
      foregroundColor: onPrimary,
      avatarPath: avatarPath,
      avatarFileExists: avatarFileExists,
      avatarVersion: avatarVersion,
      border: Border.all(color: scheme.outlineVariant, width: 1),
    );

    final stackChildren = <Widget>[
      if (isEditable)
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(onTap: onTap, child: avatar),
        )
      else
        avatar,
    ];

    if (showOnlineDot) {
      stackChildren.add(
        PositionedDirectional(
          end: 2,
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
        ),
      );
    }

    if (isEditable) {
      stackChildren.add(
        PositionedDirectional(
          end: 0,
          bottom: 0,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: UiKeys.profileAvatarEditButton,
              onTap: onTap,
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
        ),
      );
    }

    if (stackChildren.length == 1) {
      return avatar;
    }

    return Stack(clipBehavior: Clip.none, children: stackChildren);
  }
}
