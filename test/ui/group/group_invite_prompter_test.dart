// A group invite must be answerable.
//
// With "auto-accept group invites" off (the default) an invite used to be
// parked natively and shown nowhere: no row, no badge, nothing to accept, and
// gone after a restart. `GroupInvitePrompter` is the surface; these tests pin
// its contract against a capturing service (no FFI).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/navigation/app_navigation.dart';
import 'package:toxee/ui/group/group_invite_prompter.dart';
import 'package:toxee/ui/group/group_join_failure_notifier.dart';

final String _inviter = 'B' * 64;

PendingGroupInvite _invite(String id,
        {String name = 'Book club', int receivedMs = 1700000000000}) =>
    PendingGroupInvite(
      id: id,
      inviterUserId: _inviter,
      kind: 'group',
      groupName: name,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(receivedMs),
      cookieHex: 'ab',
    );

class _FakeService extends FfiChatService {
  _FakeService() : super();

  final List<PendingGroupInvite> pending = <PendingGroupInvite>[];
  final List<String> accepted = <String>[];
  final List<String?> acceptPasswords = <String?>[];
  final List<String> rejected = <String>[];
  bool acceptFails = false;
  final _changed = StreamController<void>.broadcast();
  final _failures = StreamController<GroupJoinFailure>.broadcast();

  void arrive(PendingGroupInvite invite) {
    pending.add(invite);
    _changed.add(null);
  }

  /// Native after the group refused an accepted invite: the invite is handed
  /// back unanswered (same id, same receivedAt) and announced like a new one.
  void handBack(PendingGroupInvite invite) => arrive(invite);

  /// ...and then the refusal itself, carrying the invite id.
  void refuse(String inviteId,
          [GroupJoinFailureReason reason =
              GroupJoinFailureReason.invalidPassword]) =>
      _failures.add(GroupJoinFailure(
          groupId: inviteId,
          chatId: 'c' * 64,
          reason: reason,
          established: false,
          inviteId: inviteId));

  /// The inviter sent the same invite again: native keeps the id and
  /// refreshes its receivedAt.
  void resend(PendingGroupInvite invite) {
    pending.removeWhere((i) => i.id == invite.id);
    arrive(invite);
  }

  @override
  Stream<void> get pendingGroupInvitesChanged => _changed.stream;

  @override
  Stream<GroupJoinFailure> get groupJoinFailures => _failures.stream;

  @override
  List<PendingGroupInvite> getPendingGroupInvites() => List.of(pending);

  @override
  Future<void> acceptGroupInvite(String inviteId, {String? password}) async {
    if (acceptFails) throw StateError('inviter offline');
    accepted.add(inviteId);
    acceptPasswords.add(password);
    pending.removeWhere((i) => i.id == inviteId);
  }

