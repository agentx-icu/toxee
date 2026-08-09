// Real-UI gates for the TABLET form factor of the two "add" dialogs.
//
// What is under test
// ------------------
// `AddFriendDialog` and `AddGroupDialog` each compute their own responsive
// `AppDialog.maxWidth` through a private `_dialogMaxWidth(context)`
// (`lib/ui/add_friend_dialog.dart:30-42`, `lib/ui/add_group_dialog.dart:26-38`).
// Both functions test `ResponsiveLayout.isDesktop` FIRST, then
// `isTabletLandscape`, then `isTablet`, then fall through to the mobile cap.
//
// The product rule that makes the tablet tier interesting is in
// `ResponsiveLayout.isDesktop` (`lib/util/responsive_layout.dart:119-126`):
//
//     isDesktop == true  when the OS is a desktop OS
//                  OR    isTablet(context)          <-- tablets!
//                  OR    width >= tabletBreakpoint (1024)
//
// so a tablet has a DOUBLE identity: `isTablet` is true *and* `isDesktop` is
// true. Because `_dialogMaxWidth` checks `isDesktop` first, every tablet takes
// the DESKTOP branch and the two tablet branches below it are unreachable.
// These tests lock that in numerically: on an iPad-portrait viewport the
// desktop branch and the tablet branch produce DIFFERENT widths (720 vs 640
// for add-friend, 770 vs 720 for add-group), so if anyone ever reorders the
// branches the expectations here move.
//
// Why the platform override is mandatory
// --------------------------------------
// `ResponsiveLayout._isDesktopPlatform()` reads `dart:io` `Platform.*`, which
// `debugDefaultTargetPlatformOverride` does NOT affect. `flutter test` runs on
// a desktop host, so without `debugIsDesktopPlatformOverride` every `isTablet`
// call returns false and every assertion below would silently degrade into a
// "desktop host" assertion. `setUp` installs `() => false` (a touch OS) and
// `tearDown` restores `null` — the field is process-global.
//
// Real controls driven here
// -------------------------
//   * `UiKeys.newEntryMenuButton` + `UiKeys.newEntryAddContactItem` /
//     `UiKeys.newEntryCreateGroupItem` — the production `NewEntryButton`
//     popup that opens both dialogs, presented exactly as `HomePage` does it
//     (`showDialog(builder: (_) => AddFriendDialog(...))`, no outer `Dialog`
//     wrapper — see `home_page.dart:2135-2161`).
//   * `UiKeys.addFriendPasteButton` — real clipboard paste into the real
//     `TextFormField` controller.
//   * `UiKeys.addFriendSubmitButton` — real submit + real validator gate.
//   * The real "Create Group" `FilledButton` — real validator gate.
//
// Mobile parity: `responsive_layout.dart`, `add_friend_dialog.dart` and
// `add_group_dialog.dart` are shared Dart with no platform fork in the sizing
// path, so the tiers asserted here are the same code that runs on iPadOS and
// on Android tablets. The only platform fork in `AddFriendDialog` is
// `_supportsCameraScan` (iOS/Android only), which is why the QR button is not
// expected in these host-run assertions.
//
// NOT executed in this environment (no dart/flutter available) — reviewed by
// reading only.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/add_friend_dialog.dart';
import 'package:toxee/ui/add_group_dialog.dart';
import 'package:toxee/ui/home/home_widgets.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/ui/widgets/app_dialog.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/responsive_layout.dart';

/// Our own account (76 hex chars). Kept distinct from [_peerToxId] so the
/// dialog's self-add guard never fires.
const String _selfToxId =
    'AAAAAAAA11111111AAAAAAAA22222222AAAAAAAA33333333AAAAAAAA44444444AAAAAAAA5555';

/// A well-formed 76-char peer Tox address used for the paste test.
const String _peerToxId =
    'BBBBBBBB11111111BBBBBBBB22222222BBBBBBBB33333333BBBBBBBB44444444BBBBBBBB6666';

/// English validator text from `AppLocalizations.addFriendInvalidToxIdHint`
/// (`lib/i18n/app_localizations_en.dart:311-312`).
const String _invalidToxIdHint =
    'Tox address must be 76 hexadecimal characters';

/// English validator text from `AppLocalizations.enterGroupName`, surfaced by
/// the create-card validator in `add_group_dialog.dart:480-489`.
const String _enterGroupNameHint = 'Please enter Group Name';

class _StubFfiChatService extends FfiChatService {
  _StubFfiChatService() : super();

  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  /// Every serverId handed to [addFriend]; empty means the validator gate held.
  final List<String> addFriendCalls = <String>[];

