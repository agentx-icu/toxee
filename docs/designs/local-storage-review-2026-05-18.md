# Local Storage Review — 2026-05-18

> **Status (2026-05-18 end-of-session):** All six implementation PRs landed on `fix/call-pr1`.
>
> | PR  | Scope | Commits |
> |-----|-------|---------|
> | PR1 | Tier 0 security + data-loss (S1, S2, S3a, S4, S6, S10, A3) | `0012857` |
> | PR2 | Tier 0 stubs (S7, S8, S9) | `4af4dcc` + tim2tox `2fb4e16` |
> | PR3 | Tier 1 correctness (A2, A7, A8, A9) | `11089d9` |
> | PR4 | Tier 2 perf (P2, P3, P4, P5, P11) | `2da9e97` + tim2tox `9beccd5` |
> | PR5 | Architecture (X2, X3, X4, X5, X6, X8, X9, X10, X11) | `176d7d4`, `1f62cd0`, `7646e79`, `d48101d` + tim2tox `46386e5`, `3b3131c` |
> | PR6 | Cross-platform polish (C1, C2, C4, C5, C6, C8, C9, C10 + iOS backup exclusion) | `6363975` |
>
> **Deferred to TODOS.md:**
> - X1 (Prefs god-class split) — large mechanical refactor.
> - X7 (attachment lifecycle / refcount / eviction) — needs manifest layer.
> - P1 (history cursor pagination) and P9 (streaming ZIP) — storage-format migrations.
> - P8 / P10 — couplet to X1; land together.
> - iOS `file_recv/` backup exclusion — pickup left from PR6 scope cap.
>
> **Already-fixed-in-current-code** (re-verified during the review): A6 (pinned-set drift between two builders) and A10 (`isTempPath` / `isFinalPath` overlap) were either already fixed or never as broken as the initial scan suggested.



Comprehensive review of toxee's local persistence across accounts, messages, contacts/groups, configuration, and cross-platform paths. Findings are grouped by severity. Each item is citable to a file:line and tagged with a confidence level. Numbered IDs (`A1`, `M3`, etc.) are stable for later PR references.

Sources: five parallel deep-dive explorations of `lib/`, `third_party/tim2tox/dart/lib/`, `android/`, `ios/`, `macos/`. See agent logs in transcript for full evidence trails.

---

## Tier 0 — Critical (data-loss / security / silent corruption)

### S1. Password hash + salt stored in plain SharedPreferences `[HIGH]`
- `lib/util/prefs.dart:1372-1374` writes `account_password_<toxId>` and `account_password_salt_<toxId>` to plain `SharedPreferences`.
- On iOS this is `NSUserDefaults` → backed up to iCloud by default; on Android it's a world-readable XML on rooted devices and may be exposed via ADB backup.
- IRC channel passwords already use `flutter_secure_storage` (correct pattern). Account password hash/salt should too.
- **Impact:** PBKDF2 hash exposed to offline brute-force from any leaked backup.

### S2. `.tox` profile in-place encrypt/decrypt is not atomic `[HIGH]`
- `lib/util/account_export/encryption.dart:130-208`: `encryptProfileFile`/`decryptProfileFile` do `read → FFI → writeAsBytes` with no temp-file-then-rename.
- Process kill (power loss, iOS/Android OOM, force-quit) between write start and finish → truncated/zero-length profile = lost account.
- Re-encryption happens during `teardownCurrentSession` after the service is disposed, which is the highest-risk window (no native fallback to rescue).

### S3. Backup-exclusion not configured on iOS/Android `[HIGH]`
- iOS: no `NSURLIsExcludedFromBackupKey` set on `logs/`, `file_recv/`, or QR card files. All sync to iCloud (wastes quota + privacy leak for a P2P chat app).
- Android: `AndroidManifest.xml` has no `android:allowBackup="false"` and no `dataExtractionRules` / `fullBackupContent`. Defaults to backing up SharedPreferences (including S1) + Application Support.

### S4. `SharedPreferencesAdapter.clear()` wipes everything `[HIGH]`
- `lib/adapters/shared_prefs_adapter.dart:124`: `clear()` is exposed to Tim2Tox via `PreferencesService` contract. If tim2tox ever calls it on logout/reset, it wipes global settings, account list, every account's data, theme, locale.

