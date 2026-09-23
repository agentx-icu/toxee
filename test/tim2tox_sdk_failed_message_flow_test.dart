import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/interfaces/draft_preferences_service.dart';
import 'package:tim2tox_dart/interfaces/extended_preferences_service.dart';
import 'package:tim2tox_dart/interfaces/logger_service.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/tim2tox_failed_message_persistence.dart';

const _account =
    'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
const _otherAccount =
    'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD';

V2TimMessage _v2TextMessage({
  required String id,
  required String msgID,
  required String text,
  required int timestamp,
}) {
  final message = V2TimMessage(elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT);
  message.id = id;
  message.msgID = msgID;
  message.textElem = V2TimTextElem(text: text);
  message.timestamp = timestamp;
  message.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
  return message;
}

class _ConfigurableProvider implements ChatMessageProvider {
  _ConfigurableProvider({required this.failTextSends});

  final bool failTextSends;
  final List<({String? userID, String? groupID, String text})> sentTexts = [];

  @override
  Stream<List<V2TimMessage>> streamFor({String? userID, String? groupID}) =>
      const Stream<List<V2TimMessage>>.empty();

  @override
  Future<void> sendText({
    String? userID,
    String? groupID,
    required String text,
  }) async {
    sentTexts.add((userID: userID, groupID: groupID, text: text));
    if (failTextSends) {
      throw StateError('synthetic send failure');
    }
  }

  @override
  Future<void> sendImage({
    String? userID,
    String? groupID,
    required String imagePath,
    String? imageName,
  }) async {
    throw StateError('unexpected image send');
  }

  @override
  Future<void> sendFile({
    String? userID,
    String? groupID,
    required String filePath,
    String? fileName,
  }) async {
    throw StateError('unexpected file send');
  }

  @override
  Future<void> deleteMessages({
    String? userID,
    String? groupID,
    required List<String> msgIDs,
  }) async {}
}

class _FakeFfiChatService implements FfiChatService {
  _FakeFfiChatService({
    List<ChatMessage> history = const [],
    this.throwOnAlternatingSelfIdReads = false,
    this.deletedCountOverride,
    this.throwOnDelete = false,
  }) {
    for (final message in history) {
      final conversationID = message.groupId ?? 'peer-a';
      _history.putIfAbsent(conversationID, () => []).add(message);
      _lastMessages[conversationID] = message;
    }
  }

  /// Forces the count `deleteMessages` reports, so a test can simulate the
  /// real no-op ("none of the requested msgIDs are in history"). Null keeps the
  /// optimistic default of "everything asked for was deleted".
  final int? deletedCountOverride;

  /// Simulates the delete not being PERFORMABLE (a history/persistence write
  /// that throws) — the one situation that must still surface a non-zero code.
  final bool throwOnDelete;

  final List<String> deletedIDs = <String>[];
  final List<({String peerId, String payload, bool isGroup})> controlSignals =
      <({String peerId, String payload, bool isGroup})>[];
  final bool throwOnAlternatingSelfIdReads;
  final Map<String, List<ChatMessage>> _history = <String, List<ChatMessage>>{};
  final Map<String, ChatMessage> _lastMessages = <String, ChatMessage>{};
  final StreamController<bool> _connection = StreamController<bool>.broadcast();
  final StreamController<ChatMessage> _messages =
      StreamController<ChatMessage>.broadcast();
  final StreamController<String> _avatar = StreamController<String>.broadcast();
  final StreamController<String> _nickname =
      StreamController<String>.broadcast();
  final StreamController<ConversationDraft> _conversationDraftChanges =
      StreamController<ConversationDraft>.broadcast();
  final StreamController<
    ({
      String msgID,
      String reactionID,
      String action,
      String sender,
      String? groupID,
    })
  >
  _reactions =
      StreamController<
        ({
          String msgID,
          String reactionID,
          String action,
          String sender,
          String? groupID,
        })
      >.broadcast();
  final StreamController<
    ({
      int instanceId,
      String peerId,
      String? path,
      int received,
      int total,
      bool isSend,
      String? msgID,
    })
  >
  _progress =
      StreamController<
        ({
          int instanceId,
          String peerId,
          String? path,
          int received,
          int total,
          bool isSend,
          String? msgID,
        })
      >.broadcast();
  bool _closed = false;
  int _selfIdReads = 0;

