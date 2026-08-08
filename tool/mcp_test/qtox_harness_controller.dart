import 'dart:io';

import 'qtox_harness_common.dart';
import 'qtox_harness_config.dart';
import 'qtox_harness_plan.dart';
import 'qtox_harness_prepare.dart';
import 'qtox_harness_process.dart';
import 'qtox_harness_scratch.dart';

class QtoxExternalPeerHarness {
  QtoxExternalPeerHarness({
    required this.layout,
    required this.artifact,
    required this.bootstrap,
    this.profileName,
  }) {
    if (profileName != null &&
        !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(profileName!)) {
      throw QtoxHarnessException('unsafe profile name: $profileName');
    }
  }

  final QtoxScratchLayout layout;
  final QtoxArtifactSelection artifact;
  final QtoxBootstrapConfig bootstrap;
  final String? profileName;

  QtoxHarnessPlan get plan => QtoxHarnessPlan(
    layout: layout,
    artifact: artifact,
    bootstrap: bootstrap,
    profileName: profileName,
  );

  Future<void> prepare() async {
    await _preparer.prepare(_process.teardown);
  }

  Future<QtoxPeerSession> launch() async {
    final handle = await _process.launch();
    return QtoxPeerSession._(
      harness: this,
      process: handle.process,
      stderrSink: handle.stderrSink,
    );
  }

  Future<String> signalScreenshot({
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _process.signalScreenshot(timeout: timeout);
  }

  Future<bool> teardown({Duration grace = const Duration(seconds: 5)}) {
    return _process.teardown(grace: grace);
  }

  Future<void> recordStopped({required int exitCode}) {
    return _process.recordStopped(exitCode: exitCode);
  }

  QtoxScratchGuard get _guard => QtoxScratchGuard(layout);

  QtoxMetadataStore get _metadata => QtoxMetadataStore(
    layout: layout,
    guard: _guard,
    qtoxLogPath: plan.qtoxLogPath,
  );

  QtoxHarnessPreparer get _preparer => QtoxHarnessPreparer(
    layout: layout,
    artifact: artifact,
    bootstrap: bootstrap,
    plan: plan,
    guard: _guard,
    metadata: _metadata,
  );

  QtoxProcessController get _process => QtoxProcessController(
    layout: layout,
    plan: plan,
    profileName: profileName,
    guard: _guard,
    metadata: _metadata,
    preparer: _preparer,
  );
}

class QtoxPeerSession {
  QtoxPeerSession._({
    required this.harness,
    required this.process,
    required IOSink stderrSink,
  }) {
    final stdoutDone = process.stdout.drain<void>();
    final stderrDone = process.stderr.pipe(stderrSink);
    done = _observe(stdoutDone: stdoutDone, stderrDone: stderrDone);
  }

  final QtoxExternalPeerHarness harness;
  final Process process;
  late final Future<int> done;

  int get pid => process.pid;

  Future<int> _observe({
    required Future<void> stdoutDone,
    required Future<void> stderrDone,
  }) async {
    final code = await process.exitCode;
    await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
    await harness.recordStopped(exitCode: code);
    return code;
  }
}
