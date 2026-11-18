// S91 — Pairing host/client pages, L1 real-UI loopback gate.
//
// This mounts the real host and client pages side-by-side, reads the real QR
// URL from QrImageView, pastes it into the client page, confirms the same SAS
// on both pages, and checks delivery and durable account restoration. Loopback
// and a supplied host export allow both halves to run in one widget test.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/pairing/pairing_client_page.dart';
import 'package:toxee/ui/pairing/pairing_host_page.dart';
import 'package:toxee/ui/testing/ui_keys_login.dart';
import 'package:toxee/util/account_export/encryption.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/session_password_store.dart';

import '../../account_export/test_support.dart';
import '../../account_export/tox_profile_factory.dart';

Widget _harness({
  Future<Uint8List> Function()? exportBlob,
  Future<String> Function(Uint8List)? materialize,
  String hostToxId = 'tox-host-id',
  VoidCallback? saveHostProfile,
  bool pushPairingRoute = false,
}) {
  final pairing = Row(
    children: [
      Expanded(
        child: PairingHostPage(
          toxId: hostToxId,
          lanAddressForTest: '127.0.0.1',
          exportServiceForTest: exportBlob == null
              ? null
              : () async => Uint8List.fromList(await exportBlob()),
          saveLiveProfile: saveHostProfile,
        ),
      ),
      Expanded(
        child: PairingClientPage(materializeProfileForTest: materialize),
      ),
    ],
  );
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: pushPairingRoute
        ? Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push<bool>(
                    PageRouteBuilder(
                      pageBuilder: (_, _, _) => pairing,
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                  ),
                  child: const Text('Open pairing'),
                ),
              ),
            ),
          )
        : pairing,
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  final visibleText = find
      .byType(Text, skipOffstage: false)
      .evaluate()
      .map((e) => e.widget as Text)
      .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '<rich text>')
      .toList();
  fail('Timed out waiting for $finder. Visible text: $visibleText');
}

Future<void> _pumpUntilCount(
  WidgetTester tester,
  Finder finder,
  int count, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
    if (finder.evaluate().length == count) return;
  }
  final visibleText = find
      .byType(Text, skipOffstage: false)
      .evaluate()
      .map((e) => e.widget as Text)
      .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '<rich text>')
      .toList();
  fail(
    'Timed out waiting for $count matches for $finder. '
    'Saw ${finder.evaluate().length}. Visible text: $visibleText',
  );
}

