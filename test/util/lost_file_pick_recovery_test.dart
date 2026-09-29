// M9 (doc/reference/MOBILE_DEVICE_FEATURES.md): a file picked with the
// system document picker while Android reclaimed toxee is kept natively
// (LostFilePickChannel.kt) and handed to the next process. It must be staged
// in the owning account's storage under its original name, acknowledged to
// the native side only once recorded, and survive a reclaim at every step.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/home/recovered_capture_dialog.dart';
import 'package:toxee/util/camera_capture_recovery.dart';
import 'package:toxee/util/lost_file_pick.dart';

const _alice = 'ALICE_ACCOUNT';

/// The native keeper: picks stay until acked.
class _Native {
  final picks = <LostFilePick>[];
  final acked = <String>[];

  /// Simulates a reclaim right before the ack reaches the native side.
  bool dieBeforeAck = false;

  Future<List<LostFilePick>> peek() async => List.of(picks);

  Future<void> ack(String path) async {
    if (dieBeforeAck) {
      dieBeforeAck = false;
      throw StateError('process reclaimed');
    }
    acked.add(path);
    picks.removeWhere((pick) => pick.path == path);
  }
}

void main() {
  late Directory root;
  late _Native native;
  final t0 = DateTime(2026, 9, 29, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('lost-file-pick-test-');
    CameraCaptureRecovery.capturesRoot = (account) async =>
        '${root.path}/$account/captures';
    native = _Native();
  });

  tearDown(() => root.deleteSync(recursive: true));

  LostFilePick pick(String name, {String? error, DateTime? at, String? id}) {
    final file = File('${root.path}/cache/${id ?? name}/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync('content of $name');
    return LostFilePick(
      path: file.path,
      name: name,
      accountKey: _alice,
      userId: 'peer1',
      pickedAt: at ?? t0,
      error: error,
    );
  }

  Future<void> stage() => CameraCaptureRecovery.stageFilePick(
    peek: native.peek,
    ack: native.ack,
    now: t0,
  );

  test('a lost file pick is staged under its own name, then acked', () async {
    native.picks.add(pick('report.pdf'));
    await stage();

    expect(native.acked, hasLength(1));
    final capture = (await CameraCaptureRecovery.pendingFor(_alice, now: t0))!;
    expect(capture.isFile, isTrue);
    expect(capture.name, 'report.pdf');
    expect(capture.userId, 'peer1');
    expect(capture.path, endsWith('/report.pdf'));
    expect(capture.path, startsWith('${root.path}/$_alice/captures/'));
    expect(File(capture.path).readAsStringSync(), 'content of report.pdf');
  });

  test('a reclaim before the ack keeps it, and does not stage it twice', () async {
    native.picks.add(pick('report.pdf'));
    native.dieBeforeAck = true;
    await expectLater(stage(), throwsStateError);
    expect(native.picks, hasLength(1), reason: 'the native side still has it');

    // The next process: the record already names this pick as its source.
    await stage();
    expect(native.picks, isEmpty);
    final capture = (await CameraCaptureRecovery.pendingFor(_alice, now: t0))!;
    expect(File(capture.path).readAsStringSync(), 'content of report.pdf');
    final staged = Directory('${root.path}/$_alice/captures')
        .listSync()
        .whereType<Directory>();
    expect(staged, hasLength(1), reason: 'one item, not a duplicate');
  });

  test('two lost picks: the newest is offered, both are acked', () async {
    native.picks
      ..add(pick('old.txt', id: 'a'))
      ..add(pick('new.txt', id: 'b'));
    await stage();

    expect(native.picks, isEmpty);
    final capture = (await CameraCaptureRecovery.pendingFor(_alice, now: t0))!;
    expect(capture.name, 'new.txt');
    final staged = Directory('${root.path}/$_alice/captures')
        .listSync()
        .whereType<Directory>();
    expect(staged, hasLength(1), reason: 'the replaced item is removed');
  });

  test('a failed copy or a stale pick is acked and not offered', () async {
    native.picks
      ..add(pick('broken.bin', error: 'provider returned no stream'))
      ..add(pick('stale.txt', at: t0.subtract(const Duration(hours: 2))));
    await stage();

    expect(native.picks, isEmpty);
    expect(await CameraCaptureRecovery.pendingFor(_alice, now: t0), isNull);
  });

  test('discard removes the file and its directory', () async {
    native.picks.add(pick('report.pdf'));
    await stage();
    final capture = (await CameraCaptureRecovery.pendingFor(_alice, now: t0))!;
    await CameraCaptureRecovery.resolve(capture, sent: false);
    expect(File(capture.path).existsSync(), isFalse);
    expect(File(capture.path).parent.existsSync(), isFalse);
  });

  test('a reclaim between replacing and deleting still drops the old item', () async {
    native.picks.add(pick('old.txt', id: 'a'));
    await stage();
    final old = (await CameraCaptureRecovery.pendingFor(_alice, now: t0))!;

    native.picks.add(pick('new.txt', id: 'b'));
    native.dieBeforeAck = true; // after the record switch, before the delete
    await expectLater(stage(), throwsStateError);
    expect(File(old.path).existsSync(), isTrue, reason: 'not yet deleted');

    final capture = (await CameraCaptureRecovery.pendingFor(_alice, now: t0))!;
    expect(capture.name, 'new.txt');
    expect(File(old.path).existsSync(), isFalse, reason: 'the replaced item');
    expect(File(old.path).parent.existsSync(), isFalse);
  });

  test('an unfinished replacement is finished before the next one', () async {
    native.picks.add(pick('a.txt', id: 'a'));
    await stage();
    final a = (await CameraCaptureRecovery.pendingFor(_alice, now: t0))!;
    native.picks.add(pick('b.txt', id: 'b'));
    native.dieBeforeAck = true; // A -> B noted, A not yet deleted
    await expectLater(stage(), throwsStateError);

    native.picks.add(pick('c.txt', id: 'c')); // B -> C in the next process
    await stage();
    expect(File(a.path).existsSync(), isFalse, reason: 'A is not orphaned');
    final capture = (await CameraCaptureRecovery.pendingFor(_alice, now: t0))!;
    expect(capture.name, 'c.txt');
    final staged = Directory('${root.path}/$_alice/captures')
        .listSync()
        .whereType<Directory>();
    expect(staged, hasLength(1));
  });

  test('a recorded pick is not stale, however late the next start', () async {
    native.picks.add(pick('report.pdf'));
    native.dieBeforeAck = true;
    await expectLater(stage(), throwsStateError);
    final late = t0.add(const Duration(hours: 5));
    await CameraCaptureRecovery.stageFilePick(
      peek: native.peek,
      ack: native.ack,
      now: late,
    );
    expect(native.picks, isEmpty);
    final capture = (await CameraCaptureRecovery.pendingFor(_alice, now: late))!;
    expect(File(capture.path).readAsStringSync(), 'content of report.pdf');
  });

  test('a stale pick loses its cached copy too', () async {
    final stale = pick('stale.txt', at: t0.subtract(const Duration(hours: 2)));
    native.picks.add(stale);
    await stage();
    expect(File(stale.path).existsSync(), isFalse);
    expect(File(stale.path).parent.existsSync(), isFalse);
  });

  test('a sent file is kept: the send reads it by path', () async {
    native.picks.add(pick('report.pdf'));
    await stage();
    final capture = (await CameraCaptureRecovery.pendingFor(_alice, now: t0))!;
    await CameraCaptureRecovery.resolve(capture, sent: true);
    final later = t0.add(const Duration(days: 30));
    expect(await CameraCaptureRecovery.pendingFor(_alice, now: later), isNull);
    native.picks.add(pick('next.txt', id: 'n'));
    await CameraCaptureRecovery.stageFilePick(
      peek: native.peek,
      ack: native.ack,
      now: later.subtract(const Duration(minutes: 1)),
    );
    expect(File(capture.path).existsSync(), isTrue);
  });

  testWidgets('the dialog names the file and its recipient', (tester) async {
    final capture = RecoveredCapture(
      accountKey: _alice,
      userId: 'peer1',
      path: '/nonexistent/report.pdf',
      isVideo: false,
      capturedAt: t0,
      isFile: true,
      name: 'report.pdf',
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) =>
                  RecoveredCaptureDialog(capture: capture, peerName: 'Alice'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Send the file you picked?'), findsOneWidget);
    expect(find.textContaining('Send report.pdf to Alice?'), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
  });
}
