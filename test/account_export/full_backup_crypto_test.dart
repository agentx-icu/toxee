// Unit tests for `lib/util/account_export/full_backup_crypto.dart`.
//
// WHY THIS FILE IS WORTH TESTING (security boundary)
// --------------------------------------------------
// This module is the confidentiality boundary for the "full backup" feature:
// the exported `.zip` contains the account's Tox profile (i.e. the long-lived
// private key), the full chat history, avatars and the offline queue, and it
// leaves the device — into Downloads, a share sheet, cloud storage, wherever
// the user sends it. Everything protecting that blob lives in these ~320
// lines: PBKDF2-HMAC-SHA256 (150k iterations) → AES-256-GCM with a per-export
// salt and nonce, plus a strict metadata validator that refuses any parameter
// the exporter did not itself write.
//
// The existing `full_backup_encryption_test.dart` drives this module
// *indirectly* through `AccountExportService` (whole-file export/import), so
// it covers the happy path plus a handful of tamper cases. This file tests the
// module's own API directly, which is the only way to reach the branches that
// the service-level path cannot construct (version routing, malformed
// metadata containers, type confusion, nonce reuse across exports). The two
// files were written to be complementary, not overlapping: the salt/nonce/MAC
// *length* cases and the `iterations = 1 << 40` case already live in the
// service-level file and are deliberately not repeated here.
//
// COVERED
//   * `requireFullBackupExportPassword` accept/reject contract.
//   * `backupFormatVersion` / `readArchiveMetadata` parsing, including
//     malformed JSON, non-object JSON and non-UTF-8 bytes.
//   * `backupFormatVersion`'s absent-vs-malformed split: an absent (or null)
//     field is legacy v1, while a field that is present but not an integer is
//     damage and must be refused — degrading it to v1 used to make
//     `openFullBackupArchive` hand back the still-encrypted outer archive,
//     i.e. an import that "succeeds" and restores nothing.
//   * `openFullBackupArchive` version routing: v1 passthrough, unknown-low
//     version, too-new version, damaged version.
//   * encrypt → open round trip; the plaintext never appears in the outer
//     archive; the recorded KDF/cipher parameters match what was used.
//   * NONCE AND SALT ARE FRESH PER EXPORT. Reuse of an AES-GCM nonce under the
//     same key is a catastrophic, silent break, so this gets its own test.
//   * Authenticated decryption rejects: wrong password, flipped ciphertext
//     byte, truncated ciphertext, flipped MAC byte, and a nonce borrowed from
//     a different export of the same plaintext under the same password.
//   * The boundary between "decidable without the key" and "not decidable":
//     an empty payload is refused as damage before key derivation, while a
//     non-empty truncation is pinned as indistinguishable from a wrong
//     password (AEAD tag failure carries no cause), so it keeps the password
//     exception type and only the *message* names both possibilities.
//   * Metadata validation happens *before* key derivation and rejects a
//     renamed/missing payload entry, a lowered iteration count (KDF downgrade),
//     integer/string type confusion, missing or non-object `kdf`/`encryption`
//     containers, mismatched key sizes and invalid base64.
//
// NOT COVERED (and why)
//   * No test needs `libtim2tox_ffi`: this module is pure Dart (`archive` +
//     `cryptography`), so nothing here is skipped for a missing native library.
//   * The AAD constant cannot be varied from outside the module, so
//     "decryption with the wrong AAD fails" is not reachable; the nonce-swap
//     test is the closest reachable proxy for "context is authenticated".
//   * `_randomBytes` uses `Random.secure()`; its RNG quality is a platform
//     property, not something a unit test can meaningfully assert. The
//     freshness test asserts the observable consequence instead.
//
// COST NOTE: PBKDF2 at 150 000 iterations is intentionally slow. Every test
// below that actually derives a key carries an explicit generous timeout, and
// the two encrypted fixtures are built once and memoised for the whole suite.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/account_export/exceptions.dart';
import 'package:toxee/util/account_export/full_backup_crypto.dart';

const String _password = 'correct horse battery staple';
const String _plaintextSecret = 'PLAINTEXT_SECRET_4f21ab';
const String _plaintextEntryName = 'chat_history/conversation.json';
const Timeout _kdfTimeout = Timeout(Duration(minutes: 2));

