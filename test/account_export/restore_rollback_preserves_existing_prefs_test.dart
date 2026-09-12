import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:toxee/util/account_export/restore_transaction.dart';
import 'package:toxee/util/account_export_service.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';

import 'test_support.dart';

// What this file pins, in one paragraph, because the bug it guards is invisible
// from the restore code alone.
//
// Two preference families are keyed by the FULL Tox ID:
// `black_list_<toxId>` and `tencent_cloud_chat_failed_messages_<toxId>`.
// The generic account sweep (`Prefs.clearScopedKeysForAccount`) matches the
// `_<first16>` suffix, so it cannot see either of them, and the restore
// rollback therefore had to clear them BY NAME — which it did unconditionally.
// But both families can be on disk with no registry row and no account
// directories (a user who blocked someone, or had a message fail, then had the
// account row go away), and that shape sails straight through `_preflight`.
// So a full-backup restore that aborted mid-flight deleted a block list and a
// queue of pending messages it had never created. Worse, by the time the
// rollback runs the restore may ALREADY have overwritten both families with the
// archive's own values, so "don't delete" is not enough on its own — the
// pre-existing values have to be captured before the first write and put back.
//
// Hence the three shapes below: pre-existing content survives byte-for-byte
// (whether the abort lands before or after the overwrite), nothing pre-existing
// still means nothing left behind, and a journal from an older build — which
// cannot say what was there first — is never allowed to authorize a delete.
//
// These tests deliberately assert on OBSERVABLE prefs state rather than on the
// journal's bookkeeping fields, so that the next refactor of how ownership is
// recorded cannot quietly retire the guarantee.

// A Tox ID whose first 16 chars differ from its last 16. That is load-bearing:
// the whole bug class exists because `black_list_<fullToxId>` ends with the
// LAST 16 chars, so the `_<first16>` suffix sweep misses it. A self-repeating
// test ID would accidentally be swept and the tests would pass for the wrong
// reason.
const _toxId =
    'AA11BB22CC33DD44EE55FF6677889900112233445566778899AABBCCDDEEFF01';
const _nickname = 'Rollback Prefs';

// What was on disk BEFORE any restore started: the user's real block list and
// real pending-message queue. Losing these is the regression.
const _priorBlockedPeers = <String>{'prior-peer-one', 'prior-peer-two'};
const _priorFailedQueue = '{"pending":"prior-queue-payload"}';

// What the archive carries. Different from the prior values on purpose, so a
// test cannot pass just because the restore happened to write back something
// that looks the same.
const _archiveBlockedPeers = <String>['archive-peer'];
const _archiveFailedQueue = '{"pending":"archive-queue-payload"}';

