import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/nearby/nearby_canonical_json.dart';

void main() {
  group('NearbyCanonicalJson', () {
    test('sorts keys by byte value and emits no whitespace', () {
      final s = NearbyCanonicalJson.encodeString({
        'z': 1,
        'a': 'x',
        'm': ['b', 'a'],
        'sig': 'ff',
        'seq': 7,
        'sk': 'aa',
      });
      expect(s, '{"a":"x","m":["b","a"],"seq":7,"sig":"ff","sk":"aa","z":1}');
    });

    test('escapes only quote, backslash and control characters', () {
      final s = NearbyCanonicalJson.encodeString({'name': 'A"B\\C\u0001 é 中 😀'});
      expect(s, '{"name":"A\\"B\\\\C\\u0001 é 中 😀"}');
      // Raw UTF-8 on the wire, not \u escapes.
      final bytes = NearbyCanonicalJson.encode({'n': '中'});
      expect(bytes, Uint8List.fromList(utf8.encode('{"n":"中"}')));
    });

    test('rejects doubles, bools, nulls and non-ASCII keys', () {
      expect(() => NearbyCanonicalJson.encode({'a': 1.5}), throwsArgumentError);
      expect(() => NearbyCanonicalJson.encode({'a': true}), throwsArgumentError);
      expect(() => NearbyCanonicalJson.encode({'a': null}), throwsArgumentError);
      expect(() => NearbyCanonicalJson.encode({'ключ': 1}), throwsArgumentError);
    });

    test('decodeObject accepts only the canonical form', () {
      Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));
      expect(NearbyCanonicalJson.decodeObject(b('{"a":1,"b":"x"}')), {'a': 1, 'b': 'x'});
      // Unsorted keys, whitespace, doubles, bools, nulls, escapes that are
      // not minimal: all rejected.
      expect(NearbyCanonicalJson.decodeObject(b('{"b":1,"a":2}')), isNull);
      expect(NearbyCanonicalJson.decodeObject(b('{"a": 1}')), isNull);
      expect(NearbyCanonicalJson.decodeObject(b('{"a":1.0}')), isNull);
      expect(NearbyCanonicalJson.decodeObject(b('{"a":true}')), isNull);
      expect(NearbyCanonicalJson.decodeObject(b('{"a":null}')), isNull);
      expect(NearbyCanonicalJson.decodeObject(b('{"a":"\\u0041"}')), isNull);
      expect(NearbyCanonicalJson.decodeObject(b('[1]')), isNull);
      expect(NearbyCanonicalJson.decodeObject(b('{"a":1')), isNull);
      expect(NearbyCanonicalJson.decodeObject(Uint8List.fromList([0xff, 0xfe])), isNull);
    });

    test('round trips through decode and encode byte for byte', () {
      final object = {
        'avatar': '',
        'cells': ['wx4g0', 'wx4g1'],
        'ek': 'ab' * 32,
        'exp': 1760700000,
        'lat_e3': 39905,
        'lon_e3': -116391,
        'name': 'Ann 中',
        'seq': 7,
        'sk': 'cd' * 32,
        't': 'presence',
        'v': 1,
      };
      final bytes = NearbyCanonicalJson.encode(object);
      final back = NearbyCanonicalJson.decodeObject(bytes);
      expect(back, object);
      expect(NearbyCanonicalJson.encode(back!), bytes);
    });
  });

  test('decodeObject rejects a non-ASCII key instead of throwing', () {
    expect(NearbyCanonicalJson.decodeObject(Uint8List.fromList(utf8.encode('{"é":1}'))), isNull);
    expect(NearbyCanonicalJson.decodeObject(Uint8List.fromList(utf8.encode('{"a":{"ü":1}}'))), isNull);
  });
}
