// The packaging gate's forbidden-symbol list must cover every test-only hook.
//
// WHY THIS EXISTS: tool/ci/assert_no_test_hooks.sh keeps TIM2TOX_ENABLE_TEST_HOOKS
// primitives out of anything we ship, and its list of names is hand-written. That
// worked exactly once. When a SECOND hook was added — one that sets the inbound
// group-receipt budgets, so the refusal path could be tested — the gate did not
// know about it, and a library carrying it would have passed: a shipped binary
// whose rate limits an attacker can set to 1 has no rate limits. Nothing failed;
// the omission was silent, and it was caught by a person reading a report.
//
// So this test reads the guarded region of the FFI header and fails if it
// declares a symbol the gate would not refuse. Adding a hook and forgetting to
// list it is now a red test rather than a hole in a release.
//
// It deliberately checks the DECLARATIONS rather than the built library: a test
// must not need a native build, and the header is the thing a reviewer reads.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Symbol names declared between `#ifdef TIM2TOX_ENABLE_TEST_HOOKS` and its
/// `#endif`, in declaration order.
List<String> gatedFfiSymbols(String header) {
  final out = <String>[];
  var inside = false;
  for (final raw in header.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('#ifdef TIM2TOX_ENABLE_TEST_HOOKS')) {
      inside = true;
      continue;
    }
    if (inside && line.startsWith('#endif')) {
      inside = false;
      continue;
    }
    if (!inside || line.startsWith('//')) continue;
    // `int tim2tox_ffi_name(` / `int32_t tim2tox_ffi_name(` — the FFI boundary is
    // C, so a declaration is always `<type> <name>(`.
    final match = RegExp(r'\b(tim2tox_ffi_[A-Za-z0-9_]+)\s*\(').firstMatch(line);
    if (match != null) out.add(match.group(1)!);
  }
  return out;
}

/// Every name the gate would refuse, from its `FORBIDDEN_*="..."` assignments.
Set<String> forbiddenNames(String script) => RegExp(
      r'^FORBIDDEN_[A-Z_]*="([^"$]+)"',
      multiLine: true,
    ).allMatches(script).map((m) => m.group(1)!).toSet();

void main() {
  const headerPath = 'third_party/tim2tox/ffi/tim2tox_ffi.h';
  const gatePath = 'tool/ci/assert_no_test_hooks.sh';

  test('the gate refuses every gated FFI symbol the header declares', () async {
    final header = await File(headerPath).readAsString();
    final gate = await File(gatePath).readAsString();

    final gated = gatedFfiSymbols(header);
    expect(gated, isNotEmpty,
        reason: 'no gated symbols found — either the guard spelling changed or '
            'this parser is looking in the wrong place, and either way this '
            'test would silently pass forever');

    final forbidden = forbiddenNames(gate);
    expect(forbidden, isNotEmpty, reason: 'no FORBIDDEN_* names parsed from $gatePath');

    for (final symbol in gated) {
      expect(forbidden, contains(symbol),
          reason: '$headerPath declares $symbol inside the '
              'TIM2TOX_ENABLE_TEST_HOOKS region, but $gatePath would not refuse '
              'a library carrying it. Add it (and its C++ method, which is what '
              'survives in the static library) to FORBIDDEN_NAMES.');
    }
  });

  test('every forbidden name is matched as a substring, not a whole line',
      () async {
    // The C++ method is refused by its DEMANGLED-or-mangled substring, so the
    // gate must not anchor its comparison. If someone tightens it to an exact
    // match, the mangled `__ZN16V2TIMManagerImpl23Mm6SendCraftedChallenge...`
    // stops being caught and the static-library case reopens.
    final gate = await File(gatePath).readAsString();
    expect(gate, contains(r'*"$name"*'),
        reason: 'the nm-output comparison must stay a substring match');
    expect(gate, contains('grep -aq --'),
        reason: 'the byte-scan fallback must stay a substring match too');
  });

  test('a C++ counterpart is listed for each C wrapper', () async {
    // Every hook is a C wrapper over a V2TIMManagerImpl method. The wrapper is
    // what a .dylib exports; the method is what survives in libtim2tox.a. Both
    // spellings have to be listed, which is the mistake the first version of the
    // gate made.
    final gate = await File(gatePath).readAsString();
    final forbidden = forbiddenNames(gate);
    final cWrappers = forbidden.where((n) => n.startsWith('tim2tox_ffi_')).toSet();
    final cxxMethods = forbidden.difference(cWrappers);
    expect(cWrappers, isNotEmpty);
    expect(cxxMethods.length, greaterThanOrEqualTo(cWrappers.length),
        reason: 'each C wrapper needs its C++ method listed as well; '
            'wrappers=$cWrappers methods=$cxxMethods');
  });
}
