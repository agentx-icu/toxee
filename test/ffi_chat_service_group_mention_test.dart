// GT-8: a mention travels as the "@name " text UIKit's picker inserts (the
// Tox wire has no mention list), so it is recognised on the receiving side.
// These pin the matcher and the unread-scoped "@me" flag.

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

void main() {
  late FfiChatService service;

  setUp(() async {
    service = FfiChatService();
    await service.updateSelfProfile(nickname: 'Ann', statusMessage: '');
  });

  test('matches @name followed by a boundary, not a longer name', () {
    expect(service.textMentionsSelf('@Ann hello'), isTrue);
    expect(service.textMentionsSelf('hi @Ann'), isTrue);
    expect(service.textMentionsSelf('hi @Ann, look'), isTrue);
    expect(service.textMentionsSelf('你好 @Ann，看这个'), isTrue);
    expect(service.textMentionsSelf('@Anna hello'), isFalse);
    expect(service.textMentionsSelf('Ann hello'), isFalse);
    expect(service.textMentionsSelf('@Anna and @Ann'), isTrue);
  });

  test('no nickname means no mention', () async {
    await service.updateSelfProfile(nickname: '  ', statusMessage: '');
    expect(service.textMentionsSelf('@ hello'), isFalse);
  });
}
