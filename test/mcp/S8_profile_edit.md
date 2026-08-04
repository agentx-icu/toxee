# S8 — Edit own profile (nickname + status message roundtrip)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because the self-profile dialog resolves the Tox ID asynchronously inside `showDialog` and the FFI `setSelfInfo` requires a live Tox handle (§2: "no widget tests cover this flow"); the status-message leg is already an executable hermetic runner gate (below).
**Runner gate (status-message leg)**: `tool/mcp_test/scenarios/l3_self_profile_toggle.json` (hermetic) — set/clear the own `statusMessage` via `l3_set_self_profile`, assert via `l3_dump_state.statusMessage` (enforces an empty-status start invariant so the restore is faithful). Nickname is intentionally NOT driven (mutating it would trip the test-account nickname guard); the avatar leg + the paired-peer-observes-change leg stay with S52.
**Status**: covered — the own-profile status-message roundtrip is now an executable hermetic gate (above); the nickname roundtrip + B-observes-the-change leg are exercised by the L3 self-profile path (`l3_set_self_profile` / S52 `run_fixture_c_self_profile.sh`); the prior account_list B-block was fixed (sidebar.dart). Single-instance nickname/avatar UI variant remains a manual playbook.
**Covered-by**: test/ui/profile_edit_persists_to_account_list_test.dart

