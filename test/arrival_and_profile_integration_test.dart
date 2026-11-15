import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pathsaathi/models/alarm_config.dart';
import 'package:pathsaathi/models/arrival_event.dart';
import 'package:pathsaathi/models/contact_checkin_config.dart';
import 'package:pathsaathi/models/gps_reading.dart';
import 'package:pathsaathi/models/journey.dart';
import 'package:pathsaathi/models/stop.dart';
import 'package:pathsaathi/models/user_profile.dart';
import 'package:pathsaathi/services/alarm_service.dart';
import 'package:pathsaathi/services/arrival_detector.dart';
import 'package:pathsaathi/services/journey_repository.dart';
import 'package:pathsaathi/services/journey_tracking_service.dart';
import 'package:pathsaathi/services/location_service.dart';
import 'package:pathsaathi/services/messaging_service.dart';

class MockMessagingService implements MessagingService {
  int callCount = 0;
  String? lastRecipient;
  String? lastMessage;
  bool? lastSendDirect;

  @override
  Future<MessageDeliveryStatus> sendCheckInMessage({
    required String contactName,
    required String phoneNumber,
    required String stopName,
    required String customMessage,
    String? journeyName,
    bool sendDirect = false,
  }) async {
    callCount++;
    lastRecipient = phoneNumber;
    lastMessage = customMessage;
    lastSendDirect = sendDirect;
    return sendDirect
        ? MessageDeliveryStatus.sentConfirmed
        : MessageDeliveryStatus.composerOpened;
  }

  @override
  String formatDefaultMessage({
    required String stopName,
    String? nextStopName,
  }) {
    if (nextStopName != null && nextStopName.isNotEmpty) {
      return 'Hi, I have safely reached my stop: $stopName. Continuing journey towards $nextStopName. - Sent via YatraSaathi';
    }
    return 'Hi, I have safely reached my stop: $stopName. - Sent via YatraSaathi';
  }

  @override
  String maskPhoneNumber(String rawPhone) {
    if (rawPhone.length <= 4) return '****';
    return '***-***-${rawPhone.substring(rawPhone.length - 4)}';
  }
}

class FakeTrackingLocationService extends LocationService {
  GpsReading? currentReadingToReturn;

  @override
  Future<GpsReading?> getCurrentReading() async {
    return currentReadingToReturn;
  }

  @override
  Stream<GpsReading> startLocationStream({
    int distanceFilterMeters = 0,
    int intervalSeconds = 4,
    String notificationTitle = '',
    String notificationText = '',
  }) {
    return const Stream<GpsReading>.empty();
  }

  @override
  Future<LocationPermissionState> checkPermissionState() async {
    return LocationPermissionState.always;
  }

