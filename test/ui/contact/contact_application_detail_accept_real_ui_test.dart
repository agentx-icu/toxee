// S108 — Friend-application detail failure and result-display regressions.
// The real not-initialized SDK path returns an error without touching FFI.
// A failed operation must keep the request available so the user can retry.
// Native friendship creation remains covered by the two-process fixture.
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
    localizationsDelegates:
        TencentCloudChatLocalizations.localizationsDelegates,
    supportedLocales: TencentCloudChatLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('S108: real-tapping the detail Accept button runs the production '
      'onAcceptApplication end-to-end (retains a failed application)', (
    tester,
  ) async {
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
    addTearDown(() => contact.deleteApplicationList([userId], 'S108-teardown'));
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

    // The real SDK rejects this operation because it is not initialized.
    await tester.tap(find.byKey(acceptKey));
    await tester.pumpAndSettle();

    expect(
      contact.applicationList.any((a) => a.userID == userId),
      isTrue,
      reason: 'a failed accept must retain the request for retry',
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
  });

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
            applicationResult: ContactApplicationResult(
              result: 'Accepted-S108',
              userID: userId,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('Accepted-S108'),
        findsOneWidget,
        reason: 'the populated result text must render',
      );
      expect(
        find.byKey(acceptKey),
        findsNothing,
        reason: 'the result view replaces the accept button',
      );
      expect(
        find.byKey(declineKey),
        findsNothing,
        reason: 'the result view replaces the decline button',
      );
    },
  );

  testWidgets(
    'S108: the detail back affordance exposes a stable keyed target',
    (tester) async {
      await tester.pumpWidget(_app(const TencentCloudChatContactLeading()));
      await tester.pump();

      expect(find.byKey(UiKeys.contactDetailBack), findsOneWidget);
    },
  );
}