  @override
  String get selfId {
    _selfIdReads++;
    if (throwOnAlternatingSelfIdReads && _selfIdReads.isOdd) {
      throw StateError('synthetic outer send failure');
    }
    return _account.substring(0, 64);
  }

  @override
  String? getSelfToxId() => _account;

  @override
  ExtendedPreferencesService? get preferencesService => null;

  @override
  LoggerService? get logger => null;

  @override
  Stream<bool> get connectionStatusStream => _connection.stream;

  @override
  Stream<ChatMessage> get messages => _messages.stream;

  @override
  Stream<String> get avatarUpdated => _avatar.stream;

  @override
  Stream<String> get nicknameUpdated => _nickname.stream;

  @override
  Stream<ConversationDraft> get conversationDraftChanges =>
      _conversationDraftChanges.stream;

  @override
  Stream<
    ({
      String action,
      String? groupID,
      String msgID,
      String reactionID,
      String sender,
    })
  >
  get reactionEvents => _reactions.stream;

  @override
  Stream<({String msgID, String? groupID, int readCount})> get receiptEvents =>
      const Stream.empty();

  @override
  void armNextSendNeedReadReceipt(bool value) {
    // The platform's text dispatch arms/clears this around every send; the
    // failed-message flow doesn't assert receipt intent, so a no-op is fine.
  }

  @override
  Stream<
    ({
      int instanceId,
      bool isSend,
      String? msgID,
      String? path,
      String peerId,
      int received,
      int total,
    })
  >
  get progressUpdates => _progress.stream;

  @override
  Map<String, ChatMessage> get lastMessages => _lastMessages;

  @override
  List<ChatMessage> getHistory(String id) =>
      List<ChatMessage>.from(_history[id] ?? const <ChatMessage>[]);

  @override
  Future<int> deleteMessages(List<String> msgIDs) async {
    deletedIDs.addAll(msgIDs);
    if (throwOnDelete) {
      throw StateError('history store unavailable');
    }
    return deletedCountOverride ?? msgIDs.length;
  }

  @override
  Future<void> sendControlSignal(
    String peerId,
    String payload, {
    bool isGroup = false,
  }) async {
    controlSignals.add((peerId: peerId, payload: payload, isGroup: isGroup));
  }

  @override
  void armNextSendCloudCustomData(String? data) {}

  // getHistoryMessageListV2 consults the archive when a page reaches the
  // oldest in-memory row; this fake has no archive.
  @override
  Future<bool> hasArchivedHistory(String id) async => false;

  @override
  Future<List<ChatMessage>> getArchivedHistory(String id) async =>
      const <ChatMessage>[];

