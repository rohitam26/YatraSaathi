import 'dart:collection';

/// Calculates smoothed, realistic Estimated Time of Arrival (ETA) for STOP Vanthachu.
///
/// Addresses realistic transit dynamics:
/// - Uses a rolling average velocity window to avoid fluctuating ETAs during signals or stops.
/// - Caps anomalous GPS velocity spikes.
/// - Applies an intelligent fallback transit speed (e.g. 30 km/h = 8.33 m/s) when a vehicle
///   is temporarily stopped at a junction or station platform.
class EtaCalculator {
  EtaCalculator({
    this.sampleWindowSize = 10,
    this.defaultTransitSpeedMps = 8.33, // ~30 km/h
  }) : assert(sampleWindowSize >= 1, 'Sample window size must be at least 1'),
       assert(defaultTransitSpeedMps > 0, 'Default transit speed must be positive');

  final int sampleWindowSize;
  final double defaultTransitSpeedMps;
  final Queue<double> _speedSamples = Queue<double>();

  /// Clears historical speed samples.
  void reset() {
    _speedSamples.clear();
  }

  /// Ingests a new speed sample (in meters per second).
  void addSpeedSample(double? speedMps) {
    if (speedMps == null || speedMps < 0.0 || speedMps > 150.0 || speedMps.isNaN) {
      return;
    }
    _speedSamples.addLast(speedMps);
    while (_speedSamples.length > sampleWindowSize) {
      _speedSamples.removeFirst();
    }
  }

  /// Returns smoothed velocity in meters per second.
  double get smoothedSpeedMps {
    if (_speedSamples.isEmpty) {
      return defaultTransitSpeedMps;
    }
    final sum = _speedSamples.reduce((a, b) => a + b);
    final avg = sum / _speedSamples.length;
    // When halted or creeping (< 0.8 m/s ~ 3 km/h), fallback to reasonable transit speed
    if (avg < 0.8) {
      return defaultTransitSpeedMps;
    }
    return avg;
  }

  /// Calculates remaining transit duration to target stop.
  Duration calculateEta({
    required double distanceMeters,
    double? currentSpeedMps,
  }) {
    if (distanceMeters <= 0.0) {
      return Duration.zero;
    }

    if (currentSpeedMps != null && currentSpeedMps > 0.0) {
      addSpeedSample(currentSpeedMps);
    }

    final effectiveSpeed = smoothedSpeedMps.clamp(1.0, 150.0);
    final seconds = distanceMeters / effectiveSpeed;
    return Duration(seconds: seconds.round());
  }

  /// Calculates arrival timestamp at target stop.
  DateTime calculateEstimatedArrival({
    required double distanceMeters,
    double? currentSpeedMps,
    DateTime? referenceTime,
  }) {
    final now = referenceTime ?? DateTime.now();
    final eta = calculateEta(
      distanceMeters: distanceMeters,
      currentSpeedMps: currentSpeedMps,
    );
    return now.add(eta);
  }

  /// Formats duration into user-friendly text (e.g. "< 1 min", "14 min", "1 hr 12 min").
  static String formatEta(Duration? duration) {
    if (duration == null) return '--';
    if (duration.inSeconds < 60) {
      return '< 1 min';
    }
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours == 0) {
      return '$minutes min';
    }
    if (minutes == 0) {
      return '$hours hr';
    }
    return '$hours hr $minutes min';
  }
}
