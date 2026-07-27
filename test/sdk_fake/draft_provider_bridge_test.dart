import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import 'package:tim2tox_dart/interfaces/draft_preferences_service.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/sdk_fake/fake_msg_provider.dart';
import 'package:toxee/sdk_fake/fake_uikit_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FakeUIKit.instance.dispose();
    ChatMessageProviderRegistry.provider = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    ChatMessageProviderRegistry.provider = null;
    FakeUIKit.instance.dispose();
  });

  test(
    'draft bridge delegates to the live FFI owner and rejects same-prefix account mismatch',
    () async {
      const sharedPrefix = 'ABCDEF0123456789';
      final accountA = '$sharedPrefix${List.filled(60, 'A').join()}';
      final accountB = '$sharedPrefix${List.filled(60, 'B').join()}';
      const conversationID = 'c2c_friend';
      final ffi = _RecordingFfiChatService(accountA);
      addTearDown(ffi.dispose);
      final fakeProvider = FakeChatMessageProvider(ffiService: ffi);
      addTearDown(fakeProvider.dispose);
      final ChatDraftProvider bridge = fakeProvider;

      expect(accountA, hasLength(76));
      expect(accountB, hasLength(76));
      expect(accountA.substring(0, 16), accountB.substring(0, 16));
      expect(fakeProvider, isA<ChatDraftProviderOwnsConversationState>());
      expect(
        () => bridge.saveDraft(
          conversationID: conversationID,
          accountToxId: accountA.substring(0, 16),
          draft: 'must not use a short storage key',
        ),
        throwsArgumentError,
      );
      expect(
        () => bridge.saveDraft(
          conversationID: conversationID,
          accountToxId: accountB,
          draft: 'must not reach another same-prefix account',
        ),
        throwsStateError,
      );

      await bridge.saveDraft(
        conversationID: conversationID,
        accountToxId: accountA.substring(0, 64),
        draft: 'account A draft',
      );

      expect(
        await bridge.loadDraft(
          conversationID: conversationID,
          accountToxId: accountA,
        ),
        'account A draft',
      );
      expect(ffi.loadedConversationIDs, <String>[conversationID]);
      expect(ffi.savedDraftTexts, <String?>['account A draft']);

      await bridge.saveDraft(
        conversationID: conversationID,
        accountToxId: accountA,
        draft: '',
      );

      expect(
        await bridge.loadDraft(
          conversationID: conversationID,
          accountToxId: accountA,
        ),
        isNull,
      );
      expect(ffi.savedDraftTexts, <String?>['account A draft', '']);
    },
  );

  test('adopted fallback is fully disposed by FakeUIKit teardown', () async {
    final account = List<String>.filled(76, 'A').join();
    final ffi = _RecordingFfiChatService(account);
    addTearDown(ffi.dispose);
    final fallback = FakeChatMessageProvider(ffiService: ffi);
    final owned = FakeUIKit.instance.adoptOwnedMessageProvider(fallback);
    ChatMessageProviderRegistry.provider = owned;

    expect(FakeUIKit.instance.ensureOwnedMessageProvider(ffi), same(fallback));
    expect(ffi.progressController.hasListener, isTrue);
    expect(ffi.fileRequestsController.hasListener, isTrue);
    expect(ffi.avatarUpdatedController.hasListener, isTrue);

    final conversationDone = Completer<void>();
    final conversationSubscription = fallback
        .streamFor(userID: 'friend')
        .listen((_) {}, onDone: conversationDone.complete);
    addTearDown(conversationSubscription.cancel);

    FakeUIKit.instance.dispose();
    await conversationDone.future.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);

    expect(FakeUIKit.instance.messageProvider, isNull);
    expect(ChatMessageProviderRegistry.provider, isNull);
    expect(ffi.progressController.hasListener, isFalse);
    expect(ffi.fileRequestsController.hasListener, isFalse);
    expect(ffi.avatarUpdatedController.hasListener, isFalse);

    final nextSessionProvider = FakeUIKit.instance.ensureOwnedMessageProvider(
      ffi,
    );
    ChatMessageProviderRegistry.provider = nextSessionProvider;
    expect(nextSessionProvider, isNot(same(fallback)));
    expect(ChatMessageProviderRegistry.provider, same(nextSessionProvider));

    FakeUIKit.instance.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(ChatMessageProviderRegistry.provider, isNull);
    expect(ffi.progressController.hasListener, isFalse);
  });
}

typedef _ProgressEvent = ({
  int instanceId,
  String peerId,
  String? path,
  int received,
  int total,
  bool isSend,
  String? msgID,
});

typedef _FileRequest = ({
  String peerId,
  int fileNumber,
  int fileSize,
  String fileName,
  int? instanceId,
});

class _RecordingFfiChatService implements FfiChatService {
  _RecordingFfiChatService(this.accountToxId);

  final String accountToxId;
  final Map<String, ConversationDraft> _drafts = <String, ConversationDraft>{};
  final List<String> loadedConversationIDs = <String>[];
  final List<String?> savedDraftTexts = <String?>[];
  final StreamController<_ProgressEvent> progressController =
      StreamController<_ProgressEvent>.broadcast();
  final StreamController<_FileRequest> fileRequestsController =
      StreamController<_FileRequest>.broadcast();
  final StreamController<String> avatarUpdatedController =
      StreamController<String>.broadcast();

  @override
  Stream<_ProgressEvent> get progressUpdates => progressController.stream;

  @override
  Stream<_FileRequest> get fileRequests => fileRequestsController.stream;

  @override
  Stream<String> get avatarUpdated => avatarUpdatedController.stream;

  @override
  String? getSelfToxId() => accountToxId;

  @override
  Future<ConversationDraft?> loadConversationDraft(
    String conversationID,
  ) async {
    loadedConversationIDs.add(conversationID);
    return _drafts[conversationID];
  }

  @override
  Future<ConversationDraft> setConversationDraft({
    required String conversationID,
    String? draftText,
  }) async {
    savedDraftTexts.add(draftText);
    final draft = ConversationDraft(
      conversationID: conversationID,
      text: draftText ?? '',
      timestamp: 1,
    );
    if (draft.text.isEmpty) {
      _drafts.remove(conversationID);
    } else {
      _drafts[conversationID] = draft;
    }
    return draft;
  }

  @override
  Future<void> dispose() async {
    await progressController.close();
    await fileRequestsController.close();
    await avatarUpdatedController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
