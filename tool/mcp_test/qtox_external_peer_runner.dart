// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'qtox_external_peer_harness.dart';
import 'qtox_external_peer_options.dart';

Future<void> main(List<String> args) async {
  exitCode = await _run(args);
}

Future<int> _run(List<String> args) async {
  late final QtoxRunnerOptions options;
  try {
    options = QtoxRunnerOptions.parse(args);
  } on FormatException catch (error) {
    stderr.writeln('qtox_external_peer_runner: ${error.message}');
    stderr.writeln(qtoxExternalPeerUsage);
    return 64;
  } on QtoxHarnessException catch (error) {
    stderr.writeln('qtox_external_peer_runner: ${error.message}');
    stderr.writeln(qtoxExternalPeerUsage);
    return 64;
  }
  if (options.showHelp) {
    print(qtoxExternalPeerUsage.trim());
    return 0;
  }
  if (options.error != null) {
    stderr.writeln('qtox_external_peer_runner: ${options.error}');
    stderr.writeln(qtoxExternalPeerUsage);
    return 64;
  }

  try {
    final repositoryRoot = _findRepositoryRoot();
    final layout = QtoxScratchLayout.fromRepository(
      repositoryRoot: repositoryRoot,
      scratchRoot: options.scratchRoot,
    );
    final artifact = options.artifact!;
    final bootstrap = QtoxBootstrapConfig(
      publicKey: options.bootstrapPublicKey!,
      udpPort: options.bootstrapPort,
      tcpPorts: <int>[options.bootstrapTcpPort],
    );
    final harness = QtoxExternalPeerHarness(
      layout: layout,
      artifact: artifact,
      bootstrap: bootstrap,
      profileName: options.profileName,
    );

    switch (options.action) {
      case QtoxRunnerAction.plan:
        print(harness.plan.toPrettyJson());
        return 0;
      case QtoxRunnerAction.prepare:
        await harness.prepare();
        _printStatus('prepared', harness);
        return 0;
      case QtoxRunnerAction.launch:
        final session = await harness.launch();
        _printStatus('running', harness, pid: session.pid);
        final subscriptions = <StreamSubscription<ProcessSignal>>[];
        if (!Platform.isWindows) {
          for (final signal in <ProcessSignal>[
            ProcessSignal.sigint,
            ProcessSignal.sigterm,
          ]) {
            subscriptions.add(
              signal.watch().listen((_) {
                unawaited(harness.teardown());
              }),
            );
          }
        }
        final result = await session.done;
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        return result;
      case QtoxRunnerAction.screenshot:
        final path = await harness.signalScreenshot();
        print(
          jsonEncode(<String, Object>{
            'status': 'screenshot-captured',
            'path': path,
          }),
        );
        return 0;
      case QtoxRunnerAction.teardown:
        final stopped = await harness.teardown();
        _printStatus(stopped ? 'stopped' : 'already-stopped', harness);
        return 0;
    }
  } on QtoxHarnessException catch (error) {
    stderr.writeln('qtox_external_peer_runner: ${error.message}');
    return 1;
  } on FileSystemException catch (error) {
    stderr.writeln(
      'qtox_external_peer_runner: filesystem operation failed'
      '${error.path == null ? '' : ' at ${error.path}'}',
    );
    return 1;
  } on ProcessException catch (error) {
    stderr.writeln(
      'qtox_external_peer_runner: process operation failed: ${error.executable}',
    );
    return 1;
  }
}

void _printStatus(String status, QtoxExternalPeerHarness harness, {int? pid}) {
  print(
    jsonEncode(<String, Object>{
      'status': status,
      if (pid != null) 'pid': pid,
      'scratchRoot': harness.layout.scratchRoot,
      'instanceMetadata': harness.layout.instanceMetadataPath,
      'stderr': harness.layout.stderrPath,
      'qtoxLog': harness.plan.qtoxLogPath,
      'sigusr1Screenshot': harness.layout.screenshotPath,
    }),
  );
}

String _findRepositoryRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    if (File('${directory.path}/pubspec.yaml').existsSync() &&
        Directory('${directory.path}/tool/mcp_test').existsSync()) {
      return directory.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw QtoxHarnessException(
        'run this command from inside the toxee repository',
      );
    }
    directory = parent;
  }
}
