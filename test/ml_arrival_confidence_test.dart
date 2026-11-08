import 'package:flutter_test/flutter_test.dart';
import 'package:pathsaathi/services/arrival_confidence_ml.dart';

void main() {
  group('ArrivalConfidenceEstimator ML and Fallback Suite', () {
    test('produces high confidence score (>=0.70) when dwelling inside radius with good fix', () {
      final score = ArrivalConfidenceEstimator.estimateConfidence(
        distanceMeters: 40.0,
        radiusMeters: 500.0,
        accuracyMeters: 10.0,
        sampleAge: const Duration(seconds: 2),
        speedMps: 0.5,
        consecutiveSamples: 3,
        dwellDuration: const Duration(seconds: 15),
      );

      expect(score.score, greaterThanOrEqualTo(0.70));
      expect(score.isHighConfidence, isTrue);
      expect(score.percentage, greaterThanOrEqualTo(70));
      expect(score.summary, contains('Sustained presence confirmed'));
      expect(score.isExperimental, isTrue);
    });

    test('produces low confidence (<0.50) when vehicle is far outside stop radius', () {
      final score = ArrivalConfidenceEstimator.estimateConfidence(
        distanceMeters: 1200.0,
        radiusMeters: 500.0,
        accuracyMeters: 15.0,
        sampleAge: const Duration(seconds: 3),
        speedMps: 18.0,
        consecutiveSamples: 0,
        dwellDuration: Duration.zero,
      );

      expect(score.score, lessThan(0.50));
      expect(score.isHighConfidence, isFalse);
      expect(score.summary, contains('outside boundary'));
    });

    test('penalizes confidence during express transit fly-bys (high speed, zero dwell)', () {
      final score = ArrivalConfidenceEstimator.estimateConfidence(
        distanceMeters: 100.0,
        radiusMeters: 500.0,
        accuracyMeters: 12.0,
        sampleAge: const Duration(seconds: 2),
        speedMps: 25.0, // 90 km/h transit pass-through
        consecutiveSamples: 1,
        dwellDuration: const Duration(seconds: 1),
      );

      expect(score.isHighConfidence, isFalse);
      expect(score.score, lessThan(0.70));
    });

    test('penalizes confidence when GPS accuracy is degraded (cell tower fix)', () {
      final score = ArrivalConfidenceEstimator.estimateConfidence(
        distanceMeters: 80.0,
        radiusMeters: 500.0,
        accuracyMeters: 150.0, // High horizontal error (cell tower / multipath)
        sampleAge: const Duration(seconds: 5),
        speedMps: 1.0,
        consecutiveSamples: 1,
        dwellDuration: const Duration(seconds: 1),
      );

      expect(score.isHighConfidence, isFalse);
    });

    test('handles invalid stop radius safely without throwing', () {
      final score = ArrivalConfidenceEstimator.estimateConfidence(
        distanceMeters: 50.0,
        radiusMeters: 0.0,
        accuracyMeters: 10.0,
        sampleAge: Duration.zero,
        speedMps: 0.0,
        consecutiveSamples: 0,
        dwellDuration: Duration.zero,
      );

      expect(score.score, equals(0.0));
      expect(score.isHighConfidence, isFalse);
    });

    test('ruleBasedFallback produces proportional confidence based on distance and dwell', () {
      // Well inside with dwell
      final insideScore = ArrivalConfidenceEstimator.ruleBasedFallback(
        distanceMeters: 100.0,
        radiusMeters: 500.0,
        consecutiveSamples: 3,
        dwellDuration: const Duration(seconds: 12),
      );
      expect(insideScore.score, greaterThanOrEqualTo(0.70));
      expect(insideScore.isHighConfidence, isTrue);

      // Outside radius
      final outsideScore = ArrivalConfidenceEstimator.ruleBasedFallback(
        distanceMeters: 800.0,
        radiusMeters: 500.0,
        consecutiveSamples: 0,
        dwellDuration: Duration.zero,
      );
      expect(outsideScore.score, lessThan(0.50));
      expect(outsideScore.isHighConfidence, isFalse);
    });
  });
}
