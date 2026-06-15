// UI-drive MCP tools — REAL pointer-event primitives for the real-UI sweep
// campaign (see tool/mcp_test/REAL_UI_SWEEP_CAMPAIGN.md, Batch 0).
//
// WHY: flutter_skill (the default `skill` binding) only exposes tap / tapAt /
// enterText / waitForElement / interactiveStructured — it has NO scroll, drag,
// or secondary (right-click) primitive. Several sweep scenarios need to scroll
// a long list onstage, touch-drag a member list, or open the desktop chat
// message context menu (a right-click). These tools dispatch GENUINE pointer
// events through `GestureBinding.instance.handlePointerEvent`, so the SAME
// production hit-test / gesture / scroll-physics pipeline runs that a real user
// (or WidgetTester's TestPointer) drives. They do NOT re-implement any
// production behaviour — they only synthesize the input.
//
// SAFETY: registered ONLY behind [kDebugMode] (tree-shaken out of
// profile/release). UNGATED by the test-account guard on purpose: they are pure
// input plumbing (no data mutation of their own, no account-scoped side effect)
// that must work on FRESH non-test accounts — exactly like the ungated l3
// plumbing tools (l3_open_group_add_member / l3_set_active_conversation).
//
// MOBILE PARITY: this is shared Dart. The pointer-event dispatch + element
// resolution are platform-agnostic (the same widget tree exists on iOS/Android),
// so these tools apply to mobile builds automatically — `ui_drag` in particular
// synthesizes a TOUCH drag, the canonical mobile scroll gesture.
//
// Tools (callable as `ext.mcp.toolkit.ui_*`):
//   - ui_scroll_at  {key?|x,y?, dx?, dy}     one mouse-wheel PointerScrollEvent
//   - ui_drag       {key?|fromX,fromY?, dx?, dy, steps?} touch drag (down/moves/up)
//   - ui_secondary_tap {key?|x,y?}           right-button mouse down/up
//   - ui_long_press {key?|x,y?, holdMs?}     touch down → hold → up (long-press)
//
// Each returns {ok:true} or {ok:false, error:"..."} (+ a "candidates" count when
// a key resolves to multiple onstage matches, for debuggability).

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart';

import '../../util/logger.dart';

/// Unique pointer ids per dispatched gesture so successive/concurrent gestures
/// never collide on the same id (the arena/router keys state by pointer id).
int _uiDrivePointerSeq = 7000;
int _nextPointerId() => _uiDrivePointerSeq++;

/// Resolution outcome for a `{key?|x,y?}` target.
@visibleForTesting
class UiTargetResolution {
  UiTargetResolution.point(this.point, {this.candidates = 1}) : error = null;
  UiTargetResolution.failure(this.error)
    : point = null,
      candidates = 0;

  final Offset? point;
  final String? error;
  final int candidates;

  bool get ok => point != null;
}

