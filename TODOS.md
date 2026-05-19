# TODOS

Deferred work tracked across review sessions. Each item has: what, why, pros, cons, context, effort estimate, priority, depends-on. Add new TODOs from review skills (`/plan-ceo-review`, `/plan-eng-review`, `/plan-design-review`) at the bottom; promote to in-flight by moving into a feature branch + opening a PR.

Effort notation: **CC** = a Claude-Code-assisted working day (~30-60 min focused; ~1 human-team-day compressed). Multiply CC days by 8-15× for an equivalent solo-human-team estimate.

---

## Originated from `/plan-ceo-review` 2026-05-15 (identity-portability + multi-account plan)

### 1. Platform-native cloud sync for `.tox` (iCloud Drive / Google Drive)

- **What:** Auto-encrypt and upload the active account's `.tox` blob to the user's platform-native cloud (iCloud Drive on Apple, Google Drive on Android). User-owned cloud, not toxee-run. WebDAV is permanently out of scope.
- **Why:** Manual export is a one-time event; cloud sync turns "backup-once" into "backup-always" — the only path that converts backup-curious users into backup-actual users. First lost account is a fatal trust hit.
- **Pros:** Closes the biggest practical gap in identity portability. Uses user's existing cloud, no values compromise (you're not running a server).
- **Cons:** Platform-specific cloud APIs are a maintenance tax. Adds 1-2 CC weeks. Iteration on iOS/Android cloud quirks.
- **Context:** Deferred during the 2026-05-15 CEO review SELECTIVE EXPANSION ceremony (D5 → Defer). Builds on the first-run backup wizard from PR 1 of the identity-portability plan. Wait for real-user signal before prioritizing.
- **Effort:** M (~1-2 CC weeks).
- **Priority:** P2 (after identity-portability keystone ships; before approach C — distribution).
- **Depends on / blocked by:** Identity-portability PR 1 (first-run wizard) must ship first.

### 2. Signal-style "linked devices" (one identity, multiple devices receive in parallel)

- **What:** Same Tox identity active on multiple devices simultaneously, with sent-from-one-device messages visible on all others. Requires either a contact-graph message-sync layer or an optional relay.
- **Why:** Single biggest UX gap between Tox and Signal/Telegram/iMessage. Today's `.tox`-file-shuffle is a quiet stickiness ceiling.
- **Pros:** Closes the cross-device gap that mainstream users expect. Forces opinionated thinking on "what does P2P + cross-device mean" — owned thinking is differentiation.
- **Cons:** Quarter+ of work. May require a relay component (compromises pure-P2P story; needs deliberate values stance). Touches upstream tim2tox.
- **Context:** Deferred during 2026-05-15 CEO review (D8 → Defer as phase-3). Foundation: requires multi-instance (Outcome X or Y) from identity-portability plan + QR pairing.
- **Effort:** XL (quarter+; CC ~8-12 wks).
- **Priority:** P3 (north-star; only after identity-portability keystone + approach A or C have shipped).
- **Depends on / blocked by:** Identity-portability PR 4 (multi-instance under Outcome X/Y) and PR 2 (QR pairing).

### 3. Manual-IP / Bluetooth fallback for QR + LAN pairing

- **What:** When the QR pairing handshake fails on AP-isolated or mDNS-blocked networks, offer (a) manual IP entry on Device B, and/or (b) Bluetooth-based discovery as a fallback transport.
- **Why:** Coffee-shop and corporate wifi commonly have AP isolation that breaks LAN pairing. Today (v1 of pairing) the failure mode is a clear error pointing the user to use file-based export/import — but a fallback transport would let the user finish in-app.
- **Pros:** Removes a common dead-end in the pairing UX. Bluetooth has near-universal availability.
- **Cons:** Manual IP is hostile UX (most users don't know their phone's IP). Bluetooth adds a new permission ask + native plumbing per platform. Adds ~1-2 CC weeks.
- **Context:** Surfaced in 2026-05-15 CEO review iteration-2 spec-review finding #8. Deferred to v2 of QR pairing.
- **Effort:** M-L (~1-3 CC weeks depending on whether Bluetooth is in).
- **Priority:** P3 (only if user reports of AP-isolation failures accumulate).
- **Depends on / blocked by:** PR 2 of identity-portability plan (LAN pairing v1).

### 4. Per-account voice/video calling (multi-account calling)

