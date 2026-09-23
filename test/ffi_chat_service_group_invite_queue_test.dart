// Group-invite state in FfiChatService (Codex review 3, items #3, #11, #13):
//
// * #3  the session-scoped invite / join-failure streams must deliver again
//       after dispose() + a re-init of the same service object;
// * #11 the offline-invite queue's read-modify-write must be serialized, so a
//       concurrent enqueue is neither overwritten by another enqueue nor by a
//       flush that is writing back its own snapshot;
// * #13 an accepted invite stays persisted ("joining") until its join is
//       confirmed or native hands it back.
//
// FFI dependency: FfiChatService opens the tim2tox FFI library in its
// constructor. Skipped when the library is not loadable here.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/interfaces/extended_preferences_service.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

const _friend =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _chatId =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

PendingGroupInvite _invite(String id, {String chatId = _chatId}) =>
    PendingGroupInvite(
      id: id,
      inviterUserId: _friend,
      kind: 'group',
      groupName: 'Team',
      receivedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      // NGC invite data: chat id (32 bytes) + the inviter's group key.
      cookieHex: '$chatId${'ee' * 32}',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  late Directory tempRoot;
  late _SlowPrefs prefs;
  late FfiChatService service;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('group_invite_queue_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      return tempRoot.path;
    });
    prefs = _SlowPrefs();
    if (skipReason != null) return;
    service = FfiChatService(
      preferencesService: prefs,
      messageHistoryPersistence:
          MessageHistoryPersistence(historyDirectory: '${tempRoot.path}/h'),
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (tempRoot.existsSync()) await tempRoot.delete(recursive: true);
  });

  group('session streams (#3)', skip: skipReason, () {
    test('invite and join-failure streams deliver again after a re-init',
        () async {
      service.debugBeginSessionForTest();
      var oldSessionDone = false;
      final oldSub = service.groupJoinFailures
          .listen((_) {}, onDone: () => oldSessionDone = true);

      await service.dispose();
      await pumpEventQueue();
      expect(oldSessionDone, isTrue,
          reason: 'a listener of the ended session is completed');
      await oldSub.cancel();

      // Re-login on the same object: init() opens the session again.
      service.debugBeginSessionForTest();
      final failures = <GroupJoinFailure>[];
      var invitesChanged = 0;
      final subA = service.groupJoinFailures.listen(failures.add);
      final subB =
          service.pendingGroupInvitesChanged.listen((_) => invitesChanged++);

      await service.handleGroupJoinFailed(
          'tox_7', _chatId, 'invalid_password');
      service.notifyPendingGroupInvitesChanged();
      await pumpEventQueue();

      expect(failures, hasLength(1),
          reason: 'a refusal in the new session must reach the UI');
      expect(failures.single.reason, GroupJoinFailureReason.invalidPassword);
      expect(invitesChanged, 1,
          reason: 'an invite in the new session must reach the UI');
      await subA.cancel();
      await subB.cancel();
    });
  });

  group('offline-invite queue (#11)', skip: skipReason, () {
    test('concurrent enqueues all persist', () async {
      await Future.wait([
        for (var i = 0; i < 12; i++)
          service.queueGroupInviteForOfflineFriend('tox_$i', _friend),
      ]);
      final queued = await service.debugQueuedOfflineGroupInvites();
      expect(queued, {
        for (var i = 0; i < 12; i++) 'tox_$i\t$_friend'
      });
    });

    test('an enqueue during a flush is not overwritten by the flush',
        () async {
      service.debugAddKnownGroupForTest('tox_1');
      service.debugAddKnownGroupForTest('tox_2');
      await service.queueGroupInviteForOfflineFriend('tox_1', _friend);

      final gate = Completer<void>();
      final invited = <String>[];
      final flush =
          service.debugFlushPendingGroupInvitesForTest(_friend, (gid) async {
        invited.add(gid);
        await gate.future; // the native invite is in flight
        return true; // delivered
      });
      await pumpEventQueue();
      final enqueue = service.queueGroupInviteForOfflineFriend('tox_2', _friend);
      await pumpEventQueue();
      gate.complete();
      await Future.wait([flush, enqueue]);

      expect(invited, ['tox_1']);
      expect(await service.debugQueuedOfflineGroupInvites(),
          {'tox_2\t$_friend'},
          reason: 'the delivered invite is gone and the new one survives');
    });

    test('an undelivered invite stays queued; a left group is dropped',
        () async {
      service.debugAddKnownGroupForTest('tox_1');
      await service.queueGroupInviteForOfflineFriend('tox_1', _friend);
      await service.queueGroupInviteForOfflineFriend('tox_gone', _friend);

      await service.debugFlushPendingGroupInvitesForTest(
          _friend, (_) async => false);

      expect(await service.debugQueuedOfflineGroupInvites(),
          {'tox_1\t$_friend'});
    });

    test('offline is decided by the live connection status', () {
      service.debugFriendConnectionOverride = (_) => 0;
      expect(service.isFriendNotConnected(_friend), isTrue);
      service.debugFriendConnectionOverride = (_) => 2;
      expect(service.isFriendNotConnected(_friend), isFalse);
    });
  });

  // A write queued before dispose resumes after `_sessionClosed` is set, while
  // native still holds the invites. Asking the session-gated getter then
  // reported "no invites" and ERASED the account's persisted copy, which
  // native keeps in memory only: the next login restored nothing.
  group('dispose must not erase the persisted invites', skip: skipReason, () {
    const key = 'pending_group_invites_v1';

    test('a persist that resumes after the session closed keeps them',
        () async {
      service.debugNativePendingInvitesOverride = () => [_invite('tox_inv_1')];
      await service.debugPersistPendingGroupInvitesNowForTest();
      expect(await prefs.getString(key), contains('tox_inv_1'));

      service.debugCloseSessionForTest();
      expect(service.getPendingGroupInvites(), isEmpty,
          reason: 'the public getter is still gated by the closed session');
      await service.debugPersistPendingGroupInvitesNowForTest();
      expect(await prefs.getString(key), contains('tox_inv_1'),
          reason: 'the shutting-down session must not erase the copy');
    });

    test('an unreadable native list leaves the copy alone', () async {
      service.debugNativePendingInvitesOverride = () => [_invite('tox_inv_1')];
      await service.debugPersistPendingGroupInvitesNowForTest();
      service.debugNativePendingInvitesOverride = () => null; // cannot read
      await service.debugPersistPendingGroupInvitesNowForTest();
      expect(await prefs.getString(key), contains('tox_inv_1'));
    });

    test('the last invite being answered still clears the key', () async {
      service.debugNativePendingInvitesOverride = () => [_invite('tox_inv_1')];
      await service.debugPersistPendingGroupInvitesNowForTest();
      service.debugNativePendingInvitesOverride = () => const [];
      await service.debugPersistPendingGroupInvitesNowForTest();
      expect(await prefs.getString(key), isNull);
    });
  });

  group('accepted invites awaiting confirmation (#13)', skip: skipReason, () {
    test('an accepted invite stays persisted as joining', () {
      service.debugMarkInviteJoiningForTest(_invite('tox_inv_1'));
      final entries = service.debugPendingInviteEntriesForTest(const []);
      expect(entries, hasLength(1));
      expect(entries.single['id'], 'tox_inv_1');
      expect(entries.single['joining'], isTrue);
      expect(entries.single['cookie'], startsWith(_chatId));
    });

    test('an invite native hands back is unanswered again, not joining', () {
      final invite = _invite('tox_inv_1');
      service.debugMarkInviteJoiningForTest(invite);
      final entries = service.debugPendingInviteEntriesForTest([invite]);
      expect(entries, hasLength(1));
      expect(entries.single.containsKey('joining'), isFalse);
      expect(service.debugJoiningInviteIds, isEmpty);
    });

    test('the confirmed join of its group ends the wait', () async {
      service.debugMarkInviteJoiningForTest(_invite('tox_inv_1'));
      service.debugMarkInviteJoiningForTest(
          _invite('tox_inv_2', chatId: 'ff' * 32));

      await service.debugConfirmJoiningInvitesForTest(_chatId.toUpperCase());

      expect(service.debugJoiningInviteIds, ['tox_inv_2'],
          reason: 'only the invite that leads to the joined group is done');
    });
  });
}

/// In-memory preferences whose list reads and writes yield (like a real
/// store), so unserialized read-modify-writes interleave and lose updates.
class _SlowPrefs implements ExtendedPreferencesService {
  final Map<String, Object?> _store = {};
  final Random _random = Random(7);

  Future<void> _yield() =>
      Future<void>.delayed(Duration(milliseconds: _random.nextInt(3)));

  @override
  Future<String?> getString(String key) async => _store[key] as String?;

  @override
  Future<void> setString(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _store.remove(key);
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    await _yield();
    final value = _store[key];
    return value == null ? null : List<String>.from(value as List);
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    await _yield();
    _store[key] = List<String>.from(value);
  }

  @override
  Future<Set<String>> getStringSet(String key) async =>
      (await getStringList(key))?.toSet() ?? <String>{};

  @override
  Future<void> setStringSet(String key, Set<String> value) =>
      setStringList(key, value.toList());

  @override
  Future<String?> getGroupChatId(String groupId) async =>
      _store['chat_id_$groupId'] as String?;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '_SlowPrefs does not implement ${invocation.memberName}');
}
