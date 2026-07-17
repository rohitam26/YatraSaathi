import 'package:flutter_test/flutter_test.dart';
import 'package:pathsaathi/services/distance_calculator.dart';

void main() {
  const calculator = HaversineDistanceCalculator();

  group('HaversineDistanceCalculator', () {
    test('returns 0 when coordinates are identical', () {
      final distance = calculator.distanceMeters(
        lat1: 28.6139,
        lon1: 77.2090,
        lat2: 28.6139,
        lon2: 77.2090,
      );
      expect(distance, equals(0.0));
    });

    test('calculates accurate distance between New Delhi and Mumbai', () {
      // New Delhi: 28.6139° N, 77.2090° E
      // Mumbai: 19.0760° N, 72.8777° E
      // Known great circle distance is approx 1,148 km (+/- 10 km)
      final distance = calculator.distanceMeters(
        lat1: 28.6139,
        lon1: 77.2090,
        lat2: 19.0760,
        lon2: 72.8777,
      );
      final km = distance / 1000.0;
      expect(km, greaterThan(1140.0));
      expect(km, lessThan(1160.0));
    });

    test('calculates short urban distances accurately', () {
      // ~500 meters along latitude
      final distance = calculator.distanceMeters(
        lat1: 28.6100,
        lon1: 77.2000,
        lat2: 28.6145,
        lon2: 77.2000,
      );
      expect(distance, greaterThan(490.0));
      expect(distance, lessThan(510.0));
    });

    test('validates coordinate boundaries', () {
      expect(HaversineDistanceCalculator.isValidCoordinate(0.0, 0.0), isTrue);
      expect(
        HaversineDistanceCalculator.isValidCoordinate(90.0, 180.0),
        isTrue,
      );
      expect(
        HaversineDistanceCalculator.isValidCoordinate(-90.0, -180.0),
        isTrue,
      );
      expect(
        HaversineDistanceCalculator.isValidCoordinate(90.1, 50.0),
        isFalse,
      );
      expect(
        HaversineDistanceCalculator.isValidCoordinate(-90.1, 50.0),
        isFalse,
      );
      expect(
        HaversineDistanceCalculator.isValidCoordinate(50.0, 180.1),
        isFalse,
      );
      expect(
        HaversineDistanceCalculator.isValidCoordinate(50.0, -180.1),
        isFalse,
      );
      expect(
        HaversineDistanceCalculator.isValidCoordinate(double.nan, 50.0),
        isFalse,
      );
    });

    test('throws ArgumentError on invalid start coordinates', () {
      expect(
        () => calculator.distanceMeters(
          lat1: 95.0,
          lon1: 77.0,
          lat2: 28.0,
          lon2: 77.0,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError on invalid destination coordinates', () {
      expect(
        () => calculator.distanceMeters(
          lat1: 28.0,
          lon1: 77.0,
          lat2: 28.0,
          lon2: -195.0,
        ),
        throwsArgumentError,
      );
    });
  });
}
