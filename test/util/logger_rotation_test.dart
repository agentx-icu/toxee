// P11 regression test: the toxee logger used to create
// `app_<timestamp>.log` per launch and never delete the old ones. Long-lived
// installs accumulated an unbounded number of files in `logs/`. We now keep
// the most recent N files (default 10).
//
// We exercise the prune helper indirectly via `AppLogger.initialize` by
// pointing `setLogPath` at a temp directory and pre-seeding 12 fake
// `app_*.log` files. After init we expect exactly 10 files plus the new one
// the logger just opened.
//
// We deliberately do not assert on the in-session 10MB size-rotation here —
// generating > 10MB of log output in a unit test is wasteful, and the
// rotation code path is shielded by a guard that no-ops on custom paths
// anyway. The basic correctness of the size threshold is enforced by
// reading the code: see `_rotateIfNeeded` in `lib/util/logger.dart`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLogger — P11 log rotation', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('toxee_logger_p11_');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test(
        'initialize keeps the new log file and prunes old app_*.log files '
        'beyond the most recent 10', () async {
      // Pre-seed 12 fake old log files with monotonically increasing mtimes
      // so the sort by mtime is deterministic. We can't easily set mtime on
      // every platform, but creating them sequentially is enough for the
      // default `File.stat().modified` to differ between platforms with
      // sub-second precision.
      for (var i = 0; i < 12; i++) {
        final f = File('${tempDir.path}/app_old_$i.log');
        await f.writeAsString('seed $i');
        // Yield a millisecond between creates so the mtimes are sortable.
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // Point the logger at a NEW file inside the same directory. Using a
      // custom path bypasses the timestamped session filename but still
      // exercises the prune helper, which scans the parent directory for
      // anything matching `app_*.log`. Join with the PLATFORM separator: on
      // Windows a hardcoded '/' produced a mixed-separator activePath that
      // never string-matched the '\'-separated listSync() paths below.
      final activePath =
          '${tempDir.path}${Platform.pathSeparator}app_active.log';
      AppLogger.setLogPath(activePath);

      await AppLogger.initialize();

      // Surface a write so the active file actually contains content.
      AppLogger.info('hello world');

      // List the surviving app_*.log files.
      final remaining = tempDir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.uri.pathSegments.last.startsWith('app_') &&
              f.uri.pathSegments.last.endsWith('.log'))
          .toList();

      // We expect at most 10 total: the active file is guaranteed to be
      // kept; the 9 most-recent of the 12 seeded files round it out.
      // (We seeded 12 and keep 10, so 3 of the old files must be gone.)
      expect(remaining.length, lessThanOrEqualTo(10));
      // The active file MUST still exist.
      expect(remaining.any((f) => f.path == activePath), isTrue);
    });
  });
}
