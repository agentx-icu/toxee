import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/bootstrap/desktop_window_geometry.dart';

void main() {
  const primary = Rect.fromLTWH(0, 0, 1440, 900);
  test('disconnected-monitor bounds fall back to centered default', () {
    expect(
      restoreDesktopBounds(const Rect.fromLTWH(2000, 100, 1000, 700), [
        primary,
      ]),
      isNull,
    );
  });
  test('valid negative monitor coordinates are restored', () {
    const saved = Rect.fromLTWH(-1600, -200, 1000, 700);
    expect(
      restoreDesktopBounds(saved, [
        primary,
        const Rect.fromLTWH(-1920, -300, 1920, 1080),
      ]),
      saved,
    );
  });
  test('sliver overlap is not a reachable caption', () {
    expect(
      restoreDesktopBounds(const Rect.fromLTWH(1439, 0, 1000, 700), [primary]),
      isNull,
    );
  });
  test('window on remaining display fits a smaller work area', () {
    expect(
      restoreDesktopBounds(const Rect.fromLTWH(20, 20, 1800, 1000), [primary]),
      primary,
    );
  });
  test(
    'headless display lookup failure never restores arbitrary coordinates',
    () {
      expect(
        restoreDesktopBounds(const Rect.fromLTWH(0, 0, 1000, 700), []),
        isNull,
      );
    },
  );
}
