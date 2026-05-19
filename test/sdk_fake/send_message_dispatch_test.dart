// Regression guard for P0-1: `Tim2ToxSdkPlatform.sendMessage` must dispatch
// every V2TimMessage element type the UIKit can hand it. When a branch goes
// missing, the platform returns `code: -1, desc: 'Unsupported message type: …'`
// and the user sees a silent send failure for that media class.
//
// Strategy — degraded "source-string assertion":
// Wiring `Tim2ToxSdkPlatform` against a real `ChatMessageProvider` requires
// installing the platform, an `EventBusProvider`, a `ConversationManagerProvider`,
// and live FFI bindings — too much surface to mock cheaply. Instead we treat
// the `sendMessage` function body as a contract and assert the dispatch
// keywords are textually present. This is intentionally crude but reliable:
// the only way the test passes is if a branch literally references
// `messageToSend.<kind>Elem`, which means the dispatch exists at all. A test
// that just calls a mock provider couldn't catch the very specific bug we
// care about ("a branch was deleted"), because the bug surfaces as the
// catch-all error path, not as a wrong-method call.
//
// We also assert these branches appear *inside* the `sendMessage` function,
// not anywhere in the 6000-line file (forward-message handling and conversion
// utilities also mention the same elem types and would give false positives
// if we grepped globally).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Slice the source between two anchors. Returns the substring or throws if
/// either anchor is missing — that itself is signal that the test is stale
/// vs the current file layout and should be updated.
String _sliceBetween(String src, String start, String end) {
  final s = src.indexOf(start);
  if (s < 0) {
    throw StateError(
        'send_message_dispatch_test: start anchor not found: "$start" — '
        'tim2tox_sdk_platform.dart may have been refactored; update this test.');
  }
  final e = src.indexOf(end, s);
  if (e < 0) {
    throw StateError(
        'send_message_dispatch_test: end anchor not found after start: "$end" — '
        'tim2tox_sdk_platform.dart may have been refactored; update this test.');
  }
  return src.substring(s, e);
}

void main() {
  // `flutter test` is launched from the toxee repo root, so `Directory.current`
  // resolves there. Stays valid as long as tests aren't run via `cd`-into-test.
  final repoRoot = Directory.current.path;
  final platformSrcPath =
      '$repoRoot/third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart';

  group('Tim2ToxSdkPlatform.sendMessage element-type dispatch (P0-1)', () {
    late String sendMessageBody;

    setUpAll(() async {
      final src = await File(platformSrcPath).readAsString();
      // Scope the search to the `sendMessage` function body. Forward-message
      // construction and msg converters elsewhere in this file also mention
      // these elem types and would give us false-positive matches if we
      // scanned the whole file.
      sendMessageBody = _sliceBetween(
        src,
        'Future<V2TimValueCallback<V2TimMessage>> sendMessage(',
        // The next public method after sendMessage in this file. Picked as
        // a stable anchor: it's been there since the original Platform path
        // landed. If it ever moves, the _sliceBetween throw will tell us.
        'sendMessageReadReceipts',
      );
    });

    test('has a soundElem dispatch branch', () {
      expect(
        sendMessageBody,
        contains('soundElem'),
        reason:
            'sendMessage() missing soundElem dispatch — voice messages will '
            'fall through to the "Unsupported message type" error and return '
            'code -1 (P0-1 regression).',
      );
    });

    test('has a videoElem dispatch branch', () {
      expect(
        sendMessageBody,
        contains('videoElem'),
        reason:
            'sendMessage() missing videoElem dispatch — video messages will '
            'fall through to the "Unsupported message type" error and return '
            'code -1 (P0-1 regression).',
      );
    });

    test('has a faceElem dispatch branch', () {
      expect(
        sendMessageBody,
        contains('faceElem'),
        reason:
            'sendMessage() missing faceElem dispatch — sticker/emoji messages '
            'will fall through to the "Unsupported message type" error and '
            'return code -1 (P0-1 regression).',
      );
    });

    test('has a customElem dispatch branch', () {
      expect(
        sendMessageBody,
        contains('customElem'),
        reason:
            'sendMessage() missing customElem dispatch — translation/TTS/'
            'reply/quoted custom payloads will fall through to the '
            '"Unsupported message type" error and return code -1 '
            '(P0-1 regression).',
      );
    });

    test('has a locationElem dispatch branch', () {
      expect(
        sendMessageBody,
        contains('locationElem'),
        reason:
            'sendMessage() missing locationElem dispatch — location-share '
            'messages will fall through to the "Unsupported message type" '
            'error and return code -1 (P0-1 regression).',
      );
    });
  });
}
