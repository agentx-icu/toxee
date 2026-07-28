import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/profile/profile_qr_section.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

const _qrPath = '/tmp/profile_qr_section_reentrancy_test.png';

Widget _app({
  required Future<void> Function() onSave,
  required Future<void> Function(String path) onCopy,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: ProfileQrSection(
        qrFuture: Future<String>.value(_qrPath),
        versionKey: 'reentrancy',
        isWide: true,
        primaryColor: Colors.blue,
        onSave: onSave,
        onCopy: onCopy,
      ),
    ),
  );
}

Finder _saveButton() => find.ancestor(
  of: find.byIcon(Icons.download_rounded),
  matching: find.byType(OutlinedButton),
);

Future<void> _pumpSection(
  WidgetTester tester, {
  required Future<void> Function() onSave,
  required Future<void> Function(String path) onCopy,
}) async {
  await tester.pumpWidget(_app(onSave: onSave, onCopy: onCopy));
  await tester.pump();
}

void main() {
  testWidgets(
    'save ignores duplicate taps while pending and retries after success or error',
    (tester) async {
      final operations = <Completer<void>>[];

      await _pumpSection(
        tester,
        onSave: () {
          final operation = Completer<void>();
          operations.add(operation);
          return operation.future;
        },
        onCopy: (_) async {},
      );

      await tester.tap(_saveButton());
      await tester.tap(_saveButton());
      expect(operations, hasLength(1));

      await tester.pump();
      expect(tester.widget<OutlinedButton>(_saveButton()).onPressed, isNull);

      operations[0].complete();
      await tester.pump();
      expect(tester.widget<OutlinedButton>(_saveButton()).onPressed, isNotNull);

      final error = StateError('save failed');
      Object? callbackError;
      await runZonedGuarded(() async {
        await tester.tap(_saveButton());
        await tester.tap(_saveButton());
        expect(operations, hasLength(2));

        await tester.pump();
        expect(tester.widget<OutlinedButton>(_saveButton()).onPressed, isNull);

        operations[1].completeError(error);
        await tester.pump();
      }, (caught, _) => callbackError = caught);
      expect(callbackError, same(error));
      expect(tester.widget<OutlinedButton>(_saveButton()).onPressed, isNotNull);

      await tester.tap(_saveButton());
      expect(operations, hasLength(3));
      operations[2].complete();
      await tester.pump();
    },
  );

  testWidgets(
    'copy ignores duplicate taps while pending and retries after success or error',
    (tester) async {
      final operations = <Completer<void>>[];
      final copiedPaths = <String>[];

      await _pumpSection(
        tester,
        onSave: () async {},
        onCopy: (path) {
          copiedPaths.add(path);
          final operation = Completer<void>();
          operations.add(operation);
          return operation.future;
        },
      );

      final copyButton = find.byKey(UiKeys.profileQrCopyButton);
      await tester.tap(copyButton);
      await tester.tap(copyButton);
      expect(operations, hasLength(1));
      expect(copiedPaths, [_qrPath]);

      await tester.pump();
      expect(tester.widget<OutlinedButton>(copyButton).onPressed, isNull);

      operations[0].complete();
      await tester.pump();
      expect(tester.widget<OutlinedButton>(copyButton).onPressed, isNotNull);

      final error = StateError('copy failed');
      Object? callbackError;
      await runZonedGuarded(() async {
        await tester.tap(copyButton);
        await tester.tap(copyButton);
        expect(operations, hasLength(2));
        expect(copiedPaths, [_qrPath, _qrPath]);

        await tester.pump();
        expect(tester.widget<OutlinedButton>(copyButton).onPressed, isNull);

        operations[1].completeError(error);
        await tester.pump();
      }, (caught, _) => callbackError = caught);
      expect(callbackError, same(error));
      expect(tester.widget<OutlinedButton>(copyButton).onPressed, isNotNull);

      await tester.tap(copyButton);
      expect(operations, hasLength(3));
      expect(copiedPaths, [_qrPath, _qrPath, _qrPath]);
      operations[2].complete();
      await tester.pump();
    },
  );
}
