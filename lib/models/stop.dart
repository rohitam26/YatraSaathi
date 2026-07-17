import 'package:flutter/foundation.dart';
import 'alarm_config.dart';
import 'contact_checkin_config.dart';

/// Represents a single stop along a journey.
@immutable
class Stop {
  Stop({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 500.0,
    required this.order,
    this.isFinalDestination = false,
    this.isReached = false,
    this.reachedAt,
    this.alarmConfig = const AlarmConfig(),
    List<ContactCheckInConfig>? contacts,
  }) : contacts = List.unmodifiable(contacts ?? const <ContactCheckInConfig>[]),
       assert(id.isNotEmpty, 'Stop id cannot be empty'),
       assert(name.isNotEmpty, 'Stop name cannot be empty'),
       assert(
         latitude >= -90.0 && latitude <= 90.0,
         'Latitude must be between -90 and 90 degrees',
       ),
       assert(
         longitude >= -180.0 && longitude <= 180.0,
         'Longitude must be between -180 and 180 degrees',
       ),
       assert(radiusMeters > 0, 'Radius in meters must be positive'),
       assert(order >= 0, 'Stop order must be non-negative');

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final int order;
  final bool isFinalDestination;
  final bool isReached;
  final DateTime? reachedAt;
  final AlarmConfig alarmConfig;
  final List<ContactCheckInConfig> contacts;

  /// Returns true if coordinates fall within valid geographic boundaries.
  static bool areCoordinatesValid(double lat, double lon) {
    return lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0;
  }

  Stop copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    int? order,
    bool? isFinalDestination,
    bool? isReached,
    DateTime? reachedAt,
    AlarmConfig? alarmConfig,
    List<ContactCheckInConfig>? contacts,
  }) {
    return Stop(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      order: order ?? this.order,
      isFinalDestination: isFinalDestination ?? this.isFinalDestination,
      isReached: isReached ?? this.isReached,
      reachedAt: reachedAt ?? this.reachedAt,
      alarmConfig: alarmConfig ?? this.alarmConfig,
      contacts: contacts ?? this.contacts,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
      'order': order,
      'isFinalDestination': isFinalDestination,
      'isReached': isReached,
      'reachedAt': reachedAt?.toIso8601String(),
      'alarmConfig': alarmConfig.toJson(),
      'contacts': contacts.map((c) => c.toJson()).toList(),
    };
  }

  factory Stop.fromJson(Map<String, dynamic> json) {
    return Stop(
      id: json['id'] as String,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 500.0,
      order: json['order'] as int? ?? 0,
      isFinalDestination: json['isFinalDestination'] as bool? ?? false,
      isReached: json['isReached'] as bool? ?? false,
      reachedAt: json['reachedAt'] != null
          ? DateTime.tryParse(json['reachedAt'] as String)
          : null,
      alarmConfig: json['alarmConfig'] != null
          ? AlarmConfig.fromJson(json['alarmConfig'] as Map<String, dynamic>)
          : const AlarmConfig(),
      contacts: (json['contacts'] as List<dynamic>?)
          ?.map(
            (c) => ContactCheckInConfig.fromJson(c as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Stop &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          radiusMeters == other.radiusMeters &&
          order == other.order &&
          isFinalDestination == other.isFinalDestination &&
          isReached == other.isReached &&
          reachedAt == other.reachedAt &&
          alarmConfig == other.alarmConfig &&
          listEquals(contacts, other.contacts);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    latitude,
    longitude,
    radiusMeters,
    order,
    isFinalDestination,
    isReached,
    reachedAt,
    alarmConfig,
    Object.hashAll(contacts),
  );
}
