import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';

import 'exceptions.dart';

const int fullBackupLegacyFormatVersion = 1;
const int fullBackupEncryptedFormatVersion = 2;
const String fullBackupPayloadEntryName = 'payload.enc';

const int _kdfIterations = 150000;
const int _kdfBits = 256;
const int _saltLength = 32;
const int _nonceLength = 12;
const int _macLength = 16;
const int _macBits = _macLength * 8;
const String _cipherName = 'AES-GCM';
const String _kdfName = 'PBKDF2-HMAC-SHA256';
const List<int> _aad = <int>[
  0x74,
  0x6f,
  0x78,
  0x65,
  0x65,
  0x2d,
  0x66,
  0x75,
  0x6c,
  0x6c,
  0x2d,
  0x62,
  0x61,
  0x63,
  0x6b,
  0x75,
  0x70,
  0x2d,
  0x76,
  0x32,
];

final AesGcm _cipher = AesGcm.with256bits();

void requireFullBackupExportPassword(String? password) {
  if (password == null || password.isEmpty) {
    throw const PasswordRequiredException(
      'Password required for encrypted full backup',
    );
  }
}

Future<Archive> encryptFullBackupArchive({
  required Archive plaintextArchive,
  required String password,
}) async {
  requireFullBackupExportPassword(password);

  final plaintextZip = ZipEncoder().encode(plaintextArchive);
  // ignore: unnecessary_null_comparison
  if (plaintextZip == null || plaintextZip.isEmpty) {
    throw Exception('Export produced empty archive');
  }

  final salt = _randomBytes(_saltLength);
  final nonce = _cipher.newNonce();
  final secretKey = await _deriveKey(
    password: password,
    salt: salt,
    iterations: _kdfIterations,
    bits: _kdfBits,
  );
  final secretBox = await _cipher.encrypt(
    plaintextZip,
    secretKey: secretKey,
    nonce: nonce,
    aad: _aad,
  );

  final metadata = <String, dynamic>{
    'formatVersion': fullBackupEncryptedFormatVersion,
    'payload': fullBackupPayloadEntryName,
    'kdf': <String, dynamic>{
      'algorithm': _kdfName,
      'iterations': _kdfIterations,
      'bits': _kdfBits,
      'salt': base64Encode(salt),
    },
    'encryption': <String, dynamic>{
      'cipher': _cipherName,
      'keyBits': _kdfBits,
      'nonce': base64Encode(nonce),
      'mac': base64Encode(secretBox.mac.bytes),
      'macBits': _macBits,
    },
  };

  final metadataBytes = utf8.encode(
    const JsonEncoder.withIndent('  ').convert(metadata),
  );
  final outer = Archive();
  outer.addFile(
    ArchiveFile(
      'metadata.json',
      metadataBytes.length,
      Uint8List.fromList(metadataBytes),
    ),
  );
  outer.addFile(
    ArchiveFile(
      fullBackupPayloadEntryName,
      secretBox.cipherText.length,
      Uint8List.fromList(secretBox.cipherText),
    ),
  );
  return outer;
}

Future<Archive> openFullBackupArchive({
  required Archive outerArchive,
  String? password,
}) async {
  final outerMetadata = readArchiveMetadata(outerArchive);
  final version = backupFormatVersion(outerMetadata);
  if (version == fullBackupLegacyFormatVersion) {
    return outerArchive;
  }
  if (version > fullBackupEncryptedFormatVersion) {
    throw InvalidBackupFormatException(
      'Backup format version $version is newer than this app supports '
      '($fullBackupEncryptedFormatVersion). Upgrade the app to import this backup.',
    );
  }
  if (version != fullBackupEncryptedFormatVersion) {
    throw InvalidBackupFormatException(
      'Unsupported backup format version: $version',
    );
  }
  return _decryptEncryptedArchive(
    outerArchive: outerArchive,
    outerMetadata: outerMetadata,
    password: password,
  );
}

