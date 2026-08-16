part of 'home_page.dart';

// ---------------------------------------------------------------------------
// Desktop keyboard shortcut intents
// ---------------------------------------------------------------------------
// Each intent is a marker type — the matching `CallbackAction` lives inline
// in `HomePage.build` so it can close over local state (`setState`,
// `_showAddFriendDialog`, etc.).
//
// Split out of `home_page.dart` (which is at its `tool/.complexity_baseline.txt`
// pin) as a deliberate, coherent unit rather than re-pinning the aggregator.
//
// NOTE ON REACH: the `Shortcuts`/`Actions` wrapper that binds these is guarded
// by `PlatformUtils.isDesktop`, so NONE of them exist on iOS/iPadOS/Android.
// That is why `_OpenSearchIntent`'s target — toxee's global `CustomSearch`
// overlay — needs a visible affordance on touch platforms; see
// `NewEntryButton.onOpenGlobalSearch` (`lib/ui/home/home_widgets.dart`).
class _OpenSettingsIntent extends Intent {
  const _OpenSettingsIntent();
}

class _NewConversationIntent extends Intent {
  const _NewConversationIntent();
}

class _CloseWindowIntent extends Intent {
  const _CloseWindowIntent();
}

class _OpenSearchIntent extends Intent {
  const _OpenSearchIntent();
}
