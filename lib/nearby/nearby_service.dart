import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:tim2tox_dart/service/rendezvous_transport.dart';

import 'geocell_planner.dart';
import 'geohash.dart';
import 'location_source.dart';
import 'nearby_crypto.dart';
import 'nearby_models.dart';
import 'nearby_records.dart';
import 'nearby_transport.dart';

export 'nearby_models.dart';

part 'nearby_service_inbound.dart';
part 'nearby_service_intents.dart';

/// The nearby state machine (plan §3.1–§3.4): cells ↔ transport, peer table,
/// budgets, intents, nonces. Owns nothing platform-specific: position comes
/// from a [LocationSource], the wire from a [RendezvousTransport], time from
/// [clock]. Everything is foreground-only; [stop] leaves every cell.
class NearbyService extends ChangeNotifier {
  NearbyService({
    required NearbyTransport transport,
    required LocationSource location,
    required Future<String> Function() selfAddress,
    required String Function() displayName,
    String Function()? avatarHex,
    Future<bool> Function()? canRun,
    GeocellPlanner? planner,
    DateTime Function()? clock,
    this.fixInterval = const Duration(seconds: 60),
    this.moveThresholdM = 100,
  })  : _transport = transport,
        _location = location,
        _selfAddress = selfAddress,
        _displayName = displayName,
        _avatarHex = avatarHex ?? (() => ''),
        _canRun = canRun ?? (() async => true),
        _planner = planner ?? GeocellPlanner(),
        _clock = clock ?? DateTime.now;

  final NearbyTransport _transport;
  final LocationSource _location;
  final Future<String> Function() _selfAddress;
  final String Function() _displayName;
  final String Function() _avatarHex;

  /// The account's switches (Location master AND nearby visibility). Checked
  /// by [start] and before EVERY position read, so the "nothing reads the OS
  /// position while the switch is off" guarantee lives in the service itself,
  /// not in whoever started it.
  final Future<bool> Function() _canRun;
  final GeocellPlanner _planner;
  final DateTime Function() _clock;
  final Duration fixInterval;
  final double moveThresholdM;

  // --- limits (protocol / plan §3.4) ---
  static const int presenceIntervalSeconds = 180 ~/ 3; // 60 s cadence
  static const Duration presenceOnPeerJoinMinGap = Duration(seconds: 10);
  static const Duration peerRateWindow = Duration(seconds: 10);
  static const int maxRebindsPer10Min = 3;
  static const int maxIntentsInPerHour = 3;
  static const int maxIntentsOutPerHour = 5;
  static const int maxSeenNonces = 2048;

  NearbyStatus _status = NearbyStatus.idle;
  NearbyStatus get status => _status;
  bool _running = false;
  bool get running => _running;

  /// Session generation: bumped by every [start] and [stop]. Every async
  /// step re-checks `_live(gen)` afterwards, so work that was in flight when
  /// the session stopped (or a new one started) resumes into nothing: no
  /// join, no send, no timer, no OS read (plan §4.6 lifecycle).
  int _gen = 0;
  bool _live(int gen) => _running && gen == _gen;

  NearbySessionKeys? _keys;
  NearbySessionKeys? get sessionKeys => _keys;
  String? _nick;
  int _seq = 0;
  LocationFix? _lastFix;
  DateTime? _lastFixAt;
  LocationFix? get lastFix => _lastFix;
  Timer? _fixTimer;
  StreamSubscription<RendezvousEvent>? _sub;
  /// Generation of the refresh in flight (null when none): a stop() bumps
  /// the generation, so the next session's first refresh is never blocked
  /// by a read the old session still has outstanding.
  int? _fixingGen;

  final Map<String, String> _cellByChatId = <String, String>{};
  final Map<String, String> _chatIdByCell = <String, String>{};
  final Set<String> _joinedChatIds = <String>{};
  final Set<String> _unavailableCells = <String>{};
  Set<String> get joinedCells =>
      _joinedChatIds.map((c) => _cellByChatId[c] ?? c).toSet();

