// UI-9: group avatar paths are stored RELATIVE to the account avatars dir.
//
// The `group_avatar_<id>` pref used to hold an absolute path. On iOS the app
// container's UUID segment changes on reinstall / update / restore, so the
// stored path pointed into a dead container and the group fell back to the
// placeholder. These tests lock: relative storage, backward-compatible reads
// of legacy absolute values (including re-anchoring one whose container
// moved), verbatim pass-through of non-avatar-dir values, and the Prefs /
// tim2tox adapter round trip. Shared Dart → the same code runs on every
// platform (the bug only bites where the container moves: iOS, sandboxed
// macOS reinstalls).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/adapters/shared_prefs_adapter.dart';
import 'package:toxee/ui/group/group_avatar_announce.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/group_avatar_path.dart';
import 'package:toxee/util/prefs.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pure path mapping', () {
    const prefix = 'AAAAAAAAAAAAAAAA';
    String avatarsIn(String container) => p.join(p.separator, 'c', container,
        'Library', 'account_data', prefix, 'avatars');
    final dir = avatarsIn('OLD-UUID');
    final newDir = avatarsIn('NEW-UUID');

    test('a file inside the account avatars dir is stored relative', () {
      expect(toStoredGroupAvatar(p.join(dir, 'group_g1_5.png'), prefix),
          'group_g1_5.png');
    });

    test('values outside that dir are stored verbatim', () {
      final other = p.join(p.separator, 'tmp', 'x.png');
      expect(toStoredGroupAvatar(other, prefix), other);
      final otherAccount = p.join(p.separator, 'c', 'account_data',
          'BBBBBBBBBBBBBBBB', 'avatars', 'group_g1_5.png');
      expect(toStoredGroupAvatar(otherAccount, prefix), otherAccount,
          reason: 'another account\'s avatars dir is not ours to re-anchor');
      expect(toStoredGroupAvatar('https://h/x.png', prefix), 'https://h/x.png');
      expect(toStoredGroupAvatar('', prefix), '');
    });

    test('a relative value resolves against the CURRENT avatars dir', () {
      expect(resolveStoredGroupAvatar('group_g1_5.png', newDir),
          p.join(newDir, 'group_g1_5.png'));
    });

    test('a legacy absolute path that still exists is returned as-is', () {
      final legacy = p.join(dir, 'group_g1_5.png');
      expect(
          resolveStoredGroupAvatar(legacy, dir, exists: (_) => true), legacy);
    });

    test('a legacy absolute path into a moved container is re-anchored', () {
      final legacy = p.join(dir, 'group_g1_5.png');
      final rebased = p.join(newDir, 'group_g1_5.png');
      expect(
        resolveStoredGroupAvatar(legacy, newDir,
            exists: (path) => path == rebased),
        rebased,
      );
    });

    test('a dead path with no carried-over file is left untouched', () {
      final legacy = p.join(dir, 'group_g1_5.png');
      expect(resolveStoredGroupAvatar(legacy, newDir, exists: (_) => false),
          legacy);
      final foreign = p.join(p.separator, 'tmp', 'gone.png');
      expect(resolveStoredGroupAvatar(foreign, newDir, exists: (_) => true),
          foreign);
    });

    test('URLs are never rewritten', () {
      expect(resolveStoredGroupAvatar('https://h/x.png', dir),
          'https://h/x.png');
    });
  });

  group('Prefs / adapter round trip', () {
    const toxId =
        'AAAAAAAAAAAAAAAA111111111111111111111111111111111111111111111111111111111111';
    late Directory root;
    late String avatarsDir;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('group_avatar_path_test_');
      AppPaths.debugApplicationSupportOverride = root.path;
      SharedPreferences.setMockInitialValues({});
      await Prefs.initialize(await SharedPreferences.getInstance());
      await Prefs.setCurrentAccountToxId(toxId);
      avatarsDir = await AppPaths.getAccountAvatarsPath(toxId);
      await Directory(avatarsDir).create(recursive: true);
    });

    tearDown(() async {
      AppPaths.debugApplicationSupportOverride = null;
      await Prefs.setCurrentAccountToxId(null);
      if (root.existsSync()) await root.delete(recursive: true);
    });

    Future<String?> rawStored(String groupId) async {
      final sp = await SharedPreferences.getInstance();
      final key = sp.getKeys().firstWhere(
            (k) => k.startsWith('group_avatar_$groupId'),
            orElse: () => '',
          );
      return key.isEmpty ? null : sp.getString(key);
    }

    test('Prefs stores relative and returns the absolute current path',
        () async {
      final abs = p.join(avatarsDir, 'group_g1_7.png');
      await File(abs).writeAsBytes(<int>[1]);
      await Prefs.setGroupAvatar('g1', abs);
      expect(await rawStored('g1'), 'group_g1_7.png');
      expect(await Prefs.getGroupAvatar('g1'), abs);
    });

    test('Prefs re-anchors a legacy absolute value from a moved container',
        () async {
      final current = p.join(avatarsDir, 'group_g2_7.png');
      await File(current).writeAsBytes(<int>[1]);
      final sp = await SharedPreferences.getInstance();
      // Simulate a value written by an older build under an old container.
      await Prefs.setGroupAvatar('g2', current);
      final key =
          sp.getKeys().firstWhere((k) => k.startsWith('group_avatar_g2'));
      await sp.setString(
        key,
        p.join(p.separator, 'gone', 'OLD-UUID', 'account_data',
            toxId.substring(0, 16), 'avatars', 'group_g2_7.png'),
      );
      expect(await Prefs.getGroupAvatar('g2'), current);
    });

    test('the tim2tox adapter reads and writes the same relative form',
        () async {
      final adapter = SharedPreferencesAdapter(
        await SharedPreferences.getInstance(),
        instanceId: 0,
      );
      adapter.setAccountPrefix(toxId.substring(0, 16));
      final abs = p.join(avatarsDir, 'group_g3_7.png');
      await File(abs).writeAsBytes(<int>[1]);
      await adapter.setGroupAvatar('g3', abs);
      expect(await rawStored('g3'), 'group_g3_7.png');
      expect(await adapter.getGroupAvatar('g3'), abs);
      // And the UI side sees the same value the platform wrote.
      expect(await Prefs.getGroupAvatar('g3'), abs);
    });

    test('announceGroupAvatarChange persists, announces FACE and refreshes',
        () async {
      final abs = p.join(avatarsDir, 'group_g4_7.png');
      await File(abs).writeAsBytes(<int>[1]);
      String? announcedGroup;
      String? announcedFace;
      var refreshed = 0;
      await announceGroupAvatarChange(
        groupID: 'g4',
        groupType: 'Work',
        path: abs,
        setGroupInfo: ({
          required String groupID,
          required String groupType,
          String? faceUrl,
        }) async {
          announcedGroup = groupID;
          announcedFace = faceUrl;
          return V2TimCallback(code: 0, desc: 'ok');
        },
        refreshConversations: () async => refreshed++,
      );
      expect(await Prefs.getGroupAvatar('g4'), abs);
      expect(announcedGroup, 'g4');
      expect(announcedFace, abs,
          reason: 'the platform setGroupInfo fires onGroupInfoChanged(FACE_URL) '
              'so the Contacts group list updates');
      expect(refreshed, 1,
          reason: 'the conversation row and an open chat header follow the '
              'refreshed conversation list');
    });
  });
}
