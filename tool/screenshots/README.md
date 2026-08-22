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

- `l3_set_connection`, `l3_seed_friend online=true` — presence. Seeded keys are
  not on the DHT and can never come online for real; a hero shot in which the
  app and every peer read "Offline" is not what is being shown.
- `l3_seed_friend avatarBase64=…` / `l3_create_group avatarBase64=…` — the
  persona avatars under `tool/screenshots/assets/`, installed through the same
  Prefs-backed avatar path the real avatar sync writes.
- `l3_inject_group_text epochMs=… fromUserId=<self pubkey>` — the hero's own
  group lines are injected as DELIVERED history (a real send in the offline
  seed environment parks as pending and renders a spinner); every group line
  carries a spaced timestamp like the C2C thread.
- `l3_set_capture_device hasCamera=true` (iOS/iPad) — the Simulator has no
  camera, so the video-call affordances would hide; a phone has one.
- `l3_set_orientation landscape` (iPad) — the product page frames the tablet
  shot landscape (1024x768); the Simulator boots portrait.

Navigation is **layout-aware**: desktop + iPad render the wide master-detail
shell (`l3_open_chat` binds the right pane); Android + iPhone render the narrow
bottom-nav shell (chats open as a pushed route, popped via `l3_pop_to_root`
between scenes).

Capture: desktop uses `flutter_skill.screenshot` (the Flutter layer — no
host-window grab, no screen-recording permission) in a **1400x909** window that
the driver sizes AND reads back (macOS clamps a window to the visible frame, and
a silently clamped window changes the aspect the product page declares).
Mobile uses the same Flutter-layer capture by default. `TOXEE_SHOT_NATIVE_FRAMES=1`
switches it to the **device framebuffer** (`simctl io screenshot` /
`adb exec-out screencap`) so the OS status bar and home indicator are part of
the shot instead of blank safe-area bands, pinning the status bar first
(`simctl status_bar override` / SystemUI demo mode: 9:41, full battery, Wi-Fi).
Only use it from a session that OWNS the Mac's display: measured 2026-08-22,
from a plain ssh shell `simctl io screenshot` returned a frozen composited
frame — five byte-identical scenes — while the app log showed the driver had
navigated every scene.

OS permission sheets are OS surfaces too, so they land in a framebuffer grab and
synthetic input cannot dismiss them. `capture.sh` builds with
`TOXEE_DISABLE_NOTIFICATION_PERMISSION_PROMPT=true` **and**
`TOXEE_DISABLE_CALL_PERMISSION_PREWARM=true` (the microphone sheet is the app's
own first-launch prewarm in `HomePage._maybePrewarmCallPermissions`, not a
capture artefact — `simctl privacy grant microphone` does NOT suppress it), and
additionally pre-grants what the platforms allow (`simctl privacy`,
`pm grant` after install + `pm clear`).

The iPad is captured PORTRAIT. An iPad app that supports multitasking follows
the DEVICE orientation and ignores `SystemChrome.setPreferredOrientations`, and
Simulator.app's Device ▸ Rotate Left needs an Accessibility grant a
non-interactive ssh session does not have — so `doc/product/index.html` declares
the portrait size (1024x1365) rather than the pipeline faking a landscape one.
`l3_set_orientation` still exists for a device/CI context that can honour it.

`--sync-site` resamples every platform to the point width
`doc/product/index.html` declares: desktop → 1024x665, iPad landscape →
1024x768, iPhone → 402 wide, Android → 412 wide.

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