- **What:** Allow incoming/outgoing calls on any logged-in account, not only the foregrounded one. Today (under identity-portability plan v1) ToxAV is single-handle and calls are active-account-only.
- **Why:** Identity-portability v1 shows missed-call notifications for non-active accounts but you can't pick them up live. Real multi-account messengers (Telegram, WhatsApp Business) ring on either account.
- **Pros:** Completes the multi-account product story for voice/video. Real product differentiation in the P2P space.
- **Cons:** ToxAV singleton is the blocker — needs N independent ToxAV handles per loaded account, or a single shared handle multiplexed across accounts. TUICallKit is also singleton-coded. Heavy lift.
- **Context:** Deferred in 2026-05-15 CEO review. Tagged as phase-3 in the identity-portability plan.
- **Effort:** L-XL (~3-8 CC weeks depending on Outcome X/Y vs Z; impossible under Z without tim2tox v2).
- **Priority:** P3 (phase-3 after multi-instance ships).
- **Depends on / blocked by:** Identity-portability PR 4 (multi-instance) under Outcome X or Y.

### 5. `account_export_service.dart` split refactor (35KB → modular)

- **What:** Split `lib/util/account_export_service.dart` (~1000 LOC, 35KB) into focused modules: encryption wrappers, profile structure parsing, .tox file I/O, FFI plumbing, exception types.
- **Why:** File is well past `tool/check_complexity.dart`'s 500-LOC warn threshold. CLAUDE.md says the complexity guard is currently warn-only but "the long-term direction is enforcement." This file is one of the highest-risk hot-spots for review-blocking growth.
- **Pros:** Each chunk independently testable. Easier code review on the export/import touch points (which are security-sensitive). Aligns with project convention.
- **Cons:** Pure refactor; no user-visible change. ~3-5 CC days. Carries regression risk if not test-covered first.
- **Context:** Surfaced in 2026-05-15 CEO review Section 5 (Code Quality). The file already has thorough text-trail logging that test coverage can lean on; missing piece is end-to-end test fixture for encrypted/unencrypted/qTox-format roundtrip.
- **Effort:** M (~3-5 CC days, mostly test-writing).
- **Priority:** P2 (do before identity-portability PR 1 starts so the wizard work touches a sane file, OR immediately after PR 1 ships).
- **Depends on / blocked by:** None; standalone refactor.

### 6. `multi_instance_concurrent_active_count` observability metric

- **What:** Emit a periodic counter (every 60s) of currently-loaded concurrent accounts, plus a high-water-mark gauge. Surfaces in `AppLogger` and in any future telemetry (currently no Sentry/equivalent shipped).
- **Why:** Multi-instance is a major bet; you need to know if users actually use >1 account or if it's a feature only you ever exercise. Without this metric, the product decision "was this worth it?" is unanswerable.
- **Pros:** Closes the loop on the strategic bet. Trivial implementation.
- **Cons:** Needs an opt-in telemetry channel to be useful beyond local logs; until approach C ships, this metric is local-only.
- **Context:** Surfaced in 2026-05-15 CEO review Section 8 (Observability). Identity-portability plan PR 4.
- **Effort:** S (~1 CC day).
- **Priority:** P2 (do as part of PR 4).
- **Depends on / blocked by:** Identity-portability PR 4. Full value unlocked when approach C (distribution + telemetry) ships.

---

## Originated from local-storage review 2026-05-18

### 7. `Prefs` god class — split into focused services (X1)

- **What:** `lib/util/prefs.dart` is now ~1700 LOC after PR1–PR5 landed. The `part of` split into `account_prefs.dart` / `security_prefs.dart` / `window_prefs.dart` / `chat_prefs.dart` is cosmetic — all parts share the same static class. Split into independent classes per domain: `AccountPrefs`, `ChatPrefs`, `SecurityPrefs`, `WindowPrefs`, `BootstrapPrefs`, `MigrationPrefs`. The static facade `Prefs` can stay as a compat shim that delegates.
- **Why:** Any test touching account storage must mock the whole god class or wire real SharedPreferences. The static cache (`_cachedPrefs`, `_cachedCurrentAccountToxId`) embedded directly in the god object also means a `currentAccountToxId` mutation in one test path leaves a dirty cache for the next test. The `PrefsImpl` instance facade at `lib/util/prefs/prefs_impl.dart` is a thin re-delegator — the interfaces in `prefs_interfaces.dart` are mostly bypassed.
- **Pros:** Clean ownership, testable per-domain, kills the dirty-cache footgun, makes future multi-account refactors tractable.
- **Cons:** Large mechanical refactor (~100 callsites). High regression risk without comprehensive tests first. Will conflict with any in-flight prefs change.
- **Context:** Surfaced in `docs/designs/local-storage-review-2026-05-18.md` (X1). Deferred from PR5 (architecture cleanup) of that review's roll-up because the smaller X-fixes were higher-value-per-hour.
- **Effort:** L (~5–8 CC days, including test scaffolding).
- **Priority:** P2.
- **Depends on / blocked by:** None standalone. Coordinate with TODO #5 (`account_export_service.dart` split) — both touch the prefs surface.

### 8. Attachment lifecycle management — refcount / manifest / eviction (X7)

