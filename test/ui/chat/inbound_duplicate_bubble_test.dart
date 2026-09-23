// An inbound message reaches the UIKit list twice: once through the native
// callback (a real `msg_<inst>_<ns>_<seq>` id) and once through tim2tox's
// polling path (a `<millis>_<n>_<toxId>` id). The platform dedupes the POLL
// copy against what the list already holds, which only works when the
// callback copy lands first. When the poll copy wins that race, the callback
// copy used to be let through on its id alone and the user saw two bubbles.
//
// These tests pin the fork's fallback: a callback copy merges onto a poll
// copy of an INCOMING message, while two genuine messages — including the
// same text sent twice by us — never merge.

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/data/message/tencent_cloud_chat_message_data.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat_common.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';

const _peer =
    '0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF';

bool _ffiAvailable() {
  try {
    // Building a V2TimMessage reaches the SDK, which loads its native library
    // by name; point that at tim2tox's, the way the app does.
    setNativeLibraryName('tim2tox_ffi');
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

V2TimMessage _text({
  required String msgID,
  required String text,
  required bool isSelf,
  int timestamp = 1700000000,
}) {
  final message = V2TimMessage(
    msgID: msgID,
    userID: _peer,
    sender: isSelf ? 'me' : _peer,
    isSelf: isSelf,
    timestamp: timestamp,
    elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
    textElem: V2TimTextElem(text: text),
  );
  message.id = msgID;
  return message;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  late TencentCloudChatMessageData<TencentCloudChatMessageDataKeys> data;

  setUp(() {
    data = TencentCloudChatMessageData<TencentCloudChatMessageDataKeys>(
        TencentCloudChatMessageDataKeys.none);
  });

  test('the callback copy merges onto the poll copy of an inbound message', () {
    data.onReceiveNewMessage(
        _text(msgID: '1700000000000_1_$_peer', text: 'hi', isSelf: false));
    data.onReceiveNewMessage(
        _text(msgID: 'msg_0_1700000000000000_7', text: 'hi', isSelf: false));

    final list = data.getMessageList(key: _peer);
    expect(list, hasLength(1),
        reason: 'the same inbound message must render once');
    expect(list.single.msgID, 'msg_0_1700000000000000_7',
        reason: 'the row adopts the real id the callback carries');
  }, skip: skipReason);

  // A GROUP poll id carries a fourth `_<groupId>` segment; an id-shape check
  // that stops at the sender never matched it, so groups kept the duplicate.
  test('the callback copy merges onto the poll copy of a group message', () {
    const gid = 'tox_group_7';
    V2TimMessage groupText(String msgID) {
      final message = V2TimMessage(
        msgID: msgID,
        groupID: gid,
        sender: _peer,
        isSelf: false,
        timestamp: 1700000000,
        elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
        textElem: V2TimTextElem(text: 'hi all'),
      );
      message.id = msgID;
      return message;
    }

    data.onReceiveNewMessage(groupText('1700000000000_1_${_peer}_$gid'));
    data.onReceiveNewMessage(groupText('msg_0_1700000000000000_7'));

    final list = data.getMessageList(key: gid);
    expect(list, hasLength(1),
        reason: 'the same group message must render once');
    expect(list.single.msgID, 'msg_0_1700000000000000_7');
  }, skip: skipReason);

  // Two POLL copies are two genuine messages: the peer really did send the
  // same text twice. Only a callback copy may be merged onto a poll row.
  test('the same text sent by the peer twice stays two messages', () {
    data.onReceiveNewMessage(
        _text(msgID: '1700000000000_1_$_peer', text: 'ok', isSelf: false));
    data.onReceiveNewMessage(
        _text(msgID: '1700000001000_2_$_peer', text: 'ok', isSelf: false));

    expect(data.getMessageList(key: _peer), hasLength(2),
        reason: 'neither is the callback copy of the other');
  }, skip: skipReason);

  test('the same text sent by us twice stays two messages', () {
    data.onReceiveNewMessage(
        _text(msgID: 'msg_0_1700000000000000_1', text: 'ok', isSelf: true));
    data.onReceiveNewMessage(
        _text(msgID: 'msg_0_1700000000000000_2', text: 'ok', isSelf: true));

    expect(data.getMessageList(key: _peer), hasLength(2));
  }, skip: skipReason);

  test('two inbound messages with real ids stay two messages', () {
    data.onReceiveNewMessage(
        _text(msgID: 'msg_0_1700000000000000_1', text: 'ok', isSelf: false));
    data.onReceiveNewMessage(
        _text(msgID: 'msg_0_1700000000000000_2', text: 'ok', isSelf: false));

    expect(data.getMessageList(key: _peer), hasLength(2),
        reason: 'neither row is a poll copy, so nothing may be merged');
  }, skip: skipReason);

  test('a later inbound message is not merged onto an old poll copy', () {
    data.onReceiveNewMessage(_text(
        msgID: '1700000000000_1_$_peer',
        text: 'ok',
        isSelf: false,
        timestamp: 1700000000));
    data.onReceiveNewMessage(_text(
        msgID: 'msg_0_1700000000000000_9',
        text: 'ok',
        isSelf: false,
        timestamp: 1700000600)); // ten minutes later

    expect(data.getMessageList(key: _peer), hasLength(2),
        reason: 'the merge window is seconds, not minutes');
  }, skip: skipReason);
}