> **2026-05-28**: the `account_list` mirror gap previously documented
> as a "B-block" failure has been fixed in
> `lib/ui/settings/sidebar.dart:70-84` (codex review #2 P1). The
> sections that called out the gap have been removed from this
> playbook; the assertions in §6 are now all green-path.

Reference scenario for `doc/architecture/MCP_UI_TEST_PLAYBOOK.md` §5 S8. Written so
that an AI agent (Claude, Cursor, Codex, …) can drive it end-to-end
against a real toxee binary on macOS using the MCP routing matrix in §2
of the playbook. macOS arm64 (the dev loop). Linux/Windows only differ
in the sandbox path roots (§3 / §4).

Sibling references: **S3** (account switch — sidebar `_UserAvatar`
refresh after a profile-identity change at the *account* level — same
sidebar node, same `_loadProfile()` reload path) and **S30** (friend-
alias edit — same "open profile → edit → confirm → prefs write →
restart-survives" shape, but on a friend's `friendRemark` instead of
the self's `nickname`).

## 1. Summary

Verifies the full **sidebar avatar → self-profile dialog → edit
nickname + status message → save → persistence** flow:

1. Tap the desktop sidebar `_UserAvatar` (the avatar at the top of the
   `buildSidebar` column, rendered at
   `lib/ui/settings/sidebar.dart:205-208` — now stably keyed as
   **`sidebar_user_avatar`** / `UiKeys.sidebarUserAvatar`). On
   phone/large-phone widths the same
   identity entry point on the drawer header also lands here, but
   via a different code path — see Fixture/Step variants.
2. `_UserAvatarState._openProfile()` (`sidebar.dart:329-362`) fires
   `showSelfProfile(context, service, connectionStatusStream, …)`
   (`sidebar.dart:40-174`):
   - Resolves the real Tox ID with `Prefs.getCurrentAccountToxId()`
     (falls back to `service.accountKey` on the rare login race).
   - On desktop / tablet (`ResponsiveLayout.shouldShowBottomNav` ==
     `false`) — pushes a `Dialog` containing `ProfilePage(isEditable:
     true, …)` constrained to `max(280, min(width-32, 880 or 500))` ×
     `clamp(400, height-100, 800)`, with a close-`X` `IconButton` in
     the top-right `Stack` slot (`sidebar.dart:122-173`).
   - On phone / large-phone — pushes a fullscreen `MaterialPageRoute`
     with a `Scaffold` whose AppBar uses an `Icons.close` leading
     IconButton (`sidebar.dart:94-119`). Same `ProfilePage` body inside.
3. `ProfilePage._buildContent` (`lib/ui/profile_page.dart:382-498`)
   renders the read-only header. Tapping the edit pencil in
   `ProfileHeader` (toggled by `onToggleEdit`, `profile_page.dart:417`)
   flips `_editMode = true`, which mounts `ProfileEditFields`
   (`lib/ui/profile/profile_edit_fields.dart:31-143`). That widget
   contains:
   - A nickname `TextField` with `labelText: tL10n?.setNickname ??
     appL10n.nickname` (`profile_edit_fields.dart:76-84`). Length
     budget is 12 "wide" units / 24 "narrow" — `profileTextLength`
     counts CJK as 1, Latin/digits as 0.5
     (`profile_edit_fields.dart:10-27`). Over-budget surfaces an
     `errorText` and disables Save.
   - A status `TextField` (`profile_edit_fields.dart:86-96`),
     `minLines: 1`, `maxLines: 3`, label `tL10n?.setSignature ??
     appL10n.statusMessage`, budget 24.
   - A Cancel `TextButton` (`profile_edit_fields.dart:100-103`) and a
     full-width Save `FilledButton`
     (`profile_edit_fields.dart:105-135`) whose label is
     `tL10n?.saveContact ?? appL10n.save`. Save is disabled while
     `_isSaving` is `true` or either field is over budget.
4. Type into nickname (e.g. `hehe2` → `hehe2-edited`).
5. Type into status message (e.g. empty → `S8 roundtrip status`).
6. Tap Save. `ProfilePage._handleSave` (`profile_page.dart:195-220`)
   runs:
   - `widget.onSave!(newNickname, newStatusMessage)` — which is the
     closure in `showSelfProfile` (`sidebar.dart:70-80`), in turn:
     - `service.updateSelfProfile(nickname:, statusMessage:)` —
       routes to
       `third_party/tim2tox/dart/lib/service/ffi_chat_service.dart:3657-3664`
       which UTF-8 encodes both strings, calls `_ffi.setSelfInfo`
       (Tox profile blob is rewritten on the C side; the next
       `tox_get_savedata` flush picks it up), then frees the malloc'd
       buffers.
     - `Prefs.setNickname(newNickname)` —
       `lib/util/prefs.dart:350-357` writes the global `self_nickname`
       SharedPref key (or `remove(key)` on empty).
     - `Prefs.setStatusMessage(newStatusMessage)` —
       `lib/util/prefs.dart:364-371` writes the global
       `self_status_msg` key.
     - `onProfileSaved` callback (`sidebar.dart:338-346`) runs in
       `_UserAvatarState`'s `setState` to update its local
       `_nickname`, `_nickController.text`, `_statusController.text`.
       The sidebar `_UserAvatar` rebuilds on the next frame with the
       new label.
   - `Prefs.setCardText` (`profile_page.dart:204`) — the QR card text
     edit lives in the same save action; for S8 we treat it as a
     pass-through (don't touch it).
   - `_savedNickName` / `_savedStatusMessage` cached so subsequent
     `didUpdateWidget` rebuilds don't clobber the edit.
   - `_invalidateQrCard()` re-renders the QR with the new identity
     fields (the QR encodes nickname + status indirectly via
     `_effectiveDisplayName` / `_resolveStatusText`).
   - `setState(() => _editMode = false)` flips back to read-only.
   - `AppSnackBar.showSuccess(context, tL10n?.saveContact ??
     appL10n.saved)` — root `ScaffoldMessenger` overlay toast.
7. Verify the **sidebar `_UserAvatar` label** flips to the new
   nickname. `_UserAvatarState._loadProfile()`
   (`sidebar.dart:311-327`) is not re-triggered by Save directly
   (only by `widget.service.avatarUpdated`), so the proof of
   immediate refresh is the `onProfileSaved` setState path, not a
   re-read. Verify on the next frame.
8. Restart the app. On next launch the `_StartupGate` →
   `StartupSessionUseCase` path calls
   `Prefs.setNickname(nickname)` from the loaded account record
   (`lib/util/account_service.dart:258`), `_UserAvatar.initState` →
   `_loadProfile()` → reads `Prefs.getNickname()` →
   `self_nickname` returns the new value. The Tox profile blob
   also restores the new nickname on init (since `setSelfInfo`
   landed in the C-side instance and was persisted via the next
   `tox_get_savedata` write to `tox_profile.tox`).
9. Verify the **account_list `nickname` field** for this `toxId` is
   updated to the new nickname. `showSelfProfile`'s `onSave` closure
   (`sidebar.dart:70-84`) now calls `Prefs.addAccount(toxId: …,
   nickname: newNickname, statusMessage: newStatusMessage,
   updateLastLogin: false)` after the global writes, so the account
   record is kept in sync with the freshly-edited identity.

The assertion bundle in §6 covers (a) sidebar label flip,
(b) prefs persistence (`self_nickname`, `self_status_msg`), (c) Tox
profile blob update (visible on restart and via friends seeing the
self-info callback), (d) dialog dismissal, (e) cross-restart
persistence on the global keys, and (f) the account_list mirror
write.

## 2. Why this matters

The self-profile edit path crosses **three layers** that all have to
behave:

- **UI / sidebar refresh**: the regression risk is that the
  `_UserAvatar` label stays at the *old* nickname after Save until the
  next app launch. The fix is the `onProfileSaved` setState callback
  threaded through `showSelfProfile`'s `nickName:` parameter into
  `_UserAvatarState._openProfile`. If anyone refactors
  `showSelfProfile` to drop the callback (or refactors
  `ProfilePage._handleSave` to skip calling `widget.onSave`), the
  sidebar will appear stale until restart — a privacy/UX bug class
  (the chat list looks "logged in as the old name"). The S3 sidebar-
  refresh regression is the same widget tree from a different angle.
- **Persistence (toxee `Prefs`)**: `setNickname` /
  `setStatusMessage` write `SharedPreferences` keys
  `self_nickname` / `self_status_msg`. These keys are read on next
  cold start by `_UserAvatarState._loadProfile()` AND by
  `account_service.dart` on login to seed the sidebar before the FFI
  layer has finished bootstrap. If a regression points `_loadProfile`
  at a different key (or the wrong scope — global vs account-scoped),
  the post-restart label will be wrong. The current shape is
  intentionally **global / unscoped** because at the moment Save fires,
  `currentAccountToxId` is already the active account; the next
  account switch will rewrite both keys from the new account's record
  (see S3 §2 — the `Prefs.setNickname(nickname)` call in
  `account_service.dart:258` that fixes S3 is the same writer S8
  exercises here, in the opposite direction).
- **Tox profile blob (Tim2Tox)**: `FfiChatService.updateSelfProfile`
  rewrites the in-memory Tox `self_name` and `self_status_message`,
  which are persisted on the next `tox_get_savedata` flush
  (asynchronously by the C-side via `mono_time`). The proof that the
  blob actually changed is that friends see a `friend_name` callback
  with the new value within seconds; locally the proof is that a
  fresh init (S8 restart step) reads the new value back without
  needing the SharedPref. Without this step, the user-visible name
  on the *peer side* would diverge from the self side after edit —
  exactly the privacy bug S3 guards against, applied across the wire.

There are no widget tests covering this flow because (a) the dialog
mounts inside a `showDialog` that resolves Tox-ID asynchronously, and
(b) the FFI `setSelfInfo` requires a live Tox handle. This MCP
scenario is the regression gate.

## 3. Fixture — variant of A (single account on disk, signed in)

Playbook §4 Fixture A: "single saved account, signed in". S8 pins
the starting nickname so the before/after diff is unambiguous, and
pre-clears the status message so the new value isn't masked by an
existing one. Call this **A8**.

State to set up before launching:

| Location | Required state |
|---|---|
| `~/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/profiles/p_<toxA_prefix16>/tox_profile.tox` | Account A — **plaintext** (no profile password) |
| `~/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/account_data/<toxA>/` | Present (any contents) |
| SharedPreferences `currentAccountToxId` | toxA |
| SharedPreferences `account_list` | JSON array containing A's record with `nickname: hehe2` and `statusMessage: ""` |
| SharedPreferences `self_nickname` | `hehe2` — the **before** value, asserted in §6 A2 |
| SharedPreferences `self_status_msg` | **MUST be absent** (or empty string) — so §6 A3 observes a fresh write rather than a no-op |
| SharedPreferences `autoLogin` | `true` (so the boot path lands on HomePage, not LoginPage) |
| Env | `MCP_BINDING=marionette` (synthetic-gesture fallback, see §4) |

Reference identity for the 2026-05-28 dev loop:

| Slot | Tox ID | Nickname |
|---|---|---|
| A (active) | `6065F792FFD78D27…` (any 76-hex Tox address of a real on-disk profile) | `hehe2` |

You can substitute your own identity — the assertions key off the
new vs. old nickname/status strings.

Sanity check before launch:

```bash
defaults read com.toxee.app 'flutter.self_nickname'     # must print "hehe2"
defaults read com.toxee.app 'flutter.self_status_msg' \
  > /tmp/s8_before_status.txt 2>&1
# Either "does not exist" or an empty string is OK.
```

## 4. Pre-flight

```bash
# (a) Kill any orphan Toxee processes from prior runs.
ps -ef | grep "Debug/Toxee.app" | grep -v grep | awk '{print $2}' | xargs -r kill

# (b) Snapshot pre-state we need to assert against.
SUPPORT="$HOME/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app"
defaults read com.toxee.app 'flutter.self_nickname'    > /tmp/s8_before_nickname.txt 2>/dev/null
defaults read com.toxee.app 'flutter.self_status_msg'  > /tmp/s8_before_status.txt   2>&1
defaults read com.toxee.app 'flutter.account_list'     > /tmp/s8_before_account_list.txt 2>/dev/null
# Snapshot the Tox blob mtime + sha so we can prove it was rewritten.
PREFIX16="$(echo "<toxA>" | head -c 16)"
TOX_BLOB="$SUPPORT/profiles/p_${PREFIX16}/tox_profile.tox"
stat -f '%m' "$TOX_BLOB" > /tmp/s8_before_blob_mtime.txt 2>/dev/null
shasum -a 256 "$TOX_BLOB" | awk '{print $1}' > /tmp/s8_before_blob_sha.txt 2>/dev/null

# (c) Build + launch the standalone bundle. DO NOT use `flutter run` —
#     DDS will reject the marionette/arenukvern WebSocket upgrade.
MCP_BINDING=marionette ./run_toxee.sh &

# (d) Wait for the Dart VM service URI, then convert to ws://.
LOG="$SUPPORT/flutter_client.log"
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
// arenukvern (semantic snapshot, screenshots, fmt_tap_widget,
// fmt_enter_text into the dialog TextFields)
fmt_connect_debug_app({ "mode": "uri", "uri": "$URI" })

// marionette (key-based synthetic taps; required when arenukvern's
// semantic tap silently no-ops on non-Semantics widgets)
marionette.connect({ "uri": "$URI" })
```

Verify both connections:

```jsonc
fmt_get_vm({})                          // arenukvern — returns isolate info
marionette.get_interactive_elements()   // ≥10 nodes once HomePage mounts
```

## 5. Step-by-step

> Snapshot IDs returned from `fmt_semantic_snapshot` are live — they
> expire on the next tree change. Re-snapshot before each tap that
> targets a `ref="s_N"`, especially before/after the dialog mounts and
> the `_editMode` flip (the tree mutates aggressively when
> `ProfileEditFields` swaps in).

### Step 0 — Confirm HomePage Online with the before-state label

- **Call**: `fmt_semantic_snapshot({})`
- **Expected**: snapshot includes a sidebar node whose label matches
  `^hehe2\nOnline$` (or `\n(Connecting|Offline)` during the bootstrap
  window). Tox DHT bootstrap is 5–30s; poll every 2s up to **60s**
  for `\nOnline`.
- **Also call**: `fmt_get_screenshots({ "mode": "flutter_layer",
  "compress": true })` → save as `s8_before.png` (visual diff
  baseline).

### Step 1 — Tap the sidebar `_UserAvatar` to open the profile entry

- **Locate**: the sidebar `_UserAvatar` `InkWell` is now keyed as
  `sidebar_user_avatar` (`UiKeys.sidebarUserAvatar`). The same node
  still usually surfaces as the top semantic ref in the snapshot, but
  the key is the stable primary anchor.
- **Call (preferred)**:
  ```jsonc
  marionette.tap({ "key": "sidebar_user_avatar" })
  ```
- **Expected**:
  - **Desktop / tablet** (`ResponsiveLayout.shouldShowBottomNav` ==
    `false`): a `Dialog` mounts. New semantic tree contains a
    close-`X` `IconButton` with tooltip `Close` / `关闭` in the
    top-right, plus the `ProfilePage` body (header showing the
    avatar + display name + Online dot, ToxId row with copy,
    QR card section, card-text input).
  - **Phone / large-phone**: a fullscreen route mounts with a
    `Scaffold` whose AppBar `title` is `tL10n?.profile ??
    'Profile'` and a leading `Icons.close` `IconButton`. Same
    `ProfilePage` body inside.
- **Fallback**: if the keyed tap races a stale tree, re-snapshot and retry,
  or use `fmt_tap_widget` on the top sidebar avatar semantic ref.
- **Wait**: ≤2s; re-snapshot.

### Step 2 — Toggle edit mode (tap the header pencil)

- **Call**: `fmt_semantic_snapshot({})`. Search for the
  `ProfileHeader` pencil — it's an `IconButton` with tooltip
  `tL10n?.edit ?? 'Edit'` (from `profile_page.dart:420`).
- **Call (preferred)**:
  ```jsonc
  fmt_tap_widget({ "ref": "<edit-pencil ref>", "snapshotId": "<from above>" })
  ```
- **Expected**: `_editMode` flips to `true`. New tree contains the
  two `ProfileEditFields` `TextField`s + the Cancel `TextButton`
  + the Save `FilledButton`. The header's pencil tooltip switches
  to `cancelTooltip` (`tL10n?.cancel ?? appL10n.cancel`).
- **Fallback**: `marionette.tap({ "text": "Edit" })` (locale-fragile;
  zh = `编辑`, ja = `編集`, etc.). The §8 `profilePageEditToggle`
  key is the proper fix.
- **Wait**: ≤1s.

### Step 3 — Clear and type the new nickname

- **Locate**: the nickname `TextField` in the snapshot. Its label
  matches `tL10n?.setNickname ?? appL10n.nickname`
  (en = "Nickname", zh = "昵称"). It's the **first** `TextField`
  inside `ProfileEditFields`.
- **Call (preferred)**:
  ```jsonc
  fmt_enter_text({ "ref": "<nickname-TextField ref>",
                   "snapshotId": "<re-snapshot>",
                   "text": "hehe2-edited" })
  ```
  Most MCP `enter_text` implementations *replace* the field's
  current value rather than append; verify by re-snapshotting and
  asserting the field's displayed value is exactly `hehe2-edited`
  (not `hehe2hehe2-edited`).
- **Fallback**: `marionette.enter_text({ "key":
  "profile_nickname_field", "input": "hehe2-edited" })` —
  **key does not exist yet** (see §8). Until then, fall back to
  the focused-field write: tap the nickname field first to focus,
  then `marionette.enter_text({ "input": "hehe2-edited" })`
  targeting the focused widget.
- **Expected**: `_handleEditableFieldChanged` fires (the listener
  attached in `_ProfilePageState.initState` at line 80), the
  `_qrDebounce` timer arms for 400ms, then `_invalidateQrCard()`
  re-renders the QR card with the new display name. Nothing else
  has fired yet (no Save until Step 5).
- **Wait**: <1s for the text to land; >400ms for the QR debounce
  if you want to assert the QR re-render in Step 4. For the core
  S8 assertion bundle, the QR refresh is not required.

### Step 4 — Clear and type the new status message

- **Locate**: the status `TextField` (second `TextField` in
  `ProfileEditFields`). Its label matches `tL10n?.setSignature ??
  appL10n.statusMessage` (en = "Status message", zh = "个性签名").
- **Call (preferred)**:
  ```jsonc
  fmt_enter_text({ "ref": "<status-TextField ref>",
                   "snapshotId": "<re-snapshot>",
                   "text": "S8 roundtrip status" })
  ```
- **Fallback**: `marionette.enter_text({ "key":
  "profile_status_field", "input": "S8 roundtrip status" })`
  — see §8. Same focused-field workaround as Step 3.
- **Expected**: status text lands; `_resolveStatusText` re-resolves
  on the next build. No save yet.
- **Wait**: <1s.

### Step 5 — Tap Save to commit

- **Locate**: the Save `FilledButton` at the bottom of
  `ProfileEditFields`
  (`profile_edit_fields.dart:108-135`). Label matches
  `tL10n?.saveContact ?? appL10n.save` (en = "Save", zh = "保存").
- **Call (preferred)**:
  ```jsonc
  fmt_tap_widget({ "ref": "<save-button ref>", "snapshotId": "<re-snapshot>" })
  ```
- **Fallback**: `marionette.tap({ "text": "Save" })` — locale
  fragility (zh = `保存`, ja = `保存`, ko = `저장`, ar = `حفظ`).
  Either set the locale to `en` via `LocaleController` before
  driving, or ship the §8 `profilePageSaveButton` key.
- **Expected immediate log markers** (in roughly this order):
  - `[FfiChatService] setSelfInfo` (or equivalent — the C-side log
    that proves the FFI call landed; the Dart wrapper doesn't log
    by default, so this depends on Tim2Tox-side trace level)
  - `[ProfilePage] _handleSave: persisted Prefs ...` (only if
    debug logging is enabled — not always present)
  - `[ProfilePage] save snackbar: <localized saved>`
- **Expected UI changes** (within ≤2s of the tap):
  - Save button shows a `CircularProgressIndicator` while
    `_isSaving` is `true`.
  - On success: `_editMode` flips back to `false`, the
    `ProfileEditFields` unmounts, the header pencil returns to
    "Edit" tooltip, and a success snackbar surfaces via the root
    `ScaffoldMessenger` with text `tL10n?.saveContact ??
    appL10n.saved` (en = "Saved", zh = "已保存").
  - On failure: an error snackbar with
    `appL10n.failedToSave(<error>)`. If this fires, capture
    `fmt_get_recent_logs({ "limit": 200 })` and stop — the
    persistence layer regressed.
- **Wait**: poll `fmt_semantic_snapshot({})` every 1s, up to **5s**,
  for the `_editMode` flip back to read-only. The persistence
  itself is sub-100ms; the budget is for snapshot expiry + frame
  scheduling.

### Step 6 — Verify the sidebar `_UserAvatar` label flipped

- **Call**: `fmt_semantic_snapshot({})`
- **Expected**: the sidebar node label is now `hehe2-edited\nOnline`
  (or whatever the new nickname is). This is the
  `_UserAvatarState._openProfile` `onProfileSaved` callback
  (`sidebar.dart:338-346`) running synchronously inside the
  `_handleSave` future — verifying it ran is the §6 A1 assertion.
- **Wait**: 1 frame after the dialog dismisses; if the label is
  stale on the first snapshot, re-snapshot once more after 500ms
  (rare; semantic tree rebuilds on the same `setState` so this
  should be immediate).
- **Also call**: `fmt_get_screenshots({ "mode": "flutter_layer",
  "compress": true })` → save as `s8_after_save.png`.

### Step 7 — Close the dialog (desktop) / pop the route (mobile)

- **Desktop**: the dialog auto-dismisses on the success path? **No**
  — `_handleSave` does NOT call `Navigator.pop(dialogContext)` on
  success. The dialog stays mounted with `_editMode = false`
  showing the read-only profile body. To dismiss, tap the
  close-`X` `IconButton` in the top-right of the dialog
  (`sidebar.dart:157-165`).
  - **Call**: `fmt_tap_widget({ "ref": "<close-X ref>",
    "snapshotId": "<re-snapshot>" })`
  - **Fallback**: `marionette.tap({ "text": "Close" })` (locale
    fragile; the tooltip is `AppLocalizations.of(context)?.close
    ?? 'Close'`). The §8 `profilePageDialogCloseButton` key fixes
    this.
- **Mobile**: tap the leading `Icons.close` `IconButton` in the
  fullscreen route's AppBar (`sidebar.dart:103-108`), or use
  `marionette.press_back_button()`.
- **Expected**: dialog / route is gone from the snapshot; HomePage
  is visible underneath.
- **Wait**: ≤1s.

### Step 8 — Disk + Prefs assertions (the persistence proof)

Run after Step 7 settles. This is the "did the write actually land"
gate; without it, a UI-only setState regression would pass the
visual flip but lose the nickname on restart.

```bash
SUPPORT="$HOME/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app"
PREFIX16="$(echo "<toxA>" | head -c 16)"
TOX_BLOB="$SUPPORT/profiles/p_${PREFIX16}/tox_profile.tox"

# §6 A2 — global self_nickname landed.
defaults read com.toxee.app 'flutter.self_nickname' > /tmp/s8_after_nickname.txt 2>/dev/null
grep -q "hehe2-edited" /tmp/s8_after_nickname.txt && echo OK_A2 || echo FAIL_A2

# §6 A3 — global self_status_msg landed.
defaults read com.toxee.app 'flutter.self_status_msg' > /tmp/s8_after_status.txt 2>/dev/null
grep -q "S8 roundtrip status" /tmp/s8_after_status.txt && echo OK_A3 || echo FAIL_A3

# §6 A4 — Tox profile blob was rewritten (mtime advanced and sha changed).
stat -f '%m' "$TOX_BLOB" > /tmp/s8_after_blob_mtime.txt
shasum -a 256 "$TOX_BLOB" | awk '{print $1}' > /tmp/s8_after_blob_sha.txt
test "$(cat /tmp/s8_after_blob_mtime.txt)" -gt "$(cat /tmp/s8_before_blob_mtime.txt)" \
  && echo OK_A4_mtime || echo FAIL_A4_mtime
diff -q /tmp/s8_before_blob_sha.txt /tmp/s8_after_blob_sha.txt \
  >/dev/null && echo FAIL_A4_sha || echo OK_A4_sha

# §6 A10 — account_list nickname for toxA. The mirror write at
# `sidebar.dart:70-84` (codex review #2 P1, 2026-05-28) lands the
# new nickname into the account record, so this MUST contain the
# new value.
defaults read com.toxee.app 'flutter.account_list' > /tmp/s8_after_account_list.txt 2>/dev/null
grep -q "hehe2-edited" /tmp/s8_after_account_list.txt \
  && echo OK_A10 || echo FAIL_A10
```

Note: the Tox blob `sha` and `mtime` change may not be observable
immediately after Save — `tox_get_savedata` writeback happens on
the next polling tick or on dispose. If Step 8 runs ≤500ms after
Save, allow up to 5s of poll-then-recheck. If the blob never
changes, the FFI call regressed (or the C side is dropping the
write); cross-check by tailing the C-side log if Tim2Tox tracing
is enabled.

### Step 9 — Restart and verify persistence

- **Call (shell)**:
  ```bash
  ps -ef | grep "Debug/Toxee.app" | grep -v grep | awk '{print $2}' | xargs -r kill
  sleep 2
  MCP_BINDING=marionette ./run_toxee.sh &
  # … re-grep VM URI, reconnect MCP …
  ```
- **Call (MCP)**: reconnect via `fmt_connect_debug_app` +
  `marionette.connect` as in §4.
- **Call**: `fmt_semantic_snapshot({})` once HomePage stabilizes
  to `\nOnline`.
- **Expected**: the sidebar `_UserAvatar` label is
  `hehe2-edited\nOnline`. Proof points:
  - `_loadProfile()` in `initState` reads `Prefs.getNickname()` →
    `self_nickname` returns `hehe2-edited`.
  - The Tox C-side init reads the rewritten profile blob and
    surfaces the same nickname via `tox_self_get_name`.
  - The account_list mirror (now landed at `sidebar.dart:70-84`)
    keeps the account record's nickname in sync with the global
    key, so account-switch-and-back preserves the edit.
- **Wait**: 5–60s for Tox DHT bootstrap + sidebar
  `_loadProfile` to settle.

### Step 10 — Final screenshot

- **Call**: `fmt_get_screenshots({ "mode": "flutter_layer",
  "compress": true })` → save as `s8_after_restart.png`. Sidebar
  visibly reads `hehe2-edited` plus the Online dot.

## 6. Assertions (the regression test)

| # | What to assert | How |
|---|---|---|
| A1 | After Step 6, the sidebar `_UserAvatar` label is `hehe2-edited\nOnline` (not `hehe2\nOnline`) | snapshot in Step 6 |
| A2 | SharedPreferences `self_nickname` is the literal string `hehe2-edited` | `defaults read` in Step 8 |
| A3 | SharedPreferences `self_status_msg` is the literal string `S8 roundtrip status` | `defaults read` in Step 8 |
| A4 | The Tox profile blob `tox_profile.tox` was rewritten (mtime advanced AND sha256 differs from the pre-save snapshot) | `stat`/`shasum` diff in Step 8 |
| A5 | After Step 5, the dialog flipped back to read-only (`_editMode == false`, `ProfileEditFields` unmounted, header pencil tooltip back to `Edit`) | snapshot in Step 6 / Step 7 |
| A6 | A success snackbar surfaced with localized "Saved" / `tL10n.saveContact` | `fmt_get_recent_logs` for the snackbar trace OR snapshot during the ~3s snackbar window |
| A7 | After Step 7, the dialog (desktop) / fullscreen route (mobile) is dismissed | snapshot in Step 7 |
| A8 | After Step 9 (restart), the sidebar label is `hehe2-edited\nOnline` | snapshot in Step 9 |
| A9 | After Step 9, `self_nickname` still reads `hehe2-edited` (proves the global key is the source of truth on cold start) | `defaults read` post-restart |
| A10 | After Step 8, the `account_list` JSON entry whose `toxId` matches toxA has `nickname: hehe2-edited` and `statusMessage: S8 roundtrip status` (account_list mirror) | grep on `/tmp/s8_after_account_list.txt` |
| A11 | No widget-tree exceptions during the edit + save flow | `official.get_runtime_errors({})` returns empty list relative to a Step 0 baseline |

A1+A2+A3+A4+A8+A10 are the primary regression assertions (the user-
visible flip + the persistence invariant + the Tox blob update +
restart survival + the account_list mirror — see the 2026-05-28
note at the top). A4 is the canary for a regression where
`updateSelfProfile` returns success but the FFI dropped the write
(the historical Tim2Tox-side bug class). A7 confirms the dialog
dismiss UX so users aren't left wondering "did it save".

## 7. Expected log grep targets

Tail
`~/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/flutter_client.log`
(or use `fmt_get_recent_logs`) for these substrings, in roughly this
order, after Step 5:

```
ProfilePage] _handleSave             # entry into the save closure (if debug-logged)
updateSelfProfile                    # FfiChatService entry point (line 3657)
setSelfInfo                          # C-side FFI call (Tim2Tox trace, if enabled)
self_nickname                        # SharedPreferences write target
self_status_msg                      # SharedPreferences write target
AppSnackBar.showSuccess              # success toast
```

After Step 9 (restart), look for:

```
[_UserAvatarState] _loadProfile      # only if debug-logged
self_nickname                        # restored from disk
```

Negative grep (must NOT appear after Save):

```
[ProfilePage] Failed to save         # the error-snackbar path; fires on exception
FfiChatService updateSelfProfile: malloc failed   # OOM-class regression
```

If the success snackbar fires but `self_nickname` doesn't update on
disk (A2 fails), inspect `lib/util/prefs.dart:350-357` for a regression
that silently no-ops the write (e.g. a guard added that returns
early on empty cache).

If the snackbar fires AND `self_nickname` lands AND the Tox blob mtime
does **not** advance (A4 fails), the FFI side regressed — inspect
`third_party/tim2tox/dart/lib/service/ffi_chat_service.dart:3657-3664`
and the C-side `setSelfInfo` symbol.

## 8. Remaining UiKeys follow-up

`sidebarUserAvatar` / `sidebar_user_avatar` is now shipped on the
sidebar `_UserAvatar` `InkWell`. The remaining anchors below are
still follow-up items.

| Field name (camelCase) | Wire key (snake_case) | Where to attach | Why |
|---|---|---|---|
| `profilePageEditToggle` | `profile_page_edit_toggle` | `lib/ui/profile/profile_header.dart` (the pencil `IconButton` whose tooltip is `edit` / `cancel`) — currently passes through `ProfileHeader.onToggleEdit` from `profile_page.dart:417` | Stable anchor for Step 2; today the fallback is `text: "Edit"` which breaks under zh/ja/ko/ar |
| `profileNicknameField` | `profile_nickname_field` | `lib/ui/profile/profile_edit_fields.dart:76` (the nickname `TextField`) | Stable anchor for Step 3; the only fallback today is "tap to focus, then enter_text into the focused field" |
| `profileStatusField` | `profile_status_field` | `lib/ui/profile/profile_edit_fields.dart:86` (the status `TextField`) | Stable anchor for Step 4; same fallback story as nickname |
| `profilePageSaveButton` | `profile_page_save_button` | `lib/ui/profile/profile_edit_fields.dart:108` (the Save `FilledButton`) | Locale-stable Save tap for Step 5; today the fallback is `text: "Save"` (en-only) |
| `profilePageCancelButton` | `profile_page_cancel_button` | `lib/ui/profile/profile_edit_fields.dart:100` (the Cancel `TextButton`) | Symmetric cancel — required for the negative test (cancel reverts the field values, see §10) |
| `profilePageDialogCloseButton` | `profile_page_dialog_close_button` | `lib/ui/settings/sidebar.dart:160` (the close-`X` `IconButton` inside the desktop `Dialog`'s top-right `Positioned`) | Stable anchor for Step 7 desktop dismiss; the close icon has no label other than its localized tooltip |
| `profilePageMobileCloseButton` | `profile_page_mobile_close_button` | `lib/ui/settings/sidebar.dart:103` (the AppBar leading `IconButton` on the mobile fullscreen route) | Symmetric for Step 7 mobile dismiss |

## 9. Remaining source code changes

Tracking only — the sidebar avatar anchor is already landed. The
remaining additive `key:` changes below would make the rest of S8
more locale-stable.

| File:line | Change type | Rationale |
|---|---|---|
| `lib/ui/testing/ui_keys.dart` (`// Profile page` section, new) | Add the remaining keys listed in §8 | Anchor S8 on keys rather than label substrings; fixes the §10 "label-based fallback breaks under non-en locales" blocker |
| `lib/ui/profile/profile_header.dart` (pencil `IconButton`) | Attach `key: UiKeys.profilePageEditToggle` | Step 2 anchor |
| `lib/ui/profile/profile_edit_fields.dart:76,86,100,108` | Attach the four `UiKeys.profile*` keys to nickname/status/cancel/save | Steps 3, 4, 5, and the negative cancel test |
| `lib/ui/settings/sidebar.dart:160,103` | Attach the two close-button keys | Step 7 dismiss anchors |

All §9 changes are additive (new `key:` parameters); none change
behavior. The account_list mirror write previously listed here as
"B-block fix" has already landed at `sidebar.dart:70-84` (see the
note at the top of this file).

## 10. Known blockers + workarounds

| Blocker | Impact | Workaround |
|---|---|---|
| Pencil icon (edit toggle) has no accessibility label beyond the localized tooltip | Step 2 label-based fallback breaks under non-en locales | Either set locale to `en` (S38 flow), or ship §8 `profilePageEditToggle`. CI defaults to en today. |
| The two `TextField`s in `ProfileEditFields` have no stable key | Step 3/Step 4 must rely on focus + `enter_text` to focused, or label-based fallbacks (`labelText` is localized) | Same as above — set locale to en or ship §8 keys. Field order is stable (nickname first, status second), so "tap the first TextField" works as a coordinate-based fallback. |
| Save button label is locale-dependent (`tL10n?.saveContact ?? appL10n.save`) | `marionette.tap({ "text": "Save" })` only works under en | Ship §8 `profilePageSaveButton`, or set locale via `LocaleController`. |
| `_handleSave` does NOT dismiss the desktop dialog on success — it only flips `_editMode` back to false | Test must explicitly tap the close-`X` in Step 7 | Documented in Step 7. If a future patch auto-pops the dialog on success, A7 becomes implicit and Step 7 becomes a no-op — update the playbook then. |
| Tox profile blob writeback is asynchronous (next `tox_get_savedata` poll, or on dispose) | A4 (mtime/sha diff) may not be observable immediately after Save | Allow up to 5s of poll-then-recheck after Step 8 for the blob to land. If it never lands within 30s, the FFI call regressed. |
| Snackbar window is ~3s before auto-dismiss | A6 snapshot may miss the snackbar if Step 6 takes too long | Take the snapshot for A1 immediately after Step 5, then re-snapshot for A5 + A7 after dialog dismiss. Or grep the log for the snackbar trace instead of snapshotting. |
| `_loadProfile()` in `_UserAvatarState.initState` is the only Prefs-read path for the sidebar nickname; there is no Prefs-change stream | If a refactor changes Save to write Prefs but not call `onProfileSaved`, the sidebar would go stale until the next mount | A1 (Step 6) catches this. If A1 starts failing, inspect `sidebar.dart:70-80` (the `onSave` closure) and `sidebar.dart:338-346` (the `onProfileSaved` callback) — both must be wired. |
| Profile-page edit toggle (`_editMode`) is a `ProfilePage`-private state; nothing external can force it on for tests | Step 2 cannot be skipped | None — Step 2 is mandatory. If the toggle is removed in favor of always-editable, A5 changes (no flip back) and Step 2 becomes a no-op. |
| Native file picker (avatar) can't be driven by MCP | N/A for S8 — this scenario does not touch avatar | n/a. Avatar-edit is a separate scenario (not yet specified). |
| macOS Screen Recording permission not granted | `fmt_get_screenshots` with default mode fails | Use `mode: "flutter_layer"`. All screenshot calls in this playbook already specify it. |
| DDS interposing on `flutter run` | marionette + arenukvern WebSocket upgrades rejected | Always launch via `./run_toxee.sh` (standalone bundle). |
| Tox DHT bootstrap latency 5–30s | Step 0 / Step 9 "wait for `\nOnline`" can take longer than expected | Allow 60s. Don't sleep — poll. |
| Orphan Toxee process after kill | Stale VM port; new launch picks a different port | Pre-flight (a) — kill by `Debug/Toxee.app` regex, not by bash PID. Step 9 must re-grep the VM URI after the restart, not assume the previous port. |
| Encrypted profile (`tox_profile.tox` requires a password) | `_StartupGate` opens a password dialog before HomePage mounts; S8 doesn't drive it | Fixture A8 requires plaintext. For encrypted variant, prepend the unlock dance from S40. |
| Account-switch concurrent edit (open profile dialog → switch account → confirm save) | The save would land on the new account's Prefs (per `Prefs.getCurrentAccountToxId()` at call time) | Out of scope for S8; flag as S72 (multi-account isolation) territory. The dialog should ideally close on account switch — UX bug, not S8's. |
| Negative test (Cancel) not in this scenario's happy path | A regression where Cancel silently calls Save would persist the edit unintentionally | Add a B8-cancel variant: after Step 4 (typed text), tap Cancel instead of Save. Assert §6 A2/A3/A4 — the prefs keys and blob remain at the pre-flight state. Cancel-path code is at `profile_edit_fields.dart:100-103` and `profile_page.dart:435` (just `setState(() => _editMode = false)`), never calls `widget.onSave`. |

## 11. Estimated runtime

| Phase | Wall clock |
|---|---|
| Pre-flight (kill + pre-state snapshot + build + launch + VM URI grep) | 8–15s with a warm `./build/macos/Build/Products/Debug/`; 60–120s after `--clean` |
| Step 0 (HomePage stabilize to Online) | 5–30s (Tox DHT bootstrap dominates) |
| Step 1 (tap sidebar avatar, dialog/route mounts) | 1–2s |
| Step 2 (toggle edit mode, fields mount) | 1–2s |
| Step 3 (clear + type nickname) | <1s |
| Step 4 (clear + type status) | <1s |
| Step 5 (tap Save, await persistence + setState) | 1–2s |
| Step 6 (verify sidebar label flipped) | <1s |
| Step 7 (close dialog / pop route) | <1s |
| Step 8 (prefs + Tox blob assertions) | <1s (+ up to 5s polling for blob writeback) |
| Step 9 (kill + restart + reconnect MCP + sidebar settle) | 15–60s (DHT bootstrap on cold restart dominates) |
| Step 10 (final screenshot) | <1s |
| **Happy path total (without restart, Steps 0–8)** | **10–40s** after build is warm |
| **Happy path total (with Step 9 restart)** | **30–100s** after build is warm |
| **Max timeout budget (CI)** | **180s** end-to-end, with 60s Step 0 + 60s Step 9 + slack |

Re-run cost is dominated by Tox DHT bootstrap (Step 0 and Step 9) —
the profile edit + save itself, including the Prefs writes and Tox
blob rewrite, is sub-second. If Step 9 is skipped (a "fast" S8
variant that trusts A2/A3/A4 over A8/A9), happy-path total drops to
the low end of the range. The restart phase is the only thing that
validates the read path; without it, you're trusting the prefs and
blob writers on faith.
