import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:toxee/bootstrap/app_bootstrap.dart';
import 'package:toxee/util/account_export_service.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/secret_password.dart';

import 'account_export/test_support.dart';
import 'account_export/tox_profile_factory.dart';

void main() {
  late AccountExportTestEnv env;
  late bool refuseCredentialDeletion;
  final secureStore = <String, String>{};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() async {
    env = await setUpAccountExportTestEnv();
    secureStore.clear();
    refuseCredentialDeletion = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = (call.arguments as Map?) ?? const {};
          final key = args['key'] as String?;
          switch (call.method) {
            case 'read':
              return secureStore[key];
            case 'write':
              secureStore[key!] = args['value'] as String;
              return null;
            case 'delete':
              if (refuseCredentialDeletion) {
                throw PlatformException(code: 'secure-delete-failed');
              }
              secureStore.remove(key);
              return null;
            case 'containsKey':
              return secureStore.containsKey(key);
            case 'readAll':
              return Map<String, String>.of(secureStore);
            default:
              return null;
          }
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await env.dispose();
  });

  test(
    'cold start recovers protected registration stranded after rename',
    () async {
      final fixture = ToxProfileFixture.create();
      if (fixture == null) {
        if (Platform.environment['TOXEE_TESTS_NEED_NATIVE'] == '1') {
          fail('Native Tox profile fixture is required');
        }
        markTestSkipped('Native Tox profile fixture is unavailable');
        return;
      }
      final password = SecretPassword.fromString('registration password');
      addTearDown(password.dispose);
      final profileDir = await AppPaths.getProfileDirectoryForToxId(
        fixture.toxId,
      );
      await Directory(profileDir).create(recursive: true);
      final profile = File(AppPaths.profileFileInDirectory(profileDir));
      await profile.writeAsBytes(fixture.savedata, flush: true);
      await AccountExportService.encryptProfileFile(profile.path, password);
      expect(await Prefs.setAccountPassword(fixture.toxId, password), isTrue);
      final encryptedProfile = await profile.readAsBytes();
      final marker = File(p.join(profileDir, '.toxee_registration.json'));
      await marker.writeAsString(
        jsonEncode({
          'version': 1,
          'toxId': fixture.toxId,
          'nickname': 'Interrupted registration',
          'statusMessage': 'Recovered status',
          'expectsPassword': true,
        }),
        flush: true,
      );
      final previousId = '3' * 76;
      await Prefs.addAccount(toxId: previousId, nickname: 'Existing account');
      await Prefs.setCurrentAccountToxId(previousId);

      await AppBootstrap.recoverPendingRestoreBeforeAccountExposure();
      await AppBootstrap.recoverPendingRestoreBeforeAccountExposure();

      final account = await Prefs.getAccountByToxId(fixture.toxId);
      expect(account?['nickname'], 'Interrupted registration');
      expect(account?['statusMessage'], 'Recovered status');
      expect(await Prefs.getAutoLogin(fixture.toxId), isFalse);
      expect(await Prefs.hasAccountPassword(fixture.toxId), isTrue);
      expect(await profile.readAsBytes(), encryptedProfile);
      expect(await marker.exists(), isFalse);
      expect(await Prefs.getCurrentAccountToxId(), previousId);
      expect(await Prefs.getAccountList(), hasLength(2));
    },
  );

  test(
    'an unfinished staged verifier is retried without sweeping legacy dirs',
    () async {
      final toxId = '4' * 76;
      final stage = await Directory(
        env.profiles,
      ).createTemp('.tmp_register_v1_');
      final legacyStage = await Directory(
        env.profiles,
      ).createTemp('.tmp_register_');
      await File(p.join(stage.path, '.toxee_registration.json')).writeAsString(
        jsonEncode({
          'version': 1,
          'toxId': toxId,
          'nickname': 'Unfinished registration',
          'statusMessage': '',
          'expectsPassword': true,
        }),
      );
      final password = SecretPassword.fromString('stage password');
      addTearDown(password.dispose);
      expect(await Prefs.setAccountPassword(toxId, password), isTrue);

      refuseCredentialDeletion = true;
      await AppBootstrap.recoverPendingRestoreBeforeAccountExposure();
      expect(await stage.exists(), isTrue);
      expect(await Prefs.hasAccountPassword(toxId), isTrue);

      refuseCredentialDeletion = false;
      await AppBootstrap.recoverPendingRestoreBeforeAccountExposure();
      expect(await stage.exists(), isFalse);
      expect(await Prefs.hasAccountPassword(toxId), isFalse);
      expect(await legacyStage.exists(), isTrue);
      expect(await Prefs.getAccountList(), isEmpty);
    },
  );
}
