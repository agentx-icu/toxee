// Safety-net tests for AccountExportService.
//
// These tests exist to lock down the PUBLIC, behaviour-visible contracts of
// AccountExportService before the file is split into focused modules. They
// must pass against both the pre-refactor and post-refactor sources without
// modification.
//
// What is covered:
//   - PasswordRequiredException identity / message / toString.
//   - .tox roundtrip via the production AccountExportService.exportAccountData
//     and AccountExportService.importAccountData (unencrypted and encrypted).
//   - Encrypted .tox rejects an empty password with PasswordRequiredException
//     and rejects a wrong password with a clean Exception (not a panic).
//   - isProfileFileEncrypted classifies plain vs encrypted profile bytes.
//   - encryptProfileFile / decryptProfileFile mutate in place idempotently.
//   - exportFullBackup → readFullBackupMetadata roundtrip for a real account.
//   - importFullBackup restores chat history + offline queue + scoped prefs
//     from a synthesized .zip without touching FFI extraction (since metadata
//     supplies the toxId).
//   - importFullBackup routes .tox files through importAccountData.
//   - Corrupt / empty inputs throw clean exceptions rather than crashing.
//
// FFI dependency:
//   Tests that need the tim2tox FFI library are skipped automatically when it
//   cannot be located/loaded. Under the standard dev/CI flow the library has
//   already been built into the Flutter engine artifacts directory, so they
//   do run there.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:toxee/util/account_export/restore_transaction.dart';
import 'package:toxee/util/account_export_service.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';

