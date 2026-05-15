import 'dart:io' show File;

import 'package:flutter/material.dart';

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
        // Wrap in ResizeImage so the decoded raster is sized for a small
        // search-row avatar — `CircleAvatar.backgroundImage` doesn't expose
        // cacheWidth/cacheHeight directly. 96px covers up to 32pt @ 3× DPR.
        return CircleAvatar(
          backgroundImage: ResizeImage(
            FileImage(File(path)),
            width: 96,
            height: 96,
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
    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans, style: baseStyle),
    );
  }
}
