// Regression test for the account-switch stale-globals bug (S3 / roadmap L2-1).
//
// The bug (fixed 2026-05-28, `lib/util/account_service.dart:286-301`):
// switching accounts via `AccountService.initializeServiceForAccount` advanced
// `current_account_tox_id` but did NOT reset the global `self_nickname` /
// `self_status_msg` / `self_avatar_path` Prefs. The sidebar `_UserAvatar`
// (`lib/ui/settings/sidebar.dart:327-343`) reads those globals, so after a
// switch it kept rendering the *previous* account's name and avatar — a
// privacy-class identity-confusion bug. This test locks the fix: after
// switching to account B, the global nickname/status Prefs and the current
// account pointer must all reflect B, and no stale A avatar may leak.
//
// Coverage of the fixed block: the nickname/status reset (286-289) is locked
// directly. The avatar side (297-301) is a no-op when an account is active —
// setAvatarPath writes only the scoped record then — so the user-observable
// avatar property is actually guaranteed by getAvatarPath's per-account
// no-fallback logic (393-401); this test locks THAT (post-switch avatar is B's
// null, not A's stale path).
//
// Why this lives in `test/` and not `integration_test/`:
// like `test/account_reconciliation_test.dart`, it needs the tim2tox FFI dylib
// on the dlopen path (to build real profiles and run `init`/`login`), but it
// does NOT pump `TencentCloudChatMaterialApp` / the Hive `_getLocale`
// FutureBuilder, so it needs no host bundle. It runs under plain `flutter test`
// and skips when the FFI dylib is not loadable. (The layering doc files
// "real libtim2tox_ffi" under L2; in practice the host-bundle/`needs-native`
// gate is for tests that pump the full MaterialApp — see the `app_smoke_test`
// header. FFI-only-no-pump tests run in the normal suite with a skip-guard.)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:toxee/util/account_service.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';

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

/// Write [fixture]'s savedata to the production profile path
/// (`<profileStorageRoot>/p_<first16>/tox_profile.tox`) so that
/// `AccountService.initializeServiceForAccount` can load it.
Future<void> _stageProfile(ToxProfileFixture fixture) async {
  final dir = await AppPaths.getProfileDirectoryForToxId(fixture.toxId);
  await Directory(dir).create(recursive: true);
  await File(AppPaths.profileFileInDirectory(dir))
      .writeAsBytes(fixture.savedata, flush: true);
}

void main() {
  final ffiAvailable = _ffiAvailable();
  final skipReason = ffiAvailable
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('AccountService.initializeServiceForAccount resets global identity', () {
    late AccountExportTestEnv env;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
    });

    tearDown(() async {
      await env.dispose();
    });

    test('switch to account B resets nickname/status/current-toxId globals',
        () async {
      final fixtureA = ToxProfileFixture.create();
      final fixtureB = ToxProfileFixture.create();
      // Defensive: skip:skipReason already gates this, but ToxProfileFixture
      // can still return null if tox_new fails for a non-load reason.
      if (fixtureA == null || fixtureB == null) {
        markTestSkipped('ToxProfileFixture.create() returned null');
        return;
      }
      // Two distinct identities are required for the switch to be meaningful.
      expect(fixtureA.toxId, isNot(equalsIgnoringCase(fixtureB.toxId)));

      // Stage both real profiles on disk where the switch path expects them.
      await _stageProfile(fixtureA);
      await _stageProfile(fixtureB);

      // Seed account_list with both, then make A the active account with A's
      // identity labels in the globals — the pre-switch state. A carries a
      // distinct avatar; B carries none (so a stale-A-avatar leak is visible).
      const avatarA = '/tmp/toxee_test_avatar_a.png';
      await Prefs.addAccount(
          toxId: fixtureA.toxId,
          nickname: 'AccountA',
          statusMessage: 'statusA',
          avatarPath: avatarA);
      await Prefs.addAccount(
          toxId: fixtureB.toxId, nickname: 'AccountB', statusMessage: 'statusB');
      await Prefs.setCurrentAccountToxId(fixtureA.toxId);
      await Prefs.setNickname('AccountA');
      await Prefs.setStatusMessage('statusA');

      // Sanity: A is the active identity before the switch.
      expect(await Prefs.getNickname(), 'AccountA');
      expect(await Prefs.getStatusMessage(), 'statusA');
      expect(await Prefs.getCurrentAccountToxId(), fixtureA.toxId);
      expect(await Prefs.getAvatarPath(), avatarA);

      // The unit under test. startPolling:false keeps it off the DHT/network
      // (this is an L2-class deterministic check, not a live-network flow).
      final service = await AccountService.initializeServiceForAccount(
        toxId: fixtureB.toxId,
        nickname: 'AccountB',
        statusMessage: 'statusB',
        startPolling: false,
      );
      addTearDown(() async => service.dispose());

      // Regression assertions: the globals now reflect B, not A's stale values.
      // Pre-fix, getNickname()/getStatusMessage() would still return A's labels.
      expect(await Prefs.getNickname(), 'AccountB',
          reason: 'switch must reset global self_nickname to the new account');
      expect(await Prefs.getStatusMessage(), 'statusB',
          reason:
              'switch must reset global self_status_msg to the new account');
      // current pointer advances to B (the 76-char canonical form; the
      // ShortToxIdBackfill normalisation is case-insensitive vs the fixture's
      // uppercase address).
      expect(await Prefs.getCurrentAccountToxId(),
          equalsIgnoringCase(fixtureB.toxId),
          reason: 'current account pointer must advance to account B');
      // Avatar half: B had no avatar, so after the switch the avatar getter
      // must NOT return A's stale avatar. Since the self-avatar guarantee
      // (DefaultAvatarInstaller.ensureSelfAvatar, run by the switch path) an
      // activated account always has one: B gets its own bundled default,
      // installed under B's account_data directory. getAvatarPath() is
      // per-account-scoped and deliberately refuses to fall back to the global
      // _kAvatarPath; together these assert the no-leak property, which is the
      // avatar side of the identity-confusion bug.
      final avatarAfterSwitch = await Prefs.getAvatarPath();
      expect(avatarAfterSwitch, isNotNull,
          reason: 'an activated account always has a self avatar');
      expect(avatarAfterSwitch, isNot(avatarA),
          reason: 'no stale previous-account avatar may leak after switch');
      expect(avatarAfterSwitch,
          startsWith(await AppPaths.getAccountAvatarsPath(fixtureB.toxId)),
          reason: "the post-switch avatar must live in B's own avatars dir");
      expect(await File(avatarAfterSwitch!).exists(), isTrue);
    }, skip: skipReason);
  });
}
