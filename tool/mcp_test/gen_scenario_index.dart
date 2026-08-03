// Generates test/mcp/INDEX.en.md — the single source of truth for the L3 test
// coverage map (supersedes the hand-maintained current-state tables in
// tool/mcp_test/REAL_UI_TWO_PROCESS.md).
//
// Plan: tool/mcp_test/REAL_UI_TWO_PROCESS.md section 3.3 (task M5).
//
// Pure Dart: dart:io + dart:convert only. No VM connection, no third-party deps.
// Deterministic output (stable ordering, no timestamps) so `--check` is a clean
// freshness gate in CI.
//
// Inputs (read as ground truth):
//   1. tool/mcp_test/scenarios/*.json   — carry suite/order/feature/uiDriven
//   2. tool/mcp_test/fixture_c_manifest.json — two-process driver -> S-number map
//   3. test/mcp/S*.md                    — playbook headers (canonical block)
//
// Modes:
//   (default)                  (re)write test/mcp/INDEX.en.md
//   --check                    regenerate to memory + diff vs committed file;
//                              non-zero if stale OR on machine-owned invariant
//                              violations (schema, dangling feature, fabrication)
//   --warn-playbook-headers    additionally print (report-only) every playbook
//                              missing one of the five required header fields
//
// Usage:
//   dart run tool/mcp_test/gen_scenario_index.dart
//   dart run tool/mcp_test/gen_scenario_index.dart --check --warn-playbook-headers

import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Repo-relative locations. The script resolves the repo root from its own
/// path so it can be invoked via `dart run` from anywhere.
const String _scenariosRel = 'tool/mcp_test/scenarios';
const String _manifestRel = 'tool/mcp_test/fixture_c_manifest.json';
const String _playbooksRel = 'test/mcp';
const String _indexRel = 'test/mcp/INDEX.en.md';

const String _regenCmd = 'dart run tool/mcp_test/gen_scenario_index.dart';

/// Suites recognized by the scenario JSON schema (pinned spec).
const List<String> _suiteEnum = ['session', 'settings', 'c2c', 'group'];

/// The five header fields every playbook MUST carry (Covered-by is optional).
const List<String> _requiredHeaderFields = [
  'Layer',
  'Fixture vector',
  'Harness mode',
  'Promotion target',
  'Status',
];

/// Execution classes, in roster order.
const List<String> _classOrder = ['l3-gate', 'l3-gate-echo', 'l3-ui-single'];

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// A parsed scenario JSON (only the index-relevant fields).
class _Scenario {
  _Scenario({
    required this.fileName,
    required this.id,
    required this.suite,
    required this.order,
    required this.features,
    required this.uiDriven,
    required this.requiresEchoPeer,
    required this.nonBlocking,
  });

  final String fileName;
  final String id;
  final String suite; // may be '' when missing (schema violation)
  final int order;
  final List<String> features; // e.g. ['S46', 'S47']
  final bool uiDriven;
  final bool requiresEchoPeer;
  final bool nonBlocking;

  /// Execution class derived per the pinned partition spec:
  ///   partition = uiDriven ? 2 : (requiresEchoPeer ? 1 : 0)
  ///   0 -> l3-gate, 1 -> l3-gate-echo, 2 -> l3-ui-single
  String get executionClass {
    if (uiDriven) return 'l3-ui-single';
    if (requiresEchoPeer) return 'l3-gate-echo';
    return 'l3-gate';
  }
}

/// One entry from fixture_c_manifest.json.
class _ManifestEntry {
  _ManifestEntry({
    required this.script,
    required this.scenarios,
    required this.klass,
    required this.media,
    required this.destructive,
  });

  final String script;
  final List<String> scenarios; // S-numbers
  final String klass; // 2proc-l3 | 2proc-ui
  final bool media;
  final bool destructive;
}

/// A parsed playbook (test/mcp/S<k>_*.md).
class _Playbook {
  _Playbook({
    required this.sNumber,
    required this.fileName,
    required this.title,
    required this.header,
    required this.coveredBy,
    required this.missingFields,
  });

  /// Numeric part of the S-id (e.g. 96 for S96). Used for numeric sort.
  final int sNumber;
  final String fileName; // e.g. S96_settings_autologin_toggle.md
  final String title; // H1 minus the leading "# "
  final Map<String, String> header; // field label -> value (first match)
  final List<String> coveredBy; // paths from one or more **Covered-by** lines
  final List<String> missingFields; // required fields not present

  String get layer => header['Layer'] ?? '—';
  String get status => header['Status'] ?? '—';
}

// ---------------------------------------------------------------------------
// Schema violation reporting
// ---------------------------------------------------------------------------

