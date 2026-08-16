// WHAT THE UI ACTUALLY DOES when the user confirms "delete for me".
//
// WHY THIS FILE EXISTS. The delete contract had been asserted only at the
// platform boundary (`test/tim2tox_sdk_failed_message_flow_test.dart` checked
// `V2TimCallback.code`). A return code is not a guarantee: the ONLY consumer of
// that code is the fork's `TencentCloudChatMessageSeparateDataProvider
// .deleteMessagesForMe`, whose entire reaction to a non-zero code is to SKIP
// the list strip — no toast, no dialog, no retry. So a change that made the
// platform "more honest" (non-zero when 0 rows were removed) passed every
// existing test while making the row PERMANENTLY UNDELETABLE with zero user
// feedback. These tests drive the real production method and assert the
// rendered message list, which is the thing the user sees.
//
// The list under `TencentCloudChat.instance.dataInstance.messageData` IS the
// rendered list: `TencentCloudChatMessageListView` reads it through
// `getMessageList`, and `deleteMessagesForMe` writes it back through
// `updateMessageList`. A default-constructed provider has no userID/groupID, so
// both sides resolve to the "" conversation key — the same round trip the real
// C2C provider performs against its own key.
//
// MOBILE PARITY: `deleteMessagesForMe` is shared fork Dart with no platform
// branch — the desktop menu container, the mobile long-press menu and the
// multi-select toolbar all call this one method — so these assertions cover
// iOS/Android exactly as they cover desktop.
//
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';

/// Minimal platform whose `deleteMessages` answers a scripted code, so each
/// test pins one arm of the contract the fork gates on.
class _DeleteSdkPlatform extends TencentCloudChatSdkPlatform {
  _DeleteSdkPlatform({required this.code});

  final int code;
  final List<List<String>?> requests = <List<String>?>[];

  /// Routes `V2TIMMessageManager.deleteMessages` through this platform instead
  /// of the native binary-replacement path.
  @override
  bool get isCustomPlatform => true;

  @override
  Future<V2TimCallback> deleteMessages({
    List<String>? msgIDs,
    List<dynamic>? webMessageInstanceList,
  }) async {
    requests.add(msgIDs);
    return V2TimCallback(
      code: code,
      desc: code == 0 ? 'success' : 'storage unavailable',
    );
  }
}

V2TimMessage _row({String? id, String? msgID, int timestamp = 1}) {
  final message = V2TimMessage(elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT);
  message.id = id;
  message.msgID = msgID;
  message.textElem = V2TimTextElem(text: 'row');
  message.timestamp = timestamp;
  return message;
}

List<V2TimMessage> _renderedList() =>
    TencentCloudChat.instance.dataInstance.messageData.getMessageList(key: '');

void _seed(List<V2TimMessage> rows) {
  TencentCloudChat.instance.dataInstance.messageData.messageListMap = {
    '': rows,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // `new V2TimMessage` reaches `TIMManager.getServerTime`, which dlopens the
  // native SDK. Point it at the tim2tox replacement, exactly as `main()` does
  // (lib/bootstrap/logging_bootstrap.dart), or every row construction below
  // dies on `libdart_native_imsdk.dylib` not existing.
  setNativeLibraryName('tim2tox_ffi');

  tearDown(() {
    TencentCloudChat.instance.dataInstance.messageData.messageListMap = {};
  });

  test('a normal delete removes the row from the rendered list', () async {
    TencentCloudChatSdkPlatform.instance = _DeleteSdkPlatform(code: 0);
    final target = _row(id: 'local-1', msgID: 'wire-1');
    final keep = _row(id: 'local-2', msgID: 'wire-2', timestamp: 2);
    _seed([target, keep]);

    await TencentCloudChatMessageSeparateDataProvider().deleteMessagesForMe(
      messages: [target],
    );

    expect(_renderedList().map((m) => m.msgID), ['wire-2']);
  });

  test(
    'an IDEMPOTENT re-delete still removes the row (the regression this file '
    'exists for)',
    () async {
      // The Tox platform answers `code: 0` for "already absent" precisely so
      // this second confirm is not a dead tap. If it ever answers non-zero
      // again, the row stays and the user has no way to remove it.
      TencentCloudChatSdkPlatform.instance = _DeleteSdkPlatform(code: 0);
      final target = _row(id: 'local-1', msgID: 'wire-1');
      _seed([target]);
      final provider = TencentCloudChatMessageSeparateDataProvider();

      await provider.deleteMessagesForMe(messages: [target]);
      expect(_renderedList(), isEmpty);

      // Second confirm against a list that still (stale-ly) holds the row.
      _seed([target]);
      await provider.deleteMessagesForMe(messages: [target]);
      expect(
        _renderedList(),
        isEmpty,
        reason:
            'a re-delete of an already-absent message must still strip the '
            'row; a non-zero "nothing was removed" code would make it '
            'permanently undeletable with no user-visible error',
      );
    },
  );

  test('a row with NEITHER a msgID nor an id is still removable', () async {
    // `deleteMessagesForMe` maps such a row to `""`, which matches nothing in
    // any store, so the platform legitimately removes 0. Both keyed strip
    // branches also demand a non-empty identifier, so before the `identical`
    // fallback this row could never leave the list at all — doubly stuck.
    TencentCloudChatSdkPlatform.instance = _DeleteSdkPlatform(code: 0);
    final target = _row();
    final keep = _row(id: 'local-2', msgID: 'wire-2', timestamp: 2);
    _seed([target, keep]);

    await TencentCloudChatMessageSeparateDataProvider().deleteMessagesForMe(
      messages: [target],
    );

    expect(_renderedList().length, 1);
    expect(_renderedList().single.msgID, 'wire-2');
  });

  test('two identifier-less rows: only the requested one is removed', () async {
    // Guards the `identical` fallback against over-matching: object identity
    // must not collapse two distinct rows that merely look alike.
    TencentCloudChatSdkPlatform.instance = _DeleteSdkPlatform(code: 0);
    final target = _row();
    final sibling = _row(timestamp: 2);
    _seed([target, sibling]);

    await TencentCloudChatMessageSeparateDataProvider().deleteMessagesForMe(
      messages: [target],
    );

    final rendered = _renderedList();
    expect(rendered.length, 1);
    expect(identical(rendered.single, sibling), isTrue);
  });

  test('a GENUINE failure keeps the row (the truthful UI state)', () async {
    // Non-zero now means "the delete could not be performed". The message
    // really is still stored, so showing it is honest and the user can retry.
    TencentCloudChatSdkPlatform.instance = _DeleteSdkPlatform(code: -1);
    final target = _row(id: 'local-1', msgID: 'wire-1');
    _seed([target]);

    await TencentCloudChatMessageSeparateDataProvider().deleteMessagesForMe(
      messages: [target],
    );

    expect(_renderedList().map((m) => m.msgID), ['wire-1']);
  });

  test('the fork identifies a msgID-less row by its local id', () async {
    final platform = _DeleteSdkPlatform(code: 0);
    TencentCloudChatSdkPlatform.instance = platform;
    final target = _row(id: 'local-only');
    _seed([target]);

    await TencentCloudChatMessageSeparateDataProvider().deleteMessagesForMe(
      messages: [target],
    );

    expect(
      platform.requests.single,
      ['local-only'],
      reason:
          'upstream sent `e.msgID ?? ""` down, so a failed/pending message was '
          'asked for by the empty string and matched nothing in any store',
    );
    expect(_renderedList(), isEmpty);
  });
}
