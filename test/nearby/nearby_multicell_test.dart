import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/service/rendezvous_transport.dart';
import 'package:toxee/nearby/geohash.dart';
import 'package:toxee/nearby/location_source.dart';
import 'package:toxee/nearby/nearby_crypto.dart';
import 'package:toxee/nearby/nearby_records.dart';
import 'package:toxee/nearby/nearby_service.dart';

import 'nearby_service_test.dart' show FakeLocation, FakeTransport, settle;

class _CellTransport extends FakeTransport {
  final peerByCell = <String, String>{};

  @override
  int send(String chatIdHex, Uint8List payload, {String? peerPkHex}) {
    if (peerPkHex != null && peerByCell[chatIdHex] != peerPkHex) return -2;
    return super.send(chatIdHex, payload, peerPkHex: peerPkHex);
  }
}

void main() {
  late DateTime now;
  final bounds = Geohash.bounds('wx4g0');
  final center = Geohash.decode('wx4g0');
  final primaryKey = 'a' * 64;
  final neighbourKey = 'b' * 64;
  late _CellTransport wire;
  late NearbyService service;
  late String primary;
  late String neighbour;
  late List<String> cells;
  late NearbySessionKeys bob;

  Future<Uint8List> presence({int seq = 1, String name = 'Bob'}) async =>
      (await PresenceRecord.encode(
        PresenceRecord(
          skHex: bob.skHex,
          ekHex: bob.ekHex,
          seq: seq,
          exp: now.millisecondsSinceEpoch ~/ 1000 + 180,
          name: name,
          avatarHex: '',
          latE3: (bounds.latMax * 1000).round(),
          lonE3: (center.longitude * 1000).round(),
          cells: cells,
        ),
        bob,
      ))!;

  Future<void> advertise(String cell, String key, Uint8List bytes) async {
    wire.emit(
      RendezvousPacket(cell, peerPkHex: key, isPrivate: false, payload: bytes),
    );
    await settle();
  }

  setUp(() async {
    now = DateTime.utc(2026, 11, 12, 12);
    wire = _CellTransport();
    service = NearbyService(
      transport: wire,
      location: FakeLocation(
        LocationFix(
          latitude: bounds.latMax - 0.0005,
          longitude: center.longitude,
          accuracyM: 20,
          at: now,
        ),
      ),
      selfAddress: () async => 'a' * 76,
      displayName: () => 'Me',
      clock: () => now,
    );
    await service.start();
    cells = wire.joins.map((j) => j.name.split('/').last).toList()..sort();
    primary = await NearbyService.chatIdForSeed(
      NearbyCrypto.seedForCell('wx4g0'),
    );
    neighbour = await NearbyService.chatIdForSeed(
      NearbyCrypto.seedForCell(cells.firstWhere((c) => c != 'wx4g0')),
    );
    wire.peerByCell[primary] = primaryKey;
    wire.peerByCell[neighbour] = neighbourKey;
    wire.emit(RendezvousJoined(primary, founded: false));
    wire.emit(RendezvousJoined(neighbour, founded: false));
    await settle();
    bob = await NearbyCrypto.newSessionKeys();
  });

  tearDown(() => service.dispose());

  test(
    'identical presence from different group keys retains both routes',
    () async {
      final bytes = await presence();
      await advertise(primary, primaryKey, bytes);
      await advertise(neighbour, neighbourKey, bytes);
      expect(service.peers.single.cells, {primary, neighbour});
      expect(service.droppedRecords, 0);

      wire.emit(RendezvousPeer(primary, peerPkHex: primaryKey, joined: false));
      await settle();
      expect(service.peers.single.cells, {neighbour});
      expect(
        await service.sendIntent(service.peers.single, 'Hi'),
        isA<PendingIntent>(),
      );
      expect(wire.sends.last.peer, neighbourKey);
    },
  );

  test('peer exit falls back to the surviving cells own group key', () async {
    await advertise(primary, primaryKey, await presence());
    await advertise(neighbour, neighbourKey, await presence(seq: 2));
    wire.emit(
      RendezvousPeer(neighbour, peerPkHex: neighbourKey, joined: false),
    );
    await settle();
    expect(service.peers.single.cellChatIdHex, primary);
    expect(
      await service.sendIntent(service.peers.single, 'Hi'),
      isA<PendingIntent>(),
    );
    expect(wire.sends.last.peer, primaryKey);
  });

  test(
    'a lost local cell also falls back to the surviving cells key',
    () async {
      await advertise(primary, primaryKey, await presence());
      await advertise(neighbour, neighbourKey, await presence(seq: 2));
      wire.emit(RendezvousLeft(neighbour, reason: 'stale'));
      await settle();
      expect(service.peers.single.cells, {primary});
      expect(
        await service.sendIntent(service.peers.single, 'Hi'),
        isA<PendingIntent>(),
      );
      expect(wire.sends.last.peer, primaryKey);
    },
  );

  test(
    'conflicting same-sequence presence cannot replace a verified route',
    () async {
      await advertise(primary, primaryKey, await presence());
      await advertise(
        neighbour,
        neighbourKey,
        await presence(name: 'Different'),
      );
      expect(service.peers.single.name, 'Bob');
      expect(service.peers.single.cells, {primary});
      expect(service.droppedRecords, 1);
    },
  );

  test(
    'a group key rebind preserves the old sessions other-cell route',
    () async {
      final oldBob = bob;
      final bytes = await presence();
      await advertise(primary, primaryKey, bytes);
      await advertise(neighbour, neighbourKey, bytes);
      now = now.add(const Duration(seconds: 11));
      bob = await NearbyCrypto.newSessionKeys();
      await advertise(primary, primaryKey, await presence());

      expect(service.peers.length, 2);
      final oldPeer = service.peers.singleWhere((p) => p.skHex == oldBob.skHex);
      expect(oldPeer.cells, {neighbour});
      expect(await service.sendIntent(oldPeer, 'Hi'), isA<PendingIntent>());
      expect(wire.sends.last.peer, neighbourKey);
    },
  );

  test('an older cached payload cannot restore a lost route', () async {
    final bytes = await presence();
    await advertise(primary, primaryKey, bytes);
    await advertise(neighbour, neighbourKey, bytes);
    now = now.add(const Duration(seconds: 11));
    await advertise(neighbour, neighbourKey, await presence(seq: 2));
    wire.emit(RendezvousLeft(primary, reason: 'stale'));
    await settle();
    wire.emit(RendezvousJoined(primary, founded: false));
    await settle();
    now = now.add(const Duration(seconds: 11));
    await advertise(primary, primaryKey, bytes);

    expect(service.peers.single.record.seq, 2);
    expect(service.peers.single.cells, {neighbour});
  });
}
