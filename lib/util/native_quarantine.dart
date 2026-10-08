import 'package:flutter/foundation.dart' show visibleForTesting;

import 'tox_utils.dart';

/// Accounts whose native Tox instance was NOT proven stopped in this process
/// (`FfiChatService.nativeInstanceStopped != true` after a teardown: Tim2Tox
/// quarantined an instance a background task was still using).
///
/// Such an instance can still write savedata into the account's profile
/// directory, so no deletion entry point in this process may remove that
/// directory — not the Settings flow that found out, and not the Login page
/// resuming the same deletion tombstone a moment later. A fresh process has
/// no zombie and starts with an empty registry, which is exactly when the
/// cold-start retry (`AccountDeletionCoordinator.recoverPendingDeletions`)
/// finishes the job. Process-local on purpose: there is nothing to persist.
abstract final class NativeQuarantine {
  NativeQuarantine._();

  static final List<String> _toxIds = [];

  /// Record that [toxId]'s instance could not be proven stopped.
  static void mark(String toxId) {
    if (toxId.isEmpty || contains(toxId)) return;
    _toxIds.add(toxId);
  }

  static bool contains(String toxId) =>
      toxId.isNotEmpty && _toxIds.any((id) => compareToxIds(id, toxId));

  @visibleForTesting
  static void reset() => _toxIds.clear();
}
