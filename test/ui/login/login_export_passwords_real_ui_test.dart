// Real-UI gate for the login page's saved-account export (task A6): with no
// live session, a PROTECTED account is first unlocked with its ACCOUNT password
// (verified through the shared login gate), THEN the user picks a separate
// EXPORT password in a second dialog. The two are never conflated.
//
// Drives the PRODUCTION LoginPage → account-management sheet → Export →
// PasswordPromptDialog → ExportPasswordDialog. Most cases swap only the
// exporter for a recorder (`LoginPage.exportAccount`) to observe exactly which
// password went where; the last case keeps the DEFAULT binding (real
// AccountExportService + tim2tox FFI, skipped when the library is not loadable)
// against a profile that is ciphertext at rest under the account password,
// with NO session password cached — the configuration the old binding (export
// password passed as the account password) could not handle.
//
// Mobile parity: the export handler, both dialogs and the gate are shared
// Dart; only the save step forks (covered by
// login_account_management_real_ui_test.dart's mobile case).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/login_page.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/ui/testing/ui_keys_login.dart';
import 'package:toxee/ui/testing/ui_keys_settings.dart';
import 'package:toxee/util/account_export/encryption.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/logger.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/session_password_store.dart';

import '../../account_export/test_support.dart';
import '../../account_export/tox_profile_factory.dart';

const _exportOptionKey = Key('login_account_management_export_option');
const _accountFieldKey = Key('login_quick_password_field');
const _accountPassword = 'the account password';
const _exportPassword = 'a different export password';

final class _ExportCall {
  _ExportCall(this.toxId, this.password, this.accountPassword);
  final String toxId;
  final String? password;
  final String? accountPassword;
}

Widget _app({LoginExportAccountFn? exportAccount}) {
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
      isDesktopExportPlatformOverride: true,
    ),
  );
}

