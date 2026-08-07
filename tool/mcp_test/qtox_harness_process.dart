import 'dart:io';

import 'package:path/path.dart' as p;

import 'qtox_harness_common.dart';
import 'qtox_harness_plan.dart';
import 'qtox_harness_prepare.dart';
import 'qtox_harness_scratch.dart';

class QtoxProcessHandle {
  const QtoxProcessHandle({required this.process, required this.stderrSink});

  final Process process;
  final IOSink stderrSink;
}

class QtoxProcessController {
  const QtoxProcessController({
    required this.layout,
    required this.plan,
    required this.profileName,
    required this.guard,
    required this.metadata,
    required this.preparer,
  });

  final QtoxScratchLayout layout;
  final QtoxHarnessPlan plan;
  final String? profileName;
  final QtoxScratchGuard guard;
  final QtoxMetadataStore metadata;
  final QtoxHarnessPreparer preparer;

  Future<QtoxProcessHandle> launch() async {
    guard.validateBoundary();
    await guard.requireOwnerMarker();
    await preparer.requirePreparedArtifact();
    _validateLiveWritablePaths();
    final existing = await metadata.read();
    if (existing['phase'] == 'running') {
      throw QtoxHarnessException(
        'scratch root already records a running qTox instance',
      );
    }
    if (profileName != null) {
      final profilePath = layout.guardPath(
        p.join(layout.portableRoot, '$profileName.tox'),
      );
      if (!File(profilePath).existsSync()) {
        throw QtoxHarnessException(
          'named scratch profile does not exist: $profilePath',
        );
      }
    }

    final stderrSink = File(layout.stderrPath).openWrite(mode: FileMode.write);
    late final Process process;
    try {
      process = await Process.start(
        plan.executablePath,
        plan.arguments,
        workingDirectory: plan.workingDirectory,
        environment: plan.environment,
        includeParentEnvironment: false,
        runInShell: false,
      );
    } catch (_) {
      await stderrSink.close();
      rethrow;
    }
    final identity = await _processIdentity(process.pid);
    if (identity == null) {
      process.kill(ProcessSignal.sigterm);
      await stderrSink.close();
      throw QtoxHarnessException(
        'could not capture process identity for pid ${process.pid}',
      );
    }
    await metadata.write(
      phase: 'running',
      pid: process.pid,
      processIdentity: identity,
    );
    return QtoxProcessHandle(process: process, stderrSink: stderrSink);
  }

  Future<String> signalScreenshot({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (Platform.isWindows) {
      throw QtoxHarnessException('SIGUSR1 screenshots require a POSIX host');
    }
    guard.validateBoundary();
    await guard.requireOwnerMarker();
    guard.rejectSymlinksTo(layout.screenshotPath);
    final process = await _verifiedRecordedProcess();
    final screenshot = File(layout.screenshotPath);
    if (screenshot.existsSync()) {
      await screenshot.delete();
    }
    if (!Process.killPid(process.pid, ProcessSignal.sigusr1)) {
      throw QtoxHarnessException('failed to send SIGUSR1 to qTox');
    }

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (screenshot.existsSync() && screenshot.lengthSync() > 0) {
        await metadata.write(
          phase: 'running',
          pid: process.pid,
          processIdentity: process.identity,
        );
        return screenshot.path;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw QtoxHarnessException(
      'qTox did not write the expected SIGUSR1 screenshot',
    );
  }

  Future<bool> teardown({Duration grace = const Duration(seconds: 5)}) async {
    guard.validateBoundary();
    if (!Directory(layout.scratchRoot).existsSync()) {
      return false;
    }
    await guard.requireOwnerMarker();
    final current = await metadata.read();
    if (current['phase'] != 'running') {
      return false;
    }
    final recorded = _recordedProcess(current);
    final currentIdentity = await _processIdentity(recorded.pid);
    if (currentIdentity == null) {
      await metadata.write(phase: 'stopped');
      return false;
    }
    _requireMatchingIdentity(recorded, currentIdentity);

    Process.killPid(recorded.pid, ProcessSignal.sigterm);
    final deadline = DateTime.now().add(grace);
    while (DateTime.now().isBefore(deadline)) {
      if (await _processIdentity(recorded.pid) == null) {
        await metadata.write(phase: 'stopped');
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    Process.killPid(recorded.pid, ProcessSignal.sigkill);
    await metadata.write(phase: 'stopped');
    return true;
  }

  Future<void> recordStopped({required int exitCode}) async {
    await metadata.write(phase: 'stopped', exitCode: exitCode);
  }

  Future<_RecordedProcess> _verifiedRecordedProcess() async {
    final recorded = _recordedProcess(await metadata.read());
    final currentIdentity = await _processIdentity(recorded.pid);
    if (currentIdentity == null) {
      throw QtoxHarnessException('recorded qTox process is not running');
    }
    _requireMatchingIdentity(recorded, currentIdentity);
    return recorded;
  }

  _RecordedProcess _recordedProcess(Map<String, dynamic> value) {
    final pid = value['pid'];
    final identity = value['processIdentity'];
    if (pid is! int || pid <= 1 || identity is! String || identity.isEmpty) {
      throw QtoxHarnessException('running process metadata is incomplete');
    }
    return _RecordedProcess(pid: pid, identity: identity);
  }

  void _requireMatchingIdentity(
    _RecordedProcess recorded,
    String currentIdentity,
  ) {
    if (currentIdentity != recorded.identity ||
        !currentIdentity.contains(plan.executablePath)) {
      throw QtoxHarnessException(
        'recorded pid identity does not match the staged qTox executable',
      );
    }
  }

  void _validateLiveWritablePaths() {
    for (final path in <String>[
      layout.homeRoot,
      layout.picturesRoot,
      layout.tempRoot,
      layout.xdgRoot,
      layout.portableRoot,
      layout.artifactsRoot,
      layout.stderrPath,
      plan.qtoxLogPath,
      layout.screenshotPath,
      layout.instanceMetadataPath,
    ]) {
      guard.rejectSymlinksTo(path);
    }
  }

  static Future<String?> _processIdentity(int pid) async {
    final result = await Process.run('/bin/ps', <String>[
      '-p',
      '$pid',
      '-o',
      'lstart=,command=',
    ]);
    if (result.exitCode != 0) {
      return null;
    }
    final output = (result.stdout as String).trim();
    return output.isEmpty ? null : output;
  }
}

class _RecordedProcess {
  const _RecordedProcess({required this.pid, required this.identity});

  final int pid;
  final String identity;
}