// ─────────────────────────────────────────────────────────────────────────
// Fixtures
// ─────────────────────────────────────────────────────────────────────────

Archive _plaintextArchive() {
  final bytes = Uint8List.fromList(
    utf8.encode(jsonEncode(<String, String>{'message': _plaintextSecret})),
  );
  return Archive()
    ..addFile(ArchiveFile(_plaintextEntryName, bytes.length, bytes));
}

/// Round-trips an in-memory [Archive] through the zip codec so that every
/// archive handed to the module under test is a *decoded* archive, exactly as
/// it would be in production (`ZipDecoder().decodeBytes(File.readAsBytes())`).
Archive _zipRoundTrip(Archive archive) {
  return ZipDecoder().decodeBytes(ZipEncoder().encode(archive));
}

Future<Archive> _encryptFixture() async {
  final outer = await encryptFullBackupArchive(
    plaintextArchive: _plaintextArchive(),
    password: _password,
  );
  return _zipRoundTrip(outer);
}

// Memoised so the suite pays for PBKDF2 twice, not once per test.
Future<Archive>? _fixtureAFuture;
Future<Archive>? _fixtureBFuture;

Future<Archive> _fixtureA() => _fixtureAFuture ??= _encryptFixture();
Future<Archive> _fixtureB() => _fixtureBFuture ??= _encryptFixture();

Map<String, dynamic> _metadataOf(Archive outer) {
  final file = outer.findFile('metadata.json');
  expect(file, isNotNull, reason: 'fixture must carry metadata.json');
  return json.decode(utf8.decode(file!.content as List<int>))
      as Map<String, dynamic>;
}

Uint8List _payloadOf(Archive outer) {
  final file = outer.findFile(fullBackupPayloadEntryName);
  expect(file, isNotNull, reason: 'fixture must carry the encrypted payload');
  return Uint8List.fromList(file!.content as List<int>);
}

/// Rebuilds an outer backup archive from explicit parts. Passing
/// [payloadEntryName] different from [fullBackupPayloadEntryName] simulates a
/// renamed payload; passing a null [payload] simulates a missing one.
Archive _buildOuter({
  required Map<String, dynamic> metadata,
  Uint8List? payload,
  String payloadEntryName = fullBackupPayloadEntryName,
}) {
  final metadataBytes = Uint8List.fromList(utf8.encode(jsonEncode(metadata)));
  final archive = Archive()
    ..addFile(
      ArchiveFile('metadata.json', metadataBytes.length, metadataBytes),
    );
  if (payload != null) {
    archive.addFile(
      ArchiveFile(payloadEntryName, payload.length, payload),
    );
  }
  return _zipRoundTrip(archive);
}

Archive _archiveWithMetadataBytes(List<int> bytes) {
  final data = Uint8List.fromList(bytes);
  return _zipRoundTrip(
    Archive()..addFile(ArchiveFile('metadata.json', data.length, data)),
  );
}

/// A structurally valid v2 metadata map that is *not* backed by real
/// ciphertext. Every field matches what `encryptFullBackupArchive` writes, so
/// validation runs to completion and stops at the password check — which the
/// "control" test below asserts explicitly. Each negative test mutates exactly
/// one field, so a failure can only be attributed to that mutation.
Map<String, dynamic> _syntheticMetadata() {
  return <String, dynamic>{
    'formatVersion': 2,
    'payload': fullBackupPayloadEntryName,
    'kdf': <String, dynamic>{
      'algorithm': 'PBKDF2-HMAC-SHA256',
      'iterations': 150000,
      'bits': 256,
      'salt': base64Encode(Uint8List(32)),
    },
    'encryption': <String, dynamic>{
      'cipher': 'AES-GCM',
      'keyBits': 256,
      'nonce': base64Encode(Uint8List(12)),
      'mac': base64Encode(Uint8List(16)),
      'macBits': 128,
    },
  };
}

Uint8List _syntheticPayload() =>
    Uint8List.fromList(List<int>.generate(64, (int i) => i));

/// Builds a synthetic v2 archive whose metadata has been mutated by [mutate].
Archive _syntheticOuter([
  void Function(Map<String, dynamic> metadata)? mutate,
]) {
  final metadata = _syntheticMetadata();
  mutate?.call(metadata);
  return _buildOuter(metadata: metadata, payload: _syntheticPayload());
}

