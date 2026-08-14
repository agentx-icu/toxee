import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';

/// Receive-side `__revoke__:` target resolution.
///
/// The recall bug this pins: the control signal and the stored history row
/// routinely carry the SAME peer in DIFFERENT id shapes — the signal arrives
/// with the sender's 76-char Tox ID (public key + nospam + checksum) while
/// history was persisted under the 64-char public key, or under a `c2c_`
/// prefixed conversation id. An un-normalized `fromUserId ==` comparison then
/// selects no candidate at all, so the signal is swallowed and the recalled
/// message stays visible on the receiver forever.
///
/// These are behavioral assertions on the real resolution rules, not source
/// text checks, so a future refactor that silently drops the normalization
/// fails here instead of shipping.

/// 64-char Tox public key (what history rows are normalized to).
const _senderPublicKey =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

/// The same peer as a full 76-char Tox ID (public key + nospam + checksum),
/// which is the form an inbound control signal commonly carries.
const _senderToxId = '${_senderPublicKey}BBBBBBBB1111';

/// A different peer entirely — must never be matched.
const _otherPublicKey =
    'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';

ChatMessage _row({
  required String fromUserId,
  required String text,
  required String msgID,
  required int timestampMs,
}) => ChatMessage(
  text: text,
  fromUserId: fromUserId,
  isSelf: false,
  timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
  msgID: msgID,
);

void main() {
  group('Tim2ToxSdkPlatform.resolveRevokeTarget', () {
    const revokedText = 'please unsend this one';
    const sendTimeMs = 1700000000000;

    test('matches a history row stored under the 76-char Tox ID form', () {
      // Caller normalizes the signal's sender; the ROW is the mismatched shape.
      final target = Tim2ToxSdkPlatform.resolveRevokeTarget(
        recent: [
          _row(
            fromUserId: _senderToxId,
            text: revokedText,
            msgID: 'row-1',
            timestampMs: sendTimeMs,
          ),
        ],
        senderUid: _senderPublicKey,
        revokedTextPrefix: revokedText,
        revokedTextLen: revokedText.length,
        senderTimestampMs: sendTimeMs,
      );

      expect(
        target?.msgID,
        'row-1',
        reason:
            'Regression: the revoke matcher compared the signal sender to '
            'the raw history fromUserId. A 76-char Tox ID row never equals the '
            '64-char public key, so nothing was selected and the recalled '
            'message survived on the receiver.',
      );
    });

    test('matches a history row stored under a c2c_-prefixed id', () {
      final target = Tim2ToxSdkPlatform.resolveRevokeTarget(
        recent: [
          _row(
            fromUserId: 'c2c_$_senderPublicKey',
            text: revokedText,
            msgID: 'row-prefixed',
            timestampMs: sendTimeMs,
          ),
        ],
        senderUid: _senderPublicKey,
        revokedTextPrefix: revokedText,
        revokedTextLen: revokedText.length,
        senderTimestampMs: sendTimeMs,
      );

      expect(target?.msgID, 'row-prefixed');
    });

    test('legacy timestamp-window path also normalizes the sender', () {
      // No content key (older sender): sender + closest timestamp within 5s.
      final target = Tim2ToxSdkPlatform.resolveRevokeTarget(
        recent: [
          _row(
            fromUserId: _senderToxId,
            text: revokedText,
            msgID: 'legacy-row',
            timestampMs: sendTimeMs + 1200,
          ),
        ],
        senderUid: _senderPublicKey,
        senderTimestampMs: sendTimeMs,
      );

      expect(target?.msgID, 'legacy-row');
    });

    test('never matches a different peer whose text is identical', () {
      final target = Tim2ToxSdkPlatform.resolveRevokeTarget(
        recent: [
          _row(
            fromUserId: _otherPublicKey,
            text: revokedText,
            msgID: 'other-peer-row',
            timestampMs: sendTimeMs,
          ),
        ],
        senderUid: _senderPublicKey,
        revokedTextPrefix: revokedText,
        revokedTextLen: revokedText.length,
        senderTimestampMs: sendTimeMs,
      );

      expect(target, isNull);
    });

    test(
      'ambiguous duplicate text resolves to no target rather than a guess',
      () {
        // Two identical-text rows from the same sender, both far from the
        // sender's send time: deleting either could delete the wrong one, so the
        // contract is to delete nothing.
        final target = Tim2ToxSdkPlatform.resolveRevokeTarget(
          recent: [
            _row(
              fromUserId: _senderToxId,
              text: revokedText,
              msgID: 'dup-a',
              timestampMs: sendTimeMs + 30000,
            ),
            _row(
              fromUserId: _senderToxId,
              text: revokedText,
              msgID: 'dup-b',
              timestampMs: sendTimeMs + 60000,
            ),
          ],
          senderUid: _senderPublicKey,
          revokedTextPrefix: revokedText,
          revokedTextLen: revokedText.length,
          senderTimestampMs: sendTimeMs,
        );

        expect(target, isNull);
      },
    );

    test(
      'duplicate text is disambiguated by the clearly closest send time',
      () {
        final target = Tim2ToxSdkPlatform.resolveRevokeTarget(
          recent: [
            _row(
              fromUserId: _senderToxId,
              text: revokedText,
              msgID: 'dup-near',
              timestampMs: sendTimeMs + 200,
            ),
            _row(
              fromUserId: _senderToxId,
              text: revokedText,
              msgID: 'dup-far',
              timestampMs: sendTimeMs + 90000,
            ),
          ],
          senderUid: _senderPublicKey,
          revokedTextPrefix: revokedText,
          revokedTextLen: revokedText.length,
          senderTimestampMs: sendTimeMs,
        );

        expect(target?.msgID, 'dup-near');
      },
    );

    test('control-signal rows are never selected as a revoke target', () {
      final target = Tim2ToxSdkPlatform.resolveRevokeTarget(
        recent: [
          _row(
            fromUserId: _senderToxId,
            text: '__revoke__:{"msgID":"x"}',
            msgID: 'control-row',
            timestampMs: sendTimeMs,
          ),
        ],
        senderUid: _senderPublicKey,
        senderTimestampMs: sendTimeMs,
      );

      expect(target, isNull);
    });

    test('a row without a msgID is not selectable', () {
      final target = Tim2ToxSdkPlatform.resolveRevokeTarget(
        recent: [
          ChatMessage(
            text: revokedText,
            fromUserId: _senderToxId,
            isSelf: false,
            timestamp: DateTime.fromMillisecondsSinceEpoch(sendTimeMs),
          ),
        ],
        senderUid: _senderPublicKey,
        revokedTextPrefix: revokedText,
        revokedTextLen: revokedText.length,
        senderTimestampMs: sendTimeMs,
      );

      expect(target, isNull);
    });
  });
}
