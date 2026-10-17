import 'geohash.dart';

/// Which rendezvous cells to be in, given a position fix (plan §3.1).
///
/// Pure function of (fix, previous plan state): no I/O, no clock beyond the
/// fix count, so every rule is unit-testable.
///
/// * primary precision 5 (≈ 4.9 km), overflow precision 6;
/// * join set = primary cell + the neighbours whose nearest edge is within
///   [edgeDistanceM] of the position, capped at [maxCells] (closest first);
/// * hysteresis: a cell is left only after [leaveAfterMisses] consecutive
///   fixes outside the join set;
/// * overflow: a primary cell reported full adds the precision-6 cell of the
///   position; the primary cell stays wanted (it is retried by the native
///   back-off) until the overflow is cleared.
class GeocellPlanner {
  GeocellPlanner({
    this.primaryPrecision = 5,
    this.overflowPrecision = 6,
    this.edgeDistanceM = 750,
    this.maxCells = 4,
    this.leaveAfterMisses = 2,
  });

  final int primaryPrecision;
  final int overflowPrecision;
  final double edgeDistanceM;
  final int maxCells;
  final int leaveAfterMisses;

  final Map<String, int> _misses = <String, int>{};
  final Set<String> _joined = <String>{};
  final Set<String> _full = <String>{};

  /// Cells currently planned (joined or joining).
  Set<String> get cells => Set.unmodifiable(_joined);

  /// The primary cell of the last fix.
  String? primaryCell;

  /// A cell refused us because it is full: adds the overflow cell on the
  /// next [plan].
  void markFull(String cell) => _full.add(cell);

  void clearFull(String cell) => _full.remove(cell);

  /// The transport refused the join outright: forget the cell so the next
  /// [plan] asks for it again.
  void dropped(String cell) {
    _joined.remove(cell);
    _misses.remove(cell);
  }

  /// Forget everything (stop / account switch).
  void reset() {
    _misses.clear();
    _joined.clear();
    _full.clear();
    primaryCell = null;
  }

  /// The cells the position wants right now, before hysteresis.
  List<String> wantedFor(double latitude, double longitude) {
    final primary = Geohash.encode(latitude, longitude, primaryPrecision);
    final candidates = <({String cell, double distance})>[];
    for (final n in Geohash.neighbours(primary)) {
      final d = Geohash.bounds(n).distanceFromM(latitude, longitude);
      if (d <= edgeDistanceM) candidates.add((cell: n, distance: d));
    }
    candidates.sort((a, b) => a.distance.compareTo(b.distance));
    final wanted = <String>[primary];
    for (final c in candidates) {
      if (wanted.length >= maxCells) break;
      wanted.add(c.cell);
    }
    if (_full.contains(primary)) {
      final overflow = Geohash.encode(latitude, longitude, overflowPrecision);
      if (!wanted.contains(overflow)) {
        if (wanted.length >= maxCells) wanted.removeLast();
        wanted.insert(1, overflow);
      }
    }
    return wanted;
  }

  /// Applies one fix. Returns the cells to join and to leave now.
  GeocellPlan plan(double latitude, double longitude) {
    final wanted = wantedFor(latitude, longitude);
    primaryCell = wanted.first;
    final wantedSet = wanted.toSet();
    final join = <String>[];
    final leave = <String>[];
    for (final c in wanted) {
      _misses.remove(c);
      if (_joined.add(c)) join.add(c);
    }
    for (final c in _joined.toList()) {
      if (wantedSet.contains(c)) continue;
      final misses = (_misses[c] ?? 0) + 1;
      _misses[c] = misses;
      if (misses >= leaveAfterMisses) {
        _joined.remove(c);
        _misses.remove(c);
        _full.remove(c);
        leave.add(c);
      }
    }
    return GeocellPlan(join: join, leave: leave, wanted: wanted);
  }

  /// Everything currently joined, to be left (stop).
  List<String> leaveAll() {
    final all = _joined.toList();
    reset();
    return all;
  }
}

class GeocellPlan {
  const GeocellPlan(
      {required this.join, required this.leave, required this.wanted});
  final List<String> join;
  final List<String> leave;

  /// The full wanted set, primary first.
  final List<String> wanted;
}
