import 'package:flutter/foundation.dart' show visibleForTesting;

import '../tox_utils.dart';

/// Which restore transaction a LIVE caller still owns.
///
/// `FullBackupRestoreTransaction.restore` returns once the payload is committed,
/// but its caller still has to allocate a nickname, publish the account row and
/// finalize. The transaction gate releases at that return, so without this a
/// queued restore ran recovery, saw a committed journal with no account row -
/// indistinguishable from a transaction that died partway - and deleted the
/// first caller's profile and history out from under it.
///
/// Process-local by design: a cold start has no owner, so startup recovery must
/// still resolve whatever it finds.
///
/// Both identities are kept because callers know different things. The service
/// knows its transaction id; the UI rollback wrappers know only the account, and
/// they still have to be able to release what they own when the journal cannot
/// be read at all.
final class RestoreOwnership {
  String? _transactionId;
  String? _toxId;

  /// Whether any caller currently owns a transaction.
  bool get isHeld => _transactionId != null;

  void claim({required String transactionId, required String toxId}) {
    _transactionId = transactionId;
    _toxId = toxId;
  }

  /// Whether [transactionId] is the owned one.
  bool holds(String transactionId) =>
      _transactionId != null && _transactionId == transactionId;

  /// Whether a caller identified by EITHER an exact transaction id or an
  /// equivalent account id owns what is held.
  bool heldByCaller({String? transactionId, String? toxId}) {
    if (transactionId != null && holds(transactionId)) return true;
    final owned = _toxId;
    return toxId != null && owned != null && compareToxIds(toxId, owned);
  }

  void release() {
    _transactionId = null;
    _toxId = null;
  }

  /// For tests that abandon a transaction mid-flight.
  @visibleForTesting
  void reset() => release();
}
