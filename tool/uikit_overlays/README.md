# Toxee-owned UIKit overlay

`manifest.json` and `motion-and-paste.patch` are tracked with the app. The UIKit
submodule pointer stays unchanged. Bootstrap applies only to the pinned revision
and exact original source, then verifies exact patched source. Already applied
source is checked without another mutation. Source hashes normalise CRLF only.
Local source drift and partial application fail; no reset or cleanup discards it.

- D7: shared message jump highlighting observes `MediaQuery.disableAnimations`,
  keeps a static cue for the same deadline, and owns/cancels all timers.
- I3: the existing desktop resource-paste handler handles either control/meta key
  on key-down only. It leaves Flutter's standard text-paste action in charge of
  plain text; there is no second text-insertion action.

Run `dart tool/bootstrap_deps.dart` and its `--offline-check-only` verification.
See `test/tool/bootstrap_uikit_overlay_test.dart` for real-source patch fixtures,
`test/ui/chat/message_highlight_motion_test.dart` and
`test/ui/chat/desktop_paste_modifiers_test.dart` for actual UIKit behavior.
Rebase and review the patch and all hashes together before a UIKit upgrade.
