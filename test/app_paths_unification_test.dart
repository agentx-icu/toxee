// X6 — Path-construction unification test.
//
// Checks AppPaths.lanBootstrapProfilePath (new in this PR) returns the
// historically-correct shape so existing installs keep finding their
// bootstrap profile, and that AppPaths.logFilePath now uses the
// timestamped convention instead of the deprecated flat `flutter_client.log`.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:toxee/util/app_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('toxee_app_paths_test_');
    // Mock path_provider so AppPaths writes land under our per-test temp dir
    // instead of the user's real Application Support. Same mechanism as
    // test/account_export/test_support.dart.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'getApplicationSupportDirectory':
            return tempRoot.path;
          case 'getApplicationDocumentsDirectory':
            return tempRoot.path;
          case 'getApplicationCacheDirectory':
            return p.join(tempRoot.path, 'cache');
          case 'getTemporaryDirectory':
            return p.join(tempRoot.path, 'temp');
          case 'getDownloadsDirectory':
            return p.join(tempRoot.path, 'Downloads');
          default:
            return null;
        }
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('lanBootstrapProfilePath sits under <appSupport>/tim2tox/', () async {
    final got = await AppPaths.lanBootstrapProfilePath;
    expect(p.basename(got), 'bootstrap_service_profile.tox');
    expect(p.basename(p.dirname(got)), 'tim2tox');
    expect(p.dirname(p.dirname(got)), tempRoot.path);
  });

  test(
      'logFilePath uses timestamped path under <appSupport>/logs/, '
      'no longer the flat flutter_client.log', () async {
    final got = await AppPaths.logFilePath;
    expect(p.basename(p.dirname(got)), 'logs');
    expect(p.dirname(p.dirname(got)), tempRoot.path);
    expect(p.basename(got), startsWith('app_'));
    expect(p.basename(got), endsWith('.log'));
    expect(p.basename(got), isNot(equals('flutter_client.log')));
  });
}
