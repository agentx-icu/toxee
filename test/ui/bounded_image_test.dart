// Checklist M6: large images must never be decoded at full resolution.
//
// `TencentCloudChatBoundedImage` (fork, tencent_cloud_chat_common) is the one
// decode bound used by chat bubbles, the full-screen viewer, UIKit / toxee
// avatars, the call avatar, the reply preview and the QR card. These tests pin
// its sizing math, its cache identity, its failure recovery, and that the
// toxee-owned surfaces actually use it.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_bounded_image.dart';
import 'package:toxee/call/call_avatar_controller.dart';
import 'package:toxee/call/call_ui_components.dart';
import 'package:toxee/ui/widgets/user_avatar_circle.dart';

typedef _Mode = TencentCloudChatBoundedImageMode;

(int?, int?) _target(
  int iw,
  int ih, {
  int? w,
  int? h,
  _Mode mode = _Mode.cover,
  required int maxPixels,
}) {
  final t = TencentCloudChatBoundedImage.targetSize(
    intrinsicWidth: iw,
    intrinsicHeight: ih,
    width: w,
    height: h,
    mode: mode,
    maxPixels: maxPixels,
  );
  return (t.width, t.height);
}

Future<File> _writePng(Directory dir, String name, int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366CC),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
  return file;
}

/// Resolves [provider] and returns the decoded frame's size (or the error).
Future<Object> _decode(ImageProvider provider) async {
  final stream = provider.resolve(ImageConfiguration.empty);
  final done = Completer<Object>();
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!done.isCompleted) {
        done.complete(Size(info.image.width.toDouble(), info.image.height.toDouble()));
      }
    },
    onError: (e, _) {
      if (!done.isCompleted) done.complete(e);
    },
  );
  stream.addListener(listener);
  final result = await done.future.timeout(const Duration(seconds: 10));
  stream.removeListener(listener);
  return result;
}

