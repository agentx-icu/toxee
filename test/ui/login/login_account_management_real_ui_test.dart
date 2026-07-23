// Real-UI L1 WidgetTester gates for the toxee LOGIN page saved-account
// ACCOUNT-MANAGEMENT surface: the long-press / secondary-tap bottom sheet
// (`_showAccountManagementMenu`), the Export action (`_exportAccountFrom
// LoginPage`), and the Delete-confirm dialog (`_confirmDeleteAccountFromLogin
// Page`) for BOTH the no-password (confirm-word) and password-protected
// branches.
//
// WHY these are REAL-UI gates:
//   - Every case pumps the REAL production `LoginPage` and drives the REAL
//     saved-account `InkWell` via `tester.longPress` / a synthetic secondary
//     (right-click) tap, opening the REAL `showModalBottomSheet`. We assert on
//     the REAL Export + Delete ListTiles (keyed at the widget).
//   - Export is observed through the documented `exportAccount` test seam on
//     `LoginPage` (a recording stub): tapping Export runs the production
//     `_exportAccountFromLoginPage`, which invokes the seam and then shows the
//     success SnackBar with the returned path. Both the recorded toxId AND the
//     SnackBar are real side-effects of the production handler.
//   - Delete drives the REAL confirm dialog. The no-password branch reads the
//     required confirm word from the production dialog copy and proves a wrong
//     word is rejected and the right word ("delete") deletes the account
//     (removed from the live list). The password branch wires the in-memory
//     secure-storage mock and proves a wrong password is rejected and the
//     correct one deletes — both via the production `Prefs.verifyAccount
//     Password`.
//
// CRYPTO NOTE: the password-protected delete branch runs PBKDF2 (150k iters)
// via `package:cryptography`, whose async work the `testWidgets` FakeAsync
// zone does not drive. Those interactions run inside `tester.runAsync()`.
//
// Mobile parity: login_page.dart is shared Dart; the long-press bottom sheet is
// the mobile affordance and the secondary-tap is the desktop one — both live
// in the same handler. See the header comment in lib/ui/login_page.dart.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/login_page.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/mobile_export_policy.dart';
import 'package:toxee/util/prefs.dart';

const _exportOptionKey = Key('login_account_management_export_option');
const _deleteOptionKey = Key('login_account_management_delete_option');
const _deleteConfirmInputKey = Key('login_delete_account_confirm_input');
const _deleteConfirmButtonKey = Key('login_delete_account_confirm_button');

Widget _pumpableLoginPage({
  Future<String> Function({required String toxId, String? password})?
  exportAccount,
  bool? isDesktopExportPlatformOverride,
  MobileExportSaveFile? mobileExportSaveFile,
  SaveMobileExportCopyFn? saveMobileExportCopyOverride,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: LoginPage(
      exportAccount: exportAccount,
      isDesktopExportPlatformOverride: isDesktopExportPlatformOverride,
      mobileExportSaveFile: mobileExportSaveFile,
      saveMobileExportCopyOverride: saveMobileExportCopyOverride,
    ),
  );
}

Future<void> _pumpAndLoad(WidgetTester tester, Widget root) async {
  await tester.binding.setSurfaceSize(const Size(1024, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final originalOnError = FlutterError.onError;
  addTearDown(() => FlutterError.onError = originalOnError);
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exception.toString().contains('A RenderFlex overflowed')) {
      return;
    }
    final fallback = originalOnError;
    if (fallback != null) fallback(details);
  };
  await tester.pumpWidget(root);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 400)); // settle row stagger
}