  /// Every name handed to [createGroup]; empty means the validator gate held.
  final List<String> createGroupCalls = <String>[];

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connectionStatusStream => _connection.stream;

  @override
  String get selfId => _selfToxId;

  @override
  String? getSelfToxId() => _selfToxId;

  @override
  Future<List<({String userId, String nickName, String status, bool online})>>
  getFriendList() async =>
      <({String userId, String nickName, String status, bool online})>[];

  @override
  Future<AddFriendResult> addFriend(
    String serverId, {
    String? requestMessage,
  }) async {
    addFriendCalls.add(serverId);
    return AddFriendResult(
      resultCode: 0,
      userId: serverId,
      resultInfo: '',
      dispatched: true,
    );
  }

  @override
  Future<String?> createGroup(String name, {String groupType = 'group'}) async {
    createGroupCalls.add(name);
    return 'c' * 64;
  }

  void disposeStub() => unawaited(_connection.close());
}

/// True when `libtim2tox_ffi` can be dlopen'd. `FfiChatService`'s constructor
/// calls `Tim2ToxFfi.open()`, so the stub above cannot be built without it.
bool _ffiAvailable() {
  try {
    setNativeLibraryName('tim2tox_ffi');
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

/// Holds the harness `BuildContext` so a test can ask `ResponsiveLayout` what
/// tier it actually classified the viewport as. Guards against a vacuous run
/// (e.g. the platform override not taking effect and every "tablet" case
/// silently asserting desktop-host behaviour instead).
late BuildContext _harnessContext;

Widget _harness(_StubFfiChatService service) {
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
        builder: (ctx) {
          _harnessContext = ctx;
          return Center(
            child: NewEntryButton(
              // Presented exactly like HomePage._showAddFriendDialog /
              // _showAddGroupDialog: the dialog IS an AppDialog, so it must
              // NOT be wrapped in a second Dialog (that regression showed as
              // an empty frame around the card on iPad).
              onAddFriend: () async {
                await showDialog<void>(
                  context: ctx,
                  builder: (_) => AddFriendDialog(service: service),
                );
              },
              onCreateGroup: () async {
                await showDialog<void>(
                  context: ctx,
                  builder: (_) => AddGroupDialog(
                    service: service,
                    installDefaultGroupAvatar:
                        ({required String groupId, String? toxId}) async =>
                            '/tmp/$groupId-default.png',
                  ),
                );
              },
            ),
          );
        },
      ),
    ),
  );
}

Future<void> _openFromNewEntry(WidgetTester tester, Key item) async {
  await tester.tap(find.byKey(UiKeys.newEntryMenuButton));
  await tester.pumpAndSettle();
  expect(
    find.byKey(item),
    findsOneWidget,
    reason: 'the New-entry popup must expose $item before it can be tapped',
  );
  await tester.tap(find.byKey(item));
  await tester.pumpAndSettle();
}

/// Rendered width of the dialog card.
///
/// Chain: `AppDialog` -> `Transform.translate` -> Flutter's `Dialog` ->
/// `AnimatedPadding` (the 16pt `insetPadding`) -> `Align` ->
/// `ConstrainedBox(minWidth: 280)` -> **`Material`** -> `AppDialog`'s own
/// `ConstrainedBox(maxWidth: …)` -> `Column`. The first `Material` under the
/// `AppDialog` is Flutter's dialog surface and it sizes itself to that
/// `Column`, whose title-bar `Row` (mainAxisSize.max) stretches to the
/// `maxWidth` cap. So this is the real post-clamp card width, not a
/// re-computation of the production formula.
double _dialogCardWidth(WidgetTester tester) {
  final Finder surface = find
      .descendant(of: find.byType(AppDialog), matching: find.byType(Material))
      .first;
  return tester.getSize(surface).width;
}

