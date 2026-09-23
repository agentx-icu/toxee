import 'logger.dart';
import 'prefs.dart';

/// Best-effort restore of the durable current-account pointer, for ROLLBACK
/// and teardown paths.
///
/// [Prefs.setCurrentAccountToxId] throws [CurrentAccountPointerFailure] when
/// the store refuses the write, which is what a forward path needs: it must not
/// keep running as an account the next cold start would not restore. A path
/// that is already unwinding cannot act on it — it still has to finish undoing
/// what it applied, and must not replace the failure it is reporting with this
/// one — so it records the refusal and continues. `getCurrentAccountToxId` is
/// uncached by the failed write, so reads observe whatever the store really has.
Future<void> restoreCurrentAccountPointer(String? toxId, String context) async {
  try {
    await Prefs.setCurrentAccountToxId(toxId);
  } on CurrentAccountPointerFailure catch (e, st) {
    AppLogger.logError(
      '$context could not restore the current-account pointer; the store '
      'still names the account this path was undoing',
      e,
      st,
    );
  }
}
