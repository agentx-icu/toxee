// L1 widget test for the Add Group dialog (lib/ui/add_group_dialog.dart),
// covering the create + join validation/guards described in the L3 MCP
// playbooks S32 (create group) and S33 (join by ID).
//
// Widget test over a stub service: `_StubFfiChatService extends FfiChatService`
// records whether createGroup / joinGroup would have fired. NOTE: constructing
// the FfiChatService superclass (`: super()`) opens the tim2tox FFI dylib
// (Tim2ToxFfi.open) and MessageHistoryPersistence, so this test DOES load the
// native lib — same as test/ui/add_friend_dialog_smoke_test.dart, which also
// runs without a skip-guard. It is not a pure-Dart, no-native test; the stub
// only overrides the surface the dialog reads.
// We assert up to the validation gate:
//   * create: empty name -> inline validator error, createGroup NOT called;
//     valid name -> validator passes, createGroup fires.
//   * join: empty / non-hex / wrong-length id -> inline validator error,
//     joinGroup NOT called; valid 64-hex id -> joinGroup fires.
//
// The dialog's two validators live at:
//   * join id  -> add_group_dialog.dart:326-348 (empty / hex / length==64)
//   * create   -> add_group_dialog.dart:428-434 (name required)
// Both submit handlers bail at `_*FormKey.currentState!.validate()` before
// any service call (`_joinGroup` :101, `_createGroup` :141).
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
import 'package:toxee/util/prefs.dart';

// A valid join/group id is exactly 64 hex chars (Tox CONFERENCE_ID_SIZE /
// public group chat_id). The dialog validator is
// `^[0-9A-Fa-f]+$` AND `length == 64`.
final String _validGroupId = 'a' * 64;

class _StubFfiChatService extends FfiChatService {
  _StubFfiChatService({this.createGroupResult}) : super();

  /// What the next createGroup call returns. A non-empty 64-hex string makes
  /// the create success path proceed to Prefs.setGroupName.
  final String? createGroupResult;

