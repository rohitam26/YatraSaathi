import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pathsaathi/models/alarm_config.dart';
import 'package:pathsaathi/models/arrival_event.dart';
import 'package:pathsaathi/models/commute_schedule.dart';
import 'package:pathsaathi/models/gps_reading.dart';
import 'package:pathsaathi/models/journey.dart';
import 'package:pathsaathi/models/stop.dart';
import 'package:pathsaathi/services/arrival_detector.dart';
import 'package:pathsaathi/services/dead_reckoning_service.dart';
import 'package:pathsaathi/services/eta_calculator.dart';
import 'package:pathsaathi/services/journey_repository.dart';
import 'package:pathsaathi/services/journey_tracking_service.dart';
import 'package:pathsaathi/services/location_service.dart';
import 'package:pathsaathi/services/alarm_service.dart';
import 'package:pathsaathi/services/notification_service.dart';

class FakeLocationService implements LocationService {
  final _controller = StreamController<GpsReading>.broadcast();

  @override
  Stream<GpsReading> startLocationStream({
    int distanceFilterMeters = 0,
    int intervalSeconds = 4,
    String notificationTitle = 'STOP Vanthachu Journey Active',
    String notificationText = 'Monitoring arrival at upcoming stops in the background',
  }) {
    return _controller.stream;
  }

  @override
  Future<GpsReading?> getCurrentReading() async => null;

  @override
  Future<LocationPermissionState> checkPermissionState() async =>
      LocationPermissionState.always;

  @override
  Future<LocationPermissionState> requestPermission() async =>
      LocationPermissionState.always;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  void dispose() {
    _controller.close();
  }
}

class MockAlarmService extends AlarmService {
  int alarmTriggerCount = 0;

  @override
  Future<void> triggerAlarm({
    required AlarmConfig config,
    String? stopName,
    String? journeyTitle,
    VoidCallback? onFinished,
  }) async {
    alarmTriggerCount++;
  }
}

class MockNotificationService extends NotificationService {
  int missedStopNotificationCount = 0;
  String? lastMissedStopName;