  final Map<String, NearbyPeer> _peers = <String, NearbyPeer>{};
  List<NearbyPeer> get peers {
    _pruneExpired(_clock());
    final list = _peers.values.where((p) => !_blockedSk.contains(p.skHex)).toList();
    final fix = _lastFix;
    if (fix != null) {
      list.sort((a, b) => (distanceTo(a) ?? 0).compareTo(distanceTo(b) ?? 0));
    }
    return list;
  }

  // Bindings and rates are keyed by the toxcore-authenticated NGC peer key.
  final Map<String, ({String sk, String ek})> _bindingByNgcPk = {};
  final Map<String, List<DateTime>> _rebindsByNgcPk = {};
  final Map<String, DateTime> _lastRecordByNgcPk = {};
  // The last accepted presence bytes per NGC key: the same record arrives
  // once per shared cell (identical bytes and seq); copies only add a cell.
  final Map<String, Uint8List> _lastPayloadByNgcPk = {};
  final Map<String, List<DateTime>> _intentsInByNgcPk = {};
  final List<DateTime> _intentsOut = <DateTime>[];
  DateTime? _lastPeerJoinPresence;

  final Map<String, PendingIntent> _pendingByNonce = <String, PendingIntent>{};
  final Map<String, DateTime> _consumedNonces = <String, DateTime>{};
  // Nonces of intents we RECEIVED (replay protection, plan §3.4).
  final Map<String, DateTime> _seenIncomingNonces = <String, DateTime>{};
  final Set<String> _blockedSk = <String>{};
  final List<IncomingIntent> _incoming = <IncomingIntent>[];
  List<IncomingIntent> get incomingIntents => List.unmodifiable(_incoming);
  Map<String, PendingIntent> get pendingIntents => Map.unmodifiable(_pendingByNonce);

  int _dropped = 0;
  int get droppedRecords => _dropped;

  // --- lifecycle --------------------------------------------------------------

  /// Concurrent callers share one start; a [stop] in between cancels it
  /// (the cancelled start exits at its next generation check) and lets the
  /// next [start] begin its own session at once.
  Future<void> start() {
    if (running) return Future<void>.value();
    if (_startFuture != null) return _startFuture!;
    late final Future<void> mine;
    mine = _startImpl().whenComplete(() {
      if (identical(_startFuture, mine)) _startFuture = null;
    });
    return _startFuture = mine;
  }

  Future<void>? _startFuture;

  Future<void> _startImpl() async {
    final before = _gen;
    final allowed = await _canRun();
    if (running || before != _gen || !allowed) return; // stopped / restarted
    final gen = ++_gen;
    _running = true;
    final keys = await NearbyCrypto.newSessionKeys();
    if (!_live(gen)) return;
    _keys = keys;
    _nick = NearbyCrypto.hex(NearbyCrypto.randomBytes(4));
    _seq = 0;
    _setStatus(NearbyStatus.locating);
    _sub ??= _transport.events.listen(_onEvent);
    await _refreshFix();
    if (!_live(gen)) return; // never arm a timer for a stopped session
    _fixTimer?.cancel();
    _fixTimer = Timer.periodic(fixInterval, (_) => unawaited(_refreshFix()));
  }

  /// Leaves every cell, forgets peers, cancels intents. Idempotent.
  Future<void> stop() async {
    _running = false;
    ++_gen;
    _startFuture = null; // a start in flight is cancelled; the next one is new
    _fixTimer?.cancel();
    _fixTimer = null;
    for (final cell in _planner.leaveAll()) {
      final chatId = _chatIdByCell[cell];
      if (chatId != null) _transport.leave(chatId);
    }
    _transport.leaveAll();
    _joinedChatIds.clear();
    _cellByChatId.clear();
    _chatIdByCell.clear();
    _unavailableCells.clear();
    _peers.clear();
    _bindingByNgcPk.clear();
    _rebindsByNgcPk.clear();
    _lastRecordByNgcPk.clear();
    _lastPayloadByNgcPk.clear();
    _intentsInByNgcPk.clear();
    _pendingByNonce.clear();
    _incoming.clear();
    _keys = null;
    _lastFix = null;
    _lastFixAt = null;
    _seenIncomingNonces.clear();
    if (_status != NearbyStatus.idle) _setStatus(NearbyStatus.idle);
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _running = false;
    ++_gen;
    unawaited(_sub?.cancel());
    _sub = null;
    _fixTimer?.cancel();
    super.dispose();
  }