void main() {
  group('full-backup rollback and the full-id-keyed preference families', () {
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

    // (a), abort BEFORE the restore touches either family.
    //
    // Prevents: a user with a block list and pending messages but no account row
    // tries to import a backup, the import dies while unpacking the zip, and the
    // rollback's unconditional clear-by-name wipes both — data the restore never
    // wrote and had no claim to. This is the shape the original bug report hit.
    test(
      'staging failure leaves a pre-existing block list and queue untouched',
      () async {
        await _seedPriorFullIdPrefs();
        final zipPath = await _writeBackup(env);
        FullBackupRestoreTestHooks.crashAt =
            FullBackupRestoreFailurePoint.afterStaging;

        await expectLater(
          () => AccountExportService.importFullBackup(filePath: zipPath),
          throwsA(isA<FullBackupRestoreCrashSimulation>()),
        );

        FullBackupRestoreTestHooks.reset();
        await AccountExportService.recoverPendingFullBackupRestore();

        expect(await Prefs.getBlackList(_toxId), _priorBlockedPeers);
        expect(await Prefs.exportFailedMessageQueue(_toxId), _priorFailedQueue);
      },
    );

    // (a), abort AFTER the restore has overwritten both families.
    //
    // Prevents: the half of the bug that "just don't delete on rollback" does
    // not fix. `restoreBlockedPeers` / `restoreFailedMessageQueue` run inside
    // the journalled window, so by the time the transaction fails the user's
    // own block list has already been replaced by the ARCHIVE's. A rollback
    // that merely declines to clear leaves the importing archive's blocked
    // peers and pending messages standing in for the user's — silent
    // corruption that looks like a successful no-op. The rollback has to put
    // the captured originals back.
    test(
      'post-apply failure restores the original block list and queue values',
      () async {
        await _seedPriorFullIdPrefs();
        final zipPath = await _writeBackup(env);
        FullBackupRestoreTestHooks.crashAt =
            FullBackupRestoreFailurePoint.afterScopedPrefsApply;

        await expectLater(
          () => AccountExportService.importFullBackup(filePath: zipPath),
          throwsA(isA<FullBackupRestoreCrashSimulation>()),
        );

        // Sanity: the restore really did clobber them, so the assertion below
        // is testing recovery rather than an accident of ordering. If this ever
        // fails, the archive sections stopped being applied and the interesting
        // half of this test has silently stopped running.
        expect(await Prefs.getBlackList(_toxId), _archiveBlockedPeers.toSet());
        expect(
          await Prefs.exportFailedMessageQueue(_toxId),
          _archiveFailedQueue,
        );

        FullBackupRestoreTestHooks.reset();
        await AccountExportService.recoverPendingFullBackupRestore();

        expect(await Prefs.getBlackList(_toxId), _priorBlockedPeers);
        expect(await Prefs.exportFailedMessageQueue(_toxId), _priorFailedQueue);
      },
    );

    // (b) — the invariant the fix must NOT trade away.
    //
    // Prevents: over-correcting. When the restore itself created these two
    // families, a rolled-back restore must leave nothing behind, or the next
    // person to import that account inherits a stranger's blocked peers and
    // retries a stranger's unsent messages. "Preserve what was there" has to
    // mean exactly that — and an account with nothing there gets nothing back.
    test(
      'rollback still clears both families when nothing pre-existed',
      () async {
        expect(await Prefs.getBlackList(_toxId), isEmpty);
        expect(await Prefs.exportFailedMessageQueue(_toxId), isNull);

        final zipPath = await _writeBackup(env);
        FullBackupRestoreTestHooks.crashAt =
            FullBackupRestoreFailurePoint.afterScopedPrefsApply;

        await expectLater(
          () => AccountExportService.importFullBackup(filePath: zipPath),
          throwsA(isA<FullBackupRestoreCrashSimulation>()),
        );

        FullBackupRestoreTestHooks.reset();
        await AccountExportService.recoverPendingFullBackupRestore();

        expect(await Prefs.getBlackList(_toxId), isEmpty);
        expect(await Prefs.exportFailedMessageQueue(_toxId), isNull);
        expect(await RestoreTransactionJournalStore.read(), isNull);
      },
    );

    // (c) — a journal written by a build that predates the capture.
    //
    // Prevents: the upgrade hole. A transaction can be staged on the old build
    // and recovered on the new one, and that journal carries no record of what
    // the two families looked like before it started. Unknown ownership must
    // never authorize a delete: the old default ("this transaction owns them,
    // clear them") is precisely the behaviour that caused the data loss, so on
    // an unrecognised journal the rollback leaves both families exactly as it
    // found them. Stranding a block list is recoverable by the user; deleting
    // one is not.
    test(
      'legacy journal without ownership fields never deletes either family',
      () async {
        await _seedPriorFullIdPrefs();
        await _writeJournal(_legacyJournalJson());

        await AccountExportService.recoverPendingFullBackupRestore();

        expect(await Prefs.getBlackList(_toxId), _priorBlockedPeers);
        expect(await Prefs.exportFailedMessageQueue(_toxId), _priorFailedQueue);
        // The rollback must still have run to completion — "leave the prefs
        // alone" is not a licence to leave the journal behind and re-roll-back
        // on every launch.
        expect(await RestoreTransactionJournalStore.read(), isNull);
      },
    );

    // (c) control — the same hand-written journal, but WITH an empty capture.
    //
    // Prevents: (c) passing for the wrong reason. If recovery-from-a-handmade
    // journal ever stopped reaching the full-id branch at all — a changed file
    // name, a journal rejected as malformed, an early return on a missing
    // directory — (c) would still be green while guarding nothing. This is the
    // same setup with the capture present and empty, so it must CLEAR both
    // families. One of these two tests going red is the signal; both green
    // means the "untouched" in (c) is caused by the absent keys.
    test(
      'hand-written journal with an empty capture does clear both families',
      () async {
        await _seedPriorFullIdPrefs();
        await _writeJournal(
          _legacyJournalJson()..addAll(<String, dynamic>{
            'priorBlackListCaptured': true,
            'priorFailedQueueCaptured': true,
            'priorBlackList': <String>[],
          }),
        );

        await AccountExportService.recoverPendingFullBackupRestore();

        expect(await Prefs.getBlackList(_toxId), isEmpty);
        expect(await Prefs.exportFailedMessageQueue(_toxId), isNull);
        expect(await RestoreTransactionJournalStore.read(), isNull);
      },
    );

    // (d) — the journal's own serialization.
    //
    // Prevents: a capture that survives in memory but not across the crash it
    // exists for. The whole point of the snapshot is to be readable by the NEXT
    // process, so every field has to make the round trip through the journal
    // file, including the awkward shapes: an empty captured block list and a
    // null captured queue are meaningful values ("there was nothing here"), not
    // absences, and must not collapse into "nothing was captured".
    test('journal round-trips the captured prior values through JSON', () async {
      final captured = _legacyJournalJson()
        ..addAll(<String, dynamic>{
          'priorBlackListCaptured': true,
          'priorFailedQueueCaptured': true,
          'priorBlackList': <String>['kept-peer-a', 'kept-peer-b'],
          'priorFailedQueue': _priorFailedQueue,
        });

      final reread = RestoreTransactionJournal.fromJson(
        jsonDecode(
              jsonEncode(RestoreTransactionJournal.fromJson(captured).toJson()),
            )
            as Map<String, dynamic>,
      ).toJson();

      expect(reread['priorBlackListCaptured'], isTrue);
      expect(reread['priorFailedQueueCaptured'], isTrue);
      expect(reread['priorBlackList'], <String>['kept-peer-a', 'kept-peer-b']);
      expect(reread['priorFailedQueue'], _priorFailedQueue);

      // "Captured, and there was nothing there" — the shape that makes case (b)
      // work. It must stay distinguishable from "not captured" (case (c)) after
      // a trip through the file.
      final capturedEmpty = _legacyJournalJson()
        ..addAll(<String, dynamic>{
          'priorBlackListCaptured': true,
          'priorFailedQueueCaptured': true,
          'priorBlackList': <String>[],
          'priorFailedQueue': null,
        });

      final rereadEmpty = RestoreTransactionJournal.fromJson(
        jsonDecode(
              jsonEncode(
                RestoreTransactionJournal.fromJson(capturedEmpty).toJson(),
              ),
            )
            as Map<String, dynamic>,
      ).toJson();

      expect(rereadEmpty['priorBlackListCaptured'], isTrue);
      expect(rereadEmpty['priorFailedQueueCaptured'], isTrue);
      expect(rereadEmpty['priorBlackList'], isEmpty);
      expect(rereadEmpty['priorFailedQueue'], isNull);

      // A payload with none of the keys is the upgrade case, and it must read
      // back as "not captured" so the rollback in (c) declines to touch
      // anything. Defaulting this to "captured" would re-open the data loss.
      final legacy = RestoreTransactionJournal.fromJson(
        _legacyJournalJson(),
      ).toJson();
      expect(legacy['priorBlackListCaptured'], isFalse);
      expect(legacy['priorFailedQueueCaptured'], isFalse);
    });
  });
}

