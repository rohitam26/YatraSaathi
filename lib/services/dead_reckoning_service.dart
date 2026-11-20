import 'dart:math' as math;
import '../models/gps_reading.dart';

/// Dead Reckoning projection engine for tunnel and dead-zone transit navigation.
///
/// In underground metro passages, railway tunnels, and dense terrain, GPS satellite
/// reception degrades or cuts out completely. This engine projects estimated vehicle
/// position along its last confirmed trajectory vector (velocity and bearing) for up
/// to 180 seconds, ensuring smooth proximity monitoring without false arrival alerts.
class DeadReckoningEngine {
  DeadReckoningEngine({
    this.minDropoutDuration = const Duration(seconds: 15),
    this.maxDropoutDuration = const Duration(seconds: 180),
  });

  final Duration minDropoutDuration;
  final Duration maxDropoutDuration;

  static const double _earthRadiusMeters = 6371000.0;

  /// Evaluates whether dead reckoning is active and projects current position.
  ///
  /// Returns `null` if GPS signal is fresh (< [minDropoutDuration]), if outage has
  /// exceeded confidence horizon (> [maxDropoutDuration]), or if no prior reading exists.
  GpsReading? projectPosition({
    required GpsReading? lastValidReading,
    DateTime? currentTime,
  }) {
    if (lastValidReading == null) return null;

    final now = currentTime ?? DateTime.now();
    final elapsed = now.difference(lastValidReading.timestamp);

    // 1. Fresh signal: No dead-reckoning projection required
    if (elapsed < minDropoutDuration) {
      return null;
    }

    // 2. Outage exceeded confidence threshold: dead reckoning terminates
    if (elapsed > maxDropoutDuration) {
      return null;
    }

    final elapsedSeconds = elapsed.inMilliseconds / 1000.0;
    final speed = lastValidReading.speedMps ?? 0.0;
    final bearing = lastValidReading.bearingDegrees;

    // If stationary or bearing unavailable, hold position with inflated uncertainty
    if (speed < 1.0 || bearing == null) {
      final inflatedAccuracy = (lastValidReading.accuracyMeters + (elapsedSeconds * 0.4))
          .clamp(10.0, 150.0);
      return GpsReading(
        latitude: lastValidReading.latitude,
        longitude: lastValidReading.longitude,
        accuracyMeters: inflatedAccuracy,
        timestamp: now,
        speedMps: 0.0,
        bearingDegrees: bearing,
        isDeadReckoning: true,
      );
    }

    // 3. Project along bearing vector using Great-Circle forward geodesy
    final distanceMeters = speed * elapsedSeconds;
    final angularDistance = distanceMeters / _earthRadiusMeters;
    final bearingRad = bearing * (math.pi / 180.0);

    final lat1Rad = lastValidReading.latitude * (math.pi / 180.0);
    final lon1Rad = lastValidReading.longitude * (math.pi / 180.0);

    final lat2Rad = math.asin(
      math.sin(lat1Rad) * math.cos(angularDistance) +
          math.cos(lat1Rad) * math.sin(angularDistance) * math.cos(bearingRad),
    );

    final lon2Rad = lon1Rad +
        math.atan2(
          math.sin(bearingRad) * math.sin(angularDistance) * math.cos(lat1Rad),
          math.cos(angularDistance) - math.sin(lat1Rad) * math.sin(lat2Rad),
        );

    final projectedLat = lat2Rad * (180.0 / math.pi);
    // Normalize longitude between -180 and 180
    final projectedLon = ((lon2Rad * (180.0 / math.pi)) + 540.0) % 360.0 - 180.0;

    final inflatedAccuracy = (lastValidReading.accuracyMeters + (elapsedSeconds * 0.5))
        .clamp(10.0, 150.0);

    return GpsReading(
      latitude: projectedLat,
      longitude: projectedLon,
      accuracyMeters: inflatedAccuracy,
      timestamp: now,
      speedMps: speed,
      bearingDegrees: bearing,
      isDeadReckoning: true,
    );
  }
}
