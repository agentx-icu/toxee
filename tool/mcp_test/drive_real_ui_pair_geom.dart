// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Shared GEOMETRY seams for the real-UI drivers.
//
// Split out of drive_real_ui_pair_chat.dart (which sits at its
// tool/.complexity_baseline.txt pin) so more than one case family can use them.
// Same library — this is organizational only.

/// Whether the RegisterPage is the route the user is actually LOOKING at.
///
/// `waitKey` (flutter_skill's element index) answers "is this key anywhere in
/// the tree", which is NOT the same question: `Navigator.push` leaves the route
/// underneath laid out, so a RegisterPage that was pushed and then covered by
/// (or returned from into) the home shell still matches. `_openRegisterPage`
/// used that check and therefore returned true while the app sat on HomePage —
/// live on iPad 2026-08-16, where `register_confirm_visibility_toggle_flips`
/// read `startObscured=true` off the covered route and then dispatched three
/// taps into the home shell, which of course changed nothing (screenshot
/// `ui_kg_confirm_vis_A.png` shows the Chats page). `ui_key_center`'s onstage
/// walk prunes exactly that case.
Future<bool> _registerPageOnstage(Inst inst, int timeoutSecs) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (true) {
    try {
      final r = await inst.l3('ui_key_center', {
        'key': 'register_page_nickname_field',
      });
      if (r['ok'] == true && r['onstage'] == true) return true;
    } on DriveError {
      // Fall through to the retry/timeout below.
    }
    if (!DateTime.now().isBefore(deadline)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}

/// `ui_key_center` with the box EXTENT that the plain `Inst.keyCenter` drops.
///
/// `keyCenter` returns only (x,y). A caller that has to aim at a FRACTION of a
/// widget needs its width too: `_openMessageMenuReal` targets the right/left
/// portion of a full-pane message row to land on an alignment-offset bubble,
/// and the old approximation ("the centre's absolute x is the pane half-width")
/// is only true when the chat pane is flush left — it put the tap OFF-SCREEN on
/// the iPad master-detail shell, where the pane starts after the sidebar and
/// the conversation list.
///
/// The `w`/`h` fields come from `uiKeyCenterHandler`
/// (lib/ui/testing/ui_drive_tools.dart). An older app build that does not
/// report them degrades to `w == 0`, and callers fall back to their keyed
/// whole-widget trigger instead of aiming at a bogus coordinate.
Future<({double x, double y, double w, double h})?> _keyBox(
  Inst inst,
  String key,
) async {
  try {
    final r = await inst.l3('ui_key_center', {'key': key});
    if (r['ok'] != true) return null;
    final x = (r['x'] as num?)?.toDouble();
    final y = (r['y'] as num?)?.toDouble();
    if (x == null || y == null) return null;
    return (
      x: x,
      y: y,
      w: (r['w'] as num?)?.toDouble() ?? 0,
      h: (r['h'] as num?)?.toDouble() ?? 0,
    );
  } on DriveError {
    return null;
  }
}
