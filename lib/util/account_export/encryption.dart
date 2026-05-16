// Tox profile encryption / decryption helpers used by both the .tox
// import-export path and the in-place encrypt/decrypt-on-disk helpers.
//
// All FFI plumbing (malloc, asTypedList, free) is isolated here so the
// callers can stay declarative.
//
// IMPORTANT: This module preserves the existing production semantics
// byte-for-byte, including the known buffer-lifetime caveat in the
// *ProfileFile helpers (the ciphertext/plaintext view is handed to
// File.writeAsBytes and then freed in `finally`). Don't "fix" that here
// without coordinating an explicit behaviour-change patch — the refactor
// charter is to split the file, not to alter semantics.

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkgffi;
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';

import 'ffi_constants.dart';

/// Encrypts [plaintext] with [password] using Tox's `tox_pass_encrypt`
/// implementation. Returns the freshly-allocated ciphertext as a Uint8List
/// of length `plaintext.length + toxPassEncryptionExtraLength`.
///
/// Throws an [Exception] if the underlying FFI call returns a negative
/// length (encryption failed for any reason).
Uint8List passEncrypt(Uint8List plaintext, String password) {
  final ffiLib = Tim2ToxFfi.open();
  final passwordBytes = utf8.encode(password);
  final plaintextPtr = pkgffi.malloc<ffi.Uint8>(plaintext.length);
  final ciphertextPtr =
      pkgffi.malloc<ffi.Uint8>(plaintext.length + toxPassEncryptionExtraLength);
  final passwordPtr = pkgffi.malloc<ffi.Uint8>(passwordBytes.length);
  try {
    plaintextPtr.asTypedList(plaintext.length).setAll(0, plaintext);
    passwordPtr.asTypedList(passwordBytes.length).setAll(0, passwordBytes);
    final encryptedLen = ffiLib.passEncryptNative(
      plaintextPtr,
      plaintext.length,
      passwordPtr,
      passwordBytes.length,
      ciphertextPtr,
      plaintext.length + toxPassEncryptionExtraLength,
    );
    if (encryptedLen < 0) {
      throw Exception('Encryption failed');
    }
    return Uint8List.sublistView(ciphertextPtr.asTypedList(encryptedLen));
  } finally {
    pkgffi.malloc.free(plaintextPtr);
    pkgffi.malloc.free(ciphertextPtr);
    pkgffi.malloc.free(passwordPtr);
  }
}

