import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/bootstrap/logging_bootstrap.dart';
import 'package:toxee/util/harness_environment.dart';
import 'package:toxee/util/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the real bootstrap probe never overwrites an existing log-link target',
    () async {
      expect(
        HarnessEnvironment.value(HarnessEnvironment.logDirKey),
        isNull,
        reason: 'this fixture owns only its temporary working directory',
      );
      final previousDirectory = Directory.current;
      final directory = await Directory.systemTemp.createTemp(
        'toxee_log_bootstrap_',
      );
      try {
        AppLogger.resetForTesting();
        final build = Directory('${directory.path}/build')..createSync();
        final target = File('${directory.path}/learning.json')
          ..writeAsStringSync('{"retained":"synthetic bootstrap data"}');
        final original = target.readAsBytesSync();
        final intended = Link('${build.path}/flutter_client.log')
          ..createSync(target.path);
        Directory.current = directory;
        await LoggingBootstrap.initialize();
        expect(target.readAsBytesSync(), original);
        expect(
          FileSystemEntity.typeSync(intended.path, followLinks: false),
          FileSystemEntityType.link,
        );
        expect(AppLogger.getLogPath(), isNull);
        expect(build.listSync().whereType<Directory>(), isEmpty);
      } finally {
        AppLogger.resetForTesting();
        Directory.current = previousDirectory;
        await directory.delete(recursive: true);
      }
    },
  );
}
