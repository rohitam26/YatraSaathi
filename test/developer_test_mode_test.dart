import 'package:flutter/foundation.dart';
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
import 'package:pathsaathi/ui/active_journey_screen.dart';
import 'package:pathsaathi/ui/arrival_alert_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockDeveloperAlarmService extends AlarmService {
  final List<AlarmConfig> triggeredConfigs = [];
  final List<String?> triggeredStops = [];
  int stopCalls = 0;
  int dismissCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> triggerAlarm({
    required AlarmConfig config,
    String? stopName,
    String? journeyTitle,
    VoidCallback? onFinished,
  }) async {
    triggeredConfigs.add(config);
    triggeredStops.add(stopName);
  }

  @override
  void stopAlarm() {
    stopCalls++;
  }

  @override
  void dismiss() {
    dismissCalls++;
  }

  @override
  void dispose() {
    disposeCalls++;
    super.dispose();
  }
}

class MockDeveloperMessagingService extends MessagingService {
  final List<Map<String, String>> dispatchedCalls = [];

  @override
  String formatDefaultMessage({
    required String stopName,
    String? nextStopName,
  }) {
    if (nextStopName != null && nextStopName.isNotEmpty) {
      return 'Hi, I have safely reached my stop: $stopName. Continuing journey towards $nextStopName. - Sent via STOP Vanthachu';
    }
    return 'Hi, I have safely reached my stop: $stopName. - Sent via STOP Vanthachu';
  }

  @override
  String maskPhoneNumber(String rawPhone) {
    final clean = rawPhone.trim();
    if (clean.length <= 4) return '****';
    return '***-***-${clean.substring(clean.length - 4)}';
  }

  @override
  Future<MessageDeliveryStatus> sendCheckInMessage({
    required String contactName,
    required String phoneNumber,
    required String stopName,
    required String customMessage,
    String? journeyName,
    bool sendDirect = false,
  }) async {
    dispatchedCalls.add({
      'contactName': contactName,
      'phoneNumber': phoneNumber,
      'stopName': stopName,
      'customMessage': customMessage,
      'sendDirect': sendDirect.toString(),
    });
    return sendDirect
        ? MessageDeliveryStatus.sentConfirmed
        : MessageDeliveryStatus.composerOpened;
  }
}

class FakeDeveloperLocationService extends LocationService {
  @override
  Future<LocationPermissionState> checkPermissionState() async =>
      LocationPermissionState.always;

  @override
  Future<GpsReading?> getCurrentReading() async => null;

