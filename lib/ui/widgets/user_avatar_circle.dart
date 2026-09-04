import 'dart:io';

import 'package:flutter/material.dart';

/// The one circular "person" avatar used by every toxee-owned surface that
/// renders the self account (sidebar rail, mobile settings header, profile
/// page, login account picker, settings account cards).
///
/// Renders the avatar file when [avatarPath] points at an existing file, and
/// otherwise the initial letter on [backgroundColor]. Having a single fallback
/// is the point: before this widget each surface had its own — the sidebar
/// even fell back to the UIKit's stock "hand holding a phone" photo — so the
/// same account showed three different avatars on one screen.
///
/// Pure presentation: the parent owns the path lifecycle and passes the cached
/// existence check ([avatarFileExists]) so `build` never touches the
/// filesystem, plus [avatarVersion] to bust Flutter's image cache after the
/// file at the same path was rewritten.
class UserAvatarCircle extends StatelessWidget {
  const UserAvatarCircle({
    super.key,
    required this.size,
    required this.initial,
    required this.backgroundColor,
    required this.foregroundColor,
    this.avatarPath,
    this.avatarFileExists = false,
    this.avatarVersion = 0,
    this.border,
    this.textStyle,
  });

  /// Diameter in logical pixels.
  final double size;

  /// Fallback glyph, normally [initialFor] of the display name.
  final String initial;

  /// Circle fill behind the initial (ignored while the image renders).
  final Color backgroundColor;

  /// Colour of the initial glyph.
  final Color foregroundColor;

  final String? avatarPath;
  final bool avatarFileExists;
  final int avatarVersion;

  /// Optional ring drawn around both the image and the fallback.
  final BoxBorder? border;

  /// Overrides the default initial style (size-relative, semi-bold).
  final TextStyle? textStyle;

  /// Whether [avatarPath] will be rendered as an image.
  bool get hasImage =>
      avatarPath != null && avatarPath!.isNotEmpty && avatarFileExists;

  /// First character of [name], upper-cased; [fallback] when [name] is blank.
  static String initialFor(String? name, {String fallback = '?'}) {
    final trimmed = name?.trim() ?? '';
    return trimmed.isEmpty ? fallback : trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    // Decode at the on-screen pixel size instead of the source resolution so a
    // full-size photo doesn't cost a full-size decode for a 44pt circle.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheDim = (size * dpr).ceil();

    final fallback = Center(
      child: Text(
        initial,
        style:
            textStyle ??
            TextStyle(
              fontSize: size * 0.36,
              color: foregroundColor,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
      ),
    );

    final showImage = hasImage;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: showImage ? Colors.transparent : backgroundColor,
        border: border,
      ),
      child: showImage
          ? ClipOval(
              child: Image.file(
                File(avatarPath!),
                key: ValueKey('user-avatar-$avatarPath-$avatarVersion'),
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: cacheDim,
                cacheHeight: cacheDim,
                // A file that vanished or is not decodable degrades to the
                // same initial every other surface shows — never to a
                // broken-image glyph or a foreign placeholder.
                errorBuilder: (_, __, ___) => DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: backgroundColor,
                  ),
                  child: fallback,
                ),
              ),
            )
          : fallback,
    );
  }
}
