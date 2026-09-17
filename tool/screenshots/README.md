# Product-screenshot pipeline (cross-platform)

One command captures the 5 product scenes on **four platforms** — desktop
(macOS), Android, iPad, and iOS (iPhone) — in light theme, in **two UI
languages** (English and Simplified Chinese). Frames are written straight to the
committed `doc/product/assets/<locale>/<platform>/`, at capture resolution (no
intermediate directory, no resampling).

```bash
./tool/screenshots/capture.sh                              # all platforms × en,zh
./tool/screenshots/capture.sh --platforms desktop,ios      # a subset
./tool/screenshots/capture.sh --locales zh                 # one language only
./tool/screenshots/capture.sh --platforms desktop --build  # force a rebuild
./tool/screenshots/capture.sh --platforms desktop --reset  # fresh macOS seeds
./tool/screenshots/capture.sh --reset --build              # full refresh of doc assets
```

### Languages

Each locale is a separate pass with its **own seed copy**, not just a
different UI language: the Chinese shots show Chinese names, group and
dialogue (林小雨 / 陈亮 / 「周末徒步队 🏔」), because a Chinese UI over English
conversations reads as a half-translated product. The copy lives in
`seed_data.dart` (English, plus the `SeedScript` shape) and
`seed_data_zh.dart`; only the public keys are shared — each locale has its own
initials avatars (`assets/avatar_*_zh.png` for Chinese). The driver sets
the app language with `l3_set_setting languageCode=<locale>`.

| locale | doc that shows it | committed assets |
|---|---|---|
| `en` | `README.md`, `doc/product/index.html` (default) | `doc/product/assets/en/<platform>/` |
| `zh` | `README.zh-CN.md`, `doc/product/index.html` (中文 toggle swaps the images) | `doc/product/assets/zh/<platform>/` |

Adding a locale: write a `SeedScript` for it, register it in `seedScripts`
(seed_data.dart), allow it in capture.sh's locale check, and reference
`assets/<locale>/` from that language's docs.

The desktop seed account persists between runs, so it is kept **per locale**
(`_seed_runtime/Shot` for English, `_seed_runtime/ShotZh` for Chinese) — the
seed is idempotent by message count and group name and would otherwise keep
the other language's dialogue. Mobile runs reinstall / `pm clear` per locale.

Each platform launches **one real toxee instance** with the L3 debug surface
(`MCP_BINDING=skill` + `TOXEE_L3_TEST=true`), seeds demo data **locally** (no
peer, no P2P), drives the real UI, and captures:

| scene | what (en / zh) |
|---|---|
| `c2c` | 1:1 chat with "Alex Chen" / "陈亮" — delivered bubbles both directions |
| `group_chat` | the "Weekend Hikers 🏔" / "周末徒步队 🏔" group with multi-sender history |
| `new_application` | the New-Contacts page with pending requests ("Jordan Lee" / "李佳" …) |
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
- `l3_set_orientation landscape` (iPad) — best-effort only; under `simctl`
  the iPad stays portrait (see "The iPad is captured PORTRAIT" below).

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
the portrait size (1032x1376) rather than the pipeline faking a landscape one.
`l3_set_orientation` still exists for a device/CI context that can honour it.

### Output

Each platform × locale is captured into a per-run temp dir and **published**
into `doc/product/assets/<locale>/<platform>/` only when its driver exited 0 and
all five scenes exist; a failed or SnackBar-contaminated run leaves the committed
assets untouched and prints the temp dir holding its frames. Published sizes are
the capture sizes — desktop 1400x909, iPad 1032x1376, iPhone 402x874, Android
412x891 — which is what `doc/product/index.html` declares. (Frames used to be
`sips`-downscaled to point width; that produced larger, blurrier files and was
dropped.) `TOXEE_SHOT_NATIVE_FRAMES=1` device-framebuffer frames are published
as-is too, i.e. at device pixel resolution (≈3x on phones).

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

- The macOS seed accounts persist under `_seed_runtime/` (gitignored, one per
  locale); `--reset` rebuilds them. Without `--reset` a reused seed keeps the
  day it was seeded, so its threads show a date instead of today's times. Mobile state lives on the device/sim and is cleared each run.
- The debug app must be built with the L3 surface (`--build` does this).
- A per-machine NDK override (when the default Flutter NDK is a partial install)
  goes in the gitignored `android/local.properties` as
  `flutter.ndkVersion=<version>`; committed config stays portable.
