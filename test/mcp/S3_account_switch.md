# S3 — Account switch (sidebar refresh regression)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2 current=A autoLogin=on profileCrypt=plain network=online` (Fixture A2: two plaintext profiles on disk, A active)
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because the regression assertion includes the live DHT Online-transition after teardown+re-init (A2/A6, `Notified self online status (userID=<toxB>`); the sidebar-refresh tap + Prefs-write half is an L1/L2 candidate and the account export/import/switch internals are already unit-tested.
**Status**: reference playbook (single-instance, manual/agent-driven) — account switch + sidebar-refresh; not wired to an automated two-process gate (no cross-process state needed). Covered by the manual MCP playbook drive; account export/import/switch internals are unit-tested.
**Covered-by**: test/account_switch_resets_global_prefs_test.dart

Reference scenario for `doc/architecture/MCP_UI_TEST_PLAYBOOK.md` §5 S3. Written so
that an AI agent (Claude, Cursor, Codex, …) can drive it end-to-end against
a real toxee binary on macOS using the MCP routing matrix in §2 of the
playbook. Cross-platform variant left for follow-up; this file targets
macOS arm64 (the dev loop).

## 1. Summary

Verifies that tapping the swap-icon (`Icons.swap_horiz`) on another saved
account in the **Settings → Account list**, then confirming the dialog,
correctly tears down the current Tox session, re-initializes against the
target profile, and **refreshes the sidebar `_UserAvatar` so it reflects
the new account's nickname/avatar/status** (not the old one). This is the
2026-05-28 regression — the global Prefs (`nickname`, `statusMessage`,
`avatarPath`) used to keep the previous account's labels after
`AccountSwitcher.switchAccount(...)` returned, leaving the sidebar lying.

## 2. Why this matters

The fix lives in
`lib/util/account_service.dart` `initializeServiceForAccount` (see lines
~248–272): after a successful login it now explicitly writes
`Prefs.setNickname` / `Prefs.setStatusMessage` / `Prefs.setAvatarPath`
from the target account record, so `_UserAvatar._loadProfile()` in
`lib/ui/settings/sidebar.dart` (lines 311–327) reads the *new* identity on
the next rebuild. The fix is reinforced by commit
`6262139 fix(account): use real Tox ID instead of V2TIM placeholder for
persistence` — without it, `teardownCurrentSession` would clear the wrong
password slot and `touchAccountLoginTime` would stamp the placeholder
instead of the real toxId.

A failure here means a user who switched accounts in production would see
the old account's name on the new account's chat list — a privacy bug
class (sender confusion, screenshot misattribution) we want a regression
gate on.

## 3. Fixture — variant of A (two accounts on disk, one active)

Playbook §4 Fixture A is "single saved account, signed in"; this scenario
needs two profiles with one logged in. Call it **A2**.

State to set up before launching:

| Location | Required state |
|---|---|
| `~/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/profiles/p_<toxA_prefix16>/tox_profile.tox` | Account A — currently active. **Plaintext** (no profile password) to keep the test minimal. |
| `~/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/profiles/p_<toxB_prefix16>/tox_profile.tox` | Account B — the switch target. **Plaintext.** |
| `~/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/account_data/<toxA>/` | Present (any contents OK; can be empty). |
| `~/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/account_data/<toxB>/` | Present. |
| SharedPreferences `current_account_tox_id` | Set to **toxA** (the active account). |
| SharedPreferences `account_list` | JSON array containing **both** account records (`{toxId, nickname, statusMessage, ...}`). |
| SharedPreferences `self_nickname` | Account A's nickname (e.g. `hehe2`). |
| SharedPreferences `autoLogin` | `true` (so the boot path lands on HomePage, not LoginPage). |
| Env | `MCP_BINDING=marionette` — required for synthetic-gesture fallback (see Step 4). |

Reference identities (the actual 2026-05-28 repro run):

| Slot | Tox ID | Nickname |
|---|---|---|
| A (active) | `6065F792FFD78D27…` | `hehe2` |
| B (switch target) | `55743BB8A4CAC3F131DF93820955C45F774CD4359B9F0FD87B3A4D70C460DB2C` | `Imported Account` |

You can substitute your own pair — the assertions key off prefix matches
on whatever IDs the fixture has on disk.

## 4. Pre-flight