/// A machine-owned invariant violation (hard-fails `--check`).
class _Violation {
  _Violation(this.where, this.message);
  final String where;
  final String message;
  @override
  String toString() => '$where: $message';
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  final bool checkMode = args.contains('--check');
  final bool warnHeaders = args.contains('--warn-playbook-headers');

  // Reject unknown flags so typos surface instead of silently no-op'ing.
  // NOTE: a returned int from main() is NOT used as the process exit code by
  // the Dart VM, so this script sets the top-level `exitCode` (and uses it as
  // the process code on normal completion) — CI gates on it.
  for (final a in args) {
    if (a == '--check' || a == '--warn-playbook-headers') continue;
    stderr.writeln('Unknown argument: $a');
    stderr.writeln('Usage: $_regenCmd [--check] [--warn-playbook-headers]');
    exitCode = 64;
    return;
  }

  final Directory repoRoot = _resolveRepoRoot();

  // --- Parse the three sources -------------------------------------------
  final List<_Violation> violations = <_Violation>[];

  final List<_Scenario> scenarios = _parseScenarios(repoRoot, violations);
  final List<_ManifestEntry> manifest = _parseManifest(repoRoot, violations);
  final List<_Playbook> playbooks = _parsePlaybooks(repoRoot);

  // Hard invariant: a JSON `feature` must point at an existing playbook.
  final Set<int> playbookNumbers = playbooks.map((p) => p.sNumber).toSet();
  for (final s in scenarios) {
    for (final f in s.features) {
      final int? n = _sNumberOf(f);
      if (n == null || !playbookNumbers.contains(n)) {
        violations.add(
          _Violation(
            s.fileName,
            'feature "$f" points at a nonexistent playbook '
            '(no test/mcp/S$n*_*.md)',
          ),
        );
      }
    }
  }

  // --- Build the S-number -> artifacts cross-reference -------------------
  // Scenario JSON ids that map to each S-number (via `feature`).
  final Map<int, List<_Scenario>> scenariosByS = <int, List<_Scenario>>{};
  for (final s in scenarios) {
    for (final f in s.features) {
      final int? n = _sNumberOf(f);
      if (n == null) continue;
      (scenariosByS[n] ??= <_Scenario>[]).add(s);
    }
  }

  // Fixture C scripts that map to each S-number (via manifest `scenarios`).
  final Map<int, List<_ManifestEntry>> scriptsByS =
      <int, List<_ManifestEntry>>{};
  for (final e in manifest) {
    for (final sc in e.scenarios) {
      final int? n = _sNumberOf(sc);
      if (n == null) continue;
      (scriptsByS[n] ??= <_ManifestEntry>[]).add(e);
    }
  }

  // --- Anti-fabrication guard --------------------------------------------
  // Codex-reviewed predicate (2026-06-03, two rounds; option iv): a playbook
  // FAILS the guard iff its Status makes an AFFIRMATIVE machine-coverage claim
  // AND no machine evidence resolves. This intentionally does NOT fire on the
  // many legitimate manual/agent-driven "covered" playbooks (they make no
  // executable-gate claim) — which is what keeps `--check` green on the
  // committed tree while still catching a fabricated gate (e.g. a Status that
  // says "covered by executable Fixture C gate — run_fixture_c_GHOST.sh" with
  // no such file). See tool/mcp_test/REAL_UI_TWO_PROCESS.md §3.3.
  final Map<int, _Playbook> playbookBySNumber = <int, _Playbook>{
    for (final p in playbooks) p.sNumber: p,
  };
  for (final p in playbooks) {
    if (!_statusHasAffirmativeMachineClaim(p.status)) continue;
    if (_hasResolvedMachineEvidence(
      p,
      repoRoot: repoRoot,
      scenariosByS: scenariosByS,
      scriptsByS: scriptsByS,
      playbookBySNumber: playbookBySNumber,
    )) {
      continue;
    }
    violations.add(
      _Violation(
        p.fileName,
        'Status makes an affirmative machine-coverage claim '
        '(executable/hermetic/runner gate) but no executable artifact resolves '
        '(no scenario JSON feature, no fixture-c manifest entry, no resolvable '
        '**Runner gate** / **Covered-by** file, no resolvable inline gate path)',
      ),
    );
  }

  // --- Header warnings (M9b input) ---------------------------------------
  final List<_Playbook> headerWarnPlaybooks = playbooks
      .where((p) => p.missingFields.isNotEmpty)
      .toList();

  // --- Render -------------------------------------------------------------
  final String rendered = _renderIndex(
    scenarios: scenarios,
    manifest: manifest,
    playbooks: playbooks,
    scenariosByS: scenariosByS,
    scriptsByS: scriptsByS,
    headerWarnPlaybooks: headerWarnPlaybooks,
  );

  final File indexFile = File('${repoRoot.path}/$_indexRel');