  // Records — flip true when the corresponding service method is reached,
  // i.e. only after the form validator passed.
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

Widget _harness(_StubFfiChatService service, void Function(String) onSnack) {
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
      body: Builder(
        builder: (ctx) => Center(
          child: TextButton(
            onPressed: () => showDialog<void>(
              context: ctx,
              builder: (_) => Dialog(
                child: AddGroupDialog(
                  service: service,
                  onShowSnackBar: onSnack,
                  installDefaultGroupAvatar:
                      ({required String groupId, String? toxId}) async =>
                          '/tmp/$groupId-default.png',
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

// The dialog is a tall two-card scroll view; the submit buttons can sit below
// the fold. Scroll the button into view before tapping so the hit test lands.
Future<void> _tapButton(WidgetTester tester, String label) async {
  final button = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  // HapticFeedback.lightImpact() (success/failure paths) goes through
  // SystemChannels.platform with the JSON codec — mock it or the call throws.
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());

  setUp(() async {
    // Prefs.setGroupName / setGroupAlias on the success path need a backing
    // SharedPreferences; provide an in-memory mock.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    await Prefs.setCurrentAccountToxId('B' * 76);
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      platformChannel,
      (MethodCall call) async => null,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platformChannel, null);
  });

  // ---- S32: create group -------------------------------------------------

  testWidgets(
    'S32 create: empty group name shows validator error and does NOT call createGroup',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _StubFfiChatService(createGroupResult: _validGroupId);
      addTearDown(service.disposeStub);

      await tester.pumpWidget(_harness(service, (_) {}));
      await _openDialog(tester);

      // Submit the create card with an empty name field.
      await _tapButton(tester, 'Create Group');

      expect(
        find.text('Please enter Group Name'),
        findsOneWidget,
        reason: 'empty group name must surface the required-name validator',
      );
      expect(
        service.createCalled,
        isFalse,
        reason: 'createGroup must not fire when the name validator fails',
      );
    },
  );

  testWidgets(
    'S32 create: valid name passes validation and calls createGroup with the name',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _StubFfiChatService(createGroupResult: _validGroupId);
      addTearDown(service.disposeStub);

      await tester.pumpWidget(_harness(service, (_) {}));
      await _openDialog(tester);

      await tester.enterText(
        find.byKey(UiKeys.addGroupCreateNameInput),
        'my group',
      );
      await tester.pumpAndSettle();
      await _tapButton(tester, 'Create Group');

      expect(
        find.text('Please enter Group Name'),
        findsNothing,
        reason: 'a non-empty name must clear the required-name validator',
      );
      expect(
        service.createCalled,
        isTrue,
        reason: 'createGroup must fire once the name validator passes',
      );
      expect(
        service.createNameArg,
        'my group',
        reason: 'createGroup must receive the entered (trimmed) group name',
      );
    },
  );

  // S32 create: group-type selector → FFI type-string mapping. The dialog's
  // SegmentedButton (add_group_dialog.dart:450-486, key addGroupTypeSelector)
  // drives _selectedGroupType, which _createGroup maps to the FFI type string
  // via the switch at add_group_dialog.dart:158-163:
  //   'group'        → 'Public'   (default selection; guards the
  //                                dart_compat_group.cpp PRIVATE-default footgun)
  //   'privateGroup' → 'Private'
  //   'conference'   → 'conference'
  // Each case below selects the segment by its English label, then asserts the
  // recorded createGroup groupType arg.
  for (final entry in <(String?, String)>[
    // (segmentLabelToTap | null = leave default, expectedFfiTypeArg)
    (null, 'Public'),
    ('Private', 'Private'),
    ('Conference', 'conference'),
  ]) {
    final segmentLabel = entry.$1;
    final expectedType = entry.$2;
    final selectionDesc = segmentLabel == null
        ? "default 'Public' selection"
        : "'$segmentLabel' selection";

    testWidgets('S32 create: $selectionDesc maps to FFI type "$expectedType"', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _StubFfiChatService(createGroupResult: _validGroupId);
      addTearDown(service.disposeStub);

      await tester.pumpWidget(_harness(service, (_) {}));
      await _openDialog(tester);

      await tester.enterText(
        find.byKey(UiKeys.addGroupCreateNameInput),
        'a group',
      );
      await tester.pumpAndSettle();

      // Drive the type selector (default selection needs no tap).
      if (segmentLabel != null) {
        final segment = find.descendant(
          of: find.byKey(UiKeys.addGroupTypeSelector),
          matching: find.text(segmentLabel),
        );
        await tester.ensureVisible(segment);
        await tester.pumpAndSettle();
        await tester.tap(segment);
        await tester.pumpAndSettle();
      }

      await _tapButton(tester, 'Create Group');

      expect(
        service.createCalled,
        isTrue,
        reason: 'createGroup must fire once the name validator passes',
      );
      expect(
        service.createTypeArg,
        expectedType,
        reason: '$selectionDesc must map to FFI type "$expectedType"',
      );
    });
  }

  testWidgets('S158 create: selecting Conference updates the helper hint text', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _StubFfiChatService(createGroupResult: _validGroupId);
    addTearDown(service.disposeStub);

    await tester.pumpWidget(_harness(service, (_) {}));
    await _openDialog(tester);

    expect(
      find.text(
        'Public group — discoverable on the DHT and joinable by anyone with the chat ID.',
      ),
      findsOneWidget,
      reason:
          'the dialog starts on the Public segment and should show its hint',
    );

    final conferenceSegment = find.descendant(
      of: find.byKey(UiKeys.addGroupTypeSelector),
      matching: find.text('Conference'),
    );
    await tester.ensureVisible(conferenceSegment);
    await tester.pumpAndSettle();
    await tester.tap(conferenceSegment);
    await tester.pumpAndSettle();

    expect(
      find.text('Legacy conference — older protocol, no roles or persistence.'),
      findsOneWidget,
      reason:
          'selecting the Conference segment should switch the helper hint text',
    );
  });

  // ---- S33: join group by ID ---------------------------------------------

  testWidgets(
    'S33 join: empty group ID shows validator error and does NOT call joinGroup',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _StubFfiChatService();
      addTearDown(service.disposeStub);

      await tester.pumpWidget(_harness(service, (_) {}));
      await _openDialog(tester);

      await _tapButton(tester, 'Send Join Request');

      expect(
        find.text('Please enter Group ID'),
        findsOneWidget,
        reason: 'empty join id must surface the required-id validator',
      );
      expect(
        service.joinCalled,
        isFalse,
        reason: 'joinGroup must not fire when the id validator fails',
      );
    },
  );

  testWidgets(
    'S33 join: non-hex group ID shows the hex validator and does NOT call joinGroup',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _StubFfiChatService();
      addTearDown(service.disposeStub);

      await tester.pumpWidget(_harness(service, (_) {}));
      await _openDialog(tester);

      // 'xyz' + 61 zeros: 64 chars long but contains non-hex characters.
      await tester.enterText(
        find.byKey(UiKeys.addGroupJoinIdInput),
        'xyz${'0' * 61}',
      );
      await tester.pumpAndSettle();
      await _tapButton(tester, 'Send Join Request');

      expect(
        find.text('Can only contain hexadecimal characters'),
        findsOneWidget,
        reason: 'non-hex characters must surface the hex validator',
      );
      expect(
        service.joinCalled,
        isFalse,
        reason: 'joinGroup must not fire on a non-hex id',
      );
    },
  );

