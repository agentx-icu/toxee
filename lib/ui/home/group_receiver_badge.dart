// What the group receiver badge may claim for one of our OWN group rows.
//
// Extracted from home_page.dart: it is a pure decision with no widget
// dependency, it is what two surfaces (the badge and the identity dialog) must
// agree on, and home_page.dart is at its complexity pin — a pure helper is the
// first thing that should leave such a file, not the last.

/// What the group receiver badge may claim for one of our OWN group rows: show
/// it at all, and a count ONLY while the tally behind it is complete.
///
/// [receiveTally] and [readTally] are FfiChatService's two tallies, each a count
/// plus whether that count is EXACT. Both survive a restart only as a FLOOR (the
/// row's persisted isReceived / isRead booleans), because receiver and reader
/// identities are deliberately never stored — see tim2tox 0dc54c6 and its
/// receiver-side mirror. A row RECEIVED but never READ used to restore neither a
/// floor nor an inexactness marker, so it showed nothing for a message members
/// really had got, and could later show an exact-looking 1.
///
/// The count is claimed only when the receiver tally is exact AND not short of
/// the read count (readers are a subset of receivers, so a shortfall proves the
/// tally lost entries, which the two independently capped maps allow). Otherwise
/// the badge says only "at least one member got this" — hiding it would instead
/// read as "nobody received this".
({bool show, int? count}) receiverBadge(
  ({int receiverCount, bool exactCount}) receiveTally,
  ({int readCount, bool exactCount}) readTally,
) {
  final tallied = receiveTally.receiverCount;
  final exact = receiveTally.exactCount &&
      readTally.exactCount &&
      tallied >= readTally.readCount &&
      tallied > 0;
  return (
    show: tallied > 0 || readTally.readCount > 0,
    count: exact ? tallied : null,
  );
}
