---
title: tim2tox FFI Reentrancy Audit
date: 2026-05-16
status: COMPLETE
verdict: OUTCOME_Y
author: /plan-ceo-review PR 3
---

# tim2tox FFI Reentrancy Audit

## Verdict
**OUTCOME Y** — Tim2Tox C/C++ core is genuinely multi-instance reentrant and carries `instance_id` on every callback. The chat-uikit Dart layer (`NativeLibraryManager`, `TIMManager.instance`, `Tim2ToxSdkPlatform._currentInstance`, FakeUIKit / Provider tree, `TimSdkInitializer._isInitSDK`) is hard-singleton and treats `instance_id == 0` as the only routable channel for the binary-replacement path. PR 4 can ship multi-account by either (a) running one Tox handle per process and switching profiles + cold restart, or (b) doing the Dart-side de-singleton work spelled out below — but cannot ship true concurrent multi-account without either Dart-side rework OR a hard rewrite of `chat-uikit-flutter`'s patched SDK.

## Audit methodology
1. Inventoried the C++ source tree (`third_party/tim2tox/source/*.{cpp,h}` — 41 files) and the FFI thunk layer (`third_party/tim2tox/ffi/*.{cpp,h}` — 21 files) to find every `static`/`g_*`/`getInstance`/`s_instance` symbol and assess whether each is per-instance, per-thread, or process-global.
2. Read the Dart-side multi-instance primitive (`Tim2ToxInstance`, `FfiChatService`, `ToxAVService`, `Tim2ToxSdkPlatform`) and the production binary-replacement target (`NativeLibraryManager`, `TIMManager`) in `~/.pub-cache/hosted/pub.dev/tencent_cloud_chat_sdk-8.7.7201+3/`).
3. Traced two specimen callbacks end-to-end:
   - `OnRecvNewMessage` (advanced listener / Platform path): C2C text in `V2TIMManagerImpl::HandleFriendMessage` → `SetReceiverInstanceOverride(instance_id)` (thread_local) → `msgManager->NotifyAdvancedListenersReceivedMessage` → `dart_compat_listeners.cpp:776 OnRecvNewMessage` reads `GetReceiverInstanceOverride()` → `BuildGlobalCallbackJson(..., instance_id)` → `SendCallbackToDart` → `Dart_PostCObject_DL(g_dart_port, ...)` → `NativeLibraryManager._handleNativeMessage` → patched `_handleGlobalCallback` reads `instance_id` → routes to `Tim2ToxSdkPlatform.dispatchInstanceGlobalCallback`.
   - SimpleMsgListener / `c2c:` text line (binary-replacement polling path): `OnRecvC2CTextMessage` → `enqueue_text_line("c2c:...")` → `parse_instance_id_from_line` returns 0 (only `progress_recv:`/`file_done:`/`file_request:` carry an inline id) → falls back to `GetReceiverInstanceOverride()` (thread_local set by the upstream C++ caller).
4. Read the SDK patch (`third_party/tim2tox/patches/tencent_cloud_chat_sdk/8.7.7201/0001-tim2tox-custom-platform.patch`) to confirm what production binary replacement actually does at runtime.
5. Wrote eight integration tests, one per matrix row (`test/ffi_audit/`); they execute against the real `libtim2tox_ffi.dylib` where possible and fall back to code-inspection findings (with file:line citations in the test source) where a real FFI call is not feasible in a unit-test sandbox.

## Per-surface findings (pass/fail matrix)

### Surface 1: Native `tox_new` handle
- **Finding**: `V2TIMManagerImpl` owns a `std::unique_ptr<ToxManager> tox_manager_` created lazily in `InitSDK` (`third_party/tim2tox/source/V2TIMManagerImpl.cpp:234`). The default-instance singleton lives at `g_default_instance` (`V2TIMManagerImpl.cpp:150`). Test instances are created via `tim2tox_ffi_create_test_instance_ex` (`tim2tox_ffi.cpp:595-655`) and stored in `g_test_instances: unordered_map<int64_t, V2TIMManagerImpl*>` (`tim2tox_ffi.cpp:116`). Each `V2TIMManagerImpl` instance gets its own `ToxManager`, save path, sub-managers, event thread. Constructor `V2TIMManagerImpl::V2TIMManagerImpl()` is public (`V2TIMManagerImpl.h:43`). No cross-instance state leakage on the C++ `Tox*` handle itself.
- **Verdict**: PASS for X.
- **Test**: `test/ffi_audit/surface_1_tox_handle_test.dart`.

