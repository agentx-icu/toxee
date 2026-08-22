// Group ingestion seam: self-authored rows and timestamp overrides.
//
// `ingestInboundGroupText` is the single seam the native type==10 event and
// the L3 seed harness share. Two contracts pinned here:
//
//  * a row FROM the login user (NGC echoing our own line, or a seeded self
//    line) is delivered history the user already read by writing it — it must
//    render as self and must NOT bump the group's unread count;
//  * `epochMs` backdates the row (timestamp AND the minted msgID) so a seeded
//    thread can carry realistic spacing instead of every line landing in the
//    same minute — without it the product screenshots showed eight group
//    messages all stamped with one minute.
//
// These assert the behavior of the real service, not source text.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

const _gid = '1122334455667788990011223344556677889900112233445566778899001122';
const _peer =
    'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE';
const _self = 'FlutterUIKitClient';

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

  group('FfiChatService.ingestInboundGroupText', () {
    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('ffi_group_self_');
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

    /// Disposed before the group tearDown deletes [tempRoot] (the history
    /// persistence debounces its writes behind a Timer).
    FfiChatService newService() {
      final service = FfiChatService();
      addTearDown(service.dispose);
      return service;
    }

    test(
      'a self-authored row renders as self and does not count as unread',
      () async {
        final service = newService()..debugSetSelfId(_self);

        final peerIngested = service.ingestInboundGroupText(
          gid: _gid,
          from: _peer,
          text: 'from the peer',
        );
        final selfIngested = service.ingestInboundGroupText(
          gid: _gid,
          from: _self,
          text: 'our own line, echoed',
        );

        expect(peerIngested, isTrue);
        expect(selfIngested, isTrue);
        expect(
          service.getUnreadOf('group_$_gid'),
          1,
          reason:
              'only the peer line is unread; the self line is something the '
              'user already read by writing it',
        );
        final last = service.lastMessages[_gid];
        expect(last, isNotNull);
        expect(last!.isSelf, isTrue);
        expect(last.fromUserId, _self);
      },
      skip: skipReason,
    );

    test('epochMs backdates the row and its minted msgID', () async {
      final service = newService();
      final backdated = DateTime.now()
          .subtract(const Duration(hours: 3))
          .millisecondsSinceEpoch;

      final ingested = service.ingestInboundGroupText(
        gid: _gid,
        from: _peer,
        text: 'three hours ago',
        epochMs: backdated,
      );

      expect(ingested, isTrue);
      final row = service.lastMessages[_gid]!;
      expect(row.timestamp.millisecondsSinceEpoch, backdated);
      expect(
        row.msgID,
        startsWith('${backdated}_'),
        reason: 'the msgID timestamp component follows the override too',
      );
    }, skip: skipReason);

    test(
      'without epochMs the row is stamped now (real delivery unchanged)',
      () async {
        final service = newService();
        final before = DateTime.now().millisecondsSinceEpoch;
        service.ingestInboundGroupText(gid: _gid, from: _peer, text: 'live');
        final after = DateTime.now().millisecondsSinceEpoch;
        final ts = service.lastMessages[_gid]!.timestamp.millisecondsSinceEpoch;
        expect(ts, inInclusiveRange(before, after));
      },
      skip: skipReason,
    );
  });
}
