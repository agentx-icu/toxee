import 'dart:math' as math;

/// Geohash (base32, standard alphabet) — the geocell key of the nearby
/// protocol (`toxee/nearby/v1`, see doc/plans/LOCATION_AND_NEARBY_PLAN.md
/// §3.1). Pure Dart; no package.
///
/// Precision 5 is ≈ 4.9 km × 4.9 km, precision 6 ≈ 1.2 km × 0.6 km.
class Geohash {
  Geohash._();

  static const String alphabet = '0123456789bcdefghjkmnpqrstuvwxyz';

  static const int maxPrecision = 12;

  /// Mean Earth radius in metres (haversine).
  static const double earthRadiusM = 6371008.8;

  static bool isValid(String hash) {
    if (hash.isEmpty || hash.length > maxPrecision) return false;
    for (final unit in hash.codeUnits) {
      if (!alphabet.codeUnits.contains(unit)) return false;
    }
    return true;
  }

  /// Encodes [latitude]/[longitude] (degrees) with [precision] characters.
  static String encode(double latitude, double longitude, int precision) {
    if (precision < 1 || precision > maxPrecision) {
      throw ArgumentError.value(precision, 'precision', '1..12');
    }
    if (latitude.isNaN || longitude.isNaN || latitude < -90 || latitude > 90) {
      throw ArgumentError('latitude/longitude out of range');
    }
    var lon = longitude;
    // Wrap longitude into [-180, 180).
    lon = ((lon + 180) % 360 + 360) % 360 - 180;
    var latMin = -90.0, latMax = 90.0, lonMin = -180.0, lonMax = 180.0;
    final out = StringBuffer();
    var bit = 0;
    var ch = 0;
    var even = true;
    while (out.length < precision) {
      if (even) {
        final mid = (lonMin + lonMax) / 2;
        if (lon >= mid) {
          ch = (ch << 1) | 1;
          lonMin = mid;
        } else {
          ch = ch << 1;
          lonMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (latitude >= mid) {
          ch = (ch << 1) | 1;
          latMin = mid;
        } else {
          ch = ch << 1;
          latMax = mid;
        }
      }
      even = !even;
      if (++bit == 5) {
        out.write(alphabet[ch]);
        bit = 0;
        ch = 0;
      }
    }
    return out.toString();
  }

  /// The bounding box of [hash].
  static GeohashBounds bounds(String hash) {
    if (!isValid(hash)) throw ArgumentError.value(hash, 'hash', 'not a geohash');
    var latMin = -90.0, latMax = 90.0, lonMin = -180.0, lonMax = 180.0;
    var even = true;
    for (final c in hash.split('')) {
      final idx = alphabet.indexOf(c);
      for (var n = 4; n >= 0; n--) {
        final bit = (idx >> n) & 1;
        if (even) {
          final mid = (lonMin + lonMax) / 2;
          if (bit == 1) {
            lonMin = mid;
          } else {
            lonMax = mid;
          }
        } else {
          final mid = (latMin + latMax) / 2;
          if (bit == 1) {
            latMin = mid;
          } else {
            latMax = mid;
          }
        }
        even = !even;
      }
    }
    return GeohashBounds(
        latMin: latMin, latMax: latMax, lonMin: lonMin, lonMax: lonMax);
  }

  /// Centre of [hash].
  static ({double latitude, double longitude}) decode(String hash) {
    final b = bounds(hash);
    return (
      latitude: (b.latMin + b.latMax) / 2,
      longitude: (b.lonMin + b.lonMax) / 2
    );
  }

  /// The 8 neighbours of [hash] (N, NE, E, SE, S, SW, W, NW), derived by
  /// stepping one cell in each direction from the centre. Cells at the poles
  /// that would leave the valid latitude range are omitted.
  static List<String> neighbours(String hash) {
    final b = bounds(hash);
    final latStep = b.latMax - b.latMin;
    final lonStep = b.lonMax - b.lonMin;
    final (latitude: lat, longitude: lon) = decode(hash);
    final out = <String>[];
    for (final (dLat, dLon) in const [
      (1, 0), (1, 1), (0, 1), (-1, 1), (0, -1 + 0), (-1, 0), (-1, -1), (0, -1), (1, -1)
    ]) {
      final nLat = lat + dLat * latStep;
      final nLon = lon + dLon * lonStep;
      if (nLat < -90 || nLat > 90) continue;
      final h = encode(nLat, nLon, hash.length);
      if (h != hash && !out.contains(h)) out.add(h);
    }
    return out;
  }

  /// Great-circle distance between two points, in metres.
  static double distanceM(
      double lat1, double lon1, double lat2, double lon2) {
    final p1 = _rad(lat1), p2 = _rad(lat2);
    final dp = _rad(lat2 - lat1);
    // Shortest way round across the date line.
    var dlon = (lon2 - lon1) % 360;
    if (dlon > 180) dlon -= 360;
    if (dlon < -180) dlon += 360;
    final dl = _rad(dlon);
    final a = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return 2 * earthRadiusM * math.asin(math.min(1.0, math.sqrt(a)));
  }

  /// Distance from a point inside [hash] to the nearest edge of its cell, in
  /// metres (0 when the point is outside the cell).
  static double distanceToEdgeM(String hash, double latitude, double longitude) {
    final b = bounds(hash);
    if (latitude < b.latMin || latitude > b.latMax ||
        longitude < b.lonMin || longitude > b.lonMax) {
      return 0;
    }
    final toSouth = distanceM(latitude, longitude, b.latMin, longitude);
    final toNorth = distanceM(latitude, longitude, b.latMax, longitude);
    final toWest = distanceM(latitude, longitude, latitude, b.lonMin);
    final toEast = distanceM(latitude, longitude, latitude, b.lonMax);
    return [toSouth, toNorth, toWest, toEast].reduce(math.min);
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}

class GeohashBounds {
  const GeohashBounds({
    required this.latMin,
    required this.latMax,
    required this.lonMin,
    required this.lonMax,
  });
  final double latMin;
  final double latMax;
  final double lonMin;
  final double lonMax;

  bool contains(double latitude, double longitude) {
    final lon = _towards(longitude);
    return latitude >= latMin &&
        latitude <= latMax &&
        lon >= lonMin &&
        lon <= lonMax;
  }

  /// [longitude] shifted by ±360° so it is measured on the box's side of the
  /// date line (the shortest way round).
  double _towards(double longitude) {
    final centre = (lonMin + lonMax) / 2;
    var lon = longitude;
    if (lon - centre > 180) lon -= 360;
    if (centre - lon > 180) lon += 360;
    return lon;
  }

  /// Distance in metres from the point to the nearest edge of the box, 0 when
  /// outside.
  double distanceToEdgeM(double latitude, double longitude) {
    if (!contains(latitude, longitude)) return 0;
    final toSouth = Geohash.distanceM(latitude, longitude, latMin, longitude);
    final toNorth = Geohash.distanceM(latitude, longitude, latMax, longitude);
    final toWest = Geohash.distanceM(latitude, longitude, latitude, lonMin);
    final toEast = Geohash.distanceM(latitude, longitude, latitude, lonMax);
    return [toSouth, toNorth, toWest, toEast].reduce(math.min);
  }

  /// Distance in metres from a point OUTSIDE the box to the box (0 inside).
  double distanceFromM(double latitude, double longitude) {
    if (contains(latitude, longitude)) return 0;
    final clampedLat = latitude.clamp(latMin, latMax);
    final clampedLon = _towards(longitude).clamp(lonMin, lonMax);
    return Geohash.distanceM(latitude, longitude, clampedLat, clampedLon);
  }
}
