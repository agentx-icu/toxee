import 'dart:io';

/// Line-count guard for first-party Dart sources (`lib/` and `tool/`).
/// Run from project root: `dart run tool/check_complexity.dart`
///
/// Rules:
///   1. A file over [_maxLines] that is NOT in `tool/.complexity_baseline.txt`
///      fails the build. That is the "no new giant files" rule.
///   2. Baseline entries are a **ratchet**, not an amnesty: each entry pins the
///      line count it had when it was accepted (`path:lines`). Growing past the
///      pinned count fails. Shrinking is fine and prints a nudge to re-pin.
///      (Before the ratchet existed a baselined file could grow from 501 to
///      5000 lines and stay silent forever — that is the hole this closes.)
///   3. Code-generated files are exempt by path pattern, not by baseline, so
///      they never dilute the report. See [_generatedPatterns].
///
/// `--write-baseline` re-pins every surviving entry to its current size,
/// appends newly-detected offenders, drops entries that no longer exceed the
/// cap, and **preserves the human commentary** already in the baseline file.
void main(List<String> args) {
  final writeBaseline = args.contains('--write-baseline');

  if (!Directory(_scanRoots.first).existsSync()) {
    stderr.writeln('[complexity] ${_scanRoots.first}/ not found — run from the '
        'repository root');
    exit(1);
  }

  final offenders = <String, int>{};
  for (final root in _scanRoots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final file in _dartFiles(dir)) {
      final path = _normalize(file.path);
      if (_isGenerated(path)) continue;
      final lines = file.readAsLinesSync().length;
      if (lines > _maxLines) offenders[path] = lines;
    }
  }

  if (writeBaseline) {
    _writeBaseline(offenders);
    return;
  }

  final baseline = _loadBaseline(_baselinePath);
  var failures = 0;

  for (final path in offenders.keys.toList()..sort()) {
    final lines = offenders[path]!;
    if (!baseline.containsKey(path)) {
      stderr.writeln('[complexity] $path: $lines LOC (> $_maxLines) — not in '
          '$_baselinePath');
      failures++;
      continue;
    }
    final pinned = baseline[path];
    if (pinned == null) {
      // Legacy entry written before the ratchet existed. Warn-only so the
      // migration cannot turn CI red, but nag until it is pinned.
      stdout.writeln('[complexity] (baseline, UNPINNED) $path: $lines LOC — '
          'run `dart run tool/check_complexity.dart --write-baseline` to pin '
          'it so it cannot grow silently');
    } else if (lines > pinned) {
      stderr.writeln('[complexity] $path: $lines LOC — grew past its baseline '
          'pin of $pinned LOC. Baselined files may shrink, never grow.');
      failures++;
    } else if (lines < pinned) {
      stdout.writeln('[complexity] (baseline, shrank $pinned -> $lines) $path '
          '— re-pin with --write-baseline to lock the win in');
    } else {
      stdout.writeln('[complexity] (baseline) $path: $lines LOC');
    }
  }

  for (final path in baseline.keys.toList()..sort()) {
    if (offenders.containsKey(path)) continue;
    stdout.writeln('[complexity] (stale baseline entry) $path is no longer '
        'over the $_maxLines LOC cap — drop it with --write-baseline');
  }

  if (failures > 0) {
    stderr.writeln('[complexity] $failures violation(s). Split the file, or — '
        'only if unavoidable — re-pin it in $_baselinePath and explain why in '
        'the PR.');
    exit(1);
  }
}

const _maxLines = 500;
const _baselinePath = 'tool/.complexity_baseline.txt';

/// First-party Dart roots. `tool/` was added on 2026-08-07: several
/// `tool/mcp_test/*.dart` harness drivers were well past 1500 LOC with no
/// guard at all.
const _scanRoots = <String>['lib', 'tool'];

/// Generated outputs. They are exempt outright rather than baselined: they are
/// rewritten wholesale by their generator, so pinning a line count would just
/// produce noise on every regeneration, and listing them in the baseline made
/// the real technical-debt list look ~15% bigger than it is.
///   * `lib/i18n/app_localizations*.dart` — `flutter gen-l10n` output; see
///     `l10n.yaml` (`arb-dir: lib/l10n`, `output-dir: lib/i18n`).
///   * `*.g.dart` / `*.freezed.dart` — build_runner conventions.
final _generatedPatterns = <RegExp>[
  RegExp(r'^lib/i18n/app_localizations(_[A-Za-z0-9_]+)?\.dart$'),
  RegExp(r'\.g\.dart$'),
  RegExp(r'\.freezed\.dart$'),
];

bool _isGenerated(String path) =>
    _generatedPatterns.any((re) => re.hasMatch(path));

/// Recursive `.dart` walk that prunes dot-directories (`.dart_tool`,
/// `tool/mcp_test/.ios_runtime`, …) and `build/` output trees. `listSync(
/// recursive: true)` cannot prune, and under `tool/` those trees hold
/// generated/runtime junk that would both slow the scan and produce bogus
/// offenders.
Iterable<File> _dartFiles(Directory dir) sync* {
  for (final entity in dir.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entity is Directory) {
      if (name.startsWith('.') || name == 'build') continue;
      yield* _dartFiles(entity);
    } else if (entity is File && name.endsWith('.dart')) {
      yield entity;
    }
  }
}

/// Baseline entries: `path` (legacy, value `null`) or `path:lines` (pinned).
Map<String, int?> _loadBaseline(String path) {
  final file = File(path);
  if (!file.existsSync()) return <String, int?>{};
  final entries = <String, int?>{};
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parsed = _parseEntry(line);
    entries[parsed.path] = parsed.lines;
  }
  return entries;
}

({String path, int? lines}) _parseEntry(String line) {
  final colon = line.lastIndexOf(':');
  if (colon > 0) {
    final lines = int.tryParse(line.substring(colon + 1).trim());
    if (lines != null) {
      return (path: _normalize(line.substring(0, colon).trim()), lines: lines);
    }
  }
  return (path: _normalize(line), lines: null);
}

void _writeBaseline(Map<String, int> offenders) {
  final file = File(_baselinePath);
  final out = <String>[];
  final seen = <String>{};
  var dropped = 0;

  if (file.existsSync()) {
    // Rewrite in place so the "why is this file exempt" commentary survives.
    for (final raw in file.readAsLinesSync()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) {
        out.add(raw);
        continue;
      }
      final path = _parseEntry(line).path;
      seen.add(path);
      final lines = offenders[path];
      if (lines == null) {
        dropped++;
        stdout.writeln('[complexity] dropping $path (no longer > $_maxLines '
            'LOC)');
        continue;
      }
      out.add('$path:$lines');
    }
  } else {
    out.addAll(_defaultHeader);
  }

  final added = offenders.keys.where((p) => !seen.contains(p)).toList()..sort();
  if (added.isNotEmpty) {
    out.add('# Appended by --write-baseline on '
        '${DateTime.now().toIso8601String().split('T').first}:');
    for (final path in added) {
      out.add('$path:${offenders[path]}');
    }
  }

  file.writeAsStringSync('${out.join('\n')}\n');
  stdout.writeln('[complexity] baseline rewritten: ${offenders.length} '
      'entries (${added.length} added, $dropped dropped)');
}

const _defaultHeader = <String>[
  '# Files exempt from the complexity guard, pinned at the line count they had',
  '# when they were accepted. Format: <path>:<maxLines>.',
  '# Generated by `dart run tool/check_complexity.dart --write-baseline`.',
  '# Threshold: > $_maxLines LOC. Aim to shrink this list, not grow it.',
];

String _normalize(String p) => p.replaceAll('\\', '/');