### S5. `SharedPreferencesAdapter` base methods bypass account scope `[MED-HIGH]`
- `lib/adapters/shared_prefs_adapter.dart:97-122`: `getString`/`setBool`/`setInt` etc. pass through directly without `_prefixKey`. Only the `Extended*` overrides scope. Any tim2tox call using the base contract writes unscoped → cross-account leakage.

### S6. Unscoped per-friend / per-group keys leak across accounts `[HIGH]`
- `lib/util/prefs.dart:662` `avatar_hash_<friendId>` — no account scope.
- `lib/util/prefs.dart:845` `group_member_namecard_<gid>_<uid>` — no account scope.
- `lib/util/prefs.dart:862` `group_owner_<gid>` — no account scope.
- `lib/adapters/shared_prefs_adapter.dart:33` falls back to bare `'black_list'` when toxId is null.
- These survive `clearAccountData` and are readable by every other account on the device.

### S7. `deleteMessages` always deletes zero messages `[HIGH]`
- `third_party/tim2tox/dart/lib/service/ffi_chat_service.dart:3895`: loop reconstructs `'<ts>_<from>'` and matches against UIKit-supplied msgIDs, but `_appendHistory` stores msgID as `'<ts>_<seq>_<from>'`. Format mismatch → matches never succeed. The UIKit "delete message" UI silently does nothing.

### S8. `refuseFriendApplication` / `deleteFriendApplication` are no-ops `[HIGH]`
- `third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart:6252-6313`: both return success without touching FFI or storage. Rejected friend requests come back on every 5s poll and survive restart. Ghost entries in the friend-request UI.

### S9. `setFriendInfo` (friend alias edit) is unimplemented `[HIGH]`
- `third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart:6282`: stub returning `code:0` without persisting. `Prefs.setFriendRemark` keys exist but have no write path. The UIKit profile-page alias field is write-lost.

### S10. Theme v0→v1 migration locks users to `'light'` `[HIGH]`
- `lib/util/prefs_upgrader.dart:79`: writes `'light'` to `theme_mode` if missing. But `Prefs.getThemeMode()` defaults to `'system'`. Users on the migration path get light-mode locked in despite the design defaulting to follow OS.

---

## Tier 1 — High (correctness bugs / data inconsistency)

### A1. Single-slot `SessionPasswordStore` is a multi-instance blocker `[HIGH]`
- `lib/util/session_password_store.dart:4-5`: one `(toxId,password)` pair. The current single-account constraint hides this, but multi-instance (already in roadmap per memory) will silently drop re-encryption for all but the last-stored account → profile left decrypted on disk at logout.

### A2. `importFullBackup` writes profile before Prefs.addAccount `[HIGH]`
- `lib/util/account_export/full_backup.dart:331-334` writes the `.tox` to disk; `SettingsPage._importAccount` then calls `Prefs.addAccount`. Crash between → orphan profile on disk, invisible to startup, no recovery path.

### A3. `encryptProfileFile` no guard against double-encryption `[MED]`
- `lib/util/account_export/encryption.dart:130`: doesn't check `isDataEncrypted(data)` before encrypting. Decrypt path does check. Any double-call (error recovery, double-teardown) produces double-encrypted blob silently — unrecoverable without recall of both passwords.

### A4. Dual-write race window before `BinaryReplacementHistoryHook` installed `[HIGH]`
- `lib/ui/home_page_persistence.dart:6-30`: when `selfId.isEmpty`, hook install is deferred until `connectionStatusStream` fires. Between Platform install and connection event, both paths can receive the same incoming message.
- The text-content 2s dedup misses file messages (`binary_replacement_history_hook.dart:83` returns `false` when text is empty) → duplicate file message records.

### A5. `_historyById` getter re-syncs from stale persistence cache `[HIGH]`
- `third_party/tim2tox/dart/lib/service/ffi_chat_service.dart:421-430`: after `clearC2CHistory` clears `_historyByIdInternal`, if persistence's async clear hasn't completed, the next `_historyById` read repopulates internal from stale cache → cleared conversation reappears in memory.

