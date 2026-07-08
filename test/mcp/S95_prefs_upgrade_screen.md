# S95 — Prefs newer-than-app → upgrade-required screen (cold start)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=0-or-1 current=any autoLogin=any network=offline prefsSchemaVersion=NEWER`
**Harness mode**: peerHarness=none
**Promotion target**: L2 candidate — `PrefsUpgrader.run` + `UpgradeRequiredApp` could be exercised in a pure widget test with a `SharedPreferences.setMockInitialValues({'prefs_schema_version': 99})` + pumped `UpgradeRequiredApp`. L3-pinned here because the assertion is the REAL cold-start branch in `main()` (the `runApp(UpgradeRequiredApp(...))` arm), which only fires through the full `AppBootstrap.initialize()` → `PrefsBootstrap.initialize()` path.
**Status**: covered. The `UpgradeRequiredScreen` surface (title, version-aware message body, system-update chip, and the primary "Update" action firing its production handler) is now covered at the widget layer (L1). The end-to-end cold-start gate (the `main()` upgrade arm reached via the crafted Prefs fixture) remains an L3 playbook, since it needs a deliberately-newer `prefs_schema_version` store that the runner's seeded account never has. Feature **A3** (Prefs 版本/升级检测 → 升级屏; `lib/bootstrap/prefs_bootstrap.dart`, `lib/util/prefs_upgrader.dart`, `lib/ui/upgrade_required_screen.dart`).
**Covered-by**: `test/ui/startup/upgrade_required_screen_real_ui_test.dart` (widget-layer L1: renders the real `UpgradeRequiredScreen`; the "Update" button drives its production handler via the canonical `onUpdate` ctor seam over `_openReleasesPage`).

## Precondition
- A crafted SharedPreferences store where the global schema key `prefs_schema_version` holds an int GREATER than `currentGlobalPrefsVersion` (currently **2**, `prefs_upgrader.dart:7` / key `prefs_schema_version`, `prefs_upgrader.dart:21`). Pre-write e.g. `99`.
- This is injected by the fixture, NOT `l3_set_setting` (which has no schema-version key — it rejects anything outside its narrow allow-list, `l3_debug_tools.dart:1307-1321`). On macOS write it into the app's defaults domain BEFORE launch, honoring the `TOXEE_SHARED_PREFS_PREFIX` env prefix if the harness sets one (`prefs_bootstrap.dart:16-23`): `defaults write com.toxee.app <prefix>prefs_schema_version -int 99` (the SharedPreferences key is the raw prefix + `prefs_schema_version`), then `killall cfprefsd`.
- `network=offline` is fine — the screen renders before any login/DHT; the only outbound action is the releases-page `launchUrl` on a button tap (`upgrade_required_screen.dart:133-144`).
- Locale pinned to `en` so `upgradeRequiredTitle` / `update` literals are stable.
- `MCP_BINDING=marionette`.

## Driver
1. With the crafted store in place, cold-launch the app (`MCP_BINDING=marionette ./run_toxee.sh`); `marionette.connect(uri=$URI)` + `fmt_connect_debug_app`.
2. `fmt_semantic_snapshot` of the first frame → it should be the upgrade screen, NOT LoginPage and NOT a sidebar.
3. Capture `s95_upgrade_screen.png`.
4. (Optional) tap the `update` FilledButton (`upgrade_required_screen.dart:208-221`) → confirm it attempts to open the releases URL (log line, not a real browser assertion in CI).

## Assertions
- A1: log contains `Prefs stored by newer app (99 > 2), showing upgrade required` (`prefs_bootstrap.dart:65-67`) — proves `PrefsUpgrader.run` threw `PrefsStorageNewerThanAppException` (`prefs_upgrader.dart:72-73`) and `PrefsBootstrap.initialize()` returned `AppBootstrapUpgradeRequired`.
- A2: `main()` took the upgrade arm — `runApp(UpgradeRequiredApp(...))` (`main.dart:176-185`), NOT `runApp(EchoUIKitApp())` (`main.dart:173-175`). The snapshot shows `UpgradeRequiredScreen` content.
- A3: snapshot contains the `upgradeRequiredTitle` text ("Please upgrade the app", `app_en.arb:1208`) and the `upgradeRequiredMessage(99, 2)` body ("…data version: 99…supports up to 2…", `upgrade_required_screen.dart:199` / `app_localizations_en.dart:1183`), plus the `Icons.system_update` chip (`upgrade_required_screen.dart:184`).
- A4: NO sidebar / `Online` node, NO LoginPage `savedAccounts` header — the app did not boot past the gate.
- A5 (data-safety): the upgrade screen does NOT overwrite prefs. `PrefsUpgrader.run` only writes `setInt(prefs_schema_version, …)` on the `stored < current` branch (`prefs_upgrader.dart:76-81`); the `stored > current` branch throws before any write — assert `prefs_schema_version` is still `99` after the screen renders.
- A6: `get_runtime_errors({})` baseline-clean (the thrown exception is caught in `PrefsBootstrap`, not surfaced as an uncaught error).

## Notes
- **L3-pin reason**: needs a crafted Prefs fixture (a storage version newer than the app), which the runner's normal seeded account never has — the seed always writes the current schema. This scenario is the inverse of every other S-spec: the precondition is a deliberately-corrupt-looking store.
- Only the GLOBAL version triggers the screen. Per-account migrations (`runAccountMigrations`, `prefs_upgrader.dart:86`) run later at login and do NOT throw this exception — bumping `account_prefs_version_<prefix>` will not show the upgrade screen. Use the global `prefs_schema_version` key.
- Reset between runs: `defaults delete com.toxee.app <prefix>prefs_schema_version` (or set it back to `2`); `killall cfprefsd`. Leaving `99` in place keeps the app permanently on the upgrade screen.
- The releases URL is hardcoded (`_kReleasesUrl = https://github.com/agentx-icu/toxee/releases`, `upgrade_required_screen.dart:13`) precisely because the app is behind its own data file and a server fetch would be racy — A4's button tap is best verified by the `launchUrl returned false` log path (`upgrade_required_screen.dart:139`) under a headless CI with no browser, not by a real navigation.
