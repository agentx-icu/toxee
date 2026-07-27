import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:toxee/util/account_export/atomic_file_write.dart';

void main() {
  late Directory testDirectory;

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp(
      'toxee_atomic_file_write_',
    );
  });

  tearDown(() async {
    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
  });

  test(
    'concurrent writes publish one whole payload and leave no stages',
    () async {
      final target = File(p.join(testDirectory.path, 'concurrent.bin'));
      final payloads = List<List<int>>.generate(
        12,
        (index) => List<int>.filled(128 * 1024, index + 1),
      );

      await Future.wait(
        payloads.map(
          (payload) =>
              writeBytesAtomically(target, payload, tempSuffix: '.stage'),
        ),
      );

      final result = await target.readAsBytes();
      expect(
        payloads.any((payload) => _bytesEqual(payload, result)),
        isTrue,
        reason: 'the destination must contain one complete writer payload',
      );
      expect(await _stageSiblings(target, '.stage'), isEmpty);
    },
  );

  test(
    'publisher failure preserves destination and removes its stage',
    () async {
      final target = File(p.join(testDirectory.path, 'publish_failure.bin'));
      const oldBytes = <int>[1, 2, 3, 4];
      const replacementBytes = <int>[8, 7, 6, 5];
      const foreignStageBytes = <int>[42];
      await target.writeAsBytes(oldBytes, flush: true);
      final foreignStage = File('${target.path}.stage.foreign');
      await foreignStage.writeAsBytes(foreignStageBytes, flush: true);
      File? publishedStage;

      await expectLater(
        writeBytesAtomically(
          target,
          replacementBytes,
          tempSuffix: '.stage',
          publishForTesting: (stage, destination) async {
            publishedStage = stage;
            expect(destination.path, target.path);
            expect(await stage.readAsBytes(), replacementBytes);
            throw StateError('injected publisher failure');
          },
        ),
        throwsStateError,
      );

      expect(await target.readAsBytes(), oldBytes);
      expect(publishedStage, isNotNull);
      expect(await publishedStage!.exists(), isFalse);
      expect(await foreignStage.readAsBytes(), foreignStageBytes);
      await foreignStage.delete();
      expect(await _stageSiblings(target, '.stage'), isEmpty);
    },
  );

  test('exclusive reservation retries a colliding stage path', () async {
    final target = File(p.join(testDirectory.path, 'collision.bin'));
    const payload = <int>[4, 5, 6, 7];
    const collisionBytes = <int>[99];
    const reservationId = 4242;
    final collision = File('${target.path}.stage.$pid.$reservationId.0');
    await collision.writeAsBytes(collisionBytes, flush: true);
    String? publishedStagePath;

    await writeBytesAtomically(
      target,
      payload,
      tempSuffix: '.stage',
      reservationIdForTesting: reservationId,
      publishForTesting: (stage, destination) async {
        publishedStagePath = stage.path;
        await stage.rename(destination.path);
      },
    );

    expect(await target.readAsBytes(), payload);
    expect(publishedStagePath, '${target.path}.stage.$pid.$reservationId.1');
    expect(
      await collision.readAsBytes(),
      collisionBytes,
      reason:
          'a stage reserved by another writer must not be reused or removed',
    );
    await collision.delete();
    expect(await _stageSiblings(target, '.stage'), isEmpty);
  });
}

Future<List<FileSystemEntity>> _stageSiblings(File target, String tempSuffix) {
  final prefix = '${target.path}$tempSuffix.';
  return target.parent
      .list(followLinks: false)
      .where((entity) => entity.path.startsWith(prefix))
      .toList();
}

bool _bytesEqual(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}