/// Put a block list and a pending-message queue on disk with no registry row
/// and no account directories — the shape that passes `_preflight` and that the
/// rollback used to destroy.
Future<void> _seedPriorFullIdPrefs() async {
  await Prefs.setBlackList(_priorBlockedPeers, _toxId);
  await Prefs.importFailedMessageQueue(_toxId, _priorFailedQueue);
  expect(await Prefs.getBlackList(_toxId), _priorBlockedPeers);
  expect(await Prefs.exportFailedMessageQueue(_toxId), _priorFailedQueue);
  // Both families must be invisible to the scoped sweep, otherwise the restore
  // would reject the import at pre-flight and none of this could happen.
  expect(await Prefs.exportScopedPrefsForAccount(_toxId), isEmpty);
}

Map<String, dynamic> _legacyJournalJson() => <String, dynamic>{
  'version': 1,
  'transactionId': 'legacy-transaction',
  'toxId': _toxId,
  'state': RestoreTransactionState.staged.name,
  'profileStageDir': '/nonexistent/profile_stage',
  'profileFinalDir': '/nonexistent/profile_final',
  'accountDataStageDir': '/nonexistent/data_stage',
  'accountDataFinalDir': '/nonexistent/data_final',
  'hasProfile': false,
};

/// Write the journal file by hand, in the pre-capture shape. Going through
/// `RestoreTransactionJournalStore.write` would serialize today's fields and
/// defeat the point.
Future<void> _writeJournal(Map<String, dynamic> payload) async {
  final root = await AppPaths.applicationSupportPath;
  final file = File(p.join(root, 'account_export_restore_journal.json'));
  await file.writeAsString(jsonEncode(payload), flush: true);
}

Future<String> _writeBackup(AccountExportTestEnv env) async {
  final archive = Archive();
  final metadata = <String, dynamic>{
    'formatVersion': 1,
    'toxId': _toxId,
    'nickname': _nickname,
    'statusMessage': '',
    'exportDate': DateTime.now().toIso8601String(),
    'scopedPrefs': <String, dynamic>{
      'pinned_peers': <String>['peer-a'],
    },
    'blockedPeers': _archiveBlockedPeers,
    'failedMessageQueue': _archiveFailedQueue,
  };
  final metadataBytes = utf8.encode(jsonEncode(metadata));
  archive.addFile(
    ArchiveFile(
      'metadata.json',
      metadataBytes.length,
      Uint8List.fromList(metadataBytes),
    ),
  );
  final profileBytes = utf8.encode('profile-$_toxId');
  archive.addFile(
    ArchiveFile(
      'tox_profile.tox',
      profileBytes.length,
      Uint8List.fromList(profileBytes),
    ),
  );
  final historyBytes = utf8.encode('{"message":"rollback-prefs-history"}');
  archive.addFile(
    ArchiveFile(
      'chat_history/conversation.json',
      historyBytes.length,
      Uint8List.fromList(historyBytes),
    ),
  );
  final zipPath = p.join(env.extras, 'rollback_prefs.zip');
  await File(zipPath).writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return zipPath;
}