  // ----------------------------------------------------------------------
  // Mode dispatch
  // ----------------------------------------------------------------------
  if (checkMode) {
    // Uses the top-level `exitCode` from dart:io (process exit code on
    // completion). Defaults to 0; any violation/staleness below sets it to 1.
    if (violations.isNotEmpty) {
      stderr.writeln(
        'SCHEMA / INVARIANT VIOLATIONS '
        '(${violations.length}):',
      );
      for (final v in violations) {
        stderr.writeln('  - $v');
      }
      exitCode = 1;
    }

    // M9b decision (2026-06-03): the header backlog is ZERO after the canonical
    // normalization (the only apparent S43/S45 gap was a parser artifact for the
    // `**Fixture vector** (S43a):` variant form, now handled). Header
    // completeness is therefore folded into the hard --check
    // (_headerSchemaIsHard == true): a playbook missing any of the five required
    // fields fails the gate.
    if (_headerSchemaIsHard && headerWarnPlaybooks.isNotEmpty) {
      stderr.writeln(
        'PLAYBOOK HEADER VIOLATIONS '
        '(${headerWarnPlaybooks.length}):',
      );
      for (final p in headerWarnPlaybooks) {
        stderr.writeln(
          '  - ${p.fileName}: missing ${p.missingFields.join(", ")}',
        );
      }
      exitCode = 1;
    }

    if (!indexFile.existsSync()) {
      stderr.writeln('STALE: $_indexRel does not exist; run `$_regenCmd`.');
      exitCode = 1;
    } else {
      final String committed = indexFile.readAsStringSync();
      if (committed != rendered) {
        stderr.writeln('STALE: $_indexRel is out of date; run `$_regenCmd`.');
        exitCode = 1;
      }
    }

    if (warnHeaders) {
      _printHeaderWarnings(headerWarnPlaybooks);
    }

    if (exitCode == 0) {
      stdout.writeln(
        'INDEX up to date; '
        '${playbooks.length} playbooks, no invariant violations.',
      );
    }
    return;
  }

  // Default mode: (re)write the index.
  indexFile.writeAsStringSync(rendered);
  stdout.writeln(
    'Wrote $_indexRel '
    '(${playbooks.length} playbook rows).',
  );

  if (warnHeaders) {
    _printHeaderWarnings(headerWarnPlaybooks);
  }

  if (violations.isNotEmpty) {
    // In write mode, surface violations as a warning (do not block the write),
    // mirroring the runner's tolerant generate-then-validate posture.
    stderr.writeln(
      'NOTE: ${violations.length} invariant violation(s) '
      'detected (run --check to fail on these):',
    );
    for (final v in violations) {
      stderr.writeln('  - $v');
    }
  }
  // Default (write) mode always succeeds; exitCode stays 0.
}

/// M9b switch: header completeness is folded into the hard `--check` ONLY when
/// the playbook header backlog is empty.
///
/// Currently TRUE (M9b decision, 2026-06-03): after the playbooks were
/// normalized to the canonical header block, the residue is ZERO — every one of
/// the 118 `test/mcp/S*.md` files carries all five required fields (Layer /
/// Fixture vector / Harness mode / Promotion target / Status). The only two
/// apparent gaps (S43/S45) were a parser artifact: they use the
/// `**Fixture vector** (S43a):` variant-qualified form, which the field parser
/// now recognizes. With zero residue, header completeness is folded into the
/// hard `--check`: a playbook missing any required field fails the gate.
const bool _headerSchemaIsHard = true;

// ---------------------------------------------------------------------------
// Parsing — scenarios
// ---------------------------------------------------------------------------

