// Per-account storage for the paths that cannot know the Tox ID up front.
//
// THE DEFECT: three code paths construct `FfiChatService` without
// `historyDirectory` / `queueFilePath` / `fileRecvPath` / `avatarsPath`:
//
//   1. `LoginUseCase._executeLegacy`  — manual login of an account row that
//      carries no toxId; the service it builds LIVES ON as the app's service.
//   2. `StartupSessionUseCase`'s legacy auto-login fallback — same shape.
//   3. `AccountService.register`'s bootstrap-only instance — disposed before
//      any message flow, but it still opens the stores during `init()`.
//
// Left unbound they land on tim2tox's SHARED `<AppSupport>/chat_history`,
// `offline_message_queue.json`, `file_recv` and `avatars`, which every account
// on the device shares. (1) and (2) cannot pass the paths to the constructor —
// the identity only exists after `init()` + `login()` — so they late-bind the
// storage exactly as they already late-bind the prefs prefix and the scratch
// storage. (3) gets storage under its own temp directory.
//
// These tests drive the REAL `FfiChatService` and the real toxee wiring
// (`installAccountScopedStorage`, `createRegistrationBootstrapService`); the
// tim2tox-side rebind primitives are covered by
// `third_party/tim2tox/dart/test/account_storage_rebind_test.dart`.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/util/account_scoped_service_factory.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/legacy_account_data_claim.dart';

/// Two distinct 76-char Tox addresses; only the first 16 chars select the
/// per-account data root, so they differ from the very first character.
const _toxIdA =
    'A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1'
    'A1A1A1A1A1A1';
const _toxIdB =
    'B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2'
    'B2B2B2B2B2B2';

/// The peer both accounts talk to — the collision that made shared storage
/// visible: conversation files key on the PEER, never on the local identity.
const _conversationId =
    'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

ChatMessage _message(String text, {required String id}) => ChatMessage(
  text: text,
  fromUserId: 'self',
  isSelf: true,
  timestamp: DateTime.utc(2026, 1, 1, 12, 0, 0),
  msgID: id,
);

