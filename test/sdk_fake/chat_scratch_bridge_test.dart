import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import 'package:tim2tox_dart/interfaces/scratch_file_service.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/sdk_fake/fake_msg_provider.dart';
import 'package:toxee/util/account_scratch_storage.dart';
import 'package:toxee/util/prefs.dart';

const _accountA =
    '0123456789ABCDEF111111111111111111111111111111111111111111111111111111111111';
const _accountB =
    '0123456789ABCDEF222222222222222222222222222222222222222222222222222222222222';

class _RecordingScratchService implements ScratchFileService {
  _RecordingScratchService(this.root);

  final Directory root;
  final List<({String category, String fileName, Uint8List bytes})> writes = [];
  final List<String> deletes = [];

  @override
  Future<String> writeBytesToScratch(
    Uint8List bytes, {
    required String category,
    required String suggestedFileName,
  }) async {
    writes.add((
      category: category,
      fileName: suggestedFileName,
      bytes: Uint8List.fromList(bytes),
    ));
    final file = File(
      '${root.path}${Platform.pathSeparator}$category'
      '${Platform.pathSeparator}$suggestedFileName',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<String> copyFileToScratch(
    String sourcePath, {
    required String category,
    required String suggestedFileName,
  }) {
    throw UnsupportedError('copy is not used by the UIKit bridge');
  }

  @override
  Future<void> deleteScratchFile(String path) async {
    deletes.add(path);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
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
  int? instanceId,
  String fileName,
});

class _ScratchBridgeFfi implements FfiChatService {
  _ScratchBridgeFfi({
    required ScratchFileService scratchFileService,
    required this.liveAccountToxId,
  }) : _scratchFileService = scratchFileService;

  final ScratchFileService _scratchFileService;
  String liveAccountToxId;
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
  String? getSelfToxId() => liveAccountToxId;

  @override
  Future<String> writeBytesToScratch(
    Uint8List bytes, {
    required String category,
    required String suggestedFileName,
  }) {
    return _scratchFileService.writeBytesToScratch(
      bytes,
      category: category,
      suggestedFileName: suggestedFileName,
    );
  }

  @override
  Future<void> deleteScratchFile(String path) {
    return _scratchFileService.deleteScratchFile(path);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'registration bootstrap owner fails closed before account discovery',
    () {
      final unavailable = AccountScratchStorage.unavailableUntilAccountKnown();
      expect(
        () => unavailable.writeBytesToScratch(
          Uint8List(0),
          category: 'clipboard_images',
          suggestedFileName: 'paste.png',
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  group('FakeChatMessageProvider scratch bridge', () {
    late Directory sandbox;
    late _RecordingScratchService scratch;
    late _ScratchBridgeFfi ffi;
    late FakeChatMessageProvider provider;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('scratch_bridge_test_');
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await Prefs.initialize(await SharedPreferences.getInstance());
      await Prefs.setCurrentAccountToxId(_accountA);
      scratch = _RecordingScratchService(sandbox);
      ffi = _ScratchBridgeFfi(
        scratchFileService: scratch,
        liveAccountToxId: _accountA,
      );
      provider = FakeChatMessageProvider(ffiService: ffi);
    });

    tearDown(() async {
      provider.dispose();
      await ffi.dispose();
      if (await sandbox.exists()) {
        await sandbox.delete(recursive: true);
      }
    });

    test(
      'implements UIKit bridge and delegates write and delete to FFI owner',
      () async {
        expect(provider, isA<ChatScratchFileProvider>());

        final path = await provider.writeScratchBytes(
          category: 'clipboard_images',
          suggestedFileName: 'paste.png',
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
        );
        expect(
          path,
          '${sandbox.path}${Platform.pathSeparator}clipboard_images'
          '${Platform.pathSeparator}paste.png',
        );
        expect(scratch.writes, hasLength(1));
        expect(scratch.writes.single.category, 'clipboard_images');
        expect(scratch.writes.single.fileName, 'paste.png');
        expect(scratch.writes.single.bytes, <int>[1, 2, 3]);

        await provider.deleteScratchFile(path);
        expect(scratch.deletes, <String>[path]);
      },
    );

    test(
      'rejects a mismatched live full account before owner access',
      () async {
        await Prefs.setCurrentAccountToxId(_accountB);

        await expectLater(
          provider.writeScratchBytes(
            category: 'clipboard_images',
            suggestedFileName: 'paste.png',
            bytes: Uint8List(0),
          ),
          throwsA(isA<StateError>()),
        );
        expect(scratch.writes, isEmpty);
      },
    );

    test('rejects short persisted and live account identifiers', () async {
      await Prefs.setCurrentAccountToxId(_accountA.substring(0, 64));
      await expectLater(
        provider.deleteScratchFile('/account/scratch/clipboard_images/a.png'),
        throwsA(isA<StateError>()),
      );

      await Prefs.setCurrentAccountToxId(_accountA);
      ffi.liveAccountToxId = _accountA.substring(0, 64);
      await expectLater(
        provider.deleteScratchFile('/account/scratch/clipboard_images/a.png'),
        throwsA(isA<StateError>()),
      );
      expect(scratch.deletes, isEmpty);
    });
  });
}
