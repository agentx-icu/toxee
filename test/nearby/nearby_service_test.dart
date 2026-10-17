import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/service/rendezvous_transport.dart';
import 'package:toxee/nearby/geohash.dart';
import 'package:toxee/nearby/location_source.dart';
import 'package:toxee/nearby/nearby_crypto.dart';
import 'package:toxee/nearby/nearby_records.dart';
import 'package:toxee/nearby/nearby_service.dart';
import 'package:toxee/nearby/nearby_transport.dart';

/// A wire that records calls and lets the test inject events.
class FakeTransport implements NearbyTransport {
  final StreamController<RendezvousEvent> _events =
      StreamController<RendezvousEvent>.broadcast();
  final List<({Uint8List seed, String name, String nick})> joins = [];
  final List<String> leaves = [];
  final List<({String chat, Uint8List payload, String? peer})> sends = [];
  int joinRc = 1;
  int sendRc = 1;
  int dht = 4;
  int leaveAllCalls = 0;

  @override
  Stream<RendezvousEvent> get events => _events.stream;
  @override
  int join(Uint8List seed, {required String name, required String nick}) {
    joins.add((seed: seed, name: name, nick: nick));
    return joinRc;
  }

  @override
  bool leave(String chatIdHex) {
    leaves.add(chatIdHex);
    return true;
  }

  @override
  int leaveAll() {
    leaveAllCalls++;
    return 0;
  }

  @override
  int send(String chatIdHex, Uint8List payload, {String? peerPkHex}) {
    sends.add((chat: chatIdHex, payload: payload, peer: peerPkHex));
    return sendRc;
  }

  @override
  int peerCount(String chatIdHex) => 0;
  @override
  int dhtAnnounceCapableCount() => dht;

  void emit(RendezvousEvent e) => _events.add(e);
}

class FakeLocation implements LocationSource {
  FakeLocation(this.fix, {this.now, this.fixAge = Duration.zero});
  LocationFix? fix;

