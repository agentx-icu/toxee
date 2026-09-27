// The two group-receipt surfaces toxee owns, after a restart.
//
// Group receipts are tallied per READER/RECEIVER IDENTITY in memory only
// (FfiChatService._messageReceivers / _messageReaders). Those identities are
// deliberately never persisted: a member's per-group key rotates, so a stored
// set would deanonymize who read what across restarts. What IS persisted is a
// boolean pair on the author's own row (isReceived / isRead), and tim2tox's read
// side falls back to it — commit 0dc54c6 made getMessageReadReceipts report
// readCount as a FLOOR (>= 1) and unreadCount as null, i.e. "unknown", rather
// than a fabricated number. The same commit exposed
// FfiChatService.groupRowReadTally(): that floor plus an `exactCount` flag, which
// is false for any row whose read state came off disk AND stays false for the
// rest of the session even once fresh receipts arrive, because a tally rebuilt
// after a restart is still missing whoever receipted before it.
//
// toxee's own two surfaces still read the memory-only RECEIVER tally:
//   * lib/ui/home_page_bootstrap.dart — the receiver-COUNT badge on our own
//     group bubbles. It was gated on `receiverCount > 0`, so after a restart it
//     vanished for messages members really had received. Vanishing is
//     indistinguishable from "nobody received this", which is exactly the
//     reading the persisted flag contradicts. It now shows for such a row and
//     omits only the number ([receiverBadge]).
//   * lib/ui/home_page.dart — the receiver-IDENTITY dialog. That one genuinely
//     cannot be reconstructed, so no dialog is offered for an empty tally; the
//     tap explains that the list is rebuilt from live receipts instead of
//     asserting an empty audience ("No receivers yet" did assert exactly that).
//     Its title no longer claims a total either ("Receivers so far (N)").
//
// Both gaps this test used to record are CLOSED: tim2tox grew the receiver-side
// mirror (groupRowReceiveTally + _receiverTallyPartlyUnknown), so a row RECEIVED
// but never READ now restores a floor AND an inexactness marker, and a tally that
// started after a restart is never reported as exact even if an eviction leaves
// the two maps the same size. The badge consults BOTH tallies.
//
// [receiverBadge] is the single decision both surfaces route through, which is
// what this test drives: the surfaces themselves live inside the UIKit
// conversation builder and need a full logged-in session to render.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/home/group_receiver_badge.dart';

/// The read tally of a row nobody has ever read: an exact zero.
const _never = (readCount: 0, exactCount: true);

/// The read tally of a row read in a PREVIOUS session: a floor of 1, and the
/// live tally can never be complete again this session.
const _restored = (readCount: 1, exactCount: false);

