import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String incomingCallWindowLegacyRawTokenPrefsKey =
    IncomingCallWindowLeasePrefs.legacyRawTokenKey;
const String incomingCallWindowNonceDigestPrefsKey =
    IncomingCallWindowLeasePrefs.nonceDigestKey;
const String incomingCallWindowCallDigestPrefsKey =
    IncomingCallWindowLeasePrefs.callIdDigestKey;
const String incomingCallWindowExpiresAtPrefsKey =
    IncomingCallWindowLeasePrefs.expiresAtEpochMsKey;
const List<String> incomingCallWindowLeasePreferenceKeys = <String>[
  incomingCallWindowNonceDigestPrefsKey,
  incomingCallWindowCallDigestPrefsKey,
  incomingCallWindowExpiresAtPrefsKey,
];
const List<String> incomingCallWindowLeaseCleanupPreferenceKeys =
    IncomingCallWindowLeasePrefs.allKeys;
const Duration incomingCallWindowLeaseTtl = Duration(minutes: 2);

typedef IncomingCallWindowClock = DateTime Function();
typedef IncomingCallWindowRandomBytes = List<int> Function(int length);

String stripIncomingCallWindowNonce(String payload) {
  if (!payload.startsWith('incoming_call:')) return payload;
  final separator = payload.lastIndexOf(':');
  if (separator <= 'incoming_call:'.length) return payload;
  return payload.substring(0, separator);
}

abstract interface class IncomingCallWindowLeasePreferences {
  Future<bool> setString(String key, String value);

  Future<bool> setInt(String key, int value);

  Future<bool> remove(String key);
}

typedef IncomingCallWindowPreferences = IncomingCallWindowLeasePreferences;

final class SharedPreferencesIncomingCallWindowLeasePreferences
    implements IncomingCallWindowLeasePreferences {
  const SharedPreferencesIncomingCallWindowLeasePreferences(this._preferences);

  final SharedPreferences _preferences;

  @override
  Future<bool> remove(String key) => _preferences.remove(key);

  @override
  Future<bool> setInt(String key, int value) => _preferences.setInt(key, value);

  @override
  Future<bool> setString(String key, String value) =>
      _preferences.setString(key, value);
}

typedef SharedPreferencesIncomingCallWindowPreferences =
    SharedPreferencesIncomingCallWindowLeasePreferences;

class IncomingCallWindowLeasePrefs {
  static const String legacyRawTokenKey = 'toxee_incoming_call_window_token';
  static const String nonceDigestKey =
      'toxee_incoming_call_window_nonce_sha256';
  static const String callIdDigestKey =
      'toxee_incoming_call_window_call_id_sha256';
  static const String expiresAtEpochMsKey =
      'toxee_incoming_call_window_expires_at_epoch_ms';

  static const List<String> allKeys = <String>[
    legacyRawTokenKey,
    nonceDigestKey,
    callIdDigestKey,
    expiresAtEpochMsKey,
  ];
}

@immutable
final class IncomingCallWindowLeaseIssue {
  const IncomingCallWindowLeaseIssue({
    required this.callId,
    required this.nonce,
    required this.nonceDigest,
    required this.callDigest,
    required this.expiresAtEpochMs,
  });

  final String callId;
  final String nonce;
  final String nonceDigest;
  final String callDigest;
  final int expiresAtEpochMs;

  @override
  String toString() =>
      'IncomingCallWindowLeaseIssue(expiresAtEpochMs: $expiresAtEpochMs)';
}

typedef IncomingCallWindowLease = IncomingCallWindowLeaseIssue;

final class IncomingCallWindowLeaseStorageException implements Exception {
  const IncomingCallWindowLeaseStorageException(this.message);

  final String message;

  @override
  String toString() => 'IncomingCallWindowLeaseStorageException: $message';
}

