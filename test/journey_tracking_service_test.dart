import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathsaathi/models/alarm_config.dart';
import 'package:pathsaathi/models/contact_checkin_config.dart';
import 'package:pathsaathi/models/gps_reading.dart';
import 'package:pathsaathi/models/journey.dart';
import 'package:pathsaathi/models/stop.dart';
import 'package:pathsaathi/services/alarm_service.dart';
import 'package:pathsaathi/services/arrival_detector.dart';
import 'package:pathsaathi/services/journey_repository.dart';
import 'package:pathsaathi/services/journey_tracking_service.dart';
import 'package:pathsaathi/services/location_service.dart';
import 'package:pathsaathi/services/messaging_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeLocationService extends LocationService {
  @override
  Stream<GpsReading> startLocationStream({
    int distanceFilterMeters = 15,
    int intervalSeconds = 5,
    String notificationTitle = '',
    String notificationText = '',
  }) {
    return const Stream<GpsReading>.empty();
  }
}

class FakeAlarmService extends AlarmService {
  @override
  Future<void> triggerAlarm({
    required AlarmConfig config,
    VoidCallback? onFinished,
  }) async {
    // Test fake: do nothing
  }

  @override
  void stopAlarm() {}

  @override
  void dismiss() {}

  @override
  void dispose() {}
}

class FakeMessagingService implements MessagingService {
  @override
  String formatDefaultMessage({required String stopName, String? nextStopName}) =>
      'Reached $stopName';

  @override
  String maskPhoneNumber(String rawPhone) => '***-***-1234';

  @override
  Future<MessageDeliveryStatus> sendCheckInMessage({
    required String contactName,
    required String phoneNumber,
    required String stopName,
    required String customMessage,
    String? journeyName,
  }) async {
    return MessageDeliveryStatus.composerOpened;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JourneyTrackingService End-to-End Tracking Lifecycle', () {
    late LocalJourneyRepository repository;
    late JourneyTrackingService service;
    late Journey testJourney;
    final baseTime = DateTime(2026, 11, 9, 10, 0, 0);

    final stop1 = Stop(
      id: 'stop_1',
      name: 'Tambaram Station',
      latitude: 12.9249,
      longitude: 80.1000,
      radiusMeters: 500.0,
      order: 0,
      alarmConfig: const AlarmConfig(soundEnabled: true, vibrationEnabled: false),
      contacts: const [
        ContactCheckInConfig(
          id: 'c_1',
          contactName: 'Friend',
          phoneNumber: '+919999999999',
        ),
      ],
    );

    final stop2 = Stop(
      id: 'stop_2',
      name: 'Chennai Central',
      latitude: 13.0827,
      longitude: 80.2707,
      radiusMeters: 500.0,
      order: 1,
      isFinalDestination: true,
      alarmConfig: const AlarmConfig(soundEnabled: true, vibrationEnabled: false),
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      repository = LocalJourneyRepository();

      testJourney = Journey(
        id: 'journey_track_test',
        name: 'Chennai Commute',
        createdAt: baseTime,
        updatedAt: baseTime,
        status: JourneyStatus.planning,
        stops: [stop1, stop2],
      );

      await repository.saveJourney(testJourney);

      service = JourneyTrackingService(
        repository: repository,
        locationService: FakeLocationService(),
        alarmService: FakeAlarmService(),
        messagingService: FakeMessagingService(),
        arrivalDetector: ArrivalDetector(
          consecutiveReadingsRequired: 3,
          minDwellTime: const Duration(seconds: 10),
          maxAcceptableAccuracyMeters: 50.0,
        ),
      );
    });

    tearDown(() {
      service.dispose();
    });

    test('initial state is idle', () {
      expect(service.currentState.state, equals(TrackingState.idle));
    });

    test('startTracking activates journey, selects first stop and sets monitoring state', () async {
      final success = await service.startTracking(testJourney);

      expect(success, isTrue);
      expect(service.currentState.state, equals(TrackingState.monitoring));
      expect(service.currentState.currentStop?.name, equals('Tambaram Station'));
      expect(service.currentState.activeJourney?.isActive, isTrue);
    });

