// L3 scenario runner (improvement plan items 5/7/8 — codex-vetted 2026-05-29;
// suite taxonomy + ordering/filtering — TEST_CASE_ORGANIZATION_PLAN §3.2,
// 2026-06-03).
//
// Runs declarative JSON scenarios against ONE already-running debug toxee
// instance (launched via `MCP_BINDING=marionette ./run_toxee.sh`, which injects
// TOXEE_L3_TEST=true so the `ext.mcp.toolkit.l3_*` debug tools are registered).
// Drives deterministically through those tools (no fragile synthetic gestures)
// and asserts on the JSON `l3_dump_state` read model — not log-grep, not UI
// scraping. One app, many scenarios, per-scenario reset → big test-time win.
//
//   dart run tool/mcp_test/run_l3_scenarios.dart <ws_uri> [scenarioFileOrDir] \
//       [--echo] [--allow-skip] [--no-fail-fast] \
//       [--class=...] [--suite=...] [--id=<glob>]
//   dart run tool/mcp_test/run_l3_scenarios.dart [scenarioFileOrDir] --list
//   dart run tool/mcp_test/run_l3_scenarios.dart [scenarioFileOrDir] --validate-only
//
//   <ws_uri>           e.g. ws://127.0.0.1:PORT/ws  (cat build/vm_service_uri.txt)
//                      REQUIRED except for --list / --validate-only, which never
//                      connect to a VM (so the ws_uri positional is waived there).
//   scenarioFileOrDir  default: tool/mcp_test/scenarios/
//   --echo             echo peer is running (enables requiresEchoPeer scenarios)
//   --allow-skip       a SKIP no longer forces exit 2 (see exit codes below)
//
// Execution ordering (replaces the old alphabetical-filename sort):
//   sort key = (partition, suiteRank, order, filename)
//     partition: 0 = l3-gate (hermetic), 1 = l3-gate-echo (requiresEchoPeer),
//                2 = l3-ui-single (uiDriven)  — derived from JSON flags:
//                uiDriven ? 2 : (requiresEchoPeer ? 1 : 0)
//     suiteRank: session=0, settings=1, c2c=2, group=3
//     order:     the optional "order" int (default 50), within-suite rank
//     filename:  final tiebreak (the scenario file's basename)
//
// session-suite scenarios are the PREFLIGHT: they are included in EVERY --class
// selection (never partition-filtered out) and, by default, a FAIL of any
// session-suite scenario aborts the run immediately (fail-fast) — everything
// downstream is noise once the session is broken. --no-fail-fast disables that.
// session scenarios are excluded only by an explicit --suite / --id filter.
//
// Filtering flags:
//   --class=<l3-gate|l3-gate-echo|l3-ui-single>[,...]
//       keep only scenarios whose derived class is in the list (PLUS every
//       session-suite scenario — the preflight is always present). Required for a
//       green standalone run of one partition: echo scenarios SKIP without
//       --echo and any SKIP exits 2 (unless --allow-skip), so --class=l3-gate
//       selects ONLY the hermetic partition and the run exits 0 with no skips.
//   --suite=<session|settings|c2c|group>[,...]
//       keep only scenarios in the listed suites (EXPLICIT — this DOES exclude
//       session unless "session" is named).
//   --id=<glob>   keep only scenarios whose id matches the glob (`*` wildcard);
//                 also EXPLICIT, so it can exclude session scenarios.
//   --skip=<id>[,...]  report the named scenario(s) as SKIP instead of running
//                 them (case-insensitive). For a known env-class gap the caller
//                 owns — e.g. L3-self-id asserts the on-disk echo_seeded fixture
//                 account's exact toxId, unsatisfiable on a register-seeded host.
//                 An EXPLICIT --skip does NOT trip the exit-2 gate (only implicit
//                 echo-dependent skips do).
//
// Inspection modes (NO VM connection, no ws_uri needed):
//   --list           print the resolved execution table (position, id, filename,
//                    suite, class, order, echo?, uiDriven?, blocking?, feature)
//                    after applying the same load/sort/filter pipeline; exit 0.
//   --validate-only  validate ALL scenario JSONs (unique non-empty id; suite
//                    present and in the enum; order int when present; feature an
//                    array of "S<digits>" strings when present; uiDriven bool
//                    when present); print every violation; exit non-zero if any.
//
// Exit codes: 0 all run scenarios passed; 1 a scenario FAILED or a load/suite
// error (a typo must not shrink coverage while exiting 0) or any --validate-only
// violation; 2 a SKIP without --allow-skip (so CI can't false-green by dropping
// echo-dependent scenarios); 64 usage; 65 no scenarios found; 70 VM connect
// failed; 71 L3 debug tools not registered.
//
// Scenario JSON (tool/mcp_test/scenarios/*.json):
//   { id, description, suite, order?, feature?, uiDriven?,
//     requiresEchoPeer?, nonBlocking?, target?, reset?,
//     steps:[ {action, ...} ], assertions:[ {type, ...} ],
//     teardown?:[ {action, ...} ] }   // runs after assertions + on failure;
//                                     // errors swallowed (best-effort self-clean,
//                                     // e.g. leave_group which wipes group history)
//   suite     REQUIRED logical grouping, one of session|settings|c2c|group. A
//             missing/unknown suite is a hard LOAD error (mirrors missing "id":
//             the run aborts and lists every offending file — exit 1), so no
//             scenario silently escapes the taxonomy.
//   order     OPTIONAL within-suite rank (int, default 50). Lower runs earlier.
//   feature   OPTIONAL S-number traceability, array of "S<digits>" (e.g. ["S34"]).
//   uiDriven  OPTIONAL bool (default false); true marks the *_tap real-widget
//             scenarios → derived class l3-ui-single (partition 2).
//   actions:    send_text{text,userId?} | clear_history{userId?} |
//               wait_for{predicate:"message_exists",text,isSelf?,conv?,timeoutSecs?}
//                 | wait_for{predicate:"message_count_at_least",text,isSelf?,count,conv?,timeoutSecs?}
//                 | wait_for{predicate:"unread_at_least",count?,timeoutSecs?}
//                 | wait_for{predicate:"state_contains",field,contains,timeoutSecs?}
//                 | wait_for{predicate:"state_contains_item"|"state_not_contains_item",
//                     field,containsItem|notContainsItem,timeoutSecs?} |
//               delay{ms} | tap{key|text} | long_press{key|text} |
//               enter_text{key,text} |
//               warmup{text?,timeoutSecs?} | mark_read{userId?} |
//               set_setting{key,value} (autoAcceptFriends|autoAcceptGroupInvites) |
//               irc_set_state{reset?,installed?,server?,port?,useSasl?,channels?,localAddOverride?} |
//               irc_add_channel_local{channel,groupId?,saveAs?} |
//               irc_remove_channel_local{channel,groupId?} |
//               invoke_action{messageAction:"delete"|"copy", msgId? | text+isSelf?} |
//               create_group{name?,type?(public|private),saveAs?} |
//               send_group_text{groupId,text} | leave_group{groupId}
//   assertions: state{field,equals|contains|notContains|containsItem|notContainsItem,conv?}
//                 (containsItem/notContainsItem = EXACT list-element membership —
//                  use for id lists like knownGroups/pinnedConversations so a
//                  prefix sibling, e.g. tox_1 ⊂ tox_10, can't false-match) |
//               message_exists{text,isSelf?,conv?} |
//               message_count_text{text,isSelf?,equals|atLeast,conv?}  (equals:0 = absent) |
//               message_order{texts:[...],isSelf?,conv?} |
//               message_field_contains{text,isSelf?,field,contains,conv?}
//   conv?:      override the conversation a message_*/state read targets — set to
//               "group_{{gid}}" for group-history assertions (default: `target`).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

const _usage =
    'usage: run_l3_scenarios.dart <ws_uri> [fileOrDir] [--echo] [--allow-skip]\n'
    '         [--no-fail-fast] [--class=...] [--suite=...] [--id=<glob>] [--skip=<id,...>]\n'
    '       run_l3_scenarios.dart [fileOrDir] --list        (no VM connection)\n'
    '       run_l3_scenarios.dart [fileOrDir] --validate-only (no VM connection)';

/// Multi-value flags accept either repeated `--flag=a --flag=b` or a single
/// comma list `--flag=a,b`. Returns the lowercased, trimmed, de-duped values.
Set<String> _multiFlag(List<String> args, String name) {
  final out = <String>{};
  final prefix = '--$name=';
  for (final a in args) {
    if (a.startsWith(prefix)) {
      for (final v in a.substring(prefix.length).split(',')) {
        final t = v.trim().toLowerCase();
        if (t.isNotEmpty) out.add(t);
      }
    }
  }
  return out;
}

