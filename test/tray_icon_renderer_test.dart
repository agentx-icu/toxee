import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/tray_icon_renderer.dart';

const _badge = ui.Color(0xFFE5484D);

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

Future<ui.Image> _asset(String path) =>
    _decode(File(path).readAsBytesSync());

Future<List<int>> _rgba(ui.Image image, int x, int y) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = (y * image.width + x) * 4;
  return [
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
    data.getUint8(i + 3),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TrayIconRenderer renderer;
  setUpAll(() async {
    renderer = TrayIconRenderer(
      colorIcon: await _asset('assets/tray/tray_color.png'),
      templateIcon: await _asset('assets/tray/tray_template.png'),
      badgeColor: _badge,
    );
  });

  group('badgeLabel', () {
    test('is empty without unread messages', () {
      expect(TrayIconRenderer.badgeLabel(0, 32), '');
    });
    test('caps at one digit on small icons', () {
      expect(TrayIconRenderer.badgeLabel(7, 16), '7');
      expect(TrayIconRenderer.badgeLabel(12, 16), '9+');
    });
    test('caps at 99+ on larger icons', () {
      expect(TrayIconRenderer.badgeLabel(42, 32), '42');
      expect(TrayIconRenderer.badgeLabel(123, 64), '99+');
    });
  });

  test('windows .ico holds one PNG per small-icon size', () async {
    final ico = await renderer.windowsIco(count: 3, online: true);
    final header = ByteData.sublistView(ico);
    expect(header.getUint16(0, Endian.little), 0);
    expect(header.getUint16(2, Endian.little), 1);
    const sizes = TrayIconRenderer.windowsIcoSizes;
    expect(header.getUint16(4, Endian.little), sizes.length);
    for (var i = 0; i < sizes.length; i++) {
      final base = 6 + 16 * i;
      expect(header.getUint8(base), sizes[i]);
      final length = header.getUint32(base + 8, Endian.little);
      final offset = header.getUint32(base + 12, Endian.little);
      final png = Uint8List.sublistView(ico, offset, offset + length);
      expect(png.sublist(1, 4), 'PNG'.codeUnits);
      final image = await _decode(png);
      expect(image.width, sizes[i]);
      expect(image.height, sizes[i]);
    }
  });

  test('offline colour icon is greyscale', () async {
    final image = await _decode(
        await renderer.colorPng(size: 64, count: 0, online: false));
    final px = await _rgba(image, 32, 20);
    expect(px[0], px[1]);
    expect(px[1], px[2]);
  });

  test('online colour icon keeps its colour', () async {
    final image = await _decode(
        await renderer.colorPng(size: 64, count: 0, online: true));
    final px = await _rgba(image, 32, 20);
    expect(px[0] == px[1] && px[1] == px[2], isFalse);
  });

  test('unread badge sits in the top-right corner', () async {
    final image = await _decode(
        await renderer.colorPng(size: 64, count: 5, online: true));
    // Right edge of the badge, vertically centred, clear of the label glyph.
    final px = await _rgba(image, 62, 18);
    expect(px, [0xE5, 0x48, 0x4D, 0xFF]);
  });

  test('mac template is pure black and dims when offline', () async {
    Future<int> maxAlpha(bool online) async {
      final image =
          await _decode(await renderer.macTemplatePng(online: online));
      expect(image.width, TrayIconRenderer.macTemplateSize);
      final data =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var max = 0;
      for (var i = 0; i < data.lengthInBytes; i += 4) {
        final a = data.getUint8(i + 3);
        if (a > 0) {
          // Premultiplied or not, a template carries no colour.
          expect(data.getUint8(i) + data.getUint8(i + 1) + data.getUint8(i + 2),
              0);
        }
        if (a > max) max = a;
      }
      return max;
    }

    final online = await maxAlpha(true);
    final offline = await maxAlpha(false);
    expect(online, 255);
    expect(offline, lessThan(128));
  });

  test('ico encoder writes 0 for a 256 px entry', () {
    final ico = TrayIconRenderer.encodeIco(
        [Uint8List.fromList(List.filled(8, 1))], [256]);
    expect(ico[6], 0);
    expect(ico[7], 0);
    expect(ico.length, 6 + 16 + 8);
  });
}
