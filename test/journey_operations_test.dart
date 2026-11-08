import 'package:flutter_test/flutter_test.dart';
import 'package:pathsaathi/models/alarm_config.dart';
import 'package:pathsaathi/models/contact_checkin_config.dart';
import 'package:pathsaathi/models/journey.dart';
import 'package:pathsaathi/models/stop.dart';

void main() {
  group('Journey and Stop operations', () {
    final now = DateTime(2026, 10, 25, 12, 0);

    Stop createSampleStop({
      required String id,
      required String name,
      required double lat,
      required double lon,
      int order = 0,
      bool isReached = false,
    }) {
      return Stop(
        id: id,
        name: name,
        latitude: lat,
        longitude: lon,
        radiusMeters: 400.0,
        order: order,
        isReached: isReached,
        alarmConfig: const AlarmConfig(
          soundEnabled: true,
          vibrationEnabled: true,
          snoozeDurationMinutes: 10,
        ),
        contacts: [
          ContactCheckInConfig(
            id: 'c_$id',
            contactName: 'Emergency Contact',
            phoneNumber: '+919876543210',
            customMessage: 'Arrived at $name',
          ),
        ],
      );
    }

    test('creates journey with auto-indexed stop order and final destination', () {
      final stop1 = createSampleStop(
        id: 's1',
        name: 'Station A',
        lat: 28.61,
        lon: 77.20,
      );
      final stop2 = createSampleStop(
        id: 's2',
        name: 'Station B',
        lat: 28.65,
        lon: 77.25,
      );
      final stop3 = createSampleStop(
        id: 's3',
        name: 'Station C',
        lat: 28.70,
        lon: 77.30,
      );

      final journey = Journey(
        id: 'j1',
        name: 'Delhi Metro Express',
        createdAt: now,
        updatedAt: now,
        stops: [stop1, stop2, stop3],
      );

      expect(journey.stops.length, equals(3));
      expect(journey.stops[0].order, equals(0));
      expect(journey.stops[0].isFinalDestination, isFalse);
      expect(journey.stops[1].order, equals(1));
      expect(journey.stops[1].isFinalDestination, isFalse);
      expect(journey.stops[2].order, equals(2));
      expect(journey.stops[2].isFinalDestination, isTrue);
    });

    test('adds stop dynamically and updates order and final destination', () {
      var journey = Journey(
        id: 'j1',
        name: 'Route 1',
        createdAt: now,
        updatedAt: now,
        stops: [
          createSampleStop(id: 's1', name: 'Stop 1', lat: 28.0, lon: 77.0),
        ],
      );

      expect(journey.stops[0].isFinalDestination, isFalse);

      journey = journey.addStop(
        createSampleStop(id: 's2', name: 'Stop 2', lat: 28.1, lon: 77.1),
      );

      expect(journey.stops.length, equals(2));
      expect(journey.stops[0].order, equals(0));
      expect(journey.stops[0].isFinalDestination, isFalse);
      expect(journey.stops[1].order, equals(1));
      expect(journey.stops[1].isFinalDestination, isTrue);
    });

    test('removes stop and re-indexes remaining stops', () {
      final s1 = createSampleStop(
        id: 's1',
        name: 'Stop 1',
        lat: 28.0,
        lon: 77.0,
      );
      final s2 = createSampleStop(
        id: 's2',
        name: 'Stop 2',
        lat: 28.1,
        lon: 77.1,
      );
      final s3 = createSampleStop(
        id: 's3',
        name: 'Stop 3',
        lat: 28.2,
        lon: 77.2,
      );

      var journey = Journey(
        id: 'j1',
        name: 'Route',
        createdAt: now,
        updatedAt: now,
        stops: [s1, s2, s3],
      );

      journey = journey.removeStop('s2');

      expect(journey.stops.length, equals(2));
      expect(journey.stops[0].id, equals('s1'));
      expect(journey.stops[0].order, equals(0));
      expect(journey.stops[1].id, equals('s3'));
      expect(journey.stops[1].order, equals(1));
      expect(journey.stops[1].isFinalDestination, isTrue);
    });

    test('reorders stops cleanly', () {
      final s1 = createSampleStop(
        id: 's1',
        name: 'Stop 1',
        lat: 28.0,
        lon: 77.0,
      );
      final s2 = createSampleStop(
        id: 's2',
        name: 'Stop 2',
        lat: 28.1,
        lon: 77.1,
      );
      final s3 = createSampleStop(
        id: 's3',
        name: 'Stop 3',
        lat: 28.2,
        lon: 77.2,
      );

      var journey = Journey(
        id: 'j1',
        name: 'Route',
        createdAt: now,
        updatedAt: now,
        stops: [s1, s2, s3],
      );

      // Move Stop 1 to the end
      journey = journey.reorderStops(0, 3);

      expect(journey.stops[0].id, equals('s2'));
      expect(journey.stops[1].id, equals('s3'));
      expect(journey.stops[2].id, equals('s1'));
      expect(journey.stops[2].isFinalDestination, isTrue);
    });

    test('edits an existing stop', () {
      final s1 = createSampleStop(
        id: 's1',
        name: 'Old Name',
        lat: 28.0,
        lon: 77.0,
      );
      var journey = Journey(
        id: 'j1',
        name: 'Route',
        createdAt: now,
        updatedAt: now,
        stops: [s1],
      );

      final updated = s1.copyWith(name: 'Updated Station', radiusMeters: 600.0);
      journey = journey.editStop(updated);

      expect(journey.stops[0].name, equals('Updated Station'));
      expect(journey.stops[0].radiusMeters, equals(600.0));
    });

    test('starts journey, advances active stop on arrival, completes when all reached', () {
      final s1 = createSampleStop(
        id: 's1',
        name: 'Stop 1',
        lat: 28.0,
        lon: 77.0,
      );
      final s2 = createSampleStop(
        id: 's2',
        name: 'Stop 2',
        lat: 28.1,
        lon: 77.1,
      );

      var journey = Journey(
        id: 'j1',
        name: 'Route',
        createdAt: now,
        updatedAt: now,
        stops: [s1, s2],
      );

      expect(journey.status, equals(JourneyStatus.planning));
      expect(journey.nextActiveStop, isNull);

      // Start journey
      journey = journey.start(now: now);
      expect(journey.status, equals(JourneyStatus.active));
      expect(journey.activeStopIndex, equals(0));
      expect(journey.nextActiveStop?.id, equals('s1'));

      // Mark stop 1 reached
      final reachTime1 = now.add(const Duration(minutes: 30));
      journey = journey.markStopReached('s1', reachTime1, now: reachTime1);

      expect(journey.stops[0].isReached, isTrue);
      expect(journey.stops[0].reachedAt, equals(reachTime1));
      expect(journey.activeStopIndex, equals(1));
      expect(journey.nextActiveStop?.id, equals('s2'));
      expect(journey.status, equals(JourneyStatus.active));

      // Mark stop 2 reached
      final reachTime2 = now.add(const Duration(hours: 1));
      journey = journey.markStopReached('s2', reachTime2, now: reachTime2);

      expect(journey.stops[1].isReached, isTrue);
      expect(journey.status, equals(JourneyStatus.completed));
      expect(journey.nextActiveStop, isNull);
    });

    test('cancels active journey', () {
      var journey = Journey(
        id: 'j1',
        name: 'Route',
        createdAt: now,
        updatedAt: now,
        stops: [
          createSampleStop(id: 's1', name: 'Stop 1', lat: 28.0, lon: 77.0),
        ],
      ).start(now: now);

      expect(journey.isActive, isTrue);

      journey = journey.cancel(now: now.add(const Duration(minutes: 5)));
      expect(journey.isCancelled, isTrue);
      expect(journey.nextActiveStop, isNull);
    });

    test('serializes and deserializes cleanly to JSON', () {
      final original = Journey(
        id: 'j_json',
        name: 'Intercity Journey',
        description: 'Testing JSON roundtrip',
        createdAt: now,
        updatedAt: now,
        status: JourneyStatus.active,
        activeStopIndex: 1,
        stops: [
          createSampleStop(
            id: 's1',
            name: 'Stop 1',
            lat: 28.61,
            lon: 77.20,
            isReached: true,
          ),
          createSampleStop(id: 's2', name: 'Stop 2', lat: 28.65, lon: 77.25),
        ],
      );

      final json = original.toJson();
      final restored = Journey.fromJson(json);

      expect(restored.id, equals(original.id));
      expect(restored.name, equals(original.name));
      expect(restored.description, equals(original.description));
      expect(restored.status, equals(original.status));
      expect(restored.activeStopIndex, equals(original.activeStopIndex));
      expect(restored.stops.length, equals(original.stops.length));
      expect(restored.stops[0].name, equals(original.stops[0].name));
      expect(restored.stops[0].isReached, isTrue);
      expect(
        restored.stops[0].alarmConfig.soundName,
        equals(original.stops[0].alarmConfig.soundName),
      );
      expect(
        restored.stops[0].contacts.first.phoneNumber,
        equals(original.stops[0].contacts.first.phoneNumber),
      );
    });
  });
}