- **What:** History JSON records absolute paths to received files (`<file_recv>/<uid>_<kind>_<num>_<name>`, `<avatars>/friend_<id>_avatar_<ts>.<ext>`, downloads). There is no refcount, no manifest, no eviction. `clearHistory` explicitly leaves media files on disk; only friend-deletion now triggers avatar cleanup (landed via A8 in PR3). Files orphaned by message-history clears, account deletion, account import-then-delete, etc. accumulate indefinitely.
- **Why:** Over time `file_recv/` and `avatars/` grow without bound. On mobile, silent disk filler. Also no way to migrate attachments when an account moves to a new device — the `.tox` blob carries only metadata, not files.
- **Pros:** Bounded disk usage. Enables a "wipe attachments older than N days" UX. Foundation for cross-device attachment sync (north-star).
- **Cons:** Touches both toxee (extend `FriendAssetCleanup` from A8 + the history layer) and tim2tox (where files land). Needs a write-side hook so every save records an attachment reference. Needs a one-time migration to seed the manifest from existing on-disk files.
- **Context:** Surfaced in `docs/designs/local-storage-review-2026-05-18.md` (X7). Partial step landed via A8 (friend-deletion → avatar cleanup); the rest needs the manifest layer.
- **Effort:** L (~5–7 CC days; about half of it test fixtures and migration).
- **Priority:** P2.
- **Depends on / blocked by:** None.

### 9. Cursor-based history pagination (P1) and streaming ZIP (P9)

- **What (P1):** Today `MessageHistoryPersistence` stores one flat JSON array per conversation. `getHistoryMessageListV2` reads the whole file + decodes + sorts in memory before slicing. 100k-message conversations ≈ 50MB JSON parse per cold open. Switch to chunked storage (one file per N=1000 messages, or SQLite with a rowid index) and cursor-based pagination via `lastMsgID`.
- **What (P9):** `exportFullBackup` / `importFullBackup` materialize the entire ZIP in memory (`ZipEncoder().encode(archive)` returns a complete `List<int>`). Years of history → 100MB+ archive. The `archive` package's streaming APIs are non-trivial but available.
- **Why:** P1 is the hard upper bound on history scaling — any conversation past ~10k messages has visible startup lag on mobile. P9 is OOM risk on 1–2GB-RAM phones during account migration.
- **Pros:** Removes the structural ceiling on conversation depth. Backups become feasible for power users.
- **Cons:** P1 is a storage-format migration — needs versioned on-disk format + idempotent migration. Heavy testing required.
- **Context:** Surfaced in `docs/designs/local-storage-review-2026-05-18.md` (P1, P9). Deferred from PR4 (performance roll-up).
- **Effort:** XL (P1: ~7–10 CC days; P9: ~2–3 CC days).
- **Priority:** P3 (only when first user hits the 100k threshold).
- **Depends on / blocked by:** None; P9 standalone, P1 wants test coverage first.

### 10. iOS file_recv backup-exclusion wiring (S3b leftover)

- **What:** PR6 added `AppPaths.markExcludedFromBackup(path)` (NSURLIsExcludedFromBackupKey via MethodChannel). Wired on `logs/` and the new QR card cache dir. The `file_recv/` staging directory was deferred because its `Directory.create()` call lives in `account_service.dart` which was outside PR6's allowed scope.
- **Why:** `file_recv/` is transient (files get moved to Downloads on completion) but the directory persists. iOS backs it up unless excluded. Tiny exposure but trivial fix.
- **Pros:** Closes the last iOS backup-exclusion gap for ephemeral data.
- **Cons:** None.
- **Context:** Deferred from PR6 cross-platform polish.
- **Effort:** XS (~30 min).
- **Priority:** P2.
- **Depends on / blocked by:** None.

### 11. P10 (clearAccountData double key-set walk) and P8 (account_list JSON cache)

- **What (P10):** `Prefs.clearAccountData` and `clearScopedKeysForAccount` each call `p.getKeys()` and iterate independently. O(2N) for the same logical operation.
- **What (P8):** `getAccountByToxId` decodes the entire `account_list` JSON blob on every call. Multiple per-account-settings getters chain into this. No in-memory cache of the account list.
- **Why:** Both are small wins on hot paths; together they shave noticeable latency from account-switch flows on low-end Android.
- **Pros:** Pure code change, no migrations.
- **Cons:** Both touch `prefs.dart` which is in the X1 god-class refactor's path. Better to land both as part of X1 to avoid double rebases.
- **Context:** Surfaced in `docs/designs/local-storage-review-2026-05-18.md` (P10, P8). Deferred from PR4 because prefs.dart was concurrently being edited by the cross-platform agent.
- **Effort:** S (~1 CC day combined).
- **Priority:** P2 (do as part of TODO #7 or alone).
- **Depends on / blocked by:** None standalone; coordinate with TODO #7.

---

## Format note

When adding new TODOs from future review sessions, keep this structure: numbered, with originating skill + date in the section heading. Promote a TODO by moving it to a feature branch + opening a PR; delete it from this file in the PR.
