import 'dart:math' as math;

/// Pure Dart implementation of the Haversine distance algorithm
/// for calculating spherical distance between geographic coordinates.
class HaversineDistanceCalculator {
  const HaversineDistanceCalculator({this.earthRadiusMeters = 6371000.0});

  /// Mean Earth radius in meters. Default is 6,371,000 meters.
  final double earthRadiusMeters;

  /// Validates that latitude is within [-90.0, 90.0] and longitude within [-180.0, 180.0].
  static bool isValidCoordinate(double latitude, double longitude) {
    if (latitude.isNaN || longitude.isNaN) return false;
    if (latitude < -90.0 || latitude > 90.0) return false;
    if (longitude < -180.0 || longitude > 180.0) return false;
    return true;
  }

  /// Calculates the great-circle distance between two points on Earth in meters.
  /// Throws [ArgumentError] if any coordinate is outside valid boundaries.
  double distanceMeters({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    if (!isValidCoordinate(lat1, lon1)) {
      throw ArgumentError(
        'Invalid start coordinates: lat=$lat1, lon=$lon1. Latitude must be in [-90, 90] and longitude in [-180, 180].',
      );
    }
    if (!isValidCoordinate(lat2, lon2)) {
      throw ArgumentError(
        'Invalid destination coordinates: lat=$lat2, lon=$lon2. Latitude must be in [-90, 90] and longitude in [-180, 180].',
      );
    }

    if (lat1 == lat2 && lon1 == lon2) {
      return 0.0;
    }

    final phi1 = lat1 * (math.pi / 180.0);
    final phi2 = lat2 * (math.pi / 180.0);
    final deltaPhi = (lat2 - lat1) * (math.pi / 180.0);
    final deltaLambda = (lon2 - lon1) * (math.pi / 180.0);

    final sinDeltaPhiHalf = math.sin(deltaPhi / 2.0);
    final sinDeltaLambdaHalf = math.sin(deltaLambda / 2.0);

    final a =
        (sinDeltaPhiHalf * sinDeltaPhiHalf) +
        (math.cos(phi1) *
            math.cos(phi2) *
            sinDeltaLambdaHalf *
            sinDeltaLambdaHalf);

    // Guard against floating point roundoff errors where a > 1.0 or a < 0.0
    final clampedA = a.clamp(0.0, 1.0);
    final c = 2.0 * math.atan2(math.sqrt(clampedA), math.sqrt(1.0 - clampedA));

    return earthRadiusMeters * c;
  }
}
