import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/ios_backup_policy.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const toxId =
      '0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF123456789ABC';
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'toxee_ios_backup_policy_',
    );
    AppPaths.debugApplicationSupportOverride = tempRoot.path;
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await Prefs.initialize(await SharedPreferences.getInstance());
  });

  tearDown(() async {
    AppPaths.debugApplicationSupportOverride = null;
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('IosBackupPathPolicy.resolve', () {
    test(
      'uses the active default profile root and preserves backup data',
      () async {
        final policy = await IosBackupPathPolicy.resolve(toxId);
        final accountRoot = p.join(
          tempRoot.path,
          'account_data',
          '0123456789ABCDEF',
        );

        expect(
          policy.sensitiveProfileDirectory,
          p.join(tempRoot.path, 'profiles', 'p_0123456789ABCDEF'),
        );
        expect(policy.excludedPaths, <String>{
          p.join(tempRoot.path, 'profiles', 'p_0123456789ABCDEF'),
          p.join(accountRoot, 'file_recv'),
          p.join(accountRoot, 'avatars'),
        });
        expect(policy.backupEligiblePaths, <String>{
          p.join(accountRoot, 'chat_history'),
          p.join(accountRoot, 'offline_message_queue.json'),
        });
        expect(
          policy.excludedPaths.intersection(policy.backupEligiblePaths),
          isEmpty,
        );
      },
    );

    test(
      'uses the configured profile storage root for the active account',
      () async {
        final customRoot = p.join(tempRoot.path, 'custom_profiles');
        await Prefs.setProfileStorageRoot(customRoot);

        final policy = await IosBackupPathPolicy.resolve(toxId);

        expect(
          policy.sensitiveProfileDirectory,
          p.join(customRoot, 'p_0123456789ABCDEF'),
        );
        expect(
          policy.excludedPaths,
          contains(policy.sensitiveProfileDirectory),
        );
        expect(
          policy.sensitiveProfileDirectory,
          await AppPaths.getProfileDirectoryForToxId(toxId),
        );
        expect(
          policy.sensitiveProfileDirectory,
          isNot((await AppPaths.toxProfileDir).path),
        );
      },
    );
  });

  group('IosPostLoginBackupExcluder.apply', () {
    const paths = IosBackupPathPolicy(
      sensitiveProfileDirectory: '/profiles/p_account',
      derivableExcludedPaths: <String>{
        '/account/file_recv',
        '/account/avatars',
      },
      backupEligiblePaths: <String>{
        '/account/chat_history',
        '/account/offline_message_queue.json',
      },
    );

    test(
      'awaits the sensitive profile before marking derivable paths',
      () async {
        final profileMarked = Completer<void>();
        final calls = <String>[];
        final excluder = IosPostLoginBackupExcluder(
          isIos: true,
          resolvePaths: (_) async => paths,
          excludeFromBackup: (path) {
            calls.add(path);
            if (path == paths.sensitiveProfileDirectory) {
              return profileMarked.future;
            }
            return Future<void>.value();
          },
        );

        var completed = false;
        final applyFuture = excluder.apply(toxId);
        final observedFuture = applyFuture.whenComplete(() => completed = true);
        await Future<void>.delayed(Duration.zero);

        expect(calls, <String>[paths.sensitiveProfileDirectory]);
        expect(completed, isFalse);

        profileMarked.complete();
        await observedFuture;
        expect(calls, <String>[
          paths.sensitiveProfileDirectory,
          ...paths.derivableExcludedPaths,
        ]);
      },
    );

    test('surfaces sensitive profile exclusion failure', () async {
      final calls = <String>[];
      final excluder = IosPostLoginBackupExcluder(
        isIos: true,
        resolvePaths: (_) async => paths,
        excludeFromBackup: (path) async {
          calls.add(path);
          if (path == paths.sensitiveProfileDirectory) {
            throw StateError('profile exclusion failed');
          }
        },
      );

      await expectLater(
        excluder.apply(toxId),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'profile exclusion failed',
          ),
        ),
      );
      expect(calls, <String>[paths.sensitiveProfileDirectory]);
    });

    test(
      'logs derivable failures and continues with remaining cache paths',
      () async {
        final calls = <String>[];
        final failures = <String>[];
        final excluder = IosPostLoginBackupExcluder(
          isIos: true,
          resolvePaths: (_) async => paths,
          excludeFromBackup: (path) async {
            calls.add(path);
            if (path == '/account/file_recv') {
              throw StateError('cache exclusion failed');
            }
          },
          reportDerivableFailure: (path, _, __) => failures.add(path),
        );

        await excluder.apply(toxId);

        expect(calls, <String>[
          paths.sensitiveProfileDirectory,
          ...paths.derivableExcludedPaths,
        ]);
        expect(failures, <String>['/account/file_recv']);
      },
    );

    test('is a no-op off iOS without resolving or marking paths', () async {
      var resolved = false;
      var marked = false;
      final excluder = IosPostLoginBackupExcluder(
        isIos: false,
        resolvePaths: (_) async {
          resolved = true;
          return paths;
        },
        excludeFromBackup: (_) async => marked = true,
      );

      await excluder.apply(toxId);

      expect(resolved, isFalse);
      expect(marked, isFalse);
    });

    test(
      'missing real Tox ID fails before resolving or marking a path',
      () async {
        for (final invalidToxId in <String?>[null, '', '   ']) {
          var resolved = false;
          var marked = false;
          final excluder = IosPostLoginBackupExcluder(
            isIos: true,
            resolvePaths: (_) async {
              resolved = true;
              return paths;
            },
            excludeFromBackup: (_) async => marked = true,
          );

          await expectLater(
            excluder.apply(invalidToxId),
            throwsA(isA<StateError>()),
          );
          expect(resolved, isFalse);
          expect(marked, isFalse);
        }
      },
    );

    test(
      'FlutterUIKitClient fallback cannot resolve or mark a profile path',
      () async {
        const fallbackSelfId = 'FlutterUIKitClient';
        const String? realToxId = null;
        final resolvedToxIds = <String>[];
        final markedPaths = <String>[];
        final excluder = IosPostLoginBackupExcluder(
          isIos: true,
          resolvePaths: (toxId) async {
            resolvedToxIds.add(toxId);
            return paths;
          },
          excludeFromBackup: (path) async => markedPaths.add(path),
        );

        await expectLater(
          excluder.apply(realToxId),
          throwsA(isA<StateError>()),
        );
        expect(resolvedToxIds, isNot(contains(fallbackSelfId)));
        expect(resolvedToxIds, isEmpty);
        expect(markedPaths, isEmpty);
      },
    );
  });

  test(
    'session boot awaits the iOS policy so profile failures propagate',
    () async {
      final source = await File(
        'lib/util/app_bootstrap_coordinator.dart',
      ).readAsString();

      expect(
        source,
        contains('await IosPostLoginBackupExcluder(isIos: true).apply(toxId);'),
      );
      expect(
        source,
        isNot(
          contains(
            'unawaited(IosPostLoginBackupExcluder(isIos: true).apply(toxId))',
          ),
        ),
      );
      expect(source, contains('final toxId = service.getSelfToxId();'));
      final identityGuard = source.indexOf(
        'if (toxId == null || toxId.trim().isEmpty)',
      );
      final exclusionCall = source.indexOf(
        'await IosPostLoginBackupExcluder(isIos: true).apply(toxId);',
      );
      expect(identityGuard, greaterThanOrEqualTo(0));
      expect(identityGuard, lessThan(exclusionCall));
      expect(
        source,
        isNot(contains('final toxId = service.accountKey;')),
        reason:
            'FlutterUIKitClient must never be used as the profile path identity',
      );
    },
  );
}
