import 'package:flutter/material.dart';

import '../i18n/app_localizations.dart';
import '../ui/widgets/app_snackbar.dart';
import 'logger.dart';

/// Surfaces send-failure feedback as snackbars on top of the running app.
///
/// Tier 1B (offline queue) absorbs the common "friend offline" case: those
/// sends route to the queue and are surfaced as pending bubbles, not as
/// failures. This notifier is for the remaining failure modes — too-long
/// payloads, file errors, and real network / SDK errors — that we want the
/// user to see in addition to the red bubble.
///
/// The notifier is wired via [TencentCloudChat.instance.callbacks.onSDKFailed]
/// (see `home_page_bootstrap.dart`). It expects a global
/// [GlobalKey<ScaffoldMessengerState>] so the toast survives across page
/// transitions inside the app.
///
/// **Dedup**: identical `(apiName, code)` pairs are suppressed inside a 3s
/// window so a burst of failed sends doesn't carpet the screen. The window is
/// per-key (not global) so distinct error types are still allowed through.
///
/// **Why this uses `AppSnackBar.showErrorOnBuilder` and not
/// `AppSnackBar.showError`** (`lib/ui/widgets/app_snackbar.dart`):
/// `showError` takes a [BuildContext] and resolves its target with
/// `ScaffoldMessenger.of(context)`, i.e. an ANCESTOR lookup for
/// `_ScaffoldMessengerScope`. A `ScaffoldMessenger` publishes that scope to its
/// DESCENDANTS, so the only context this class can reach without a widget —
/// `scaffoldMessengerKey.currentState!.context` — can never resolve its own
/// messenger. In production the key is handed to `MaterialApp`
/// (`lib/main.dart`), where that messenger is the root one with no ancestor
/// messenger at all, so the lookup failed outright and the toast never
/// appeared. The `...On` entry points exist precisely so we can hand
/// `AppSnackBar` the messenger we already hold.
///
/// The `Builder` variant is used because [_humanize] reads
/// `AppLocalizations.of(context)`: that has to resolve at the DISPLAY site, not
/// from whatever context this class can reach. See `AppSnackBar`'s class doc
/// for why display-site resolution is the invariant.
class SendFailureNotifier {
  SendFailureNotifier._();

  /// Module-wide ScaffoldMessenger key wired into `MaterialApp` in
  /// `main.dart`. It is what lets non-widget code (e.g. SDK callbacks) raise a
  /// toast without a [BuildContext] in hand. When it is not attached — before
  /// the app is up, or after teardown — the failure is logged and dropped.
  ///
  /// The messenger it points at must have at least one descendant `Scaffold`,
  /// otherwise `showSnackBar` has nothing to present in. That holds for every
  /// app screen (login and home are both Scaffolds).
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static const Duration _dedupWindow = Duration(seconds: 3);

  /// Tox text payload upper bound the C layer enforces (see
  /// `MAX_MESSAGE_LENGTH` in `c-toxcore`). Used to render a precise toast for
  /// the most user-actionable failure.
  static const int toxMaxTextBytes = 1372;

  static final Map<String, DateTime> _lastShown = <String, DateTime>{};

  /// Key on the coloured surface inside the toast. Lets tests assert that the
  /// error colours are resolved from the app's theme at the display site rather
  /// than from a themeless context.
  ///
  /// Re-exported from `AppSnackBar` — which now owns the styling — so this
  /// module's tests do not have to know where the surface is built.
  @visibleForTesting
  static const Key toastSurfaceKey = AppSnackBar.toastSurfaceKey;

  /// Handle an SDK failure callback. Only `apiName == 'sendMessage'` is
  /// surfaced as a snackbar today; other api failures continue to be logged
  /// by the SDK trigger itself.
  static void handleSdkFailure(String apiName, int code, String desc) {
    if (apiName != 'sendMessage') {
      return;
    }
    final messengerState = scaffoldMessengerKey.currentState;
    if (messengerState == null) {
      AppLogger.warn(
          '[SendFailureNotifier] sendMessage failed (code=$code) but no scaffoldMessenger is mounted; suppressing toast');
      return;
    }

    final dedupKey = '$apiName:$code';
    final now = DateTime.now();
    final lastShown = _lastShown[dedupKey];
    if (lastShown != null && now.difference(lastShown) < _dedupWindow) {
      AppLogger.debug(
          '[SendFailureNotifier] dedup suppressed toast for code=$code (last shown ${now.difference(lastShown).inMilliseconds}ms ago)');
      return;
    }
    _lastShown[dedupKey] = now;

    // `AppSnackBar` does the `hideCurrentSnackBar()` itself: without it a
    // second (non-deduped) failure would sit in the messenger queue behind the
    // 4s error toast instead of replacing it.
    AppSnackBar.showErrorOnBuilder(
      messengerState,
      (context) => _humanize(context, code, desc),
    );
  }

  /// Reset dedup state. Intended for tests and account-switch cleanup.
  @visibleForTesting
  static void resetForTests() {
    _lastShown.clear();
  }

  static String _humanize(BuildContext context, int code, String desc) {
    final l10n = AppLocalizations.of(context);
    final lower = desc.toLowerCase();

    // Order matters: pattern checks run before the generic fallback. We
    // pattern-match the Tim2Tox desc because it is the most reliable signal
    // (the platform path always returns -1, with the real reason in desc).
    if (lower.contains('too long') ||
        lower.contains('exceeds') ||
        lower.contains('body_size') ||
        lower.contains('msg_body_size')) {
      return 'Message too long (max $toxMaxTextBytes bytes)';
    }
    if (lower.contains('friend is offline') ||
        lower.contains('friend offline') ||
        lower.contains('not connected') ||
        lower.contains('disconnect')) {
      // Should be rare now that Tier 1B queues offline sends silently; we
      // still translate it just in case a code path slips through.
      return 'Friend offline — will retry when they reconnect';
    }
    if (lower.contains('group') && lower.contains('file')) {
      return 'File transfer in group chats is not supported';
    }
    if (lower.contains('file') &&
        (lower.contains('not found') ||
            lower.contains('missing') ||
            lower.contains('cannot') ||
            lower.contains('failed'))) {
      return 'File send failed: ${_trim(desc)}';
    }

    // Final fallback uses the existing localized "Send failed: <reason>"
    // template. If the platform returned an empty desc we substitute a
    // human-friendly fallback so the toast is never literally "Send failed: ".
    final safeDesc = desc.trim().isEmpty
        ? (code != 0 ? 'error $code' : 'unknown error')
        : _trim(desc);
    if (l10n != null) {
      return l10n.sendFailed(safeDesc);
    }
    return 'Send failed: $safeDesc';
  }

  static String _trim(String desc) {
    const limit = 120;
    final trimmed = desc.trim();
    if (trimmed.length <= limit) return trimmed;
    return '${trimmed.substring(0, limit)}…';
  }
}
