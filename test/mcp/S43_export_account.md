# S43 — Export account → native save dialog

**Layer**: L3 (MCP playbook)
**Fixture vector** (S43a): `accounts=1 current=A profileCrypt=plain autoLogin=on network=online`
**Fixture vector** (S43b): `accounts=1 current=A profileCrypt=pwd:<P_ACCOUNT> autoLogin=on network=online` (export sealed with a DIFFERENT `<P_EXPORT>`)
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because the macOS native save dialog (`FilePicker.platform.saveFile`) cannot be driven by MCP; promotes to L2 only behind a debug-gated picker override (see Notes)
**Status**: covered (profile `.tox` export path, sandbox-safe destination)

## Precondition
- One signed-in account A on HomePage; settings reachable via `sidebarSettings`.
- **S43a**: export confirmed with an EMPTY export password → unencrypted `.tox` (`passEncrypt`-free path), whether or not the account has a password.
- **S43b**: export sealed with `<P_EXPORT>`, deliberately different from the account password `<P_ACCOUNT>` (since A6, 2026-10-01, the export password is never the account password; in session the at-rest profile is opened with the session password).
- Save destination must be a writable, pre-known path **inside the app sandbox**
  (for example `~/Library/Containers/com.toxee.app/Data/Documents/...` on
  macOS). A raw `/tmp/...` path is rejected by the sandbox. Before Step 3, call
  `l3_set_export_save_path` with that absolute path; pre-clean it so the
  post-tap existence check is meaningful.
- `MCP_BINDING=marionette`.

## Driver
1. Wait for `<nicknameA>\nOnline` (60s poll).
2. `marionette.tap({key: "sidebar_settings_tab"})` (`UiKeys.sidebarSettings`).
3. Tap `Export Account` button — `AppLocalizations.exportAccount` = `Export Account` (`settings_page_build.dart:142-146`). No UiKey exists; tap by label/ref today (see Notes).
4. Format chooser opens (`_showExportOptions`, `settings_page.dart:277`) — bottom sheet on mobile, centered `Dialog` on desktop. Two `ListTile`s: `Profile (.tox)` (`exportOptionProfileTox`) and `Full Backup (.zip)` (`exportOptionFullBackup`). Tap `Profile (.tox)` → pops `'tox'` → `_exportAccount` (`settings_page.dart:343`).
5. EXPORT-password dialog (`ExportPasswordDialog`, title `Choose an export password`) — always, for protected and unprotected accounts; it never asks for the account password in session. Keys: `settings_export_password_field` / `_confirm_field` / `_ok_button` / `_cancel_button`; while the field is empty `settings_export_password_empty_warning` is shown. **S43a**: tap OK with both fields empty. **S43b**: enter `<P_EXPORT>` in both fields, tap OK. Mismatch → `passwordsDoNotMatch` SnackBar, dialog stays. `tool/mcp_test/drive_export_account.dart <ws> <out> [<P_EXPORT>]` drives this step.
6. App code reaches `runL3AwareExportSaveFilePicker(...)` in `_exportAccount`; on canonical L3 launches the previously-set `l3_set_export_save_path` override short-circuits the native macOS save panel and returns the fixed path. Without the override, desktop still falls through to `FilePicker.platform.saveFile(...)`.
7. After picker returns, `AccountExportService.exportAccountData(toxId, password, filePath)` writes the blob (`settings_page.dart:463`).

## Assertions
- A1: chooser shows exactly two options; `Profile (.tox)` pop value is `'tox'`.
- A2: the export-password dialog mounts before the save dialog in BOTH variants; no account-password prompt appears.
- A3: success SnackBar `accountExportedSuccessfully(filePath)` = `Account exported successfully to: <path>` (`settings_page.dart:472`).
- A4: written file exists at the chosen path with a `.tox` suffix — `_exportAccount` force-appends `.tox` if missing (`tox_file_io.dart:186-187`).
- A5 (S43a, plaintext): log `[AccountExportService] Export: No encryption, using plain profile` (`tox_file_io.dart:177-178`); first bytes are NOT the `toxEsave` magic.
- A6 (S43b, encrypted): the file opens with `<P_EXPORT>` and NOT with `<P_ACCOUNT>`; logs `[AccountExportService] Export: Encrypting with password...` then `Export: Encrypted to <N> bytes` (`tox_file_io.dart:166-170`); `head -c 8 <path>` == `toxEsave`.
- A7: terminal log `[AccountExportService] Account export successful: <path> (<N> bytes)` (`tox_file_io.dart:211-212`).
- A8: cancelling the save dialog (picker returns null) → no SnackBar, no write (`outputPath == null` early-return, `settings_page.dart:461`).
- Negative grep: `Export account error`, `Error writing export file`, `Export: Encryption error` must NOT appear (`settings_page.dart:479`, `tox_file_io.dart:215/172`).
- `official.get_runtime_errors({})` returns baseline.

## Notes
- App-side blocker resolved: `settings_page.dart` now routes export save
  selection through a debug-gated seam (`runL3AwareExportSaveFilePicker`)
  backed by `l3_set_export_save_path`. The override is only active behind
  `kDebugMode && bool.fromEnvironment('TOXEE_L3_TEST')`; outside that path
  export still uses the native save dialog.
- Verified 2026-05-30 via `tool/mcp_test/drive_export_account.dart` against a
  restored seeded account: export landed at
  `~/Library/Containers/com.toxee.app/Data/Documents/toxee_s43_export.tox`
  and produced a non-`toxEsave` prefix (plaintext profile export path).
- Wanted key `settingsExportAccountButton` (playbook §6b) is NOT in `ui_keys.dart`; tap by label `Export Account` / semantic ref today. Same for the chooser tiles and `Profile (.tox)` option.
- S43c (full-backup `.zip` branch via `_exportFullBackup`, `settings_page.dart:350`) deferred — same native save dialog, `<...>_backup.zip` default name, no per-format password gate.
- The label `Export Account` is reused as button, chooser title, AND `saveFile` `dialogTitle` — disambiguate by role/parent when keyless.
