// Real-UI gates for two profile-entry scenarios:
//
// S104 — Sidebar user-avatar tap → opens self-profile
//   Drives the REAL `buildSidebar` widget, taps the REAL `UiKeys.sidebarUserAvatar`
//   `InkWell` (which calls `_openProfile` → `showSelfProfile`), and then asserts the
//   REAL resolved identity surfaces: that `profileEditToggle` is present (isEditable
//   == true), that `profileToxIdSelectableText.data` equals the seeded 76-hex toxId
//   (not a placeholder), that the displayed nickname matches the seeded one, and
//   that the dismiss path (close-button) removes the profile from the tree.
//
// S101 — Self-profile: enter/exit edit-mode toggle
//   The enter+edit+save leg is already covered by
//   `profile_edit_persists_to_account_list_test.dart`. The MISSING leg is the
//   bidirectional toggle / EXIT: fire the toggle once → assert edit-mode fields mount,
//   fire it again → assert fields UNMOUNT (the `_editMode=false` flip). Also covers
//   the Save→exit path: enter edit, save, assert fields unmount without a second tap.
//
// Why these drive the real production path:
//   - `buildSidebar` + `_UserAvatar` are the real production sidebar widgets; tapping
//     `sidebarUserAvatar` calls the real `_openProfile` → real `showSelfProfile` which
//     awaits `Prefs.getCurrentAccountToxId()` and builds the real `ProfilePage`.
//   - `profileEditToggle.onPressed` is the real `onToggleEdit` callback wired to
//     `setState(() => _editMode = !_editMode)` in `ProfilePage`.
//   - `profileSaveButton.onPressed` is the real `_handleSave` → `onSave` closure.
//   All of these are the exact production widgets, not test doubles.
//
// Harness notes:
//   - No native lib, no real network — fully hermetic, CI-runnable.
//   - `pumpAndSettle()` is NOT used: the profile QR section (`ProfileQrSection`)
//     contains a perpetual `CircularProgressIndicator` that prevents settlement.
//     Instead `_settle()` pumps a fixed number of frames (matching the existing tests).
//   - Desktop surface size 1280x900 forces the `showDialog` (not mobile) path, which
//     is the same path exercised by the existing harness tests.
//   - `flutter/platform` (JSONMethodCodec) and `plugins.flutter.io/path_provider`
//     channels are mocked because `MaterialApp` emits `SystemChrome` platform calls
//     and `ProfilePage`/Prefs init resolve app directories.
//   - Mobile parity: all widgets under test live in `lib/ui/profile/` and
//     `lib/ui/settings/sidebar.dart` — shared Dart code, identical on iOS/Android.
//     The only platform fork is Dialog (desktop) vs fullscreen route (mobile), both
//     in `sidebar.dart`. The identity and toggle assertions in A1–A4 hold on both.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/profile/profile_header.dart';
import 'package:toxee/ui/settings/sidebar.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/prefs.dart';

// A well-formed 76-char uppercase-hex Tox ID (public key 64 chars + nospam
// 8 chars + checksum 4 chars). No FFI call is needed because the stub
// returns it directly from `getSelfToxId()`, bypassing the native library.
const String _toxId =
    'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF01234567';
const String _nickname = 'HarnessNick';
const String _statusMessage = 'HarnessStatus';

/// Minimal FfiChatService stub: answers getSelfToxId / selfId from the const
/// above and absorbs updateSelfProfile / updateAvatar with no-ops. Inherits
/// the non-abstract `avatarUpdated` broadcast stream from the base class.
class _HarnessService extends FfiChatService {
  _HarnessService() : super();

  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connectionStatusStream => _connection.stream;

  @override
  String get selfId => _toxId;

  @override
  String? getSelfToxId() => _toxId;

  @override
  Future<void> updateSelfProfile({
    required String nickname,
    required String statusMessage,
  }) async {}

  @override
  Future<void> updateAvatar(String? avatarPath) async {}

  void disposeStub() => unawaited(_connection.close());
}