Future<void> _pumpLogin(WidgetTester tester, Widget root) async {
  await tester.binding.setSurfaceSize(const Size(1024, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(root);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Runs [action] then pumps the REAL event loop (PBKDF2, secure-storage and
/// file I/O hop it) until [isDone] or the budget runs out.
Future<void> _runUntil(
  WidgetTester tester,
  Future<void> Function() action,
  bool Function() isDone, {
  String what = 'condition',
}) async {
  var ok = false;
  await tester.runAsync(() async {
    await action();
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 50));
      if (isDone()) {
        ok = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
  if (!ok) fail('timed out waiting for $what');
  await tester.pump();
}

bool _present(Key key) => find.byKey(key).evaluate().isNotEmpty;

Future<void> _tapExport(WidgetTester tester, String toxId) async {
  await tester.longPress(find.byKey(UiKeys.loginPageAccountCard(toxId)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _fillExportPassword(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(SettingsUiKeys.exportPasswordField), value);
  await tester.enterText(
    find.byKey(SettingsUiKeys.exportPasswordConfirmField),
    value,
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final secureStore = <String, String>{};
  var secureStoreBroken = false;

  void installSecureStore() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (MethodCall call) async {
          if (secureStoreBroken) {
            throw PlatformException(code: 'unavailable');
          }
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
  }

  group('with a recording exporter', () {
    const toxId =
        'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE';
    late Directory root;
    late List<_ExportCall> calls;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('login_export_pw_');
      AppPaths.debugApplicationSupportOverride = root.path;
      AppLogger.resetForTesting();
      secureStore.clear();
      secureStoreBroken = false;
      installSecureStore();
      SharedPreferences.setMockInitialValues({
        'account_list': jsonEncode([
          {'toxId': toxId, 'nickname': 'Erin', 'statusMessage': ''},
        ]),
      });
      await Prefs.initialize(await SharedPreferences.getInstance());
      calls = [];
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureChannel, null);
      AppPaths.debugApplicationSupportOverride = null;
      AppLogger.resetForTesting();
      if (await root.exists()) await root.delete(recursive: true);
    });

    String outPath() => p.join(root.path, 'Erin.tox');

    Future<String> recorder({
      required String toxId,
      String? password,
      String? accountPassword,
    }) async {
      calls.add(_ExportCall(toxId, password, accountPassword));
      File(outPath()).writeAsStringSync('export');
      return outPath();
    }

    Future<void> protect(WidgetTester tester) async {
      await tester.runAsync(() async {
        expect(await Prefs.setAccountPassword(toxId, _accountPassword), isTrue);
      });
    }

    testWidgets(
      'protected: account password verified first, then a SEPARATE export '
      'password; each reaches its own parameter',
      (tester) async {
        await protect(tester);
        await _pumpLogin(tester, _app(exportAccount: recorder));
        await _tapExport(tester, toxId);
        await _runUntil(
          tester,
          () => tester.tap(find.byKey(_exportOptionKey)),
          () => _present(_accountFieldKey),
          what: 'account password prompt',
        );
        expect(
          find.text('Enter the account password of "Erin" to export it'),
          findsOneWidget,
        );
        expect(find.byKey(SettingsUiKeys.exportPasswordField), findsNothing);

        await tester.enterText(find.byKey(_accountFieldKey), _accountPassword);
        await _runUntil(
          tester,
          () => tester.tap(find.byKey(LoginUiKeys.passwordPromptOkButton)),
          () => _present(SettingsUiKeys.exportPasswordField),
          what: 'export password dialog',
        );
        expect(find.byKey(_accountFieldKey), findsNothing);
        expect(find.text('Choose an export password'), findsOneWidget);

        await _fillExportPassword(tester, _exportPassword);
        await _runUntil(
          tester,
          () => tester.tap(find.byKey(SettingsUiKeys.exportPasswordOkButton)),
          () => calls.isNotEmpty,
          what: 'export call',
        );
        expect(calls.single.toxId, toxId);
        expect(calls.single.accountPassword, _accountPassword);
        expect(calls.single.password, _exportPassword);
      },
    );

    testWidgets(
      'protected + empty export password: unlocks with the account password, '
      'exports unencrypted (never falls back to the account password)',
      (tester) async {
        await protect(tester);
        await _pumpLogin(tester, _app(exportAccount: recorder));
        await _tapExport(tester, toxId);
        await _runUntil(
          tester,
          () => tester.tap(find.byKey(_exportOptionKey)),
          () => _present(_accountFieldKey),
        );
        await tester.enterText(find.byKey(_accountFieldKey), _accountPassword);
        await _runUntil(
          tester,
          () => tester.tap(find.byKey(LoginUiKeys.passwordPromptOkButton)),
          () => _present(SettingsUiKeys.exportPasswordField),
        );
        expect(
          find.byKey(SettingsUiKeys.exportPasswordEmptyWarning),
          findsOneWidget,
        );
        await _runUntil(
          tester,
          () => tester.tap(find.byKey(SettingsUiKeys.exportPasswordOkButton)),
          () => calls.isNotEmpty,
        );
        expect(calls.single.accountPassword, _accountPassword);
        expect(calls.single.password, isNull);
      },
    );

    testWidgets(
      'WRONG account password: error, no export dialog, nothing written',
      (tester) async {
        await protect(tester);
        await _pumpLogin(tester, _app(exportAccount: recorder));
        await _tapExport(tester, toxId);
        await _runUntil(
          tester,
          () => tester.tap(find.byKey(_exportOptionKey)),
          () => _present(_accountFieldKey),
        );
        await tester.enterText(find.byKey(_accountFieldKey), 'wrong password');
        await _runUntil(
          tester,
          () => tester.tap(find.byKey(LoginUiKeys.passwordPromptOkButton)),
          () => find.text('Invalid password').evaluate().isNotEmpty,
          what: 'invalid password snackbar',
        );
        expect(find.byKey(SettingsUiKeys.exportPasswordField), findsNothing);
        expect(calls, isEmpty);
        expect(File(outPath()).existsSync(), isFalse);
      },
    );

    testWidgets('cancel at the account step exports nothing', (tester) async {
      await protect(tester);
      await _pumpLogin(tester, _app(exportAccount: recorder));
      await _tapExport(tester, toxId);
      await _runUntil(
        tester,
        () => tester.tap(find.byKey(_exportOptionKey)),
        () => _present(_accountFieldKey),
      );
      await _runUntil(
        tester,
        () => tester.tap(find.byKey(LoginUiKeys.passwordPromptCancelButton)),
        () => !_present(_accountFieldKey),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(SettingsUiKeys.exportPasswordField), findsNothing);
      expect(calls, isEmpty);
    });

    testWidgets('cancel at the export step exports nothing', (tester) async {
      await protect(tester);
      await _pumpLogin(tester, _app(exportAccount: recorder));
      await _tapExport(tester, toxId);
      await _runUntil(
        tester,
        () => tester.tap(find.byKey(_exportOptionKey)),
        () => _present(_accountFieldKey),
      );
      await tester.enterText(find.byKey(_accountFieldKey), _accountPassword);
      await _runUntil(
        tester,
        () => tester.tap(find.byKey(LoginUiKeys.passwordPromptOkButton)),
        () => _present(SettingsUiKeys.exportPasswordField),
      );
      await tester.tap(find.byKey(SettingsUiKeys.exportPasswordCancelButton));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(SettingsUiKeys.exportPasswordField), findsNothing);
      expect(calls, isEmpty);
      expect(File(outPath()).existsSync(), isFalse);
    });

    testWidgets(
      'unprotected: no account prompt, straight to the export password',
      (tester) async {
        await _pumpLogin(tester, _app(exportAccount: recorder));
        await _tapExport(tester, toxId);
        await _runUntil(
          tester,
          () => tester.tap(find.byKey(_exportOptionKey)),
          () => _present(SettingsUiKeys.exportPasswordField),
        );
        expect(find.byKey(_accountFieldKey), findsNothing);
        await _fillExportPassword(tester, _exportPassword);
        await _runUntil(
          tester,
          () => tester.tap(find.byKey(SettingsUiKeys.exportPasswordOkButton)),
          () => calls.isNotEmpty,
        );
        expect(calls.single.accountPassword, isNull);
        expect(calls.single.password, _exportPassword);
      },
    );

    testWidgets(
      'unreadable secure store: named error, no prompt, nothing exported',
      (tester) async {
        await protect(tester);
        secureStoreBroken = true;
        await _pumpLogin(tester, _app(exportAccount: recorder));
        await _tapExport(tester, toxId);
        await _runUntil(
          tester,
          () => tester.tap(find.byKey(_exportOptionKey)),
          () => find.byType(SnackBar).evaluate().isNotEmpty,
          what: 'secure storage error snackbar',
        );
        expect(find.textContaining('Secure storage is unavailable'), findsOne);
        expect(find.text('Invalid password'), findsNothing);
        expect(find.byKey(_accountFieldKey), findsNothing);
        expect(find.byKey(SettingsUiKeys.exportPasswordField), findsNothing);
        expect(calls, isEmpty);
      },
    );
  });

  group('default binding (real exporter, FFI)', () {
    bool ffiAvailable() {
      try {
        Tim2ToxFfi.open();
        return true;
      } catch (_) {
        return false;
      }
    }

    final skip = ffiAvailable()
        ? null
        : 'tim2tox FFI library not loadable in this environment';

    late AccountExportTestEnv env;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
      AppLogger.resetForTesting();
      secureStore.clear();
      secureStoreBroken = false;
      installSecureStore();
      SessionPasswordStore.clear();
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureChannel, null);
      SessionPasswordStore.clear();
      AppLogger.resetForTesting();
      await env.dispose();
    });

    testWidgets(
      'ciphertext-at-rest profile, no session: the file is sealed with the '
      'EXPORT password and does not open with the account password',
      (tester) async {
        late ToxProfileFixture fixture;
        await tester.runAsync(() async {
          fixture = ToxProfileFixture.create()!;
          await Prefs.addAccount(toxId: fixture.toxId, nickname: 'Frank');
          expect(
            await Prefs.setAccountPassword(fixture.toxId, _accountPassword),
            isTrue,
          );
          final dir = await AppPaths.getProfileDirectoryForToxId(fixture.toxId);
          await Directory(dir).create(recursive: true);
          await File(
            AppPaths.profileFileInDirectory(dir),
          ).writeAsBytes(passEncrypt(fixture.savedata, _accountPassword));
        });
        Iterable<File> exported() => Directory(
          env.downloads,
        ).listSync().whereType<File>().where((f) => f.path.endsWith('.tox'));

        await _pumpLogin(tester, _app());
        await _tapExport(tester, fixture.toxId);
        await _runUntil(
          tester,
          () => tester.tap(find.byKey(_exportOptionKey)),
          () => _present(_accountFieldKey),
        );
        await tester.enterText(find.byKey(_accountFieldKey), _accountPassword);
        await _runUntil(
          tester,
          () => tester.tap(find.byKey(LoginUiKeys.passwordPromptOkButton)),
          () => _present(SettingsUiKeys.exportPasswordField),
        );
        await _fillExportPassword(tester, _exportPassword);
        await _runUntil(
          tester,
          () => tester.tap(find.byKey(SettingsUiKeys.exportPasswordOkButton)),
          () => exported().isNotEmpty,
          what: 'exported .tox in downloads',
        );

        final bytes = exported().single.readAsBytesSync();
        expect(isDataEncrypted(bytes), isTrue);
        expect(passDecrypt(bytes, _exportPassword), fixture.savedata);
        expect(() => passDecrypt(bytes, _accountPassword), throwsA(anything));
      },
      skip: skip != null,
    );
  });
}
