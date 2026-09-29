import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'bootstrap_nodes.dart';
import 'logger.dart';
import 'network_change_rebootstrapper.dart';
import 'platform_utils.dart';
import 'prefs.dart';

/// Single source of truth for getting Tox DHT bootstrap nodes onto a running
/// session.
///
/// Why this exists: `FfiChatService.init()`'s `_loadAndApplySavedBootstrapNode`
/// only applies whatever is *already* persisted in prefs. A brand-new account
/// has nothing persisted — registration (`AccountService.registerNewAccount`)
/// never fetches a node — so the very first session of a fresh account would
/// otherwise reach `init()` with no DHT entry point and sit at "Connecting…"
/// until the next cold start (when the auto-login path happened to fetch one).
///
/// Every startup path (auto-login, manual login, registration) funnels through
/// [AppBootstrapCoordinator.boot], which calls [ensureForSession]. That makes
/// this the one place that guarantees nodes are applied to the live instance,
/// regardless of how the session was created.
class BootstrapNodeEnsurer {
  BootstrapNodeEnsurer._();

  /// In auto mode we bootstrap from several online nodes rather than one. Tox
  /// joins the DHT faster and more reliably with multiple entry points, and a
  /// single saved node going offline no longer pins the client offline.
  static const int maxAutoNodes = 4;

  /// Test seam: overrides the source of the live node list so tests don't hit
  /// the network. Defaults to [BootstrapNodesService.fetchNodes] when null.
  @visibleForTesting
  static Future<List<BootstrapNode>> Function()? debugNodeFetcher;

  /// Reads the persisted bootstrap mode, downgrading `'lan'` → `'auto'` on
  /// mobile (the LAN bootstrap daemon is desktop-only) and persisting the
  /// downgrade so the rest of the app sees a consistent mode.
  static Future<String> normalizeMode() async {
    var mode = await Prefs.getBootstrapNodeMode();
    if (!PlatformUtils.isDesktop && mode == 'lan') {
      await Prefs.setBootstrapNodeMode('auto');
      mode = 'auto';
    }
    return mode;
  }

  /// Ensures the freshly-booted [service] has bootstrap nodes applied.
  ///
  /// - Any persisted "current" node is applied immediately (cheap, local FFI
  ///   call) so a warm start with a known-good node connects without waiting on
  ///   the network.
  /// - On a fresh auto-mode account (no persisted node), the built-in fallback
  ///   nodes are applied immediately — no network — and prefs is seeded, so the
  ///   first session has DHT entry points right away even if nodes.tox.chat is
  ///   slow or down. This is the fix for "a freshly-registered account can't
  ///   reach the DHT in its first session".
  /// - In auto mode, the live node list is then fetched in the background and a
  ///   few more nodes are applied for freshness/resilience. The fetch never
  ///   gates navigation on an HTTP round-trip, and never writes prefs (so it
  ///   can't mutate state after a logout/teardown that raced it).
  static Future<void> ensureForSession(FfiChatService service) async {
    final mode = await normalizeMode();
    final saved = await Prefs.getCurrentBootstrapNode();
    if (saved != null) {
      await _safeAdd(service, saved.host, saved.port, saved.pubkey);
    } else if (mode == 'auto') {
      await _seedFromFallback(service);
    }
    // Manual / LAN: honor the user's explicit node, no live-list refresh.
    if (mode != 'auto') return;
    // Augment from the live node list in the background (fresher / more nodes)
    // without gating navigation.
    unawaited(_applyOnlineNodes(service));
  }

  /// Resilience for a session that is not connected (e.g. on app resume): in
  /// auto mode re-fetches the live list and applies fresh nodes, so a saved
  /// node that has since gone offline does not strand the client. In manual /
  /// LAN mode just re-applies the user's saved node. Best-effort.
  static Future<void> refreshIfDisconnected(FfiChatService service) async {
    if (service.isConnected) return;
    final mode = await normalizeMode();
    if (mode == 'auto') {
      await _applyOnlineNodes(service);
      return;
    }
    final saved = await Prefs.getCurrentBootstrapNode();
    if (saved != null) {
      await _safeAdd(service, saved.host, saved.port, saved.pubkey);
    }
  }

