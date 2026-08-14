# integration_test — host-binary smokes

`integration_test/` is reserved for tests that genuinely need the host
platform bundle: real `libtim2tox_ffi` dlopen, `window_manager`, system
tray, file picker, camera/microphone, OS notifications. Those tests pay
the cost of building a Toxee.app (macOS) / Toxee.exe / Toxee APK before
the Dart isolate starts.

**Hermetic widget tests live in `test/`.** They use
`TestWidgetsFlutterBinding` + mock plugin channels and don't need a host
binary.

## Current contents

| File | Why here |
|---|---|
| `app_smoke_test.dart` | Cold-start chain. Wants to be hermetic but `TencentCloudChatMaterialApp._getLocale` → `TencentCloudChat.instance.cache.init` (Hive) hangs when run from `test/` because Hive needs more than path_provider channel mocks to bootstrap. Host build supplies the rest. |

Host-bundle harnesses that mount `EchoUIKitApp` directly call
`host_bundle_test_support.dart` before installing channel stubs. These tests
bypass `main()` / `AppBootstrap` / `DesktopShellBootstrap`, so desktop hosts
must initialize the real `window_manager` plugin themselves. Otherwise the
second frame's `DesktopWindowFrame.isMaximized` call reaches the macOS Swift
`WindowManager.mainWindow` force-unwrap before initialization and SIGTRAPs.
The helper calls `ensureInitialized()` on macOS, Windows, and Linux and is a
no-op on mobile.

## Move history (2026-05-28)

1. **Initial audit** flagged this test as "should be in `test/`" — it uses
   `TestWidgetsFlutterBinding` + channel mocks, matches the widget-test
   structure exactly.
2. **Moved** to `test/startup_smoke_test.dart`.
3. **Found** on actual run: hangs at `FutureBuilder<Locale?>`, never reaches
   `LoginPage`. `pumpAndSettle` returns silently (no scheduled frames), so
   the failure looked like a passing test until the assertion fires.
4. **Moved back** to `integration_test/app_smoke_test.dart` with
   `@Tags(['needs-native'])`. The opt-in `.github/workflows/e2e.yml` (label
   `ci:e2e`) is the only CI surface that runs it.

The hermetic version of this test is a real follow-up — possible if
someone properly stubs Hive's directory init (or pumps an alternative
locale source). Not done in this round.

## Add Friend dialog smoke stayed in `test/`

`test/ui/add_friend_dialog_smoke_test.dart` (the smaller-scope smoke for
`NewEntryButton → AddFriendDialog`) is genuinely hermetic and runs from
`test/` cleanly. The scope difference: it never pumps
`TencentCloudChatMaterialApp` at the root, so it dodges the Hive
bootstrap entirely.

## When adding a new integration_test

1. Confirm it actually needs the host bundle. If `TestWidgetsFlutterBinding`
   + channel mocks would work, put it in `test/` instead.
2. Tag with `@Tags(['needs-native'])` so `flutter test --exclude-tags=needs-native`
   skips it on lighter CI.
3. The opt-in workflow `.github/workflows/e2e.yml` (label `ci:e2e`) gates
   `flutter test integration_test/ -d <platform>` per PR.