double _appDialogMaxWidth(WidgetTester tester) {
  return tester.widget<AppDialog>(find.byType(AppDialog)).maxWidth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  late _StubFfiChatService service;

  // SystemChannels.platform uses JSONMethodCodec. It carries both the
  // SystemChrome calls MaterialApp emits and the Clipboard.getData the paste
  // button issues, so the handler must speak that codec.
  const MethodChannel platformChannel = MethodChannel(
    'flutter/platform',
    JSONMethodCodec(),
  );

  /// What `Clipboard.getData('text/plain')` will answer. Set per test.
  String? clipboardText;

  setUp(() async {
    clipboardText = null;

    // Tablets are NOT a desktop OS: force the touch-platform branch so
    // isTablet / isTabletPortrait / isTabletLandscape become reachable.
    ResponsiveLayout.debugIsDesktopPlatformOverride = () => false;

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    await Prefs.setCurrentAccountToxId(_selfToxId);

    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(platformChannel, (
      MethodCall call,
    ) async {
      if (call.method == 'Clipboard.getData') {
        if (clipboardText == null) return null;
        return <String, dynamic>{'text': clipboardText};
      }
      // HapticFeedback.vibrate, SystemChrome.* — irrelevant here.
      return null;
    });
  });

  tearDown(() {
    // Process-global: leaking either of these poisons every later test in the
    // same isolate.
    ResponsiveLayout.debugIsDesktopPlatformOverride = null;
    messenger.setMockMethodCallHandler(platformChannel, null);
  });

  /// Boots the harness at [size] and returns false when the native library is
  /// missing (the caller then reports a real skip).
  Future<bool> boot(WidgetTester tester, Size size) async {
    if (!_ffiAvailable()) return false;
    service = _StubFfiChatService();
    addTearDown(service.disposeStub);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_harness(service));
    await tester.pumpAndSettle();
    return true;
  }

  // -------------------------------------------------------------------------
  // iPad Pro 11" portrait — 834 x 1194. shortestSide 834 => tablet tier;
  // width 834 >= largePhoneBreakpoint (720) => sidebar tier;
  // width 834 >= masterDetailBreakpoint (800) => master-detail tier.
  // -------------------------------------------------------------------------
  group('iPad portrait 834x1194', () {
    testWidgets(
      'add-contact dialog takes the DESKTOP 720 cap, not the 640 tablet cap',
      (WidgetTester tester) async {
        if (!await boot(tester, const Size(834, 1194))) {
          markTestSkipped('libtim2tox_ffi is not loadable in this environment');
          return;
        }

        // Guard against a vacuous run: prove we really are in the tablet tier
        // AND that the tier claims desktop at the same time (the double
        // identity the dialog sizing depends on).
        expect(
          ResponsiveLayout.isTablet(_harnessContext),
          isTrue,
          reason: 'shortestSide 834 is inside [600, 1024) => tablet tier',
        );
        expect(
          ResponsiveLayout.isTabletPortrait(_harnessContext),
          isTrue,
          reason: '834x1194 is portrait',
        );
        expect(
          ResponsiveLayout.isDesktop(_harnessContext),
          isTrue,
          reason:
              'product rule: a tablet reports isDesktop==true in every '
              'orientation (responsive_layout.dart:119-126)',
        );

        await _openFromNewEntry(tester, UiKeys.newEntryAddContactItem);
        expect(
          find.byKey(UiKeys.addFriendIdInput),
          findsOneWidget,
          reason: 'the real AddFriendDialog must be mounted after the tap',
        );

        // desktop branch: (834 - 64).clamp(280, 720) == 720
        // tablet branch (unreachable): (834 - 48).clamp(280, 640) == 640
        expect(
          _appDialogMaxWidth(tester),
          720.0,
          reason:
              'iPad portrait must resolve the desktop cap (720). 640 here '
              'would mean the isTablet branch started winning over isDesktop.',
        );
        expect(
          _dialogCardWidth(tester),
          closeTo(720.0, 0.5),
          reason: 'the rendered card must actually be clamped to that cap',
        );
      },
    );

    testWidgets(
      'create-group dialog is w-64 (770) and the empty-name validator blocks createGroup',
      (WidgetTester tester) async {
        if (!await boot(tester, const Size(834, 1194))) {
          markTestSkipped('libtim2tox_ffi is not loadable in this environment');
          return;
        }

        await _openFromNewEntry(tester, UiKeys.newEntryCreateGroupItem);
        expect(
          find.byKey(UiKeys.addGroupCreateNameInput),
          findsOneWidget,
          reason: 'the real AddGroupDialog must be mounted after the tap',
        );

        // desktop branch: (834 - 64).clamp(280, 820) == 770  (below the cap)
        // tablet branch (unreachable): (834 - 48).clamp(280, 720) == 720
        expect(
          _appDialogMaxWidth(tester),
          770.0,
          reason:
              'iPad portrait add-group must be width-64 (770). 720 would mean '
              'the unreachable isTablet branch became reachable.',
        );

        // REAL CONTROL: submit the create card with an empty name.
        final Finder createButton = find.widgetWithText(
          FilledButton,
          'Create Group',
        );
        await tester.ensureVisible(createButton);
        await tester.pumpAndSettle();
        await tester.tap(createButton);
        await tester.pumpAndSettle();

        expect(
          find.text(_enterGroupNameHint),
          findsOneWidget,
          reason: 'the empty-name validator must surface on a tablet too',
        );
        expect(
          service.createGroupCalls,
          isEmpty,
          reason: 'createGroup must not fire while the validator is failing',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // iPad Pro 11" landscape — 1194 x 834. shortestSide is still 834, so the
  // device stays in the tablet tier; only the orientation flips.
  // -------------------------------------------------------------------------
  group('iPad landscape 1194x834', () {
    testWidgets(
      'paste button fills the real Tox ID field and enables the real submit button',
      (WidgetTester tester) async {
        if (!await boot(tester, const Size(1194, 834))) {
          markTestSkipped('libtim2tox_ffi is not loadable in this environment');
          return;
        }

        expect(
          ResponsiveLayout.isTabletLandscape(_harnessContext),
          isTrue,
          reason: '1194x834 on a touch OS is a tablet held in landscape',
        );

        clipboardText = _peerToxId;
        await _openFromNewEntry(tester, UiKeys.newEntryAddContactItem);

        final Finder submit = find.byKey(UiKeys.addFriendSubmitButton);
        expect(
          tester.widget<FilledButton>(submit).onPressed,
          isNull,
          reason: 'submit is gated on a non-empty Tox ID before the paste',
        );

        // REAL CONTROL: the paste IconButton inside the field's suffix row.
        await tester.tap(find.byKey(UiKeys.addFriendPasteButton));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<TextFormField>(find.byKey(UiKeys.addFriendIdInput))
              .controller
              ?.text,
          _peerToxId,
          reason: 'paste must land in the real ID controller',
        );
        expect(
          tester.widget<FilledButton>(submit).onPressed,
          isNotNull,
          reason: 'a pasted ID must enable submit (both fields now non-empty)',
        );
      },
    );

    testWidgets('add-group dialog reaches the 820 desktop cap in landscape', (
      WidgetTester tester,
    ) async {
      if (!await boot(tester, const Size(1194, 834))) {
        markTestSkipped('libtim2tox_ffi is not loadable in this environment');
        return;
      }

      await _openFromNewEntry(tester, UiKeys.newEntryCreateGroupItem);

      // desktop branch: (1194 - 64).clamp(280, 820) == 820
      expect(
        _appDialogMaxWidth(tester),
        820.0,
        reason: 'landscape tablet has room for the full 820 create-group cap',
      );
    });
  });

  // -------------------------------------------------------------------------
  // 7-9" tablet portrait — 768 x 1024 (classic iPad mini / Android tablet).
  // shortestSide 768 => tablet; width 768 is >= 720 (sidebar) but < 800
  // (no master-detail), so this size sits between the two width breakpoints.
  // -------------------------------------------------------------------------
  group('small tablet portrait 768x1024', () {
    testWidgets(
      'dialog width is w-64 (704, under the cap) and an invalid Tox ID is rejected before addFriend',
      (WidgetTester tester) async {
        if (!await boot(tester, const Size(768, 1024))) {
          markTestSkipped('libtim2tox_ffi is not loadable in this environment');
          return;
        }

        expect(
          ResponsiveLayout.isTablet(_harnessContext),
          isTrue,
          reason: 'shortestSide 768 is inside [600, 1024)',
        );
        expect(
          ResponsiveLayout.shouldShowMasterDetail(_harnessContext),
          isFalse,
          reason: 'width 768 < masterDetailBreakpoint (800)',
        );

        await _openFromNewEntry(tester, UiKeys.newEntryAddContactItem);

        // desktop branch: (768 - 64).clamp(280, 720) == 704 (cap not reached)
        // tablet branch (unreachable): (768 - 48).clamp(280, 640) == 640
        expect(
          _appDialogMaxWidth(tester),
          704.0,
          reason:
              'below the 720 cap the width tracks the viewport minus the '
              '64pt desktop inset',
        );

        // REAL CONTROL: type a 64-char key (the old, wrong length) and submit.
        await tester.enterText(find.byKey(UiKeys.addFriendIdInput), 'A' * 64);
        await tester.pumpAndSettle();

        final Finder submit = find.byKey(UiKeys.addFriendSubmitButton);
        expect(
          tester.widget<FilledButton>(submit).onPressed,
          isNotNull,
          reason: 'submit is enabled on non-empty input (validation is on tap)',
        );
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        await tester.tap(submit);
        await tester.pumpAndSettle();

        expect(
          find.text(_invalidToxIdHint),
          findsOneWidget,
          reason: 'a 64-char key is not a 76-char Tox address',
        );
        expect(
          service.addFriendCalls,
          isEmpty,
          reason: 'addFriend must not fire while the validator is failing',
        );
        expect(
          find.byKey(UiKeys.addFriendIdInput),
          findsOneWidget,
          reason: 'a failed validation must keep the dialog open for a retry',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Boundary: mobileBreakpoint == 600 on `shortestSide`. This is the edge a
  // refactor is most likely to move by one pixel.
  // -------------------------------------------------------------------------
  group('phone/tablet boundary at shortestSide 600', () {
    testWidgets('900x600 (shortestSide == 600) is a tablet -> 720 cap', (
      WidgetTester tester,
    ) async {
      if (!await boot(tester, const Size(900, 600))) {
        markTestSkipped('libtim2tox_ffi is not loadable in this environment');
        return;
      }

      expect(
        ResponsiveLayout.isTablet(_harnessContext),
        isTrue,
        reason: 'the tablet tier is inclusive at exactly 600',
      );
      expect(ResponsiveLayout.isMobile(_harnessContext), isFalse);

      await _openFromNewEntry(tester, UiKeys.newEntryAddContactItem);
      // desktop branch (tablet => isDesktop): (900-64).clamp(280,720) == 720
      expect(_appDialogMaxWidth(tester), 720.0);
    });

    testWidgets('900x599 (shortestSide == 599) is a phone -> 480 cap', (
      WidgetTester tester,
    ) async {
      if (!await boot(tester, const Size(900, 599))) {
        markTestSkipped('libtim2tox_ffi is not loadable in this environment');
        return;
      }

      expect(
        ResponsiveLayout.isTablet(_harnessContext),
        isFalse,
        reason: 'one pixel below the breakpoint is still the phone tier',
      );
      expect(
        ResponsiveLayout.isDesktop(_harnessContext),
        isFalse,
        reason:
            'not a desktop OS, not a tablet, and width 900 < 1024 => no '
            'desktop classification, so the mobile branch is reachable',
      );

      await _openFromNewEntry(tester, UiKeys.newEntryAddContactItem);
      // mobile branch: (900 - 32).clamp(280, 480) == 480
      expect(
        _appDialogMaxWidth(tester),
        480.0,
        reason:
            'the phone tier keeps the narrow 480 cap — this is the assertion '
            'that proves the 600 boundary is real and not cosmetic',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Boundary: tabletBreakpoint == 1024 on `shortestSide`.
  //
  // Finding locked in here: crossing 1024 flips `isTablet` true -> false but
  // changes NOTHING downstream, because `isDesktop` is already true on the
  // tablet side (via the isTablet clause) and stays true on the far side (via
  // `width >= 1024` — a viewport whose shortestSide is >= 1024 necessarily has
  // width >= 1024). The dialog cap is identical on both sides. If a future
  // change makes the two tiers diverge, the second half of this test starts
  // failing and that divergence becomes an explicit decision.
  // -------------------------------------------------------------------------
  group('tablet/desktop boundary at shortestSide 1024', () {
    testWidgets(
      'isTablet flips at 1024 while the dialog cap stays on the desktop branch',
      (WidgetTester tester) async {
        if (!await boot(tester, const Size(1400, 1023))) {
          markTestSkipped('libtim2tox_ffi is not loadable in this environment');
          return;
        }

        expect(
          ResponsiveLayout.isTablet(_harnessContext),
          isTrue,
          reason: 'shortestSide 1023 < tabletBreakpoint (1024)',
        );
        expect(ResponsiveLayout.isDesktop(_harnessContext), isTrue);

        await _openFromNewEntry(tester, UiKeys.newEntryAddContactItem);
        expect(_appDialogMaxWidth(tester), 720.0);

        // Grow by one logical pixel: the device leaves the tablet tier.
        await tester.binding.setSurfaceSize(const Size(1400, 1024));
        await tester.pumpAndSettle();

        expect(
          ResponsiveLayout.isTablet(_harnessContext),
          isFalse,
          reason: 'shortestSide 1024 is at/above tabletBreakpoint',
        );
        expect(
          ResponsiveLayout.isDesktop(_harnessContext),
          isTrue,
          reason: 'now desktop by the width >= 1024 fallback instead',
        );
        expect(
          _appDialogMaxWidth(tester),
          720.0,
          reason:
              'both sides of the 1024 boundary land on the desktop branch, so '
              'the user-visible dialog geometry does not change',
        );
      },
    );
  });
}
