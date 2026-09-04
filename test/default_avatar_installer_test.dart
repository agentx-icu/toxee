import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/default_avatar_installer.dart';
import 'package:toxee/util/prefs.dart';

import 'account_export/test_support.dart';

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this._assets);

  final Map<String, Uint8List> _assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) {
      throw FlutterError('Missing fake asset for $key');
    }
    return ByteData.sublistView(bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DefaultAvatarInstaller', () {
    late AccountExportTestEnv env;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
    });

    tearDown(() async {
      await env.dispose();
      AppPaths.debugApplicationSupportOverride = null;
    });

    test(
      'installs the bundled default personal avatar into the account avatar directory',
      () async {
        const toxId =
            '00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF001122334455';
        final bundle = _FakeAssetBundle({
          DefaultAvatarInstaller.defaultUserAsset: Uint8List.fromList(<int>[
            1,
            2,
            3,
            4,
            5,
          ]),
        });

        await Prefs.setCurrentAccountToxId(toxId);

        final avatarPath =
            await DefaultAvatarInstaller.installDefaultUserAvatar(
              toxId: toxId,
              bundle: bundle,
            );

        final avatarsDir = await AppPaths.getAccountAvatarsPath(toxId);
        expect(avatarPath, startsWith(avatarsDir));
        expect(p.basename(avatarPath), 'avatar_${toxId}_default.png');
        expect(await File(avatarPath).exists(), isTrue);
        expect(await File(avatarPath).readAsBytes(), <int>[1, 2, 3, 4, 5]);
      },
    );

    test(
      'installs the bundled default group avatar into the account avatar directory and persists the pref',
      () async {
        const toxId =
            '00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF001122334455';
        const groupId = 'group-alpha';
        final bundle = _FakeAssetBundle({
          DefaultAvatarInstaller.defaultGroupAsset: Uint8List.fromList(<int>[
            9,
            8,
            7,
            6,
          ]),
        });

        await Prefs.setCurrentAccountToxId(toxId);

        final avatarPath =
            await DefaultAvatarInstaller.installDefaultGroupAvatar(
              groupId: groupId,
              toxId: toxId,
              bundle: bundle,
            );
        await Prefs.setGroupAvatar(groupId, avatarPath);

        final avatarsDir = await AppPaths.getAccountAvatarsPath(toxId);
        expect(avatarPath, startsWith(avatarsDir));
        expect(p.basename(avatarPath), 'group_group-alpha_default.png');
        expect(await File(avatarPath).exists(), isTrue);
        expect(await File(avatarPath).readAsBytes(), <int>[9, 8, 7, 6]);
        expect(await Prefs.getGroupAvatar(groupId), avatarPath);
      },
    );
  });

  group('DefaultAvatarInstaller.ensureSelfAvatar', () {
    const toxId =
        '00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF001122334455';
    final publicKey = toxId.substring(0, 64);
    final scopedKey = 'self_avatar_path_${toxId.substring(0, 16)}';
    final defaultBundle = _FakeAssetBundle({
      DefaultAvatarInstaller.defaultUserAsset: Uint8List.fromList(<int>[
        1,
        2,
        3,
      ]),
    });
    // A bundle with no assets: installing the default would throw, so a
    // test that passes it proves the default was NOT (re)installed.
    final emptyBundle = _FakeAssetBundle({});
    late AccountExportTestEnv env;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
    });

    tearDown(() async {
      await env.dispose();
      AppPaths.debugApplicationSupportOverride = null;
    });

    Future<File> writeAvatar(String fileName) async {
      final avatarsDir = await AppPaths.getAccountAvatarsPath(toxId);
      final file = File(p.join(avatarsDir, fileName));
      await file.create(recursive: true);
      await file.writeAsBytes(<int>[7], flush: true);
      return file;
    }

    test('installs the bundled default when the account has no avatar anywhere '
        'and writes both stores', () async {
      // A recovered / imported account: row exists, no avatarPath.
      await Prefs.addAccount(toxId: toxId, nickname: 'Recovered 00112233');

      final path = await DefaultAvatarInstaller.ensureSelfAvatar(
        toxId: toxId,
        bundle: defaultBundle,
      );

      expect(path, isNotNull);
      expect(p.basename(path!), 'avatar_${toxId}_default.png');
      expect(await File(path).readAsBytes(), <int>[1, 2, 3]);
      final row = await Prefs.getAccountByToxId(toxId);
      expect(row?['avatarPath'], path);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(scopedKey), path);
      // Both readers agree once the account is active.
      await Prefs.setCurrentAccountToxId(toxId);
      expect(await Prefs.getAvatarPath(), path);
    });

    test(
      'keeps the account_list avatar and mirrors it to the scoped key',
      () async {
        final existing = await writeAvatar('avatar_${toxId}_1783520987718.png');
        await Prefs.addAccount(
          toxId: toxId,
          nickname: 'Me',
          avatarPath: existing.path,
        );

        final path = await DefaultAvatarInstaller.ensureSelfAvatar(
          toxId: toxId,
          bundle: emptyBundle,
        );

        expect(path, existing.path);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(scopedKey), existing.path);
      },
    );

    test(
      'adopts the scoped key (full-backup restore) when the row has none',
      () async {
        final restored = await writeAvatar('avatar_${toxId}_restored.png');
        await Prefs.addAccount(toxId: toxId, nickname: 'Me');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(scopedKey, restored.path);

        final path = await DefaultAvatarInstaller.ensureSelfAvatar(
          toxId: toxId,
          bundle: emptyBundle,
        );

        expect(path, restored.path);
        final row = await Prefs.getAccountByToxId(toxId);
        expect(row?['avatarPath'], restored.path);
      },
    );

    test('adopts the newest self-avatar file on disk — matched by public key, '
        'any extension, friend/group files ignored', () async {
      await Prefs.addAccount(toxId: toxId, nickname: 'Me');
      final older = await writeAvatar('avatar_${publicKey}_100.jpg');
      final newer = await writeAvatar('avatar_${toxId}_200.jpeg');
      final friend = await writeAvatar('friend_${'F' * 64}_avatar_999.png');
      final now = DateTime.now();
      await older.setLastModified(now.subtract(const Duration(hours: 2)));
      await newer.setLastModified(now.subtract(const Duration(hours: 1)));
      await friend.setLastModified(now);

      final path = await DefaultAvatarInstaller.ensureSelfAvatar(
        toxId: toxId,
        bundle: emptyBundle,
      );

      expect(path, newer.path);
      final row = await Prefs.getAccountByToxId(toxId);
      expect(row?['avatarPath'], newer.path);
    });

    test('replaces a row path whose file is gone', () async {
      await Prefs.addAccount(
        toxId: toxId,
        nickname: 'Me',
        avatarPath: p.join(env.appSupport, 'missing.png'),
      );

      final path = await DefaultAvatarInstaller.ensureSelfAvatar(
        toxId: toxId,
        bundle: defaultBundle,
      );

      expect(path, isNotNull);
      expect(p.basename(path!), 'avatar_${toxId}_default.png');
      final row = await Prefs.getAccountByToxId(toxId);
      expect(row?['avatarPath'], path);
    });

    test(
      'never throws and leaves the stores alone when the asset is missing',
      () async {
        await Prefs.addAccount(toxId: toxId, nickname: 'Me');

        final path = await DefaultAvatarInstaller.ensureSelfAvatar(
          toxId: toxId,
          bundle: emptyBundle,
        );

        expect(path, isNull);
        final row = await Prefs.getAccountByToxId(toxId);
        expect(row?.containsKey('avatarPath'), isFalse);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(scopedKey), isNull);
      },
    );

    test('Prefs.getAvatarPath falls back to the scoped key when the row has '
        'no avatar, but never to the global legacy key', () async {
      await Prefs.addAccount(toxId: toxId, nickname: 'Me');
      await Prefs.setCurrentAccountToxId(toxId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('self_avatar_path', '/other/account/avatar.png');
      expect(await Prefs.getAvatarPath(), isNull);

      await prefs.setString(scopedKey, '/restored/avatar.png');
      expect(await Prefs.getAvatarPath(), '/restored/avatar.png');
    });
  });
}
