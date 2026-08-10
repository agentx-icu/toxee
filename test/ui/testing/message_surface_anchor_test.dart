// Message-surface automation anchors.
//
// History: this file used to be `message_surface_anchor_source_test.dart`. It
// had NO `test()` and NO `expect()` — a bare `main()` that read seven source
// files with `readAsStringSync` and threw `StateError` when a substring was
// missing. It executed zero lines of product code, so it contributed nothing to
// coverage and would break on a reflow or a rename while still proving nothing
// about runtime behaviour.
//
// It was split in two:
//   * The `UiKeys` constants are pinned HERE, by importing the real catalog and
//     asserting the real `Key` objects. `tool/mcp_test` drivers and the
//     marionette MCP binding address widgets by the *string* inside the key, so
//     the string is a wire contract with out-of-process tooling: renaming a
//     Dart field is free, changing its string silently breaks every driver.
//     Asserting the constant executes product code and survives reformatting.
//   * The "…and the key is attached at this call site" greps moved to
//     `tool/check_source_contracts.py --list` (group `ui-anchors`). Those target
//     the vendored `third_party/chat-uikit-flutter` fork and a UIKit
//     `messageInputBuilder` that cannot be pumped without a booted session, so
//     a grep is the only thing available — but a grep is a lint, not a test.

library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

void main() {
  group('message-surface UiKeys wire contract', () {
    test('chat input and send button keys keep their automation strings', () {
      expect(
        UiKeys.chatInputTextField,
        const Key('chat_input_text_field'),
        reason:
            'tool/mcp_test drivers tap/type into this key by string; changing '
            'it breaks every real-UI chat scenario.',
      );
      expect(
        UiKeys.chatSendButton,
        const Key('chat_send_button'),
        reason:
            'Mobile chat drivers tap this key by string. (Desktop sends via '
            'Enter on chatInputTextField — see the caveat in ui_keys.dart.)',
      );
    });

    test('chat anchors are distinct keys', () {
      // A copy/paste that gave two anchors the same string would make
      // find.byKey ambiguous at runtime, which is exactly the failure mode the
      // old source-grep could not detect.
      expect(UiKeys.chatInputTextField, isNot(UiKeys.chatSendButton));
    });
  });
}