  /// Triggers a position fix now (page opened, resume).
  Future<void> refresh() => _refreshFix();

  Future<void> _refreshFix() async {
    if (!running || _fixingGen == _gen) return;
    final gen = _gen;
    _fixingGen = gen;
    try {
      // The switches may have been turned off since the last tick: no read.
      final allowed = await _canRun();
      if (!_live(gen)) return; // stopped while the switches were read
      if (!allowed) {
        await stop();
        return;
      }
      _pruneExpired(_clock());
      final fix = await _location.currentFix();
      if (!_live(gen)) return;
      if (fix == null) {
        // A revoked permission or a disabled location service ends the
        // session (checklist P2); a transient GPS failure keeps the last fix
        // but stops broadcasting it once it is older than its presence TTL.
        final permission = await _location.permissionState();
        if (!_live(gen)) return;
        if (permission != LocationPermissionState.granted) {
          await stop();
          _setStatus(NearbyStatus.noLocation);
          return;
        }
        if (_lastFix == null) _setStatus(NearbyStatus.noLocation);
        _notify();
        return;
      }
      // A cached provider fix is only as fresh as its own timestamp.
      final now = _clock();
      final age = now.difference(fix.at);
      if (age.inSeconds > NearbyLimits.presenceTtlSeconds) {
        if (_lastFix == null) _setStatus(NearbyStatus.noLocation);
        _notify();
        return;
      }
      final previous = _lastFix;
      _lastFix = fix;
      _lastFixAt = age.isNegative ? now : fix.at;
      final moved = previous == null ||
          Geohash.distanceM(previous.latitude, previous.longitude, fix.latitude,
                  fix.longitude) >=
              moveThresholdM;
      await _applyPlan(fix, gen);
      if (!_live(gen)) return;
      if (moved || _dueForPresence()) await _broadcastPresence();
      if (!_live(gen)) return;
      _notify();
    } finally {
      if (_fixingGen == gen) _fixingGen = null;
    }
  }

  DateTime? _lastPresenceAt;
  bool _dueForPresence() {
    final last = _lastPresenceAt;
    return last == null ||
        _clock().difference(last).inSeconds >= presenceIntervalSeconds;
  }

  Future<void> _applyPlan(LocationFix fix, int gen) async {
    final plan = _planner.plan(fix.latitude, fix.longitude);
    for (final cell in plan.leave) {
      final chatId = _chatIdByCell.remove(cell);
      if (chatId != null) {
        _transport.leave(chatId);
        _cellByChatId.remove(chatId);
        _joinedChatIds.remove(chatId);
        _dropPeersOfCell(chatId);
      }
    }
    for (final cell in plan.join) {
      if (_unavailableCells.contains(cell)) continue;
      final seed = NearbyCrypto.seedForCell(cell);
      final chatId = await chatIdForSeed(seed);
      if (!_live(gen)) return;
      _cellByChatId[chatId] = cell;
      _chatIdByCell[cell] = chatId;
      final rc = _transport.join(seed,
          name: 'toxee-nearby/v1/$cell', nick: _nick ?? 'toxee');
      if (rc == 0) {
        // Refused outright (e.g. transport not ready): forget it so the next
        // fix asks again instead of believing the cell is on its way.
        _cellByChatId.remove(chatId);
        _chatIdByCell.remove(cell);
        _planner.dropped(cell);
      }
    }
    if (_joinedChatIds.isEmpty &&
        (_status == NearbyStatus.locating || _status == NearbyStatus.noLocation)) {
      _setStatus(_transport.dhtAnnounceCapableCount() == 0
          ? NearbyStatus.dhtNotReady
          : NearbyStatus.joining);
    }
  }