List<_Scenario> _parseScenarios(
  Directory repoRoot,
  List<_Violation> violations,
) {
  final Directory dir = Directory('${repoRoot.path}/$_scenariosRel');
  if (!dir.existsSync()) {
    stderr.writeln('FATAL: scenarios dir not found: ${dir.path}');
    exit(70);
  }
  final List<File> files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final List<_Scenario> out = <_Scenario>[];
  final Set<String> seenIds = <String>{};

  for (final f in files) {
    final String name = _baseName(f.path);
    final dynamic decoded;
    try {
      decoded = jsonDecode(f.readAsStringSync());
    } catch (e) {
      violations.add(_Violation(name, 'invalid JSON: $e'));
      continue;
    }
    if (decoded is! Map) {
      violations.add(_Violation(name, 'top-level JSON is not an object'));
      continue;
    }
    final Map<String, dynamic> m = decoded.cast<String, dynamic>();

    // id: unique, non-empty.
    final dynamic idRaw = m['id'];
    final String id = idRaw is String ? idRaw : '';
    if (id.isEmpty) {
      violations.add(_Violation(name, 'missing or empty "id"'));
    } else if (!seenIds.add(id)) {
      violations.add(_Violation(name, 'duplicate "id": $id'));
    }

    // suite: required, in enum.
    final dynamic suiteRaw = m['suite'];
    String suite = '';
    if (suiteRaw is! String || suiteRaw.isEmpty) {
      violations.add(_Violation(name, 'missing required "suite"'));
    } else if (!_suiteEnum.contains(suiteRaw)) {
      violations.add(
        _Violation(
          name,
          'invalid "suite": "$suiteRaw" (expected one of $_suiteEnum)',
        ),
      );
      suite = suiteRaw;
    } else {
      suite = suiteRaw;
    }

    // order: int when present.
    int order = 50;
    if (m.containsKey('order')) {
      final dynamic o = m['order'];
      if (o is int) {
        order = o;
      } else {
        violations.add(_Violation(name, '"order" must be an int (got $o)'));
      }
    }

    // feature: array of "S<digits>" strings when present.
    final List<String> features = <String>[];
    if (m.containsKey('feature')) {
      final dynamic fe = m['feature'];
      if (fe is! List) {
        violations.add(_Violation(name, '"feature" must be an array'));
      } else {
        for (final item in fe) {
          if (item is String && _sNumberPattern.hasMatch(item)) {
            features.add(item);
          } else {
            violations.add(
              _Violation(
                name,
                '"feature" entry "$item" is not an "S<digits>" string',
              ),
            );
          }
        }
      }
    }

    // uiDriven: bool when present.
    bool uiDriven = false;
    if (m.containsKey('uiDriven')) {
      final dynamic u = m['uiDriven'];
      if (u is bool) {
        uiDriven = u;
      } else {
        violations.add(_Violation(name, '"uiDriven" must be a bool (got $u)'));
      }
    }

    final bool requiresEchoPeer = m['requiresEchoPeer'] == true;
    final bool nonBlocking = m['nonBlocking'] == true;

    out.add(
      _Scenario(
        fileName: name,
        id: id,
        suite: suite,
        order: order,
        features: features,
        uiDriven: uiDriven,
        requiresEchoPeer: requiresEchoPeer,
        nonBlocking: nonBlocking,
      ),
    );
  }
  return out;
}

// ---------------------------------------------------------------------------
// Parsing — manifest
// ---------------------------------------------------------------------------

List<_ManifestEntry> _parseManifest(
  Directory repoRoot,
  List<_Violation> violations,
) {
  final File f = File('${repoRoot.path}/$_manifestRel');
  if (!f.existsSync()) {
    stderr.writeln('FATAL: manifest not found: ${f.path}');
    exit(70);
  }
  final dynamic decoded;
  try {
    decoded = jsonDecode(f.readAsStringSync());
  } catch (e) {
    // Record as a violation (hard-fails --check) instead of crashing with an
    // uncaught FormatException, mirroring _parseScenarios's tolerant decode.
    violations.add(_Violation(_manifestRel, 'invalid JSON: $e'));
    return <_ManifestEntry>[];
  }
  if (decoded is! Map || decoded['entries'] is! List) {
    violations.add(_Violation(_manifestRel, 'missing "entries" array'));
    return <_ManifestEntry>[];
  }
  final List<_ManifestEntry> out = <_ManifestEntry>[];
  for (final e in (decoded['entries'] as List)) {
    if (e is! Map) continue;
    final String script = (e['script'] as String?) ?? '?';
    // Anti-fabrication hardening (codex final review P2): a manifest row whose
    // `script` does not resolve on disk must not count as coverage evidence —
    // otherwise a ghost `run_fixture_c_x.sh` entry would satisfy --check.
    // Record a hard violation and EXCLUDE the entry from artifact maps.
    if (!File('${repoRoot.path}/tool/mcp_test/$script').existsSync()) {
      violations.add(
        _Violation(
          _manifestRel,
          'entry "$script" does not resolve under tool/mcp_test/ '
          '(ghost script cannot serve as coverage evidence)',
        ),
      );
      continue;
    }
    final List<String> scenarios = <String>[];
    final dynamic sc = e['scenarios'];
    if (sc is List) {
      for (final item in sc) {
        if (item is String) scenarios.add(item);
      }
    }
    out.add(
      _ManifestEntry(
        script: script,
        scenarios: scenarios,
        klass: (e['class'] as String?) ?? '?',
        media: e['media'] == true,
        destructive: e['destructive'] == true,
      ),
    );
  }
  return out;
}

// ---------------------------------------------------------------------------
// Parsing — playbooks
// ---------------------------------------------------------------------------

