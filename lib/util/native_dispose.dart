import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'logger.dart';
import 'native_quarantine.dart';
import 'safe_diagnostics.dart';

/// Disposes [service] and reports whether its native instance was PROVEN
/// stopped (`FfiChatService.nativeInstanceStopped == true`).
///
/// Every other outcome — `dispose()` threw, Tim2Tox quarantined an instance a
/// background task was still using, or an older tim2tox that cannot tell —
/// is recorded in [NativeQuarantine] under every id in [toxIds], so no
/// deletion in this process removes a directory a late savedata write could
/// still land in. This is the one place a discarded service's outcome is
/// judged: a cleanup that disposes and only logs a throw loses exactly the
/// "returned normally but quarantined" case.
///
/// [toxIds] null means "ask the service" (a registration bootstrap instance
/// has no id the caller knows yet); the probe is guarded, because this never
/// throws.
Future<bool> disposeRecordingQuarantine(
  FfiChatService service, {
  required String stage,
  Iterable<String?>? toxIds,
}) async {
  final ids = <String>[
    for (final id in toxIds ?? <String?>[_selfToxIdOrNull(service)])
      if (id != null && id.isNotEmpty) id,
  ];
  void markAll() {
    for (final id in ids) {
      NativeQuarantine.mark(id);
    }
  }

  try {
    await service.dispose();
  } catch (e) {
    SafeDiagnostics.logFailure(
      '[AccountService] native_dispose_failed stage=$stage',
      e,
    );
    markAll();
    return false;
  }
  final override = NativeDisposeTestHooks.nativeStoppedOverride;
  final bool? stopped;
  try {
    stopped = override != null
        ? override(service)
        : service.nativeInstanceStopped;
  } catch (e) {
    SafeDiagnostics.logFailure(
      '[AccountService] native_dispose_outcome_unknown stage=$stage',
      e,
    );
    markAll();
    return false;
  }
  if (stopped == true) return true;
  markAll();
  AppLogger.warn(
    '[AccountService] stage=$stage: the Tox instance was quarantined rather '
    'than stopped; its directories are left for the next start instead of '
    'being deleted under a possible late save',
  );
  return false;
}

String? _selfToxIdOrNull(FfiChatService service) {
  try {
    return service.getSelfToxId();
  } catch (_) {
    return null;
  }
}

abstract final class NativeDisposeTestHooks {
  NativeDisposeTestHooks._();

  /// Replaces `nativeInstanceStopped` after a real `dispose()`, so a test can
  /// make a real service look quarantined. Null => the real flag.
  @visibleForTesting
  static bool? Function(FfiChatService service)? nativeStoppedOverride;

  @visibleForTesting
  static void reset() {
    nativeStoppedOverride = null;
  }
}
