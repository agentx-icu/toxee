// A join the group refuses must be explained, not silently kept as "joined".
//
// Tox reports a refused join (wrong/missing password, group full) after the
// join call returned. The service drops the group and reports it on
// `groupJoinFailures`; `GroupJoinFailureNotifier` is the surface. These tests
// pin it against a capturing service (no FFI).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/navigation/app_navigation.dart';
import 'package:toxee/ui/group/group_join_failure_notifier.dart';

final String _chatId = 'c' * 64;

class _FakeService extends FfiChatService {
  _FakeService() : super();

  final _failures = StreamController<GroupJoinFailure>.broadcast();
  final List<({String id, String? password})> joins = [];

  void refuse(GroupJoinFailureReason reason,
          {String chatId = '', bool established = false, String inviteId = ''}) =>
      _failures.add(GroupJoinFailure(
          groupId: 'tox_7',
          chatId: chatId,
          reason: reason,
          established: established,
          inviteId: inviteId));

  @override
  Stream<GroupJoinFailure> get groupJoinFailures => _failures.stream;

  @override
  Future<void> joinGroup(String groupId,
      {String? requestMessage, String? password}) async {
    joins.add((id: groupId, password: password));
  }

  final List<({String id, String? password})> accepts = [];

  @override
  Future<void> acceptGroupInvite(String inviteId, {String? password}) async {
    accepts.add((id: inviteId, password: password));
  }
}

Future<void> _pumpApp(WidgetTester tester) => tester.pumpWidget(MaterialApp(
      navigatorKey: appNavigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const Scaffold(body: SizedBox.shrink()),
    ));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a full group is explained, with no password retry',
      (tester) async {
    await _pumpApp(tester);
    final service = _FakeService();
    GroupJoinFailureNotifier.instance.attach(service);

    service.refuse(GroupJoinFailureReason.groupFull, chatId: _chatId);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group_join_failure_dialog')),
        findsOneWidget);
    expect(find.text('This group is full.'), findsOneWidget);
    expect(find.byKey(const ValueKey('group_join_failure_password_button')),
        findsNothing);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(service.joins, isEmpty);
  });

  testWidgets('a password refusal offers a retry that joins with the password',
      (tester) async {
    await _pumpApp(tester);
    final service = _FakeService();
    GroupJoinFailureNotifier.instance.attach(service);

    service.refuse(GroupJoinFailureReason.invalidPassword, chatId: _chatId);
    await tester.pumpAndSettle();
    expect(find.textContaining('needs a password'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('group_join_failure_password_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('group_join_password_input')), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pumpAndSettle();
    expect(service.joins, [(id: _chatId, password: 'secret')]);
  });

  testWidgets('an over-long password is rejected before joining',
      (tester) async {
    await _pumpApp(tester);
    final service = _FakeService();
    GroupJoinFailureNotifier.instance.attach(service);

    service.refuse(GroupJoinFailureReason.invalidPassword, chatId: _chatId);
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('group_join_failure_password_button')));
    await tester.pumpAndSettle();
    // 11 × 3-byte characters = 33 bytes: over the 32-byte Tox limit.
    await tester.enterText(
        find.byKey(const ValueKey('group_join_password_input')), '密' * 11);
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pumpAndSettle();
    expect(find.text('A group password is at most 32 bytes'), findsOneWidget);
    expect(service.joins, isEmpty);
  });

  testWidgets('an established group is retried by its id, even with no chat id',
      (tester) async {
    await _pumpApp(tester);
    final service = _FakeService();
    GroupJoinFailureNotifier.instance.attach(service);

    service.refuse(GroupJoinFailureReason.invalidPassword, established: true);
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('group_join_failure_password_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('group_join_password_input')), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pumpAndSettle();
    expect(service.joins, [(id: 'tox_7', password: 'pw')]);
  });

  testWidgets('a refused invite is retried through the invite', (tester) async {
    await _pumpApp(tester);
    final service = _FakeService();
    GroupJoinFailureNotifier.instance.attach(service);

    service.refuse(GroupJoinFailureReason.invalidPassword,
        chatId: _chatId, inviteId: 'tox_inv_3_99');
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('group_join_failure_password_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('group_join_password_input')), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pumpAndSettle();
    expect(service.accepts, [(id: 'tox_inv_3_99', password: 'pw')]);
    expect(service.joins, isEmpty,
        reason: 'joinGroup would record the invite alias as a group');
  });

  testWidgets('an empty password is refused before joining', (tester) async {
    await _pumpApp(tester);
    final service = _FakeService();
    GroupJoinFailureNotifier.instance.attach(service);

    service.refuse(GroupJoinFailureReason.invalidPassword, chatId: _chatId);
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('group_join_failure_password_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the group password'), findsOneWidget);
    expect(service.joins, isEmpty);
  });

  test('password validation counts UTF-8 bytes', () {
    expect(GroupJoinFailureNotifier.isValidPassword('a' * 32), isTrue);
    expect(GroupJoinFailureNotifier.isValidPassword('a' * 33), isFalse);
    expect(GroupJoinFailureNotifier.isValidPassword(''), isTrue);
  });
}