### Surface 2: Native ToxAV handle
- **Finding**: `ToxAVManager` is now per-instance, owned by `V2TIMManagerImpl::toxav_manager_` (`V2TIMManagerImpl.h:250`, allocated at `V2TIMManagerImpl.cpp:238`). The `ToxAVManager::getInstance()` static is preserved for backward compatibility but production code paths in `V2TIMManagerImpl::GetToxAVManager()` return the per-instance pointer. AV callback registries `g_instance_av_callbacks` keyed by `instance_id` (`tim2tox_ffi.cpp:2668`) and AV FFI calls all take `instance_id` as the first arg (`avInitialize`, `avShutdown`, `avIterate`, `avStartCall`, etc. — `tim2tox_ffi.dart:201-260`).
- **Verdict**: PASS for X.
- **Test**: `test/ffi_audit/surface_2_toxav_handle_test.dart`.

### Surface 3: Native polling thread
- **Finding**: Each `V2TIMManagerImpl` instance spawns its own `event_thread_` from `InitSDK` (`V2TIMManagerImpl.h:253`, started in `InitSDK` around `V2TIMManagerImpl.cpp:1456`). The thread holds `task_queue_` and `task_mutex_` per-instance. Test mode skips `event_thread` spawn so the Dart-side harness can drive `iterate_instance` manually. Thread id is captured in `event_thread_id_` (`V2TIMManagerImpl.h:254`) and consulted by `RunOnEventThread` to avoid self-deadlock. Two instances ⇒ two threads ⇒ both can dispatch their own `Tox_iterate` and their own queued tasks without contending.
- **Verdict**: PASS for X.
- **Test**: `test/ffi_audit/surface_3_polling_thread_test.dart`.

### Surface 4: Native callback registries (friend, group, file, connection, log)
- **Finding**: All friend/group/conversation/signaling callbacks land on the per-instance event thread. The dispatcher pattern is:
  1. Upstream C++ handler (`V2TIMManagerImpl::HandleFriendMessage`, `HandleGroupMessageGroup`, etc.) calls `SetReceiverInstanceOverride(GetInstanceIdFromManager(this))` (`V2TIMManagerImpl.cpp:5010, 5083, 5268`).
  2. `g_receiver_instance_override` is **`thread_local`** (`tim2tox_ffi.cpp:700`), so concurrent event threads do not stomp on each other.
  3. The listener layer (`dart_compat_listeners.cpp:776` `OnRecvNewMessage`) reads the override and embeds it in the globalCallback JSON via `BuildGlobalCallbackJson(..., instance_id)` (`json_parser.cpp:160`).
  4. File transfer events carry the `instance_id` literally in the polling line: `"file_request:<id>:..."` (`tim2tox_ffi.cpp:493`); `parse_instance_id_from_line` (`tim2tox_ffi.cpp:241`) extracts it before queueing.
  5. Send/recv file maps are keyed by `instance_id` (`tim2tox_ffi.cpp:345, 348`).
  6. Per-instance metadata maps: `g_known_groups_list`, `g_group_id_to_chat_id`, `g_group_id_to_group_type`, `g_auto_accept_group_invites` are all keyed `int64_t instance_id -> ...` (`tim2tox_ffi.cpp:139-157`).
- **Verdict**: PASS for X. *Caveat*: The C2C/group text "simple listener" polling path enqueues lines like `"c2c:<sender>:<text>"` with no inline instance id; routing relies on the thread_local override being set up the C++ call stack. Verified via inspection of `V2TIMManagerImpl::HandleFriendMessage` at `V2TIMManagerImpl.cpp:5083-5085` and `HandleGroupMessageGroup` at `V2TIMManagerImpl.cpp:5010-5012` — both set/clear the override around the notify call. Group private messages: same (`V2TIMManagerImpl.cpp:5268-5308`).
- **Test**: `test/ffi_audit/surface_4_callback_registries_test.dart`.

### Surface 5: NativeLibraryManager — one-`.so`-N-handles
- **Finding**: `NativeLibraryManager` (in the patched `tencent_cloud_chat_sdk` package) is a static singleton (`static NativeLibraryManager instance = NativeLibraryManager()`). The `final DynamicLibrary _dylib = (...)()` closure runs once at static-init time, snapshotting `_nativeLibName`. `setNativeLibraryName('tim2tox_ffi')` must be called BEFORE any reference to `NativeLibraryManager.bindings`/`_dylib`; if called later it is a no-op. Source: SDK patch `0001-tim2tox-custom-platform.patch:5613-5660`; production call site `lib/bootstrap/logging_bootstrap.dart:118`. The library can therefore only host **one** native `.dylib`/`.so` per process — there is no API for "load tim2tox_ffi twice with different names". This is fine for multi-account if all accounts share the same FFI shared library, which is the intended design.
- **Verdict**: PASS for X (one .so is sufficient; the C side supports N handles through it).
- **Test**: `test/ffi_audit/surface_5_library_load_test.dart`.

