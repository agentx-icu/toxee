part of 'package:toxee/util/prefs.dart';

// The pending failed-message queue, as backup/rollback plumbing rather than a
// pref accessor family. Split out of `prefs.dart` (complexity-gate pin); a `part`
// so it can reach `Prefs`'s private key builders.
//
// Why any of this exists: the modern key is
// `tencent_cloud_chat_failed_messages_<FULL toxId>`, which the `_<first16>`
// suffix sweeps used by the scoped-prefs export and by account deletion cannot
// match. So the queue was absent from every full backup (a restore silently
// dropped messages the user believed were pending) and survived a rolled-back
// restore for the next import to inherit.

/// The account's pending failed-message queue, as a portable string, or null
/// when there is none.
///
/// Exists because the queue key is `tencent_cloud_chat_failed_messages_<full
/// toxId>`, which the `_<first16>`-suffix export sweep does not match — so it
/// was absent from every full backup, and a restore silently dropped messages
/// the user believes are still waiting to send. Read under both the modern
/// full-id key and the legacy 16-char one.
Future<String?> exportFailedMessageQueueImpl(String toxId) async {
  final normalized = toxId.trim();
  if (normalized.isEmpty) return null;
  final p = await Prefs._getPrefs();
  final direct = p.getString('${Prefs._kFailedMessagesBase}_$normalized');
  if (direct != null && direct.isNotEmpty) return direct;
  final legacyKey = Prefs._legacyFailedMessagesKeyForToxId(normalized);
  if (legacyKey == null) return null;
  final legacy = p.getString(legacyKey);
  return (legacy != null && legacy.isNotEmpty) ? legacy : null;
}

/// Restore a queue captured by [exportFailedMessageQueue].
///
/// Written under the modern full-id key; the runtime reads that shape first.
Future<void> importFailedMessageQueueImpl(
  String toxId,
  String payload,
) async {
  final normalized = toxId.trim();
  if (normalized.isEmpty || payload.isEmpty) return;
  final p = await Prefs._getPrefs();
  await p.setString('${Prefs._kFailedMessagesBase}_$normalized', payload);
}

/// Returns whether every removal actually took, so a caller establishing a
/// rollback does not treat a refused write as success.
Future<bool> clearFailedMessageQueueImpl(String toxId) async {
  final normalized = toxId.trim();
  if (normalized.isEmpty) return true;
  final p = await Prefs._getPrefs();
  var allRemoved = await p.remove('${Prefs._kFailedMessagesBase}_$normalized');
  final legacyKey = Prefs._legacyFailedMessagesKeyForToxId(normalized);
  if (legacyKey != null && !await p.remove(legacyKey)) allRemoved = false;
  return allRemoved;
}