  @override
  Future<void> clearC2CHistory(String userID) async {
    _history.remove(userID);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await Future.wait<void>([
      _connection.close(),
      _messages.close(),
      _avatar.close(),
      _nickname.close(),
      _conversationDraftChanges.close(),
      _reactions.close(),
      _progress.close(),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Tim2ToxSdkPlatform _platformFor(_FakeFfiChatService service) {
  final platform = Tim2ToxSdkPlatform(ffiService: service);
  addTearDown(() async {
    platform.dispose();
    NativeLibraryManager.customCallbackHandler = null;
    await service.close();
  });
  return platform;
}

Future<List<Map<String, dynamic>>> _failedRows({
  String? userID,
  String? groupID,
  String? accountToxId = _account,
}) {
  return Tim2ToxFailedMessagePersistence.loadFailedMessages(
    userID: userID,
    groupID: groupID,
    accountToxId: accountToxId,
  );
}

/// The pre-account-scoping base key. Nothing writes it any more (a save
/// without an account is refused), so legacy rows are seeded directly.
const _legacyUnscopedKey = 'tencent_cloud_chat_failed_messages';

Future<void> _seedLegacyUnscopedRow({
  required String userID,
  required String id,
  required String msgID,
  required String text,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final store = <String, dynamic>{
    if (prefs.getString(_legacyUnscopedKey) case final String raw)
      ...(jsonDecode(raw) as Map<String, dynamic>),
  };
  final rows = <dynamic>[...?(store[userID] as List<dynamic>?)];
  rows.add(<String, dynamic>{
    'id': id,
    'msgID': msgID,
    'timestamp': 200,
    'elemType': MessageElemType.V2TIM_ELEM_TYPE_TEXT,
    'text': text,
    'userID': userID,
    'isSelf': true,
    'status': MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
  });
  store[userID] = rows;
  await prefs.setString(_legacyUnscopedKey, jsonEncode(store));
}

Future<List<dynamic>> _legacyUnscopedRows(String userID) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_legacyUnscopedKey);
  if (raw == null) return const [];
  return ((jsonDecode(raw) as Map<String, dynamic>)[userID] as List<dynamic>?) ??
      const [];
}

Future<void> _saveFailedForAccount({
  required V2TimMessage message,
  required String? accountToxId,
  String? userID,
  String? groupID,
}) {
  message.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
  return Tim2ToxFailedMessagePersistence.saveFailedMessage(
    message: message,
    userID: userID,
    groupID: groupID,
    accountToxId: accountToxId,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    setNativeLibraryName('tim2tox_ffi');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ChatMessageProviderRegistry.provider = null;
    TencentCloudChat.instance.dataInstance.messageData.messageListMap = {};
  });

  tearDown(() {
    ChatMessageProviderRegistry.provider = null;
    TencentCloudChat.instance.dataInstance.messageData.messageListMap = {};
    NativeLibraryManager.customCallbackHandler = null;
  });

  group('Tim2ToxSdkPlatform failed-message flow', () {
    test('inner send failure persists one finalized failed C2C row', () async {
      final service = _FakeFfiChatService();
      final platform = _platformFor(service);
      final message = _v2TextMessage(
        id: 'local-inner',
        msgID: 'wire-inner',
        text: 'inner failure',
        timestamp: 200,
      );
      TencentCloudChat.instance.dataInstance.messageData.messageListMap = {
        'peer-a': [message],
      };
      ChatMessageProviderRegistry.provider = _ConfigurableProvider(
        failTextSends: true,
      );

      final first = await platform.sendMessage(
        id: 'local-inner',
        receiver: 'peer-a',
        groupID: '',
      );
      final second = await platform.sendMessage(
        id: 'local-inner',
        receiver: 'peer-a',
        groupID: '',
      );

      final rows = await _failedRows(userID: 'peer-a');
      expect(first.code, -1);
      expect(second.code, -1);
      expect(rows, hasLength(1));
      expect(rows.single['id'], 'local-inner');
      expect(rows.single['msgID'], 'wire-inner');
      expect(rows.single['userID'], 'peer-a');
      expect(rows.single['groupID'], isNull);
      expect(rows.single['text'], 'inner failure');
      expect(rows.single['status'], MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL);
    });

    test(
      'explicit provider-unavailable failure persists a retry row',
      () async {
        final service = _FakeFfiChatService();
        final platform = _platformFor(service);
        final message = _v2TextMessage(
          id: 'local-no-provider',
          msgID: 'wire-no-provider',
          text: 'provider unavailable',
          timestamp: 201,
        );
        TencentCloudChat.instance.dataInstance.messageData.messageListMap = {
          'peer-a': [message],
        };
        ChatMessageProviderRegistry.provider = null;

        final result = await platform.sendMessage(
          id: 'local-no-provider',
          receiver: 'peer-a',
          groupID: '',
        );

        expect(result.code, -1);
        final rows = await _failedRows(userID: 'peer-a');
        expect(rows, hasLength(1));
        expect(rows.single['msgID'], 'wire-no-provider');
        expect(rows.single['text'], 'provider unavailable');
        expect(rows.single['status'], MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL);
      },
    );

    test(
      'outer send failure persists one finalized group-scoped row',
      () async {
        final service = _FakeFfiChatService(
          throwOnAlternatingSelfIdReads: true,
        );
        final platform = _platformFor(service);
        final message = _v2TextMessage(
          id: 'local-outer',
          msgID: 'wire-outer',
          text: 'outer failure',
          timestamp: 201,
        );
        TencentCloudChat.instance.dataInstance.messageData.messageListMap = {
          'tox_group_room': [message],
        };
        ChatMessageProviderRegistry.provider = _ConfigurableProvider(
          failTextSends: false,
        );

        final first = await platform.sendMessage(
          id: 'local-outer',
          receiver: 'peer-a',
          groupID: 'tox_group_room',
        );
        message.sender = null;
        final second = await platform.sendMessage(
          id: 'local-outer',
          receiver: 'peer-a',
          groupID: 'tox_group_room',
        );

        final rows = await _failedRows(groupID: 'tox_group_room');
        expect(first.code, -1);
        expect(second.code, -1);
        expect(rows, hasLength(1));
        expect(rows.single['id'], 'local-outer');
        expect(rows.single['msgID'], 'wire-outer');
        expect(rows.single['text'], 'outer failure');
        expect(rows.single['userID'], isNull);
        expect(rows.single['groupID'], 'tox_group_room');
        expect(rows.single['status'], MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL);
      },
    );

    test(
      'outer failure without id recovers the selected message payload',
      () async {
        final service = _FakeFfiChatService(
          throwOnAlternatingSelfIdReads: true,
        );
        final platform = _platformFor(service);
        final message = _v2TextMessage(
          id: 'local-no-id',
          msgID: 'wire-no-id',
          text: 'selected without id',
          timestamp: 202,
        )..isSelf = true;
        TencentCloudChat.instance.dataInstance.messageData.messageListMap = {
          'peer-a': [message],
        };
        ChatMessageProviderRegistry.provider = _ConfigurableProvider(
          failTextSends: false,
        );

        final result = await platform.sendMessage(
          receiver: 'peer-a',
          groupID: '',
        );

        expect(result.code, -1);
        final rows = await _failedRows(userID: 'peer-a');
        expect(rows, hasLength(1));
        expect(rows.single['id'], 'local-no-id');
        expect(rows.single['msgID'], 'wire-no-id');
        expect(rows.single['text'], 'selected without id');
      },
    );

    test(
      'restart reloads a failed row and successful resend removes it',
      () async {
        final failedService = _FakeFfiChatService();
        final failedPlatform = _platformFor(failedService);
        final message = _v2TextMessage(
          id: 'local-restart',
          msgID: 'wire-restart',
          text: 'retry after restart',
          timestamp: 202,
        );
        TencentCloudChat.instance.dataInstance.messageData.messageListMap = {
          'peer-a': [message],
        };
        ChatMessageProviderRegistry.provider = _ConfigurableProvider(
          failTextSends: true,
        );

        final failed = await failedPlatform.sendMessage(
          id: 'local-restart',
          receiver: 'peer-a',
          groupID: '',
        );
        expect(failed.code, -1);
        expect(await _failedRows(userID: 'peer-a'), hasLength(1));

        failedPlatform.dispose();
        await failedService.close();
        TencentCloudChat.instance.dataInstance.messageData.messageListMap = {};

        final resendProvider = _ConfigurableProvider(failTextSends: false);
        ChatMessageProviderRegistry.provider = resendProvider;
        final restartedService = _FakeFfiChatService();
        final restartedPlatform = _platformFor(restartedService);

        expect(await _failedRows(userID: 'peer-a'), hasLength(1));
        final resent = await restartedPlatform.reSendMessage(
          msgID: 'wire-restart',
        );

        expect(resent.code, 0);
        expect(resendProvider.sentTexts, [
          (userID: 'peer-a', groupID: null, text: 'retry after restart'),
        ]);
        expect(restartedService.deletedIDs, ['wire-restart']);
        expect(await _failedRows(userID: 'peer-a'), isEmpty);
      },
    );

    test('failed resend keeps the durable row for another restart', () async {
      final service = _FakeFfiChatService();
      final platform = _platformFor(service);
      await _saveFailedForAccount(
        message: _v2TextMessage(
          id: 'local-resend-fail',
          msgID: 'wire-resend-fail',
          text: 'retry remains durable',
          timestamp: 203,
        ),
        userID: 'peer-a',
        accountToxId: _account,
      );
      ChatMessageProviderRegistry.provider = null;

      final result = await platform.reSendMessage(msgID: 'wire-resend-fail');

      expect(result.code, -1);
      expect(service.deletedIDs, ['wire-resend-fail']);
      final rows = await _failedRows(userID: 'peer-a');
      expect(rows, hasLength(1));
      expect(rows.single['msgID'], 'wire-resend-fail');
    });

    test(
      'resend by local id preserves wire msgID through failure and success',
      () async {
        final service = _FakeFfiChatService();
        final platform = _platformFor(service);
        await _saveFailedForAccount(
          message: _v2TextMessage(
            id: 'local-distinct',
            msgID: 'wire-distinct',
            text: 'distinct identifiers',
            timestamp: 204,
          ),
          userID: 'peer-a',
          accountToxId: _account,
        );
        ChatMessageProviderRegistry.provider = _ConfigurableProvider(
          failTextSends: true,
        );

        final failed = await platform.reSendMessage(msgID: 'local-distinct');

        expect(failed.code, -1);
        expect(failed.data?.id, 'local-distinct');
        expect(failed.data?.msgID, 'wire-distinct');
        expect(service.deletedIDs, ['wire-distinct']);
        final retainedRows = await _failedRows(userID: 'peer-a');
        expect(retainedRows, hasLength(1));
        expect(retainedRows.single['id'], 'local-distinct');
        expect(retainedRows.single['msgID'], 'wire-distinct');

        final provider = _ConfigurableProvider(failTextSends: false);
        ChatMessageProviderRegistry.provider = provider;
        final succeeded = await platform.reSendMessage(msgID: 'local-distinct');

        expect(succeeded.code, 0);
        expect(succeeded.data?.id, 'local-distinct');
        expect(succeeded.data?.msgID, 'wire-distinct');
        expect(service.deletedIDs, ['wire-distinct', 'wire-distinct']);
        expect(provider.sentTexts, [
          (userID: 'peer-a', groupID: null, text: 'distinct identifiers'),
        ]);
        expect(await _failedRows(userID: 'peer-a'), isEmpty);
      },
    );

    // Pre #5 / #2: rows under the pre-scoping base key carry no owner. Any
    // account used to import them, show them and resend them AS ITSELF. They
    // are now invisible to every account and left untouched on disk.
    test('a legacy unscoped failed row is never resent by an account',
        () async {
      final service = _FakeFfiChatService();
      final platform = _platformFor(service);
      await _seedLegacyUnscopedRow(
        userID: 'peer-a',
        id: 'legacy-local-resend',
        msgID: 'legacy-wire-resend',
        text: 'legacy retry',
      );

      final provider = _ConfigurableProvider(failTextSends: false);
      ChatMessageProviderRegistry.provider = provider;
      final result = await platform.reSendMessage(msgID: 'legacy-wire-resend');

      expect(result.code, -1);
      expect(result.desc, contains('not found'));
      expect(provider.sentTexts, isEmpty);
      expect(service.deletedIDs, isEmpty);
      expect(await _failedRows(userID: 'peer-a'), isEmpty);
      expect(await _legacyUnscopedRows('peer-a'), hasLength(1));
    });

    test('an unscoped read or write never touches the legacy base key',
        () async {
      await _seedLegacyUnscopedRow(
        userID: 'peer-a',
        id: 'legacy-local',
        msgID: 'legacy-wire',
        text: 'someone else',
      );
      expect(await _failedRows(userID: 'peer-a', accountToxId: null), isEmpty);
      expect(
        await Tim2ToxFailedMessagePersistence.findFailedMessageByID(
          messageID: 'legacy-wire',
          accountToxId: _account,
        ),
        isNull,
      );
      await _saveFailedForAccount(
        message: _v2TextMessage(
          id: 'no-owner',
          msgID: 'no-owner',
          text: 'no account',
          timestamp: 1,
        ),
        userID: 'peer-a',
        accountToxId: null,
      );
      expect(
        await Tim2ToxFailedMessagePersistence.removeFailedMessagesByIDs(
          messageIDs: {'legacy-wire'},
          accountToxId: null,
        ),
        0,
      );
      final legacy = await _legacyUnscopedRows('peer-a');
      expect(legacy, hasLength(1));
      expect((legacy.single as Map)['msgID'], 'legacy-wire');
    });

    test(
      'deleteMessages removes only current-account failed rows by id',
      () async {
        final service = _FakeFfiChatService();
        final platform = _platformFor(service);
        await _saveFailedForAccount(
          message: _v2TextMessage(
            id: 'local-delete',
            msgID: 'wire-delete',
            text: 'delete me',
            timestamp: 203,
          ),
          userID: 'peer-a',
          accountToxId: _account,
        );
        await _saveFailedForAccount(
          message: _v2TextMessage(
            id: 'other-local-delete',
            msgID: 'local-delete',
            text: 'keep other account',
            timestamp: 204,
          ),
          userID: 'peer-a',
          accountToxId: _otherAccount,
        );
        await _seedLegacyUnscopedRow(
          userID: 'peer-a',
          id: 'legacy-base-delete',
          msgID: 'local-delete',
          text: 'unowned legacy row',
        );

        final result = await platform.deleteMessages(msgIDs: ['local-delete']);

        expect(result.code, 0, reason: result.desc);
        expect(service.deletedIDs, ['local-delete']);
        expect(await _failedRows(userID: 'peer-a'), isEmpty);
        // The unowned base key is not this account's to mutate.
        expect(await _legacyUnscopedRows('peer-a'), hasLength(1));
        expect(
          await _failedRows(userID: 'peer-a', accountToxId: _otherAccount),
          hasLength(1),
        );
      },
    );

    test(
      'revokeMessage removes only the current-account matching failed row',
      () async {
        final historyMessage = ChatMessage(
          text: 'revoke me',
          fromUserId: _account.substring(0, 64),
          isSelf: true,
          timestamp: DateTime.now().subtract(const Duration(seconds: 10)),
          msgID: 'wire-revoke',
        );
        final service = _FakeFfiChatService(history: [historyMessage]);
        final platform = _platformFor(service);
        await _saveFailedForAccount(
          message: _v2TextMessage(
            id: 'local-revoke',
            msgID: 'wire-revoke',
            text: 'revoke me',
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ),
          userID: 'peer-a',
          accountToxId: _account,
        );
        await _saveFailedForAccount(
          message: _v2TextMessage(
            id: 'other-local-revoke',
            msgID: 'wire-revoke',
            text: 'keep other revoke',
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ),
          userID: 'peer-a',
          accountToxId: _otherAccount,
        );
        await _seedLegacyUnscopedRow(
          userID: 'peer-a',
          id: 'legacy-base-revoke',
          msgID: 'wire-revoke',
          text: 'unowned legacy revoke',
        );

        final result = await platform.revokeMessage(msgID: 'wire-revoke');

        expect(result.code, 0, reason: result.desc);
        expect(service.deletedIDs, ['wire-revoke']);
        expect(await _failedRows(userID: 'peer-a'), isEmpty);
        // The unowned base key is not this account's to mutate.
        expect(await _legacyUnscopedRows('peer-a'), hasLength(1));
        expect(
          await _failedRows(userID: 'peer-a', accountToxId: _otherAccount),
          hasLength(1),
        );
        expect(service.controlSignals, isNotEmpty);
        final payload = service.controlSignals.single.payload;
        expect(
          jsonDecode(payload.substring('__revoke__:'.length)),
          containsPair('msgID', 'wire-revoke'),
        );
      },
    );
  });

  // CONTRACT: "delete for me" is IDEMPOTENT. `code == 0` means "none of the
  // requested messages is in a local store any more", NOT "this call is the one
  // that removed them".
  //
  // TWO regressions are pinned here, in opposite directions:
  //  (1) the original bug — `code: 0, desc: 'success'` answered blindly, so a
  //      genuine storage FAILURE was reported as a success and the UI stripped
  //      a row that is still on disk;
  //  (2) the 2026-08-16 over-correction — non-zero when 0 messages were removed.
  //      The only consumer of that code is the fork's `deleteMessagesForMe`,
  //      which reacts by SKIPPING the list strip and nothing else, so an
  //      idempotent re-delete (or a row the fork can only identify as `""`)
  //      made the message permanently undeletable with no user feedback at all.
  //
  // The UI-visible half of this contract is asserted in
  // test/ui/chat/message_delete_for_me_real_ui_test.dart, which drives the real
  // fork provider and checks the rendered message list — a return code nobody
  // acts on is not a guarantee.
  group('Tim2ToxSdkPlatform deleteMessages idempotence', () {
    test(
      'deleting 0 of N is SUCCESS — the messages are already absent',
      () async {
        final service = _FakeFfiChatService(deletedCountOverride: 0);
        final platform = _platformFor(service);

        final result = await platform.deleteMessages(
          msgIDs: ['wire-absent-1', 'wire-absent-2'],
        );

        // Success, because the caller's post-condition ("not in my history")
        // holds. Non-zero here made the row undeletable forever.
        expect(result.code, 0, reason: result.desc);
        // The no-op is still DIAGNOSABLE — the count is reported, not discarded.
        expect(result.desc, contains('already absent'));
        expect(result.desc, contains('0 of 2'));
        // The attempt still reached the service — not a short circuit.
        expect(service.deletedIDs, ['wire-absent-1', 'wire-absent-2']);
      },
    );

    test(
      'an empty request is SUCCESS, not an error code nobody renders',
      () async {
        final service = _FakeFfiChatService(deletedCountOverride: 0);
        final platform = _platformFor(service);

        final result = await platform.deleteMessages(msgIDs: const []);

        expect(result.code, 0, reason: result.desc);
        expect(service.deletedIDs, isEmpty);
      },
    );

    test('a genuine storage failure is the ONLY non-zero code', () async {
      final service = _FakeFfiChatService(throwOnDelete: true);
      final platform = _platformFor(service);

      final result = await platform.deleteMessages(msgIDs: ['wire-present']);

      // Keeping the row on screen is the truthful state here: the message
      // really is still stored, and the user can retry.
      expect(result.code, isNot(0));
      expect(result.desc, contains('deleteMessages failed'));
    });

    test('reports success when history rows were removed', () async {
      final service = _FakeFfiChatService();
      final platform = _platformFor(service);

      final result = await platform.deleteMessages(msgIDs: ['wire-present']);

      expect(result.code, 0, reason: result.desc);
      expect(result.desc, 'success');
    });

    test(
      'reports success when ONLY a failed-message row was removed',
      () async {
        // A never-sent message lives solely in the failed-message store, so the
        // history count is legitimately 0.
        final service = _FakeFfiChatService(deletedCountOverride: 0);
        final platform = _platformFor(service);
        await _saveFailedForAccount(
          message: _v2TextMessage(
            id: 'local-failed',
            msgID: 'wire-failed',
            text: 'never sent',
            timestamp: 900,
          ),
          accountToxId: _account,
          userID: 'peer-a',
        );
        expect(await _failedRows(userID: 'peer-a'), hasLength(1));

        final result = await platform.deleteMessages(msgIDs: ['wire-failed']);

        expect(result.code, 0, reason: result.desc);
        expect(result.desc, 'success');
        expect(await _failedRows(userID: 'peer-a'), isEmpty);
      },
    );
  });

  group('GF-5 group media refusal + failed rows in history', () {
    ChatMessage historyRow(String msgID, int seconds) => ChatMessage(
          text: 'h$seconds',
          fromUserId: 'peer-a',
          isSelf: false,
          timestamp: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
          msgID: msgID,
        );

    V2TimMessage imageMessage(String id, int timestamp) {
      final message =
          V2TimMessage(elemType: MessageElemType.V2TIM_ELEM_TYPE_IMAGE);
      message.id = id;
      message.msgID = id;
      message.imageElem = V2TimImageElem(path: '/tmp/$id.png');
      message.timestamp = timestamp;
      message.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
      return message;
    }

    test('a pure media send into a group is refused and NOT persisted',
        () async {
      final service = _FakeFfiChatService();
      final platform = _platformFor(service);
      final message = imageMessage('local-group-img', 500);
      TencentCloudChat.instance.dataInstance.messageData.messageListMap = {
        'tox_group_1': [message],
      };
      // The provider throws on any image send: reaching it would persist a
      // failed row through the exception path.
      ChatMessageProviderRegistry.provider = _ConfigurableProvider(
        failTextSends: false,
      );

      final result = await platform.sendMessage(
        id: 'local-group-img',
        receiver: '',
        groupID: 'tox_group_1',
      );

      expect(result.code, -1);
      expect(result.desc.toLowerCase(), contains('group'));
      expect(result.desc.toLowerCase(), contains('file'));
      expect(result.data?.status, MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL);
      expect(result.data?.id, 'local-group-img');
      expect(await _failedRows(groupID: 'tox_group_1'), isEmpty);
    });

    test('a legacy failed group-media row is refused on resend, row kept',
        () async {
      final service = _FakeFfiChatService();
      final platform = _platformFor(service);
      await _saveFailedForAccount(
        message: imageMessage('legacy-group-img', 510),
        accountToxId: _account,
        groupID: 'tox_group_1',
      );

      final result = await platform.reSendMessage(msgID: 'legacy-group-img');

      expect(result.code, -1);
      expect(result.desc.toLowerCase(), contains('group'));
      expect(service.deletedIDs, isEmpty,
          reason: 'refused before the pre-resend history cleanup');
      expect(await _failedRows(groupID: 'tox_group_1'), hasLength(1));
    });

    test(
        'failed rows missing from history come back in getHistoryMessageListV2 '
        'with their media element; rows present in history turn SEND_FAIL',
        () async {
      final service = _FakeFfiChatService(history: [
        historyRow('h100', 100),
        historyRow('h300', 300),
      ]);
      final platform = _platformFor(service);
      final image = imageMessage('failed-img', 200)..userID = 'peer-a';
      await _saveFailedForAccount(
        message: image,
        accountToxId: _account,
        userID: 'peer-a',
      );
      await _saveFailedForAccount(
        message: _v2TextMessage(
          id: 'failed-text',
          msgID: 'failed-text',
          text: 'newest failed',
          timestamp: 400,
        ),
        accountToxId: _account,
        userID: 'peer-a',
      );
      // A row that IS in history but is persisted as failed.
      await _saveFailedForAccount(
        message: _v2TextMessage(
          id: 'h300',
          msgID: 'h300',
          text: 'h300',
          timestamp: 300,
        ),
        accountToxId: _account,
        userID: 'peer-a',
      );

      final res = await platform.getHistoryMessageListV2(
        userID: 'peer-a',
        count: 20,
      );

      expect(res.code, 0, reason: res.desc);
      final list = res.data!.messageList;
      expect(list.map((m) => m.msgID).toList(),
          ['failed-text', 'h300', 'failed-img', 'h100']);
      final restoredImage = list[2];
      expect(restoredImage.elemType, MessageElemType.V2TIM_ELEM_TYPE_IMAGE);
      expect(restoredImage.imageElem?.path, '/tmp/failed-img.png');
      expect(restoredImage.status, MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL);
      expect(list[0].status, MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL);
      expect(list[1].status, MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL);
      expect(list[3].status, isNot(MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL));
    });

    test('a failed row lands on the page whose window holds it, never as a '
        'page anchor', () async {
      final service = _FakeFfiChatService(history: [
        historyRow('h100', 100),
        historyRow('h200', 200),
        historyRow('h300', 300),
        historyRow('h400', 400),
      ]);
      final platform = _platformFor(service);
      for (final (id, ts) in [('f350', 350), ('f250', 250), ('f50', 50)]) {
        await _saveFailedForAccount(
          message: _v2TextMessage(id: id, msgID: id, text: id, timestamp: ts),
          accountToxId: _account,
          userID: 'peer-a',
        );
      }

      final first = await platform.getHistoryMessageListV2(
        userID: 'peer-a',
        count: 2,
      );
      expect(first.data!.isFinished, isFalse);
      expect(first.data!.messageList.map((m) => m.msgID).toList(),
          ['h400', 'f350', 'h300']);

      final second = await platform.getHistoryMessageListV2(
        userID: 'peer-a',
        count: 2,
        lastMsgID: 'h300',
      );
      expect(second.data!.isFinished, isTrue);
      expect(second.data!.messageList.map((m) => m.msgID).toList(),
          ['f250', 'h200', 'h100', 'f50']);
    });

    test('clearing C2C history also drops its failed rows', () async {
      final service = _FakeFfiChatService();
      final platform = _platformFor(service);
      await _saveFailedForAccount(
        message: _v2TextMessage(
          id: 'to-clear',
          msgID: 'to-clear',
          text: 'x',
          timestamp: 10,
        ),
        accountToxId: _account,
        userID: 'peer-a',
      );

      final res = await platform.clearC2CHistoryMessage(userID: 'peer-a');

      expect(res.code, 0, reason: res.desc);
      expect(await _failedRows(userID: 'peer-a'), isEmpty);
    });
  });
}