List<_Playbook> _parsePlaybooks(Directory repoRoot) {
  final Directory dir = Directory('${repoRoot.path}/$_playbooksRel');
  if (!dir.existsSync()) {
    stderr.writeln('FATAL: playbooks dir not found: ${dir.path}');
    exit(70);
  }
  final RegExp sFile = RegExp(r'^S(\d+)_.*\.md$');
  final List<File> files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => sFile.hasMatch(_baseName(f.path)))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final List<_Playbook> out = <_Playbook>[];
  for (final f in files) {
    final String name = _baseName(f.path);
    final int sNum = int.parse(sFile.firstMatch(name)!.group(1)!);
    final List<String> lines = f.readAsLinesSync();

    // H1 title (first "# ..." line). Strip the leading "# ".
    String title = name; // fallback
    for (final l in lines) {
      final String t = l.trimRight();
      if (t.startsWith('# ')) {
        title = t.substring(2).trim();
        break;
      }
    }

    // Header fields. The canonical block is `**Label**: value`, but two
    // legitimate variant forms exist in the corpus and must NOT be read as a
    // missing field (codex/Verify-relevant):
    //   * qualifier OUTSIDE the bold — `**Fixture vector** (S43a): …`
    //     (S43/S45 carry two fixture variants);
    //   * qualifier INSIDE the bold — `**Runner gate (status-message leg)**: …`
    //     (S8's runner-gate leg).
    // So: capture the whole bold label, allow an optional ` (qualifier)` before
    // the colon, then strip any trailing ` (…)` from the captured label so both
    // forms normalize to the base field name. First match per label wins.
    final Map<String, String> header = <String, String>{};
    final List<String> coveredBy = <String>[];
    final RegExp fieldRe =
        RegExp(r'^\*\*([^*]+?)\*\*(?:\s*\([^)]*\))?:\s*(.*)$');
    final RegExp trailingQualifierRe = RegExp(r'\s*\([^)]*\)\s*$');
    for (final l in lines) {
      final Match? mm = fieldRe.firstMatch(l.trimRight());
      if (mm == null) continue;
      final String label =
          mm.group(1)!.replaceAll(trailingQualifierRe, '').trim();
      final String value = mm.group(2)!.trim();
      if (label == 'Covered-by') {
        if (value.isNotEmpty) coveredBy.add(value);
        continue;
      }
      header.putIfAbsent(label, () => value);
    }

    final List<String> missing = <String>[];
    for (final field in _requiredHeaderFields) {
      final String? v = header[field];
      if (v == null || v.isEmpty) missing.add(field);
    }

    out.add(
      _Playbook(
        sNumber: sNum,
        fileName: name,
        title: title,
        header: header,
        coveredBy: coveredBy,
        missingFields: missing,
      ),
    );
  }

  out.sort((a, b) => a.sNumber.compareTo(b.sNumber));
  return out;
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

