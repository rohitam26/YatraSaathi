import '../models/arrival_event.dart';
import '../models/gps_reading.dart';
import '../models/journey.dart';
import 'distance_calculator.dart';

/// Rule-based arrival detection engine.
///
/// Ensures high-reliability arrival alerts by validating:
/// 1. Geographic boundaries and distance within stop radius.
/// 2. GPS accuracy threshold (rejects noisy readings).
/// 3. Temporal freshness (rejects stale readings).
/// 4. Repeated consecutive consistent samples (never triggers on single reading).
/// 5. Minimum dwell time within the arrival zone.
/// 6. Duplicate-event suppression per stop.
class ArrivalDetector {
  ArrivalDetector({
    this.distanceCalculator = const HaversineDistanceCalculator(),
    this.maxAcceptableAccuracyMeters = 50.0,
    this.maxSampleAge = const Duration(seconds: 45),
    this.consecutiveReadingsRequired = 3,
    this.minDwellTime = const Duration(seconds: 10),
  }) : assert(
         maxAcceptableAccuracyMeters > 0,
         'Accuracy threshold must be positive',
       ),
       assert(
         consecutiveReadingsRequired >= 2,
         'Consecutive readings required must be at least 2 to prevent single-sample anomalies',
       );

  final HaversineDistanceCalculator distanceCalculator;
  final double maxAcceptableAccuracyMeters;
  final Duration maxSampleAge;
  final int consecutiveReadingsRequired;
  final Duration minDwellTime;

  final Set<String> _handledStopIds = <String>{};
  final List<GpsReading> _insideRadiusSamples = <GpsReading>[];
  String? _monitoredStopId;
  DateTime? _firstInsideTimestamp;

  /// Resets internal buffer state and handled stop history.
  void reset() {
    _handledStopIds.clear();
    _insideRadiusSamples.clear();
    _monitoredStopId = null;
    _firstInsideTimestamp = null;
  }

  /// Manually mark a stop as handled to suppress further events for it.
  void markStopHandled(String stopId) {
    _handledStopIds.add(stopId);
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

    // 4. Coordinate validity check
    if (!reading.hasValidCoordinates) {
      return ArrivalDetectionResult(
        status: ArrivalStatus.locationUncertain,
        reading: reading,
        activeStop: activeStop,
        reason:
            'GPS coordinates out of valid range (lat=${reading.latitude}, lon=${reading.longitude}).',
      );
    }

    // 5. Freshness / Stale check
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

    // 7. Calculate distance
    final distance = distanceCalculator.distanceMeters(
      lat1: reading.latitude,
      lon1: reading.longitude,
      lat2: activeStop.latitude,
      lon2: activeStop.longitude,
    );

    // 8. Outside arrival radius
    if (distance > activeStop.radiusMeters) {
      // Clear sample buffer because user is outside the radius
      _insideRadiusSamples.clear();
      _firstInsideTimestamp = null;

      return ArrivalDetectionResult(
        status: ArrivalStatus.approaching,
        reading: reading,
        activeStop: activeStop,
        distanceMeters: distance,
        reason:
            'Approaching "${activeStop.name}". Distance: ${distance.toStringAsFixed(1)}m (radius: ${activeStop.radiusMeters.toStringAsFixed(0)}m).',
      );
    }

    // 9. Inside radius - accumulate sample and check dwell / consistency
    _insideRadiusSamples.add(reading);
    _firstInsideTimestamp ??= reading.timestamp;

    final dwell = reading.timestamp.difference(_firstInsideTimestamp!);
    final count = _insideRadiusSamples.length;

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
          'Inside arrival radius (${distance.toStringAsFixed(1)}m). Verifying stability ($count/$consecutiveReadingsRequired samples, ${dwell.inSeconds}s/${minDwellTime.inSeconds}s dwell).',
    );
  }
}
