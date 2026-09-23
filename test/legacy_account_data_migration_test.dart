// The one-shot migration of the pre-multi-account global dataset.
//
// Two data-safety defects it used to have (2026-09-22 review):
//
//   * IT NEVER ENDED. The claim is durable and the legacy source is never
//     retired, so every login by the owning account re-copied any destination
//     file that was missing — and "missing" is exactly what clearing a
//     conversation produces. Deleted history came back at the next sign-in.
//   * THE LEGACY OFFLINE QUEUE WAS NEVER SENT when the account already had a
//     queue of its own (one offline send is enough to create one): it was
//     parked in an inert `<...>.legacy.json` that no runtime reads.
//
// Desktop and mobile share this code path (account initialization), so both
// fixes apply to both.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/legacy_account_data_claim.dart';

const _toxId =
    'A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1'
    'A1A1A1A1A1A1';
const _conversationId =
    'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';

Map<String, Object?> _queueItem(String text, {required String id}) => {
  'kind': 'text',
  'text': text,
  'filePath': null,
  'fileName': null,
  'timestamp': DateTime.utc(2026, 1, 1, 12, 0, 0).toIso8601String(),
  'msgID': id,
  'contentKind': 'normal',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('legacy_migration_');
    AppPaths.debugApplicationSupportOverride = tempRoot.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          return tempRoot.path;
        });
    // The claim is already recorded for this account: it is the upgrade shape
    // these tests are about, and the entitlement rules have their own tests.
    SharedPreferences.setMockInitialValues({
      LegacyAccountDataClaim.claimedByKey: _toxId,
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    AppPaths.debugApplicationSupportOverride = null;
    if (tempRoot.existsSync()) await tempRoot.delete(recursive: true);
  });

  String accountRoot() =>
      p.join(tempRoot.path, 'account_data', _toxId.substring(0, 16));
  File accountHistoryFile() =>
      File(p.join(accountRoot(), 'chat_history', '$_conversationId.json'));
  File accountQueueFile() =>
      File(p.join(accountRoot(), 'offline_message_queue.json'));

  Future<void> seedLegacyHistory(String text) async {
    final dir = Directory(p.join(tempRoot.path, 'chat_history'));
    await dir.create(recursive: true);
    await File(p.join(dir.path, '$_conversationId.json')).writeAsString(
      jsonEncode({
        'conversationId': _conversationId,
        'version': 2,
        'messages': [
          {'text': text, 'fromUserId': 'PEER', 'isSelf': false},
        ],
      }),
    );
  }

  Future<void> seedLegacyQueue(List<Map<String, Object?>> items) async {
    await File(
      p.join(tempRoot.path, 'offline_message_queue.json'),
    ).writeAsString(jsonEncode({_conversationId: items}));
  }

  test('history deleted after the migration is not copied back', () async {
    await seedLegacyHistory('from-the-legacy-install');

    await migrateLegacyAccountDataIfClaimed(_toxId);
    expect(await accountHistoryFile().exists(), isTrue);
    expect(
      File(p.join(accountRoot(), legacyMigrationDoneMarkerName)).existsSync(),
      isTrue,
      reason: 'the completed migration must be recorded',
    );

    // The user clears that conversation: its account-side file is deleted.
    await accountHistoryFile().delete();

    // Next login by the same (owning) account.
    await migrateLegacyAccountDataIfClaimed(_toxId);
    expect(
      await accountHistoryFile().exists(),
      isFalse,
      reason: 'a completed migration must never re-copy deleted history',
    );
  });

  test('the legacy offline queue is merged, not parked', () async {
    await seedLegacyQueue([_queueItem('never-sent-from-the-old-install',
        id: 'legacy-1')]);
    // The account already has a queue of its own — one offline send is enough.
    await Directory(accountRoot()).create(recursive: true);
    await accountQueueFile().writeAsString(
      jsonEncode({
        _conversationId: [_queueItem('queued-by-this-account', id: 'own-1')],
      }),
    );

    await migrateLegacyAccountDataIfClaimed(_toxId);

    final merged =
        jsonDecode(await accountQueueFile().readAsString())
            as Map<String, dynamic>;
    final ids = (merged[_conversationId] as List)
        .map((e) => (e as Map<String, dynamic>)['msgID'])
        .toList();
    expect(ids, containsAll(<String>['own-1', 'legacy-1']));
    expect(
      File('${accountQueueFile().path}.legacy.json').existsSync(),
      isFalse,
      reason: 'nothing may be left behind as unreachable pending work',
    );
  });

  test('a queue parked by an earlier build is absorbed', () async {
    await Directory(accountRoot()).create(recursive: true);
    await accountQueueFile().writeAsString(
      jsonEncode({
        _conversationId: [_queueItem('queued-by-this-account', id: 'own-1')],
      }),
    );
    // What the previous behaviour left on an upgraded install.
    await File('${accountQueueFile().path}.legacy.json').writeAsString(
      jsonEncode({
        _conversationId: [_queueItem('stranded-by-the-old-build', id: 'old-1')],
      }),
    );

    await migrateLegacyAccountDataIfClaimed(_toxId);

    final merged =
        jsonDecode(await accountQueueFile().readAsString())
            as Map<String, dynamic>;
    final ids = (merged[_conversationId] as List)
        .map((e) => (e as Map<String, dynamic>)['msgID'])
        .toList();
    expect(ids, containsAll(<String>['own-1', 'old-1']));
    expect(
      File('${accountQueueFile().path}.legacy.json').existsSync(),
      isFalse,
    );
    // Merging twice must not duplicate anything (the marker also prevents it).
    await migrateLegacyAccountDataIfClaimed(_toxId);
    final again =
        jsonDecode(await accountQueueFile().readAsString())
            as Map<String, dynamic>;
    expect((again[_conversationId] as List).length, 2);
  });
}
