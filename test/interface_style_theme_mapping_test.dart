import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/app_theme_data.dart';
import 'package:toxee/util/app_theme_config.dart';
import 'package:toxee/util/interface_style.dart';

void main() {
  for (final style in InterfaceStyle.values) {
    for (final brightness in Brightness.values) {
      test('$style $brightness maps Material and UIKit to one identity', () {
        final palette = style.palette(brightness);
        final material = brightness == Brightness.light
            ? buildLightTheme(style: style)
            : buildDarkTheme(style: style);
        final model = AppThemeConfig.createYouthfulThemeModel(style: style);
        final uikit = brightness == Brightness.light
            ? model.lightTheme
            : model.darkTheme;
        expect(material.colorScheme.primary, palette.primary);
        expect(material.colorScheme.onPrimary, palette.onPrimary);
        expect(material.scaffoldBackgroundColor, palette.canvas);
        expect(uikit.primaryColor, palette.primary);
        expect(uikit.onPrimary, palette.onPrimary);
        expect(uikit.selfMessageBubbleColor, palette.sent);
        expect(uikit.othersMessageTextColor, palette.receivedText);
        expect(uikit.conversationItemLastMessageTextColor, palette.muted);
        expect(model.visualStyle.bubbleRadius, style.geometry.bubbleRadius);
        final shape = material.cardTheme.shape! as RoundedRectangleBorder;
        expect(
          shape.borderRadius,
          BorderRadius.circular(style.geometry.panelRadius),
        );
      });
    }
  }
  for (final style in InterfaceStyle.values.where(
    (style) => style != InterfaceStyle.classic,
  )) {
    for (final brightness in Brightness.values) {
      test('$style $brightness retains required contrast in real tokens', () {
        final p = style.palette(brightness);
        double contrast(Color foreground, Color background) {
          final a = foreground.computeLuminance(),
              b = background.computeLuminance();
          return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
        }

        for (final surface in [
          p.canvas,
          p.panel,
          p.rail,
          p.selected,
          p.sent,
          p.received,
        ]) {
          expect(contrast(p.text, surface), greaterThanOrEqualTo(4.5));
          expect(contrast(p.muted, surface), greaterThanOrEqualTo(4.5));
        }
        expect(contrast(p.onPrimary, p.primary), greaterThanOrEqualTo(4.5));
        expect(contrast(p.onUnread, p.unread), greaterThanOrEqualTo(4.5));
        for (final surface in [p.canvas, p.panel]) {
          expect(contrast(p.controlBorder, surface), greaterThanOrEqualTo(3));
          expect(contrast(p.link, surface), greaterThanOrEqualTo(4.5));
        }
      });
    }
  }
}