### Surface 6: `Dart_PostCObject` `instance_id` carrier (Platform path AND binary-replacement path)
- **Finding (Platform path)**: `BuildGlobalCallbackJson` always includes `"instance_id": <int64>` (`json_parser.cpp:168`). All ~60 `SendCallbackToDart("globalCallback", json_msg, GetCallbackUserData(instance_id, "..."))` sites in `dart_compat_listeners.cpp` pass `instance_id` (collected from `GetReceiverInstanceOverride()` or the request-time `GetCurrentInstanceId()` captured in `DartFriendInfoVectorCallback`). PASS.
- **Finding (binary-replacement path)**: The patched `NativeLibraryManager._handleGlobalCallback` (SDK patch:5726-5747) now reads `instance_id` from the JSON, and if the `TencentCloudChatSdkPlatform.instance` is a `Tim2ToxSdkPlatform`, calls `dispatchInstanceGlobalCallback(instanceId, ...)`. For non-zero `instance_id`, early-returns before reaching the static `_sdkListener?.onXxx()` dispatch (with `FriendAddRequest` as the one exception that always falls through). For `instance_id == 0`, the call falls through to the static listener AND was already routed to the platform — meaning the production single-account path (`instance_id == 0`) is broadcast to BOTH the static singletons AND the per-instance map.
- **Finding (simple-listener polling path, `poll_text`)**: `poll_text(int64_t instance_id, ...)` filters by `instance_id` — only returns lines whose enqueued `pair.first == 0 || pair.first == instance_id` (`tim2tox_ffi.cpp:311`). Lines enqueued with `instance_id == 0` are broadcast to all pollers. The dependence on thread_local override is correctly used by the C++ callers (verified Surface 4).
- **Verdict**: PASS for X on the JSON carriage; **NEEDS_Y** on the production dispatch side because `_sdkListener`/`_advancedMessageListener` in the *un*-patched static fields of `NativeLibraryManager` are single-listener slots — there's no way to register two `V2TimSDKListener` with different `instance_id` filters using the binary-replacement API. The patched dispatcher routes correctly when a `Tim2ToxSdkPlatform` is installed, but only `Tim2ToxSdkPlatform.dispatchInstanceGlobalCallback` keeps per-instance listener maps. Anything in the codebase that still goes `TIMManager.instance.addAdvancedMsgListener(...)` registers a process-global listener (see Surface 7).
- **Test**: `test/ffi_audit/surface_6_instance_id_carrier_test.dart`.

### Surface 7: `TIMManager.instance` / UIKit Provider tree scope-awareness
- **Finding**: `TIMManager.instance` is `static TIMManager instance = TIMManager();` — a single instance per process (`~/.pub-cache/.../native_im/adapter/tim_manager.dart:33`). Its `_isInitSDK` bool, `v2TimSDKListenerList`, `v2TimSimpleMsgListenerList`, and `_sdkAppID` are all instance state on that singleton — so process-global in practice. UIKit (`chat-uikit-flutter`) is built on top of TIMManager singletons, FakeUIKit (`lib/sdk_fake/`) is single-instance, `SessionRuntimeCoordinator._state` is `static`, `Tim2ToxSdkPlatform._currentInstance` is `static`. There is no scope/zone/InheritedWidget that switches `TIMManager.instance` between accounts.
- **Verdict**: **FAIL for X**, NEEDS_Y rework. Concurrent multi-account requires either: (a) accept that only one account is "live" at a time and tear down + rebuild on switch, or (b) extensive refactor of every `TIMManager.instance.xxx` call site (~100+ across chat-uikit-flutter + toxee) to take a scoped manager. The runtime cost of (b) is roughly equivalent to forking `chat-uikit-flutter`.
- **Test**: `test/ffi_audit/surface_7_tim_manager_scope_test.dart`.

### Surface 8: `TimSdkInitializer._isInitSDK` flag
- **Finding**: `TimSdkInitializer.ensureInitialized()` (`lib/runtime/tim_sdk_initializer.dart:8`) gates on `TIMManager.instance.isInitSDK()`. The flag is the single `_isInitSDK` boolean on the TIMManager singleton (Surface 7). After it flips true once, subsequent calls — even from a different account context — short-circuit and never re-run `initSDK`. This is benign because `initSDK` only configures the SDK's app-id/uiPlatform; it does not log the user in. The actual per-account init happens via `FfiChatService.init` + `service.login`. So the flag itself is *wrappable* — a multi-account refactor can leave this as-is and use `SessionRuntimeCoordinator.disposeRuntime` + `ensureInitialized` to drive the per-session lifecycle.
- **Verdict**: PASS as-is for serial multi-account (account switch). Needs no rework under Outcome Y.
- **Test**: `test/ffi_audit/surface_8_init_sdk_flag_test.dart`.

