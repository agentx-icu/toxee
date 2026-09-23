/// Absorbing the pre-multi-account offline queue into an account's own one.
///
/// Split out of `legacy_account_data_claim.dart` (which owns the entitlement
/// decision) purely so neither file carries both policies — and because that
/// one is at the complexity gate's file-size cap.
///
/// The defect this exists for: the legacy queue is a SINGLE file, so
/// "copy it only when the destination does not exist" dropped it the moment
/// the account had a queue of its own, which one offline send is enough to
/// create. Preserving it as an inert `<...>.legacy.json` stopped the loss but
/// left the messages unsendable. They are merged now, by message identity.
library;

import 'dart:convert';
import 'dart:io';

import 'logger.dart';

/// Whether `OfflineMessageQueuePersistence` could read this row back.
///
/// Its parser throws on the first row it cannot decode and the whole queue file
/// is then reported corrupt, so one malformed legacy row must not be allowed to
/// take a working queue down with it.
bool _isLoadableQueueItem(Map<String, dynamic> row) {
  final timestamp = row['timestamp'];
  if (timestamp is! String || DateTime.tryParse(timestamp) == null) {
    return false;
  }
  for (final key in const <String>[
    'kind',
    'text',
    'filePath',
    'fileName',
    'msgID',
    'cloudCustomData',
  ]) {
    final value = row[key];
    if (value != null && value is! String) return false;
  }
  return true;
}

/// Merge every queue in [sources] that exists into [destination], by message
/// identity, and persist the result atomically.
///
/// Identity is the durable `msgID` when the item has one (the same id the
/// pending history row carries), else the `(kind, text, filePath, timestamp)`
/// tuple — the shape queue files written before `msgID` existed have. Items
/// are ordered by timestamp so the drain replays them in send order.
///
/// Never throws: this runs inside account initialization and must not be able
/// to block a login. Returns whether the merge completed — a failure leaves
/// every file exactly as it was, and the caller then leaves the migration
/// unrecorded so the next login retries it.
Future<bool> mergeLegacyOfflineQueues({
  required File destination,
  required List<File> sources,
}) async {
  try {
    final merged = <String, List<Map<String, dynamic>>>{};
    final seen = <String, Set<String>>{};
    var mergedAny = false;

    void absorb(Map<String, dynamic> queue, {required bool validate}) {
      for (final entry in queue.entries) {
        final rows = entry.value;
        if (rows is! List) continue;
        final into = merged.putIfAbsent(entry.key, () => []);
        final ids = seen.putIfAbsent(entry.key, () => <String>{});
        for (final row in rows) {
          if (row is! Map<String, dynamic>) continue;
          // A row the queue store cannot parse makes the WHOLE file
          // unreadable, so a malformed legacy row must not be merged into a
          // queue that currently loads. The account's own rows pass through
          // untouched — if one of those is bad, the file was already broken.
          if (validate && !_isLoadableQueueItem(row)) continue;
          final msgID = row['msgID'];
          final identity = msgID is String && msgID.isNotEmpty
              ? 'id:$msgID'
              : 'tuple:${row['kind']}\u0000${row['text']}\u0000'
                  '${row['filePath']}\u0000${row['timestamp']}';
          if (!ids.add(identity)) continue;
          into.add(row);
        }
      }
    }

    Future<Map<String, dynamic>?> read(File file) async {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    }

    final existing = await read(destination);
    if (existing != null) absorb(existing, validate: false);
    for (final source in sources) {
      final queue = await read(source);
      if (queue == null) continue;
      absorb(queue, validate: true);
      mergedAny = true;
    }
    if (!mergedAny) return true;

    for (final rows in merged.values) {
      rows.sort((a, b) {
        final at = DateTime.tryParse('${a['timestamp']}');
        final bt = DateTime.tryParse('${b['timestamp']}');
        if (at == null || bt == null) return 0;
        return at.compareTo(bt);
      });
    }

    final temp = File('${destination.path}.merge.tmp');
    await temp.writeAsString(jsonEncode(merged), flush: true);
    await temp.rename(destination.path);
    // The `.bak` companion the queue store keeps would otherwise be able to
    // restore a pre-merge snapshot over this.
    final backup = File('${destination.path}.bak');
    if (await backup.exists()) await backup.delete();
    // Mark an absorbed `.legacy.json` consumed so it is never merged twice and
    // is recognisable as history rather than pending work.
    for (final source in sources) {
      if (!source.path.endsWith('.legacy.json')) continue;
      if (await source.exists()) {
        await source.rename('${source.path}.merged');
      }
    }
    AppLogger.log(
      '[LegacyAccountDataClaim] merged the legacy offline queue into the '
      'account queue (${merged.length} conversation(s))',
    );
    return true;
  } catch (e, st) {
    AppLogger.logError(
      '[LegacyAccountDataClaim] could not merge the legacy offline queue; '
      'leaving both files untouched',
      e,
      st,
    );
    return false;
  }
}
