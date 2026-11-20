import 'package:flutter/foundation.dart';

/// Configuration for arrival alerts and alarms at an individual stop.
@immutable
class AlarmConfig {
  const AlarmConfig({
    this.soundEnabled = true,
    this.soundName = 'Default Chime',
    this.vibrationEnabled = true,
    this.volume = 1.0,
    this.repeatUntilDismissed = true,
    this.snoozeDurationMinutes = 5,
    this.repeatIntervalSeconds = 30,
    this.maxRepeats = 3,
    this.gradualVolumeRampUp = false,
    this.isDismissed = false,
    this.isSnoozed = false,
    this.snoozedUntil,
  }) : assert(snoozeDurationMinutes > 0, 'Snooze duration must be positive'),
       assert(repeatIntervalSeconds > 0, 'Repeat interval must be positive'),
       assert(maxRepeats >= 0, 'Max repeats cannot be negative'),
       assert(volume >= 0.0 && volume <= 1.0, 'Volume must be between 0.0 and 1.0');

  /// Creates a standard default alarm configuration.
  factory AlarmConfig.standard() => const AlarmConfig();

  final bool soundEnabled;
  final String soundName;
  final bool vibrationEnabled;
  final double volume;
  final bool repeatUntilDismissed;
  final int snoozeDurationMinutes;
  final int repeatIntervalSeconds;
  final int maxRepeats;
  final bool gradualVolumeRampUp;
  final bool isDismissed;
  final bool isSnoozed;
  final DateTime? snoozedUntil;

  AlarmConfig copyWith({
    bool? soundEnabled,
    String? soundName,
    bool? vibrationEnabled,
    double? volume,
    bool? repeatUntilDismissed,
    int? snoozeDurationMinutes,
    int? repeatIntervalSeconds,
    int? maxRepeats,
    bool? gradualVolumeRampUp,
    bool? isDismissed,
    bool? isSnoozed,
    DateTime? snoozedUntil,
  }) {
    return AlarmConfig(
      soundEnabled: soundEnabled ?? this.soundEnabled,
      soundName: soundName ?? this.soundName,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      volume: volume ?? this.volume,
      repeatUntilDismissed: repeatUntilDismissed ?? this.repeatUntilDismissed,
      snoozeDurationMinutes:
          snoozeDurationMinutes ?? this.snoozeDurationMinutes,
      repeatIntervalSeconds:
          repeatIntervalSeconds ?? this.repeatIntervalSeconds,
      maxRepeats: maxRepeats ?? this.maxRepeats,
      gradualVolumeRampUp: gradualVolumeRampUp ?? this.gradualVolumeRampUp,
      isDismissed: isDismissed ?? this.isDismissed,
      isSnoozed: isSnoozed ?? this.isSnoozed,
      snoozedUntil: snoozedUntil ?? this.snoozedUntil,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'soundEnabled': soundEnabled,
      'soundName': soundName,
      'vibrationEnabled': vibrationEnabled,
      'volume': volume,
      'repeatUntilDismissed': repeatUntilDismissed,
      'snoozeDurationMinutes': snoozeDurationMinutes,
      'repeatIntervalSeconds': repeatIntervalSeconds,
      'maxRepeats': maxRepeats,
      'gradualVolumeRampUp': gradualVolumeRampUp,
      'isDismissed': isDismissed,
      'isSnoozed': isSnoozed,
      'snoozedUntil': snoozedUntil?.toIso8601String(),
    };
  }

  factory AlarmConfig.fromJson(Map<String, dynamic> json) {
    return AlarmConfig(
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      soundName: json['soundName'] as String? ?? 'Default Chime',
      vibrationEnabled: json['vibrationEnabled'] as bool? ?? true,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      repeatUntilDismissed: json['repeatUntilDismissed'] as bool? ?? true,
      snoozeDurationMinutes: json['snoozeDurationMinutes'] as int? ?? 5,
      repeatIntervalSeconds: json['repeatIntervalSeconds'] as int? ?? 30,
      maxRepeats: json['maxRepeats'] as int? ?? 3,
      gradualVolumeRampUp: json['gradualVolumeRampUp'] as bool? ?? false,
      isDismissed: json['isDismissed'] as bool? ?? false,
      isSnoozed: json['isSnoozed'] as bool? ?? false,
      snoozedUntil: json['snoozedUntil'] != null
          ? DateTime.tryParse(json['snoozedUntil'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlarmConfig &&
          runtimeType == other.runtimeType &&
          soundEnabled == other.soundEnabled &&
          soundName == other.soundName &&
          vibrationEnabled == other.vibrationEnabled &&
          volume == other.volume &&
          repeatUntilDismissed == other.repeatUntilDismissed &&
          snoozeDurationMinutes == other.snoozeDurationMinutes &&
          repeatIntervalSeconds == other.repeatIntervalSeconds &&
          maxRepeats == other.maxRepeats &&
          gradualVolumeRampUp == other.gradualVolumeRampUp &&
          isDismissed == other.isDismissed &&
          isSnoozed == other.isSnoozed &&
          snoozedUntil == other.snoozedUntil;

  @override
  int get hashCode => Object.hash(
    soundEnabled,
    soundName,
    vibrationEnabled,
    volume,
    repeatUntilDismissed,
    snoozeDurationMinutes,
    repeatIntervalSeconds,
    maxRepeats,
    gradualVolumeRampUp,
    isDismissed,
    isSnoozed,
    snoozedUntil,
  );
}
