import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

class _TestFfiChatService extends FfiChatService {
  _TestFfiChatService({MessageHistoryPersistence? persistence})
    : super(messageHistoryPersistence: persistence);

  ChatMessage? lastC2cMessage(String userId) => lastMessages[userId];

  List<ChatMessage> historyFor(String userId) => getHistory(userId);
}

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempRoot;

  final ffiAvailable = _ffiAvailable();
  final skipReason = ffiAvailable
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('FfiChatService C2C custom ingest', () {
    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp(
        'ffi_c2c_custom_ingest_test_',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (
            MethodCall call,
          ) async {
            switch (call.method) {
              case 'getApplicationSupportDirectory':
              case 'getApplicationDocumentsDirectory':
                return tempRoot.path;
              case 'getApplicationCacheDirectory':
                return '${tempRoot.path}/cache';
              case 'getTemporaryDirectory':
                return '${tempRoot.path}/temp';
              case 'getDownloadsDirectory':
                return '${tempRoot.path}/downloads';
              default:
                return null;
            }
          });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('materializes inbound custom data as a C2C custom message', () async {
      final service = _TestFfiChatService();
      // Disposed before the teardown pulls the path_provider mock. Ingesting
      // arms a 200 ms history-save timer, and a timer that fires after the mock
      // is gone throws a late `MissingPluginException` that fails this test
      // under full-suite load while passing in isolation.
      addTearDown(() async => service.dispose());
      const sender = 'peer_pubkey_custom';
      const data = '{"type":"reply_probe","body":"quotable"}';

      final accepted = service.ingestInboundC2cCustom(from: sender, data: data);

      expect(accepted, isTrue);
      final history = service.historyFor(sender);
      expect(history, hasLength(1));
      expect(history.single.text, data);
      expect(history.single.mediaKind, 'custom');
      expect(history.single.groupId, isNull);
      expect(history.single.isSelf, isFalse);
      expect(
        service.lastC2cMessage(sender)?.mediaKind,
        'custom',
        reason: 'conversation preview state should refresh immediately',
      );
    }, skip: skipReason);
  });
}
