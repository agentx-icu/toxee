# Product-screenshot pipeline (cross-platform)

One command captures the 5 product scenes on **four platforms** — desktop
(macOS), Android, iPad, and iOS (iPhone) — in light theme. Output lands in
`./screenshot/<platform>/`.

```bash
./tool/screenshots/capture.sh                              # all four platforms
./tool/screenshots/capture.sh --platforms desktop,ios      # a subset
./tool/screenshots/capture.sh --platforms desktop --build  # force a rebuild
./tool/screenshots/capture.sh --platforms desktop --reset  # fresh macOS seed
```

Each platform launches **one real toxee instance** with the L3 debug surface
(`MCP_BINDING=skill` + `TOXEE_L3_TEST=true`), seeds demo data **locally** (no
peer, no P2P), drives the real UI, and captures:

| scene | what |
|---|---|
| `c2c` | 1:1 chat with "Alex Chen" — delivered bubbles both directions |
| `group_chat` | the "Weekend Hikers 🏔" group with multi-sender history |
| `new_application` | the New-Contacts page with a pending "Jordan Lee" request |
| `self_profile` | the hero's profile (nickname, status, Tox ID + QR) |
| `settings` | the settings page |

While it runs, **don't steal foreground from the macOS window** (the desktop
scene walk owns the foreground; mobile sims render off-screen).

## Targets (override via env)

| platform | default device | env override |
|---|---|---|
| `desktop` | the macOS app | — |
| `android` | first `adb` emulator | `TOXEE_SHOT_ANDROID_SERIAL` |
| `ios` | booted iPhone, else iPhone 16 Pro | `TOXEE_SHOT_IOS_UDID` |
| `ipad` | booted iPad, else iPad Pro 13-inch (M4) | `TOXEE_SHOT_IPAD_UDID` |

Mobile devices/sims must exist; the tool boots a simulator if needed and builds
+ installs the debug app itself.

## How it works

Everything is seeded **per-instance via new debug-only L3 tools** — no fragile
cross-platform P2P. The tools are gated to test/seed accounts and tree-shaken
from release builds:

- `l3_seed_friend {userId, nickname}` — add a confirmed friend by public key
  (`tox_friend_add_norequest`, no handshake) with a cached display name.
- `l3_inject_c2c_text {userId, text, isSelf, epochMs}` — materialize a DELIVERED
  text bubble in either direction.
- `l3_inject_friend_application {userId, nickname, wording}` — a pending inbound
  friend request for the New-Contacts page.
- `l3_create_group` + `l3_inject_group_text` — the group + its history.
- `l3_open_self_profile` / `l3_pop_to_root` — layout-agnostic navigation hooks.

Navigation is **layout-aware**: desktop + iPad render the wide master-detail
shell (`l3_open_chat` binds the right pane); Android + iPhone render the narrow
bottom-nav shell (chats open as a pushed route, popped via `l3_pop_to_root`
between scenes). Capture is `flutter_skill.screenshot`, which renders the
Flutter layer (`RenderRepaintBoundary.toImage`) identically on every platform —
no host-window grab, no screen-recording permission.

### Per-platform launch + VM-service discovery

- **desktop** — built via `run_toxee.sh` and launched through
  `tool/mcp_test/launch_toxee_instance.sh` (ws URI from `instance.json`). Self-
  heals a missing Xcode debug-dylib with one clean rebuild.
- **android** — `flutter build apk` (NDK FFI via `tool/build_android_ffi.sh`),
  `adb install`, `am start`; the VM URI is read from **logcat** and the port is
  `adb forward`ed to the host. App data is cleared each run (`pm clear`).
- **ios / ipad** — `flutter build ios --simulator` + the tim2tox FFI framework
  injected into `Runner.app/Frameworks` (`tool/build_ios_sim_ffi.sh`), installed
  via `simctl`; the VM URI is read from the unified **log stream** and reached
  directly (the sim shares the host's localhost). App reinstalled each run.

Mobile runs always start from a fresh account (the equivalent of desktop
`--reset`) for deterministic captures.

## Maintenance notes

- The macOS seed account persists under `_seed_runtime/` (gitignored); `--reset`
  rebuilds it. Mobile state lives on the device/sim and is cleared each run.
- The debug app must be built with the L3 surface (`--build` does this).
- `screenshot/` is gitignored — curate/copy out anything you want to keep.
- A per-machine NDK override (when the default Flutter NDK is a partial install)
  goes in the gitignored `android/local.properties` as
  `flutter.ndkVersion=<version>`; committed config stays portable.