/// Find the global CENTER point of the on-screen [RenderBox] for the widget
/// carrying `ValueKey(keyName)`. Onstage candidates are gathered by walking
/// `Element.debugVisitOnstageChildren` from the root — the canonical Flutter
/// traversal that test finders use, which an `Offstage(offstage:true)` AND an
/// `IndexedStack`'s hidden branches override to prune. That is the documented
/// hazard: a plain `visitChildren` walk matches keyed widgets inside offstage
/// IndexedStack subtrees (HomePage's IndexedStack tabs); the onstage walk skips
/// them. Each onstage candidate is still required to be an attached,
/// positively-sized RenderBox. When several ONSTAGE candidates remain the first
/// is used and `candidates` reflects the count.
@visibleForTesting
UiTargetResolution resolveKeyCenter(String keyName) {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) {
    return UiTargetResolution.failure('no_root_element');
  }
  bool matchesKey(Element element) {
    final key = element.widget.key;
    return key is ValueKey && key.value == keyName;
  }

  // Onstage walk: prunes offstage Offstage / IndexedStack branches.
  final onstage = <Element>[];
  void visitOnstage(Element element) {
    if (matchesKey(element) && _sizedBoxFor(element) != null) {
      onstage.add(element);
    }
    element.debugVisitOnstageChildren(visitOnstage);
  }

  visitOnstage(root);

  if (onstage.isNotEmpty) {
    final box = _sizedBoxFor(onstage.first)!;
    final center = box.localToGlobal(box.size.center(Offset.zero));
    return UiTargetResolution.point(center, candidates: onstage.length);
  }

  // No onstage match. Some pushed routes / overlays are NOT reached by
  // `debugVisitOnstageChildren` from the root in every layout (e.g. the desktop
  // group-profile route under the master-detail nested Navigator), even though
  // their widgets are genuinely laid out and ON SCREEN. Fall back to a FULL
  // `visitChildren` walk that still requires (a) an attached, positively-sized
  // RenderBox AND (b) no ancestor that hides it from paint. (b) is the guard
  // that keeps the IndexedStack/Offstage exclusion the onstage walk gives: a
  // non-selected IndexedStack child IS laid out (hasSize == true) but Flutter
  // 3.41 wraps it in `Visibility(visible:false, maintain*:true)` / an
  // `Offstage(offstage:true)`, so `_ancestorsPaint` returns false for it. A real
  // on-screen route the onstage walk missed has no such hiding ancestor and is
  // found — this is why a keyed FloatingActionButton / SelectableText in the
  // group profile (invisible to flutter_skill's interactiveStructured too)
  // becomes resolvable here.
  final full = <Element>[];
  void visitAllSized(Element element) {
    if (matchesKey(element) &&
        _sizedBoxFor(element) != null &&
        _ancestorsPaint(element)) {
      full.add(element);
    }
    element.visitChildren(visitAllSized);
  }

  visitAllSized(root);
  if (full.isNotEmpty) {
    // Prefer the LAST candidate: visitChildren walks the Navigator's routes in
    // stack order, so the most-recently-pushed (TOPMOST, visible) route's
    // element comes last. When several painting routes carry the same key (e.g.
    // a real-UI sweep re-opens the SAME group profile across cases and the
    // deep-link/avatar-tap routes accumulate — returnToChatsHome's
    // pushReplacement only replaces the top route, leaving buried duplicates),
    // `first` would resolve the OLDEST, off-screen, covered route (clear/leave
    // below the fold at a stale position, the mute switch un-tappable). The last
    // candidate is the on-top route the user actually sees. For the common
    // single-candidate case first == last, so this is a no-op there.
    final box = _sizedBoxFor(full.last)!;
    final center = box.localToGlobal(box.size.center(Offset.zero));
    return UiTargetResolution.point(center, candidates: full.length);
  }

  // Still nothing sized: distinguish "exists but only offstage/unsized" from
  // "absent" so a driver can tell a wrong-tab key from a typo.
  var existsAnywhere = false;
  void visitAll(Element element) {
    if (matchesKey(element)) existsAnywhere = true;
    element.visitChildren(visitAll);
  }

  visitAll(root);
  return UiTargetResolution.failure(
    existsAnywhere ? 'key_offstage_only:$keyName' : 'key_not_found:$keyName',
  );
}

/// The attached, positively-sized [RenderBox] for [element], or null when none
/// is available. `element.renderObject` already descends a ComponentElement
/// (FAB / SelectableText / KeyedSubtree) to its first descendant RenderObject,
/// so this resolves composite keyed widgets — but it must still be a laid-out
/// RenderBox for `localToGlobal`/`size.center` to be meaningful.
RenderBox? _sizedBoxFor(Element element) {
  final ro = element.renderObject;
  if (ro is RenderBox && ro.attached && ro.hasSize && !ro.size.isEmpty) {
    return ro;
  }
  return null;
}

/// True when no ancestor of [element] hides it from PAINT. Used by the
/// full-tree fallback in [resolveKeyCenter] to exclude laid-out-but-not-painted
/// widgets (a non-selected `IndexedStack` child, an `Offstage(offstage:true)`
/// branch, a `Visibility(visible:false)` subtree) while still accepting a real
/// on-screen route the onstage walk missed. Flutter 3.41 wraps IndexedStack's
/// hidden children in `Visibility(visible:false, maintain*:true)`, so checking
/// the `Offstage`/`Visibility` ancestors catches them even though they are
/// laid out (hasSize == true).
bool _ancestorsPaint(Element element) {
  var painted = true;
  element.visitAncestorElements((ancestor) {
    final w = ancestor.widget;
    if (w is Offstage && w.offstage) {
      painted = false;
      return false; // stop walking
    }
    if (w is Visibility && !w.visible) {
      painted = false;
      return false;
    }
    return true; // keep walking up
  });
  return painted;
}

/// Resolve a `{key?|x,y?}` request into a global point. `key` wins when present;
/// otherwise [xParam]/[yParam] are parsed as raw global coordinates.
@visibleForTesting
UiTargetResolution resolveTarget(
  String? key, {
  String? xParam,
  String? yParam,
}) {
  if (key != null && key.trim().isNotEmpty) {
    return resolveKeyCenter(key.trim());
  }
  final x = double.tryParse(xParam ?? '');
  final y = double.tryParse(yParam ?? '');
  if (x == null || y == null) {
    return UiTargetResolution.failure('need_key_or_xy');
  }
  return UiTargetResolution.point(Offset(x, y));
}

