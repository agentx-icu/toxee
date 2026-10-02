// Tox profile encryption / decryption helpers used by both the .tox
// import-export path and the in-place encrypt/decrypt-on-disk helpers.
//
// All FFI plumbing (malloc, asTypedList, free) is isolated here so the
// callers can stay declarative.
//
// Buffer ownership: every Uint8List that crosses this module's boundary
// (returned from passEncrypt/passDecrypt, or handed to File.writeAsBytes)
// is a Dart-owned copy of the FFI buffer, made via Uint8List.fromList
// before the finally-block free runs. The previous implementation returned
// asTypedList views over freed memory; in some allocators that produced
// garbage ciphertext on disk for encrypted profiles. See the
// encrypted-roundtrip regression test in test/account_export/.

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkgffi;
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';

import '../secret_password.dart';
import 'exceptions.dart';
import 'ffi_constants.dart';

/// Encrypts [plaintext] with [password] using Tox's `tox_pass_encrypt`
/// implementation. Returns the freshly-allocated ciphertext as a Uint8List
/// of length `plaintext.length + toxPassEncryptionExtraLength`.
///
/// Throws an [Exception] if the underlying FFI call returns a negative
/// length (encryption failed for any reason).
Uint8List passEncrypt(Uint8List plaintext, SecretPassword password) =>
    password.withBytes((bytes) => passEncryptBytes(plaintext, bytes));

/// [passEncrypt] over raw UTF-8 password bytes, which are borrowed: copied
/// into native memory, that copy zeroed, the caller's buffer untouched.
Uint8List passEncryptBytes(Uint8List plaintext, Uint8List passwordBytes) {
  final ffiLib = Tim2ToxFfi.open();
  final plaintextPtr = pkgffi.malloc<ffi.Uint8>(plaintext.length);
  final ciphertextPtr =
      pkgffi.malloc<ffi.Uint8>(plaintext.length + toxPassEncryptionExtraLength);
  try {
    plaintextPtr.asTypedList(plaintext.length).setAll(0, plaintext);
    final encryptedLen = _withNativePassword(
      passwordBytes,
      (passwordPtr, passwordLen) => ffiLib.passEncryptNative(
        plaintextPtr,
        plaintext.length,
        passwordPtr,
        passwordLen,
        ciphertextPtr,
        plaintext.length + toxPassEncryptionExtraLength,
      ),
    );
    if (encryptedLen < 0) {
      throw Exception('Encryption failed');
    }
    return Uint8List.fromList(ciphertextPtr.asTypedList(encryptedLen));
  } finally {
    pkgffi.malloc.free(plaintextPtr);
    pkgffi.malloc.free(ciphertextPtr);
  }
}

/// Decrypts [ciphertext] with [password] using Tox's `tox_pass_decrypt`.
/// Returns the freshly-allocated plaintext as a Uint8List of length
/// `ciphertext.length - toxPassEncryptionExtraLength`.
///
/// Throws an [Exception] if the FFI call returns a negative length
/// (wrong password, corrupted blob, or any other tox decryption error).
Uint8List passDecrypt(Uint8List ciphertext, SecretPassword password) =>
    password.withBytes((bytes) => passDecryptBytes(ciphertext, bytes));

/// [passDecrypt] over raw UTF-8 password bytes (borrowed; see
/// [passEncryptBytes]).
Uint8List passDecryptBytes(Uint8List ciphertext, Uint8List passwordBytes) {
  final ffiLib = Tim2ToxFfi.open();
  final ciphertextPtr = pkgffi.malloc<ffi.Uint8>(ciphertext.length);
  final plaintextPtr = pkgffi
      .malloc<ffi.Uint8>(ciphertext.length - toxPassEncryptionExtraLength);
  try {
    ciphertextPtr.asTypedList(ciphertext.length).setAll(0, ciphertext);
    final decryptedLen = _withNativePassword(
      passwordBytes,
      (passwordPtr, passwordLen) => ffiLib.passDecryptNative(
        ciphertextPtr,
        ciphertext.length,
        passwordPtr,
        passwordLen,
        plaintextPtr,
        ciphertext.length - toxPassEncryptionExtraLength,
      ),
    );
    if (decryptedLen < 0) {
      throw Exception(
          'Decryption failed - incorrect password or corrupted file');
    }
    return Uint8List.fromList(plaintextPtr.asTypedList(decryptedLen));
  } finally {
    pkgffi.malloc.free(ciphertextPtr);
    pkgffi.malloc.free(plaintextPtr);
  }
}

