# S40 — Set / change / remove account password (encrypt profile)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on profileCrypt=plain(no-password) network=online` (Fixture A variant: single plaintext profile, no verifier at start)
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because the data-safety assertions (A1/A6/A14) read on-disk `tox_profile.tox` encryption magic bytes (`toxEsave`) across graceful-quit + relaunch cycles plus OS-keychain (`flutter_secure_storage`) verifier reads; the atomic setPassword snapshot-restore is already unit-tested.
**Status**: reference playbook (single-instance) — password set/change/remove + relaunch disk-encryption + LoginPage gate; the atomic setPassword snapshot-restore is unit-tested (test/ suite). Full UI relaunch flow remains a manual/agent-driven playbook.
**Covered-by**: test/account_password_lifecycle_test.dart

Scenario ID: **S40**
Title: 账号密码设置 / 修改 / 解除 → relaunch 验证磁盘加密 + LoginPage 密码门控
Catalog reference: `doc/architecture/MCP_UI_TEST_PLAYBOOK.md` §5e S40 sketch
Last updated: 2026-05-28

This is **数据安全关键测试** — verifies that toxee's "password protect
this account" UI actually:

1. Stores a verifier (PBKDF2 hash + salt) in OS-level secure storage so
   `Prefs.hasAccountPassword(toxId)` returns `true`.
2. **Encrypts `tox_profile.tox` on disk** so the Tox secret key + DHT
   state are unreadable without the password (tox `pass_encrypt`,
   `toxEsave` magic + scrypt salt + xsalsa20 + poly1305).
3. Forces the next cold start through a password gate
   (`LoginPage._showPasswordDialog`) before the FFI ever sees the
   profile.

Five sub-cases (S40a-e) are driven inside the same playbook so an AI
agent can run the whole password lifecycle in one MCP session and
guarantee the password rotation does not corrupt other accounts' state.

## 1. Summary

| Sub-case | Pre-state | Action | Post-relaunch expectation |
|---|---|---|---|
| **S40a** | A is plaintext, no password | Set password `P1`; quit; relaunch | `tox_profile.tox` magic = `toxEsave`; LoginPage card tap → password dialog → entering `P1` lands on HomePage |
| **S40b** | (continues from S40a) | quit; relaunch; enter `WRONG` | password dialog rejects with `invalidPassword` SnackBar; stays on LoginPage; profile file remains encrypted on disk |
| **S40c** | A has `P1` | settings → set password → enter `P2` (new) → submit; quit; relaunch | LoginPage with `P1` → reject; LoginPage with `P2` → success; on-disk profile decrypts with `P2`, not `P1` |
| **S40d** | A has `P2` | settings → set password → leave **new password blank** → submit; quit; relaunch | LoginPage card tap → no password dialog; profile file magic ≠ `toxEsave` (plaintext on disk); `Prefs.hasAccountPassword(toxA) == false` |
| **S40e** | A has `P2`, `autoLogin = true` (re-set in S40c) | quit; relaunch with autoLogin on | **Currently expected: LoginPage with password dialog** — `StartupSessionUseCase.execute` calls `AccountService.initializeServiceForAccount` with `password: null` (see line 68-73), so the encrypted profile fails to decrypt and the startup gate falls back to LoginPage. Document the **actual** observed behavior; treat any silent auto-decrypt as a security bug |

S40a is the load-bearing case. The other four guard against the common
post-fix regressions (password rotation drops the old verifier, "remove
password" doesn't actually decrypt the file, autoLogin silently bypasses
the password by reading from SessionPasswordStore across processes, etc).

## 2. Why this matters

Two separate concerns must both move together; if they fall out of
sync the result is a security failure that looks fine in the UI:

- **Verifier persistence.** `Prefs.setAccountPassword(toxId, password)`
  writes a PBKDF2 hash + salt to `flutter_secure_storage` keyed by
  `toxId`. Source: `lib/util/prefs.dart:1725` →
  `PasswordVerifier.setPassword` (in `lib/util/password_verifier.dart`).
  This is what the LoginPage dialog verifies against
  (`Prefs.verifyAccountPassword`, `prefs.dart:1742`). If only this
  half lands, the user sees a password prompt but the on-disk profile
  is still plaintext — anyone with filesystem access can read it.
- **On-disk encryption.** The actual `tox_profile.tox` encryption
  happens **not** at "set password" time but at the *next*
  `AccountService.teardownCurrentSession` call (line 116-132 of
  `lib/util/account_service.dart`) which reads
  `SessionPasswordStore.get(toxId)` and calls
  `AccountExportService.encryptProfileFile(profilePath, sessionPassword)`.
  `SessionPasswordStore.set(toxId, password)` is **not** called by the
  settings page when setting a password — it is only set during
  `initializeServiceForAccount` (line 245). Implication:
  **the file is NOT actually encrypted until logout / app quit /
  account switch**. This is the single subtlest fact about this
  scenario; misunderstanding it causes false-failure reports.

If the file fails to encrypt at logout (e.g. `SessionPasswordStore`
was cleared early, or the profile copy was busy), the next launch
will succeed without a password because the file is still plaintext
on disk — a silent **encryption bypass** the test must catch.

