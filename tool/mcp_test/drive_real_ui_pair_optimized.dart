// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

Future<void> _registerRealUiAccount(Inst inst, String nickname) async {
  await recoverStartupExceptions(inst);
  print('[${inst.name}] registering "$nickname" via real UI...');
  await inst.tapText('Register new account');
  await Future<void>.delayed(const Duration(seconds: 2));
  var nicknameCommitted = await inst.focusType(
    'register_page_nickname_field',
    nickname,
  );
  if (!nicknameCommitted) {
    nicknameCommitted = await inst.focusType(
      'register_page_nickname_field',
      nickname,
    );
  }
  if (!nicknameCommitted) {
    throw DriveError('[${inst.name}] nickname input did not commit');
  }
  await Future<void>.delayed(const Duration(milliseconds: 400));
  await inst.tapKey('register_page_register_button');
  await inst.foreground();
  await inst.waitState(
    (s) => s['sessionReady'] == true,
    timeoutSecs: 60,
    label: 'sessionReady',
  );
}

// _tapDesktopComposer lives next to the _composerX/_composerY constants it
// guards, in drive_real_ui_pair_message_call.dart: this file's key-first
// resolution was merged there with that file's mobile-shell tripwire, so the
// coordinate fallback can never silently tap off-screen on a phone.

Future<void> _setDesktopComposerText(
  Inst inst,
  String text, {
  required bool clearFirst,
}) async {
  final setText = await inst.l3('l3_composer_set_text', {'text': text});
  if (setText['ok'] == true) {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    return;
  }
  if (clearFirst) {
    await inst.osaClear();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  await inst.osaPaste(text);
  await Future<void>.delayed(const Duration(milliseconds: 800));
}

Future<bool?> _sendComposerViaProductionSeam(Inst inst, String text) async {
  final directSend = await inst.l3('l3_composer_send');
  if (directSend['ok'] != true) return null;
  for (var check = 0; check < 10; check++) {
    if (await _anyConversationLastMessageIs(inst, text)) return true;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return false;
}

Future<bool> _sendAndWait(
  Inst sender,
  Inst receiver,
  String receiverPubkey,
  String text, {
  int timeoutSecs = 60,
}) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    await openChat(sender, receiverPubkey);
    final targetConversation = 'c2c_${_pubkey(receiverPubkey)}';
    if (!await _chatSurfaceReady(sender, targetConversation, timeoutSecs: 10)) {
      print(
        '[pair] sendAndWait: target chat not ready '
        '(target=$targetConversation current=${await _currentConversationId(sender)})',
      );
      continue;
    }
    final sent = await sendComposerMessage(sender, text);
    final senderCommitted = await _waitC2cMessageText(
      sender,
      receiverPubkey,
      text,
      isSelf: true,
      timeoutSecs: timeoutSecs,
    );
    if (sent && senderCommitted) return true;
    print(
      '[pair] WARN sendAndWait retry for "$text" '
      '(attempt ${attempt + 1}/2 sent=$sent local=$senderCommitted '
      'senderConv=${await _currentConversationId(sender)} '
      'receiverLast=${await _lastMessage(receiver)})',
    );
    await sender.shot('/tmp/send_fail_${sender.name}_${attempt + 1}.png');
    await receiver.foreground();
    await receiver.shot('/tmp/send_fail_${receiver.name}_${attempt + 1}.png');
  }
  return false;
}

Future<int> runMessageBurst(Inst a, Inst b, String nickA, String nickB) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (!await areFriends(a, toxB) || !await areFriends(b, toxA)) {
    print('[pair] message_burst requires an existing friendship');
    return 1;
  }
  final bobPk = _pubkey(toxB);
  final alicePk = _pubkey(toxA);
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final aMsgs = [
    'RUIBURST-A1-$nonce',
    'RUIBURST-A2-$nonce',
    'RUIBURST-A3-$nonce',
  ];
  final bMsgs = [
    'RUIBURST-B1-$nonce',
    'RUIBURST-B2-$nonce',
    'RUIBURST-B3-$nonce',
  ];

  for (var i = 0; i < aMsgs.length; i++) {
    final aOk = await _sendAndWait(a, b, bobPk, aMsgs[i], timeoutSecs: 60);
    final bGot = await _waitC2cMessageText(
      b,
      alicePk,
      aMsgs[i],
      isSelf: false,
      timeoutSecs: 60,
    );
    if (!aOk || !bGot) {
      print('[pair] FAIL: burst A->$i did not converge');
      return 1;
    }
    final bOk = await _sendAndWait(b, a, alicePk, bMsgs[i], timeoutSecs: 60);
    final aGot = await _waitC2cMessageText(
      a,
      bobPk,
      bMsgs[i],
      isSelf: false,
      timeoutSecs: 60,
    );
    if (!bOk || !aGot) {
      print('[pair] FAIL: burst B->$i did not converge');
      return 1;
    }
  }

  await a.shot('/tmp/ui_message_burst_A.png');
  await b.foreground();
  await b.shot('/tmp/ui_message_burst_B.png');
  print('[pair] PASS: alternating real-UI burst converged both directions');
  return 0;
}

// Optimized real-UI bundles.
//
// These do NOT introduce new UI assertions. They compose already-registered
// sweeps inside one live pair launch so run phase can pay the expensive costs
// (launching Toxee, registering accounts, and establishing A<->B friendship)
// fewer times. The small domain campaigns remain the right tool for debugging a
// failure; these bundles are for broad regression coverage once the pieces are
// healthy.

