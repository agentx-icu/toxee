part of 'nearby_service.dart';

/// Initiator half of [NearbyService]: sending a friend-request intent to a
/// peer, matching the Tox friend application that answers it, and the
/// per-session block list.
extension NearbyServiceIntents on NearbyService {
  // --- intents (initiator) --------------------------------------------------

  /// Sends a friend-request intent to [peer]. Returns the pending record, or
  /// a [NearbyIntentFailure].
  Future<Object> sendIntent(NearbyPeer peer, String message) async {
    final keys = _keys;
    if (keys == null || !running) return NearbyIntentFailure.notRunning;
    if (!IntentBody.validMessage(message)) return NearbyIntentFailure.messageTooLong;
    final now = _clock();
    _intentsOut.removeWhere((t) => now.difference(t) > const Duration(hours: 1));
    if (_intentsOut.length >= NearbyService.maxIntentsOutPerHour) return NearbyIntentFailure.rateLimited;
    final chatId = peer.cellChatIdHex;
    if (chatId == null || !_joinedChatIds.contains(chatId)) {
      return NearbyIntentFailure.peerGone;
    }
    // Reserve the slot before the async work (concurrent taps), give it
    // back on every failure path.
    final slot = now;
    _intentsOut.add(slot);
    final gen = _gen;
    Object fail(NearbyIntentFailure f) {
      _intentsOut.remove(slot);
      return f;
    }
    final address = (await _selfAddress()).toLowerCase();
    if (!_live(gen)) return fail(NearbyIntentFailure.notRunning);
    final nonceHex = NearbyCrypto.hex(NearbyCrypto.randomBytes(NearbyLimits.nonceBytes));
    final body = IntentBody(
      address: address,
      nonceHex: nonceHex,
      message: message,
      exp: now.millisecondsSinceEpoch ~/ 1000 + NearbyLimits.intentTtlSeconds,
    );
    final bytes = await IntentRecord.encode(
        keys: keys, recipientEkHex: peer.ekHex, body: body);
    if (!_live(gen)) return fail(NearbyIntentFailure.notRunning);
    if (bytes == null) return fail(NearbyIntentFailure.messageTooLong);
    if (!_joinedChatIds.contains(chatId)) return fail(NearbyIntentFailure.peerGone);
    final rc = _transport.send(chatId, bytes, peerPkHex: peer.ngcPeerPkHex);
    if (rc != 1) return fail(NearbyIntentFailure.peerGone);
    final pending = PendingIntent(
      nonceHex: nonceHex,
      expiresAt: now.add(const Duration(seconds: NearbyLimits.intentTtlSeconds)),
      targetSkHex: peer.skHex,
      targetEkHex: peer.ekHex,
      targetName: peer.name,
    );
    _pendingByNonce[nonceHex] = pending;
    _notify();
    return pending;
  }

  /// A friend application arrived; if its wording carries one of our pending
  /// nonces the intent is consumed and returned (the UI shows the confirm
  /// card). Anything else returns null and stays an ordinary application.
  PendingIntent? matchFriendApplication(String? wording) {
    final n = IntentBody.nonceFromWording(wording);
    if (n == null) return null;
    final now = _clock();
    _pruneExpired(now);
    if (_consumedNonces.containsKey(n)) return null;
    final pending = _pendingByNonce.remove(n);
    if (pending == null) return null;
    _consumedNonces[n] = pending.expiresAt;
    _notify();
    return pending;
  }

  /// Cancels every pending intent (rotate my Tox ID, stop, account switch).
  void cancelPendingIntents() {
    _pendingByNonce.clear();
    _notify();
  }

  void dismissIncoming(IncomingIntent intent) {
    _incoming.remove(intent);
    _notify();
  }

  void block(NearbyPeer peer) {
    _blockedSk.add(peer.skHex);
    _peers.remove(peer.skHex);
    _incoming.removeWhere((i) => i.fromSkHex == peer.skHex);
    _notify();
  }

  bool isBlocked(String skHex) => _blockedSk.contains(skHex);
}
