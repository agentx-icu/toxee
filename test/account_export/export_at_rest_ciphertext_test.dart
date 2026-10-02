// With native savedata encryption a protected account's tox_profile.tox is
// ciphertext at rest. Exports must open it with the account password before
// applying the export password the user chose, and never ship the at-rest
// ciphertext under a password the user did not pick.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:toxee/util/account_export/encryption.dart';
import 'package:toxee/util/account_export/exceptions.dart';
import 'package:toxee/util/account_export_service.dart';
import 'package:toxee/util/account_reconciliation.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/session_password_store.dart';

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

const _accountPassword = 'account password at rest';
const _exportPassword = 'a different export password';

void main() {
  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  late AccountExportTestEnv env;
  late ToxProfileFixture fixture;
  late String profilePath;

  setUp(() async {
    env = await setUpAccountExportTestEnv();
    SessionPasswordStore.clear();
    fixture = ToxProfileFixture.create()!;
    await Prefs.addAccount(toxId: fixture.toxId, nickname: 'At rest');
    final dir = await AppPaths.getProfileDirectoryForToxId(fixture.toxId);
    await Directory(dir).create(recursive: true);
    profilePath = AppPaths.profileFileInDirectory(dir);
    await File(profilePath)
        .writeAsBytes(passEncrypt(fixture.savedata, SecretPassword.fromString(_accountPassword)));
  });

  tearDown(() async {
    SessionPasswordStore.clear();
    await env.dispose();
  });

  test('refuses to export ciphertext it cannot open', () async {
    await expectLater(
      () => AccountExportService.exportAccountData(
        toxId: fixture.toxId,
        password: SecretPassword.fromString(_exportPassword),
        filePath: p.join(env.extras, 'refused.tox'),
      ),
      throwsA(isA<SessionPasswordUnavailableException>()),
    );
    expect(File(p.join(env.extras, 'refused.tox')).existsSync(), isFalse);
  }, skip: skipReason);

  test('opens the profile with the verified account password, then applies '
      'the export password', () async {
    final out = await AccountExportService.exportAccountData(
      toxId: fixture.toxId,
      password: SecretPassword.fromString(_exportPassword),
      accountPassword: SecretPassword.fromString(_accountPassword),
      filePath: p.join(env.extras, 'exported.tox'),
    );
    final bytes = await File(out).readAsBytes();
    expect(isDataEncrypted(bytes), isTrue);
    expect(passDecrypt(bytes, SecretPassword.fromString(_exportPassword)), fixture.savedata,
        reason: 'protected by the EXPORT password, not the account password');
  }, skip: skipReason);

  test('a live session opens it with the cached session password; no export '
      'password means plaintext bytes', () async {
    SessionPasswordStore.set(fixture.toxId, SecretPassword.fromString(_accountPassword));
    final out = await AccountExportService.exportAccountData(
      toxId: fixture.toxId,
      filePath: p.join(env.extras, 'plain.tox'),
    );
    expect(await File(out).readAsBytes(), fixture.savedata);
  }, skip: skipReason);

  test('full backup stores the plaintext profile inside the encrypted archive',
      () async {
    SessionPasswordStore.set(fixture.toxId, SecretPassword.fromString(_accountPassword));
    final zip = await AccountExportService.exportFullBackup(
      toxId: fixture.toxId,
      password: SecretPassword.fromString(_exportPassword),
      filePath: p.join(env.extras, 'backup.zip'),
    );
    final metadata = await AccountExportService.readFullBackupMetadata(
      zip,
      password: SecretPassword.fromString(_exportPassword),
    );
    expect(metadata['toxId'], fixture.toxId);
    expect(await File(profilePath).readAsBytes(),
        isNot(equals(fixture.savedata)),
        reason: 'the on-disk copy stays ciphertext');
  }, skip: skipReason);

  test('orphan reconciliation skips an encrypted profile quietly', () async {
    await Prefs.removeAccount(fixture.toxId);
    final prefix = fixture.publicKeyHex.substring(0, 16);
    final orphanDir = Directory(p.join(env.profiles, 'p_$prefix'));
    await orphanDir.create(recursive: true);
    await File(p.join(orphanDir.path, 'tox_profile.tox'))
        .writeAsBytes(passEncrypt(fixture.savedata, SecretPassword.fromString(_accountPassword)));
    expect(await AccountReconciliation.reconcileOrphanedProfiles(), 0);
    expect(await Prefs.getAccountList(), isEmpty);
  }, skip: skipReason);
}
