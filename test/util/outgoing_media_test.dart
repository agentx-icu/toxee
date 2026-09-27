// M2 (doc/reference/MOBILE_DEVICE_FEATURES.md): HEIC photos go out as JPEG
// because desktop peers often cannot show HEIC. Decided by content, not the
// name; the copy lands in the account's storage under a fresh name; a failed
// conversion stops the send instead of delivering the HEIC.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data.dart';
import 'package:toxee/util/outgoing_media.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('toxee/media_transcode');
  late Directory root;
  PlatformException? nativeError;
  final calls = <Map<Object?, Object?>>[];
  String? probedCodec;
  Completer<void>? transcodeGate;
  var cancelTooLate = false; // native already finished when Cancel landed

  List<int> heic() => [0, 0, 0, 24, ...'ftypheic'.codeUnits, 0, 0, 0, 0];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('outgoing-media-test-');
    OutgoingMedia.outputRoot = (account) async => '${root.path}/$account/out';
    OutgoingMedia.hasConverter = () => true;
    OutgoingMedia.hasVideoConverter = () => true;
    OutgoingMedia.presenter = null;
    OutgoingMedia.currentAccount = () async => null;
    nativeError = null;
    probedCodec = null;
    transcodeGate = null;
    cancelTooLate = false;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map<Object?, Object?>;
      calls.add({...args, 'method': call.method});
      if (call.method == 'probeVideo') return probedCodec;
      if (call.method == 'cancelTranscode') {
        if (!cancelTooLate) nativeError = PlatformException(code: 'CANCELLED');
        transcodeGate?.complete();
        return null;
      }
      if (call.method == 'transcodeToH264') {
        // Progress back to Dart, the way the native side reports it.
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              channel.name,
              channel.codec.encodeMethodCall(
                MethodCall('progress', {'id': args['id'], 'progress': 0.5}),
              ),
              (_) {},
            );
        await transcodeGate?.future;
      }
      final error = nativeError;
      if (error != null) {
        File(args['target']! as String).writeAsBytesSync(const [1]); // partial
        throw error;
      }
      File(args['target']! as String).writeAsBytesSync(const [0xFF, 0xD8, 0xFF]);
      return null;
    });
  });

  tearDown(() {
    TencentCloudChatMessageSeparateDataProvider.outgoingMediaPreparer = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    root.deleteSync(recursive: true);
  });

  String file(String name, List<int> bytes) =>
      (File('${root.path}/$name')..writeAsBytesSync(bytes)).path;

  test('anything but HEIC is sent as is', () async {
    final jpeg = file('a.jpg', const [0xFF, 0xD8, 0xFF, 0xE0]);
    final pdf = file('b.heic', '%PDF-1.7'.codeUnits); // the name lies
    expect(await OutgoingMedia.prepare(jpeg, accountKey: 'A'), jpeg);
    expect(await OutgoingMedia.prepare(pdf, accountKey: 'A'), pdf);
    expect(calls, isEmpty);
  });

  test('HEIC, even without its extension, becomes a JPEG in the account dir', () async {
    final photo = file('IMG_0001', heic());
    final first = await OutgoingMedia.prepare(photo, accountKey: 'A');
    final second = await OutgoingMedia.prepare(photo, accountKey: 'A');

    expect(first, startsWith('${root.path}/A/out/IMG_0001_'));
    expect(first, endsWith('.jpg'));
    expect(second, isNot(first), reason: 'a queued send may still read the first');
    expect(File(first).readAsBytesSync(), const [0xFF, 0xD8, 0xFF]);
    expect(File('$first.part').existsSync(), isFalse);
    expect(calls.first['source'], photo);
  });

  test('a failed conversion stops the send and leaves no partial file', () async {
    nativeError = PlatformException(code: 'FAILED', message: 'decode');
    final photo = file('p.heic', heic());
    await expectLater(
      OutgoingMedia.prepare(photo, accountKey: 'A'),
      throwsA(isA<MediaConversionException>()),
    );
    expect(Directory('${root.path}/A/out').listSync(), isEmpty);
  });

  test('no converter on this platform or OS version: sent as is', () async {
    final photo = file('p.heic', heic());
    nativeError = PlatformException(code: 'UNSUPPORTED');
    expect(await OutgoingMedia.prepare(photo, accountKey: 'A'), photo);

    OutgoingMedia.hasConverter = () => false;
    calls.clear();
    expect(await OutgoingMedia.prepare(photo, accountKey: 'A'), photo);
    expect(calls, isEmpty);
  });

  test('two sends of one photo at once get two files', () async {
    final photo = file('same.heic', heic());
    final both = await Future.wait([
      OutgoingMedia.prepare(photo, accountKey: 'A'),
      OutgoingMedia.prepare(photo, accountKey: 'A'),
    ]);
    expect(both[0], isNot(both[1]));
    expect(both.every((f) => File(f).existsSync()), isTrue);
  });

  test('a missing converter channel or storage error stops the send', () async {
    final photo = file('p.heic', heic());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await expectLater(
      OutgoingMedia.prepare(photo, accountKey: 'A'),
      throwsA(isA<MediaConversionException>()),
    );

    // A directory whose .part files cannot be created (read-only).
    final locked = Directory('${root.path}/locked')..createSync();
    await Process.run('chmod', ['555', locked.path]);
    addTearDown(() => Process.run('chmod', ['755', locked.path]));
    OutgoingMedia.outputRoot = (_) async => locked.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(
      OutgoingMedia.prepare(photo, accountKey: 'A'),
      throwsA(isA<MediaConversionException>()),
    ).timeout(const Duration(seconds: 5));

    OutgoingMedia.outputRoot = (_) async => throw const FileSystemException('denied');
    await expectLater(
      OutgoingMedia.prepare(photo, accountKey: 'A'),
      throwsA(isA<MediaConversionException>()),
    );
  });

  List<int> mp4(String brand) => [0, 0, 0, 24, ...'ftyp$brand'.codeUnits, 0, 0, 0, 0];

  test('an HEVC video becomes an H.264 MP4, with progress', () async {
    probedCodec = 'hvc1';
    final clip = file('IMG_0002.MOV', mp4('qt  '));
    MediaTranscodeHandle? shown;
    var doneAfter = false;
    OutgoingMedia.presenter = (handle, done) {
      shown = handle;
      unawaited(done.then((_) => doneAfter = true));
    };

    final out = await OutgoingMedia.prepare(clip, accountKey: 'A');

    expect(out, startsWith('${root.path}/A/out/IMG_0002_'));
    expect(out, endsWith('.mp4'));
    expect(calls.map((c) => c['method']), ['probeVideo', 'transcodeToH264']);
    expect(shown!.progress.value, 0.5);
    await Future<void>.delayed(Duration.zero);
    expect(doneAfter, isTrue, reason: 'the progress UI closes');
  });

  test('H.264, unreadable video, or no video converter: sent as is', () async {
    final clip = file('c.mp4', mp4('isom'));
    probedCodec = 'avc1';
    expect(await OutgoingMedia.prepare(clip, accountKey: 'A'), clip);
    probedCodec = null;
    expect(await OutgoingMedia.prepare(clip, accountKey: 'A'), clip);
    OutgoingMedia.hasVideoConverter = () => false;
    calls.clear();
    expect(await OutgoingMedia.prepare(clip, accountKey: 'A'), clip);
    expect(calls, isEmpty);
  });

  test('cancel stops the send quietly and leaves nothing behind', () async {
    probedCodec = 'hvc1';
    transcodeGate = Completer<void>();
    final clip = file('c.mov', mp4('qt  '));
    OutgoingMedia.presenter = (handle, _) => unawaited(handle.cancel());
    await expectLater(
      OutgoingMedia.prepare(clip, accountKey: 'A'),
      throwsA(isA<MediaConversionCancelled>()),
    );
    expect(Directory('${root.path}/A/out').listSync(), isEmpty);

    // The UIKit path: cancelled is not a failure to report.
    transcodeGate = Completer<void>();
    nativeError = null;
    final reasons = <String>[];
    OutgoingMedia.currentAccount = () async => 'A';
    OutgoingMedia.installForUiKit(onFailure: reasons.add);
    final preparer =
        TencentCloudChatMessageSeparateDataProvider.outgoingMediaPreparer!;
    expect(await preparer(clip), isNull);
    expect(reasons, isEmpty);
  });

  test('a Cancel that lands as the export finishes still stops the send', () async {
    probedCodec = 'hvc1';
    cancelTooLate = true;
    transcodeGate = Completer<void>();
    final clip = file('late.mov', mp4('qt  '));
    OutgoingMedia.presenter = (handle, _) => unawaited(handle.cancel());
    await expectLater(
      OutgoingMedia.prepare(clip, accountKey: 'A'),
      throwsA(isA<MediaConversionCancelled>()),
    );
    expect(Directory('${root.path}/A/out').listSync(), isEmpty);
  });

  test('UIKit sends get the converted path, or stop with a reason', () async {
    SharedPreferences.setMockInitialValues({});
    final reasons = <String>[];
    OutgoingMedia.installForUiKit(onFailure: reasons.add);
    final preparer =
        TencentCloudChatMessageSeparateDataProvider.outgoingMediaPreparer!;
    final photo = file('p.heic', heic());

    // No signed-in account: nowhere to keep the copy, so the send stops.
    expect(await preparer(photo), isNull);
    expect(reasons, hasLength(1));

    final jpeg = file('ok.jpg', const [0xFF, 0xD8, 0xFF, 0xE0]);
    expect(await preparer(jpeg), jpeg);
  });
}