### A6. Pinned conversations drift in `_refreshConversations` vs `getConversationList` `[HIGH]`
- `lib/sdk_fake/fake_im.dart:299` checks `pinned.contains(f.userId)` (raw ID).
- `lib/sdk_fake/fake_managers.dart:124` checks `_pinned.contains(normalizedUserId)`.
- `setPinned` stores normalized → the 5s bus emission always emits `isPinned:false` and overwrites the correct value.

### A7. `FakeConversationManager._pinned` set is empty until async read fires `[MED]`
- `lib/sdk_fake/fake_managers.dart:33-37`: fire-and-forget `Prefs.getPinned().then(...)`. Any sync `getConversationList()` before the callback returns shows all pinned as un-pinned.

### A8. Friend deletion leaks avatar file + hash key on disk `[HIGH]`
- `third_party/tim2tox/dart/lib/service/ffi_chat_service.dart:3818-3879`: removes prefs entries and clears chat history but does NOT delete `<avatars>/friend_<id>_avatar_<ts>.<ext>` nor `avatar_hash_<friendId>` key. Permanent disk leak.

### A9. `FakeConversationManager.deleteConversation` is a stub `[HIGH]`
- `lib/adapters/conversation_manager_adapter.dart:31-35`: explicitly does nothing. UIKit's "delete conversation" reappears on next 5s poll.

### A10. `ChatMessage.isTempPath`/`isFinalPath` are contradictory `[MED]`
- `third_party/tim2tox/dart/lib/models/chat_message.dart:143-157`: same path matches both predicates (both check `/file_recv/`). `_mergeMessages` treats a completed file as temporary → stale `/tmp/receiving_` path stored.

### A11. Hardcoded `/tmp/receiving_` prefix invalid on mobile `[MED]`
- `third_party/tim2tox/dart/lib/service/ffi_chat_service.dart:1764` and `chat_message.dart:145`: literal `/tmp/`. On iOS/Android temp is not `/tmp/`; `isTempPath` returns false for in-progress transfers; `_mergeMessages` treats pending as final.

### A12. `clearHistory` in MessageHistoryPersistence does directory scan per call `[MED]`
- `third_party/tim2tox/dart/lib/utils/message_history_persistence.dart:628-689`: reads + JSON-parses every `.json` file looking for `conversationId` match. 100 conversations = 100 reads + parses per single clear.

### A13. `_writeLocks` Completer pattern silently swallows write errors `[MED]`
- `third_party/tim2tox/dart/lib/utils/message_history_persistence.dart:102-153`: `completeError` is called but the surrounding code intentionally swallows the rethrow ("For now, we complete the error but don't rethrow"). Failed history writes vanish.

### A14. `OfflineMessageQueue` is cleared on every startup `[MED]`
- `third_party/tim2tox/dart/lib/service/ffi_chat_service.dart:5495`: `loadQueue(clearOnLoad:true)`. Any unsent queued message is silently dropped on crash → outgoing messages can vanish.

### A15. v1→v2 global migration is a literal no-op but bumped version `[LOW]`
- `lib/util/prefs_upgrader.dart`: version counter inflated without work; per-account stored-newer-than-current check is `>=` not `>` and silently skips instead of erroring on downgrade.

---

## Tier 2 — Performance

### P1. Full conversation JSON loaded on every cold open `[HIGH]`
- `tim2tox_sdk_platform.dart:4826-4983`: 100k-message conversation = ~50MB file read + JSON decode + O(n log n) sort, all before the first 20-message page renders. No streaming, no cursor, no on-disk pagination. Hard ceiling on history scaling.

### P2. `_appendHistory` re-serializes the entire in-memory list per message `[HIGH]`
- `ffi_chat_service.dart:3562`: every new message → full `jsonEncode` of ~1000-message list + write to disk. I/O proportional to history depth × message rate.

### P3. `loadAllHistories` sequential at startup `[MED]`
- `message_history_persistence.dart:404-435`: N conversations = N sequential disk reads. No `Future.wait`.

### P4. `getHistoryMessageListV2` sorts 3 times per call `[MED]`
- `tim2tox_sdk_platform.dart:4924, 4942, 4953`: redundant sorts after each filter step.

