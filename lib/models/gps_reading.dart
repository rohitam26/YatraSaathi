import 'package:flutter/foundation.dart';
import 'stop.dart';

/// Represents a raw or processed GPS location sample.
@immutable
class GpsReading {
  const GpsReading({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
    this.speedMps,
    this.bearingDegrees,
    this.isDeadReckoning = false,
  }) : assert(
         latitude >= -90.0 && latitude <= 90.0,
         'Latitude must be between -90 and 90 degrees',
       ),
       assert(
         longitude >= -180.0 && longitude <= 180.0,
         'Longitude must be between -180 and 180 degrees',
       ),
       assert(accuracyMeters >= 0.0, 'Accuracy in meters cannot be negative');

  /// Permissive constructor for raw sensor telemetry allowing domain validators
  /// (e.g. ArrivalDetector, LocationEngine) to evaluate validity without assertion exceptions.
  const GpsReading.raw({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
    this.speedMps,
    this.bearingDegrees,
    this.isDeadReckoning = false,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime timestamp;
  final double? speedMps;
  final double? bearingDegrees;
  final bool isDeadReckoning;

  bool get hasValidCoordinates =>
      Stop.areCoordinatesValid(latitude, longitude);

  /// Helper to get vehicle speed in kilometers per hour.
  double? get speedKmh => speedMps != null ? speedMps! * 3.6 : null;

  /// Helper to calculate age of this sample relative to a given point in time.
  Duration age({DateTime? referenceTime}) {
    final now = referenceTime ?? DateTime.now();
    return now.difference(timestamp);
  }

  GpsReading copyWith({
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    DateTime? timestamp,
    double? speedMps,
    double? bearingDegrees,
    bool? isDeadReckoning,
  }) {
    return GpsReading(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      timestamp: timestamp ?? this.timestamp,
      speedMps: speedMps ?? this.speedMps,
      bearingDegrees: bearingDegrees ?? this.bearingDegrees,
      isDeadReckoning: isDeadReckoning ?? this.isDeadReckoning,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracyMeters': accuracyMeters,
      'timestamp': timestamp.toIso8601String(),
      'speedMps': speedMps,
      'bearingDegrees': bearingDegrees,
      'isDeadReckoning': isDeadReckoning,
    };
  }

  factory GpsReading.fromJson(Map<String, dynamic> json) {
    return GpsReading(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracyMeters: (json['accuracyMeters'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      speedMps: (json['speedMps'] as num?)?.toDouble(),
      bearingDegrees: (json['bearingDegrees'] as num?)?.toDouble(),
      isDeadReckoning: (json['isDeadReckoning'] as bool?) ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GpsReading &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          accuracyMeters == other.accuracyMeters &&
          timestamp == other.timestamp &&
          speedMps == other.speedMps &&
          bearingDegrees == other.bearingDegrees &&
          isDeadReckoning == other.isDeadReckoning;

  @override
  int get hashCode => Object.hash(
    latitude,
    longitude,
    accuracyMeters,
    timestamp,
    speedMps,
    bearingDegrees,
    isDeadReckoning,
  );
}
