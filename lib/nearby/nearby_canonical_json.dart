import 'dart:convert';
import 'dart:typed_data';

/// Canonical JSON of the nearby protocol (`toxee/nearby/v1`, plan §3.4):
///
/// * objects: keys sorted by byte value (keys are ASCII), no whitespace;
/// * strings: only `"`, `\` and control characters < 0x20 are escaped (the
///   latter as `\u00XX`); every other code point is emitted as raw UTF-8;
/// * numbers: integers only — no doubles, no exponents, no `-0`;
/// * arrays keep the order given by the record;
/// * `bool` and `null` are not part of the protocol and are rejected.
///
/// The bytes a signer signs and a verifier re-serialises are identical by
/// construction, which is what makes the signature check meaningful.
class NearbyCanonicalJson {
  NearbyCanonicalJson._();

  /// Canonical UTF-8 bytes of [value].
  static Uint8List encode(Object value) {
    final sb = StringBuffer();
    _write(sb, value);
    return Uint8List.fromList(utf8.encode(sb.toString()));
  }

  /// Canonical text of [value].
  static String encodeString(Object value) {
    final sb = StringBuffer();
    _write(sb, value);
    return sb.toString();
  }

  /// Parses JSON text and checks that it is canonical: re-encoding the parsed
  /// value must reproduce the input bytes exactly. Returns null otherwise or
  /// when the text contains anything outside the protocol's value set.
  static Map<String, Object>? decodeObject(Uint8List bytes) {
    final String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return null;
    }
    final Object? parsed;
    try {
      parsed = json.decode(text);
    } on FormatException {
      return null;
    }
    if (parsed is! Map) return null;
    final Map<String, Object> object;
    try {
      object = _normalise(parsed) as Map<String, Object>;
    } on FormatException {
      return null;
    }
    final String canonical;
    try {
      canonical = encodeString(object);
    } on ArgumentError {
      return null; // e.g. a non-ASCII key: outside the protocol's value set
    }
    if (canonical != text) return null;
    return object;
  }

  /// Rejects doubles (JSON numbers with a fraction/exponent decode as double),
  /// booleans and nulls; converts maps to `Map<String, Object>`.
  static Object _normalise(Object? v) {
    if (v == null || v is bool) throw const FormatException('not allowed');
    if (v is double) throw const FormatException('doubles are not allowed');
    if (v is int || v is String) return v;
    if (v is List) return v.map(_normalise).toList(growable: false);
    if (v is Map) {
      final out = <String, Object>{};
      v.forEach((k, val) {
        if (k is! String) throw const FormatException('non-string key');
        out[k] = _normalise(val);
      });
      return out;
    }
    throw const FormatException('unsupported value');
  }

  static void _write(StringBuffer sb, Object value) {
    if (value is int) {
      sb.write(value.toString());
    } else if (value is String) {
      _writeString(sb, value);
    } else if (value is List) {
      sb.write('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) sb.write(',');
        final element = value[i];
        if (element == null) throw ArgumentError('null is not allowed');
        _write(sb, element as Object);
      }
      sb.write(']');
    } else if (value is Map) {
      final keys = value.keys.map((k) {
        if (k is! String || !_isAscii(k)) {
          throw ArgumentError('keys must be ASCII strings');
        }
        return k;
      }).toList()
        ..sort(_compareBytes);
      sb.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) sb.write(',');
        _writeString(sb, keys[i]);
        sb.write(':');
        final element = value[keys[i]];
        if (element == null) throw ArgumentError('null is not allowed');
        _write(sb, element as Object);
      }
      sb.write('}');
    } else if (value is double || value is bool) {
      throw ArgumentError('${value.runtimeType} is not part of the protocol');
    } else {
      throw ArgumentError('unsupported value ${value.runtimeType}');
    }
  }

  static void _writeString(StringBuffer sb, String s) {
    sb.write('"');
    for (final unit in s.runes) {
      if (unit == 0x22) {
        sb.write(r'\"');
      } else if (unit == 0x5c) {
        sb.write(r'\\');
      } else if (unit < 0x20) {
        sb.write(r'\u');
        sb.write(unit.toRadixString(16).padLeft(4, '0'));
      } else {
        sb.writeCharCode(unit);
      }
    }
    sb.write('"');
  }

  static bool _isAscii(String s) => s.codeUnits.every((u) => u < 0x80);

  static int _compareBytes(String a, String b) => a.compareTo(b);
}
