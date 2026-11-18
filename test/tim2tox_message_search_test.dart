// L1 gate for S93 — the in-conversation message search MATCHER, the pure core
// of the `Tim2ToxSdkPlatform.searchLocalMessages` fix (the C++
// `SearchLocalMessages` is an empty stub, so toxee's message search was
// returning nothing until this override searched the Dart-side history).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_param.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/sdk/message_search.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

ChatMessage _msg(
  String text, {
  String? fileName,
  String? mediaKind,
  bool isSelf = false,
}) =>
    ChatMessage(
      text: text,
      fromUserId: isSelf ? 'self' : 'peer',
      isSelf: isSelf,
      timestamp: DateTime(2024, 1, 1),
      fileName: fileName,
      mediaKind: mediaKind,
      msgID: 'm',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');
  final nativePath = Platform.environment['TOXEE_TEST_LOG_LIBRARY'];
  if (nativePath != null) setNativeLibraryPath(nativePath);
  final nativeAvailable = _nativeAvailable();

  test(
    'SDK search joins cold, recent, and archived hits without duplicates',
    () async {
      final dir = await Directory.systemTemp.createTemp('tim2tox_search_');
      addTearDown(() => dir.delete(recursive: true));
      const peer =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const archiveOnly =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      const coldOnly =
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
      ChatMessage hit(String id, String sender, int seconds) => ChatMessage(
        text: 'pizza',
        fromUserId: sender,
        isSelf: false,
        timestamp: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
        msgID: id,
      );

      final previousHandler = NativeLibraryManager.customCallbackHandler;
      final persistence = MessageHistoryPersistence(historyDirectory: dir.path);
      final service = FfiChatService(messageHistoryPersistence: persistence);
      final platform = Tim2ToxSdkPlatform(ffiService: service);
      addTearDown(() async {
        platform.dispose();
        NativeLibraryManager.customCallbackHandler = previousHandler;
        await service.dispose();
      });
      final recent = hit('recent', peer, 1700000002);
      final archived = hit('archived', peer, 1700000001);
      await persistence.saveHistory(peer, [recent]);
      await persistence.saveHistory(coldOnly, [
        hit('cold-only', coldOnly, 1700000003),
      ]);
      await File('${dir.path}/$peer.archive.jsonl').writeAsString(
        '${jsonEncode(archived.toJson())}\n${jsonEncode(recent.toJson())}\n',
      );
      await File('${dir.path}/$archiveOnly.archive.jsonl').writeAsString(
        '${jsonEncode(hit('archive-only', archiveOnly, 1700000000).toJson())}\n',
      );
      persistence.clearAllCached();

      final scoped = await platform.searchLocalMessages(
        searchParam: V2TimMessageSearchParam(
          type: 0,
          conversationID: 'c2c_$peer',
          keywordList: ['Pizza'],
        ),
      );
      expect(scoped.code, 0);
      expect(scoped.data!.totalCount, 2);
      expect(
        scoped.data!.messageSearchResultItems!.single.messageList!.map(
          (m) => m.msgID,
        ),
        ['archived', 'recent'],
      );

      final global = await platform.searchLocalMessages(
        searchParam: V2TimMessageSearchParam(type: 0, keywordList: ['pizza']),
      );
      expect(global.code, 0);
      expect(global.data!.totalCount, 3);
      expect(
        global.data!.messageSearchResultItems!.expand(
          (item) => item.messageList!.map((m) => m.msgID),
        ),
        unorderedEquals(['archived', 'recent', 'archive-only', 'cold-only']),
      );
    },
    skip: nativeAvailable ? null : 'tim2tox FFI library not loadable',
  );

  group('S93 chatMessageMatchesKeywords', () {
    test('case-insensitive substring on the bubble text', () {
      final m = _msg('Order a Pizza tonight');
      expect(chatMessageMatchesKeywords(m, keywords: ['pizza'], matchAll: false),
          isTrue);
      expect(chatMessageMatchesKeywords(m, keywords: ['PIZZA'], matchAll: false),
          isTrue,
          reason: 'match must be case-insensitive');
      expect(chatMessageMatchesKeywords(m, keywords: ['burger'], matchAll: false),
          isFalse);
    });

    test('OR matches ANY keyword; AND requires ALL', () {
      final m = _msg('pizza and salad');
      expect(
          chatMessageMatchesKeywords(m,
              keywords: ['pizza', 'burger'], matchAll: false),
          isTrue,
          reason: 'OR: pizza present');
      expect(
          chatMessageMatchesKeywords(m,
              keywords: ['pizza', 'burger'], matchAll: true),
          isFalse,
          reason: 'AND: burger absent');
      expect(
          chatMessageMatchesKeywords(m,
              keywords: ['pizza', 'salad'], matchAll: true),
          isTrue,
          reason: 'AND: both present');
    });

    test('a file message matches by its fileName', () {
      final m = _msg('', fileName: 'quarterly-pizza-report.pdf', mediaKind: 'file');
      expect(chatMessageMatchesKeywords(m, keywords: ['pizza'], matchAll: false),
          isTrue,
          reason: 'owned payload fields include fileName, not just text');
    });

    test('control-signal messages are NEVER searchable', () {
      for (final prefix in kSearchControlSignalPrefixes) {
        final m = _msg('${prefix}pizza{"x":1}');
        expect(
            chatMessageMatchesKeywords(m, keywords: ['pizza'], matchAll: false),
            isFalse,
            reason: '$prefix messages must be excluded from search results');
      }
    });

    test('empty / whitespace keywords are ignored; no effective keyword matches '
        'nothing', () {
      final m = _msg('pizza');
      expect(chatMessageMatchesKeywords(m, keywords: [], matchAll: false), isFalse);
      expect(chatMessageMatchesKeywords(m, keywords: ['   '], matchAll: false),
          isFalse);
      // An empty keyword is dropped, leaving 'pizza' which matches (OR and AND).
      expect(chatMessageMatchesKeywords(m, keywords: ['', 'pizza'], matchAll: false),
          isTrue);
      expect(chatMessageMatchesKeywords(m, keywords: ['', 'pizza'], matchAll: true),
          isTrue,
          reason: 'AND must ignore the empty keyword, not fail on it');
    });
  });

  group('S93 isSearchableMessage', () {
    test('excludes control-signal carriers, allows normal messages', () {
      expect(isSearchableMessage(_msg('hello there')), isTrue);
      expect(isSearchableMessage(_msg('', fileName: 'doc.pdf', mediaKind: 'file')),
          isTrue);
      for (final prefix in kSearchControlSignalPrefixes) {
        expect(isSearchableMessage(_msg('${prefix}payload')), isFalse,
            reason: '$prefix is a control signal, not a searchable bubble');
      }
    });
  });

  group('S93 effectiveKeywords', () {
    test('trims, lower-cases, and drops empty/whitespace entries', () {
      expect(effectiveKeywords(['  Pizza ', '', '   ', 'SALAD']),
          <String>['pizza', 'salad']);
      expect(effectiveKeywords(<String>[]), isEmpty);
      expect(effectiveKeywords(['   ']), isEmpty);
    });
  });
}

bool _nativeAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}
