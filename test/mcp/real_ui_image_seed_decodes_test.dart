// Every base64 PNG the real-UI drivers seed must actually DECODE.
//
// WHY THIS EXISTS. `message_viewer_save_and_zoom_surface` was red on iPhone,
// iPad and Android for four device shifts. It was blamed on a tap-duration
// window, a flaky gesture, a stale file path and a cached decode failure. The
// truth was the FIXTURE: the shared seed was a 1x1 8-bit GRAY+ALPHA PNG that
// `file(1)` happily reports as "PNG image data, 1 x 1" while Flutter's codec
// rejects outright ("Codec failed to produce an image, possibly due to invalid
// image data"). The product was right to render its decode-error placeholder —
// and because that placeholder is an `InkWell` which wins the gesture arena
// over the image bubble's `GestureDetector`, the bubble became genuinely
// untappable, so the failure looked exactly like a broken viewer.
//
// A device campaign is an expensive place to learn that. This runs in
// `flutter test`, in under a second, against the seeds as they appear IN THE
// DRIVER SOURCE — so it cannot drift from what the campaigns actually send.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Driver files that seed an image over `l3_send_file` / the attachment path.
const _driverFiles = <String>[
  'tool/mcp_test/drive_real_ui_pair_keyed_gaps4_attach.dart',
  'tool/mcp_test/drive_real_ui_pair_p1_chat.dart',
  'tool/mcp_test/drive_real_ui_pair_chat.dart',
  'tool/mcp_test/drive_real_ui_pair_high_value_extra.dart',
  'tool/mcp_test/drive_real_ui_pair_p2_verify.dart',
  'tool/mcp_test/drive_real_ui_pair_profile.dart',
];

/// Every base64 PNG literal in [source], re-joined across Dart's adjacent
/// string-literal concatenation (the drivers wrap them at 76 columns).
List<String> _pngLiterals(String source) {
  final out = <String>[];
  // A PNG's base64 always starts with the 8-byte signature -> "iVBORw0KGgo".
  final start = RegExp(r"'iVBORw0KGgo");
  for (final m in start.allMatches(source)) {
    var i = m.start;
    final buf = StringBuffer();
    // Walk consecutive single-quoted literals separated only by whitespace.
    while (i < source.length && source[i] == "'") {
      final end = source.indexOf("'", i + 1);
      if (end < 0) break;
      buf.write(source.substring(i + 1, end));
      i = end + 1;
      while (i < source.length && (source[i] == ' ' || source[i] == '\n')) {
        i++;
      }
    }
    out.add(buf.toString());
  }
  return out;
}

void main() {
  test('every real-UI driver image seed decodes with the Flutter codec', () async {
    var checked = 0;
    for (final path in _driverFiles) {
      final file = File(path);
      if (!file.existsSync()) continue; // tolerate a future rename
      final literals = _pngLiterals(file.readAsStringSync());
      for (final b64 in literals) {
        late final Uint8List bytes;
        try {
          bytes = base64Decode(b64);
        } on FormatException catch (e) {
          fail('$path: seed is not valid base64: $e');
        }
        ui.FrameInfo frame;
        try {
          // The decode error surfaces on getNextFrame(), not on
          // instantiateImageCodec — both must be inside the guard.
          final codec = await ui.instantiateImageCodec(bytes);
          frame = await codec.getNextFrame();
        } catch (e) {
          fail(
            '$path: a seeded PNG (${bytes.length} bytes, '
            'b64 starts "${b64.substring(0, 24)}...") does NOT decode: $e\n'
            'A real-UI image case seeded with this renders the decode-error '
            'placeholder, whose InkWell swallows the tap meant for the image '
            'bubble — the case then fails as if the VIEWER were broken. '
            'Replace the seed with one this test accepts.',
          );
        }
        expect(
          frame.image.width,
          greaterThan(0),
          reason: '$path: seeded PNG decoded to a zero-width image',
        );
        checked++;
      }
    }
    expect(
      checked,
      greaterThan(0),
      reason: 'no image seeds were found — did the drivers move?',
    );
  });
}
