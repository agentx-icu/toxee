import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_bounded_image.dart';

import '../../util/app_theme_config.dart';

/// Shared utility methods for search UI components.
class SearchUtils {
  SearchUtils._();

  /// Builds a [CircleAvatar] that supports both `file://` paths and network URLs.
  /// Only shows [defaultChild] when there is no valid image (no overlay on avatar).
  static Widget avatarWidget(String? url, Widget defaultChild) {
    if (url == null || url.isEmpty) return CircleAvatar(child: defaultChild);
    final isLocalFile = url.startsWith('file://') || (url.startsWith('/') && !url.startsWith('//'));
    if (isLocalFile) {
      try {
        final path = url.startsWith('file://') ? url.substring(7) : url;
        // Decode sized for a small search-row avatar (96px covers up to 32pt
        // @ 3x DPR), keeping the aspect ratio for the cover crop —
        // `CircleAvatar.backgroundImage` doesn't expose cacheWidth/cacheHeight.
        return CircleAvatar(
          backgroundImage: TencentCloudChatBoundedImage(
            FileImage(File(path)),
            width: 96,
            height: 96,
            maxPixels: TencentCloudChatBoundedImage.defaultMaxPixelsFor(96, 96),
          ),
        );
      } catch (_) {
        return CircleAvatar(child: defaultChild);
      }
    }
    return CircleAvatar(backgroundImage: NetworkImage(url));
  }

  /// Builds rich text with [keyword] highlighted (case-insensitive).
  /// [maxLines] controls the maximum number of lines (default 1).
  static Widget buildHighlightedText(
    String text,
    String keyword,
    TextStyle baseStyle, {
    bool isDark = false,
    int maxLines = 1,
  }) {
    if (text.isEmpty || keyword.isEmpty) {
      return Text(text, style: baseStyle, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    }
    final lowerText = text.toLowerCase();
    final lowerKeyword = keyword.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final i = lowerText.indexOf(lowerKeyword, start);
      if (i < 0) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        }
        break;
      }
      if (i > start) {
        spans.add(TextSpan(text: text.substring(start, i), style: baseStyle));
      }
      // Highlight token sources from AppThemeConfig: yellow-200 in light mode
      // (gentle, classic search highlight), primary-tinted in dark mode (the
      // amber-on-slate combo was muddy — on-brand blue reads cleaner).
      spans.add(TextSpan(
        text: text.substring(i, i + keyword.length),
        style: baseStyle.copyWith(
          backgroundColor: isDark
              ? AppThemeConfig.searchHighlightColorDark
              : AppThemeConfig.searchHighlightColorLight,
          fontWeight: FontWeight.w600,
        ),
      ));
      start = i + keyword.length;
    }
    // Text.rich, not RichText: RichText ignores the system text scale (L11).
    return Text.rich(
      TextSpan(children: spans, style: baseStyle),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
