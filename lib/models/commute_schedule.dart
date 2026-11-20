import 'package:flutter/foundation.dart';
import 'journey.dart';
import 'stop.dart';

/// Represents a recurring commute schedule or journey template for daily travelers.
///
/// Enables single-tap initialization of recurring commutes (e.g. Daily Office Commute,
/// Weekend Return, Morning Metro) with pre-configured stops, radii, alarms, and safety contacts.
@immutable
class CommuteSchedule {
  const CommuteSchedule({
    required this.id,
    required this.name,
    required this.sourceName,
    required this.destinationName,
    required this.stops,
    this.daysOfWeek = const [1, 2, 3, 4, 5], // Default: Monday through Friday
    this.departureTime = '08:30',
    this.isFavorite = true,
    this.autoStartReminder = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String sourceName;
  final String destinationName;
  final List<Stop> stops;
  final List<int> daysOfWeek; // 1 = Monday, 7 = Sunday
  final String departureTime; // Format "HH:mm" (24-hour)
  final bool isFavorite;
  final bool autoStartReminder;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Creates a live, actionable [Journey] from this template ready for immediate tracking.
  Journey toJourney({String? customName}) {
    final now = DateTime.now();
    return Journey(
      id: 'journey_${now.millisecondsSinceEpoch}_${id.hashCode.abs()}',
      name: customName ?? name,
      stops: stops.map((s) => s.copyWith(isReached: false, reachedAt: null)).toList(),
      createdAt: now,
      updatedAt: now,
    );
  }

  CommuteSchedule copyWith({
    String? id,
    String? name,
    String? sourceName,
    String? destinationName,
    List<Stop>? stops,
    List<int>? daysOfWeek,
    String? departureTime,
    bool? isFavorite,
    bool? autoStartReminder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CommuteSchedule(
      id: id ?? this.id,
      name: name ?? this.name,
      sourceName: sourceName ?? this.sourceName,
      destinationName: destinationName ?? this.destinationName,
      stops: stops ?? this.stops,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      departureTime: departureTime ?? this.departureTime,
      isFavorite: isFavorite ?? this.isFavorite,
      autoStartReminder: autoStartReminder ?? this.autoStartReminder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'sourceName': sourceName,
      'destinationName': destinationName,
      'stops': stops.map((s) => s.toJson()).toList(),
      'daysOfWeek': daysOfWeek,
      'departureTime': departureTime,
      'isFavorite': isFavorite,
      'autoStartReminder': autoStartReminder,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory CommuteSchedule.fromJson(Map<String, dynamic> json) {
    return CommuteSchedule(
      id: json['id'] as String,
      name: json['name'] as String,
      sourceName: (json['sourceName'] as String?) ?? '',
      destinationName: (json['destinationName'] as String?) ?? '',
      stops: (json['stops'] as List<dynamic>?)
              ?.map((e) => Stop.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <Stop>[],
      daysOfWeek: (json['daysOfWeek'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          const [1, 2, 3, 4, 5],
      departureTime: (json['departureTime'] as String?) ?? '08:30',
      isFavorite: (json['isFavorite'] as bool?) ?? true,
      autoStartReminder: (json['autoStartReminder'] as bool?) ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommuteSchedule &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          sourceName == other.sourceName &&
          destinationName == other.destinationName &&
          departureTime == other.departureTime &&
          isFavorite == other.isFavorite &&
          autoStartReminder == other.autoStartReminder &&
          listEquals(daysOfWeek, other.daysOfWeek) &&
          listEquals(stops, other.stops);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        sourceName,
        destinationName,
        departureTime,
        isFavorite,
        autoStartReminder,
      );
}