### P5. `file.lengthSync()` blocks UI isolate inside getHistoryMessageListV2 `[MED]`
- `tim2tox_sdk_platform.dart:5208-5213`: sync stat per file/image message in the page.

### P6. Per-friend sequential prefs reads in conversation-list build `[MED]`
- `fake_managers.dart:55` and `fake_im.dart:399`: each friend triggers `await Prefs.getFriendAvatarPath/Nickname/Activity` sequentially. 50 friends = 50+ sequential roundtrips. Triggered on every incoming message.

### P7. Startup fast-poll fires every 500ms for 10s `[MED]`
- `fake_im.dart:93-151`: 20 full FFI `getFriendList` calls in 10 seconds, each triggering the P6 loop.

### P8. `account_list` JSON decoded on every per-account settings read `[MED]`
- `lib/util/prefs.dart:1258`: `getAccountByToxId` calls `getAccountList` which decodes the whole JSON blob. No in-memory cache. Compounds for unmigrated accounts that fall through to lazy inline migration.

### P9. Full-archive in-memory ZIP for export/import `[MED]`
- `full_backup.dart:179, 293`: `ZipEncoder().encode()` returns a complete `List<int>`; same on decode. Large account → OOM risk on 1-2GB RAM phones.

### P10. `clearAccountData` walks key set twice `[LOW]`
- `lib/util/prefs.dart:949-950`: `clearAccountData` and `clearScopedKeysForAccount` each iterate `p.getKeys()` independently. O(2N) for the same operation.

### P11. Logs grow unboundedly `[MED]`
- `lib/util/logger.dart:82-115`: new `app_<timestamp>.log` per launch, no rotation, no max count, no cleanup. On long-running installs the `logs/` directory grows forever.

---

## Tier 3 — Architectural

### X1. `Prefs` is a 1500-line god class
- All scoping, crypto, migration, IRC config, window geometry, account CRUD in one static facade. `PrefsImpl` is a thin re-delegator; the `prefs_interfaces.dart` interfaces are mostly bypassed.

### X2. Two scoping implementations
- `Prefs._scopedKey` and `SharedPrefsAdapter._prefixKey` independently implement `${key}_${prefix}`. No shared helper. Silent divergence risk.

### X3. Migration logic split across three places
- `PrefsUpgrader.run`, `runAccountMigrations`, and inline lazy migrations in individual getters (e.g., `getAutoAcceptFriends`). No single place to learn what migrations exist.

### X4. Two in-memory message caches that can diverge
- `FfiChatService._historyByIdInternal` and `MessageHistoryPersistence._historyById` are logically the same data. Direct list mutations in `_handleFileDone` bypass the persistence cache and only call `_saveHistory`.

### X5. Two conversation-list builders
- `FakeConversationManager.getConversationList()` and `FakeIM._refreshConversationsWithFriends` build the same list independently with different normalization. A6/A9 are concrete drift examples.

### X6. Three independent path-construction sites
- `lib/util/app_paths.dart` is the central authority, but `third_party/tim2tox/dart/lib/service/ffi_chat_service.dart` (`file_recv`, `avatars`), `lib/util/lan_bootstrap_service.dart`, and `lib/bootstrap/logging_bootstrap.dart` all construct paths directly.

### X7. No attachment lifecycle management
- History JSON references absolute paths to received files. No refcount, no manifest, no eviction. `clearHistory` explicitly leaves media. Over time `file_recv/` and `avatars/` grow without bound.

### X8. `BinaryReplacementHistoryHook` uses static singleton state
- `_persistence` and `_selfId` are static fields. Re-init after logout replaces them globally; in-flight callbacks from previous session can land under the new selfId.

### X9. `localFriends` serves two conflicting roles
- Cold-start cache (before Tox returns) AND authoritative mirror (overwritten every 5s). `_toxFriendListReceived` flag mediates but the destructive overwrite discards any app-side additions between accept and first poll.

### X10. Backup file never cleaned up after success
- `message_history_persistence.dart:140-142`: comment says cleanup-on-next-write but code is commented out. `cleanupTempFiles` only deletes `.bak` >7 days old. Doubles disk footprint.