String _historyTextIn(Directory dir) {
  if (!dir.existsSync()) return '';
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .map((f) => f.readAsStringSync())
      .join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempRoot;

  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('legacy_account_storage_');
    AppPaths.debugApplicationSupportOverride = tempRoot.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (
          MethodCall call,
        ) async {
          switch (call.method) {
            case 'getApplicationSupportDirectory':
            case 'getApplicationDocumentsDirectory':
              return tempRoot.path;
            case 'getApplicationCacheDirectory':
              return p.join(tempRoot.path, 'cache');
            case 'getTemporaryDirectory':
              return p.join(tempRoot.path, 'temp');
            case 'getDownloadsDirectory':
              return p.join(tempRoot.path, 'downloads');
            default:
              return null;
          }
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    AppPaths.debugApplicationSupportOverride = null;
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Directory sharedHistoryDir() =>
      Directory(p.join(tempRoot.path, 'chat_history'));
  Directory accountHistoryDir(String toxId) => Directory(
    p.join(tempRoot.path, 'account_data', toxId.substring(0, 16), 'chat_history'),
  );
  File accountQueueFile(String toxId) => File(
    p.join(
      tempRoot.path,
      'account_data',
      toxId.substring(0, 16),
      'offline_message_queue.json',
    ),
  );

  /// A service in the exact shape the legacy login paths build: no storage
  /// paths, because the Tox ID does not exist yet.
  FfiChatService newLegacyShapeService() {
    final service = FfiChatService();
    addTearDown(service.dispose);
    return service;
  }

  group('legacy login paths late-bind per-account storage', () {
    test(
      'after the Tox ID is known, writes land under the account directory and '
      'not in the shared default',
      () async {
        // This account owns the legacy global dataset (the upgrade shape), so
        // the migration inside `installAccountScopedStorage` adopts it.
        SharedPreferences.setMockInitialValues({
          LegacyAccountDataClaim.claimedByKey: _toxIdA,
        });

        final service = newLegacyShapeService();
        // What `init()` already did before `login()` could reveal the Tox ID:
        // loaded and wrote history in the SHARED default.
        await service.messageHistoryPersistence.saveHistory(_conversationId, [
          _message('written-before-the-tox-id-was-known', id: 'm1'),
        ]);
        expect(
          _historyTextIn(sharedHistoryDir()),
          contains('written-before-the-tox-id-was-known'),
          reason: 'baseline: the unbound service uses the shared default',
        );

        await installAccountScopedStorage(service: service, toxId: _toxIdA);

        // The legacy dataset was adopted by its rightful owner and is readable
        // again through the account-scoped store.
        expect(
          _historyTextIn(accountHistoryDir(_toxIdA)),
          contains('written-before-the-tox-id-was-known'),
        );
        expect(
          service.messageHistoryPersistence
              .getHistory(_conversationId)
              .map((m) => m.text),
          contains('written-before-the-tox-id-was-known'),
          reason: 'installAccountStorage reloads from the new location',
        );

        // Everything from here on belongs to the account alone.
        await service.messageHistoryPersistence.saveHistory(_conversationId, [
          _message('written-after-binding', id: 'm2'),
        ]);
        await service.messageHistoryPersistence.flushPendingSaves();
        await service.offlineMessageQueuePersistence.addMessage(_conversationId, (
          kind: 'text',
          text: 'queued-after-binding',
          filePath: null,
          fileName: null,
          timestamp: DateTime.utc(2026, 1, 1, 12, 1, 0),
          msgID: 'q1',
          cloudCustomData: null,
          contentKind: ChatMessageContentKind.normal,
        ));

        expect(
          _historyTextIn(accountHistoryDir(_toxIdA)),
          contains('written-after-binding'),
        );
        expect(
          _historyTextIn(sharedHistoryDir()),
          isNot(contains('written-after-binding')),
          reason: 'the shared default must receive nothing after binding',
        );
        expect(accountQueueFile(_toxIdA).existsSync(), isTrue);
        expect(
          accountQueueFile(_toxIdA).readAsStringSync(),
          contains('queued-after-binding'),
        );
        expect(
          File(p.join(tempRoot.path, 'offline_message_queue.json')).existsSync(),
          isFalse,
          reason: 'the shared offline queue must never be created',
        );
      },
      skip: skipReason,
    );

    test(
      'two legacy accounts on one device do not see each other history',
      () async {
        // Nobody proved ownership of the legacy dataset, so neither account
        // adopts it — each starts with an empty per-account store.
        SharedPreferences.setMockInitialValues({});

        final serviceA = newLegacyShapeService();
        await installAccountScopedStorage(service: serviceA, toxId: _toxIdA);
        await serviceA.messageHistoryPersistence.saveHistory(_conversationId, [
          _message('alice-and-the-peer', id: 'a1'),
        ]);
        await serviceA.messageHistoryPersistence.flushPendingSaves();

        final serviceB = newLegacyShapeService();
        await installAccountScopedStorage(service: serviceB, toxId: _toxIdB);
        await serviceB.messageHistoryPersistence.saveHistory(_conversationId, [
          _message('bob-and-the-same-peer', id: 'b1'),
        ]);
        await serviceB.messageHistoryPersistence.flushPendingSaves();

        expect(
          (await serviceA.messageHistoryPersistence.loadHistory(
            _conversationId,
          )).map((m) => m.text),
          ['alice-and-the-peer'],
        );
        expect(
          (await serviceB.messageHistoryPersistence.loadHistory(
            _conversationId,
          )).map((m) => m.text),
          ['bob-and-the-same-peer'],
        );
        expect(
          _historyTextIn(accountHistoryDir(_toxIdA)),
          isNot(contains('bob-and-the-same-peer')),
        );
        expect(
          _historyTextIn(accountHistoryDir(_toxIdB)),
          isNot(contains('alice-and-the-peer')),
        );
      },
      skip: skipReason,
    );

    test(
      'installAccountStorage refuses once the session is live',
      () async {
        SharedPreferences.setMockInitialValues({});
        final service = newLegacyShapeService();
        service.debugMarkPollingStartedForTest();

        await expectLater(
          installAccountScopedStorage(service: service, toxId: _toxIdA),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('polling'),
            ),
          ),
        );
      },
      skip: skipReason,
    );

    test(
      'installAccountStorage refuses a second, different account',
      () async {
        SharedPreferences.setMockInitialValues({});
        final service = newLegacyShapeService();
        await installAccountScopedStorage(service: service, toxId: _toxIdA);

        // Idempotent for the SAME account.
        await installAccountScopedStorage(service: service, toxId: _toxIdA);

        await expectLater(
          installAccountScopedStorage(service: service, toxId: _toxIdB),
          throwsA(isA<StateError>()),
        );
      },
      skip: skipReason,
    );
  });

  group('registration bootstrap service', () {
    test(
      'writes into its own temp directory, never the shared default',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final tempDir = p.join(tempRoot.path, '.tmp_register_1');
        await Directory(tempDir).create(recursive: true);

        final service = createRegistrationBootstrapService(
          prefs: prefs,
          tempDir: tempDir,
        );
        await service.messageHistoryPersistence.saveHistory(_conversationId, [
          _message('bootstrap-row', id: 'r1'),
        ]);
        await service.messageHistoryPersistence.flushPendingSaves();
        await service.dispose();

        final storageRoot = bootstrapStorageRootIn(tempDir);
        expect(
          _historyTextIn(Directory(p.join(storageRoot, 'chat_history'))),
          contains('bootstrap-row'),
        );
        expect(
          sharedHistoryDir().existsSync(),
          isFalse,
          reason: 'the bootstrap-only instance must not touch, or even create, '
              'the shared default chat history',
        );
        expect(
          File(p.join(tempRoot.path, 'offline_message_queue.json')).existsSync(),
          isFalse,
        );

        // The temp storage dies with the registration, wherever the temp
        // directory ended up (it is renamed to the profile directory first).
        await deleteBootstrapStorageQuietly(storageRoot);
        expect(Directory(storageRoot).existsSync(), isFalse);
      },
      skip: skipReason,
    );
  });
}
