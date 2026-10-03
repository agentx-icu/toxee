// A group message composed OFFLINE must still be able to collect read
// receipts after the app restarts before it is sent.
//
// The cross-peer identity of a group message (the `gmid:` alias) only exists
// once the message is on the wire, so the offline-queue drain stamps it onto
// the row it created at compose time. History loading clears `isPending` on
// every row from a previous session while the queue item survives the restart,
// and the drain used to look only at PENDING rows: the restarted row never got
// its alias and no receipt could ever correlate to it. The same test pins that
// the author's needReadReceipt intent rides on that row across the restart.

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart' as pkgffi;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';
import 'package:tim2tox_dart/utils/offline_message_queue_persistence.dart';

const _selfToxId =
    'ABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABAB0000000012EF';
const _selfGroupKey =
    'EFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEF';
const _groupId = 'drain-alias-group';

/// Answers identity, reports every group as wire-ready, and accepts group
/// sends, reporting toxcore's per-send message id like the real exports.
class _GroupSendFfi extends Tim2ToxFfi {
  _GroupSendFfi() : super.forTesting();

  int groupSends = 0;
  final ffi.Pointer<pkgffi.Utf8> _groupKey = _selfGroupKey.toNativeUtf8();

  static int _write(String s, ffi.Pointer<ffi.Int8> buf, int cap) {
    final bytes = utf8.encode(s);
    if (bytes.length + 1 > cap) return -(bytes.length + 1);
    final out = buf.cast<ffi.Uint8>().asTypedList(bytes.length + 1);
    out.setAll(0, bytes);
    out[bytes.length] = 0;
    return bytes.length;
  }

  @override
  int Function() get getCurrentInstanceId => () => 0;

  @override
  void Function() get uninit => () {};

  @override
  int Function(ffi.Pointer<ffi.Int8>, int) get getSelfToxId =>
      (buf, cap) => _write(_selfToxId, buf, cap);

  @override
  int Function(ffi.Pointer<ffi.Int8>, int) get getFriendList =>
      (buf, cap) => _write('', buf, cap);

  @override
  int Function(ffi.Pointer<pkgffi.Utf8>) get groupWireReady => (_) => 1;

  @override
  int Function(ffi.Pointer<pkgffi.Utf8>, ffi.Pointer<pkgffi.Utf8>)
      get sendGroupText => (_, __) {
            groupSends++;
            return 1;
          };

  @override
  int Function() get lastGroupSendMessageId => () => 4242;

  @override
  ffi.Pointer<pkgffi.Utf8> Function() get lastGroupSendSelfKey =>
      () => _groupKey;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _GroupSendFfi ffiStub;

  FfiChatService open() => FfiChatService(
        ffiForTesting: ffiStub,
        messageHistoryPersistence: MessageHistoryPersistence(
          historyDirectory: p.join(tempDir.path, 'history'),
        ),
        offlineMessageQueuePersistence: OfflineMessageQueuePersistence(
          queueFilePath: p.join(tempDir.path, 'offline_queue.json'),
        ),
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('group_drain_alias_');
    await Directory(p.join(tempDir.path, 'history')).create(recursive: true);
    ffiStub = _GroupSendFfi();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('a group text queued before a restart gets its gmid alias on drain',
      () async {
    // Session 1: offline compose with receipt intent, then "quit".
    final before = open();
    before.debugSetConnected(false);
    before.armNextSendNeedReadReceipt(true);
    final queued = await before.sendGroupTextWithResult(
      _groupId,
      'composed offline',
      clientMessageID: 'client-drain-1',
    );
    expect(queued.isPending, isTrue);
    expect(ffiStub.groupSends, 0);
    await before.dispose();

    // Session 2: the queue item survived; history loading cleared isPending.
    final after = open();
    addTearDown(after.dispose);
    await after.offlineMessageQueuePersistence.loadQueue();
    await after.loadHistory(_groupId);
    final reloaded = after.getHistory(_groupId).single;
    expect(reloaded.msgID, 'client-drain-1');
    expect(reloaded.isPending, isFalse);
    expect(reloaded.needReadReceipt, isTrue,
        reason: 'the author-local intent rides on the persisted row');
    expect(reloaded.altMsgIds, isEmpty);

    after.debugSetConnected(true);
    await after.retryPendingGroupMessages(_groupId);

    expect(ffiStub.groupSends, 1);
    final drained = after.getHistory(_groupId).single;
    expect(
      drained.altMsgIds.where((id) => id.startsWith('gmid:')),
      hasLength(1),
      reason: 'without the alias no read receipt can correlate to this row',
    );
    expect(drained.needReadReceipt, isTrue);
    expect(
      after.offlineMessageQueuePersistence.getMessages('group:$_groupId'),
      isEmpty,
    );
    final alias = drained.altMsgIds.single;

    // Read the file through a fresh session BEFORE session 2 is disposed:
    // dispose flushes dirty history, which would hide a missing drain save.
    // The queue item is gone, so the alias must already be on disk.
    final third = open();
    addTearDown(third.dispose);
    await third.loadHistory(_groupId);
    expect(third.getHistory(_groupId).single.altMsgIds, [alias]);
  });

  test('a legacy queue item without msgID never stamps a settled row',
      () async {
    // A restarted row and a pre-msgID queue item that only share the
    // millisecond: the timestamp fallback is ambiguous, so the pending gate
    // still applies and nothing is stamped.
    final before = open();
    before.debugSetConnected(false);
    final row = await before.sendGroupTextWithResult(_groupId, 'legacy text');
    await before.dispose();
    final queueFile = File(p.join(tempDir.path, 'offline_queue.json'));
    final queued = jsonDecode(await queueFile.readAsString()) as Map;
    for (final item in (queued['group:$_groupId'] as List)) {
      (item as Map).remove('msgID');
    }
    await queueFile.writeAsString(jsonEncode(queued));

    final after = open();
    addTearDown(after.dispose);
    await after.offlineMessageQueuePersistence.loadQueue();
    await after.loadHistory(_groupId);
    expect(after.getHistory(_groupId).single.msgID, row.msgID);
    after.debugSetConnected(true);
    await after.retryPendingGroupMessages(_groupId);

    expect(ffiStub.groupSends, 1, reason: 'the message itself still goes out');
    expect(after.getHistory(_groupId).single.altMsgIds, isEmpty);
  });
}
