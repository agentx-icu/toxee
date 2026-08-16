part of 'ui_drive_tools.dart';

// MCP registration layer for the ui_drive pointer tools. Split out of
// `ui_drive_tools.dart` when that file crossed the complexity gate: the parent
// keeps the key RESOLVER + the pure, directly-testable pointer handlers, and
// this part keeps the thin `MCPCallEntry` wrappers, the tool schemas and
// `registerUiDriveToolsIfDebug` (plus the one-liner hide-keyboard handler they
// wrap). Pure move — tool names, schemas and handler bodies are unchanged.


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
        '{ok, x?, y?, w?, h?, viewWidth?, viewHeight?, error?, candidates?, '
        'onstage?}. `onstage:false` means the box was found only by the '
        'full-tree fallback (laid out, but covered by an opaque pushed route) — '
        'a gesture there hits the COVER. `viewWidth`/`viewHeight` are the view\'s '
        'LOGICAL size: this resolver has no viewport check, but flutter_skill\'s '
        '`tap` rejects any centre outside the view ±50 px with elementNotVisible, '
        'so compare (x,y) against them before blaming a missing key. Lets the '
        'harness check whether a keyed (possibly non-interactive) anchor is '
        'really inside the visible viewport.',
    inputSchema: ObjectSchema(
      properties: {
        'key': StringSchema(description: 'ValueKey to resolve the center of.'),
      },
    ),
  ),
);

/// Drop the primary focus, which closes the platform soft keyboard.
///
/// WHY (Android, 2026-08-15): the soft IME is an OS surface over the BOTTOM of
/// the screen, but widget geometry ignores it — so `interactiveStructured` /
/// `ui_key_center` report a button's centre while the keyboard sits ON that
/// point, and the harness dispatches a "successful" tap the IME swallows. (The
/// manual-bootstrap-node Test button resolved at y=583 of 914 and every press
/// was eaten.) `l3_pop_to_root` is no substitute: it pops the ROUTE, not the
/// keyboard. `unfocus()` is the ordinary production dismissal path, so this
/// reaches it rather than synthesizing anything. Shared Dart — iOS too.
@visibleForTesting
Map<String, Object?> uiHideKeyboardHandler() {
  final focus = FocusManager.instance.primaryFocus;
  if (focus == null) return {'ok': true, 'hadFocus': false};
  focus.unfocus();
  return {'ok': true, 'hadFocus': true};
}

MCPCallEntry _uiHideKeyboardEntry() => MCPCallEntry.tool(
  handler: (request) async => _result(uiHideKeyboardHandler()),
  definition: MCPToolDefinition(
    name: 'ui_hide_keyboard',
    description:
        'DEBUG-ONLY (ungated): drop the primary focus so the platform soft '
        'keyboard closes. Use before tapping a control in the lower half of a '
        'mobile screen after typing — the IME overlays the hit point while the '
        'widget geometry still reports it as visible. Returns {ok, hadFocus}.',
    inputSchema: ObjectSchema(properties: {}),
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
    '(ui_scroll_at, ui_drag, ui_secondary_tap, ui_long_press, ui_key_center, '
    'ui_hide_keyboard).',
  );
  addMcpTool(_uiScrollAtEntry());
  addMcpTool(_uiDragEntry());
  addMcpTool(_uiSecondaryTapEntry());
  addMcpTool(_uiLongPressEntry());
  addMcpTool(_uiKeyCenterEntry());
  addMcpTool(_uiHideKeyboardEntry());
}
