// S91 — Pairing host/client pages, L1 real-UI loopback gate.
//
// This mounts the real host and client pages side-by-side, reads the real QR
// URL from QrImageView, pastes it into the client page, confirms the same SAS
// on both pages, and asserts the encrypted profile bytes arrive at the client
// materializer. The only production seam is the advertised LAN address:
// WidgetTester injects 127.0.0.1 so both halves can run in one process.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/pairing/pairing_client_page.dart';
import 'package:toxee/ui/pairing/pairing_host_page.dart';

Widget _harness({
  required Future<Uint8List> Function() exportBlob,
  required Future<String> Function(Uint8List) materialize,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Row(
      children: [
        Expanded(
          child: PairingHostPage(
            toxId: 'tox-host-id',
            lanAddressForTest: '127.0.0.1',
            exportServiceForTest: exportBlob,
          ),
        ),
        Expanded(
          child: PairingClientPage(materializeProfileForTest: materialize),
        ),
      ],
    ),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
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
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'S91 host/client QR + SAS confirmation transfers the profile blob',
    (tester) async {
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

      await _pumpUntil(tester, find.byType(QrImageView));
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      final qrKey = qr.key as ValueKey<String>;
      final qrUrl = qrKey.value.substring('pairing_qr_url:'.length);
      expect(qrUrl, startsWith('tox://pair?'));

      await tester.enterText(find.byType(TextField), qrUrl);
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pump();

      final sasConfirmButtons = find.widgetWithText(
        FilledButton,
        'The codes match',
      );
      await _pumpUntilCount(tester, sasConfirmButtons, 2);
      expect(
        sasConfirmButtons,
        findsNWidgets(2),
        reason: 'both host and client must render the SAS confirmation action',
      );

      await tester.tap(sasConfirmButtons.first);
      await tester.pump();
      await tester.tap(sasConfirmButtons.last);
      await tester.pump();

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
        find.text('Account sent. The other device now has your account.'),
        findsOneWidget,
      );
    },
  );
}