### X11. No per-account isolation enforcement on `historyDirectory`
- `MessageHistoryPersistence` defaults to `<AppSupport>/chat_history` with no account scoping. Relies on caller injecting per-account dir. If caller forgets, all accounts merge histories.

---

## Tier 4 — Cross-platform / Polish

### C1. Linux uses `~/.config/toxee/profiles` instead of XDG_DATA_HOME `[LOW]`
- `app_paths.dart:88-91`: XDG spec says user data → `~/.local/share`, not `~/.config`.

### C2. Android 4-parent traversal fragile for shared Downloads `[MED]`
- `app_paths.dart:307-317`: `extDir.parent.parent.parent.parent.path` to reach `/sdcard/Download`. OEM-dependent depth. On API 29+ scoped storage, primary write silently fails; falls through to app-private Downloads.

### C3. Windows long-path `[LOW]`
- Path = `%APPDATA%\<publisher>\<app>\account_data\<prefix>\chat_history\<sanitized-id>.json`. Comfortable but no long-path opt-in declared.

### C4. String concat instead of `p.join` in many places `[LOW]`
- `ffi_chat_service.dart:926`, `offline_message_queue_persistence.dart:44`, `message_history_persistence.dart:52-55`, `qr_card_generator.dart:187`, `ringtone_player.dart:104`, `logging_bootstrap.dart:19,42`. Works on POSIX, wrong on Windows where it sometimes returns mixed-separator paths.

### C5. QR card image in Application Support, should be Caches `[LOW]`
- `qr_card_generator.dart:183-192`: derivable artifact in backed-up location. Cleanup keeps last 5; still wrong directory.

### C6. Pairing temp `.tox` in Application Support, should be Temporary `[LOW]`
- `pairing_client_page.dart:90-92`, `pairing_host_page.dart:163`: crash between write and `finally` delete leaves a `.tox` blob in backed-up location.

### C7. macOS sandbox `getProfileStorageRoot` comment misleading `[LOW]`
- `app_paths.dart:78-82`: comment says `~/Library/Application Support/toxee/profiles` but under sandbox actually lands in `~/Library/Containers/.../Data/Library/Application Support/toxee/profiles`. Behavior correct, comment wrong.

### C8. `Prefs.setAvatarPath` redundant dual-write `[MED]`
- `lib/util/prefs.dart:301-312`: writes scoped + legacy global. Getter ignores the legacy key but it leaks across accounts and is read by any code that hasn't been updated.

### C9. `getAccountByToxId` uses exception-driven control flow `[LOW]`
- `lib/util/prefs.dart:1262-1298`: four nested `try`/`catch` blocks instead of `firstWhereOrNull`. Anti-pattern, also a perf hit when called from migration fallback paths.

### C10. `importScopedPrefsForAccount` runtime cast can throw mid-write `[LOW]`
- `lib/util/prefs.dart:1009`: `value.cast<String>()` on imported list elements. Non-string element throws mid-iteration with no rollback → partial-state import.

---

## Summary by Theme

| Theme | Items |
|-------|-------|
| Security (sensitive data in plain prefs / backup leaks) | S1, S3, S6 |
| Data-loss (corruption, lost messages, silent drop) | S2, S4, S7, A2, A3, A4, A14 |
| Multi-account scope leakage | S5, S6, A1, C8 |
| Functional stubs (UI does nothing) | S7, S8, S9, A9 |
| Race conditions | A4, A5, A7 |
| Performance | P1–P11 |
| Architectural | X1–X11 |
| Disk leaks (no cleanup) | A8, X7, X10, P11 |
| Cross-platform | C1–C7 |

---

## Verification Status (2026-05-18)

Tier 0 + Tier 1 verified by reading cited file:line directly.