Map<String, dynamic> readArchiveMetadata(Archive archive) {
  final metadataFile = archive.findFile('metadata.json');
  if (metadataFile == null) return <String, dynamic>{};
  try {
    final decoded = json.decode(utf8.decode(metadataFile.content as List<int>));
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on FormatException catch (e) {
    // PRIVACY: do NOT interpolate `$e`. `FormatException.toString()` appends an
    // excerpt of `source` around `offset` when both are set, and `json.decode`
    // sets both — so the excerpt would be raw `metadata.json`, which carries the
    // nickname, the Tox ID and scoped prefs (friend avatar paths). That string
    // then reaches `flutter_client.log` verbatim via
    // `AppLogger.logError` -> `_emit(LogLevel.error, 'Error: $error')`
    // (lib/util/logger.dart:360) — the file users attach to bug reports.
    // `message` + `offset` are the diagnostic bits; neither quotes the source.
    throw InvalidBackupFormatException(
      'Backup metadata is malformed (${e.message} at offset ${e.offset})',
    );
  }
  throw const InvalidBackupFormatException('Backup metadata is not an object');
}

/// Reads the `formatVersion` out of backup metadata.
///
/// ABSENT vs MALFORMED is the whole point of this function:
///
///  * **Absent** (or explicitly `null`) means *legacy v1*. toxee builds that
///    predate the version field wrote no `formatVersion` at all and their
///    archives are plaintext, so defaulting to
///    [fullBackupLegacyFormatVersion] is the documented compatibility contract
///    (see `full_backup.dart`).
///  * **Present but not an integer** is not a v1 archive — it is a damaged
///    v2 one. Degrading it to v1 would make [openFullBackupArchive] hand the
///    still-encrypted *outer* archive straight back to the importer, which
///    then finds no `tox_profile.tox` and no `chat_history/` and "restores"
///    nothing while reporting success. Fail loudly instead.
///
/// A JSON number that happens to be encoded as a whole float (`2.0`, which is
/// what several JSON writers emit for integers) and a numeric string (`"2"`)
/// are accepted: both are lossless spellings of an integer, and accepting them
/// still routes the archive to the decryptor rather than silently downgrading
/// it. Anything else — `"v2"`, `2.5`, `true`, a list — throws.
int backupFormatVersion(Map<String, dynamic> metadata) {
  final rawVersion = metadata['formatVersion'];
  if (rawVersion == null) return fullBackupLegacyFormatVersion;
  if (rawVersion is int) return rawVersion;
  if (rawVersion is double &&
      rawVersion.isFinite &&
      rawVersion == rawVersion.roundToDouble()) {
    return rawVersion.toInt();
  }
  if (rawVersion is String) {
    final parsed = int.tryParse(rawVersion.trim());
    if (parsed != null) return parsed;
  }
  throw const InvalidBackupFormatException(
    'Backup metadata formatVersion is not an integer; the archive is damaged',
  );
}

Future<Archive> _decryptEncryptedArchive({
  required Archive outerArchive,
  required Map<String, dynamic> outerMetadata,
  required String? password,
}) async {
  final payloadName = _requiredString(outerMetadata, 'payload');
  if (payloadName != fullBackupPayloadEntryName) {
    throw const InvalidBackupFormatException(
      'Unsupported encrypted full backup payload entry',
    );
  }
  final payloadFile = outerArchive.findFile(payloadName);
  if (payloadFile == null) {
    throw const InvalidBackupFormatException(
      'Encrypted full backup payload is missing',
    );
  }
  final rawPayload = payloadFile.content;
  final cipherText = rawPayload is List<int>
      ? Uint8List.fromList(rawPayload)
      : Uint8List(0);
  // AES-GCM is length preserving, and [encryptFullBackupArchive] refuses to
  // encrypt an empty zip, so a zero-length payload cannot have been produced by
  // this exporter: the file was truncated or the entry was replaced. That is
  // decidable without the password, so report it as damage rather than letting
  // it fall through to the MAC check and come back as "wrong password".
  //
  // A payload that is truncated but still non-empty is NOT decidable here: GCM
  // ciphertext carries no length field, so every byte length is syntactically
  // valid and only the MAC rejects it. See the catch block below.
  if (cipherText.isEmpty) {
    throw const InvalidBackupFormatException(
      'Encrypted full backup payload is empty or unreadable; '
      'the archive is damaged',
    );
  }

  final kdf = _requiredMap(outerMetadata, 'kdf');
  final encryption = _requiredMap(outerMetadata, 'encryption');
  final kdfName = _requiredString(kdf, 'algorithm');
  final cipherName = _requiredString(encryption, 'cipher');
  final iterations = _requiredInt(kdf, 'iterations');
  final bits = _requiredInt(kdf, 'bits');
  final keyBits = _requiredInt(encryption, 'keyBits');
  final macBits = _requiredInt(encryption, 'macBits');
  if (kdfName != _kdfName ||
      cipherName != _cipherName ||
      iterations != _kdfIterations ||
      bits != _kdfBits ||
      keyBits != _kdfBits ||
      macBits != _macBits) {
    throw const InvalidBackupFormatException(
      'Unsupported encrypted full backup parameters',
    );
  }

  final salt = _decodeBase64Field(kdf, 'salt');
  final nonce = _decodeBase64Field(encryption, 'nonce');
  final mac = _decodeBase64Field(encryption, 'mac');
  _requireLength(salt, _saltLength, 'salt');
  _requireLength(nonce, _nonceLength, 'nonce');
  _requireLength(mac, _macLength, 'MAC');

  requireFullBackupExportPassword(password);
  final secretKey = await _deriveKey(
    password: password!,
    salt: salt,
    iterations: iterations,
    bits: bits,
  );
  final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));

  try {
    final plaintextZip = await _cipher.decrypt(
      secretBox,
      secretKey: secretKey,
      aad: _aad,
    );
    return ZipDecoder().decodeBytes(plaintextZip);
  } on SecretBoxAuthenticationError catch (_) {
    // A MAC failure is DELIBERATELY not split into "wrong password" and
    // "tampered ciphertext". That distinction does not exist at this layer: an
    // AEAD tag check fails identically for a wrong key, a flipped ciphertext
    // byte, a truncated payload and a swapped nonce — that indistinguishability
    // is the design of the primitive, not a gap in this code. Inventing a
    // separate "tampered" exception here could only ever be a guess, and a
    // wrong guess ("this backup was tampered with") is worse than a vague one.
    //
    // Everything that IS decidable without the key is already rejected above as
    // InvalidBackupFormatException: wrong salt/nonce/MAC lengths, invalid
    // base64, downgraded KDF parameters, a renamed/missing/empty payload. So
    // by the time control reaches here the archive is structurally intact and
    // "wrong password" is the single most likely cause — which is why the type
    // stays InvalidBackupPasswordException and the UI keeps prompting for a
    // password. The message names the other possibility instead of asserting a
    // cause it cannot know.
    throw const InvalidBackupPasswordException(
      'Authenticated decryption failed for encrypted full backup: the '
      'password is wrong, or the payload was modified or truncated',
    );
  } on FormatException catch (e) {
    throw InvalidBackupFormatException(
      'Decrypted full backup payload is not a valid zip: $e',
    );
  }
}

