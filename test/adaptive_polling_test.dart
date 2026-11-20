import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathsaathi/models/alarm_config.dart';
import 'package:pathsaathi/models/gps_reading.dart';
import 'package:pathsaathi/models/journey.dart';
import 'package:pathsaathi/models/stop.dart';
import 'package:pathsaathi/services/adaptive_polling_policy.dart';
import 'package:pathsaathi/services/alarm_service.dart';
import 'package:pathsaathi/services/journey_repository.dart';
import 'package:pathsaathi/services/journey_tracking_service.dart';
import 'package:pathsaathi/services/location_service.dart';
import 'package:pathsaathi/services/messaging_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeLocationService implements LocationService {
  final _controller = StreamController<GpsReading>.broadcast();
  int lastIntervalSeconds = 3;
  int streamStartCount = 0;

  @override
  Stream<GpsReading> startLocationStream({
    int distanceFilterMeters = 0,
    int intervalSeconds = 4,
    String notificationTitle = 'STOP Vanthachu Journey Active',
    String notificationText = 'Monitoring arrival at upcoming stops in the background',
  }) {
    streamStartCount++;
    lastIntervalSeconds = intervalSeconds;
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

class FakeAlarmService extends AlarmService {
  @override
  void stopAlarm() {}
  @override
  void dismiss() {}
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

  group('Milestone 4: Adaptive Polling Policy Unit Benchmarks', () {
    const policy = AdaptivePollingPolicy();

    test('calculates 60s polling interval for long cruising distance (> 30 km)', () {
      final interval = policy.calculateIntervalSeconds(distanceMeters: 45000.0);
      final tier = policy.resolveTier(distanceMeters: 45000.0);

      expect(interval, equals(60));
      expect(tier, equals(PollingTier.cruising));
    });

    test('calculates 45s polling interval for standard cruising distance (10 km - 30 km)', () {
      final interval = policy.calculateIntervalSeconds(distanceMeters: 18000.0);
      final tier = policy.resolveTier(distanceMeters: 18000.0);

      expect(interval, equals(45));
      expect(tier, equals(PollingTier.cruising));
    });

    test('calculates 15s polling interval for intermediate approach (2 km - 10 km)', () {
      final interval = policy.calculateIntervalSeconds(
        distanceMeters: 6000.0,
        speedMps: 15.0, // 54 km/h
      );
      final tier = policy.resolveTier(distanceMeters: 6000.0);

      expect(interval, equals(15));
      expect(tier, equals(PollingTier.intermediate));
    });

    test('accelerates intermediate polling to 10s for high-speed express transit (> 100 km/h)', () {
      final interval = policy.calculateIntervalSeconds(
        distanceMeters: 7000.0,
        speedMps: 32.0, // ~115 km/h express train
      );

      expect(interval, equals(10));
    });

    test('calculates 3s high-precision polling for terminal arrival approach (< 2 km)', () {
      final interval = policy.calculateIntervalSeconds(distanceMeters: 1200.0);
      final tier = policy.resolveTier(distanceMeters: 1200.0);

      expect(interval, equals(3));
      expect(tier, equals(PollingTier.terminal));
    });

    test('adapts to battery conservation mode when battery level is critical (<= 15%)', () {
      // Long distance with low battery: 90s
      final longDistInterval = policy.calculateIntervalSeconds(
        distanceMeters: 25000.0,
        batteryLevelPercent: 12,
      );
      final longDistTier = policy.resolveTier(
        distanceMeters: 25000.0,
        batteryLevelPercent: 12,
      );
      expect(longDistInterval, equals(90));
      expect(longDistTier, equals(PollingTier.batteryConservation));

      // Intermediate distance with low battery: 25s
      final interDistInterval = policy.calculateIntervalSeconds(
        distanceMeters: 5000.0,
        batteryLevelPercent: 10,
      );
      expect(interDistInterval, equals(25));

      // Terminal zone with low battery: maintains 5s precision to safeguard arrival alert
      final terminalDistInterval = policy.calculateIntervalSeconds(
        distanceMeters: 800.0,
        batteryLevelPercent: 8,
      );
      final terminalDistTier = policy.resolveTier(
        distanceMeters: 800.0,
        batteryLevelPercent: 8,
      );
      expect(terminalDistInterval, equals(5));
      expect(terminalDistTier, equals(PollingTier.terminal));
    });
  });

  group('Milestone 4: JourneyTrackingService Dynamic Adaptive Polling Integration', () {
    late LocalJourneyRepository repository;
    final baseTime = DateTime(2026, 11, 10, 9, 0, 0);

    // Stop at Central Station (13.0827, 80.2707)
    final destination = Stop(
      id: 'stop_dest',
      name: 'Chennai Central',
      latitude: 13.0827,
      longitude: 80.2707,
      radiusMeters: 500.0,
      order: 0,
      isFinalDestination: true,
      alarmConfig: const AlarmConfig(soundEnabled: true, vibrationEnabled: false),
    );

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      repository = LocalJourneyRepository();
    });

    test('dynamically scales location stream polling interval as vehicle approaches stop', () async {
      final journey = Journey(
        id: 'journey_adaptive_test',
        name: 'Intercity Express',
        createdAt: baseTime,
        updatedAt: baseTime,
        status: JourneyStatus.planning,
        stops: [destination],
      );
      await repository.saveJourney(journey);

      final fakeLocation = FakeLocationService();
      final service = JourneyTrackingService(
        repository: repository,
        locationService: fakeLocation,
        alarmService: FakeAlarmService(),
        messagingService: FakeMessagingService(),
      );

      await service.startTracking(journey);
      expect(service.currentState.state, equals(TrackingState.monitoring));
      expect(fakeLocation.lastIntervalSeconds, equals(3));

      // 1. First reading: 40 km away (latitude: 12.7230, ~40km south)
      final t1 = baseTime.add(const Duration(seconds: 1));
      await service.processGpsReading(
        GpsReading(
          latitude: 12.7230,
          longitude: 80.2707,
          accuracyMeters: 15.0,
          timestamp: t1,
        ),
        evaluationTime: t1,
      );

      expect(service.currentIntervalSeconds, equals(60));
      expect(service.currentState.pollingTier, equals(PollingTier.cruising));
      expect(fakeLocation.lastIntervalSeconds, equals(60));

      // 2. Second reading: 6 km away (latitude: 13.0287, ~6km south)
      // Traveled 34 km in 20 minutes (1200s) ~ 102 km/h realistic train speed
      final t2 = baseTime.add(const Duration(seconds: 1201));
      await service.processGpsReading(
        GpsReading(
          latitude: 13.0287,
          longitude: 80.2707,
          accuracyMeters: 15.0,
          timestamp: t2,
        ),
        evaluationTime: t2,
      );

      expect(service.currentIntervalSeconds, equals(15));
      expect(service.currentState.pollingTier, equals(PollingTier.intermediate));
      expect(fakeLocation.lastIntervalSeconds, equals(15));

      // 3. Third reading: 1 km away (latitude: 13.0737, ~1km south)
      // Traveled 5 km in 200s ~ 90 km/h realistic approach speed
      final t3 = baseTime.add(const Duration(seconds: 1401));
      await service.processGpsReading(
        GpsReading(
          latitude: 13.0737,
          longitude: 80.2707,
          accuracyMeters: 10.0,
          timestamp: t3,
        ),
        evaluationTime: t3,
      );

      expect(service.currentIntervalSeconds, equals(3));
      expect(service.currentState.pollingTier, equals(PollingTier.terminal));
      expect(fakeLocation.lastIntervalSeconds, equals(3));

      service.dispose();
    });

    test('adapts to battery conservation mode in active tracking service', () async {
      final journey = Journey(
        id: 'journey_battery_test',
        name: 'Battery Saver Trip',
        createdAt: baseTime,
        updatedAt: baseTime,
        status: JourneyStatus.planning,
        stops: [destination],
      );
      await repository.saveJourney(journey);

      final fakeLocation = FakeLocationService();
      final service = JourneyTrackingService(
        repository: repository,
        locationService: fakeLocation,
        alarmService: FakeAlarmService(),
        messagingService: FakeMessagingService(),
      );

      await service.startTracking(journey);

      // Set low battery (10%)
      service.setBatteryLevel(10);
      expect(service.batteryLevelPercent, equals(10));

      // Reading at 25 km away
      final t1 = baseTime.add(const Duration(seconds: 1));
      await service.processGpsReading(
        GpsReading(
          latitude: 12.8580,
          longitude: 80.2707,
          accuracyMeters: 15.0,
          timestamp: t1,
        ),
        evaluationTime: t1,
      );

      expect(service.currentIntervalSeconds, equals(90));
      expect(service.currentState.pollingTier, equals(PollingTier.batteryConservation));
      expect(fakeLocation.lastIntervalSeconds, equals(90));

      service.dispose();
    });
  });
}
