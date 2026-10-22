import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/download_directory_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/download-directory');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.initialize(await SharedPreferences.getInstance());
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('selection saves only after retaining the scoped grant', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'denied'),
    );
    await expectLater(
      DownloadDirectoryAccess.select(
        '/chosen',
        channel: channel,
        isMacOS: true,
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(await Prefs.getDownloadsDirectory(), isNull);
  });
  test('restoration uses the bookmark resolved path', () async {
    await Prefs.setDownloadsDirectory('/old');
    messenger.setMockMethodCallHandler(channel, (_) async => '/moved');
    expect(
      await DownloadDirectoryAccess.restore(channel: channel, isMacOS: true),
      isTrue,
    );
    expect(await Prefs.getDownloadsDirectory(), '/moved');
  });
  test(
    'expired access clears the unusable custom path and signals fallback',
    () async {
      await Prefs.setDownloadsDirectory('/denied');
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'denied'),
      );
      expect(
        await DownloadDirectoryAccess.restore(channel: channel, isMacOS: true),
        isFalse,
      );
      expect(await Prefs.getDownloadsDirectory(), isNull);
    },
  );
}