void main() {
  group('targetSize math', () {
    test('cover keeps the aspect ratio and covers both sides', () {
      // A 4000x3000 photo in a 120 px avatar: short side = 120.
      expect(_target(4000, 3000, w: 120, h: 120, maxPixels: 1 << 20), (160, 120));
      expect(_target(3000, 4000, w: 120, h: 120, maxPixels: 1 << 20), (120, 160));
    });

    test('fit keeps the whole image inside the box', () {
      // 48 MP photo in the viewer's 4096 box.
      expect(
        _target(8064, 6048, w: 4096, h: 4096, mode: _Mode.fit, maxPixels: 16 << 20),
        (4096, 3072),
      );
    });

    test('never upscales', () {
      expect(_target(50, 40, w: 120, h: 120, maxPixels: 1 << 20), (null, null));
    });

    test('the pixel ceiling bounds extreme aspect ratios', () {
      // A 500x16000 strip in a ~594 px bubble would need 8 MP; capped at 2 MP.
      final (w, h) = _target(500, 16000, w: 594, maxPixels: 2 << 20);
      expect(w! * h!, lessThanOrEqualTo(2 << 20));
      expect((w / h - 500 / 16000).abs(), lessThan(0.001));
    });

    test('a sub-pixel side is clamped to 1 px and the ceiling still holds', () {
      final (w, h) = _target(1, 1000000, w: 120, h: 120, maxPixels: 65536);
      expect((w, h), (1, 65536));
    });

    test('default ceiling scales with the box and stays in range', () {
      expect(TencentCloudChatBoundedImage.defaultMaxPixelsFor(96, 96), 64 * 1024);
      expect(
        TencentCloudChatBoundedImage.defaultMaxPixelsFor(4000, 4000),
        4 * 1024 * 1024,
      );
    });
  });

  group('provider identity', () {
    test('equality covers every sizing parameter', () {
      final base = TencentCloudChatBoundedImage(
        FileImage(File('/a.png')),
        width: 10,
        height: 10,
        maxPixels: 100,
      );
      expect(
        base,
        TencentCloudChatBoundedImage(
          FileImage(File('/a.png')),
          width: 10,
          height: 10,
          maxPixels: 100,
        ),
      );
      expect(
        base == TencentCloudChatBoundedImage(FileImage(File('/a.png')), width: 10, height: 10, maxPixels: 99),
        isFalse,
      );
      expect(
        base ==
            TencentCloudChatBoundedImage(
              FileImage(File('/a.png')),
              width: 10,
              height: 10,
              mode: _Mode.fit,
              maxPixels: 100,
            ),
        isFalse,
      );
    });
  });

  group('real decode', () {
    testWidgets('decodes at the bounded size, not the file size', (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('toxee_bounded_');
        addTearDown(() => dir.delete(recursive: true));
        final file = await _writePng(dir, 'big.png', 1200, 800);
        final size = await _decode(
          TencentCloudChatBoundedImage.file(
            file.path,
            logicalWidth: 60,
            logicalHeight: 60,
            devicePixelRatio: 2,
          ),
        );
        // Cover 120x120 of a 3:2 image: 180x120.
        expect(size, const Size(180, 120));
      });
    });

    testWidgets('a failed decode is evicted, so the file can recover', (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('toxee_bounded_');
        addTearDown(() => dir.delete(recursive: true));
        final path = '${dir.path}/late.png';
        final provider = TencentCloudChatBoundedImage.file(
          path,
          logicalWidth: 50,
          logicalHeight: 50,
          devicePixelRatio: 1,
        );
        // Half-written / missing file: the decode fails.
        await File(path).writeAsBytes(<int>[1, 2, 3], flush: true);
        expect(await _decode(provider), isNot(isA<Size>()));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        // The bubble's retry re-resolves once the transfer finished.
        await _writePng(dir, 'late.png', 200, 100);
        expect(await _decode(provider), const Size(100, 50));
      });
    });

    testWidgets('a file rewritten at the same path is a new cache entry', (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('toxee_bounded_');
        addTearDown(() => dir.delete(recursive: true));
        final provider = TencentCloudChatBoundedImage.file(
          '${dir.path}/avatar.png',
          logicalWidth: 40,
          logicalHeight: 40,
          devicePixelRatio: 1,
        );
        await _writePng(dir, 'avatar.png', 80, 80);
        expect(await _decode(provider), const Size(40, 40));
        // A new avatar at the same path (different size and mtime).
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        await _writePng(dir, 'avatar.png', 160, 80);
        expect(await _decode(provider), const Size(80, 40));
      });
    });
  });

  group('toxee surfaces use the bound', () {
    testWidgets('UserAvatarCircle decodes at its physical size', (tester) async {
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: UserAvatarCircle(
            size: 44,
            initial: 'R',
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            avatarPath: '/nonexistent/avatar.png',
            avatarFileExists: true,
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image)).image;
      expect(image, isA<TencentCloudChatBoundedImage>());
      final bounded = image as TencentCloudChatBoundedImage;
      expect((bounded.width, bounded.height), (132, 132));
      expect(bounded.mode, _Mode.cover);
    });

    testWidgets('the call avatar decodes at its physical size', (tester) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = CallAvatarController(
        loadPath: (_) async => '/nonexistent/peer.png',
        fileExists: (_) async => true,
      );
      addTearDown(controller.dispose);
      await controller.loadForUser('peer');
      await tester.pumpWidget(
        MaterialApp(
          home: CallUserAvatar(
            userId: 'peer',
            controller: controller,
            name: 'Peer',
            radius: 50,
            fontSize: 20,
          ),
        ),
      );
      await tester.pump();
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      final image = avatar.backgroundImage;
      expect(image, isA<TencentCloudChatBoundedImage>());
      final bounded = image as TencentCloudChatBoundedImage;
      expect((bounded.width, bounded.height), (200, 200));
    });
  });
}
