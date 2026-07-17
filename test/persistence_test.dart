import 'package:flutter_test/flutter_test.dart';
import 'package:pathsaathi/models/journey.dart';
import 'package:pathsaathi/models/stop.dart';
import 'package:pathsaathi/services/journey_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalJourneyRepository Persistence', () {
    final now = DateTime(2026, 10, 25, 10, 0);

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('returns empty list when no journeys are stored', () async {
      final repo = LocalJourneyRepository();
      final list = await repo.getJourneys();
      expect(list, isEmpty);

      final active = await repo.getActiveJourney();
      expect(active, isNull);
    });

    test('saves a journey and retrieves it successfully', () async {
      final repo = LocalJourneyRepository();

      final journey = Journey(
        id: 'j_saved',
        name: 'Work to Home',
        description: 'Daily evening commute',
        createdAt: now,
        updatedAt: now,
        stops: [
          Stop(
            id: 's_stop1',
            name: 'Office Metro',
            latitude: 28.50,
            longitude: 77.10,
            radiusMeters: 300,
            order: 0,
          ),
          Stop(
            id: 's_stop2',
            name: 'Home Station',
            latitude: 28.60,
            longitude: 77.20,
            radiusMeters: 500,
            order: 1,
            isFinalDestination: true,
          ),
        ],
      );

      await repo.saveJourney(journey);

      final all = await repo.getJourneys();
      expect(all.length, equals(1));
      expect(all.first.id, equals('j_saved'));
      expect(all.first.name, equals('Work to Home'));
      expect(all.first.stops.length, equals(2));
      expect(all.first.stops[1].name, equals('Home Station'));
      expect(all.first.stops[1].isFinalDestination, isTrue);
    });

    test('updates existing journey by id', () async {
      final repo = LocalJourneyRepository();

      final journey = Journey(
        id: 'j_update',
        name: 'Initial Name',
        createdAt: now,
        updatedAt: now,
      );

      await repo.saveJourney(journey);

      final updated = journey.copyWith(
        name: 'Modified Name',
        updatedAt: now.add(const Duration(minutes: 10)),
      );
      await repo.saveJourney(updated);

      final all = await repo.getJourneys();
      expect(all.length, equals(1));
      expect(all.first.name, equals('Modified Name'));
    });

    test('tracks active journey ID across simulated restarts', () async {
      final repo = LocalJourneyRepository();

      final activeJourney = Journey(
        id: 'j_active_commute',
        name: 'Active Route',
        createdAt: now,
        updatedAt: now,
        status: JourneyStatus.active,
        stops: [
          Stop(
            id: 's1',
            name: 'Intermediate Junction',
            latitude: 28.5,
            longitude: 77.1,
            order: 0,
          ),
        ],
        activeStopIndex: 0,
      );

      await repo.saveJourney(activeJourney);

      // Verify active journey getter
      final loadedActive = await repo.getActiveJourney();
      expect(loadedActive, isNotNull);
      expect(loadedActive?.id, equals('j_active_commute'));
      expect(loadedActive?.isActive, isTrue);

      // Cancel journey and save
      final cancelled = activeJourney.cancel();
      await repo.saveJourney(cancelled);

      final postCancelActive = await repo.getActiveJourney();
      expect(postCancelActive, isNull);
    });

    test('deletes journey and removes from active if it was active', () async {
      final repo = LocalJourneyRepository();

      final j1 = Journey(
        id: 'j1',
        name: 'Journey One',
        createdAt: now,
        updatedAt: now,
        status: JourneyStatus.active,
      );
      final j2 = Journey(
        id: 'j2',
        name: 'Journey Two',
        createdAt: now,
        updatedAt: now,
      );

      await repo.saveJourney(j1);
      await repo.saveJourney(j2);

      expect((await repo.getJourneys()).length, equals(2));
      expect((await repo.getActiveJourney())?.id, equals('j1'));

      await repo.deleteJourney('j1');

      final remaining = await repo.getJourneys();
      expect(remaining.length, equals(1));
      expect(remaining.first.id, equals('j2'));
      expect(await repo.getActiveJourney(), isNull);
    });
  });
}