  /// Stamps every returned fix with the test clock (a real provider returns
  /// a fresh timestamp); [fixAge] makes it a cached, older fix.
  final DateTime Function()? now;
  Duration fixAge;
  @override
  Future<LocationFix?> currentFix({Duration timeout = const Duration(seconds: 15)}) async {
    final f = fix;
    if (f == null) return null;
    final clock = now;
    if (clock == null) return f;
    return LocationFix(
        latitude: f.latitude, longitude: f.longitude, accuracyM: f.accuracyM, at: clock().subtract(fixAge));
  }
  @override
  Future<bool> openSettings() async => true;
  @override
  Future<LocationPermissionState> permissionState() async => LocationPermissionState.granted;
  @override
  Future<LocationPermissionState> requestPermission() async => LocationPermissionState.granted;
}

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  final (latitude: lat, longitude: lon) = Geohash.decode('wx4g0');
  final fix = LocationFix(latitude: lat, longitude: lon, accuracyM: 20, at: DateTime(2026));
  var nowMs = DateTime.utc(2026, 1, 1, 12).millisecondsSinceEpoch;
  DateTime clock() => DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true);
  int nowS() => nowMs ~/ 1000;

  late FakeTransport wire;
  late FakeLocation location;
  late NearbyService service;
  const myAddress = 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';

  setUp(() {
    wire = FakeTransport();
    location = FakeLocation(fix, now: clock);
    service = NearbyService(
      transport: wire,
      location: location,
      selfAddress: () async => myAddress,
      displayName: () => 'Me',
      clock: clock,
    );
  });

  tearDown(() => service.dispose());

  Future<String> cellChat(String cell) =>
      NearbyService.chatIdForSeed(NearbyCrypto.seedForCell(cell));

  /// A presence record from a fake peer, signed by its own session keys.
  Future<Uint8List> presenceFrom(NearbySessionKeys k, {int seq = 1, String name = 'Bob'}) async =>
      (await PresenceRecord.encode(
          PresenceRecord(
            skHex: k.skHex,
            ekHex: k.ekHex,
            seq: seq,
            exp: nowS() + 180,
            name: name,
            avatarHex: '',
            latE3: (lat * 1000).round() + 2,
            lonE3: (lon * 1000).round(),
            cells: ['wx4g0'],
          ),
          k))!;

  test('start joins the primary cell with the protocol name and a random nick, then broadcasts presence on joined', () async {
    await service.start();
    expect(service.running, isTrue);
    expect(wire.joins.length, 1);
    expect(wire.joins.single.name, 'toxee-nearby/v1/wx4g0');
    expect(wire.joins.single.nick.length, 8);
    expect(wire.joins.single.seed, NearbyCrypto.seedForCell('wx4g0'));
    expect(service.status, NearbyStatus.joining);
    final chat = await cellChat('wx4g0');
    wire.emit(RendezvousJoined(chat, founded: true));
    await settle();
    expect(service.status, NearbyStatus.active);
    expect(wire.sends.length, 1);
    final record = await PresenceRecord.decode(wire.sends.single.payload, nowS());
    expect(record, isNotNull);
    expect(record!.name, 'Me');
    expect(record.cells, ['wx4g0']);
    expect(record.skHex, service.sessionKeys!.skHex);
  });

  test('without a fix the status says so; with no announce-capable nodes it says DHT not ready', () async {
    location.fix = null;
    await service.start();
    expect(service.status, NearbyStatus.noLocation);
    expect(wire.joins, isEmpty);
    await service.stop();
    location.fix = fix;
    wire.dht = 0;
    await service.start();
    expect(service.status, NearbyStatus.dhtNotReady);
  });

  test('presence from a peer appears, replay and rebinding abuse are dropped', () async {
    await service.start();
    final chat = await cellChat('wx4g0');
    wire.emit(RendezvousJoined(chat, founded: false));
    await settle();
    final bob = await NearbyCrypto.newSessionKeys();
    final bobNgc = 'b' * 64;
    wire.emit(RendezvousPacket(chat, peerPkHex: bobNgc, isPrivate: false, payload: await presenceFrom(bob)));
    await settle();
    expect(service.peers.length, 1);
    expect(service.peers.single.name, 'Bob');
    // The peer reports milli-degree coordinates (lat + 0.002°): compare with
    // the distance to that rounded position, not to the exact one.
    final expected = Geohash.distanceM(lat, lon,
        ((lat * 1000).round() + 2) / 1000.0, (lon * 1000).round() / 1000.0);
    expect(service.distanceTo(service.peers.single), closeTo(expected, 1));
    // Same seq again within 10 s: dropped by the rate (1 record / 10 s / peer).
    nowMs += 5000;
    wire.emit(RendezvousPacket(chat, peerPkHex: bobNgc, isPrivate: false, payload: await presenceFrom(bob, seq: 1)));
    await settle();
    expect(service.droppedRecords, 1);
    // After 10 s a replayed seq is still dropped, a newer seq is accepted.
    nowMs += 6000;
    wire.emit(RendezvousPacket(chat, peerPkHex: bobNgc, isPrivate: false, payload: await presenceFrom(bob, seq: 1)));
    await settle();
    expect(service.droppedRecords, 2);
    nowMs += 11000;
    wire.emit(RendezvousPacket(chat, peerPkHex: bobNgc, isPrivate: false, payload: await presenceFrom(bob, seq: 2, name: 'Bobby')));
    await settle();
    expect(service.peers.single.name, 'Bobby');
    // The same NGC peer rotating its session key more than 3 times in 10 min is dropped.
    for (var i = 0; i < 3; i++) {
      nowMs += 11000;
      final k = await NearbyCrypto.newSessionKeys();
      wire.emit(RendezvousPacket(chat, peerPkHex: bobNgc, isPrivate: false, payload: await presenceFrom(k)));
      await settle();
      expect(service.peers.single.skHex, k.skHex);
    }
    nowMs += 11000;
    final k4 = await NearbyCrypto.newSessionKeys();
    final before = service.droppedRecords;
    wire.emit(RendezvousPacket(chat, peerPkHex: bobNgc, isPrivate: false, payload: await presenceFrom(k4)));
    await settle();
    expect(service.droppedRecords, before + 1);
    expect(service.peers.single.skHex, isNot(k4.skHex));
  });

  test('sendIntent seals to the peer, records the pending nonce, and the matching friend application consumes it once', () async {
    await service.start();
    final chat = await cellChat('wx4g0');
    wire.emit(RendezvousJoined(chat, founded: false));
    await settle();
    final bob = await NearbyCrypto.newSessionKeys();
    final bobNgc = 'b' * 64;
    wire.emit(RendezvousPacket(chat, peerPkHex: bobNgc, isPrivate: false, payload: await presenceFrom(bob)));
    await settle();
    final peer = service.peers.single;
    final result = await service.sendIntent(peer, 'hi');
    expect(result, isA<PendingIntent>());
    final pending = result as PendingIntent;
    expect(pending.targetSkHex, bob.skHex);
    expect(pending.targetEkHex, bob.ekHex);
    final sent = wire.sends.last;
    expect(sent.peer, bobNgc);
    // Bob can open it and finds our address + the nonce.
    final record = (await IntentRecord.decode(sent.payload))!;
    final body = (await record.open(bob, nowS()))!;
    expect(body.address, myAddress);
    expect(body.nonceHex, pending.nonceHex);
    // The friend application that carries the nonce matches exactly once.
    final wording = body.requestWording();
    expect(service.matchFriendApplication(wording)?.nonceHex, pending.nonceHex);
    expect(service.matchFriendApplication(wording), isNull);
    expect(service.matchFriendApplication('toxee-nearby:${'0' * 32} x'), isNull);
    expect(service.matchFriendApplication('hello'), isNull);
    // Outgoing rate: 5 per hour.
    for (var i = 0; i < 4; i++) {
      expect(await service.sendIntent(peer, 'again'), isA<PendingIntent>());
    }
    expect(await service.sendIntent(peer, 'too many'), NearbyIntentFailure.rateLimited);
    expect(await service.sendIntent(peer, 'x' * 141), NearbyIntentFailure.messageTooLong);
  });

  test('an incoming intent is accepted only from the NGC peer that published that sk, within the rate', () async {
    await service.start();
    final chat = await cellChat('wx4g0');
    wire.emit(RendezvousJoined(chat, founded: false));
    await settle();
    final alice = await NearbyCrypto.newSessionKeys();
    final aliceNgc = 'c' * 64;
    wire.emit(RendezvousPacket(chat, peerPkHex: aliceNgc, isPrivate: false, payload: await presenceFrom(alice, name: 'Alice')));
    await settle();
    final me = service.sessionKeys!;
    var nonceCounter = 0;
    Future<Uint8List> intentFrom(NearbySessionKeys k, {String msg = 'hey', String? nonce}) async =>
        (await IntentRecord.encode(
          keys: k,
          recipientEkHex: me.ekHex,
          body: IntentBody(
              address: 'f' * 76,
              nonceHex: nonce ?? (++nonceCounter).toRadixString(16).padLeft(32, '0'),
              message: msg,
              exp: nowS() + 600),
        ))!;
    // From the bound peer: accepted.
    wire.emit(RendezvousPacket(chat, peerPkHex: aliceNgc, isPrivate: true, payload: await intentFrom(alice)));
    await settle();
    expect(service.incomingIntents.length, 1);
    expect(service.incomingIntents.single.fromName, 'Alice');
    expect(service.incomingIntents.single.address, 'f' * 76);
    // Same signed key but from a different NGC peer: dropped (binding).
    final before = service.droppedRecords;
    wire.emit(RendezvousPacket(chat, peerPkHex: 'd' * 64, isPrivate: true, payload: await intentFrom(alice)));
    await settle();
    expect(service.droppedRecords, before + 1);
    expect(service.incomingIntents.length, 1);
    // A replayed nonce is dropped even from the right peer.
    final first = service.incomingIntents.single.nonceHex;
    wire.emit(RendezvousPacket(chat, peerPkHex: aliceNgc, isPrivate: true, payload: await intentFrom(alice, nonce: first)));
    await settle();
    expect(service.incomingIntents.length, 1);
    // Rate: 3 per hour per NGC peer (the replay above consumed a slot too).
    wire.emit(RendezvousPacket(chat, peerPkHex: aliceNgc, isPrivate: true, payload: await intentFrom(alice, msg: '2')));
    wire.emit(RendezvousPacket(chat, peerPkHex: aliceNgc, isPrivate: true, payload: await intentFrom(alice, msg: '3')));
    wire.emit(RendezvousPacket(chat, peerPkHex: aliceNgc, isPrivate: true, payload: await intentFrom(alice, msg: '4')));
    await settle();
    expect(service.incomingIntents.length, 2);
    // Block drops the peer and its intents.
    service.block(service.peers.single);
    expect(service.incomingIntents, isEmpty);
    expect(service.peers, isEmpty);
  });

  test('full cell adds the overflow cell; stop leaves everything and forgets peers', () async {
    await service.start();
    final chat = await cellChat('wx4g0');
    wire.emit(RendezvousLeft(chat, reason: 'full'));
    await settle();
    await service.refresh();
    final fine = Geohash.encode(lat, lon, 6);
    expect(wire.joins.map((j) => j.name), contains('toxee-nearby/v1/$fine'));
    await service.stop();
    expect(service.running, isFalse);
    expect(wire.leaveAllCalls, greaterThanOrEqualTo(1), reason: 'every cell is left');
    expect(service.joinedCells, isEmpty);
    expect(service.peers, isEmpty);
  });

  test('the switches gate every read: start refuses, a later off stops without touching the OS', () async {
    var allowed = true;
    var reads = 0;
    final counting = _CountingLocation(fix, () => reads++, now: clock);
    final gated = NearbyService(
      transport: wire,
      location: counting,
      selfAddress: () async => myAddress,
      displayName: () => 'Me',
      clock: clock,
      canRun: () async => allowed,
    );
    addTearDown(gated.dispose);
    allowed = false;
    await gated.start();
    expect(gated.running, isFalse);
    expect(reads, 0);
    allowed = true;
    await gated.start();
    expect(gated.running, isTrue);
    expect(reads, 1);
    allowed = false;
    await gated.refresh();
    expect(gated.running, isFalse, reason: 'switch off mid-session stops before any read');
    expect(reads, 1);
  });

  test('a revoked permission ends the session; a stale fix is not advertised', () async {
    final revocable = _RevocableLocation(fix, now: clock);
    final svc = NearbyService(
      transport: wire,
      location: revocable,
      selfAddress: () async => myAddress,
      displayName: () => 'Me',
      clock: clock,
    );
    addTearDown(svc.dispose);
    await svc.start();
    final chat = await cellChat('wx4g0');
    wire.emit(RendezvousJoined(chat, founded: true));
    await settle();
    expect(wire.sends.length, 1);
    // GPS hiccup (permission still granted): the session survives, but once
    // the last fix is older than the presence TTL nothing is broadcast.
    revocable.fix = null;
    nowMs += 200 * 1000;
    await svc.refresh();
    expect(svc.running, isTrue);
    wire.emit(RendezvousPeer(chat, peerPkHex: 'b' * 64, joined: true));
    await settle();
    expect(wire.sends.length, 1, reason: 'no presence with a 200 s old fix');
    // Permission revoked: the session ends.
    revocable.granted = false;
    await svc.refresh();
    expect(svc.running, isFalse);
    expect(svc.status, NearbyStatus.noLocation);
  });

  test('a stop during the switch read or the key generation leaves nothing behind', () async {
    // 1. canRun answers late and positively, but stop() ran meanwhile: no read.
    final gate = Completer<bool>();
    var reads = 0;
    final counting = _CountingLocation(fix, () => reads++, now: clock);
    final gated = NearbyService(
      transport: wire,
      location: counting,
      selfAddress: () async => myAddress,
      displayName: () => 'Me',
      clock: clock,
      canRun: () => gate.future,
    );
    addTearDown(gated.dispose);
    final starting = gated.start();
    await settle();
    expect(gated.running, isFalse, reason: 'not running until the switches answered');
    await gated.stop();
    gate.complete(true);
    await starting;
    expect(gated.running, isFalse);
    expect(reads, 0);
    expect(wire.joins, isEmpty);
    // 2. A session stopped while its keys were being generated never joins
    //    and never arms its timer.
    final second = service.start();
    await service.stop();
    await second;
    expect(service.running, isFalse);
    expect(wire.joins, isEmpty);
    nowMs += 61 * 1000;
    await settle();
    expect(wire.joins, isEmpty, reason: 'no timer survived the stop');
  });

  test('a cached provider fix older than the presence TTL is not adopted or advertised', () async {
    location.fixAge = const Duration(seconds: 200);
    await service.start();
    expect(service.lastFix, isNull);
    expect(service.status, NearbyStatus.noLocation);
    expect(wire.joins, isEmpty);
    location.fixAge = Duration.zero;
    await service.refresh();
    expect(service.lastFix, isNotNull);
    expect(wire.joins, isNotEmpty);
  });

  test('a peer heard on two cells survives leaving one of them', () async {
    // Stand 55 m from the northern edge of wx4g0: the planner joins the
    // northern neighbour as well.
    final b = Geohash.bounds('wx4g0');
    location.fix = LocationFix(latitude: b.latMax - 0.0005, longitude: lon, accuracyM: 20, at: DateTime(2026));
    await service.start();
    final labels = wire.joins.map((j) => j.name.substring('toxee-nearby/v1/'.length)).toList();
    expect(labels, contains('wx4g0'));
    final neighbourLabel = labels.firstWhere((l) => l != 'wx4g0');
    final primary = await cellChat('wx4g0');
    final neighbour = await cellChat(neighbourLabel);
    wire.emit(RendezvousJoined(primary, founded: false));
    wire.emit(RendezvousJoined(neighbour, founded: false));
    final bob = await NearbyCrypto.newSessionKeys();
    final bobNgc = 'cc' * 32;
    wire.emit(RendezvousPacket(primary, peerPkHex: bobNgc, isPrivate: false, payload: await presenceFrom(bob, seq: 1)));
    await settle();
    nowMs += 11 * 1000; // per-key presence rate
    wire.emit(RendezvousPacket(neighbour, peerPkHex: bobNgc, isPrivate: false, payload: await presenceFrom(bob, seq: 2)));
    await settle();
    expect(service.peers.length, 1, reason: 'one person, two cells');
    expect(service.peers.single.cells, {primary, neighbour});
    // Bob leaves the primary cell: still listed, now addressed on the neighbour.
    wire.emit(RendezvousPeer(primary, peerPkHex: bobNgc, joined: false));
    await settle();
    expect(service.peers.length, 1);
    expect(service.peers.single.cellChatIdHex, neighbour);
    // We lose the neighbour cell too: gone.
    wire.emit(RendezvousLeft(neighbour, reason: 'stale'));
    await settle();
    expect(service.peers, isEmpty);
  });

  test('concurrent say-hi taps cannot exceed five intents per hour', () async {
    await service.start();
    final chat = await cellChat('wx4g0');
    wire.emit(RendezvousJoined(chat, founded: false));
    final bob = await NearbyCrypto.newSessionKeys();
    wire.emit(RendezvousPacket(chat, peerPkHex: 'dd' * 32, isPrivate: false, payload: await presenceFrom(bob)));
    await settle();
    final peer = service.peers.single;
    final results = await Future.wait(List.generate(7, (_) => service.sendIntent(peer, 'hi')));
    expect(results.whereType<PendingIntent>().length, 5);
    expect(results.where((r) => r == NearbyIntentFailure.rateLimited).length, 2);
    // A failed send gives its slot back.
    wire.sendRc = 0;
    nowMs += 3600 * 1000 + 1;
    expect(await service.sendIntent(peer, 'again'), NearbyIntentFailure.peerGone);
    wire.sendRc = 1;
    expect(await service.sendIntent(peer, 'again'), isA<PendingIntent>());
  });

  test('a failing cell is reported as unavailable until a join succeeds', () async {
    await service.start();
    final chat = await cellChat('wx4g0');
    wire.emit(RendezvousLeft(chat, reason: 'failed'));
    await settle();
    expect(service.status, NearbyStatus.cellUnavailable);
    wire.emit(RendezvousJoined(chat, founded: true));
    await settle();
    expect(service.status, NearbyStatus.active);
  });

  test('concurrent starts share one start; a quick stop + start restarts at once', () async {
    await Future.wait([service.start(), service.start(), service.start()]);
    expect(service.running, isTrue);
    expect(wire.joins.length, 1, reason: 'one session, one join');
    await service.stop();
    final cancelled = service.start();
    await service.stop();
    await service.start(); // begins its own session, not queued behind the cancelled one
    await cancelled;
    expect(service.running, isTrue);
    expect(wire.joins.length, 2);
    // A refresh racing dispose never notifies a disposed notifier.
    final refreshing = service.refresh();
    service.dispose();
    await refreshing;
    service = NearbyService(
      transport: wire,
      location: location,
      selfAddress: () async => myAddress,
      displayName: () => 'Me',
      clock: clock,
    ); // for tearDown
  });

  test('the same broadcast arriving through two cells records both cells', () async {
    final b = Geohash.bounds('wx4g0');
    location.fix = LocationFix(latitude: b.latMax - 0.0005, longitude: lon, accuracyM: 20, at: DateTime(2026));
    await service.start();
    final labels = wire.joins.map((j) => j.name.substring('toxee-nearby/v1/'.length)).toList();
    final primary = await cellChat('wx4g0');
    final neighbour = await cellChat(labels.firstWhere((l) => l != 'wx4g0'));
    wire.emit(RendezvousJoined(primary, founded: false));
    wire.emit(RendezvousJoined(neighbour, founded: false));
    final bob = await NearbyCrypto.newSessionKeys();
    final bobNgc = 'ee' * 32;
    final bytes = await presenceFrom(bob, seq: 1);
    // Identical bytes, milliseconds apart (the sender's one broadcast).
    wire.emit(RendezvousPacket(primary, peerPkHex: bobNgc, isPrivate: false, payload: bytes));
    wire.emit(RendezvousPacket(neighbour, peerPkHex: bobNgc, isPrivate: false, payload: bytes));
    await settle();
    expect(service.peers.single.cells, {primary, neighbour});
    expect(service.droppedRecords, 0, reason: 'a copy is not a replay');
    // A cell we left between arrival and verification is not restored.
    nowMs += 11 * 1000;
    final later = presenceFrom(bob, seq: 2);
    wire.emit(RendezvousPacket(neighbour, peerPkHex: bobNgc, isPrivate: false, payload: await later));
    wire.emit(RendezvousLeft(neighbour, reason: 'stale'));
    await settle();
    expect(service.peers.single.cells, {primary});
    expect(service.peers.single.cellChatIdHex, primary);
  });

  test('an intent right after the presence expired is still accepted (binding outlives the card)', () async {
    await service.start();
    final chat = await cellChat('wx4g0');
    wire.emit(RendezvousJoined(chat, founded: false));
    final alice = await NearbyCrypto.newSessionKeys();
    final aliceNgc = 'ab' * 32;
    wire.emit(RendezvousPacket(chat, peerPkHex: aliceNgc, isPrivate: false, payload: await presenceFrom(alice)));
    await settle();
    expect(service.peers.length, 1);
    nowMs += 181 * 1000; // the presence record expired
    expect(service.peers, isEmpty);
    final me = service.sessionKeys!;
    final intent = (await IntentRecord.encode(
      keys: alice,
      recipientEkHex: me.ekHex,
      body: IntentBody(address: 'f' * 76, nonceHex: '7' * 32, message: 'still here', exp: nowS() + 600),
    ))!;
    wire.emit(RendezvousPacket(chat, peerPkHex: aliceNgc, isPrivate: true, payload: intent));
    await settle();
    expect(service.incomingIntents.length, 1);
  });

  test('a restart during an outstanding position read takes its own fix at once', () async {
    final gate = Completer<LocationFix?>();
    var reads = 0;
    LocationFix fresh() => LocationFix(latitude: lat, longitude: lon, accuracyM: 20, at: clock());
    final slow = _GatedLocation(() { reads++; return reads == 1 ? gate.future : Future.value(fresh()); });
    final svc = NearbyService(
      transport: wire,
      location: slow,
      selfAddress: () async => myAddress,
      displayName: () => 'Me',
      clock: clock,
    );
    addTearDown(svc.dispose);
    final first = svc.start(); // blocks in currentFix()
    await settle();
    expect(reads, 1);
    await svc.stop();
    await svc.start(); // pause/resume: must not be blocked by the old read
    expect(svc.running, isTrue);
    expect(reads, 2, reason: 'the new session read the OS itself');
    expect(svc.lastFix, isNotNull);
    expect(wire.joins, isNotEmpty);
    gate.complete(fresh()); // the old read lands: ignored
    await first;
    await settle();
    expect(wire.joins.length, 1);
  });
}

class _CountingLocation extends FakeLocation {
  _CountingLocation(super.fix, this.onRead, {super.now});
  final void Function() onRead;
  @override
  Future<LocationFix?> currentFix({Duration timeout = const Duration(seconds: 15)}) {
    onRead();
    return super.currentFix(timeout: timeout);
  }
}

class _RevocableLocation extends FakeLocation {
  _RevocableLocation(super.fix, {super.now});
  bool granted = true;
  @override
  Future<LocationPermissionState> permissionState() async =>
      granted ? LocationPermissionState.granted : LocationPermissionState.deniedForever;
}

class _GatedLocation implements LocationSource {
  _GatedLocation(this.read);
  final Future<LocationFix?> Function() read;
  @override
  Future<LocationFix?> currentFix({Duration timeout = const Duration(seconds: 15)}) => read();
  @override
  Future<bool> openSettings() async => true;
  @override
  Future<LocationPermissionState> permissionState() async => LocationPermissionState.granted;
  @override
  Future<LocationPermissionState> requestPermission() async => LocationPermissionState.granted;
}