final class IncomingCallWindowLeaseStore {
  IncomingCallWindowLeaseStore({
    SharedPreferences? prefs,
    IncomingCallWindowLeasePreferences? preferences,
    IncomingCallWindowClock? clock,
    IncomingCallWindowClock? now,
    IncomingCallWindowRandomBytes? randomBytes,
    Duration ttl = defaultTtl,
  }) : assert(prefs == null || preferences == null),
       assert(clock == null || now == null),
       _preferences =
           preferences ??
           (prefs == null
               ? null
               : SharedPreferencesIncomingCallWindowLeasePreferences(prefs)),
       _clock = clock ?? now ?? DateTime.now,
       _randomBytes = randomBytes ?? _secureRandomBytes,
       _ttl = ttl;

  static const Duration defaultTtl = incomingCallWindowLeaseTtl;
  static const int nonceByteLength = 32;
  static const int maxCallIdLength = 512;

  final IncomingCallWindowLeasePreferences? _preferences;
  final IncomingCallWindowClock _clock;
  final IncomingCallWindowRandomBytes _randomBytes;
  final Duration _ttl;

  Future<IncomingCallWindowLeaseIssue> issue(String callId) async {
    _validateCallId(callId);
    final preferences = await _resolvePreferences();
    await _clearWithPreferences(preferences);

    final nonce = _newNonce();
    final issue = IncomingCallWindowLeaseIssue(
      callId: callId,
      nonce: nonce,
      nonceDigest: _sha256Hex(nonce),
      callDigest: _callDigest(callId),
      expiresAtEpochMs: _clock().add(_ttl).millisecondsSinceEpoch,
    );

    try {
      await _requireWrite(
        preferences.setString(
          incomingCallWindowNonceDigestPrefsKey,
          issue.nonceDigest,
        ),
      );
      await _requireWrite(
        preferences.setString(
          incomingCallWindowCallDigestPrefsKey,
          issue.callDigest,
        ),
      );
      await _requireWrite(
        preferences.setInt(
          incomingCallWindowExpiresAtPrefsKey,
          issue.expiresAtEpochMs,
        ),
      );
      return issue;
    } catch (_, stackTrace) {
      try {
        await _clearWithPreferences(preferences);
      } catch (_) {
        Error.throwWithStackTrace(
          const IncomingCallWindowLeaseStorageException(
            'issue failed and rollback could not remove every lease key',
          ),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(
        const IncomingCallWindowLeaseStorageException('issue failed'),
        stackTrace,
      );
    }
  }

  Future<void> clear() async {
    await _clearWithPreferences(await _resolvePreferences());
  }

  Future<IncomingCallWindowLeasePreferences> _resolvePreferences() async {
    final preferences = _preferences;
    if (preferences != null) return preferences;
    return SharedPreferencesIncomingCallWindowLeasePreferences(
      await SharedPreferences.getInstance(),
    );
  }

  Future<void> _clearWithPreferences(
    IncomingCallWindowLeasePreferences preferences,
  ) async {
    var failed = false;
    for (final key in incomingCallWindowLeaseCleanupPreferenceKeys) {
      try {
        if (!await preferences.remove(key)) failed = true;
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

  static void _validateCallId(String callId) {
    if (callId.isEmpty ||
        callId.length > maxCallIdLength ||
        callId.trim() != callId ||
        callId.contains(':') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(callId)) {
      throw ArgumentError(
        'callId must be 1-512 code units, trimmed, and payload-delimiter safe',
      );
    }
  }

  String _newNonce() {
    final bytes = _randomBytes(nonceByteLength);
    if (bytes.length != nonceByteLength) {
      throw StateError(
        'Incoming-call nonce source returned ${bytes.length} bytes',
      );
    }
    return _hex(bytes);
  }

  static List<int> _secureRandomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(
      length,
      (_) => random.nextInt(0x100),
      growable: false,
    );
  }

  static String _callDigest(String callId) {
    return _sha256Hex('toxee.incoming-call.v1:$callId');
  }

  static String _sha256Hex(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  static String _hex(List<int> bytes) {
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  @visibleForTesting
  static String callIdentityDigestForTest(String callId) {
    return _callDigest(callId);
  }
}
