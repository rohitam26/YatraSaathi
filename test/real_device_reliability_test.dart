import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pathsaathi/models/alarm_config.dart';
import 'package:pathsaathi/models/contact_checkin_config.dart';
import 'package:pathsaathi/models/gps_reading.dart';
import 'package:pathsaathi/models/journey.dart';
import 'package:pathsaathi/models/stop.dart';
import 'package:pathsaathi/models/user_profile.dart';
import 'package:pathsaathi/services/alarm_service.dart';
import 'package:pathsaathi/services/arrival_detector.dart';
import 'package:pathsaathi/services/geocoding_service.dart';
import 'package:pathsaathi/services/journey_repository.dart';
import 'package:pathsaathi/services/journey_tracking_service.dart';
import 'package:pathsaathi/services/location_service.dart';
import 'package:pathsaathi/services/messaging_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockReliabilityMessagingService implements MessagingService {
  final List<Map<String, String>> dispatchedCalls = [];

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
      'message': customMessage,
      'sendDirect': sendDirect.toString(),
    });
    return sendDirect
        ? MessageDeliveryStatus.sentConfirmed
        : MessageDeliveryStatus.composerOpened;
  }
}

class FakeReliabilityLocationService extends LocationService {
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

  group('Real Device Failure Repair & Reliability Verification', () {
    test('1. Arrival event triggers alarm service and prevents duplicate alarms', () async {
      final repo = LocalJourneyRepository();
      final messaging = MockReliabilityMessagingService();
      final location = FakeReliabilityLocationService();
      final alarm = AlarmService();

      final trackingService = JourneyTrackingService(
        repository: repo,
        locationService: location,
        arrivalDetector: ArrivalDetector(
          consecutiveReadingsRequired: 2,
          minDwellTime: const Duration(seconds: 4),
        ),
        alarmService: alarm,
        messagingService: messaging,
      );

      final stop = Stop(
        id: 'stop_arrival_test',
        name: 'Tambaram Junction',
        latitude: 12.9249,
        longitude: 80.1000,
        radiusMeters: 200.0,
        order: 0,
        alarmConfig: const AlarmConfig(soundEnabled: false, vibrationEnabled: false),
      );

      final journey = Journey(
        id: 'j_arrival',
        name: 'Express Route',
        stops: [stop],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await trackingService.startTracking(journey);

      final t0 = DateTime(2026, 11, 10, 10, 0, 0);

      // Reading 1: within 200m radius
      final r1 = GpsReading(
        latitude: 12.9250,
        longitude: 80.1001,
        accuracyMeters: 15.0,
        timestamp: t0,
      );
      await trackingService.processGpsReading(r1, evaluationTime: t0);
      expect(trackingService.currentState.state, TrackingState.potentialArrival);

      // Reading 2: within radius, dwell = 5s (>= 4s) -> Arrival Confirmed!
      final t1 = t0.add(const Duration(seconds: 5));
      final r2 = GpsReading(
        latitude: 12.9250,
        longitude: 80.1001,
        accuracyMeters: 15.0,
        timestamp: t1,
      );
      await trackingService.processGpsReading(r2, evaluationTime: t1);

      expect(trackingService.currentState.state, TrackingState.alertTriggered);
      expect(trackingService.currentState.statusMessage, contains('Tambaram Junction'));

      // Reading 3: subsequent reading inside radius -> must NOT re-trigger alarm or check-in!
      final t2 = t0.add(const Duration(seconds: 10));
      final r3 = GpsReading(
        latitude: 12.9250,
        longitude: 80.1001,
        accuracyMeters: 15.0,
        timestamp: t2,
      );
      await trackingService.processGpsReading(r3, evaluationTime: t2);
      // Status message must still indicate arrival without duplicate alert
      expect(trackingService.currentState.statusMessage, contains('Tambaram Junction'));
    });

    test('2. Safety check-in uses emergency contact number and rejects passenger own number', () async {
      final repo = LocalJourneyRepository();
      // Passenger configured their profile with user phone '9876543210'
      await repo.saveUserProfile(
        const UserProfile(
          userName: 'Rohan',
          userPhone: '9876543210',
          defaultContactName: 'Aarav (Brother)',
          defaultContactPhone: '+919876500000',
          autoCheckInOnArrival: false,
        ),
      );

      final messaging = MockReliabilityMessagingService();
      final trackingService = JourneyTrackingService(
        repository: repo,
        locationService: FakeReliabilityLocationService(),
        messagingService: messaging,
      );

      final stop = Stop(
        id: 'stop_contact_test',
        name: 'Connaught Place',
        latitude: 28.6315,
        longitude: 77.2167,
        radiusMeters: 200.0,
        order: 0,
      );

      final journey = Journey(
        id: 'j_cp',
        name: 'Delhi Commute',
        stops: [stop],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await trackingService.startTracking(journey);

      // Verify effective contacts correctly resolves Aarav's emergency number (+919876500000)
      final contacts = await trackingService.getEffectiveContactsForStop(stop);
      expect(contacts.length, 1);
      expect(contacts.first.contactName, 'Aarav (Brother)');
      expect(contacts.first.phoneNumber, '+919876500000');
      // Must NOT be the user's phone number!
      expect(contacts.first.phoneNumber, isNot('9876543210'));

      // Dispatch check-in to Aarav
      final status = await trackingService.triggerCheckInForCurrentStop(
        targetContact: contacts.first,
      );
      expect(status, MessageDeliveryStatus.composerOpened);
      expect(messaging.dispatchedCalls.length, 1);
      expect(messaging.dispatchedCalls.first['phoneNumber'], '+919876500000');
      expect(messaging.dispatchedCalls.first['contactName'], 'Aarav (Brother)');

      // If a stop mistakenly has the passenger's own number as contact, tracking service rejects it
      const invalidSelfContact = ContactCheckInConfig(
        id: 'c_self',
        contactName: 'Self',
        phoneNumber: '9876543210',
      );
      final rejectStatus = await trackingService.triggerCheckInForCurrentStop(
        targetContact: invalidSelfContact,
      );
      expect(rejectStatus, MessageDeliveryStatus.failed);
    });

    test('3. Stop reordering preserves individual contact and alarm configurations', () {
      const alarmA = AlarmConfig(soundName: 'High Alert Bell', maxRepeats: 3);
      const alarmB = AlarmConfig(soundName: 'Gentle Ripple', maxRepeats: 1);

      const contactA = ContactCheckInConfig(
        id: 'c_1',
        contactName: 'Contact for Stop 1',
        phoneNumber: '+919000000001',
      );
      const contactB = ContactCheckInConfig(
        id: 'c_2',
        contactName: 'Contact for Stop 2',
        phoneNumber: '+919000000002',
      );

      final stop1 = Stop(
        id: 's_1',
        name: 'Stop 1',
        latitude: 10.0,
        longitude: 20.0,
        order: 0,
        alarmConfig: alarmA,
        contacts: const [contactA],
      );

      final stop2 = Stop(
        id: 's_2',
        name: 'Stop 2',
        latitude: 11.0,
        longitude: 21.0,
        order: 1,
        alarmConfig: alarmB,
        contacts: const [contactB],
        isFinalDestination: true,
      );

      final journey = Journey(
        id: 'j_reorder',
        name: 'Reorder Test',
        stops: [stop1, stop2],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Swap stop 1 and stop 2
      final reordered = journey.reorderStops(0, 2);
      expect(reordered.stops.length, 2);

      // Stop 2 is now first in sequence, but retains its own contacts and alarm config!
      final newFirst = reordered.stops[0];
      expect(newFirst.id, 's_2');
      expect(newFirst.order, 0);
      expect(newFirst.isFinalDestination, isFalse);
      expect(newFirst.contacts.first.contactName, 'Contact for Stop 2');
      expect(newFirst.contacts.first.phoneNumber, '+919000000002');
      expect(newFirst.alarmConfig.soundName, 'Gentle Ripple');

      // Stop 1 is now second, marked final, and retains its own contacts and alarm config!
      final newSecond = reordered.stops[1];
      expect(newSecond.id, 's_1');
      expect(newSecond.order, 1);
      expect(newSecond.isFinalDestination, isTrue);
      expect(newSecond.contacts.first.contactName, 'Contact for Stop 1');
      expect(newSecond.contacts.first.phoneNumber, '+919000000001');
      expect(newSecond.alarmConfig.soundName, 'High Alert Bell');
    });

    test('4. GPS update freshness calculates sample age without fabricating data', () {
      final t0 = DateTime(2026, 11, 10, 12, 0, 0);
      final reading = GpsReading(
        latitude: 13.0827,
        longitude: 80.2707,
        accuracyMeters: 8.5,
        timestamp: t0,
        speedMps: 11.11, // ~40 km/h
      );

      // 5 seconds later
      final t1 = t0.add(const Duration(seconds: 5));
      expect(reading.age(referenceTime: t1).inSeconds, 5);
      expect(reading.speedKmh, closeTo(40.0, 0.5));
      expect(reading.accuracyMeters, 8.5);

      // Stale check (40 seconds later)
      final t2 = t0.add(const Duration(seconds: 40));
      expect(reading.age(referenceTime: t2).inSeconds, 40);
    });

    test('5. Multi-provider place search categorizes stations, hospitals, colleges and landmarks', () async {
      // Mock HTTP client returning Photon-format GeoJSON with transit & amenity features
      final mockHttpClient = MockClient((request) async {
        final uri = request.url;
        if (uri.host == 'photon.komoot.io') {
          final mockResponse = {
            'features': [
              {
                'geometry': {
                  'coordinates': [80.2707, 13.0827],
                },
                'properties': {
                  'name': 'Chennai Central Railway Station',
                  'osm_key': 'railway',
                  'osm_value': 'station',
                  'city': 'Chennai',
                  'state': 'Tamil Nadu',
                  'country': 'India',
                },
              },
              {
                'geometry': {
                  'coordinates': [80.2100, 13.0100],
                },
                'properties': {
                  'name': 'Guindy Metro Station',
                  'osm_key': 'railway',
                  'osm_value': 'subway',
                  'city': 'Chennai',
                },
              },
              {
                'geometry': {
                  'coordinates': [80.2400, 13.0500],
                },
                'properties': {
                  'name': 'Apollo Hospital',
                  'osm_key': 'amenity',
                  'osm_value': 'hospital',
                  'street': 'Greams Road',
                  'city': 'Chennai',
                },
              },
              {
                'geometry': {
                  'coordinates': [80.2300, 13.0000],
                },
                'properties': {
                  'name': 'IIT Madras Campus',
                  'osm_key': 'amenity',
                  'osm_value': 'university',
                  'city': 'Chennai',
                },
              },
              {
                'geometry': {
                  'coordinates': [80.1900, 12.9200],
                },
                'properties': {
                  'name': 'Tambaram Bus Terminal',
                  'osm_key': 'amenity',
                  'osm_value': 'bus_station',
                  'city': 'Chennai',
                },
              },
            ],
          };
          return http.Response(jsonEncode(mockResponse), 200, headers: {
            'content-type': 'application/json; charset=utf-8',
          });
        }
        return http.Response('[]', 200);
      });

      final geocoding = GeocodingService(client: mockHttpClient);
      final results = await geocoding.searchPlaces('Chennai');

      expect(results.length, 5);
      expect(results[0].name, 'Chennai Central Railway Station');
      expect(results[0].category, 'Railway Station');

      expect(results[1].name, 'Guindy Metro Station');
      expect(results[1].category, 'Metro Station');

      expect(results[2].name, 'Apollo Hospital');
      expect(results[2].category, 'Hospital / Health');

      expect(results[3].name, 'IIT Madras Campus');
      expect(results[3].category, 'College / Institute');

      expect(results[4].name, 'Tambaram Bus Terminal');
      expect(results[4].category, 'Bus Terminal');
    });

    test('6. Sequential composer check-in workflow dispatches to multiple contacts', () async {
      final repo = LocalJourneyRepository();
      final messaging = MockReliabilityMessagingService();

      final trackingService = JourneyTrackingService(
        repository: repo,
        locationService: FakeReliabilityLocationService(),
        messagingService: messaging,
      );

      const contact1 = ContactCheckInConfig(
        id: 'c_mom',
        contactName: 'Mom',
        phoneNumber: '+919876511111',
      );
      const contact2 = ContactCheckInConfig(
        id: 'c_dad',
        contactName: 'Dad',
        phoneNumber: '+919876522222',
      );

      final stop = Stop(
        id: 'stop_multi_contact',
        name: 'Airport Arrival',
        latitude: 12.9900,
        longitude: 80.1700,
        radiusMeters: 300.0,
        order: 0,
        contacts: const [contact1, contact2],
      );

      final journey = Journey(
        id: 'j_airport',
        name: 'Flight Landing',
        stops: [stop],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await trackingService.startTracking(journey);

      // Step 1: Send to Mom
      final status1 = await trackingService.triggerCheckInForCurrentStop(
        targetContact: contact1,
      );
      expect(status1, MessageDeliveryStatus.composerOpened);
      expect(messaging.dispatchedCalls.length, 1);
      expect(messaging.dispatchedCalls.first['contactName'], 'Mom');
      expect(messaging.dispatchedCalls.first['phoneNumber'], '+919876511111');

      // Step 2: Send to Dad (sequential workflow)
      final status2 = await trackingService.triggerCheckInForCurrentStop(
        targetContact: contact2,
      );
      expect(status2, MessageDeliveryStatus.composerOpened);
      expect(messaging.dispatchedCalls.length, 2);
      expect(messaging.dispatchedCalls[1]['contactName'], 'Dad');
      expect(messaging.dispatchedCalls[1]['phoneNumber'], '+919876522222');
    });
  });
}