double _num(String? raw, double fallback) =>
    double.tryParse(raw ?? '') ?? fallback;

// ---------------------------------------------------------------------------
// Pure handlers — directly callable from tests (no MCP harness needed).
// They synthesize input via GestureBinding and pump live frames between moves.
// ---------------------------------------------------------------------------

/// One mouse-wheel scroll at the resolved point. Hit-testing for a
/// `PointerSignalEvent` happens inside `handlePointerEvent`, so the Scrollable
/// under [at] receives the scroll — the same mechanism WidgetTester's
/// `TestPointer.scroll` exercises.
@visibleForTesting
Map<String, Object?> uiScrollAtHandler({
  String? key,
  String? x,
  String? y,
  String? dx,
  String? dy,
}) {
  final resolved = resolveTarget(key, xParam: x, yParam: y);
  if (!resolved.ok) return {'ok': false, 'error': resolved.error};
  final delta = Offset(_num(dx, 0), _num(dy, 0));
  GestureBinding.instance.handlePointerEvent(
    PointerScrollEvent(
      position: resolved.point!,
      scrollDelta: delta,
      kind: PointerDeviceKind.mouse,
    ),
  );
  return {'ok': true, 'candidates': resolved.candidates};
}

/// Touch drag: PointerDown → N PointerMove → PointerUp, with a short awaited
/// delay between moves so the host pumps live frames and scroll physics engage.
/// In a hermetic widget test the caller pumps; the delay is harmless there.
@visibleForTesting
Future<Map<String, Object?>> uiDragHandler({
  String? key,
  String? fromX,
  String? fromY,
  String? dx,
  String? dy,
  String? steps,
  Duration stepDelay = const Duration(milliseconds: 16),
}) async {
  final resolved = resolveTarget(key, xParam: fromX, yParam: fromY);
  if (!resolved.ok) return {'ok': false, 'error': resolved.error};
  final start = resolved.point!;
  final total = Offset(_num(dx, 0), _num(dy, 0));
  final stepCount = int.tryParse(steps ?? '') ?? 12;
  final n = stepCount < 1 ? 1 : stepCount;
  final pointer = _nextPointerId();
  final binding = GestureBinding.instance;

  binding.handlePointerEvent(
    PointerDownEvent(
      pointer: pointer,
      position: start,
      kind: PointerDeviceKind.touch,
    ),
  );
  final perStep = total / n.toDouble();
  var current = start;
  for (var i = 0; i < n; i++) {
    current += perStep;
    binding.handlePointerEvent(
      PointerMoveEvent(
        pointer: pointer,
        position: current,
        delta: perStep,
        kind: PointerDeviceKind.touch,
      ),
    );
    // Only await a real inter-move delay when one is requested. In a live app
    // this lets frames pump so scroll physics engage; passing Duration.zero
    // (hermetic widget tests) skips the await entirely — a zero-duration
    // Future.delayed schedules a fake-async timer the test can't fire while the
    // handler is still suspended, which would deadlock the test (FakeAsync).
    if (stepDelay > Duration.zero) {
      await Future<void>.delayed(stepDelay);
    }
  }
  binding.handlePointerEvent(
    PointerUpEvent(
      pointer: pointer,
      position: current,
      kind: PointerDeviceKind.touch,
    ),
  );
  return {'ok': true, 'candidates': resolved.candidates};
}

/// Right-click: a secondary-button mouse PointerDown then PointerUp at the
/// resolved point. Drives the production secondary-tap handlers (e.g. the
/// desktop chat message menu's `Listener.onPointerDown` buttons check).
@visibleForTesting
Map<String, Object?> uiSecondaryTapHandler({String? key, String? x, String? y}) {
  final resolved = resolveTarget(key, xParam: x, yParam: y);
  if (!resolved.ok) return {'ok': false, 'error': resolved.error};
  final point = resolved.point!;
  final pointer = _nextPointerId();
  final binding = GestureBinding.instance;
  binding.handlePointerEvent(
    PointerDownEvent(
      pointer: pointer,
      position: point,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    ),
  );
  binding.handlePointerEvent(
    PointerUpEvent(
      pointer: pointer,
      position: point,
      kind: PointerDeviceKind.mouse,
      // Mouse-up reports no buttons held (the secondary button was released).
    ),
  );
  return {'ok': true, 'candidates': resolved.candidates};
}