```bash
# (a) Kill any orphan Toxee from a prior run (otherwise VM URI grep will
#     return a stale port).
ps -ef | grep "Debug/Toxee.app" | grep -v grep | awk '{print $2}' | xargs -r kill

# (b) Build + launch the standalone bundle. DO NOT use `flutter run` —
#     DDS will reject the marionette/arenukvern WebSocket upgrade.
MCP_BINDING=marionette ./run_toxee.sh &

# (c) Wait until the Dart VM service announces itself, then convert the
#     HTTP URI to the ws:// form arenukvern + marionette expect.
LOG="$HOME/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/flutter_client.log"
for _ in $(seq 1 30); do
  URI=$(grep -oE "http://127\.0\.0\.1:[0-9]+/[A-Za-z0-9_=-]+" "$LOG" \
        | tail -1 | sed 's|http://|ws://|; s|/$|/ws|')
  case "$URI" in ws://*) break;; esac
  sleep 1
done
[ -z "$URI" ] && { echo "VM URI not found"; exit 1; }
echo "VM_URI=$URI"
```

Then in the MCP layer (parallel, both must succeed):

```jsonc
// arenukvern (semantic snapshots, screenshots, fmt_tap_widget)
fmt_connect_debug_app({ "mode": "uri", "uri": "$URI" })

// marionette (key-based synthetic taps — fallback for non-Semantics widgets)
marionette.connect({ "uri": "$URI" })
```

Verify both connections by calling:

```jsonc
fmt_get_vm({})                       // arenukvern — should return isolate info
marionette.get_interactive_elements()  // should return ≥10 nodes
```

## 5. Step-by-step

> Snapshot IDs (`snapshotId`) returned from `fmt_semantic_snapshot` are
> live — they expire on the next tree change. Re-snapshot before each
> tap that targets a `ref="s_N"`.

### Step 1 — Confirm we're on HomePage with Account A active

- **Call**: `fmt_semantic_snapshot({})`
- **Expected**: snapshot includes a node whose label matches the regex
  `^<nicknameA>\nOnline$` (or `\n(Connecting|Offline)` for the brief
  bootstrap window). For the reference fixture this is `hehe2\nOnline`.
- **Wait**: poll `fmt_semantic_snapshot` every 2s, up to **60s**, until the
  `\nOnline` line appears. Tox DHT bootstrap is 5–30s on a cold cache.
- **Also call**: `fmt_get_screenshots({ "mode": "flutter_layer", "compress": true })`
  — store as `s3_before.png` (used for the visual diff in Step 7).

### Step 2 — Open Settings

- **Call**: `marionette.tap({ "key": "sidebar_settings_tab" })`
  (key from `UiKeys.sidebarSettings`, snake_case wire value
  `sidebar_settings_tab`).
- **Expected**: marionette returns ok; widget tree now contains the
  account list rendered by `lib/ui/settings/settings_page_build.dart`.
- **Wait**: ≤2s. Re-snapshot with `fmt_semantic_snapshot({})`. There
  should now be a node labeled
  `<nicknameB>\n<short-toxIdB>` (the swap target row built by
  `_AccountListTile` in `lib/ui/settings/settings_page_widgets.dart`).
- **Fallback**: if the semantic tap silently no-ops (older builds), use
  `fmt_tap_widget({ "ref": "<s_N for 设置 in sidebar>", "snapshotId": "..." })`.

### Step 3 — Locate the non-current account row's swap-icon

- **Call**: `fmt_semantic_snapshot({})`. Search the returned nodes for one
  whose label contains the **target nickname** (B = `Imported Account` in
  the reference run) and **does not** contain the "(current)" / 当前
  chip. The swap-icon IconButton (`Icons.swap_horiz`) is the rightmost
  child of that row; in the 2026-05-28 trace it surfaced as semantic
  ref **`s_16`**, label `"Switch to this account"` /
  `"切换到此账号"` (tooltip from `AppLocalizations.switchToThisAccount`).
- **Note**: do not hardcode `s_16` — semantic refs are tree-order
  dependent and shift when the account list grows. Match by tooltip
  label.

### Step 4 — Tap the swap-icon

- **Call (preferred)**:
  ```jsonc
  fmt_tap_widget({ "ref": "<swap-icon ref>", "snapshotId": "<snapshotId from Step 3>" })
  ```
- **Expected**: a confirmation `AlertDialog` mounts with title `切换账号`
  (or `Switch Account` / locale equivalent) and body
  `确定要切换到 "<nicknameB>" 吗？您将被登出当前账号。`
- **Wait**: ≤2s. Verify by re-snapshotting and looking for the dialog
  action keys `settings_account_switch_confirm_button` /
  `settings_account_switch_cancel_button`. If the semantic tap no-ops, fall back to
  `marionette.tap({ "key": "settings_account_swap_button:<toxIdB>" })`
  — **this key does not exist yet**; see §8.

### Step 5 — Confirm the dialog

- **Preferred call**:
  `marionette.tap({ "key": "settings_account_switch_confirm_button" })`.
- **Fallback**: `fmt_tap_widget({ "ref": "<s_N for the 切换账号 button>", "snapshotId": "..." })`
  *(the second `切换账号` is the dialog action, not the title — pick the
  one whose semantic role is button)*.
