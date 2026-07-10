// P1 regression guard: platforms without a camera capture backend
// (Windows/Linux) must not offer video-call entry points — voice stays, video
// hides. The gate is the fork-level `useVideoCall` flag, set at session init
// from CallMediaCapabilities.supportsVideoCapture().
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_user_profile_body.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_header/tencent_cloud_chat_message_header_actions.dart';

Widget _host(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: TencentCloudChatLocalizations.localizationsDelegates,
    supportedLocales: TencentCloudChatLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  tearDown(() {
    // Global UIKit data flag — restore the default so other tests are
    // unaffected.
    TencentCloudChat.instance.dataInstance.basic.useVideoCall = true;
  });

  group('chat header call actions', () {
    testWidgets('useVideoCall=false hides the video button, keeps voice',
        (tester) async {
      await tester.pumpWidget(_host(TencentCloudChatMessageHeaderActions(
        useCallKit: true,
        useVideoCall: false,
        startVoiceCall: () {},
        startVideoCall: () {},
      )));

      expect(find.byKey(const ValueKey('chat_call_voice_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_call_video_button')), findsNothing);
    });

    testWidgets('useVideoCall defaults to true (both buttons shown)',
        (tester) async {
      await tester.pumpWidget(_host(TencentCloudChatMessageHeaderActions(
        useCallKit: true,
        startVoiceCall: () {},
        startVideoCall: () {},
      )));

      expect(find.byKey(const ValueKey('chat_call_voice_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_call_video_button')), findsOneWidget);
    });
  });

  group('friend profile tiles', () {
    testWidgets('useVideoCall=false drops the video tile (Send + Voice only)',
        (tester) async {
      TencentCloudChat.instance.dataInstance.basic.useVideoCall = false;

      await tester.pumpWidget(_host(TencentCloudChatUserProfileChatButton(
        userFullInfo: V2TimUserFullInfo(userID: 'some-user'),
        isNavigatedFromChat: true,
      )));

      expect(
        find.byKey(const ValueKey('friend_profile_voice_call_tile')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('friend_profile_video_call_tile')),
        findsNothing,
      );
    });

    testWidgets('useVideoCall=true keeps all three tiles', (tester) async {
      TencentCloudChat.instance.dataInstance.basic.useVideoCall = true;

      await tester.pumpWidget(_host(TencentCloudChatUserProfileChatButton(
        userFullInfo: V2TimUserFullInfo(userID: 'some-user'),
        isNavigatedFromChat: true,
      )));

      expect(
        find.byKey(const ValueKey('friend_profile_voice_call_tile')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('friend_profile_video_call_tile')),
        findsOneWidget,
      );
    });
  });
}
