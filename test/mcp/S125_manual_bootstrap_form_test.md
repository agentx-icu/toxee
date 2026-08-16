# S125 — Manual bootstrap form: open → enter host/port/pubkey → test (real taps)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online bootstrapMode=manual`
**Harness mode**: peerHarness=none
**Promotion target**: L1 WidgetTester for the FORM input + validation surface (`test/ui/settings/bootstrap_settings_section_test.dart` exists); the live-connect leg (`addBootstrapNode` → `tox_bootstrap`) is L3-pinned (real DHT).
**Status**: covered (split: the add path is an AGENT-DRIVEN debug-tool flow (S89 L3-manual), NOT a runner gate; the manual FORM fill + `_testManualNode` tap is the marionette real-UI step; the form/validation surface is L1). Real-UI sibling of S89.

> Real-UI sibling of S89. S89 frames the agent-driven (L3-manual) debug-tool add path (`l3_dht_info` → `l3_add_bootstrap_node`); S125 walks the keyed manual FORM: Settings → bootstrap section → set mode=manual → tap the input button → fill host/port/pubkey → tap test → observe the connectivity result. The form fields + validation are L1-promotable; the live `addBootstrapNode` connect is L3.

## Precondition
- Debug macOS app built with the L3 surface:
  `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`; launched `MCP_BINDING=marionette ./run_toxee.sh`.
- Account A signed in, online, test/seed account (mutating L3 tools refuse a non-test account, `l3_debug_tools.dart` `_activeAccountIsTest`); sidebar `<nick>\nOnline` (poll ≤60s).
- `Prefs.bootstrapNodeMode == 'manual'` so the section renders the manual-input affordance instead of the auto picker (`bootstrap_settings_section.dart:733` `if (_bootstrapNodeMode == 'manual')`). Set via the desktop radio `UiKeys.settingsBootstrapModeManual` (`settings_bootstrap_mode_manual`, `bootstrap_settings_section.dart:1130`) — sibling S99/S85 — OR `l3_set_setting {key:'bootstrapNodeMode', value:'manual'}` (`l3_debug_tools.dart:1853-1868`). Restore `auto` at end so the fixture self-cleans.
- `network=online`, a real local DHT endpoint exists (the running Tox instance binds a UDP port — readable via `l3_dht_info`).
- Locale pinned to `en` for stable `testNode` / `nodeTestSuccess` literals.
- `MCP_BINDING=marionette`.

## Executable Driver

No runner gate exists. `run_l3_scenarios.dart` has NO `add_bootstrap_node`/`dht_info` action (its action switch supports `send_text/clear_history/delay/wait_for/warmup/tap/long_press/enter_text/invoke_action/mark_read/set_setting/set_pinned/set_friend_remark/set_self_profile/set_blocked/set_recv_opt/reply_text/forward_message/create_group/send_group_text/leave_group` only — `run_l3_scenarios.dart:358-522`) and there is no scenario JSON for the add path. The add-path debug tools `l3_dht_info` (`_l3DhtInfoEntry()` @ `lib/ui/testing/l3_debug_tools.dart:3158`, registered `name: 'l3_dht_info'` @ `:3184`) and `l3_add_bootstrap_node` (`_l3AddBootstrapNodeEntry()` @ `:3198`, registered `name: 'l3_add_bootstrap_node'` @ `:3247`) are driveable ONLY via a LIVE marionette/agent session (the S89 L3-MANUAL path), not via the JSON runner. The FORM input + validation surface is the L1 promotion target (`test/ui/settings/bootstrap_settings_section_test.dart`).

## UI Driver
1. Connect; `fmt_semantic_snapshot` → confirm sidebar `<nick>\nOnline`; baseline `official.get_runtime_errors({})`.
2. Set mode=manual: navigate Settings → bootstrap section → tap `UiKeys.settingsBootstrapModeManual` (`settings_bootstrap_mode_manual`, `bootstrap_settings_section.dart:1130`). (Or `l3_set_setting {bootstrapNodeMode:'manual'}`.) Confirm the manual affordance renders.
3. Tap `UiKeys.manualNodeInputButton` (`manual_node_input_button`, `bootstrap_settings_section.dart:736`) — the `OutlinedButton.icon` toggling `_manualInputExpanded`; the `AnimatedSize` form (`:891`) expands.
4. `marionette.enter_text` into the three fields: `UiKeys.manualNodeHostField` (`manual_node_host_field`, `:906`) ← a reachable host; `UiKeys.manualNodePortField` (`manual_node_port_field`, `:928`) ← the UDP port (use the `l3_dht_info` `udpPort` and host `127.0.0.1` for a structurally-valid local probe); `UiKeys.manualNodePubkeyField` (`manual_node_pubkey_field`, `:951`) ← the 64-hex pubkey (the `l3_dht_info` `dhtId` for the local probe).
5. Tap `UiKeys.manualNodeTestButton` (`manual_node_test_button`, `bootstrap_settings_section.dart:1011`) — fires `_testManualNode` (`:230`), which validates the fields then calls `service.addBootstrapNode(host, port, pubkey)` (`:266`) and shows the `_StatusPill` (`nodeTestSuccess` / `nodeTestFailed`) + a SnackBar (`:294`).
6. Poll the snapshot + log ≤30s for the test result; if `success`, the `setAsCurrentNode` `ElevatedButton` appears (`:1030`) — optionally tap it (`_setManualNodeAsCurrent`, `:326`) to persist via `Prefs.setCurrentBootstrapNode` (`:347`).