/// Same service but also records the last updateSelfProfile call so we can
/// prove the real onSave closure executed in the edit-toggle test.
class _RecordingHarnessService extends _HarnessService {
  ({String nickname, String statusMessage})? lastProfileUpdate;

  @override
  Future<void> updateSelfProfile({
    required String nickname,
    required String statusMessage,
  }) async {
    lastProfileUpdate = (nickname: nickname, statusMessage: statusMessage);
  }
}

class _PendingRecordingHarnessService extends _RecordingHarnessService {
  final Completer<void> _updateCompleter = Completer<void>();
  int updateCallCount = 0;

  @override
  Future<void> updateSelfProfile({
    required String nickname,
    required String statusMessage,
  }) {
    updateCallCount++;
    lastProfileUpdate = (nickname: nickname, statusMessage: statusMessage);
    return _updateCompleter.future;
  }

  void completeUpdate() {
    if (!_updateCompleter.isCompleted) _updateCompleter.complete();
  }
}

Widget _app(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: child),
  );
}

/// Bounded settle: pumps 8 × 100 ms frames instead of `pumpAndSettle()`.
/// The profile QR section has a perpetual `CircularProgressIndicator` that
/// would cause `pumpAndSettle()` to hang (it never settles). 800 ms is
/// sufficient for the dialog route transition, edit-mode rebuild, and the
/// async Prefs writes that `showSelfProfile`/`_handleSave` perform.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  late Directory tempRoot;

  // `flutter/platform` uses JSONMethodCodec — MaterialApp emits SystemChrome
  // platform calls (e.g. setSystemUIOverlayStyle) and crashes without a mock.
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());

  // path_provider is required because ProfilePage._loadAvatar() and
  // ProfilePage._loadCardText() call Prefs which resolves the support
  // directory via path_provider on the first SharedPreferences getInstance().
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'profile_open_and_edit_toggle_real_ui_test_',
    );
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      platformChannel,
      (MethodCall call) async => null,
    );
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      switch (call.method) {
        case 'getApplicationSupportDirectory':
          return tempRoot.path;
        case 'getApplicationDocumentsDirectory':
          return tempRoot.path;
        case 'getApplicationCacheDirectory':
          return p.join(tempRoot.path, 'cache');
        case 'getTemporaryDirectory':
          return p.join(tempRoot.path, 'temp');
        case 'getDownloadsDirectory':
          return p.join(tempRoot.path, 'Downloads');
        default:
          return null;
      }
    });

    // Seed Prefs with one account so showSelfProfile resolves the real toxId.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    await Prefs.addAccount(
      toxId: _toxId,
      nickname: _nickname,
      statusMessage: _statusMessage,
    );
    await Prefs.setCurrentAccountToxId(_toxId);
    await Prefs.setNickname(_nickname);
    await Prefs.setStatusMessage(_statusMessage);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platformChannel, null);
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  // ---------------------------------------------------------------------------
  // S104 — Sidebar avatar tap → opens self-profile
  // ---------------------------------------------------------------------------
  group('S104 — sidebar avatar tap opens self-profile', () {
    testWidgets('tap sidebarUserAvatar → profile mounts with correct identity (A1–A4)', (
      WidgetTester tester,
    ) async {
      final service = _HarnessService();
      addTearDown(service.disposeStub);

      // Desktop surface so showSelfProfile takes the showDialog (not
      // MaterialPageRoute) path — mirrors the harness in profile_anchor_keys_test.
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Pump the real sidebar with the real _UserAvatar InkWell.
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => buildSidebar(
              context: context,
              selectedIndex: 0,
              onTap: (_) {},
              service: service,
              connectionStatusStream: service.connectionStatusStream,
            ),
          ),
        ),
      );
      await _settle(tester);

      // Pre-condition: sidebar is visible, profile NOT yet open.
      expect(
        find.byKey(UiKeys.sidebarUserAvatar),
        findsOneWidget,
        reason: 'sidebar must render the avatar InkWell before any tap',
      );
      expect(
        find.byKey(UiKeys.profileEditToggle),
        findsNothing,
        reason:
            'profile must NOT be open before the avatar tap (pre-condition)',
      );

      // REAL INTERACTION: tap the production InkWell → _openProfile →
      // showSelfProfile (awaits Prefs.getCurrentAccountToxId, builds ProfilePage).
      await tester.tap(find.byKey(UiKeys.sidebarUserAvatar));
      await _settle(tester);

      // --- A1: profileEditToggle present → ProfilePage mounted with isEditable:true
      // The toggle (profile_header.dart:107-112) is only rendered when the
      // `isEditable` flag is true — its presence proves the right constructor
      // branch was taken inside showSelfProfile (sidebar.dart:62-66).
      expect(
        find.byKey(UiKeys.profileEditToggle),
        findsOneWidget,
        reason:
            'A1: profileEditToggle must appear → ProfilePage(isEditable:true) mounted',
      );

      // --- A2: profileToxIdSelectableText VALUE equals the seeded 76-hex toxId
      // showSelfProfile resolves the id via `Prefs.getCurrentAccountToxId()`.
      // If the resolve regressed to the UIKit placeholder, the value would NOT
      // equal _toxId. Reading `.data` from the real widget proves the resolved
      // identity was threaded all the way to ProfileToxIdSection.
      expect(
        find.byKey(UiKeys.profileToxIdSelectableText),
        findsOneWidget,
        reason: 'A2: profileToxIdSelectableText key must be present',
      );
      final selectableText = tester.widget<SelectableText>(
        find.byKey(UiKeys.profileToxIdSelectableText),
      );
      expect(
        selectableText.data,
        _toxId,
        reason:
            'A2: SelectableText.data must equal the seeded toxId (not a placeholder)',
      );

      // --- A3: displayed nickname in the header matches the seeded nickname.
      // Scope to the profile's ProfileHeader: the sidebar `_UserAvatar` ALSO
      // renders the nickname (sidebar.dart:483-487), so an unscoped
      // find.text(_nickname) would match the sidebar copy underneath the dialog
      // and be vacuous. Asserting it INSIDE ProfileHeader proves the live
      // identity (ProfilePage._effectiveDisplayName) threaded into the opened
      // profile, not a stale/empty string.
      expect(
        find.descendant(
          of: find.byType(ProfileHeader),
          matching: find.text(_nickname),
        ),
        findsOneWidget,
        reason:
            'A3: the opened profile header must display the seeded nickname',
      );

      // --- A4: profileToxIdCopyButton present (ProfileToxIdSection rendered fully).
      expect(
        find.byKey(UiKeys.profileToxIdCopyButton),
        findsOneWidget,
        reason: 'A4: copy button must be present (belt-and-suspenders on A1)',
      );
    });

    testWidgets('dismiss (close-button) removes profile from tree (A5)', (
      WidgetTester tester,
    ) async {
      final service = _HarnessService();
      addTearDown(service.disposeStub);

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => buildSidebar(
              context: context,
              selectedIndex: 0,
              onTap: (_) {},
              service: service,
              connectionStatusStream: service.connectionStatusStream,
            ),
          ),
        ),
      );
      await _settle(tester);

      // Open the profile via the real tap.
      await tester.tap(find.byKey(UiKeys.sidebarUserAvatar));
      await _settle(tester);

      // Profile must be open.
      expect(
        find.byKey(UiKeys.profileEditToggle),
        findsOneWidget,
        reason: 'profile must be open before testing dismiss',
      );

      // REAL DISMISS: the desktop dialog exposes a Positioned close IconButton
      // at the top-right with icon Icons.close (sidebar.dart:179-186). Pop via
      // the real Navigator to exercise the production dismiss path.
      // The dialog is dismissed by tapping the close icon that wraps the
      // `Navigator.of(dialogContext).pop()` callback.
      // The profileEditToggle is also an IconButton; find the close-dialog one
      // by its Icons.close icon data. The profile close button is Positioned
      // inside the dialog Stack (sidebar.dart:178) with icon Icons.close;
      // the edit toggle (profile_header.dart:109) also uses Icons.close when in
      // edit mode — but edit mode is NOT active here, so the toggle shows
      // Icons.edit. The single Icons.close button in the read-only dialog is
      // the dismiss affordance.
      final closeIconFinder = find.byWidgetPredicate((widget) {
        if (widget is! IconButton) return false;
        final iconWidget = widget.icon;
        if (iconWidget is! Icon) return false;
        return iconWidget.icon == Icons.close;
      });
      expect(
        closeIconFinder,
        findsAtLeastNWidgets(1),
        reason: 'dismiss: close IconButton must be present in the dialog',
      );

      // Fire the first close button's onPressed (the dialog dismiss affordance).
      // In read-only mode the edit toggle shows Icons.edit not Icons.close, so
      // every Icons.close button here is the dialog-level close affordance.
      final closeButton = tester.firstWidget<IconButton>(closeIconFinder);
      closeButton.onPressed!.call();
      await _settle(tester);

      // --- A5: after dismiss, profileEditToggle is gone.
      expect(
        find.byKey(UiKeys.profileEditToggle),
        findsNothing,
        reason:
            'A5: profileEditToggle must be gone after the dialog is dismissed',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // S101 — Self-profile: enter/exit edit-mode toggle
  // ---------------------------------------------------------------------------
  group('S101 — self-profile edit-mode bidirectional toggle', () {
    /// Opens the profile via a test button that calls the real `showSelfProfile`.
    /// This mirrors `profile_edit_persists_to_account_list_test.dart`'s harness
    /// helper.
    Widget buildHarness(_RecordingHarnessService svc) {
      return _app(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showSelfProfile(
                context,
                svc,
                svc.connectionStatusStream,
                nickName: _nickname,
                statusMessage: _statusMessage,
              ),
              child: const Text('open profile'),
            ),
          ),
        ),
      );
    }

    testWidgets('toggle ON mounts edit fields, toggle OFF unmounts them (A1 + A4)', (
      WidgetTester tester,
    ) async {
      final service = _RecordingHarnessService();
      addTearDown(service.disposeStub);

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildHarness(service));
      await tester.pump();

      // Open the real ProfilePage via showSelfProfile.
      await tester.tap(find.text('open profile'));
      await _settle(tester);

      // Pre-condition: profile is open in read-only mode.
      expect(
        find.byKey(UiKeys.profileEditToggle),
        findsOneWidget,
        reason: 'profileEditToggle must be present in read-only mode',
      );
      expect(
        find.byKey(UiKeys.profileSaveButton),
        findsNothing,
        reason: 'saveButton must NOT be present before entering edit mode',
      );

      // -----------------------------------------------------------------------
      // Toggle ON → assert A1: edit-mode fields mount.
      // Fire the real onPressed of the profileEditToggle (the production
      // `onToggleEdit` callback which calls `setState(() => _editMode = true)`
      // in ProfilePage). Direct `.call()` is used for the same hit-test reason
      // documented in profile_edit_persists_to_account_list_test.dart:153-161.
      tester
          .widget<IconButton>(find.byKey(UiKeys.profileEditToggle))
          .onPressed!
          .call();
      await _settle(tester);

      // A1: after toggle ON, all three edit-mode widgets must mount.
      expect(
        find.byKey(UiKeys.profileNicknameField),
        findsOneWidget,
        reason: 'A1: profileNicknameField must mount after toggle ON',
      );
      expect(
        find.byKey(UiKeys.profileStatusField),
        findsOneWidget,
        reason: 'A1: profileStatusField must mount after toggle ON',
      );
      expect(
        find.byKey(UiKeys.profileSaveButton),
        findsOneWidget,
        reason: 'A1: profileSaveButton must mount after toggle ON',
      );

      // -----------------------------------------------------------------------
      // Toggle OFF → assert A4: edit-mode fields UNMOUNT.
      // The profileEditToggle is still present (it is always rendered when
      // isEditable:true). Fire it again — this is the EXIT path.
      tester
          .widget<IconButton>(find.byKey(UiKeys.profileEditToggle))
          .onPressed!
          .call();
      await _settle(tester);

      // A4: after toggle OFF (no save), the save button and edit fields unmount.
      expect(
        find.byKey(UiKeys.profileSaveButton),
        findsNothing,
        reason:
            'A4: profileSaveButton must UNMOUNT after toggling edit mode OFF '
            '(without saving) — this is the _editMode=false flip',
      );
      expect(
        find.byKey(UiKeys.profileNicknameField),
        findsNothing,
        reason: 'A4: profileNicknameField must UNMOUNT after toggle OFF',
      );
      expect(
        find.byKey(UiKeys.profileStatusField),
        findsNothing,
        reason: 'A4: profileStatusField must UNMOUNT after toggle OFF',
      );

      // Toggle is still there (read-only mode, not dismissed).
      expect(
        find.byKey(UiKeys.profileEditToggle),
        findsOneWidget,
        reason:
            'profileEditToggle must remain in read-only mode (not dismissed)',
      );
    });

    testWidgets(
      'Cancel restores persisted nickname and status without updating profile',
      (WidgetTester tester) async {
        final service = _RecordingHarnessService();
        addTearDown(service.disposeStub);

        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(buildHarness(service));
        await tester.pump();
        await tester.tap(find.text('open profile'));
        await _settle(tester);

        tester
            .widget<IconButton>(find.byKey(UiKeys.profileEditToggle))
            .onPressed!
            .call();
        await _settle(tester);

        await tester.enterText(
          find.byKey(UiKeys.profileNicknameField),
          'Discarded nickname',
        );
        await tester.enterText(
          find.byKey(UiKeys.profileStatusField),
          'Discarded status',
        );
        await tester.pump();

        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await _settle(tester);

        expect(
          find.byKey(UiKeys.profileNicknameField),
          findsNothing,
          reason: 'the real Cancel control must leave edit mode',
        );
        expect(
          service.lastProfileUpdate,
          isNull,
          reason: 'Cancel must not call updateSelfProfile',
        );

        tester
            .widget<IconButton>(find.byKey(UiKeys.profileEditToggle))
            .onPressed!
            .call();
        await _settle(tester);

        expect(
          tester
              .widget<TextField>(find.byKey(UiKeys.profileNicknameField))
              .controller!
              .text,
          _nickname,
          reason: 're-entering edit must show the persisted nickname',
        );
        expect(
          tester
              .widget<TextField>(find.byKey(UiKeys.profileStatusField))
              .controller!
              .text,
          _statusMessage,
          reason: 're-entering edit must show the persisted status',
        );
        expect(
          service.lastProfileUpdate,
          isNull,
          reason: 're-entering after Cancel must not update the service',
        );
      },
    );

    testWidgets('Save path: edit fields unmount after successful save (A3)', (
      WidgetTester tester,
    ) async {
      final service = _RecordingHarnessService();
      addTearDown(service.disposeStub);

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildHarness(service));
      await tester.pump();

      // Open the profile.
      await tester.tap(find.text('open profile'));
      await _settle(tester);

      // Enter edit mode.
      tester
          .widget<IconButton>(find.byKey(UiKeys.profileEditToggle))
          .onPressed!
          .call();
      await _settle(tester);

      // Confirm fields are present before save.
      expect(find.byKey(UiKeys.profileSaveButton), findsOneWidget);

      // Edit status so save button is enabled (short text, well under the
      // 24-CJK-char / 48-ASCII-char limit checked by profileTextLength).
      await tester.enterText(
        find.byKey(UiKeys.profileStatusField),
        'S101 save test',
      );
      await tester.pump();

      // Fire the REAL _handleSave via the real FilledButton.onPressed.
      // This runs: onSave (service.updateSelfProfile + Prefs writes) +
      // setState(() => _editMode = false).
      final saveButton = tester.widget<FilledButton>(
        find.byKey(UiKeys.profileSaveButton),
      );
      expect(
        saveButton.onPressed,
        isNotNull,
        reason: 'save button must be enabled after valid text input',
      );
      saveButton.onPressed!.call();
      await _settle(tester);

      // Prove the real onSave closure ran (not just a UI visual check).
      expect(
        service.lastProfileUpdate?.nickname,
        _nickname,
        reason:
            'A3 proof: real updateSelfProfile was called — onSave closure executed',
      );

      // --- A3: after Save, the edit fields UNMOUNT (the _editMode=false flip
      // inside _handleSave → setState(() => _editMode = false)).
      expect(
        find.byKey(UiKeys.profileSaveButton),
        findsNothing,
        reason:
            'A3: profileSaveButton must UNMOUNT after a successful save '
            '(setState(() => _editMode = false) in _handleSave)',
      );
      expect(
        find.byKey(UiKeys.profileNicknameField),
        findsNothing,
        reason: 'A3: profileNicknameField must UNMOUNT after save',
      );
      expect(
        find.byKey(UiKeys.profileStatusField),
        findsNothing,
        reason: 'A3: profileStatusField must UNMOUNT after save',
      );

      // The dialog remains mounted in read-only mode (not popped by _handleSave).
      expect(
        find.byKey(UiKeys.profileEditToggle),
        findsOneWidget,
        reason: 'profileEditToggle must remain after save (dialog stays open)',
      );
    });

    testWidgets(
      'header cancel is disabled during save and submitted values remain saved',
      (WidgetTester tester) async {
        final service = _PendingRecordingHarnessService();
        addTearDown(service.disposeStub);
        addTearDown(service.completeUpdate);

        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(buildHarness(service));
        await tester.pump();
        await tester.tap(find.text('open profile'));
        await _settle(tester);

        final enterEditCallback = tester
            .widget<IconButton>(find.byKey(UiKeys.profileEditToggle))
            .onPressed!;
        enterEditCallback.call();
        await _settle(tester);

        const submittedNickname = 'Submitted nickname';
        const submittedStatus = 'Submitted status';
        await tester.enterText(
          find.byKey(UiKeys.profileNicknameField),
          submittedNickname,
        );
        await tester.enterText(
          find.byKey(UiKeys.profileStatusField),
          submittedStatus,
        );
        await tester.pump();

        final headerCancelCallback = tester
            .widget<IconButton>(find.byKey(UiKeys.profileEditToggle))
            .onPressed!;
        tester
            .widget<FilledButton>(find.byKey(UiKeys.profileSaveButton))
            .onPressed!
            .call();
        await tester.pump();

        expect(service.updateCallCount, 1);
        expect(service.lastProfileUpdate, (
          nickname: submittedNickname,
          statusMessage: submittedStatus,
        ));
        expect(
          tester
              .widget<IconButton>(find.byKey(UiKeys.profileEditToggle))
              .onPressed,
          isNull,
          reason: 'the header cancel affordance must be disabled while saving',
        );

        headerCancelCallback.call();
        await tester.pump();
        expect(
          find.byKey(UiKeys.profileNicknameField),
          findsOneWidget,
          reason: 'a stale header callback must not cancel a pending save',
        );

        service.completeUpdate();
        await _settle(tester);

        expect(service.updateCallCount, 1);
        expect(
          find.descendant(
            of: find.byType(ProfileHeader),
            matching: find.text(submittedNickname),
          ),
          findsOneWidget,
          reason: 'the completed save must display the submitted nickname',
        );
        expect(
          find.descendant(
            of: find.byType(ProfileHeader),
            matching: find.text(submittedStatus),
          ),
          findsOneWidget,
          reason: 'the completed save must display the submitted status',
        );

        tester
            .widget<IconButton>(find.byKey(UiKeys.profileEditToggle))
            .onPressed!
            .call();
        await _settle(tester);

        expect(
          tester
              .widget<TextField>(find.byKey(UiKeys.profileNicknameField))
              .controller!
              .text,
          submittedNickname,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(UiKeys.profileStatusField))
              .controller!
              .text,
          submittedStatus,
        );
      },
    );
  });
}
