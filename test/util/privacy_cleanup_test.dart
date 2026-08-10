// Unit tests for `lib/util/privacy_cleanup.dart` (`AccountPrivacyCleanup`).
//
// WHY THIS FILE IS WORTH TESTING (security boundary)
// --------------------------------------------------
// `purgeDeletedAccountResidue` is the last stage of "delete this account" that
// touches data the earlier stages deliberately leave behind:
//
//   * diagnostic logs — `<appSupport>/logs/**` plus the deprecated flat
//     `<appSupport>/flutter_client.log`. These contain peer IDs, message
//     metadata and file names for the account the user just asked us to
//     forget, so failing to purge them silently defeats the whole deletion.
//   * the failed-message queue — `Prefs.clearScopedKeysForAccount` explicitly
//     *skips* the legacy 16-char-prefix key (`key != legacyFailedMessagesKey`),
//     so this module is the only thing that removes it. The key names must stay
//     byte-identical to `Tim2ToxFailedMessagePersistence`'s `_storageKey` /
//     `_legacyStorageKey`, which is a cross-package contract with no compiler
//     enforcement.
//   * the global (unscoped) `self_nickname` / `self_status_msg` /
//     `self_avatar_path` / `current_account_tox_id` prefs, but only when the
//     account being deleted really is the active one.
//
// Both failure directions are damaging: leaving residue is a privacy leak, and
// over-deleting wipes a *surviving* account's profile. Every test below pins
// one side or the other.
//
// This is shared Dart under `lib/util/`, so it is the same code path on macOS,
// Linux, Windows, iOS and Android — no mobile counterpart to chase.
//
// The queue key is the sharpest edge here. The *writer*
// (`Tim2ToxSdkPlatform._persistFinalizedFailedMessage`) keys by
// `FfiChatService.getSelfToxId()` — always the 76-char address — while the
// *deleter* is driven by `Prefs.getCurrentAccountToxId()` or an `account_list`
// row, which for an imported account can still hold the 64-char public key
// (`ShortToxIdBackfill` upgrades it on login but has several documented
// give-up paths). Matching those two by string equality silently strands the
// 76-char key, and `Prefs.clearScopedKeysForAccount` will not collect it
// either because a 76-char suffix does not end in `_<first16>`. The
// cross-representation tests below pin that.
//
// COVERED
//   * log tree + flat log removal, and that a working log sink is reopened
//     afterwards (including after a *failed* purge).
//   * non-log application-support data — including a *surviving* account's
//     `account_data/` root — and unrelated prefs survive.
//   * failed-message removal verified end-to-end against the real
//     `Tim2ToxFailedMessagePersistence` writer, plus the hand-seeded legacy
//     16-char key that no current API can still produce.
//   * queue removal across Tox ID representations in both directions
//     (76-char key vs 64-char deletion driver and vice versa) and across hex
//     case, each with a second account as the over-deletion control.
//   * the over-deletion guards on that sweep: a queue key whose suffix is not
//     an account-ID shape, and the unsuffixed pre-account-scoping key, both
//     survive.
//   * a Tox ID shorter than the 16-char legacy prefix does not trigger a
//     prefix-wildcard removal.
//   * all four `deletedCurrentAccount` / pointer combinations, including the
//     76-char-address-vs-64-char-public-key comparison, an empty pointer
//     string, and the ordering that production actually uses (the pointer is
//     already cleared by the earlier `currentAccount` stage before this one
//     runs).
//   * idempotency, and a first run against a host that has no logs at all.
//
// NOT COVERED (and why)
//   * "deleting account A keeps account B's logs" — it does not, on purpose.
//     `AppPaths.logsDir` is one global `<appSupport>/logs` whose files are
//     named `app_<sessionTimestamp>.log` and interleave every session on the
//     install, so no subset maps to one account. The purge takes the whole
//     tree and privacy wins over diagnosability; see the doc comment on
//     `AccountPrivacyCleanup._purgeDiagnosticLogs`. What *is* pinned below is
//     the boundary of that blast radius: nothing outside `logs/` goes with it.
//   * `AppLogger`'s own rotation/pruning behaviour — that is
//     `logger_rotation_test.dart`'s job; here we only assert that a usable sink
//     exists again afterwards.
//   * The Windows branch of the "purge fails" test: making a directory
//     undeletable there needs an open handle or an ACL edit rather than POSIX
//     mode bits, so that case is explicitly `markTestSkipped`, never silently
//     skipped.
//   * Anything about *which* stage of `AccountDeletion` calls this — that is
//     `account_deletion` / journal territory.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/utils/tim2tox_failed_message_persistence.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/logger.dart';
import 'package:toxee/util/privacy_cleanup.dart';

