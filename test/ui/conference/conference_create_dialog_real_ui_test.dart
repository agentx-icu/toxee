// Conference real-UI gates for the Add Group dialog (lib/ui/add_group_dialog.dart):
// the CREATE-a-legacy-conference branch (S156/S157/S158) and the negative
// join-by-ID boundary (S185). These drive the REAL production dialog widget and
// assert the REAL side-effect recorded by a thin FfiChatService stub — the same
// pattern as test/ui/add_group_dialog_test.dart, but framed on the conference
// branch (`_selectedGroupType == 'conference'` → FFI type string 'conference',
// add_group_dialog.dart:158-163).
//
// What is hermetic here (and what is NOT):
//   * S156: selecting the keyed Conference segment then Create routes the real
//     `_createGroup` through the conference branch (createGroup(groupType:
//     'conference')). The native `tox_conference_new` + the conversation row
//     appearing in the chats list is the two-process leg, covered by the
//     `conference_message` real-UI pair gate (drive_real_ui_pair.dart).
//   * S157: after a successful create the dialog renders the created-info card
//     and its Copy ID button writes the 64-hex conference id to the clipboard.
//   * S158: selecting Conference swaps the helper hint to the localized
//     conferenceHint and the selector stays on Conference.
//   * S185: a 64-hex conference id is accepted at the JOIN form layer (joinGroup
//     fires) — but the current join-by-ID path is NGC-specific, so no conference
//     is actually joined and no ghost row is created (the negative half is the
//     downstream native behaviour, documented, not hermetic here).
//
// Mobile parity: AddGroupDialog is shared Dart (no platform split) — this L1
// gate covers iOS/Android too.
//
// Constructing `_StubFfiChatService extends FfiChatService` opens the tim2tox
// FFI dylib via `super()` (Tim2ToxFfi.open) + MessageHistoryPersistence, exactly
// like add_group_dialog_test.dart / add_friend_dialog_smoke_test.dart; the stub
// only overrides the surface the dialog reads.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/add_group_dialog.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

// A valid join/conference id is exactly 64 hex chars (Tox CONFERENCE_ID_SIZE ==
// public group chat_id == 32 bytes). The dialog validator is `^[0-9A-Fa-f]+$`
// AND `length == 64`.
final String _validConferenceId = 'c' * 64;

class _StubFfiChatService extends FfiChatService {
  _StubFfiChatService({this.createGroupResult}) : super();

  /// What the next createGroup call returns. A non-empty 64-hex string makes
  /// the create success path proceed to the created-info card.
  final String? createGroupResult;

  bool createCalled = false;
  String? createNameArg;
  String? createTypeArg;
  bool joinCalled = false;
  String? joinIdArg;

  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connectionStatusStream => _connection.stream;

  @override
  String? getSelfToxId() => 'B' * 76;

  @override
  Future<String?> createGroup(String name, {String groupType = 'group'}) async {
    createCalled = true;
    createNameArg = name;
    createTypeArg = groupType;
    return createGroupResult;
  }

  @override
  Future<void> joinGroup(String groupId,
      {String? requestMessage, String? password}) async {
    joinCalled = true;
    joinIdArg = groupId;
  }

  void disposeStub() => unawaited(_connection.close());
}

// Mounts AddGroupDialog DIRECTLY as the body (not via showDialog). The dialog
// auto-pops on a successful create (navigator.maybePop in _createGroup); mounted
// directly there is nothing to pop, so the created-info card stays mounted for
// assertion.
Widget _directHarness(_StubFfiChatService service) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: SingleChildScrollView(
        child: AddGroupDialog(
          service: service,
          onShowSnackBar: (_) {},
          // The production create path now installs a default group avatar
          // (real asset+file IO via DefaultAvatarInstaller) — inject the seam
          // the dialog exposes for exactly this, or the IO never completes
          // under FakeAsync and pumpAndSettle times out.
          installDefaultGroupAvatar:
              ({required String groupId, String? toxId}) async =>
                  '/tmp/$groupId-default.png',
        ),
      ),
    ),
  );
}

