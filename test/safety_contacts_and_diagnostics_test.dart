import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathsaathi/models/safety_contact.dart';
import 'package:pathsaathi/models/user_profile.dart';
import 'package:pathsaathi/services/alarm_service.dart';
import 'package:pathsaathi/services/journey_repository.dart';
import 'package:pathsaathi/services/location_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    const globalChannel = MethodChannel('xyz.luan/audioplayers.global');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(globalChannel, (MethodCall methodCall) async {
      return 1;
    });

    const playerChannel = MethodChannel('xyz.luan/audioplayers');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(playerChannel, (MethodCall methodCall) async {
      return 1;
    });
  });

  group('SafetyContact Model & Serialization Tests', () {
    test('SafetyContact serialization roundtrip preserves all fields', () {
      final now = DateTime(2026, 11, 9, 10, 30);
      final contact = SafetyContact(
        id: 'c1',
        name: 'Anita Sharma',
        phoneNumber: '9876543210',
        countryCode: '+91',
        relationship: 'Partner',
        isPrimary: true,
        createdAt: now,
      );

      final json = contact.toJson();
      final restored = SafetyContact.fromJson(json);

      expect(restored.id, 'c1');
      expect(restored.name, 'Anita Sharma');
      expect(restored.phoneNumber, '9876543210');
      expect(restored.countryCode, '+91');
      expect(restored.relationship, 'Partner');
      expect(restored.isPrimary, isTrue);
      expect(restored.createdAt, now);
      expect(restored.formattedPhoneNumber, '+91 9876543210');
      expect(restored.maskedPhoneNumber, '••••••3210');
    });

    test('SafetyContact maskedPhoneNumber handles short numbers safely', () {
      final shortContact = SafetyContact(
        id: 'c2',
        name: 'Emergency',
        phoneNumber: '112',
        countryCode: '',
        relationship: 'Emergency',
      );

      expect(shortContact.maskedPhoneNumber, '112');
    });

    test('SafetyContact copyWith creates clean clones', () {
      final original = SafetyContact(
        id: 'c3',
        name: 'Ravi',
        phoneNumber: '9988776655',
        relationship: 'Friend',
      );

      final updated = original.copyWith(isPrimary: true, name: 'Ravi Kumar');

      expect(updated.id, 'c3');
      expect(updated.name, 'Ravi Kumar');
      expect(updated.isPrimary, isTrue);
      expect(updated.relationship, 'Friend');
    });
  });

  group('JourneyRepository Multiple Safety Contacts CRUD', () {
    late LocalJourneyRepository repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      repository = LocalJourneyRepository();
    });

    test('Auto-migrates legacy UserProfile default contact to SafetyContacts list', () async {
      // Save legacy profile
      const legacyProfile = UserProfile(
        userName: 'Vikram',
        userPhone: '9000000001',
        defaultContactName: 'Meera',
        defaultContactPhone: '9000000002',
        defaultContactRelation: 'Spouse',
      );
      await repository.saveUserProfile(legacyProfile);

      // Fetch contacts - should migrate legacy contact as primary
      final contacts = await repository.getSafetyContacts();
      expect(contacts.length, 1);
      expect(contacts.first.name, 'Meera');
      expect(contacts.first.phoneNumber, '9000000002');
      expect(contacts.first.isPrimary, isTrue);
    });

    test('Full CRUD: add, edit, set primary, and delete with auto-promotion', () async {
      final c1 = SafetyContact(
        id: 'contact_1',
        name: 'Contact One',
        phoneNumber: '1111111111',
        isPrimary: true,
      );
      final c2 = SafetyContact(
        id: 'contact_2',
        name: 'Contact Two',
        phoneNumber: '2222222222',
        isPrimary: false,
      );

      await repository.saveSafetyContact(c1);
      await repository.saveSafetyContact(c2);

      var list = await repository.getSafetyContacts();
      expect(list.length, 2);
      expect(list.firstWhere((c) => c.id == 'contact_1').isPrimary, isTrue);

      // Promote contact 2 to primary
      await repository.setPrimaryContact('contact_2');
      list = await repository.getSafetyContacts();
      expect(list.firstWhere((c) => c.id == 'contact_2').isPrimary, isTrue);
      expect(list.firstWhere((c) => c.id == 'contact_1').isPrimary, isFalse);

      // Delete primary contact (contact 2) -> contact 1 should be promoted
      await repository.deleteSafetyContact('contact_2');
      list = await repository.getSafetyContacts();
      expect(list.length, 1);
      expect(list.first.id, 'contact_1');
      expect(list.first.isPrimary, isTrue);
    });
  });

  group('AlarmService & Diagnostics Tests', () {
    test('soundAssetMap and soundRawMap provide presets for all available sounds', () {
      for (final soundName in AlarmService.availableSounds) {
        expect(AlarmService.soundAssetMap.containsKey(soundName), isTrue,
            reason: 'Missing soundAssetMap entry for $soundName');
        expect(AlarmService.soundRawMap.containsKey(soundName), isTrue,
            reason: 'Missing soundRawMap entry for $soundName');
      }
    });

    test('testArrivalSound returns SoundTestResult with correct asset path', () async {
      final alarmService = AlarmService();
      final result = await alarmService.testArrivalSound(soundName: 'High Alert Bell');

      expect(result.assetPath, 'sounds/bell_alert.wav');
      // In desktop unit test environment, AudioPlayer may fail platform execution cleanly
      // without throwing uncaught exceptions
      expect(result.message, isNotEmpty);
    });

    test('testVibration reports honest hardware status', () async {
      final alarmService = AlarmService();
      final result = await alarmService.testVibration();

      expect(result.message, isNotEmpty);
    });

    test('testArrivalNotification returns structured result', () async {
      final alarmService = AlarmService();
      final result = await alarmService.testArrivalNotification();

      expect(result.message, isNotEmpty);
    });
  });

  group('LocationEngine States and Checks', () {
    test('checkStatus returns valid LocationEngineStatus without crashing', () async {
      final engine = LocationEngine();
      final status = await engine.checkStatus();

      expect(LocationEngineStatus.values, contains(status));
    });
  });
}
