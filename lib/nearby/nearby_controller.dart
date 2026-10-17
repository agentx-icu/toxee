import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_application.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../util/ffi_chat_service_account_key.dart';
import '../util/logger.dart';
import '../util/prefs.dart';
import 'location_source.dart';
import 'nearby_friend_request.dart';
import 'nearby_service.dart';
import 'nearby_transport.dart';

/// Process singleton with the `IrcAppManager` shape: one live session at a
/// time. `attach(service)` at HomePage bootstrap, `shutdownSession(service)`
/// from account teardown (stage `nearbyShutdown`, before the service is
/// disposed), `stop()` on pause and from the Settings switches.
class NearbyController with WidgetsBindingObserver {
  NearbyController._();
  static final NearbyController instance = NearbyController._();

  /// Test seam: replaces the OS location source for the next [attach].
  static LocationSource? locationSourceOverride;

  /// Test seam: replaces the tim2tox rendezvous transport for the next
  /// [attach] (widget tests never load the native library).
  static NearbyTransport Function(FfiChatService service)? transportOverride;

  /// The 5-minute idle stop armed when the nearby page closes (plan §3.1);
  /// kept so a reopen can cancel it.
  static Timer? idleTimer;

  FfiChatService? _service;
  NearbyService? _nearby;
  NearbyFriendRequestMatcher? _matcher;
  bool _observing = false;

  /// Teardown of the previous session; a new session never starts over the
  /// same transport before it finished (its `leaveAll` would hit our cells).
  Future<void>? _pendingTeardown;

  /// Nearby pages currently mounted: resume restarts the session only while
  /// one is open (foreground-only, page-driven, plan §3.1).
  int _pagesOpen = 0;
  void pageOpened() => _pagesOpen++;
  void pageClosed() => _pagesOpen = _pagesOpen > 0 ? _pagesOpen - 1 : 0;

  NearbyService? get nearby => _nearby;
  NearbyFriendRequestMatcher? get matcher => _matcher;
  FfiChatService? get service => _service;
  bool get attached => _service != null;

  /// Binds the live session. Idempotent for the same service; a different
  /// service first tears the previous one down.
  void attach(FfiChatService service,
      {required String Function() displayName,
      String Function()? avatarHex}) {
    if (identical(_service, service) && _nearby != null) return;
    // Tear the previous session down on its OWN objects (captured here), so
    // replacing the fields below cannot make the shutdown a no-op.
    final previous = (service: _service, nearby: _nearby, matcher: _matcher);
    if (previous.service != null) {
      final earlier = _pendingTeardown;
      _pendingTeardown = () async {
        await earlier;
        await _teardown(previous.nearby, previous.matcher);
      }();
    }
    _service = service;
    final toxId = service.accountKey;
    _nearby = NearbyService(
      transport: transportOverride?.call(service) ??
          RendezvousNearbyTransport(service.rendezvous),
      location: locationSourceOverride ?? const GeolocatorLocationSource(),
      selfAddress: () async => service.accountKey,
      displayName: displayName,
      avatarHex: avatarHex,
      // The account's switches, re-read before every position read.
      canRun: () async =>
          await LocationPrefs.getLocationEnabled(toxId) &&
          await LocationPrefs.getNearbyVisible(toxId),
    );
    _matcher = NearbyFriendRequestMatcher(_nearby!);
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
  }

  /// Feeds the friend applications HomePage already receives.
  List<NearbyReply> offerApplications(List<V2TimFriendApplication> apps) =>
      _matcher?.offer(apps) ?? const [];

  /// Starts nearby if the account's switches allow it (the service re-checks
  /// them itself before every position read).
  Future<bool> startIfEnabled() async {
    final stops = _stops;
    // Wait for the WHOLE teardown chain, even if attach() extended it while
    // we waited; a stop() that landed meanwhile wins.
    Future<void>? seen;
    while (!identical(_pendingTeardown, seen)) {
      seen = _pendingTeardown;
      await seen;
    }
    if (_stops != stops) return false;
    final nearby = _nearby;
    if (nearby == null) return false;
    await nearby.start();
    return nearby.running;
  }

  /// Bumped by every [stop] (pause, switches, page idle): a start that was
  /// queued behind a teardown when the stop came must not go through.
  int _stops = 0;

  /// Resume while a nearby page is open: start again (pause stopped us) and
  /// take a fresh fix.
  Future<void> _resume() async {
    if (_pagesOpen == 0) return;
    if (await startIfEnabled()) await _nearby?.refresh();
  }

  Future<void> stop() async {
    _stops++;
    try {
      await _nearby?.stop();
    } catch (e, st) {
      AppLogger.logError('[Nearby] stop failed', e, st);
    }
  }

  /// Must run while [service] is still alive (before `service.dispose()`).
  /// Best-effort: teardown must never throw.
  Future<void> shutdownSession(FfiChatService service) async {
    if (!identical(_service, service)) return;
    _stops++;
    final nearby = _nearby;
    final matcher = _matcher;
    _nearby = null;
    _matcher = null;
    _service = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    final earlier = _pendingTeardown;
    final mine = () async {
      await earlier;
      await _teardown(nearby, matcher);
    }();
    _pendingTeardown = mine;
    await mine;
  }

  static Future<void> _teardown(
      NearbyService? nearby, NearbyFriendRequestMatcher? matcher) async {
    try {
      await nearby?.stop();
      nearby?.cancelPendingIntents();
      nearby?.dispose();
      await matcher?.dispose();
    } catch (e, st) {
      AppLogger.log('[Nearby] teardown error (non-fatal): $e\n$st');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Foreground-only feature (checklist B1/B8): nothing runs in background.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(stop());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_resume());
    }
  }
}