/// Long-press: a touch PointerDown, a held delay, then PointerUp at the same
/// point. The hold (default 800 ms) sits past BOTH long-press deadlines in the
/// tree — the framework's `kLongPressTimeout` (500 ms) AND the fork's custom
/// conversation-row recognizer (`TencentCloudChatGesture`,
/// `LongPressGestureRecognizer(duration: 650 ms)`) — so the production
/// `onLongPress` handlers fire instead of falling through as a tap (which on a
/// conversation row would NAVIGATE). The MOBILE trigger twin of
/// [uiSecondaryTapHandler] (the message/conversation-row context menus open via
/// long-press on mobile, right-click on desktop). Same FakeAsync rule as
/// [uiDragHandler]: the await
/// only happens for a positive hold; hermetic tests start the future un-awaited
/// and `tester.pump(hold)` to advance fake time (which fires both the
/// recognizer's internal deadline timer and this handler's delay).
@visibleForTesting
Future<Map<String, Object?>> uiLongPressHandler({
  String? key,
  String? x,
  String? y,
  String? holdMs,
  Duration hold = const Duration(milliseconds: 800),
}) async {
  final resolved = resolveTarget(key, xParam: x, yParam: y);
  if (!resolved.ok) return {'ok': false, 'error': resolved.error};
  final point = resolved.point!;
  final parsedMs = int.tryParse(holdMs ?? '');
  final holdFor = parsedMs != null ? Duration(milliseconds: parsedMs) : hold;
  final pointer = _nextPointerId();
  final binding = GestureBinding.instance;
  binding.handlePointerEvent(
    PointerDownEvent(
      pointer: pointer,
      position: point,
      kind: PointerDeviceKind.touch,
    ),
  );
  if (holdFor > Duration.zero) {
    await Future<void>.delayed(holdFor);
  }
  binding.handlePointerEvent(
    PointerUpEvent(
      pointer: pointer,
      position: point,
      kind: PointerDeviceKind.touch,
    ),
  );
  return {'ok': true, 'candidates': resolved.candidates};
}

/// Resolve the on-screen global center (x,y) of a keyed widget — READ-ONLY (no
/// input dispatched). Lets the harness tell whether a keyed but NON-interactive
/// scroll anchor (e.g. a SizedBox wrapping a SegmentedButton, whose per-segment
/// labels aren't surfaced by flutter_skill's interactiveStructured) is within the
/// visible viewport before tapping a child of it. Returns {ok, x?, y?, error?}.
@visibleForTesting
Map<String, Object?> uiKeyCenterHandler({String? key}) {
  if (key == null || key.trim().isEmpty) {
    return {'ok': false, 'error': 'need_key'};
  }
  final resolved = resolveKeyCenter(key.trim());
  if (!resolved.ok) return {'ok': false, 'error': resolved.error};
  final p = resolved.point!;
  return {'ok': true, 'x': p.dx, 'y': p.dy, 'candidates': resolved.candidates};
}

MCPCallResult _result(Map<String, Object?> r) => MCPCallResult(
  message: r['ok'] == true ? 'ok' : 'error: ${r['error']}',
  parameters: r,
);

// ---------------------------------------------------------------------------
// Thin MCP registration around the pure handlers.
// ---------------------------------------------------------------------------

MCPCallEntry _uiScrollAtEntry() => MCPCallEntry.tool(
  handler: (request) async => _result(
    uiScrollAtHandler(
      key: request['key'],
      x: request['x'],
      y: request['y'],
      dx: request['dx'],
      dy: request['dy'],
    ),
  ),
  definition: MCPToolDefinition(
    name: 'ui_scroll_at',
    description:
        'DEBUG-ONLY (ungated): dispatch one mouse-wheel PointerScrollEvent at a '
        'widget key center (key) or raw global coords (x,y), with dx/dy delta. '
        'Runs the real hit-test/scroll pipeline. Returns {ok, error?, candidates}.',
    inputSchema: ObjectSchema(
      properties: {
        'key': StringSchema(description: 'ValueKey of the scroll point center.'),
        'x': StringSchema(description: 'Raw global x (when no key).'),
        'y': StringSchema(description: 'Raw global y (when no key).'),
        'dx': StringSchema(description: 'Horizontal scroll delta (default 0).'),
        'dy': StringSchema(description: 'Vertical scroll delta (down positive).'),
      },
    ),
  ),
);

