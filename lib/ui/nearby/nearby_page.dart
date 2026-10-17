import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../../i18n/app_localizations.dart';
import '../../nearby/nearby_controller.dart';
import '../../nearby/nearby_records.dart';
import '../../nearby/nearby_service.dart';
import '../testing/nearby_ui_keys.dart';
import 'nearby_privacy_notice.dart';

/// People nearby: the members of our geocells with a coarse distance, a
/// "say hi" that sends a friend-request intent, and the incoming intents we
/// received (accept = send the Tox friend request that carries the nonce).
class NearbyPage extends StatefulWidget {
  const NearbyPage({
    super.key,
    required this.service,
    required this.enabled,
    this.onOpenSettings,
  });

  final FfiChatService service;

  /// Location master + nearby visibility are on for this account.
  final bool enabled;
  final VoidCallback? onOpenSettings;

  @override
  State<NearbyPage> createState() => _NearbyPageState();
}

class _NearbyPageState extends State<NearbyPage> {
  NearbyService? get _nearby => NearbyController.instance.nearby;
  Timer? _idle;

  @override
  void initState() {
    super.initState();
    _nearby?.addListener(_onChanged);
    NearbyController.instance.pageOpened();
    NearbyController.idleTimer?.cancel();
    NearbyController.idleTimer = null;
    // The controller + service re-read the account's switches; the
    // `enabled` snapshot only decides what to render.
    if (widget.enabled) unawaited(_startAndRefresh());
  }

  /// Start (again, after a pause / switch) and take a fresh fix.
  Future<void> _startAndRefresh() async {
    if (await NearbyController.instance.startIfEnabled()) {
      await _nearby?.refresh();
    }
  }