  /// The Chat ID (ed25519 public key) of a seed — what the transport reports.
  static Future<String> chatIdForSeed(Uint8List seed) async {
    final kp = await Ed25519().newKeyPairFromSeed(seed);
    final pk = await kp.extractPublicKey();
    return NearbyCrypto.hex(Uint8List.fromList(pk.bytes));
  }

  // --- presence --------------------------------------------------------------

  Future<void> _broadcastPresence() async {
    final keys = _keys;
    final fix = _lastFix;
    final fixAt = _lastFixAt;
    if (keys == null || fix == null || fixAt == null || _joinedChatIds.isEmpty) return;
    final now = _clock();
    final gen = _gen;
    // Never advertise a position older than the record it would carry.
    if (now.difference(fixAt).inSeconds > NearbyLimits.presenceTtlSeconds) return;
    final record = PresenceRecord(
      skHex: keys.skHex,
      ekHex: keys.ekHex,
      seq: ++_seq,
      exp: now.millisecondsSinceEpoch ~/ 1000 + NearbyLimits.presenceTtlSeconds,
      name: _displayName(),
      avatarHex: _avatarHex(),
      latE3: (fix.latitude * 1000).round(),
      lonE3: (fix.longitude * 1000).round(),
      cells: joinedCells.toList()..sort(),
    );
    final bytes = await PresenceRecord.encode(record, keys);
    if (bytes == null || !_live(gen)) return;
    for (final chatId in _joinedChatIds) {
      _transport.send(chatId, bytes);
    }
    _lastPresenceAt = now;
  }

  // --- events -----------------------------------------------------------------

  void _onEvent(RendezvousEvent e) {
    if (!running) return;
    if (!_cellByChatId.containsKey(e.chatIdHex)) return; // not one of ours
    switch (e) {
      case RendezvousJoined():
        _joinedChatIds.add(e.chatIdHex);
        // A successful join clears an earlier "full" / "unavailable" of the
        // same cell, so neither the precision-6 overflow cell nor the
        // unavailable state outlives the recovery.
        final joinedCell = _cellByChatId[e.chatIdHex];
        if (joinedCell != null) {
          _planner.clearFull(joinedCell);
          _unavailableCells.remove(joinedCell);
        }
        // Joined is joined, whatever stage the planner was in (a cell can
        // answer before the first fix's planning finished).
        _setStatus(NearbyStatus.active);
        unawaited(_broadcastPresence());
        _notify();
      case RendezvousLeft():
        _joinedChatIds.remove(e.chatIdHex);
        _dropPeersOfCell(e.chatIdHex);
        if (e.reason == 'full') {
          final cell = _cellByChatId[e.chatIdHex];
          if (cell != null) _planner.markFull(cell);
        } else if (e.reason == 'failed' || e.reason == 'kicked' || e.reason == 'stale') {
          // The native side backs off and retries by itself; the UI only
          // needs to know the cell is not available right now.
          final cell = _cellByChatId[e.chatIdHex];
          if (cell != null) _unavailableCells.add(cell);
          Timer(const Duration(minutes: 10), () => _unavailableCells.remove(cell));
          // Nothing joined and at least one cell failing: say so (plan §3.1
          // "unavailable for 10 min and the UI says so").
          if (_joinedChatIds.isEmpty && _unavailableCells.isNotEmpty) {
            _setStatus(NearbyStatus.cellUnavailable);
          }
        }
        _notify();
      case RendezvousPeer():
        if (e.joined) {
          final last = _lastPeerJoinPresence;
          final now = _clock();
          if (last == null || now.difference(last) >= presenceOnPeerJoinMinGap) {
            _lastPeerJoinPresence = now;
            unawaited(_broadcastPresence());
          }
        } else {
          _forgetNgcPeer(e.peerPkHex, e.chatIdHex);
          _notify();
        }
      case RendezvousPeersChanged():
        _notify();
      case RendezvousFull():
        final cell = _cellByChatId[e.chatIdHex];
        if (cell != null) _planner.markFull(cell);
      case RendezvousPacket():
        unawaited(_onPacket(e));
    }
  }