String? _singleFlag(List<String> args, String name) {
  final prefix = '--$name=';
  for (final a in args) {
    if (a.startsWith(prefix)) return a.substring(prefix.length);
  }
  return null;
}

/// Entry point. Sets [exitCode] from [_run]'s return value rather than relying
/// on a returned int (returning an int from `main` does NOT set the process
/// exit code under `dart run` — confirmed; the whole documented exit-code
/// contract, incl. the new --validate-only / usage codes, depends on this).
/// Uses `exitCode =` (not `exit()`) so the buffered REPORT output still flushes.
Future<void> main(List<String> args) async {
  exitCode = await _run(args);
}

Future<int> _run(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();

  // Reject unknown flags up front (codex final review P2): a typo'd flag
  // (e.g. --clas=l3-gate or --validate) must not silently run the full suite
  // in the wrong mode. Mirrors gen_scenario_index.dart's strictness.
  const knownBoolFlags = {
    '--echo',
    '--allow-skip',
    '--no-fail-fast',
    '--list',
    '--validate-only',
  };
  const knownValueFlagPrefixes = ['--class=', '--suite=', '--id=', '--skip='];
  final unknownFlags = args
      .where((a) => a.startsWith('--'))
      .where(
        (a) =>
            !knownBoolFlags.contains(a) &&
            !knownValueFlagPrefixes.any(a.startsWith),
      )
      .toList();
  if (unknownFlags.isNotEmpty) {
    stderr.writeln('[runner] unknown flag(s): ${unknownFlags.join(', ')}');
    stderr.writeln(_usage);
    return 64;
  }

  final echoUp = args.contains('--echo');
  final allowSkip = args.contains('--allow-skip');
  final failFast = !args.contains('--no-fail-fast');
  final listOnly = args.contains('--list');
  final validateOnly = args.contains('--validate-only');
  final classFilter = _multiFlag(args, 'class');
  final suiteFilter = _multiFlag(args, 'suite');
  final idGlob = _singleFlag(args, 'id');
  // --skip=<id,id>: report the named scenarios as SKIP instead of running
  // them. For env-class gaps a caller KNOWS about — e.g. L3-self-id asserts
  // the on-disk echo_seeded fixture account's exact toxId, which a
  // register-seeded fresh host (drive_l3_register --seed-echo) can never
  // satisfy — so the run stays honest (explicit SKIP) instead of tallying a
  // known-impossible FAIL.
  final skipIds = _multiFlag(args, 'skip');

  // Validate the --class values up front (a typo'd class must not silently
  // select nothing). Allowed values are the three derived class names.
  const validClasses = {'l3-gate', 'l3-gate-echo', 'l3-ui-single'};
  final badClasses = classFilter.difference(validClasses);
  if (badClasses.isNotEmpty) {
    stderr.writeln(
      '[runner] unknown --class value(s): ${badClasses.join(', ')} '
      '(allowed: ${validClasses.join('|')})',
    );
    return 64;
  }
  const validSuites = {'session', 'settings', 'c2c', 'group'};
  final badSuites = suiteFilter.difference(validSuites);
  if (badSuites.isNotEmpty) {
    stderr.writeln(
      '[runner] unknown --suite value(s): ${badSuites.join(', ')} '
      '(allowed: ${validSuites.join('|')})',
    );
    return 64;
  }

  // --list / --validate-only never connect to a VM, so the ws_uri positional is
  // waived: the (optional) positional becomes the scenario path directly.
  final noVmMode = listOnly || validateOnly;
  if (!noVmMode && positional.isEmpty) {
    stderr.writeln(_usage);
    return 64;
  }
  final scenarioPath = noVmMode
      ? (positional.isNotEmpty ? positional[0] : 'tool/mcp_test/scenarios')
      : (positional.length >= 2 ? positional[1] : 'tool/mcp_test/scenarios');
  final String wsUri = noVmMode ? '' : positional[0];

  // --validate-only: validate ALL scenario JSONs and report every violation; no
  // VM connection, no sort/filter. Stricter than the load-time suite check —
  // also catches order/feature/uiDriven type errors and duplicate ids.
  if (validateOnly) {
    return _runValidateOnly(scenarioPath);
  }

  final loaded = _loadScenarios(scenarioPath);
  final scenarios = loaded.scenarios;
  // codex P1: malformed/missing-id/missing-or-unknown-suite scenario files are
  // hard errors, not silent skips — a typo must not shrink coverage while
  // exiting 0. (suite is enforced here too, mirroring the missing-id contract.)
  for (final e in loaded.errors) {
    stderr.writeln('[runner] LOAD ERROR: $e');
  }
  // Sort into the deterministic partition order (replaces alphabetical):
  // (partition, suiteRank, order, filename). Done before filtering so --list
  // and the run share one ordering.
  scenarios.sort(_compareScenarios);

  // Apply --class / --suite / --id filters. session-suite scenarios are the
  // preflight: --class keeps them regardless of partition; only an EXPLICIT
  // --suite / --id can drop them.
  final selected = _applyFilters(
    scenarios,
    classFilter: classFilter,
    suiteFilter: suiteFilter,
    idGlob: idGlob,
  );

  // --list: print the resolved execution table and exit (no VM connection).
  // Load errors were already printed to stderr above; --list still exits 0
  // (it is an inspection mode; --validate-only is the schema gate).
  if (listOnly) {
    _printList(selected);
    return 0;
  }

  if (selected.isEmpty && loaded.errors.isEmpty) {
    stderr.writeln('no scenarios found at $scenarioPath');
    return 65;
  }
  stdout.writeln(
    '[runner] ${selected.length} scenario(s) selected '
    '(${scenarios.length} loaded); echoPeer=$echoUp; failFast=$failFast; '
    'loadErrors=${loaded.errors.length}',
  );

  late VmService vm;
  try {
    vm = await vmServiceConnectUri(wsUri);
  } catch (e) {
    stderr.writeln('[runner] vm connect failed: $e');
    return 70;
  }
  final isolateId = await _findMainIsolate(vm);
  final d = _L3Driver(vm, isolateId);
  try {
    await d.waitForExtension('ext.mcp.toolkit.l3_dump_state', timeoutSecs: 60);
  } catch (e) {
    stderr.writeln(
      '[runner] L3 debug tools not registered: $e\n'
      'Launch with MCP_BINDING=marionette ./run_toxee.sh (TOXEE_L3_TEST).',
    );
    return 71;
  }

  final results = <_Result>[];
  var aborted = false;
  for (final sc in selected) {
    final s = sc.map;
    final scenarioId = s['id'] as String? ?? '?';
    // _multiFlag lowercases its values, so compare case-insensitively — the
    // scenario ids are mixed-case (e.g. "L3-self-id"), and a raw compare
    // silently never matched (the scenario ran + failed instead of skipping).
    if (skipIds.contains(scenarioId.toLowerCase())) {
      results.add(_Result(scenarioId, 'SKIP', 'skipped via --skip'));
      stdout.writeln('[runner] SKIP $scenarioId (--skip)');
      continue;
    }
    if ((s['requiresEchoPeer'] == true) && !echoUp) {
      results.add(
        _Result(
          s['id'] as String? ?? '?',
          'SKIP',
          'requiresEchoPeer but --echo not passed',
        ),
      );
      stdout.writeln('[runner] SKIP ${s['id']} (needs echo peer)');
      continue;
    }
    if (s['requiresEchoPeer'] == true) {
      final echoReady = await _ensureEchoPeerReady();
      if (echoReady != null) {
        results.add(_Result(s['id'] as String? ?? '?', 'FAIL', echoReady));
        stdout.writeln('[runner] FAIL ${s['id']} — $echoReady');
        // Preflight fail-fast also covers an echo-peer setup failure for a
        // session-suite scenario (a broken session preflight, by any cause,
        // makes everything downstream noise).
        if (failFast && _suiteOf(s) == 'session') {
          stderr.writeln(
            '[runner] PREFLIGHT FAIL — session scenario ${s['id']} failed; '
            'aborting (pass --no-fail-fast to continue).',
          );
          aborted = true;
          break;
        }
        continue;
      }
    }
    // #18 (codex AGREE): substitute a fresh per-run nonce into the scenario's
    // string VALUES (never keys) so fixed scenario texts can't collide across
    // back-to-back runs — a straggler echo from a prior run carries an OLD
    // nonce, so it can no longer inflate this run's `message_count_text`
    // assertions. One nonce value per run; the SAME `{{nonce}}` token used
    // twice resolves to the SAME string, preserving l3_identical_self_text's
    // byte-identical pair. Scenarios without the token are unaffected. NOTE
    // (codex): this fixes text-collision races only — it does NOT make
    // conversation-wide assertions (messageCount, unreadCount) straggler-proof;
    // those still depend on the reset achieving true emptiness.
    final s2 = (_substituteNonce(s, _freshNonce()) as Map)
        .cast<String, dynamic>();
    final r = await _runScenario(d, s2);
    results.add(r);
    stdout.writeln(
      '[runner] ${r.status} ${r.id}'
      '${r.detail.isEmpty ? '' : ' — ${r.detail}'}',
    );
    // Preflight fail-fast: a hard FAIL of a session-suite scenario aborts the
    // run (downstream is noise once the session is broken). FLAKY (nonBlocking)
    // never aborts. --no-fail-fast restores the run-everything behavior.
    if (failFast && r.status == 'FAIL' && _suiteOf(s) == 'session') {
      stderr.writeln(
        '[runner] PREFLIGHT FAIL — session scenario ${r.id} failed; '
        'aborting remaining scenarios (pass --no-fail-fast to continue).',
      );
      aborted = true;
      break;
    }
  }
  if (aborted) {
    stdout.writeln(
      '[runner] run aborted after preflight failure; '
      '${selected.length - results.length} scenario(s) not run.',
    );
  }

  // Report.
  final pass = results.where((r) => r.status == 'PASS').length;
  final fail = results.where((r) => r.status == 'FAIL').length;
  final skip = results.where((r) => r.status == 'SKIP').length;
  final flaky = results.where((r) => r.status == 'FLAKY').length;
  stdout.writeln('\n===== L3 RUNNER REPORT =====');
  for (final r in results) {
    stdout.writeln(
      '  ${r.status.padRight(5)} ${r.id}'
      '${r.detail.isEmpty ? '' : '  (${r.detail})'}',
    );
  }
  stdout.writeln(
    '  ---- $pass passed, $fail failed, $flaky flaky, '
    '$skip skipped, ${loaded.errors.length} load-error(s) ----',
  );
  if (flaky > 0) {
    stderr.writeln(
      '[runner] $flaky nonBlocking scenario(s) failed (FLAKY) — '
      'not counted as failures. Stabilize + remove nonBlocking before '
      'trusting them as gates.',
    );
  }
  await vm.dispose();
  // Exit codes (codex P1/P2): any failure or load error → 1 (hard fail);
  // skips without --allow-skip → 2 (so CI can't false-green by dropping
  // echo-dependent scenarios); otherwise 0.
  if (fail > 0 || loaded.errors.isNotEmpty) return 1;
  // Caller-REQUESTED skips (--skip=<id>) are already an explicit, visible
  // decision — only implicit skips (echo-dependent scenarios dropped without
  // --echo) need the --allow-skip acknowledgement to prevent silent
  // false-greens.
  final implicitSkips = results
      .where((r) => r.status == 'SKIP' && r.detail != 'skipped via --skip')
      .length;
  if (implicitSkips > 0 && !allowSkip) {
    stderr.writeln(
      '[runner] $implicitSkips scenario(s) skipped and --allow-skip not '
      'set → exit 2. Pass --echo (and any needed harness) or --allow-skip.',
    );
    return 2;
  }
  return 0;
}