  @override
  void dispose() {
    NearbyController.instance.pageClosed();
    _nearby?.removeListener(_onChanged);
    // Plan §3.1: nearby stops 5 min after the page is closed.
    final nearby = _nearby;
    _idle?.cancel();
    if (nearby != null) {
      _idle = Timer(const Duration(minutes: 5), () => unawaited(nearby.stop()));
      NearbyController.idleTimer = _idle;
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final nearby = _nearby;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.peopleNearby),
        actions: [
          if (nearby != null && widget.enabled)
            IconButton(
              tooltip: l10n.refresh,
              icon: const Icon(Icons.refresh),
              onPressed: () => unawaited(_startAndRefresh()),
            ),
        ],
      ),
      body: !widget.enabled || nearby == null
          ? _Notice(
              icon: Icons.location_off_outlined,
              text: l10n.nearbyOff,
              action: widget.onOpenSettings == null
                  ? null
                  : FilledButton(
                      onPressed: widget.onOpenSettings,
                      child: Text(l10n.openSettings),
                    ),
            )
          : _body(context, nearby, l10n),
    );
  }

  Widget _body(BuildContext context, NearbyService nearby, AppLocalizations l10n) {
    final peers = nearby.peers;
    final incoming = nearby.incomingIntents;
    final header = switch (nearby.status) {
      NearbyStatus.idle => l10n.nearbyPaused,
      NearbyStatus.locating => l10n.nearbyLocating,
      NearbyStatus.joining => l10n.nearbyJoining,
      NearbyStatus.noLocation => l10n.nearbyNoLocation,
      NearbyStatus.dhtNotReady => l10n.nearbyDhtNotReady,
      NearbyStatus.cellUnavailable => l10n.nearbyCellUnavailable,
      NearbyStatus.active =>
        peers.isEmpty ? l10n.nearbyNobody : l10n.nearbyPeopleCount(peers.length),
    };
    final busy = nearby.running &&
        nearby.status != NearbyStatus.noLocation &&
        (nearby.status != NearbyStatus.active || peers.isEmpty);
    return ListView(
      key: NearbyUiKeys.nearbyPeerList,
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            if (busy)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            Expanded(child: Text(header, style: Theme.of(context).textTheme.bodyMedium)),
          ],
        ),
        const SizedBox(height: 12),
        for (final intent in incoming) _IncomingCard(intent: intent, nearby: nearby, service: widget.service),
        for (final peer in peers) _PeerCard(peer: peer, nearby: nearby),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class _PeerCard extends StatelessWidget {
  const _PeerCard({required this.peer, required this.nearby});
  final NearbyPeer peer;
  final NearbyService nearby;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final distance = nearby.distanceTo(peer);
    final distanceText = distance == null
        ? ''
        : distance < 1000
            ? l10n.nearbyDistanceMeters(((distance / 100).ceil() * 100).toInt())
            : l10n.nearbyDistanceKm((distance / 1000).toStringAsFixed(1));
    final name = peer.name.isEmpty ? l10n.nearbyUnnamed : peer.name;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(child: Text(name.characters.first.toUpperCase())),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: distanceText.isEmpty ? null : Text(distanceText),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: l10n.nearbyBlock,
              icon: const Icon(Icons.block),
              onPressed: () {
                nearby.block(peer);
                ScaffoldMessenger.maybeOf(context)
                  ?..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(l10n.nearbyBlocked)));
              },
            ),
            FilledButton.tonal(
              onPressed: () => unawaited(_sayHi(context)),
              child: Text(l10n.nearbySayHi),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sayHi(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        // The wire budget (bytes inside the sealed record) binds before the
        // 140-character limit for non-ASCII text: count what actually fits.
        final used = IntentBody.messageWireBytes(controller.text.trim());
        final fits = used <= IntentBody.maxMessageWireBytes &&
            IntentBody.validMessage(controller.text.trim());
        return AlertDialog(
          title: Text(peer.name.isEmpty ? l10n.nearbyUnnamed : peer.name),
          content: TextField(
            controller: controller,
            maxLength: NearbyLimits.messageMaxCodePoints,
            maxLines: 3,
            onChanged: (_) => setDialogState(() {}),
            decoration: InputDecoration(
              hintText: l10n.nearbyRequestMessageHint,
              counterText: '$used/${IntentBody.maxMessageWireBytes}',
              errorText: fits ? null : l10n.nearbyRequestTooLong,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.cancel)),
            FilledButton(
              onPressed: fits ? () => Navigator.of(ctx).pop(controller.text.trim()) : null,
              child: Text(l10n.nearbySendRequest),
            ),
          ],
        );
      }),
    );
    controller.dispose();
    if (message == null || !context.mounted) return;
    // Consent: the intent discloses the user's own Tox ID to this one peer.
    if (!await showNearbyConsent(context, peer.name.isEmpty ? l10n.nearbyUnnamed : peer.name)) {
      return;
    }
    // The dialogs took time: the page may be gone or nearby stopped.
    if (!context.mounted || !nearby.running) return;
    final result = await nearby.sendIntent(peer, message);
    if (!context.mounted) return;
    final text = switch (result) {
      PendingIntent() => l10n.nearbyRequestSent,
      NearbyIntentFailure.rateLimited => l10n.nearbyRequestLimit,
      NearbyIntentFailure.messageTooLong => l10n.nearbyRequestTooLong,
      NearbyIntentFailure.peerGone => l10n.nearbyPeerGone,
      _ => l10n.nearbyPeerGone,
    };
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

class _IncomingCard extends StatelessWidget {
  const _IncomingCard({required this.intent, required this.nearby, required this.service});
  final IncomingIntent intent;
  final NearbyService nearby;
  final FfiChatService service;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = intent.fromName.isEmpty ? l10n.nearbyUnnamed : intent.fromName;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.nearbyIncomingTitle, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(l10n.nearbyIncomingBody(name)),
            if (intent.message.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('“${intent.message}”', style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => nearby.dismissIncoming(intent),
                  child: Text(l10n.nearbyIncomingDecline),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => unawaited(_accept(context)),
                  child: Text(l10n.nearbyIncomingAccept),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Accept = send the Tox friend request to the disclosed address with the
  /// nonce in its wording; the initiator confirms on its side.
  Future<void> _accept(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await service.addFriend(intent.address, requestMessage: intent.requestWording);
    if (!context.mounted) return;
    nearby.dismissIncoming(intent);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(result.resultCode == 0 ? l10n.nearbyRequestSent : l10n.nearbyPeerGone)));
  }
}
