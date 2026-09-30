import 'dart:io';

import 'package:flutter/services.dart';

import '../util/logger.dart';

/// Keeps a second Flutter engine in the same Android process away from the
/// Tox session (see android/.../SessionOwnerChannel.kt).
///
/// tim2tox is a per-process singleton. A second MainActivity — reachable with
/// FLAG_ACTIVITY_MULTIPLE_TASK — used to run the whole startup again: a second
/// login on the same native instance, its callbacks re-registered to the new
/// isolate, two services polling and saving the profile. [claimOrYield] runs
/// before any of that: the first engine claims the session; a later one brings
/// the owner's task to the front and closes its own.
class SingleSessionGuard {
  SingleSessionGuard._();

  static const MethodChannel _channel = MethodChannel('toxee/session_owner');

  /// True when this engine may start the session. False means it yielded to
  /// the owning engine and must not start anything.
  ///
  /// Only Android can put two engines in one process here. A failing claim
  /// never blocks startup (the worst case is the old behaviour); a known
  /// non-owner never starts, even when yielding fails.
  static Future<bool> claimOrYield({
    MethodChannel channel = _channel,
    bool? isAndroid,
  }) async {
    if (!(isAndroid ?? Platform.isAndroid)) return true;
    bool owner;
    try {
      owner = await channel.invokeMethod<bool>('claim') ?? true;
    } on MissingPluginException {
      return true;
    } catch (e) {
      AppLogger.warn('[SingleSessionGuard] claim failed, continuing: $e');
      return true;
    }
    if (owner) return true;
    // Another engine owns the session: never start, even if yielding fails.
    AppLogger.warn('[SingleSessionGuard] another window owns the session');
    try {
      await channel.invokeMethod<void>('yieldToOwner');
    } catch (e) {
      AppLogger.warn('[SingleSessionGuard] yield failed: $e');
    }
    return false;
  }
}