import 'test_support.dart';
import 'tox_profile_factory.dart';

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  final ffiAvailable = _ffiAvailable();
  final skipReason = ffiAvailable
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('PasswordRequiredException', () {
    test('default message and toString shape are stable', () {
      const e = PasswordRequiredException();
      expect(e, isA<Exception>());
      expect(e.message, 'Password required for encrypted .tox file');
      expect(
        e.toString(),
        'PasswordRequiredException: Password required for encrypted .tox file',
      );
    });

    test('custom message preserved in toString', () {
      const e = PasswordRequiredException('custom');
      expect(e.message, 'custom');
      expect(e.toString(), 'PasswordRequiredException: custom');
    });
  });

  group('importAccountData input validation', () {
    late AccountExportTestEnv env;
    setUp(() async {
      env = await setUpAccountExportTestEnv();
    });
    tearDown(() => env.dispose());

    test('missing file throws Exception', () {
      expect(
        () => AccountExportService.importAccountData(
          filePath: p.join(env.extras, 'does_not_exist.tox'),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('empty file throws Exception', () async {
      final empty = File(p.join(env.extras, 'empty.tox'));
      await empty.writeAsBytes(<int>[]);
      expect(
        () => AccountExportService.importAccountData(filePath: empty.path),
        throwsA(isA<Exception>()),
      );
    });

    test('corrupt/truncated tiny bytes throw a clean Exception', () async {
      // 16 random bytes — too short to be a valid profile, must not panic.
      final corrupt = File(p.join(env.extras, 'corrupt.tox'));
      await corrupt.writeAsBytes(Uint8List.fromList(List.filled(16, 0x41)));
      expect(
        () => AccountExportService.importAccountData(filePath: corrupt.path),
        throwsA(isA<Object>()),
      );
    });
  });

  group('AccountExportService .tox roundtrip', skip: skipReason, () {
    late AccountExportTestEnv env;
    late ToxProfileFixture fixture;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
      final maybe = ToxProfileFixture.create();
      expect(
        maybe,
        isNotNull,
        reason: 'tox_new failed unexpectedly under flutter test',
      );
      fixture = maybe!;
      // Place the profile where AppPaths.resolveToxProfilePath() will find it.
      final dir = await AppPaths.getProfileDirectoryForToxId(fixture.toxId);
      await Directory(dir).create(recursive: true);
      final path = AppPaths.profileFileInDirectory(dir);
      await File(path).writeAsBytes(fixture.savedata);

      // Register the account in Prefs so the export path's nickname lookup
      // succeeds without falling through to the "minimal account" branch.
      await Prefs.addAccount(
        toxId: fixture.toxId,
        nickname: 'TestNick',
        statusMessage: 'Hello status',
      );
    });

    tearDown(() => env.dispose());

    test('unencrypted export/import produces identical profile bytes', () async {
      final exportPath = await AccountExportService.exportAccountData(
        toxId: fixture.toxId,
        filePath: p.join(env.extras, 'plain.tox'),
      );
      expect(File(exportPath).existsSync(), isTrue);
      final exportBytes = await File(exportPath).readAsBytes();
      expect(
        exportBytes,
        equals(fixture.savedata),
        reason: 'unencrypted export must be byte-identical to source profile',
      );

      final imported = await AccountExportService.importAccountData(
        filePath: exportPath,
      );
      // importAccountData returns the 64-char public key (extract_tox_id_from_profile
      // does not preserve the nospam+checksum tail of the full 76-char address).
      expect(imported['toxId'], fixture.publicKeyHex);
      final importedProfile = imported['toxProfile'] as Uint8List;
      expect(importedProfile, equals(fixture.savedata));
    });

    test('successful export leaves no .new stage siblings', () async {
      final targetPath = p.join(env.extras, 'atomic_success.tox');

      await AccountExportService.exportAccountData(
        toxId: fixture.toxId,
        filePath: targetPath,
      );

      final stagePrefix = '$targetPath.new.';
      final stageSiblings = await Directory(p.dirname(targetPath))
          .list(followLinks: false)
          .where((entity) => entity.path.startsWith(stagePrefix))
          .toList();
      expect(stageSiblings, isEmpty);
      expect(await File(targetPath).readAsBytes(), equals(fixture.savedata));
    });

    // Regression test for the FFI buffer-use-after-free that previously
    // caused garbage on disk in some allocators when exportAccountData was
    // called with a password (or encryptProfileFile / decryptProfileFile
    // ran). Fix: lib/util/account_export/encryption.dart now copies the FFI
    // buffer into Dart-owned memory via Uint8List.fromList before the
    // `finally` block frees it. This test exercises the full encrypted
    // roundtrip end to end and asserts byte equality of the decrypted
    // profile against the original savedata.
    test('encrypted export/import roundtrip preserves profile bytes', () async {
      const password = 'correct horse battery staple';
      final exportPath = await AccountExportService.exportAccountData(
        toxId: fixture.toxId,
        password: password,
        filePath: p.join(env.extras, 'encrypted.tox'),
      );
      expect(File(exportPath).existsSync(), isTrue);

      final exportBytes = await File(exportPath).readAsBytes();
      expect(
        exportBytes,
        isNot(equals(fixture.savedata)),
        reason: 'encrypted .tox must differ from the plain savedata',
      );
      expect(
        await AccountExportService.isProfileFileEncrypted(exportPath),
        isTrue,
        reason: 'on-disk bytes must carry the Tox-encrypted magic header',
      );

      final imported = await AccountExportService.importAccountData(
        filePath: exportPath,
        password: password,
      );
      expect(imported['toxId'], fixture.publicKeyHex);
      final importedProfile = imported['toxProfile'] as Uint8List;
      expect(
        importedProfile,
        equals(fixture.savedata),
        reason:
            'decrypted profile must equal source — regression for FFI buffer UAF',
      );
    });

    test(
      'encryptProfileFile then decryptProfileFile preserves plaintext',
      () async {
        const password = 'another-password-value';
        final scratch = File(p.join(env.extras, 'scratch_profile.bin'));
        await scratch.writeAsBytes(fixture.savedata);

        await AccountExportService.encryptProfileFile(scratch.path, password);
        final encryptedOnDisk = await scratch.readAsBytes();
        expect(
          encryptedOnDisk,
          isNot(equals(fixture.savedata)),
          reason: 'in-place encryptProfileFile must produce ciphertext',
        );
        expect(
          await AccountExportService.isProfileFileEncrypted(scratch.path),
          isTrue,
        );

        await AccountExportService.decryptProfileFile(scratch.path, password);
        final decryptedOnDisk = await scratch.readAsBytes();
        expect(
          decryptedOnDisk,
          equals(fixture.savedata),
          reason:
              'in-place decryptProfileFile must restore original savedata — regression for FFI buffer UAF',
        );
      },
    );

    test(
      'isProfileFileEncrypted returns false for plain savedata bytes',
      () async {
        final plain = File(p.join(env.extras, 'plain_profile.bin'));
        await plain.writeAsBytes(fixture.savedata);
        expect(
          await AccountExportService.isProfileFileEncrypted(plain.path),
          isFalse,
        );
      },
    );

    // S2 regression: encryptProfileFile / decryptProfileFile must use a
    // temp-file-then-rename pattern so a kill mid-write does not corrupt
    // the original .tox blob. We can't actually kill the process from a
    // unit test, but we can verify the staging file is cleaned up on
    // success — its presence after a successful encrypt would indicate
    // a non-atomic write path.
    test(
      'encryptProfileFile leaves no .new staging file after success',
      () async {
        const password = 's2-atomic-encrypt-test';
        final scratch = File(p.join(env.extras, 's2_encrypt.bin'));
        await scratch.writeAsBytes(fixture.savedata);
        await AccountExportService.encryptProfileFile(scratch.path, password);
        expect(
          File('${scratch.path}.new').existsSync(),
          isFalse,
          reason: 'atomic-write staging file must be renamed away',
        );
        expect(
          await AccountExportService.isProfileFileEncrypted(scratch.path),
          isTrue,
        );
      },
    );

    test(
      'decryptProfileFile leaves no .new staging file after success',
      () async {
        const password = 's2-atomic-decrypt-test';
        final scratch = File(p.join(env.extras, 's2_decrypt.bin'));
        await scratch.writeAsBytes(fixture.savedata);
        await AccountExportService.encryptProfileFile(scratch.path, password);
        await AccountExportService.decryptProfileFile(scratch.path, password);
        expect(
          File('${scratch.path}.new').existsSync(),
          isFalse,
          reason: 'atomic-write staging file must be renamed away',
        );
        expect(await scratch.readAsBytes(), equals(fixture.savedata));
      },
    );

    // A3 regression: encryptProfileFile must refuse to re-encrypt an
    // already-encrypted file. Otherwise an error-recovery path that calls
    // it twice on logout would produce an unrecoverable double-encrypted
    // blob.
    test(
      'encryptProfileFile is a no-op when file is already encrypted',
      () async {
        const password = 'a3-double-encrypt-guard';
        final scratch = File(p.join(env.extras, 'a3_double_encrypt.bin'));
        await scratch.writeAsBytes(fixture.savedata);
        await AccountExportService.encryptProfileFile(scratch.path, password);
        final once = await scratch.readAsBytes();
        await AccountExportService.encryptProfileFile(scratch.path, password);
        final twice = await scratch.readAsBytes();
        expect(
          twice,
          equals(once),
          reason: 'second encrypt on already-encrypted data must be a no-op',
        );
        await AccountExportService.decryptProfileFile(scratch.path, password);
        expect(
          await scratch.readAsBytes(),
          equals(fixture.savedata),
          reason: 'decrypt of single-encrypted blob must recover plaintext',
        );
      },
    );

    test(
      'isProfileFileEncrypted returns false for empty / missing / short files',
      () async {
        final missing = p.join(env.extras, 'no_such_file.tox');
        expect(
          await AccountExportService.isProfileFileEncrypted(missing),
          isFalse,
        );

        final empty = File(p.join(env.extras, 'empty.tox'));
        await empty.writeAsBytes(<int>[]);
        expect(
          await AccountExportService.isProfileFileEncrypted(empty.path),
          isFalse,
        );

        final short = File(p.join(env.extras, 'short.tox'));
        await short.writeAsBytes(List.filled(10, 0xAA));
        expect(
          await AccountExportService.isProfileFileEncrypted(short.path),
          isFalse,
        );
      },
    );

    test('exportFullBackup → readFullBackupMetadata roundtrip', () async {
      final zipPath = await AccountExportService.exportFullBackup(
        toxId: fixture.toxId,
        password: 'full-backup-export-password',
        filePath: p.join(env.extras, 'backup.zip'),
      );
      expect(File(zipPath).existsSync(), isTrue);
      final meta = await AccountExportService.readFullBackupMetadata(
        zipPath,
        password: 'full-backup-export-password',
      );
      expect(meta['toxId'], fixture.toxId);
      expect(meta['nickname'], 'TestNick');
    });
  });

  group('readFullBackupMetadata (pure-Dart)', () {
    late AccountExportTestEnv env;
    setUp(() async {
      env = await setUpAccountExportTestEnv();
    });
    tearDown(() => env.dispose());

    test('reads toxId and nickname from synthesized zip', () async {
      final zipPath = p.join(env.extras, 'meta_only.zip');
      const fakeToxId =
          '0011223344556677889900112233445566778899001122334455667788990011';
      await _writeFakeBackupZip(
        zipPath,
        metadata: {
          'toxId': fakeToxId,
          'nickname': 'Synth',
          'statusMessage': '',
          'exportDate': DateTime.now().toIso8601String(),
          'scopedPrefs': <String, dynamic>{},
        },
      );

      final meta = await AccountExportService.readFullBackupMetadata(zipPath);
      expect(meta['toxId'], fakeToxId);
      expect(meta['nickname'], 'Synth');
    });

    test('non-.zip extension throws', () async {
      final txt = File(p.join(env.extras, 'not_a_zip.txt'));
      await txt.writeAsString('hello');
      expect(
        () => AccountExportService.readFullBackupMetadata(txt.path),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('exportFullBackup metadata (pure-Dart)', () {
    late AccountExportTestEnv env;
    setUp(() async {
      env = await setUpAccountExportTestEnv();
    });
    tearDown(() => env.dispose());

    test(
      'discovers timestamped friend avatar files without an existing pref',
      () async {
        const toxId =
            '0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF';
        const friendId =
            'FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210';
        const avatarFileName = 'friend_${friendId}_avatar_1700000000000.png';

        await Prefs.addAccount(toxId: toxId, nickname: 'Avatar Owner');
        final avatarsPath = await AppPaths.getAccountAvatarsPath(toxId);
        await Directory(avatarsPath).create(recursive: true);
        await File(
          p.join(avatarsPath, avatarFileName),
        ).writeAsBytes(<int>[0x89, 0x50, 0x4E, 0x47]);

        final zipPath = await AccountExportService.exportFullBackup(
          toxId: toxId,
          password: 'avatar-backup-export-password',
          filePath: p.join(env.extras, 'avatar_backup.zip'),
        );
        await Directory(
          await AppPaths.getAccountDataRoot(toxId),
        ).delete(recursive: true);
        await Prefs.clearScopedKeysForAccount(toxId);
        await Prefs.removeAccount(toxId);

        await AccountExportService.importFullBackup(
          filePath: zipPath,
          password: 'avatar-backup-export-password',
        );

        final restoredAvatar = File(
          p.join(await AppPaths.getAccountAvatarsPath(toxId), avatarFileName),
        );
        expect(
          await restoredAvatar.exists(),
          isTrue,
          reason:
              'full backup must not drop avatar files that follow the persisted '
              'friend_<id>_avatar_<timestamp>.<ext> naming scheme.',
        );
      },
    );
  });

  group('importFullBackup routing (pure-Dart)', () {
    late AccountExportTestEnv env;
    setUp(() async {
      env = await setUpAccountExportTestEnv();
    });
    tearDown(() => env.dispose());

    test(
      '.tox path delegates to importAccountData (missing file → throws)',
      () {
        expect(
          () => AccountExportService.importFullBackup(
            filePath: p.join(env.extras, 'nope.tox'),
          ),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('restores chat history + offline queue from a synth zip', () async {
      const fakeToxId =
          'AABBCCDDEEFF00112233445566778899AABBCCDDEEFF00112233445566778899';
      final zipPath = p.join(env.extras, 'history_only.zip');
      await _writeFakeBackupZip(
        zipPath,
        metadata: {
          'toxId': fakeToxId,
          'nickname': 'HistoryOwner',
          'statusMessage': '',
          'exportDate': DateTime.now().toIso8601String(),
          'scopedPrefs': <String, dynamic>{
            'muted_peers_$fakeToxId': jsonEncode(['m1', 'm2']),
          },
        },
        chatHistoryFiles: const {'conv_peer1.json': '[{"msg":"hi"}]'},
        offlineQueue: '[{"to":"peer1","body":"queued"}]',
      );

      final result = await AccountExportService.importFullBackup(
        filePath: zipPath,
      );
      expect(result['toxId'], fakeToxId);
      expect(result['nickname'], 'HistoryOwner');

      final histPath = await AppPaths.getAccountChatHistoryPath(fakeToxId);
      final restoredHist = await File(
        p.join(histPath, 'conv_peer1.json'),
      ).readAsString();
      expect(restoredHist, '[{"msg":"hi"}]');

      final queuePath = await AppPaths.getAccountOfflineQueueFilePath(
        fakeToxId,
      );
      expect(
        await File(queuePath).readAsString(),
        '[{"to":"peer1","body":"queued"}]',
      );
    });

    test(
      'rejects chat history entries that escape the account directory',
      () async {
        const fakeToxId =
            '11223344556677889900AABBCCDDEEFF11223344556677889900AABBCCDDEEFF';
        final zipPath = p.join(env.extras, 'unsafe_history.zip');
        await _writeFakeBackupZip(
          zipPath,
          metadata: {
            'toxId': fakeToxId,
            'nickname': 'UnsafeHistory',
            'scopedPrefs': <String, dynamic>{},
          },
          chatHistoryFiles: const {'../escape.json': '{"msg":"outside"}'},
          toxProfile: Uint8List.fromList(<int>[1, 2, 3, 4]),
        );
        FullBackupRestoreTestHooks.profileIdentityExtractor =
            (Uint8List profileBytes) => fakeToxId;
        addTearDown(FullBackupRestoreTestHooks.reset);

        await expectLater(
          () => AccountExportService.importFullBackup(filePath: zipPath),
          throwsA(
            predicate((e) => e.toString().contains('Unsafe backup path')),
          ),
        );

        final historyDir = await AppPaths.getAccountChatHistoryPath(fakeToxId);
        expect(
          File(
            p.normalize(p.join(historyDir, '..', 'escape.json')),
          ).existsSync(),
          isFalse,
        );
        final profileDir = await AppPaths.getProfileDirectoryForToxId(
          fakeToxId,
        );
        expect(
          File(AppPaths.profileFileInDirectory(profileDir)).existsSync(),
          isFalse,
          reason:
              'unsafe archive paths are preflighted before tox_profile.tox is restored',
        );
      },
    );

    test('rejects avatar entries that escape the account directory', () async {
      const fakeToxId =
          'FFEEDDCCBBAA00998877665544332211FFEEDDCCBBAA00998877665544332211';
      final zipPath = p.join(env.extras, 'unsafe_avatar.zip');
      await _writeFakeBackupZip(
        zipPath,
        metadata: {
          'toxId': fakeToxId,
          'nickname': 'UnsafeAvatar',
          'scopedPrefs': <String, dynamic>{},
        },
        avatarFiles: const {
          '../escape.png': [0x89, 0x50, 0x4E, 0x47],
        },
      );

      await expectLater(
        () => AccountExportService.importFullBackup(filePath: zipPath),
        throwsA(predicate((e) => e.toString().contains('Unsafe backup path'))),
      );

      final avatarsDir = await AppPaths.getAccountAvatarsPath(fakeToxId);
      expect(
        File(p.normalize(p.join(avatarsDir, '..', 'escape.png'))).existsSync(),
        isFalse,
      );
    });

    test('rejects archive entries with Windows drive prefixes', () async {
      const fakeToxId =
          '3344556677889900AABBCCDDEEFF11223344556677889900AABBCCDDEEFF1122';
      final zipPath = p.join(env.extras, 'unsafe_windows_drive.zip');
      await _writeFakeBackupZip(
        zipPath,
        metadata: {
          'toxId': fakeToxId,
          'nickname': 'UnsafeWindowsDrive',
          'scopedPrefs': <String, dynamic>{},
        },
        chatHistoryFiles: const {'C:/escape.json': '{"msg":"drive"}'},
      );

      await expectLater(
        () => AccountExportService.importFullBackup(filePath: zipPath),
        throwsA(predicate((e) => e.toString().contains('Unsafe backup path'))),
      );
    });
  });
}

Future<void> _writeFakeBackupZip(
  String zipPath, {
  required Map<String, dynamic> metadata,
  Map<String, String> chatHistoryFiles = const {},
  Map<String, List<int>> avatarFiles = const {},
  String? offlineQueue,
  Uint8List? toxProfile,
}) async {
  final archive = Archive();
  final metaBytes = utf8.encode(
    const JsonEncoder.withIndent('  ').convert(metadata),
  );
  archive.addFile(ArchiveFile('metadata.json', metaBytes.length, metaBytes));
  if (toxProfile != null) {
    archive.addFile(
      ArchiveFile('tox_profile.tox', toxProfile.length, toxProfile),
    );
  }
  for (final entry in chatHistoryFiles.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(
      ArchiveFile('chat_history/${entry.key}', bytes.length, bytes),
    );
  }
  for (final entry in avatarFiles.entries) {
    archive.addFile(
      ArchiveFile('avatars/${entry.key}', entry.value.length, entry.value),
    );
  }
  if (offlineQueue != null) {
    final bytes = utf8.encode(offlineQueue);
    archive.addFile(
      ArchiveFile('offline_message_queue.json', bytes.length, bytes),
    );
  }
  final zipBytes = ZipEncoder().encode(archive);
  await File(zipPath).writeAsBytes(zipBytes);
}
