import 'dart:async';

import 'package:flutter/material.dart';

import '../../util/logger.dart';

/// Which full-window routes stand between the home shell and the user.
///
/// On a master-detail (wide) layout the UIKit pages — group profile, member
/// list, member info, user profile — are pushed as [MaterialPageRoute]s on the
/// ROOT navigator (`TencentCloudChatRouter.navigateTo`), so they cover the
/// whole window, right pane included. `HomePage` itself is an `AppPageRoute`
/// (a `PageRouteBuilder`), which is why "pop every MaterialPageRoute" stops at
/// the shell and never disposes it.
///
/// [keepFullscreenDialogs] protects surfaces a user-facing open must not tear
/// down: the AV conference session page is a `fullscreenDialog`
/// MaterialPageRoute whose dispose leaves the conference. The L3 deep-link
/// seams keep their historical predicate (pop every MaterialPageRoute) by
/// passing false.
bool isShellOverlayRoute(
  Route<dynamic> route, {
  required bool keepFullscreenDialogs,
}) {
  if (route.isFirst || route is! MaterialPageRoute) return false;
  if (keepFullscreenDialogs && route.fullscreenDialog) return false;
  return true;
}

/// Pop the shell-covering overlay routes off [navigator] (see
/// [isShellOverlayRoute]). Stops at the first route that is not an overlay,
/// so a dialog / popup menu on top — or the conference page — is left alone.
///
/// Waits for the end of the current frame first and retries while the
/// navigator is locked: the callers (a notification tap, a profile's "Send a
/// message" tile, an L3 seam) can fire in the middle of a navigation.
///
/// [stopAt] additionally stops at a matching route (kept on screen) — used on
/// compact layouts to reveal an already-pushed chat route instead of pushing a
/// duplicate.
Future<void> popShellOverlayRoutes(
  NavigatorState? navigator, {
  bool keepFullscreenDialogs = true,
  bool Function(Route<dynamic> route)? stopAt,
}) async {
  if (navigator == null) return;
  for (var attempt = 0; attempt < 12; attempt++) {
    await WidgetsBinding.instance.endOfFrame;
    if (!navigator.mounted) return;
    try {
      navigator.popUntil(
        (route) =>
            (stopAt?.call(route) ?? false) ||
            !isShellOverlayRoute(
              route,
              keepFullscreenDialogs: keepFullscreenDialogs,
            ),
      );
      return;
    } on Object catch (e, st) {
      if (!e.toString().contains('!_debugLocked') || attempt == 11) {
        AppLogger.logError('[HomePage] overlay route pop skipped', e, st);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

/// Open a chat on the master-detail shell: clear the full-window routes that
/// cover the right pane, then bind the pane via [select].
///
/// Every wide `_openChat` caller needs this, not only notification taps:
/// `_openChat` on a wide layout only rebinds the right pane, and ANY overlay
/// route on the root navigator hides that pane — so an open that leaves one in
/// place is invisible and reads as a dead tap. The callers are a notification
/// tap (the reported case), a profile's "Send a message" tile (which pops only
/// the profile itself — a member list / member info beneath it used to keep
/// covering the chat), the contacts-tab group row and the L3 open-chat seam
/// (both harmless: nothing is on top of the shell then). Compact layouts do
/// not come here — they PUSH the chat route, which lands on top of any
/// overlay and is therefore always visible.
///
/// [select] runs synchronously (before the pops complete) so the pane is
/// already bound when the overlays animate away.
void openChatOnWideShell({
  required NavigatorState? navigator,
  required VoidCallback select,
}) {
  select();
  if (navigator != null) {
    // Fire-and-forget: the pop waits for the frame; the bind above is done.
    unawaited(popShellOverlayRoutes(navigator));
  }
}
