# Location privacy and nearby routing fixes

**Goal:** Fix the three verified location review findings without changing the
nearby wire protocol or its foreground-only product behavior.

**Architecture:** Stop nearby discovery on desktop `hidden` as well as mobile
`paused`. Bind location sends to the initiating account and live Home session,
checking validity after asynchronous work and immediately before SDK dispatch.
Keep authenticated NGC peer keys per rendezvous cell, merge identical verified
presence copies, and select the key belonging to the surviving cell.

**Tech stack:** Flutter/Dart, existing geolocator source, tim2tox rendezvous
transport, flutter_test.

**Status:** Implemented and verified on 2026-11-12.

## 1. Write and run failing regressions

- Extend `test/nearby/nearby_controller_test.dart` with hidden/resumed behavior.
- Extend `test/nearby/location_sender_test.dart` with disposal during positioning,
  account changes, and teardown while the Home page is still mounted.
- Add `test/nearby/nearby_multicell_test.dart` using different NGC public keys in
  each cell. Verify duplicate presence merging, cell/peer exit fallback, valid
  greeting routes, and rejection of conflicting or stale signed records.
- Run these tests and confirm failures match the three original findings.

## 2. Fix lifecycle and account ownership

- Update `lib/nearby/nearby_controller.dart` to stop on `hidden`.
- Update `lib/nearby/location_sender.dart` to capture the account, validate the
  initiating context/session around awaits, and guard the SDK send path.
- Pass live session ownership from `lib/ui/home_page.dart`.
- Run the controller and sender tests.

## 3. Fix per-cell routes

- Update `lib/nearby/nearby_models.dart` to own cell-to-NGC-key routes.
- Update `nearby_service_inbound.dart` to merge identical verified records while
  preserving sequence, rate and binding checks.
- Update `nearby_service.dart` route removal and `nearby_service_intents.dart`
  route selection/revalidation.
- Run multicell and existing service/protocol tests.

## 4. Verify and review

- Run the complete nearby, location bubble, platform declaration, and relevant
  settings test suites; format changed Dart files and check the diff.
- For tests, reuse the isolated tim2tox Dart dependency with the repository's
  bounded logging overlay. Do not change the user's native checkout.
- Independently review the final diff with Codex and resolve actionable issues.
- Report verified results and any skipped native/device checks. No Claude review.

## Validation results

- Before implementation, six regression scenarios failed for the expected
  lifecycle, disposed/account-changed sender, and per-cell routing reasons.
- Native-enabled feature and settings suite: **91 passed, 0 skipped**. The three
  previously skipped bubble tests now run against a freshly built tim2tox FFI
  library with the repository's bounded logging overlay.
- The default UIKit path is covered by fake SDK manager tests for teardown during
  message creation and during the asynchronous profile lookup, checking that no
  optimistic message is inserted and no message is sent.
- Added rebind and stale-payload cases to preserve route isolation and replay
  rejection while merging identical verified broadcasts from distinct group keys.
- Targeted Dart analysis: **No issues found**. `git diff --check` passed.
- Independent Codex review found no remaining blocking issue in these changes.
- Two independent native Flutter test processes passed the real UDP network
  scenario: two-cell discovery with distinct NGC keys, surviving-cell greeting,
  nonce-matched friend confirmation, bidirectional C2C location messages through
  the production SDK provider, private group invitation/join and bidirectional
  group location messages, and disappearance after visibility is disabled.
- Focused and native-network tests used an isolated dependency copy with the
  existing bounded logging patch. PR-wide checks use the app's normal bootstrap
  overlays; no submodule revision is changed. Network validation uses same-host
  loopback UDP and fixed synthetic coordinates; physical-device GPS, cross-NAT
  connectivity, and legacy-conference location messages were not exercised.
- Reproduction and evidence: [native verification](../reference/LOCATION_NATIVE_NETWORK_VERIFICATION.md).

## Follow-up: native group location messages

Extend the existing two-process wall-clock scenario after C2C verification:
create a private native group through the SDK, invite and explicitly join the
second account, wait for actual native group readiness, and send a location in
both directions using the default `LocationSender`. Check the immutable group
identity, opposite sender's per-group native public key, location type and
coordinates. Require both group-receive markers in the runner. If this reveals
a product defect, retain the failing native regression, fix its root cause, and
rerun the scenario plus the location/nearby regression suite.

**Completed:** Both native processes exited 0 in `two-peer-group-run-2`. The
production SDK created/invited/joined the private group; Alice's `tox_2` and Bob's
`tox_1` resolved to the same native chat identity. Both received the opposite
member's structured location message with its actual per-group public key and
distinct coordinates. The runner requires group readiness/send/receive evidence
from both processes. The description test expectation was corrected to the
existing coordinate-label format; no additional product fix was required.
The native-enabled regression suite again passed 91 tests with no skips, targeted
analysis and diff checks passed, and independent Codex review found no blocker.

PR preparation: the full Flutter suite passed 3,242 tests with one opt-in native
network test skipped during ordinary discovery (both roles separately passed via
the native runner). All 1,038 proposed Dart files passed strict analysis; the
complexity guard, bootstrap offline validation and source contracts passed.