/// Decrypts [ciphertext] with [password] using Tox's `tox_pass_decrypt`.
/// Returns the freshly-allocated plaintext as a Uint8List of length
/// `ciphertext.length - toxPassEncryptionExtraLength`.
///
/// Throws an [Exception] if the FFI call returns a negative length
/// (wrong password, corrupted blob, or any other tox decryption error).
Uint8List passDecrypt(Uint8List ciphertext, String password) {
  final ffiLib = Tim2ToxFfi.open();
  final passwordBytes = utf8.encode(password);
  final ciphertextPtr = pkgffi.malloc<ffi.Uint8>(ciphertext.length);
  final plaintextPtr = pkgffi
      .malloc<ffi.Uint8>(ciphertext.length - toxPassEncryptionExtraLength);
  final passwordPtr = pkgffi.malloc<ffi.Uint8>(passwordBytes.length);
  try {
    ciphertextPtr.asTypedList(ciphertext.length).setAll(0, ciphertext);
    passwordPtr.asTypedList(passwordBytes.length).setAll(0, passwordBytes);
    final decryptedLen = ffiLib.passDecryptNative(
      ciphertextPtr,
      ciphertext.length,
      passwordPtr,
      passwordBytes.length,
      plaintextPtr,
      ciphertext.length - toxPassEncryptionExtraLength,
    );
    if (decryptedLen < 0) {
      throw Exception(
          'Decryption failed - incorrect password or corrupted file');
    }
    return Uint8List.sublistView(plaintextPtr.asTypedList(decryptedLen));
  } finally {
    pkgffi.malloc.free(ciphertextPtr);
    pkgffi.malloc.free(plaintextPtr);
    pkgffi.malloc.free(passwordPtr);
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

/// Encrypt a profile file in place (plain -> encrypted). Used after register
/// or on logout. No-op when [password] is empty.
Future<void> encryptProfileFile(String profileFilePath, String password) async {
  if (password.isEmpty) return;
  final file = File(profileFilePath);
  if (!await file.exists()) {
    throw Exception('Profile file not found: $profileFilePath');
  }
  final plainData = await file.readAsBytes();
  if (plainData.isEmpty) throw Exception('Profile file is empty');
  final ffiLib = Tim2ToxFfi.open();
  final plaintextPtr = pkgffi.malloc<ffi.Uint8>(plainData.length);
  final ciphertextPtr =
      pkgffi.malloc<ffi.Uint8>(plainData.length + toxPassEncryptionExtraLength);
  final passwordBytes = utf8.encode(password);
  final passwordPtr = pkgffi.malloc<ffi.Uint8>(passwordBytes.length);
  try {
    plaintextPtr.asTypedList(plainData.length).setAll(0, plainData);
    passwordPtr.asTypedList(passwordBytes.length).setAll(0, passwordBytes);
    final encryptedLen = ffiLib.passEncryptNative(
      plaintextPtr,
      plainData.length,
      passwordPtr,
      passwordBytes.length,
      ciphertextPtr,
      plainData.length + toxPassEncryptionExtraLength,
    );
    if (encryptedLen < 0) throw Exception('Encryption failed');
    final encrypted =
        Uint8List.sublistView(ciphertextPtr.asTypedList(encryptedLen));
    await file.writeAsBytes(encrypted);
  } finally {
    pkgffi.malloc.free(plaintextPtr);
    pkgffi.malloc.free(ciphertextPtr);
    pkgffi.malloc.free(passwordPtr);
  }
}

/// Decrypt a profile file in place (encrypted -> plain). Used before init
/// when account has a password. Returns silently if the file is already
/// plain. Throws [ArgumentError] when [password] is empty.
Future<void> decryptProfileFile(String profileFilePath, String password) async {
  if (password.isEmpty) throw ArgumentError('Password required to decrypt');
  final file = File(profileFilePath);
  if (!await file.exists()) {
    throw Exception('Profile file not found: $profileFilePath');
  }
  final fileData = await file.readAsBytes();
  if (fileData.isEmpty) throw Exception('Profile file is empty');
  final isEncrypted = await isProfileFileEncrypted(profileFilePath);
  if (!isEncrypted) return; // already plain
  final ffiLib = Tim2ToxFfi.open();
  final ciphertextPtr = pkgffi.malloc<ffi.Uint8>(fileData.length);
  final plaintextPtr = pkgffi
      .malloc<ffi.Uint8>(fileData.length - toxPassEncryptionExtraLength);
  final passwordBytes = utf8.encode(password);
  final passwordPtr = pkgffi.malloc<ffi.Uint8>(passwordBytes.length);
  try {
    ciphertextPtr.asTypedList(fileData.length).setAll(0, fileData);
    passwordPtr.asTypedList(passwordBytes.length).setAll(0, passwordBytes);
    final decryptedLen = ffiLib.passDecryptNative(
      ciphertextPtr,
      fileData.length,
      passwordPtr,
      passwordBytes.length,
      plaintextPtr,
      fileData.length - toxPassEncryptionExtraLength,
    );
    if (decryptedLen < 0) {
      throw Exception(
          'Decryption failed - incorrect password or corrupted file');
    }
    final decrypted =
        Uint8List.sublistView(plaintextPtr.asTypedList(decryptedLen));
    await file.writeAsBytes(decrypted);
  } finally {
    pkgffi.malloc.free(ciphertextPtr);
    pkgffi.malloc.free(plaintextPtr);
    pkgffi.malloc.free(passwordPtr);
  }
}