The `tox_savedata` magic header is `toxEsave` (8 ASCII bytes — *not*
11 as the original S40 sketch implied). Source of truth:
`third_party/tim2tox/third_party/c-toxcore/toxencryptsave/defines.h:9-10`
— `TOX_ENC_SAVE_MAGIC_NUMBER = "toxEsave"`, `MAGIC_LENGTH = 8`. The
full `TOX_PASS_ENCRYPTION_EXTRA_LENGTH` overhead is **80 bytes** =
8-byte magic + 32-byte salt + 24-byte nonce + 16-byte MAC. The first
8 bytes are sufficient for the encryption assertion; the rest is
randomised per-encrypt.

## 3. Fixture — variant of A (single saved account, plaintext, no password)

Playbook §4 Fixture A is "single saved account, signed in"; this
scenario specifically requires Account A to be **plaintext on disk and
without a verifier** at the start so S40a can drive the first
encryption transition.

State to set up before launching:

| Location | Required state |
|---|---|
| `~/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/profiles/p_<toxA_prefix16>/tox_profile.tox` | Account A — **plaintext**. First 8 bytes must NOT be `toxEsave`. Verify with `head -c 8 <path> \| xxd \| grep -i 'tox'` returning nothing. |
| `~/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/account_data/<toxA>/` | Present (any contents OK). |
| SharedPreferences `currentAccountToxId` | Set to **toxA**. |
| SharedPreferences `account_list` | JSON array containing exactly one record `{toxId: <toxA>, nickname: <nickA>, ...}`. |
| SharedPreferences `nickname` | Account A's nickname. |
| SharedPreferences `autoLogin` | `true` for the boot-to-HomePage entry; **toggle to `false`** before each relaunch in steps that need LoginPage as the entry point (S40a/b/c/d). For S40e leave it `true`. |
| `flutter_secure_storage` for account password (`<toxA>_password_hash`, `<toxA>_password_salt`) | **Empty / not present.** This guarantees `Prefs.hasAccountPassword(toxA) == false` going in. Verify by running the app once with a probe widget OR by deleting via the macOS Keychain (`security delete-generic-password -s flutter_secure_storage`) before the test. |
| Env | `MCP_BINDING=marionette ./run_toxee.sh` — required for synthetic-gesture fallback on the `AlertDialog` action buttons. |

Reference identity (substitute your own — assertions key off prefix
matches on whatever IDs the fixture has on disk):

| Slot | Tox ID | Nickname |
|---|---|---|
| A (active) | `6065F792FFD78D27…` | `hehe2` |

Helper shell snippet to clear stale secure-storage entries before the
test (idempotent):

```bash
# (a) Wipe any pre-existing password verifier so we start from
#     "no password" — both the secure-storage and the legacy
#     plain-prefs paths.
TOXA=<toxA full ID>
defaults delete com.toxee.app "${TOXA}_password_hash" 2>/dev/null || true
defaults delete com.toxee.app "${TOXA}_password_salt" 2>/dev/null || true
security delete-generic-password -s flutter_secure_storage \
  -a "${TOXA}_password_hash" 2>/dev/null || true
security delete-generic-password -s flutter_secure_storage \
  -a "${TOXA}_password_salt" 2>/dev/null || true

# (b) Sanity check: profile is plaintext.
PROFILE="$HOME/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/profiles/p_${TOXA:0:16}/tox_profile.tox"
head -c 8 "$PROFILE" | od -c | head -1
# Expect: NOT 't o x E s a v e'.
```

## 4. Pre-flight

