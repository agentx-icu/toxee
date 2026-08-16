// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// TAP / KEY-RESOLUTION DIAGNOSTICS — shared by every case in the campaign.
//
// WHY THIS EXISTS. `Inst.tryTapKey` used to swallow the `skill('tap')` payload
// entirely: it looped, compared `success`, and returned a bare bool. That made
// three PHYSICALLY DIFFERENT failures indistinguishable in every campaign log:
//
//   1. the key is not in the widget tree at all      -> error.code E001
//      (`elementNotFound`, with flutter_skill's own `suggestions` list)
//   2. the key IS in the tree but its resolved centre lies outside the view
//      ±50 px, so flutter_skill REFUSES to dispatch  -> error.code E002
//      (`elementNotVisible`, carrying `position: {x, y}`)
//   3. the tap really was dispatched and the widget's callback did nothing
//      -> `success: true` and no observable effect
//
// Case (2) is the nasty one, because `ui_key_center` has NO viewport check
// while `tap` does: an off-edge control is "found" by `keyCenter` and "missing"
// to `tap`. Reading only the bool, a driver concludes "the sheet never mounted"
// when the truth is "the opener is off the right edge of this device". These
// helpers keep the payload so the FAIL message can say which of the three it
// was. Shared Dart in the driver — every platform's campaign benefits.

