import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/interfaces/logger_service.dart';
import 'package:tim2tox_dart/interfaces/scratch_file_service.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';
import 'package:tim2tox_dart/utils/offline_message_queue_persistence.dart';

class _ControlledHistoryPersistence extends MessageHistoryPersistence {
  _ControlledHistoryPersistence({
    required super.historyDirectory,
    required this.onLoadHistory,
  });

  final Future<List<ChatMessage>> Function(String id) onLoadHistory;

  int loadCalls = 0;
  int disposeCalls = 0;
  int flushCalls = 0;

  @override
  Future<List<ChatMessage>> loadHistory(String id, {Set<String>? quitGroups}) {
    loadCalls++;
    return onLoadHistory(id);
  }

  @override
  Future<void> flushPendingSaves() async {
    flushCalls++;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

class _RecordingLogger implements LoggerService {
  final List<String> errors = <String>[];
  final Completer<void> errorLogged = Completer<void>();

  @override
  void log(String message) {}

  @override
  void logDebug(String message) {}

  @override
  void logError(String message, Object error, StackTrace stack) {
    errors.add('$message | $error');
    if (!errorLogged.isCompleted) {
      errorLogged.complete();
    }
  }

  @override
  void logWarning(String message) {}
}

class _RecordingScratchFileService implements ScratchFileService {
  _RecordingScratchFileService(this.rootPath);

  final String rootPath;

  int deleteCalls = 0;
  final List<String> deletedPaths = <String>[];

  @override
  Future<String> copyFileToScratch(
    String sourcePath, {
    required String category,
    required String suggestedFileName,
  }) async {
    return '$rootPath/${category}_$suggestedFileName';
  }

  @override
  Future<void> deleteScratchFile(String path) async {
    deleteCalls++;
    deletedPaths.add(path);
  }

  @override
  Future<String> writeBytesToScratch(
    Uint8List bytes, {
    required String category,
    required String suggestedFileName,
  }) async {
    final path = '$rootPath/${category}_$suggestedFileName';
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return path;
  }
}

bool _ffiAvailable() {
  final exeDir = File(Platform.resolvedExecutable).parent;
  const libName = 'libtim2tox_ffi.dylib';
  final candidates = <String>[
    '${exeDir.path}/../../tim2tox/build/ffi/$libName',
    '${exeDir.path}/../../../tim2tox/build/ffi/$libName',
    '${exeDir.path}/$libName',
    '${exeDir.path}/../Frameworks/$libName',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return true;
    }
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('FfiChatService history load tracking', () {
    test(
      'awaited loadHistory is tracked once and blocks dispose until it finishes',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'ffi_chat_service_history_load_tracking_test_',
        );
        addTearDown(() async {
          if (tempRoot.existsSync()) {
            await tempRoot.delete(recursive: true);
          }
        });

        final loadStarted = Completer<void>();
        final releaseLoad = Completer<void>();
        final persistence = _ControlledHistoryPersistence(
          historyDirectory: '${tempRoot.path}/history',
          onLoadHistory: (id) async {
            if (!loadStarted.isCompleted) {
              loadStarted.complete();
            }
            await releaseLoad.future;
            return const <ChatMessage>[];
          },
        );
        final service = FfiChatService(
          messageHistoryPersistence: persistence,
          offlineMessageQueuePersistence: OfflineMessageQueuePersistence(
            queueFilePath: '${tempRoot.path}/queue.json',
          ),
        );

        final firstLoad = service.loadHistory('group_compat_audit');
        await loadStarted.future;

        final secondLoad = service.loadHistory('group_compat_audit');
        expect(
          identical(firstLoad, secondLoad),
          isTrue,
          reason: 'same-conversation loads should share the tracked future',
        );
        expect(
          persistence.loadCalls,
          1,
          reason:
              'in-flight history loads should be reused for the same conversation',
        );

        final disposeFuture = service.dispose();
        expect(
          persistence.disposeCalls,
          0,
          reason: 'dispose must wait for the tracked history load fence',
        );

        releaseLoad.complete();
        await Future.wait([firstLoad, secondLoad, disposeFuture]);

        expect(persistence.disposeCalls, 1);
        expect(persistence.flushCalls, 1);
      },
      skip: skipReason,
    );

    test(
      'loadHistory propagates errors to awaited callers and getHistory still logs them',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'ffi_chat_service_history_load_error_test_',
        );
        addTearDown(() async {
          if (tempRoot.existsSync()) {
            await tempRoot.delete(recursive: true);
          }
        });

        final logger = _RecordingLogger();
        final persistence = _ControlledHistoryPersistence(
          historyDirectory: '${tempRoot.path}/history',
          onLoadHistory: (id) =>
              Future<List<ChatMessage>>.error(StateError('boom for $id')),
        );
        final service = FfiChatService(
          loggerService: logger,
          messageHistoryPersistence: persistence,
          offlineMessageQueuePersistence: OfflineMessageQueuePersistence(
            queueFilePath: '${tempRoot.path}/queue.json',
          ),
        );

        addTearDown(service.dispose);

        await expectLater(
          service.loadHistory('group_error_path'),
          throwsA(isA<StateError>()),
        );
        expect(persistence.loadCalls, 1);

        expect(service.getHistory('group_error_path_fire_and_forget'), isEmpty);
        await logger.errorLogged.future;

        expect(logger.errors, isNotEmpty);
        expect(logger.errors.single, contains('history load failed'));
        expect(logger.errors.single, contains('boom for'));
      },
      skip: skipReason,
    );

    test(
      'dispose drains a failed getHistory load once and still reaches cleanup',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'ffi_chat_service_history_dispose_drain_test_',
        );
        addTearDown(() async {
          if (tempRoot.existsSync()) {
            await tempRoot.delete(recursive: true);
          }
        });

        final loadStarted = Completer<void>();
        final releaseLoad = Completer<void>();
        final logger = _RecordingLogger();
        final scratchService = _RecordingScratchFileService(tempRoot.path);
        final persistence = _ControlledHistoryPersistence(
          historyDirectory: '${tempRoot.path}/history',
          onLoadHistory: (id) async {
            if (!loadStarted.isCompleted) {
              loadStarted.complete();
            }
            await releaseLoad.future;
            throw StateError('boom for $id');
          },
        );
        final service = FfiChatService(
          loggerService: logger,
          messageHistoryPersistence: persistence,
          offlineMessageQueuePersistence: OfflineMessageQueuePersistence(
            queueFilePath: '${tempRoot.path}/queue.json',
          ),
          scratchFileService: scratchService,
        );

        await service.writeBytesToScratch(
          Uint8List.fromList(const [1, 2, 3]),
          category: 'dispose',
          suggestedFileName: 'proof.txt',
        );

        expect(service.getHistory('group_dispose_failure'), isEmpty);
        await loadStarted.future;

        final disposeFuture = service.dispose();
        releaseLoad.complete();

        await logger.errorLogged.future;
        await expectLater(disposeFuture, completes);

        expect(persistence.loadCalls, 1);
        expect(persistence.flushCalls, 1);
        expect(persistence.disposeCalls, 1);
        expect(scratchService.deleteCalls, 1);
        expect(logger.errors, hasLength(1));
        expect(logger.errors.single, contains('history load failed'));
        expect(
          logger.errors.single,
          contains('boom for group_dispose_failure'),
        );
      },
      skip: skipReason,
    );
  });
}
