import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathsaathi/models/alarm_config.dart';
import 'package:pathsaathi/models/gps_reading.dart';
import 'package:pathsaathi/models/journey.dart';
import 'package:pathsaathi/models/stop.dart';
import 'package:pathsaathi/services/alarm_service.dart';
import 'package:pathsaathi/services/journey_repository.dart';
import 'package:pathsaathi/services/journey_tracking_service.dart';
import 'package:pathsaathi/services/location_service.dart';
import 'package:pathsaathi/services/messaging_service.dart';
import 'package:pathsaathi/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeLocationService implements LocationService {
  final _controller = StreamController<GpsReading>.broadcast();
  bool streamStarted = false;
  int lastIntervalSeconds = 0;
  String? lastNotificationTitle;

  @override
  Stream<GpsReading> startLocationStream({
    int distanceFilterMeters = 0,
    int intervalSeconds = 4,
    String notificationTitle = 'STOP Vanthachu Journey Active',
    String notificationText = 'Monitoring arrival at upcoming stops in the background',
  }) {
    streamStarted = true;
    lastIntervalSeconds = intervalSeconds;
    lastNotificationTitle = notificationTitle;
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

  void emit(GpsReading reading) {
    _controller.add(reading);
  }

  @override
  void dispose() {
    _controller.close();
  }
}

class FakeAlarmService extends AlarmService {
  bool _fakeActive = false;
  String? lastAlarmStop;

  @override
  bool get isAlarmActive => _fakeActive;

  @override
  Future<void> triggerAlarm({
    required AlarmConfig config,
    String? stopName,
    String? journeyTitle,
    VoidCallback? onFinished,
  }) async {
    _fakeActive = true;
    lastAlarmStop = stopName;
  }

  @override
  void stopAlarm() {
    _fakeActive = false;
  }

  @override
  void dismiss() {
    _fakeActive = false;
  }

  @override
  void snooze({Duration? overrideDuration}) {
    _fakeActive = false;
  }
}

class FakeNotificationService extends NotificationService {
  String? lastRecoveryJourney;
  String? lastRecoveryStop;
  bool recoveryCancelled = false;

  @override
  Future<void> postSessionRecoveryNotification({
    required String journeyName,
    required String nextStopName,
  }) async {
    lastRecoveryJourney = journeyName;
    lastRecoveryStop = nextStopName;
    recoveryCancelled = false;
  }

  @override
  Future<void> cancelRecoveryNotification() async {
    recoveryCancelled = true;
  }
}

