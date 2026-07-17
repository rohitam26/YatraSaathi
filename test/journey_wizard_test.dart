import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pathsaathi/models/alarm_config.dart';
import 'package:pathsaathi/models/contact_checkin_config.dart';
import 'package:pathsaathi/models/gps_reading.dart';
import 'package:pathsaathi/models/journey.dart';
import 'package:pathsaathi/models/stop.dart';
import 'package:pathsaathi/services/geocoding_service.dart';
import 'package:pathsaathi/services/journey_repository.dart';
import 'package:pathsaathi/services/journey_tracking_service.dart';
import 'package:pathsaathi/services/location_service.dart';
import 'package:pathsaathi/ui/journey_wizard_screen.dart';
import 'package:pathsaathi/ui/widgets/journey_map_view.dart';
import 'package:pathsaathi/ui/widgets/map_location_picker.dart';
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

  @override
  Future<GpsReading?> getCurrentReading() async {
    return GpsReading(
      latitude: 13.0827,
      longitude: 80.2707,
      accuracyMeters: 10,
      timestamp: DateTime(2026, 1, 1),
    );
  }
}

class MockOfflineClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw Exception('Simulated Offline Network');
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('JourneyWizardScreen UX Redesign Tests', () {
    testWidgets('renders 5-step wizard and validates required fields in Step 1', (
      WidgetTester tester,
    ) async {
      final repo = LocalJourneyRepository();
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: JourneyWizardScreen(repository: repo),
        ),
      );
      await tester.pump();

      // Check Wizard AppBar title
      expect(find.text('Plan a Journey'), findsOneWidget);

      // Verify Step Titles in horizontal stepper
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Stops'), findsOneWidget);
      expect(find.text('Alerts'), findsOneWidget);
      expect(find.text('Safety'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);

      // Verify Step 1 fields
      expect(find.text('Name Your Journey'), findsOneWidget);
      expect(find.text('Journey Name *'), findsOneWidget);
      expect(find.text('Starting Point'), findsWidgets);
      expect(find.text('Final Destination'), findsWidgets);

      // Try tapping Next Step without filling mandatory journey name
      await tester.tap(find.text('Next Step'));
      await tester.pump();

      // Should show validation error
      expect(find.text('Please name your journey'), findsOneWidget);
    });

    testWidgets('populates existing journey into wizard cleanly for editing', (
      WidgetTester tester,
    ) async {
      final repo = LocalJourneyRepository();
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final existingJourney = Journey(
        id: 'existing_test_1',
        name: 'Chennai Central to Bangalore',
        status: JourneyStatus.planning,
        stops: [
          Stop(
            id: 'stop_1',
            name: 'Chennai Central',
            latitude: 13.0827,
            longitude: 80.2707,
            radiusMeters: 500,
            order: 0,
            isFinalDestination: false,
          ),
          Stop(
            id: 'stop_2',
            name: 'Katpadi Junction',
            latitude: 12.9698,
            longitude: 79.1378,
            radiusMeters: 500,
            order: 1,
            isFinalDestination: false,
          ),
          Stop(
            id: 'stop_3',
            name: 'Bangalore City',
            latitude: 12.9716,
            longitude: 77.5946,
            radiusMeters: 500,
            order: 2,
            isFinalDestination: true,
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: JourneyWizardScreen(
            existingJourney: existingJourney,
            repository: repo,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Edit Journey'), findsOneWidget);
      expect(find.text('Chennai Central to Bangalore'), findsOneWidget);

      // Navigate to Step 2 (Stops)
      await tester.tap(find.text('Next Step'));
      await tester.pump();

      expect(find.textContaining('Journey Stops'), findsOneWidget);
      expect(find.text('Chennai Central'), findsWidgets);
      expect(find.text('Katpadi Junction'), findsWidgets);
      expect(find.text('Bangalore City'), findsWidgets);
    });

    testWidgets('JourneyMapView renders without crash when empty or populated', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Empty map view
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: JourneyMapView(stops: []),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(JourneyMapView), findsOneWidget);

      // Populated map view
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JourneyMapView(
              stops: [
                Stop(
                  id: 's1',
                  name: 'Start',
                  latitude: 13.0827,
                  longitude: 80.2707,
                  radiusMeters: 500,
                  order: 0,
                  isFinalDestination: false,
                ),
                Stop(
                  id: 's2',
                  name: 'End',
                  latitude: 13.0850,
                  longitude: 80.2750,
                  radiusMeters: 500,
                  order: 1,
                  isFinalDestination: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(JourneyMapView), findsOneWidget);
    });

    testWidgets('MapLocationPicker renders search bar, controls, and opens manual coordinate dialog', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: MapLocationPicker(
            initialLatitude: 13.0827,
            initialLongitude: 80.2707,
            initialPlaceName: 'Chennai Central',
            locationService: FakeLocationService(),
            geocodingService: GeocodingService(client: MockOfflineClient()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Choose Location on Map'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget); // Search bar
      expect(find.byTooltip('Manual Coordinates'), findsOneWidget);
      expect(find.byTooltip('My Location'), findsOneWidget);
      expect(find.text('Use This Location'), findsOneWidget);

      // Tap Manual Coordinates FAB
      await tester.tap(find.byTooltip('Manual Coordinates'));
      await tester.pumpAndSettle();

      expect(find.text('Manual Coordinates (Offline Fallback)'), findsOneWidget);
      expect(find.text('Latitude (-90 to +90)'), findsOneWidget);
      expect(find.text('Longitude (-180 to +180)'), findsOneWidget);

      // Cancel dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Manual Coordinates (Offline Fallback)'), findsNothing);
    });

    test('GeocodingService reverse geocode offline fallback works gracefully', () async {
      final service = GeocodingService(client: MockOfflineClient());
      final place = await service.reverseGeocode(13.0827, 80.2707);
      expect(place, isNotNull);
      expect(place!.latitude, 13.0827);
      expect(place.longitude, 80.2707);
      expect(place.name, isNotEmpty);
      expect(place.address, isNotEmpty);
      service.dispose();
    });

    test('Stop retains custom alarm and contact configuration when edited and reordered', () {
      final stop1 = Stop(
        id: 'stop_1',
        name: 'Tambaram',
        latitude: 12.9249,
        longitude: 80.1000,
        radiusMeters: 1000,
        order: 0,
        alarmConfig: const AlarmConfig(
          soundEnabled: true,
          soundName: 'High Alert Bell',
          vibrationEnabled: true,
          maxRepeats: 5,
        ),
        contacts: [
          const ContactCheckInConfig(
            id: 'c1',
            contactName: 'Emergency Contact',
            phoneNumber: '+91 98765 43210',
            customMessage: 'Reached Tambaram safely',
          ),
        ],
      );

      final stop2 = Stop(
        id: 'stop_2',
        name: 'Chengalpattu',
        latitude: 12.6841,
        longitude: 79.9836,
        radiusMeters: 2000,
        order: 1,
        isFinalDestination: true,
        alarmConfig: const AlarmConfig(
          soundEnabled: false,
          soundName: 'Default Chime',
          vibrationEnabled: true,
        ),
      );

      // Reorder stops
      final journey = Journey(
        id: 'j1',
        name: 'Suburban Commute',
        stops: [stop1, stop2],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(journey.stops.length, 2);
      expect(journey.stops[0].name, 'Tambaram');
      expect(journey.stops[0].alarmConfig.soundName, 'High Alert Bell');
      expect(journey.stops[0].contacts.first.phoneNumber, '+91 98765 43210');
      expect(journey.stops[1].alarmConfig.soundEnabled, false);

      // Reorder to put stop2 first
      final reordered = journey.reorderStops(1, 0);
      expect(reordered.stops[0].name, 'Chengalpattu');
      expect(reordered.stops[0].alarmConfig.soundEnabled, false);
      expect(reordered.stops[1].name, 'Tambaram');
      expect(reordered.stops[1].alarmConfig.soundName, 'High Alert Bell');
      expect(reordered.stops[1].contacts.first.customMessage, 'Reached Tambaram safely');
    });

    test('JourneyTrackingService restoreActiveSession recovers target stop correctly', () async {
      final repo = LocalJourneyRepository();
      final stop1 = Stop(
        id: 's1',
        name: 'Start Stop',
        latitude: 13.0827,
        longitude: 80.2707,
        radiusMeters: 500,
        order: 0,
        isReached: true, // reached
      );
      final stop2 = Stop(
        id: 's2',
        name: 'Target Station',
        latitude: 13.0850,
        longitude: 80.2800,
        radiusMeters: 500,
        order: 1,
        isReached: false, // next active stop!
        isFinalDestination: true,
      );
      final journey = Journey(
        id: 'active_journey_restore',
        name: 'Express Route',
        status: JourneyStatus.active,
        stops: [stop1, stop2],
        activeStopIndex: 1,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repo.saveJourney(journey);
      await repo.setActiveJourneyId(journey.id);

      final trackingService = JourneyTrackingService(
        repository: repo,
        locationService: FakeLocationService(),
      );
      final restored = await trackingService.restoreActiveSession();

      expect(restored, isTrue);
      expect(trackingService.currentState.state, TrackingState.monitoring);
      expect(trackingService.currentState.currentStop, isNotNull);
      expect(trackingService.currentState.currentStop!.name, 'Target Station');
      expect(trackingService.currentState.activeJourney!.nextActiveStop!.name, 'Target Station');
      expect(trackingService.currentState.activeJourney!.remainingStops.length, 1);
    });
  });
}
