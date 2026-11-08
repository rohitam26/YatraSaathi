import 'package:flutter_test/flutter_test.dart';
import 'package:pathsaathi/models/arrival_event.dart';
import 'package:pathsaathi/models/gps_reading.dart';
import 'package:pathsaathi/models/journey.dart';
import 'package:pathsaathi/models/stop.dart';
import 'package:pathsaathi/services/arrival_detector.dart';

void main() {
  group('ArrivalDetector Rule-based Engine', () {
    late ArrivalDetector detector;
    late Journey testJourney;
    final baseTime = DateTime(2026, 10, 25, 14, 0, 0);

    // Stop at 28.6139, 77.2090 with 500m radius
    final targetStop = Stop(
      id: 'stop_target',
      name: 'Central Station',
      latitude: 28.6139,
      longitude: 77.2090,
      radiusMeters: 500.0,
      order: 0,
    );

    setUp(() {
      detector = ArrivalDetector(
        maxAcceptableAccuracyMeters: 40.0,
        maxSampleAge: const Duration(seconds: 30),
        consecutiveReadingsRequired: 3,
        minDwellTime: const Duration(seconds: 10),
      );

      testJourney = Journey(
        id: 'journey_test',
        name: 'Test Commute',
        createdAt: baseTime,
        updatedAt: baseTime,
        status: JourneyStatus.active,
        stops: [targetStop],
        activeStopIndex: 0,
      );
    });

    test('returns noActiveStop when journey is not active', () {
      final inactiveJourney = testJourney.copyWith(
        status: JourneyStatus.planning,
      );
      final reading = GpsReading(
        latitude: 28.6139,
        longitude: 77.2090,
        accuracyMeters: 10.0,
        timestamp: baseTime,
      );

      final result = detector.evaluate(
        journey: inactiveJourney,
        reading: reading,
        evaluationTime: baseTime,
      );

      expect(result.status, equals(ArrivalStatus.noActiveStop));
      expect(result.hasNoActiveStop, isTrue);
    });

    test('returns locationUncertain when GPS reading is stale', () {
      // Sample is 60 seconds old (threshold is 30s)
      final staleReading = GpsReading(
        latitude: 28.6139,
        longitude: 77.2090,
        accuracyMeters: 10.0,
        timestamp: baseTime.subtract(const Duration(seconds: 60)),
      );

      final result = detector.evaluate(
        journey: testJourney,
        reading: staleReading,
        evaluationTime: baseTime,
      );

      expect(result.status, equals(ArrivalStatus.locationUncertain));
      expect(result.isLocationUncertain, isTrue);
      expect(result.reason, contains('stale'));
    });

    test('returns locationUncertain when GPS accuracy is too noisy', () {
      // Sample accuracy is ±80m (threshold is 40m)
      final noisyReading = GpsReading(
        latitude: 28.6139,
        longitude: 77.2090,
        accuracyMeters: 80.0,
        timestamp: baseTime,
      );

      final result = detector.evaluate(
        journey: testJourney,
        reading: noisyReading,
        evaluationTime: baseTime,
      );

      expect(result.status, equals(ArrivalStatus.locationUncertain));
      expect(result.reason, contains('accuracy'));
    });

    test('returns approaching when position is outside arrival radius', () {
      // ~2.5km away
      final farReading = GpsReading(
        latitude: 28.6350,
        longitude: 77.2200,
        accuracyMeters: 15.0,
        timestamp: baseTime,
      );

      final result = detector.evaluate(
        journey: testJourney,
        reading: farReading,
        evaluationTime: baseTime,
      );

      expect(result.status, equals(ArrivalStatus.approaching));
      expect(result.distanceMeters, greaterThan(500.0));
      expect(result.isArrived, isFalse);
    });

    test('never triggers arrival on a single reading inside radius', () {
      // Exactly at the stop, highly accurate
      final firstInsideReading = GpsReading(
        latitude: 28.6139,
        longitude: 77.2090,
        accuracyMeters: 10.0,
        timestamp: baseTime,
      );

      final result = detector.evaluate(
        journey: testJourney,
        reading: firstInsideReading,
        evaluationTime: baseTime,
      );

      // Must NOT be arrived yet
      expect(result.status, equals(ArrivalStatus.approaching));
      expect(result.isArrived, isFalse);
      expect(result.consecutiveSamples, equals(1));
      expect(result.reason, contains('Verifying stability'));
    });

    test('confirms arrival only after consecutive readings AND minimum dwell time', () {
      // Sample 1 at t=0s
      final r1 = GpsReading(
        latitude: 28.6139,
        longitude: 77.2090,
        accuracyMeters: 10.0,
        timestamp: baseTime,
      );
      final res1 = detector.evaluate(
        journey: testJourney,
        reading: r1,
        evaluationTime: baseTime,
      );
      expect(res1.status, equals(ArrivalStatus.approaching));
      expect(res1.consecutiveSamples, equals(1));

      // Sample 2 at t=5s (consecutive=2, but dwell=5s < 10s)
      final t2 = baseTime.add(const Duration(seconds: 5));
      final r2 = GpsReading(
        latitude: 28.61395,
        longitude: 77.20905,
        accuracyMeters: 12.0,
        timestamp: t2,
      );
      final res2 = detector.evaluate(
        journey: testJourney,
        reading: r2,
        evaluationTime: t2,
      );
      expect(res2.status, equals(ArrivalStatus.approaching));
      expect(res2.consecutiveSamples, equals(2));

      // Sample 3 at t=12s (consecutive=3 >= 3, and dwell=12s >= 10s)
      final t3 = baseTime.add(const Duration(seconds: 12));
      final r3 = GpsReading(
        latitude: 28.61392,
        longitude: 77.20902,
        accuracyMeters: 8.0,
        timestamp: t3,
      );
      final res3 = detector.evaluate(
        journey: testJourney,
        reading: r3,
        evaluationTime: t3,
      );

      // Now arrival is confirmed!
      expect(res3.status, equals(ArrivalStatus.arrived));
      expect(res3.isArrived, isTrue);
      expect(res3.event, isNotNull);
      expect(res3.event?.stopId, equals('stop_target'));
      expect(res3.event?.distanceMeters, lessThan(50.0));
      expect(res3.dwellDuration.inSeconds, equals(12));
    });

    test('suppresses duplicate arrival events on subsequent readings for same stop', () {
      // Trigger arrival first
      for (int sec in [0, 6, 12]) {
        final t = baseTime.add(Duration(seconds: sec));
        detector.evaluate(
          journey: testJourney,
          reading: GpsReading(
            latitude: 28.6139,
            longitude: 77.2090,
            accuracyMeters: 10.0,
            timestamp: t,
          ),
          evaluationTime: t,
        );
      }

      // Next reading after arrival was already confirmed
      final t4 = baseTime.add(const Duration(seconds: 18));
      final r4 = GpsReading(
        latitude: 28.6139,
        longitude: 77.2090,
        accuracyMeters: 10.0,
        timestamp: t4,
      );
      final res4 = detector.evaluate(
        journey: testJourney,
        reading: r4,
        evaluationTime: t4,
      );

      expect(res4.status, equals(ArrivalStatus.alreadyHandled));
      expect(res4.isAlreadyHandled, isTrue);
      expect(res4.reason, contains('already triggered'));
      expect(res4.event, isNull);
    });

    test('resets consecutive sample count if vehicle moves outside radius', () {
      // Sample 1 inside at t=0s
      detector.evaluate(
        journey: testJourney,
        reading: GpsReading(
          latitude: 28.6139,
          longitude: 77.2090,
          accuracyMeters: 10.0,
          timestamp: baseTime,
        ),
        evaluationTime: baseTime,
      );

      // Sample 2 moves far away at t=5s
      final t2 = baseTime.add(const Duration(seconds: 5));
      final outsideRes = detector.evaluate(
        journey: testJourney,
        reading: GpsReading(
          latitude: 28.7000,
          longitude: 77.3000,
          accuracyMeters: 10.0,
          timestamp: t2,
        ),
        evaluationTime: t2,
      );
      expect(outsideRes.status, equals(ArrivalStatus.approaching));

      // Sample 3 comes back inside at t=10s
      final t3 = baseTime.add(const Duration(seconds: 10));
      final insideRes2 = detector.evaluate(
        journey: testJourney,
        reading: GpsReading(
          latitude: 28.6139,
          longitude: 77.2090,
          accuracyMeters: 10.0,
          timestamp: t3,
        ),
        evaluationTime: t3,
      );

      // Sample count should be reset to 1
      expect(insideRes2.consecutiveSamples, equals(1));
      expect(insideRes2.status, equals(ArrivalStatus.approaching));
    });
  });
}
