import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_file_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:toxee/sdk_fake/fake_models.dart';
import 'package:toxee/sdk_fake/fake_im.dart';
import 'package:toxee/sdk_fake/fake_msg_provider.dart';
import 'package:toxee/sdk_fake/fake_uikit_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    setNativeLibraryName('tim2tox_ffi');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('stale in-flight history cannot overwrite a newer existing-row update',
      () async {
    const peerID = 'peer';
    const conversationID = 'c2c_$peerID';
    const messageID = 'same-message';
    const livePath = '/live/newer.bin';
    const stalePath = '/history/stale.bin';
    final loaderStarted = Completer<void>();
    final staleHistory = Completer<List<FakeMessage>>();
    final provider = FakeChatMessageProvider(
      historyLoader: (conversationID) {
        if (!loaderStarted.isCompleted) {
          loaderStarted.complete();
        }
        return staleHistory.future;
      },
    );
    addTearDown(provider.dispose);

    V2TimMessage fileMessage(String path, int status) {
      final message = V2TimMessage(
        elemType: MessageElemType.V2TIM_ELEM_TYPE_FILE,
      );
      message
        ..msgID = messageID
        ..userID = peerID
        ..timestamp = 1
        ..status = status
        ..fileElem = V2TimFileElem(
          path: path,
          fileName: 'payload.bin',
          localUrl: path,
        );
      return message;
    }

    provider.updateMessageInBuffer(
      fileMessage('/seed/original.bin', MessageStatus.V2TIM_MSG_STATUS_SENDING),
      userID: peerID,
    );

    final emissions = <List<V2TimMessage>>[];
    final liveEmission = Completer<void>();
    final subscription = provider.streamFor(userID: peerID).listen((messages) {
      emissions.add(messages);
      if (!liveEmission.isCompleted &&
          messages.single.fileElem?.path == livePath) {
        liveEmission.complete();
      }
    });
    addTearDown(subscription.cancel);

    final reloadCompletion = provider.debugHistoryReloadCompletion(
      conversationID,
    );
    expect(reloadCompletion, isNotNull);
    await loaderStarted.future;
    provider.updateMessageInBuffer(
      fileMessage(livePath, MessageStatus.V2TIM_MSG_STATUS_SENDING),
      userID: peerID,
    );
    await liveEmission.future;

    staleHistory.complete(<FakeMessage>[
      FakeMessage(
        msgID: messageID,
        conversationID: conversationID,
        fromUser: peerID,
        text: 'payload.bin',
        timestampMs: 1000,
        filePath: stalePath,
        fileName: 'payload.bin',
        mediaKind: 'file',
      ),
    ]);
    await reloadCompletion;

    final current = provider.findMessageByID(messageID);
    expect(current?.fileElem?.path, livePath);
    expect(current?.status, MessageStatus.V2TIM_MSG_STATUS_SENDING);
    expect(provider.debugCachedFriendAvatar(peerID), isNull);
    expect(emissions, hasLength(1),
        reason: 'The stale history reload must not emit after a live mutation.');
    expect(emissions.single.single.fileElem?.path, livePath);
  });

  test('pre-row progress cache invalidates an in-flight history reload', () async {
    const peerID = 'progress-peer';
    const conversationID = 'c2c_$peerID';
    const messageID = 'progress-message';
    final loaderStarted = Completer<void>();
    final staleHistory = Completer<List<FakeMessage>>();
    final provider = FakeChatMessageProvider(
      historyLoader: (_) {
        if (!loaderStarted.isCompleted) {
          loaderStarted.complete();
        }
        return staleHistory.future;
      },
    );
    addTearDown(provider.dispose);

    final emissions = <List<V2TimMessage>>[];
    final subscription = provider.streamFor(userID: peerID).listen(emissions.add);
    addTearDown(subscription.cancel);
    await loaderStarted.future;
    final reloadCompletion = provider.debugHistoryReloadCompletion(
      conversationID,
    );
    expect(reloadCompletion, isNotNull);

    provider.debugSetFileProgress(
      messageID,
      peerID: peerID,
      received: 25,
      total: 100,
      path: '/live/partial.bin',
    );
    staleHistory.complete(<FakeMessage>[
      FakeMessage(
        msgID: messageID,
        conversationID: conversationID,
        fromUser: peerID,
        text: 'payload.bin',
        timestampMs: 1000,
        filePath: '/history/stale.bin',
        fileName: 'payload.bin',
        mediaKind: 'file',
        isPending: true,
      ),
    ]);
    await reloadCompletion;

    expect(provider.fileProgress[messageID]?.received, 25);
    expect(
      emissions,
      isEmpty,
      reason: 'Progress cache changes must invalidate an older history load.',
    );
  });

  test('queued live topic event invalidates reload before async mapping', () async {
    const peerID = 'topic-peer';
    const conversationID = 'c2c_$peerID';
    const messageID = 'topic-message';
    final loaderStarted = Completer<void>();
    final staleHistory = Completer<List<FakeMessage>>();
    final mappingStarted = Completer<void>();
    final releaseMapping = Completer<void>();
    final provider = FakeChatMessageProvider(
      historyLoader: (_) {
        if (!loaderStarted.isCompleted) {
          loaderStarted.complete();
        }
        return staleHistory.future;
      },
      topicMappingBarrier: (_) {
        if (!mappingStarted.isCompleted) {
          mappingStarted.complete();
        }
        return releaseMapping.future;
      },
    );
    addTearDown(provider.dispose);

    final emissions = <List<V2TimMessage>>[];
    final liveEmission = Completer<void>();
    final subscription = provider.streamFor(userID: peerID).listen((messages) {
      emissions.add(messages);
      if (!liveEmission.isCompleted &&
          messages.single.msgID == messageID &&
          messages.single.textElem?.text == 'live') {
        liveEmission.complete();
      }
    });
    addTearDown(subscription.cancel);
    await loaderStarted.future;
    final reloadCompletion = provider.debugHistoryReloadCompletion(
      conversationID,
    );
    expect(reloadCompletion, isNotNull);

    FakeUIKit.instance.eventBusInstance.emit(
      FakeIM.topicMessage,
      FakeMessage(
        msgID: messageID,
        conversationID: conversationID,
        fromUser: peerID,
        text: 'live',
        timestampMs: 2000,
      ),
    );
    await mappingStarted.future;
    staleHistory.complete(<FakeMessage>[
      FakeMessage(
        msgID: messageID,
        conversationID: conversationID,
        fromUser: peerID,
        text: 'stale',
        timestampMs: 1000,
      ),
    ]);
    await reloadCompletion;
    expect(emissions, isEmpty);

    releaseMapping.complete();
    await liveEmission.future;
    expect(emissions.single.single.textElem?.text, 'live');
  });

  test('live topic commit invalidates reload started during async mapping', () async {
    const peerID = 'commit-peer';
    const conversationID = 'c2c_$peerID';
    const messageID = 'commit-message';
    final firstHistory = Completer<List<FakeMessage>>();
    final duringMappingHistory = Completer<List<FakeMessage>>();
    final mappingStarted = Completer<void>();
    final releaseMapping = Completer<void>();
    var loadCount = 0;
    final provider = FakeChatMessageProvider(
      historyLoader: (_) {
        loadCount += 1;
        return loadCount == 1 ? firstHistory.future : duringMappingHistory.future;
      },
      topicMappingBarrier: (_) {
        if (!mappingStarted.isCompleted) {
          mappingStarted.complete();
        }
        return releaseMapping.future;
      },
    );
    addTearDown(provider.dispose);

    final emissions = <List<V2TimMessage>>[];
    final liveEmission = Completer<void>();
    final subscription = provider.streamFor(userID: peerID).listen((messages) {
      emissions.add(messages);
      if (!liveEmission.isCompleted &&
          messages.isNotEmpty &&
          messages.single.textElem?.text == 'live') {
        liveEmission.complete();
      }
    });
    addTearDown(subscription.cancel);
    final firstReload = provider.debugHistoryReloadCompletion(conversationID);
    expect(firstReload, isNotNull);
    firstHistory.complete(<FakeMessage>[]);
    await firstReload;
    emissions.clear();

    FakeUIKit.instance.eventBusInstance.emit(
      FakeIM.topicMessage,
      FakeMessage(
        msgID: messageID,
        conversationID: conversationID,
        fromUser: peerID,
        text: 'live',
        timestampMs: 2000,
      ),
    );
    await mappingStarted.future;

    provider.streamFor(userID: peerID);
    final reloadDuringMapping = provider.debugHistoryReloadCompletion(
      conversationID,
    );
    expect(reloadDuringMapping, isNotNull);
    releaseMapping.complete();
    await liveEmission.future;
    duringMappingHistory.complete(<FakeMessage>[
      FakeMessage(
        msgID: messageID,
        conversationID: conversationID,
        fromUser: peerID,
        text: 'stale',
        timestampMs: 1000,
      ),
    ]);
    await reloadDuringMapping;
    await Future<void>.delayed(Duration.zero);

    final rowEmissions = emissions.where((messages) => messages.isNotEmpty).toList();
    expect(rowEmissions, hasLength(1));
    expect(rowEmissions.single.single.textElem?.text, 'live');
  });

  test('dispose prevents an in-flight reload from rebuilding buffers', () async {
    const peerID = 'disposed-peer';
    const conversationID = 'c2c_$peerID';
    const messageID = 'disposed-message';
    final loaderStarted = Completer<void>();
    final staleHistory = Completer<List<FakeMessage>>();
    final provider = FakeChatMessageProvider(
      historyLoader: (_) {
        if (!loaderStarted.isCompleted) {
          loaderStarted.complete();
        }
        return staleHistory.future;
      },
    );

    provider.streamFor(userID: peerID);
    final reloadCompletion = provider.debugHistoryReloadCompletion(
      conversationID,
    );
    expect(reloadCompletion, isNotNull);
    await loaderStarted.future;
    provider.dispose();
    staleHistory.complete(<FakeMessage>[
      FakeMessage(
        msgID: messageID,
        conversationID: conversationID,
        fromUser: peerID,
        text: 'must-not-resurrect',
        timestampMs: 1000,
      ),
    ]);
    await reloadCompletion;

    expect(provider.findMessageByID(messageID), isNull);
    expect(provider.debugCachedFriendAvatar(peerID), isNull);
    expect(provider.debugControllerCount, 0);
    await provider.streamFor(userID: peerID).drain<void>();
    expect(provider.debugControllerCount, 0);
  });
}
