/// Annex to [UiKeys] (`lib/ui/testing/ui_keys.dart`) for widgets whose keys are
/// attached INSIDE the vendored Tencent UIKit fork
/// (`third_party/chat-uikit-flutter/`) rather than at a toxee call site.
///
/// WHY A SEPARATE FILE. `ui_keys.dart` is pinned at its current line count in
/// `tool/.complexity_baseline.txt` (the guard is a ratchet: baselined files may
/// shrink, never grow), so new entries cannot be appended there. Splitting is
/// the repository's documented alternative to re-pinning, and the split line is
/// a real one: everything here is a MIRROR of a `ValueKey(...)` literal that
/// lives in the fork, kept in-tree so a grep from the app side finds it and so
/// the naming convention has one home.
///
/// Same conventions as [UiKeys]: the Dart field is camelCase, the underlying
/// `Key` string is snake_case `<surface>_<role>`, and the entries are grouped by
/// the fork file that owns them. These constants are intentionally not
/// referenced from app code — the fork attaches the literal itself, exactly like
/// the pre-existing `UiKeys.messageAttachment*` mirror block — and the real-UI
/// drivers match on the STRING via `find.byKey` / `ui_key_center`.
library;

import 'package:flutter/foundation.dart';

/// Fork-owned automation keys. Instantiated nowhere; use the statics directly.
class ForkUiKeys {
  ForkUiKeys._();

  // ---------------------------------------------------------------------
  // Message multi-select toolbar
  // (tencent_cloud_chat_message_input/select_mode/
  //  tencent_cloud_chat_message_input_select_mode.dart)
  //
  // Reached from the message menu's `message_menu_item:multiSelect` entry,
  // which the fork only offers on message types it has not stripped it from
  // (see tencent_cloud_chat_message_item_with_menu_container.dart: TEXT and
  // file/image/video/sound bubbles all remove `_uikit_multi_message`, so a
  // CUSTOM bubble is the reachable driver today). Entering select mode swaps
  // the whole composer for this toolbar on every form factor.
  // ---------------------------------------------------------------------

  /// Delete-for-me affordance; present in all three builders (phone / tablet /
  /// desktop) whenever `enableMessageDeleteForSelf` is on.
  static const Key messageSelectDeleteButton = Key(
    'message_select_delete_button',
  );

  /// PHONE only (`defaultBuilder`): the single forward icon that opens the
  /// forward-type bottom sheet. Tablet/desktop render the per-type buttons
  /// below instead of a sheet.
  static const Key messageSelectForwardButton = Key(
    'message_select_forward_button',
  );

  /// TABLET/DESKTOP: forward each selected message individually (no sheet).
  static const Key messageSelectForwardIndividuallyButton = Key(
    'message_select_forward_individually_button',
  );

  /// TABLET/DESKTOP: forward the selection as one combined (merger) message.
  /// toxee pins `enableMessageForwardCombined` to false until the merger-elem
  /// protocol lands, so this button does not render today.
  static const Key messageSelectForwardCombinedButton = Key(
    'message_select_forward_combined_button',
  );

  /// Rows inside the PHONE forward-type bottom sheet.
  static const Key messageSelectForwardIndividuallyItem = Key(
    'message_select_forward_individually_item',
  );
  static const Key messageSelectForwardCombinedItem = Key(
    'message_select_forward_combined_item',
  );

  /// The multi-select delete confirmation dialog's two actions.
  static const Key messageSelectDeleteConfirmButton = Key(
    'message_select_delete_confirm_button',
  );
  static const Key messageSelectDeleteCancelButton = Key(
    'message_select_delete_cancel_button',
  );

  // ---------------------------------------------------------------------
  // Message multi-select HEADER bar
  // (tencent_cloud_chat_message_header/
  //  tencent_cloud_chat_message_header_select_mode.dart)
  //
  // Replaces the normal chat header while `inSelectMode` is true. It renders no
  // icons and every label is localized, so these three keys are the only stable
  // handles on the surface — `messageSelectCancelButton` in particular is how
  // automation LEAVES select mode (Escape is a no-op on mobile).
  // ---------------------------------------------------------------------

  static const Key messageSelectClearButton = Key(
    'message_select_clear_button',
  );

  /// The live "<n> selected" counter. Presence/absence of this key is the
  /// authoritative in-select-mode signal; its text is the selected count.
  static const Key messageSelectCountText = Key('message_select_count_text');

  static const Key messageSelectCancelButton = Key(
    'message_select_cancel_button',
  );

  // ---------------------------------------------------------------------
  // Forward target picker
  // (tencent_cloud_chat_message_input/forward/
  //  tencent_cloud_chat_message_forward.dart)
  // ---------------------------------------------------------------------

  /// Dismiss twin of the pre-existing `forward_picker_send_button`. Needed by
  /// cases that assert the picker SURFACE without actually forwarding: the
  /// picker is a desktop popup / modal sheet where a barrier tap is unreliable
  /// and Escape is a no-op on mobile.
  static const Key forwardPickerCancelButton = Key(
    'forward_picker_cancel_button',
  );

  // ---------------------------------------------------------------------
  // Group member surfaces (tencent_cloud_chat_contact/lib/widgets/*)
  // ---------------------------------------------------------------------

  /// Member-info route -> that member's user profile (the row labelled with the
  /// localized `tL10n.profile`).
  static const Key groupMemberInfoProfileEntry = Key(
    'group_member_info_profile_entry',
  );

  /// The MOBILE member manage sheet's dismiss action. Its siblings were already
  /// keyed (`group_member_action_{info,role,kick}_button`); this completes the
  /// set so a case that opens the sheet can close it deterministically.
  static const Key groupMemberActionCancelButton = Key(
    'group_member_action_cancel_button',
  );

  // ---------------------------------------------------------------------
  // Image bubble tap target
  // (tencent_cloud_chat_message_widgets/message_type_builders/
  //  tencent_cloud_chat_message_image.dart)
  // ---------------------------------------------------------------------

  /// `message_image_bubble:<msgID>` — the keyed `GestureDetector` that opens the
  /// full-screen viewer. PER-MESSAGE, so use [messageImageBubble] to build it.
  ///
  /// Automation previously had to aim at a fraction of the ROW
  /// (`message_list_item:<msgID>`), which is the whole chat pane wide while the
  /// bubble is alignment-offset and capped at 198pt — and the row key sits on a
  /// non-interactive widget that `interactiveStructured` does not report, so a
  /// bounds lookup through flutter_skill found nothing and the tap ladder in
  /// `message_viewer_save_and_zoom_surface` dispatched ZERO taps. This key is
  /// the tap target itself; its presence also proves the image DECODED (the
  /// loading / error placeholders are different subtrees without it).
  static Key messageImageBubble(String msgId) =>
      Key('message_image_bubble:$msgId');

  /// `message_image_loading:<msgID>` / `message_image_error:<msgID>` — the two
  /// placeholders the image bubble can show INSTEAD of the picture. They share
  /// the same geometry (`width x width*1.33`), so a bounds probe cannot tell
  /// them apart; without these keys a failing case could only report "the
  /// viewer did not open" and could not say whether the image was still
  /// decoding, had failed to decode, or the gesture had missed.
  ///
  /// The error placeholder is also an `InkWell`, which WINS the gesture arena
  /// over the image's parent `GestureDetector` — an errored bubble is therefore
  /// untappable by construction, which is the real reason
  /// `message_viewer_save_and_zoom_surface` could not open the viewer.
  static Key messageImageLoading(String msgId) =>
      Key('message_image_loading:$msgId');
  static Key messageImageError(String msgId) =>
      Key('message_image_error:$msgId');
}
