import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkgffi;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:toxee/util/account_export/atomic_file_write.dart';
import 'package:toxee/util/account_export/encryption.dart';
import 'package:toxee/util/account_export/native_buffers.dart';
import 'package:toxee/util/account_export/posix_directory_sync.dart';
import 'package:toxee/util/account_export/tox_file_io.dart';
import 'package:toxee/util/secret_password.dart';

/// Back-port of DitMesh review L10 (native profile buffers are wiped before
/// they are freed) and L11 (a rename is followed by a directory flush).

class _RecordingAllocator implements ffi.Allocator {
  final Map<int, int> _sizes = {};
  final List<bool> zeroAtFree = [];

  @override
  ffi.Pointer<T> allocate<T extends ffi.NativeType>(
    int byteCount, {
    int? alignment,
  }) {
    final ptr = pkgffi.malloc.allocate<T>(byteCount, alignment: alignment);
    _sizes[ptr.address] = byteCount;
    return ptr;
  }

  @override
  void free(ffi.Pointer<ffi.NativeType> pointer) {
    final size = _sizes.remove(pointer.address)!;
    zeroAtFree.add(
      pointer.cast<ffi.Uint8>().asTypedList(size).every((b) => b == 0),
    );
    pkgffi.malloc.free(pointer);
  }
}

/// Echo "crypto": encrypt prefixes 80 bytes of 0xEE, decrypt strips them;
/// [fail] reports a native error after writing the output.
class _EchoFfi extends Tim2ToxFfi {
  _EchoFfi() : super.forTesting();
  bool fail = false;

  @override
  int Function(ffi.Pointer<ffi.Uint8>, int) get isDataEncryptedNative =>
      (ptr, len) => ptr.asTypedList(len).first == 0xEE ? 1 : 0;

  @override
  int Function(
    ffi.Pointer<ffi.Uint8>,
    int,
    ffi.Pointer<ffi.Uint8>,
    int,
    ffi.Pointer<ffi.Uint8>,
    int,
  ) get passEncryptNative => (inp, inLen, pw, pwLen, out, outLen) {
        final o = out.asTypedList(outLen);
        o.fillRange(0, 80, 0xEE);
        o.setAll(80, inp.asTypedList(inLen));
        return fail ? -1 : outLen;
      };

  @override
  int Function(
    ffi.Pointer<ffi.Uint8>,
    int,
    ffi.Pointer<ffi.Uint8>,
    int,
    ffi.Pointer<ffi.Uint8>,
    int,
  ) get passDecryptNative => (inp, inLen, pw, pwLen, out, outLen) {
        out.asTypedList(outLen).setAll(0, inp.asTypedList(inLen).sublist(80));
        return fail ? -1 : outLen;
      };

  @override
  int Function(
    ffi.Pointer<ffi.Uint8>,
    int,
    ffi.Pointer<ffi.Uint8>,
    int,
    ffi.Pointer<ffi.Int8>,
    int,
  ) get extractToxIdFromProfileNative => (prof, len, pw, pwLen, buf, cap) {
        final id = 'AB' * 32;
        buf.cast<ffi.Uint8>().asTypedList(id.length).setAll(0, id.codeUnits);
        return fail ? -1 : id.length;
      };
}

void main() {
  group('native profile buffers are wiped', () {
    late _RecordingAllocator allocator;
    late _EchoFfi native;
    final secret = Uint8List.fromList(List.generate(200, (i) => i % 250 + 1));
    final pw = Uint8List.fromList('secret'.codeUnits);

    setUp(() {
      allocator = _RecordingAllocator();
      native = _EchoFfi();
      nativeBufferAllocator = allocator;
      profileCryptoFfi = () => native;
    });

    tearDown(() {
      nativeBufferAllocator = pkgffi.malloc;
      profileCryptoFfi = Tim2ToxFfi.open;
    });

    test('on success, with the returned copies intact', () {
      final sealed = passEncryptBytes(secret, pw);
      expect(sealed.length, secret.length + 80);
      expect(passDecryptBytes(sealed, pw), secret);
      expect(isDataEncrypted(sealed), isTrue);
      expect(isDataEncrypted(secret), isFalse);
      expect(
        extractToxIdFromProfile(secret, SecretPassword.fromString('pw')),
        'AB' * 32,
      );
      expect(pw, 'secret'.codeUnits, reason: 'the caller buffer is borrowed');
      expect(allocator.zeroAtFree, isNotEmpty);
      expect(allocator.zeroAtFree, everyElement(isTrue));
    });

    test('on native failure', () {
      native.fail = true;
      expect(() => passEncryptBytes(secret, pw), throwsException);
      expect(
        () => passDecryptBytes(Uint8List(300)..fillRange(0, 300, 7), pw),
        throwsException,
      );
      expect(() => extractToxIdFromProfile(secret), throwsException);
      expect(allocator.zeroAtFree, hasLength(8));
      expect(allocator.zeroAtFree, everyElement(isTrue));
    });
  });

  group('directory flush after a rename', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('toxee_dir_sync_');
    });
    tearDown(() async {
      directorySync = PosixDirectorySync.sync;
      await dir.delete(recursive: true);
    });

    test('flushes a directory on POSIX, no-op on Windows', () {
      expect(PosixDirectorySync.supported, !Platform.isWindows);
      expect(PosixDirectorySync.sync(dir.path), !Platform.isWindows);
      expect(PosixDirectorySync.sync(p.join(dir.path, 'missing')), isFalse);
    });

    test('writeBytesAtomically flushes the parent after publishing', () async {
      final target = File(p.join(dir.path, 'journal.json'));
      final flushed = <String>[];
      directorySync = (path) {
        expect(target.readAsBytesSync(), [1, 2, 3]);
        flushed.add(path);
        return true;
      };
      await writeBytesAtomically(target, [1, 2, 3]);
      expect(flushed, [dir.path]);
    });

    test('a failing flush leaves the committed write in place', () async {
      final target = File(p.join(dir.path, 'journal.json'));
      directorySync = (_) => throw const FileSystemException('EIO');
      await writeBytesAtomically(target, [9]);
      expect(target.readAsBytesSync(), [9]);
      directorySync = (_) => false;
      await writeBytesAtomically(target, [8]);
      expect(target.readAsBytesSync(), [8]);
    });

    test('the in-place profile rewrite flushes its directory too', () async {
      final native = _EchoFfi();
      profileCryptoFfi = () => native;
      addTearDown(() => profileCryptoFfi = Tim2ToxFfi.open);
      final profile = File(p.join(dir.path, 'tox_profile.tox'))
        ..writeAsBytesSync(List.generate(120, (i) => i + 1));
      final flushed = <String>[];
      directorySync = (path) {
        flushed.add(path);
        return true;
      };
      await encryptProfileFile(profile.path, SecretPassword.fromString('pw'));
      expect(profile.readAsBytesSync().first, 0xEE);
      expect(flushed, [dir.path]);
    });
  });
}
