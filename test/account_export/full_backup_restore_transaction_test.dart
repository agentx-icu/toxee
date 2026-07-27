import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/account_export/restore_transaction.dart';
import 'package:toxee/util/account_export_service.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/prefs/draft_prefs.dart';

import 'test_support.dart';

const _toxId =
    'ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD';
const _otherToxId =
    '1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF';
const _nickname = 'Journaled Zip';

void main() {
  group('journaled full-backup restore transaction', () {
    late AccountExportTestEnv env;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
      FullBackupRestoreTestHooks.reset();
      FullBackupRestoreTestHooks.profileIdentityExtractor =
          (Uint8List profileBytes) => _toxId;
    });

    tearDown(() async {
      FullBackupRestoreTestHooks.reset();
      await env.dispose();
    });

    test(
      'rejects invalid metadata toxId before journal or restore writes',
      () async {
        final zipPath = await _writeBackup(
          env,
          toxId: _toxId,
          metadataToxId: 'not-a-tox-id',
        );

        await expectLater(
          () => AccountExportService.importFullBackup(filePath: zipPath),
          throwsA(isA<FormatException>()),
        );

        await _expectNoRestoreWrites();
      },
    );

    test(
      'rejects profile identity mismatch before journal or restore writes',
      () async {
        FullBackupRestoreTestHooks.profileIdentityExtractor =
            (Uint8List profileBytes) => _otherToxId;
        final zipPath = await _writeBackup(
          env,
          toxId: _toxId,
          profileIdentity: _otherToxId,
        );

        await expectLater(
          () => AccountExportService.importFullBackup(filePath: zipPath),
          throwsA(isA<StateError>()),
        );

        await _expectNoRestoreWrites();
      },
    );

    test(
      'keeps imported data hidden from account_list until caller finalizes',
      () async {
        final zipPath = await _writeBackup(env, toxId: _toxId);

        final result = await AccountExportService.importFullBackup(
          filePath: zipPath,
        );

        expect(result['toxId'], _toxId);
        expect(result['nickname'], _nickname);
        expect(await Prefs.getAccountByToxId(_toxId), isNull);
        expect(await _profileExists(_toxId), isTrue);
        expect(await _historyText(_toxId), contains('journal-history'));
        expect(
          (await Prefs.exportScopedPrefsForAccount(_toxId))['pinned_peers'],
          <String>['peer-a'],
        );
        expect(await RestoreTransactionJournalStore.read(), isNotNull);

        await Prefs.addAccount(
          toxId: _toxId,
          nickname: _nickname,
          autoLogin: false,
        );
        await AccountExportService.finalizeFullBackupImport(toxId: _toxId);

        expect(await Prefs.getAccountByToxId(_toxId), isNotNull);
        expect(await RestoreTransactionJournalStore.read(), isNull);
        expect(await _profileExists(_toxId), isTrue);
        expect(await _historyText(_toxId), contains('journal-history'));
      },
    );

    test(
      'restores portable draft section under the imported full ID',
      () async {
        const conversation = 'c2c:peer:with:colons';
        const fullToxId = '${_toxId}1234567800AB';
        final zipPath = await _writeBackup(
          env,
          toxId: fullToxId,
          scopedPrefs: <String, dynamic>{
            DraftPrefs.portableBackupSectionKey: <String, dynamic>{
              conversation: jsonEncode(<String, Object>{
                'text': 'journal draft text',
                'updatedAt': 1700000000,
              }),
            },
          },
        );

        await AccountExportService.importFullBackup(filePath: zipPath);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('draft_v2:$fullToxId:$conversation'), isNotNull);
        expect(prefs.getString('draft_v2:$_otherToxId:$conversation'), isNull);
        final restored = await DraftPrefs(
          prefs,
          activeAccountToxId: () async => fullToxId,
        ).loadDraft(accountToxId: fullToxId, conversationID: conversation);
        expect(restored?.text, 'journal draft text');
        expect(restored?.updatedAt, 1700000000);
      },
    );

    test(
      'recovery rolls back restored draft without deleting same-prefix v2 draft',
      () async {
        const conversation = 'c2c:peer:with:colons';
        const fullToxId = '${_toxId}1234567800AB';
        final samePrefixToxId =
            '${_toxId.substring(0, 16)}${List<String>.filled(60, 'B').join()}';
        final samePrefixConversation =
            'c2c:other:${fullToxId.substring(0, 16)}';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'draft_v2:$samePrefixToxId:$samePrefixConversation',
          jsonEncode(<String, Object>{'text': 'keep sibling', 'updatedAt': 2}),
        );
        final zipPath = await _writeBackup(
          env,
          toxId: fullToxId,
          scopedPrefs: <String, dynamic>{
            DraftPrefs.portableBackupSectionKey: <String, dynamic>{
              conversation: jsonEncode(<String, Object>{
                'text': 'rollback draft text',
                'updatedAt': 1700000001,
              }),
            },
          },
        );
        FullBackupRestoreTestHooks.crashAt =
            FullBackupRestoreFailurePoint.afterScopedPrefsApply;

        await expectLater(
          () => AccountExportService.importFullBackup(filePath: zipPath),
          throwsA(isA<FullBackupRestoreCrashSimulation>()),
        );

        FullBackupRestoreTestHooks.reset();
        await AccountExportService.recoverPendingFullBackupRestore();

        expect(prefs.getString('draft_v2:$fullToxId:$conversation'), isNull);
        expect(
          prefs.getString('draft_v2:$samePrefixToxId:$samePrefixConversation'),
          isNotNull,
        );
      },
    );

    test(
      'refuses to overwrite an existing destination profile directory',
      () async {
        final zipPath = await _writeBackup(env, toxId: _toxId);
        final profileDir = await AppPaths.getProfileDirectoryForToxId(_toxId);
        await Directory(profileDir).create(recursive: true);
        final existingProfile = File(
          AppPaths.profileFileInDirectory(profileDir),
        );
        await existingProfile.writeAsString('pre-existing-profile');

        await expectLater(
          () => AccountExportService.importFullBackup(filePath: zipPath),
          throwsA(isA<StateError>()),
        );

        expect(await existingProfile.readAsString(), 'pre-existing-profile');
        expect(await (await _historyFile(_toxId)).exists(), isFalse);
        expect(await RestoreTransactionJournalStore.read(), isNull);
      },
    );

    for (final scenario
        in <
          ({FullBackupRestoreFailurePoint point, RestoreTransactionState state})
        >[
          (
            point: FullBackupRestoreFailurePoint.afterStaging,
            state: RestoreTransactionState.staged,
          ),
          (
            point: FullBackupRestoreFailurePoint.afterProfileCommit,
            state: RestoreTransactionState.profileCommitted,
          ),
          (
            point: FullBackupRestoreFailurePoint.afterAccountDataCommit,
            state: RestoreTransactionState.accountDataCommitted,
          ),
          (
            point: FullBackupRestoreFailurePoint.afterScopedPrefsApply,
            state: RestoreTransactionState.scopedPrefsApplied,
          ),
        ]) {
      test('cold-start recovery rolls back ${scenario.state.name}', () async {
        final zipPath = await _writeBackup(env, toxId: _toxId);
        FullBackupRestoreTestHooks.crashAt = scenario.point;

        await expectLater(
          () => AccountExportService.importFullBackup(filePath: zipPath),
          throwsA(isA<FullBackupRestoreCrashSimulation>()),
        );

        final journal = await RestoreTransactionJournalStore.read();
        expect(journal, isNotNull);
        expect(journal!.state, scenario.state);

        FullBackupRestoreTestHooks.reset();
        await AccountExportService.recoverPendingFullBackupRestore();

        expect(await Prefs.getAccountByToxId(_toxId), isNull);
        expect(await _profileExists(_toxId), isFalse);
        expect(
          await Directory(await AppPaths.getAccountDataRoot(_toxId)).exists(),
          isFalse,
        );
        expect(await Prefs.exportScopedPrefsForAccount(_toxId), isEmpty);
        expect(await RestoreTransactionJournalStore.read(), isNull);
      });
    }

    test(
      'cold-start recovery preserves visible account when finalize was skipped',
      () async {
        final zipPath = await _writeBackup(env, toxId: _toxId);
        await AccountExportService.importFullBackup(filePath: zipPath);
        expect(
          (await RestoreTransactionJournalStore.read())!.state,
          RestoreTransactionState.scopedPrefsApplied,
        );

        await Prefs.addAccount(
          toxId: _toxId,
          nickname: _nickname,
          autoLogin: false,
        );

        await AccountExportService.recoverPendingFullBackupRestore();

        expect(await Prefs.getAccountByToxId(_toxId), isNotNull);
        expect(await _profileExists(_toxId), isTrue);
        expect(await _historyText(_toxId), contains('journal-history'));
        expect(
          (await Prefs.exportScopedPrefsForAccount(_toxId))['pinned_peers'],
          <String>['peer-a'],
        );
        expect(await RestoreTransactionJournalStore.read(), isNull);
      },
    );

    test(
      'cold-start recovery finalizes visible account with uncleared journal',
      () async {
        final zipPath = await _writeBackup(env, toxId: _toxId);
        await AccountExportService.importFullBackup(filePath: zipPath);
        await Prefs.addAccount(
          toxId: _toxId,
          nickname: _nickname,
          autoLogin: false,
        );

        FullBackupRestoreTestHooks.crashAt =
            FullBackupRestoreFailurePoint.afterAccountRegistryVisible;
        await expectLater(
          () => AccountExportService.finalizeFullBackupImport(toxId: _toxId),
          throwsA(isA<FullBackupRestoreCrashSimulation>()),
        );
        expect(
          (await RestoreTransactionJournalStore.read())!.state,
          RestoreTransactionState.accountRegistryVisible,
        );

        FullBackupRestoreTestHooks.reset();
        await AccountExportService.recoverPendingFullBackupRestore();

        expect(await Prefs.getAccountByToxId(_toxId), isNotNull);
        expect(await _profileExists(_toxId), isTrue);
        expect(await _historyText(_toxId), contains('journal-history'));
        expect(await RestoreTransactionJournalStore.read(), isNull);
      },
    );
  });
}

