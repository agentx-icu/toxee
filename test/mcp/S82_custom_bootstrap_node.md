# S82 — Custom / failover DHT bootstrap node → connect

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online dhtCache=cold`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because the Online assertion is a real DHT bootstrap off the selected node (5–30s); L2 has no live network to observe the offline→online transition.
**Status**: covered

## Precondition
- Account A signed in, online; sidebar `_UserAvatar` shows `<nicknameA>\nOnline`.
- `network=online`, real DHT reachable; `dhtCache=cold` so the connect must come from the selected node.
- Bootstrap mode is `auto` — Settings exposes the node picker (`BootstrapNodesPage`) only in auto mode; manual mode shows the manual-input affordance instead, now anchored by `UiKeys.manualNodeInputButton` for the sister manual-entry flow.
- Locale pinned to `en` so the sidebar literal `Online` is stable.
- `MCP_BINDING=marionette`.

## Driver
1. Connect (`marionette.connect` + `fmt_connect_debug_app`); `fmt_semantic_snapshot` → confirm sidebar `<nicknameA>\nOnline`; capture `official.get_runtime_errors({})` baseline.
2. Navigate to Settings → Bootstrap node section; tap the `routeSelection` button (`OutlinedButton.icon`, `bootstrap_settings_section.dart:667-687`) to push `BootstrapNodesPage`.
3. `fmt_semantic_snapshot` of the node list; pick one `ONLINE` row (`node.status == 'ONLINE'`, the only tappable rows — `InkWell.onTap: isOnline ? ... : null`, `bootstrap_nodes_page.dart:342`). Optionally tap its `testNode` icon first and poll for the `success` label + `<latency>ms`.
4. Tap the row → confirm the `switchNode` AlertDialog → tap `ok` (`bootstrap_nodes_page.dart:142-158`).
5. Poll log up to 30s for the apply + Online markers (Assertions); poll snapshot for sidebar staying/returning to `<nicknameA>\nOnline`.

## Assertions
- A1: Step 1 baseline `get_runtime_errors` empty.
- A2: after Step 4, log contains `[Bootstrap] add_bootstrap_node instance_id=<id> host=<ip> port=<port> bootstrap_ok=1 err=0` (`tim2tox_ffi.cpp:2177`), proving `tox_bootstrap` accepted the selected node.
- A3: `addBootstrapNode` returned success → `Prefs.setCurrentBootstrapNode(...)` persisted (`bootstrap_nodes_page.dart:200`); the `nodeSwitched` SnackBar appears (`bootstrap_nodes_page.dart:218`).
- A4: log contains `HandleSelfConnectionStatus: ENTRY` then `HandleSelfConnectionStatus: Notified self online status (userID=<toxA>` (`V2TIMManagerImpl.cpp:5334/5461`) within the poll window.
- A5: sidebar `_UserAvatar` shows `<nicknameA>\nOnline`; status dot is `AppThemeConfig.successColor`.
- A6 (negative): no `[ffi] add_bootstrap_node: tox_bootstrap failed` (`tim2tox_ffi.cpp:2166`); no `[BootstrapNodeEnsurer] addBootstrapNode failed` (`bootstrap_node_ensurer.dart:146`); no `FATAL`/`terminate called`; `get_runtime_errors` matches baseline.

## Notes
- Single client, no peer required: this is a self-connection / DHT-join assertion against a real bootstrap node, so it runs with one toxee instance and no Fixture C twin.
- Custom-node UI exists as a SELECT-from-online-list picker (`BootstrapNodesPage`), not a free-form host/port/key entry in auto mode; the free-form path is the `manualNodeInput` affordance under manual mode. That manual section now ships stable anchors for MCP/manual automation: `UiKeys.manualNodeInputButton`, `UiKeys.manualNodeHostField`, `UiKeys.manualNodePortField`, `UiKeys.manualNodePubkeyField`, and `UiKeys.manualNodeTestButton`.
- No UiKey on node rows — tap by semantic ref (`fmt_tap_widget(ref="s_N")`) matching the `<ipv4>:<port>` monospace title.
- Node testing works PRE-LOGIN too since 2026-08-14: `_testNode` routes through `BootstrapNodeProbe`, which stands up its own ephemeral Tox instance when there is no session (`lib/util/bootstrap_node_probe.dart`). This scenario runs post-login, where the probe reuses the live service.
- Cold-cache DHT join is the wall-clock variance (5–30s); do not sleep — poll for the Online markers. Tox dedups/drops unreachable entries silently, so a stale-but-structurally-valid node still yields `bootstrap_ok=1`; A4 (Online) is the real connectivity proof.