import '../account_export/test_support.dart';

/// 64-char Tox public keys and their 76-char full-address forms.
const String _pubKeyA =
    'AA11AA11AA11AA11AA11AA11AA11AA11AA11AA11AA11AA11AA11AA11AA11AA11';
const String _addressA = '${_pubKeyA}CAFEBABE0000';
const String _prefixA = 'AA11AA11AA11AA11';
const String _pubKeyB =
    'BB22BB22BB22BB22BB22BB22BB22BB22BB22BB22BB22BB22BB22BB22BB22BB22';
const String _addressB = '${_pubKeyB}DEADBEEF0000';
const String _prefixB = 'BB22BB22BB22BB22';

/// Mirrors `Tim2ToxFailedMessagePersistence._persistenceKey` and
/// `AccountPrivacyCleanup._failedMessagesBase`. Duplicated on purpose: if the
/// three ever diverge, the parity tests below break.
const String _failedMessagesBase = 'tencent_cloud_chat_failed_messages';

const String _logSecret = 'LOG_SECRET_7c31de';
const String _startMarker = '=== App Log Started ===';

Map<String, dynamic> _failedRow(String id) => <String, dynamic>{
  'id': id,
  'msgID': 'wire-$id',
  'timestamp': 100,
  'text': 'failed message $id',
};

