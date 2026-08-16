// Group unread writer/reader key contract.
//
// `_unreadByPeer` is reached from both hybrid paths with differently-shaped
// conversation ids: the native/binary-replacement path forwards the raw `gid`
// carried by the message, while the Platform path and the conversation list
// speak `group_<gid>`. Before the canonical-key fix the writer stored under
// whichever shape it was handed and the reader looked under another, so a
// group badge silently read 0 while the C2C entries still counted — the
// `C2C=2 / group=0 / total=2` symptom seen in the P1 chat campaign.
//
// These assert the behavior of the real service, not source text.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/binary_replacement_history_hook.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

/// A realistic 64-char group id (normalization is identity for this shape, so
/// the test isolates the PREFIX mismatch rather than a truncation artifact).
const _gid = '1122334455667788990011223344556677889900112233445566778899001122';

/// Public key used as the inbound sender.
const _peer =
    'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE';

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

  group('FfiChatService group unread key contract', () {
    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('ffi_group_unread_');
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

    /// Build a service that is torn down before [tempRoot] is deleted.
    ///
    /// Every test here builds a REAL [FfiChatService], which owns a
    /// [MessageHistoryPersistence] writing into the mocked AppSupport root
    /// (`tempRoot`). Its appends are DEBOUNCED behind a Timer, so an undisposed
    /// service can land a file in `tempRoot` after the group `tearDown` has
    /// begun deleting it — `delete(recursive: true)` then fails with
    /// `Directory not empty` (errno 66). That is a load-dependent race: it
    /// never reproduced running this file alone, only inside the full
    /// `flutter test` run.
    ///
    /// `dispose()` flushes pending saves and cancels the debounce timers, and
    /// test-scoped `addTearDown` callbacks run BEFORE the enclosing group
    /// `tearDown`, so the writer is provably stopped before the delete.
    FfiChatService newService() {
      final service = FfiChatService();
      addTearDown(service.dispose);
      return service;
    }

    /// Same contract for the standalone persistence instances the hook tests
    /// construct directly.
    MessageHistoryPersistence newPersistence({required int instanceId}) {
      final persistence = MessageHistoryPersistence(instanceId: instanceId);
      addTearDown(persistence.dispose);
      return persistence;
    }

    test(
      'a prefixed writer and a raw reader address the same unread bucket',
      () async {
        final service = newService();
        await service.registerJoinedGroupState(_gid);

        // The Platform path hands the group id along in the `group_` shape.
        service.incrementGroupUnread('group_$_gid');
        service.incrementGroupUnread('group_$_gid');

        expect(
          service.getUnreadOf(_gid),
          2,
          reason:
              'Regression: incrementGroupUnread stored under the raw '
              'argument, so a `group_`-prefixed write landed in a bucket the '
              'sidebar (which reads the bare gid) never looks at — the badge '
              'read 0 while messages kept arriving.',
        );
        expect(
          service.getUnreadOf('group_$_gid'),
          2,
          reason: 'both id shapes must resolve to the one canonical key',
        );
      },
      skip: skipReason,
    );

    test(
      'a raw writer is readable through the prefixed conversation id',
      () async {
        final service = newService();
        await service.registerJoinedGroupState(_gid);

        // The native path forwards the raw gid off the message.
        service.incrementGroupUnread(_gid);

        expect(service.getUnreadOf('group_$_gid'), 1);
        expect(service.getUnreadOf(_gid), 1);
      },
      skip: skipReason,
    );

    test(
      'opening the conversation zeroes the badge regardless of id shape',
      () async {
        final service = newService();
        await service.registerJoinedGroupState(_gid);
        service.incrementGroupUnread(_gid);
        expect(service.getUnreadOf(_gid), 1);

        // The UI marks the prefixed conversation id active...
        service.setActivePeer('group_$_gid');
        expect(service.getUnreadOf(_gid), 0);

        // ...and a further inbound for the OPEN conversation must not
        // re-raise the badge, which requires the active-peer comparison to be
        // normalized too.
        service.incrementGroupUnread('group_$_gid');
        expect(
          service.getUnreadOf(_gid),
          0,
          reason:
              'incrementGroupUnread compared a raw/prefixed argument '
              'against the normalized _activePeerId, so the conversation the '
              'user was looking at kept accruing unread',
        );
      },
      skip: skipReason,
    );

    test(
      'an inbound group message still counts when the emit is suppressed',
      () async {
        // THE PRODUCT CONFIGURATION: UIKit owns the inbound listener surface,
        // so `_emitInboundMessage` suppresses `_messages.add`, AND
        // `groupUnreadHandledExternally` is true (set by
        // SessionRuntimeCoordinator) to hand the unread bump to
        // Tim2ToxSdkPlatform's `messages.listen`. Those two together used to
        // leave the bump with NO owner: the listener never ran because the
        // message never reached the stream, and this service skipped the bump
        // waiting for it. Group unread stayed 0 for every inbound group
        // message — the real `C2C=2 / group=0 / total=2` sidebar symptom that
        // the key-normalization tests above do NOT catch (a bare `tox_N` gid
        // normalizes to itself, so key shape was never the failing part).
        final service = newService();
        await service.registerJoinedGroupState(_gid);
        service.groupUnreadHandledExternally = true;
        BinaryReplacementHistoryHook.initialize(
          newPersistence(instanceId: 999321),
          'SELF',
        );
        addTearDown(BinaryReplacementHistoryHook.uninstallStandalone);
        expect(
          BinaryReplacementHistoryHook.ownsInboundMessageHistory,
          isTrue,
          reason:
              'precondition: the emit must be suppressed for this test to '
              'reproduce the product configuration',
        );

        final ingested = service.ingestInboundGroupText(
          gid: _gid,
          from: _peer,
          text: 'group hello',
        );

        expect(ingested, isTrue);
        expect(
          service.getUnreadOf(_gid),
          1,
          reason:
              'Regression: the unread bump was deferred to a '
              'messages.listen subscriber that never runs when the emit is '
              'suppressed, so no one counted the message.',
        );
      },
      skip: skipReason,
    );

    test(
      'a control signal reaches the stream even when normal emits are suppressed',
      () async {
        // `__revoke__:` is a COMMAND, not a displayable message. The only
        // receive-side handler that deletes the recalled row
        // (Tim2ToxSdkPlatform._maybeInterceptControlSignal) runs from
        // `messages.listen`, so a suppressed emit drops the recall on the
        // floor — the peer keeps the message forever. That is the `bGone=false`
        // half of the real-UI chat_recall_message failure.
        final service = newService();
        await service.registerJoinedGroupState(_gid);
        BinaryReplacementHistoryHook.initialize(
          newPersistence(instanceId: 999322),
          'SELF',
        );
        addTearDown(BinaryReplacementHistoryHook.uninstallStandalone);

        final seen = <String>[];
        final sub = service.messages.listen((m) => seen.add(m.text));
        addTearDown(sub.cancel);

        service.ingestInboundGroupText(
          gid: _gid,
          from: _peer,
          text: 'a plain message',
        );
        service.ingestInboundGroupText(
          gid: _gid,
          from: _peer,
          text: '__revoke__:{"msgID":"x"}',
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          seen,
          isNot(contains('a plain message')),
          reason:
              'a normal inbound stays suppressed — the native advanced '
              'listener already surfaced it',
        );
        expect(
          seen,
          contains('__revoke__:{"msgID":"x"}'),
          reason:
              'Regression: the control signal was suppressed alongside '
              'ordinary messages, so the revoke interceptor never ran.',
        );
      },
      skip: skipReason,
    );

    // NOTE: the matching `_quitGroups` normalization (a `group_`-prefixed id
    // must not slip past the quit filter) is deliberately NOT covered here —
    // `quitGroup()` performs a real `DartQuitGroup` FFI round-trip and awaits a
    // native callback, so it cannot run in a unit test. It is exercised by the
    // group real-UI sweeps instead.
  });
}
