import 'dart:io';
import 'package:flutter/material.dart';

import '../../util/app_theme_config.dart';

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
    final bool hasCustomAvatar =
        avatarPath != null && avatarPath!.isNotEmpty && avatarFileExists;
    // 3× DPR target so the decoded image is sized for hi-DPI displays without
    // wasting memory on full-res source files.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheDim = (size * dpr).ceil();

    final Widget avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hasCustomAvatar ? Colors.transparent : primaryColor,
        border: Border.all(color: scheme.outlineVariant, width: 1),
      ),
      alignment: Alignment.center,
      child: hasCustomAvatar
          ? ClipOval(
              child: Image.file(
                File(avatarPath!),
                key: ValueKey('avatar-$avatarVersion'),
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: cacheDim,
                cacheHeight: cacheDim,
              ),
            )
          : Text(
              displayInitial,
              style: TextStyle(
                fontSize: size * 0.36,
                color: onPrimary,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
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
      stackChildren.add(PositionedDirectional(
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
      ));
    }

    if (isEditable) {
      stackChildren.add(PositionedDirectional(
        end: 0,
        bottom: 0,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
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
      ));
    }

    if (stackChildren.length == 1) {
      return avatar;
    }

    return Stack(clipBehavior: Clip.none, children: stackChildren);
  }
}