MCPCallEntry _uiDragEntry() => MCPCallEntry.tool(
  handler: (request) async => _result(
    await uiDragHandler(
      key: request['key'],
      fromX: request['fromX'],
      fromY: request['fromY'],
      dx: request['dx'],
      dy: request['dy'],
      steps: request['steps'],
    ),
  ),
  definition: MCPToolDefinition(
    name: 'ui_drag',
    description:
        'DEBUG-ONLY (ungated): touch-drag (PointerDown -> N PointerMove -> '
        'PointerUp) from a key center (key) or raw coords (fromX,fromY) by '
        '(dx,dy) over steps moves (default 12). Engages real scroll physics; '
        'mobile-style touch scroll. Returns {ok, error?, candidates}.',
    inputSchema: ObjectSchema(
      properties: {
        'key': StringSchema(description: 'ValueKey of the drag start center.'),
        'fromX': StringSchema(description: 'Raw global start x (when no key).'),
        'fromY': StringSchema(description: 'Raw global start y (when no key).'),
        'dx': StringSchema(description: 'Total horizontal drag (default 0).'),
        'dy': StringSchema(description: 'Total vertical drag (up negative).'),
        'steps': StringSchema(description: 'Number of move events (default 12).'),
      },
    ),
  ),
);

MCPCallEntry _uiSecondaryTapEntry() => MCPCallEntry.tool(
  handler: (request) async => _result(
    uiSecondaryTapHandler(
      key: request['key'],
      x: request['x'],
      y: request['y'],
    ),
  ),
  definition: MCPToolDefinition(
    name: 'ui_secondary_tap',
    description:
        'DEBUG-ONLY (ungated): right-click (secondary-button mouse PointerDown '
        'then PointerUp) at a key center (key) or raw coords (x,y). Opens the '
        'desktop chat message context menu. Returns {ok, error?, candidates}.',
    inputSchema: ObjectSchema(
      properties: {
        'key': StringSchema(description: 'ValueKey of the right-click center.'),
        'x': StringSchema(description: 'Raw global x (when no key).'),
        'y': StringSchema(description: 'Raw global y (when no key).'),
      },
    ),
  ),
);

MCPCallEntry _uiLongPressEntry() => MCPCallEntry.tool(
  handler: (request) async => _result(
    await uiLongPressHandler(
      key: request['key'],
      x: request['x'],
      y: request['y'],
      holdMs: request['holdMs'],
    ),
  ),
  definition: MCPToolDefinition(
    name: 'ui_long_press',
    description:
        'DEBUG-ONLY (ungated): long-press (touch PointerDown, hold holdMs — '
        'default 800 ms, past the 500 ms framework timeout AND the fork '
        'conversation-row recognizer at 650 ms — then PointerUp) at a key '
        'center (key) or raw coords (x,y). Drives the production onLongPress '
        'handlers (the mobile context-menu trigger). '
        'Returns {ok, error?, candidates}.',
    inputSchema: ObjectSchema(
      properties: {
        'key': StringSchema(description: 'ValueKey of the long-press center.'),
        'x': StringSchema(description: 'Raw global x (when no key).'),
        'y': StringSchema(description: 'Raw global y (when no key).'),
        'holdMs': StringSchema(
          description: 'Hold duration in ms (default 600; >500 long-presses).',
        ),
      },
    ),
  ),
);

MCPCallEntry _uiKeyCenterEntry() => MCPCallEntry.tool(
  handler: (request) async => _result(uiKeyCenterHandler(key: request['key'])),
  definition: MCPToolDefinition(
    name: 'ui_key_center',
    description:
        'DEBUG-ONLY (ungated): READ-ONLY — resolve the on-screen global center '
        '(x,y) of a keyed widget without dispatching any input. Returns '
        '{ok, x?, y?, error?, candidates?}. Lets the harness check whether a '
        'keyed (possibly non-interactive) scroll anchor is within the viewport.',
    inputSchema: ObjectSchema(
      properties: {
        'key': StringSchema(description: 'ValueKey to resolve the center of.'),
      },
    ),
  ),
);

/// Register the UI-drive pointer tools. No-op outside [kDebugMode]
/// (tree-shaken from profile/release). Call after
/// `MCPToolkitBinding.instance.initialize()` in `main()`. UNGATED — these are
/// pure input plumbing and must work on fresh non-test accounts.
void registerUiDriveToolsIfDebug() {
  if (!kDebugMode) return;
  AppLogger.info(
    '[ui-drive] Registering pointer-event tools '
    '(ui_scroll_at, ui_drag, ui_secondary_tap, ui_long_press, ui_key_center).',
  );
  addMcpTool(_uiScrollAtEntry());
  addMcpTool(_uiDragEntry());
  addMcpTool(_uiSecondaryTapEntry());
  addMcpTool(_uiLongPressEntry());
  addMcpTool(_uiKeyCenterEntry());
}