class FakeMessagingService extends MessagingService {
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
    bool sendDirect = false,
  }) async =>
      MessageDeliveryStatus.sentConfirmed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone 3: Background Tracking & Journey Recovery Lifecycle', () {
    late LocalJourneyRepository repository;
    final baseTime = DateTime(2026, 11, 10, 8, 0, 0);

    final stop1 = Stop(
      id: 'stop_guindy',
      name: 'Guindy Metro',
      latitude: 13.0067,
      longitude: 80.2025,
      radiusMeters: 300.0,
      order: 0,
      alarmConfig: const AlarmConfig(soundEnabled: true, vibrationEnabled: false),
    );

    final stop2 = Stop(
      id: 'stop_central',
      name: 'Chennai Central',
      latitude: 13.0827,
      longitude: 80.2707,
      radiusMeters: 400.0,
      order: 1,
      isFinalDestination: true,
      alarmConfig: const AlarmConfig(soundEnabled: true, vibrationEnabled: false),
    );

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      repository = LocalJourneyRepository();
    });

    test('recovers active session on cold start targeting first unreached stop', () async {
      // 1. Arrange: An active journey in repository with stop 1 reached and stop 2 unreached
      final reachedStop1 = stop1.copyWith(
        isReached: true,
        reachedAt: baseTime.add(const Duration(minutes: 20)),
      );

      final activeJourney = Journey(
        id: 'journey_commute',
        name: 'Morning Commute',
        createdAt: baseTime,
        updatedAt: baseTime.add(const Duration(minutes: 20)),
        status: JourneyStatus.active,
        stops: [reachedStop1, stop2],
        activeStopIndex: 1,
      );

      await repository.saveJourney(activeJourney);

      final fakeLocation = FakeLocationService();
      final fakeAlarm = FakeAlarmService();
      final fakeNotif = FakeNotificationService();

      final service = JourneyTrackingService(
        repository: repository,
        locationService: fakeLocation,
        alarmService: fakeAlarm,
        messagingService: FakeMessagingService(),
        notificationService: fakeNotif,
      );

      // 2. Act: App cold start invokes restoreActiveSession()
      final restored = await service.restoreActiveSession();

      // 3. Assert
      expect(restored, isTrue);
      expect(service.currentState.state, equals(TrackingState.monitoring));
      expect(service.currentState.currentStop?.id, equals('stop_central'));
      expect(service.currentState.activeJourney?.id, equals('journey_commute'));
      expect(fakeLocation.streamStarted, isTrue);
      expect(fakeLocation.lastNotificationTitle, contains('Morning Commute'));
      expect(fakeNotif.lastRecoveryJourney, equals('Morning Commute'));
      expect(fakeNotif.lastRecoveryStop, equals('Chennai Central'));

      service.dispose();
    });

    test('recovers paused session on cold start without subscribing continuous GPS', () async {
      // 1. Arrange: Journey paused by traveler before app termination
      final pausedJourney = Journey(
        id: 'journey_paused_test',
        name: 'Interrupted Transit',
        createdAt: baseTime,
        updatedAt: baseTime.add(const Duration(minutes: 5)),
        status: JourneyStatus.paused,
        stops: [stop1, stop2],
        activeStopIndex: 0,
      );

      await repository.saveJourney(pausedJourney);

      final fakeLocation = FakeLocationService();
      final fakeNotif = FakeNotificationService();

      final service = JourneyTrackingService(
        repository: repository,
        locationService: fakeLocation,
        alarmService: FakeAlarmService(),
        messagingService: FakeMessagingService(),
        notificationService: fakeNotif,
      );

      // 2. Act: Cold start restores paused session
      final restored = await service.restoreActiveSession();

      // 3. Assert: State is paused, GPS stream is NOT active
      expect(restored, isTrue);
      expect(service.currentState.state, equals(TrackingState.paused));
      expect(service.currentState.currentStop?.id, equals('stop_guindy'));
      expect(fakeLocation.streamStarted, isFalse);

      service.dispose();
    });

    test('returns false when no active journey exists in repository', () async {
      final fakeLocation = FakeLocationService();
      final service = JourneyTrackingService(
        repository: repository,
        locationService: fakeLocation,
        alarmService: FakeAlarmService(),
        messagingService: FakeMessagingService(),
      );

      final restored = await service.restoreActiveSession();

      expect(restored, isFalse);
      expect(service.currentState.state, equals(TrackingState.idle));
      expect(service.currentState.currentStop, isNull);
      expect(fakeLocation.streamStarted, isFalse);

      service.dispose();
    });

    test('retains journey progress across simulated process death and completes remaining stops', () async {
      final journey = Journey(
        id: 'journey_robustness',
        name: 'Airport Express',
        createdAt: baseTime,
        updatedAt: baseTime,
        status: JourneyStatus.planning,
        stops: [stop1, stop2],
      );

      await repository.saveJourney(journey);

      final fakeLocation1 = FakeLocationService();
      final fakeAlarm1 = FakeAlarmService();
      final service1 = JourneyTrackingService(
        repository: repository,
        locationService: fakeLocation1,
        alarmService: fakeAlarm1,
        messagingService: FakeMessagingService(),
      );

      // 1. Start tracking in Process 1
      await service1.startTracking(journey);
      expect(service1.currentState.state, equals(TrackingState.monitoring));
      expect(service1.currentState.currentStop?.id, equals('stop_guindy'));

      // 2. Trigger arrival at Stop 1 and acknowledge to advance
      await service1.advanceToNextStop();
      expect(service1.currentState.currentStop?.id, equals('stop_central'));

      // 3. Simulate sudden OS process termination
      service1.dispose();

      // 4. Process 2 spawns on device reboot / app restart
      final fakeLocation2 = FakeLocationService();
      final fakeAlarm2 = FakeAlarmService();
      final service2 = JourneyTrackingService(
        repository: repository,
        locationService: fakeLocation2,
        alarmService: fakeAlarm2,
        messagingService: FakeMessagingService(),
      );

      final restored = await service2.restoreActiveSession();
      expect(restored, isTrue);
      expect(service2.currentState.state, equals(TrackingState.monitoring));
      expect(service2.currentState.currentStop?.id, equals('stop_central'));

      // 5. Arrive at Stop 2 in Process 2 and complete the journey
      await service2.advanceToNextStop();
      expect(service2.currentState.state, equals(TrackingState.journeyCompleted));

      // 6. Verify repository now reflects completed journey
      final finalJourney = await repository.getJourney('journey_robustness');
      expect(finalJourney?.isCompleted, isTrue);
      expect(await repository.getActiveJourney(), isNull);

      service2.dispose();
    });
  });
}
