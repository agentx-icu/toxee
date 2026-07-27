import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _sliceBetween(String src, String start, String end) {
  final s = src.indexOf(start);
  if (s < 0) {
    throw StateError(
      'control_signal_regression_test: start anchor not found: "$start"',
    );
  }
  final e = src.indexOf(end, s);
  if (e < 0) {
    throw StateError(
      'control_signal_regression_test: end anchor not found after "$start": "$end"',
    );
  }
  return src.substring(s, e);
}

void main() {
  final repoRoot = Directory.current.path;
  final routingPath = '$repoRoot/lib/sdk_fake/fake_msg_provider_routing.dart';
  final mappingPath = '$repoRoot/lib/sdk_fake/fake_msg_provider_mapping.dart';
  final messageProviderPath = '$repoRoot/lib/sdk_fake/fake_msg_provider.dart';
  final conversationProviderPath = '$repoRoot/lib/sdk_fake/fake_provider.dart';

  group('sdk_fake control-signal regressions', () {
    late String routingSrc;
    late String mappingSrc;
    late String messageProviderSrc;
    late String conversationProviderSrc;

    setUpAll(() async {
      routingSrc = await File(routingPath).readAsString();
      mappingSrc = await File(mappingPath).readAsString();
      messageProviderSrc = await File(messageProviderPath).readAsString();
      conversationProviderSrc = await File(
        conversationProviderPath,
      ).readAsString();
    });

    test(
      'live __revoke__ handling updates existing buffer instead of only swallowing',
      () {
        final onTopicBody = _sliceBetween(
          routingSrc,
          'Future<void> _onTopicMessage(FakeMessage m) async {',
          '/// Map FakeMessage to V2TimMessage',
        );

        expect(
          onTopicBody,
          contains('_applyRevokeControlSignalToBuffer'),
          reason:
              'Regression: sdk_fake live revoke handling still only swallows '
              'the __revoke__ control signal. It must also remove the revoked '
              'message from the current in-memory buffer so the open '
              'conversation updates immediately.',
        );
      },
    );

    test('history reload normalizes control signals before mapping bubbles', () {
      final loadHistoryBody = _sliceBetween(
        mappingSrc,
        'Future<void> _loadHistoryForConversation(String conversationID) async {',
        '} catch (e) {',
      );

      expect(
        loadHistoryBody,
        contains('_normalizeControlSignalsInHistory'),
        reason:
            'Regression: sdk_fake history reload still feeds raw control '
            'signals directly into _mapMsg. Page reload / app restart must '
            'normalize __face__/__custom__/__location__ placeholders and '
            'apply __revoke__ removals before rebuilding the buffer.',
      );
    });

    test(
      'history normalization swallows revoke and preserves rich envelopes',
      () {
        final helperBody = _sliceBetween(
          mappingSrc,
          'List<FakeMessage> _normalizeControlSignalsInHistory(',
          'Future<void> _loadHistoryForConversation(',
        );

        expect(helperBody, contains('parseTextControlEnvelope'));
        expect(helperBody, contains('RevokeTextEnvelope'));
        expect(helperBody, isNot(contains('_rewriteControlSignalForBubble')));
      },
    );

    test('live and history mapping use the shared typed envelope parser', () {
      expect(
        messageProviderSrc,
        contains('utils/control_message_envelope.dart'),
      );

      final mapBody = _sliceBetween(
        mappingSrc,
        'V2TimMessage _mapMsg(FakeMessage m) {',
        'Future<void> _loadHistoryForConversation(',
      );
      expect(mapBody, contains('parseTextControlEnvelope'));
      expect(
        mapBody,
        contains('m.mediaKind == null || m.mediaKind!.isEmpty'),
        reason: 'already-typed custom media must not be envelope-parsed again',
      );
      expect(mapBody, contains('FaceTextEnvelope'));
      expect(mapBody, contains('LocationTextEnvelope'));
      expect(mapBody, contains('CustomTextEnvelope'));

      final previewBody = _sliceBetween(
        conversationProviderSrc,
        'V2TimMessage _chatMessageToV2TimMessage(',
        'Stream<List<V2TimConversation>> get conversationStream',
      );
      expect(previewBody, contains('parseTextControlEnvelope'));
      expect(
        previewBody,
        contains('chatMsg.mediaKind == null || chatMsg.mediaKind!.isEmpty'),
        reason: 'preview must not envelope-parse already-typed custom media',
      );
      expect(previewBody, contains("case 'custom':"));
      expect(previewBody, contains('data: chatMsg.text'));
      expect(previewBody, contains('FaceTextEnvelope'));
      expect(previewBody, contains('LocationTextEnvelope'));
      expect(previewBody, contains('CustomTextEnvelope'));
    });
  });
}
