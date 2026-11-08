import 'package:flutter/foundation.dart';
import 'gps_reading.dart';
import 'stop.dart';

/// Status of the arrival detection evaluation.
enum ArrivalStatus {
  approaching,
  arrived,
  locationUncertain,
  alreadyHandled,
  noActiveStop,
}

/// An immutable record of a confirmed arrival event.
@immutable
class ArrivalEvent {
  const ArrivalEvent({
    required this.id,
    required this.journeyId,
    required this.stopId,
    required this.stopName,
    required this.timestamp,
    required this.triggerReading,
    required this.distanceMeters,
    required this.dwellDuration,
    this.isDuplicate = false,
  });

  final String id;
  final String journeyId;
  final String stopId;
  final String stopName;
  final DateTime timestamp;
  final GpsReading triggerReading;
  final double distanceMeters;
  final Duration dwellDuration;
  final bool isDuplicate;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'journeyId': journeyId,
      'stopId': stopId,
      'stopName': stopName,
      'timestamp': timestamp.toIso8601String(),
      'triggerReading': triggerReading.toJson(),
      'distanceMeters': distanceMeters,
      'dwellDurationMs': dwellDuration.inMilliseconds,
      'isDuplicate': isDuplicate,
    };
  }

  factory ArrivalEvent.fromJson(Map<String, dynamic> json) {
    return ArrivalEvent(
      id: json['id'] as String,
      journeyId: json['journeyId'] as String,
      stopId: json['stopId'] as String,
      stopName: json['stopName'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      triggerReading: GpsReading.fromJson(
        json['triggerReading'] as Map<String, dynamic>,
      ),
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
      dwellDuration: Duration(
        milliseconds: json['dwellDurationMs'] as int? ?? 0,
      ),
      isDuplicate: json['isDuplicate'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrivalEvent &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          journeyId == other.journeyId &&
          stopId == other.stopId &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(id, journeyId, stopId, timestamp);
}

/// Result returned from evaluating a GPS reading against the active stop.
@immutable
class ArrivalDetectionResult {
  const ArrivalDetectionResult({
    required this.status,
    required this.reading,
    this.activeStop,
    this.distanceMeters,
    this.dwellDuration = Duration.zero,
    this.consecutiveSamples = 0,
    required this.reason,
    this.event,
  });

  final ArrivalStatus status;
  final GpsReading reading;
  final Stop? activeStop;
  final double? distanceMeters;
  final Duration dwellDuration;
  final int consecutiveSamples;
  final String reason;
  final ArrivalEvent? event;

  bool get isArrived => status == ArrivalStatus.arrived;
  bool get isLocationUncertain => status == ArrivalStatus.locationUncertain;
  bool get isApproaching => status == ArrivalStatus.approaching;
  bool get isAlreadyHandled => status == ArrivalStatus.alreadyHandled;
  bool get hasNoActiveStop => status == ArrivalStatus.noActiveStop;

  @override
  String toString() =>
      'ArrivalDetectionResult(status: $status, distance: ${distanceMeters?.toStringAsFixed(1)}m, reason: $reason)';
}
