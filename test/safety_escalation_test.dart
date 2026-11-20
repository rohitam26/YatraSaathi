import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pathsaathi/models/alarm_config.dart';
import 'package:pathsaathi/models/contact_checkin_config.dart';
import 'package:pathsaathi/models/gps_reading.dart';
import 'package:pathsaathi/models/journey.dart';
import 'package:pathsaathi/models/stop.dart';
import 'package:pathsaathi/models/user_profile.dart';
import 'package:pathsaathi/services/alarm_service.dart';
import 'package:pathsaathi/services/journey_repository.dart';
import 'package:pathsaathi/services/journey_tracking_service.dart';
import 'package:pathsaathi/services/location_service.dart';
import 'package:pathsaathi/services/messaging_service.dart';
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
  @override
  Future<void> triggerAlarm({
    required AlarmConfig config,
    String? stopName,
    String? journeyTitle,
    VoidCallback? onFinished,
  }) async {}

  @override
  void stopAlarm() {}

  @override
  void dismiss() {}
}

class MockMessagingService extends MessagingService {
  final List<String> dispatchedMessages = [];
  final List<String> dispatchedRecipients = [];

  @override
  Future<MessageDeliveryStatus> sendCheckInMessage({
    required String contactName,
    required String phoneNumber,
    required String stopName,
    required String customMessage,
    String? journeyName,
    bool sendDirect = false,
  }) async {
    dispatchedRecipients.add(phoneNumber);
    dispatchedMessages.add(customMessage);
    return MessageDeliveryStatus.sentConfirmed;
  }

  @override
  String formatDefaultMessage({
    required String stopName,
    String? nextStopName,
  }) {
    return 'Hi! I have safely reached my stop: $stopName. - Sent via STOP Vanthachu';
  }

  @override
  String maskPhoneNumber(String rawPhone) {
    if (rawPhone.length <= 4) return '****';
    return '***-***-${rawPhone.substring(rawPhone.length - 4)}';
  }
}

class MockNotificationService extends NotificationService {
  int emergencyNotificationCount = 0;
  String? lastEscalatedStop;

