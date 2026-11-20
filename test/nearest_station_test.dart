import 'package:flutter_test/flutter_test.dart';
import 'package:pathsaathi/models/gps_reading.dart';
import 'package:pathsaathi/services/nearest_station_service.dart';

void main() {
  group('Issue 2: GPS & Nearest-Station Detection Correction Tests', () {
    final service = NearestStationService();

    test('detects passenger is "At Guindy Metro & Station" when within 300m and NOT Near Central', () {
      final guindyReading = GpsReading(
        latitude: 13.0067,
        longitude: 80.2025,
        accuracyMeters: 8.0,
        timestamp: DateTime.now(),
      );

      final result = service.calculateNearestStation(guindyReading);

      expect(result.proximityType, equals(StationProximityType.atStation));
      expect(result.nearestStation?.name, equals('Guindy Metro & Station'));
      expect(result.displayTitle, equals('At Guindy Metro & Station'));
      expect(result.displayTitle, isNot(contains('Central')));
      expect(result.isNearby, isTrue);
    });

    test('detects passenger is "At Tambaram (TBM)" and NOT Near Central', () {
      final tambaramReading = GpsReading(
        latitude: 12.9249,
        longitude: 80.1000,
        accuracyMeters: 10.0,
        timestamp: DateTime.now(),
      );

      final result = service.calculateNearestStation(tambaramReading);

      expect(result.proximityType, equals(StationProximityType.atStation));
      expect(result.nearestStation?.name, equals('Tambaram (TBM)'));
      expect(result.displayTitle, equals('At Tambaram (TBM)'));
      expect(result.displayTitle, isNot(contains('Central')));
      expect(result.isNearby, isTrue);
    });

    test('detects passenger is genuinely "At Chennai Central (MAS)" when at Central coordinates', () {
      final centralReading = GpsReading(
        latitude: 13.0827,
        longitude: 80.2707,
        accuracyMeters: 6.0,
        timestamp: DateTime.now(),
      );

      final result = service.calculateNearestStation(centralReading);

      expect(result.proximityType, equals(StationProximityType.atStation));
      expect(result.nearestStation?.name, equals('Chennai Central (MAS)'));
      expect(result.displayTitle, equals('At Chennai Central (MAS)'));
    });

    test('classifies location between 300m and 3km as "Near [Station] (approx. X km)"', () {
      // Point approx. 1.2 km from Guindy
      final nearGuindyReading = GpsReading(
        latitude: 13.0150,
        longitude: 80.2080,
        accuracyMeters: 12.0,
        timestamp: DateTime.now(),
      );

      final result = service.calculateNearestStation(nearGuindyReading);

      expect(result.proximityType, equals(StationProximityType.nearStation));
      expect(result.nearestStation?.name, equals('Guindy Metro & Station'));
      expect(result.displayTitle, contains('Near Guindy Metro & Station'));
      expect(result.displayTitle, contains('km'));
      expect(result.isNearby, isTrue);
    });

    test('identifies distant location (> 3km) without falsely claiming user is near station', () {
      // User is located in rural Tamil Nadu highway (30+ km from closest station)
      final ruralReading = GpsReading(
        latitude: 12.5000,
        longitude: 79.5000,
        accuracyMeters: 15.0,
        timestamp: DateTime.now(),
      );

      final result = service.calculateNearestStation(ruralReading);

      expect(result.proximityType, equals(StationProximityType.distantStation));
      expect(result.displayTitle, startsWith('Nearest:'));
      expect(result.displayTitle, contains('away'));
      expect(result.displaySubtitle, contains('Outside immediate station vicinity'));
      expect(result.isNearby, isFalse);
    });

    test('never claims user in Bangalore is near Chennai Central', () {
      final bangaloreReading = GpsReading(
        latitude: 12.9716,
        longitude: 77.5946,
        accuracyMeters: 15.0,
        timestamp: DateTime.now(),
      );

      final result = service.calculateNearestStation(bangaloreReading);

      expect(result.nearestStation?.name, isNot(contains('Chennai Central')));
      expect(result.displayTitle, isNot(contains('Chennai Central')));
      expect(result.nearestStation?.address, contains('Bengaluru'));
    });

    test('returns "Finding your location..." when GPS reading is null', () {
      final result = service.calculateNearestStation(null);

      expect(result.proximityType, equals(StationProximityType.unavailable));
      expect(result.displayTitle, equals('Finding your location...'));
      expect(result.nearestStation, isNull);
    });

    test('rejects uninitialized Null Island (0.0, 0.0) coordinates', () {
      final nullIslandReading = GpsReading(
        latitude: 0.0,
        longitude: 0.0,
        accuracyMeters: 10.0,
        timestamp: DateTime.now(),
      );

      final result = service.calculateNearestStation(nullIslandReading);

      expect(result.proximityType, equals(StationProximityType.unavailable));
      expect(result.statusMessage, contains('uninitialized GPS fix'));
    });

    test('flags degraded accuracy when accuracy exceeds 150 meters', () {
      final lowAccuracyReading = GpsReading(
        latitude: 13.0827,
        longitude: 80.2707,
        accuracyMeters: 250.0,
        timestamp: DateTime.now(),
      );

      final result = service.calculateNearestStation(lowAccuracyReading);

      expect(result.proximityType, equals(StationProximityType.unavailable));
      expect(result.isAccurate, isFalse);
      expect(result.statusMessage, contains('Location accuracy low (±250m)'));
    });

    test('formats GPS accuracy and sample freshness in debug telemetry', () {
      final fixTime = DateTime.now().subtract(const Duration(seconds: 12));
      final reading = GpsReading(
        latitude: 13.0067,
        longitude: 80.2012,
        accuracyMeters: 14.5,
        timestamp: fixTime,
      );

      final result = service.calculateNearestStation(reading);

      expect(result.debugTelemetry, contains('13.0067'));
      expect(result.debugTelemetry, contains('80.2012'));
      expect(result.debugTelemetry, contains('±14.5m'));
      expect(result.debugTelemetry, contains('12s ago'));
    });
  });
}
