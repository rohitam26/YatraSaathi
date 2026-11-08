import 'package:flutter/foundation.dart';
import 'stop.dart';

/// Status of a journey.
enum JourneyStatus { planning, active, paused, completed, cancelled }

/// Represents a multi-stop journey.
@immutable
class Journey {
  Journey({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.status = JourneyStatus.planning,
    List<Stop>? stops,
    this.activeStopIndex = -1,
  }) : stops = List.unmodifiable(_reindexStops(stops ?? const <Stop>[])),
       assert(id.isNotEmpty, 'Journey id cannot be empty'),
       assert(name.isNotEmpty, 'Journey name cannot be empty');

  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final JourneyStatus status;
  final List<Stop> stops;
  final int activeStopIndex;

  /// Helper to ensure orders are sequentially numbered 0, 1, 2...
  static List<Stop> _reindexStops(List<Stop> source) {
    final list = <Stop>[];
    for (int i = 0; i < source.length; i++) {
      final isLast = i == source.length - 1;
      list.add(
        source[i].copyWith(
          order: i,
          isFinalDestination: isLast && source.length > 1,
        ),
      );
    }
    return list;
  }

  /// Returns the current active stop to watch for arrival, or null if none.
  Stop? get nextActiveStop {
    if (status != JourneyStatus.active) return null;
    if (activeStopIndex >= 0 && activeStopIndex < stops.length) {
      return stops[activeStopIndex];
    }
    return null;
  }

  bool get isActive => status == JourneyStatus.active;
  bool get isPaused => status == JourneyStatus.paused;
  bool get isCompleted => status == JourneyStatus.completed;
  bool get isCancelled => status == JourneyStatus.cancelled;
  bool get isPlanning => status == JourneyStatus.planning;
  int get totalStops => stops.length;

  /// Returns all stops that haven't been reached yet.
  List<Stop> get remainingStops => stops.where((s) => !s.isReached).toList();

  /// Starts the journey and activates the first unreached stop.
  Journey start({DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    int nextIndex = stops.indexWhere((s) => !s.isReached);
    if (nextIndex == -1 && stops.isNotEmpty) {
      nextIndex = 0;
    }
    return copyWith(
      status: JourneyStatus.active,
      activeStopIndex: nextIndex,
      updatedAt: timestamp,
    );
  }

  /// Pauses the active journey.
  Journey pause({DateTime? now}) {
    return copyWith(
      status: JourneyStatus.paused,
      updatedAt: now ?? DateTime.now(),
    );
  }

  /// Resumes a paused journey.
  Journey resume({DateTime? now}) {
    return copyWith(
      status: JourneyStatus.active,
      updatedAt: now ?? DateTime.now(),
    );
  }

  /// Marks the journey as completed.
  Journey complete({DateTime? now}) {
    return copyWith(
      status: JourneyStatus.completed,
      activeStopIndex: -1,
      updatedAt: now ?? DateTime.now(),
    );
  }

  /// Cancels the current journey.
  Journey cancel({DateTime? now}) {
    return copyWith(
      status: JourneyStatus.cancelled,
      activeStopIndex: -1,
      updatedAt: now ?? DateTime.now(),
    );
  }

  /// Adds a new stop to the journey.
  Journey addStop(Stop stop, {DateTime? now}) {
    final newStops = List<Stop>.from(stops)..add(stop);
    final reindexed = _reindexStops(newStops);
    return copyWith(
      stops: reindexed,
      updatedAt: now ?? DateTime.now(),
      activeStopIndex:
          activeStopIndex == -1 && status == JourneyStatus.active
              ? 0
              : activeStopIndex,
    );
  }

  /// Removes a stop by id and re-indexes remaining stops.
  Journey removeStop(String stopId, {DateTime? now}) {
    final newStops = stops.where((s) => s.id != stopId).toList();
    final reindexed = _reindexStops(newStops);

    int newActiveIndex = activeStopIndex;
    if (reindexed.isEmpty) {
      newActiveIndex = -1;
    } else if (newActiveIndex >= reindexed.length) {
      newActiveIndex = reindexed.length - 1;
    }

    return copyWith(
      stops: reindexed,
      activeStopIndex: newActiveIndex,
      updatedAt: now ?? DateTime.now(),
    );
  }

  /// Edits an existing stop matching `updatedStop.id`.
  Journey editStop(Stop updatedStop, {DateTime? now}) {
    final newStops = stops.map((s) {
      return s.id == updatedStop.id ? updatedStop : s;
    }).toList();

    return copyWith(
      stops: _reindexStops(newStops),
      updatedAt: now ?? DateTime.now(),
    );
  }

  /// Reorders a stop from oldIndex to newIndex.
  Journey reorderStops(int oldIndex, int newIndex, {DateTime? now}) {
    if (oldIndex < 0 || oldIndex >= stops.length) return this;
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) {
      targetIndex -= 1;
    }
    if (targetIndex < 0 || targetIndex >= stops.length) return this;

    final newStops = List<Stop>.from(stops);
    final item = newStops.removeAt(oldIndex);
    newStops.insert(targetIndex, item);

    final reindexed = _reindexStops(newStops);

    // Recalculate activeStopIndex to follow the active stop id if possible
    int newActiveIndex = activeStopIndex;
    if (activeStopIndex >= 0 && activeStopIndex < stops.length) {
      final activeId = stops[activeStopIndex].id;
      newActiveIndex = reindexed.indexWhere((s) => s.id == activeId);
    }

    return copyWith(
      stops: reindexed,
      activeStopIndex: newActiveIndex,
      updatedAt: now ?? DateTime.now(),
    );
  }

