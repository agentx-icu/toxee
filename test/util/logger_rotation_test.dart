// Real file IO exercises the same native owner used by production. Its
// canonical numeric app_<session>.log family is bounded across launches; names
// outside that family belong to their caller and must not be deleted.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLogger — P11 log rotation', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('toxee_logger_p11_');
      AppLogger.resetForTesting();
    });

    tearDown(() async {
      AppLogger.resetForTesting();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('initialize keeps the new log file and prunes old app_*.log files '
        'beyond the most recent 10', () async {
      // Pre-seed 12 fake old log files with monotonically increasing mtimes
      // so the sort by mtime is deterministic. The mtimes are STAMPED, not
      // obtained by sleeping between creates: a filesystem with coarse
      // timestamp granularity (or a host that ran the loop faster than that
      // granularity) gave several files the same mtime and made the prune
      // order — and therefore this test — a coin flip.
      final base = DateTime.now().subtract(const Duration(hours: 1));
      for (var i = 0; i < 12; i++) {
        final f = File('${tempDir.path}/app_${1700000000000 + i}.log');
        await f.writeAsString('seed $i');
        await f.setLastModified(base.add(Duration(minutes: i)));
      }

      // Point the logger at a new numeric canonical session in the same family.
      // Join with the PLATFORM separator: on
      // Windows a hardcoded '/' produced a mixed-separator activePath that
      // never string-matched the '\'-separated listSync() paths below.
      final activePath =
          '${tempDir.path}${Platform.pathSeparator}app_1800000000000.log';
      final unrelated = File('${tempDir.path}/app_developer_notes.log')
        ..writeAsStringSync('unrelated synthetic notes');
      AppLogger.setLogPath(activePath);

      await AppLogger.initialize();

      // Surface a write so the active file actually contains content.
      AppLogger.info('hello world');

      // List the surviving app_*.log files.
      final remaining = tempDir
          .listSync()
          .whereType<File>()
          .where(
            (f) => RegExp(
              r'^app_[0-9]+(_[0-9]+)*\.log$',
            ).hasMatch(f.uri.pathSegments.last),
          )
          .toList();

      // We expect at most 10 total: the active file is guaranteed to be
      // kept; the 9 most-recent of the 12 seeded files round it out.
      // (We seeded 12 and keep 10, so 3 of the old files must be gone.)
      expect(remaining.length, 10);
      // The active file MUST still exist.
      expect(remaining.any((f) => f.path == activePath), isTrue);
      for (var i = 0; i < 12; i++) {
        expect(
          File('${tempDir.path}/app_${1700000000000 + i}.log').existsSync(),
          i >= 3,
        );
      }
      expect(unrelated.readAsStringSync(), 'unrelated synthetic notes');
    });
  });
}
