// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Optimized real-UI bundles.
//
// These do NOT introduce new UI assertions. They compose already-registered
// sweeps inside one live pair launch so run phase can pay the expensive costs
// (launching Toxee, registering accounts, and establishing A<->B friendship)
// fewer times. The small domain campaigns remain the right tool for debugging a
// failure; these bundles are for broad regression coverage once the pieces are
// healthy.

const _optimizedSweepScenarios = {
  'sweep_single_app_optimized',
  'sweep_c2c_optimized',
  'sweep_friendship_optimized',
  'sweep_optimized_current',
};

bool _isOptimizedSweepScenario(String scenario) =>
    _optimizedSweepScenarios.contains(scenario);

Future<int> runOptimizedSweep(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario,
) async {
  return switch (scenario) {
    'sweep_single_app_optimized' => await runSingleAppOptimizedSweep(a, nickA),
    'sweep_c2c_optimized' => await runC2cOptimizedSweep(a, b, nickA, nickB),
    'sweep_friendship_optimized' => await runFriendshipOptimizedSweep(
      a,
      b,
      nickA,
      nickB,
    ),
    'sweep_optimized_current' => await runCurrentOptimizedSweep(
      a,
      b,
      nickA,
      nickB,
    ),
    _ => throw ArgumentError('unsupported optimized sweep: $scenario'),
  };
}

Future<int> runSingleAppOptimizedSweep(Inst a, String nickA) {
  return _runOptimizedSequence('sweep_single_app_optimized', [
    _OptimizedStep('sweep_settings2', () => runSettingsSweep2(a, nickA)),
    _OptimizedStep('sweep_profile', () => runProfileSweep(a, nickA)),
    _OptimizedStep('sweep_login', () => runLoginSweep(a, nickA)),
    _OptimizedStep('sweep_p1_single', () => runP1SingleSweep(a, nickA)),
    _OptimizedStep('sweep_p1_extra', () => runP1ExtraSweep(a, nickA)),
    _OptimizedStep(
      'sweep_account_conf_extra',
      () => runAccountConfExtraSweep(a, nickA),
    ),
    _OptimizedStep(
      'sweep_account_deep_extra',
      () => runAccountDeepExtraSweep(a, nickA),
    ),
  ]);
}

Future<int> runC2cOptimizedSweep(Inst a, Inst b, String nickA, String nickB) {
  return _runOptimizedSequence('sweep_c2c_optimized', [
    _OptimizedStep('sweep_conv', () => runConvSweep(a, b, nickA, nickB)),
    _OptimizedStep('sweep_chat', () => runChatSweep(a, b, nickA, nickB)),
    _OptimizedStep(
      'sweep_c2c_extra',
      () => runC2cExtraSweep(a, b, nickA, nickB),
    ),
    _OptimizedStep(
      'sweep_c2c_deep_extra',
      () => runC2cDeepExtraSweep(a, b, nickA, nickB),
    ),
  ]);
}

Future<int> runFriendshipOptimizedSweep(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) {
  return _runOptimizedSequence('sweep_friendship_optimized', [
    _OptimizedStep(
      'sweep_c2c_optimized',
      () => runC2cOptimizedSweep(a, b, nickA, nickB),
    ),
    _OptimizedStep('sweep_p1_chat', () => runP1ChatSweep(a, b, nickA, nickB)),
    _OptimizedStep('sweep_p2_reply', () => runP2ReplySweep(a, b, nickA, nickB)),
    _OptimizedStep(
      'sweep_p2_verify',
      () => runP2VerifySweep(a, b, nickA, nickB),
    ),
    _OptimizedStep(
      'sweep_p3_writable',
      () => runP3WritableSweep(a, b, nickA, nickB),
    ),
    _OptimizedStep('sweep_group2', () => runGroup2Sweep(a, b, nickA, nickB)),
    _OptimizedStep(
      'sweep_group_conf_member_extra',
      () => runGroupConfMemberExtraSweep(a, b, nickA, nickB),
    ),
    _OptimizedStep(
      'sweep_group_conf_deep_extra',
      () => runGroupConfDeepExtraSweep(a, b, nickA, nickB),
    ),
    _OptimizedStep(
      'sweep_calls_misc',
      () => runCallsMiscSweep(a, b, nickA, nickB),
    ),
  ]);
}

Future<int> runCurrentOptimizedSweep(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) {
  return _runOptimizedSequence('sweep_optimized_current', [
    _OptimizedStep(
      'sweep_single_app_optimized',
      () => runSingleAppOptimizedSweep(a, nickA),
    ),
    _OptimizedStep(
      'sweep_friendship_optimized',
      () => runFriendshipOptimizedSweep(a, b, nickA, nickB),
    ),
  ]);
}

Future<int> _runOptimizedSequence(
  String label,
  List<_OptimizedStep> steps,
) async {
  var passed = 0;
  var failed = 0;
  final results = <String, String>{};

  for (final step in steps) {
    print('[sweep] $label START ${step.name}');
    try {
      final code = await step.run();
      if (code == 0) {
        passed++;
        results[step.name] = 'PASS';
        print('[sweep] $label PASS ${step.name}');
      } else {
        failed++;
        results[step.name] = 'FAIL($code)';
        print('[sweep] $label FAIL ${step.name} exit=$code');
      }
    } on PermissionBlockedError {
      rethrow;
    } on Object catch (e, st) {
      failed++;
      results[step.name] = 'EXCEPTION';
      print('[sweep] $label EXCEPTION ${step.name}: $e');
      print(st);
    }
  }

  print(
    '[sweep] $label summary: passed=$passed failed=$failed results=$results',
  );
  return failed == 0 ? 0 : 1;
}

final class _OptimizedStep {
  const _OptimizedStep(this.name, this.run);

  final String name;
  final Future<int> Function() run;
}
