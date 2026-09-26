// Guards the platform constraints on the generated icon and avatar files
// (tool/branding/generate_brand_assets.py). Each of these was broken before:
// the iOS/macOS/Android icons were opaque RGB with a fake transparency
// checkerboard painted in, the Windows .ico held a single 256 px image, and
// the default group avatar was a 960 KB RGB image with white corners.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

class _Png {
  _Png(this.width, this.height, this.colorType);
  final int width;
  final int height;
  final int colorType; // 2 = RGB, 6 = RGBA

  bool get hasAlpha => colorType == 4 || colorType == 6;

  static _Png read(String path) => parse(File(path).readAsBytesSync());

  static _Png parse(Uint8List bytes) {
    expect(bytes.sublist(1, 4), 'PNG'.codeUnits, reason: 'not a PNG');
    final d = ByteData.sublistView(bytes);
    return _Png(d.getUint32(16), d.getUint32(20), d.getUint8(25));
  }
}

void main() {
  const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  const mac = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
  const res = 'android/app/src/main/res';

  test('iOS icons are opaque and match Contents.json', () {
    final contents = jsonDecode(File('$ios/Contents.json').readAsStringSync())
        as Map<String, dynamic>;
    for (final raw in contents['images'] as List) {
      final entry = raw as Map<String, dynamic>;
      final points = double.parse((entry['size'] as String).split('x').first);
      final scale = int.parse((entry['scale'] as String).replaceAll('x', ''));
      final png = _Png.read('$ios/${entry['filename']}');
      expect(png.width, (points * scale).round(), reason: entry['filename']);
      // App Store Connect rejects an app icon with an alpha channel.
      expect(png.hasAlpha, isFalse, reason: entry['filename']);
    }
  });

  test('macOS icons keep transparent corners (Big Sur grid)', () {
    for (final size in [16, 32, 64, 128, 256, 512, 1024]) {
      final png = _Png.read('$mac/app_icon_$size.png');
      expect(png.width, size);
      expect(png.hasAlpha, isTrue, reason: 'app_icon_$size.png');
    }
  });

  test('Android ships adaptive, round, themed and status-bar icons', () {
    const densities = {
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    };
    densities.forEach((d, k) {
      expect(_Png.read('$res/mipmap-$d/ic_launcher.png').width,
          (48 * k).round());
      expect(_Png.read('$res/mipmap-$d/ic_launcher_round.png').hasAlpha,
          isTrue);
      for (final layer in ['foreground', 'background', 'monochrome']) {
        expect(_Png.read('$res/mipmap-$d/ic_launcher_$layer.png').width,
            (108 * k).round());
      }
      expect(_Png.read('$res/drawable-$d/ic_stat_toxee.png').width,
          (24 * k).round());
    });
    for (final name in ['ic_launcher', 'ic_launcher_round']) {
      final xml =
          File('$res/mipmap-anydpi-v26/$name.xml').readAsStringSync();
      expect(xml, contains('@mipmap/ic_launcher_monochrome'));
    }
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher_round"'));
  });

  test('Windows .ico carries the small sizes the shell asks for', () {
    final ico = File('windows/runner/resources/app_icon.ico').readAsBytesSync();
    final d = ByteData.sublistView(ico);
    final count = d.getUint16(4, Endian.little);
    final sizes = [
      for (var i = 0; i < count; i++)
        d.getUint8(6 + 16 * i) == 0 ? 256 : d.getUint8(6 + 16 * i),
    ];
    expect(sizes, containsAll([16, 20, 24, 32, 48, 256]));
  });

  test('Linux hicolor theme has every size plus scalable', () {
    for (final size in [16, 24, 32, 48, 64, 128, 256, 512]) {
      expect(
          _Png.read('linux/icons/hicolor/${size}x$size/apps/toxee.png').width,
          size);
    }
    expect(File('linux/icons/hicolor/scalable/apps/toxee.svg').existsSync(),
        isTrue);
  });

  test('default avatars are small, square and full-bleed', () {
    for (final name in ['default_user', 'default_contact', 'default_group']) {
      final path = 'assets/avatars/$name.png';
      final png = _Png.read(path);
      expect(png.width, png.height, reason: path);
      expect(png.width, 512, reason: path);
      // The self avatar is pushed to friends over Tox, whose avatar
      // transfer is capped at 64 KiB.
      expect(File(path).lengthSync(), lessThan(64 * 1024), reason: path);
    }
  });

  test('tray art exists', () {
    expect(_Png.read('assets/tray/tray_color.png').hasAlpha, isTrue);
    expect(_Png.read('assets/tray/tray_template.png').hasAlpha, isTrue);
  });
}
