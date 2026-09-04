import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform_converters.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';
import 'package:tim2tox_dart/utils/offline_message_queue_persistence.dart';

class _OfflineFileService extends FfiChatService {
  _OfflineFileService({
    required super.messageHistoryPersistence,
    required super.offlineMessageQueuePersistence,
  });

  @override
  Future<List<({String userId, String nickName, String status, bool online})>>
  getFriendList() async => const [];
}

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

  test('offline file row preserves byte size across history reload', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'ffi_file_metadata_test_',
    );
    final historyDirectory = '${tempRoot.path}/history';
    final persistence = MessageHistoryPersistence(
      historyDirectory: historyDirectory,
    );
    final service = _OfflineFileService(
      messageHistoryPersistence: persistence,
      offlineMessageQueuePersistence: OfflineMessageQueuePersistence(
        queueFilePath: '${tempRoot.path}/offline_queue.json',
      ),
    );
    addTearDown(() async {
      await service.dispose();
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    const peerId =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    final sourceFile = File('${tempRoot.path}/payload.bin');
    await sourceFile.writeAsBytes(List<int>.generate(123, (index) => index));

    final echo = await service.sendFile(peerId, sourceFile.path);
    await persistence.flushPendingSaves();
    final reloaded = MessageHistoryPersistence(
      historyDirectory: historyDirectory,
    );
    await reloaded.loadHistory(peerId);
    final row = reloaded.getCachedList(peerId)?.single;

    expect(row?.fileName, 'payload.bin');
    expect(row?.fileSize, 123);
    expect(row?.mediaKind, 'file');
    // sendFile hands back the pending echo it queued, and its identity is
    // the persisted row's — the id the UI must adopt for its optimistic
    // bubble (otherwise the echo renders as a second bubble).
    expect(echo, isNotNull);
    expect(echo!.isPending, isTrue);
    expect(echo.msgID, isNotEmpty);
    expect(row?.msgID, echo.msgID);
  }, skip: skipReason);

  test(
    'cold-history file keeps persisted size when local file is missing',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'ffi_file_cold_history_test_',
      );
      final missingPath = '${tempRoot.path}/already-removed.bin';
      final service = FfiChatService(
        historyDirectory: '${tempRoot.path}/history',
        queueFilePath: '${tempRoot.path}/offline_queue.json',
      );
      final platform = Tim2ToxSdkPlatform(ffiService: service);
      addTearDown(() async {
        platform.dispose();
        await service.dispose();
        if (tempRoot.existsSync()) {
          await tempRoot.delete(recursive: true);
        }
      });

      expect(File(missingPath).existsSync(), isFalse);
      final converted = platform.chatMessageToV2TimMessage(
        ChatMessage(
          text: '',
          fromUserId: 'peer',
          isSelf: false,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          filePath: missingPath,
          fileName: 'already-removed.bin',
          mediaKind: 'file',
          fileSize: 987654,
          msgID: 'cold-history-file',
        ),
        'self',
      );

      expect(converted.fileElem?.fileSize, 987654);
    },
    skip: skipReason,
  );

  test(
    'inbound file lifecycle preserves request metadata on completion',
    () async {
      final source = await File(
        '${Directory.current.path}/third_party/tim2tox/dart/lib/service/'
        'ffi_chat_service.dart',
      ).readAsString();
      final requestStart = source.indexOf(
        '// Create a pending file message with temporary path',
      );
      final requestEnd = source.indexOf(
        '// Track this file transfer for progress updates',
        requestStart,
      );
      final requestBlock = source.substring(requestStart, requestEnd);
      expect(requestBlock, contains('fileSize: fileSize'));

      final completionStart = source.indexOf(
        'final updatedMsg = oldMsg.copyWith(',
      );
      final completionEnd = source.indexOf(
        '// CRITICAL: Check if message was already updated',
        completionStart,
      );
      final completionBlock = source.substring(completionStart, completionEnd);
      expect(completionBlock, contains('filePath:'));
      expect(completionBlock, contains('isPending: false'));
    },
  );

  test('file completion copy preserves all non-completion metadata', () {
    final original = ChatMessage(
      text: 'payload',
      fromUserId: 'peer',
      isSelf: false,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000123),
      groupId: 'group',
      filePath: '/tmp/receiving_payload.bin',
      fileName: 'payload.bin',
      mediaKind: 'file',
      isPending: true,
      isReceived: true,
      isRead: true,
      msgID: 'message-id',
      version: 3,
      fileSize: 123456,
      mimeType: 'application/octet-stream',
      fileHash: 'sha256-value',
      altMsgIds: const ['alternate-id'],
      cloudCustomData: '{"reply":"metadata"}',
    );

    final completed = original.copyWith(
      filePath: '/downloads/payload.bin',
      fileName: 'payload.bin',
      isPending: false,
    );

    expect(completed.filePath, '/downloads/payload.bin');
    expect(completed.isPending, isFalse);
    expect(completed.fileSize, original.fileSize);
    expect(completed.cloudCustomData, original.cloudCustomData);
    expect(completed.mimeType, original.mimeType);
    expect(completed.fileHash, original.fileHash);
    expect(completed.altMsgIds, original.altMsgIds);
    expect(completed.timestamp, original.timestamp);
    expect(completed.isReceived, original.isReceived);
    expect(completed.isRead, original.isRead);
    expect(completed.version, original.version);
    expect(completed.mediaKind, original.mediaKind);
  });

  test('every file-done history update copies its existing row', () async {
    final source = await File(
      '${Directory.current.path}/third_party/tim2tox/dart/lib/service/'
      'ffi_chat_service.dart',
    ).readAsString();
    final start = source.indexOf('Future<void> _handleFileDone(');
    final end = source.indexOf('Future<String?> _moveFileToDownloads(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final handler = source.substring(start, end);

    expect(handler, isNot(contains('final updatedMsg = ChatMessage(')));
    expect(
      RegExp(
        r'final updatedMsg = (?:oldMsg|msg)\.copyWith\(',
      ).allMatches(handler).length,
      greaterThanOrEqualTo(4),
    );
  });
}