Future<SecretKey> _deriveKey({
  required String password,
  required List<int> salt,
  required int iterations,
  required int bits,
}) {
  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: bits,
  );
  return pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> metadata, String key) {
  final value = metadata[key];
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    try {
      return Map<String, dynamic>.from(value);
    } on TypeError {
      // Fall through to the typed format exception below.
    }
  }
  throw InvalidBackupFormatException(
    'Encrypted full backup metadata missing object $key',
  );
}

int _requiredInt(Map<String, dynamic> metadata, String key) {
  final value = metadata[key];
  if (value is int) return value;
  throw InvalidBackupFormatException(
    'Encrypted full backup metadata missing integer $key',
  );
}

String _requiredString(Map<String, dynamic> metadata, String key) {
  final value = metadata[key];
  if (value is String && value.isNotEmpty) return value;
  throw InvalidBackupFormatException(
    'Encrypted full backup metadata missing string $key',
  );
}

Uint8List _decodeBase64Field(Map<String, dynamic> metadata, String key) {
  final value = metadata[key];
  if (value is! String || value.isEmpty) {
    throw InvalidBackupFormatException(
      'Encrypted full backup metadata missing $key',
    );
  }
  try {
    return Uint8List.fromList(base64Decode(value));
  } on FormatException {
    throw InvalidBackupFormatException(
      'Encrypted full backup metadata has invalid base64 $key',
    );
  }
}

void _requireLength(List<int> value, int expected, String name) {
  if (value.length != expected) {
    throw InvalidBackupFormatException(
      'Encrypted full backup $name must be exactly $expected bytes',
    );
  }
}

Uint8List _randomBytes(int length) {
  final random = Random.secure();
  final out = Uint8List(length);
  for (var i = 0; i < out.length; i++) {
    out[i] = random.nextInt(256);
  }
  return out;
}
