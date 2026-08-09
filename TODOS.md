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

## Originated from the `doc/research/` archival sweep 2026-08-07

Carried over from `doc/research/UI_AUTOMATION_ROADMAP.en.md` before it was archived to
[`doc/research/archive/UI_AUTOMATION_ROADMAP.md`](doc/research/archive/UI_AUTOMATION_ROADMAP.md).
Every other item in that doc's backlog was re-verified against the tree on 2026-08-07 and
found **already resolved** (`l3_delete_friend`, `cleanConversationUnreadMessageCount`,
`l3_clear_group_history`, `UiKeys.groupMemberActionRoleButton`, the `messageAttachment*`
anchors, the fork's `emoji_panel_button` / `sticker_panel_button`, and the S96–S125 L1
promotion now recorded in `tool/mcp_test/REAL_UI_GATES.md`). Only the four below survive.

### 12. Desktop chat composer has no tappable Send affordance (`UiKeys.chatSendButton` unattached)

- **What:** `UiKeys.chatSendButton` (`Key('chat_send_button')`, `lib/ui/testing/ui_keys.dart:525`) is declared but never attached on desktop — UIKit's desktop input sends on Enter only, so there is no widget to key. Either add a real Send button to the desktop composer in the `chat-uikit-flutter` fork and attach the key at the `messageInputBuilder` override (`lib/ui/home_page_bootstrap.dart`), or formally retire the desktop half of the key and keep the Enter-only contract documented.
- **Why:** Every real-UI desktop send currently goes through `enterText` + a synthetic `\n`. That is a second code path from what a mouse user does, and it is the reason the key carries a "do NOT tap this on desktop" caveat comment. It is also a genuine UX question: desktop IMs normally offer a click-to-send button.
- **Pros:** Removes the last "declared but unusable" anchor; makes desktop send drivable the same way mobile is; likely a small product win for mouse-first users.
- **Cons:** Adding a button is a fork change to `third_party/chat-uikit-flutter/`, which means patch-maintenance cost (`doc/operations/PATCH_MAINTENANCE.md`) and coordination with any in-flight fork work.
- **Mobile parity:** Mobile is already covered — the key wraps the input row containing the send icon, and `l3_composer_set_text` (`lib/ui/testing/l3_debug_tools.dart:1709`) exists precisely so the ExtendedTextField composer reveals the send button for a real tap. This TODO is desktop-only.
- **Context:** `doc/research/archive/UI_AUTOMATION_ROADMAP.md` §"2026-06-03 — UI-control scenario batch (S96–S125)", S120.
- **Effort:** S–M (~1–2 CC days, most of it fork + patch plumbing).
- **Priority:** P3 (test-ergonomics; the Enter path works and is documented).
- **Depends on / blocked by:** Fork coordination if the button is added.

### 13. Group add-member picker rows are still text/semantic-driven

- **What:** The group invite flow has keys for the entry (`groupAddMemberButton`), the confirm action (`groupMemberInviteConfirmButton`) and the inbound accept (`groupInviteAcceptButton(<gid>)`), but **not** for the individual candidate rows inside the member picker. Add a per-candidate `ValueKey` (shape: `group_invite_candidate:<userId>`, matching the existing dynamic-row convention locked by `test/ui/testing/ui_keys_dynamic_rows_test.dart`).
- **Why:** `group_add_member_picker` and the `rui-group-conf-member-extra` sweep currently select candidates by visible text, which breaks under localisation, remark names, and duplicate nicknames.
- **Pros:** Makes the one remaining unkeyed step of a fully-keyed flow deterministic; small and mechanical.
- **Cons:** The picker widget lives in the UIKit fork, so same patch-maintenance cost as #12.
- **Mobile parity:** The key would live in shared Dart in the fork widget, so mobile is covered by the same change.
- **Context:** `doc/research/archive/UI_AUTOMATION_ROADMAP.md` §"Remaining backlog after this sync", "Group invite flow" row.
- **Effort:** XS–S (~0.5 CC day).
- **Priority:** P3.
- **Depends on / blocked by:** Fork coordination.

### 14. S119 conversation removal is not gateable

- **What:** There is no `l3_*` tool that removes a conversation, and none can be written honestly today: the conversation list is derived from the friend list, so the row-level "Delete" only clears history and the row reappears. Either give conversations an independent hidden/removed state in `FfiChatService` + `MessageHistoryPersistence` so removal is a real, persistable operation, or close S119 as a documented non-gate.
- **Why:** `S119_conversation_row_delete_menu_confirm` can assert the dialog and the history clear but not the user-visible promise ("this conversation goes away"). Leaving it half-gated is the kind of green-washing the working agreement forbids.
- **Pros:** Turns a permanently-yellow scenario into either a real gate or an explicit, reasoned skip. The hidden-conversation state is also a genuine product feature (users expect "delete chat" to stick).
- **Cons:** The honest fix is a Tim2Tox-side data-model change (conversation visibility independent of friendship), not a test change. Touches `third_party/tim2tox/dart/`.
- **Mobile parity:** Shared Dart — the fix and the gate would cover mobile automatically.
- **Context:** `doc/research/archive/UI_AUTOMATION_ROADMAP.md` §"2026-06-03 — UI-control scenario batch (S96–S125)", S119; scenario spec `test/mcp/S119_conversation_row_delete_menu_confirm.md`.
- **Effort:** M (~2–4 CC days for the data-model half; XS if closed as a documented non-gate).
- **Priority:** P2 if treated as a product gap; P3 if only a test concern.
- **Depends on / blocked by:** Product decision on whether "delete conversation" should persist.

### 15. Deeper message-bubble internals and custom menu options remain unkeyed

- **What:** `tool/mcp_test/REAL_UI_GATES.md` records that built-in context-menu items are keyed (`message_menu_item:<action>`) but `additionalMessageMenuOptions` are deliberately left unkeyed to avoid duplicate sibling keys, and message-bubble internals (media sub-elements, read-receipt affordances, quote/reply bodies) have no anchors. Decide a uniqueness scheme for custom options (e.g. `message_menu_item:custom:<label-hash>`) and add bubble-internal anchors where a real-UI gate needs them.
- **Why:** This is the last fork-heavy surface where L3 playbooks still fall back to labels or semantic refs, and it is what keeps several chat-core cases at L1 WidgetTester only.
- **Pros:** Would let the chat-core real-UI cases assert bubble content precisely instead of by visible text.
- **Cons:** Largest of the four — deep fork surface, and the duplicate-key hazard is real (that is why it was skipped). Low marginal value while `REAL_UI_GATES.md`'s 14 WidgetTester gates already cover the flows in CI.
- **Mobile parity:** Fork-side shared Dart; the desktop and mobile menu builders both consume the same keys, so one change covers both (the existing `message_menu_item:<action>` key was landed for MOBILE **and** DESKTOP for exactly this reason).
- **Context:** `doc/research/archive/UI_AUTOMATION_ROADMAP.md` §"Still intentionally out of scope"; `tool/mcp_test/REAL_UI_GATES.md`.
- **Effort:** M–L (~3–5 CC days).
- **Priority:** P3.
- **Depends on / blocked by:** Fork coordination; only worth doing behind a concrete gate that needs it.

---

## Format note

When adding new TODOs from future review sessions, keep this structure: numbered, with originating skill + date in the section heading. Promote a TODO by moving it to a feature branch + opening a PR; delete it from this file in the PR.
