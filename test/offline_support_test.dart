import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pathsaathi/data/station_database.dart';
import 'package:pathsaathi/models/alarm_config.dart';
import 'package:pathsaathi/models/arrival_event.dart';
import 'package:pathsaathi/models/gps_reading.dart';
import 'package:pathsaathi/models/journey.dart';
import 'package:pathsaathi/models/stop.dart';
import 'package:pathsaathi/services/arrival_detector.dart';
import 'package:pathsaathi/services/geocoding_service.dart';

class OfflineHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw http.ClientException('Simulated Network Outage (Offline Transit)');
  }
}

void main() {
  group('Milestone 5: LocalStationDatabase Curated Transit Directory', () {
    test('database contains verified transit hubs across India', () {
      expect(LocalStationDatabase.stations.length, greaterThanOrEqualTo(20));
      for (final s in LocalStationDatabase.stations) {
        expect(s.name, isNotEmpty);
        expect(s.latitude, inInclusiveRange(-90.0, 90.0));
        expect(s.longitude, inInclusiveRange(-180.0, 180.0));
        expect(s.category, anyOf(equals('Railway Station'), equals('Metro Station')));
      }
    });

    test('search returns matching stations for case-insensitive city and name queries', () {
      final masResults = LocalStationDatabase.search('chennai');
      expect(masResults.length, greaterThanOrEqualTo(3));
      expect(masResults.any((s) => s.name.contains('Central')), isTrue);
      expect(masResults.any((s) => s.name.contains('Egmore')), isTrue);
      expect(masResults.any((s) => s.name.contains('Tambaram')), isTrue);

      final metroResults = LocalStationDatabase.search('metro');
      expect(metroResults.length, greaterThanOrEqualTo(2));

      final delhiResults = LocalStationDatabase.search('delhi');
      expect(delhiResults.length, greaterThanOrEqualTo(3));

      final emptyResults = LocalStationDatabase.search('   ');
      expect(emptyResults, isEmpty);
    });

    test('findNearest resolves nearby station within tolerance radius', () {
      // 100 meters away from Chennai Central (13.0827, 80.2707)
      final nearMAS = LocalStationDatabase.findNearest(13.0835, 80.2707);
      expect(nearMAS, isNotNull);
      expect(nearMAS!.name, contains('Chennai Central'));

      // 150 meters away from Guindy Metro (13.0067, 80.2025)
      final nearGuindy = LocalStationDatabase.findNearest(13.0075, 80.2025);
      expect(nearGuindy, isNotNull);
      expect(nearGuindy!.name, contains('Guindy'));

      // Coordinates in the middle of Arabian Sea (far from any station)
      final sea = LocalStationDatabase.findNearest(15.0000, 68.0000);
      expect(sea, isNull);
    });
  });

  group('Milestone 5: GeocodingService Offline Resilience', () {
    late GeocodingService offlineService;

    setUp(() {
      offlineService = GeocodingService(client: OfflineHttpClient());
    });

    tearDown(() {
      offlineService.dispose();
    });

    test('searchPlaces gracefully falls back to local station database when network is down', () async {
      // When network throws ClientException, searchPlaces seamlessly returns curated station
      final results = await offlineService.searchPlaces('Tambaram');

      expect(results, isNotEmpty);
      expect(results.first.name, contains('Tambaram'));
      expect(results.first.latitude, closeTo(12.9249, 0.001));
      expect(results.first.longitude, closeTo(80.1000, 0.001));
    });

    test('searchPlaces returns empty list without crashing when offline query has no matches', () async {
      final results = await offlineService.searchPlaces('NonExistentPlaceXYZ987');
      expect(results, isEmpty);
    });

    test('reverseGeocode resolves to station name when near known transit hub offline', () async {
      // Coordinates right at Chennai Central
      final place = await offlineService.reverseGeocode(13.0827, 80.2707);

      expect(place, isNotNull);
      expect(place!.name, contains('Chennai Central'));
      expect(place.category, equals('Railway Station'));
    });

    test('reverseGeocode provides coordinate string fallback when offline far from stations', () async {
      // Rural highway coordinate (9.5000, 77.8000)
      final place = await offlineService.reverseGeocode(9.5000, 77.8000);

      expect(place, isNotNull);
      expect(place!.name, contains('Location (9.5000, 77.8000)'));
      expect(place.category, equals('Coordinates'));
    });
  });

  group('Milestone 5: Completely Offline Journey Monitoring', () {
    test('rule-based arrival detector runs 100% offline with zero network calls', () {
      final baseTime = DateTime(2026, 11, 10, 12, 0, 0);
      final detector = ArrivalDetector(
        consecutiveReadingsRequired: 2,
        minDwellTime: const Duration(seconds: 4),
      );

      final offlineStop = Stop(
        id: 'stop_offline_mas',
        name: 'Chennai Central',
        latitude: 13.0827,
        longitude: 80.2707,
        radiusMeters: 500.0,
        order: 0,
        alarmConfig: const AlarmConfig(soundEnabled: true, vibrationEnabled: false),
      );

      final offlineJourney = Journey(
        id: 'journey_offline',
        name: 'Offline Test Route',
        createdAt: baseTime,
        updatedAt: baseTime,
        status: JourneyStatus.active,
        stops: [offlineStop],
        activeStopIndex: 0,
      );

      // Reading 1 inside radius
      final r1 = GpsReading(
        latitude: 13.0827,
        longitude: 80.2707,
        accuracyMeters: 10.0,
        timestamp: baseTime,
      );
      final res1 = detector.evaluate(
        journey: offlineJourney,
        reading: r1,
        evaluationTime: baseTime,
      );
      expect(res1.status, equals(ArrivalStatus.approaching));

      // Reading 2 inside radius after dwell
      final t2 = baseTime.add(const Duration(seconds: 5));
      final r2 = GpsReading(
        latitude: 13.0827,
        longitude: 80.2707,
        accuracyMeters: 10.0,
        timestamp: t2,
      );
      final res2 = detector.evaluate(
        journey: offlineJourney,
        reading: r2,
        evaluationTime: t2,
      );
      expect(res2.status, equals(ArrivalStatus.arrived));
      expect(res2.isArrived, isTrue);
    });
  });
}