  @override
  void rejectGroupInvite(String inviteId) {
    rejected.add(inviteId);
    pending.removeWhere((i) => i.id == inviteId);
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

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('an arriving invite is shown with the group name; Join accepts',
      (tester) async {
    await _pumpApp(tester);
    final service = _FakeService();
    GroupInvitePrompter.instance.attach(service, autoAccept: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group_invite_dialog')), findsNothing);

    service.arrive(_invite('tox_inv_1_1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group_invite_dialog')), findsOneWidget);
    expect(find.textContaining('Book club'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('group_invite_join_button')));
    await tester.pumpAndSettle();
    expect(service.accepted, ['tox_inv_1_1']);
    expect(find.byKey(const ValueKey('group_invite_dialog')), findsNothing);
  });

  testWidgets('Decline forgets the invite; Later keeps it without re-asking',
      (tester) async {
    await _pumpApp(tester);
    final service = _FakeService()
      ..pending.addAll([_invite('inv_a'), _invite('inv_b', name: '')]);
    GroupInvitePrompter.instance.attach(service, autoAccept: false);
    await tester.pumpAndSettle();

    // Invites already waiting at attach time (restored from the last session)
    // are asked about, oldest first.
    await tester.tap(find.byKey(const ValueKey('group_invite_decline_button')));
    await tester.pumpAndSettle();
    expect(service.rejected, ['inv_a']);

    // The second one carries no name (a conference): still a sensible prompt.
    expect(find.byKey(const ValueKey('group_invite_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group_invite_later_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group_invite_dialog')), findsNothing);
    expect(service.pending.map((i) => i.id), ['inv_b'],
        reason: '"Later" must not drop the invite');
  });

  testWidgets('a failed accept keeps the invite and tells the user why',
      (tester) async {
    await _pumpApp(tester);
    final service = _FakeService()
      ..acceptFails = true
      ..pending.add(_invite('inv_c'));
    GroupInvitePrompter.instance.attach(service, autoAccept: false);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('group_invite_join_button')));
    await tester.pumpAndSettle();
    expect(service.pending.map((i) => i.id), ['inv_c']);
    expect(find.textContaining('may be offline'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  });

  testWidgets('attaching another account\'s service while a prompt is open '
      'moves on to that account', (tester) async {
    await _pumpApp(tester);
    final first = _FakeService()..pending.add(_invite('inv_first'));
    GroupInvitePrompter.instance.attach(first, autoAccept: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group_invite_dialog')), findsOneWidget);

    // Account switch: the previous service's dialog is still up.
    final second = _FakeService()..pending.add(_invite('inv_second'));
    GroupInvitePrompter.instance.attach(second, autoAccept: true);
    await tester.pumpAndSettle();
    expect(second.accepted, ['inv_second']);
    expect(first.accepted, isEmpty);
  });

  testWidgets('with auto-accept on, a waiting invite is accepted unprompted',
      (tester) async {
    await _pumpApp(tester);
    final service = _FakeService()..pending.add(_invite('inv_d'));
    // The persisted setting reaches the native gate only at HomePage
    // bootstrap; an invite that beat it there is still honored.
    GroupInvitePrompter.instance.attach(service, autoAccept: true);
    await tester.pumpAndSettle();
    expect(service.accepted, ['inv_d']);
    expect(find.byKey(const ValueKey('group_invite_dialog')), findsNothing);
  });

  const inviteDialog = ValueKey('group_invite_dialog');
  const failureDialog = ValueKey('group_join_failure_dialog');

  testWidgets('auto-accept: an invite handed back by a refusing group is '
      'accepted once, then left to the failure dialog and asked about once',
      (tester) async {
    await _pumpApp(tester);
    final service = _FakeService();
    GroupInvitePrompter.instance.attach(service, autoAccept: true);
    GroupJoinFailureNotifier.instance.attach(service);
    await tester.pumpAndSettle();

    final invite = _invite('tox_inv_2_5');
    service.arrive(invite);
    await tester.pumpAndSettle();
    expect(service.accepted, ['tox_inv_2_5']);

    // The group wants a password: native hands the invite back first...
    service.handBack(invite);
    await tester.pumpAndSettle();
    expect(service.accepted, ['tox_inv_2_5'],
        reason: 'a re-accept with no password would be refused forever');
    expect(find.byKey(inviteDialog), findsNothing);

    // ...then reports the refusal: explained exactly once.
    service.refuse('tox_inv_2_5');
    await tester.pumpAndSettle();
    expect(find.byKey(failureDialog), findsOneWidget);
    expect(find.byKey(inviteDialog), findsNothing);
    expect(service.accepted, ['tox_inv_2_5']);

    // Dismissed without a password: the invite is still the user's to answer
    // (asked, never auto-accepted), not dropped.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byKey(failureDialog), findsNothing);
    expect(find.byKey(inviteDialog), findsOneWidget);
    expect(service.accepted, ['tox_inv_2_5']);

    await tester.tap(find.byKey(const ValueKey('group_invite_later_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(inviteDialog), findsNothing);
    expect(service.pending.map((i) => i.id), ['tox_inv_2_5']);
    expect(service.accepted, ['tox_inv_2_5']);
  });

  testWidgets('auto-accept off: a refused invite is not prompted again under '
      'the failure dialog; redeeming it there leaves no stale prompt',
      (tester) async {
    await _pumpApp(tester);
    final service = _FakeService();
    GroupInvitePrompter.instance.attach(service, autoAccept: false);
    GroupJoinFailureNotifier.instance.attach(service);
    await tester.pumpAndSettle();

    final invite = _invite('tox_inv_3_7');
    service.arrive(invite);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('group_invite_join_button')));
    await tester.pumpAndSettle();
    expect(service.accepted, ['tox_inv_3_7']);

    service
      ..handBack(invite)
      ..refuse('tox_inv_3_7');
    await tester.pumpAndSettle();
    expect(find.byKey(failureDialog), findsOneWidget);
    expect(find.byKey(inviteDialog), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('group_join_failure_password_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('group_join_password_input')), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pumpAndSettle();
    expect(service.accepted, ['tox_inv_3_7', 'tox_inv_3_7']);
    expect(service.acceptPasswords, [null, 'pw']);
    expect(find.byKey(inviteDialog), findsNothing);
    expect(find.byKey(failureDialog), findsNothing);

    // Wrong password: handed back and refused again: the notifier explains
    // it again, still with no invite prompt under it.
    service
      ..handBack(invite)
      ..refuse('tox_inv_3_7');
    await tester.pumpAndSettle();
    expect(find.byKey(failureDialog), findsOneWidget);
    expect(find.byKey(inviteDialog), findsNothing);

    // Given up on: asked once more, so it can still be declined.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byKey(inviteDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group_invite_decline_button')));
    await tester.pumpAndSettle();
    expect(service.rejected, ['tox_inv_3_7']);
    expect(service.accepted, hasLength(2));
  });

  testWidgets('"Later" holds until the inviter sends the invite again',
      (tester) async {
    await _pumpApp(tester);
    final service = _FakeService();
    GroupInvitePrompter.instance.attach(service, autoAccept: false);
    await tester.pumpAndSettle();

    service.arrive(_invite('tox_inv_4_1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('group_invite_later_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(inviteDialog), findsNothing);

    // Another invite's arrival re-reads the list: the deferred one stays put.
    service.arrive(_invite('tox_inv_4_2', name: 'Chess'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Chess'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group_invite_later_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(inviteDialog), findsNothing);

    // Re-sent by the inviter (same id, fresh receivedAt): asked again.
    service.resend(_invite('tox_inv_4_1', receivedMs: 1700000005000));
    await tester.pumpAndSettle();
    expect(find.byKey(inviteDialog), findsOneWidget);
    expect(find.textContaining('Book club'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group_invite_join_button')));
    await tester.pumpAndSettle();
    expect(service.accepted, ['tox_inv_4_1']);
    expect(find.byKey(inviteDialog), findsNothing,
        reason: 'Chess was put off and not re-sent');
  });

  // An accept that FAILS (typically an offline inviter) used to be filed like
  // "Later": the inviter coming back does not refresh `receivedAt`, so the
  // invite was unreachable until the app restarted.
  testWidgets('a failed accept can be retried from the failure dialog',
      (tester) async {
    await _pumpApp(tester);
    final service = _FakeService()
      ..acceptFails = true
      ..pending.add(_invite('tox_inv_5_1'));
    GroupInvitePrompter.instance.attach(service, autoAccept: false);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('group_invite_join_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group_invite_accept_failed_dialog')),
        findsOneWidget);
    expect(service.accepted, isEmpty);

    // The inviter is back: Retry accepts without waiting for anything else.
    service.acceptFails = false;
    await tester
        .tap(find.byKey(const ValueKey('group_invite_accept_retry_button')));
    await tester.pumpAndSettle();
    expect(service.accepted, ['tox_inv_5_1']);
    expect(find.byKey(inviteDialog), findsNothing);
  });

  testWidgets('a failed accept is asked again on the next invite change, '
      'and not before', (tester) async {
    await _pumpApp(tester);
    final service = _FakeService()
      ..acceptFails = true
      ..pending.add(_invite('tox_inv_5_2'));
    GroupInvitePrompter.instance.attach(service, autoAccept: false);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('group_invite_join_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // No dialog stack, no retry loop while nothing changes.
    expect(find.byKey(inviteDialog), findsNothing);
    expect(service.accepted, isEmpty);

    // The list changes (here: another invite arrives), so the failed one is
    // answerable again rather than lost for the session.
    service.acceptFails = false;
    service.arrive(_invite('tox_inv_5_3', name: 'Chess'));
    await tester.pumpAndSettle();
    expect(find.byKey(inviteDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group_invite_join_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('group_invite_join_button')));
    await tester.pumpAndSettle();
    expect(service.accepted, containsAll(['tox_inv_5_2', 'tox_inv_5_3']));
  });

  // Android back / Escape is not an answer: filing it as "Later" hid the
  // invite until the inviter re-sent it.
  testWidgets('a dismissed prompt is asked again on the next invite change',
      (tester) async {
    await _pumpApp(tester);
    final service = _FakeService()..pending.add(_invite('tox_inv_6_1'));
    GroupInvitePrompter.instance.attach(service, autoAccept: false);
    await tester.pumpAndSettle();
    expect(find.byKey(inviteDialog), findsOneWidget);

    // Dismiss without answering (what the system back button does).
    Navigator.of(appNavigatorKey.currentContext!).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(inviteDialog), findsNothing);
    expect(service.accepted, isEmpty);
    expect(service.rejected, isEmpty);

    // Any change to the list reopens it — no need for the inviter to re-send.
    service.arrive(_invite('tox_inv_6_2', name: 'Chess'));
    await tester.pumpAndSettle();
    expect(find.byKey(inviteDialog), findsOneWidget);
    expect(find.textContaining('Book club'), findsOneWidget,
        reason: 'the dismissed invite is asked first, not dropped');
  }, skip: null);

  testWidgets('switching auto-accept on covers invites already put off',
      (tester) async {
    await _pumpApp(tester);
    final service = _FakeService()..pending.add(_invite('tox_inv_5_4'));
    GroupInvitePrompter.instance.attach(service, autoAccept: false);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('group_invite_later_button')));
    await tester.pumpAndSettle();
    expect(service.accepted, isEmpty);

    GroupInvitePrompter.instance.autoAccept = true;
    await tester.pumpAndSettle();
    expect(service.accepted, ['tox_inv_5_4'],
        reason: 'the setting says waiting invites are accepted');
  });

  testWidgets('a join that succeeded does not swallow a later invite with the '
      'same id', (tester) async {
    await _pumpApp(tester);
    final service = _FakeService()..pending.add(_invite('tox_inv_5_5'));
    GroupInvitePrompter.instance.attach(service, autoAccept: false);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('group_invite_join_button')));
    await tester.pumpAndSettle();
    expect(service.accepted, ['tox_inv_5_5']);

    // The inviter invites again later; native reuses the id with a fresh
    // receivedAt. The accepted-and-pending record must not hide it.
    service.resend(_invite('tox_inv_5_5', receivedMs: 1700000009000));
    await tester.pumpAndSettle();
    expect(find.byKey(inviteDialog), findsOneWidget);
  });
}
