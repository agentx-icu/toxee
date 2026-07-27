import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/bootstrap/app_bootstrap.dart';
import 'package:toxee/util/account_deletion.dart';
import 'package:toxee/util/account_scratch_storage.dart';
import 'package:toxee/util/account_service.dart';
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
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.initialize(await SharedPreferences.getInstance());
    AccountDeletionTestHooks.removePassword = (_) async => true;
  });

  tearDown(() async {
    AccountDeletionTestHooks.reset();
    AppPaths.debugApplicationSupportOverride = null;
    if (await testRoot.exists()) {
      await testRoot.delete(recursive: true);
    }
  });

  AccountScratchStorage storageFor(String toxId) {
    return AccountScratchStorage(
      accountToxId: toxId,
      accountDataRoot: p.join(applicationSupport.path, 'account_data', toxId),
    );
  }

  test(
    'full account IDs with the same prefix have isolated scratch roots',
    () async {
      expect(
        await AppPaths.getAccountScratchDataRoot(_accountA),
        p.join(applicationSupport.path, 'account_data', _accountA),
      );
      expect(
        await AppPaths.getAccountScratchDataRoot(_accountB),
        p.join(applicationSupport.path, 'account_data', _accountB),
      );
      final first = storageFor(_accountA);
      final second = storageFor(_accountB);

      final firstPath = await first.writeBytesToScratch(
        Uint8List.fromList(<int>[1, 2, 3]),
        category: 'message_images',
        suggestedFileName: 'preview.png',
      );
      final secondPath = await second.writeBytesToScratch(
        Uint8List.fromList(<int>[4, 5, 6]),
        category: 'message_images',
        suggestedFileName: 'preview.png',
      );

      expect(firstPath, contains(_accountA));
      expect(secondPath, contains(_accountB));
      expect(firstPath, isNot(secondPath));
      expect(await File(firstPath).readAsBytes(), <int>[1, 2, 3]);
      expect(await File(secondPath).readAsBytes(), <int>[4, 5, 6]);
    },
  );

  test(
    'writes and copies publish complete files without temporary leftovers',
    () async {
      final storage = storageFor(_accountA);
      final firstBytes = Uint8List.fromList(List<int>.filled(4096, 0x11));
      final secondBytes = Uint8List.fromList(List<int>.filled(8192, 0x22));

      final writes = await Future.wait(<Future<String>>[
        storage.writeBytesToScratch(
          firstBytes,
          category: 'avatars',
          suggestedFileName: 'same.bin',
        ),
        storage.writeBytesToScratch(
          secondBytes,
          category: 'avatars',
          suggestedFileName: 'same.bin',
        ),
      ]);
      expect(writes[0], isNot(writes[1]));
      expect(await File(writes.first).readAsBytes(), firstBytes);
      expect(await File(writes.last).readAsBytes(), secondBytes);

      final source = File(p.join(testRoot.path, 'user-selected.jpg'));
      await source.writeAsBytes(<int>[9, 8, 7, 6]);
      final copiedPath = await storage.copyFileToScratch(
        source.path,
        category: 'image_paste',
        suggestedFileName: p.basename(source.path),
      );
      expect(await File(copiedPath).readAsBytes(), <int>[9, 8, 7, 6]);

      final scratchEntries = await Directory(
        storage.scratchRoot,
      ).list(recursive: true, followLinks: false).toList();
      expect(
        scratchEntries.where(
          (entry) => p.basename(entry.path).contains('.tmp.'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'rejects unsafe target names and denies traversal and symlink escapes',
    () async {
      final storage = storageFor(_accountA);
      await expectLater(
        storage.writeBytesToScratch(
          Uint8List.fromList(<int>[1]),
          category: '../../image paste',
          suggestedFileName: '../picked image.png',
        ),
        throwsArgumentError,
      );
      await storage.writeBytesToScratch(
        Uint8List.fromList(<int>[1]),
        category: 'image_paste',
        suggestedFileName: 'picked-image.png',
      );

      final external = File(p.join(testRoot.path, 'export.zip'));
      await external.writeAsString('user export');
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
      expect(await external.readAsString(), 'user export');
    },
  );

  test(
    'TTL cleanup visits only known scratch and exact legacy roots',
    () async {
      final now = DateTime(2026, 7, 26, 12);
      final cutoff = now.subtract(const Duration(days: 7));
      final storage = storageFor(_accountA);
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
      for (final sentinel in sentinels) {
        expect(await sentinel.exists(), isTrue, reason: sentinel.path);
      }
      expect(await downloads.exists(), isTrue);
    },
  );

  test(
    'cold-start cleanup failures degrade without escaping bootstrap',
    () async {
      var called = false;
      await AppBootstrap.cleanupScratchAtColdStart(
        cleanup: () async {
          called = true;
          throw const FileSystemException('injected cleanup failure');
        },
      );
      expect(called, isTrue);
    },
  );

  test('account deletion removes only that full-ID scratch root', () async {
    final first = storageFor(_accountA);
    final second = storageFor(_accountB);
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

    await AccountService.deleteAccountWithoutService(toxId: _accountA);

    expect(await Directory(first.accountDataRoot).exists(), isFalse);
    expect(await File(secondFile).exists(), isTrue);
    expect(await export.exists(), isTrue);
  });
}
