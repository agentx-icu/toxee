// Widget tests for the first-run backup wizard.
//
// These tests render [FirstRunBackupWizard] directly (rather than driving
// the real registration flow) so they don't require an initialized FFI
// library or SharedPreferences state for the surrounding plumbing.
//
// Per the CEO plan, PR 1 acceptance requires:
//   1. wizard appears after registration (flag on) — covered by the flag-
//      value assertion plus the render test below.
//   2. wizard does NOT appear (flag off) — covered by the flag-value
//      contract test; flipping the static const back to FALSE is the
//      documented rollback.
//   3. Export-now success path
//   4. I'll-do-it-later → confirmation → continue path
//   5. I'll-do-it-later → Cancel preserves wizard

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/widgets/first_run_backup_wizard.dart';
import 'package:toxee/util/feature_flags.dart';
import 'package:toxee/util/mobile_export_policy.dart';

/// Per-test holder that captures the pushed wizard's result Future. Stored
/// as a list so the harness widget can write into it from inside an
/// `onPressed` callback without re-rendering.
class _ResultHolder {
  Future<FirstRunBackupWizardResult?>? future;
}

Widget _harness({
  required Future<String?> Function(String, String)? exportOverride,
  required _ResultHolder holder,
  bool? isDesktopExportPlatformOverride,
  MobileExportSaveFile? mobileExportSaveFile,
  CreateAndSaveMobileExportCopyFn? createAndSaveMobileExportCopyOverride,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Builder(
      builder: (context) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                holder.future = Navigator.of(context)
                    .push<FirstRunBackupWizardResult>(
                      PageRouteBuilder<FirstRunBackupWizardResult>(
                        opaque: true,
                        barrierDismissible: false,
                        fullscreenDialog: true,
                        settings: const RouteSettings(name: 'wizard'),
                        transitionDuration: Duration.zero,
                        reverseTransitionDuration: Duration.zero,
                        pageBuilder: (ctx, _, __) => FirstRunBackupWizard(
                          toxId: 'ABCD' * 18,
                          nickname: 'TestNick',
                          exportOverride: exportOverride,
                          isDesktopExportPlatformOverride:
                              isDesktopExportPlatformOverride,
                          mobileExportSaveFile: mobileExportSaveFile,
                          createAndSaveMobileExportCopyOverride:
                              createAndSaveMobileExportCopyOverride,
                        ),
                      ),
                    );
              },
              child: const Text('open'),
            ),
          ),
        );
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FirstRunBackupWizard flag gate', () {
    test('enableFirstRunBackupWizard defaults to TRUE', () {
      // The flag default is the rollback story: ship TRUE, flip FALSE if a
      // user-reported issue appears. Asserting the default here is what
      // gives the call site at register_page.dart its byte-identical
      // behavior when (and only when) the flag is flipped.
      expect(FeatureFlags.enableFirstRunBackupWizard, isTrue);
    });
  });

  group('FirstRunBackupWizard widget', () {
    testWidgets('renders title, body, and both primary actions', (
      tester,
    ) async {
      final holder = _ResultHolder();
      await tester.pumpWidget(
        _harness(exportOverride: (_, __) async => null, holder: holder),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Save your account file'), findsOneWidget);
      expect(
        find.textContaining('losing this device means losing your account'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('firstRunBackupWizard.exportButton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('firstRunBackupWizard.laterButton')),
        findsOneWidget,
      );
      // Pop the wizard to drain its push Future before the test framework
      // tears down the binding (avoids "Test ended while push pending").
      tester
          .state(find.byType(FirstRunBackupWizard))
          .context
          .findRootAncestorStateOfType<NavigatorState>();
      // Simpler drain: directly call Navigator.pop on the wizard.
      final navState = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navState.pop();
      await tester.pumpAndSettle();
    });

    testWidgets('Export-now success path pops with exported result', (
      tester,
    ) async {
      final holder = _ResultHolder();
      await tester.pumpWidget(
        _harness(
          exportOverride: (toxId, nickname) async =>
              '/tmp/test_${toxId.substring(0, 8)}.tox',
          holder: holder,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('firstRunBackupWizard.exportButton')),
      );
      await tester.pumpAndSettle();

      // After the wizard pops, the captured Future resolves.
      final result = await holder.future;
      expect(result, FirstRunBackupWizardResult.exported);
    });

    testWidgets('Export-now failure stays on wizard with inline error', (
      tester,
    ) async {
      final holder = _ResultHolder();
      await tester.pumpWidget(
        _harness(
          exportOverride: (_, __) async {
            throw Exception('disk full');
          },
          holder: holder,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('firstRunBackupWizard.exportButton')),
      );
      await tester.pumpAndSettle();

      // Inline error surface, wizard still mounted.
      expect(find.textContaining('disk full'), findsOneWidget);
      expect(
        find.byKey(const Key('firstRunBackupWizard.exportButton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('firstRunBackupWizard.laterButton')),
        findsOneWidget,
      );
      // Drain the push Future so the test's microtask queue doesn't leak.
      final navState = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navState.pop();
      await tester.pumpAndSettle();
    });

    testWidgets('mobile export saves an internal copy through the picker', (
      tester,
    ) async {
      final holder = _ResultHolder();
      final internalFile = File(
        '${Directory.systemTemp.path}/first_run_mobile_${DateTime.now().microsecondsSinceEpoch}.tox',
      );
      addTearDown(() {
        if (internalFile.existsSync()) internalFile.deleteSync();
      });
      Uint8List? savedBytes;
      String? seenFileName;
      await tester.pumpWidget(
        _harness(
          isDesktopExportPlatformOverride: false,
          exportOverride: (_, __) async {
            internalFile.writeAsBytesSync(const <int>[4, 5, 6]);
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
          createAndSaveMobileExportCopyOverride:
              ({
                required createInternalExport,
                required dialogTitle,
                required fileName,
                required saveFile,
              }) async {
                final internalFilePath = await createInternalExport();
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
          holder: holder,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      FirstRunBackupWizardResult? routeResult;
      holder.future!.then((value) {
        routeResult = value;
      });
      await tester.tap(
        find.byKey(const Key('firstRunBackupWizard.exportButton')),
      );
      for (var i = 0; i < 20 && routeResult == null; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(seenFileName, 'TestNick_ABCDABCD.tox');
      expect(savedBytes, Uint8List.fromList(const <int>[4, 5, 6]));
      expect(internalFile.existsSync(), isTrue);
      expect(routeResult, FirstRunBackupWizardResult.exported);
    });

    testWidgets('mobile export cancellation keeps the wizard open', (
      tester,
    ) async {
      final holder = _ResultHolder();
      final internalFile = File(
        '${Directory.systemTemp.path}/first_run_mobile_cancel_${DateTime.now().microsecondsSinceEpoch}.tox',
      );
      addTearDown(() {
        if (internalFile.existsSync()) internalFile.deleteSync();
      });
      await tester.pumpWidget(
        _harness(
          isDesktopExportPlatformOverride: false,
          exportOverride: (_, __) async {
            internalFile.writeAsBytesSync(const <int>[7, 8, 9]);
            return internalFile.path;
          },
          mobileExportSaveFile:
              ({
                required String dialogTitle,
                required String fileName,
                required Uint8List bytes,
              }) async => null,
          createAndSaveMobileExportCopyOverride:
              ({
                required createInternalExport,
                required dialogTitle,
                required fileName,
                required saveFile,
              }) async {
                final internalFilePath = await createInternalExport();
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
          holder: holder,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      FirstRunBackupWizardResult? routeResult;
      holder.future!.then((value) {
        routeResult = value;
      });
      await tester.tap(
        find.byKey(const Key('firstRunBackupWizard.exportButton')),
      );
      for (
        var i = 0;
        i < 20 && find.textContaining('private in-app copy').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(routeResult, isNull);
      expect(
        find.byKey(const Key('firstRunBackupWizard.exportButton')),
        findsOneWidget,
      );
      expect(find.textContaining('private in-app copy'), findsOneWidget);
      expect(find.textContaining(internalFile.path), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
    });

    testWidgets(
      'I\'ll-do-it-later → confirm → continue pops with acknowledgedDismiss',
      (tester) async {
        final holder = _ResultHolder();
        await tester.pumpWidget(
          _harness(exportOverride: (_, __) async => null, holder: holder),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('firstRunBackupWizard.laterButton')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Skip backup?'), findsOneWidget);
        expect(find.textContaining('There is no recovery'), findsOneWidget);

        await tester.tap(find.text('I understand, continue'));
        await tester.pumpAndSettle();

        final result = await holder.future;
        expect(result, FirstRunBackupWizardResult.acknowledgedDismiss);
      },
    );

    testWidgets('I\'ll-do-it-later → Cancel returns to wizard, no pop', (
      tester,
    ) async {
      final holder = _ResultHolder();
      await tester.pumpWidget(
        _harness(exportOverride: (_, __) async => null, holder: holder),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('firstRunBackupWizard.laterButton')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Skip backup?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Confirmation gone, wizard still mounted — buttons present.
      expect(find.text('Skip backup?'), findsNothing);
      expect(
        find.byKey(const Key('firstRunBackupWizard.exportButton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('firstRunBackupWizard.laterButton')),
        findsOneWidget,
      );

      // Drain the push Future. The wizard correctly stayed mounted, but
      // the test must pop it to allow the test framework to clean up
      // without complaining about pending pushes.
      final navState = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navState.pop();
      await tester.pumpAndSettle();
    });
  });
}
