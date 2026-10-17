import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/nearby/geocell_planner.dart';
import 'package:toxee/nearby/geohash.dart';

void main() {
  group('GeocellPlanner', () {
    test('a central position wants only its primary cell', () {
      final p = GeocellPlanner();
      final (latitude: lat, longitude: lon) = Geohash.decode('wx4g0');
      final plan = p.plan(lat, lon);
      expect(plan.wanted, ['wx4g0']);
      expect(plan.join, ['wx4g0']);
      expect(plan.leave, isEmpty);
      expect(p.primaryCell, 'wx4g0');
    });

    test('near an edge the neighbour within 750 m is added, capped at 4 cells', () {
      final p = GeocellPlanner();
      final b = Geohash.bounds('wx4g0');
      // 200 m south of the northern edge, 200 m west of the eastern edge:
      // north, east and north-east neighbours qualify.
      final lat = b.latMax - 200 / 111320;
      final lon = b.lonMax - 200 / (111320 * 0.77);
      final plan = p.plan(lat, lon);
      expect(plan.wanted.first, 'wx4g0');
      expect(plan.wanted.length, lessThanOrEqualTo(4));
      expect(plan.wanted.length, greaterThanOrEqualTo(3));
      // Far from every edge: nothing but the primary.
      final (latitude: clat, longitude: clon) = Geohash.decode('wx4g0');
      expect(GeocellPlanner().plan(clat, clon).wanted, ['wx4g0']);
    });

    test('hysteresis: a cell is left after two consecutive misses', () {
      final p = GeocellPlanner();
      final (latitude: lat0, longitude: lon0) = Geohash.decode('wx4g0');
      p.plan(lat0, lon0);
      final (latitude: lat1, longitude: lon1) = Geohash.decode('wx4g1');
      final first = p.plan(lat1, lon1);
      expect(first.join, contains('wx4g1'));
      expect(first.leave, isEmpty, reason: 'one miss keeps the old cell');
      final second = p.plan(lat1, lon1);
      expect(second.leave, ['wx4g0']);
      expect(p.cells, isNot(contains('wx4g0')));
      // Coming back resets the miss counter.
      p.plan(lat0, lon0);
      final again = p.plan(lat1, lon1);
      expect(again.leave, isEmpty);
    });

    test('overflow: a full primary cell adds the precision-6 cell and keeps the primary', () {
      final p = GeocellPlanner();
      final (latitude: lat, longitude: lon) = Geohash.decode('wx4g0');
      p.plan(lat, lon);
      p.markFull('wx4g0');
      final plan = p.plan(lat, lon);
      final fine = Geohash.encode(lat, lon, 6);
      expect(plan.wanted, ['wx4g0', fine]);
      expect(plan.join, [fine]);
      p.clearFull('wx4g0');
      final cleared = p.plan(lat, lon);
      expect(cleared.wanted, ['wx4g0']);
      expect(cleared.leave, isEmpty); // first miss
      expect(p.plan(lat, lon).leave, [fine]);
    });

    test('leaveAll returns every joined cell and resets', () {
      final p = GeocellPlanner();
      final (latitude: lat, longitude: lon) = Geohash.decode('wx4g0');
      p.plan(lat, lon);
      expect(p.leaveAll(), ['wx4g0']);
      expect(p.cells, isEmpty);
      expect(p.primaryCell, isNull);
    });
  });

  test('a dropped cell is planned again on the next fix', () {
    final p = GeocellPlanner();
    final (latitude: lat, longitude: lon) = Geohash.decode('wx4g0');
    expect(p.plan(lat, lon).join, ['wx4g0']);
    expect(p.plan(lat, lon).join, isEmpty);
    p.dropped('wx4g0');
    expect(p.plan(lat, lon).join, ['wx4g0']);
  });
}
