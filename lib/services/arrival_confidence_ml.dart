import 'dart:math' as math;

/// Represents the output of the arrival confidence evaluation.
class ArrivalConfidenceScore {
  const ArrivalConfidenceScore({
    required this.score,
    required this.isHighConfidence,
    required this.summary,
    required this.featureContributions,
    this.isExperimental = true,
  });

  /// Probability between 0.0 (certain non-arrival) and 1.0 (certain arrival).
  final double score;

  /// True if score is >= 0.70.
  final bool isHighConfidence;

  /// Human-readable explanation of why this confidence level was produced.
  final String summary;

  /// Map of individual feature names to their normalized values and contributions.
  final Map<String, double> featureContributions;

  /// True indicating this score was derived from the experimental ML pipeline.
  final bool isExperimental;

  int get percentage => (score * 100).round().clamp(0, 100);

  @override
  String toString() =>
      'ArrivalConfidenceScore($percentage%, high=$isHighConfidence, summary: $summary)';
}

/// Offline inference engine for transit stop arrival confidence estimation.
///
/// Uses pre-trained weights from `ml/train_arrival_model.py` for zero-latency,
/// privacy-preserving on-device evaluation.
class ArrivalConfidenceEstimator {
  const ArrivalConfidenceEstimator();

  // Learned parameters from trained logistic regression pipeline
  static const double _wDistanceRatio = -1.6840;
  static const double _wAccuracyScore = 0.0351;
  static const double _wFreshnessScore = 0.2989;
  static const double _wSpeedScore = -1.6463;
  static const double _wConsecutiveRatio = 1.5049;
  static const double _wDwellRatio = 2.7258;
  static const double _wSpeedStability = 0.6185;
  static const double _wConvergenceRate = -1.3870;
  static const double _bias = -1.2459;

  /// Estimates arrival confidence given current geospatial and kinematic telemetry.
  static ArrivalConfidenceScore estimateConfidence({
    required double distanceMeters,
    required double radiusMeters,
    required double accuracyMeters,
    required Duration sampleAge,
    required double speedMps,
    required int consecutiveSamples,
    required Duration dwellDuration,
    double recentSpeedVariance = 0.5,
    double convergenceRateMps = 0.0,
  }) {
    if (radiusMeters <= 0.0) {
      return const ArrivalConfidenceScore(
        score: 0.0,
        isHighConfidence: false,
        summary: 'Invalid stop radius.',
        featureContributions: {},
      );
    }

    // 1. Normalized feature extraction
    final distanceRatio = (distanceMeters / radiusMeters).clamp(0.0, 2.0);
    final accuracyScore = (1.0 - (accuracyMeters / 100.0)).clamp(0.0, 1.0);
    final freshnessScore =
        (1.0 - (sampleAge.inSeconds / 60.0)).clamp(0.0, 1.0);
    final speedScore = (speedMps / 30.0).clamp(0.0, 1.0);
    final consecutiveRatio = (consecutiveSamples / 3.0).clamp(0.0, 1.0);
    final dwellRatio = (dwellDuration.inSeconds / 10.0).clamp(0.0, 1.0);
    final speedStability = (1.0 - recentSpeedVariance).clamp(0.0, 1.0);
    final convergenceScore = ((convergenceRateMps + 10.0) / 30.0).clamp(
      0.0,
      1.0,
    );

    // 2. Weighted sum (Logit)
    final z =
        (_wDistanceRatio * distanceRatio) +
        (_wAccuracyScore * accuracyScore) +
        (_wFreshnessScore * freshnessScore) +
        (_wSpeedScore * speedScore) +
        (_wConsecutiveRatio * consecutiveRatio) +
        (_wDwellRatio * dwellRatio) +
        (_wSpeedStability * speedStability) +
        (_wConvergenceRate * convergenceScore) +
        _bias;

    // 3. Sigmoid activation with overflow protection
    final zClamped = z.clamp(-25.0, 25.0);
    final probability = 1.0 / (1.0 + math.exp(-zClamped));

    // 4. Construct human-readable reasoning
    final summaryBuffer = StringBuffer();
    if (distanceMeters <= radiusMeters) {
      summaryBuffer.write('Inside stop radius (${distanceMeters.toStringAsFixed(0)}m). ');
      if (dwellDuration.inSeconds >= 10 && consecutiveSamples >= 3) {
        summaryBuffer.write('Sustained presence confirmed with stable dwell time.');
      } else {
        summaryBuffer.write('Verifying station dwell stability (${dwellDuration.inSeconds}s).');
      }
    } else {
      summaryBuffer.write(
        'Approaching stop (${(distanceMeters - radiusMeters).toStringAsFixed(0)}m outside boundary).',
      );
    }

    final contributions = <String, double>{
      'distance_ratio': distanceRatio,
      'accuracy_score': accuracyScore,
      'freshness_score': freshnessScore,
      'speed_score': speedScore,
      'consecutive_samples': consecutiveRatio,
      'dwell_ratio': dwellRatio,
      'speed_stability': speedStability,
      'convergence_rate': convergenceScore,
    };

    return ArrivalConfidenceScore(
      score: probability,
      isHighConfidence: probability >= 0.70,
      summary: summaryBuffer.toString(),
      featureContributions: contributions,
      isExperimental: true,
    );
  }

  /// Rule-based fallback estimator when telemetry features are sparse or noisy.
  static ArrivalConfidenceScore ruleBasedFallback({
    required double distanceMeters,
    required double radiusMeters,
    required int consecutiveSamples,
    required Duration dwellDuration,
  }) {
    if (radiusMeters <= 0.0) {
      return const ArrivalConfidenceScore(
        score: 0.0,
        isHighConfidence: false,
        summary: 'Invalid stop radius',
        featureContributions: {},
        isExperimental: false,
      );
    }

    double score = 0.0;
    if (distanceMeters <= radiusMeters) {
      // Base score inside radius
      score = 0.40;
      // Bonus for consecutive samples (up to +0.30)
      score += (consecutiveSamples / 3.0).clamp(0.0, 1.0) * 0.30;
      // Bonus for dwell time (up to +0.30)
      score += (dwellDuration.inSeconds / 10.0).clamp(0.0, 1.0) * 0.30;
    } else {
      // Outside radius: degrade linearly up to 2x radius
      final excess = distanceMeters - radiusMeters;
      score = (1.0 - (excess / radiusMeters)).clamp(0.0, 0.35);
    }

    return ArrivalConfidenceScore(
      score: score.clamp(0.0, 1.0),
      isHighConfidence: score >= 0.70,
      summary: score >= 0.70
          ? 'Confirmed presence inside target radius.'
          : 'Vehicle in transit towards target stop.',
      featureContributions: {'distance_meters': distanceMeters},
      isExperimental: false,
    );
  }
}

