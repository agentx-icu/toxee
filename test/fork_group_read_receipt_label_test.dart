import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/utils/group_read_receipt_label.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';

/// The fork's long-press read-receipt label must not turn a FLOOR into a count.
///
/// A group message's read state survives a restart as a boolean only — reader
/// identities are deliberately never persisted, because each member's per-group
/// public key rotates and a stored reader set would de-anonymize who read what
/// across restarts (tim2tox 0dc54c6). `getMessageReadReceipts` therefore reports
/// `readCount` as a lower bound of 1 and `unreadCount` as **null** for such a
/// row, and the fork used to render that as `memberReadCount(1)` — "1 member
/// read" for a message two members had read before the restart.
///
/// `unreadCount == null` is the signal: the bridge could not derive
/// "members - 1 - readCount", so no exact member count can be established from
/// that receipt. These tests pin both renderings, and that `isAllRead` (which
/// requires an exact `unreadCount == 0`) still wins when it is set.
///
/// This lives under toxee's `test/` rather than in the fork package because
/// toxee's `flutter test` is the gate CI actually runs; the fork's own package
/// tests are never executed by `.github/workflows/analyze.yml`.
void main() {
  TencentCloudChatLocalizations en() =>
      lookupTencentCloudChatLocalizations(const Locale('en'));

  TencentCloudChatLocalizations zhHant() => lookupTencentCloudChatLocalizations(
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  );

  String label(
    TencentCloudChatLocalizations l10n, {
    required int? readCount,
    required int? unreadCount,
    bool isAllRead = false,
  }) => groupReadReceiptMenuLabel(
    l10n: l10n,
    isAllRead: isAllRead,
    readCount: readCount,
    unreadCount: unreadCount,
  );

  group('exact count (live receipt with member math)', () {
    test('renders the definite count', () {
      expect(
        label(en(), readCount: 1, unreadCount: 2),
        en().memberReadCount(1),
      );
      expect(
        label(en(), readCount: 3, unreadCount: 1),
        en().memberReadCount(3),
      );
      expect(label(en(), readCount: 1, unreadCount: 2), '1 member read');
      expect(label(en(), readCount: 3, unreadCount: 1), '3 members read');
    });

    test('an exact zero stays "no member read"', () {
      expect(label(en(), readCount: 0, unreadCount: 4), 'No member read');
    });

    test('a receipt with no counts at all stays exact', () {
      expect(label(en(), readCount: null, unreadCount: 3), 'No member read');
    });
  });

  group('unknown count (restored read state: unreadCount == null)', () {
    test('renders the count as a lower bound, never as a definite number', () {
      expect(
        label(en(), readCount: 1, unreadCount: null),
        en().memberReadCountAtLeast(1),
      );
      expect(label(en(), readCount: 1, unreadCount: null), 'At least 1 member read');
      expect(
        label(en(), readCount: 3, unreadCount: null),
        'At least 3 members read',
      );
      // The whole point: the restored floor of 1 must not read like an exact 1.
      expect(
        label(en(), readCount: 1, unreadCount: null),
        isNot(label(en(), readCount: 1, unreadCount: 2)),
      );
    });

    test('a zero read count is still exact — only membership was unknown', () {
      // groupRowReadTally reports an exact 0 when nothing was restored; the null
      // unread there means the member-list lookup failed, not that readers are
      // unaccounted for. "At least 0 members read" would be nonsense.
      expect(label(en(), readCount: 0, unreadCount: null), 'No member read');
      expect(label(en(), readCount: null, unreadCount: null), 'No member read');
    });

    test('is localized, not English-only', () {
      expect(
        label(zhHant(), readCount: 2, unreadCount: null),
        zhHant().memberReadCountAtLeast(2),
      );
      expect(label(zhHant(), readCount: 2, unreadCount: null), '至少 2 位成員已讀');
      expect(label(zhHant(), readCount: 2, unreadCount: 1), '2 位成員已讀');
    });
  });

  group('all read', () {
    test('takes precedence over both count renderings', () {
      expect(
        label(en(), readCount: 4, unreadCount: 0, isAllRead: true),
        'All members read',
      );
    });

    test('an unknown count can never produce it', () {
      // isAllRead is the caller's (exact `unreadCount == 0`) decision; a null
      // unread count must not let the label claim everyone read.
      expect(
        label(en(), readCount: 9, unreadCount: null),
        isNot('All members read'),
      );
    });

    test('still wins over the lower-bound branch if a caller forces it', () {
      // The menu container cannot produce isAllRead with a null unreadCount
      // (line 352 requires `unreadCount == 0`), but pin the precedence anyway so
      // a future caller cannot end up with two competing claims.
      expect(
        label(en(), readCount: 2, unreadCount: null, isAllRead: true),
        'All members read',
      );
    });
  });
}
