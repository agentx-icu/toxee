import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/home/desktop_input_options.dart';

typedef _Friend = ({
  String userId,
  String nickName,
  bool online,
  String status,
});

class _DelayedFriendsService implements FfiChatService {
  final friends = Completer<List<_Friend>>();
  @override
  Future<List<_Friend>> getFriendList() => friends.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'a personal-card lookup does not read an unmounted composer context',
    (tester) async {
      final service = _DelayedFriendsService();
        var options = <TencentCloudChatMessageGeneralOptionItem>[];
      final messages = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              options = buildToxeeDesktopInputOptions(
                context,
                userID: 'A' * 64,
                service: service,
                pickAndSendFile: (context, {userId, groupId}) async {},
                showSnackBar: messages.add,
                createSelfQrCardImage: () async =>
                    throw StateError('No card should be generated'),
              );
              return const SizedBox();
            },
          ),
        ),
      );
      final card = options.singleWhere(
        (option) => option.icon == Icons.qr_code_2,
      );
      final pending = card.onTap();
      await tester.pumpWidget(const SizedBox());
      service.friends.complete([]);
      await pending;
      expect(messages, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
