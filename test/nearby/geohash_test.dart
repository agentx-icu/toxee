import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/nearby/geohash.dart';

void main() {
  group('Geohash', () {
    test('encodes known vectors', () {
      // Reference values from the public geohash definition.
      expect(Geohash.encode(57.64911, 10.40744, 11), 'u4pruydqqvj');
      expect(Geohash.encode(39.9042, 116.4074, 5), 'wx4g0');
      expect(Geohash.encode(0, 0, 1), 's');
      expect(Geohash.encode(-90, -180, 3), '000');
    });

    test('decode returns the centre of the cell and bounds contain it', () {
      final (latitude: lat, longitude: lon) = Geohash.decode('wx4g0');
      final b = Geohash.bounds('wx4g0');
      expect(b.contains(lat, lon), isTrue);
      expect(Geohash.encode(lat, lon, 5), 'wx4g0');
      // precision 5: ~4.9 km × 4.9 km
      expect(b.latMax - b.latMin, closeTo(0.0439, 0.0005));
      expect(b.lonMax - b.lonMin, closeTo(0.0439, 0.0005));
    });

    test('validity follows the base32 alphabet and length', () {
      expect(Geohash.isValid('wx4g0'), isTrue);
      expect(Geohash.isValid('WX4G0'), isFalse);
      expect(Geohash.isValid('wx4a0'), isFalse);
      expect(Geohash.isValid(''), isFalse);
      expect(Geohash.isValid('a' * 13), isFalse);
    });

    test('neighbours are the eight surrounding cells', () {
      final n = Geohash.neighbours('wx4g0');
      expect(n.length, 8);
      expect(n, isNot(contains('wx4g0')));
      expect(n.toSet().length, 8);
      final (latitude: lat, longitude: lon) = Geohash.decode('wx4g0');
      for (final h in n) {
        final (latitude: nlat, longitude: nlon) = Geohash.decode(h);
        expect(Geohash.distanceM(lat, lon, nlat, nlon), lessThan(8000));
      }
    });

    test('haversine distance matches a known pair', () {
      // Beijing → Shanghai ≈ 1068 km
      expect(Geohash.distanceM(39.9042, 116.4074, 31.2304, 121.4737) / 1000,
          closeTo(1068, 5));
      expect(Geohash.distanceM(1, 1, 1, 1), 0);
    });

    test('distance to edge is 0 outside and positive inside', () {
      final b = Geohash.bounds('wx4g0');
      final (latitude: lat, longitude: lon) = Geohash.decode('wx4g0');
      // At 40° N a precision-5 cell is ~4.9 km tall and ~3.7 km wide, so the
      // centre is ~1.87 km from the nearest (east/west) edge.
      expect(b.distanceToEdgeM(lat, lon), greaterThan(1500));
      expect(b.distanceToEdgeM(lat + 1, lon), 0);
      expect(b.distanceFromM(lat, lon), 0);
      expect(b.distanceFromM(b.latMax + 0.01, lon), closeTo(1113, 20));
    });

    test('rejects invalid input', () {
      expect(() => Geohash.encode(0, 0, 0), throwsArgumentError);
      expect(() => Geohash.encode(91, 0, 5), throwsArgumentError);
      expect(() => Geohash.bounds('WX4G0'), throwsArgumentError);
    });
  });

  test('distances wrap across the date line', () {
    // 179.9°E and 179.9°W are ~22 km apart at the equator, not 40 000 km.
    expect(Geohash.distanceM(0, 179.9, 0, -179.9), closeTo(22260, 100));
    final east = Geohash.bounds(Geohash.encode(0, 179.99, 5));
    expect(east.distanceFromM(0, -179.99), lessThan(5000));
    expect(east.contains(0, 179.99 - 360), isTrue);
  });
}
