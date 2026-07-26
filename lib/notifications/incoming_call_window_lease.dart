import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String incomingCallWindowNonceDigestPrefsKey =
    'toxee_incoming_call_window_token';
const String incomingCallWindowCallDigestPrefsKey =
    'toxee_incoming_call_window_call_digest';
const String incomingCallWindowExpiresAtPrefsKey =
    'toxee_incoming_call_window_expires_at_ms';
const List<String> incomingCallWindowLeasePreferenceKeys = <String>[
  incomingCallWindowNonceDigestPrefsKey,
  incomingCallWindowCallDigestPrefsKey,
  incomingCallWindowExpiresAtPrefsKey,
];
const Duration incomingCallWindowLeaseTtl = Duration(minutes: 2);

const String _callDigestDomain = 'toxee:incoming-call-window:call:v1';

typedef IncomingCallWindowClock = DateTime Function();
typedef IncomingCallWindowRandomBytes = List<int> Function(int length);

String stripIncomingCallWindowNonce(String payload) {
  if (!payload.startsWith('incoming_call:')) return payload;
  final separator = payload.lastIndexOf(':');
  if (separator <= 'incoming_call:'.length) return payload;
  return payload.substring(0, separator);
}

abstract interface class IncomingCallWindowPreferences {
  Future<bool> setString(String key, String value);

  Future<bool> setInt(String key, int value);

  Future<bool> remove(String key);
}

final class SharedPreferencesIncomingCallWindowPreferences
    implements IncomingCallWindowPreferences {
  const SharedPreferencesIncomingCallWindowPreferences(this._preferences);

  final SharedPreferences _preferences;

  @override
  Future<bool> remove(String key) => _preferences.remove(key);

  @override
  Future<bool> setInt(String key, int value) => _preferences.setInt(key, value);

  @override
  Future<bool> setString(String key, String value) =>
      _preferences.setString(key, value);
}

final class IncomingCallWindowLeaseIssue {
  const IncomingCallWindowLeaseIssue({
    required this.nonce,
    required this.nonceDigest,
    required this.callDigest,
    required this.expiresAtEpochMs,
  });

  final String nonce;
  final String nonceDigest;
  final String callDigest;
  final int expiresAtEpochMs;

  @override
  String toString() =>
      'IncomingCallWindowLeaseIssue(expiresAtEpochMs: $expiresAtEpochMs)';
}

final class IncomingCallWindowLeaseStorageException implements Exception {
  const IncomingCallWindowLeaseStorageException(this.message);

  final String message;

  @override
  String toString() => 'IncomingCallWindowLeaseStorageException: $message';
}

final class IncomingCallWindowLeaseStore {
  IncomingCallWindowLeaseStore({
    required IncomingCallWindowPreferences preferences,
    IncomingCallWindowClock? now,
    IncomingCallWindowRandomBytes? randomBytes,
  }) : _preferences = preferences,
       _now = now ?? DateTime.now,
       _randomBytes = randomBytes ?? _secureRandomBytes;

  final IncomingCallWindowPreferences _preferences;
  final IncomingCallWindowClock _now;
  final IncomingCallWindowRandomBytes _randomBytes;

  Future<IncomingCallWindowLeaseIssue> issue(String callId) async {
    await clear();

    final randomBytes = _randomBytes(32);
    if (randomBytes.length != 32) {
      throw const IncomingCallWindowLeaseStorageException(
        'secure random source returned an invalid length',
      );
    }
    final nonce = _hex(randomBytes);
    final issue = IncomingCallWindowLeaseIssue(
      nonce: nonce,
      nonceDigest: sha256.convert(utf8.encode(nonce)).toString(),
      callDigest: _callDigest(callId),
      expiresAtEpochMs: _now()
          .add(incomingCallWindowLeaseTtl)
          .millisecondsSinceEpoch,
    );

    try {
      await _requireWrite(
        _preferences.setString(
          incomingCallWindowNonceDigestPrefsKey,
          issue.nonceDigest,
        ),
      );
      await _requireWrite(
        _preferences.setString(
          incomingCallWindowCallDigestPrefsKey,
          issue.callDigest,
        ),
      );
      await _requireWrite(
        _preferences.setInt(
          incomingCallWindowExpiresAtPrefsKey,
          issue.expiresAtEpochMs,
        ),
      );
      return issue;
    } catch (_) {
      try {
        await clear();
      } catch (_) {
        throw const IncomingCallWindowLeaseStorageException(
          'issue failed and partial-lease cleanup failed',
        );
      }
      throw const IncomingCallWindowLeaseStorageException('issue failed');
    }
  }

  Future<void> clear() async {
    var failed = false;
    for (final key in incomingCallWindowLeasePreferenceKeys) {
      try {
        if (!await _preferences.remove(key)) failed = true;
      } catch (_) {
        failed = true;
      }
    }
    if (failed) {
      throw const IncomingCallWindowLeaseStorageException(
        'one or more lease keys could not be removed',
      );
    }
  }

  static Future<void> _requireWrite(Future<bool> write) async {
    if (!await write) {
      throw const IncomingCallWindowLeaseStorageException(
        'lease key could not be written',
      );
    }
  }

  static List<int> _secureRandomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(
      length,
      (_) => random.nextInt(256),
      growable: false,
    );
  }

  static String _callDigest(String callId) {
    return sha256.convert(<int>[
      ...utf8.encode(_callDigestDomain),
      0,
      ...utf8.encode(callId),
    ]).toString();
  }

  static String _hex(List<int> bytes) {
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}