## Assertions
- A1 (baseline): Step 1 — `official.get_runtime_errors({})` empty.
- A2 (form expands + fields keyed): after Step 3, `manual_node_host_field`, `manual_node_port_field`, `manual_node_pubkey_field` are all present in the tree (the `_manualInputExpanded` Column, `bootstrap_settings_section.dart:894-971`).
- A3 (validation, soft): empty/invalid input short-circuits before any network call — `_testManualNode` returns early with the `invalidNodeInfo` SnackBar if any field is empty (`:234-243`) or port ∉ (0, 65535] (`:245-256`). This is the L1-promotable validation surface (drive it by tapping test with a blank field).
- A4 (live add / connectivity, primary): for the local-endpoint probe (`127.0.0.1:<udpPort>` + `<dhtId>`), `_testManualNode` → `service.addBootstrapNode` returns true → `_manualNodeTestResult == 'success'` → the `_StatusPill` shows `nodeTestSuccess` and a `<latency>ms` label (`:976-1002`). Log: `[Bootstrap] add_bootstrap_node instance_id=<id> host=127.0.0.1 port=<udpPort> bootstrap_ok=1 err=0` (`tim2tox_ffi.cpp:2177`). The agent-driven debug-tool half (S89 A2/A3, live session only) corroborates: `l3_dht_info` returns `udpPort>0` + 64-hex `dhtId`, `l3_add_bootstrap_node` returns `{ok:true}`.
- A5 (persist, if Step 6 taken): after tapping `setAsCurrentNode`, `Prefs.getCurrentBootstrapNode()` returns the entered `{host,port,pubkey}` (`_setManualNodeAsCurrent` → `Prefs.setCurrentBootstrapNode`, `:347`); `setAsCurrentNode` is gated on a prior `success` test (`:327`, else `canOnlySelectTestedNode`).
- A6 (negative): no `[ffi] add_bootstrap_node: tox_bootstrap failed` (`tim2tox_ffi.cpp:2166`); no `FATAL` / `terminate called`; `official.get_runtime_errors({})` matches the Step-1 baseline. Restore `bootstrapNodeMode=auto` at end.

## Notes
- **Honest split**: the add path + DHT-endpoint readout (A4 corroboration) is an AGENT-DRIVEN debug-tool flow via `l3_add_bootstrap_node`/`l3_dht_info` (S89 L3-manual) — these are debug TOOLS callable only in a live marionette/agent session, NOT a `run_l3_scenarios.dart` gate (the runner has no `add_bootstrap_node`/`dht_info` action). The FORM fill + `_testManualNode` tap + `setAsCurrentNode` persistence are L3-manual in outcome; the fields/buttons carry stable UiKeys but the form-fill itself is a marionette step. The field/validation surface is the L1 promotion (`test/ui/settings/bootstrap_settings_section_test.dart` exists).
- **Test needs a genuinely reachable node**: `_testManualNode` delegates to `BootstrapNodeProbe` (`lib/util/bootstrap_node_probe.dart`), which goes green only on a DHT `getnodes` response authenticated with the typed public key. Probing `127.0.0.1:<own-udpPort>` still works (A4); a remote public node depends on that node being up — do NOT assert a fixed remote latency. Works pre-login too (ephemeral Tox instance), so `service != null` is no longer a precondition.
- Keys verified: `manualNodeInputButton` @ `bootstrap_settings_section.dart:736`; `manualNodeHostField` @ `:906`; `manualNodePortField` @ `:928`; `manualNodePubkeyField` @ `:951`; `manualNodeTestButton` @ `:1011` (all defined `ui_keys.dart:256-260`). Mode radio `settingsBootstrapModeManual` @ `:1130`.
- Sibling distinction: S89 = agent-driven (L3-manual) add path framing (same `l3_dht_info`/`l3_add_bootstrap_node` debug tools); S82 = the AUTO-mode online-node PICKER (different affordance, no free-form fields); S99/S85 = the mode-toggle itself; S125 = the keyed manual FORM walk.
- Mobile parity: mobile has no `lan` mode and renders a 2-segment auto/manual control (`_buildModeRowMobile`, `bootstrap_settings_section.dart:1086`); the manual FORM fields + test button are in the SHARED widget body, so the keys cover mobile, but this spec drives the desktop mode radio in Step 2 (use the mobile segmented control there on phone).