Uint8List _flipByte(Uint8List bytes, int index) {
  final copy = Uint8List.fromList(bytes);
  copy[index] ^= 0xFF;
  return copy;
}

bool _containsUtf8(List<int> bytes, String needle) {
  return utf8.decode(bytes, allowMalformed: true).contains(needle);
}

Matcher get _throwsInvalidFormat => throwsA(isA<InvalidBackupFormatException>());

// ─────────────────────────────────────────────────────────────────────────

void main() {
  group('requireFullBackupExportPassword', () {
    test('rejects a null password', () {
      expect(
        () => requireFullBackupExportPassword(null),
        throwsA(isA<PasswordRequiredException>()),
      );
    });

    test('rejects an empty password', () {
      expect(
        () => requireFullBackupExportPassword(''),
        throwsA(isA<PasswordRequiredException>()),
      );
    });

    test('accepts any non-empty password, including whitespace only', () {
      // Pins the actual contract: this guard checks *presence*, not strength
      // and not trimming. A caller that wants " " rejected must do it itself.
      expect(() => requireFullBackupExportPassword(' '), returnsNormally);
      expect(() => requireFullBackupExportPassword('p'), returnsNormally);
    });
  });

  group('backupFormatVersion', () {
    test('reads an integer version', () {
      expect(backupFormatVersion(<String, dynamic>{'formatVersion': 2}), 2);
      expect(backupFormatVersion(<String, dynamic>{'formatVersion': 7}), 7);
    });

    test('parses a numeric string version', () {
      expect(backupFormatVersion(<String, dynamic>{'formatVersion': '2'}), 2);
    });

    test('defaults to the legacy version when the field is absent', () {
      expect(
        backupFormatVersion(<String, dynamic>{}),
        fullBackupLegacyFormatVersion,
      );
    });

    test('treats an explicit null the same as an absent field', () {
      // JSON `"formatVersion": null` carries no more information than omitting
      // the key, so it keeps the legacy-compatibility default rather than being
      // treated as damage.
      expect(
        backupFormatVersion(<String, dynamic>{'formatVersion': null}),
        fullBackupLegacyFormatVersion,
      );
    });

    test('accepts a whole float, which is how some JSON writers emit ints', () {
      // Lossless spelling of an integer, so it is accepted and routed to the
      // decryptor. What must never happen is the silent downgrade to v1 that
      // the next test pins.
      expect(backupFormatVersion(<String, dynamic>{'formatVersion': 2.0}), 2);
    });

    test('rejects a present-but-malformed version instead of degrading to v1',
        () {
      // THE REGRESSION THIS GUARDS: a `formatVersion` that is present but not
      // an integer used to fall back to v1, and `openFullBackupArchive` then
      // returned the still-encrypted outer archive as if it were the restore
      // payload — an import that "succeeds" and restores nothing. Absent means
      // legacy; malformed means damaged.
      // Deliberately non-nullable: `null` is the *absent* case handled above,
      // so it must not drift into this list.
      for (final Object malformed in <Object>[
        'v2',
        '',
        '2.5',
        2.5,
        double.nan,
        true,
        <int>[2],
        <String, dynamic>{'value': 2},
      ]) {
        expect(
          () => backupFormatVersion(<String, dynamic>{
            'formatVersion': malformed,
          }),
          throwsA(
            isA<InvalidBackupFormatException>().having(
              (InvalidBackupFormatException e) => e.message,
              'message',
              contains('formatVersion'),
            ),
          ),
          reason: 'formatVersion=$malformed must not degrade to v1',
        );
      }
    });
  });

  group('readArchiveMetadata', () {
    test('returns an empty map when metadata.json is absent', () {
      final payload = _syntheticPayload();
      final archive = _zipRoundTrip(
        Archive()
          ..addFile(ArchiveFile('other.bin', payload.length, payload)),
      );
      expect(readArchiveMetadata(archive), isEmpty);
    });

    test('parses a JSON object', () {
      final metadata = readArchiveMetadata(
        _archiveWithMetadataBytes(
          utf8.encode(jsonEncode(<String, dynamic>{'formatVersion': 2})),
        ),
      );
      expect(metadata['formatVersion'], 2);
    });

    test('rejects malformed JSON', () {
      expect(
        () => readArchiveMetadata(
          _archiveWithMetadataBytes(utf8.encode('{"formatVersion": ')),
        ),
        _throwsInvalidFormat,
      );
    });

    test('rejects JSON that is not an object', () {
      expect(
        () => readArchiveMetadata(
          _archiveWithMetadataBytes(utf8.encode('[1, 2, 3]')),
        ),
        throwsA(
          isA<InvalidBackupFormatException>().having(
            (InvalidBackupFormatException e) => e.message,
            'message',
            contains('not an object'),
          ),
        ),
      );
      expect(
        () => readArchiveMetadata(
          _archiveWithMetadataBytes(utf8.encode('42')),
        ),
        _throwsInvalidFormat,
      );
    });

    test('rejects metadata that is not valid UTF-8', () {
      // 0xFF is never a legal UTF-8 byte; `utf8.decode` throws FormatException
      // and must surface as the typed backup error, not as a raw crash.
      expect(
        () => readArchiveMetadata(
          _archiveWithMetadataBytes(<int>[0xFF, 0xFE, 0x7B, 0x7D]),
        ),
        _throwsInvalidFormat,
      );
    });
  });

  group('openFullBackupArchive version routing', () {
    test('a v1 archive is returned untouched and needs no password', () async {
      final payload = _syntheticPayload();
      final legacy = _buildOuter(
        metadata: <String, dynamic>{'formatVersion': 1, 'toxId': 'legacy'},
        payload: payload,
      );

      final opened = await openFullBackupArchive(outerArchive: legacy);

      expect(identical(opened, legacy), isTrue);
      expect(opened.findFile(fullBackupPayloadEntryName), isNotNull);
    });

    test('an archive without metadata is treated as legacy v1', () async {
      final payload = _syntheticPayload();
      final bare = _zipRoundTrip(
        Archive()..addFile(ArchiveFile('data.bin', payload.length, payload)),
      );

      final opened = await openFullBackupArchive(outerArchive: bare);

      expect(identical(opened, bare), isTrue);
    });

    test('a newer format version is refused with an upgrade hint', () async {
      final outer = _syntheticOuter((Map<String, dynamic> metadata) {
        metadata['formatVersion'] = 3;
      });

      await expectLater(
        () => openFullBackupArchive(outerArchive: outer, password: _password),
        throwsA(
          isA<InvalidBackupFormatException>().having(
            (InvalidBackupFormatException e) => e.message,
            'message',
            contains('newer than this app supports'),
          ),
        ),
      );
    });

    test('an unknown low version is refused', () async {
      final outer = _syntheticOuter((Map<String, dynamic> metadata) {
        metadata['formatVersion'] = 0;
      });

      await expectLater(
        () => openFullBackupArchive(outerArchive: outer, password: _password),
        throwsA(
          isA<InvalidBackupFormatException>().having(
            (InvalidBackupFormatException e) => e.message,
            'message',
            contains('Unsupported backup format version: 0'),
          ),
        ),
      );
    });

    test('a v2 archive with a damaged formatVersion is refused, not returned '
        'as if it were plaintext', () async {
      // End-to-end shape of the silent-failure bug: `formatVersion` degrading
      // to v1 made this call return the *outer* (still encrypted) archive, and
      // the importer then walked an archive containing only `metadata.json`
      // and `payload.enc` — no profile, no chat history — and reported
      // success. The archive must be refused instead.
      for (final Object malformed in <Object>['v2', 2.5, true]) {
        final outer = _syntheticOuter((Map<String, dynamic> metadata) {
          metadata['formatVersion'] = malformed;
        });

        await expectLater(
          () => openFullBackupArchive(outerArchive: outer, password: _password),
          _throwsInvalidFormat,
          reason: 'formatVersion=$malformed',
        );
      }
    });
  });

  group('encrypt → open round trip', () {
    test('restores the exact plaintext archive under the correct password',
        () async {
      final outer = await _fixtureA();

      final inner = await openFullBackupArchive(
        outerArchive: outer,
        password: _password,
      );

      final restored = inner.findFile(_plaintextEntryName);
      expect(restored, isNotNull);
      expect(
        utf8.decode(restored!.content as List<int>),
        jsonEncode(<String, String>{'message': _plaintextSecret}),
      );
    }, timeout: _kdfTimeout);

    test('the outer archive carries only metadata and ciphertext', () async {
      final outer = await _fixtureA();

      expect(
        outer.files.where((ArchiveFile f) => f.isFile).map((f) => f.name),
        unorderedEquals(<String>['metadata.json', fullBackupPayloadEntryName]),
      );
      expect(outer.findFile(_plaintextEntryName), isNull);
      expect(
        _containsUtf8(_payloadOf(outer), _plaintextSecret),
        isFalse,
        reason: 'ciphertext must not expose the plaintext',
      );
      expect(
        jsonEncode(_metadataOf(outer)).contains(_plaintextSecret),
        isFalse,
        reason: 'metadata must not expose the plaintext',
      );
    }, timeout: _kdfTimeout);

    test('metadata records exactly the KDF and cipher parameters used',
        () async {
      final metadata = _metadataOf(await _fixtureA());
      final kdf = metadata['kdf'] as Map<String, dynamic>;
      final encryption = metadata['encryption'] as Map<String, dynamic>;

      expect(metadata['formatVersion'], fullBackupEncryptedFormatVersion);
      expect(metadata['payload'], fullBackupPayloadEntryName);
      expect(kdf['algorithm'], 'PBKDF2-HMAC-SHA256');
      expect(kdf['iterations'], 150000);
      expect(kdf['bits'], 256);
      expect(base64Decode(kdf['salt'] as String), hasLength(32));
      expect(encryption['cipher'], 'AES-GCM');
      expect(encryption['keyBits'], 256);
      expect(encryption['macBits'], 128);
      expect(base64Decode(encryption['nonce'] as String), hasLength(12));
      expect(base64Decode(encryption['mac'] as String), hasLength(16));
    }, timeout: _kdfTimeout);

    test('two exports of identical input use a fresh salt, nonce and '
        'ciphertext', () async {
      // AES-GCM nonce reuse under the same key destroys both confidentiality
      // and authenticity, and a reused salt would make the derived key reusable
      // across exports. This is the single most important property here.
      final a = _metadataOf(await _fixtureA());
      final b = _metadataOf(await _fixtureB());
      final kdfA = a['kdf'] as Map<String, dynamic>;
      final kdfB = b['kdf'] as Map<String, dynamic>;
      final encA = a['encryption'] as Map<String, dynamic>;
      final encB = b['encryption'] as Map<String, dynamic>;

      expect(kdfA['salt'], isNot(equals(kdfB['salt'])));
      expect(encA['nonce'], isNot(equals(encB['nonce'])));
      expect(encA['mac'], isNot(equals(encB['mac'])));
      expect(
        _payloadOf(await _fixtureA()),
        isNot(equals(_payloadOf(await _fixtureB()))),
      );
    }, timeout: _kdfTimeout);
  });

  group('authenticated decryption rejects tampering', () {
    test('a wrong password fails with InvalidBackupPasswordException',
        () async {
      final outer = await _fixtureA();

      await expectLater(
        () => openFullBackupArchive(
          outerArchive: outer,
          password: 'not the export password',
        ),
        throwsA(isA<InvalidBackupPasswordException>()),
      );
    }, timeout: _kdfTimeout);

    test('a v2 archive without a password asks for one instead of failing '
        'decryption', () async {
      // Typed as PasswordRequiredException (not InvalidBackupPassword) so the
      // UI can prompt instead of accusing the user of a typo.
      final outer = await _fixtureA();

      await expectLater(
        () => openFullBackupArchive(outerArchive: outer),
        throwsA(isA<PasswordRequiredException>()),
      );
      await expectLater(
        () => openFullBackupArchive(outerArchive: outer, password: ''),
        throwsA(isA<PasswordRequiredException>()),
      );
    }, timeout: _kdfTimeout);

    test('a flipped ciphertext byte fails authentication', () async {
      final outer = await _fixtureA();
      final tampered = _buildOuter(
        metadata: _metadataOf(outer),
        payload: _flipByte(_payloadOf(outer), 0),
      );

      await expectLater(
        () =>
            openFullBackupArchive(outerArchive: tampered, password: _password),
        throwsA(isA<InvalidBackupPasswordException>()),
      );
    }, timeout: _kdfTimeout);

    test('a truncated ciphertext fails authentication and is reported as a '
        'password-or-tamper failure', () async {
      // Pinned deliberately as *not* distinguishable from a wrong password.
      // GCM ciphertext carries no length field, so a payload that is short by
      // eight bytes is syntactically indistinguishable from a correct one and
      // only the tag check rejects it — with the same error a wrong key
      // produces. The type therefore stays InvalidBackupPasswordException (the
      // UI keeps prompting for a password, which is the likelier cause), and
      // the message is required to name the other possibility rather than
      // asserting a cause the primitive cannot supply.
      final outer = await _fixtureA();
      final full = _payloadOf(outer);
      final tampered = _buildOuter(
        metadata: _metadataOf(outer),
        payload: full.sublist(0, full.length - 8),
      );

      await expectLater(
        () =>
            openFullBackupArchive(outerArchive: tampered, password: _password),
        throwsA(
          isA<InvalidBackupPasswordException>().having(
            (InvalidBackupPasswordException e) => e.message,
            'message',
            allOf(contains('password is wrong'), contains('truncated')),
          ),
        ),
      );
    }, timeout: _kdfTimeout);

    test('an empty payload is reported as damage, not as a wrong password',
        () async {
      // The one truncation that IS decidable without the key: the exporter
      // refuses to encrypt an empty zip, so a zero-length `payload.enc` cannot
      // have come from it. Rejected before key derivation, so this test needs
      // no PBKDF2 fixture and no extended timeout — which is itself the point:
      // structural damage is classified without ever touching the password.
      final damaged = _buildOuter(
        metadata: _syntheticMetadata(),
        payload: Uint8List(0),
      );

      await expectLater(
        () => openFullBackupArchive(outerArchive: damaged, password: _password),
        throwsA(
          isA<InvalidBackupFormatException>().having(
            (InvalidBackupFormatException e) => e.message,
            'message',
            contains('damaged'),
          ),
        ),
      );
    });

    test('a flipped MAC byte fails authentication', () async {
      final outer = await _fixtureA();
      final metadata = _metadataOf(outer);
      final encryption = metadata['encryption'] as Map<String, dynamic>;
      encryption['mac'] = base64Encode(
        _flipByte(
          Uint8List.fromList(base64Decode(encryption['mac'] as String)),
          0,
        ),
      );
      final tampered = _buildOuter(
        metadata: metadata,
        payload: _payloadOf(outer),
      );

      await expectLater(
        () =>
            openFullBackupArchive(outerArchive: tampered, password: _password),
        throwsA(isA<InvalidBackupPasswordException>()),
      );
    }, timeout: _kdfTimeout);

    test('a nonce borrowed from another export fails authentication',
        () async {
      // Same password and same salt (so the same key), but the nonce from a
      // different export. GCM authenticates the nonce, so this must not decrypt
      // even though every declared parameter is individually well formed.
      final outer = await _fixtureA();
      final metadata = _metadataOf(outer);
      final foreign = _metadataOf(await _fixtureB());
      (metadata['encryption'] as Map<String, dynamic>)['nonce'] =
          (foreign['encryption'] as Map<String, dynamic>)['nonce'];
      final tampered = _buildOuter(
        metadata: metadata,
        payload: _payloadOf(outer),
      );

      await expectLater(
        () =>
            openFullBackupArchive(outerArchive: tampered, password: _password),
        throwsA(isA<InvalidBackupPasswordException>()),
      );
    }, timeout: _kdfTimeout);
  });

  group('metadata validation runs before key derivation', () {
    test('control: an otherwise valid synthetic archive reaches the password '
        'check', () async {
      // Anchors the whole group. Every negative case below reuses this exact
      // metadata with a single field mutated, so each failure is attributable
      // to that mutation and not to the fixture being malformed to begin with.
      await expectLater(
        () => openFullBackupArchive(outerArchive: _syntheticOuter()),
        throwsA(isA<PasswordRequiredException>()),
      );
    });

    test('rejects a renamed payload entry', () async {
      final outer = _buildOuter(
        metadata: _syntheticMetadata()..['payload'] = 'data.bin',
        payload: _syntheticPayload(),
        payloadEntryName: 'data.bin',
      );

      await expectLater(
        () => openFullBackupArchive(outerArchive: outer, password: _password),
        throwsA(
          isA<InvalidBackupFormatException>().having(
            (InvalidBackupFormatException e) => e.message,
            'message',
            contains('payload entry'),
          ),
        ),
      );
    });

    test('rejects a missing payload entry', () async {
      final outer = _buildOuter(metadata: _syntheticMetadata());

      await expectLater(
        () => openFullBackupArchive(outerArchive: outer, password: _password),
        throwsA(
          isA<InvalidBackupFormatException>().having(
            (InvalidBackupFormatException e) => e.message,
            'message',
            contains('payload is missing'),
          ),
        ),
      );
    });

    test('rejects a lowered KDF iteration count', () async {
      // A downgrade to 1 000 iterations would make offline password cracking
      // ~150x cheaper while still decrypting correctly, so it must be refused
      // on the *reader* side even though the ciphertext is otherwise fine.
      final outer = _syntheticOuter((Map<String, dynamic> metadata) {
        (metadata['kdf'] as Map<String, dynamic>)['iterations'] = 1000;
      });

      await expectLater(
        () => openFullBackupArchive(outerArchive: outer, password: _password),
        _throwsInvalidFormat,
      );
    });

    test('rejects a stringified iteration count (type confusion)', () async {
      final outer = _syntheticOuter((Map<String, dynamic> metadata) {
        (metadata['kdf'] as Map<String, dynamic>)['iterations'] = '150000';
      });

      await expectLater(
        () => openFullBackupArchive(outerArchive: outer, password: _password),
        _throwsInvalidFormat,
      );
    });

    test('rejects a missing kdf container', () async {
      final outer = _syntheticOuter((Map<String, dynamic> metadata) {
        metadata.remove('kdf');
      });

      await expectLater(
        () => openFullBackupArchive(outerArchive: outer, password: _password),
        _throwsInvalidFormat,
      );
    });

    test('rejects a non-object kdf container', () async {
      final outer = _syntheticOuter((Map<String, dynamic> metadata) {
        metadata['kdf'] = 'PBKDF2-HMAC-SHA256';
      });

      await expectLater(
        () => openFullBackupArchive(outerArchive: outer, password: _password),
        _throwsInvalidFormat,
      );
    });

    test('rejects a missing encryption container', () async {
      final outer = _syntheticOuter((Map<String, dynamic> metadata) {
        metadata.remove('encryption');
      });

      await expectLater(
        () => openFullBackupArchive(outerArchive: outer, password: _password),
        _throwsInvalidFormat,
      );
    });

    test('rejects a shortened cipher key size', () async {
      final outer = _syntheticOuter((Map<String, dynamic> metadata) {
        (metadata['encryption'] as Map<String, dynamic>)['keyBits'] = 128;
      });

      await expectLater(
        () => openFullBackupArchive(outerArchive: outer, password: _password),
        _throwsInvalidFormat,
      );
    });

    test('rejects a shortened derived key size', () async {
      final outer = _syntheticOuter((Map<String, dynamic> metadata) {
        (metadata['kdf'] as Map<String, dynamic>)['bits'] = 128;
      });

      await expectLater(
        () => openFullBackupArchive(outerArchive: outer, password: _password),
        _throwsInvalidFormat,
      );
    });

    test('rejects a salt that is not valid base64', () async {
      final outer = _syntheticOuter((Map<String, dynamic> metadata) {
        (metadata['kdf'] as Map<String, dynamic>)['salt'] = 'not-base64!!!';
      });

      await expectLater(
        () => openFullBackupArchive(outerArchive: outer, password: _password),
        throwsA(
          isA<InvalidBackupFormatException>().having(
            (InvalidBackupFormatException e) => e.message,
            'message',
            contains('invalid base64'),
          ),
        ),
      );
    });

    test('rejects a missing nonce', () async {
      final outer = _syntheticOuter((Map<String, dynamic> metadata) {
        (metadata['encryption'] as Map<String, dynamic>).remove('nonce');
      });

      await expectLater(
        () => openFullBackupArchive(outerArchive: outer, password: _password),
        _throwsInvalidFormat,
      );
    });
  });
}
