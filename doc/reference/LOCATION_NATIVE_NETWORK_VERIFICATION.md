# Location native and two-peer verification

Verified on macOS arm64 on 2026-11-12. The location/nearby/settings suite passed
**91 tests with no skips**. The two-peer scenario passed in independent native
processes (PIDs 14429 and 14430); both Flutter runners exited with code 0.
The PR-wide Flutter suite subsequently passed **3,242 tests**; its one opt-in
network test is skipped in ordinary discovery and is exercised separately by the
successful two-process runner above. Strict analysis covered all 1,038 proposed
Dart files; complexity and source-contract checks passed.

## Coverage

- Previously skipped native location bubble construction, rendering, and map
  launch behavior.
- Actual native UDP connectivity between two independent Tox instances.
- Nearby discovery across two geohash cells with distinct per-group NGC keys.
- Leaving one cell preserves the peer and permits an encrypted greeting through
  the surviving route.
- The recipient receives the greeting and sends a real friend request. The sender
  matches its nonce and explicitly accepts; both friends become connected.
- Both sides call the production `LocationSender`, UIKit message provider and
  tim2tox SDK/native transport. The receiving SDK listener verifies the other
  account's sender key and distinct latitude/longitude in a structured location
  element (`elemType == 7`).
- Private native group creation, invitation, explicit join, and native wire
  readiness through the production SDK. Both sides then send group location
  messages through the default `LocationSender` and production provider. The
  receiving SDK listener checks the immutable native group identity, the other
  sender's per-group NGC key, `isSelf == false`, location type, distinct
  coordinates and coordinate-label description. In this run Alice's local group
  was `tox_2` and Bob's was `tox_1`, resolving to the same native chat identity.
- Disabling nearby visibility stops the local service and removes the remote
  peer from the other side's list.

The test uses loopback UDP on the same machine and fixed synthetic positions in
the Pacific. It does not exercise OS GPS/permission dialogs, physical devices,
cross-NAT connectivity, or other group kinds such as legacy conferences. Audio platform channels
are stubbed because UIKit creates a ringtone player; the messaging and rendezvous
transports are real. Files exchange endpoints, session public keys and phase
markers; they do not deliver presence, greetings, friend requests, group
invitations or messages.

## Re-run the prepared harness

The verification build and Flutter project are isolated under the app's ignored
`build/` directory, preserving the original tim2tox checkout:

```sh
TOXEE_VERIFY_RUN="$PWD/build/location-verification-2q4l4xk1"
export SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk
export TOXEE_LOCATION_NATIVE_LIB="$TOXEE_VERIFY_RUN/native-build/ffi/libtim2tox_ffi.dylib"

flutter test --no-pub --packages "$TOXEE_VERIFY_RUN/package_config.json" \
  test/nearby test/location_message_bubble_test.dart \
  test/location_platform_declarations_test.dart \
  test/ui/testing/settings_anchor_test.dart --reporter expanded

python3 tool/test_location_native_network.py \
  --harness "$TOXEE_VERIFY_RUN/flutter-harness" \
  --native-lib "$TOXEE_LOCATION_NATIVE_LIB" \
  --output "$TOXEE_VERIFY_RUN/two-peer-rerun"
```

The runner creates a fresh exchange directory on every invocation, starts both
peers, checks both exit codes and evidence files, and fails on timeout, missing
evidence (including both group sends/receives), skipped tests, or teardown errors.
A requested native library must match
the fixture-selected binary. The test is opt-in when run without the runner.
Explicit `TOXEE_LOCATION_NATIVE_LIB` also makes native bubble loading fail loudly
instead of silently skipping.

## Rebuilding after removing build artifacts

The prepared harness is disposable. To recreate it:

1. Copy `third_party/tim2tox` to a scratch source directory, including its
   initialized submodules. Exclude generated build directories. Initialize the
   scratch copy as its own Git root before applying
   `tool/native_log_overlays/bounded-logging.patch` with `git apply
   --unidiff-zero --ignore-space-change`. Confirm the patched file hashes against
   `tool/native_log_overlays/manifest.json`.
