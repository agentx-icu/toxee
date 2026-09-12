// Regression tests for the throwaway decrypted-profile copy that
// `discoverPlaceholderRealToxId` makes.
//
// Discovering the real Tox ID behind a `FlutterUIKitClient`-keyed account means
// OPENING the account, so for a password-protected one it can only happen after
// `LoginUseCase` has verified the password. It deliberately does NOT decrypt the
// account's own `tox_profile.tox`: it copies the file into a scratch directory
// under application support, decrypts the COPY, runs a throwaway session against
// it, and deletes the scratch in a `finally`.
//
// Two things went wrong with that, and both are what these tests exist to stop
// coming back:
//
//   * A kill between the decrypt and the `finally` stranded a DECRYPTED PRIVATE
//     KEY on disk indefinitely. Nothing else removed it — the early-return
//     guards at the top of discovery returned before any cleanup ran, and
//     account deletion knows nothing about these directories. The fix is
//     `sweepPlaceholderDiscoveryScratch()`, called at the very top of discovery
//     (ahead of every guard) and again from `AppBootstrap`'s recovery phase.
//
//   * The scratch directory had ONE deterministic name, so two concurrent
//     discoveries deleted each other's copy. That is worse than a lost temp
//     file: a native init that finds no profile does not fail, it mints a FRESH
//     identity, and the migration would then re-key the existing account's data
//     to that fabricated identity. Wrong identity, real data. The fix is a
//     per-call name, with the shared prefix kept only so the sweep can still
//     find strays.
//
// Everything here is hermetic — the sweep and the guards are what is under test,
// never the native session, so none of it needs `libtim2tox_ffi`.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/logger.dart';
import 'package:toxee/util/placeholder_account_migration.dart';
import 'package:toxee/util/placeholder_identity_discovery.dart';
import 'package:toxee/util/prefs.dart';

import 'account_export/test_support.dart';

const _placeholder = PlaceholderAccountMigration.placeholderToxId;

/// The on-disk contract the sweep matches on. Pinned here as a literal rather
/// than imported (it is private to the implementation) precisely because a
/// silent rename would make the sweep stop finding yesterday's strays while
/// every other test still passed.
const _scratchPrefix = '.placeholder_discovery_scratch_';

const _secureChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