  @override
  Future<LocationPermissionState> requestPermission() async {
    return LocationPermissionState.always;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UserProfile Model & Persistence', () {
    test('serializes and deserializes UserProfile correctly', () {
      const profile = UserProfile(
        userName: 'Priya Sharma',
        userPhone: '9876543210',
        countryCode: '+91',
        defaultContactName: 'Aakash Sharma',
        defaultContactPhone: '+919811122233',
        defaultContactRelation: 'Partner',
        defaultMessage: 'Reached safely! Love, Priya',
        autoCheckInOnArrival: true,
      );

      final json = profile.toJson();
      final restored = UserProfile.fromJson(json);

      expect(restored.userName, 'Priya Sharma');
      expect(restored.formattedUserPhone, '+919876543210');
      expect(restored.defaultContactName, 'Aakash Sharma');
      expect(restored.formattedContactPhone, '+919811122233');
      expect(restored.defaultContactRelation, 'Partner');
      expect(restored.hasUserProfile, isTrue);
      expect(restored.hasDefaultContact, isTrue);
    });

    test('saves, edits and restores UserProfile via LocalJourneyRepository', () async {
      final repo = LocalJourneyRepository();

      // Initial state is default empty profile
      final initial = await repo.getUserProfile();
      expect(initial.hasUserProfile, isFalse);

      // Save profile
      const profile = UserProfile(
        userName: 'Vikram',
        userPhone: '9840012345',
        defaultContactName: 'Deepa',
        defaultContactPhone: '9840054321',
      );
      await repo.saveUserProfile(profile);

      // Restore
      final restored = await repo.getUserProfile();
      expect(restored.userName, 'Vikram');
      expect(restored.userPhone, '9840012345');
      expect(restored.defaultContactName, 'Deepa');
      expect(restored.defaultContactPhone, '9840054321');
      expect(restored.formattedUserPhone, '+919840012345');
      expect(restored.formattedContactPhone, '+919840054321');

      // Edit and update
      final updated = restored.copyWith(userName: 'Vikram Sundaram');
      await repo.saveUserProfile(updated);

      final reRestored = await repo.getUserProfile();
      expect(reRestored.userName, 'Vikram Sundaram');
    });

    test('generates personalized default check-in message', () {
      const profile = UserProfile(
        userName: 'Kavita',
        userPhone: '9876500000',
        defaultContactName: 'Mom',
        defaultContactPhone: '9876511111',
      );

      final msg = profile.formatPersonalizedMessage(
        stopName: 'Central Station',
        nextStopName: 'Airport',
      );
      expect(msg, contains('Kavita'));
      expect(msg, contains('Central Station'));
      expect(msg, contains('Airport'));
      expect(msg, contains('Sent via YatraSaathi'));
    });
  });

  group('Arrival Detection & Physical GPS Conditions', () {
    test('accepts realistic GPS accuracy of 60m inside 200m radius without flagging uncertain', () {
      final detector = ArrivalDetector(
        maxAcceptableAccuracyMeters: 80.0,
      );

      final stop = Stop(
        id: 'stop_1',
        name: 'Tambaram Station',
        latitude: 12.9249,
        longitude: 80.1000,
        radiusMeters: 200.0,
        order: 0,
      );

      final journey = Journey(
        id: 'j_1',
        name: 'Local Commute',
        stops: [stop],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: JourneyStatus.active,
      );

      // GPS Reading with ±65m accuracy (typical physical smartphone performance)
      final reading = GpsReading(
        latitude: 12.9250, // ~15m from stop center
        longitude: 80.1001,
        accuracyMeters: 65.0,
        timestamp: DateTime.now(),
      );

      final result = detector.evaluate(journey: journey, reading: reading);
      // Must NOT be locationUncertain
      expect(result.status, isNot(ArrivalStatus.locationUncertain));
      expect(result.status, ArrivalStatus.approaching);
      expect(result.distanceMeters, lessThan(200.0));
    });

    test('verifies arrival when starting journey already inside destination radius', () {
      final detector = ArrivalDetector(
        consecutiveReadingsRequired: 2,
        minDwellTime: const Duration(seconds: 4),
      );

      final stop = Stop(
        id: 'stop_1',
        name: 'Home Station',
        latitude: 12.9249,
        longitude: 80.1000,
        radiusMeters: 300.0,
        order: 0,
      );

      final journey = Journey(
        id: 'j_1',
        name: 'Return Journey',
        stops: [stop],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: JourneyStatus.active,
      );

      final t0 = DateTime(2026, 3, 15, 10, 0, 0);

      // Reading 1 (t=0s): stationary inside radius
      final r1 = GpsReading(
        latitude: 12.9249,
        longitude: 80.1000,
        accuracyMeters: 20.0,
        timestamp: t0,
      );
      final res1 = detector.evaluate(journey: journey, reading: r1, evaluationTime: t0);
      expect(res1.status, ArrivalStatus.approaching);
      expect(res1.consecutiveSamples, 1);

      // Reading 2 (t=5s): stationary inside radius, dwell satisfied
      final t1 = t0.add(const Duration(seconds: 5));
      final r2 = GpsReading(
        latitude: 12.9249,
        longitude: 80.1000,
        accuracyMeters: 18.0,
        timestamp: t1,
      );
      final res2 = detector.evaluate(journey: journey, reading: r2, evaluationTime: t1);
      expect(res2.isArrived, isTrue);
      expect(res2.consecutiveSamples, 2);
      expect(res2.dwellDuration.inSeconds, 5);
    });

    test('suppresses duplicate arrival events on repeated subsequent readings', () {
      final detector = ArrivalDetector(
        consecutiveReadingsRequired: 2,
        minDwellTime: const Duration(seconds: 4),
      );

      final stop = Stop(
        id: 'stop_1',
        name: 'Terminal',
        latitude: 12.9249,
        longitude: 80.1000,
        radiusMeters: 300.0,
        order: 0,
      );

      final journey = Journey(
        id: 'j_1',
        name: 'Commute',
        stops: [stop],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: JourneyStatus.active,
      );

      final t0 = DateTime(2026, 3, 15, 10, 0, 0);
      final r1 = GpsReading(
        latitude: 12.9249,
        longitude: 80.1000,
        accuracyMeters: 10.0,
        timestamp: t0,
      );
      detector.evaluate(journey: journey, reading: r1, evaluationTime: t0);

      final t1 = t0.add(const Duration(seconds: 5));
      final r2 = GpsReading(
        latitude: 12.9249,
        longitude: 80.1000,
        accuracyMeters: 10.0,
        timestamp: t1,
      );
      final res2 = detector.evaluate(journey: journey, reading: r2, evaluationTime: t1);
      expect(res2.isArrived, isTrue);

      // Subsequent readings must be flagged alreadyHandled
      final t2 = t0.add(const Duration(seconds: 10));
      final r3 = GpsReading(
        latitude: 12.9249,
        longitude: 80.1000,
        accuracyMeters: 10.0,
        timestamp: t2,
      );
      final res3 = detector.evaluate(journey: journey, reading: r3, evaluationTime: t2);
      expect(res3.status, ArrivalStatus.alreadyHandled);
    });
  });

  group('End-to-End Tracking Service Pipeline', () {
    test('confirmed arrival triggers alarm and check-in fallback from UserProfile', () async {
      final repo = LocalJourneyRepository();
      // Configure default safety profile
      await repo.saveUserProfile(
        const UserProfile(
          userName: 'Arun',
          userPhone: '9840123456',
          defaultContactName: 'Karthik',
          defaultContactPhone: '+919940123456',
          autoCheckInOnArrival: true,
        ),
      );

      final mockMessaging = MockMessagingService();
      final fakeLocation = FakeTrackingLocationService();
      final alarmService = AlarmService();

      final trackingService = JourneyTrackingService(
        repository: repo,
        locationService: fakeLocation,
        arrivalDetector: ArrivalDetector(
          consecutiveReadingsRequired: 2,
          minDwellTime: const Duration(seconds: 4),
        ),
        alarmService: alarmService,
        messagingService: mockMessaging,
      );

      final stop = Stop(
        id: 'stop_100',
        name: 'Guindy Metro',
        latitude: 13.0067,
        longitude: 80.2023,
        radiusMeters: 250.0,
        order: 0,
        // No per-stop contact configured -> tests fallback to profile
        contacts: const [],
        alarmConfig: const AlarmConfig(soundEnabled: false, vibrationEnabled: false),
      );

      final journey = Journey(
        id: 'journey_100',
        name: 'Metro Line',
        stops: [stop],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await trackingService.startTracking(journey);
      expect(trackingService.currentState.state, TrackingState.monitoring);

      final t0 = DateTime(2026, 4, 1, 8, 30, 0);

      // Reading 1: within stop radius
      final r1 = GpsReading(
        latitude: 13.0068,
        longitude: 80.2024,
        accuracyMeters: 15.0,
        timestamp: t0,
      );
      await trackingService.processGpsReading(r1, evaluationTime: t0);
      expect(trackingService.currentState.state, TrackingState.potentialArrival);
      expect(mockMessaging.callCount, 0);

      // Reading 2: within stop radius, dwell satisfied -> Arrival Confirmed!
      final t1 = t0.add(const Duration(seconds: 5));
      final r2 = GpsReading(
        latitude: 13.0068,
        longitude: 80.2024,
        accuracyMeters: 15.0,
        timestamp: t1,
      );
      await trackingService.processGpsReading(r2, evaluationTime: t1);

      expect(trackingService.currentState.state, TrackingState.alertTriggered);
      // Check-in was dispatched to default profile contact
      expect(mockMessaging.callCount, 1);
      expect(mockMessaging.lastRecipient, '+919940123456');
      expect(mockMessaging.lastMessage, contains('Guindy Metro'));

      // Subsequent readings should not re-trigger check-in
      final t2 = t0.add(const Duration(seconds: 10));
      final r3 = GpsReading(
        latitude: 13.0068,
        longitude: 80.2024,
        accuracyMeters: 15.0,
        timestamp: t2,
      );
      await trackingService.processGpsReading(r3, evaluationTime: t2);
      expect(mockMessaging.callCount, 1); // Still 1, duplicate prevented!
    });

    test('stop-specific contact overrides default safety profile', () async {
      final repo = LocalJourneyRepository();
      await repo.saveUserProfile(
        const UserProfile(
          defaultContactName: 'Global Default Contact',
          defaultContactPhone: '+911111111111',
        ),
      );

      final mockMessaging = MockMessagingService();
      final fakeLocation = FakeTrackingLocationService();
      final alarmService = AlarmService();

      final trackingService = JourneyTrackingService(
        repository: repo,
        locationService: fakeLocation,
        arrivalDetector: ArrivalDetector(
          consecutiveReadingsRequired: 2,
          minDwellTime: const Duration(seconds: 4),
        ),
        alarmService: alarmService,
        messagingService: mockMessaging,
      );

      // Stop with explicit override contact
      final stop = Stop(
        id: 'stop_special',
        name: 'Special Stop',
        latitude: 13.0000,
        longitude: 80.2000,
        radiusMeters: 200.0,
        order: 0,
        contacts: const [
          ContactCheckInConfig(
            id: 'c_override',
            contactName: 'Custom Host',
            phoneNumber: '+919999988888',
            customMessage: 'Hey Host, I have reached Special Stop!',
          ),
        ],
        alarmConfig: const AlarmConfig(soundEnabled: false, vibrationEnabled: false),
      );

      final journey = Journey(
        id: 'journey_special',
        name: 'Host Visit',
        stops: [stop],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await trackingService.startTracking(journey);

      final t0 = DateTime(2026, 4, 1, 9, 0, 0);
      final r1 = GpsReading(
        latitude: 13.0000,
        longitude: 80.2000,
        accuracyMeters: 10.0,
        timestamp: t0,
      );
      await trackingService.processGpsReading(r1, evaluationTime: t0);

      final t1 = t0.add(const Duration(seconds: 6));
      final r2 = GpsReading(
        latitude: 13.0000,
        longitude: 80.2000,
        accuracyMeters: 10.0,
        timestamp: t1,
      );
      await trackingService.processGpsReading(r2, evaluationTime: t1);

      expect(mockMessaging.callCount, 1);
      // Overridden contact was dialed, NOT the global default
      expect(mockMessaging.lastRecipient, '+919999988888');
      expect(mockMessaging.lastMessage, 'Hey Host, I have reached Special Stop!');
    });

    test('manual arrival confirmation triggers alert and advances journey reliably', () async {
      final repo = LocalJourneyRepository();
      final mockMessaging = MockMessagingService();
      final fakeLocation = FakeTrackingLocationService();
      final alarmService = AlarmService();

      final trackingService = JourneyTrackingService(
        repository: repo,
        locationService: fakeLocation,
        alarmService: alarmService,
        messagingService: mockMessaging,
      );

      final stop1 = Stop(
        id: 's_1',
        name: 'Station 1',
        latitude: 13.00,
        longitude: 80.20,
        radiusMeters: 100,
        order: 0,
        alarmConfig: const AlarmConfig(soundEnabled: false, vibrationEnabled: false),
      );
      final stop2 = Stop(
        id: 's_2',
        name: 'Station 2',
        latitude: 13.10,
        longitude: 80.30,
        radiusMeters: 100,
        order: 1,
        isFinalDestination: true,
        alarmConfig: const AlarmConfig(soundEnabled: false, vibrationEnabled: false),
      );

      final journey = Journey(
        id: 'j_multi',
        name: 'Multi Stop Commute',
        stops: [stop1, stop2],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await trackingService.startTracking(journey);
      expect(trackingService.currentState.currentStop?.id, 's_1');

      // Passenger manually confirms arrival at Station 1 (e.g. under shielded station canopy)
      await trackingService.confirmArrivalManually();
      expect(trackingService.currentState.state, TrackingState.alertTriggered);
      expect(trackingService.currentState.statusMessage, contains('Station 1'));

      // Advance to next stop
      await trackingService.advanceToNextStop();
      expect(trackingService.currentState.currentStop?.id, 's_2');
      expect(trackingService.currentState.state, TrackingState.monitoring);

      // Confirm arrival at final destination
      await trackingService.confirmArrivalManually();
      expect(trackingService.currentState.state, TrackingState.alertTriggered);

      // Acknowledge final stop
      await trackingService.advanceToNextStop();
      expect(trackingService.currentState.state, TrackingState.journeyCompleted);
    });
  });
}
