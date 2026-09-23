// Tim2ToxSdkPlatform's native custom-callback handler is process-global
// (NativeLibraryManager.customCallbackHandler). The native group notifications
// it handles — groupQuitNotification (voluntary quit and kick),
// groupJoinNotification, groupJoinFailedNotification, groupInviteNotification,
// groupChatIdStored, groupTypeStored — carry no user_data, so native stamps
// each with the emitting session (`instance_id`, `session_epoch`, see
// third_party/tim2tox/ffi/dart_compat_group.cpp). A notification is applied
// only when the platform's service owns that instance AND the epoch is still
// the instance's live native session. Anything else must be ignored: another
// test node's, the previous account's after an account switch on the same
// (default) instance, or an unstamped one.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

/// Default-instance bindings (instance 0, like production toxee) whose native
/// session epochs the test controls.
class _SessionFfi extends Tim2ToxFfi {
  _SessionFfi() : super.forTesting();

  final Map<int, int> liveEpochs = <int, int>{};

  @override
  int Function() get getCurrentInstanceId => () => 0;

  @override
  int Function(int) get getSessionEpoch =>
      (int instanceId) => liveEpochs[instanceId] ?? 0;

  @override
  void Function() get uninit => () {};
}

class _RecordingService extends FfiChatService {
  _RecordingService(_SessionFfi ffi, Directory dir)
    : super(
        ffiForTesting: ffi,
        historyDirectory: p.join(dir.path, 'history'),
        queueFilePath: p.join(dir.path, 'offline_queue.json'),
      );

  final List<String> events = <String>[];

  @override
  Future<void> cleanupGroupState(
    String groupId, {
    bool keepHistory = false,
  }) async {
    events.add('quit:$groupId:${keepHistory ? 'kicked' : 'left'}');
  }

  @override
  Future<void> registerJoinedGroupState(String groupId) async {
    events.add('join:$groupId');
  }

  @override
  Future<void> handleGroupJoinFailed(
    String groupId,
    String chatId,
    String reason, {
    bool established = false,
    String inviteId = '',
  }) async {
    events.add('joinFailed:$groupId:$reason');
  }

  @override
  void notifyPendingGroupInvitesChanged() {
    events.add('invite');
  }
}

const Map<String, Map<String, dynamic>> _notifications = {
  'groupQuitNotification': {
    'callback': 'groupQuitNotification',
    'group_id': 'tox_group_0',
    'reason': 'kicked',
  },
  'groupJoinNotification': {
    'callback': 'groupJoinNotification',
    'group_id': 'tox_group_0',
  },
  'groupJoinFailedNotification': {
    'callback': 'groupJoinFailedNotification',
    'group_id': 'tox_group_0',
    'chat_id': '',
    'reason': 'peer_limit',
    'established': true,
    'invite_id': '',
  },
  'groupInviteNotification': {
    'callback': 'groupInviteNotification',
    'invite_id': 'invite_1',
  },
};

const List<String> _expectedEvents = <String>[
  'quit:tox_group_0:kicked',
  'join:tox_group_0',
  'joinFailed:tox_group_0:peer_limit',
  'invite',
];

Map<String, dynamic> _stamped(
  Map<String, dynamic> payload,
  int instanceId,
  int sessionEpoch,
) => <String, dynamic>{
  ...payload,
  'instance_id': instanceId,
  'session_epoch': sessionEpoch,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    setNativeLibraryName('tim2tox_ffi');
  });

  late Directory tempDir;
  late _SessionFfi ffi;
  late _RecordingService service;
  late Tim2ToxSdkPlatform platform;

  Future<void> deliver(String name, Map<String, dynamic> data) async {
    final handler = NativeLibraryManager.customCallbackHandler;
    expect(handler, isNotNull);
    await handler!(name, data, {});
  }

  Future<void> deliverAll(int instanceId, int sessionEpoch) async {
    for (final entry in _notifications.entries) {
      await deliver(entry.key, _stamped(entry.value, instanceId, sessionEpoch));
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp(
      'toxee_native_session_scope_',
    );
    FfiChatService.clearPollingRegistryForTests();
    ffi = _SessionFfi()..liveEpochs[0] = 5;
    service = _RecordingService(ffi, tempDir);
    platform = Tim2ToxSdkPlatform(ffiService: service);
  });

  tearDown(() async {
    platform.dispose();
    NativeLibraryManager.customCallbackHandler = null;
    FfiChatService.clearPollingRegistryForTests();
    await service.dispose();
    await tempDir.delete(recursive: true);
  });

  group('Tim2ToxSdkPlatform native group notification scoping', () {
    test('applies notifications of its own live session', () async {
      await deliverAll(0, 5);
      expect(service.events, _expectedEvents);
    });

    test('ignores notifications stamped with a foreign instance_id', () async {
      ffi.liveEpochs[7] = 9;
      await deliverAll(7, 9);
      expect(service.events, isEmpty);
    });

    test('ignores the previous account session after a switch', () async {
      // Account A's session (epoch 5) ended and account B's started on the
      // same default instance: A's delayed notifications are stale...
      ffi.liveEpochs[0] = 6;
      await deliverAll(0, 5);
      expect(service.events, isEmpty);
      // ...while B's own still apply.
      await deliverAll(0, 6);
      expect(service.events, _expectedEvents);
    });

    test('ignores notifications while the instance has no session', () async {
      ffi.liveEpochs.remove(0);
      await deliverAll(0, 5);
      expect(service.events, isEmpty);
    });

    test('ignores unstamped notifications', () async {
      for (final entry in _notifications.entries) {
        await deliver(entry.key, Map<String, dynamic>.of(entry.value));
      }
      expect(service.events, isEmpty);
    });

    test('a shared default-instance service still owns its registered test '
        'nodes (the auto_tests single-service harness)', () async {
      FfiChatService.registerInstanceForPolling(7);
      ffi.liveEpochs[7] = 9;
      await deliverAll(7, 9);
      expect(service.events, _expectedEvents);
      service.events.clear();
      await deliverAll(7, 8);
      expect(service.events, isEmpty, reason: 'stale epoch of node 7');
    });
  });
}
