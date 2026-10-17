part of 'nearby_service.dart';

/// Inbound half of [NearbyService]: presence records and intents received
/// over the cell, with the validation table of plan §3.4 (rates and the
/// sk/ek ↔ NGC-peer-key binding are keyed by the toxcore-authenticated NGC
/// peer key).
extension _NearbyServiceInbound on NearbyService {
  Future<void> _onPacket(RendezvousPacket e) async {
    final now = _clock();
    final nowS = now.millisecondsSinceEpoch ~/ 1000;
    final gen = _gen;
    // Native per-peer budget already applied; this is the protocol-level
    // rate: 1 presence per 10 s per NGC peer key.
    if (!e.isPrivate) {
      // The sender broadcasts one record to every cell it is in: a copy of
      // the bytes we already verified from this key only adds the cell.
      final lastBytes = _lastPayloadByNgcPk[e.peerPkHex];
      if (lastBytes != null && _sameBytes(lastBytes, e.payload)) {
        final bound = _bindingByNgcPk[e.peerPkHex];
        final peer = bound == null ? null : _peers[bound.sk];
        if (peer != null && _joinedChatIds.contains(e.chatIdHex) && peer.cells.add(e.chatIdHex)) {
          _notify();
        }
        return;
      }
      final last = _lastRecordByNgcPk[e.peerPkHex];
      if (last != null && now.difference(last) < NearbyService.peerRateWindow) {
        _dropped++;
        return;
      }
      // Reserve the slot BEFORE the async verification so a burst from one
      // NGC key cannot pass the limit concurrently.
      _lastRecordByNgcPk[e.peerPkHex] = now;
      final record = await PresenceRecord.decode(e.payload, nowS);
      // The session and the cell must both still be current after the
      // async verification: a cell left meanwhile must not come back.
      if (record == null || !_live(gen) || !_joinedChatIds.contains(e.chatIdHex)) {
        _dropped++;
        return;
      }
      if (_acceptPresence(e, record, now)) _lastPayloadByNgcPk[e.peerPkHex] = e.payload;
      return;
    }
    final intent = await IntentRecord.decode(e.payload);
    if (intent == null || !_live(gen)) {
      _dropped++;
      return;
    }
    await _acceptIntent(e, intent, now, nowS, gen);
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// True when the record was taken (new or newer).
  bool _acceptPresence(RendezvousPacket e, PresenceRecord r, DateTime now) {
    if (_keys != null && r.skHex == _keys!.skHex) return false; // our own echo
    final bound = _bindingByNgcPk[e.peerPkHex];
    if (bound == null) {
      _bindingByNgcPk[e.peerPkHex] = (sk: r.skHex, ek: r.ekHex);
    } else if (bound.sk != r.skHex || bound.ek != r.ekHex) {
      final rebinds = _rebindsByNgcPk.putIfAbsent(e.peerPkHex, () => []);
      rebinds.removeWhere((t) => now.difference(t) > const Duration(minutes: 10));
      if (rebinds.length >= NearbyService.maxRebindsPer10Min) {
        _dropped++;
        return false;
      }
      rebinds.add(now);
      _peers.remove(bound.sk);
      _bindingByNgcPk[e.peerPkHex] = (sk: r.skHex, ek: r.ekHex);
    }
    final existing = _peers[r.skHex];
    if (existing != null) {
      // A copy of the same record through another cell has identical bytes
      // and was absorbed before verification (_onPacket); a re-signed record
      // with an old seq is a replay.
      if (r.seq <= existing.record.seq) {
        _dropped++;
        return false; // replay / stale
      }
      existing.record = r;
      existing.ekHex = r.ekHex;
      existing.ngcPeerPkHex = e.peerPkHex;
      existing.lastSeen = now;
      existing.cellChatIdHex = e.chatIdHex;
      existing.cells.add(e.chatIdHex);
    } else {
      _peers[r.skHex] = NearbyPeer(
        skHex: r.skHex,
        ekHex: r.ekHex,
        ngcPeerPkHex: e.peerPkHex,
        record: r,
        lastSeen: now,
      )
        ..cellChatIdHex = e.chatIdHex
        ..cells.add(e.chatIdHex);
    }
    _pruneExpired(now);
    _notify();
    return true;
  }

  Future<void> _acceptIntent(
      RendezvousPacket e, IntentRecord intent, DateTime now, int nowS, int gen) async {
    final keys = _keys;
    if (keys == null) return;
    final bound = _bindingByNgcPk[e.peerPkHex];
    if (bound == null || bound.sk != intent.fromSkHex) {
      _dropped++;
      return; // the signed key is not the one this NGC peer published
    }
    if (_blockedSk.contains(intent.fromSkHex)) {
      _dropped++;
      return;
    }
    final inRate = _intentsInByNgcPk.putIfAbsent(e.peerPkHex, () => []);
    inRate.removeWhere((t) => now.difference(t) > const Duration(hours: 1));
    if (inRate.length >= NearbyService.maxIntentsInPerHour) {
      _dropped++;
      return;
    }
    inRate.add(now);  // reserved before the async open (burst-safe)
    final body = await intent.open(keys, nowS);
    if (body == null || !_live(gen) || !_joinedChatIds.contains(e.chatIdHex)) {
      _dropped++;
      return;
    }
    // Replay protection: one card per nonce, for as long as it is valid.
    if (_seenIncomingNonces.containsKey(body.nonceHex)) {
      _dropped++;
      return;
    }
    _seenIncomingNonces[body.nonceHex] =
        DateTime.fromMillisecondsSinceEpoch(body.exp * 1000, isUtc: true);
    final fromName = _peers[intent.fromSkHex]?.name ?? '';
    _incoming.add(IncomingIntent(
      fromSkHex: intent.fromSkHex,
      fromName: fromName,
      address: body.address,
      nonceHex: body.nonceHex,
      message: body.message,
      receivedAt: now,
    ));
    _notify();
  }
}
