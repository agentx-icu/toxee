/// Annex to [UiKeys] (`lib/ui/testing/ui_keys.dart`) for automation anchors on
/// the **home shell chrome** — the toxee-owned widgets injected into the UIKit
/// conversation / contact app bars (`lib/ui/home/home_widgets.dart`).
///
/// WHY A SEPARATE FILE. `ui_keys.dart` is pinned at its current line count in
/// `tool/.complexity_baseline.txt` (the guard is a ratchet: baselined files may
/// shrink, never grow), so new entries cannot be appended there. Splitting is
/// the repository's documented alternative to re-pinning — the same move
/// `ui_keys_fork.dart` (fork-owned keys) and `ui_keys_login.dart` (pre-login
/// keys) already make.
///
/// Same conventions as [UiKeys]: camelCase Dart field, snake_case
/// `<surface>_<role>` key string, grouped by the widget file that owns them.
library;

import 'package:flutter/foundation.dart';

/// Home-shell chrome automation keys. Instantiated nowhere; use the statics
/// directly.
class HomeUiKeys {
  HomeUiKeys._();

  // ---------------------------------------------------------------------
  // NewEntryButton (lib/ui/home/home_widgets.dart)
  // ---------------------------------------------------------------------

  /// The magnifier that opens toxee's global search overlay (`CustomSearch` in
  /// all-conversations mode) from the conversation app bar.
  ///
  /// Renders ONLY on non-desktop platforms. On desktop the same overlay is
  /// reachable through the Cmd/Ctrl+F `_OpenSearchIntent` shortcut
  /// (`home_page.dart`), which is registered behind `PlatformUtils.isDesktop`
  /// and therefore does not exist on iOS/iPadOS/Android — this button is that
  /// missing entry point, not a duplicate of it.
  static const Key conversationGlobalSearchButton = Key(
    'conversation_global_search_button',
  );
}