Future<String?> _ensureEchoPeerReady() async {
  final result = await Process.run(
    './tool/mcp_test/ensure_echo_peer.sh',
    const <String>[],
  );
  if (result.exitCode != 0) {
    final stdoutText = (result.stdout as String?)?.trim() ?? '';
    final stderrText = (result.stderr as String?)?.trim() ?? '';
    final detail = [
      stdoutText,
      stderrText,
    ].where((s) => s.isNotEmpty).join(' | ');
    return detail.isEmpty
        ? 'echo peer ensure failed with exit=${result.exitCode}'
        : 'echo peer ensure failed: $detail';
  }
  return _waitForEchoPeerOnline();
}

Future<String?> _waitForEchoPeerOnline() async {
  final logFile = File('tool/mcp_test/echo_peer.stdout.log');
  const needle = 'Server: Online';
  for (var i = 0; i < 45; i++) {
    if (await logFile.exists()) {
      final text = await logFile.readAsString();
      if (text.contains(needle)) return null;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return 'echo peer never reached online readiness '
      '(missing "$needle" in tool/mcp_test/echo_peer.stdout.log)';
}

// ---------- per-run nonce templating (#18, codex-vetted 2026-05-30) ----------

int _nonceSeq = 0;

/// A fresh per-run nonce: microsecond clock + a monotonic counter, base36.
/// Unique across back-to-back runs in one process AND across processes (two
/// runs in the same microsecond still differ by the counter).
String _freshNonce() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '${(_nonceSeq++).toRadixString(36)}';

/// Deep-substitute the literal token `{{nonce}}` with [nonce] across all
/// String VALUES of a scenario (Map values + List elements), leaving Map KEYS
/// (field names, action names, assertion types) untouched (codex: never
/// template control strings). Returns a NEW structure; the input is unmutated,
/// so the loaded scenario can be re-templated on a later run with a new nonce.
Object? _substituteNonce(Object? node, String nonce) {
  if (node is String) return node.replaceAll('{{nonce}}', nonce);
  if (node is List) {
    return node.map((e) => _substituteNonce(e, nonce)).toList();
  }
  if (node is Map) {
    return node.map((k, v) => MapEntry(k, _substituteNonce(v, nonce)));
  }
  return node;
}

/// Replace `{{key}}` tokens with RUNTIME-captured values (e.g. a group id a
/// `create_group` step stashed via `saveAs`). Like [_substituteNonce] but
/// applied per step/assertion at dispatch time, since the values aren't known
/// at scenario-load time. Deep-substitutes string VALUES only; a no-op when
/// nothing is captured.
Object? _substituteCaptured(Object? node, Map<String, String> captured) {
  if (captured.isEmpty) return node;
  if (node is String) {
    var out = node;
    captured.forEach((k, v) => out = out.replaceAll('{{$k}}', v));
    return out;
  }
  if (node is List) {
    return node.map((e) => _substituteCaptured(e, captured)).toList();
  }
  if (node is Map) {
    return node.map((k, v) => MapEntry(k, _substituteCaptured(v, captured)));
  }
  return node;
}

class _Result {
  _Result(this.id, this.status, this.detail);
  final String id;
  final String status; // PASS | FAIL | FLAKY | SKIP
  final String detail;
}

Future<_Result> _runScenario(_L3Driver d, Map<String, dynamic> s) async {
  final id = s['id'] as String? ?? '?';
  final target = s['target'] as String?;
  // codex (Phase 4): a scenario whose pass depends on un-controlled real-DHT
  // timing (e.g. first-packet warmup latency under burst) must NOT be a hard
  // gate until a readiness wait + measured pass-rate justify it. `nonBlocking`
  // downgrades a failure to FLAKY — surfaced loudly, but it does not fail the
  // run. Remove the flag once the scenario is proven stable.
  final nonBlocking = s['nonBlocking'] == true;
  // Runtime-captured values (e.g. a group id created mid-scenario by a
  // `create_group` step's `saveAs`), resolved into later `{{key}}` tokens.
  // Distinct from the load-time {{nonce}} pass — these aren't known until a
  // step runs.
  final captured = <String, String>{};
  try {
    if (s['reset'] == true) {
      await _resetConversation(d, target);
    }
    for (final raw in (s['steps'] as List? ?? const [])) {
      final step = (raw as Map).cast<String, dynamic>();
      await _runStep(d, step, target, captured);
    }
    for (final raw in (s['assertions'] as List? ?? const [])) {
      final a = (raw as Map).cast<String, dynamic>();
      final err = await _checkAssertion(d, a, target, captured);
      if (err != null) {
        return _Result(id, nonBlocking ? 'FLAKY' : 'FAIL', err);
      }
    }
    return _Result(id, 'PASS', '');
  } catch (e) {
    return _Result(id, nonBlocking ? 'FLAKY' : 'FAIL', '$e');
  } finally {
    // Optional teardown: best-effort self-clean that runs AFTER assertions and
    // on the failure/throw path. Needed because leave_group WIPES group history
    // (FfiChatService.quitGroup → clearGroupHistory) — so a group-history
    // scenario asserts on the LIVE group, then leaves here. Running on every
    // exit path keeps a failed scenario from leaking a dangling group into the
    // next scenario's knownGroups. Teardown errors are swallowed: teardown is
    // advisory and must never change the verdict or mask the real result.
    for (final raw in (s['teardown'] as List? ?? const [])) {
      try {
        await _runStep(
          d,
          (raw as Map).cast<String, dynamic>(),
          target,
          captured,
        );
      } catch (_) {
        // advisory — ignore
      }
    }
  }
}

/// Robust per-scenario reset (codex P1): a single clear can race a delayed
/// echo from the previous scenario that lands just after the wipe. Clear, then
/// poll until the conversation reads empty; re-clear up to a few times if a
/// straggler repopulates it. Bounded so a genuinely-busy conversation can't
/// hang the run.
Future<void> _resetConversation(_L3Driver d, String? target) async {
  const attempts = 4;
  for (var i = 0; i < attempts; i++) {
    await d.clearHistory(userId: target);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final msgs = await d.messages(conv: target);
    if (msgs.isEmpty) return;
  }
  // Last clear; proceed even if non-empty (scenarios filter by unique text).
  await d.clearHistory(userId: target);
}

Future<void> _runStep(
  _L3Driver d,
  Map<String, dynamic> rawStep,
  String? target,
  Map<String, String> captured,
) async {
  // Resolve runtime `{{key}}` captures (from a prior create_group/saveAs) at
  // dispatch time — the load-time {{nonce}} pass already ran.
  final step = (_substituteCaptured(rawStep, captured) as Map)
      .cast<String, dynamic>();
  final action = step['action'] as String?;
  switch (action) {
    case 'send_text':
      await d.sendText(
        step['text'] as String? ?? '',
        userId: step['userId'] as String? ?? target,
      );
      break;
    case 'clear_history':
      await d.clearHistory(userId: step['userId'] as String? ?? target);
      break;
    case 'delay':
      await Future<void>.delayed(
        Duration(milliseconds: (step['ms'] as num?)?.toInt() ?? 500),
      );
      break;
    case 'wait_for':
      await _waitForPredicate(d, step, target);
      break;
    case 'warmup':
      // codex (Phase 4): establish the DHT route + echo round-trip BEFORE the
      // asserted sends, so first-packet warmup latency doesn't masquerade as a
      // send bug. Sends a throwaway text and waits for its echo; the result is
      // never asserted. Best-effort — a warmup timeout is swallowed (the real
      // steps' own wait_for is the gate).
      try {
        final t =
            step['text'] as String? ??
            'warmup-${DateTime.now().microsecondsSinceEpoch}';
        await d.sendText(t, userId: step['userId'] as String? ?? target);
        await _waitForPredicate(d, {
          'predicate': 'message_exists',
          'text': t,
          'isSelf': false,
          'timeoutSecs': (step['timeoutSecs'] as num?)?.toInt() ?? 45,
        }, target);
      } catch (_) {
        // Warmup is advisory; ignore its failure.
      }
      break;
    case 'tap':
      if (step['key'] != null) {
        await d.callExt('ext.flutter.marionette.tap', {'key': step['key']});
      } else if (step['text'] != null) {
        await d.callExt('ext.flutter.marionette.tap', {'text': step['text']});
      }
      break;
    case 'long_press':
      // Real-UI long-press, mirroring `tap`: locate by {key} or {text} and
      // dispatch the marionette long-press service extension. Used to open the
      // message-action menu on a chat row (the REAL-UI path for S15), instead
      // of the l3_invoke_message_action debug bypass.
      //
      // ASSUMPTION (NOT yet verified against marionette_flutter — confirm on the
      // first live run via `mcp__marionette__list_custom_extensions` / the
      // package source): the extension is named `ext.flutter.marionette.longPress`,
      // following the same ext.flutter.marionette.<verb> convention as `tap`
      // (ext.flutter.marionette.tap) and `enterText`. If the real verb differs
      // (e.g. `longTap`/`pressAndHold`), update this string only.
      if (step['key'] != null) {
        await d.callExt('ext.flutter.marionette.longPress', {
          'key': step['key'],
        });
      } else if (step['text'] != null) {
        await d.callExt('ext.flutter.marionette.longPress', {
          'text': step['text'],
        });
      }
      break;
    case 'enter_text':
      await d.callExt('ext.flutter.marionette.enterText', {
        'key': step['key'],
        'input': step['text'],
      });
      break;
    case 'invoke_action':
      await _invokeMessageAction(d, step, target);
      break;
    case 'mark_read':
      await d.markRead(userId: step['userId'] as String? ?? target);
      break;
    case 'set_setting':
      // #5: drive a fixture-safe account setting (autoAccept flags) via the
      // l3_set_setting debug tool so a scenario can prove a toggle round-trips
      // through l3_dump_state. `value` is a JSON bool; callExt stringifies it.
      await d.setSetting(step['key'] as String? ?? '', step['value']);
      break;
    case 'set_pinned':
      // F2: drive l3_set_pinned so a scenario proves a pin/unpin round-trips
      // through l3_dump_state.pinnedConversations. `conversationId` defaults to
      // the scenario target; `pinned` is a JSON bool (callExt stringifies it).
      await d.setPinned(
        step['conversationId'] as String? ??
            step['userId'] as String? ??
            target,
        step['pinned'],
      );
      break;
    case 'set_friend_remark':
      // S30/H5: drive l3_set_friend_remark so a scenario proves a remark
      // set/clear round-trips through l3_dump_state.friends[].remark. `userId`
      // defaults to the target; empty `remark` clears it (Prefs.setFriendRemark).
      await d.setFriendRemark(
        step['userId'] as String? ?? target,
        step['remark'] as String? ?? '',
      );
      break;
    case 'set_self_profile':
      // S8/B10: drive l3_set_self_profile so a scenario proves a self-profile
      // field round-trips through l3_dump_state. Only statusMessage is wired
      // (nickname mutation would trip the test-account nickname guard); empty
      // statusMessage clears it.
      await d.setSelfProfile(statusMessage: step['statusMessage'] as String?);
      break;
    case 'set_blocked':
      // S29: drive l3_set_blocked so a scenario proves block/unblock round-trips
      // through l3_dump_state.blockedUsers AND that an inbound message from a
      // blocked echo peer is suppressed. `blocked` is a JSON bool.
      await d.setBlocked(step['userId'] as String? ?? target, step['blocked']);
      break;
    case 'set_recv_opt':
      // S83: drive l3_set_c2c_recv_opt (0=receive, 1=no-notify, 2=block/mute)
      // so a scenario proves the recvOpt round-trips through
      // l3_dump_state.conversations[].recvOpt. `opt` is 0|1|2.
      await d.setRecvOpt(step['userId'] as String? ?? target, step['opt']);
      break;
    case 'irc_set_state':
      await d.ircSetState(
        reset: step['reset'],
        installed: step['installed'],
        server: step['server'] as String?,
        port: step['port'],
        useSasl: step['useSasl'],
        channels: step['channels'],
        localAddOverride: step['localAddOverride'],
      );
      break;
    case 'irc_add_channel_local':
      final groupId = await d.ircAddChannelLocal(
        channel: step['channel'] as String? ?? '',
        groupId: step['groupId'] as String?,
      );
      if (step['saveAs'] != null) captured[step['saveAs'] as String] = groupId;
      break;
    case 'irc_remove_channel_local':
      await d.ircRemoveChannelLocal(
        channel: step['channel'] as String? ?? '',
        groupId: step['groupId'] as String?,
      );
      break;
    case 'reply_text':
      // S18: send a reply quoting an existing message (by replyToText, with an
      // optional replyToIsSelf disambiguator) so a scenario can assert the
      // reply persists with the messageReply cloudCustomData.
      await d.replyText(
        step['text'] as String? ?? '',
        replyToText: step['replyToText'] as String?,
        replyToMsgId: step['replyToMsgId'] as String?,
        replyToIsSelf: step['replyToIsSelf'],
        userId: step['userId'] as String? ?? target,
      );
      break;
    case 'forward_message':
      // S17: forward a resolved source message's text to a target conversation.
      await d.forwardMessage(
        sourceText: step['sourceText'] as String? ?? '',
        sourceIsSelf: step['sourceIsSelf'],
        fromUserId: step['fromUserId'] as String? ?? target,
        toUserId: step['toUserId'] as String? ?? target,
      );
      break;
    case 'create_group':
      // S35: create a group and stash its LOCAL group id (e.g. "tox_1" — NOT
      // the 64-char chatId; that's what knownGroups holds + quitGroup takes)
      // under `saveAs` (default "groupId") so later steps/assertions reference
      // it via {{<saveAs>}}. Optional `type` (public|private) selects the NGC
      // privacy state; both forms are tracked identically in knownGroups.
      final gid = await d.createGroup(
        name: step['name'] as String?,
        type: step['type'] as String?,
      );
      captured[step['saveAs'] as String? ?? 'groupId'] = gid;
      break;
    case 'send_group_text':
      // Group analog of `send_text`: send into the group identified by
      // `groupId` (a local id or group_<id>, typically {{gid}} captured from a
      // prior create_group). Persists to the group's LOCAL history as isSelf.
      await d.sendGroupText(
        step['groupId'] as String? ?? '',
        step['text'] as String? ?? '',
      );
      break;
    case 'leave_group':
      // S35: leave a group by its LOCAL group id (FfiChatService.quitGroup →
      // native tox_group_leave; removes it from knownGroups).
      await d.leaveGroup(step['groupId'] as String? ?? target ?? '');
      break;
    default:
      throw 'unknown action: $action';
  }
}

/// Drive a message-menu action (delete/copy) deterministically via
/// `l3_invoke_message_action` — the harness has no long-press semantic action,
/// so this is the only reliable way to exercise S15. The target message is
/// either an explicit `msgId`, or resolved from the live `l3_dump_state`
/// message list by `text` (+ optional `isSelf`) — resolving here (not in the
/// scenario JSON) keeps scenarios free of run-specific native ids.
Future<void> _invokeMessageAction(
  _L3Driver d,
  Map<String, dynamic> step,
  String? target,
) async {
  final messageAction = step['messageAction'] as String?;
  if (messageAction == null) {
    throw 'invoke_action requires "messageAction" (delete|copy)';
  }
  var msgId = step['msgId'] as String?;
  if (msgId == null) {
    final text = step['text'] as String?;
    final isSelf = step['isSelf'] as bool?;
    if (text == null) {
      throw 'invoke_action needs "msgId" or "text" to locate the message';
    }
    // Collect ALL matches rather than breaking on the first. Resolving by text
    // is ambiguous when the same text exists twice (e.g. a self message and its
    // verbatim echo). Acting on an arbitrary one could delete/copy the wrong
    // message and mask a regression — so require a UNIQUE match (callers use
    // isSelf to disambiguate, or pass an explicit msgId).
    final matches = <String>[];
    for (final raw in await d.messages(conv: target)) {
      final m = (raw as Map).cast<String, dynamic>();
      if (m['text'] != text) continue;
      if (isSelf != null && m['isSelf'] != isSelf) continue;
      final id = m['msgID'] as String?;
      if (id != null) matches.add(id);
    }
    if (matches.isEmpty) {
      throw 'invoke_action: no message matched text="$text" isSelf=$isSelf';
    }
    if (matches.length > 1) {
      throw 'invoke_action: ambiguous — ${matches.length} messages match '
          'text="$text" isSelf=$isSelf; add "isSelf" or use explicit "msgId"';
    }
    msgId = matches.first;
  }
  await d.invokeMessageAction(
    msgId: msgId,
    action: messageAction,
    userId: target,
  );
}

Future<void> _waitForPredicate(
  _L3Driver d,
  Map<String, dynamic> step,
  String? target,
) async {
  final predicate = step['predicate'] as String?;
  final timeoutSecs = (step['timeoutSecs'] as num?)?.toInt() ?? 30;
  // Optional conversation override (see _checkAssertion): a group-history wait
  // polls the group_<gid> conversation, not the scenario's static C2C target.
  final conv = step['conv'] as String? ?? target;
  // Misconfiguration guard (codex P2): the item predicates coerce a missing /
  // empty target to '' which no list contains — so without this a
  // state_not_contains_item with no `notContainsItem` would VACUOUSLY pass on
  // the first poll (and state_contains_item with none would just spin to a
  // timeout). Fail LOUDLY on the authoring mistake instead of green-washing it.
  if (predicate == 'state_contains_item' &&
      (step['containsItem'] == null || '${step['containsItem']}'.isEmpty)) {
    throw 'state_contains_item requires a non-empty "containsItem"';
  }
  if (predicate == 'state_not_contains_item' &&
      (step['notContainsItem'] == null ||
          '${step['notContainsItem']}'.isEmpty)) {
    throw 'state_not_contains_item requires a non-empty "notContainsItem"';
  }
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (predicate == 'message_exists') {
      final msgs = await d.messages(conv: conv);
      if (_matchCount(msgs, step['text'] as String?, step['isSelf'] as bool?) >
          0) {
        return;
      }
    } else if (predicate == 'message_count_at_least') {
      // Poll the conversation history until AT LEAST `count` messages match
      // `text` (+optional isSelf). Stronger than message_exists (which fires at
      // the first match): lets a burst / duplicate scenario assert its exact
      // count over a SETTLED read instead of a fixed delay — e.g. wait until
      // BOTH identical group self-sends have landed before asserting equals:2,
      // so the gate can't pass while a second row is still in flight.
      final want = (step['count'] as num?)?.toInt() ?? 1;
      final msgs = await d.messages(conv: conv);
      if (_matchCount(msgs, step['text'] as String?, step['isSelf'] as bool?) >=
          want) {
        return;
      }
    } else if (predicate == 'unread_at_least') {
      // Poll l3_dump_state.unreadCount until it reaches the threshold — lets a
      // scenario prove an inbound message actually incremented unread BEFORE
      // mark_read clears it (the S19 loop).
      final want = (step['count'] as num?)?.toInt() ?? 1;
      final state = await d.dumpState(conv: conv);
      final unread = (state['unreadCount'] as num?)?.toInt() ?? 0;
      if (unread >= want) return;
    } else if (predicate == 'state_contains') {
      // #4 (codex): poll a dump_state field until its stringified value
      // contains the given substring. Handles the UI-live `conversations`
      // hydration race (the list populates shortly AFTER login) so a later
      // `state{contains}` assertion is not read before the sidebar is built.
      // Works on any field — a List value is stringified before the substring
      // check, matching the `state{contains}` assertion semantics.
      final state = await d.dumpState(conv: conv);
      final actual = state[step['field']]?.toString() ?? '';
      if (actual.contains(step['contains'] as String? ?? '')) return;
    } else if (predicate == 'state_equals') {
      // codex P2: EXACT-value poll for SCALAR fields (int/string/bool). Avoids
      // the substring false-pass of state_contains on numbers (a stuck `130`
      // satisfies both `contains:"30"` and `contains:"13"`). Mirrors the
      // `state{equals}` assertion's equality, so JSON 13/"manual"/true compare
      // against the dump's int/String/bool directly.
      final state = await d.dumpState(conv: conv);
      if (state[step['field']] == step['equals']) return;
    } else if (predicate == 'state_not_contains') {
      // Poll until a substring is ABSENT from a field's stringified value —
      // the settle half of an absence assertion (cleared remark, declined
      // application). Mirrors the state{notContains} assertion. codex P2: only
      // satisfy once the field is PRESENT and lacks the substring — a
      // missing/errored field must not vacuously pass (keep waiting instead).
      final state = await d.dumpState(conv: conv);
      final field = step['field'];
      if (state.containsKey(field)) {
        final actual = state[field]?.toString() ?? '';
        if (!actual.contains(step['notContains'] as String? ?? '')) return;
      }
    } else if (predicate == 'state_contains_item' ||
        predicate == 'state_not_contains_item') {
      // EXACT list-element membership poll — the settle half of the
      // containsItem / notContainsItem assertions. Avoids the prefix-substring
      // trap (tox_1 ⊂ tox_10) when waiting on knownGroups / pinnedConversations.
      // Acts only once the field is PRESENT and a List; a missing/non-list
      // value keeps waiting (then times out loudly) rather than vacuously
      // satisfying — mirrors the state_not_contains codex P2.
      final state = await d.dumpState(conv: conv);
      final value = state[step['field']];
      if (value is List) {
        final items = value.map((e) => e.toString()).toSet();
        if (predicate == 'state_contains_item' &&
            items.contains((step['containsItem'] ?? '').toString())) {
          return;
        }
        if (predicate == 'state_not_contains_item' &&
            !items.contains((step['notContainsItem'] ?? '').toString())) {
          return;
        }
      }
    } else {
      throw 'unknown wait_for predicate: $predicate';
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }
  throw 'wait_for($predicate field=${step['field']} text=${step['text']} '
      'count=${step['count']} contains=${step['contains']} '
      'equals=${step['equals']} notContains=${step['notContains']} '
      'containsItem=${step['containsItem']} '
      'notContainsItem=${step['notContainsItem']}) timed out after ${timeoutSecs}s';
}

Future<String?> _checkAssertion(
  _L3Driver d,
  Map<String, dynamic> rawA,
  String? target,
  Map<String, String> captured,
) async {
  // Resolve runtime `{{key}}` captures (e.g. {{groupId}} from create_group).
  final a = (_substituteCaptured(rawA, captured) as Map)
      .cast<String, dynamic>();
  final type = a['type'] as String?;
  // Optional per-assertion conversation override. Group-history assertions
  // (message_*) must read the GROUP conversation (group_<gid>, where gid is a
  // runtime {{capture}}), not the scenario's static C2C `target`. Absent → the
  // existing behavior (default to `target`), so C2C scenarios are unchanged.
  final conv = a['conv'] as String? ?? target;
  switch (type) {
    case 'state':
      if (!a.containsKey('equals') &&
          !a.containsKey('contains') &&
          !a.containsKey('notContains') &&
          !a.containsKey('containsItem') &&
          !a.containsKey('notContainsItem')) {
        return 'vacuous "state" assertion (needs "equals", "contains", '
            '"notContains", "containsItem", or "notContainsItem"): $a';
      }
      final state = await d.dumpState(conv: conv);
      final field = a['field'] as String?;
      final actual = state[field];
      if (a.containsKey('equals') && actual != a['equals']) {
        return 'state.$field expected ${a['equals']}, got $actual';
      }
      if (a.containsKey('contains') &&
          !(actual?.toString() ?? '').contains(a['contains'] as String)) {
        return 'state.$field expected to contain "${a['contains']}", got $actual';
      }
      // notContains: assert a substring is ABSENT — the absence half of a
      // round-trip (e.g. a cleared friend remark / a declined friend
      // application no longer present in the stringified list field).
      if (a.containsKey('notContains')) {
        // codex P2: a MISSING field must NOT vacuously satisfy an absence
        // check — if the read-model dropped/errored the field (e.g.
        // `friendsError` instead of `friends`), fail loudly instead of
        // reading absent-as-clean.
        if (!state.containsKey(field)) {
          return 'state.$field absent — cannot assert notContains '
              '"${a['notContains']}" (read-model missing or errored)';
        }
        if ((actual?.toString() ?? '').contains(a['notContains'] as String)) {
          return 'state.$field expected NOT to contain "${a['notContains']}", '
              'got $actual';
        }
      }
      // containsItem / notContainsItem: EXACT list-element membership, NOT a
      // substring. Required for id-list fields (knownGroups, pinnedConversations)
      // where a bare `contains` false-matches a prefix-sharing sibling — e.g.
      // "tox_1" is a substring of "tox_10", and "group_tox_1" of "group_tox_10".
      // The field MUST be a List: a missing/non-list value fails LOUDLY rather
      // than reading absent-as-clean (mirrors the notContains codex P2).
      if (a.containsKey('containsItem') || a.containsKey('notContainsItem')) {
        if (actual is! List) {
          return 'state.$field is not a list (${actual.runtimeType}) — '
              'containsItem/notContainsItem require a list field';
        }
        final items = actual.map((e) => e.toString()).toSet();
        if (a.containsKey('containsItem')) {
          final want = (a['containsItem'] ?? '').toString();
          if (want.isEmpty) {
            return 'state.$field containsItem must be a non-empty value';
          }
          if (!items.contains(want)) {
            return 'state.$field expected to contain item "$want", got $actual';
          }
        }
        if (a.containsKey('notContainsItem')) {
          // codex P2: an empty notContainsItem would vacuously pass (no list
          // contains '') — reject it so the absence check is meaningful.
          final want = (a['notContainsItem'] ?? '').toString();
          if (want.isEmpty) {
            return 'state.$field notContainsItem must be a non-empty value';
          }
          if (items.contains(want)) {
            return 'state.$field expected NOT to contain item "$want", '
                'got $actual';
          }
        }
      }
      return null;
    case 'message_exists':
      final msgs = await d.messages(conv: conv);
      final n = _matchCount(msgs, a['text'] as String?, a['isSelf'] as bool?);
      return n > 0
          ? null
          : 'no message text="${a['text']}" isSelf=${a['isSelf']}';
    case 'message_count_text':
      if (!a.containsKey('equals') && !a.containsKey('atLeast')) {
        return 'vacuous "message_count_text" (needs "equals" or "atLeast"): $a';
      }
      final msgs = await d.messages(conv: conv);
      final n = _matchCount(msgs, a['text'] as String?, a['isSelf'] as bool?);
      if (a.containsKey('equals') && n != (a['equals'] as num).toInt()) {
        return 'message_count_text("${a['text']}",isSelf=${a['isSelf']}) '
            'expected ${a['equals']}, got $n';
      }
      if (a.containsKey('atLeast') && n < (a['atLeast'] as num).toInt()) {
        return 'message_count_text("${a['text']}") expected >= '
            '${a['atLeast']}, got $n';
      }
      return null;
    case 'message_order':
      // codex (Phase 4): assert the persisted dump returns the given texts in
      // this relative order (timestamp-ascending ground truth). Each text must
      // appear exactly once and their positions strictly increase.
      // `isSelf` filter is important: if the echo peer is up, a self message is
      // echoed back verbatim, so the same text exists twice (self + incoming).
      // Scope ordering to one direction (the sent self messages) so a running
      // peer doesn't make every text "ambiguous". codex item-1 nonce caveat.
      final want = (a['texts'] as List?)?.cast<String>();
      if (want == null || want.length < 2) {
        return 'message_order needs "texts": [>=2 message texts]';
      }
      final orderSelf = a['isSelf'] as bool?;
      final msgs = await d.messages(conv: conv);
      final positions = <int>[];
      for (final t in want) {
        final idxs = <int>[];
        for (var i = 0; i < msgs.length; i++) {
          final m = msgs[i] as Map;
          if (m['text'] != t) continue;
          if (orderSelf != null && m['isSelf'] != orderSelf) continue;
          idxs.add(i);
        }
        if (idxs.isEmpty) return 'message_order: text "$t" not found';
        if (idxs.length > 1) {
          return 'message_order: text "$t" appears ${idxs.length}× (ambiguous '
              '— add "isSelf" to disambiguate or use unique nonce texts)';
        }
        positions.add(idxs.first);
      }
      for (var i = 1; i < positions.length; i++) {
        if (positions[i] <= positions[i - 1]) {
          return 'message_order: "${want[i]}" (pos ${positions[i]}) not after '
              '"${want[i - 1]}" (pos ${positions[i - 1]})';
        }
      }
      return null;
    case 'message_field_contains':
      // S17/S18: resolve a UNIQUE message by text (+optional isSelf) and assert
      // its [field] stringified contains [contains] — e.g. the reply message's
      // cloudCustomData carries the quoted base text / "messageReply". A missing
      // field stringifies to '' so a real absence fails the contains.
      if (!a.containsKey('field') || !a.containsKey('contains')) {
        return 'message_field_contains needs "field" and "contains": $a';
      }
      final mfMsgs = await d.messages(conv: conv);
      final mfText = a['text'] as String?;
      final mfIsSelf = a['isSelf'] as bool?;
      final hits = <Map>[];
      for (final raw in mfMsgs) {
        final m = raw as Map;
        if (mfText != null && m['text'] != mfText) continue;
        if (mfIsSelf != null && m['isSelf'] != mfIsSelf) continue;
        hits.add(m);
      }
      if (hits.isEmpty) {
        return 'message_field_contains: no message text="$mfText" '
            'isSelf=$mfIsSelf';
      }
      if (hits.length > 1) {
        return 'message_field_contains: text="$mfText" isSelf=$mfIsSelf '
            'matched ${hits.length} (ambiguous — use a unique nonce text)';
      }
      final mfField = a['field'] as String;
      final mfActual = hits.first[mfField]?.toString() ?? '';
      if (!mfActual.contains(a['contains'] as String)) {
        return 'message_field_contains: message text="$mfText" field=$mfField '
            'expected to contain "${a['contains']}", got "$mfActual"';
      }
      return null;
    default:
      return 'unknown assertion type: $type';
  }
}

int _matchCount(List<dynamic> msgs, String? text, bool? isSelf) {
  var n = 0;
  for (final raw in msgs) {
    final m = (raw as Map).cast<String, dynamic>();
    if (text != null && m['text'] != text) continue;
    if (isSelf != null && m['isSelf'] != isSelf) continue;
    n++;
  }
  return n;
}

/// A loaded scenario plus its source file basename (needed for the
/// (partition, suiteRank, order, filename) sort tiebreak, --list, and error
/// reporting). The raw parsed JSON lives in [map]; helpers read suite/order/etc.
class _Scenario {
  _Scenario(this.file, this.map);
  final String file; // basename, e.g. "l3_session_state.json"
  final Map<String, dynamic> map;
  String get id => map['id'] as String? ?? '?';
}

/// The four logical suites and their sort rank (lower runs earlier).
const Map<String, int> _suiteRanks = {
  'session': 0,
  'settings': 1,
  'c2c': 2,
  'group': 3,
};

String? _suiteOf(Map<String, dynamic> s) {
  final v = s['suite'];
  return v is String ? v.toLowerCase() : null;
}

int _suiteRank(Map<String, dynamic> s) => _suiteRanks[_suiteOf(s)] ?? 99;

int _orderOf(Map<String, dynamic> s) => (s['order'] as num?)?.toInt() ?? 50;

/// Derived execution partition (replaces alphabetical grouping):
/// uiDriven ? 2 : (requiresEchoPeer ? 1 : 0).
int _partitionOf(Map<String, dynamic> s) {
  if (s['uiDriven'] == true) return 2;
  if (s['requiresEchoPeer'] == true) return 1;
  return 0;
}

/// Derived execution class name for partition: 0=l3-gate, 1=l3-gate-echo,
/// 2=l3-ui-single.
String _classOf(Map<String, dynamic> s) =>
    const ['l3-gate', 'l3-gate-echo', 'l3-ui-single'][_partitionOf(s)];

/// The pinned sort key: (partition, suiteRank, order, filename).
int _compareScenarios(_Scenario a, _Scenario b) {
  var c = _partitionOf(a.map).compareTo(_partitionOf(b.map));
  if (c != 0) return c;
  c = _suiteRank(a.map).compareTo(_suiteRank(b.map));
  if (c != 0) return c;
  c = _orderOf(a.map).compareTo(_orderOf(b.map));
  if (c != 0) return c;
  return a.file.compareTo(b.file);
}

/// Apply --class / --suite / --id filters. session-suite scenarios are the
/// preflight: they are kept under any --class selection (never partition-
/// filtered out); only an EXPLICIT --suite / --id can drop them.
List<_Scenario> _applyFilters(
  List<_Scenario> scenarios, {
  required Set<String> classFilter,
  required Set<String> suiteFilter,
  required String? idGlob,
}) {
  final glob = idGlob == null ? null : _globToRegExp(idGlob);
  return scenarios.where((sc) {
    final s = sc.map;
    final isSession = _suiteOf(s) == 'session';
    // --class: keep matching classes, but always keep the session preflight.
    if (classFilter.isNotEmpty &&
        !classFilter.contains(_classOf(s)) &&
        !isSession) {
      return false;
    }
    // --suite: EXPLICIT — excludes session unless "session" is named.
    if (suiteFilter.isNotEmpty && !suiteFilter.contains(_suiteOf(s))) {
      return false;
    }
    // --id: EXPLICIT — a non-matching id is dropped even for session scenarios.
    if (glob != null && !glob.hasMatch(sc.id)) {
      return false;
    }
    return true;
  }).toList();
}

/// Translate a `*`-glob (the only wildcard the spec defines for --id) into an
/// anchored RegExp. All other regex metacharacters in the pattern are escaped
/// so an id like "L3-pin-toggle" matches literally.
RegExp _globToRegExp(String glob) {
  final sb = StringBuffer('^');
  for (final ch in glob.split('')) {
    if (ch == '*') {
      sb.write('.*');
    } else {
      sb.write(RegExp.escape(ch));
    }
  }
  sb.write(r'$');
  return RegExp(sb.toString());
}

/// --list: print the resolved execution table (no VM connection). Columns:
/// position, id, filename, suite, class, order, echo?, uiDriven?, blocking?,
/// feature.
void _printList(List<_Scenario> selected) {
  stdout.writeln(
    '# pos  id  filename  suite  class  order  echo  uiDriven  blocking  feature',
  );
  var pos = 0;
  for (final sc in selected) {
    final s = sc.map;
    final feature = (s['feature'] as List?)?.join(',') ?? '';
    stdout.writeln(
      '${pos.toString().padLeft(3)}  '
      '${sc.id}  '
      '${sc.file}  '
      '${_suiteOf(s) ?? '?'}  '
      '${_classOf(s)}  '
      '${_orderOf(s)}  '
      '${s['requiresEchoPeer'] == true ? 'yes' : 'no'}  '
      '${s['uiDriven'] == true ? 'yes' : 'no'}  '
      '${s['nonBlocking'] == true ? 'no' : 'yes'}  '
      '$feature',
    );
    pos++;
  }
  stdout.writeln('---- ${selected.length} scenario(s) ----');
}

/// --validate-only: validate ALL scenario JSONs (no VM connection). Checks:
/// unique non-empty id; suite present and in the enum; order int when present;
/// feature an array of "S<digits>" strings when present; uiDriven bool when
/// present. Prints every violation; returns 1 if any (else 0). Also re-uses the
/// load-time JSON/id/suite checks via [_loadScenarios].
int _runValidateOnly(String path) {
  final violations = <String>[];
  final loaded = _loadScenarios(path);
  // Load-time errors (bad JSON, missing id, missing/unknown suite) are already
  // violations — surface them too.
  violations.addAll(loaded.errors);

  final seenIds = <String, String>{}; // id -> first file that used it
  for (final sc in loaded.scenarios) {
    final s = sc.map;
    final where = sc.file;
    // id uniqueness (non-empty id is already guaranteed by _loadScenarios).
    final id = s['id'] as String?;
    if (id != null) {
      final prior = seenIds[id];
      if (prior != null) {
        violations.add('$where: duplicate id "$id" (also in $prior)');
      } else {
        seenIds[id] = where;
      }
    }
    // suite present + in enum is enforced by _loadScenarios (→ loaded.errors),
    // so it is not re-checked here; the remaining optional fields are.
    // order: int when present.
    if (s.containsKey('order') && s['order'] is! int) {
      violations.add(
        '$where: "order" must be an int when present, got '
        '${s['order']} (${s['order'].runtimeType})',
      );
    }
    // uiDriven: bool when present.
    if (s.containsKey('uiDriven') && s['uiDriven'] is! bool) {
      violations.add(
        '$where: "uiDriven" must be a bool when present, got '
        '${s['uiDriven']} (${s['uiDriven'].runtimeType})',
      );
    }
    // feature: array of "S<digits>" strings when present.
    if (s.containsKey('feature')) {
      final f = s['feature'];
      if (f is! List) {
        violations.add(
          '$where: "feature" must be an array when present, got '
          '${f.runtimeType}',
        );
      } else {
        final re = RegExp(r'^S\d+$');
        for (final e in f) {
          if (e is! String || !re.hasMatch(e)) {
            violations.add(
              '$where: "feature" entries must be "S<digits>" strings, got "$e"',
            );
          }
        }
      }
    }
  }

  if (violations.isEmpty) {
    stdout.writeln(
      '[validate] OK — ${loaded.scenarios.length} scenario(s), 0 violations.',
    );
    return 0;
  }
  stderr.writeln('[validate] ${violations.length} violation(s):');
  for (final v in violations) {
    stderr.writeln('  - $v');
  }
  return 1;
}

/// Loads scenarios. Returns the parsed scenarios (each with its source basename)
/// AND a list of load errors (bad JSON / missing id / missing-or-unknown suite)
/// so the caller can FAIL the run instead of silently running a reduced set
/// (codex P1: a typo must not yield a false green). The suite check mirrors the
/// missing-id contract: every scenario MUST declare a suite in the enum.
({List<_Scenario> scenarios, List<String> errors}) _loadScenarios(String path) {
  final out = <_Scenario>[];
  final errors = <String>[];
  final type = FileSystemEntity.typeSync(path);
  final files = <File>[];
  if (type == FileSystemEntityType.directory) {
    for (final e in Directory(
      path,
    ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
      if (e is File && e.path.endsWith('.json')) files.add(e);
    }
  } else if (type == FileSystemEntityType.file) {
    files.add(File(path));
  } else {
    errors.add('scenario path not found: $path');
  }
  for (final f in files) {
    final base = _basename(f.path);
    try {
      final m = (jsonDecode(f.readAsStringSync()) as Map)
          .cast<String, dynamic>();
      if ((m['id'] as String?)?.isNotEmpty != true) {
        errors.add('$base: missing/empty "id"');
        continue;
      }
      // suite is REQUIRED and must be in the enum — hard load error, mirroring
      // the missing-id handling (no silent default; every file migrates).
      final suite = m['suite'];
      if (suite is! String || !_suiteRanks.containsKey(suite.toLowerCase())) {
        errors.add(
          '$base: missing/unknown "suite" (got ${suite is String ? '"$suite"' : suite}; '
          'must be one of ${_suiteRanks.keys.join('|')})',
        );
        continue;
      }
      out.add(_Scenario(base, m));
    } catch (e) {
      errors.add('$base: bad JSON: $e');
    }
  }
  return (scenarios: out, errors: errors);
}

/// Basename of a path (final segment after `/` or `\`). Avoids a package:path
/// dependency for this single use.
String _basename(String path) {
  final norm = path.replaceAll('\\', '/');
  final i = norm.lastIndexOf('/');
  return i < 0 ? norm : norm.substring(i + 1);
}

// ---------- driver ----------

class _L3Driver {
  _L3Driver(this.vm, this.isolateId);
  final VmService vm;
  final String isolateId;

  Future<void> waitForExtension(String name, {required int timeoutSecs}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final iso = await vm.getIsolate(isolateId);
      if ((iso.extensionRPCs ?? const <String>[]).contains(name)) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw 'extension $name not registered within ${timeoutSecs}s';
  }

  /// Call a service extension; returns its result JSON map.
  Future<Map<String, dynamic>> callExt(
    String method,
    Map<String, Object?> args,
  ) async {
    final stringArgs = <String, String>{
      for (final e in args.entries)
        if (e.value != null) e.key: e.value.toString(),
    };
    final resp = await vm.callServiceExtension(
      method,
      isolateId: isolateId,
      args: stringArgs,
    );
    return resp.json ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> dumpState({String? conv}) => callExt(
    'ext.mcp.toolkit.l3_dump_state',
    {if (conv != null) 'conversationId': conv},
  );

  Future<List<dynamic>> messages({String? conv}) async {
    final s = await dumpState(conv: conv);
    return (s['messages'] as List?) ?? const [];
  }

  Future<void> sendText(String text, {String? userId}) async {
    final r = await callExt('ext.mcp.toolkit.l3_send_text', {
      'text': text,
      if (userId != null) 'userId': userId,
    });
    if (r['ok'] != true) throw 'l3_send_text failed: ${r['message']}';
  }

  Future<void> clearHistory({String? userId}) async {
    final r = await callExt('ext.mcp.toolkit.l3_clear_history', {
      if (userId != null) 'userId': userId,
    });
    if (r['ok'] != true) throw 'l3_clear_history failed: ${r['message']}';
  }

  Future<void> invokeMessageAction({
    required String msgId,
    required String action,
    String? userId,
  }) async {
    final r = await callExt('ext.mcp.toolkit.l3_invoke_message_action', {
      'msgId': msgId,
      'action': action,
      if (userId != null) 'userId': userId,
    });
    if (r['ok'] != true) {
      throw 'l3_invoke_message_action($action) failed: ${r['message']}';
    }
  }

  Future<void> markRead({String? userId}) async {
    final r = await callExt('ext.mcp.toolkit.l3_mark_read', {
      if (userId != null) 'userId': userId,
    });
    if (r['ok'] != true) throw 'l3_mark_read failed: ${r['message']}';
  }

  Future<void> setSetting(String key, Object? value) async {
    final r = await callExt('ext.mcp.toolkit.l3_set_setting', {
      'key': key,
      'value': value,
    });
    if (r['ok'] != true) throw 'l3_set_setting failed: ${r['message']}';
  }

  Future<void> setPinned(String? conversationId, Object? pinned) async {
    final r = await callExt('ext.mcp.toolkit.l3_set_pinned', {
      if (conversationId != null) 'conversationId': conversationId,
      'pinned': pinned ?? true,
    });
    if (r['ok'] != true) throw 'l3_set_pinned failed: ${r['message']}';
  }

  Future<void> setFriendRemark(String? userId, String remark) async {
    final r = await callExt('ext.mcp.toolkit.l3_set_friend_remark', {
      if (userId != null) 'userId': userId,
      'remark': remark,
    });
    if (r['ok'] != true) throw 'l3_set_friend_remark failed: ${r['message']}';
  }

  Future<void> setSelfProfile({String? statusMessage}) async {
    final r = await callExt('ext.mcp.toolkit.l3_set_self_profile', {
      if (statusMessage != null) 'statusMessage': statusMessage,
    });
    if (r['ok'] != true) throw 'l3_set_self_profile failed: ${r['message']}';
  }

  Future<void> setBlocked(String? userId, Object? blocked) async {
    final r = await callExt('ext.mcp.toolkit.l3_set_blocked', {
      if (userId != null) 'userId': userId,
      'blocked': blocked ?? true,
    });
    if (r['ok'] != true) throw 'l3_set_blocked failed: ${r['message']}';
  }

  Future<void> setRecvOpt(String? userId, Object? opt) async {
    final r = await callExt('ext.mcp.toolkit.l3_set_c2c_recv_opt', {
      if (userId != null) 'userId': userId,
      'opt': opt ?? 0,
    });
    if (r['ok'] != true) throw 'l3_set_c2c_recv_opt failed: ${r['message']}';
  }

  Future<void> ircSetState({
    Object? reset,
    Object? installed,
    String? server,
    Object? port,
    Object? useSasl,
    Object? channels,
    Object? localAddOverride,
  }) async {
    final r = await callExt('ext.mcp.toolkit.l3_irc_set_state', {
      if (reset != null) 'reset': reset,
      if (installed != null) 'installed': installed,
      if (server != null) 'server': server,
      if (port != null) 'port': port,
      if (useSasl != null) 'useSasl': useSasl,
      if (channels != null) 'channels': jsonEncode(channels),
      if (localAddOverride != null) 'localAddOverride': localAddOverride,
    });
    if (r['ok'] != true) throw 'l3_irc_set_state failed: ${r['message']}';
  }

  Future<String> ircAddChannelLocal({
    required String channel,
    String? groupId,
  }) async {
    final r = await callExt('ext.mcp.toolkit.l3_irc_add_channel_local', {
      'channel': channel,
      if (groupId != null) 'groupId': groupId,
    });
    if (r['ok'] != true) {
      throw 'l3_irc_add_channel_local failed: ${r['message']}';
    }
    final mappedGroupId = r['groupId'] as String?;
    if (mappedGroupId == null || mappedGroupId.isEmpty) {
      throw 'l3_irc_add_channel_local returned no groupId';
    }
    return mappedGroupId;
  }

  Future<void> ircRemoveChannelLocal({
    required String channel,
    String? groupId,
  }) async {
    final r = await callExt('ext.mcp.toolkit.l3_irc_remove_channel_local', {
      'channel': channel,
      if (groupId != null) 'groupId': groupId,
    });
    if (r['ok'] != true) {
      throw 'l3_irc_remove_channel_local failed: ${r['message']}';
    }
  }

  Future<void> replyText(
    String text, {
    String? replyToText,
    String? replyToMsgId,
    Object? replyToIsSelf,
    String? userId,
  }) async {
    final r = await callExt('ext.mcp.toolkit.l3_reply_text', {
      'text': text,
      if (replyToText != null) 'replyToText': replyToText,
      if (replyToMsgId != null) 'replyToMsgId': replyToMsgId,
      if (replyToIsSelf != null) 'replyToIsSelf': replyToIsSelf,
      if (userId != null) 'userId': userId,
    });
    if (r['ok'] != true) throw 'l3_reply_text failed: ${r['message']}';
  }

  Future<void> forwardMessage({
    required String sourceText,
    Object? sourceIsSelf,
    String? fromUserId,
    String? toUserId,
  }) async {
    final r = await callExt('ext.mcp.toolkit.l3_forward_message', {
      'sourceText': sourceText,
      if (sourceIsSelf != null) 'sourceIsSelf': sourceIsSelf,
      if (fromUserId != null) 'fromUserId': fromUserId,
      if (toUserId != null) 'toUserId': toUserId,
    });
    if (r['ok'] != true) throw 'l3_forward_message failed: ${r['message']}';
  }

  /// S35: create a group, returning its LOCAL group id (e.g. "tox_1").
  /// [type] selects the NGC privacy state — 'public' (default, DHT-joinable)
  /// or 'private' (invite-only). The local-id + knownGroups bookkeeping is
  /// identical for both, so the hermetic gates work with either.
  Future<String> createGroup({String? name, String? type}) async {
    final r = await callExt('ext.mcp.toolkit.l3_create_group', {
      if (name != null) 'name': name,
      if (type != null) 'type': type,
    });
    if (r['ok'] != true) throw 'l3_create_group failed: ${r['message']}';
    final gid = r['groupId'] as String?;
    if (gid == null || gid.isEmpty) throw 'l3_create_group returned no groupId';
    return gid;
  }

  /// Group analog of [sendText]: send a text into a group the local account
  /// belongs to (FfiChatService.sendGroupText). When connected, the send
  /// persists synchronously to the group's LOCAL history as isSelf=true, keyed
  /// by the bare group id — readable via l3_dump_state{conversationId:group_<gid>}.
  Future<void> sendGroupText(String groupId, String text) async {
    final r = await callExt('ext.mcp.toolkit.l3_send_group_text', {
      'groupId': groupId,
      'text': text,
    });
    if (r['ok'] != true) throw 'l3_send_group_text failed: ${r['message']}';
  }

  /// S35: leave a group by its LOCAL group id.
  Future<void> leaveGroup(String groupId) async {
    final r = await callExt('ext.mcp.toolkit.l3_leave_group', {
      'groupId': groupId,
    });
    if (r['ok'] != true) throw 'l3_leave_group failed: ${r['message']}';
  }
}

Future<String> _findMainIsolate(VmService vm) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final isolates = (await vm.getVM()).isolates ?? const <IsolateRef>[];
    if (isolates.isNotEmpty) {
      for (final iso in isolates) {
        if ((iso.name ?? '').toLowerCase().contains('main')) return iso.id!;
      }
      return isolates.first.id!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw 'no isolate appeared on VM';
}