| ID  | Status  | Notes |
|-----|---------|-------|
| S1  | ✅ confirmed | `prefs.dart:1372-1374` PBKDF2 hash + salt in plain SharedPreferences. |
| S2  | ✅ confirmed | `encryption.dart:158, 202` direct `writeAsBytes` to original path. |
| S3  | ✅ confirmed | AndroidManifest has no `allowBackup`, no `dataExtractionRules`; Info.plist has `UIFileSharingEnabled` but no `NSURLIsExcludedFromBackupKey` anywhere. |
| S4  | ✅ confirmed | `shared_prefs_adapter.dart:124` `clear()` pass-through. |
| S5  | ⚠️ partial | Base methods don't scope, but the `ExtendedPreferencesService` overrides do. Risk depends on tim2tox call sites — audit before fixing. |
| S6  | ✅ confirmed | `prefs.dart:662, 845, 862` unscoped keys. Also adapter at `shared_prefs_adapter.dart:311, 379` uses a DIFFERENT name (`friend_avatar_hash_…` vs `avatar_hash_…`) AND scopes — two parallel stores. |
| S7  | ✅ confirmed | `ffi_chat_service.dart:1309` stores `'<ts>_<seq>_<from>'`; `:3895` matches `'<ts>_<fromUserId>'`. Format mismatch. |
| S8  | ✅ confirmed | `tim2tox_sdk_platform.dart:6252, 6296` explicit comments "just return success", no FFI calls. |
| S9  | ✅ confirmed | `tim2tox_sdk_platform.dart:6282` explicit "For now, just return success", no Prefs write. |
| S10 | ✅ confirmed | `prefs_upgrader.dart:77-83` writes `'light'` overriding `'system'` default. |
| A1  | ✅ confirmed | Single-slot static fields in `session_password_store.dart`. |
| A2  | ✅ confirmed | `full_backup.dart:329-364` profile write order; `Prefs.addAccount` outside this file. |
| A3  | ✅ confirmed (from S2 read) | No `isDataEncrypted` guard in `encryptProfileFile`. |
| A4  | ✅ confirmed | `home_page_persistence.dart:6-30` deferred hook install + `binary_replacement_history_hook.dart:82` empty-text fallback skip. |
| A5  | ✅ confirmed | `ffi_chat_service.dart:421-430` lazy merge from persistence cache when internal map empty. |
| A6  | ❌ refuted in current code | Both `fake_im.dart` and `fake_managers.dart` build from `friendMap` keyed by `normalizeToxId(f.userId)` and check pinned with the same normalized key. Agent likely read an older snapshot. |
| A7  | ✅ confirmed | `fake_managers.dart:33-37` fire-and-forget `Prefs.getPinned().then(...)`. |
| A8  | ✅ confirmed | `ffi_chat_service.dart:3818-3879` no avatar-file delete, no `avatar_hash_<id>` key delete. |
| A9  | ✅ confirmed | `conversation_manager_adapter.dart:31-35` explicit stub. |
| A10 | ⚠️ partial | `isTempPath` and `isFinalPath` cannot both be true (`isFinalPath` guards on `!isTempPath`), but the `/file_recv/` branch inside `isFinalPath` is dead code. |
| A11 | ✅ confirmed | `chat_message.dart:145-147` literal `/tmp/` prefixes; on macOS sandbox tmp is `/var/folders/.../T/`. |
| A12 | ✅ confirmed | `message_history_persistence.dart` clearHistory implementation scans the directory. |
| A13 | ✅ confirmed | `message_history_persistence.dart:145-149` explicit comment "complete the error but don't rethrow". |
| A14 | ✅ confirmed | `ffi_chat_service.dart:5495` `clearOnLoad:true`. |
| A15 | ✅ confirmed | `prefs_upgrader.dart:65` `>=` not `>` on per-account version check. |

Tier 2 / Tier 3 / Tier 4 not yet verified — will spot-check during the relevant PR.

## Notes

- Tim2Tox findings (`third_party/tim2tox/dart/lib/...`) are fixable in-tree because tim2tox is also user-owned ([memory: tim2tox_fork_ownership]).
- Some items (A14, "always-clear queue") may be intentional design — confirm before fixing. The explicit comment at `ffi_chat_service.dart:5494` says "prevent resending old messages" — design choice. Consider keep+expire-after-N-days as a follow-up.
- Multi-instance items (A1, X8) flagged because the identity-portability roadmap already includes multi-instance as phase-3.
- "Refactor `Prefs` god class" (X1) is a noisy refactor with regression risk; deferred. See TODOS.md item #5 for the parallel `account_export_service.dart` split candidate.