- **Expected immediate log markers** (verified to exist in code):
  - `[ToxAVService] shutdown() called`
  - `[ffi] tim2tox_ffi_init_with_path: using initPath=…/p_<toxB_prefix16>`
  - `HandleSelfConnectionStatus: Notified self online status (userID=<toxB>…)`
- **Wait**: poll `fmt_get_recent_logs({ "limit": 200 })` every 2s, up to
  **45s**, for *all* of the markers above. Full teardown + re-init +
  reconnect typically takes 10–15s on a warm machine; budget 45s for
  CI / cold DHT.

### Step 6 — Wait for sidebar to re-render with Account B identity

- **Call**: `fmt_semantic_snapshot({})` every 2s, up to **30s**.
- **Expected**: the sidebar `_UserAvatar` node label transitions from
  `<nicknameA>\nOnline` → `<nicknameB>\nOnline`.
  For the reference fixture: `hehe2\nOnline` → `Imported Account\nOnline`
  (truncated to "Imported..." if the sidebar is in compact mode — match
  by prefix).

### Step 7 — Visual diff + final screenshot

- **Call**: `fmt_get_screenshots({ "mode": "flutter_layer", "compress": true })`
  → save as `s3_after.png`.
- **Optional**: compare `s3_before.png` vs `s3_after.png` — the sidebar
  region's average pixel hash should differ (avatar initials changed:
  `H` → `I` for the reference pair); the rest of the chrome should be
  visually similar.

## 6. Assertions (the regression test)

| # | What to assert | How |
|---|---|---|
| A1 | Before switch: sidebar label starts with `<nicknameA>` | semantic_snapshot in Step 1 |
| A2 | After switch: sidebar label starts with `<nicknameB>` | semantic_snapshot in Step 6 |
| A3 | `Prefs.currentAccountToxId` == toxB | Read `~/Library/Containers/com.toxee.app/Data/Library/Preferences/com.toxee.app.plist` via `defaults read com.toxee.app 'flutter.current_account_tox_id'` (Containers-scoped path; the wire key is snake_case — see `lib/util/prefs.dart:62`) |
| A4 | `Prefs.nickname` == nicknameB (the regression-fix assertion) | `defaults read com.toxee.app 'flutter.self_nickname'` (wire key — see `lib/util/prefs.dart:32`) |
| A5 | Active Tox profile dir is `p_<toxB_prefix16>` | grep log for `tim2tox_ffi_init_with_path: using initPath=…/p_<toxB_prefix16>` |
| A6 | Self online status fires for toxB | grep log for `Notified self online status (userID=<toxB>` |
| A7 | Account A's old session was torn down | grep log for `[ToxAVService] shutdown() called` *before* the new `init_with_path` line |
| A8 | No widget-tree exceptions during the swap | `official.get_runtime_errors({})` returns empty list (or only pre-existing benign ones — capture a baseline in Step 1) |

A1+A2 are the primary regression assertion. A4 is the bug that 2026-05-28
specifically introduced and that the `Prefs.setNickname(nickname)` in
`account_service.dart:258` now fixes.

## 7. Expected log grep targets

Tail
`~/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/flutter_client.log`
(or use `fmt_get_recent_logs`) for these substrings, in this order:

```
[ToxAVService] shutdown() called
[ffi] tim2tox_ffi_init_with_path: using initPath=
HandleSelfConnectionStatus: Notified self online status (userID=
```

Negative grep (must NOT appear after the switch):

```
HandleSelfConnectionStatus: Notified self online status (userID=<toxA_prefix>
```

— if Account A's connection status keeps firing after teardown, the old
session leaked.

## 8. UiKeys Status

Shipped in this workspace:

| Field name (camelCase) | Wire key (snake_case) | Where to attach | Why |
|---|---|---|---|
| `settingsAccountSwitchConfirmButton` | `settings_account_switch_confirm_button` | `lib/ui/settings/settings_page.dart:244-247` (the TextButton in the confirm dialog whose label is `switchAccount`) | Locale-stable confirm action for Step 5 |
| `settingsAccountSwitchCancelButton` | `settings_account_switch_cancel_button` | `lib/ui/settings/settings_page.dart:240-243` | Symmetric cancel action for the negative path |

Still pending follow-up anchors:

| Field name (camelCase) | Wire key (snake_case) | Where to attach | Why |
|---|---|---|---|
| `settingsAccountTile` (dynamic) | `settings_account_tile:<toxId>` | `lib/ui/settings/settings_page_widgets.dart:73` (the outer `Card` / `ListTile` for each `_AccountListTile`) | Reliable per-account row anchor; lets the test locate B without scanning labels |
| `settingsAccountSwapButton` (dynamic) | `settings_account_swap_button:<toxId>` | `lib/ui/settings/settings_page_widgets.dart:103` (the `IconButton(Icons.swap_horiz, ...)`) | Marionette fallback when semantic tap no-ops |
| `sidebarUserAvatar` | `sidebar_user_avatar` | `lib/ui/settings/sidebar.dart` (`_UserAvatar` root tap target; now live via `UiKeys.sidebarUserAvatar`) | So the assertion "label starts with `<nicknameB>`" can target the avatar node directly instead of pattern-matching labels |