/// Copies [passwordBytes] into native memory for [body] and zero-fills that
/// copy before freeing it: `malloc.free` only returns the block to the
/// allocator, so the password would otherwise sit in reusable heap.
T _withNativePassword<T>(
  Uint8List passwordBytes,
  T Function(ffi.Pointer<ffi.Uint8> ptr, int len) body,
) {
  final len = passwordBytes.length;
  final ptr = pkgffi.malloc<ffi.Uint8>(len == 0 ? 1 : len);
  try {
    ptr.asTypedList(len).setAll(0, passwordBytes);
    return body(ptr, len);
  } finally {
    ptr.asTypedList(len).fillRange(0, len, 0);
    pkgffi.malloc.free(ptr);
  }
}

/// Returns true iff the first [toxPassEncryptionExtraLength] bytes of [data]
/// match the Tox encrypted-save magic. Returns false for any data shorter
/// than the magic-header window.
bool isDataEncrypted(Uint8List data) {
  if (data.length < toxPassEncryptionExtraLength) return false;
  final ffiLib = Tim2ToxFfi.open();
  final dataPtr = pkgffi.malloc<ffi.Uint8>(toxPassEncryptionExtraLength);
  try {
    dataPtr
        .asTypedList(toxPassEncryptionExtraLength)
        .setAll(0, data.take(toxPassEncryptionExtraLength).toList());
    return ffiLib.isDataEncryptedNative(dataPtr, toxPassEncryptionExtraLength) ==
        1;
  } finally {
    pkgffi.malloc.free(dataPtr);
  }
}

/// Check if a profile file (tox_profile.tox) is encrypted. Returns false for
/// missing / empty / short files and for any error during FFI probing.
Future<bool> isProfileFileEncrypted(String profileFilePath) async {
  final file = File(profileFilePath);
  if (!await file.exists()) return false;
  final data = await file.readAsBytes();
  if (data.length < toxPassEncryptionExtraLength) return false;
  try {
    return isDataEncrypted(data);
  } catch (_) {
    return false;
  }
}

/// Atomic in-place write: stage bytes to `<path>.new`, fsync, then rename over
/// the original. `File.writeAsBytes(flush: true)` issues fsync on the file
/// descriptor before close, and `rename()` is atomic on a single filesystem on
/// POSIX (renameat2/AT_REPLACE behavior) and Windows (MoveFileEx with replace).
/// This protects the account profile from corruption if the process is killed
/// mid-write — the previous file is preserved up to the moment of rename, and
/// the .new file is best-effort cleaned up on failure.
Future<void> _writeBytesAtomic(File target, Uint8List bytes) async {
  final stage = File('${target.path}.new');
  try {
    await stage.writeAsBytes(bytes, flush: true);
    await stage.rename(target.path);
  } catch (_) {
    if (await stage.exists()) {
      try {
        await stage.delete();
      } catch (_) {
        // Best-effort cleanup of staging file. We're about to rethrow the
        // original write/rename error which carries the real failure; a
        // delete failure here would only mask it. Stale `.new` files are
        // harmless — the next atomic write reuses the same path.
      }
    }
    rethrow;
  }
}

/// Encrypt a profile file in place (plain -> encrypted). Used after register
/// or on logout. No-op when [password] is empty. Refuses to re-encrypt an
/// already-encrypted file (silent double-encrypt would produce an unrecoverable
/// blob).
Future<void> encryptProfileFile(
  String profileFilePath,
  SecretPassword password,
) async {
  if (password.isEmpty) return;
  final file = File(profileFilePath);
  if (!await file.exists()) {
    // PRIVACY: no path in the message — see ProfileFileMissingException.
    throw const ProfileFileMissingException(ProfileCryptoOperation.encrypt);
  }
  final plainData = await file.readAsBytes();
  if (plainData.isEmpty) throw Exception('Profile file is empty');
  // Guard against accidental double-encryption: an error-recovery path that
  // calls encryptProfileFile after the file was already encrypted on logout
  // would otherwise produce a double-encrypted blob that the user's password
  // cannot decrypt in one pass.
  if (isDataEncrypted(plainData)) return;
  await _writeBytesAtomic(file, passEncrypt(plainData, password));
}

/// Decrypt a profile file in place (encrypted -> plain). Used before init
/// when account has a password. Returns silently if the file is already
/// plain. Throws [ArgumentError] when [password] is empty.
Future<void> decryptProfileFile(
  String profileFilePath,
  SecretPassword password,
) async {
  if (password.isEmpty) throw ArgumentError('Password required to decrypt');
  final file = File(profileFilePath);
  if (!await file.exists()) {
    // PRIVACY: no path in the message — see ProfileFileMissingException.
    throw const ProfileFileMissingException(ProfileCryptoOperation.decrypt);
  }
  final fileData = await file.readAsBytes();
  if (fileData.isEmpty) throw Exception('Profile file is empty');
  final isEncrypted = await isProfileFileEncrypted(profileFilePath);
  if (!isEncrypted) return; // already plain
  await _writeBytesAtomic(file, passDecrypt(fileData, password));
}