## Aggregated verdict

| Surface | Status | Required for X | Required for Y |
|---------|--------|----------------|----------------|
| 1 tox_new handle | PASS | ✓ | ✓ |
| 2 ToxAV handle | PASS | ✓ | ✓ |
| 3 Polling thread | PASS | ✓ | ✓ |
| 4 Native callback registries | PASS | ✓ | ✓ |
| 5 NativeLibraryManager .so load | PASS | ✓ | ✓ |
| 6 instance_id carrier (Platform) | PASS | ✓ | ✓ |
| 6 instance_id carrier (binary-replacement static listeners) | NEEDS_Y | ✗ — singleton listener slots | wrap-able via Tim2ToxSdkPlatform |
| 7 TIMManager.instance / Provider tree | FAIL | ✗ — hard singleton | requires UIKit / Provider rework |
| 8 TimSdkInitializer._isInitSDK | PASS for serial | n/a | ✓ (wrappable) |

- Outcome X requires: all 8 ✓ → not met (rows 7 + binary-listener half of row 6 fail)
- Outcome Y requires: 1–6 ✓ C-side, 7 acknowledged as needing UIKit work, 8 wrappable → **met**
- Outcome Z: any of 1–6 ✗ on the C side → not triggered

**Selected verdict: OUTCOME Y.** The C/FFI substrate is genuinely multi-instance. The blocker for true concurrent multi-account is entirely on the Dart UIKit side: the `TIMManager`/`NativeLibraryManager` singletons cannot host two accounts simultaneously, and the FakeUIKit/Provider tree under `lib/sdk_fake/` and `chat-uikit-flutter/` assumes one identity per process. Tim2Tox itself does not need a v2 rewrite; the upgrade path is in toxee + chat-uikit-flutter.

## Implications for PR 4

PR 4 (multi-account) has three viable shapes under Outcome Y:

1. **"Switch + tear down" multi-account (low-risk, ship in days)**. Treat multi-account as serial: keep singletons; on account switch, call `SessionRuntimeCoordinator.disposeRuntime()` + `FfiChatService.dispose()` (which calls `unregisterInstanceForPolling`), then re-`ensureInitialized` with the new account's `historyDirectory`/`fileRecvPath`/`avatarsPath`. The Dart-side `_instanceId == 0` ("default instance") is reused but its underlying `g_default_instance` ToxManager is destroyed and re-constructed because `V2TIMManagerImpl::~V2TIMManagerImpl` releases `tox_manager_`. *Risk*: `g_default_instance` is `static V2TIMManagerImpl* g_default_instance = nullptr` (`V2TIMManagerImpl.cpp:150`) and is **never** reset to `nullptr` after `UnInitSDK` — verify this with a real teardown test before shipping. Required file changes: `lib/auth/`, `lib/runtime/session_runtime_coordinator.dart` (add `disposeRuntime` audit), `lib/util/account_service.dart`, `tool/bootstrap_deps.dart` (probably no change). Minimal touch on tim2tox.

2. **Test-instance multi-account (medium-risk, ship in weeks)**. Use `Tim2ToxFfi.createTestInstanceNative(initPath)` to create one tim2tox instance per account, switch active instance with `Tim2ToxInstance.runWithInstance(...)`. Per-instance signaling and ToxAV already work this way. But every chat-uikit Provider/manager call that goes `TIMManager.instance.xxx` would have to be wrapped in `runWithInstance` — a per-call thread-local context. Concurrent dispatch (two accounts active in the same isolate) is not safe because `g_current_instance_id` is process-global mutex-protected (`tim2tox_ffi.cpp:119, 707`); calls from account A interleaving with account B will lose. *To make this safe* you'd need every `TIMManager.instance.xxx` call to be wrapped in a `Tim2ToxInstance` scope AND to ensure no cross-account interleaving — i.e. one isolate per account. Not viable in a Flutter app without isolate-per-account, which is a much bigger refactor.

3. **One-process-per-account (out of scope here, mentioned for completeness)**. Spawn a separate Flutter isolate (or even a separate OS process) per account, each with its own `dart_native_imsdk` / `tim2tox_ffi` load. Most isolation, hardest UX (switching = isolate handoff).

