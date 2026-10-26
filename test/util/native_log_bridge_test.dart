import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Tim2ToxFfi ffi;
  int generation = 0;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('toxee_log_bridge_');
    AppLogger.resetForTesting();
    ffi = Tim2ToxFfi.open();
    generation = 0;
  });
  tearDown(() async {
    AppPaths.debugApplicationSupportOverride = null;
    AppLogger.resetForTesting();
    expect(ffi.releaseLogOwned(generation), 0);
    await directory.delete(recursive: true);
  });

  String physicalPath(String leaf) =>
      '${directory.resolveSymbolicLinksSync()}${Platform.pathSeparator}$leaf';

  test(
    'public ABI claims one owner and stale generations never close another',
    () {
      final first = ffi.configureLogOwned(physicalPath('app_1.log'));
      generation = first.generation;
      expect(first.status, 0);
      expect(generation, greaterThan(0));
      expect(ffi.configureLogOwned(physicalPath('app_2.log')).status, 7);
      expect(ffi.releaseLogOwned(0), 5);
      expect(ffi.appendLogOwned(generation + 1, Uint8List.fromList([65])), 5);
      expect(ffi.releaseLogOwned(generation + 1), 5);
      expect(ffi.appendLogOwned(generation, Uint8List.fromList([65, 10])), 0);
      expect(File(physicalPath('app_1.log')).readAsStringSync(), 'A\n');
      expect(ffi.releaseLogOwned(generation), 0);
      expect(ffi.releaseLogOwned(generation), 0);
      final old = generation;
      final second = ffi.configureLogOwned(physicalPath('app_2.log'));
      generation = second.generation;
      expect(second.status, 0);
      expect(generation, greaterThan(old));
      expect(ffi.releaseLogOwned(old), 5);
      expect(ffi.appendLogOwned(generation, Uint8List.fromList([66, 10])), 0);
      expect(File(physicalPath('app_2.log')).readAsStringSync(), 'B\n');
    },
  );

  test('the public ABI bounds UTF-8 records without a Dart pre-truncation', () {
    final claim = ffi.configureLogOwned(physicalPath('app_1.log'));
    generation = claim.generation;
    expect(claim.status, 0);
    final record = Uint8List.fromList(utf8.encode('🙂' * 40000));
    expect(ffi.appendLogOwned(generation, record), 1);
    final bytes = File(physicalPath('app_1.log')).readAsBytesSync();
    expect(bytes.length, lessThanOrEqualTo(64 * 1024));
    expect(utf8.decode(bytes), contains('omitted_bytes='));
    expect(ffi.appendLogOwned(generation, Uint8List(0)), 2);
    expect(ffi.appendLogOwned(generation, Uint8List.fromList([0xff])), 2);
    expect(ffi.appendLogOwned(generation, Uint8List.fromList([65])), 0);
  });

  test(
    'an embedded NUL path is rejected before it can address another file',
    () {
      final path = physicalPath('app_1.log');
      expect(ffi.configureLogOwned('$path\u0000hidden').status, 2);
      expect(File(path).existsSync(), isFalse);
      expect(ffi.releaseLogOwned(0), 0);
    },
  );

  test(
    'existing close/delete/fresh paths release the real native descriptor',
    () async {
      final first = File('${directory.path}/app_1.log');
      AppLogger.setLogPath(first.path);
      await AppLogger.initialize();
      AppLogger.info('before close');
      expect(first.readAsStringSync(), contains('before close'));
      expect(ffi.releaseLogOwned(0), 5);
      AppLogger.closeLogSinkForDeletion();
      expect(ffi.releaseLogOwned(0), 0);
      first.deleteSync();
      AppLogger.info('after close must not recreate the deleted leaf');
      expect(first.existsSync(), isFalse);
      final next = File('${directory.path}/app_2.log');
      await AppLogger.openFreshLogSink(next.path);
      AppLogger.info('fresh owner');
      expect(next.readAsStringSync(), contains('=== App Log Started ==='));
      expect(next.readAsStringSync(), contains('fresh owner'));
      expect(ffi.releaseLogOwned(0), 5);
      AppLogger.closeLogSinkForDeletion();
      expect(ffi.releaseLogOwned(0), 0);
    },
  );

  test(
    'close invalidates an initialization still preparing its directory',
    () async {
      final file = File('${directory.path}/app_1.log');
      AppLogger.setLogPath(file.path);
      final pending = AppLogger.initialize();
      AppLogger.closeLogSinkForDeletion();
      await pending;
      expect(file.existsSync(), isFalse);
      expect(AppLogger.getLogPath(), isNull);
      expect(ffi.releaseLogOwned(0), 0);
      await AppLogger.openFreshLogSink('${directory.path}/app_2.log');
      expect(File('${directory.path}/app_2.log').existsSync(), isTrue);
      expect(file.existsSync(), isFalse);
    },
  );

  test(
    'concurrent initializations share one real native owner and stable path',
    () async {
      AppPaths.debugApplicationSupportOverride = directory.path;
      await Future.wait([AppLogger.initialize(), AppLogger.initialize()]);
      final path = AppLogger.getLogPath();
      expect(path, isNotNull);
      expect(File(path!).readAsStringSync(), '=== App Log Started ===\n');
      final files = (await AppPaths.logsDir)
          .listSync()
          .whereType<File>()
          .toList();
      expect(files.where((file) => file.path.endsWith('.log')).length, 1);
      expect(files.length, 2);
      expect(
        files
            .singleWhere(
              (file) => file.uri.pathSegments.last == '.app.log.sink-lock',
            )
            .lengthSync(),
        1024,
      );
    },
  );

  test(
    'the AppPaths startup path resolves OS aliases before a secure claim',
    () async {
      // Use the original path_provider-shaped path, including /var on Darwin.
      // The product's initializer, rather than the fixture, resolves the parent.
      AppPaths.debugApplicationSupportOverride = directory.path;
      final requestedDirectory = await AppPaths.logsDir;
      AppLogger.resetForTesting(production: true);
      await AppLogger.initialize();
      final actual = AppLogger.getLogPath();
      expect(actual, isNotNull);
      expect(
        File(actual!).readAsStringSync(),
        contains('=== App Log Started ==='),
      );
      expect(
        File(actual).parent.path,
        requestedDirectory.resolveSymbolicLinksSync(),
      );
      expect(File(actual).uri.pathSegments.last, matches(r'^app_[0-9]+\.log$'));
      expect(ffi.releaseLogOwned(0), 5);
      AppLogger.closeLogSinkForDeletion();
    },
  );
}