void main() {
  group('receiverBadge', () {
    test('a tally built entirely this session keeps its exact count', () {
      final badge = receiverBadge((receiverCount: 3, exactCount: true), (readCount: 2, exactCount: true));
      expect(badge.show, isTrue);
      expect(
        badge.count,
        3,
        reason: 'every receipt behind this tally arrived while we were running, '
            'so the number is a count and not a floor — and the dialog can '
            'name exactly these 3',
      );
    });

    test('a row restored from disk shows the badge without a number', () {
      // THE REGRESSION. The tally starts empty on every launch, so this is what
      // a relaunched app sees for a message members did get.
      final badge = receiverBadge((receiverCount: 0, exactCount: true), _restored);
      expect(
        badge.show,
        isTrue,
        reason: 'the pre-fix gate was `receiverCount > 0`, which hid the badge '
            'here and so claimed nothing had been received',
      );
      expect(
        badge.count,
        isNull,
        reason: 'and the number must stay UNKNOWN: receiver identities are '
            'never persisted, so "1" would be fabricated precision — the same '
            'reason tim2tox reports unreadCount as null (0dc54c6)',
      );
    });

    test('a receipt arriving AFTER a restart does not restore precision', () {
      // codex review finding: the fix must not treat a rebuilt tally as exact.
      // A member receipted before the restart (hence the persisted floor) and
      // another receipts now, so the live tally holds 1 of 2 receivers.
      final badge = receiverBadge((receiverCount: 1, exactCount: false), _restored);
      expect(badge.show, isTrue);
      expect(
        badge.count,
        isNull,
        reason: 'showing 1 would under-report the member whose identity died '
            'with the restart; exactCount stays false for the session',
      );
    });

    test('a row RECEIVED but never read shows the badge without a number', () {
      // The gap this batch closed. Before the receiver-side mirror existed, such
      // a row restored neither a floor nor an inexactness marker: the badge
      // vanished for a message members really had got, and a single later
      // receipt made it claim an exact "1".
      final badge = receiverBadge(
        (receiverCount: 1, exactCount: false),
        (readCount: 0, exactCount: true),
      );
      expect(badge.show, isTrue,
          reason: 'members did receive it; hiding it reads as "nobody got this"');
      expect(badge.count, isNull,
          reason: 'the 1 is a floor restored from isReceived, not a count');
    });

    test('a receiver tally short of the read count is not a count', () {
      // codex review finding 2: the bridge caps _messageReceivers and
      // _messageReaders independently, so a receiver entry can be evicted and
      // then rebuilt by one fresh receipt while the reader entry (and therefore
      // exactCount) survives intact. Readers are a subset of receivers, so
      // tallied < readCount is proof on its own that entries were lost.
      final badge = receiverBadge((receiverCount: 1, exactCount: true), (readCount: 3, exactCount: true));
      expect(badge.show, isTrue);
      expect(
        badge.count,
        isNull,
        reason: '3 members read it, so "1 received" cannot be a count. The '
            'residual case — an eviction that leaves the two tallies the same '
            'size — is invisible from here and needs a receiver-side inexact '
            'marker in tim2tox, mirroring _readerTallyPartlyUnknown',
      );
    });

    test('an empty tally with no persisted receipt shows nothing', () {
      final badge = receiverBadge((receiverCount: 0, exactCount: true), _never);
      expect(badge.show, isFalse);
      expect(badge.count, isNull);
    });

    test('a known read can never be hidden, even with no receiver tally', () {
      // Defensive: readers are a subset of receivers, so this should not occur
      // — but a read row must never render as "nobody got it".
      expect(receiverBadge((receiverCount: 0, exactCount: true), (readCount: 1, exactCount: true)).show, isTrue);
    });
  });

  group('the surfaces route through receiverBadge', () {
    test('the count badge is not gated on the live tally alone', () async {
      final src = await File(
        'lib/ui/home_page_bootstrap.dart',
      ).readAsString();
      expect(
        src,
        isNot(contains('if (receiverCount > 0) {')),
        reason: 'gating the badge on the memory-only tally is the defect',
      );
      // Pinned on WHAT is called, not on how the argument is spelled: both
      // tallies must come from the service, which is the only thing that knows
      // whether a count is exact or a floor restored from the row's booleans.
      // The FakeUIKit wrapper can only report a bare number, and using it is
      // what made a restored row show nothing and then an exact-looking 1.
      expect(src, contains('widget.service.groupRowReadTally('),
          reason: 'the read floor and its exactness flag must come from the '
              'bridge');
      expect(src, contains('widget.service.groupRowReceiveTally('),
          reason: 'so must the receiver tally');
      expect(
        src,
        isNot(contains('getMessageReceiverCount(msgID)')),
        reason: 'the bare count carries no exactness, so it cannot be the '
            'badge\'s input',
      );
      expect(src, contains('if (badge.show) {'));
    });

    test('the identity dialog never claims an empty audience', () async {
      final src = await File('lib/ui/home_page.dart').readAsString();
      final start = src.indexOf('  Future<void> _showMessageReceiversDialog');
      expect(start, isNonNegative);
      final body = src.substring(start, src.indexOf('\n  }', start));
      expect(
        body,
        isNot(contains('noReceivers')),
        reason: '"No receivers yet" reads as "nobody received this", which is '
            'not what an empty tally means for a reloaded row',
      );
      expect(body, contains('messageReceiversNotStored'));
    });

    test('the dialog title does not promise a complete list', () async {
      final arb = await File('lib/l10n/app_en.arb').readAsString();
      expect(
        arb,
        contains('"messageReceivers": "Receivers so far ({count})"'),
        reason: 'the parenthesised number is the receipts tallied so far, not '
            'a total of the members who got the message',
      );
    });
  });
}