  /// Advances to the next unreached stop, or marks journey completed.
  Journey selectNextActiveStop({DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    final nextIndex = stops.indexWhere(
      (s) => !s.isReached,
      activeStopIndex >= 0 ? activeStopIndex + 1 : 0,
    );

    if (nextIndex == -1) {
      // Check if any unreached stop exists anywhere
      final anyUnreached = stops.indexWhere((s) => !s.isReached);
      if (anyUnreached == -1) {
        return copyWith(
          status: JourneyStatus.completed,
          activeStopIndex: -1,
          updatedAt: timestamp,
        );
      }
      return copyWith(activeStopIndex: anyUnreached, updatedAt: timestamp);
    }

    return copyWith(activeStopIndex: nextIndex, updatedAt: timestamp);
  }

  /// Marks a specific stop as reached and selects the next active stop.
  Journey markStopReached(
    String stopId,
    DateTime reachedTimestamp, {
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final newStops = stops.map((s) {
      if (s.id == stopId) {
        return s.copyWith(isReached: true, reachedAt: reachedTimestamp);
      }
      return s;
    }).toList();

    final updatedJourney = copyWith(stops: newStops, updatedAt: timestamp);
    return updatedJourney.selectNextActiveStop(now: timestamp);
  }

  Journey copyWith({
    String? id,
    String? name,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
    JourneyStatus? status,
    List<Stop>? stops,
    int? activeStopIndex,
  }) {
    return Journey(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      stops: stops ?? this.stops,
      activeStopIndex: activeStopIndex ?? this.activeStopIndex,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'status': status.name,
      'stops': stops.map((s) => s.toJson()).toList(),
      'activeStopIndex': activeStopIndex,
    };
  }

  factory Journey.fromJson(Map<String, dynamic> json) {
    return Journey(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      status: JourneyStatus.values.byName(
        json['status'] as String? ?? 'planning',
      ),
      stops: (json['stops'] as List<dynamic>?)
          ?.map((s) => Stop.fromJson(s as Map<String, dynamic>))
          .toList(),
      activeStopIndex: json['activeStopIndex'] as int? ?? -1,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Journey &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          description == other.description &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          status == other.status &&
          activeStopIndex == other.activeStopIndex &&
          listEquals(stops, other.stops);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    createdAt,
    updatedAt,
    status,
    activeStopIndex,
    Object.hashAll(stops),
  );
}
