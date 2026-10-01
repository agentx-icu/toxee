// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_callbacks.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_models.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact_builders.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_application_info.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_application_list.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';

class _Platform extends TencentCloudChatSdkPlatform {
  int calls = 0;
  Completer<V2TimValueCallback<V2TimFriendOperationResult>>? pending;
  String outcome = 'failure';

  @override
  bool get isCustomPlatform => true;

  Future<V2TimValueCallback<V2TimFriendOperationResult>> _respond(String id) {
    calls++;
    if (pending != null) return pending!.future;
    if (outcome == 'exception') return Future.error(StateError('offline'));
    return Future.value(
      V2TimValueCallback(
        code: outcome == 'outer-error' ? 54 : 0,
        desc: 'ok',
        data: V2TimFriendOperationResult(
          userID: id,
          resultCode: outcome == 'success' || outcome == 'outer-error' ? 0 : 17,
        ),
      ),
    );
  }

  @override
  Future<V2TimValueCallback<V2TimFriendOperationResult>>
  acceptFriendApplication({
    required int responseType,
    required int type,
    required String userID,
  }) => _respond(userID);

  @override
  Future<V2TimValueCallback<V2TimFriendOperationResult>>
  refuseFriendApplication({required int type, required String userID}) =>
      _respond(userID);
}

Widget _app(Widget child, {double width = 800, double scale = 1}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates:
        TencentCloudChatLocalizations.localizationsDelegates,
    supportedLocales: TencentCloudChatLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) {
          TencentCloudChatIntl().init(context);
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, child: child),
            ),
          );
        },
      ),
    ),
  );
}

Widget _surface(String surface, V2TimFriendApplication request) {
  final result = ContactApplicationResult(result: '', userID: '');
  if (surface == 'detail') {
    return TencentCloudChatContactApplicationInfoButton(
      application: request,
      applicationResult: result,
    );
  }
  return TencentCloudChatContactApplicationItem(application: request);
}

Finder _button(String surface, bool accept, String id) => find.byKey(
  ValueKey(
    'contact_application_${surface == 'detail' ? 'detail_' : ''}${accept ? 'accept' : 'decline'}_button:$id',
  ),
);

