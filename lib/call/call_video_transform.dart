import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

/// Converts BGRA8888 (single plane, 4 bytes per pixel) to YUV420 (I420).
/// Used on macOS where camera_macos may expose image stream as BGRA/ARGB.
class RgbToYuv420 {
  RgbToYuv420._();

  /// [bgra] is one plane: B, G, R, A per pixel; [bytesPerRow] defaults to width * 4.
  static ({Uint8List y, Uint8List u, Uint8List v}) bgra8888ToYuv420({
    required Uint8List bgra,
    required int width,
    required int height,
    int? bytesPerRow,
  }) {
    final stride = bytesPerRow ?? width * 4;
    final y = Uint8List(width * height);
    final uvWidth = width ~/ 2;
    final uvHeight = height ~/ 2;
    final u = Uint8List(uvWidth * uvHeight);
    final v = Uint8List(uvWidth * uvHeight);

    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        final i = row * stride + col * 4;
        if (i + 3 >= bgra.length) break;
        final b = bgra[i].toDouble();
        final g = bgra[i + 1].toDouble();
        final r = bgra[i + 2].toDouble();
        // BT.601
        final yVal = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
        final cb = (128 - 0.169 * r - 0.331 * g + 0.5 * b).round().clamp(0, 255);
        final cr = (128 + 0.5 * r - 0.419 * g - 0.081 * b).round().clamp(0, 255);
        y[row * width + col] = yVal;
        if (row.isEven && col.isEven) {
          final uvIndex = (row ~/ 2) * uvWidth + (col ~/ 2);
          u[uvIndex] = cb;
          v[uvIndex] = cr;
        }
      }
    }
    return (y: y, u: u, v: v);
  }

  /// [argb] is one plane: A, R, G, B per pixel (e.g. camera_macos stream).
  static ({Uint8List y, Uint8List u, Uint8List v}) argb8888ToYuv420({
    required Uint8List argb,
    required int width,
    required int height,
    int? bytesPerRow,
  }) {
    final stride = bytesPerRow ?? width * 4;
    final y = Uint8List(width * height);
    final uvWidth = width ~/ 2;
    final uvHeight = height ~/ 2;
    final u = Uint8List(uvWidth * uvHeight);
    final v = Uint8List(uvWidth * uvHeight);

    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        final i = row * stride + col * 4;
        if (i + 3 >= argb.length) break;
        final r = argb[i + 1].toDouble();
        final g = argb[i + 2].toDouble();
        final b = argb[i + 3].toDouble();
        final yVal = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
        final cb = (128 - 0.169 * r - 0.331 * g + 0.5 * b).round().clamp(0, 255);
        final cr = (128 + 0.5 * r - 0.419 * g - 0.081 * b).round().clamp(0, 255);
        y[row * width + col] = yVal;
        if (row.isEven && col.isEven) {
          final uvIndex = (row ~/ 2) * uvWidth + (col ~/ 2);
          u[uvIndex] = cb;
          v[uvIndex] = cr;
        }
      }
    }
    return (y: y, u: u, v: v);
  }
}

class TransformedI420Frame {
  final Uint8List y;
  final Uint8List u;
  final Uint8List v;
  final int width;
  final int height;

  const TransformedI420Frame({
    required this.y,
    required this.u,
    required this.v,
    required this.width,
    required this.height,
  });
}

class OutgoingVideoTransform {
  final int quarterTurns;
  final bool shouldMirror;

  const OutgoingVideoTransform({
    required this.quarterTurns,
    required this.shouldMirror,
  });

  static OutgoingVideoTransform compute({
    required TargetPlatform platform,
    required DeviceOrientation deviceOrientation,
    required CameraDescription camera,
  }) {
    if (platform != TargetPlatform.android) {
      // iOS / macOS / Linux / Windows: the camera plugin delivers frames
      // pre-rotated to portraitUp via the underlying AVFoundation /
      // platform pipeline, so a second client-side rotation would
      // double-rotate. If a future iPad/iPhone variant ever delivers
      // unrotated frames (e.g. some external accessory cameras), surface a
      // dedicated platform path here rather than enabling Android's
      // sensor-orientation math by accident.
      return const OutgoingVideoTransform(
        quarterTurns: 0,
        shouldMirror: false,
      );
    }

    final deviceDegrees = switch (deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };

    final rotationDegrees = switch (camera.lensDirection) {
      CameraLensDirection.front =>
        (camera.sensorOrientation + deviceDegrees) % 360,
      _ => (camera.sensorOrientation - deviceDegrees + 360) % 360,
    };

    return OutgoingVideoTransform(
      quarterTurns: rotationDegrees ~/ 90,
      shouldMirror: false,
    );
  }
}

class I420FrameTransformer {
  const I420FrameTransformer._();

  static TransformedI420Frame apply({
    required Uint8List y,
    required Uint8List u,
    required Uint8List v,
    required int width,
    required int height,
    required int quarterTurns,
  }) {
    final normalizedQuarterTurns = quarterTurns % 4;
    if (normalizedQuarterTurns == 0) {
      return TransformedI420Frame(
        y: y,
        u: u,
        v: v,
        width: width,
        height: height,
      );
    }

    final rotatedY = _rotatePlane(
      plane: y,
      width: width,
      height: height,
      quarterTurns: normalizedQuarterTurns,
    );
    final chromaWidth = width ~/ 2;
    final chromaHeight = height ~/ 2;
    final rotatedU = _rotatePlane(
      plane: u,
      width: chromaWidth,
      height: chromaHeight,
      quarterTurns: normalizedQuarterTurns,
    );
    final rotatedV = _rotatePlane(
      plane: v,
      width: chromaWidth,
      height: chromaHeight,
      quarterTurns: normalizedQuarterTurns,
    );

    return TransformedI420Frame(
      y: rotatedY,
      u: rotatedU,
      v: rotatedV,
      width: normalizedQuarterTurns.isOdd ? height : width,
      height: normalizedQuarterTurns.isOdd ? width : height,
    );
  }

  static Uint8List _rotatePlane({
    required Uint8List plane,
    required int width,
    required int height,
    required int quarterTurns,
  }) {
    final output = Uint8List((quarterTurns.isOdd ? height : width) *
        (quarterTurns.isOdd ? width : height));
    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        final sourceIndex = row * width + col;
        late final int destRow;
        late final int destCol;
        switch (quarterTurns) {
          case 1:
            destRow = col;
            destCol = height - row - 1;
            break;
          case 2:
            destRow = height - row - 1;
            destCol = width - col - 1;
            break;
          case 3:
            destRow = width - col - 1;
            destCol = row;
            break;
          default:
            destRow = row;
            destCol = col;
            break;
        }
        final destWidth = quarterTurns.isOdd ? height : width;
        final destIndex = destRow * destWidth + destCol;
        output[destIndex] = plane[sourceIndex];
      }
    }
    return output;
  }
}
