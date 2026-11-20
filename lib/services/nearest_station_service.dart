import 'package:flutter/foundation.dart';
import '../data/station_database.dart';
import '../models/gps_reading.dart';
import 'distance_calculator.dart';
import 'geocoding_service.dart';

/// Categorization of user's spatial proximity to a transit station.
enum StationProximityType {
  /// User is physically inside or directly adjacent to the station (<= 300m).
  atStation,

  /// User is within a sensible walking/transit radius of the station (<= 3,000m).
  nearStation,

  /// Closest station exists in database, but user is far outside transit vicinity (> 3,000m).
  distantStation,

  /// Location is actively acquiring, GPS disabled, or reading unavailable.
  unavailable,
}

/// Structured result describing nearest transit station and location telemetry.
@immutable
class NearestStationResult {
  const NearestStationResult({
    required this.proximityType,
    this.nearestStation,
    this.distanceMeters,
    this.reading,
    this.statusMessage = '',
    this.isStale = false,
    this.isAccurate = true,
  });

  final StationProximityType proximityType;
  final GeocodedPlace? nearestStation;
  final double? distanceMeters;
  final GpsReading? reading;
  final String statusMessage;
  final bool isStale;
  final bool isAccurate;

  /// True if user is genuinely within immediate or nearby transit radius (<= 3km).
  bool get isNearby =>
      proximityType == StationProximityType.atStation ||
      proximityType == StationProximityType.nearStation;

  /// Distance formatted cleanly for humans: e.g. "150 m" or "2.4 km".
  String get formattedDistance {
    if (distanceMeters == null) return '--';
    if (distanceMeters! < 1000.0) {
      return '${distanceMeters!.toStringAsFixed(0)} m';
    }
    return '${(distanceMeters! / 1000.0).toStringAsFixed(1)} km';
  }

  /// User-facing headline text.
  ///
  /// Never claims user is "Near [Station]" if they are far away.
  String get displayTitle {
    switch (proximityType) {
      case StationProximityType.atStation:
        return 'At ${nearestStation?.name ?? "Station"}';
      case StationProximityType.nearStation:
        return 'Near ${nearestStation?.name ?? "Station"} ($formattedDistance)';
      case StationProximityType.distantStation:
        return 'Nearest: ${nearestStation?.name ?? "Station"} ($formattedDistance away)';
      case StationProximityType.unavailable:
        return statusMessage.isNotEmpty ? statusMessage : 'Finding your location...';
    }
  }

  /// Secondary subtitle with helpful context.
  String get displaySubtitle {
    switch (proximityType) {
      case StationProximityType.atStation:
        return 'You are at this transit station (${nearestStation?.category ?? "Station"}).';
      case StationProximityType.nearStation:
        return 'Within nearby transit zone ($formattedDistance).';
      case StationProximityType.distantStation:
        return 'Outside immediate station vicinity. Closest transit hub is $formattedDistance away.';
      case StationProximityType.unavailable:
        return 'Acquiring high-accuracy satellite fix. Please wait...';
    }
  }

  /// Internal diagnostic string for debugging.
  String get debugTelemetry {
    if (reading == null) return 'GPS: No Fix';
    final acc = '±${reading!.accuracyMeters.toStringAsFixed(1)}m';
    final age = reading!.age();
    final ageStr = age.inSeconds < 60 ? '${age.inSeconds}s ago' : '${age.inMinutes}m ago';
    final coords = '${reading!.latitude.toStringAsFixed(4)}, ${reading!.longitude.toStringAsFixed(4)}';
    return 'GPS: $coords ($acc, $ageStr)';
  }

  factory NearestStationResult.unavailable({String reason = 'Finding your location...'}) {
    return NearestStationResult(
      proximityType: StationProximityType.unavailable,
      statusMessage: reason,
    );
  }
}

/// Service calculating the genuine nearest transit station from real GPS fixes.
///
/// Prevents false "Near Central" defaults by enforcing:
/// 1. Zero hardcoded coordinate fallbacks.
/// 2. Freshness and accuracy checks on GPS fixes.
/// 3. Clear distinction between "At Station", "Near Station", and "Distant Station".
/// 4. Spherical Haversine distance calculations.
class NearestStationService {
  NearestStationService({
    HaversineDistanceCalculator? distanceCalculator,
    this.atStationThresholdMeters = 300.0,
    this.nearStationThresholdMeters = 3000.0, // 3 km
    this.maxAcceptableAccuracyMeters = 150.0,
    this.maxStaleDuration = const Duration(minutes: 2),
  }) : _distanceCalculator = distanceCalculator ?? const HaversineDistanceCalculator();

  final HaversineDistanceCalculator _distanceCalculator;
  final double atStationThresholdMeters;
  final double nearStationThresholdMeters;
  final double maxAcceptableAccuracyMeters;
  final Duration maxStaleDuration;

  /// Calculates nearest station given a live or cached [GpsReading].
  NearestStationResult calculateNearestStation(
    GpsReading? reading, {
    DateTime? referenceTime,
  }) {
    if (reading == null) {
      return NearestStationResult.unavailable(
        reason: 'Finding your location...',
      );
    }

    final now = referenceTime ?? DateTime.now();
    final age = reading.age(referenceTime: now);
    final isStale = age > maxStaleDuration;
    final isAccurate = reading.accuracyMeters <= maxAcceptableAccuracyMeters;

    // Reject uninitialized Null Island coordinates (0.0, 0.0)
    if (reading.latitude.abs() < 0.0001 && reading.longitude.abs() < 0.0001) {
      return NearestStationResult.unavailable(
        reason: 'Location fix unavailable (uninitialized GPS fix).',
      );
    }

    // Degraded accuracy notice
    if (!isAccurate) {
      return NearestStationResult(
        proximityType: StationProximityType.unavailable,
        reading: reading,
        isAccurate: false,
        isStale: isStale,
        statusMessage: 'Location accuracy low (±${reading.accuracyMeters.toStringAsFixed(0)}m). Refining fix...',
      );
    }

    // Find closest station from curated database
    GeocodedPlace? bestStation;
    double minDistance = double.infinity;

    for (final station in LocalStationDatabase.stations) {
      final dist = _distanceCalculator.distanceMeters(
        lat1: reading.latitude,
        lon1: reading.longitude,
        lat2: station.latitude,
        lon2: station.longitude,
      );

      if (dist < minDistance) {
        minDistance = dist;
        bestStation = station;
      }
    }

    if (bestStation == null || minDistance.isInfinite) {
      return NearestStationResult.unavailable(
        reason: 'No cataloged transit stations found.',
      );
    }

    StationProximityType proximity;
    if (minDistance <= atStationThresholdMeters) {
      proximity = StationProximityType.atStation;
    } else if (minDistance <= nearStationThresholdMeters) {
      proximity = StationProximityType.nearStation;
    } else {
      proximity = StationProximityType.distantStation;
    }

    return NearestStationResult(
      proximityType: proximity,
      nearestStation: bestStation,
      distanceMeters: minDistance,
      reading: reading,
      isStale: isStale,
      isAccurate: isAccurate,
    );
  }
}
