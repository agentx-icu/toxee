// Legacy single-profile adoption with a password.
//
// `AccountService.initializeServiceForAccount` falls back to the pre-multi-
// account `<appSupport>/tim2tox/tox_profile.tox` when the per-account profile
// is missing, but only after proving the legacy file is this account's. An
// ENCRYPTED legacy file used to be refused outright (`identity_unreadable`)
// even though the caller's password would open it; now it is attributed with
// that password (`adoptLegacyProfileForAccount`), copied as-is (ciphertext)
// and opened by the native init. A wrong or missing password still refuses.
//
// Layer: like test/account_password_lifecycle_test.dart this needs the real
// libtim2tox_ffi dylib (Tox encryption + profile load), so every test carries
// the _ffiAvailable() skip-guard. CI builds and stages the dylib.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:toxee/util/account_export/account_export_service.dart';
import 'package:toxee/util/account_service.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/session_password_store.dart';

import 'account_export/test_support.dart';
import 'account_export/tox_profile_factory.dart';

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

/// Write the fixture where the pre-multi-account app kept its one profile.
Future<String> _stageLegacyProfile(ToxProfileFixture fixture) async {
  final dir = await AppPaths.toxProfileDir;
  await dir.create(recursive: true);
  final path = p.join(dir.path, 'tox_profile.tox');
  await File(path).writeAsBytes(fixture.savedata, flush: true);
  return path;
}

Future<String> _perAccountProfilePath(String toxId) async =>
    AppPaths.profileFileInDirectory(
      await AppPaths.getProfileDirectoryForToxId(toxId),
    );

final Matcher _refusesAdoption = throwsA(
  predicate<Object>(
    (e) => e.toString().contains('Profile not found for account'),
    'refuses with "Profile not found for account"',
  ),
);

