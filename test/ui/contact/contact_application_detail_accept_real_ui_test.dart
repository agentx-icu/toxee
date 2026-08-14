// S108 — Friend-application DETAIL screen accept: real-UI L1 gate.
//
// S108's accept *data-path* (a friendship is actually created over the DHT) is
// inherently native (FFI `DartHandleFriendAddRequest`) and is covered TWO-PROCESS
// by `tool/mcp_test/run_fixture_c_accept.sh` + the `handshake_detail` 2proc-ui
// driver. That native success cannot be reproduced hermetically. What CAN be
// driven at L1 — and is what the existing anchor tests
// (`contact_application_detail_keys_test.dart`,
// `contact_application_info_anchors_test.dart`) do NOT cover — is:
//
//   1. A REAL tap on the keyed detail Accept button runs the PRODUCTION
//      `onAcceptApplication` end-to-end (button → bound handler → the real
//      `contactSDK.acceptFriendApplication` wrapper → the real friendship
//      manager). In a widget test the SDK is not initialized, so
//      `acceptFriendApplication` returns gracefully (ERR_SDK_NOT_INITIALIZED,
//      `tim_friendship_manager.dart:312`) WITHOUT touching FFI; the production
//      handler then runs its real graceful-failure path, which removes the
//      application from `dataInstance.contact` via the real `deleteApplicationList`
//      (`tencent_cloud_chat_contact_application_info.dart:305-306`). We seed an
//      application and assert it is gone — proving the button drives the REAL
//      handler (a regression that un-wired `onAcceptApplication`, or threw on the
//      not-init path, would fail this). The success "Accepted" state (resultCode
//      == 0) needs the native accept → stays L3/2proc.
//
//   2. The post-accept RESULT-DISPLAY UI: once `applicationResult` is populated
//      (what `onAcceptApplication` sets on success), the real `defaultBuilder`
//      branch (`:340-354`) shows the result text and REPLACES the accept/decline
//      buttons. We assert that real transition directly (hermetic).
//
// Mobile parity: the detail screen + its `contact_application_detail_accept_button`
// key + `onAcceptApplication` are SHARED UIKit-fork widgets (no platform split),
// so this L1 gate covers iOS/Android too; the native accept success is the same
// FFI path on every platform (and stays L3/2proc).
//
// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_models.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_application_info.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_leading.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

Widget _app(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: TencentCloudChatLocalizations.localizationsDelegates,
    supportedLocales: TencentCloudChatLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets(
    'S108: real-tapping the detail Accept button runs the production '
    'onAcceptApplication end-to-end (removes the application)',
    (tester) async {
      const userId = 'friend_detail_s108_accept';
      final application = V2TimFriendApplication(
        userID: userId,
        nickname: 'Detail Accept Friend',
        addWording: 'please add me',
        type: 1,
      );

      // Seed the application into the REAL contact data so the production
      // handler's real side-effect (deleteApplicationList) is observable.
      final contact = TencentCloudChat.instance.dataInstance.contact;
      contact.buildApplicationList([application], 'S108-seed');
      addTearDown(
        () => contact.deleteApplicationList([userId], 'S108-teardown'),
      );
      expect(
        contact.applicationList.any((a) => a.userID == userId),
        isTrue,
        reason: 'precondition: the seeded application is in the contact data',
      );

      await tester.pumpWidget(
        _app(
          TencentCloudChatContactApplicationInfoButton(
            application: application,
            applicationResult: ContactApplicationResult(result: '', userID: ''),
          ),
        ),
      );
      await tester.pump();

      // The real detail Accept button (wired to the bound production
      // onAcceptApplication, tencent_cloud_chat_contact_application_info.dart:374).
      final acceptKey = UiKeys.contactApplicationDetailAcceptButton(userId);
      expect(find.byKey(acceptKey), findsOneWidget);

      // REAL interaction: tap it. onAcceptApplication awaits the real SDK
      // wrapper; on the not-initialized L1 path it resolves gracefully and runs
      // the real application-cleanup branch.
      await tester.tap(find.byKey(acceptKey));
      await tester.pumpAndSettle();

      // Proof the PRODUCTION handler ran end-to-end (not a stub, not a no-op):
      // the application left the real contact data via onAcceptApplication's real
      // deleteApplicationList path. A regression un-wiring the button, or one that
      // threw on the not-init path, would fail here.
      expect(
        contact.applicationList.any((a) => a.userID == userId),
        isFalse,
        reason:
            'tapping the detail Accept button must run the production '
            'onAcceptApplication (which removes the application)',
      );

      // Hardening: the not-init path takes the graceful-FAILURE branch, so the
      // widget must NOT transition to its success result-display state (that only
      // happens on resultCode==0, the L3/2proc native-accept leg). The accept
      // button is therefore still mounted — proving we exercised the documented
      // not-init path, not a spurious success.
      expect(
        find.byKey(acceptKey),
        findsOneWidget,
        reason:
            'the not-init accept must NOT spuriously enter the success '
            'result-display state',
      );
    },
  );

  testWidgets(
    'S108: a populated applicationResult renders the result text and replaces '
    'the accept/decline buttons (real post-accept UI state)',
    (tester) async {
      const userId = 'friend_detail_s108_result';
      final application = V2TimFriendApplication(
        userID: userId,
        nickname: 'Detail Result Friend',
        type: 1,
      );
      final acceptKey = UiKeys.contactApplicationDetailAcceptButton(userId);
      final declineKey = UiKeys.contactApplicationDetailDeclineButton(userId);

      // Pre-accept surface: empty result → the action buttons render (non-vacuous
      // baseline for the transition below).
      await tester.pumpWidget(
        _app(
          TencentCloudChatContactApplicationInfoButton(
            application: application,
            applicationResult: ContactApplicationResult(result: '', userID: ''),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(acceptKey), findsOneWidget);
      expect(find.byKey(declineKey), findsOneWidget);

      // Post-accept surface: a populated result (matching the application's user)
      // — exactly what onAcceptApplication sets on success — drives the real
      // defaultBuilder result branch: the result text shows and the action
      // buttons are gone.
      await tester.pumpWidget(
        _app(
          TencentCloudChatContactApplicationInfoButton(
            application: application,
            applicationResult:
                ContactApplicationResult(result: 'Accepted-S108', userID: userId),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Accepted-S108'), findsOneWidget,
          reason: 'the populated result text must render');
      expect(find.byKey(acceptKey), findsNothing,
          reason: 'the result view replaces the accept button');
      expect(find.byKey(declineKey), findsNothing,
          reason: 'the result view replaces the decline button');
    },
  );

  testWidgets(
    'S108: the detail back affordance exposes a stable keyed target',
    (tester) async {
      await tester.pumpWidget(_app(const TencentCloudChatContactLeading()));
      await tester.pump();

      expect(
        find.byKey(UiKeys.contactDetailBack),
        findsOneWidget,
      );
    },
  );
}
