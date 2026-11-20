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

      // Sample 2 moves outside radius (620m away) at realistic transit speed (t=15s)
      final t2 = baseTime.add(const Duration(seconds: 15));
      final outsideRes = detector.evaluate(
        journey: testJourney,
        reading: GpsReading(
          latitude: 28.6195,
          longitude: 77.2090,
          accuracyMeters: 10.0,
          timestamp: t2,
        ),
        evaluationTime: t2,
      );
      expect(outsideRes.status, equals(ArrivalStatus.approaching));

      // Sample 3 comes back inside at t=30s
      final t3 = baseTime.add(const Duration(seconds: 30));
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

    group('Milestone 2: Real-World Abnormal & Edge GPS Conditions', () {
      test('rejects Null Island (0.0, 0.0) coordinates', () {
        final nullIslandReading = GpsReading(
          latitude: 0.0,
          longitude: 0.0,
          accuracyMeters: 5.0,
          timestamp: baseTime,
        );

        final result = detector.evaluate(
          journey: testJourney,
          reading: nullIslandReading,
          evaluationTime: baseTime,
        );

        expect(result.status, equals(ArrivalStatus.locationUncertain));
        expect(result.reason, contains('Null Island'));
      });

      test('rejects future timestamps caused by device clock skew', () {
        final futureReading = GpsReading(
          latitude: 28.6139,
          longitude: 77.2090,
          accuracyMeters: 10.0,
          timestamp: baseTime.add(const Duration(minutes: 5)),
        );

        final result = detector.evaluate(
          journey: testJourney,
          reading: futureReading,
          evaluationTime: baseTime,
        );

        expect(result.status, equals(ArrivalStatus.locationUncertain));
        expect(result.reason, contains('in the future'));
      });

      test('rejects GPS accuracy circle when too wide relative to stop radius', () {
        final wideAccuracyReading = GpsReading(
          latitude: 28.6139,
          longitude: 77.2090,
          accuracyMeters: 38.0, // under maxAcceptableAccuracyMeters (40m)
          timestamp: baseTime,
        );

        final smallStop = targetStop.copyWith(radiusMeters: 20.0);
        final smallJourney = testJourney.copyWith(stops: [smallStop]);

        final result = detector.evaluate(
          journey: smallJourney,
          reading: wideAccuracyReading,
          evaluationTime: baseTime,
        );

        expect(result.status, equals(ArrivalStatus.locationUncertain));
        expect(result.reason, contains('too wide relative to stop radius'));
      });

      test('detects and filters sudden anomalous GPS teleportation jumps', () {
        final jumpDetector = ArrivalDetector(
          maxPhysicallyPossibleSpeedMps: 80.0,
        );
        final r1 = GpsReading(
          latitude: 28.6139,
          longitude: 77.2090,
          accuracyMeters: 10.0,
          timestamp: baseTime,
        );
        final res1 = jumpDetector.evaluate(
          journey: testJourney,
          reading: r1,
          evaluationTime: baseTime,
        );
        expect(res1.status, equals(ArrivalStatus.approaching));

        // Fix 2: 2 seconds later, position suddenly jumps 15 km away
        final t2 = baseTime.add(const Duration(seconds: 2));
        final jumpReading = GpsReading(
          latitude: 28.7500,
          longitude: 77.2090,
          accuracyMeters: 10.0,
          timestamp: t2,
        );
        final res2 = jumpDetector.evaluate(
          journey: testJourney,
          reading: jumpReading,
          evaluationTime: t2,
        );

        expect(res2.status, equals(ArrivalStatus.locationUncertain));
        expect(res2.reason, contains('Anomalous GPS jump detected'));
      });

      test('prevents arrival trigger when express vehicle passes through stop at high speed', () {
        // Vehicle enters stop radius at 72 km/h (20 m/s), exceeding 12.5 m/s threshold
        for (int sec in [0, 5, 11]) {
          final t = baseTime.add(Duration(seconds: sec));
          final res = detector.evaluate(
            journey: testJourney,
            reading: GpsReading(
              latitude: 28.6139,
              longitude: 77.2090,
              accuracyMeters: 10.0,
              speedMps: 20.0, // 72 km/h
              timestamp: t,
            ),
            evaluationTime: t,
          );
          expect(res.status, equals(ArrivalStatus.approaching));
          expect(res.reason, contains('Transit pass-through detected'));
          expect(res.isArrived, isFalse);
        }

        // When vehicle decelerates to stopping speed (2 m/s = 7.2 km/h), arrival confirms
        final tConfirm = baseTime.add(const Duration(seconds: 12));
        final resConfirm = detector.evaluate(
          journey: testJourney,
          reading: GpsReading(
            latitude: 28.6139,
            longitude: 77.2090,
            accuracyMeters: 10.0,
            speedMps: 2.0, // decelerated
            timestamp: tConfirm,
          ),
          evaluationTime: tConfirm,
        );
        expect(resConfirm.status, equals(ArrivalStatus.arrived));
        expect(resConfirm.isArrived, isTrue);
      });

      test('nearby stop disambiguation correctly prioritizes active stop in multi-stop sequence', () {
        final stop1 = Stop(
          id: 'stop_1',
          name: 'Station 1',
          latitude: 28.6139,
          longitude: 77.2090,
          radiusMeters: 300.0,
          order: 0,
        );
        final stop2 = Stop(
          id: 'stop_2',
          name: 'Station 2',
          latitude: 28.6175,
          longitude: 77.2090,
          radiusMeters: 300.0,
          order: 1,
        );

        final multiStopJourney = Journey(
          id: 'journey_multi',
          name: 'Twin Stations',
          createdAt: baseTime,
          updatedAt: baseTime,
          status: JourneyStatus.active,
          stops: [stop1, stop2],
          activeStopIndex: 0,
        );

        final nearStop2Reading = GpsReading(
          latitude: 28.6170,
          longitude: 77.2090,
          accuracyMeters: 10.0,
          timestamp: baseTime,
        );

        final disambiguation = detector.disambiguateStops(
          journey: multiStopJourney,
          reading: nearStop2Reading,
        );

        expect((disambiguation['activeStop'] as Stop).id, equals(stop1.id));
        expect((disambiguation['closestStop'] as Stop).id, equals(stop2.id));
        expect(disambiguation['isTargetingClosest'], isFalse);

        final res = detector.evaluate(
          journey: multiStopJourney,
          reading: nearStop2Reading,
          evaluationTime: baseTime,
        );
        expect(res.activeStop?.id, equals('stop_1'));
      });
    });
  });
}