Future<void> _confirmPairing(WidgetTester tester) async {
  await _pumpUntil(tester, find.byType(QrImageView));
  final qr = tester.widget<QrImageView>(find.byType(QrImageView));
  final qrKey = qr.key as ValueKey<String>;
  final qrUrl = qrKey.value.substring('pairing_qr_url:'.length);
  expect(qrUrl, startsWith('tox://pair?'));

  await tester.enterText(find.byType(TextField), qrUrl);
  await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
  await tester.pump();
  expect(find.text('Account received. You\'re paired.'), findsNothing);

  final confirm = find.widgetWithText(FilledButton, 'The codes match');
  await _pumpUntilCount(tester, confirm, 2);
  await tester.tap(confirm.first);
  await tester.pump();
  await tester.tap(confirm.last);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'S91 host/client QR + SAS confirmation transfers the profile blob',
    (tester) async => tester.runAsync(() async {
      tester.view.physicalSize = const Size(1200, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final exported = Uint8List.fromList([1, 2, 3, 5, 8, 13]);
      Uint8List? received;

      await tester.pumpWidget(
        _harness(
          exportBlob: () async => exported,
          materialize: (bytes) async {
            received = Uint8List.fromList(bytes);
            return 'tox-client-id';
          },
        ),
      );

      await _confirmPairing(tester);

      await _pumpUntil(
        tester,
        find.text('Account received. You\'re paired.'),
        timeout: const Duration(seconds: 8),
      );

      expect(
        received,
        exported,
        reason: 'client materializer must receive the decrypted host profile',
      );
      expect(
        find.text(
          'Account sent. Check the receiving device to confirm the import.',
        ),
        findsOneWidget,
      );
    }),
  );

  testWidgets(
    'production pairing sends a protected profile without a plaintext file',
    (tester) async => tester.runAsync(() async {
      final fixture = ToxProfileFixture.create();
      if (fixture == null) {
        markTestSkipped('tim2tox FFI library not loadable');
        return;
      }
      final env = await setUpAccountExportTestEnv();
      addTearDown(env.dispose);
      tester.view.physicalSize = const Size(1200, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final password = SecretPassword.fromString('host-at-rest');
      addTearDown(password.dispose);
      SessionPasswordStore.set(fixture.toxId, password);
      addTearDown(() => SessionPasswordStore.clear(fixture.toxId));
      final profileDir = await AppPaths.getProfileDirectoryForToxId(
        fixture.toxId,
      );
      await Directory(profileDir).create(recursive: true);
      final profile = File(AppPaths.profileFileInDirectory(profileDir));
      final encrypted = passEncrypt(fixture.savedata, password);
      var checkpointCount = 0;

      Uint8List? received;
      await tester.pumpWidget(
        _harness(
          hostToxId: fixture.toxId,
          saveHostProfile: () {
            checkpointCount++;
            profile.writeAsBytesSync(encrypted, flush: true);
          },
          materialize: (bytes) async {
            received = Uint8List.fromList(bytes);
            return fixture.toxId;
          },
        ),
      );
      await _confirmPairing(tester);
      await _pumpUntil(tester, find.text('Account received. You\'re paired.'));

      expect(checkpointCount, 1);
      expect(received, fixture.savedata);
      expect(await profile.readAsBytes(), encrypted);
      expect(await Directory('${env.root.path}/temp').exists(), isFalse);
    }),
  );

  testWidgets(
    'back and SAS controls cannot abandon a committing profile import',
    (tester) async => tester.runAsync(() async {
      tester.view.physicalSize = const Size(1200, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final importStarted = Completer<void>();
      final finishImport = Completer<String>();
      addTearDown(() {
        if (!finishImport.isCompleted) finishImport.complete('tox-client-id');
      });
      await tester.pumpWidget(
        _harness(
          pushPairingRoute: true,
          exportBlob: () async => Uint8List.fromList([1, 2, 3]),
          materialize: (_) {
            importStarted.complete();
            return finishImport.future;
          },
        ),
      );
      await tester.tap(find.text('Open pairing'));
      await tester.pump(const Duration(milliseconds: 400));
      await _confirmPairing(tester);
      await importStarted.future.timeout(const Duration(seconds: 5));
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      final receiver = find.byType(PairingClientPage);
      expect(receiver, findsOneWidget);
      Finder receiverButton(Finder child) =>
          find.descendant(of: receiver, matching: child);
      expect(
        tester
            .widget<FilledButton>(
              receiverButton(
                find.widgetWithText(FilledButton, 'The codes match'),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              receiverButton(find.widgetWithText(OutlinedButton, 'Cancel')),
            )
            .onPressed,
        isNull,
      );

      finishImport.complete('tox-client-id');
      await _pumpUntil(tester, find.text('Account received. You\'re paired.'));
      await tester.tap(
        receiverButton(find.widgetWithText(FilledButton, 'Done')),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Open pairing'), findsOneWidget);
    }),
  );

  for (final scenario in [
    (
      name: 'publishes a received account',
      protect: false,
      duplicate: false,
      cancel: false,
    ),
    (
      name: 'restores an encrypted account',
      protect: true,
      duplicate: false,
      cancel: false,
    ),
    (
      name: 'refuses an existing account',
      protect: false,
      duplicate: true,
      cancel: false,
    ),
    (
      name: 'cancels an encrypted account import',
      protect: true,
      duplicate: false,
      cancel: true,
    ),
  ]) {
    testWidgets(
      'production pairing ${scenario.name}',
      (tester) async => tester.runAsync(() async {
        final fixture = ToxProfileFixture.create();
        if (fixture == null) {
          markTestSkipped('tim2tox FFI library not loadable');
          return;
        }
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        FlutterSecureStorage.setMockInitialValues({});
        tester.view.physicalSize = const Size(1200, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final password = SecretPassword.fromString('paired-account-pw');
        addTearDown(password.dispose);
        final sent = scenario.protect
            ? passEncrypt(fixture.savedata, password)
            : fixture.savedata;
        final profileDir = await AppPaths.getProfileDirectoryForToxId(
          fixture.toxId,
        );
        final dest = File(AppPaths.profileFileInDirectory(profileDir));
        if (scenario.duplicate) {
          await Prefs.addAccount(toxId: fixture.toxId, nickname: 'Existing');
          await Directory(profileDir).create(recursive: true);
          await dest.writeAsBytes(fixture.savedata);
        }
        await tester.pumpWidget(_harness(exportBlob: () async => sent));
        await _confirmPairing(tester);

        if (scenario.protect) {
          final field = find.byKey(LoginUiKeys.passwordPromptField);
          await _pumpUntil(tester, field);
          if (scenario.cancel) {
            await tester.tap(
              find.byKey(LoginUiKeys.passwordPromptCancelButton),
            );
            await _pumpUntil(tester, find.text('Pairing cancelled.'));
            expect(await Prefs.getAccountByToxId(fixture.toxId), isNull);
            expect(await dest.exists(), isFalse);
            return;
          }
          await tester.enterText(field, 'paired-account-pw');
          await tester.tap(find.byKey(LoginUiKeys.passwordPromptOkButton));
          await tester.pump();
        }
        if (scenario.duplicate) {
          await _pumpUntil(
            tester,
            find.textContaining('Account Already Exists'),
          );
          expect(find.text('Account received. You\'re paired.'), findsNothing);
        } else {
          await _pumpUntil(
            tester,
            find.text('Account received. You\'re paired.'),
          );
        }

        final account = await Prefs.getAccountByToxId(fixture.toxId);
        expect(account, isNotNull);
        if (scenario.duplicate) expect(account?['nickname'], 'Existing');
        expect(await dest.exists(), isTrue);
        final savedata = await dest.readAsBytes();
        if (scenario.protect) {
          expect(isDataEncrypted(savedata), isTrue);
          expect(passDecrypt(savedata, password), fixture.savedata);
          expect(
            await Prefs.verifyAccountPassword(fixture.publicKeyHex, password),
            isTrue,
          );
        } else {
          expect(savedata, fixture.savedata);
        }
        expect(tester.takeException(), isNull);
      }),
    );
  }
}