  /// Bounded state: everything keyed by a peer or a nonce is dropped once
  /// its window passed, so churn and key rotation cannot grow the maps.
  void _pruneExpired(DateTime now) {
    final nowS = now.millisecondsSinceEpoch ~/ 1000;
    _peers.removeWhere((_, p) => p.record.exp <= nowS);
    // A binding outlives the displayed record: an intent may follow a
    // presence that just expired. It goes once the key was silent for an
    // hour (the intent rate window) and has no peer on display.
    _bindingByNgcPk.removeWhere((pk, b) =>
        !_peers.containsKey(b.sk) &&
        now.difference(_lastRecordByNgcPk[pk] ?? now) > const Duration(hours: 1));
    _lastPayloadByNgcPk.removeWhere((pk, _) => !_bindingByNgcPk.containsKey(pk));
    _rebindsByNgcPk.removeWhere((_, l) {
      l.removeWhere((t) => now.difference(t) > const Duration(minutes: 10));
      return l.isEmpty;
    });
    _intentsInByNgcPk.removeWhere((_, l) {
      l.removeWhere((t) => now.difference(t) > const Duration(hours: 1));
      return l.isEmpty;
    });
    _lastRecordByNgcPk.removeWhere(
        (pk, t) => now.difference(t) > const Duration(hours: 1) && !_bindingByNgcPk.containsKey(pk));
    _consumedNonces.removeWhere((_, exp) => exp.isBefore(now));
    _seenIncomingNonces.removeWhere((_, exp) => exp.isBefore(now));
    if (_seenIncomingNonces.length > maxSeenNonces) {
      final byExpiry = _seenIncomingNonces.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final e in byExpiry.take(_seenIncomingNonces.length - maxSeenNonces)) {
        _seenIncomingNonces.remove(e.key);
      }
    }
    _pendingByNonce.removeWhere((_, p) => p.expiresAt.isBefore(now));
  }

  /// notifyListeners for the inbound part file (protected member).
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// A cell is gone for us: peers heard only there disappear, peers also
  /// heard on another joined cell stay (and are addressed there).
  void _dropPeersOfCell(String chatIdHex) {
    _peers.removeWhere((_, p) {
      p.cells.remove(chatIdHex);
      if (p.cells.isEmpty) return true;
      if (p.cellChatIdHex == chatIdHex) p.cellChatIdHex = p.cells.first;
      return false;
    });
  }

  /// An NGC peer left one cell; the same key may still be in another.
  void _forgetNgcPeer(String ngcPk, String chatIdHex) {
    final bound = _bindingByNgcPk[ngcPk];
    if (bound == null) return;
    final peer = _peers[bound.sk];
    if (peer != null) {
      peer.cells.remove(chatIdHex);
      if (peer.cells.isNotEmpty) {
        if (peer.cellChatIdHex == chatIdHex) peer.cellChatIdHex = peer.cells.first;
        return;
      }
      _peers.remove(bound.sk);
    }
    _bindingByNgcPk.remove(ngcPk);
    _lastRecordByNgcPk.remove(ngcPk);
  }

  /// Coarse distance in metres from our last fix to [peer]'s reported cell
  /// position, or null without a fix.
  double? distanceTo(NearbyPeer peer) {
    final fix = _lastFix;
    if (fix == null) return null;
    return Geohash.distanceM(fix.latitude, fix.longitude, peer.record.latitude,
        peer.record.longitude);
  }

  void _setStatus(NearbyStatus s) {
    if (_status == s) return;
    _status = s;
    _notify();
  }
}
