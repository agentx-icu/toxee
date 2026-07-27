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
    throw InvalidBackupFormatException('Backup metadata is malformed: $e');
  }
  throw const InvalidBackupFormatException('Backup metadata is not an object');
}

int backupFormatVersion(Map<String, dynamic> metadata) {
  final rawVersion = metadata['formatVersion'];
  if (rawVersion is int) return rawVersion;
  return int.tryParse(rawVersion?.toString() ?? '') ??
      fullBackupLegacyFormatVersion;
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
  final secretBox = SecretBox(
    Uint8List.fromList(payloadFile.content as List<int>),
    nonce: nonce,
    mac: Mac(mac),
  );

  try {
    final plaintextZip = await _cipher.decrypt(
      secretBox,
      secretKey: secretKey,
      aad: _aad,
    );
    return ZipDecoder().decodeBytes(plaintextZip);
  } on SecretBoxAuthenticationError catch (_) {
    throw const InvalidBackupPasswordException(
      'Authenticated decryption failed for encrypted full backup',
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
