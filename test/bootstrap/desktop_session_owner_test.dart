import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'processes sharing a store yield and activate, crash releases ownership',
    () async {
      final root = await Directory.systemTemp.createTemp('toxee-owner-');
      Process? first;
      Process? second;
      Process? replacement;
      addTearDown(() async {
        for (final process in [first, second, replacement]) {
          if (process == null) continue;
          process.kill();
          await process.exitCode;
        }
        await root.delete(recursive: true);
      });
      Future<Process> launch() => Process.start('dart', [
        'test/bootstrap/desktop_session_owner_process.dart',
        root.path,
      ]);
      first = await launch();
      final lines = first.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();
      expect(await lines.first.timeout(const Duration(seconds: 10)), 'owner');
      final activation = lines.first;
      expect(jsonDecode(await File('${root.path}/.session-owner.json').readAsString())['port'], isA<int>());
      second = await launch();
      expect(await second.stdout.transform(utf8.decoder).join(), 'yielded\n');
      expect(await activation, 'activated');
      first.kill(ProcessSignal.sigkill);
      await first.exitCode;
      replacement = await launch();
      expect(
        await replacement.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
        'owner',
      );
    },
  );
}