  @override
  Future<void> postMissedStopNotification({
    required String stopName,
    required double distancePastMeters,
    String? journeyTitle,
  }) async {
    missedStopNotificationCount++;
    lastMissedStopName = stopName;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Milestone 6: EtaCalculator Smoothed Velocity & ETA Tests', () {
    late EtaCalculator calculator;

    setUp(() {
      calculator = EtaCalculator(sampleWindowSize: 5, defaultTransitSpeedMps: 10.0);
    });

    test('calculates duration and estimated arrival accurately under constant velocity', () {
      final now = DateTime(2026, 11, 19, 10, 0, 0);
      // Distance: 3000m at 20 m/s (72 km/h) -> 150 seconds = 2 min 30 sec
      final duration = calculator.calculateEta(distanceMeters: 3000, currentSpeedMps: 20.0);
      expect(duration.inSeconds, equals(150));

      final arrival = calculator.calculateEstimatedArrival(
        distanceMeters: 3000,
        currentSpeedMps: 20.0,
        referenceTime: now,
      );
      expect(arrival, equals(now.add(const Duration(seconds: 150))));
    });

    test('smooths speed over sliding window and filters out anomalous spikes/negatives', () {
      calculator.addSpeedSample(10.0);
      calculator.addSpeedSample(12.0);
      calculator.addSpeedSample(14.0);
      // Anomalous spike (> 150 m/s = 540 km/h) should be ignored
      calculator.addSpeedSample(999.0);
      // Negative speed should be ignored
      calculator.addSpeedSample(-5.0);

      // Average of 10, 12, 14 = 12.0 m/s
      expect(calculator.smoothedSpeedMps, closeTo(12.0, 0.01));
    });

    test('falls back to default transit speed when vehicle is stopped (< 0.8 m/s) at signal', () {
      calculator.addSpeedSample(0.0);
      calculator.addSpeedSample(0.2);
      // Halted -> fallback to defaultTransitSpeedMps (10.0 m/s)
      expect(calculator.smoothedSpeedMps, equals(10.0));
    });

    test('formats duration into concise user-facing strings', () {
      expect(EtaCalculator.formatEta(null), equals('--'));
      expect(EtaCalculator.formatEta(const Duration(seconds: 40)), equals('< 1 min'));
      expect(EtaCalculator.formatEta(const Duration(minutes: 18)), equals('18 min'));
      expect(EtaCalculator.formatEta(const Duration(minutes: 60)), equals('1 hr'));
      expect(EtaCalculator.formatEta(const Duration(hours: 1, minutes: 25)), equals('1 hr 25 min'));
    });
  });

  group('Milestone 6: DeadReckoningEngine Tunnel & Dead-Zone Navigation', () {
    late DeadReckoningEngine engine;

    setUp(() {
      engine = DeadReckoningEngine(
        minDropoutDuration: const Duration(seconds: 15),
        maxDropoutDuration: const Duration(seconds: 180),
      );
    });

    test('returns null if last GPS sample is fresh (< 15 seconds old)', () {
      final now = DateTime(2026, 11, 19, 12, 0, 10);
      final last = GpsReading(
        latitude: 13.0827,
        longitude: 80.2707,
        accuracyMeters: 5.0,
        timestamp: DateTime(2026, 11, 19, 12, 0, 0), // 10s old
        speedMps: 15.0,
        bearingDegrees: 90.0,
      );

      final projected = engine.projectPosition(lastValidReading: last, currentTime: now);
      expect(projected, isNull);
    });

    test('returns null if GPS outage has exceeded safety confidence window (> 180 seconds)', () {
      final now = DateTime(2026, 11, 19, 12, 5, 0);
      final last = GpsReading(
        latitude: 13.0827,
        longitude: 80.2707,
        accuracyMeters: 5.0,
        timestamp: DateTime(2026, 11, 19, 12, 0, 0), // 300s old
        speedMps: 15.0,
        bearingDegrees: 90.0,
      );

      final projected = engine.projectPosition(lastValidReading: last, currentTime: now);
      expect(projected, isNull);
    });

    test('projects position along bearing vector during tunnel transit (30s elapsed)', () {
      final t0 = DateTime(2026, 11, 19, 12, 0, 0);
      final t1 = t0.add(const Duration(seconds: 30));
      // Moving due North (0 degrees bearing) at 20 m/s for 30s = 600 meters displacement
      final last = GpsReading(
        latitude: 13.0000,
        longitude: 80.0000,
        accuracyMeters: 8.0,
        timestamp: t0,
        speedMps: 20.0,
        bearingDegrees: 0.0,
      );

      final projected = engine.projectPosition(lastValidReading: last, currentTime: t1);
      expect(projected, isNotNull);
      expect(projected!.isDeadReckoning, isTrue);
      // North displacement increases latitude
      expect(projected.latitude, greaterThan(13.0000));
      expect(projected.longitude, closeTo(80.0000, 0.0001));
      // Accuracy error is inflated smoothly (8.0 + 30 * 0.5 = 23.0m)
      expect(projected.accuracyMeters, closeTo(23.0, 0.5));
    });

    test('ArrivalDetector rejects arrival confirmation when reading is from dead reckoning', () {
      final detector = ArrivalDetector(consecutiveReadingsRequired: 2, minDwellTime: Duration.zero);
      final now = DateTime.now();

      final stop = Stop(
        id: 'stop_1',
        name: 'Tunnel Station',
        latitude: 13.0827,
        longitude: 80.2707,
        radiusMeters: 500,
        order: 0,
      );

      final journey = Journey(
        id: 'j_1',
        name: 'Metro Line',
        stops: [stop],
        createdAt: now,
        updatedAt: now,
      ).start();

      // Dead reckoning reading right on the stop coordinates
      final deadReckoningReading = GpsReading(
        latitude: 13.0827,
        longitude: 80.2707,
        accuracyMeters: 25.0,
        timestamp: now,
        speedMps: 10.0,
        bearingDegrees: 45.0,
        isDeadReckoning: true,
      );

      final result = detector.evaluate(journey: journey, reading: deadReckoningReading, evaluationTime: now);
      // MUST NOT confirm arrival!
      expect(result.status, equals(ArrivalStatus.approaching));
      expect(result.isArrived, isFalse);
      expect(result.reason, contains('Tunnel dead reckoning projection'));
    });
  });

  group('Milestone 6: Overshoot / Missed Stop Detection Tests', () {
    test('transitions to missedStop state when passenger overshoots stop radius without acknowledging', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = LocalJourneyRepository();
      final mockAlarm = MockAlarmService();
      final mockNotif = MockNotificationService();

      final stop = Stop(
        id: 'guindy_stop',
        name: 'Guindy Station',
        latitude: 13.0067,
        longitude: 80.2025,
        radiusMeters: 200,
        order: 0,
      );

      final journey = Journey(
        id: 'j_commute',
        name: 'Office Return',
        stops: [stop],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final trackingService = JourneyTrackingService(
        repository: repo,
        locationService: FakeLocationService(),
        alarmService: mockAlarm,
        notificationService: mockNotif,
      );

      await trackingService.startTracking(journey);
      expect(trackingService.currentState.state, equals(TrackingState.monitoring));

      final baseTime = DateTime(2026, 11, 19, 17, 30, 0);

      // Reading 1: Vehicle enters stop zone (100m away, inside 200m radius)
      await trackingService.processGpsReading(
        GpsReading(
          latitude: 13.0075,
          longitude: 80.2025,
          accuracyMeters: 5.0,
          timestamp: baseTime,
          speedMps: 5.0,
        ),
        evaluationTime: baseTime,
      );

      expect(trackingService.currentState.state, anyOf(equals(TrackingState.potentialArrival), equals(TrackingState.monitoring)));

      // Reading 2: Vehicle drives past without stopping and is now 1.2 km away
      final overshotTime = baseTime.add(const Duration(seconds: 40));
      await trackingService.processGpsReading(
        GpsReading(
          latitude: 13.0180, // ~1.25 km North
          longitude: 80.2025,
          accuracyMeters: 5.0,
          timestamp: overshotTime,
          speedMps: 18.0,
        ),
        evaluationTime: overshotTime,
      );

      // Verify Missed Stop detection triggered!
      expect(trackingService.currentState.state, equals(TrackingState.missedStop));
      expect(trackingService.currentState.isMissedStop, isTrue);
      expect(trackingService.currentState.statusMessage, contains('Warning: You appear to have passed "Guindy Station"'));
      expect(mockNotif.missedStopNotificationCount, equals(1));
      expect(mockNotif.lastMissedStopName, equals('Guindy Station'));

      trackingService.dispose();
    });
  });

  group('Milestone 6: CommuteSchedule Model & Repository Persistence', () {
    test('serializes and deserializes CommuteSchedule accurately', () {
      final now = DateTime(2026, 11, 19, 8, 30, 0);
      final stop1 = Stop(
        id: 'stop_1',
        name: 'Tambaram',
        latitude: 12.9249,
        longitude: 80.1000,
        radiusMeters: 300,
        order: 0,
      );
      final stop2 = Stop(
        id: 'stop_2',
        name: 'Guindy',
        latitude: 13.0067,
        longitude: 80.2025,
        radiusMeters: 250,
        order: 1,
        isFinalDestination: true,
      );

      final schedule = CommuteSchedule(
        id: 'commute_morning',
        name: 'Daily Morning Train',
        sourceName: 'Tambaram',
        destinationName: 'Guindy',
        stops: [stop1, stop2],
        daysOfWeek: [1, 2, 3, 4, 5],
        departureTime: '08:15',
        isFavorite: true,
        autoStartReminder: true,
        createdAt: now,
        updatedAt: now,
      );

      final json = schedule.toJson();
      final restored = CommuteSchedule.fromJson(json);

      expect(restored.id, equals('commute_morning'));
      expect(restored.name, equals('Daily Morning Train'));
      expect(restored.sourceName, equals('Tambaram'));
      expect(restored.destinationName, equals('Guindy'));
      expect(restored.departureTime, equals('08:15'));
      expect(restored.stops.length, equals(2));
      expect(restored.daysOfWeek, equals([1, 2, 3, 4, 5]));

      // Convert to actionable Journey
      final actionableJourney = restored.toJourney();
      expect(actionableJourney.name, equals('Daily Morning Train'));
      expect(actionableJourney.stops.length, equals(2));
      expect(actionableJourney.stops.every((s) => !s.isReached), isTrue);
    });

    test('LocalJourneyRepository saves, retrieves, and deletes commute templates', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = LocalJourneyRepository();

      final schedule = CommuteSchedule(
        id: 'office_evening',
        name: 'Evening Return',
        sourceName: 'Guindy',
        destinationName: 'Tambaram',
        stops: [
          Stop(
            id: 's_guindy',
            name: 'Guindy',
            latitude: 13.0067,
            longitude: 80.2025,
            radiusMeters: 200,
            order: 0,
          ),
          Stop(
            id: 's_tambaram',
            name: 'Tambaram',
            latitude: 12.9249,
            longitude: 80.1000,
            radiusMeters: 300,
            order: 1,
            isFinalDestination: true,
          ),
        ],
        daysOfWeek: [1, 2, 3, 4, 5],
        departureTime: '17:45',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repo.saveCommuteSchedule(schedule);

      final list = await repo.getCommuteSchedules();
      expect(list.length, equals(1));
      expect(list.first.id, equals('office_evening'));

      final single = await repo.getCommuteSchedule('office_evening');
      expect(single, isNotNull);
      expect(single!.name, equals('Evening Return'));

      await repo.deleteCommuteSchedule('office_evening');
      final afterDelete = await repo.getCommuteSchedules();
      expect(afterDelete, isEmpty);
    });
  });
}
