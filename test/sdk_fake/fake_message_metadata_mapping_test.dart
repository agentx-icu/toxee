import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';
import 'package:toxee/sdk_fake/fake_event_bus.dart';
import 'package:toxee/sdk_fake/fake_managers.dart';
import 'package:toxee/sdk_fake/fake_msg_provider.dart';

bool _ffiAvailable() {
  try {
    setNativeLibraryName('tim2tox_ffi');
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'cold history mapping retains persisted metadata when the local file is missing',
    () async {
      const peerID = 'metadata-peer';
      const messageID = 'persisted-file-message';
      const persistedFileSize = 987654;
      const cloudCustomData = '{"messageReply":{"messageID":"quoted-message"}}';
      final root = await Directory.systemTemp.createTemp(
        'toxee_fake_message_metadata_',
      );
      addTearDown(() => root.delete(recursive: true));

      final writer = MessageHistoryPersistence(
        historyDirectory: '${root.path}/history',
      );
      await writer.appendHistory(
        peerID,
        ChatMessage(
          text: 'missing.bin',
          fromUserId: peerID,
          isSelf: false,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
          msgID: messageID,
          filePath: '${root.path}/missing/missing.bin',
          fileName: 'missing.bin',
          mediaKind: 'file',
          fileSize: persistedFileSize,
          cloudCustomData: cloudCustomData,
        ),
      );
      for (final media in <(String, int)>[
        ('image', 111111),
        ('video', 222222),
        ('audio', 333333),
      ]) {
        await writer.appendHistory(
          peerID,
          ChatMessage(
            text: '${media.$1}.bin',
            fromUserId: peerID,
            isSelf: false,
            timestamp: DateTime.fromMillisecondsSinceEpoch(media.$2),
            msgID: 'persisted-${media.$1}-message',
            filePath: '${root.path}/missing/${media.$1}.bin',
            fileName: '${media.$1}.bin',
            mediaKind: media.$1,
            fileSize: media.$2,
            cloudCustomData: cloudCustomData,
          ),
        );
      }
      await writer.dispose();

      final reader = MessageHistoryPersistence(
        historyDirectory: '${root.path}/history',
      );
      await reader.loadHistory(peerID);
      final ffi = FfiChatService(
        messageHistoryPersistence: reader,
        queueFilePath: '${root.path}/offline_queue.json',
      );
      addTearDown(ffi.dispose);
      final bus = FakeEventBus();
      addTearDown(bus.dispose);
      final manager = FakeMessageManager(bus, ffi);
      final history = await manager.getHistory('c2c_$peerID');
      final fileHistory =
          history.firstWhere((message) => message.msgID == messageID);
      expect(fileHistory.fileSize, persistedFileSize);
      expect(fileHistory.cloudCustomData, cloudCustomData);
      final provider = FakeChatMessageProvider(
        historyLoader: manager.getHistory,
      );
      addTearDown(provider.dispose);

      provider.streamFor(userID: peerID);
      final reload = provider.debugHistoryReloadCompletion('c2c_$peerID');
      expect(reload, isNotNull);
      await reload;

      final mapped = provider.findMessageByID(messageID);
      expect(mapped, isNotNull);
      expect(mapped!.fileElem?.fileSize, persistedFileSize);
      expect(mapped.cloudCustomData, cloudCustomData);
      final image = provider.findMessageByID('persisted-image-message');
      expect(image?.imageElem?.imageList?.first?.size, 111111);
      expect(image?.cloudCustomData, cloudCustomData);
      final video = provider.findMessageByID('persisted-video-message');
      expect(video?.videoElem?.videoSize, 222222);
      expect(video?.cloudCustomData, cloudCustomData);
      final audio = provider.findMessageByID('persisted-audio-message');
      expect(audio?.soundElem?.dataSize, 333333);
      expect(audio?.cloudCustomData, cloudCustomData);
    },
    skip: skipReason,
  );
}