  /// Re-applies bootstrap nodes after the device's default network path
  /// changed (checklist N1, driven by `NetworkChangeReBootstrapper`).
  ///
  /// Unlike [refreshIfDisconnected] this is NOT gated on `isConnected`: the
  /// Tox connection status lags an IP change, and the stale window is exactly
  /// when a kick helps. Order: the saved node and, in auto mode, the built-in
  /// fallback nodes first (no network round-trip), then the live list. Uses
  /// `tryBootstrapNode`, so prefs are never written from here.
  ///
  /// [isLive] is checked before every native call: once it reads false (the
  /// session was torn down while this awaited prefs or the node list) nothing
  /// more is applied — `tryBootstrapNode` targets the CURRENT native instance,
  /// which may already belong to the next account.
  static Future<void> reapplyForNetworkChange(
    FfiChatService service, {
    bool Function()? isLive,
  }) async {
    bool live() => isLive?.call() ?? true;
    final mode = await normalizeMode();
    final saved = await Prefs.getCurrentBootstrapNode();
    if (!live()) return;
    if (saved != null) {
      await _safeTry(service, saved.host, saved.port, saved.pubkey);
    }
    if (mode != 'auto') return;
    for (final n in BootstrapNodesService.fallbackNodes.take(maxAutoNodes)) {
      if (n.publicKey.isNotEmpty) {
        await _tryAllHosts(service, n, isLive: live);
      }
    }
    await _applyOnlineNodes(service, isLive: live);
  }

  /// Starts following default-network changes for a live session and returns
  /// the disposer for the session's DisposableBag (no-op on desktop). See
  /// [NetworkChangeReBootstrapper].
  static void Function() watchNetworkChanges(FfiChatService service) =>
      NetworkChangeReBootstrapper.startForSession(service);

  /// Applies the built-in fallback nodes to [service] and seeds prefs with the
  /// first, with no network call. Used for the first-run auto-mode case so the
  /// session always has entry points immediately.
  static Future<void> _seedFromFallback(FfiChatService service) async {
    final fallback = BootstrapNodesService.fallbackNodes
        .where((n) => n.preferredHost != null && n.publicKey.isNotEmpty)
        .toList();
    if (fallback.isEmpty) return;
    final first = fallback.first;
    final firstHost = first.preferredHost;
    if (firstHost == null) return;
    await Prefs.setCurrentBootstrapNode(firstHost, first.port, first.publicKey);
    for (final n in fallback.take(maxAutoNodes)) {
      await _tryAllHosts(service, n);
    }
  }

  static Future<void> _applyOnlineNodes(
    FfiChatService service, {
    bool Function()? isLive,
  }) async {
    try {
      final fetch = debugNodeFetcher ?? BootstrapNodesService.fetchNodes;
      final nodes = await fetch();
      if (!(isLive?.call() ?? true)) return;
      var usable = nodes
          .where(
            (n) =>
                n.status == 'ONLINE' &&
                n.preferredHost != null &&
                n.publicKey.isNotEmpty,
          )
          .toList();
      if (usable.isEmpty) {
        // The API was reachable but flagged every node OFFLINE (stale or
        // pessimistic status). Applying a possibly-stale node still beats
        // applying nothing — Tox just drops entries it can't reach — so fall
        // back to any structurally-valid node rather than leaving the session
        // with no entry points.
        usable = nodes
            .where((n) => n.preferredHost != null && n.publicKey.isNotEmpty)
            .toList();
      }
      for (final n in usable.take(maxAutoNodes)) {
        if (!(isLive?.call() ?? true)) return;
        await _tryAllHosts(service, n, isLive: isLive);
      }
    } catch (e, st) {
      AppLogger.logError(
        '[BootstrapNodeEnsurer] failed to apply online nodes',
        e,
        st,
      );
    }
  }

  static Future<void> _safeAdd(
    FfiChatService service,
    String host,
    int port,
    String pubkey,
  ) async {
    try {
      await service.addBootstrapNode(host, port, pubkey);
    } catch (e, st) {
      AppLogger.logError(
        '[BootstrapNodeEnsurer] addBootstrapNode failed ($host:$port)',
        e,
        st,
      );
    }
  }

  /// Bootstraps every address [node] advertises (see
  /// [BootstrapNode.bootstrapHosts]): IPv4 first, then IPv6.
  static Future<void> _tryAllHosts(
    FfiChatService service,
    BootstrapNode node, {
    bool Function()? isLive,
  }) async {
    for (final host in node.bootstrapHosts) {
      if (!(isLive?.call() ?? true)) return;
      await _safeTry(service, host, node.port, node.publicKey);
    }
  }

  static Future<void> _safeTry(
    FfiChatService service,
    String host,
    int port,
    String pubkey,
  ) async {
    try {
      await service.tryBootstrapNode(host, port, pubkey);
    } catch (e, st) {
      AppLogger.logError(
        '[BootstrapNodeEnsurer] tryBootstrapNode failed ($host:$port)',
        e,
        st,
      );
    }
  }
}
