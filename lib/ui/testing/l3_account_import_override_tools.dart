// L3 account-import override — `l3_set_account_import_pick_path`, the
// debug-only open-file seam the login page's "Restore from .tox file" /
// "Import Account" flows and the settings import read instead of the native
// picker.
//
// Split out of `l3_debug_tools.dart` (which is pinned in
// `tool/.complexity_baseline.txt`) as a `part`, because the handler reads the
// library-private `_activeAccountIsTest` / `_accountImportPickFilePathOverride`
// / `_normalizeExportSaveOverridePath` that stay in `l3_debug_tools.dart`.
//
// GUARD RULE: the test/seed-account guard exists to keep an accidentally
// enabled surface away from a REAL logged-in account's data. On a fresh install
// (or a signed-out login page) there is no such account, and without the
// override the restore/import flows cannot be driven at all — so the override
// is also allowed when NO account is active, and still refused while a live
// non-test account is active.

part of 'l3_debug_tools.dart';

/// True when nothing is signed in: no live session ([ActiveSession.current]),
/// no teardown in flight ([ActiveSession.pendingTeardown]) and no
/// current-account pointer (a fresh install, or after sign-out / deletion
/// cleared it). No single one is enough — the pointer is set before the
/// session boots, and a session can outlive a cleared pointer during
/// teardown.
Future<bool> _noAccountActive() async {
  if (ActiveSession.current != null) return false;
  if (ActiveSession.pendingTeardown != null) return false;
  final toxId = (await Prefs.getCurrentAccountToxId())?.trim() ?? '';
  return toxId.isEmpty;
}

/// Runs the `l3_set_account_import_pick_path` handler as the harness would,
/// so the guard rule above is testable without the MCP transport.
@visibleForTesting
Future<MCPCallResult> debugL3SetAccountImportPickPathForTests(
  Map<String, String> request,
) async => _l3SetAccountImportPickPathEntry().value.handler(request);

MCPCallEntry _l3SetAccountImportPickPathEntry() => MCPCallEntry.tool(
  handler: (request) async {
    // Allowed with no account active at all (nothing to protect) or for a
    // test/seed account; refused for a live non-test account.
    if (!await _noAccountActive() && !await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_set_account_import_pick_path: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    // PREFER contentB64 (attachment-seam contract): a host /tmp path is
    // unreadable in-sandbox — the APP materializes the bytes instead.
    final contentB64 = request['contentB64']?.toString();
    if (contentB64 != null && contentB64.isNotEmpty) {
      final name = (request['fileName']?.toString().trim().isNotEmpty ?? false)
          ? request['fileName']!.toString().trim()
          : 'l3_import.tox';
      final List<int> bytes;
      try {
        bytes = base64Decode(contentB64);
      } on FormatException catch (e) {
        return MCPCallResult(
          message:
              'l3_set_account_import_pick_path: contentB64 not valid base64: '
              '$e',
          parameters: {'ok': false, 'error': 'bad_base64'},
        );
      }
      final dir = await Directory.systemTemp.createTemp('l3import');
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(bytes);
      _accountImportPickFilePathOverride = f.path;
      AppLogger.info(
        '[L3] l3_set_account_import_pick_path: materialized $name -> ${f.path}',
      );
      return MCPCallResult(
        message: 'account import pick override materialized',
        parameters: {'ok': true, 'path': f.path},
      );
    }
    final path = _normalizeExportSaveOverridePath(request['path']?.toString());
    _accountImportPickFilePathOverride = path;
    AppLogger.info(
      '[L3] l3_set_account_import_pick_path: '
      '${path == null ? "CLEARED" : "SET -> $path"}',
    );
    return MCPCallResult(
      message: path == null
          ? 'account import pick override cleared'
          : 'account import pick override set',
      parameters: {'ok': true, 'path': path, 'cleared': path == null},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_set_account_import_pick_path',
    description:
        'L3 TEST ONLY: set or clear the debug-only open-file override used '
        'by login restore/import flows (bypasses the native picker). Allowed '
        'for a test/seed account OR when no account is active at all (fresh '
        'install / signed-out login page — nothing to protect); refused '
        '(non_test_account) while a live non-test account is active. PREFER '
        '"contentB64" + "fileName" — a host /tmp "path" is unreadable '
        'in-sandbox. Empty path clears.',
    inputSchema: ObjectSchema(
      properties: {
        'path': StringSchema(
          description:
              'Absolute .tox/.zip path to return from account import pickFiles. '
              'Empty clears. Use only for already-app-accessible files.',
        ),
        'contentB64': StringSchema(
          description:
              'Base64 file bytes; the app writes them to a sandbox-readable '
              'temp file and returns THAT path. Preferred over "path".',
        ),
        'fileName': StringSchema(
          description: 'File name for the materialized contentB64 file.',
        ),
      },
    ),
  ),
);
