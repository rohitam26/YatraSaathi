import 'package:flutter/foundation.dart';
import '../models/arrival_event.dart';
import '../models/gps_reading.dart';
import '../models/journey.dart';
import '../models/stop.dart';
import 'distance_calculator.dart';

/// Rule-based deterministic arrival detection engine for STOP Vanthachu.
///
/// Ensures high-reliability arrival alerts by validating:
/// 1. Active stop existence and sequence verification.
/// 2. Duplicate-event suppression per stop.
/// 3. Coordinate validity (range bounds, NaN/infinity rejection, Null Island filter).
/// 4. Temporal freshness & future timestamp clock-skew detection.
/// 5. GPS accuracy threshold (absolute and relative to stop radius).
/// 6. Coordinate-jump / teleportation anomaly rejection.
/// 7. Geographic boundaries and Haversine distance within arrival radius.
/// 8. Moving vehicle transit pass-through speed gating (prevents false alarms on express bypasses).
/// 9. Repeated consecutive consistent samples (never triggers on single reading).
/// 10. Minimum dwell time within the arrival zone.
class ArrivalDetector {
  ArrivalDetector({
    this.distanceCalculator = const HaversineDistanceCalculator(),
    this.maxAcceptableAccuracyMeters = 80.0,
    this.maxSampleAge = const Duration(seconds: 45),
    this.consecutiveReadingsRequired = 2,
    this.minDwellTime = const Duration(seconds: 4),
    this.maxArrivalSpeedMps = 12.5, // ~45 km/h
    this.maxPhysicallyPossibleSpeedMps, // Optional teleportation jump threshold (e.g. 80.0 m/s ~ 288 km/h)
    this.allowNullIsland = false,
  }) : assert(
         maxAcceptableAccuracyMeters > 0,
         'Accuracy threshold must be positive',
       ),
       assert(
         consecutiveReadingsRequired >= 2,
         'Consecutive readings required must be at least 2 to prevent single-sample anomalies',
       ),
       assert(
         maxArrivalSpeedMps > 0,
         'Max arrival speed must be positive',
       );

  final HaversineDistanceCalculator distanceCalculator;
  final double maxAcceptableAccuracyMeters;
  final Duration maxSampleAge;
  final int consecutiveReadingsRequired;
  final Duration minDwellTime;
  final double maxArrivalSpeedMps;
  final double? maxPhysicallyPossibleSpeedMps;
  final bool allowNullIsland;

  final Set<String> _handledStopIds = <String>{};
  final List<GpsReading> _insideRadiusSamples = <GpsReading>[];
  String? _monitoredStopId;
  DateTime? _firstInsideTimestamp;
  GpsReading? _lastValidReading;

  /// Resets internal buffer state, last valid reading, and handled stop history.
  void reset() {
    _handledStopIds.clear();
    _insideRadiusSamples.clear();
    _monitoredStopId = null;
    _firstInsideTimestamp = null;
    _lastValidReading = null;
  }

  /// Manually mark a stop as handled to suppress further events for it.
  void markStopHandled(String stopId) {
    _handledStopIds.add(stopId);
  }

  /// Evaluates whether a given stop has already been handled.
  bool isStopHandled(String stopId) => _handledStopIds.contains(stopId);

  /// Disambiguates whether the vehicle is closer to another stop in [journey]
  /// while [journey.nextActiveStop] remains active.
  Map<String, dynamic> disambiguateStops({
    required Journey journey,
    required GpsReading reading,
  }) {
    Stop? closestStop;
    double minDistance = double.infinity;

    for (final stop in journey.stops) {
      final d = distanceCalculator.distanceMeters(
        lat1: reading.latitude,
        lon1: reading.longitude,
        lat2: stop.latitude,
        lon2: stop.longitude,
      );
      if (d < minDistance) {
        minDistance = d;
        closestStop = stop;
      }
    }

    final active = journey.nextActiveStop;
    final isTargetingClosest = active != null && closestStop?.id == active.id;

    return {
      'activeStop': active,
      'closestStop': closestStop,
      'distanceToClosestMeters': minDistance,
      'isTargetingClosest': isTargetingClosest,
    };
  }