// SKIP exit code, matching the three-state driver contract (0 PASS / 1 FAIL /
// 75 SKIP). Declared per-part to match the existing convention in this library
// (_realUiSkipExitCodeHighValue, _realUiSkipExitCodeP2Verify,
// _realUiSkipExitCodeForBatch8) — worth collapsing into one shared constant,
// but that is a separate cleanup across four files.
const _realUiSkipExitCodeOptimized = 75;

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
  final settingsStep = a.isMobileShell
      ? _OptimizedStep(
          'sweep_ios_settings_main',
          () => runIosSettingsMainSweep(a, nickA),
        )
      // No `peer` here on purpose: this bundle launches ONE app, and
          // settings_prelogin_bootstrap_node_test needs a second LIVE Tox node
          // to prove the "reachable" half of its differential. runSettingsSweep2
          // therefore EXCLUDES that case (with a printed reason) instead of
          // pretending it passed; it stays a hard gate in sweep_settings2.
      : _OptimizedStep('sweep_settings2', () => runSettingsSweep2(a, nickA));
  return _runOptimizedSequence('sweep_single_app_optimized', [
    settingsStep,
    _OptimizedStep('sweep_profile', () => runProfileSweep(a, nickA)),
    _OptimizedStep('sweep_login', () => runLoginSweep(a, nickA)),
    _OptimizedStep('sweep_p1_extra', () => runP1ExtraSweep(a, nickA)),
    _OptimizedStep(
      'sweep_app_entry_extra',
      () => runAppEntryExtraSweep(a, nickA),
    ),
    _OptimizedStep(
      'sweep_account_conf_extra',
      () => runAccountConfExtraSweep(a, nickA),
    ),
    _OptimizedStep(
      'sweep_account_deep_extra',
      () => runAccountDeepExtraSweep(a, nickA),
    ),
    // Keyed-gaps batch #2 (register page / IRC app / add-group type selector).
    // Single-instance, required=no-friend / result=no-friend, and its own
    // end-clean relogins + resets the local IRC prefs — so it composes here
    // without a reset. Placed AFTER app_entry_extra (they share the IRC
    // Applications surface, and app_entry_extra's IRC cases already reset it)
    // and BEFORE the destructive p1_single tail.
    _OptimizedStep('sweep_keyed_gaps', () => runKeyedGapsSweep(a, nickA)),
    // Keyed-gaps batch #4, login half (the LoginPage delete-account CONFIRM).
    // Single-instance, required=no-friend / result=no-friend: it provisions a
    // throwaway account, deletes it, and quick-logs back into the primary in a
    // `finally`. Placed immediately BEFORE the p1_single tail because it is the
    // first account-destructive step — everything above it still expects a
    // pristine account list.
    _OptimizedStep(
      'sweep_keyed_gaps4_login',
      () => runKeyedGaps4LoginSweep(a, nickA),
    ),
    // p1_single runs LAST: its `account_delete_full_flow` is DESTRUCTIVE (it
    // deletes accounts across multiple logout/login cycles) and poisons the
    // shared-launch state for any sweep that runs after it (the inter-sweep
    // recovery then fails with "did not recover to HomePage" / a register-flow
    // mismatch and cascades every later sweep). Per the campaign's reuse-startup
    // policy, destructive cases run last so nothing downstream is poisoned.
    _OptimizedStep('sweep_p1_single', () => runP1SingleSweep(a, nickA)),
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
      'sweep_group_mention',
      () => runGroupMentionSweep(a, b, nickA, nickB),
    ),
    _OptimizedStep(
      'sweep_group_conf_member_extra',
      () => runGroupConfMemberExtraSweep(a, b, nickA, nickB),
    ),
    _OptimizedStep(
      'sweep_group_conf_deep_extra',
      () => runGroupConfDeepExtraSweep(a, b, nickA, nickB),
    ),
    // Keyed-gaps batch #3: same shape as sweep_group_conf_member_extra
    // (required=no-friend / result=friends, establishes its own throwaway group
    // and cleans it up), so it rides this bundle instead of a launch of its own.
    _OptimizedStep(
      'sweep_keyed_gaps3',
      () => runKeyedGaps3Sweep(a, b, nickA, nickB),
    ),
    // Keyed-gaps batch #4, two-process half: identical state contract to batch
    // #3 (required=no-friend / result=friends, own handshake, own throwaway
    // group cleaned up by the shared helper), so it chains here with no reset
    // and no extra launch.
    _OptimizedStep(
      'sweep_keyed_gaps4',
      () => runKeyedGaps4Sweep(a, b, nickA, nickB),
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
  var skipped = 0;
  final results = <String, String>{};

  for (final step in steps) {
    print('[sweep] $label START ${step.name}');
    try {
      final code = await step.run();
      if (code == 0) {
        passed++;
        results[step.name] = 'PASS';
        print('[sweep] $label PASS ${step.name}');
      } else if (code == _realUiSkipExitCodeOptimized) {
        // A child sweep that could not construct its environment reports SKIP
        // (75), the same three-state contract the individual drivers use.
        // Counting it as FAIL(75) here would turn an honest "not runnable"
        // into a red build; counting it as PASS would hide it. Track it.
        skipped++;
        results[step.name] = 'SKIP';
        print('[sweep] $label SKIP ${step.name}');
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
    '[sweep] $label summary: passed=$passed failed=$failed skipped=$skipped '
    'results=$results',
  );
  if (failed > 0) return 1;
  // Every child skipped => this bundle asserted nothing. Propagate SKIP rather
  // than reporting a green run.
  if (passed == 0 && skipped > 0) return _realUiSkipExitCodeOptimized;
  return 0;
}

final class _OptimizedStep {
  const _OptimizedStep(this.name, this.run);

  final String name;
  final Future<int> Function() run;
}