  @override
  Future<void> postEmergencyEscalationNotification({
    required String stopName,
    required String contactName,
    String? journeyTitle,
  }) async {
    emergencyNotificationCount++;
    lastEscalatedStop = stopName;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone 8: UserProfile Emergency Escalation Configuration', () {
    test('UserProfile defaults have escalation enabled with 180s timeout', () {
      const profile = UserProfile();
      expect(profile.enableEmergencyEscalation, isTrue);
      expect(profile.escalationTimeoutSeconds, equals(180));
    });

    test('formatEmergencySosMessage creates valid emergency text with Google Maps URL', () {
      const profile = UserProfile(userName: 'Karthik');
      final msg = profile.formatEmergencySosMessage(
        latitude: 13.0827,
        longitude: 80.2707,
        stopName: 'Chennai Central',
      );

      expect(msg, contains('EMERGENCY SOS: Karthik'));
      expect(msg, contains('near Chennai Central'));
      expect(msg, contains('https://maps.google.com/?q=13.0827,80.2707'));
      expect(msg, contains('STOP Vanthachu Emergency Escalation'));
    });

    test('serializes and deserializes UserProfile escalation attributes', () {
      const profile = UserProfile(
        userName: 'Aarav',
        userPhone: '9876543210',
        enableEmergencyEscalation: true,
        escalationTimeoutSeconds: 120,
      );

      final json = profile.toJson();
      final restored = UserProfile.fromJson(json);

      expect(restored.enableEmergencyEscalation, isTrue);
      expect(restored.escalationTimeoutSeconds, equals(120));
      expect(restored.userName, equals('Aarav'));
    });
  });

  group('Milestone 8: Multi-Tier Emergency Escalation Workflow', () {
    test('triggers emergency SOS dispatch when arrival alert is unacknowledged', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = LocalJourneyRepository();
      final mockMessaging = MockMessagingService();
      final mockNotif = MockNotificationService();

      // Configure user profile with short 1-second timeout for rapid test execution
      await repo.saveUserProfile(
        const UserProfile(
          userName: 'Traveler Ananya',
          userPhone: '9111111111',
          defaultContactName: 'Parent Contact',
          defaultContactPhone: '9888888888',
          enableEmergencyEscalation: true,
          escalationTimeoutSeconds: 1, // 1 second timeout
        ),
      );

      final contact = ContactCheckInConfig(
        id: 'contact_p1',
        contactName: 'Parent Contact',
        phoneNumber: '9888888888',
        customMessage: '',
      );

      final stop = Stop(
        id: 'stop_tam',
        name: 'Tambaram',
        latitude: 12.9249,
        longitude: 80.1000,
        radiusMeters: 300,
        order: 0,
        contacts: [contact],
      );

      final journey = Journey(
        id: 'j_escalate',
        name: 'Evening Train',
        stops: [stop],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final trackingService = JourneyTrackingService(
        repository: repo,
        locationService: FakeLocationService(),
        alarmService: MockAlarmService(),
        messagingService: mockMessaging,
        notificationService: mockNotif,
      );

      await trackingService.startTracking(journey);

      final arrivalTime = DateTime(2026, 11, 19, 19, 0, 0);

      // Trigger 2 consecutive readings inside radius to confirm arrival
      await trackingService.processGpsReading(
        GpsReading(
          latitude: 12.9249,
          longitude: 80.1000,
          accuracyMeters: 5.0,
          timestamp: arrivalTime,
          speedMps: 2.0,
        ),
        evaluationTime: arrivalTime,
      );

      await trackingService.processGpsReading(
        GpsReading(
          latitude: 12.9249,
          longitude: 80.1000,
          accuracyMeters: 5.0,
          timestamp: arrivalTime.add(const Duration(seconds: 5)),
          speedMps: 0.0,
        ),
        evaluationTime: arrivalTime.add(const Duration(seconds: 5)),
      );

      expect(trackingService.currentState.state, equals(TrackingState.alertTriggered));
      expect(trackingService.currentState.escalationCountdownSeconds, isNotNull);

      // Wait 1.2 seconds for the 1-second escalation timer to expire
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      // Verify Auto-Escalation Dispatched!
      expect(trackingService.currentState.isEscalated, isTrue);
      expect(mockMessaging.dispatchedRecipients.length, greaterThanOrEqualTo(1));
      expect(mockMessaging.dispatchedRecipients.last, equals('9888888888'));
      expect(mockMessaging.dispatchedMessages.last, contains('EMERGENCY SOS'));
      expect(mockMessaging.dispatchedMessages.last, contains('https://maps.google.com/?q=12.9249,80.1'));
      expect(mockNotif.emergencyNotificationCount, equals(1));
      expect(mockNotif.lastEscalatedStop, equals('Tambaram'));

      trackingService.dispose();
    });

    test('cancels escalation timer when traveler acknowledges stop or cancels check-in', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = LocalJourneyRepository();
      final mockMessaging = MockMessagingService();
      final mockNotif = MockNotificationService();

      await repo.saveUserProfile(
        const UserProfile(
          userName: 'Traveler Ananya',
          userPhone: '9111111111',
          defaultContactName: 'Parent Contact',
          defaultContactPhone: '9888888888',
          enableEmergencyEscalation: true,
          escalationTimeoutSeconds: 3,
        ),
      );

      final stop = Stop(
        id: 'stop_ack',
        name: 'Egmore',
        latitude: 13.0797,
        longitude: 80.2612,
        radiusMeters: 300,
        order: 0,
      );

      final journey = Journey(
        id: 'j_ack',
        name: 'Egmore Express',
        stops: [stop],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final trackingService = JourneyTrackingService(
        repository: repo,
        locationService: FakeLocationService(),
        alarmService: MockAlarmService(),
        messagingService: mockMessaging,
        notificationService: mockNotif,
      );

      await trackingService.startTracking(journey);
      final t0 = DateTime.now();

      await trackingService.processGpsReading(
        GpsReading(latitude: 13.0797, longitude: 80.2612, accuracyMeters: 5.0, timestamp: t0),
        evaluationTime: t0,
      );
      await trackingService.processGpsReading(
        GpsReading(latitude: 13.0797, longitude: 80.2612, accuracyMeters: 5.0, timestamp: t0.add(const Duration(seconds: 5))),
        evaluationTime: t0.add(const Duration(seconds: 5)),
      );

      expect(trackingService.currentState.state, equals(TrackingState.alertTriggered));

      // Passenger acknowledges / cancels check-in
      trackingService.cancelCheckIn();
      expect(trackingService.currentState.escalationCountdownSeconds, isNull);

      // Wait 3.5 seconds
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      // Escalation was cancelled; no emergency notification posted
      expect(trackingService.currentState.isEscalated, isFalse);
      expect(mockNotif.emergencyNotificationCount, equals(0));

      trackingService.dispose();
    });

    test('triggerDirectEmergencySos sends immediate location broadcast to primary contact', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = LocalJourneyRepository();
      final mockMessaging = MockMessagingService();

      await repo.saveUserProfile(
        const UserProfile(
          userName: 'Rohan',
          userPhone: '9000000001',
          defaultContactName: 'Emergency Help',
          defaultContactPhone: '9888888888',
        ),
      );

      final stop = Stop(
        id: 's_mid',
        name: 'Central',
        latitude: 13.0827,
        longitude: 80.2707,
        radiusMeters: 300,
        order: 0,
      );

      final journey = Journey(
        id: 'j_sos',
        name: 'Night Train',
        stops: [stop],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final trackingService = JourneyTrackingService(
        repository: repo,
        locationService: FakeLocationService(),
        alarmService: MockAlarmService(),
        messagingService: mockMessaging,
      );

      await trackingService.startTracking(journey);

      // Trigger direct SOS
      final status = await trackingService.triggerDirectEmergencySos();

      expect(status, equals(MessageDeliveryStatus.sentConfirmed));
      expect(trackingService.currentState.isEscalated, isTrue);
      expect(mockMessaging.dispatchedRecipients.last, equals('+919888888888'));
      expect(mockMessaging.dispatchedMessages.last, contains('EMERGENCY SOS: Rohan'));
      expect(mockMessaging.dispatchedMessages.last, contains('https://maps.google.com/?q=13.0827,80.2707'));

      trackingService.dispose();
    });
  });
}
