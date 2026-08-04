# S100 — Settings: Copy Tox ID button → OS clipboard (real tap)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any (Offline OK)`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned for the clipboard leg — the host pasteboard (`pbpaste`) is the only ground truth for the real `Clipboard.setData` write, and OS-clipboard cross-process verification is L3-only per `UI_TEST_LAYERING.md` §3. (An L1 could only check a `Clipboard` test-double, not the real OS write.) The id-EXPOSURE half is L1-promotable.
**Status**: covered (data-half gate exists; the real tap + OS clipboard write is L3, verified out-of-band). **S100 adds NO new executable gate — it is an extracted single-control subcase of S31** (the canonical self-id-copy scenario, which already drives this same Settings (V2) button in its Driver); do not count it as incremental coverage. The DATA half — `l3_dump_state.currentAccountToxId` exposes the seeded self id — is proven by `l3_self_id.json` (**S31**). The clipboard leg has NO JSON gate (cross-process) and is verified via `pbpaste`, exactly like S16/S31. This is the **Settings (V2)** entry point; S31 already runs both the Profile (V1) and Settings (V2) copy controls in one session.

## Precondition
- Account A signed in, plaintext profile; `Prefs.getCurrentAccountToxId()` returns the real 76-hex toxId (the value the copy button reads — the Tox ID row builder feeds `toxId` into the `IconButton`'s `onPressed`).
- macOS pasteboard pre-cleared: `pbcopy </dev/null`.
- `EXPECTED_TOXID` captured out-of-band (76 hex, `^[0-9a-fA-F]{76}$`) — e.g. `defaults read com.toxee.app 'flutter.current_account_tox_id'` (wire key `flutter.current_account_tox_id`, `lib/util/prefs.dart`), or read `l3_dump_state.currentAccountToxId`.
- App launched with the L3 surface: `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`, run `MCP_BINDING=marionette ./run_toxee.sh`.

## Executable Driver

```bash
# PROVEN data-half (S31, passes today): asserts l3_dump_state.currentAccountToxId exposes the seeded self id
dart run tool/mcp_test/run_l3_scenarios.dart tool/mcp_test/scenarios/l3_self_id.json

# Clipboard leg has NO JSON gate (cross-process). Verify out-of-band after the tap:
pbpaste   # must equal EXPECTED_TOXID (76 hex)
```

`l3_self_id.json` is read-only (no steps): it asserts `l3_dump_state.currentAccountToxId` contains the seeded fixture prefix `B4C5B0957C662A83` (sourced from `Prefs.getCurrentAccountToxId()`, the same persisted self identity the copy UI reads). That proves the id value is *exposed* to the copy path. The actual `Clipboard.setData(text: toxId)` write is NOT covered by any gate and stays verified out-of-band via `pbpaste` — there is intentionally no tap-gate for S100's clipboard leg (a JSON runner cannot read the OS pasteboard).

## UI Driver
1. Shell: `pbcopy </dev/null` — clear the pasteboard.
2. `marionette.tap(UiKeys.sidebarSettings)` (`sidebar_settings_tab`) — open the Settings screen.
3. `marionette.tap(UiKeys.settingsCopyToxIdButton)` (`settings_copy_tox_id_button`) — the copy `IconButton` in the Account card's Tox ID row at `lib/ui/settings/settings_page_build.dart:130`; `onPressed` → `Clipboard.setData(ClipboardData(text: toxId))` + a `ScaffoldMessenger` SnackBar with localized `idCopiedToClipboard` (`:137-149`).
4. Within ~1s (SnackBar auto-dismisses ~4s): capture the SnackBar via snapshot; shell `pbpaste`.

## Assertions
- A1 (pre-tap): clipboard empty (Step 1 cleared it).
- A2 (primary, clipboard write): after Step 3, `pbpaste` == `EXPECTED_TOXID`, 76 hex matching `^[0-9a-fA-F]{76}$` — the real OS clipboard received the full Tox ID.
- A3 (SnackBar): the localized `idCopiedToClipboard` SnackBar appeared (`settings_page_build.dart:144`).
- A4 (data-exposure, executable): `l3_dump_state.currentAccountToxId` contains `B4C5B0957C662A83` (the `l3_self_id.json` assertion) — proves the id the copy reads is exposed; equals the clipboard contents.
- A5 (placeholder-leak guard, primary): clipboard NEVER equals `FlutterUIKitClient` (the V2TIM login placeholder) — regression here would mean the copy handler regressed off the real `toxId`. Mirrors S31 A14.

## Notes
- L3-pin reason: the clipboard write is only observable on the host pasteboard (`pbpaste`); no JSON runner can read it. The id-exposure half IS executable (S31 `l3_self_id.json`). Key verified wired at `lib/ui/settings/settings_page_build.dart:130` (`key: UiKeys.settingsCopyToxIdButton`).
- Sibling distinction: **S31** is the canonical self-id copy scenario and ALREADY exercises this same Settings-V2 button (its Driver Step 8) plus the Profile-V1 button. S100 is the focused single-control real-tap of the Settings copy button; treat S31 as the superset.
- Seeded prefix: `l3_self_id.json` asserts `B4C5B0957C662A83`; note `8895A8D6` is a test-account-guard allowlist prefix, NOT this fixture's account (the older S31 doc text still cites `8895A8D6` — the gate JSON is the current source of truth).
- Settings copy uses raw `ScaffoldMessenger.showSnackBar` (default Material) while Profile uses `AppSnackBar.showSuccess` — assert by SnackBar text, not visual style.
- Other-platform clipboard reads: Linux `xclip -o -selection clipboard` (X11) / `wl-paste` (Wayland); Windows `powershell -Command Get-Clipboard`. The button + handler are shared Dart, so mobile hits the identical `Clipboard.setData` path.
