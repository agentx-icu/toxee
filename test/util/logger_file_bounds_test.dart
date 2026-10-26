import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('toxee_log_bounds_');
    AppLogger.resetForTesting();
  });
  tearDown(() async {
    AppLogger.resetForTesting();
    await directory.delete(recursive: true);
  });

  test('an oversized UTF-8 record has an explicit bounded omission', () async {
    final log = File('${directory.path}/app_1700000000000.log');
    AppLogger.setLogPath(log.path);
    await AppLogger.initialize();
    final before = log.lengthSync();
    AppLogger.info('🙂' * 40000);
    final bytes = log.readAsBytesSync().sublist(before);
    expect(bytes.length, lessThanOrEqualTo(64 * 1024));
    expect(utf8.decode(bytes), contains('omitted_bytes='));
  });

  test('the explicit debug or harness path also stays bounded', () async {
    final log = File('${directory.path}/flutter_client.log');
    AppLogger.setLogPath(log.path);
    await AppLogger.initialize();
    final handle = log.openSync(mode: FileMode.append);
    handle.truncateSync(10 * 1024 * 1024);
    handle.closeSync();
    AppLogger.info('record after the boundary');
    expect(log.lengthSync(), lessThanOrEqualTo(10 * 1024 * 1024));
    expect(log.readAsStringSync(), contains('record after the boundary'));
  });

  test('a symlink sink never modifies its unrelated target', () async {
    final target = File('${directory.path}/learning.json')
      ..writeAsStringSync('{"retained":"synthetic-learning"}');
    final before = target.readAsBytesSync();
    final link = Link('${directory.path}/app_1700000000000.log');
    link.createSync(target.path);
    AppLogger.setLogPath(link.path);
    await AppLogger.initialize();
    AppLogger.error('must never append to learning');
    expect(target.readAsBytesSync(), before);
  });

  test('a hard-link sink never modifies its unrelated target', () async {
    final target = File('${directory.path}/learning.json')
      ..writeAsStringSync('{"retained":"synthetic-learning"}');
    final before = target.readAsBytesSync();
    final path = '${directory.path}/app_1700000000000.log';
    final link = Platform.isWindows
        ? await Process.run('cmd', ['/c', 'mklink', '/H', path, target.path])
        : await Process.run('ln', [target.path, path]);
    expect(link.exitCode, 0, reason: '${link.stdout}${link.stderr}');
    AppLogger.setLogPath(path);
    await AppLogger.initialize();
    AppLogger.error('must never append to learning');
    expect(AppLogger.getLogPath(), isNull);
    expect(target.readAsBytesSync(), before);
  });

  test(
    'custom histories retain ten bounded files and stable basename',
    () async {
      final log = File('${directory.path}/flutter_client.log');
      final unrelated = File('${directory.path}/developer.log')
        ..writeAsStringSync('retained unrelated notes');
      AppLogger.setLogPath(log.path);
      await AppLogger.initialize();
      final active = AppLogger.getLogPath();
      for (var i = 0; i < 12; i++) {
        final handle = log.openSync(mode: FileMode.append);
        handle.truncateSync(10 * 1024 * 1024);
        handle.closeSync();
        AppLogger.info('newest synthetic event $i');
        expect(AppLogger.getLogPath(), active);
        final family = directory.listSync().whereType<File>().where(
          (file) => RegExp(
            r'^flutter_client(_[0-9]+)?\.log$',
          ).hasMatch(file.uri.pathSegments.last),
        );
        expect(family.length, lessThanOrEqualTo(10));
        expect(
          family.every((file) => file.lengthSync() <= 10 * 1024 * 1024),
          isTrue,
        );
        expect(log.readAsStringSync(), contains('newest synthetic event $i'));
      }
      expect(unrelated.readAsStringSync(), 'retained unrelated notes');
    },
  );
}