String _renderIndex({
  required List<_Scenario> scenarios,
  required List<_ManifestEntry> manifest,
  required List<_Playbook> playbooks,
  required Map<int, List<_Scenario>> scenariosByS,
  required Map<int, List<_ManifestEntry>> scriptsByS,
  required List<_Playbook> headerWarnPlaybooks,
}) {
  final StringBuffer b = StringBuffer();

  // --- Header -------------------------------------------------------------
  b.writeln('# L3 Test Coverage Index (GENERATED — do not edit by hand)');
  b.writeln();
  b.writeln(
    'This file is GENERATED by `tool/mcp_test/gen_scenario_index.dart` '
    'from three sources of truth:',
  );
  b.writeln(
    'the scenario JSONs (`$_scenariosRel/*.json`), the Fixture C '
    'manifest (`$_manifestRel`),',
  );
  b.writeln(
    'and the L3 playbook headers (`$_playbooksRel/S*.md`). '
    'Edits here are overwritten.',
  );
  b.writeln();
  b.writeln('Regenerate: `$_regenCmd`');
  b.writeln();
  b.writeln(
    'Freshness gate (CI / pre-commit): '
    '`$_regenCmd --check --warn-playbook-headers`',
  );
  b.writeln();
  b.writeln(
    'Plan: `tool/mcp_test/REAL_UI_TWO_PROCESS.md` §3.3. '
    'Execution class is derived from each scenario JSON\'s flags:',
  );
  b.writeln(
    '`uiDriven` → `l3-ui-single`; else `requiresEchoPeer` → '
    '`l3-gate-echo`; else `l3-gate`.',
  );
  b.writeln();

  // --- Per-S table --------------------------------------------------------
  b.writeln('## Coverage by scenario (S-number)');
  b.writeln();
  b.writeln(
    'One row per L3 playbook (`test/mcp/S*.md`), numeric order. '
    '"Executable artifacts" lists the',
  );
  b.writeln(
    'machine-runnable gates that cover the scenario: L3 runner JSON '
    'ids (via each JSON\'s `feature`),',
  );
  b.writeln(
    'Fixture C two-process scripts (via `$_manifestRel`), and any '
    '`Covered-by:` flutter-test paths.',
  );
  b.writeln();
  b.writeln(
    '| S | Title | Layer | Exec class(es) | Executable artifacts | '
    'Status |',
  );
  b.writeln(
    '|---|-------|-------|----------------|----------------------|'
    '--------|',
  );

  for (final p in playbooks) {
    final List<String> classes = <String>[];
    final List<String> artifacts = <String>[];

    // L3 runner JSON ids (sorted by id for determinism).
    final List<_Scenario> sc = (scenariosByS[p.sNumber] ?? <_Scenario>[])
      ..sort((a, x) => a.id.compareTo(x.id));
    for (final s in sc) {
      final String nb = s.nonBlocking ? ' _(nonBlocking)_' : '';
      artifacts.add('`${s.id}` (${s.executionClass})$nb');
      if (!classes.contains(s.executionClass)) classes.add(s.executionClass);
    }

    // Fixture C scripts (sorted by script name for determinism).
    final List<_ManifestEntry> me =
        (scriptsByS[p.sNumber] ?? <_ManifestEntry>[])
          ..sort((a, x) => a.script.compareTo(x.script));
    for (final e in me) {
      final List<String> tags = <String>[];
      if (e.media) tags.add('media');
      if (e.destructive) tags.add('destructive');
      final String tagStr = tags.isEmpty ? '' : ' [${tags.join(", ")}]';
      artifacts.add('`${e.script}` (${e.klass})$tagStr');
      if (!classes.contains(e.klass)) classes.add(e.klass);
    }

    // Covered-by flutter-test paths.
    for (final cb in p.coveredBy) {
      artifacts.add('`$cb` (Covered-by)');
    }

    final String classStr = classes.isEmpty ? '—' : classes.join('<br>');
    final String artStr = artifacts.isEmpty
        ? '_(none — manual playbook)_'
        : artifacts.join('<br>');

    b.writeln(
      '| S${p.sNumber} | ${_cell(p.title)} | ${_cell(p.layer)} | '
      '$classStr | $artStr | ${_cell(_firstSentence(p.status))} |',
    );
  }
  b.writeln();

  // --- Per-class rosters --------------------------------------------------
  b.writeln('## Execution-class rosters (derived from scenario JSON flags)');
  b.writeln();

  for (final klass in _classOrder) {
    final List<_Scenario> members =
        scenarios.where((s) => s.executionClass == klass).toList()
          ..sort((a, x) {
            final int r = _suiteRank(a.suite).compareTo(_suiteRank(x.suite));
            if (r != 0) return r;
            final int o = a.order.compareTo(x.order);
            if (o != 0) return o;
            return a.fileName.compareTo(x.fileName);
          });
    b.writeln('### `$klass` (${members.length})');
    b.writeln();
    if (members.isEmpty) {
      b.writeln('_(no scenarios)_');
      b.writeln();
      continue;
    }
    b.writeln('| id | suite | order | feature | nonBlocking |');
    b.writeln('|----|-------|-------|---------|-------------|');
    for (final s in members) {
      final String feat = s.features.isEmpty ? '—' : s.features.join(', ');
      b.writeln(
        '| `${s.id}` | ${s.suite} | ${s.order} | $feat | '
        '${s.nonBlocking ? "yes" : "no"} |',
      );
    }
    b.writeln();
  }

  // --- Fixture C roster ---------------------------------------------------
  b.writeln('### Fixture C two-process drivers (`$_manifestRel`)');
  b.writeln();
  b.writeln('| script | scenarios | class | media | destructive |');
  b.writeln('|--------|-----------|-------|-------|-------------|');
  for (final e in manifest) {
    b.writeln(
      '| `${e.script}` | ${e.scenarios.join(", ")} | ${e.klass} | '
      '${e.media ? "yes" : "no"} | ${e.destructive ? "yes" : "no"} |',
    );
  }
  b.writeln();

  // --- Appendix: header warnings -----------------------------------------
  b.writeln('## Appendix: playbook header warnings');
  b.writeln();
  b.writeln(
    'Playbooks missing one of the five required header fields '
    '(${_requiredHeaderFields.join(" / ")}).',
  );
  b.writeln(
    'Hard-gated by `--check` (M9b: the residue is zero, so header '
    'completeness now fails the gate — plan §3.3 / M9).',
  );
  b.writeln();
  if (headerWarnPlaybooks.isEmpty) {
    b.writeln('_None — every playbook carries the full canonical header._');
  } else {
    b.writeln('| Playbook | Missing fields |');
    b.writeln('|----------|----------------|');
    final List<_Playbook> sorted = List<_Playbook>.from(headerWarnPlaybooks)
      ..sort((a, x) => a.sNumber.compareTo(x.sNumber));
    for (final p in sorted) {
      b.writeln('| `${p.fileName}` | ${p.missingFields.join(", ")} |');
    }
  }
  b.writeln();

  return b.toString();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

void _printHeaderWarnings(List<_Playbook> warnings) {
  if (warnings.isEmpty) {
    stdout.writeln(
      'Playbook headers: all complete '
      '(${_requiredHeaderFields.length} required fields present everywhere).',
    );
    return;
  }
  stdout.writeln(
    'Playbook header warnings (report-only, '
    '${warnings.length}):',
  );
  final List<_Playbook> sorted = List<_Playbook>.from(warnings)
    ..sort((a, x) => a.sNumber.compareTo(x.sNumber));
  for (final p in sorted) {
    stdout.writeln('  - ${p.fileName}: missing ${p.missingFields.join(", ")}');
  }
}

// ---------------------------------------------------------------------------
// Anti-fabrication guard (codex predicate, option iv)
// ---------------------------------------------------------------------------

/// Machine-coverage qualifier terms. A Status clause asserts machine coverage
/// when it contains "covered" together with one of these.
final RegExp _machineQualifierRe = RegExp(
  r'executable|hermetic|runner gate|fixture c gate',
  caseSensitive: false,
);

/// A negator appearing shortly (≤ ~30 chars) before a claim term suppresses the
/// clause, so "NOT a hermetic runner gate" / "no executable run_*.sh" /
/// "do not mark ... covered (executable)" do NOT trip the guard.
final RegExp _negatedClaimRe = RegExp(
  r'(\bno\b|\bnot\b|\bnever\b|n.t|do not)[^.]{0,30}'
  r'(covered|executable|hermetic|runner gate|fixture c gate)',
  caseSensitive: false,
);

/// TRIGGER: split Status into clauses on sentence punctuation; a clause fires
/// only if it contains "covered" AND a machine qualifier AND is not negated.
/// "driveable", "runner-assertable", "gate contract", "Maps to feature", and
/// "inventory §..." are deliberately NOT triggers.
bool _statusHasAffirmativeMachineClaim(String status) {
  for (final clause in status.split(RegExp(r'[.!?;]'))) {
    final String lc = clause.toLowerCase();
    if (!lc.contains('covered')) continue;
    if (!_machineQualifierRe.hasMatch(lc)) continue;
    if (_negatedClaimRe.hasMatch(lc)) continue;
    return true;
  }
  return false;
}

/// Extracts repo-relative artifact paths (a .sh / .json / .dart under tool/ or
/// test/) from an arbitrary text blob.
Iterable<String> _artifactPathsIn(String text) {
  return RegExp(
    r'(?:tool|test)/[A-Za-z0-9_./-]+\.(?:sh|json|dart)',
  ).allMatches(text).map((m) => m.group(0)!);
}

/// True if [repoRelOrToken] resolves to an existing file under the repo root,
/// trying the path as-is, then relative to tool/mcp_test, then by basename.
bool _fileResolves(Directory repoRoot, String repoRelOrToken) {
  final String root = repoRoot.path;
  if (File('$root/$repoRelOrToken').existsSync()) return true;
  if (File('$root/tool/mcp_test/$repoRelOrToken').existsSync()) return true;
  if (File('$root/tool/mcp_test/scenarios/$repoRelOrToken').existsSync()) {
    return true;
  }
  return false;
}

/// True if this S-number has a directly-resolvable executable artifact, used
/// both as the primary evidence test and (without the cross-ref recursion) as
/// the resolver for `covered by S<NN>` cross-references.
bool _hasDirectArtifact(
  _Playbook p, {
  required Directory repoRoot,
  required Map<int, List<_Scenario>> scenariosByS,
  required Map<int, List<_ManifestEntry>> scriptsByS,
}) {
  // (1) own resolved artifact: a scenario JSON feature or a manifest entry.
  if ((scenariosByS[p.sNumber]?.isNotEmpty ?? false) ||
      (scriptsByS[p.sNumber]?.isNotEmpty ?? false)) {
    return true;
  }
  // (2) **Runner gate** header naming an existing file.
  final String? runnerGate = p.header['Runner gate'];
  if (runnerGate != null) {
    for (final tok in _artifactPathsIn(runnerGate)) {
      if (_fileResolves(repoRoot, tok)) return true;
    }
  }
  // (3) **Covered-by** line naming an existing file.
  for (final cb in p.coveredBy) {
    for (final tok in _artifactPathsIn(cb)) {
      if (_fileResolves(repoRoot, tok)) return true;
    }
    // Covered-by may be a bare basename like foo_test.dart.
    if (cb.endsWith('.dart') && _fileResolves(repoRoot, cb.trim())) return true;
  }
  return false;
}

/// EVIDENCE: any of the four direct forms above, OR an inline Status gate path
/// that exists, OR a `covered by S<NN>` / `S<NN>'s gate` cross-reference whose
/// referenced playbook itself has a direct artifact. "Maps to feature **Fn**"
/// / "inventory §..." are NEVER counted as evidence.
bool _hasResolvedMachineEvidence(
  _Playbook p, {
  required Directory repoRoot,
  required Map<int, List<_Scenario>> scenariosByS,
  required Map<int, List<_ManifestEntry>> scriptsByS,
  required Map<int, _Playbook> playbookBySNumber,
}) {
  if (_hasDirectArtifact(
    p,
    repoRoot: repoRoot,
    scenariosByS: scenariosByS,
    scriptsByS: scriptsByS,
  )) {
    return true;
  }

  // (4b) an existing gate path mentioned inline in Status (sh/json/dart).
  for (final tok in _artifactPathsIn(p.status)) {
    if (_fileResolves(repoRoot, tok)) return true;
  }
  // Status also names bare gate files like `run_fixture_c_x.sh` / `l3_x.json`.
  for (final m in RegExp(
    r'run_fixture_c_[A-Za-z0-9_]+\.sh|l3_[A-Za-z0-9_]+\.json',
  ).allMatches(p.status)) {
    if (_fileResolves(repoRoot, m.group(0)!)) return true;
  }

  // (5) cross-reference: "covered by S<NN>" / "S<NN>'s gate" where the
  // referenced playbook has a direct artifact (no recursion into cross-refs).
  final Set<int> refs = <int>{};
  for (final m in RegExp(
    r"covered by S(\d+)",
    caseSensitive: false,
  ).allMatches(p.status)) {
    refs.add(int.parse(m.group(1)!));
  }
  for (final m in RegExp(r"S(\d+)'s gate").allMatches(p.status)) {
    refs.add(int.parse(m.group(1)!));
  }
  for (final n in refs) {
    if (n == p.sNumber) continue;
    final _Playbook? ref = playbookBySNumber[n];
    if (ref == null) continue;
    if (_hasDirectArtifact(
      ref,
      repoRoot: repoRoot,
      scenariosByS: scenariosByS,
      scriptsByS: scriptsByS,
    )) {
      return true;
    }
  }
  return false;
}

final RegExp _sNumberPattern = RegExp(r'^S\d+$');

/// Returns the numeric part of an "S<digits>" token, or null if it doesn't
/// match the pattern.
int? _sNumberOf(String token) {
  if (!_sNumberPattern.hasMatch(token)) return null;
  return int.parse(token.substring(1));
}

int _suiteRank(String suite) {
  switch (suite) {
    case 'session':
      return 0;
    case 'settings':
      return 1;
    case 'c2c':
      return 2;
    case 'group':
      return 3;
    default:
      return 99;
  }
}

String _baseName(String path) {
  final int i = path.lastIndexOf('/');
  return i < 0 ? path : path.substring(i + 1);
}

/// Escapes a value for safe inclusion in a Markdown table cell (pipes only;
/// the values are short header strings, not arbitrary prose).
String _cell(String v) => v.replaceAll('|', r'\|').trim();

/// Collapses a multi-clause Status to its first sentence so the table cell
/// stays readable. Splits on the first " — " (em-dash separator used in the
/// canonical headers) or the first period, whichever comes first.
String _firstSentence(String status) {
  String s = status.trim();
  final int dash = s.indexOf(' — ');
  final int dot = s.indexOf('. ');
  int cut = -1;
  if (dash >= 0 && (dot < 0 || dash < dot)) {
    cut = dash;
  } else if (dot >= 0) {
    cut = dot;
  }
  if (cut > 0) s = s.substring(0, cut);
  // Hard cap so a single very long clause cannot blow out the table width.
  const int cap = 120;
  if (s.length > cap) s = '${s.substring(0, cap - 1)}…';
  return s;
}

/// Resolves the repo root from this script's own location
/// (.../tool/mcp_test/gen_scenario_index.dart -> repo root two dirs up).
Directory _resolveRepoRoot() {
  final Uri self = Platform.script;
  if (self.scheme == 'file') {
    final String scriptPath = self.toFilePath();
    // .../tool/mcp_test/gen_scenario_index.dart
    final String mcpTestDir = _parentDir(scriptPath);
    final String toolDir = _parentDir(mcpTestDir);
    final String root = _parentDir(toolDir);
    final Directory d = Directory(root);
    // Sanity: the scenarios dir must exist under the resolved root.
    if (Directory('${d.path}/$_scenariosRel').existsSync()) return d;
  }
  // Fallback: assume CWD is the repo root (the documented invocation).
  final Directory cwd = Directory.current;
  if (Directory('${cwd.path}/$_scenariosRel').existsSync()) return cwd;
  stderr.writeln(
    'FATAL: cannot locate repo root '
    '(scenarios dir not found relative to script or CWD).',
  );
  exit(70);
}

String _parentDir(String path) {
  final int i = path.lastIndexOf('/');
  return i <= 0 ? '/' : path.substring(0, i);
}
