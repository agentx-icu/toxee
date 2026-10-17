import 'dart:typed_data';

import 'package:tim2tox_dart/service/rendezvous_transport.dart';

/// What the nearby state machine needs from the wire. The production
/// implementation forwards to tim2tox's [RendezvousTransport]; tests supply a
/// fake and never load the native library.
abstract class NearbyTransport {
  Stream<RendezvousEvent> get events;

  /// 1 accepted, 0 refused, 2 already present.
  int join(Uint8List seed, {required String name, required String nick});
  bool leave(String chatIdHex);
  int leaveAll();

  /// 1 sent, 0 not sent, -1 too large, -2 unknown peer, -3 unknown cell.
  int send(String chatIdHex, Uint8List payload, {String? peerPkHex});
  int peerCount(String chatIdHex);
  int dhtAnnounceCapableCount();
}

class RendezvousNearbyTransport implements NearbyTransport {
  RendezvousNearbyTransport(this._inner);
  final RendezvousTransport _inner;

  @override
  Stream<RendezvousEvent> get events => _inner.events;
  @override
  int join(Uint8List seed, {required String name, required String nick}) =>
      _inner.join(seed, name: name, nick: nick);
  @override
  bool leave(String chatIdHex) => _inner.leave(chatIdHex);
  @override
  int leaveAll() => _inner.leaveAll();
  @override
  int send(String chatIdHex, Uint8List payload, {String? peerPkHex}) =>
      _inner.send(chatIdHex, payload, peerPkHex: peerPkHex);
  @override
  int peerCount(String chatIdHex) => _inner.peerCount(chatIdHex);
  @override
  int dhtAnnounceCapableCount() => _inner.dhtAnnounceCapableCount();
}