void main() {
  late AccountExportTestEnv env;
  final secureStore = <String, String>{};

  setUp(() async {
    env = await setUpAccountExportTestEnv();
    AppLogger.resetForTesting();
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, (MethodCall call) async {
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
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, null);
    await env.dispose();
  });

  /// Stages a stranded scratch directory holding a file that stands in for the
  /// decrypted profile, and returns it.
  Future<Directory> strandScratch(String suffix) async {
    final dir = Directory(p.join(env.appSupport, '$_scratchPrefix$suffix'));
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'tox_profile.tox'))
        .writeAsString('decrypted private key stand-in');
    return dir;
  }

  group('sweepPlaceholderDiscoveryScratch', () {
    test('removes every stranded decrypted-profile copy', () async {
      // Prevents: a plaintext private key left on disk. A kill between the
      // decrypt and the `finally` used to strand the copy forever — nothing
      // else on any startup path knew the directory existed — and more than one
      // can accumulate, because each discovery now makes its own.
      final strays = [
        await strandScratch('1000_11'),
        await strandScratch('2000_22'),
        await strandScratch('3000_33'),
      ];
      // A nested payload: the sweep must remove a non-empty tree, not just an
      // empty directory.
      final nested = Directory(p.join(strays.first.path, 'inner'));
      await nested.create(recursive: true);
      await File(p.join(nested.path, 'more.bin')).writeAsBytes([1, 2, 3]);

      await sweepPlaceholderDiscoveryScratch();

      for (final stray in strays) {
        expect(await stray.exists(), isFalse,
            reason: '${p.basename(stray.path)} still holds a decrypted key');
      }
    });

    test('leaves everything that is not a scratch copy alone', () async {
      // Prevents: an account re-keyed to a fabricated identity — or simply
      // destroyed. The sweep runs unattended on every cold start, over the same
      // directory that holds `profiles/`, `account_data/` and the account list,
      // so an over-broad match here deletes the user's real account data with
      // no prompt and no undo.
      final stray = await strandScratch('4000_44');

      final realDirs = [
        Directory(p.join(env.appSupport, 'profiles')),
        Directory(p.join(env.appSupport, 'account_data')),
        // Near misses, one per direction: no leading dot, and the prefix
        // truncated before its trailing underscore.
        Directory(p.join(env.appSupport, 'placeholder_discovery_scratch_5000')),
        Directory(p.join(env.appSupport, '.placeholder_discovery')),
      ];
      for (final dir in realDirs) {
        await dir.create(recursive: true);
        await File(p.join(dir.path, 'keepme')).writeAsString('real data');
      }
      final realFile = File(p.join(env.appSupport, 'accounts.json'));
      await realFile.writeAsString('[]');

      await sweepPlaceholderDiscoveryScratch();

      expect(await stray.exists(), isFalse);
      for (final dir in realDirs) {
        expect(await dir.exists(), isTrue,
            reason: '${p.basename(dir.path)} was swept away');
        expect(await File(p.join(dir.path, 'keepme')).exists(), isTrue);
      }
      expect(await realFile.exists(), isTrue);
    });

    test('a copy it cannot remove does not throw out of the sweep', () async {
      // Prevents: a plaintext private key left on disk — by way of a startup
      // that never gets past the sweep. Both callers are on paths that must
      // proceed: discovery runs this before its own guards, and `AppBootstrap`
      // runs it inside the recovery phase whose failure blocks the whole app.
      // One unremovable leftover (wrong permissions, a file held open) must not
      // become a dead app or an aborted migration.
      final stray = await strandScratch('5000_55');
      // Deleting an entry needs write permission on its PARENT, so making
      // application support read-only makes the stray genuinely undeletable
      // while still leaving it listable.
      final chmodOff = await Process.run('chmod', ['u-w', env.appSupport]);
      expect(chmodOff.exitCode, 0, reason: 'test setup: chmod failed');
      addTearDown(() async {
        await Process.run('chmod', ['u+w', env.appSupport]);
      });

      await expectLater(sweepPlaceholderDiscoveryScratch(), completes);

      expect(await stray.exists(), isTrue,
          reason: 'test setup: the stray was removable after all, so this case '
              'never exercised the failure path');
    },
        skip: Platform.isWindows
            ? 'POSIX permission bits do not make a directory undeletable on '
                'Windows'
            : null);

    test('an absent application support directory does not throw', () async {
      // Prevents: the same dead startup as above, on a first run. The sweep is
      // the first thing discovery does and it runs during `AppBootstrap`'s
      // recovery phase, both of which can execute before anything has created
      // the directory it scans.
      await Directory(env.appSupport).delete(recursive: true);
      expect(await Directory(env.appSupport).exists(), isFalse);

      await expectLater(sweepPlaceholderDiscoveryScratch(), completes);
    });
  });

  group('discoverPlaceholderRealToxId', () {
    test('sweeps a stranded copy even when it refuses a protected account',
        () async {
      // Prevents: a plaintext private key left on disk forever. This is the
      // exact path that used to walk past the leftover — a protected account
      // with no verified password returns at the guard, so before the sweep was
      // hoisted above every guard the cleanup only ran on a discovery that got
      // all the way through, which for this account never happens until the
      // user logs in (and may never happen at all).
      final profileDir = await AppPaths.getProfileDirectoryForToxId(
        _placeholder,
      );
      await Directory(profileDir).create(recursive: true);
      await File(AppPaths.profileFileInDirectory(profileDir)).writeAsBytes(
        List<int>.generate(512, (i) => i % 251),
      );
      expect(
        await Prefs.setAccountPassword(_placeholder, 'correct horse'),
        isTrue,
      );
      expect(
        await Prefs.accountProtectionState(_placeholder),
        AccountProtectionState.protected,
        reason: 'test setup: the account must really look protected',
      );

      final stray = await strandScratch('6000_66');
      final bystander = File(p.join(env.appSupport, 'accounts.json'));
      await bystander.writeAsString('[]');

      final result = await discoverPlaceholderRealToxId();

      expect(result, isNull,
          reason: 'no Tox ID may be discovered without authentication');
      expect(await stray.exists(), isFalse,
          reason: 'the refusal returned without removing the decrypted copy');
      expect(await bystander.exists(), isTrue);
    });
  });

  group('wiring (source shape)', () {
    // These three cannot be observed from a unit-test process: two are about
    // WHERE a call sits relative to control flow that returns before it, and
    // the third is about a name that only a native session would ever consume.
    final discoverySource =
        File('lib/util/placeholder_identity_discovery.dart').readAsStringSync();
    final bootstrapSource =
        File('lib/bootstrap/app_bootstrap.dart').readAsStringSync();

    test('discovery sweeps before any guard can return', () async {
      // Prevents: a plaintext private key left on disk. Moving the sweep even
      // one statement below the first guard restores the original bug outright
      // — the protected-account and missing-profile returns fire on exactly the
      // accounts whose strays nothing else will ever collect.
      final fnStart =
          discoverySource.indexOf('Future<String?> discoverPlaceholderRealToxId');
      expect(fnStart, greaterThanOrEqualTo(0));
      final body = discoverySource.substring(fnStart);

      final sweepAt = body.indexOf('await sweepPlaceholderDiscoveryScratch();');
      final firstReturnNull = body.indexOf('return null;');

      expect(sweepAt, greaterThanOrEqualTo(0),
          reason: 'discovery no longer sweeps at all');
      expect(firstReturnNull, greaterThanOrEqualTo(0));
      expect(sweepAt, lessThan(firstReturnNull),
          reason: 'the sweep must precede every early return');
    });

    test('startup sweeps stranded copies before any guard can skip it',
        () async {
      // Prevents: a plaintext private key left on disk across a run in which
      // discovery never executes. Discovery only runs for an un-migrated
      // placeholder account; once the account is migrated (or while it stays
      // deferred behind a login the user does not perform), startup is the only
      // thing left that will ever collect the stray.
      //
      // The POSITION is the point. Inside the recovery phase, the sweep was
      // skipped whenever recovery threw (an unreadable journal raises the
      // blocked screen) and whenever the preferences bootstrap returned early -
      // so a stray survived every subsequent start, which is the state it was
      // added to prevent.
      expect(
        bootstrapSource,
        contains("import '../util/placeholder_identity_discovery.dart';"),
      );
      final sweepCall =
          bootstrapSource.indexOf('await _sweepStrandedScratchCopies();');
      final prefsGuard =
          bootstrapSource.indexOf('final prefsResult = await PrefsBootstrap');
      final recoveryStart = bootstrapSource
          .indexOf('await recoverPendingRestoreBeforeAccountExposure();');
      expect(sweepCall, greaterThanOrEqualTo(0),
          reason: 'startup no longer collects stranded copies');
      expect(prefsGuard, greaterThan(sweepCall),
          reason: 'a preferences upgrade that returns early must not skip it');
      expect(recoveryStart, greaterThan(sweepCall),
          reason: 'a recovery that throws must not skip it');
      expect(
        bootstrapSource,
        contains('await sweepPlaceholderDiscoveryScratch();'),
      );
    });

    test('the scratch directory name is built per call', () async {
      // Prevents: an account re-keyed to a fabricated identity. With one
      // deterministic name, two concurrent discoveries delete each other's
      // copy; a native init that then finds no profile does not fail, it mints
      // a FRESH identity, and the migration re-keys the real account's data to
      // it. Only the native session can surface that at runtime, so the
      // per-call name is pinned at the source.
      expect(
        discoverySource,
        contains("const _scratchDirPrefix = '$_scratchPrefix';"),
        reason: 'the sweep and the directories it hunts must agree on a prefix',
      );

      final open = discoverySource.indexOf('scratch = Directory(');
      expect(open, greaterThanOrEqualTo(0));
      final close = discoverySource.indexOf('await scratch.create(', open);
      expect(close, greaterThan(open));
      final construction = discoverySource.substring(open, close);

      expect(construction, contains(r'$_scratchDirPrefix'),
          reason: 'the shared prefix is what makes a stray sweepable');
      expect(construction, contains('microsecondsSinceEpoch'),
          reason: 'a constant name lets concurrent discoveries collide');
      expect(construction, contains('pid'),
          reason: 'two processes can start a discovery in the same microsecond');
    });
  });
}