Future<void> _purge(
  String toxId, {
  required bool deletedCurrentAccount,
}) {
  return AccountPrivacyCleanup.purgeDeletedAccountResidue(
    toxId: toxId,
    deletedCurrentAccount: deletedCurrentAccount,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AccountExportTestEnv env;
  late SharedPreferences prefs;
  late Directory logsDir;
  late File flatLog;

  setUp(() async {
    env = await setUpAccountExportTestEnv();
    AppPaths.debugApplicationSupportOverride = env.appSupport;
    AppLogger.resetForTesting();
    AppLogger.setConsoleLoggingEnabled(false);
    prefs = await SharedPreferences.getInstance();
    logsDir = Directory(p.join(env.appSupport, 'logs'));
    flatLog = File(p.join(env.appSupport, 'flutter_client.log'));
  });

  tearDown(() async {
    AppLogger.resetForTesting();
    AppPaths.debugApplicationSupportOverride = null;
    await env.dispose();
  });

  Future<void> seedDiagnosticLogs() async {
    await logsDir.create(recursive: true);
    await File(p.join(logsDir.path, 'app_0001.log')).writeAsString(_logSecret);
    await Directory(p.join(logsDir.path, 'nested')).create(recursive: true);
    await File(
      p.join(logsDir.path, 'nested', 'deep.log'),
    ).writeAsString(_logSecret);
    await flatLog.writeAsString(_logSecret);
  }

  Future<void> seedSelfProfilePrefs() async {
    await prefs.setString('self_nickname', 'Deleted Nick');
    await prefs.setString('self_status_msg', 'Deleted Status');
    await prefs.setString('self_avatar_path', '/tmp/deleted_avatar.png');
  }

  void expectSelfProfilePrefsPresent() {
    expect(prefs.getString('self_nickname'), 'Deleted Nick');
    expect(prefs.getString('self_status_msg'), 'Deleted Status');
    expect(prefs.getString('self_avatar_path'), '/tmp/deleted_avatar.png');
  }

  void expectSelfProfilePrefsCleared() {
    expect(prefs.getString('self_nickname'), isNull);
    expect(prefs.getString('self_status_msg'), isNull);
    expect(prefs.getString('self_avatar_path'), isNull);
  }

  /// Every regular file currently under `<appSupport>/logs`.
  List<File> logFiles() {
    return logsDir.listSync(recursive: true).whereType<File>().toList();
  }

  void expectFreshLogSink() {
    expect(logsDir.existsSync(), isTrue, reason: 'logs dir must be recreated');
    final files = logFiles();
    expect(files, isNotEmpty, reason: 'a fresh log sink must be reopened');
    expect(
      files.any(
        (File f) =>
            p.basename(f.path).startsWith('app_') &&
            f.readAsStringSync().contains(_startMarker),
      ),
      isTrue,
      reason: 'the reopened sink must have been written to, not just named',
    );
  }

  group('diagnostic log purge', () {
    test('deletes the log tree and the deprecated flat log, then reopens a '
        'fresh sink', () async {
      await seedDiagnosticLogs();

      await _purge(_addressA, deletedCurrentAccount: false);

      expect(flatLog.existsSync(), isFalse);
      expect(File(p.join(logsDir.path, 'app_0001.log')).existsSync(), isFalse);
      expect(Directory(p.join(logsDir.path, 'nested')).existsSync(), isFalse);
      expectFreshLogSink();
      for (final file in logFiles()) {
        expect(
          file.readAsStringSync(),
          isNot(contains(_logSecret)),
          reason: 'purged log content must not survive in ${file.path}',
        );
      }
    });

    test('succeeds and creates a sink when no logs existed at all', () async {
      expect(logsDir.existsSync(), isFalse);
      expect(flatLog.existsSync(), isFalse);

      await _purge(_addressA, deletedCurrentAccount: false);

      expectFreshLogSink();
    });

    test('leaves non-log application-support data untouched', () async {
      await seedDiagnosticLogs();
      final keep = <String, File>{
        'history': File(p.join(env.appSupport, 'chat_history', 'c.json')),
        'avatar': File(p.join(env.appSupport, 'avatars', 'a.png')),
        'profile': File(p.join(env.appSupport, 'tim2tox', 'p.tox')),
        // Name-prefix collision guard: only the `logs` *directory* may go.
        'lookalike': File(p.join(env.appSupport, 'logs_archive.txt')),
        // The log purge is deliberately install-wide; this pins where that
        // stops. A surviving account's own data root must be untouched, since
        // that tree *is* account-scoped (`AppPaths.getAccountDataRoot`).
        'survivor': File(
          p.join(
            env.appSupport,
            'account_data',
            _prefixB,
            'chat_history',
            'peer.json',
          ),
        ),
      };
      for (final file in keep.values) {
        await file.parent.create(recursive: true);
        await file.writeAsString('keep-${p.basename(file.path)}');
      }

      await _purge(_addressA, deletedCurrentAccount: false);

      for (final entry in keep.entries) {
        expect(
          entry.value.existsSync(),
          isTrue,
          reason: '${entry.key} must survive the privacy purge',
        );
        expect(
          entry.value.readAsStringSync(),
          'keep-${p.basename(entry.value.path)}',
        );
      }
    });

    test('reopens a usable log sink even when the purge itself fails',
        () async {
      if (Platform.isWindows) {
        markTestSkipped(
          'Needs POSIX mode bits to make a directory undeletable; the Windows '
          'equivalent requires an ACL edit or a held handle.',
        );
        return;
      }
      await seedDiagnosticLogs();
      final legacyA = '${_failedMessagesBase}_$_prefixA';
      await prefs.setString(legacyA, '{"peer-a":[]}');
      // Removing `<appSupport>/logs` requires write permission on
      // `<appSupport>`, so clearing it makes the delete fail mid-purge.
      final chmod = await Process.run('chmod', <String>['0555', env.appSupport]);
      expect(chmod.exitCode, 0);
      final probe = File(p.join(env.appSupport, 'probe.tmp'));
      var privileged = false;
      try {
        await probe.writeAsString('x');
        privileged = true;
      } on FileSystemException {
        privileged = false;
      }

      try {
        if (privileged) {
          markTestSkipped(
            'Running with privileges that bypass POSIX mode bits, so the '
            'failure this test needs cannot be provoked.',
          );
          return;
        }

        await expectLater(
          () => _purge(_addressA, deletedCurrentAccount: false),
          throwsA(isA<FileSystemException>()),
        );

        // The purge aborted inside the log stage, so nothing after it ran:
        // the deprecated flat log and the queue keys are still present, which
        // is what makes the deletion journal retry this stage meaningful.
        expect(flatLog.existsSync(), isTrue);
        expect(prefs.getString(legacyA), isNotNull);
        // Logging must nevertheless not be left dead: `_tryReopenLogSink` runs
        // before the rethrow so later diagnostics still land somewhere.
        expectFreshLogSink();
      } finally {
        await Process.run('chmod', <String>['0755', env.appSupport]);
        if (privileged && probe.existsSync()) {
          await probe.delete();
        }
      }
    });
  });

  group('failed-message queue removal', () {
    test('removes exactly the deleted account\'s queue written by '
        'Tim2ToxFailedMessagePersistence', () async {
      await Tim2ToxFailedMessagePersistence.saveFailedMessageData(
        messageData: _failedRow('a-1'),
        userID: 'peer-a',
        accountToxId: _addressA,
      );
      await Tim2ToxFailedMessagePersistence.saveFailedMessageData(
        messageData: _failedRow('b-1'),
        userID: 'peer-b',
        accountToxId: _addressB,
      );
      expect(
        await Tim2ToxFailedMessagePersistence.loadFailedMessages(
          userID: 'peer-a',
          accountToxId: _addressA,
        ),
        hasLength(1),
        reason: 'precondition: A must have a queued failure to purge',
      );

      await _purge(_addressA, deletedCurrentAccount: false);

      expect(
        await Tim2ToxFailedMessagePersistence.loadFailedMessages(
          userID: 'peer-a',
          accountToxId: _addressA,
        ),
        isEmpty,
      );
      expect(
        await Tim2ToxFailedMessagePersistence.loadFailedMessages(
          userID: 'peer-b',
          accountToxId: _addressB,
        ),
        hasLength(1),
        reason: 'a surviving account must keep its own failed messages',
      );
    });

    test('removes the legacy 16-char-prefix queue key that scoped-pref '
        'clearing deliberately skips', () async {
      final legacyA = '${_failedMessagesBase}_$_prefixA';
      final legacyB = '${_failedMessagesBase}_$_prefixB';
      await prefs.setString(
        legacyA,
        jsonEncode(<String, dynamic>{
          'peer-a': <Map<String, dynamic>>[_failedRow('legacy-a')],
        }),
      );
      await prefs.setString(
        legacyB,
        jsonEncode(<String, dynamic>{
          'peer-b': <Map<String, dynamic>>[_failedRow('legacy-b')],
        }),
      );

      await _purge(_addressA, deletedCurrentAccount: false);

      expect(prefs.getString(legacyA), isNull);
      expect(prefs.getString(legacyB), isNotNull);
    });

    test('removes a queue keyed by the 76-char address when deletion is '
        'driven by the 64-char public key', () async {
      // The production mismatch: the writer only ever has the full address
      // (`getSelfToxId()`), while an imported account whose
      // `ShortToxIdBackfill` did not complete is still deleted under its
      // 64-char public key. Plain string
      // equality misses the key entirely, and `clearScopedKeysForAccount`
      // cannot collect it either (a 76-char suffix does not end in `_<16>`),
      // so the queue — peer IDs and message text — would outlive the account.
      await Tim2ToxFailedMessagePersistence.saveFailedMessageData(
        messageData: _failedRow('a-1'),
        userID: 'peer-a',
        accountToxId: _addressA,
      );
      await Tim2ToxFailedMessagePersistence.saveFailedMessageData(
        messageData: _failedRow('b-1'),
        userID: 'peer-b',
        accountToxId: _addressB,
      );
      expect(prefs.getString('${_failedMessagesBase}_$_addressA'), isNotNull);

      await _purge(_pubKeyA, deletedCurrentAccount: false);

      expect(
        prefs.getString('${_failedMessagesBase}_$_addressA'),
        isNull,
        reason: 'the full-address key belongs to the account being deleted',
      );
      expect(
        await Tim2ToxFailedMessagePersistence.loadFailedMessages(
          userID: 'peer-a',
          accountToxId: _addressA,
        ),
        isEmpty,
      );
      expect(
        prefs.getString('${_failedMessagesBase}_$_addressB'),
        isNotNull,
        reason: 'a different account keeps its queue across the sweep',
      );
    });

    test('removes a queue keyed by the 64-char public key when deletion is '
        'driven by the 76-char address', () async {
      // The mirror image: the record that survived is short and the deletion
      // driver is long (e.g. the backfill rewrote `account_list` but its
      // pointer rewrite threw, or a pre-backfill session wrote the queue).
      await Tim2ToxFailedMessagePersistence.saveFailedMessageData(
        messageData: _failedRow('a-1'),
        userID: 'peer-a',
        accountToxId: _pubKeyA,
      );
      await Tim2ToxFailedMessagePersistence.saveFailedMessageData(
        messageData: _failedRow('b-1'),
        userID: 'peer-b',
        accountToxId: _pubKeyB,
      );

      await _purge(_addressA, deletedCurrentAccount: false);

      expect(prefs.getString('${_failedMessagesBase}_$_pubKeyA'), isNull);
      expect(prefs.getString('${_failedMessagesBase}_$_pubKeyB'), isNotNull);
    });

    test('matches the account ID regardless of hex case', () async {
      // Tox IDs are hex, so two spellings that differ only in case are the
      // same account and can never be two different ones — widening the match
      // this far is free of over-deletion risk.
      final lowerA = '${_failedMessagesBase}_${_addressA.toLowerCase()}';
      final lowerB = '${_failedMessagesBase}_${_addressB.toLowerCase()}';
      await prefs.setString(lowerA, '{"peer-a":[]}');
      await prefs.setString(lowerB, '{"peer-b":[]}');

      await _purge(_addressA, deletedCurrentAccount: false);

      expect(prefs.getString(lowerA), isNull);
      expect(prefs.getString(lowerB), isNotNull);
    });

    test('leaves queue keys whose suffix is not an account-ID shape', () async {
      // Over-deletion guard for the sweep. Only 16/64/76-char hex suffixes are
      // shapes `Tim2ToxFailedMessagePersistence` can produce; anything else
      // must not be truncated down to 64 chars and mistaken for this account.
      final longer = '${_failedMessagesBase}_${_addressA}_shard2';
      final nonHex = '${_failedMessagesBase}_ZZ11ZZ11ZZ11ZZ11';
      final unsuffixed = _failedMessagesBase;
      await prefs.setString(longer, '{"peer":[]}');
      await prefs.setString(nonHex, '{"peer":[]}');
      // Pre-account-scoping rows: not attributable to the deleted account, so
      // removing them would eat a surviving account's pending sends.
      await prefs.setString(unsuffixed, '{"peer":[]}');

      await _purge(_addressA, deletedCurrentAccount: false);

      expect(prefs.getString(longer), isNotNull);
      expect(prefs.getString(nonHex), isNotNull);
      expect(prefs.getString(unsuffixed), isNotNull);
    });

    test('a Tox ID shorter than the legacy prefix removes only its exact key',
        () async {
      const String shortId = 'AA11AA11';
      final exactKey = '${_failedMessagesBase}_$shortId';
      final prefixKey = '${_failedMessagesBase}_$_prefixA';
      await prefs.setString(exactKey, '{"peer":[]}');
      await prefs.setString(prefixKey, '{"peer":[]}');

      await _purge(shortId, deletedCurrentAccount: false);

      expect(prefs.getString(exactKey), isNull);
      expect(
        prefs.getString(prefixKey),
        isNotNull,
        reason: 'a short ID must not act as a wildcard over longer keys',
      );
    });

    test('unrelated preferences are never touched', () async {
      await prefs.setString('unrelated_setting', 'keep me');

      await _purge(_addressA, deletedCurrentAccount: true);

      expect(prefs.getString('unrelated_setting'), 'keep me');
      expect(prefs.getString('profile_storage_root'), env.profiles);
      expect(prefs.getString('downloads_directory'), env.downloads);
    });
  });

  group('global self-profile preferences', () {
    test('are preserved when the deleted account was not the current one',
        () async {
      await seedSelfProfilePrefs();
      await prefs.setString('current_account_tox_id', _addressA);

      await _purge(_addressA, deletedCurrentAccount: false);

      expectSelfProfilePrefsPresent();
      expect(prefs.getString('current_account_tox_id'), _addressA);
    });

    test('are preserved when the pointer names a different surviving account',
        () async {
      await seedSelfProfilePrefs();
      await prefs.setString('current_account_tox_id', _addressB);

      await _purge(_addressA, deletedCurrentAccount: true);

      expectSelfProfilePrefsPresent();
      expect(
        prefs.getString('current_account_tox_id'),
        _addressB,
        reason: 'deleting A must not unseat the active account B',
      );
    });

    test('are cleared when the pointer is the same account in 76-char form',
        () async {
      // The pointer is stored as the full 76-char address while deletion is
      // driven by the 64-char public key; `compareToxIds` must bridge the two
      // or the deleted account's nickname/avatar would linger.
      await seedSelfProfilePrefs();
      await prefs.setString('current_account_tox_id', _addressA);

      await _purge(_pubKeyA, deletedCurrentAccount: true);

      expectSelfProfilePrefsCleared();
      expect(prefs.getString('current_account_tox_id'), isNull);
    });

    test('are cleared and the pointer key removed when the pointer is an '
        'empty string', () async {
      // An empty pointer names no account, so it is treated as "no owner" —
      // the same verdict that authorises clearing the globals. Leaving the
      // key behind as `''` would contradict that and keep a vestigial entry
      // in a store the deletion just declared clean.
      await seedSelfProfilePrefs();
      await prefs.setString('current_account_tox_id', '');

      await _purge(_addressA, deletedCurrentAccount: true);

      expectSelfProfilePrefsCleared();
      expect(
        prefs.getString('current_account_tox_id'),
        isNull,
        reason: 'an empty pointer must not survive as an empty-string key',
      );
      expect(prefs.containsKey('current_account_tox_id'), isFalse);
    });

    test('are cleared when the pointer was already reset by the earlier '
        'deletion stage', () async {
      // Production ordering: `AccountDeletion`'s `currentAccount` stage clears
      // `current_account_tox_id` *before* the `privacyResidue` stage runs, so
      // this is the path real deletions take.
      await seedSelfProfilePrefs();
      expect(prefs.getString('current_account_tox_id'), isNull);

      await _purge(_addressA, deletedCurrentAccount: true);

      expectSelfProfilePrefsCleared();
    });
  });

  test('is idempotent across repeated runs', () async {
    await seedDiagnosticLogs();
    await seedSelfProfilePrefs();
    await prefs.setString('current_account_tox_id', _addressA);
    await Tim2ToxFailedMessagePersistence.saveFailedMessageData(
      messageData: _failedRow('a-1'),
      userID: 'peer-a',
      accountToxId: _addressA,
    );
    await Tim2ToxFailedMessagePersistence.saveFailedMessageData(
      messageData: _failedRow('b-1'),
      userID: 'peer-b',
      accountToxId: _addressB,
    );

    await _purge(_addressA, deletedCurrentAccount: true);
    await _purge(_addressA, deletedCurrentAccount: true);

    expectSelfProfilePrefsCleared();
    expect(prefs.getString('current_account_tox_id'), isNull);
    expect(
      await Tim2ToxFailedMessagePersistence.loadFailedMessages(
        userID: 'peer-a',
        accountToxId: _addressA,
      ),
      isEmpty,
    );
    expect(
      await Tim2ToxFailedMessagePersistence.loadFailedMessages(
        userID: 'peer-b',
        accountToxId: _addressB,
      ),
      hasLength(1),
      reason: 'repeating the purge must not start eating other accounts',
    );
    expect(flatLog.existsSync(), isFalse);
    expectFreshLogSink();
  });
}
