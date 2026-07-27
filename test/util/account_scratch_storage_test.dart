import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/bootstrap/app_bootstrap.dart';
import 'package:toxee/util/account_deletion.dart';
import 'package:toxee/util/account_scratch_storage.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';

const _accountA =
    '0123456789ABCDEF111111111111111111111111111111111111111111111111111111111111';
const _accountB =
    '0123456789ABCDEF222222222222222222222222222222222222222222222222222222222222';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testRoot;
  late Directory applicationSupport;

  setUp(() async {
    testRoot = await Directory.systemTemp.createTemp('toxee_scratch_test_');
    applicationSupport = Directory(p.join(testRoot.path, 'app_support'));
    await applicationSupport.create(recursive: true);
    AppPaths.debugApplicationSupportOverride = applicationSupport.path;
    AccountDeletionTestHooks.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.initialize(await SharedPreferences.getInstance());
  });

  tearDown(() async {
    AccountDeletionTestHooks.reset();
    AppPaths.debugApplicationSupportOverride = null;
    if (await testRoot.exists()) {
      await testRoot.delete(recursive: true);
    }
  });

  Future<AccountScratchStorage> storageFor(String toxId) async {
    return AccountScratchStorage(
      accountToxId: toxId,
      accountDataRoot: await AppPaths.getAccountScratchDataRoot(toxId),
    );
  }

  test(
    'scratch resolver uses the full account ID for same-prefix accounts',
    () async {
      final firstRoot = await AppPaths.getAccountScratchDataRoot(_accountA);
      final secondRoot = await AppPaths.getAccountScratchDataRoot(_accountB);

      expect(
        firstRoot,
        p.join(applicationSupport.path, 'account_data', _accountA),
      );
      expect(
        secondRoot,
        p.join(applicationSupport.path, 'account_data', _accountB),
      );
      expect(firstRoot, isNot(secondRoot));
      expect(
        await AppPaths.getAccountScratchRoot(_accountA),
        p.join(firstRoot, 'scratch'),
      );
    },
  );

  test('invalid account IDs are rejected before path creation', () async {
    expect(
      () => AccountScratchStorage(
        accountToxId: _accountA.substring(0, 64),
        accountDataRoot: testRoot.path,
      ),
      throwsArgumentError,
    );
    await expectLater(
      AppPaths.getAccountScratchDataRoot('../$_accountA'),
      throwsArgumentError,
    );
  });

  test(
    'writes and copies publish complete isolated files without temp leftovers',
    () async {
      final first = await storageFor(_accountA);
      final second = await storageFor(_accountB);
      final firstBytes = Uint8List.fromList(List<int>.filled(4096, 0x11));
      final secondBytes = Uint8List.fromList(List<int>.filled(8192, 0x22));

      final written = await Future.wait(<Future<String>>[
        first.writeBytesToScratch(
          firstBytes,
          category: 'clipboard_images',
          suggestedFileName: 'same.png',
        ),
        second.writeBytesToScratch(
          secondBytes,
          category: 'clipboard_images',
          suggestedFileName: 'same.png',
        ),
      ]);
      expect(written.first, contains(_accountA));
      expect(written.last, contains(_accountB));
      expect(await File(written.first).readAsBytes(), firstBytes);
      expect(await File(written.last).readAsBytes(), secondBytes);

      final source = File(p.join(testRoot.path, 'picked.jpg'));
      await source.writeAsBytes(<int>[9, 8, 7, 6]);
      final copied = await first.copyFileToScratch(
        source.path,
        category: 'image_paste',
        suggestedFileName: 'picked.jpg',
      );
      expect(await File(copied).readAsBytes(), <int>[9, 8, 7, 6]);

      final entries = await Directory(
        first.scratchRoot,
      ).list(recursive: true, followLinks: false).toList();
      expect(
        entries.where((entry) => p.basename(entry.path).contains('.tmp.')),
        isEmpty,
      );
    },
  );

  test(
    'invalid categories, basenames, and failed copies do not publish files',
    () async {
      final storage = await storageFor(_accountA);
      await expectLater(
        storage.writeBytesToScratch(
          Uint8List(0),
          category: '../bad',
          suggestedFileName: 'safe.png',
        ),
        throwsArgumentError,
      );
      await expectLater(
        storage.writeBytesToScratch(
          Uint8List(0),
          category: 'clipboard_images',
          suggestedFileName: '../escape.png',
        ),
        throwsArgumentError,
      );

      final sourceDirectory = Directory(p.join(testRoot.path, 'not_a_file'));
      await sourceDirectory.create();
      await expectLater(
        storage.copyFileToScratch(
          sourceDirectory.path,
          category: 'clipboard_images',
          suggestedFileName: 'copy.png',
        ),
        throwsArgumentError,
      );
      expect(await Directory(storage.scratchRoot).exists(), isFalse);
    },
  );

  test('delete accepts only canonical owned non-symlink files', () async {
    final storage = await storageFor(_accountA);
    final owned = await storage.writeBytesToScratch(
      Uint8List.fromList(<int>[1]),
      category: 'clipboard_images',
      suggestedFileName: 'owned.png',
    );
    await storage.deleteScratchFile(owned);
    expect(await File(owned).exists(), isFalse);

    final external = File(p.join(testRoot.path, 'account-export.zip'));
    await external.writeAsString('keep');
    await expectLater(
      storage.deleteScratchFile(external.path),
      throwsArgumentError,
    );

    final link = Link(p.join(storage.scratchRoot, 'linked-export.zip'));
    await link.create(external.path);
    await expectLater(
      storage.deleteScratchFile(link.path),
      throwsArgumentError,
    );
    expect(await external.readAsString(), 'keep');
  });

  test(
    'symlink scratch roots are rejected before writing outside the account',
    () async {
      final storage = await storageFor(_accountA);
      final external = Directory(p.join(testRoot.path, 'external_scratch'));
      await external.create(recursive: true);
      await Directory(storage.accountDataRoot).create(recursive: true);
      await Link(storage.scratchRoot).create(external.path);

      await expectLater(
        storage.writeBytesToScratch(
          Uint8List.fromList(<int>[1]),
          category: 'clipboard_images',
          suggestedFileName: 'escape.png',
        ),
        throwsA(isA<StateError>()),
      );
      expect(await external.list().toList(), isEmpty);
    },
  );

  test(
    'TTL cleanup touches only known scratch and exact legacy roots',
    () async {
      final now = DateTime(2026, 7, 26, 12);
      final cutoff = now.subtract(const Duration(days: 7));
      final storage = await storageFor(_accountA);
      final expired = File(
        p.join(storage.scratchRoot, 'avatars', 'expired.png'),
      );
      final boundary = File(
        p.join(storage.scratchRoot, 'avatars', 'boundary.png'),
      );
      final fresh = File(p.join(storage.scratchRoot, 'avatars', 'fresh.png'));
      await expired.parent.create(recursive: true);
      await expired.writeAsString('old');
      await boundary.writeAsString('boundary');
      await fresh.writeAsString('fresh');
      await expired.setLastModified(
        cutoff.subtract(const Duration(seconds: 1)),
      );
      await boundary.setLastModified(cutoff);
      await fresh.setLastModified(cutoff.add(const Duration(seconds: 1)));

      final linkedExternal = File(p.join(testRoot.path, 'linked-export.tox'));
      await linkedExternal.writeAsString('keep');
      await Link(
        p.join(storage.scratchRoot, 'avatars', 'linked.tox'),
      ).create(linkedExternal.path);

      final fakeSystemTemp = Directory(p.join(testRoot.path, 'system_temp'));
      final avatarLegacy = File(
        p.join(fakeSystemTemp.path, 'toxee_avatar_cache', 'old-avatar.png'),
      );
      final genericTemp = File(
        p.join(fakeSystemTemp.path, 'another_app', 'keep.tmp'),
      );
      await avatarLegacy.parent.create(recursive: true);
      await genericTemp.parent.create(recursive: true);
      await avatarLegacy.writeAsString('old');
      await genericTemp.writeAsString('keep');
      await avatarLegacy.setLastModified(
        cutoff.subtract(const Duration(days: 1)),
      );
      await genericTemp.setLastModified(
        cutoff.subtract(const Duration(days: 1)),
      );

      final downloads = Directory(p.join(testRoot.path, 'Downloads'));
      final pasteLegacy = File(
        p.join(downloads.path, 'toxee_image_paste', 'old-paste.png'),
      );
      await pasteLegacy.parent.create(recursive: true);
      await pasteLegacy.writeAsString('old');
      await pasteLegacy.setLastModified(
        cutoff.subtract(const Duration(days: 1)),
      );

      final sentinels = <File>[
        File(p.join(downloads.path, 'account-export.zip')),
        File(p.join(downloads.path, 'profile.tox')),
        File(p.join(downloads.path, 'screenshot.png')),
        File(p.join(downloads.path, 'Photos', 'photo.jpg')),
        File(p.join(downloads.path, 'MediaStore', 'media.jpg')),
        File(p.join(testRoot.path, 'external-export.zip')),
      ];
      for (final sentinel in sentinels) {
        await sentinel.parent.create(recursive: true);
        await sentinel.writeAsString('keep');
        await sentinel.setLastModified(
          cutoff.subtract(const Duration(days: 1)),
        );
      }

      await AccountScratchStorage.cleanupExpired(
        applicationSupportRoot: applicationSupport.path,
        configuredDownloadsRoot: downloads.path,
        systemTempRoot: fakeSystemTemp.path,
        now: now,
      );

      expect(await expired.exists(), isFalse);
      expect(await boundary.exists(), isTrue);
      expect(await fresh.exists(), isTrue);
      expect(await avatarLegacy.exists(), isFalse);
      expect(await pasteLegacy.exists(), isFalse);
      expect(await genericTemp.exists(), isTrue);
      expect(await linkedExternal.exists(), isTrue);
      for (final sentinel in sentinels) {
        expect(await sentinel.exists(), isTrue, reason: sentinel.path);
      }
      expect(await downloads.exists(), isTrue);
    },
  );

  test('cold-start cleanup failures are nonfatal', () async {
    var called = false;
    await AppBootstrap.cleanupScratchAtColdStart(
      cleanup: () async {
        called = true;
        throw const FileSystemException('injected cleanup failure');
      },
    );
    expect(called, isTrue);
  });

  test('account deletion removes this full-ID scratch root only', () async {
    final first = await storageFor(_accountA);
    final second = await storageFor(_accountB);
    await first.writeBytesToScratch(
      Uint8List.fromList(<int>[1]),
      category: 'avatars',
      suggestedFileName: 'first.png',
    );
    final secondFile = await second.writeBytesToScratch(
      Uint8List.fromList(<int>[2]),
      category: 'avatars',
      suggestedFileName: 'second.png',
    );
    final export = File(p.join(testRoot.path, 'saved-account.zip'));
    await export.writeAsString('keep');

    AccountDeletionTestHooks.removePassword = (_) async => true;
    AccountDeletionTestHooks.clearPrefsData = (_) async {};
    AccountDeletionTestHooks.cleanupPrivacyResidue = (_) async {};
    AccountDeletionTestHooks.removeAccount = (_) async {};
    final result = await AccountDeletionCoordinator.deleteAccount(
      toxId: _accountA,
    );

    expect(result.completed, isTrue);
    expect(await Directory(first.accountDataRoot).exists(), isFalse);
    expect(await File(secondFile).exists(), isTrue);
    expect(await export.exists(), isTrue);
  });
}