extension InstTapDiagnostics on Inst {
  /// [tryTapKey] that KEEPS the diagnosis.
  ///
  /// Same retry/backoff semantics as [tryTapKey] (that method is now a thin
  /// wrapper over this one, so no call site changes behaviour); the difference
  /// is that the LAST attempt's raw `skill('tap')` map comes back with the
  /// verdict instead of being dropped on the floor.
  Future<({bool ok, Map<String, dynamic> result})> tryTapKeyDetailed(
    String key, {
    int retries = 3,
  }) async {
    var last = <String, dynamic>{};
    for (var i = 0; i < retries; i++) {
      last = await skill('tap', {'key': key});
      if (last['success'] == true) return (ok: true, result: last);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return (ok: false, result: last);
  }

  /// Wait until [key]'s resolved centre STOPS MOVING, and report whether it did.
  ///
  /// WHY THIS IS NEEDED (root cause of a whole class of phantom "the control did
  /// nothing" failures). A coordinate tap is a two-step operation: the driver
  /// reads a centre over RPC, then dispatches a pointer at that point over a
  /// SECOND RPC. If the widget is mid-animation, it has moved between the two
  /// and the pointer lands on empty space — with no error anywhere, because
  /// every step "succeeded". Live on Android the multi-select toolbar resolved
  /// at x=419.4 and x=200.8 for a button that settles at x=40.0: the mobile
  /// composer swaps in the select-mode toolbar through an AnimatedSwitcher whose
  /// transitionBuilder is a `SlideTransition` from `Offset(1, 0)`
  /// (`..._message_input_mobile.dart:972-983`), i.e. it flies in from the RIGHT
  /// edge, so x sweeps the full viewport width while y stays put.
  ///
  /// Element-resolved `skill('tap')` is immune (it invokes the callback rather
  /// than a point), which is exactly why some cases appeared to work and others
  /// did not — the difference was never the control, it was the input path.
  ///
  /// Returns the settled `ui_key_center` map once [stableSamples] consecutive
  /// reads agree to within half a logical pixel, or null on timeout. Platform
  /// agnostic: iOS/iPad run the same AnimatedSwitcher, so this fixes them too.
  Future<Map<String, dynamic>?> waitKeyCenterSettled(
    String key, {
    int timeoutSecs = 10,
    int stableSamples = 2,
    Duration interval = const Duration(milliseconds: 150),
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    Map<String, dynamic>? previous;
    var stable = 0;
    while (DateTime.now().isBefore(deadline)) {
      final current = await keyCenterDetail(key);
      if (current != null && previous != null) {
        final dx = ((current['x'] as num) - (previous['x'] as num)).abs();
        final dy = ((current['y'] as num) - (previous['y'] as num)).abs();
        stable = (dx < 0.5 && dy < 0.5) ? stable + 1 : 0;
        if (stable >= stableSamples) return current;
      } else {
        stable = 0;
      }
      previous = current;
      await Future<void>.delayed(interval);
    }
    return null;
  }

  /// The RAW `ui_key_center` map for [key] (`x`, `y`, `w`, `h`, `onstage`,
  /// `candidates`, and the view's logical `viewWidth`/`viewHeight`), or null
  /// when the resolver could not find the key.
  ///
  /// [Inst.keyCenter] deliberately narrows this to (x, y); a case that is
  /// diagnosing a tap rejection needs the rest — above all the view extent the
  /// centre has to be compared against.
  Future<Map<String, dynamic>?> keyCenterDetail(String key) async {
    try {
      final r = await l3('ui_key_center', {'key': key});
      if (r['ok'] != true) return null;
      return r;
    } on DriveError {
      return null;
    }
  }
}

/// One-line rendering of a `skill('tap')` payload for campaign logs.
///
/// Deliberately prints the error CODE verbatim (E001 vs E002 is the whole
/// diagnosis) plus `position` when flutter_skill supplied it — that field is
/// only present on the off-screen rejection, so its presence alone identifies
/// the layout-overflow case.
String describeTapResult(Map<String, dynamic> r) {
  if (r.isEmpty) return '<no tap attempted>';
  final err = r['error'];
  final code = err is Map ? err['code'] : null;
  final message = err is Map ? err['message'] : null;
  final pos = r['position'];
  return [
    'success=${r['success']}',
    if (code != null) 'code=$code',
    if (pos != null) 'position=$pos',
    if (message != null) 'message=$message',
  ].join(' ');
}

/// EVERY `interactiveStructured` element carrying [key], in tree order, with the
/// bounds flutter_skill reports for it.
///
/// This is the view `Inst.tapKeyCenter` actually acts on: it scans the same list
/// and taps the LAST match with positive bounds. `interactiveStructured` has no
/// paint/cover/onstage guard, so a stale copy left behind by an AnimatedSwitcher
/// or a popped route is reported exactly like the live widget — and if the stale
/// one sorts last, the coordinate tap lands on it and silently does nothing.
/// Printing the whole list is the only way to see that from a log; a single
/// resolved centre cannot show it.
Future<List<String>> describeKeyMatches(Inst a, String key) async {
  try {
    final r = await a.skill('interactiveStructured', const {});
    final data = r['data'];
    final elements = data is Map ? data['elements'] : null;
    if (elements is! List) return const <String>[];
    final out = <String>[];
    for (final e in elements) {
      if (e is! Map || e['key'] != key) continue;
      final b = e['bounds'];
      out.add(b is Map ? 'bounds(x=${b['x']} y=${b['y']} w=${b['w']} h=${b['h']})' : 'bounds=<none>');
    }
    return out;
  } on Object catch (e) {
    return <String>['<dump unavailable: $e>'];
  }
}

/// One-line rendering of a `ui_key_center` payload, with an explicit verdict on
/// whether the centre is inside the window `tap` will accept.
String describeKeyCenter(Map<String, dynamic>? r) {
  if (r == null) return '<unresolved>';
  final x = (r['x'] as num?)?.toDouble();
  final y = (r['y'] as num?)?.toDouble();
  final vw = (r['viewWidth'] as num?)?.toDouble();
  final vh = (r['viewHeight'] as num?)?.toDouble();
  final parts = <String>[
    'x=$x',
    'y=$y',
    'w=${r['w']}',
    'h=${r['h']}',
    'onstage=${r['onstage']}',
    'candidates=${r['candidates']}',
    'view=${vw}x$vh',
  ];
  if (x != null && y != null && vw != null && vh != null) {
    // The exact predicate flutter_skill applies before dispatching (±50 px of
    // slack on every edge); recomputing it here turns "tap said no" into a
    // statement about geometry rather than a guess.
    final tappable = x >= -50 && x <= vw + 50 && y >= -50 && y <= vh + 50;
    parts.add('withinTapWindow=$tappable');
  }
  return parts.join(' ');
}