## 9. Remaining source code changes

Tracking only — none of these are needed to *run* the scenario via the
semantic-label fallbacks above, but adding them makes the test robust
against locale changes, theme changes, and account-list reordering.

| File:line | Change type | Rationale |
|---|---|---|
| `lib/ui/testing/ui_keys.dart` (Settings section) | Add the remaining 3 keys listed in §8 | Anchor the scenario on keys rather than label substrings |
| `lib/ui/settings/settings_page_widgets.dart:73` | Attach `key: ValueKey('settings_account_tile:$toxId')` to the `_AccountListTile` `Card` | Per-row anchor |
| `lib/ui/settings/settings_page_widgets.dart:102-106` | Attach `key: ValueKey('settings_account_swap_button:$toxId')` to the swap `IconButton` | Marionette tap target |
| `lib/ui/settings/sidebar.dart` (`_UserAvatar` root) | Already live via `UiKeys.sidebarUserAvatar` | Locale-stable sidebar identity anchor |

All changes are additive (new `key:` parameters on existing widgets);
none change behavior.

## 10. Known blockers + workarounds

| Blocker | Impact | Workaround |
|---|---|---|
| Native file picker can't be driven by MCP | N/A here — S3 only switches between *existing* on-disk accounts, never imports | n/a |
| macOS Screen Recording permission not granted | `fmt_get_screenshots` with default `mode` fails | Use `mode: "flutter_layer"` (Flutter-layer capture, doesn't need the permission). All screenshot calls in this playbook already specify it. |
| DDS interposing on `flutter run` | marionette + arenukvern WebSocket upgrades rejected | Always launch via `./run_toxee.sh` (standalone bundle). Never `flutter run` for this scenario. |
| Tox DHT bootstrap latency 5–30s | Step 1 "wait for `\nOnline`" can take longer than expected | Allow 60s in Step 1, 45s in Step 5. Don't sleep — poll. |
| Orphan Toxee process after kill (bash wrapper exits, binary survives under launchd) | Stale VM port; new launch picks a different port, grep hits the wrong one | Pre-flight (a) — kill by `Debug/Toxee.app` regex, not by bash PID. |
| Account B requires a password (encrypted profile on disk) | `AccountSwitcher.switchAccount` opens a password dialog that this scenario doesn't drive | Fixture A2 explicitly requires both profiles **plaintext**. For the encrypted variant, write a separate scenario (S3b) — needs `marionette.enter_text` into the password field. |
| `arenukvern.fmt_tap_widget` silently no-ops on widgets without `Semantics.onTap` | Step 4/Step 5 taps go nowhere | Step 5 can now use `marionette.tap({ key: "settings_account_switch_confirm_button" })`; Step 4 still needs the pending swap-button key or a locale-fragile text fallback. |
| Sidebar `_UserAvatar` label is rebuilt on `setState` triggered by `_loadProfile()` which runs in `initState`, **not** on a profile-change stream | Theoretically the sidebar could miss the re-load if `_UserAvatarState` is reused across the switch | Per code review of `sidebar.dart:285`, `_UserAvatar` is unmounted/remounted when `HomePage` is replaced via `pushAndRemoveUntil` in `account_switcher.dart:97-101`, so `initState` re-fires. If a future refactor stops replacing the page, add a `_loadProfile()` trigger on `Prefs` change. |

## 11. Estimated runtime

| Phase | Wall clock |
|---|---|
| Pre-flight (kill + build + launch + VM URI grep) | 8–15s with a warm `./build/macos/Build/Products/Debug/` (no recompile); 60–120s after `--clean` |
| Steps 1–2 (HomePage stabilize + open Settings) | 5–30s (Tox bootstrap dominates) |
| Step 3 (semantic snapshot + locate swap-icon) | <1s |
| Steps 4–5 (tap swap, confirm dialog, wait for re-init) | 10–15s |
| Step 6 (sidebar re-renders) | 1–5s |
| Step 7 (screenshot) | <1s |
| **Happy path total** | **25–60s** after build is warm |
| **Max timeout budget (CI)** | **180s** end-to-end, with 60s Step 1 + 45s Step 5 + 30s Step 6 + slack |

Re-run cost is dominated by Tox DHT bootstrap — caching the DHT node list
across runs (which toxee already does via the bootstrap nodes pref) keeps
warm-cache runs at the low end of the range.