Future<String> _writeBackup(
  AccountExportTestEnv env, {
  required String toxId,
  String? metadataToxId,
  String? profileIdentity,
  Map<String, dynamic>? scopedPrefs,
}) async {
  final archive = Archive();
  final metadata = <String, dynamic>{
    'formatVersion': 1,
    'toxId': metadataToxId ?? toxId,
    'nickname': _nickname,
    'statusMessage': '',
    'exportDate': DateTime.now().toIso8601String(),
    'scopedPrefs':
        scopedPrefs ??
        <String, dynamic>{
          'pinned_peers': <String>['peer-a'],
        },
  };
  final metadataBytes = utf8.encode(
    const JsonEncoder.withIndent('  ').convert(metadata),
  );
  archive.addFile(
    ArchiveFile(
      'metadata.json',
      metadataBytes.length,
      Uint8List.fromList(metadataBytes),
    ),
  );
  final profileBytes = utf8.encode('profile-${profileIdentity ?? toxId}');
  archive.addFile(
    ArchiveFile(
      'tox_profile.tox',
      profileBytes.length,
      Uint8List.fromList(profileBytes),
    ),
  );
  final historyBytes = utf8.encode('{"message":"journal-history"}');
  archive.addFile(
    ArchiveFile(
      'chat_history/conversation.json',
      historyBytes.length,
      Uint8List.fromList(historyBytes),
    ),
  );
  final queueBytes = utf8.encode('{"queued":"journal-queue"}');
  archive.addFile(
    ArchiveFile(
      'offline_message_queue.json',
      queueBytes.length,
      Uint8List.fromList(queueBytes),
    ),
  );
  final zipPath = p.join(env.extras, '${toxId.substring(0, 8)}.zip');
  final zipBytes = ZipEncoder().encode(archive);
  await File(zipPath).writeAsBytes(zipBytes, flush: true);
  return zipPath;
}

Future<void> _expectNoRestoreWrites() async {
  expect(await RestoreTransactionJournalStore.read(), isNull);
  final profileRoot = Directory(await AppPaths.getProfileStorageRoot());
  if (await profileRoot.exists()) {
    final entries = await profileRoot.list().toList();
    expect(entries, isEmpty);
  }
  final accountDataRoot = Directory(
    p.join(await AppPaths.applicationSupportPath, 'account_data'),
  );
  expect(await accountDataRoot.exists(), isFalse);
}

Future<bool> _profileExists(String toxId) async {
  final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
  return File(AppPaths.profileFileInDirectory(profileDir)).exists();
}

Future<File> _historyFile(String toxId) async {
  final historyDir = await AppPaths.getAccountChatHistoryPath(toxId);
  return File(p.join(historyDir, 'conversation.json'));
}

Future<String> _historyText(String toxId) async {
  return (await _historyFile(toxId)).readAsString();
}
