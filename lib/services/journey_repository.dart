import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/commute_schedule.dart';
import '../models/journey.dart';
import '../models/safety_contact.dart';
import '../models/user_profile.dart';

/// Repository interface for managing journey persistence and safety contacts.
abstract class JourneyRepository {
  Future<List<Journey>> getJourneys();
  Future<Journey?> getJourney(String id);
  Future<void> saveJourney(Journey journey);
  Future<void> deleteJourney(String id);
  Future<Journey?> getActiveJourney();
  Future<void> setActiveJourneyId(String? id);
  Future<UserProfile> getUserProfile();
  Future<void> saveUserProfile(UserProfile profile);
  Future<List<SafetyContact>> getSafetyContacts();
  Future<void> saveSafetyContact(SafetyContact contact);
  Future<void> deleteSafetyContact(String id);
  Future<void> setPrimaryContact(String id);
  Future<List<CommuteSchedule>> getCommuteSchedules();
  Future<CommuteSchedule?> getCommuteSchedule(String id);
  Future<void> saveCommuteSchedule(CommuteSchedule schedule);
  Future<void> deleteCommuteSchedule(String id);
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
  static const String _userProfileKey = 'yatrasaathi_user_profile_v1';
  static const String _safetyContactsKey = 'yatrasaathi_safety_contacts_v1';
  static const String _commuteSchedulesKey = 'yatrasaathi_commute_schedules_v1';

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

