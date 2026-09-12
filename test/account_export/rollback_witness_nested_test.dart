// Reproduces codex's round-18 case against the fixed code: a nested file is
// deleted, then the directory delete fails because its parent is non-writable.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/account_export/restore_paths.dart';
import 'package:toxee/util/account_export/restore_transaction_journal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const toxId =
      'AA11BB22CC33DD44EE55FF6677889900112233445566778899AABBCCDDEEFF01';

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.initialize(await SharedPreferences.getInstance());
    // The account row MUST exist, or `rollbackRemovedNothing` short-circuits on
    // it and the test passes without ever comparing paths - which is exactly how
    // the first version of this test passed against a non-recursive baseline.
    await Prefs.addAccount(toxId: toxId, nickname: 'Nested');
  });

  test('nested payload loss is NOT classified as untouched', () async {
    final root = await Directory.systemTemp.createTemp('witness_nested_');
    addTearDown(() async {
      await Process.run('chmod', ['-R', 'u+w', root.path]);
      await root.delete(recursive: true);
    });
    final dataRoot = Directory('${root.path}/account_data')..createSync();
    final history = Directory('${dataRoot.path}/chat_history')..createSync();
    final peer = File('${history.path}/peer.json')..writeAsStringSync('{}');

    final journal = RestoreTransactionJournal(
      transactionId: 't1',
      toxId: toxId,
      state: RestoreTransactionState.staged,
      profileStageDir: '${root.path}/pstage',
      profileFinalDir: '${root.path}/pfinal',
      accountDataStageDir: '${root.path}/dstage',
      accountDataFinalDir: dataRoot.path,
      hasProfile: false,
    );

    final witnessBefore = await captureRollbackWitness(journal);
    expect(witnessBefore.usable, isTrue);

    // Guard the guard: with everything still in place this must read as
    // untouched, so the `isFalse` below cannot come from an unrelated
    // short-circuit (a missing account row did exactly that once).
    expect(await rollbackRemovedNothing(journal, witnessBefore), isTrue,
        reason: 'nothing removed yet, so the baseline must still match');

    peer.deleteSync();
    expect(history.existsSync(), isTrue,
        reason: 'every TOP-LEVEL name survives, which is what fooled the old check');

    expect(await rollbackRemovedNothing(journal, witnessBefore), isFalse,
        reason: 'all restored history is gone; this must not read as untouched');
  });
}
