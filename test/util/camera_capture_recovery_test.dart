// M9 (doc/reference/MOBILE_DEVICE_FEATURES.md): a photo / video taken while
// Android reclaimed toxee comes back to a new process. It must be staged in
// the owning account's storage (surviving another reclaim), offered to that
// account only, and ended by an explicit send or discard.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/mobile/tencent_cloud_chat_message_camera.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/home/recovered_capture_dialog.dart';
import 'package:toxee/util/camera_capture_recovery.dart';

const _alice = 'ALICE_ACCOUNT';
const _bob = 'BOB_ACCOUNT';

void main() {
  late Directory root;
  late File picked;
  final t0 = DateTime(2026, 9, 27, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('capture-recovery-test-');
    CameraCaptureRecovery.capturesRoot = (account) async =>
        '${root.path}/$account/captures';
    picked = File('${root.path}/picker_cache.jpg')
      ..writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 1]);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<LostCameraCapture?> lostPhoto() async =>
      LostCameraCapture(path: picked.path, isVideo: false);

  Future<void> reclaimDuringCamera({DateTime? at}) async {
    await CameraCaptureRecovery.remember(
      accountKey: _alice,
      userId: 'peer1',
      now: at ?? t0,
    );
    // ...process reclaimed, camera returns to a new process...
    await CameraCaptureRecovery.stage(retrieve: lostPhoto, now: t0);
  }

  test('a lost capture is staged for its account and chat only', () async {
    await reclaimDuringCamera();

    expect(picked.existsSync(), isFalse, reason: 'moved out of the cache');
    expect(await CameraCaptureRecovery.pendingFor(_bob, now: t0), isNull);
    final capture = await CameraCaptureRecovery.pendingFor(_alice, now: t0);
    expect(capture, isNotNull);
    expect(capture!.userId, 'peer1');
    expect(capture.isVideo, isFalse);
    expect(capture.path, startsWith('${root.path}/$_alice/captures/'));
    expect(File(capture.path).readAsBytesSync(), const [0xFF, 0xD8, 0xFF, 1]);
  });

  test('it survives another restart until answered', () async {
    await reclaimDuringCamera();
    // A second process start finds no new lost data but the same pending one.
    await CameraCaptureRecovery.stage(retrieve: () async => null, now: t0);
    expect(await CameraCaptureRecovery.pendingFor(_alice, now: t0), isNotNull);
  });

  test('send keeps the file (the send reads it); discard deletes it', () async {
    await reclaimDuringCamera();
    final sent = (await CameraCaptureRecovery.pendingFor(_alice, now: t0))!;
    await CameraCaptureRecovery.resolve(sent, sent: true);
    expect(await CameraCaptureRecovery.pendingFor(_alice, now: t0), isNull);
    expect(File(sent.path).existsSync(), isTrue);

    picked.writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 2]);
    await reclaimDuringCamera();
    final discarded =
        (await CameraCaptureRecovery.pendingFor(_alice, now: t0))!;
    await CameraCaptureRecovery.resolve(discarded, sent: false);
    expect(File(discarded.path).existsSync(), isFalse);
    expect(await CameraCaptureRecovery.pendingFor(_alice, now: t0), isNull);
  });

  test('no target, or a stale one: the capture is deleted', () async {
    await CameraCaptureRecovery.stage(retrieve: lostPhoto, now: t0);
    expect(picked.existsSync(), isFalse);
    expect(await CameraCaptureRecovery.pendingFor(_alice, now: t0), isNull);

    picked.writeAsBytesSync(const [1]);
    await reclaimDuringCamera(at: t0.subtract(const Duration(hours: 2)));
    expect(picked.existsSync(), isFalse);
    expect(await CameraCaptureRecovery.pendingFor(_alice, now: t0), isNull);
  });

  test('a normal return clears the target', () async {
    await CameraCaptureRecovery.remember(accountKey: _alice, userId: 'p');
    await CameraCaptureRecovery.forget();
    await CameraCaptureRecovery.stage(retrieve: lostPhoto, now: t0);
    expect(await CameraCaptureRecovery.pendingFor(_alice, now: t0), isNull);
  });

  test('a picker error is not a capture', () async {
    await CameraCaptureRecovery.remember(accountKey: _alice, userId: 'p');
    await CameraCaptureRecovery.stage(
      retrieve: () async =>
          const LostCameraCapture(isVideo: false, error: 'camera_access'),
      now: t0,
    );
    expect(await CameraCaptureRecovery.pendingFor(_alice, now: t0), isNull);
  });

  test('expiry and logout drop the pending capture', () async {
    await reclaimDuringCamera();
    final capture = (await CameraCaptureRecovery.pendingFor(_alice, now: t0))!;
    expect(
      await CameraCaptureRecovery.pendingFor(
        _alice,
        now: t0.add(const Duration(days: 2)),
      ),
      isNull,
    );
    expect(File(capture.path).existsSync(), isFalse);

    picked.writeAsBytesSync(const [3]);
    await reclaimDuringCamera();
    final again = (await CameraCaptureRecovery.pendingFor(_alice, now: t0))!;
    await CameraCaptureRecovery.purge(_alice);
    expect(File(again.path).existsSync(), isFalse);
  });

  test('a staging interrupted before the move is finished later', () async {
    // What a reclaim right after the record write leaves behind: the record
    // (with the source) exists, the file is still in the picker's cache.
    final dir = Directory('${root.path}/$_alice/captures')..createSync(recursive: true);
    final staged = '${dir.path}/1_0_picker_cache.jpg';
    File('${dir.path}/pending_$_alice.json').writeAsStringSync(
      '{"accountKey":"$_alice","userId":"peer1","path":"$staged",'
      '"isVideo":false,"capturedAt":${t0.millisecondsSinceEpoch},'
      '"sourcePath":"${picked.path}"}',
    );
    final capture = await CameraCaptureRecovery.pendingFor(_alice, now: t0);
    expect(capture?.path, staged);
    expect(File(staged).existsSync(), isTrue);
    expect(picked.existsSync(), isFalse);
  });

  test('accounts sharing a storage prefix keep their own captures', () async {
    CameraCaptureRecovery.capturesRoot = (_) async => '${root.path}/shared';
    await reclaimDuringCamera();
    picked.writeAsBytesSync(const [9]);
    await CameraCaptureRecovery.remember(
      accountKey: _bob,
      userId: 'peer2',
      now: t0,
    );
    await CameraCaptureRecovery.stage(retrieve: lostPhoto, now: t0);

    final alice = await CameraCaptureRecovery.pendingFor(_alice, now: t0);
    final bob = await CameraCaptureRecovery.pendingFor(_bob, now: t0);
    expect(alice?.userId, 'peer1');
    expect(bob?.userId, 'peer2');
    await CameraCaptureRecovery.purge(_bob);
    expect(File(alice!.path).existsSync(), isTrue);
  });

  test('a logout during staging still purges what staging wrote', () async {
    await CameraCaptureRecovery.remember(
      accountKey: _alice,
      userId: 'peer1',
      now: t0,
    );
    final staging = CameraCaptureRecovery.stage(retrieve: lostPhoto, now: t0);
    final purge = CameraCaptureRecovery.purge(_alice); // queued behind it
    await Future.wait([staging, purge]);
    expect(await CameraCaptureRecovery.pendingFor(_alice, now: t0), isNull);
    expect(Directory('${root.path}/$_alice/captures').listSync(), isEmpty);
  });

  testWidgets('the dialog names the recipient and answers send / discard', (
    tester,
  ) async {
    final capture = RecoveredCapture(
      accountKey: _alice,
      userId: 'peer1',
      path: '/nonexistent.jpg',
      isVideo: false,
      capturedAt: t0,
    );
    bool? answer;
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
            onPressed: () async => answer = await showDialog<bool>(
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
    expect(find.text('Send the photo you took?'), findsOneWidget);
    expect(find.textContaining('Send it to Alice?'), findsOneWidget);

    await tester.tap(find.byKey(RecoveredCaptureDialog.sendKey));
    await tester.pumpAndSettle();
    expect(answer, isTrue);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RecoveredCaptureDialog.discardKey));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });
}