  @override
  Stream<GpsReading> startLocationStream({
    int distanceFilterMeters = 0,
    int intervalSeconds = 3,
    String notificationTitle = '',
    String notificationText = '',
  }) {
    return const Stream.empty();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Developer Test Mode — 2-Stop Independent Verification', () {
    late LocalJourneyRepository repository;
    late MockDeveloperAlarmService mockAlarm;
    late MockDeveloperMessagingService mockMessaging;
    late FakeDeveloperLocationService fakeLocation;
    late JourneyTrackingService trackingService;

    final stop1 = Stop(
      id: 'stop_guindy',
      name: 'Guindy Metro',
      latitude: 13.0067,
      longitude: 80.2030,
      radiusMeters: 400.0,
      order: 0,
      alarmConfig: const AlarmConfig(soundEnabled: true, vibrationEnabled: true),
      contacts: const [
        ContactCheckInConfig(
          id: 'contact_alice',
          contactName: 'Alice Colleague',
          phoneNumber: '+919876543210',
          customMessage: 'Reached Guindy Metro station! Changing lines.',
        ),
      ],
    );

    final stop2 = Stop(
      id: 'stop_central',
      name: 'Chennai Central',
      latitude: 13.0827,
      longitude: 80.2707,
      radiusMeters: 500.0,
      order: 1,
      alarmConfig: const AlarmConfig(soundEnabled: true, vibrationEnabled: true),
      contacts: const [
        ContactCheckInConfig(
          id: 'contact_bob',
          contactName: 'Bob Family',
          phoneNumber: '+919840123456',
          customMessage: 'Reached Chennai Central, boarding the express train now.',
        ),
      ],
    );

    final twoStopJourney = Journey(
      id: 'journey_chennai_commute',
      name: 'Chennai Daily Commute',
      description: 'Tambaram to Central via Guindy',
      stops: [stop1, stop2],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    setUp(() {
      repository = LocalJourneyRepository();
      mockAlarm = MockDeveloperAlarmService();
      mockMessaging = MockDeveloperMessagingService();
      fakeLocation = FakeDeveloperLocationService();

      trackingService = JourneyTrackingService(
        repository: repository,
        locationService: fakeLocation,
        arrivalDetector: ArrivalDetector(
          consecutiveReadingsRequired: 2,
          minDwellTime: const Duration(seconds: 4),
        ),
        alarmService: mockAlarm,
        messagingService: mockMessaging,
      );
    });

    tearDown(() {
      trackingService.dispose();
    });

    test('1. Stop 1 test arrival: triggers alarm, Alice contact, marks isTestMode, prevents duplicates', () async {
      await repository.saveJourney(twoStopJourney);
      await trackingService.startTracking(twoStopJourney);

      expect(trackingService.currentState.state, TrackingState.monitoring);
      expect(trackingService.currentState.currentStop?.name, 'Guindy Metro');

      // Simulate arrival for Stop 1
      final success = await trackingService.simulateDeveloperTestArrival(targetStop: stop1);
      expect(success, isTrue, reason: 'Developer test arrival simulation should succeed');

      // Verify tracking state transitions to alertTriggered
      expect(trackingService.currentState.state, TrackingState.alertTriggered);
      expect(trackingService.currentState.currentStop?.id, stop1.id);

      // Verify test mode flag on result and event
      final result = trackingService.currentState.arrivalResult;
      final event = result?.event;
      expect(result, isNotNull);
      expect(result!.isTestMode, isTrue, reason: 'Must be distinctly flagged as test mode');
      expect(result.reason, contains('TEST MODE'));
      expect(event, isNotNull);
      expect(event!.isTestMode, isTrue);

      // Verify alarm playback triggered
      expect(mockAlarm.triggeredStops, contains('Guindy Metro'));
      expect(mockAlarm.triggeredConfigs.first.soundEnabled, isTrue);

      // Verify SMS composer opened with Alice's specific configuration
      expect(mockMessaging.dispatchedCalls.length, 1);
      final firstDispatch = mockMessaging.dispatchedCalls.first;
      expect(firstDispatch['contactName'], 'Alice Colleague');
      expect(firstDispatch['phoneNumber'], '+919876543210');
      expect(firstDispatch['customMessage'], 'Reached Guindy Metro station! Changing lines.');
      expect(firstDispatch['stopName'], 'Guindy Metro');

      // Verify duplicate alert prevention
      final duplicateAttempt = await trackingService.simulateDeveloperTestArrival(targetStop: stop1);
      expect(duplicateAttempt, isFalse, reason: 'Duplicate test alert for Stop 1 must be rejected');
      expect(mockAlarm.triggeredStops.length, 1, reason: 'No extra alarm triggered');
      expect(mockMessaging.dispatchedCalls.length, 1, reason: 'No extra SMS opened');
    });

    test('2. Multi-stop progression: Stop 1 -> Stop 2 -> Completion', () async {
      await repository.saveJourney(twoStopJourney);
      await trackingService.startTracking(twoStopJourney);

      // Simulate Stop 1 arrival
      await trackingService.simulateDeveloperTestArrival(targetStop: stop1);
      expect(trackingService.currentState.state, TrackingState.alertTriggered);

      // Advance to next stop
      await trackingService.advanceToNextStop();

      // Verify journey advances to Stop 2
      expect(trackingService.currentState.state, TrackingState.monitoring);
      expect(trackingService.currentState.currentStop?.id, stop2.id);
      expect(trackingService.currentState.currentStop?.name, 'Chennai Central');
      expect(mockAlarm.dismissCalls, greaterThanOrEqualTo(1));

      // Simulate Stop 2 arrival
      final successStop2 = await trackingService.simulateDeveloperTestArrival(targetStop: stop2);
      expect(successStop2, isTrue);

      expect(trackingService.currentState.state, TrackingState.alertTriggered);
      expect(trackingService.currentState.arrivalResult?.isTestMode, isTrue);

      // Verify alarm triggered for Stop 2
      expect(mockAlarm.triggeredStops.last, 'Chennai Central');

      // Verify SMS composer opened for Bob (Stop 2's specific contact)
      expect(mockMessaging.dispatchedCalls.length, 2);
      final secondDispatch = mockMessaging.dispatchedCalls.last;
      expect(secondDispatch['contactName'], 'Bob Family');
      expect(secondDispatch['phoneNumber'], '+919840123456');
      expect(secondDispatch['customMessage'], 'Reached Chennai Central, boarding the express train now.');

      // Prevent duplicate alert for Stop 2
      final dupStop2 = await trackingService.simulateDeveloperTestArrival(targetStop: stop2);
      expect(dupStop2, isFalse);

      // Advance from Stop 2 (final destination) -> finishes the entire journey
      await trackingService.advanceToNextStop();

      expect(trackingService.currentState.state, TrackingState.journeyCompleted);
      expect(trackingService.currentState.activeJourney?.isCompleted, isTrue);
      expect(mockAlarm.stopCalls, greaterThanOrEqualTo(1));
    });

    test('3. Test Arrival directly on Stop 2 without Stop 1 still uses Stop 2 configuration', () async {
      await repository.saveJourney(twoStopJourney);
      await trackingService.startTracking(twoStopJourney);

      // Directly simulate Stop 2 arrival
      final success = await trackingService.simulateDeveloperTestArrival(targetStop: stop2);
      expect(success, isTrue);

      expect(trackingService.currentState.currentStop?.id, stop2.id);
      expect(mockAlarm.triggeredStops.last, 'Chennai Central');
      expect(mockMessaging.dispatchedCalls.last['contactName'], 'Bob Family');
    });

    testWidgets('4. ArrivalAlertDialog displays TEST MODE banner when isTestMode is true', (tester) async {
      await repository.saveJourney(twoStopJourney);
      await trackingService.startTracking(twoStopJourney);
      await trackingService.simulateDeveloperTestArrival(targetStop: stop1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ArrivalAlertDialog(
              stop: stop1,
              trackingService: trackingService,
              onDismiss: () {},
              onContinueNext: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Look for the purple TEST MODE banner
      expect(find.textContaining('TEST MODE — SIMULATED ARRIVAL'), findsOneWidget);
      expect(find.text('Guindy Metro'), findsOneWidget);
      expect(find.textContaining('Alice Colleague'), findsOneWidget);
    });

    testWidgets('5. ActiveJourneyScreen renders Developer Test Mode buttons in debug mode', (tester) async {
      await repository.saveJourney(twoStopJourney);
      await trackingService.startTracking(twoStopJourney);

      await tester.pumpWidget(
        MaterialApp(
          home: ActiveJourneyScreen(
            trackingService: trackingService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      if (kDebugMode) {
        expect(find.textContaining('Developer Test Mode'), findsOneWidget);
        expect(find.textContaining('Test Arrival: Stop 1'), findsOneWidget);
        expect(find.textContaining('Test Arrival: Stop 2'), findsOneWidget);
      }
    });
  });
}
