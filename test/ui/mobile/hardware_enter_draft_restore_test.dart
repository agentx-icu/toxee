// I3 (doc/reference/MOBILE_DEVICE_FEATURES.md): a hardware-Enter send that
// was taken out of the composer and then not sent goes back into the stored
// draft of ITS conversation when no composer for it is mounted — and a
// composer mounted meanwhile loads the draft only after that restore.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/tencent_cloud_chat_message_draft_coordinator.dart';

class _MemoryDrafts implements ChatDraftProvider {
  final Map<String, String> drafts = {};
  Completer<void>? loadGate;
  Completer<void>? saveGate;

  @override
  Future<String?> loadDraft({
    required String conversationID,
    required String accountToxId,
  }) async {
    await loadGate?.future;
    return drafts['$accountToxId/$conversationID'];
  }

  @override
  Future<void> saveDraft({
    required String conversationID,
    required String accountToxId,
    String? draft,
  }) async {
    await saveGate?.future;
    final key = '$accountToxId/$conversationID';
    if (draft == null) {
      drafts.remove(key);
    } else {
      drafts[key] = draft;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryDrafts provider;

  TencentCloudChatMessageDraftCoordinator coordinator(String userID) {
    return TencentCloudChatMessageDraftCoordinator(
      updateConversationPreview: (_, __) {},
      fallbackProvider: provider,
      registeredProvider: () => null,
    )..updateContext(userID: userID);
  }

  setUp(() {
    provider = _MemoryDrafts();
    final previous = TencentCloudChat.instance.dataInstance.basic.currentUser;
    TencentCloudChat.instance.dataInstance.basic
        .updateCurrentUserInfo(userFullInfo: V2TimUserFullInfo(userID: 'me'));
    addTearDown(() {
      if (previous != null) {
        TencentCloudChat.instance.dataInstance.basic
            .updateCurrentUserInfo(userFullInfo: previous);
      }
    });
  });

  test('the failed text goes in front of the stored draft', () async {
    provider.drafts['me/c2c_bob'] = 'typed since';
    final drafts = coordinator('bob');
    await drafts.restoreIntoDraft(drafts.identity, ['abc']);
    expect(provider.drafts['me/c2c_bob'], 'abc\ntyped since');
  });

  test('it goes to the conversation it was sent in, not the current one',
      () async {
    final drafts = coordinator('bob');
    final sentIn = drafts.identity;
    drafts.updateContext(userID: 'carol');
    await drafts.restoreIntoDraft(sentIn, ['for bob']);
    expect(provider.drafts['me/c2c_bob'], 'for bob');
    expect(provider.drafts.containsKey('me/c2c_carol'), isFalse);
  });

  test('a composer mounted meanwhile loads the draft after the restore',
      () async {
    provider.drafts['me/c2c_bob'] = 'D';
    provider.loadGate = Completer<void>();
    final disposed = coordinator('bob');
    final restoring = disposed.restoreIntoDraft(disposed.identity, ['abc']);

    final successor = coordinator('bob');
    final applied = <String>[];
    final loading = successor.loadDraft(
      initialText: '',
      currentText: () => '',
      isActive: () => true,
      applyText: applied.add,
    );
    provider.loadGate!.complete();
    await Future.wait([restoring, loading]);
    expect(applied, ['abc\nD']);
  });

  test('a composer mounted right after another loads that one\'s last save',
      () async {
    provider.drafts['me/c2c_bob'] = 'abc';
    provider.saveGate = Completer<void>();
    final disposed = coordinator('bob');
    disposed.saveDraft('h'); // typed after the Enter, save still running

    final successor = coordinator('bob');
    final applied = <String>[];
    final loading = successor.loadDraft(
      initialText: '',
      currentText: () => '',
      isActive: () => true,
      applyText: applied.add,
    );
    await pumpEventQueue();
    expect(applied, isEmpty, reason: 'waits for the other composer\'s save');
    provider.saveGate!.complete();
    await loading;
    expect(applied, ['h']);
  });
}