    // If journey status became active or paused, track it as active session
    if (journey.isActive || journey.isPaused) {
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
      // Fallback: search for any journey currently marked active or paused
      final journeys = await getJourneys();
      for (final j in journeys) {
        if (j.isActive || j.isPaused) {
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
  Future<UserProfile> getUserProfile() async {
    final prefs = await _prefs;
    final jsonStr = prefs.getString(_userProfileKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      // Legacy fallback
      final name = prefs.getString('pref_contact_name') ?? '';
      final phone = prefs.getString('pref_contact_phone') ?? '';
      final msg = prefs.getString('pref_checkin_msg') ?? '';
      if (name.isNotEmpty || phone.isNotEmpty) {
        return UserProfile(
          defaultContactName: name,
          defaultContactPhone: phone,
          defaultMessage: msg.isNotEmpty
              ? msg
              : 'Hi! I have safely reached my stop. - Sent via STOP Vanthachu',
        );
      }
      return const UserProfile();
    }
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return UserProfile.fromJson(map);
    } catch (_) {
      return const UserProfile();
    }
  }

  @override
  Future<void> saveUserProfile(UserProfile profile) async {
    final prefs = await _prefs;
    await prefs.setString(_userProfileKey, jsonEncode(profile.toJson()));
    // Sync legacy keys for backward compatibility
    await prefs.setString('pref_contact_name', profile.defaultContactName);
    await prefs.setString('pref_contact_phone', profile.defaultContactPhone);
    await prefs.setString('pref_checkin_msg', profile.defaultMessage);
  }

  @override
  Future<List<SafetyContact>> getSafetyContacts() async {
    final prefs = await _prefs;
    final jsonStrings = prefs.getStringList(_safetyContactsKey);

    if (jsonStrings == null || jsonStrings.isEmpty) {
      // Automatic migration: If no contacts saved yet, inspect UserProfile
      final profile = await getUserProfile();
      if (profile.hasDefaultContact) {
        final migrated = SafetyContact(
          id: 'contact_migrated_primary',
          name: profile.defaultContactName,
          phoneNumber: profile.defaultContactPhone,
          countryCode: profile.countryCode,
          relationship: profile.defaultContactRelation,
          isPrimary: true,
          createdAt: DateTime.now(),
        );
        await prefs.setStringList(_safetyContactsKey, [jsonEncode(migrated.toJson())]);
        return [migrated];
      }
      return <SafetyContact>[];
    }

    final contacts = <SafetyContact>[];
    for (final str in jsonStrings) {
      try {
        final map = jsonDecode(str) as Map<String, dynamic>;
        contacts.add(SafetyContact.fromJson(map));
      } catch (_) {}
    }

    // Sort: primary first, then newest
    contacts.sort((a, b) {
      if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return contacts;
  }

  @override
  Future<void> saveSafetyContact(SafetyContact contact) async {
    final prefs = await _prefs;
    final contacts = await getSafetyContacts();

    // If marked primary, ensure other contacts are un-marked
    if (contact.isPrimary) {
      for (int i = 0; i < contacts.length; i++) {
        if (contacts[i].id != contact.id) {
          contacts[i] = contacts[i].copyWith(isPrimary: false);
        }
      }
    }

    final index = contacts.indexWhere((c) => c.id == contact.id);
    if (index >= 0) {
      contacts[index] = contact;
    } else {
      // If this is the only contact, automatically mark it primary
      final toAdd = contacts.isEmpty ? contact.copyWith(isPrimary: true) : contact;
      contacts.add(toAdd);
    }

    final jsonList = contacts.map((c) => jsonEncode(c.toJson())).toList();
    await prefs.setStringList(_safetyContactsKey, jsonList);
  }

  @override
  Future<void> deleteSafetyContact(String id) async {
    final prefs = await _prefs;
    final contacts = await getSafetyContacts();
    final removed = contacts.where((c) => c.id == id).firstOrNull;
    contacts.removeWhere((c) => c.id == id);

    // If the removed contact was primary, promote the next available contact
    if (removed?.isPrimary == true && contacts.isNotEmpty) {
      contacts[0] = contacts[0].copyWith(isPrimary: true);
    }

    final jsonList = contacts.map((c) => jsonEncode(c.toJson())).toList();
    await prefs.setStringList(_safetyContactsKey, jsonList);
  }

  @override
  Future<void> setPrimaryContact(String id) async {
    final prefs = await _prefs;
    final contacts = await getSafetyContacts();
    for (int i = 0; i < contacts.length; i++) {
      contacts[i] = contacts[i].copyWith(isPrimary: contacts[i].id == id);
    }
    final jsonList = contacts.map((c) => jsonEncode(c.toJson())).toList();
    await prefs.setStringList(_safetyContactsKey, jsonList);
  }

  @override
  Future<List<CommuteSchedule>> getCommuteSchedules() async {
    final prefs = await _prefs;
    final jsonStrings = prefs.getStringList(_commuteSchedulesKey) ?? <String>[];
    final schedules = <CommuteSchedule>[];

    for (final jsonStr in jsonStrings) {
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        schedules.add(CommuteSchedule.fromJson(map));
      } catch (_) {
        // Skip malformed entries
      }
    }

    schedules.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return schedules;
  }

  @override
  Future<CommuteSchedule?> getCommuteSchedule(String id) async {
    final schedules = await getCommuteSchedules();
    for (final s in schedules) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<void> saveCommuteSchedule(CommuteSchedule schedule) async {
    final prefs = await _prefs;
    final schedules = await getCommuteSchedules();

    final index = schedules.indexWhere((s) => s.id == schedule.id);
    if (index >= 0) {
      schedules[index] = schedule;
    } else {
      schedules.add(schedule);
    }

    final jsonList = schedules.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_commuteSchedulesKey, jsonList);
  }

  @override
  Future<void> deleteCommuteSchedule(String id) async {
    final prefs = await _prefs;
    final schedules = await getCommuteSchedules();
    schedules.removeWhere((s) => s.id == id);

    final jsonList = schedules.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_commuteSchedulesKey, jsonList);
  }

  @override
  Future<void> clearAll() async {
    final prefs = await _prefs;
    await prefs.remove(_journeysKey);
    await prefs.remove(_activeJourneyIdKey);
    await prefs.remove(_userProfileKey);
    await prefs.remove(_safetyContactsKey);
    await prefs.remove(_commuteSchedulesKey);
  }
}
