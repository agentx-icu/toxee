// An OLDER full backup (written before exports opened the at-rest ciphertext)
// can carry an encrypted tox_profile.tox under the ACCOUNT password, which is
// independent of the archive password. Restore must authenticate it before
// any write, keep the on-disk copy encrypted, and install that password as
// the account's verifier inside the restore transaction.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:toxee/util/account_export/encryption.dart';
import 'package:toxee/util/account_export/exceptions.dart';
import 'package:toxee/util/account_export/full_backup_crypto.dart';
import 'package:toxee/util/account_export/restore_transaction_journal.dart';
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

const _archivePassword = 'archive password';
const _profilePassword = 'account password of the old install';

void main() {
  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';
  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureStore = <String, String>{};

  late AccountExportTestEnv env;
  late ToxProfileFixture fixture;
  late String zipPath;
  late String zipNoIdPath;

  Future<String> writeArchive(String name, Map<String, Object> metadata) async {
    final plain = Archive()
      ..addFile(ArchiveFile.noCompress(
        'tox_profile.tox',
        0,
        passEncrypt(fixture.savedata, _profilePassword),
      ))
      ..addFile(ArchiveFile.noCompress(
        'metadata.json',
        0,
        utf8.encode(jsonEncode(metadata)),
      ));
    final encrypted = await encryptFullBackupArchive(
      plaintextArchive: plain,
      password: _archivePassword,
    );
    final path = p.join(env.extras, name);
    await File(path).writeAsBytes(ZipEncoder().encode(encrypted));
    return path;
  }

  setUp(() async {
    env = await setUpAccountExportTestEnv();
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (MethodCall call) async {
      final args =
          (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      switch (call.method) {
        case 'write':
          secureStore[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return secureStore[args['key'] as String];
        case 'delete':
          secureStore.remove(args['key'] as String);
          return null;
        case 'containsKey':
          return secureStore.containsKey(args['key'] as String);
        case 'readAll':
          return Map<String, String>.from(secureStore);
        case 'deleteAll':
          secureStore.clear();
          return null;
        default:
          return null;
      }
    });
    fixture = ToxProfileFixture.create()!;
    // The archive an older build would have written for a protected account
    // that was not the live session: its profile is the at-rest ciphertext.
    zipPath = await writeArchive('old_backup.zip', {
      'formatVersion': fullBackupEncryptedFormatVersion,
      'toxId': fixture.toxId,
      'nickname': 'Old install',
    });
    // Same, from a build whose metadata carried no toxId: the identity can
    // only come from the (encrypted) profile.
    zipNoIdPath = await writeArchive('old_backup_no_id.zip', {
      'formatVersion': fullBackupEncryptedFormatVersion,
      'nickname': 'Old install',
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    await env.dispose();
  });

  test('preflight asks for the profile password before any write', () async {
    await expectLater(
      () => AccountExportService.readFullBackupMetadata(
        zipPath,
        password: _archivePassword,
      ),
      throwsA(isA<BackupProfilePasswordRequiredException>()),
    );
    await expectLater(
      () => AccountExportService.readFullBackupMetadata(
        zipPath,
        password: _archivePassword,
        profilePassword: 'not it',
      ),
      throwsA(isA<InvalidBackupPasswordException>()),
    );
    final metadata = await AccountExportService.readFullBackupMetadata(
      zipPath,
      password: _archivePassword,
      profilePassword: _profilePassword,
    );
    expect(metadata['toxId'], fixture.toxId);
    final dir = await AppPaths.getProfileDirectoryForToxId(fixture.toxId);
    expect(Directory(dir).existsSync(), isFalse, reason: 'nothing written');
  }, skip: skipReason);

  test('metadata without a toxId: a wrong profile password keeps its typed '
      'error, the right one yields the identity', () async {
    await expectLater(
      () => AccountExportService.readFullBackupMetadata(
        zipNoIdPath,
        password: _archivePassword,
      ),
      throwsA(isA<BackupProfilePasswordRequiredException>()),
    );
    await expectLater(
      () => AccountExportService.readFullBackupMetadata(
        zipNoIdPath,
        password: _archivePassword,
        profilePassword: 'not it',
      ),
      throwsA(isA<InvalidBackupPasswordException>()),
    );
    final metadata = await AccountExportService.readFullBackupMetadata(
      zipNoIdPath,
      password: _archivePassword,
      profilePassword: _profilePassword,
    );
    // Without metadata the identity comes from the profile itself, which
    // yields the 64-char public key (the existing extractor contract).
    expect(metadata['toxId'], fixture.publicKeyHex);
  }, skip: skipReason);

  test('restore keeps the profile encrypted and installs its password as the '
      'verifier before the account is published', () async {
    await AccountExportService.importFullBackup(
      filePath: zipPath,
      password: _archivePassword,
      profilePassword: _profilePassword,
    );
    final dir = await AppPaths.getProfileDirectoryForToxId(fixture.toxId);
    final onDisk =
        await File(AppPaths.profileFileInDirectory(dir)).readAsBytes();
    expect(isDataEncrypted(onDisk), isTrue);
    expect(passDecrypt(onDisk, _profilePassword), fixture.savedata);
    expect(await Prefs.verifyAccountPassword(fixture.toxId, _profilePassword),
        isTrue);
    final journal = await RestoreTransactionJournalStore.read();
    expect(journal?.verifierInstalled, isTrue);

    await Prefs.addAccount(toxId: fixture.toxId, nickname: 'Old install');
    await AccountExportService.finalizeFullBackupImport(toxId: fixture.toxId);
    expect(await RestoreTransactionJournalStore.read(), isNull);
    expect(await Prefs.verifyAccountPassword(fixture.toxId, _profilePassword),
        isTrue, reason: 'finalize keeps the verifier with the account');
  }, skip: skipReason);

  test('a rolled-back restore takes its verifier with it', () async {
    await AccountExportService.importFullBackup(
      filePath: zipPath,
      password: _archivePassword,
      profilePassword: _profilePassword,
    );
    expect(await Prefs.hasAccountPassword(fixture.toxId), isTrue);
    await AccountExportService.rollbackPendingFullBackupRestore(
      toxId: fixture.toxId,
    );
    expect(await Prefs.hasAccountPassword(fixture.toxId), isFalse);
    expect(await RestoreTransactionJournalStore.read(), isNull);
  }, skip: skipReason);
}