Future<void> _tapFilledButton(WidgetTester tester, String label) async {
  final button = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _selectConferenceSegment(WidgetTester tester) async {
  final segment = find.descendant(
    of: find.byKey(UiKeys.addGroupTypeSelector),
    matching: find.text('Conference'),
  );
  await tester.ensureVisible(segment);
  await tester.pumpAndSettle();
  await tester.tap(segment);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  // The dialog's success/failure paths call HapticFeedback + Clipboard.setData,
  // both on SystemChannels.platform (JSON codec). Mock the channel and capture
  // Clipboard writes so the copy-id assertion can read them.
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());
  String? clipboardText;

  setUp(() {
    clipboardText = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(platformChannel, (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platformChannel, null);
  });

  // ---- S156: create a legacy conference -----------------------------------
  testWidgets(
    'S156 conference: selecting the Conference segment + Create routes through '
    'the real conference create branch',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _StubFfiChatService(createGroupResult: _validConferenceId);
      addTearDown(service.disposeStub);

      await tester.pumpWidget(_directHarness(service));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(UiKeys.addGroupCreateNameInput),
        'Team Standup Conference',
      );
      await tester.pumpAndSettle();
      await _selectConferenceSegment(tester);
      await _tapFilledButton(tester, 'Create Group');

      expect(service.createCalled, isTrue,
          reason: 'create must fire once the name validator passes');
      expect(service.createTypeArg, 'conference',
          reason:
              'the Conference segment must resolve to the FFI conference branch, '
              'not Public/Private group creation');
      expect(service.createNameArg, 'Team Standup Conference',
          reason: 'createGroup must receive the entered conference name');
      // The created-info card (the conference-row stand-in at the dialog layer)
      // renders the resolved 64-hex conference id.
      expect(
        find.byWidgetPredicate(
            (w) => w is SelectableText && w.data == _validConferenceId),
        findsOneWidget,
        reason: 'the created-info card should show the new conference id',
      );
    },
  );

  // ---- S157: copy the created conference id -------------------------------
  testWidgets(
    'S157 conference: the created-info Copy ID button copies the 64-hex '
    'conference id to the clipboard',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _StubFfiChatService(createGroupResult: _validConferenceId);
      addTearDown(service.disposeStub);

      await tester.pumpWidget(_directHarness(service));
      await tester.pumpAndSettle();

      // The Copy ID affordance is absent before a create (non-vacuous baseline).
      expect(find.byKey(UiKeys.addGroupCopyIdButton), findsNothing);

      await tester.enterText(
        find.byKey(UiKeys.addGroupCreateNameInput),
        'Copyable Conference',
      );
      await tester.pumpAndSettle();
      await _selectConferenceSegment(tester);
      await _tapFilledButton(tester, 'Create Group');

      expect(service.createTypeArg, 'conference');
      final copyButton = find.byKey(UiKeys.addGroupCopyIdButton);
      expect(copyButton, findsOneWidget,
          reason: 'the created-info Copy ID button should render after create');

      await tester.ensureVisible(copyButton);
      await tester.pumpAndSettle();
      await tester.tap(copyButton);
      await tester.pumpAndSettle();

      expect(clipboardText, _validConferenceId,
          reason: 'Copy ID must write the created conference id to the clipboard');
    },
  );

  // ---- S158: the Conference segment swaps the helper hint -----------------
  testWidgets(
    'S158 conference: selecting Conference swaps the helper hint and stays '
    'selected',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _StubFfiChatService(createGroupResult: _validConferenceId);
      addTearDown(service.disposeStub);

      await tester.pumpWidget(_directHarness(service));
      await tester.pumpAndSettle();

      // Default is the Public segment + its hint.
      expect(
        find.text(
            'Public group — discoverable on the DHT and joinable by anyone with the chat ID.'),
        findsOneWidget,
      );
      expect(
        find.text('Legacy conference — older protocol, no roles or persistence.'),
        findsNothing,
      );

      await _selectConferenceSegment(tester);

      expect(
        find.text('Legacy conference — older protocol, no roles or persistence.'),
        findsOneWidget,
        reason: 'selecting Conference must switch the helper hint',
      );
      expect(
        find.text(
            'Public group — discoverable on the DHT and joinable by anyone with the chat ID.'),
        findsNothing,
        reason: 'the public hint must be gone once Conference is selected',
      );

      // The selector stays on Conference: creating now resolves to the
      // conference branch (proves the segment selection stuck, not just the
      // hint text).
      await tester.enterText(
        find.byKey(UiKeys.addGroupCreateNameInput),
        'Hint Conference',
      );
      await tester.pumpAndSettle();
      await _tapFilledButton(tester, 'Create Group');
      expect(service.createTypeArg, 'conference',
          reason: 'the Conference segment must remain selected after the hint swap');
    },
  );

  // ---- S185: join-by-ID accepts a 64-hex conference id at the form layer ---
  // Negative scenario: the JOIN validator accepts a 64-hex conference id (same
  // shape as a public group chat_id) and dispatches joinGroup — but the
  // downstream join-by-ID path is NGC-specific and does NOT actually join a
  // legacy conference (the failed-join / no-ghost-row half is native, covered
  // two-process). The hermetic, single-process observable is: the form accepts
  // the id and fires the real joinGroup wrapper.
  testWidgets(
    'S185 conference: a 64-hex conference id passes the join validator and '
    'dispatches the real joinGroup (NGC-only downstream)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _StubFfiChatService();
      addTearDown(service.disposeStub);

      await tester.pumpWidget(_directHarness(service));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(UiKeys.addGroupJoinIdInput),
        _validConferenceId,
      );
      await tester.pumpAndSettle();
      await _tapFilledButton(tester, 'Send Join Request');

      // Form-layer acceptance: joinGroup only fires AFTER the join validator
      // passes (_joinGroup bails at _joinFormKey.currentState!.validate()), so a
      // recorded joinGroup call with the entered id IS the proof the 64-hex
      // conference id was accepted at the form layer (no fragile error-string
      // matching needed).
      expect(service.joinCalled, isTrue,
          reason: 'a 64-hex conference id must pass the form and dispatch joinGroup');
      expect(service.joinIdArg, _validConferenceId);

      // No created-info / conference row is materialised by a join attempt: the
      // join-by-ID path only queues a request (and, for a legacy conference,
      // does not actually join — the NGC-only boundary this scenario captures).
      expect(find.byKey(UiKeys.addGroupCopyIdButton), findsNothing,
          reason: 'joining must not create a (ghost) conference row');
    },
  );
}
