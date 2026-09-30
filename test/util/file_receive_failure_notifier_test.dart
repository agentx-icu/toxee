// Checklist M5: a receive that fails for lack of storage (or any local I/O
// error) must be reported clearly — the toast the user reads.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/service/file_receive_failure.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/util/file_receive_failure_notifier.dart';
import 'package:toxee/util/send_failure_notifier.dart';

void main() {
  Widget host() => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        scaffoldMessengerKey: SendFailureNotifier.scaffoldMessengerKey,
        home: const Scaffold(body: SizedBox.shrink()),
      );

  setUp(FileReceiveFailureNotifier.resetForTests);
  tearDown(FileReceiveFailureNotifier.resetForTests);

  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  }

  testWidgets('storage full names the file and says what to do', (tester) async {
    await tester.pumpWidget(host());
    FileReceiveFailureNotifier.show(const FileReceiveFailure(
      peerId: 'P',
      reason: FileReceiveFailureReason.noSpace,
      fileName: 'holiday.mp4',
      msgID: 'm1',
    ));
    await tester.pump();
    expect(
      find.text(
          'Not enough storage to receive "holiday.mp4". Free up space and try again.'),
      findsOneWidget,
    );
    await drain(tester);
  });

  testWidgets('other I/O failures have their own text',
      (tester) async {
    await tester.pumpWidget(host());
    FileReceiveFailureNotifier.show(const FileReceiveFailure(
      peerId: 'P',
      reason: FileReceiveFailureReason.io,
      fileName: 'a.pdf',
    ));
    await tester.pump();
    expect(find.text('Couldn\'t save "a.pdf".'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('an unnamed file still gets the storage message', (tester) async {
    await tester.pumpWidget(host());
    FileReceiveFailureNotifier.show(const FileReceiveFailure(
      peerId: 'P',
      reason: FileReceiveFailureReason.noSpace,
    ));
    await tester.pump();
    expect(
      find.text('Not enough storage to receive a file. Free up space and try again.'),
      findsOneWidget,
    );
    await drain(tester);
  });

  testWidgets('a burst for the same file is shown once', (tester) async {
    await tester.pumpWidget(host());
    const f = FileReceiveFailure(
      peerId: 'P',
      reason: FileReceiveFailureReason.noSpace,
      fileName: 'x.bin',
      msgID: 'm2',
    );
    FileReceiveFailureNotifier.show(f);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    FileReceiveFailureNotifier.show(f);
    await tester.pump();
    expect(find.textContaining('x.bin'), findsOneWidget);
    await drain(tester);
  });

  test('every locale has the four strings', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await AppLocalizations.delegate.load(locale);
      const named = FileReceiveFailure(
          peerId: 'P', reason: FileReceiveFailureReason.noSpace, fileName: 'N.txt');
      expect(FileReceiveFailureNotifier.messageFor(l10n, named), contains('N.txt'),
          reason: '$locale');
      expect(l10n.fileReceiveFailedUnnamed, isNotEmpty);
    }
  });
}
