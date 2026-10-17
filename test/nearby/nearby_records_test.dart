import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/nearby/nearby_canonical_json.dart';
import 'package:toxee/nearby/nearby_crypto.dart';
import 'package:toxee/nearby/nearby_records.dart';

void main() {
  const now = 1760700000;

  PresenceRecord presence(NearbySessionKeys k,
          {int seq = 1,
          int exp = now + 180,
          String name = 'Ann',
          List<String> cells = const ['wx4g0']}) =>
      PresenceRecord(
        skHex: k.skHex,
        ekHex: k.ekHex,
        seq: seq,
        exp: exp,
        name: name,
        avatarHex: '',
        latE3: 39905,
        lonE3: 116391,
        cells: cells,
      );

  group('PresenceRecord', () {
    test('encodes canonical signed bytes that decode and verify', () async {
      final k = await NearbyCrypto.newSessionKeys();
      final bytes = (await PresenceRecord.encode(presence(k), k))!;
      final text = utf8.decode(bytes);
      expect(text, startsWith('{"avatar":"","cells":["wx4g0"],"ek":"'));
      expect(text, contains('"seq":1,"sig":"'));
      expect(text, endsWith('"t":"presence","v":1}'));
      final back = await PresenceRecord.decode(bytes, now);
      expect(back, isNotNull);
      expect(back!.skHex, k.skHex);
      expect(back.name, 'Ann');
      expect(back.latitude, closeTo(39.905, 1e-9));
      expect(back.cells, ['wx4g0']);
    });

    test('rejects tampering, bad expiry, wrong key and oversize', () async {
      final k = await NearbyCrypto.newSessionKeys();
      final bytes = (await PresenceRecord.encode(presence(k), k))!;
      final reasons = <String>[];
      // Flip a payload byte: signature fails.
      final tampered = Uint8List.fromList(bytes);
      final idx = utf8.decode(bytes).indexOf('"name":"Ann"') + 9;
      tampered[idx] = 'B'.codeUnitAt(0);
      expect(await PresenceRecord.decode(tampered, now, reason: reasons), isNull);
      expect(reasons, contains('signature'));
      // Expiry too far in the future / already past.
      expect(await PresenceRecord.decode((await PresenceRecord.encode(presence(k, exp: now + 241), k))!, now), isNull);
      expect(await PresenceRecord.decode((await PresenceRecord.encode(presence(k, exp: now + 240), k))!, now), isNotNull);
      expect(await PresenceRecord.decode((await PresenceRecord.encode(presence(k, exp: now - 60), k))!, now), isNull);
      expect(await PresenceRecord.decode((await PresenceRecord.encode(presence(k, exp: now - 59), k))!, now), isNotNull);
      // Signed by another key but claiming k's sk: fails.
      final other = await NearbyCrypto.newSessionKeys();
      final forged = await PresenceRecord.encode(presence(k), other);
      expect(await PresenceRecord.decode(forged!, now), isNull);
      // Name limits: 32 code points / 96 bytes.
      expect(await PresenceRecord.encode(presence(k, name: 'x' * 33), k), isNull);
      expect(await PresenceRecord.encode(presence(k, name: '中' * 32), k), isNotNull); // 32 code points, 96 bytes: the limit
      expect(await PresenceRecord.encode(presence(k, name: '😀' * 25), k), isNull); // 100 bytes
      // Too many cells / unsorted cells handled by encode (it sorts) and decode.
      expect(await PresenceRecord.encode(presence(k, cells: List.generate(9, (i) => 'wx4g$i')), k), isNull);
    });

    test('decode rejects upper-case hex and non-canonical text', () async {
      final k = await NearbyCrypto.newSessionKeys();
      final bytes = (await PresenceRecord.encode(presence(k), k))!;
      final upper = utf8.decode(bytes).replaceFirst('"sk":"', '"sk":"').replaceFirst(k.skHex, k.skHex.toUpperCase());
      expect(await PresenceRecord.decode(Uint8List.fromList(utf8.encode(upper)), now), isNull);
      final spaced = utf8.decode(bytes).replaceFirst(',', ', ');
      expect(await PresenceRecord.decode(Uint8List.fromList(utf8.encode(spaced)), now), isNull);
    });
  });

  group('IntentRecord', () {
    test('seals, signs, decodes and opens; wrong recipient and replayed aad fail', () async {
      final a = await NearbyCrypto.newSessionKeys();
      final b = await NearbyCrypto.newSessionKeys();
      final body = IntentBody(
        address: 'a' * 76,
        nonceHex: NearbyCrypto.hex(NearbyCrypto.randomBytes(16)),
        message: 'hi 你好',
        exp: now + 600,
      );
      final bytes = (await IntentRecord.encode(keys: a, recipientEkHex: b.ekHex, body: body))!;
      expect(bytes.length, lessThanOrEqualTo(NearbyLimits.maxPayloadBytes));
      final record = (await IntentRecord.decode(bytes))!;
      expect(record.fromSkHex, a.skHex);
      expect(record.toEkHex, b.ekHex);
      final opened = (await record.open(b, now))!;
      expect(opened.address, 'a' * 76);
      expect(opened.message, 'hi 你好');
      expect(opened.nonceHex, body.nonceHex);
      // Another recipient cannot open it.
      final c = await NearbyCrypto.newSessionKeys();
      expect(await record.open(c, now), isNull);
      // Expired body.
      expect(await record.open(b, now + 601), isNull);
      // Tamper the `from` field: signature fails at decode.
      final text = utf8.decode(bytes);
      final swapped = text.replaceFirst(a.skHex, c.skHex);
      expect(await IntentRecord.decode(Uint8List.fromList(utf8.encode(swapped))), isNull);
    });

    test('message limits: 140 code points and 280 bytes, frame budget', () async {
      final a = await NearbyCrypto.newSessionKeys();
      final b = await NearbyCrypto.newSessionKeys();
      IntentBody body(String msg) => IntentBody(address: 'a' * 76, nonceHex: '0' * 32, message: msg, exp: now + 600);
      expect(await IntentRecord.encode(keys: a, recipientEkHex: b.ekHex, body: body('x' * 140)), isNotNull);
      expect(await IntentRecord.encode(keys: a, recipientEkHex: b.ekHex, body: body('x' * 141)), isNull);
      // 94 four-byte emoji = 376 bytes > 280, though only 94 code points.
      expect(await IntentRecord.encode(keys: a, recipientEkHex: b.ekHex, body: body('😀' * 94)), isNull);
      // 93 three-byte CJK = 279 bytes passes the message limits but the
      // hex-encoded box then breaks the 1200-byte frame budget: refused.
      expect(await IntentRecord.encode(keys: a, recipientEkHex: b.ekHex, body: body('中' * 93)), isNull);
      // 60 CJK (180 bytes) fits the frame.
      expect(await IntentRecord.encode(keys: a, recipientEkHex: b.ekHex, body: body('中' * 60)), isNotNull);
      expect(IntentBody.validMessage('a\u0001b'), isFalse);
    });

    test('request wording carries the nonce and parses back', () {
      final body = IntentBody(address: 'a' * 76, nonceHex: 'ab' * 16, message: 'hello there', exp: 0);
      expect(body.requestWording(), 'toxee-nearby:${'ab' * 16} hello there');
      expect(IntentBody.nonceFromWording(body.requestWording()), 'ab' * 16);
      expect(IntentBody.nonceFromWording('toxee-nearby:${'ab' * 16}'), 'ab' * 16);
      expect(IntentBody.nonceFromWording('toxee-nearby:${'AB' * 16} x'), isNull);
      expect(IntentBody.nonceFromWording('hello'), isNull);
      expect(IntentBody.nonceFromWording(null), isNull);
    });

    test('aad is the canonical header with values', () {
      final aad = NearbyCanonicalJson.encodeString(IntentRecord.aadOf('f' * 64, 't' * 64, 'e' * 64));
      expect(aad, '{"epk":"${'e' * 64}","from":"${'f' * 64}","t":"intent","to":"${'t' * 64}","v":1}');
    });
  });

  test('maxMessageWireBytes is exactly where encode() stops fitting the frame', () async {
    final me = await NearbyCrypto.newSessionKeys();
    final you = await NearbyCrypto.newSessionKeys();
    Future<bool> fits(String msg) async =>
        await IntentRecord.encode(
          keys: me,
          recipientEkHex: you.ekHex,
          body: IntentBody(address: 'a' * 76, nonceHex: '1' * 32, message: msg, exp: 1767268800 + 600),
        ) !=
        null;
    // Multi-byte text, so the 140-code-point limit does not bind first.
    const max = IntentBody.maxMessageWireBytes;
    final atBudget = '中' * (max ~/ 3) + 'x' * (max % 3);
    expect(IntentBody.messageWireBytes(atBudget), max);
    expect(IntentBody.fitsFrame(atBudget), isTrue);
    expect(IntentBody.validMessage(atBudget), isTrue);
    expect(await fits(atBudget), isTrue);
    expect(IntentBody.fitsFrame('${atBudget}y'), isFalse);
    expect(await fits('${atBudget}y'), isFalse);
    // Escapes and multi-byte characters count as what they cost on the wire.
    expect(IntentBody.messageWireBytes('a\nb'), 8); // \u000a on the wire
    expect(IntentBody.messageWireBytes('中'), 3);
    expect(IntentBody.messageWireBytes('"'), 2);
  });
}