  testWidgets(
    'S33 join: wrong-length hex id shows the length validator and does NOT call joinGroup',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _StubFfiChatService();
      addTearDown(service.disposeStub);

      await tester.pumpWidget(_harness(service, (_) {}));
      await _openDialog(tester);

      // 'deadbeef' is valid hex but only 8 chars (≠ 64).
      await tester.enterText(
        find.byKey(UiKeys.addGroupJoinIdInput),
        'deadbeef',
      );
      await tester.pumpAndSettle();
      await _tapButton(tester, 'Send Join Request');

      expect(
        find.text('Invalid ID length'),
        findsOneWidget,
        reason:
            'a hex id of the wrong length must surface the length validator',
      );
      expect(
        service.joinCalled,
        isFalse,
        reason: 'joinGroup must not fire on a wrong-length id',
      );
    },
  );

  testWidgets(
    'S33 join: valid 64-hex id passes validation and calls joinGroup with the id',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _StubFfiChatService();
      addTearDown(service.disposeStub);

      await tester.pumpWidget(_harness(service, (_) {}));
      await _openDialog(tester);

      await tester.enterText(
        find.byKey(UiKeys.addGroupJoinIdInput),
        _validGroupId,
      );
      await tester.pumpAndSettle();
      await _tapButton(tester, 'Send Join Request');

      expect(
        find.text('Please enter Group ID'),
        findsNothing,
        reason: 'a valid id must clear the required-id validator',
      );
      expect(
        find.text('Can only contain hexadecimal characters'),
        findsNothing,
        reason: 'a valid hex id must clear the hex validator',
      );
      expect(
        find.text('Invalid ID length'),
        findsNothing,
        reason: 'a 64-char id must clear the length validator',
      );
      expect(
        service.joinCalled,
        isTrue,
        reason: 'joinGroup must fire once the id validator passes',
      );
      expect(
        service.joinIdArg,
        _validGroupId,
        reason: 'joinGroup must receive the entered (trimmed) group id',
      );
    },
  );

  // S128 create copy-id: after a successful create the dialog shows the
  // created-info card (new group id + Copy ID button). The dialog normally
  // auto-closes (navigator.maybePop in _createGroup), so mount AddGroupDialog
  // DIRECTLY as the body (not via showDialog) — maybePop then has nothing to
  // pop and the card stays mounted for assertion.
  testWidgets(
    'S128 create success renders the created-info card with Copy ID button and the new id',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _StubFfiChatService(createGroupResult: _validGroupId);
      addTearDown(service.disposeStub);

      await tester.pumpWidget(
        MaterialApp(
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
                installDefaultGroupAvatar:
                    ({required String groupId, String? toxId}) async =>
                        '/tmp/$groupId-default.png',
                closeOnCreateSuccess: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Created-info card (and its Copy ID button) is absent before a create.
      expect(find.byKey(UiKeys.addGroupCopyIdButton), findsNothing);

      await tester.enterText(
        find.byKey(UiKeys.addGroupCreateNameInput),
        'copy-id group',
      );
      await tester.pumpAndSettle();
      await _tapButton(tester, 'Create Group');

      expect(
        service.createCalled,
        isTrue,
        reason: 'createGroup must fire once the name validator passes',
      );
      // After create, the created-info card renders the Copy ID button + the id.
      expect(
        find.byKey(UiKeys.addGroupCopyIdButton),
        findsOneWidget,
        reason: 'the created-info Copy ID button should render after create',
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == _validGroupId,
        ),
        findsOneWidget,
        reason: 'the created-info card should display the new group id',
      );
    },
  );
}
