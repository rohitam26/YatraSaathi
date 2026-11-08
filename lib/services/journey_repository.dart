import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/journey.dart';

/// Repository interface for managing journey persistence.
abstract class JourneyRepository {
  Future<List<Journey>> getJourneys();
  Future<Journey?> getJourney(String id);
  Future<void> saveJourney(Journey journey);
  Future<void> deleteJourney(String id);
  Future<Journey?> getActiveJourney();
  Future<void> setActiveJourneyId(String? id);
  Future<void> clearAll();
}

/// Local persistence implementation using Android/iOS platform storage
/// via SharedPreferences with JSON serialization.
class LocalJourneyRepository implements JourneyRepository {
  LocalJourneyRepository({SharedPreferences? preferences})
    : _preferencesOverride = preferences;

  final SharedPreferences? _preferencesOverride;

  static const String _journeysKey = 'yatrasaathi_saved_journeys_v1';
  static const String _activeJourneyIdKey = 'yatrasaathi_active_journey_id_v1';

  Future<SharedPreferences> get _prefs async =>
      _preferencesOverride ?? await SharedPreferences.getInstance();

  @override
  Future<List<Journey>> getJourneys() async {
    final prefs = await _prefs;
    final jsonStrings = prefs.getStringList(_journeysKey) ?? <String>[];
    final journeys = <Journey>[];

    for (final jsonStr in jsonStrings) {
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        journeys.add(Journey.fromJson(map));
      } catch (_) {
        // Skip malformed entries without crashing
      }
    }

    // Sort by most recently updated
    journeys.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return journeys;
  }

  @override
  Future<Journey?> getJourney(String id) async {
    final journeys = await getJourneys();
    for (final j in journeys) {
      if (j.id == id) return j;
    }
    return null;
  }

  @override
  Future<void> saveJourney(Journey journey) async {
    final prefs = await _prefs;
    final journeys = await getJourneys();

    final index = journeys.indexWhere((j) => j.id == journey.id);
    if (index >= 0) {
      journeys[index] = journey;
    } else {
      journeys.add(journey);
    }

    final jsonList = journeys.map((j) => jsonEncode(j.toJson())).toList();
    await prefs.setStringList(_journeysKey, jsonList);

    // If journey status became active, track it as active
    if (journey.isActive) {
      await prefs.setString(_activeJourneyIdKey, journey.id);
    } else {
      final currentActiveId = prefs.getString(_activeJourneyIdKey);
      if (currentActiveId == journey.id) {
        await prefs.remove(_activeJourneyIdKey);
      }
    }
  }

  @override
  Future<void> deleteJourney(String id) async {
    final prefs = await _prefs;
    final journeys = await getJourneys();
    journeys.removeWhere((j) => j.id == id);

    final jsonList = journeys.map((j) => jsonEncode(j.toJson())).toList();
    await prefs.setStringList(_journeysKey, jsonList);

    final currentActiveId = prefs.getString(_activeJourneyIdKey);
    if (currentActiveId == id) {
      await prefs.remove(_activeJourneyIdKey);
    }
  }

  @override
  Future<Journey?> getActiveJourney() async {
    final prefs = await _prefs;
    final activeId = prefs.getString(_activeJourneyIdKey);
    if (activeId == null) {
      // Fallback: search for any journey currently marked active
      final journeys = await getJourneys();
      for (final j in journeys) {
        if (j.isActive) {
          await prefs.setString(_activeJourneyIdKey, j.id);
          return j;
        }
      }
      return null;
    }
    return getJourney(activeId);
  }

  @override
  Future<void> setActiveJourneyId(String? id) async {
    final prefs = await _prefs;
    if (id == null) {
      await prefs.remove(_activeJourneyIdKey);
    } else {
      await prefs.setString(_activeJourneyIdKey, id);
    }
  }

  @override
  Future<void> clearAll() async {
    final prefs = await _prefs;
    await prefs.remove(_journeysKey);
    await prefs.remove(_activeJourneyIdKey);
  }
}