2. Build its FFI library with CMake/Ninja, Release, `BUILD_FFI=ON` and
   `TIM2TOX_ENABLE_TEST_HOOKS=ON`. This run also enabled `BUILD_TOXAV`,
   `MUST_BUILD_TOXAV`, `BOOTSTRAP_DAEMON`, `DHT_BOOTSTRAP`, `ENABLE_STATIC`, and
   `USE_IPV6`; disabled `STRICT_ABI`, `ENABLE_SHARED`, `UNITTEST`, `AUTOTEST`,
   `BUILD_MISC_TESTS`, `BUILD_FUN_UTILS`, `BUILD_FUZZ_TESTS`, and `EXPERIMENTAL_API`.
   CMake 4 needs `CMAKE_POLICY_VERSION_MINIMUM=3.5`. Use the installed Homebrew
   opus/libvpx/libconfig/libsodium prefix paths. Both compilers and the sysroot
   must come from the same Xcode installation: the default CLT SDK on this host
   was incompatible with the selected Xcode linker.
3. Point the copied tim2tox's `build` directory at that native build. Create a
   scratch Flutter project from this app's pubspec, lockfile, overrides and
   analysis/test configuration. Symlink `lib`, `test`, `assets`, and `tool` to
   this app; symlink its third-party dependencies, pointing `tim2tox` at the
   patched copy. Run `flutter pub get` in that scratch project. The recorded
   harness also includes the standalone `test` dev dependency used during native
   scenario investigation; the new peer test itself uses `flutter_test`.
4. Run the Python runner with that project as `--harness` and its native FFI
   library as `--native-lib`. Run the unit suite from that project as well, or
   use an absolute-URI package configuration pointing at the patched Dart copy.

## Recorded evidence

All paths below are relative to `build/location-verification-2q4l4xk1/`:

- `full-location-native-group-regression.log`: 91 passed, no skips.
- `full-pr-flutter-suite.log`: 3,242 passed, one opt-in network test skipped.
- `tracked-pr-analysis.log`: all 1,038 proposed Dart files, no diagnostics.
- `two-peer-group-run-2/result.json`: pass, both exit codes 0, distinct native
  PIDs, native packet counters, decoded C2C and group location elements, native
  group identities and per-group sender keys.
- `two-peer-group-run-2/alice.log`, `bob.log`, and the fresh `exchange-*` directory:
  native calls, phase assertions and both clean teardowns.
- `native-build.log`, `configure.log`, `native-build/CMakeCache.txt`: build
  configuration and output. The verified dylib SHA-256 is
  `6d1e00272bfbd9b600aefddadad5700637dbea4522f2f065f5a178567d8d076a`.

The first two C2C network attempts failed on test-harness listener/audio setup;
their process failures were retained as failures. The first group attempt reached
both real group receivers but failed on an incorrect test expectation that the
location description contained accuracy text. The description assertion now
checks the existing coordinate-label format. No additional product defect was
found. The final run uses the actual SDK listener registry and stubs the unrelated
audio method/event channels; independent Codex review found no blocking issue.

## Mobile and cross-platform review

The fixes are in shared Dart: account/session cancellation and per-cell native
keys apply to iOS and Android as well as desktop. Mobile already delivered
`paused`; the added `hidden` stop closes the desktop lifecycle gap and is covered
by a synthetic Flutter lifecycle regression. No OS background-location mode is
introduced. The native test's multiple processes are test infrastructure; the
production client keeps its existing single-instance session model.

Repository device checklist dispositions:

| Items | Status and evidence |
| --- | --- |
| 1: size (L3–L6, L8) | No layout change; existing location bubble verified at 320 width. Tablet/foldable device qualification remains separate. |
| 2–3: safe areas/keyboard, accessibility (L1/L2/L10/L11/I5) | Not applicable to these state/routing changes; no controls or layout changed. |
| 4–5: lifecycle/background (B1/B4/B6/B8/B10/V4/M9) | Verified controller hidden/paused/resume and session-teardown cancellation regressions. Camera/capture and profile persistence are unchanged. |
| 6–7: audio/camera (A1–A11/V4/V5) | Not applicable; no product audio/camera behavior changed. Only the test ringtone channels are stubbed. |
| 8: permissions (P1/P2/P8/B3) | Switch/session gates verified; declarations regression passes. Physical GPS and OS permission dialogs need devices. Notification permissions are unchanged. |
| 9: network (N1–N3/N6) | Loopback UDP and surviving-cell routing verified. Handover, weak links, TCP-only, IPv6-only and cross-NAT need network/device qualification. |
| 10: peer compatibility (M2) | Existing wire envelopes preserved; native C2C/private-group messages round-trip. Cross-OS device interoperability still needs hosts. |
| 11: singleton (L7/L7a) | Verified by source review: only the test uses independent instances/processes. |
| 12: mobile parity | Shared Dart fixes cover mobile; physical iOS/Android lifecycle and GPS qualification remains. |