/// Tap a fire-and-forget handler that runs PBKDF2 work, then pump the REAL
/// event loop until [isDone] (bounded). Required for the password-protected
/// delete branch whose verifyAccountPassword hops the real event loop.
Future<void> _tapAndAwait(
  WidgetTester tester, {
  required Finder trigger,
  required bool Function() isDone,
}) async {
  await tester.runAsync(() async {
    await tester.tap(trigger);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (isDone()) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Right-click (desktop) on a finder: dispatch a secondary-button pointer
/// down/up so the production `onSecondaryTapUp` fires.
Future<void> _secondaryTap(WidgetTester tester, Finder finder) async {
  final center = tester.getCenter(finder);
  final gesture = await tester.startGesture(
    center,
    buttons: kSecondaryButton,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final secureStore = <String, String>{};
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    secureStore.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureChannel, (MethodCall call) async {
      final args =
          (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      switch (call.method) {
        case 'write':
          secureStore[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return secureStore[args['key'] as String];
        case 'delete':
          secureStore.remove(args['key'] as String);
          return null;
        case 'containsKey':
          return secureStore.containsKey(args['key'] as String);
        case 'readAll':
          return Map<String, String>.from(secureStore);
        case 'deleteAll':
          secureStore.clear();
          return null;
        default:
          return null;
      }
    });
    // _confirmDeleteAccountFromLoginPage -> AccountService.deleteAccountWithout
    // Service touches AppPaths (path_provider) when removing the profile/data
    // dirs; mock to a temp path so it no-ops cleanly.
    messenger.setMockMethodCallHandler(pathProviderChannel, (
      MethodCall call,
    ) async {
      return '${Directory.systemTemp.path}/login_acct_mgmt_test';
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureChannel, null);
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
  });

  Future<void> initAccounts(List<Map<String, String>> accounts) async {
    SharedPreferences.setMockInitialValues({
      'account_list': jsonEncode(accounts),
    });
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
  }

  group('LoginPage account-management bottom sheet', () {
    testWidgets(
      'long-press on a saved-account card opens the sheet with Export + Delete',
      (tester) async {
        const toxId =
            'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
        await initAccounts([
          {'toxId': toxId, 'nickname': 'Alice', 'statusMessage': ''},
        ]);
        await _pumpAndLoad(tester, _pumpableLoginPage());

        await tester.longPress(find.byKey(UiKeys.loginPageAccountCard(toxId)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.byKey(_exportOptionKey),
          findsOneWidget,
          reason: 'Export option must render in the management sheet',
        );
        expect(
          find.byKey(_deleteOptionKey),
          findsOneWidget,
          reason: 'Delete option must render in the management sheet',
        );
        // The sheet title shows the account nickname.
        expect(find.text('Alice'), findsWidgets);
      },
    );

    testWidgets(
      'secondary-tap (desktop right-click) on a saved-account card opens the '
      'same sheet',
      (tester) async {
        const toxId =
            'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
        await initAccounts([
          {'toxId': toxId, 'nickname': 'Bob', 'statusMessage': ''},
        ]);
        await _pumpAndLoad(tester, _pumpableLoginPage());

        await _secondaryTap(
          tester,
          find.byKey(UiKeys.loginPageAccountCard(toxId)),
        );

        expect(
          find.byKey(_exportOptionKey),
          findsOneWidget,
          reason: 'Right-click must open the management sheet with Export',
        );
        expect(find.byKey(_deleteOptionKey), findsOneWidget);
      },
    );
  });

  group('LoginPage account export', () {
    testWidgets(
      'tapping Export invokes the export handler for THAT account and shows the '
      'success SnackBar with the returned path',
      (tester) async {
        const toxId =
            'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
        String? exportedToxId;
        await initAccounts([
          {'toxId': toxId, 'nickname': 'Carol', 'statusMessage': ''},
        ]);
        await _pumpAndLoad(
          tester,
          _pumpableLoginPage(
            exportAccount: ({required String toxId, String? password}) async {
              exportedToxId = toxId;
              return '/tmp/Carol_${toxId.substring(0, 8)}.tox';
            },
          ),
        );

        await tester.longPress(find.byKey(UiKeys.loginPageAccountCard(toxId)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        await tester.tap(find.byKey(_exportOptionKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        // The production handler invoked the export seam with the row's toxId.
        expect(
          exportedToxId,
          toxId,
          reason:
              'Export must call the export handler with the selected account '
              'toxId',
        );
        // And surfaced the success SnackBar carrying the returned file path.
        expect(
          find.textContaining('exported successfully'),
          findsOneWidget,
          reason: 'Export success must surface the success SnackBar',
        );
        expect(
          find.textContaining('Carol_${toxId.substring(0, 8)}.tox'),
          findsOneWidget,
          reason: 'The SnackBar must echo the path the handler returned',
        );
      },
    );

    testWidgets(
      'an export FAILURE surfaces the failure SnackBar (handler still ran)',
      (tester) async {
        const toxId =
            'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD';
        var invoked = false;
        await initAccounts([
          {'toxId': toxId, 'nickname': 'Dave', 'statusMessage': ''},
        ]);
        await _pumpAndLoad(
          tester,
          _pumpableLoginPage(
            exportAccount: ({required String toxId, String? password}) async {
              invoked = true;
              throw Exception('disk full');
            },
          ),
        );

        await tester.longPress(find.byKey(UiKeys.loginPageAccountCard(toxId)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(_exportOptionKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          invoked,
          isTrue,
          reason: 'The production export handler must have run',
        );
        expect(
          find.textContaining(RegExp('Failed to export', caseSensitive: false)),
          findsOneWidget,
          reason: 'A throwing export must surface the failure SnackBar',
        );
      },
    );

    testWidgets(
      'mobile export keeps the internal copy and saves bytes through the picker',
      (tester) async {
        const toxId =
            '1212121212121212121212121212121212121212121212121212121212121212';
        final internalFile = File(
          '${Directory.systemTemp.path}/login_mobile_export_${DateTime.now().microsecondsSinceEpoch}.tox',
        );
        addTearDown(() {
          if (internalFile.existsSync()) internalFile.deleteSync();
        });
        Uint8List? savedBytes;
        String? seenFileName;
        await initAccounts([
          {'toxId': toxId, 'nickname': 'Mobile Alice', 'statusMessage': ''},
        ]);
        await _pumpAndLoad(
          tester,
          _pumpableLoginPage(
            isDesktopExportPlatformOverride: false,
            exportAccount: ({required String toxId, String? password}) async {
              internalFile.writeAsBytesSync(const <int>[6, 7, 8]);
              return internalFile.path;
            },
            mobileExportSaveFile:
                ({
                  required String dialogTitle,
                  required String fileName,
                  required Uint8List bytes,
                }) async {
                  seenFileName = fileName;
                  savedBytes = bytes;
                  return '/user-visible/$fileName';
                },
            saveMobileExportCopyOverride:
                ({
                  required internalFilePath,
                  required dialogTitle,
                  required fileName,
                  required saveFile,
                }) async {
                  final bytes = File(internalFilePath).readAsBytesSync();
                  final userSelectedPath = await saveFile(
                    dialogTitle: dialogTitle,
                    fileName: fileName,
                    bytes: bytes,
                  );
                  return MobileExportSaveResult(
                    disposition: userSelectedPath == null
                        ? MobileExportSaveDisposition.cancelled
                        : MobileExportSaveDisposition.exported,
                    internalFilePath: internalFilePath,
                    userSelectedPath: userSelectedPath,
                  );
                },
          ),
        );

        await tester.longPress(find.byKey(UiKeys.loginPageAccountCard(toxId)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(_exportOptionKey));
        for (var i = 0; i < 20 && seenFileName == null; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(seenFileName, 'Mobile Alice_12121212.tox');
        expect(savedBytes, Uint8List.fromList(const <int>[6, 7, 8]));
        expect(internalFile.existsSync(), isTrue);
        expect(find.textContaining('/user-visible/'), findsOneWidget);
      },
    );
  });

  group('LoginPage account delete — no-password (confirm word)', () {
    testWidgets(
      'opening Delete shows the confirm dialog with the required word from the '
      'production copy',
      (tester) async {
        const toxId =
            'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE';
        await initAccounts([
          {'toxId': toxId, 'nickname': 'Eve', 'statusMessage': ''},
        ]);
        await _pumpAndLoad(tester, _pumpableLoginPage());

        await tester.longPress(find.byKey(UiKeys.loginPageAccountCard(toxId)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(_deleteOptionKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.byKey(_deleteConfirmInputKey),
          findsOneWidget,
          reason: 'No-password account must show the confirm-word input',
        );
        // The dialog copy embeds the required word ("delete") via
        // deleteAccountConfirmWordPrompt('delete').
        expect(
          find.textContaining('delete'),
          findsWidgets,
          reason: 'The confirm-word prompt must name the required word',
        );
      },
    );

    testWidgets(
      'a WRONG confirm word is rejected; the account stays in the list',
      (tester) async {
        const toxId =
            'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';
        await initAccounts([
          {'toxId': toxId, 'nickname': 'Frank', 'statusMessage': ''},
        ]);
        await _pumpAndLoad(tester, _pumpableLoginPage());
        await tester.longPress(find.byKey(UiKeys.loginPageAccountCard(toxId)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(_deleteOptionKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        await tester.enterText(find.byKey(_deleteConfirmInputKey), 'nope');
        await tester.pump();
        await tester.tap(find.byKey(_deleteConfirmButtonKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        // Wrong word -> error SnackBar, dialog stays open, account not removed.
        expect(
          find.byType(AlertDialog),
          findsOneWidget,
          reason: 'A wrong word must keep the confirm dialog open',
        );
        expect(
          await Prefs.getAccountByToxId(toxId),
          isNotNull,
          reason: 'A wrong confirm word must NOT delete the account',
        );
      },
    );

    testWidgets(
      'the CORRECT confirm word deletes the account and removes it from the list',
      (tester) async {
        const toxId =
            '1111111111111111111111111111111111111111111111111111111111111111';
        await initAccounts([
          {'toxId': toxId, 'nickname': 'Grace', 'statusMessage': ''},
        ]);
        await _pumpAndLoad(tester, _pumpableLoginPage());
        // Precondition: the row is present.
        expect(find.byKey(UiKeys.loginPageAccountCard(toxId)), findsOneWidget);

        await tester.longPress(find.byKey(UiKeys.loginPageAccountCard(toxId)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(_deleteOptionKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        await tester.enterText(find.byKey(_deleteConfirmInputKey), 'delete');
        await tester.pump();
        // deleteAccountWithoutService awaits SharedPreferences + path_provider
        // channels and then _loadAccountList rebuilds — drive the real event
        // loop until the card is gone so all those async hops complete.
        await _tapAndAwait(
          tester,
          trigger: find.byKey(_deleteConfirmButtonKey),
          isDone: () =>
              find.byKey(UiKeys.loginPageAccountCard(toxId)).evaluate().isEmpty,
        );

        // The production deleteAccountWithoutService ran -> account gone from
        // Prefs and the card removed from the rebuilt list.
        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason: 'A correct word must dismiss the dialog',
        );
        expect(
          await Prefs.getAccountByToxId(toxId),
          isNull,
          reason: 'The correct confirm word must delete the account',
        );
        expect(
          find.byKey(UiKeys.loginPageAccountCard(toxId)),
          findsNothing,
          reason: 'The deleted account card must disappear from the list',
        );
      },
    );
  });

  group('LoginPage account delete — password-protected', () {
    testWidgets('a WRONG password is rejected; the account stays in the list', (
      tester,
    ) async {
      const toxId =
          '2222222222222222222222222222222222222222222222222222222222222222';
      await initAccounts([
        {'toxId': toxId, 'nickname': 'Heidi', 'statusMessage': ''},
      ]);
      // Seed a real password (PBKDF2) on the real event loop.
      await tester.runAsync(() async {
        final ok = await Prefs.setAccountPassword(toxId, 'correct-pw');
        expect(ok, isTrue);
      });
      await _pumpAndLoad(tester, _pumpableLoginPage());

      await tester.longPress(find.byKey(UiKeys.loginPageAccountCard(toxId)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      // Delete -> _confirmDeleteAccountFromLoginPage first awaits
      // hasAccountPassword; run that open inside runAsync.
      await _tapAndAwait(
        tester,
        trigger: find.byKey(_deleteOptionKey),
        isDone: () => find.byType(AlertDialog).evaluate().isNotEmpty,
      );

      // Password-protected branch shows the password input (obscured).
      final input = find.byKey(_deleteConfirmInputKey);
      expect(input, findsOneWidget);
      expect(
        tester.widget<TextField>(input).obscureText,
        isTrue,
        reason: 'Password-delete branch must obscure the input',
      );

      await tester.enterText(input, 'wrong-pw');
      await tester.pump();
      await _tapAndAwait(
        tester,
        trigger: find.byKey(_deleteConfirmButtonKey),
        // Done when the error SnackBar is up (dialog stays open).
        isDone: () => find
            .textContaining(RegExp('Invalid password', caseSensitive: false))
            .evaluate()
            .isNotEmpty,
      );

      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: 'A wrong password must keep the confirm dialog open',
      );
      expect(
        await Prefs.getAccountByToxId(toxId),
        isNotNull,
        reason: 'A wrong password must NOT delete the account',
      );
    });

    testWidgets(
      'the CORRECT password deletes the account and removes it from the list',
      (tester) async {
        const toxId =
            '3333333333333333333333333333333333333333333333333333333333333333';
        await initAccounts([
          {'toxId': toxId, 'nickname': 'Ivan', 'statusMessage': ''},
        ]);
        await tester.runAsync(() async {
          final ok = await Prefs.setAccountPassword(toxId, 'correct-pw');
          expect(ok, isTrue);
        });
        await _pumpAndLoad(tester, _pumpableLoginPage());

        await tester.longPress(find.byKey(UiKeys.loginPageAccountCard(toxId)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await _tapAndAwait(
          tester,
          trigger: find.byKey(_deleteOptionKey),
          isDone: () => find.byType(AlertDialog).evaluate().isNotEmpty,
        );

        await tester.enterText(
          find.byKey(_deleteConfirmInputKey),
          'correct-pw',
        );
        await tester.pump();
        await _tapAndAwait(
          tester,
          trigger: find.byKey(_deleteConfirmButtonKey),
          isDone: () => find.byType(AlertDialog).evaluate().isEmpty,
        );

        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason: 'A correct password must dismiss the dialog',
        );
        expect(
          await Prefs.getAccountByToxId(toxId),
          isNull,
          reason: 'The correct password must delete the account',
        );
        expect(
          find.byKey(UiKeys.loginPageAccountCard(toxId)),
          findsNothing,
          reason: 'The deleted account card must disappear from the list',
        );
      },
    );
  });
}

// Needed for the path_provider temp-dir mock.