    test('advances through simulated GPS stream, triggers arrival alert, advances to stop 2, and completes', () async {
      await service.startTracking(testJourney);

      // 1. Reading approaching (outside 500m radius)
      service.processGpsReading(
        GpsReading(
          latitude: 12.9150,
          longitude: 80.1000,
          accuracyMeters: 10.0,
          timestamp: baseTime,
          speedMps: 15.0,
        ),
        evaluationTime: baseTime,
      );

      expect(service.currentState.state, equals(TrackingState.monitoring));
      expect(service.currentState.distanceToStopMeters, greaterThan(500.0));

      // 2. Reading inside radius (sample 1 of 3)
      final insideTime1 = baseTime.add(const Duration(seconds: 5));
      service.processGpsReading(
        GpsReading(
          latitude: 12.9249,
          longitude: 80.1000,
          accuracyMeters: 8.0,
          timestamp: insideTime1,
          speedMps: 2.0,
        ),
        evaluationTime: insideTime1,
      );
      expect(service.currentState.state, equals(TrackingState.potentialArrival));

      // 3. Reading inside radius (sample 2 of 3)
      final insideTime2 = baseTime.add(const Duration(seconds: 10));
      service.processGpsReading(
        GpsReading(
          latitude: 12.9249,
          longitude: 80.1000,
          accuracyMeters: 8.0,
          timestamp: insideTime2,
          speedMps: 1.0,
        ),
        evaluationTime: insideTime2,
      );
      expect(service.currentState.state, equals(TrackingState.potentialArrival));

      // 4. Reading inside radius (sample 3 of 3, dwell time = 15s >= 10s)
      final insideTime3 = baseTime.add(const Duration(seconds: 20));
      service.processGpsReading(
        GpsReading(
          latitude: 12.9249,
          longitude: 80.1000,
          accuracyMeters: 8.0,
          timestamp: insideTime3,
          speedMps: 0.2,
        ),
        evaluationTime: insideTime3,
      );

      // Alert triggered!
      expect(service.currentState.state, equals(TrackingState.alertTriggered));
      expect(service.currentState.currentStop?.name, equals('Tambaram Station'));
      expect(service.currentState.confidenceScore?.isHighConfidence, isTrue);

      // 5. Acknowledge and advance to next stop
      await service.advanceToNextStop();

      expect(service.currentState.state, equals(TrackingState.monitoring));
      expect(service.currentState.currentStop?.name, equals('Chennai Central'));

      // 6. Arrive at final destination (Chennai Central: 13.0827, 80.2707)
      final finalTime1 = baseTime.add(const Duration(minutes: 30));
      final finalTime2 = baseTime.add(const Duration(minutes: 30, seconds: 5));
      final finalTime3 = baseTime.add(const Duration(minutes: 30, seconds: 15));

      service.processGpsReading(
        GpsReading(
          latitude: 13.0827,
          longitude: 80.2707,
          accuracyMeters: 10.0,
          timestamp: finalTime1,
        ),
        evaluationTime: finalTime1,
      );
      service.processGpsReading(
        GpsReading(
          latitude: 13.0827,
          longitude: 80.2707,
          accuracyMeters: 10.0,
          timestamp: finalTime2,
        ),
        evaluationTime: finalTime2,
      );
      service.processGpsReading(
        GpsReading(
          latitude: 13.0827,
          longitude: 80.2707,
          accuracyMeters: 10.0,
          timestamp: finalTime3,
        ),
        evaluationTime: finalTime3,
      );

      expect(service.currentState.state, equals(TrackingState.alertTriggered));

      // 7. Complete final stop
      await service.advanceToNextStop();

      expect(service.currentState.state, equals(TrackingState.journeyCompleted));
      final savedInRepo = await repository.getJourney('journey_track_test');
      expect(savedInRepo?.isCompleted, isTrue);
    });

    test('pause, resume, and cancel tracking updates journey state and halts alarms', () async {
      await service.startTracking(testJourney);
      expect(service.currentState.isMonitoring, isTrue);

      await service.pauseTracking();
      expect(service.currentState.isPaused, isTrue);

      await service.resumeTracking();
      expect(service.currentState.isMonitoring, isTrue);

      await service.cancelTracking();
      expect(service.currentState.state, equals(TrackingState.cancelled));

      final saved = await repository.getJourney('journey_track_test');
      expect(saved?.isCancelled, isTrue);
    });
  });
}
