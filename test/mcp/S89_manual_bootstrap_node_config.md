# S89 — Manual bootstrap node config + test (settings) → DHT reachability

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online bootstrapMode=manual`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned — the runner-assertable half (`l3_add_bootstrap_node` → `l3_dht_info`) needs the live native FFI session + a real local UDP endpoint; the manual-form + "test node" UI half is L3-manual (settings render + tap). L2 has no live Tox handle to accept a node or report a UDP port.
**Status**: covered (split: runner-assertable add path + L3-manual UI form). Feature **C3** (手动节点配置与测试; `lib/ui/settings/bootstrap_settings_section.dart`, `lib/ui/settings/bootstrap_nodes_page.dart`). The manual-form anchors are now shipped.

## Precondition
- Account A signed in, online, test/seed account (mutating L3 tools refuse a non-test account, `l3_debug_tools.dart:253`).
- `Prefs.bootstrapNodeMode == 'manual'` so the settings section renders the manual-input affordance (`manualNodeInput` button) instead of the auto picker. Set via `l3_set_setting {key:'bootstrapNodeMode', value:'manual'}` (`l3_debug_tools.dart:1281-1296`); restore `auto` at end so the fixture self-cleans.
- `network=online`, a real local DHT endpoint exists (the running Tox instance binds a UDP port).
- Locale pinned to `en` for stable `testNode` / `setAsCurrentNode` literals.
- `MCP_BINDING=marionette`.

## Driver
1. Connect (`marionette.connect` + `fmt_connect_debug_app`); confirm sidebar `<nicknameA>\nOnline`; capture `get_runtime_errors({})` baseline.
2. **Runner-assertable add path** — call `l3_dht_info {}` (`l3_debug_tools.dart:2456-2489`) → record `{udpPort, dhtId}` as the local endpoint. Then `l3_add_bootstrap_node {host:'127.0.0.1', port:<udpPort>, pubkey:<dhtId>}` (`l3_debug_tools.dart:2496-2561`) → drives `FfiChatService.addBootstrapNode` → `tox_bootstrap`.
3. **L3-manual UI form** — open Settings → Bootstrap section; tap `UiKeys.manualNodeInputButton` to expand; fill `UiKeys.manualNodeHostField`, `UiKeys.manualNodePortField`, and `UiKeys.manualNodePubkeyField` via `fmt_enter_text`; tap `UiKeys.manualNodeTestButton` to invoke `_testManualNode`.
4. On a `success` test result, tap `setAsCurrentNode` (`bootstrap_settings_section.dart:953-1000` → `_setManualNodeAsCurrent`, line 324) and confirm the `nodeSetSuccess` SnackBar.

## Assertions
- A1: Step 1 baseline `get_runtime_errors` empty.
- A2: Step 2 `l3_dht_info` returns `udpPort>0` and a 64-hex `dhtId` (proves the live endpoint exists). `l3_add_bootstrap_node` returns `{ok:true}` — `addBootstrapNode` accepted the node (`l3_debug_tools.dart:2522-2530`).
- A3: log contains `[Bootstrap] add_bootstrap_node instance_id=<id> host=127.0.0.1 port=<udpPort> bootstrap_ok=1 err=0` (`tim2tox_ffi.cpp:2177`).
- A4 (L3-manual): after Step 4, `Prefs.getCurrentBootstrapNode()` returns the entered `{host,port,pubkey}` (`Prefs.setCurrentBootstrapNode`, `bootstrap_settings_section.dart:343`); the `nodeSetSuccess` SnackBar appeared.
- A5 (negative): no `[ffi] add_bootstrap_node: tox_bootstrap failed` (`tim2tox_ffi.cpp:2166`); no `FATAL`; `get_runtime_errors` matches baseline.

## Notes
- **Honest split**: the add path + DHT-endpoint readout (A2/A3) is fully runner-assertable through `l3_add_bootstrap_node`/`l3_dht_info`. The form-fill + `setAsCurrentNode` persistence (A4) remains L3-manual in outcome, but the manual affordance and fields now carry stable UiKeys: `manualNodeInputButton`, `manualNodeHostField`, `manualNodePortField`, `manualNodePubkeyField`, and `manualNodeTestButton`.
- **"Test connectivity" is a REAL reachability probe**: `_testManualNode` delegates to `BootstrapNodeProbe`, which sends a DHT `getnodes` request to the candidate and reports `nodeTestSuccess` ("Node reachable") only when a nodes response comes back. The verdict is **"any DHT nodes response on an isolated probe instance"**, NOT "a response authenticated with the typed public key" — `tox_callback_dht_nodes_response` does not report the responder (it fires once per node *contained in* the reply, and a node never lists itself), so waiting for the candidate's own key waits forever. Attribution comes from ISOLATION instead: the probe runs on a fresh short-lived Tox instance with local discovery off that is told about no node but the candidate, and toxcore only accepts a nodes response whose sender key/address/ping-id match a request that instance actually sent. See `BootstrapNodeProbe`'s class doc and `scenario_dht_nodes_response_api_test.dart`.
- A structurally-valid-but-dead node reports "Node unreachable" — do NOT assert a fixed remote-node latency, and do NOT expect a well-formed descriptor alone to go green. Two verdicts are deliberately NOT negatives about the node and stay promotable: `udpUnavailable` (no UDP socket bound, or not one `getnodes` could be sent during the window) and `BootstrapProbeUnavailable` (the probe instance failed to start — our defect, not the node's). The probe works with OR without a session (pre-login it uses its own ephemeral Tox instance), so this scenario is not post-login-only.
- `setAsCurrentNode` is gated on a prior `success` test result (`_manualNodeTestResult != 'success'` → `canOnlySelectTestedNode`, `bootstrap_settings_section.dart:325-334`), so Step 4 must follow a successful Step 3 test.
- Mobile has no `lan` mode and renders a 2-segment auto/manual control (`_buildModeRowMobile`, `bootstrap_settings_section.dart:1086`); this spec targets desktop manual mode.