Future<void> _tap(
  WidgetTester tester,
  String surface,
  bool accept,
  String id,
) async {
  if (surface != 'menu') {
    await tester.tap(_button(surface, accept, id));
    return;
  }
  final gesture = await tester.startGesture(
    tester.getTopLeft(find.byKey(ValueKey('contact_application_item:$id'))) +
        const Offset(20, 20),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
  final item = find.widgetWithText(
    PopupMenuItem<String>,
    accept ? 'Accept' : 'Reject',
  );
  expect(item, findsOneWidget);
  await tester.tap(item);
}

void main() {
  late _Platform platform;
  late List<String> notifications;
  late TencentCloudChatCallbacks callbacks;

  setUp(() {
    final old = TencentCloudChatSdkPlatform.instance;
    platform = _Platform();
    TencentCloudChatSdkPlatform.instance = platform;
    addTearDown(() => TencentCloudChatSdkPlatform.instance = old);
    final contact = TencentCloudChat.instance.dataInstance.contact;
    final oldBuilder = contact.contactBuilder;
    contact.contactBuilder = TencentCloudChatContactBuilders();
    addTearDown(() => contact.contactBuilder = oldBuilder);
    notifications = [];
    callbacks = TencentCloudChatCallbacks(
      onTencentCloudChatUIKitUserNotificationEvent: (component, event) =>
          notifications.add(event.text),
    );
    TencentCloudChat.instance.callbacks.addCallback(callbacks);
    addTearDown(
      () => TencentCloudChat.instance.callbacks.removeCallback(callbacks),
    );
  });

  V2TimFriendApplication seed(String id) {
    final request = V2TimFriendApplication(
      userID: id,
      nickname: 'Alice',
      type: 1,
    );
    final contact = TencentCloudChat.instance.dataInstance.contact;
    contact.buildApplicationList([request], 'operation-test');
    addTearDown(
      () => contact.deleteApplicationList([id], 'operation-test-teardown'),
    );
    return request;
  }

  for (final replacePlatform in [false, true]) {
    for (final outcome in ['success', 'failure', 'exception']) {
      testWidgets(
        'account switch isolates $outcome with ${replacePlatform ? "same login alias and new SDK session" : "different account ID"}',
        (tester) async {
          final id = 'same-applicant-$replacePlatform-$outcome';
          final basic = TencentCloudChat.instance.dataInstance.basic;
          final oldUser = basic.currentUser;
          final oldLogin = basic.hasLoggedIn;
          addTearDown(() {
            if (oldUser == null) {
              basic.clear();
            } else {
              basic.updateCurrentUserInfo(userFullInfo: oldUser);
            }
            basic.updateLoginStatus(status: oldLogin);
          });
          basic.updateCurrentUserInfo(
            userFullInfo: V2TimUserFullInfo(
              userID: replacePlatform ? 'FlutterUIKitClient' : 'account-a',
            ),
          );
          final oldPlatform = platform;
          final oldCompletion =
              Completer<V2TimValueCallback<V2TimFriendOperationResult>>();
          oldPlatform.pending = oldCompletion;
          addTearDown(() async {
            if (!oldCompletion.isCompleted) {
              oldCompletion.complete(
                V2TimValueCallback(code: -1, desc: 'test cleanup'),
              );
            }
            await Future<void>.delayed(Duration.zero);
          });
          await tester.pumpWidget(_app(_surface('detail', seed(id))));
          await _tap(tester, 'detail', true, id);
          await tester.pump();
          expect(oldPlatform.calls, 1);
          await tester.pumpWidget(_app(const SizedBox()));

          // Runtime installs a new Tim2Tox SDK platform on each account switch;
          // all real toxee accounts may still use the same UIKit login alias.
          if (replacePlatform) {
            platform = _Platform();
            TencentCloudChatSdkPlatform.instance = platform;
          } else {
            basic.updateCurrentUserInfo(
              userFullInfo: V2TimUserFullInfo(userID: 'account-b'),
            );
          }
          final newCompletion =
              Completer<V2TimValueCallback<V2TimFriendOperationResult>>();
          platform.pending = newCompletion;
          addTearDown(() async {
            if (!newCompletion.isCompleted) {
              newCompletion.complete(
                V2TimValueCallback(code: -1, desc: 'test cleanup'),
              );
            }
            await Future<void>.delayed(Duration.zero);
          });
          final contact = TencentCloudChat.instance.dataInstance.contact;
          contact.deleteApplicationList([id], 'old-account-teardown');
          await tester.pumpWidget(_app(_surface('detail', seed(id))));
          contact.setApplicationCode(23, 'new-account-sentinel');
          await _tap(tester, 'detail', false, id);
          await tester.pump();

          if (outcome == 'exception') {
            oldCompletion.completeError(StateError('old account offline'));
          } else {
            oldCompletion.complete(
              V2TimValueCallback(
                code: 0,
                desc: 'old result',
                data: V2TimFriendOperationResult(
                  userID: id,
                  resultCode: outcome == 'success' || outcome == 'outer-error'
                      ? 0
                      : 17,
                ),
              ),
            );
          }
          await tester.pumpAndSettle();
          expect(
            contact.applicationList.any((r) => r.userID == id),
            isTrue,
            reason:
                'an old account completion must not delete the current account request',
          );
          expect(
            contact.applicationCode,
            23,
            reason:
                'an old account must not update current account operation data',
          );
          expect(contact.applicationUserID, 'new-account-sentinel');
          expect(
            notifications,
            isEmpty,
            reason: 'old account failures must not surface in the new session',
          );
          expect(
            platform.calls,
            replacePlatform ? 1 : 2,
            reason:
                'new account must not inherit another session operation guard',
          );
          expect(
            tester.widget<TextButton>(_button('detail', false, id)).onPressed,
            isNull,
            reason: 'old completion must not release the new account guard',
          );
          newCompletion.complete(
            V2TimValueCallback(
              code: 0,
              desc: 'current result',
              data: V2TimFriendOperationResult(userID: id, resultCode: 0),
            ),
          );
          await tester.pumpAndSettle();
          expect(contact.applicationList.any((r) => r.userID == id), isFalse);
          expect(find.text('Declined'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final surface in ['list', 'detail', 'menu']) {
    for (final accept in [true, false]) {
      for (final outcome in [
        'success',
        'failure',
        'exception',
        'outer-error',
      ]) {
        testWidgets(
          '$surface ${accept ? 'accept' : 'refuse'} $outcome keeps correct request state',
          (tester) async {
            final id = '$surface-$accept-$outcome';
            platform.outcome = outcome;
            await tester.pumpWidget(_app(_surface(surface, seed(id))));
            await _tap(tester, surface, accept, id);
            await tester.pumpAndSettle();
            expect(platform.calls, 1);
            expect(tester.takeException(), isNull);
            expect(
              TencentCloudChat.instance.dataInstance.contact.applicationList
                  .any((r) => r.userID == id),
              outcome != 'success',
            );
            if (outcome == 'success') {
              expect(notifications, isEmpty);
              expect(
                find.text(accept ? 'Accepted' : 'Declined'),
                findsOneWidget,
              );
            } else {
              expect(notifications, ['Operation failed. Please try again.']);
              await _tap(tester, surface, accept, id);
              await tester.pumpAndSettle();
              expect(platform.calls, 2, reason: 'failure must permit retry');
            }
          },
        );
      }
    }

    testWidgets(
      '$surface suppresses repeated operations until request completes',
      (tester) async {
        final id = '$surface-pending';
        platform.pending = Completer();
        await tester.pumpWidget(_app(_surface(surface, seed(id))));
        await _tap(tester, surface, true, id);
        await tester.pump();
        if (surface == 'menu') {
          // The same request can be addressed by the row buttons while the menu
          // operation is pending. They must share the operation guard.
          await tester.tap(_button('list', false, id));
        } else {
          await tester.tap(_button(surface, false, id));
          await tester.tap(_button(surface, true, id));
        }
        await tester.pump();
        expect(platform.calls, 1);
        platform.pending!.complete(
          V2TimValueCallback(
            code: 0,
            desc: 'ok',
            data: V2TimFriendOperationResult(userID: id, resultCode: 17),
          ),
        );
        await tester.pumpAndSettle();
        await _tap(tester, surface, false, id);
        await tester.pumpAndSettle();
        expect(platform.calls, 2);
      },
    );

    testWidgets('$surface completion after dispose has no state error', (
      tester,
    ) async {
      final id = '$surface-disposed';
      platform.pending = Completer();
      await tester.pumpWidget(_app(_surface(surface, seed(id))));
      await _tap(tester, surface, true, id);
      await tester.pump();
      await tester.pumpWidget(_app(const SizedBox()));
      platform.pending!.complete(
        V2TimValueCallback(
          code: 0,
          desc: 'ok',
          data: V2TimFriendOperationResult(userID: id, resultCode: 0),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        TencentCloudChat.instance.dataInstance.contact.applicationList.any(
          (r) => r.userID == id,
        ),
        isFalse,
      );
    });
  }

  testWidgets('list button without optional result still displays success', (
    tester,
  ) async {
    const id = 'optional-result';
    platform.outcome = 'success';
    await tester.pumpWidget(
      _app(TencentCloudChatApplicationItemButton(application: seed(id))),
    );
    await tester.tap(_button('list', true, id));
    await tester.pumpAndSettle();
    expect(find.text('Accepted'), findsOneWidget);
    expect(_button('list', true, id), findsNothing);
  });

  testWidgets('detail button edge is a full semantic target', (tester) async {
    const id = 'detail-edge';
    await tester.pumpWidget(_app(_surface('detail', seed(id))));
    final button = _button('detail', false, id);
    final rect = tester.getRect(button);
    expect(rect.height, greaterThanOrEqualTo(44));
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    await tester.tapAt(rect.bottomRight - const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(platform.calls, 1);
  });

  testWidgets('list button padding is tappable and target is at least 44 px', (
    tester,
  ) async {
    const id = 'edge-tap';
    await tester.pumpWidget(_app(_surface('list', seed(id))));
    final button = _button('list', true, id);
    final rect = tester.getRect(button);
    expect(rect.width, greaterThanOrEqualTo(44));
    expect(rect.height, greaterThanOrEqualTo(44));
    await tester.tapAt(rect.topLeft + const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(
      platform.calls,
      1,
      reason: 'button edge padding belongs to the button',
    );
    expect(find.byType(TencentCloudChatContactApplicationInfo), findsNothing);
  });

  testWidgets('list actions wrap at large text without shrinking or overflow', (
    tester,
  ) async {
    const id = 'large-text';
    await tester.pumpWidget(
      _app(_surface('list', seed(id)), width: 320, scale: 2),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(FittedBox), findsNothing);
    final accept = tester.getRect(_button('list', true, id));
    final refuse = tester.getRect(_button('list', false, id));
    expect(accept.height, greaterThanOrEqualTo(44));
    expect(refuse.height, greaterThanOrEqualTo(44));
    expect(refuse.top, greaterThanOrEqualTo(accept.bottom));
  });
}