```bash
# (a) Kill any orphan Toxee from a prior run.
ps -ef | grep "Debug/Toxee.app" | grep -v grep | awk '{print $2}' | xargs -r kill

# (b) Reset the fixture (see §3 helper).
# (c) Build + launch the standalone bundle. DO NOT use `flutter run` —
#     DDS rejects the marionette/arenukvern WebSocket upgrade.
MCP_BINDING=marionette ./run_toxee.sh &

# (d) Wait for VM URI and convert to ws://...
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

Then in the MCP layer:

```jsonc
fmt_connect_debug_app({ "mode": "uri", "uri": "$URI" })
marionette.connect({ "uri": "$URI" })
```

Verify with `fmt_get_vm({})` + `marionette.get_interactive_elements()`.

Shell helper used by every assertion below — magic byte check:

```bash
PROFILE="$HOME/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/profiles/p_${TOXA:0:16}/tox_profile.tox"
profile_is_encrypted() {
  # Returns 0 (true) iff the first 8 bytes equal ASCII 'toxEsave'.
  [ "$(head -c 8 "$PROFILE" 2>/dev/null)" = "toxEsave" ]
}
```

## 5. Step-by-step

Snapshot IDs (`snapshotId`) from `fmt_semantic_snapshot` are live —
re-snapshot before every tap that targets a `ref="s_N"`. The
`AlertDialog`s used by the password flow (set / confirm / login)
mount and unmount across taps, so a stale snapshot id silently no-ops.

> Locale convention for this playbook: assertions reference both
> English and zh-Hans labels because i18n is exercised by the
> password copy. For the reference run, locale is `en` — substitute
> the corresponding string from `lib/i18n/app_localizations_<lang>.dart`
> if your fixture differs.

### S40a — Set password → relaunch → enter correct password

#### Step 1 — Stabilize on HomePage as Account A (plaintext)

- `fmt_semantic_snapshot({})` — expect a node labeled
  `<nicknameA>\nOnline` (or `\nConnecting` for the bootstrap window).
- Poll every 2s up to **60s** until the `\nOnline` line appears.
- `fmt_get_screenshots({mode:"flutter_layer", compress:true})` → save
  as `s40a_before.png`.
- Sanity: from the shell, `profile_is_encrypted` must return **false**
  before any password action.

#### Step 2 — Navigate to Settings

- `marionette.tap({ "key": "sidebar_settings_tab" })` (UiKey
  `sidebarSettings`).
- Wait ≤2s. `fmt_semantic_snapshot({})` should now contain a button
  labeled `Set Password` / `设置密码` (the
  `OutlinedButton.icon(Icons.lock, ...)` at
  `lib/ui/settings/settings_page_build.dart:147-151`).

#### Step 3 — Tap "Set Password"

- **Preferred**:
  `marionette.tap({ "key": "settings_set_password_button" })`.
- **Fallback for older builds without the anchor:** snapshot, find the node whose
  label exactly matches the *active locale's* string for
  `AppLocalizations.setPassword` (`Set Password` / `设置密码`), then
  `fmt_tap_widget({ ref: <that ref>, snapshotId: ... })`.
- **Expected**: an `AlertDialog` mounts with title
  `Set Password` (`AppLocalizations.setPassword`), containing two
  `TextField`s with labels `New Password` and `Confirm Password`.
  Source: `_showSetPasswordDialog` in
  `lib/ui/settings/settings_page.dart:805-869`.

#### Step 4 — Type matching password into both fields

- **Preferred (after §8 lands):**
  ```jsonc
  marionette.enter_text({ "key": "settings_set_password_new_input",     "input": "P1_test_password" })
  marionette.enter_text({ "key": "settings_set_password_confirm_input", "input": "P1_test_password" })
  ```
- **Fallback today:** snapshot, find both TextFields by their
  `labelText` (the only two `TextField`s inside the dialog), then
  `arenukvern.fmt_enter_text({ ref: <newPwdRef>, ... })` for each.
  Pick the one with `New Password` / `新密码` first.

#### Step 5 — Submit

- **Preferred (after §8 lands):**
  `marionette.tap({ "key": "settings_set_password_submit_button" })`.
- **Fallback today:** snapshot, find the dialog action labeled `OK`
  / `确定` (`AppLocalizations.ok` — there will be two `OK`s in the
  app right now, only one of which is mounted as an `AlertDialog`
  action; disambiguate by role=button + parent dialog).
- **Expected**: dialog dismisses, SnackBar appears with text
  `Password set successfully` (`AppLocalizations.passwordSetSuccessfully`).
- **At this point on disk**: `tox_profile.tox` is **still plaintext**.
  See §2 — the file does not encrypt until teardown. Sanity-check:
  `profile_is_encrypted` returns **false**.
- **In secure storage**: `Prefs.hasAccountPassword(toxA)` now returns
  **true**. Verify indirectly by checking that the settings "Set
  Password" button label re-renders to `Change Password` /
  `修改密码` on the next snapshot (the `_showSetPasswordDialog`
  title flips based on `hasPassword`, line 812 — but the
  *button* label in settings_page_build.dart:149 is hardcoded to
  `setPassword` and does NOT change; see §10 blocker). The
  reliable assertion is the dialog title flip on the next open,
  not the button label.

#### Step 5b — Disable Auto Login (required before quit)

- Settings → toggle the **Auto Login** switch off.
- **Verify**: `defaults read com.toxee.app 'flutter.account_list'` shows
  `autoLogin=false` for the current account row.
- Rationale: at relaunch we want to land on LoginPage and exercise
  the password-prompt path (Steps 7–10). With `autoLogin=true`, the
  cold-start auto-login path runs first, tries to decrypt with
  `password: null`, and bounces to LoginPage anyway — but with a
  confusing error trace in the log that obscures the assertion.

#### Step 6 — Quit the app gracefully (this is where on-disk encryption happens)

- **Send a graceful Cmd-Q** so the orderly shutdown runs and the
  teardown re-encrypt fires. Two equivalent forms:
  - Press `Cmd-Q` while Toxee.app is foregrounded, or
  - From the shell: `osascript -e 'tell application "Toxee" to quit'`.
- A hard `kill -9` skips the orderly shutdown and leaves the profile
  plaintext on disk — don't use it for S40a.
- **After quit**, from the shell:
  ```bash
  profile_is_encrypted   # must return TRUE
  xxd "$PROFILE" | head -1 | grep -E "^00000000:.*746f 7845"
  # ^ magic bytes: "toxE" — encrypted profile marker.
  ```
  If this fails, the test fails here — the verifier was set but
  the file was never encrypted. This is the silent encryption
  bypass §2 warned about.

#### Step 7 — Relaunch

- `MCP_BINDING=marionette ./run_toxee.sh &`
- Refresh `VM_URI` and re-connect both MCPs.
- The app lands on LoginPage (Step 5b set `autoLogin=false`).

#### Step 8 — Tap the account card on LoginPage

- `fmt_semantic_snapshot({})` — expect a `LoginPage` card labeled
  with `<nicknameA>` and the toxId prefix.
- **Preferred:**
  `marionette.tap({ "key": "login_page_account_card:<toxA>" })`.
- **Fallback**: `fmt_tap_widget({ ref: <card ref> })`.
- **Expected**: an `AlertDialog` mounts with title equal to
  `AppLocalizations.enterPasswordForAccount(<nicknameA>)` — e.g.
  `Enter password for hehe2`. Source:
  `lib/ui/login_page.dart:284` → `_showPasswordDialog` at
  `lib/ui/login_page.dart:173-210`.

#### Step 9 — Type the correct password

- **Preferred (after §8 lands):**
  `marionette.enter_text({ "key": "login_page_password_input", "input": "P1_test_password" })`.
- **Fallback**: snapshot, find the single `TextField` inside the
  AlertDialog and `arenukvern.fmt_enter_text` into it.
- Tap `OK` (preferred key `login_page_password_submit_button`;
  fallback: match label `OK` inside dialog).

#### Step 10 — Wait for HomePage

- Poll `fmt_semantic_snapshot` every 2s for ≤30s. Sidebar
  `<nicknameA>\nOnline` must reappear.
- Log markers (poll
  `fmt_get_recent_logs({ limit: 200 })`):
  - `[ffi] tim2tox_ffi_init_with_path: using initPath=…/p_<toxA_prefix16>`
  - `[FfiChatService] login(...) ok`
  - `HandleSelfConnectionStatus: Notified self online status (userID=<toxA>…)`
- During init: the encrypted profile must have been decrypted
  in-place by `AccountExportService.decryptProfileFile` (called
  from `initializeServiceForAccount` line 210). After this point
  **the profile is plaintext on disk again** while the session
  runs — re-encrypt only happens on teardown. Verify:
  `profile_is_encrypted` returns **false** while logged in.
- `fmt_get_screenshots` → `s40a_after.png`.

### S40b — Wrong password rejected

Continues from S40a. The profile is now encrypted on disk again
because Step 10's teardown will re-encrypt it on the next quit.
**Before this sub-case**: re-run the graceful quit from Step 6 so
the disk state is fresh-encrypted with `P1_test_password`. Verify
`profile_is_encrypted` returns true.

#### Step 11 — Relaunch, tap card

- Same as S40a Steps 7-8.

#### Step 12 — Type WRONG password

- `marionette.enter_text({ ..., "input": "wrong_pw_XYZ" })`.
- Tap `OK`.
- **Expected**:
  - Dialog dismisses but no navigation occurs.
  - Red SnackBar appears with text equal to
    `AppLocalizations.invalidPassword` (`Invalid password` /
    `密码错误`). Source: `login_page.dart:295`.
  - LoginPage `_error` state field gets set; the field renders
    inline above the account cards (look for a node labeled
    `Invalid password` with red/error styling in the snapshot).
  - `_verifiedPassword` / `_verifiedPasswordToxId` are reset to
    null (lines 289-290) so the next tap on the card forces a
    fresh dialog (no cached-bad password).
- **Critical disk assertion**: `profile_is_encrypted` must still
  return **true**. A wrong password must NOT touch the file.
  Source: `decryptProfileFile` is only called by
  `initializeServiceForAccount` *after* `verifyAccountPassword`
  succeeds; the verifier check happens in `_quickLogin` line
  287, before `_login()` is dispatched.

### S40c — Change password (P1 → P2)

#### Step 13 — Log in with P1 (re-use Steps 7-10 with the correct password).

#### Step 14 — Navigate to Settings → Set Password again

- Tap `sidebar_settings_tab`, then `settings_set_password_button`
  (fallback: `Set Password` label tap on older builds).
- **Expected**: AlertDialog title is now `Change Password` /
  `修改密码` (`AppLocalizations.changePassword`) because
  `hasPassword == true` (settings_page.dart:812).

#### Step 15 — Enter new password P2 in both fields

- `New Password` field: `P2_rotated_pw`.
- `Confirm Password` field: `P2_rotated_pw`.
- Tap `OK`.
- **Expected**: dialog dismisses, SnackBar `Password set
  successfully`. **NB**: the current dialog does NOT prompt for the
  *old* password before changing — security-wise this means a
  sleeping-laptop / shoulder-surf attacker can rotate the password
  from inside a logged-in session. Flag this in your findings; do
  not block the test on it.

#### Step 16 — Quit gracefully (osascript Cmd-Q).

- On-disk encryption uses the **current** `SessionPasswordStore`
  value, which is whatever was set when this session was
  initialized (i.e. `P1` from Step 13, NOT `P2`). Source:
  `teardownCurrentSession` reads
  `SessionPasswordStore.get(toxId)` at line 92, and that store
  was not updated by `_setAccountPassword`. **This is a known
  bug class:** the on-disk file ends up re-encrypted with the
  OLD password while the verifier validates the NEW one — next
  launch will accept `P2` to pass the verifier, then fail to
  decrypt the file (because the file is encrypted with `P1`).
  The test must check both cases. See §10 blocker for the
  current state and the workaround (explicit logout +
  re-initialize between password change and quit).

#### Step 17 — Relaunch, attempt P1

- Tap card → enter `P1_test_password`.
- **Expected** (post-bugfix world): `Invalid password` SnackBar —
  verifier rejects.
- **Expected** (current bug world): verifier rejects `P1` (correct),
  user types `P2`, verifier accepts, profile decrypt fails with
  the `decryptProfileFile` exception `Decryption failed -
  incorrect password or corrupted file`. The startup catches it
  via the try/catch in `initializeServiceForAccount` line 275 →
  rolls back the global prefs → `StartupShowError` shown.

#### Step 18 — Tap card again, enter P2

- In the post-bugfix world: lands on HomePage.
- In the current bug world: the relaunch sequence above either
  succeeds (if `teardownCurrentSession` correctly re-encrypted
  with `P2`) or fails with the mismatch above. The agent must
  log both observations distinctly — `verifier_accepted=true`
  vs `profile_decrypted=true` — and not collapse them into a
  single pass/fail.

### S40d — Remove password (decrypt)

#### Step 19 — Log in with the current valid password (P2 from S40c).

#### Step 20 — Settings → Set Password → leave both fields blank → OK

- The dialog's submit handler (settings_page.dart:847-865) accepts
  empty password as the "remove" sentinel. The new + confirm must
  both be empty (or equal); if one is filled and the other empty,
  `passwordsDoNotMatch` SnackBar fires.
- **Expected**: SnackBar `Password removed`
  (`AppLocalizations.passwordRemoved`). `Prefs.removeAccountPassword(toxA)`
  ran (settings_page.dart:709). Secure-storage entries are
  cleared.

#### Step 21 — Quit gracefully

- **On-disk**: this is the symmetric bug — `SessionPasswordStore.get(toxA)`
  still holds `P2` from the session-init time. The teardown will
  **re-encrypt the profile with `P2`** even though the verifier
  was just removed. On next launch the LoginPage will skip the
  password dialog (because `hasAccountPassword == false`), then
  `initializeServiceForAccount` is called with `password: null`,
  the file IS encrypted on disk, `decryptProfileFile` is never
  called (password is null), and `FfiChatService.init` will fail
  to parse the encrypted blob as a Tox save → `StartupShowError`.
- The post-bugfix world fix: when the user removes the password,
  decrypt-in-place immediately AND clear `SessionPasswordStore` so
  teardown's re-encrypt is a no-op. The test must document this
  gap. See §10.

#### Step 22 — Relaunch, tap card

- **Expected (post-fix)**: no password dialog. Lands directly on
  HomePage.
- **Expected (current)**: the failure mode above.
- Either way, assert `profile_is_encrypted` returns **false** on
  disk after the next normal logout cycle. If it ever returns
  true after the user explicitly removed the password, that is a
  hard fail — the user thinks the profile is plaintext but it
  isn't.

### S40e — Auto-login with encrypted profile

#### Step 23 — Restore P2 (or P1 — pick one that the disk encryption uses), set `autoLogin=true`, quit.

#### Step 24 — Relaunch

- **Expected**: `StartupSessionUseCase.execute` reads
  `autoLogin=true`, resolves the saved nickname → toxId, calls
  `AccountService.initializeServiceForAccount(toxId, nickname:…,
  password: null, startPolling: false)` (line 68-73; **no password
  argument**). `initializeServiceForAccount` line 206-217:
  `password == null` so `isProfileFileEncrypted` is NEVER probed,
  `decryptProfileFile` is NEVER called, the encrypted blob is
  handed to `FfiChatService.init` which fails.
- The current expected outcome is therefore: **autoLogin fails
  gracefully → falls back to `StartupShowError` or
  `StartupShowLogin`**. The LoginPage then surfaces the password
  prompt on the next card tap.
- **Document the actual observed path** — what the AI agent sees
  in the log, and what UI state is on screen 10s after launch.
  Do not assume a future "auto-login uses keychain-cached
  session password" behavior; the
  `SessionPasswordStore` is process-local in-memory only
  (see `lib/util/session_password_store.dart`), so a kill-restart
  cycle ALWAYS loses it.
- A passing S40e is: encrypted profile + autoLogin → user is
  prompted for the password exactly once on next launch. A
  failing S40e is: encrypted profile + autoLogin → app silently
  decrypts using some cached value (which would be a security
  regression).

## 6. Assertions matrix

| # | Assertion | Sub-case | Mechanism |
|---|---|---|---|
| A1 | Before any password action, `head -c 8 profile.tox` ≠ `toxEsave` | S40a Step 1 | Shell `profile_is_encrypted` |
| A2 | `Set Password` button visible on settings page | S40a Step 2 | `fmt_semantic_snapshot` label match |
| A3 | `_showSetPasswordDialog` mounts (title `Set Password`) | S40a Step 3 | `fmt_semantic_snapshot` label match |
| A4 | SnackBar `Password set successfully` after submit | S40a Step 5 | `fmt_semantic_snapshot` label match |
| A5 | Re-opening the dialog now titles it `Change Password` | S40c Step 14 | Mounts twice; second time `hasPassword=true` |
| A6 | After graceful quit, `head -c 8 profile.tox` == `toxEsave` | S40a Step 6 | Shell |
| A7 | On relaunch, tapping account card opens password dialog | S40a Step 8 | `fmt_semantic_snapshot` shows `Enter password for <nick>` AlertDialog |
| A8 | Correct password → HomePage + sidebar online | S40a Step 10 | `fmt_semantic_snapshot` + log markers |
| A9 | Wrong password → `Invalid password` SnackBar + LoginPage stays | S40b Step 12 | `fmt_semantic_snapshot` |
| A10 | Wrong password attempt does NOT mutate profile bytes | S40b Step 12 | `profile_is_encrypted` still true; file mtime unchanged |
| A11 | Change-password: old P1 rejected after relaunch | S40c Step 17 | `Invalid password` SnackBar |
| A12 | Change-password: new P2 accepted after relaunch | S40c Step 18 | HomePage reached |
| A13 | Remove-password: card tap on next launch skips dialog | S40d Step 22 | No `AlertDialog` mount; goes straight to busy state |
| A14 | Remove-password: profile is plaintext on disk after the second logout cycle | S40d Step 22 | `profile_is_encrypted` returns false |
| A15 | autoLogin + encrypted profile → falls back to LoginPage with password prompt | S40e Step 24 | `fmt_semantic_snapshot` + `StartupShowLogin` log |
| A16 | While logged in, the in-memory `SessionPasswordStore.get(toxId)` returns the password used to decrypt — verifier roundtrips this via `Prefs.verifyAccountPassword` | All | Code-side: a test override or a debug-log line emit; cannot be asserted from MCP alone — track as §10 |
| A17 | No other account's verifier or profile is mutated by these flows (multi-account isolation) | All (run S40 with a second plaintext account on disk and assert it stays untouched) | Compare `head -c 8` and secure-storage entries pre/post |

A1+A6+A14 are the **data-safety assertions** — without them this
test only verifies UI, not security.

A10 is the regression assertion against "wrong password somehow
re-encrypts or corrupts the file" — a class of bugs that
double-encryption guards in `encryptProfileFile:171` exist to
prevent but a test should still cover.

A17 is the **rotation isolation** assertion — if changing
account A's password somehow rewrites account B's secure-storage
slot, that is a cross-account leak.

## 7. Expected log grep targets

Tail
`~/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/flutter_client.log`
(or use `fmt_get_recent_logs`) for these substrings.

Positive markers (must appear during S40a):

```
[AccountService] initializeServiceForAccount     # (or equivalent log line — current code uses no AppLogger.log here; see §10)
[ffi] tim2tox_ffi_init_with_path: using initPath=
[FfiChatService] login(...) ok
HandleSelfConnectionStatus: Notified self online status (userID=
```

On password set (graceful quit): there are **no** positive teardown
or encrypt-completion log markers in code today (the only
`[AccountService] teardown:` lines are error paths — see
`lib/util/account_service.dart:111,130`). Verify the encrypt
transition via the post-quit disk assertion in Step 6
(`xxd ... | grep "746f 7845"` for the `toxE` magic) rather than via
log grep. See §10 for the proposed observability add.

Negative grep (must NOT appear):

```
Decryption failed - incorrect password or corrupted file
```

— if this appears outside of S40b/Step 12's wrong-password attempt,
some other code path tried to decrypt with the wrong key.

```
Profile file is empty
```

— would indicate an atomic-write race; tox_profile.tox should
never be observed empty by any path.

If the AI agent has structured access to per-isolate Dart logging,
the load-bearing log statements to look for are emitted by
`encryption.dart:159-198` (encrypt) and `encryption.dart:203-242`
(decrypt) — both currently have no explicit `AppLogger.log` calls,
only error throws. Adding two structured log lines would make this
playbook self-checking without disk grep. See §10.

## 8. Required UiKeys inventory (remaining new keys + landed anchors)

Tracking only — implementer will add these in a follow-up patch, in
a new `// Settings page — password section` block of
`lib/ui/testing/ui_keys.dart`, and in the existing `// Login page`
block.

| Field name (camelCase) | Wire key (snake_case) | Where to attach | Why |
|---|---|---|---|
| `settingsSetPasswordButton` | `settings_set_password_button` | `lib/ui/settings/settings_page_build.dart:147-151` (the `OutlinedButton.icon(Icons.lock, ...)`) | Already live; marionette-tap target for the entry point of S40a/c/d |
| `settingsSetPasswordNewInput` | `settings_set_password_new_input` | `lib/ui/settings/settings_page.dart:816-827` (the first `TextField` in `_showSetPasswordDialog`) | Disambiguates the two TextFields when both are mounted simultaneously |
| `settingsSetPasswordConfirmInput` | `settings_set_password_confirm_input` | `lib/ui/settings/settings_page.dart:829-840` (the second `TextField`) | Same |
| `settingsSetPasswordSubmitButton` | `settings_set_password_submit_button` | `lib/ui/settings/settings_page.dart:847-865` (the `OK` TextButton) | Locale-stable submit — `OK` label appears in many dialogs |
| `settingsSetPasswordCancelButton` | `settings_set_password_cancel_button` | `lib/ui/settings/settings_page.dart:843-846` | Symmetric cancel — useful for "user changed mind" sub-case |
| `loginPageAccountCard` (dynamic) | `login_page_account_card:<toxId>` | LoginPage saved-account `InkWell` tap target (`UiKeys.loginPageAccountCard(toxId)` in `lib/ui/login_page.dart`) | Reliable per-account anchor on LoginPage; this key is now live and should replace label matching |
| `loginPagePasswordDialog` | `login_page_password_dialog` | `lib/ui/login_page.dart:179` (the `AlertDialog` returned by `_showPasswordDialog`) | Anchors the dialog itself so the subsequent input/submit taps cannot accidentally hit a different dialog |
| `loginPagePasswordInput` | `login_page_password_input` | `lib/ui/login_page.dart:181-196` (the single `TextField`) | Marionette `enter_text` target |
| `loginPagePasswordSubmitButton` | `login_page_password_submit_button` | `lib/ui/login_page.dart:202-205` (the `OK` TextButton) | Disambiguates from the cancel button + from other dialogs |
| `loginPagePasswordCancelButton` | `login_page_password_cancel_button` | `lib/ui/login_page.dart:198-201` | Cancel-path coverage |

Both login dialog blocks (`_showPasswordDialog` and
`_showConfirmPasswordDialog`) exist; only the first one is used on
the LoginPage card-tap flow that S40 drives. The export/import dialog
uses `_showConfirmPasswordDialog` — different flow, out of scope here.

## 9. Required source code changes (DO NOT apply in this PR)

Targeted, minimal. Tracking only.

| File:line | Change type | Rationale |
|---|---|---|
| `lib/ui/testing/ui_keys.dart` | Add the remaining 8 keys listed in §8; `settingsSetPasswordButton` and `loginPageAccountCard` already exist | Anchor scenario on keys, not label substrings |
| `lib/ui/settings/settings_page.dart:816-840` | `key:` on both TextFields | Disambiguate inputs |
| `lib/ui/settings/settings_page.dart:843-865` | `key:` on both TextButtons | Locale-stable dialog actions |
| `lib/ui/login_page.dart:179` | `key: UiKeys.loginPagePasswordDialog` on the `AlertDialog` | Dialog anchor |
| `lib/ui/login_page.dart:181-205` | `key:` on the TextField + both TextButtons | Input + actions |
| `lib/ui/login_page.dart` (saved-accounts list builder) | Already implemented: `key: UiKeys.loginPageAccountCard(toxId)` on each account `InkWell` | Per-account card anchor — also doubles as the click target for S40a/b/c/d/e Step 8 |
| `lib/util/account_service.dart:127` (after `encryptProfileFile`) | Add `AppLogger.log('[AccountExportService] encryptProfileFile ok ($profilePath)')` | Makes A6 a log grep instead of a shell grep — keeps the playbook self-checking |
| `lib/util/account_service.dart:210` (after `decryptProfileFile`) | Symmetric `AppLogger.log('[AccountExportService] decryptProfileFile ok ($profileFile)')` | Same |
| `lib/ui/settings/settings_page.dart:686` (`_setAccountPassword`) | After `Prefs.setAccountPassword(...)`, also call `SessionPasswordStore.set(toxId, password)` — and after `Prefs.removeAccountPassword(...)`, call `SessionPasswordStore.clear(toxId)` | **Security-correctness fix** for the bug surfaced by S40c Step 16 + S40d Step 21 (verifier and on-disk encryption drift). Without this fix, S40c can land the user in an unrecoverable state where the verifier accepts `P2` but the file is encrypted with `P1`. |
| `lib/ui/settings/settings_page.dart:686` (`_setAccountPassword`, in the empty-password branch at line 707-717) | After clearing the verifier, also call `AccountExportService.decryptProfileFile(profilePath, sessionPassword)` to bring the on-disk file back to plaintext immediately. Match the `_setAccountPassword` semantics: the user just took the lock off, leaving the on-disk profile encrypted until next quit is a footgun. | Same class of fix; closes the S40d gap |
| `lib/ui/settings/settings_page_build.dart:147-151` | Conditionally label the button `Change Password` / `修改密码` when `Prefs.hasAccountPassword(...) == true` (read once in initState, refresh on `_setAccountPassword` completion) | Currently the button label is hardcoded `setPassword`; the dialog title flips but the button label does not. A small UX polish that S40a Step 5 currently relies on the DIALOG title for, not the button. |

The first five plus the already-landed LoginPage account-card key are
pure additive `key:` parameters (zero behavior change). The
password-dialog keys remain pending, and the session-password update is
a critical security correctness change
that the test would otherwise exist only to document the bug —
strong recommendation to land it together with the test.

## 10. Known blockers + workarounds

| Blocker | Impact | Workaround |
|---|---|---|
| `SessionPasswordStore` is not updated when `_setAccountPassword` runs while logged in | S40c (change password) and S40d (remove password) produce inconsistent on-disk state after the next teardown | (a) Documented in §9 (file change). (b) Workaround for the test until the fix lands: between Step 15 and Step 16, force a logout-then-login cycle so the new session re-init pulls the current verifier into `SessionPasswordStore`. Concretely: tap `Log Out` → on LoginPage tap card → enter new password → wait for HomePage → only THEN quit. |
| Native dialog hard-kill skips teardown | If the test uses `kill -9` instead of graceful Cmd-Q, the profile is never re-encrypted and S40a Step 6 fails A6 | Always use `osascript -e 'quit app "Toxee"'` for graceful shutdown. `pkill -f Debug/Toxee.app` is OK for orphan cleanup BUT not as the "end of session" quit. |
| `flutter_secure_storage` on macOS is keychain-backed and survives `defaults delete` | Stale verifier entries from prior runs make S40a Step 1 start in the wrong state (`hasAccountPassword=true` going in) | Use `security delete-generic-password` as shown in §3, or run a one-shot cleanup widget from a debug-only screen before the test. |
| Login `_showPasswordDialog` is keyed only by the `AlertDialog` widget; multiple dialogs can mount in rapid sequence (e.g. wrong-password → error SnackBar → user taps card again → new dialog) | A stale `snapshotId` from arenukvern points at a dismissed dialog and silent no-ops | Re-snapshot immediately before every `fmt_tap_widget` on a dialog action. Or use marionette `tap({ key: ... })` once §8 keys land. |
| Locale-dependent label strings | `Set Password` vs `设置密码` mean different selectors fire based on the active locale | Always normalize the test to `en` before the run: tap `sidebar_settings_tab` → language row → English (S38 covers this), then run S40. |
| `_verifiedPassword` cache survives within a single LoginPage session | Wrong-password attempts that hit `Invalid password` correctly clear the cache (lines 289-290), but a successful entry stays cached → tapping a different account's card on the same LoginPage uses the wrong cache | Out of scope here (S40 only drives a single account). Track as a follow-up scenario S40f if multi-account password isolation is in play. |
| `AppLogger` does not log the encrypt/decrypt success today | A6 / A14 cannot be checked via log grep, only via on-disk magic-byte read | §9 lists the two log-line additions. Until they land, the shell `profile_is_encrypted` helper is the only assertion. |
| `head -c 8` requires shell access from the test runner | A pure-MCP test that only has VM-service access cannot read disk bytes | Use the `arenukvern.fmt_evaluate_dart_expression` route to `File('$profilePath').readAsBytes()` and take the first 8 bytes (the FFI `isProfileFileEncrypted` helper is also available; expose via a debug-only MCP tool). |
| First-launch keychain prompt | On a fresh `flutter_secure_storage` write, macOS may prompt for keychain access — blocks the test | Pre-approve `Toxee` in Keychain Access on the test machine, or grant `Always Allow` on the first prompt of the day. |
| `_setAccountPassword` does NOT prompt for the old password before rotating | A logged-in attacker (or shoulder-surfer) can change the password without proving they know the old one | Flag in findings, do not gate the test on it. Track as follow-up scenario S40g (require-old-password). |
| Encrypted profile + autoLogin path does not yet have explicit handling for "needs password" | S40e currently observes a generic startup error; ideal behavior would be a dedicated `StartupShowPasswordPrompt` outcome | Document the **actual** observed path. Add as a follow-up: the startup gate should detect `isProfileFileEncrypted == true && password == null` early and route to a "this account needs a password to unlock" UI before LoginPage even paints. |
| Account export/import dialog also uses passwords (`_showConfirmPasswordDialog`) but is a separate flow | Risk of conflating S40 with S43 (export account) assertions | S40 strictly drives the **profile-protection password** (verifier + on-disk encrypt). The export password is a separate input even though it currently shares the value (`_setAccountPassword` and export both call `Prefs.setAccountPassword`). Keep the two scenarios isolated. |

## 11. Estimated runtime

| Phase | Wall clock |
|---|---|
| Pre-flight (kill + reset secure storage + build + launch + VM URI grep) | 15–30s with warm build; 60–120s after `--clean` |
| S40a Steps 1-5 (set password) | 10–20s (taps + dialog interactions) |
| S40a Step 6 (graceful quit + on-disk encrypt verify) | 5–10s |
| S40a Steps 7-10 (relaunch + correct password + HomePage) | 30–60s (Tox bootstrap dominates Step 10) |
| S40b (wrong password) | 10–20s |
| S40c (change password) | 60–90s — runs through the "force logout-login cycle" workaround for the `SessionPasswordStore` blocker |
| S40d (remove password) | 60–90s |
| S40e (autoLogin variant) | 20–40s |
| **Happy-path total (S40a only)** | **70–120s** after build is warm |
| **Full S40a-e suite** | **5–8 minutes** end-to-end |
| **Max timeout budget (CI)** | **15 minutes** with 60s Tox-bootstrap window per relaunch + slack |

Re-run cost is dominated by Tox DHT bootstrap on every relaunch (3
relaunches in the full suite: after S40a, S40c, S40d). Caching the
DHT node list across runs keeps each relaunch's online-wait at the
low end of the range.

---

## Appendix — End-to-end shell harness sketch

For a CI-style invocation, the following pseudo-shell encodes
S40a's happy path. Real implementation would wrap MCP calls in
the orchestrator skeleton from `doc/architecture/MCP_UI_TEST_PLAYBOOK.md` §6.

```bash
# Prerequisites: TOXA, NICK_A, P1, MCP client.
PROFILE_DIR="$HOME/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/profiles/p_${TOXA:0:16}"
PROFILE="$PROFILE_DIR/tox_profile.tox"
LOG="$HOME/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/flutter_client.log"

# A1: pre-state plaintext.
[ "$(head -c 8 "$PROFILE")" = "toxEsave" ] && { echo "FAIL A1"; exit 1; }

# (run MCP: launch, tap settings → set password → P1+P1 → OK)

# Quit gracefully.
osascript -e 'quit app "Toxee"'
sleep 3

# A6: on-disk encrypted.
[ "$(head -c 8 "$PROFILE")" = "toxEsave" ] || { echo "FAIL A6"; exit 1; }

# Relaunch.
MCP_BINDING=marionette ./run_toxee.sh &
# (re-extract VM URI, reconnect MCPs, re-snapshot)
# (run MCP: tap card → enter P1 → OK → wait online)

# A8: HomePage reached + sidebar online.
# (poll fmt_semantic_snapshot for "<NICK_A>\nOnline" up to 60s)

echo "S40a PASS"
```

Wrap the equivalent for S40b/c/d/e by varying the password value
and the quit/relaunch ordering. The full suite is best driven from
an AI agent following this playbook directly rather than from a
shell script, because the dialog timing and snapshot retry logic
are easier to express interactively.
