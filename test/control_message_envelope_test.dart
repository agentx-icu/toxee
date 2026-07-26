import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/utils/control_message_envelope.dart';

void main() {
  group('parseTextControlEnvelope', () {
    test('leaves ordinary and unknown-prefixed text plain', () {
      expect(parseTextControlEnvelope('hello'), isA<PlainTextEnvelope>());
      expect(
        parseTextControlEnvelope('__future__:opaque'),
        isA<PlainTextEnvelope>(),
      );
    });

    test('parses structured face and location envelopes', () {
      final face = parseTextControlEnvelope(
        '__face__:{"index":7,"data":"smile"}',
      );
      expect(face, isA<FaceTextEnvelope>());
      final parsedFace = face as FaceTextEnvelope;
      expect(parsedFace.rawPayload, '{"index":7,"data":"smile"}');
      expect(parsedFace.payload['index'], 7);
      expect(parsedFace.payload['data'], 'smile');

      final location = parseTextControlEnvelope(
        '__location__:{"desc":"park","longitude":1.5,"latitude":2.5}',
      );
      expect(location, isA<LocationTextEnvelope>());
      final parsedLocation = location as LocationTextEnvelope;
      expect(parsedLocation.payload['desc'], 'park');
      expect(parsedLocation.payload['longitude'], 1.5);
      expect(parsedLocation.payload['latitude'], 2.5);
    });

    test(
      'falls back to plain text for malformed structured rich envelopes',
      () {
        expect(
          parseTextControlEnvelope('__face__:not-json'),
          isA<PlainTextEnvelope>(),
        );
        expect(
          parseTextControlEnvelope('__location__:[1,2]'),
          isA<PlainTextEnvelope>(),
        );
        expect(
          parseTextControlEnvelope('__face__:{"index":"wrong","data":"smile"}'),
          isA<PlainTextEnvelope>(),
        );
        expect(
          parseTextControlEnvelope(
            '__location__:{"desc":"park","longitude":1.5}',
          ),
          isA<PlainTextEnvelope>(),
        );
      },
    );

    test('preserves arbitrary custom suffixes without requiring JSON', () {
      final opaque = parseTextControlEnvelope('__custom__:opaque-v1:AAECAw==');
      expect(opaque, isA<CustomTextEnvelope>());
      expect((opaque as CustomTextEnvelope).rawPayload, 'opaque-v1:AAECAw==');

      final json = parseTextControlEnvelope('__custom__:{"kind":"legacy"}');
      expect(json, isA<CustomTextEnvelope>());
      expect((json as CustomTextEnvelope).rawPayload, '{"kind":"legacy"}');
    });

    test('recognizes valid and malformed revoke envelopes for swallowing', () {
      final valid = parseTextControlEnvelope(
        '__revoke__:{"msgID":"message-1"}',
      );
      expect(valid, isA<RevokeTextEnvelope>());
      final parsedValid = valid as RevokeTextEnvelope;
      expect(parsedValid.shouldSwallow, isTrue);
      expect(parsedValid.payload?['msgID'], 'message-1');

      final malformed = parseTextControlEnvelope('__revoke__:not-json');
      expect(malformed, isA<RevokeTextEnvelope>());
      final parsedMalformed = malformed as RevokeTextEnvelope;
      expect(parsedMalformed.shouldSwallow, isTrue);
      expect(parsedMalformed.payload, isNull);
      expect(parsedMalformed.rawPayload, 'not-json');
    });
  });
}
