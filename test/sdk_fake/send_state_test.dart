// Our own message's send state, as the fake layer hands it to UIKit.
//
// Tim2Tox keeps it on the row: a send still queued is pending (also after a
// restart), a failed one is isFailed, a cancelled one isCancelled. The fake
// layer used to guess instead: any pending row older than 10 s rendered as
// SEND_FAIL, so a text queued for an offline peer showed a Retry button
// while it was still going to be sent.

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:toxee/sdk_fake/fake_models.dart';
import 'package:toxee/sdk_fake/send_state.dart';

// fromJson: the plain constructor asks the native SDK for the server time.
V2TimMessage _blank() => V2TimMessage.fromJson(<String, dynamic>{});

int? _status({
  bool isCancelled = false,
  bool isPending = false,
  bool isFailed = false,
}) {
  final msg = _blank();
  final applied = applyOwnSendState(
    msg,
    isCancelled: isCancelled,
    isPending: isPending,
    isFailed: isFailed,
  );
  return applied ? msg.status : null;
}

void main() {
  test('a queued send is SENDING however long it waits', () {
    expect(_status(isPending: true), MessageStatus.V2TIM_MSG_STATUS_SENDING);
  });

  test('a failed send is SEND_FAIL', () {
    expect(_status(isFailed: true), MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL);
  });

  test('a cancelled send is LOCAL_REVOKED with the Tim2Tox marker', () {
    final msg = _blank()..localCustomData = '{"toxGroupMsgId":5}';
    expect(
      applyOwnSendState(
        msg,
        isCancelled: true,
        isPending: true,
        isFailed: true,
      ),
      isTrue,
    );
    expect(msg.status, MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED);
    expect(queuedCancelledFromLocalCustomData(msg.localCustomData), isTrue);
    expect(toxGroupMsgIdFromLocalCustomData(msg.localCustomData), 5);
  });

  test('a message that went out is left to its receipts', () {
    expect(_status(), isNull);
  });

  test('FakeMessage carries the send state both ways', () {
    final row = ChatMessage(
      text: 'hi',
      fromUserId: 'me',
      isSelf: true,
      timestamp: DateTime.fromMillisecondsSinceEpoch(5000),
      msgID: 'm1',
      isFailed: true,
      isReceived: true,
    );
    final fake = FakeMessage.fromChat(row, conversationID: 'c2c_peer');
    expect(fake.isFailed, isTrue);
    expect(fake.isReceived, isTrue);
    expect(
      FakeMessage.fromChat(
        row,
        conversationID: 'c2c_peer',
        withReceipts: false,
      ).isReceived,
      isFalse,
    );
    final cancelled = FakeMessage.fromChat(
      ChatMessage(
        text: 'x',
        fromUserId: 'me',
        isSelf: true,
        timestamp: DateTime.fromMillisecondsSinceEpoch(6000),
        msgID: 'm2',
        isCancelled: true,
      ),
      conversationID: 'c2c_peer',
    );
    final back = cancelled.toChat(isSelf: true);
    expect(back.isCancelled, isTrue);
    expect(back.msgID, 'm2');
  });
}
