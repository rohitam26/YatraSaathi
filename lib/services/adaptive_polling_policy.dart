import 'package:flutter/foundation.dart';

/// Operational tier representing dynamic GPS sensor power management.
enum PollingTier {
  /// < 2 km: Terminal precision mode (3-5s polling, high GPS frequency).
  terminal,

  /// 2 km - 10 km: Intermediate transit mode (10-15s polling).
  intermediate,

  /// > 10 km: Long-distance cruising conservation mode (30-60s polling).
  cruising,

  /// Critical low battery preservation mode (battery <= 15%).
  batteryConservation,
}

/// Computes optimal location polling intervals based on distance to upcoming stop,
/// vehicle velocity, and battery preservation constraints.
@immutable
class AdaptivePollingPolicy {
  const AdaptivePollingPolicy({
    this.terminalThresholdMeters = 2000.0,
    this.intermediateThresholdMeters = 10000.0,
    this.terminalIntervalSeconds = 3,
    this.intermediateIntervalSeconds = 15,
    this.cruisingIntervalSeconds = 45,
    this.longCruisingIntervalSeconds = 60,
    this.lowBatteryThresholdPercent = 15,
  });

  final double terminalThresholdMeters;
  final double intermediateThresholdMeters;
  final int terminalIntervalSeconds;
  final int intermediateIntervalSeconds;
  final int cruisingIntervalSeconds;
  final int longCruisingIntervalSeconds;
  final int lowBatteryThresholdPercent;

  /// Calculates the recommended polling interval in seconds.
  int calculateIntervalSeconds({
    required double distanceMeters,
    double? speedMps,
    int? batteryLevelPercent,
    bool batterySaverActive = false,
  }) {
    final isLowBattery = batterySaverActive ||
        (batteryLevelPercent != null &&
            batteryLevelPercent <= lowBatteryThresholdPercent);

    // 1. Terminal Approach (< 2 km): High accuracy is critical for arrival detection
    if (distanceMeters <= terminalThresholdMeters) {
      if (isLowBattery) {
        return 5; // Slight back-off for critical battery
      }
      return terminalIntervalSeconds; // 3 seconds
    }

    // 2. Intermediate Approach (2 km - 10 km)
    if (distanceMeters <= intermediateThresholdMeters) {
      if (isLowBattery) {
        return 25;
      }
      // If moving at high speed (> 100 km/h ~ 27.8 m/s), poll more frequently
      if (speedMps != null && speedMps > 27.8) {
        return 10;
      }
      return intermediateIntervalSeconds; // 15 seconds
    }

    // 3. Long-Distance Cruising (> 10 km)
    if (isLowBattery) {
      return 90; // High battery savings during long transit
    }

    if (distanceMeters > 30000.0) {
      // Greater than 30 km away
      return longCruisingIntervalSeconds; // 60 seconds
    }

    return cruisingIntervalSeconds; // 45 seconds
  }

  /// Resolves the corresponding [PollingTier] for telemetry and user display.
  PollingTier resolveTier({
    required double distanceMeters,
    int? batteryLevelPercent,
    bool batterySaverActive = false,
  }) {
    final isLowBattery = batterySaverActive ||
        (batteryLevelPercent != null &&
            batteryLevelPercent <= lowBatteryThresholdPercent);

    if (isLowBattery && distanceMeters > terminalThresholdMeters) {
      return PollingTier.batteryConservation;
    }
    if (distanceMeters <= terminalThresholdMeters) {
      return PollingTier.terminal;
    }
    if (distanceMeters <= intermediateThresholdMeters) {
      return PollingTier.intermediate;
    }
    return PollingTier.cruising;
  }
}