void main() {
  final ffiAvailable = _ffiAvailable();
  final skipReason = ffiAvailable
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  late AccountExportTestEnv env;

  setUp(() async {
    env = await setUpAccountExportTestEnv();
    SessionPasswordStore.clear();
  });

  tearDown(() async {
    SessionPasswordStore.clear();
    await env.dispose();
  });

  group('encrypted legacy profile', () {
    test('is adopted with the account password and stays ciphertext on disk',
        () async {
      final fixture = ToxProfileFixture.create();
      if (fixture == null) {
        markTestSkipped('ToxProfileFixture.create() returned null');
        return;
      }
      const password = 'legacy-pw';
      final legacyPath = await _stageLegacyProfile(fixture);
      await AccountExportService.encryptProfileFile(legacyPath, password);
      final profilePath = await _perAccountProfilePath(fixture.toxId);
      expect(File(profilePath).existsSync(), isFalse,
          reason: 'precondition: no per-account profile yet');
      await Prefs.addAccount(toxId: fixture.toxId, nickname: 'Legacy');
      await Prefs.setCurrentAccountToxId(fixture.toxId);

      final service = await AccountService.initializeServiceForAccount(
        toxId: fixture.toxId,
        password: password,
        startPolling: false,
      );
      addTearDown(() async {
        try {
          await service.dispose();
        } catch (_) {}
      });

      expect(File(profilePath).existsSync(), isTrue,
          reason: 'the legacy profile was adopted as this account\'s');
      expect(await AccountExportService.isProfileFileEncrypted(profilePath),
          isTrue,
          reason: 'copied as-is: never plaintext on disk');
      expect(await AccountExportService.isProfileFileEncrypted(legacyPath),
          isTrue,
          reason: 'the legacy file is left where it was, untouched');
      expect(SessionPasswordStore.get(fixture.toxId), password,
          reason: 'the session ran as this account under its password');
    }, skip: skipReason);

    test('is refused with a wrong password and nothing is copied', () async {
      final fixture = ToxProfileFixture.create();
      if (fixture == null) {
        markTestSkipped('ToxProfileFixture.create() returned null');
        return;
      }
      final legacyPath = await _stageLegacyProfile(fixture);
      await AccountExportService.encryptProfileFile(legacyPath, 'right-pw');
      await Prefs.addAccount(toxId: fixture.toxId, nickname: 'Legacy');

      await expectLater(
        AccountService.initializeServiceForAccount(
          toxId: fixture.toxId,
          password: 'wrong-pw',
          startPolling: false,
        ),
        _refusesAdoption,
      );
      expect(
          File(await _perAccountProfilePath(fixture.toxId)).existsSync(),
          isFalse,
          reason: 'an unattributed legacy file is never installed');
      expect(await AccountExportService.isProfileFileEncrypted(legacyPath),
          isTrue);
    }, skip: skipReason);

    test('is refused without a password', () async {
      final fixture = ToxProfileFixture.create();
      if (fixture == null) {
        markTestSkipped('ToxProfileFixture.create() returned null');
        return;
      }
      final legacyPath = await _stageLegacyProfile(fixture);
      await AccountExportService.encryptProfileFile(legacyPath, 'pw');
      await Prefs.addAccount(toxId: fixture.toxId, nickname: 'Legacy');

      await expectLater(
        AccountService.initializeServiceForAccount(
          toxId: fixture.toxId,
          startPolling: false,
        ),
        _refusesAdoption,
      );
      expect(
          File(await _perAccountProfilePath(fixture.toxId)).existsSync(),
          isFalse);
    }, skip: skipReason);

    test('belonging to another identity is refused even with its password, '
        'and nothing is copied', () async {
      final legacy = ToxProfileFixture.create();
      final requested = ToxProfileFixture.create();
      if (legacy == null || requested == null) {
        markTestSkipped('ToxProfileFixture.create() returned null');
        return;
      }
      const password = 'shared-pw';
      final legacyPath = await _stageLegacyProfile(legacy);
      await AccountExportService.encryptProfileFile(legacyPath, password);
      await Prefs.addAccount(toxId: requested.toxId, nickname: 'Other');

      await expectLater(
        AccountService.initializeServiceForAccount(
          toxId: requested.toxId,
          password: password,
          startPolling: false,
        ),
        _refusesAdoption,
      );
      expect(
          File(await _perAccountProfilePath(requested.toxId)).existsSync(),
          isFalse,
          reason: 'the password opens the file but does not make it ours');
      expect(
          File(await _perAccountProfilePath(legacy.toxId)).existsSync(),
          isFalse);
    }, skip: skipReason);
  });

  group('plaintext legacy profile', () {
    test('is adopted with a password and encrypted by the init itself',
        () async {
      final fixture = ToxProfileFixture.create();
      if (fixture == null) {
        markTestSkipped('ToxProfileFixture.create() returned null');
        return;
      }
      const password = 'upgrade-pw';
      final legacyPath = await _stageLegacyProfile(fixture);
      await Prefs.addAccount(toxId: fixture.toxId, nickname: 'Legacy');
      await Prefs.setCurrentAccountToxId(fixture.toxId);

      final service = await AccountService.initializeServiceForAccount(
        toxId: fixture.toxId,
        password: password,
        startPolling: false,
      );
      addTearDown(() async {
        try {
          await service.dispose();
        } catch (_) {}
      });
      final profilePath = await _perAccountProfilePath(fixture.toxId);
      expect(await AccountExportService.isProfileFileEncrypted(profilePath),
          isTrue,
          reason: 'plaintext is attributed without the password, then the '
              'native init re-writes the adopted copy encrypted');
      expect(await AccountExportService.isProfileFileEncrypted(legacyPath),
          isFalse,
          reason: 'the legacy original is left as it was');
    }, skip: skipReason);

    test('is still adopted without a password', () async {
      final fixture = ToxProfileFixture.create();
      if (fixture == null) {
        markTestSkipped('ToxProfileFixture.create() returned null');
        return;
      }
      await _stageLegacyProfile(fixture);
      await Prefs.addAccount(toxId: fixture.toxId, nickname: 'Legacy');
      await Prefs.setCurrentAccountToxId(fixture.toxId);

      final service = await AccountService.initializeServiceForAccount(
        toxId: fixture.toxId,
        startPolling: false,
      );
      addTearDown(() async {
        try {
          await service.dispose();
        } catch (_) {}
      });
      final profilePath = await _perAccountProfilePath(fixture.toxId);
      expect(File(profilePath).existsSync(), isTrue);
      expect(await AccountExportService.isProfileFileEncrypted(profilePath),
          isFalse);
    }, skip: skipReason);

    test('belonging to another identity is refused', () async {
      final legacy = ToxProfileFixture.create();
      final requested = ToxProfileFixture.create();
      if (legacy == null || requested == null) {
        markTestSkipped('ToxProfileFixture.create() returned null');
        return;
      }
      await _stageLegacyProfile(legacy);
      await Prefs.addAccount(toxId: requested.toxId, nickname: 'Other');

      await expectLater(
        AccountService.initializeServiceForAccount(
          toxId: requested.toxId,
          startPolling: false,
        ),
        _refusesAdoption,
      );
      expect(
          File(await _perAccountProfilePath(requested.toxId)).existsSync(),
          isFalse);
    }, skip: skipReason);
  });
}