  /// Evaluates an incoming [reading] against the journey's current [nextActiveStop].
  ///
  /// Provide [evaluationTime] when evaluating historical or simulated streams,
  /// otherwise uses system current time to check sample freshness.
  ArrivalDetectionResult evaluate({
    required Journey journey,
    required GpsReading reading,
    DateTime? evaluationTime,
  }) {
    final now = evaluationTime ?? DateTime.now();

    // 1. Verify that the journey has an active stop
    final activeStop = journey.nextActiveStop;
    if (activeStop == null) {
      return ArrivalDetectionResult(
        status: ArrivalStatus.noActiveStop,
        reading: reading,
        reason: 'Journey is not active or has no remaining active stops.',
      );
    }

    // 2. Synchronize monitored stop buffer
    if (_monitoredStopId != activeStop.id) {
      _monitoredStopId = activeStop.id;
      _insideRadiusSamples.clear();
      _firstInsideTimestamp = null;
    }

    // 3. Duplicate event suppression
    if (activeStop.isReached || _handledStopIds.contains(activeStop.id)) {
      return ArrivalDetectionResult(
        status: ArrivalStatus.alreadyHandled,
        reading: reading,
        activeStop: activeStop,
        reason:
            'Arrival event for stop "${activeStop.name}" was already triggered.',
      );
    }

    // 4. Coordinate validity & NaN/Inf check
    if (reading.latitude.isNaN ||
        reading.longitude.isNaN ||
        reading.latitude.isInfinite ||
        reading.longitude.isInfinite ||
        !reading.hasValidCoordinates) {
      return ArrivalDetectionResult(
        status: ArrivalStatus.locationUncertain,
        reading: reading,
        activeStop: activeStop,
        reason:
            'GPS coordinates out of valid range (lat=${reading.latitude}, lon=${reading.longitude}).',
      );
    }

    // 4b. Null Island (0.0, 0.0) check
    if (!allowNullIsland && reading.latitude == 0.0 && reading.longitude == 0.0) {
      final stopDistFromNullIsland = distanceCalculator.distanceMeters(
        lat1: 0.0,
        lon1: 0.0,
        lat2: activeStop.latitude,
        lon2: activeStop.longitude,
      );
      if (stopDistFromNullIsland > 50000.0) {
        return ArrivalDetectionResult(
          status: ArrivalStatus.locationUncertain,
          reading: reading,
          activeStop: activeStop,
          reason:
              'GPS coordinates returned Null Island (0.0, 0.0) default. Sensor fix uninitialized.',
        );
      }
    }

    // 5. Future timestamp / clock-skew check
    if (reading.timestamp.isAfter(now.add(const Duration(seconds: 15)))) {
      return ArrivalDetectionResult(
        status: ArrivalStatus.locationUncertain,
        reading: reading,
        activeStop: activeStop,
        reason:
            'GPS sample timestamp is in the future (${reading.timestamp.toIso8601String()}). Device clock skew detected.',
      );
    }

    // 5b. Freshness / Stale check
    final sampleAge = now.difference(reading.timestamp);
    if (sampleAge > maxSampleAge) {
      return ArrivalDetectionResult(
        status: ArrivalStatus.locationUncertain,
        reading: reading,
        activeStop: activeStop,
        reason:
            'GPS sample is stale (${sampleAge.inSeconds}s old, max allowed is ${maxSampleAge.inSeconds}s).',
      );
    }

    // 6. Accuracy check (reject noisy / cellar / tower-only GPS)
    if (reading.accuracyMeters > maxAcceptableAccuracyMeters) {
      return ArrivalDetectionResult(
        status: ArrivalStatus.locationUncertain,
        reading: reading,
        activeStop: activeStop,
        reason:
            'GPS accuracy error too high (±${reading.accuracyMeters.toStringAsFixed(1)}m, threshold is ±${maxAcceptableAccuracyMeters.toStringAsFixed(1)}m).',
      );
    }

    // 6b. Accuracy relative to stop radius
    if (reading.accuracyMeters > activeStop.radiusMeters * 1.5) {
      return ArrivalDetectionResult(
        status: ArrivalStatus.locationUncertain,
        reading: reading,
        activeStop: activeStop,
        reason:
            'GPS accuracy circle (±${reading.accuracyMeters.toStringAsFixed(1)}m) is too wide relative to stop radius (${activeStop.radiusMeters.toStringAsFixed(0)}m).',
      );
    }

    // 7. Coordinate-Jump / Teleportation Anomaly Detection
    if (maxPhysicallyPossibleSpeedMps != null && _lastValidReading != null) {
      final jumpDist = distanceCalculator.distanceMeters(
        lat1: _lastValidReading!.latitude,
        lon1: _lastValidReading!.longitude,
        lat2: reading.latitude,
        lon2: reading.longitude,
      );
      final dt = reading.timestamp.difference(_lastValidReading!.timestamp).inMilliseconds.abs() / 1000.0;
      if (dt >= 0.2 && dt <= 180.0) {
        final apparentSpeedMps = jumpDist / dt;
        if (jumpDist > 500.0 && apparentSpeedMps > maxPhysicallyPossibleSpeedMps!) {
          return ArrivalDetectionResult(
            status: ArrivalStatus.locationUncertain,
            reading: reading,
            activeStop: activeStop,
            reason:
                'Anomalous GPS jump detected: moved ${jumpDist.toStringAsFixed(0)}m in ${dt.toStringAsFixed(1)}s (apparent speed ${(apparentSpeedMps * 3.6).toStringAsFixed(0)} km/h). Filtered to prevent false alert.',
          );
        }
      }
    }

    _lastValidReading = reading;

    // 8. Calculate distance to active stop
    final distance = distanceCalculator.distanceMeters(
      lat1: reading.latitude,
      lon1: reading.longitude,
      lat2: activeStop.latitude,
      lon2: activeStop.longitude,
    );

    // 8b. Tunnel Dead-Reckoning Protection:
    // Synthetic projection during GPS blind spots updates proximity and tracking UI,
    // but MUST NEVER trigger confirmed arrival until a true GPS sensor fix is acquired.
    if (reading.isDeadReckoning) {
      return ArrivalDetectionResult(
        status: ArrivalStatus.approaching,
        reading: reading,
        activeStop: activeStop,
        distanceMeters: distance,
        reason:
            'Tunnel dead reckoning projection for "${activeStop.name}". Distance: ${distance.toStringAsFixed(1)}m. Awaiting sensor fix.',
      );
    }

    // 9. Outside arrival radius
    if (distance > activeStop.radiusMeters) {
      // Clear sample buffer only when clearly outside the radius (hysteresis buffer of 15m)
      if (distance > activeStop.radiusMeters + 15.0) {
        _insideRadiusSamples.clear();
        _firstInsideTimestamp = null;
      }

      return ArrivalDetectionResult(
        status: ArrivalStatus.approaching,
        reading: reading,
        activeStop: activeStop,
        distanceMeters: distance,
        reason:
            'Approaching "${activeStop.name}". Distance: ${distance.toStringAsFixed(1)}m (radius: ${activeStop.radiusMeters.toStringAsFixed(0)}m).',
      );
    }

    // 10. Inside radius - accumulate sample and check dwell / consistency
    _insideRadiusSamples.add(reading);
    _firstInsideTimestamp ??= reading.timestamp;

    final dwell = reading.timestamp.difference(_firstInsideTimestamp!);
    final count = _insideRadiusSamples.length;

    debugPrint('[ARRIVAL_EVAL @ ${now.toIso8601String()}] Stop: "${activeStop.name}", Dist: ${distance.toStringAsFixed(1)}m, Acc: ±${reading.accuracyMeters.toStringAsFixed(1)}m, Samples: $count/$consecutiveReadingsRequired, Dwell: ${dwell.inSeconds}s/${minDwellTime.inSeconds}s');

    // 10b. Transit pass-through speed check: express train or non-stopping vehicle
    if (reading.speedMps != null && reading.speedMps! > maxArrivalSpeedMps) {
      return ArrivalDetectionResult(
        status: ArrivalStatus.approaching,
        reading: reading,
        activeStop: activeStop,
        distanceMeters: distance,
        dwellDuration: dwell,
        consecutiveSamples: count,
        reason:
            'Inside "${activeStop.name}" zone, but traveling at ${(reading.speedMps! * 3.6).toStringAsFixed(0)} km/h (exceeds arrival stopping speed of ${(maxArrivalSpeedMps * 3.6).toStringAsFixed(0)} km/h). Transit pass-through detected.',
      );
    }

    // Check if conditions for arrival verification are satisfied
    final hasEnoughSamples = count >= consecutiveReadingsRequired;
    final hasSatisfiedDwell = dwell >= minDwellTime;

    if (hasEnoughSamples && hasSatisfiedDwell) {
      _handledStopIds.add(activeStop.id);

      final event = ArrivalEvent(
        id: 'arrival_${reading.timestamp.millisecondsSinceEpoch}_${activeStop.id}',
        journeyId: journey.id,
        stopId: activeStop.id,
        stopName: activeStop.name,
        timestamp: reading.timestamp,
        triggerReading: reading,
        distanceMeters: distance,
        dwellDuration: dwell,
      );

      return ArrivalDetectionResult(
        status: ArrivalStatus.arrived,
        reading: reading,
        activeStop: activeStop,
        distanceMeters: distance,
        dwellDuration: dwell,
        consecutiveSamples: count,
        reason:
            'Arrival confirmed at "${activeStop.name}"! Distance: ${distance.toStringAsFixed(1)}m, $count consistent readings, dwell: ${dwell.inSeconds}s.',
        event: event,
      );
    }

    // Still validating stability inside the radius
    return ArrivalDetectionResult(
      status: ArrivalStatus.approaching,
      reading: reading,
      activeStop: activeStop,
      distanceMeters: distance,
      dwellDuration: dwell,
      consecutiveSamples: count,
      reason:
          'Inside arrival zone ($count/$consecutiveReadingsRequired readings, dwell: ${dwell.inSeconds}s/${minDwellTime.inSeconds}s). Verifying stability...',
    );
  }
}
