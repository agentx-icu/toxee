// M3 (doc/reference/MOBILE_DEVICE_FEATURES.md): the chat media viewer's Save
// goes to the photo library on phones. Received files often have no
// extension, so the type comes from the content; a type the library cannot
// take (or a kind mismatch) returns null so the save dialog handles it, while
// a refusal from the library is reported as a failure.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_viewer/tencent_cloud_chat_message_viewer.dart';
import 'package:toxee/util/gallery_saver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('toxee/qr_save');
  late Directory dir;
  final calls = <Map<Object?, Object?>>[];
  Object? nativeAnswer;

  List<int> ftyp(String brand) => [0, 0, 0, 24, ...'ftyp$brand'.codeUnits];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('gallery-saver-test-');
    calls.clear();
    nativeAnswer = 'content://media/1';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.arguments as Map<Object?, Object?>);
      final answer = nativeAnswer;
      if (answer is PlatformException) throw answer;
      return answer;
    });
  });

  tearDown(() {
    MessageViewerMediaSaver.defaultGallerySaver = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    dir.deleteSync(recursive: true);
  });

  String file(String name, List<int> bytes) =>
      (File('${dir.path}/$name')..writeAsBytesSync(bytes)).path;

  test('content decides the type', () {
    expect(GallerySaver.sniffMimeType([0xFF, 0xD8, 0xFF, 0xE0]), 'image/jpeg');
    expect(GallerySaver.sniffMimeType([0x89, 0x50, 0x4E, 0x47]), 'image/png');
    expect(GallerySaver.sniffMimeType('GIF89a'.codeUnits), 'image/gif');
    expect(
      GallerySaver.sniffMimeType([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits]),
      'image/webp',
    );
    expect(GallerySaver.sniffMimeType(ftyp('heic')), 'image/heic');
    expect(GallerySaver.sniffMimeType(ftyp('qt  ')), 'video/quicktime');
    expect(GallerySaver.sniffMimeType(ftyp('isom')), 'video/mp4');
    expect(GallerySaver.sniffMimeType(ftyp('3gp4')), 'video/3gpp');
    expect(GallerySaver.sniffMimeType('%PDF-1.7'.codeUnits), isNull);
    expect(GallerySaver.sniffMimeType(const []), isNull);
  });

  test('the saved name gets a matching extension', () {
    expect(GallerySaver.withExtension('123_photo', 'image/jpeg'), '123_photo.jpg');
    expect(GallerySaver.withExtension('a.JPEG', 'image/jpeg'), 'a.JPEG');
    expect(GallerySaver.withExtension('clip.bin', 'video/mp4'), 'clip.bin.mp4');
    expect(GallerySaver.withExtension('clip.mov', 'video/quicktime'), 'clip.mov');
  });

  test('kind mismatch, unknown content and iOS WebM go to the dialog', () async {
    final video = file('noext_video', ftyp('isom'));
    final pdf = file('doc', '%PDF-1.7'.codeUnits);
    final webm = file('w', [0x1A, 0x45, 0xDF, 0xA3, ...List.filled(20, 0), ...'webm'.codeUnits]);
    expect(
      await GallerySaver.mimeTypeOf(video, MessageViewerMediaKind.image, isIOS: false),
      isNull,
    );
    expect(
      await GallerySaver.mimeTypeOf(pdf, MessageViewerMediaKind.image, isIOS: false),
      isNull,
    );
    expect(
      await GallerySaver.mimeTypeOf(webm, MessageViewerMediaKind.video, isIOS: true),
      isNull,
    );
    expect(
      await GallerySaver.mimeTypeOf(webm, MessageViewerMediaKind.video, isIOS: false),
      'video/webm',
    );
  });

  test('an extensionless video is saved as a video with a named extension', () async {
    final path = file('abcdef', ftyp('qt  '));
    final result = await GallerySaver.saveMessageMedia(
      path: path,
      kind: MessageViewerMediaKind.video,
      fileName: '1700_abcdef',
    );
    expect(result, MessageViewerMediaSaveResult.saved);
    expect(calls.single['path'], path);
    expect(calls.single['mimeType'], 'video/quicktime');
    expect(calls.single['displayName'], '1700_abcdef.mov');
  });

  test('a refusal from the library is a failure', () async {
    nativeAnswer = PlatformException(code: 'SAVE_FAILED');
    final result = await GallerySaver.saveMessageMedia(
      path: file('p.png', [0x89, 0x50, 0x4E, 0x47]),
      kind: MessageViewerMediaKind.image,
      fileName: 'p.png',
    );
    expect(result, MessageViewerMediaSaveResult.failed);
  });

  test('installs on phones only', () {
    GallerySaver.install(isMobile: false);
    expect(MessageViewerMediaSaver.defaultGallerySaver, isNull);
    GallerySaver.install(isMobile: true);
    expect(MessageViewerMediaSaver.defaultGallerySaver, isNotNull);
  });

  test('QR saves keep the PNG default', () async {
    await GallerySaver.saveFile('/tmp/qr.png');
    expect(calls.single['mimeType'], 'image/png');
    expect(calls.single.containsKey('displayName'), isFalse);
  });
}
