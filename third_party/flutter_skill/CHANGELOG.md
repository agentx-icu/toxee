## 0.9.36

**Fix EACCES: ensure native binary has execute permission before spawn**

### Changes
- TODO: Add your changes here

---

## 0.9.35

**Fix inspect empty text, Flutter 3.38+ URI detection, MCP stdout pollution, Homebrew arm64 on Intel, Windows flutter command**

### Changes
- TODO: Add your changes here

---

## 0.9.34

**notifications/tools/list_changed support + idb integration for native iOS automation**

### Changes
- TODO: Add your changes here

---

## 0.9.33

**fix dart format CI check across all files**

### Changes
- TODO: Add your changes here

---

## 0.9.32

**fix dart format in CI**

### Changes
- TODO: Add your changes here

---

## 0.9.31

**fix scroll_to crash on unmounted context (#28), improve setup error messages (#15)**

### Changes
- TODO: Add your changes here

---

## 0.9.30

**Fix Gemini/Vertex AI "Duplicate function declaration" error (issue #32)**

### Changes
- Fix: remove duplicate `get_network_requests` definition — direct root cause of Gemini 400 error
- Fix: limit tools/list to ~11 connection tools before any connection, preventing Gemini 128-tool limit breach
- Add: `connectionOnlyTools` set and `geminiToolLimit` constant in ToolRegistry
- Add: `test/tool_registry_test.dart` — 17 unit tests covering tool filtering behavior

---

## 0.9.29

**Fix: add connect_openclaw_browser and connect_webmcp to tool_registry**

### Changes
- Fix: register `connect_openclaw_browser` and `connect_webmcp` in tool_registry.dart so they appear in tools/list

---

## 0.9.28

**Add connect_openclaw_browser and connect_webmcp tools; fix OpenClaw plugin binary path**

### Changes
- Add `connect_openclaw_browser` tool: instant connection to OpenClaw's built-in Chrome (port 18800, no launch needed)
- Add `connect_webmcp` tool: Chrome 146+ native WebMCP support with auto-detection and CDP fallback
- Fix OpenClaw plugin binary path: use `~/.pub-cache/bin/flutter_skill` instead of volatile `/tmp/fs-*`

---

## 0.9.27

**fix coordinate filtering, tap(ref) elem_ fix, Windows lock fallback, CLI error improvements**

### Changes
- TODO: Add your changes here

---

## 0.9.25

**fix coordinate system: filter non-active routes, fix tap(ref: elem_NNN), fix off-screen tap detection**

### Changes
- TODO: Add your changes here

---

## 0.9.24

**fix 6 UX issues: DTD error detection, wider port scan, connect_by_pid, stale session cleanup, screenshot save_to_file default**

### Changes
- TODO: Add your changes here

---

## 0.9.23

**fix null check crash and stop auto-opening browser on RPC errors from target app**

### Changes
- TODO: Add your changes here

---

## 0.9.22

**Support Chrome 146 WebMCP: discover and call navigator.modelContextTesting tools**

### Changes
- Added Chrome 146+ native WebMCP support to discover_page_tools and call_page_tool
- discover_page_tools now checks navigator.modelContextTesting.getTools() first (source: webmcp-native)
- call_page_tool now routes to navigator.modelContextTesting.executeTool() for WebMCP tools
- Enable via chrome://flags/#enable-webmcp-testing in Chrome 146
- Compatible with all existing tool discovery sources (js-registered, data-mcp-tool, forms, etc.)

---

## 0.9.21

**Auto-accept Chrome 146 remote debugging consent dialog**

### Changes
- Chrome 146 consent port shows "Allow remote debugging?" dialog on every connection — user had to manually click Allow each time
- Now auto-clicks the Allow button via macOS Accessibility API (AXSheet + AXButton description="Allow") in parallel with the WebSocket connection
- Users no longer need to manually confirm remote debugging — connect_cdp works seamlessly

---

## 0.9.20

**Respect launch_chrome:false — skip session-copy when user Chrome has no debug port**

### Changes
- When launch_chrome:false, Chrome is running but has no debug port: now fails with a clear error instead of launching a session-copy Chrome
- Previously Steps 2&3 (enable via chrome://inspect and restart with debug port) ran even with launch_chrome:false, overriding user intent
- Now Steps 2&3 only run when launch_chrome:true; false means "use existing debug port only"

---

## 0.9.19

**Fix Chrome 146 consent port: skip Origin header in WebSocket upgrade**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.9.18

**Support Chrome 146 consent-based remote debugging port**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.9.17

**Session-copy profile: preserve user logins when Chrome 145+ blocks default profile debug port**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.9.16

**Fix Chrome 145+ silently ignoring --remote-debugging-port on default profile**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.9.15

**Remove Chrome for Testing dependency from CDP driver**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.9.14

**Fix Page.enable hang on chrome://newtab; auto-enable remote debugging**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.9.13

**Auto-tick chrome remote debugging checkbox; no Chrome restart**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.9.12

**Restart existing Chrome with debug port; preserve user session**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.9.11

**Auto-enable Chrome remote debugging when connecting via CDP**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.9.10

**UX fixes: fill tool, press_key iOS fallback, go_back count, coordinate hint**

### Bug Fixes
- **`fill` tool registered**: `fill` was documented but threw `Unknown tool: fill`. Now maps to `enter_text` (clear + set value). Closes user-reported issue.
- **`press_key` on iOS/Android**: Added NativeDriver fallback so `press_key` works in Flutter VM Service mode on simulators/emulators (previously returned unsupported error). Enter key now triggers iOS search without needing CDP mode.
- **`enter_text` without key**: When called without `key`/`ref`, returns an actionable `hint` field pointing to `inspect_interactive()` instead of the confusing `No TextField matching key 'null' found` error.
- **`go_back` with `count`**: Accepts a `count` parameter to pop multiple routes in one call with 300 ms pauses between steps — replaces repeated `go_back()` chains.
- **`native_screenshot` coordinate hint**: Response now includes `scale_factor` and a `coordinate_hint` field that explains the physical→logical pixel conversion, eliminating manual coordinate guessing.

---

## 0.9.9

**C++ desktop automation SDK**

### New SDK
- **C++ Bridge SDK** (`sdks/cpp/`): Cross-platform native C++ automation bridge. Embeds a zero-dependency WebSocket server (RFC 6455) + JSON-RPC 2.0 dispatcher in your C++ app so AI agents can control it via the flutter-skill protocol. Closes #22.
  - **macOS**: CGEvent for input synthesis, `screencapture` for screenshots, AXUIElement for accessibility inspection
  - **Windows**: `SendInput` + GDI+ (screenshots) + `GetForegroundWindow`
  - **Linux**: XTest extension + XGetImage/libpng + EWMH
  - No external dependencies — SHA-1, base64, and WebSocket framing are bundled
  - Full CMake build system (`CMakeLists.txt`) for all three platforms
- **Tests**: 30 unit tests (JSON-RPC, SHA-1/base64/WebSocket RFC vectors, bridge protocol with mock backend) + 27 real integration tests verified live on macOS (1630 KB PNG screenshot, tap, scroll, all key names, enter_text, inspect, window title)

---

## 0.9.8

**Multi-flavor app detection, fresh-install UX, Docker/Snap build fixes, CI smoke tests**

### Bug Fixes
- **Multi-flavor app detection** (#24): `scan_and_connect` now accepts `flavor` and `device_id` parameters. When multiple flavors run simultaneously, flutter-skill picks the correct instance instead of connecting randomly.
- **Fresh-install plugins warning** (#23): Removed the `Plugins directory not found` warning on clean installs — silently skipped instead.
- **Docker build**: Dockerfile now uses `ghcr.io/cirruslabs/flutter:stable` so `flutter pub get` resolves Flutter SDK dependencies correctly.
- **Snap build**: Added `git config --global --add safe.directory /opt/flutter` to resolve `detected dubious ownership` error in snapcraft builds.

### CI / Testing
- Smoke test job added to CI: verifies fresh `flutter pub global activate` install works end-to-end.
- Post-release smoke test in release workflow: installs from pub.dev and npm after publish and confirms server responds.

---

## 0.9.7

**press_key for Flutter VM Service, pytest plugin, HarmonyOS SDK, CI smoke tests**

### Bug Fixes
- **press_key in Flutter mode**: `press_key` now works when connected via VM Service (not just CDP/bridge). Calls the existing `ext.flutter.flutter_skill.pressKey` extension that was already registered in the target app but never wired from the CLI side. Fixes #21.

### New SDKs
- **pytest-flutter-skill** (`sdks/python/`): pytest plugin for AI-driven Flutter/web app automation. Provides a `flutter_skill` fixture that starts the MCP server and wraps all tools as Python methods with native pytest assertions (`assert_visible`, `assert_text`, `assert_not_visible`, `find_element`). Closes #14.
- **HarmonyOS SDK** (`sdks/harmonyos/`): ArkTS bridge SDK (`FlutterSkillAbility.ets`) for HarmonyOS apps. Implements screenshot, tap, enter_text, press_key, scroll, go_back, get_current_route, inspect, get_logs over WebSocket on port 18118. Closes #13.

### CI / Testing
- **Smoke test job** added to CI: simulates a new user installing from local source via `dart pub global activate`, then verifies `--version`, MCP `initialize`, and `tools/list` work correctly.
- **Post-release smoke test** added to release workflow: installs from pub.dev and npm after each release (with retry for CDN propagation) and verifies the published package serves JSON-RPC correctly.

---

## 0.9.6

**Shadow DOM deep pierce for tap/snapshot, serve port reuse fix**

### Changes
- `tap` text search now uses `_dqAll('*')` instead of a hardcoded tag list, so custom elements like Reddit's `faceplate-button` are found by text match
- Snapshot second pass collects `button/[role=button]/[type=submit]` elements nested inside shadow roots
- `serve` binds with `shared: true` (SO_REUSEADDR) to avoid TIME_WAIT "Address already in use" crashes on restart

---

## 0.9.1

**CLI client commands, GitHub Pages docs, comprehensive platform guide**

### New Features
- **CLI client commands for serve API**: `nav`, `snap`, `screenshot`, `tap`, `type`, `key`, `eval`, `title`, `text`, `hover`, `upload`, `tools`, `call`, `wait`
- **GitHub Pages documentation site**: Static docs site at `docs/site/` with auto-deploy workflow

### Documentation
- Comprehensive IDE/platform integration guide with all supported AI platforms
- CLI client reference (`docs/CLI_CLIENT.md`) with scripting examples and CI/CD patterns
- Updated IDE setup guide with OpenClaw serve mode and Continue.dev sections

### Bug Fixes
- **Chrome WebSocket 403 Forbidden**: Fixed Origin header handling
- **Domain-based tab matching**: Never hijack unrelated tabs
- **PUT for /json/new**: Chrome 145+ requires PUT instead of GET

---

## 0.9.0

**iOS native automation + React Native support + bridge reliability**

### New Features
- **6 native P0 tools**: `native_long_press`, `native_gesture`, `native_press_key`, `native_key_combo`, `native_button`, `native_list_simulators`
- **Video recording**: `native_video_start` / `native_video_stop` — H.264 MP4 via simctl recordVideo
- **Frame capture**: `native_capture_frames` — burst JPEG at configurable FPS
- **Hardware buttons**: `apple_pay` and `side` button support via HID injection
- **fs-ios-bridge**: Native ObjC HID injector (74KB) using SimulatorKit private APIs — ~1ms latency vs ~1s for osascript
- **React Native iOS**: Full bridge + native tool support verified (41/42 pass)

### Bug Fixes
- **Bridge mode null safety**: drag coordinate support, edge_swipe defaults, assert_text nullable key
- **execute_batch**: accepts both `actions` and `commands` param names
- **native_gesture/key_combo**: flexible param types (List and String)
- **get_widget_properties**: improved error message for missing key
- **get_text_value**: nullable key support

### Test Results
| Platform | Pass | Total | Rate |
|----------|------|-------|------|
| Web CDP | 128 | 128 | 100% |
| iOS Native | 28 | 29 | 97% |
| iOS Multi-App | 62 | 62 | 100% |
| iOS Cross-Stack | 28 | 28 | 100% |
| iOS Bridge (Flutter) | 62 | 62 | 100% |
| React Native iOS | 41 | 42 | 98% |

### Stats
- **253** MCP tool definitions / **176** in tool registry
- **10** platforms supported
- **fs-ios-bridge**: tap, long-press, swipe, key, button, gesture, screenshot, key-combo, text, list

## 0.8.9

**Heavy DOM site stability + CI fixes**

### Bug Fixes
- **get_network_requests**: Limited to 100 entries (configurable via `limit` param) — prevents OOM/hang on heavy DOM sites (YouTube, Amazon, Reddit)
- **dart analyze**: Resolved all 8 warnings (unused vars, unnecessary null assertions)
- **dart format**: Formatted all 41 files

### Performance Verified — Heavy DOM Sites
| Site | Tools | Time | Snapshot |
|------|-------|------|----------|
| YouTube | 15/15 ✅ | 6.9s | 43ms |
| Amazon | 15/15 ✅ | 14.2s | 1ms |
| Reddit | 15/15 ✅ | 17.9s | 6ms |
| HN | 15/15 ✅ | 4.8s | 53ms |
| Wikipedia | 15/15 ✅ | 7.8s | 15ms |

## 0.8.8

**CDP reliability + multi-platform fixes**

### Bug Fixes
- **swipe/drag/gesture**: Single 10s overall timeout instead of per-event (prevents cascading CDP failures)
- **connect_cdp**: URL now optional — port-only connections for Electron, Android, external browsers
- **Region screenshots**: JPEG@80 with 10s timeout + fallback to full screenshot
- **switch_tab/close_tab**: Support `index` param (AI agents pass index, not target_id)
- **diff_baseline_create**: Added `max_pages` param (default 10) to prevent unbounded crawling
- **CDP JSON serialization**: All JS returns use `JSON.stringify()` → `jsonDecode()` for reliable object handling

### Refactoring
- Extracted `_jsResolveElement()` and `_parseJsonEval()` helpers — eliminated hardcoded selector patterns
- Net -75 lines in CDP driver

### Test Results
| Platform | Pass | Fail | Skip |
|----------|------|------|------|
| Web CDP | 140 | 2 | 23 |
| Electron | 139 | 0 | 26 |
| Flutter Web | 139 | 0 | 26 |
| Android | 134 | 5 | 26 |

## 0.8.3

**Fix WebSocket stability + ping/pong keepalive**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.8.2

**Zero-config CDP, 143 device presets, smart tool filtering, 5 codegen formats, retry/reconnect**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.8.1

**139 MCP tools, CDP browser testing, 10-platform support, screenshot fixes**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.8.0

**inspect_interactive, semantic refs, press_key, 75-test E2E suite**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.7.8

**Release 0.7.8**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.7.7

**Release 0.7.7**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.7.6

**CI improvements + MCP Registry auto-publish**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.7.5

**Release 0.7.5**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.7.4

**Multi-framework SDK support — 8 platforms, 181/183 E2E tests passing**

### New Features
- **8 platform SDKs**: Flutter (iOS/Web), Electron, Android Native, KMP Desktop, Tauri, .NET, React Native
- **Zero-config onboarding**: `flutter-skill init` auto-detects platform and patches entry points
- **`flutter-skill demo`**: launches a built-in demo Flutter app for instant testing
- **CLI actions**: scroll, screenshot, get_text, find_element, wait_for_element, go_back, swipe
- **Tauri eval-with-result**: solved Tauri v2 fire-and-forget eval via secondary WebSocket result channel
- **iOS SDK**: SwiftUI view modifiers, FlutterSkillRegistry, WebSocket bridge with full protocol support

### E2E Test Results
- Flutter iOS: 21/21 ✅ | Flutter Web: 20/20 ✅ | Electron: 24/24 ✅
- Android Native: 24/24 ✅ | KMP Desktop: 22/22 ✅
- .NET: 23/24 ✅ | Tauri: 23/24 ✅ | React Native: 24/24 ✅

### Infrastructure
- Comprehensive E2E test suite (`bridge_e2e_test.mjs`) covering all 13 bridge protocol actions
- Test apps for each platform in `test/e2e/`
- Release script now syncs versions across all SDK packages

---

## 0.7.3

**Release script fix and cleanup**

### Fixes
- Fixed release script adding duplicate CHANGELOG entries when version entry already exists
- Cleaned up CHANGELOG formatting

---

## 0.7.2

**Fix type cast errors in get_errors and get_network_requests**

### Bug Fixes
- Fixed `get_errors` crashing with `type 'String' is not a subtype of type 'int?'` when passing limit/offset parameters
- Fixed `get_network_requests` with same type cast issue for limit parameter
- Used safe `int.tryParse` pattern instead of direct `as int?` cast for JSON-RPC params

---

## 0.7.1

**Bug fixes, screenshot reliability, and new features**

### Bug Fixes
- **Screenshot after navigation**: Fixed stale screenshot showing old page after `Navigator.push()`. Now captures from the RenderView layer instead of first RepaintBoundary, correctly rendering the current visible page
- **enter_text without key**: Can now enter text into the currently focused TextField without providing a widget key. Tap a field first, then call `enter_text(text: "...")`
- **assert_text on buttons**: `assert_text` now reads child Text widgets from buttons, labels, and other non-TextField elements
- **Session auto-switch**: `connect_app`, `launch_app`, and `scan_and_connect` now always switch the active session to the newly connected app
- **screenshot_region**: Added `save_to_file` support (saves to temp file like regular screenshot)
- **get_errors pagination**: Added `limit` and `offset` parameters to prevent massive responses
- **inspect page filter**: Added `current_page_only` parameter to filter out elements from old Navigator routes

### New Features
- **Network monitoring**: 3 new MCP tools (`enable_network_monitoring`, `get_network_requests`, `clear_network_requests`) for tracking HTTP traffic via VM Service profiling
- **README rewrite**: Clearer positioning as an AI-powered E2E testing tool with better examples and discoverability

### Region Screenshot
- `screenshot_region` now reuses the same RenderView layer capture, fixing the same stale-page issue as regular screenshots

---

## 0.7.0

**Enhanced developer experience: install scripts, CLI tips, and doctor command**

### Features
- **`flutter-skill doctor`**: New command to check installation and environment health (Flutter/Dart SDK, devices, native tools, IDE config, tool priority rules)
- **`--version` / `-v` flag**: Quick version check from CLI (`flutter-skill --version`)
- **Interactive CLI tips**: Running `flutter-skill-mcp` in terminal shows helpful usage guide with examples instead of hanging
- **Auto-config IDE settings**: Install script automatically writes MCP config to Claude Code (`~/.claude/settings.json`) and Cursor (`~/.cursor/mcp.json`)

### Install Script Improvements
- One-click install auto-configures everything (IDE settings, tool priority rules, PATH)
- Safe JSON merging via python3 (preserves existing settings)
- POSIX-compatible output (`printf` instead of `echo -e`)
- Removed `--force` npm warning during updates
- Smart version verification with regex validation
- Added fish shell PATH support
- Windows PowerShell auto-config with `ConvertFrom-Json`/`ConvertTo-Json`

### New Files
- `lib/src/cli/doctor.dart` - Environment health checker
- `uninstall.sh` - Clean uninstall for macOS/Linux
- `uninstall.ps1` - Clean uninstall for Windows

### Release Script
- `scripts/release.sh` now auto-syncs Homebrew formula version

---

## 0.6.2

**Improve pub.dev score**

### Changes
- Add `example/example.dart` for pub.dev package scoring
- Widen `vm_service` dependency to `>=14.0.0 <16.0.0` (supports v15)
- Remove unused persistent character fields (fixes 6 analyzer warnings)
- Fix "multiple pubspec.yaml" issue by adding `demo_app/` to `.pubignore`
- Replace `Color.withValues()` with `withOpacity()` for Flutter 3.24 compatibility

---

## 0.6.1

**Native platform interaction tools and VM Service reconnection fix**

### Features
- **Native Platform Interaction**: 4 new MCP tools (`native_screenshot`, `native_tap`, `native_input_text`, `native_swipe`) for interacting with native OS views that are invisible to Flutter's VM Service (photo pickers, permission dialogs, share sheets)
  - iOS Simulator: Uses macOS Accessibility API — no external dependencies
  - Android Emulator: Uses adb shell commands
  - Smart element targeting with scoring system for accurate tap detection
  - Auto-dismissal of iOS paste confirmation dialog

### Bug Fixes
- **VM Service Reconnection**: Fix `LateInitializationError` crash when VM Service connection breaks. Client now auto-reconnects and retries failed operations transparently

---

## 0.6.0

**Enhanced smart discovery with parallel port checking and priority-based selection**

### 🚀 Features
- **Parallel Port Checking**: 6x faster port scanning by checking all ports simultaneously
  - Sequential (old): 6 ports × 500ms = 3000ms
  - Parallel (new): 500ms (returns as soon as first succeeds)
  - Uses `Future.any()` to race all port checks
- **Priority-Based Smart Selection**: Intelligent app ranking for zero manual selection
  - Ranks by: exact directory match → device match → recency (lowest PID)
  - Auto-selects correct app based on current working directory
  - Handles multiple apps in same location with device filtering
- **Process-Based Discovery**: Extract VM Service URI directly from running processes
  - No port scanning needed for most cases
  - Uses `ps aux` and `lsof` for instant discovery

### ⚡ Performance Improvements
- Port scanning: 3000ms → 500ms (6x faster)
- Process discovery: 200ms → 100ms (2x faster)
- Multi-app selection: Manual → Auto (instant)

### 🌍 Internationalization
- Translated all Chinese comments to English
- Updated documentation to follow project standards
- All user-facing strings now in English

### 📚 Documentation
- Added `docs/SMART_DISCOVERY.md` - Complete smart discovery documentation
- Added `docs/SMART_SELECTION.md` - Smart app selection guide
- Added `docs/MULTI_APP_SELECTION.md` - Multi-app handling documentation

### 🧹 Cleanup
- No cache files created (clean filesystem)
- Removed experimental caching system
- Deprecated sequential port checking method

---

## 0.5.5

**Fix Twitter OAuth authentication**

### 🐛 Bug Fixes
- 🔧 **Fixed Twitter OAuth Authentication**: Switch from Bearer Token to OAuth 1.0a
  - Twitter API v2 create tweets endpoint requires User Context authentication
  - Bearer Token (App-Only) is not supported for posting tweets
  - Now uses OAuth 1.0a with API Key, API Secret, Access Token, and Access Token Secret
  - Uses `nearform-actions/github-action-notify-twitter` action for OAuth signing

### 💡 What Changed
- ✅ Twitter posting now works correctly with User Context authentication
- ✅ Automatic release announcements will be posted to Twitter/X
- ✅ No more "Unsupported Authentication" errors

## 0.5.4

**Add automated Twitter/X posting for release announcements**

### 🤖 CI/CD Improvements
- 🐦 **Automated Twitter/X Posting**: Release workflow now auto-posts release announcements to Twitter/X
  - Posts tweet with version, installation commands, and release link
  - Uses Twitter API v2 with Bearer Token authentication
  - Includes relevant hashtags (#Flutter #AI #MCP #DartLang)
  - Auto-triggered on every release
  - Non-blocking (won't fail release if Twitter posting fails)

### 📚 Documentation
- 📖 Added `docs/TWITTER_SETUP.md` with complete Twitter API configuration guide
  - Step-by-step Bearer Token setup instructions
  - Troubleshooting guide for common errors
  - Security best practices
  - Tweet content customization instructions

### 💡 Benefits
- ✅ Automatic social media presence for releases
- ✅ Instant community notification
- ✅ Consistent release announcements
- ✅ Zero manual effort required

## 0.5.3

**Add automated Winget PR submission to release workflow**

### 🤖 CI/CD Improvements
- 🚀 **Automated Winget Submission**: Release workflow now auto-submits PRs to microsoft/winget-pkgs
  - Uses `winget-releaser` GitHub Action for automatic PR creation
  - Every release will be submitted to Microsoft's official Winget repository
  - Eliminates manual PR submission for Windows package manager

### 💡 Benefits
- ✅ Windows users can install via `winget install AIDashboard.FlutterSkill`
- ✅ Automatic version updates in Microsoft's official package repository
- ✅ No more manual PR submissions to winget-pkgs

## 0.5.2

**Critical bug fixes for coordinate detection and JSON serialization**

### 🐛 Bug Fixes (Critical)
- 🔧 **Fixed JSON Serialization Error in find_by_type**: Added `safeRound()` helper to handle NaN/Infinity values
  - Previously crashed with "Unsupported object: NaN" or "Unsupported object: Infinity"
  - Now safely converts all coordinate values to finite integers
  - Consistent with `inspect()` implementation

- 📍 **Improved TextField Coordinate Detection**: Added reliability detection for widget coordinates
  - New `coordinatesReliable` flag on all elements
  - Detects when TextFields report false (0,0) coordinates
  - Provides warning message: "Coordinates may be unreliable - use key or text for targeting"
  - Helps AI agents know when to fall back to key/text-based targeting

### 🔧 Improvements
- 📋 **Enhanced MCP Tool Descriptions**: Updated `inspect` and `find_by_type` documentation
  - Documents `coordinatesReliable` flag in output format
  - Warns about TextField coordinate issues
  - Guides AI agents to use keys when coordinates are unreliable

### 💡 Benefits
- ✅ find_by_type no longer crashes on off-screen or animated widgets
- ✅ AI agents can detect unreliable coordinates and adjust targeting strategy
- ✅ Better error messages guide users to use keys instead of coordinates
- ✅ More robust JSON serialization prevents crashes

### 📝 Migration Guide
No breaking changes. New `coordinatesReliable` field is optional to check:

```dart
// Check coordinate reliability before using coordinates
final elements = await inspect();
for (final element in elements) {
  if (element['coordinatesReliable'] == true) {
    // Safe to use bounds/center coordinates
    tap(x: element['center']['x'], y: element['center']['y']);
  } else {
    // Fall back to key/text targeting
    if (element['key'] != null) {
      tap(key: element['key']);
    }
  }
}
```

---

## 0.5.1

**Major usability improvements for screenshots, errors, and logging**

### 🎯 P0 Fixes (Critical)
- 📸 **Screenshot Optimization**: Now saves to file by default instead of returning base64
  - Returns file path, filename, size, format
  - Dramatically reduces response size
  - `save_to_file` parameter (default: true)
  - Backward compatible: set `save_to_file=false` for base64
  - Files saved to temp directory with timestamp

- 🔌 **Improved Connection Error Messages**: Detailed, actionable error messages
  - Clear status indicators with emojis (📍, 🔧, 💡, ⚠️)
  - 3 connection options with code examples
  - Troubleshooting checklist included
  - Shows VM Service URI in errors for context
  - Better guidance for first-time users

### 🔧 P1 Improvements
- 📊 **Structured Log/Error Responses**:
  - `get_logs()`: Returns logs with summary (total_count, message)
  - `get_errors()`: Returns errors with summary (has_errors, total_count, message)
  - `clear_logs()`: Returns structured success response
  - Easier to parse and display in UI

### 💡 Benefits
- ✅ Smaller response sizes (file paths vs base64 data)
- ✅ Better developer experience with clear error messages
- ✅ Faster problem resolution
- ✅ More structured, parseable responses
- ✅ Files can be opened directly in viewers/editors

### 📝 Migration Guide
**Screenshot:**
```dart
// New behavior (default)
screenshot()  // Returns: {"file_path": "/tmp/...", "size_bytes": 45678}

// Legacy behavior
screenshot(save_to_file: false)  // Returns: {"image": "base64..."}
```

**Logs/Errors:**
```dart
// New response format
get_errors()
// Returns: {
//   "errors": [...],
//   "summary": {
//     "total_count": 3,
//     "has_errors": true,
//     "message": "3 error(s) found ⚠️"
//   }
// }
```

---

## 0.5.0

**Add visual test indicators for UI automation**

### ✨ New Features
- 🎨 **Visual Test Indicators**: Real-time visual feedback for all test actions
  - Tap indicator: Expanding circle with fade-out animation
  - Swipe indicator: Arrow with dashed trail showing direction
  - Long press indicator: Filling progress circle
  - Text input indicator: Glowing border with blink effect
- 📢 **Action Hints**: Top banner displaying current operation ("Tapping 'Submit'", etc.)
- 🎛️ **Configurable Styles**: Three modes to choose from
  - `minimal`: Small, fast (200ms), no hints
  - `standard`: Medium, normal speed (500ms), 1s hints (default)
  - `detailed`: Large, slow (800ms), 2s hints + debug info
- 🔧 **Easy Control**: Enable/disable indicators on the fly
  - MCP tool: `enable_test_indicators(enabled: true, style: "standard")`
  - MCP tool: `get_indicator_status()`
  - VM Service extensions: `enableIndicators`, `disableIndicators`, `getIndicatorStatus`

### 🏗️ Architecture
- `TestIndicatorOverlay`: Manages overlay entry and indicator lifecycle
- `TestIndicatorWidget`: Renders all visual effects with smooth animations
- Indicator components: `TapIndicator`, `SwipeIndicator`, `LongPressIndicator`, `TextInputIndicator`, `ActionHint`
- Uses Flutter Overlay for cross-platform compatibility
- IgnorePointer prevents interaction interference
- Automatic cleanup after animations complete

### 📖 Benefits
- 🎥 **Better Test Videos**: All indicators visible in screen recordings
- 🐛 **Easier Debugging**: See exactly what's being clicked/swiped
- 📱 **Works Everywhere**: iOS, Android, Web, Desktop
- ⚡ **Zero Impact**: No performance cost when disabled
- 🔄 **Auto-Integration**: Automatically shows for all test actions

### 📝 Usage Example
```dart
// Enable indicators
await enable_test_indicators(enabled: true, style: "standard");

// All actions now show visual feedback automatically
await tap(text: "Submit");           // Shows tap ripple + "Tapping 'Submit'"
await swipe(direction: "left");       // Shows swipe arrow + "Swiping left"
await long_press(text: "Menu");       // Shows progress circle + "Long pressing 'Menu'"
await enter_text(key: "email", text: "test@example.com");  // Shows glow + "Entering text"

// Disable when done
await enable_test_indicators(enabled: false);
```

### 📚 Documentation
- Design document: `docs/TEST_INDICATORS_DESIGN.md`
- Includes architecture, configuration options, and future enhancements

---

## 0.4.9

**Fix screenshot_element null handling and add text parameter**

### Bug Fixes
- 🐛 Fixed "type 'Null' is not a subtype of type 'String'" error in `screenshot_element`
- ✅ Added `text` parameter support (in addition to `key`) for finding elements by text content
- 🔍 Automatically looks up element key when `text` parameter is provided
- 🛡️ Added null check for `takeElementScreenshot` return value
- 📝 Returns descriptive error messages when element not found or screenshot fails

### Improvements
- 🎯 `screenshot_element` now matches behavior of other action tools (`tap`, `long_press`, etc.)
- 🔄 Supports both `screenshot_element(key: "button_1")` and `screenshot_element(text: "Submit")`

### Technical Details
- Queries `getInteractiveElements()` to find matching text when key not provided
- Returns `{"error": "...", "message": "..."}` instead of crashing on null

---

## 0.4.8

**Fix Infinity/NaN crash when inspecting widgets**

### Bug Fixes
- 🐛 Fixed "Unsupported operation: Infinity or NaN toInt" crash in `_findInteractiveElements`
- ✅ Added `safeRound()` helper function to handle invalid numeric values
- 🛡️ Widget bounds calculation now safely handles `Infinity` and `NaN` values (returns 0)
- 🔧 Prevents MCP error -32603 when inspecting widgets with problematic layouts
- 📦 Supports edge cases: `Positioned.fill`, `FractionalTranslation`, and malformed widget trees

### Technical Details
- Checks `value.isFinite` before calling `.round()` on position/size values
- Gracefully degrades to `{x: 0, y: 0, width: 0, height: 0}` for invalid bounds

---

## 0.4.7

**Auto-update flutter_skill dependency in target projects**

### Improvements
- 🔄 `setup` now automatically updates existing `flutter_skill` dependency to latest version from pub.dev
- ✅ Enhanced `flutter pub upgrade flutter_skill` checks when dependency already exists
- 📊 Clear status feedback: "✅ updated", "✅ up to date", or "⚠️ failed"
- 🔧 Ensures target projects always use the latest compatible version
- ♻️ Maintains backward compatibility with first-time installations

### Behavior Changes
- Previously: Skipped setup if dependency already existed (even if outdated)
- Now: Actively upgrades to latest version when dependency is found

---

## 0.4.6

**Fix release script to auto-update server.dart version**

### Bug Fixes
- 🔧 Fixed release script to automatically update `_currentVersion` in `lib/src/cli/server.dart`
- 🔄 Ensures version consistency across all release artifacts (pubspec, npm, VSCode, JetBrains, server.dart)
- ✅ Prevents version mismatch errors in MCP server startup

---

## 0.4.5

**Add MCP auto-fix and diagnostics**

### Features
- ✨ New `diagnose_project` MCP tool for comprehensive project diagnostics
- 🔧 Auto-fix capability in `connect_app` and `scan_and_connect` tools
- 📁 Optional `project_path` parameter for automatic configuration
- 🛠️ Diagnostic shell script (`scripts/diagnose.sh`) for manual troubleshooting

### Improvements
- 📊 Enhanced error logging with complete diagnostic output
- 🔍 Automatic detection and repair of missing `flutter_skill` dependency
- ⚙️ Automatic detection and repair of missing `FlutterSkillBinding` initialization
- ✅ Backward compatible (all tools work without `project_path` parameter)

### Documentation
- 📖 New AUTO_FIX_IMPROVEMENTS.md guide
- ✅ New test_auto_fix.md testing checklist
- 🔧 Updated TROUBLESHOOTING.md with auto-fix workflows
- 🌍 README.md translated to English

---

## 0.4.4

**Fix dart analyze errors**

### Bug Fixes
- Fix `WebSocket.connect` timeout parameter issue (use `.timeout()` method instead of named parameter)
- Add missing `dart:convert` import for `utf8` usage in protocol detector
- Fix test file: `getWidgetTree` returns `Map` not `String`, use correct `takeScreenshot` method name
- Add `.mcp.json` to gitignore

---

## 0.4.3

**Multi-session support for parallel Flutter app testing**

### 🎯 Major Features

**Multi-Session Management**
- ✨ Support for parallel testing of multiple Flutter apps simultaneously
- 🏗️ Complete SessionManager architecture for Kotlin (IntelliJ plugin)
- 📊 SessionInfo model with state tracking (CREATED → LAUNCHING → CONNECTED → DISCONNECTED → ERROR)
- 🔢 Automatic port assignment (50001-60000 range) with conflict detection
- 🔄 Session switching and lifecycle management
- 📝 Session persistence and tracking

**UI Components**
- 🎨 New SessionTabBar component with tab-based session switching
- ➕ New Session Dialog with device auto-detection
- 📱 Device detection for iOS/Android/Web/Desktop platforms
- 🎯 Real-time status indicators (● connected, ○ disconnected, ⏳ launching, ⚠️ error)
- 🖱️ Click to switch sessions, close button on tabs
- ✨ Hover effects and visual feedback

**MCP Server Enhancements**
- 🔧 All MCP tools now support `session_id` parameter
- 📋 New tools: `list_sessions`, `switch_session`, `close_session`
- 🔄 Multi-client management with session isolation
- ⬆️ Backward compatible (defaults to active session)

### 📁 Code Changes

- **New Files**: 11 files created (~5800 lines total)
  - SessionManager.kt (200+ lines)
  - SessionTabBar.kt (284 lines)
  - NewSessionDialog.kt (450+ lines)
  - SessionManagerTest.kt (450+ lines)
  - multi_session_test.dart (441 lines)
  - Complete documentation suite

- **Modified Files**: 5 files updated
  - lib/src/cli/server.dart (+478, -134 lines)
  - All UI cards updated for session support

### 🧪 Testing

- ✅ Dart tests: 20/20 passed (100% pass rate)
- ✅ Kotlin compilation: BUILD SUCCESSFUL
- ✅ Plugin build: BUILD SUCCESSFUL
- ✅ Session isolation tests
- ✅ Port allocation tests
- ✅ State transition tests

### 📚 Documentation

- 📖 Multi-session testing guide
- 🎨 Complete UI design documentation
- 🧪 Comprehensive testing documentation
- 📊 Implementation report with all task details
- 🗂️ Organized documentation structure (docs/ui/, docs/testing/, docs/releases/)

### 🔧 Improvements

- 🏗️ Organized project structure (moved docs and scripts to subdirectories)
- 📝 Better separation of concerns
- 🧹 Cleaner root directory with only core files

---

## 0.4.1

**Cross-Platform UI/UX Overhaul & VM Service Integration**

### 🎨 Major UI/UX Improvements

**VSCode Extension**
- ✨ Complete sidebar redesign with professional card-based layout
- 📊 5 functional sections: Connection Status, Quick Actions, Interactive Elements, Recent Activity, AI Editors
- 🔗 Real-time connection status with live device information
- 🎯 Interactive elements list with tap, input, and inspect capabilities
- 📜 Activity history tracking with timestamps
- 🔍 Element search and filtering
- 🎨 Perfect theme adaptation (light/dark modes)

**IntelliJ IDEA Plugin**
- ✨ Tool Window complete refactor with card-based UI components
- 🌳 Interactive Elements tree view with hierarchical display
- ⚡ 2x2 Quick Actions grid for common operations
- 📊 Recent Activity list with visual indicators (shows 5 items consistently)
- 🎨 Seamless theme integration (Light/Darcula/High Contrast)
- 🔍 Element search and filtering capabilities

**Cross-Platform Consistency**
- 🤝 Unified design language across VSCode and IntelliJ
- 🎯 Semantic color system (success=green, warning=yellow, error=red)
- 📐 Consistent spacing using design tokens (16px between cards)
- ⚡ Identical interaction flows and error messaging
- 📊 Overall consistency score: 95/100

### 🔌 Complete VM Service Integration

**Core Features**
- 🔗 Full WebSocket-based VM Service Protocol client implementation
- 📱 Real-time UI element inspection from running Flutter apps
- 👆 Tap operations via VM Service extensions
- ⌨️ Text input into TextField widgets
- 📸 Screenshot capture (base64-encoded PNG, with quality control)
- 🔄 Hot reload triggering (`reloadSources`)
- 🌳 Widget tree inspection
- 📊 Activity tracking with success/failure indicators

**VSCode Implementation**
- Added `VmServiceClient.ts` - Complete WebSocket client (400+ lines)
- Added `FlutterSkillViewProvider.ts` - WebviewViewProvider with real VM operations
- Added `ActivityTracker.ts` - Activity history management
- Enhanced `vmServiceScanner.ts` with VM client integration
- Dynamic element list updates from real Flutter apps

**IntelliJ Implementation**
- Added `VmServiceClient.kt` - Production-ready client (835 lines)
  - JSON-RPC 2.0 protocol
  - Kotlin coroutines integration
  - CompletableFuture.await() extension
  - 17+ public API methods
- Enhanced `VmServiceScanner.kt` with VM integration methods
- Updated `InteractiveElementsCard.kt` with real tap/input operations
- Updated `QuickActionsCard.kt` with hot reload functionality
- Updated `FlutterSkillService.kt` to use VM Service directly
- Service callbacks wired to update UI cards

### 🛠️ Technical Improvements

**Version Management**
- VSCode: Dynamic version reading from package.json
- IntelliJ: Dynamic version reading from plugin.xml
- Eliminated all hardcoded version strings

**Architecture**
- Card-based component system (IntelliJ)
- WebviewViewProvider pattern (VSCode)
- State management with callbacks
- Proper async/await patterns with coroutines
- Comprehensive error handling and user feedback

### 📚 Documentation

- Added `docs/CROSS_PLATFORM_VERIFICATION.md` - Detailed verification report
- Added `docs/UI_UX_DESIGN_GUIDE.md` - Design system specification
- Added `docs/UI_IMPLEMENTATION_ROADMAP.md` - Implementation plan

### 🐛 Bug Fixes

- Fixed type inference issues in Kotlin coroutines
- Fixed ErrorInfo reference scoping (VmServiceResponse.ErrorInfo)
- Fixed WebSocket import in TypeScript (require syntax)
- Fixed activity display consistency (both platforms show 5 items)

### 📊 What This Solves

**Before:**
- ❌ Basic UI with minimal information
- ❌ No real-time connection status
- ❌ Hardcoded example data in UI
- ❌ CLI commands instead of VM Service integration
- ❌ No activity tracking

**After:**
- ✅ Professional card-based UI across both platforms
- ✅ Real-time connection status and device info
- ✅ Live data from running Flutter apps
- ✅ Direct VM Service integration
- ✅ Complete activity history tracking
- ✅ Unified cross-platform experience

---

## 0.4.0

**One-Click Installation & Tool Priority System**

### 🚀 Major Features

**1. One-Click Installation**
- Added universal installation scripts for all platforms
- macOS/Linux: `curl -fsSL https://raw.githubusercontent.com/ai-dashboad/flutter-skill/main/install.sh | bash`
- Windows: `iwr https://raw.githubusercontent.com/ai-dashboad/flutter-skill/main/install.ps1 -useb | iex`
- Auto-detects best installation method (npm > Homebrew/Scoop > source)
- Auto-configures PATH and dependencies
- Zero manual configuration needed

**2. Automatic Tool Priority Setup**
- New command: `flutter_skill setup`
- Installs Claude Code priority rules automatically
- Ensures flutter-skill is ALWAYS used instead of Dart MCP
- First-run reminder if not installed
- Supports `--force` and `--silent` flags

**3. Comprehensive Tool Priority System**
- Added decision tree and enforcement rules
- Updated SKILL.md with alternatives comparison
- Created detailed setup guide (TOOL_PRIORITY_SETUP.md)
- Added tool-priority.md prompt rules
- 100% priority for flutter-skill in Flutter testing

### ✨ New Commands

```bash
# One-click setup of tool priority rules
flutter_skill setup

# Force reinstall/update rules
flutter_skill setup --force

# Silent installation (for scripts)
flutter_skill setup --silent
```

### 📚 Documentation

- Added `install.sh` - Universal installer for macOS/Linux
- Added `install.ps1` - Universal installer for Windows
- Added `TOOL_PRIORITY_SETUP.md` - Setup and verification guide
- Added `docs/prompts/tool-priority.md` - Claude Code priority rules
- Updated `README.md` - One-click installation instructions
- Updated `CLAUDE.md` - Tool selection rules

### 🎯 What This Solves

**Before:**
- ❌ Users had to manually install and configure
- ❌ PATH issues on different systems
- ❌ Dependency conflicts
- ❌ Claude Code might use Dart MCP instead of flutter-skill

**After:**
- ✅ One command to install everything
- ✅ Auto-configures all settings
- ✅ Works across all platforms
- ✅ Claude Code always prioritizes flutter-skill

### 📊 Installation Methods (Auto-Detected)

| Method | Priority | Speed | Requirements |
|--------|----------|-------|--------------|
| npm | 1st (best) | Instant | Node.js |
| Homebrew/Scoop | 2nd | Fast | macOS/Windows |
| From source | 3rd (fallback) | Medium | Flutter SDK |

### 🔧 Technical Improvements

- Created `lib/src/cli/setup_priority.dart` - Setup command implementation
- Updated `bin/flutter_skill.dart` - Added setup command routing
- Added auto-detection for installed priority rules
- Improved error messages and user guidance

---

## 0.3.1

**Web Platform Optimization - Screenshot & Tap Enhancements**

### 🎯 Core Improvements

**1. Screenshot Optimization**
- Fixed token overflow issue (247,878 → ~50,000 tokens, ↓80%)
- Default quality: 1.0 → 0.5
- Default max_width: null → 800px
- Screenshot success rate: 50% → 100%

**2. Tap Tool Enhancement**
- Added coordinate support: `tap(x: 30, y: 22)`
- Now supports 3 methods: key, text, or coordinates
- Can now tap icon buttons without text
- Overall tap success rate: 45% → 96%

### ✨ New Features

**Coordinate-based Tap**
```dart
// Method 1: By Widget key
tap(key: "submit_button")

// Method 2: By visible text
tap(text: "Submit")

// Method 3: By coordinates (NEW)
inspect()  // Get center: {"x": 30, "y": 22}
tap(x: 30, y: 22)  // Tap at coordinates
```

**Optimized Screenshot Defaults**
```dart
screenshot()  // Now returns 50KB instead of 248KB

// High quality when needed
screenshot(quality: 1.0, max_width: null)
```

### 📚 Documentation

- Added `WEB_OPTIMIZATION.md` - Complete Web platform guide
- Added `RELEASE_NOTES_v0.3.1.md` - Detailed release notes
- Added `QUICK_REFERENCE_WEB.md` - Quick reference card

### 📊 Performance Impact

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Screenshot size | 248KB | 50KB | ↓80% |
| Token usage | 247,878 | ~50,000 | ↓80% |
| Tap success rate | 45% | 96% | ↑113% |
| Screenshot success | 50% | 100% | ↑100% |

### 🔧 Technical Details

- File: `lib/src/cli/server.dart`
- Modified screenshot defaults (line 1372-1377)
- Enhanced tap tool with coordinate support (line 1289-1327)
- Updated tool descriptions for better AI recognition

### 🎓 Use Cases

**Before (Failed)**:
- ❌ Cannot tap icon buttons without text
- ❌ Screenshot causes token overflow

**After (Works)**:
- ✅ Tap any visible element via coordinates
- ✅ Screenshot with automatic optimization

---

## 0.3.0

**Auto-priority configuration for 95%+ AI recognition rate**

### 🎯 Automatic Flutter-Skill Prioritization

Claude Code now automatically recognizes and prioritizes flutter-skill MCP tools when working in Flutter projects.

### ✨ New Features

**1. 📋 Enhanced SKILL.md**
- Added `priority: high` and `auto_activate: true` configuration
- 50+ bilingual trigger keywords (English + Chinese)
- Structured examples with intent mapping
- Project context auto-detection rules

**2. 📁 Project-Level Prompts**
- `docs/prompts/flutter-testing.md` - Decision trees for tool selection
- Auto-workflow detection for common scenarios
- Context-aware testing patterns

**3. 🛠️ Installation & Verification Tools**
- `scripts/install_prompts.sh` - Easy setup for auto-priority configuration
- `scripts/verify_auto_priority.sh` - Verify configuration correctness
- `AUTO_PRIORITY_SETUP.md` - Comprehensive setup guide

**4. 🌐 Bilingual Support**
- Full Chinese/English trigger word coverage
- Supports natural language queries: "测试应用", "test app", "在iOS上测试"
- Context-aware understanding of ambiguous requests

### 🚀 Impact

- ✅ Auto-detect Flutter projects (pubspec.yaml, lib/main.dart)
- ✅ Prioritize flutter-skill for UI testing over flutter test
- ✅ Understand context from previous messages
- ✅ Proactively suggest appropriate workflows
- ✅ Support casual language: "测试一下", "check it", "try this"

### 📚 Documentation

- Added `AUTO_PRIORITY_SETUP.md` with complete setup instructions
- Moved project prompts to `docs/prompts/` for better visibility
- Cleaned up obsolete documentation files

### 🧹 Cleanup

- Removed: CHANGELOG_FIXES.md, ERROR_REPORTING.md, OPTIMIZATION_SUMMARY.md, RELEASE_GUIDE.md, SKILL_OLD.md
- Consolidated optimization guides into main documentation

---

## 0.2.26

**AI Tool Discovery Enhancement - 95%+ Recognition Rate**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.2.26

**AI Tool Discovery Enhancement - 95%+ Recognition Rate**

### 🎯 Ultimate Optimization for AI Tool Recognition

Implemented high-priority strategies from ADVANCED_OPTIMIZATION.md to achieve 95%+ recognition rate.

### ✨ Improvements

**1. ⚡ Priority Tool Marking**
- All critical tools now have ⚡ PRIORITY TOOL markers
- Clear visual priority indicators in tool descriptions
- Helps AI agents quickly identify the right tool for UI testing tasks

**2. 🌐 Bilingual Trigger Keywords (English + Chinese)**
- Complete trigger keyword library for each tool
- English keywords: test, verify, tap, click, enter, screenshot, simulator, etc.
- Chinese keywords: 测试, 验证, 点击, 输入, 截图, 模拟器, etc.
- Supports natural language queries in both languages

**3. ✅ Clear Usage Guidelines**
- [USE WHEN] sections explicitly define when to use each tool
- [DO NOT USE] sections prevent misuse (e.g., unit tests vs UI tests)
- [WORKFLOW] sections guide AI agents through proper tool sequences

**4. 📋 Enhanced Tool Descriptions**

Optimized tools:
- `launch_app`: UI testing priority tool with 24+ trigger keywords
- `inspect`: UI discovery tool for finding elements
- `tap`: UI interaction tool for button clicks
- `enter_text`: Text input tool for forms
- `screenshot`: Visual capture tool for debugging
- `scan_and_connect`: Auto-connect tool for running apps

### 📊 Expected Impact

| Metric | Before (v0.2.25) | After (v0.2.26) | Improvement |
|--------|------------------|-----------------|-------------|
| "test app" recognition | ~90% | ~97% | +7% |
| Chinese queries | ~80% | ~95% | +15% |
| Negative case avoidance | ~85% | ~95% | +10% |
| Overall recognition | ~88% | ~95%+ | +7%+ |

### 🔧 Technical Details

- Structured metadata in tool descriptions
- Multi-language support (EN/CN)
- Disambiguation patterns
- Context-aware suggestions
- Workflow auto-detection hints

---

## 0.2.25

**AI Agent Tool Discovery Enhancement**

### 🎯 Problem Solved
Claude Code (and other AI agents) couldn't auto-invoke flutter-skill when users said "test app" or "iOS simulator test".

### ✨ Improvements
- **Enhanced MCP tool descriptions** with rich trigger keywords
  - `launch_app`: Added "test", "simulator", "emulator", "E2E", "verify" keywords
  - `inspect`: Added "what's on screen", "list buttons" triggers
  - `tap`: Added "click button", "press", "select" triggers
  - `enter_text`: Clarified use for "forms", "login screens"
  - `screenshot`: Added "show me", "visual debugging" triggers

- **Comprehensive SKILL.md** for AI agents
  - Clear `when_to_use` / `when_not_to_use` guidelines
  - Trigger keywords list for auto-invocation
  - AI Agent workflow patterns and examples
  - Distinction vs. `flutter test` (unit testing)

### 📊 Impact
- 10% → 90% success rate for "test Flutter app" queries
- 5% → 85% success rate for "iOS simulator" queries
- Better tool discovery and automatic invocation
- Clear AI agent usage patterns

### 📝 Documentation
- `SKILL.md`: Complete rewrite with AI-first approach
- `OPTIMIZATION_SUMMARY.md`: Detailed analysis and guide
- `publish.sh`: Publishing helper script

---

## 0.2.24

**Critical Bug Fixes and Zero-Config Error Reporting**

### 🐛 Bug Fixes
- Fixed `LateInitializationError` causing MCP server crashes
- Added process lock mechanism to prevent multiple instances (`~/.flutter_skill.lock`)
- Improved connection state validation and error messages
- Fixed `getMemoryStats()` exception handling
- Auto-cleanup of stale processes (10-minute timeout)

### ✨ New Features
- **Zero-config automatic error reporting** - no GitHub token required!
- Browser auto-opens with pre-filled issue template
- New CLI command: `flutter_skill report-error`
- Smart error filtering (only reports critical errors)
- Cross-platform support (macOS/Linux/Windows)

### 📝 Documentation
- Added `ERROR_REPORTING.md` - complete error reporting guide
- Added `CHANGELOG_FIXES.md` - detailed technical changelog
- Added comprehensive test coverage (6/6 tests passing)

### 🔧 Technical Details
- Implemented file-based locking mechanism
- Enhanced `_requireConnection()` with better diagnostics
- Automatic browser opening for issue creation
- Privacy-focused design (no sensitive data collected)

---

## 0.2.23

**Fix IntelliJ plugin publishing - upgrade Kotlin Gradle Plugin to 2.0.21**

### Bug Fixes
- Fixed JetBrains Marketplace publishing failure caused by Kotlin Gradle Plugin compatibility issue
- Upgraded Kotlin Gradle Plugin from 1.9.21 to 2.0.21 for compatibility with IntelliJ Platform Gradle Plugin 2.2.1
- IntelliJ plugin now successfully publishes to JetBrains Marketplace

---

## 0.2.21

**IntelliJ Plugin Enhancement**

### New Features

- **Auto-open Tool Window** - Flutter Skill panel opens automatically for Flutter projects
- **AI CLI Tool Detection** - Automatically detects installed AI tools:
  - Claude Code, Cursor, Windsurf, Continue, Aider
  - GitHub Copilot, OpenAI CLI, Gemini CLI, Ollama, LM Studio

### Enhanced UI

- Connection status section with visual indicator
- Detected AI tools list with version info
- "Configure" button for one-click MCP setup
- "Copy Config" button for easy configuration sharing

---

## 0.2.20

**Multi-Platform Distribution**

### New Installation Methods

| Method | Platform | Command |
|--------|----------|---------|
| Docker | All | `docker pull ghcr.io/ai-dashboad/flutter-skill` |
| Snap | Linux | `snap install flutter-skill` |
| Scoop | Windows | `scoop install flutter-skill` |
| Winget | Windows | `winget install AIDashboard.FlutterSkill` |
| Devcontainer | All | Feature: `ghcr.io/ai-dashboad/flutter-skill/flutter-skill` |

### Documentation

- Added Continue.dev integration guide (`docs/continue-dev.md`)

### CI/CD

- Added Docker workflow for GHCR publishing
- Added Snap workflow for Snap Store publishing
- Added Winget manifest generation on release
- Added Scoop manifest generation on release
- Added Devcontainer feature publishing workflow

---

## 0.2.19

**Smart Diagnosis Tool**

### New MCP Tools

- `diagnose` - Intelligent log and UI analysis with fix suggestions
  - Analyzes logs for common error patterns (network, layout, null errors)
  - Detects UI issues (empty state, high memory usage)
  - Returns structured diagnosis with issues, suggestions, and next steps
  - Calculates health score (0-100)

### Supported Issue Detection

| Type | Severity | Detection |
|------|----------|-----------|
| Network connection error | critical | Log pattern matching |
| Timeout exception | critical | Log pattern matching |
| Layout overflow | warning | Log pattern matching |
| Null check error | critical | Log pattern matching |
| State error (disposed widget) | warning | Log pattern matching |
| High memory usage | warning | Memory threshold check |
| Empty UI state | warning | UI element inspection |

### Example Usage

```json
// Call diagnose tool
{ "tool": "diagnose", "arguments": { "scope": "all" } }

// Returns
{
  "summary": { "total_issues": 2, "critical": 1, "warning": 1, "health_score": 60 },
  "issues": [ { "id": "E001", "type": "network_connection_error", "severity": "critical" } ],
  "suggestions": [ { "for_issue": "E001", "action": "Check network configuration", "steps": [...] } ],
  "next_steps": [ { "tool": "tap", "params": { "text": "Retry" } } ]
}
```

---

## 0.2.18

**Connection Reliability & Error Handling Improvements**

### Bug Fixes
- `connect_app` now retries 3 times with exponential backoff
- Auto-normalize VM Service URI format (http→ws, add /ws suffix)
- `launch_app` timeout increased from 120s to 180s for slow builds

### Improved Error Messages
- Structured error responses with error codes (E201, E301)
- Actionable suggestions on connection/launch failures
- Clear next steps for troubleshooting

### Example Error Response
```json
{
  "success": false,
  "error": {"code": "E201", "message": "Failed to connect after 3 attempts"},
  "suggestions": ["Try scan_and_connect()", "Verify app is running"]
}
```

---

## 0.2.17

**P2 Optimizations - Gesture Presets & Wait for Idle**

### New MCP Tools

- `gesture` - Perform gestures with presets or custom coordinates
  - Presets: `drawer_open`, `drawer_close`, `pull_refresh`, `page_back`, `swipe_left`, `swipe_right`
  - Custom: Specify `from_x/from_y/to_x/to_y` as screen ratios (0.0-1.0)

- `wait_for_idle` - Wait for app to stabilize (no animations/UI changes)
  - Parameters: `timeout` (default 5000ms), `min_idle_time` (default 500ms)
  - Returns idle status and timing info

### Gesture Presets

| Preset | Description |
|--------|-------------|
| drawer_open | Swipe from left edge to open drawer |
| drawer_close | Swipe to close drawer |
| pull_refresh | Pull down to refresh |
| page_back | iOS-style back gesture |
| swipe_left/right | Horizontal swipes |

---

## 0.2.16

**P0/P1 Expert-level Optimizations**

### Changes
- Fixed 403 Forbidden error when connecting to Chrome 146 consent port (port opened via chrome://inspect/#remote-debugging)
- Chrome 146 rejects WebSocket connections that include an Origin header; Dart built-in WebSocket.connect() always adds one
- Added _connectWebSocketNoOrigin(): raw TCP socket WebSocket upgrade that omits the Origin header
- All CDP WebSocket connections now use no-Origin mode when consent port is detected
- Users can now connect to their real Chrome browser without any session-copy workaround

---

## 0.2.16

**P0/P1 Expert-level Optimizations**

### P0 - Fuzzy Match Suggestions
- `tap()` and `enter_text()` return similar keys/texts when element not found
- Helps developers quickly identify correct key names

### P1 - Enhanced inspect()
- Added `id` field for element identification
- Added `ancestors` array (last 3 meaningful parent widgets)
- Added `widgetType` for actual Flutter widget class
- Added `tooltip` and `icon` extraction
- Added `visible` status
- Changed position/size to `bounds` object format

### P1 - Error Code System
- Added ErrorCode class (E001-E302)
- Structured error responses with code, message, suggestions
- Codes: elementNotFound, elementNotVisible, inputFailed, etc.

---

## 0.2.15

**Critical Bug Fixes & AI Agent Improvements**

### Bug Fixes
- **Fixed tap/enter_text/scroll_to returning misleading success** - Now returns `{success: false, error: "Element not found"}` when element not found
- Previously these tools returned success even when the target element didn't exist

### New MCP Tools
- `edge_swipe` - Swipe from screen edge for drawer menus and iOS back gestures
  - Parameters: `edge` (left/right/top/bottom), `direction` (up/down/left/right), `distance`
- `screenshot_region` - Capture a cropped region of the screen

### Enhanced Tools
- `inspect` now returns element coordinates:
  - `position: {x, y}` - top-left corner
  - `size: {width, height}` - element dimensions
  - `center: {x, y}` - center point for coordinate-based tapping
  - `semanticsLabel` - accessibility label when available
- `screenshot` now accepts:
  - `quality` (0.1-1.0) - reduce image size via pixel ratio
  - `max_width` - scale down large screenshots

### Improvements
- Better error messages with element key/text in failure responses
- Tappable elements (InkWell, GestureDetector) now include extracted text

---

## 0.2.14

**Testing Efficiency & Batch Operations**

### New MCP Tools
- `execute_batch` - Execute multiple actions in sequence (reduces round-trip latency)
- `tap_at` / `long_press_at` - Coordinate-based interactions
- `swipe_coordinates` - Swipe from one coordinate to another
- `scroll_until_visible` - Scroll until target element becomes visible
- `assert_visible` / `assert_not_visible` - Assert element visibility
- `assert_text` - Assert element text content (equals or contains)
- `assert_element_count` - Assert count of elements matching criteria
- `get_page_state` - Get complete page state snapshot
- `get_interactable_elements` - Get all interactable elements with suggested actions
- `get_frame_stats` - Frame rendering statistics
- `get_memory_stats` - Memory usage statistics

### Efficiency Improvements
- Batch operations reduce test execution time by 60%+
- Smart scroll eliminates manual scroll + check loops
- Built-in assertions simplify test validation

---

## 0.2.13

**Feature Parity & Developer Experience**

### New MCP Tools
- `scan_and_connect` - Auto-scan VM Service ports and connect to first found Flutter app
- `list_running_apps` - List all running Flutter apps with their VM Service URIs
- `stop_app` - Stop the currently running Flutter app
- `disconnect` - Disconnect from app without stopping it
- `get_connection_status` - Get connection info with actionable suggestions
- `hot_restart` - Full app restart (resets state)

### Enhanced Tools
- `launch_app` now supports:
  - `dart_defines` - Pass compile-time variables (e.g., `["ENV=staging", "DEBUG=true"]`)
  - `flavor` - Build flavor selection
  - `target` - Custom entry point file
  - `extra_args` - Additional flutter run arguments

### Improved Error Messages
- Connection errors now include specific solutions
- `get_connection_status` shows available apps and suggestions

---

## 0.2.12

**Auto-Update Checking**

### New Features
- Auto-update checking for all installation methods
- npm: Checks registry every 24 hours, shows notification
- VSCode: Extension auto-updates via marketplace
- IntelliJ: Plugin auto-updates via JetBrains marketplace
- Homebrew: `brew upgrade flutter-skill`

---

## 0.2.11

**Homebrew Distribution**

### New Features
- Homebrew formula with pre-compiled native binary
- `brew tap ai-dashboad/flutter-skill && brew install flutter-skill`
- Auto-upgrades via `brew upgrade`

---

## 0.2.10

**IntelliJ Native Binary Support**

### New Features
- Native binary auto-download for IntelliJ/Android Studio plugin
- Background download with progress indicator
- Cached to `~/.flutter-skill/bin/`

---

## 0.2.9

**npm Native Binary Auto-Download**

### New Features
- npm postinstall script auto-downloads native binary
- Platform detection: macOS (arm64/x64), Linux (x64), Windows (x64)
- Fallback to Dart runtime if download fails

---

## 0.2.8

**Native Binary Compilation**

### Performance
- Native binary compilation for ~100x faster MCP startup
- Startup time: ~0.01s (native) vs ~1s (Dart JIT)
- GitHub Actions builds for all platforms

---

## 0.2.7

**VSCode Native Binary Support**

### New Features
- VSCode extension auto-downloads native binary
- Background download on extension activation
- Automatic fallback to Dart runtime

---

## 0.2.6

**Claude Code Config Fix**

### Bug Fixes
- Fixed Claude Code MCP config detection
- Correct path: `~/.claude/settings.json` (was incorrectly using `~/.claude.json`)
- Config now properly merges into existing settings

---

## 0.2.0

**Major Feature Release - 25+ MCP Tools**

### New Features
- **UI Inspection**: `get_widget_tree`, `get_widget_properties`, `get_text_content`, `find_by_type`
- **Interactions**: `double_tap`, `long_press`, `swipe`, `drag`
- **State Validation**: `get_text_value`, `get_checkbox_state`, `get_slider_value`, `wait_for_element`, `wait_for_gone`
- **Screenshots**: `screenshot` (full app), `screenshot_element` (specific element)
- **Navigation**: `get_current_route`, `go_back`, `get_navigation_stack`
- **Debug & Logs**: `get_logs`, `get_errors`, `get_performance`, `clear_logs`
- **Development**: `hot_reload`, `pub_search`

### Bug Fixes
- Fixed global swipe using `platformDispatcher.views` for screen center calculation
- Fixed `screenshot_element` to capture any widget by finding nearest `RenderRepaintBoundary` ancestor

### Documentation
- Complete rewrite of README.md with all tool categories
- Updated SKILL.md with full tool reference and parameters
- Updated USAGE_GUIDE.md with CLI and MCP examples

## 0.1.6

- Docs: Updated README to reflect unified `flutter_skill` global commands.

## 0.1.5

- Fix: Added missing implementation for `scroll` extension found during comprehensive verification.
- Verified: All CLI features (inspect, tap, enterText, scroll) verified against real macOS app.

## 0.1.4

- Housekeeping: Removed `demo_counter` test app from package distribution.

## 0.1.3

- Fix: Critical fix for `launch` command to correctly capture VM Service URI with auth tokens.
- Fix: Critical fix for `inspect` command to correctly traverse widget tree (was stubbed in 0.1.2).
- Feature: `launch` command now forwards arguments to `flutter run` (e.g. `-d macos`).

## 0.1.2

- Docs: Updated README architecture diagram to reflect `flutter_skill` executable.
- No functional changes.

## 0.1.1

- Featured: Simplified CLI with `flutter_skill` global executable.
- Refactor: Moved CLI logic to `lib/src/cli` for better reusability.
- Usage: `flutter_skill launch`, `flutter_skill inspect`, etc.

## 0.1.0

- Initial release of Flutter Skill.
- Includes `launch`, `inspect`, `act` CLI tools.
- Includes `flutter_skill` app-side binding.
- Includes MCP server implementation.

## 0.9.26 (2026-03-17)

- Added `--chrome-port=N` as an alias for `--cdp-port=N` for better compatibility
- Fixed: Parsing of `--chrome-port` parameter (previously threw FormatException)
- This allows connecting to Chrome instances running on non-default ports (e.g., 18800)
