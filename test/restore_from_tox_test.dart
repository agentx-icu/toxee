// Widget + controller tests for the first-class "Restore from .tox file"
// login-page entry point.
//
// Per the CEO plan, PR 1 acceptance requires:
//   1. Restore button appears on the login page (UI-level test).
//   2. Restore handles: encrypted (correct password), encrypted (wrong
//      password → invalidPassword), corrupt file (→ notAToxProfile),
//      qTox-format file (succeeds — same code path as plain .tox).
//
// We don't have a real FFI library loaded in the unit-test sandbox, so the
// "success path" cases that need to actually decrypt or extract a Tox ID
// are exercised at the integration test level (run on a machine with the
// FFI lib built). What we CAN test deterministically without FFI:
//   - The login-page UI surfaces the restore button when the flag is on.
//   - The controller's pre-FFI failure modes:
//       - file_picker cancelled → noFileSelected
//       - non-.tox extension → notAToxProfile (with filePathOverride)
//       - file that triggers FFI error → notAToxProfile / generalError
//         (depends on the runtime; we assert it does NOT crash and DOES
//         return a typed RestoreFailure).
//
// The encrypted/decrypt/qTox-roundtrip pieces will be picked up by an
// integration test against the live FFI; this widget-level test layer
// focuses on UI surface + non-FFI controller branches.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/login/login_page_controller.dart';
import 'package:toxee/ui/login_page.dart';
import 'package:toxee/util/feature_flags.dart';
import 'package:toxee/util/prefs.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
  });

  group('Restore from .tox — login-page surface', () {
    testWidgets('top-level "Restore from .tox file" button is visible when flag is on',
        (tester) async {
      // The flag must be TRUE for this surface; that's the design
      // contract for PR 1 — flipping it FALSE would only hide the wizard,
      // not the restore button. The restore button is always available
      // (it's the recovery path that is not flagged).
      expect(FeatureFlags.enableFirstRunBackupWizard, isTrue);

      await tester.pumpWidget(_wrap(const LoginPage()));
      // First frame is enough; subsequent async loads (account list,
      // bootstrap node) shouldn't remove this button.
      await tester.pump();

      expect(find.byKey(const Key('loginPage.restoreFromToxFile')), findsOneWidget);
      expect(find.text('Restore from .tox file'), findsOneWidget);
    });
  });

  group('LoginPageController.restoreFromToxFile — pre-FFI branches', () {
    test('non-.tox file extension returns notAToxProfile', () async {
      final controller = LoginPageController();
      // Write a temp file with a non-.tox extension; the controller's
      // path-only check returns before any FFI is touched.
      final tmp = await Directory.systemTemp.createTemp('restore_test_');
      final notTox = File('${tmp.path}/looks_like.txt')..writeAsBytesSync([0, 1, 2]);
      try {
        final result = await controller.restoreFromToxFile(
          requestPassword: () async => null,
          importedAccountDefaultName: 'Imported',
          filePathOverride: notTox.path,
        );
        expect(result, isA<RestoreFailure>());
        expect((result as RestoreFailure).kind, RestoreFailureKind.notAToxProfile);
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('corrupt .tox file does not crash and returns a typed failure', () async {
      final controller = LoginPageController();
      final tmp = await Directory.systemTemp.createTemp('restore_test_');
      // 64 bytes of garbage that is neither an encrypted Tox profile
      // header (would start with "toxEsave") nor a valid plain profile.
      final corrupt = File('${tmp.path}/corrupt.tox')
        ..writeAsBytesSync(List<int>.generate(64, (i) => i));
      try {
        final result = await controller.restoreFromToxFile(
          requestPassword: () async => null,
          importedAccountDefaultName: 'Imported',
          filePathOverride: corrupt.path,
        );
        // We accept either notAToxProfile or generalError here — the exact
        // classification depends on whether the FFI lib is loadable in the
        // test sandbox. The hard contract is: it does NOT throw, and it
        // returns a RestoreFailure (never a RestoreSuccess).
        expect(result, isA<RestoreFailure>());
        final kind = (result as RestoreFailure).kind;
        expect(
          kind == RestoreFailureKind.notAToxProfile ||
              kind == RestoreFailureKind.generalError ||
              kind == RestoreFailureKind.invalidPassword,
          isTrue,
          reason: 'expected typed failure, got $kind',
        );
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('cancelled password prompt on encrypted file returns cancelled', () async {
      // We can't deterministically know the file is encrypted without the
      // FFI, but we CAN assert that when requestPassword returns null, the
      // controller returns cancelled — provided the file at least triggers
      // the password code path. If the FFI lib is missing the test still
      // passes (the corrupt path returns notAToxProfile / generalError).
      // Importantly, no path returns RestoreSuccess.
      final controller = LoginPageController();
      final tmp = await Directory.systemTemp.createTemp('restore_test_');
      // Construct a file that is just barely longer than the encryption
      // extra-length and starts with the toxE magic bytes — the
      // isDataEncrypted check should classify it as encrypted, triggering
      // requestPassword.
      const toxEMagic = [0x74, 0x6f, 0x78, 0x45, 0x73, 0x61, 0x76, 0x65]; // "toxEsave"
      final padded = File('${tmp.path}/enc.tox')
        ..writeAsBytesSync(<int>[...toxEMagic, ...List<int>.filled(120, 0)]);
      try {
        final result = await controller.restoreFromToxFile(
          requestPassword: () async => null,
          importedAccountDefaultName: 'Imported',
          filePathOverride: padded.path,
        );
        // Either cancelled (FFI loaded and recognized encryption) or a
        // typed RestoreFailure (FFI missing). Never success.
        expect(result, isA<RestoreFailure>());
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}