Recommendation: PR 4 should ship shape **(1)**, then take a deliberate decision on whether shape (2) is worth the cost. Shape (2) effectively requires forking `chat-uikit-flutter` to accept a scoped `TIMManager` parameter rather than `.instance` — which we already own (per the `MEMORY.md` note: "UIKit fork is user-owned").

File-by-file PR 4 list under shape (1):
- `lib/auth/login_use_case.dart`: extend to take an `AccountSummary`; persist per-account `historyDirectory` and `fileRecvPath` derived from account-id.
- `lib/runtime/session_runtime_coordinator.dart`: tighten `disposeRuntime` to also call `_currentInstance = null` on `Tim2ToxSdkPlatform` (currently only reverts `TencentCloudChatSdkPlatform.instance`).
- `lib/util/account_service.dart`: switch from "active account" to "switch active account" semantics; route old `FfiChatService` through `dispose` before constructing a new one.
- `lib/startup/startup_session_use_case.dart`: handle new "switch account" outcome.
- `lib/ui/settings/` (or new page): UI for switching accounts.
- Add an integration test that completes a full account-A → account-B switch and verifies no message bleed-over.

The optional refactor that lets PR 4 ship shape (2) safely is `chat-uikit-flutter` taking a `TimManagerHandle` argument throughout — explicitly out of scope for PR 4 per CEO triage.

## tim2tox v2 upgrade-path sketch

Because the verdict is Y, no v2 rewrite of tim2tox is required to unlock multi-account. The marginal C-side polish that would harden the multi-instance story long-term (each ~1-2 weeks of human work):

1. **Fix `g_default_instance` post-`UnInitSDK` reset**. Currently `g_default_instance` is leaked-on-purpose and never set to `nullptr`. Account switch via shape (1) above is fine because the same singleton is re-used, but the ToxManager owned by it is replaced. Make `UnInitSDK` explicitly reset `tox_manager_` (already done) and arrange for `g_default_instance` to be safe under `tox_manager_ == nullptr` (assertions present, but the lifetime is implicit).
2. **Replace `thread_local g_receiver_instance_override` with explicit listener context pointer**. Today's design depends on every call site that triggers a listener to wrap it in `SetReceiverInstanceOverride/Clear`. Missed sites silently route to instance 0. Move the override into a stack-allocated `ReceiverInstanceScope` RAII guard so failure to clear becomes a compile-time / scope-level invariant.
3. **Remove `g_current_instance_id` in favor of always-passed `instance_id` parameter** on every FFI binding. The current FFI design started instance-aware on AV but is half-migrated for non-AV calls (some take `instance_id` first, e.g. `tim2tox_ffi_iterate_instance`, `tim2tox_ffi_login_async`; others rely on the current-instance global, e.g. `tim2tox_ffi_send_text`, `tim2tox_ffi_accept_friend`). Completing the migration would let multiple isolates use tim2tox concurrently without `setCurrentInstance` racing.
4. **Move signaling listener registration off the "current instance" implicit context**. Per the `MULTI_INSTANCE_SUPPORT.en.md` note, listener registration is sensitive to whichever instance was current at registration time.

None of these are blockers for PR 4. They are good housekeeping for the eventual day someone wants to run concurrent multi-account in one isolate.

## Open questions surfaced during audit

1. **Should PR 4 land before the recommended UIKit fork work?** The "switch + tear down" shape is shippable now and gives users multi-account UX (just not concurrent). If the orchestrator wants concurrent multi-account on day one, PR 4 must include the chat-uikit-flutter de-singleton work and PR scope roughly triples.
2. **What happens to `BinaryReplacementHistoryHook` during account teardown?** It's initialized in `HomePage._initAfterSessionReady()` and uses `TIMManager.instance.addAdvancedMsgListener`. Under shape (1), HomePage will be torn down and rebuilt on account switch; verify the listener is removed via the matching `removeAdvancedMsgListener` on dispose. If not, listeners accumulate across switches.
3. **Per-account profile encryption**. Identity portability (PR 1) implies a Tox profile per account; the current `tim2tox_ffi_init_with_path` takes one path. Confirm with Agent 1's PR 1 whether the path swap on account switch is enough.
4. **Polling-thread reset semantics**. `FfiChatService.startPolling()` starts a Dart Timer; `dispose` cancels it. But the C++ `event_thread_` of the per-instance manager keeps running until `UnInitSDK`. Confirm with Agent 2 that account teardown explicitly calls `UnInitSDK` (or the equivalent FFI `tim2tox_ffi_uninit`); otherwise the old account's event_thread keeps polling DHT after the user thinks they logged out.

End of audit.
