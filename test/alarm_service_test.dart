import 'package:flutter_test/flutter_test.dart';
import 'package:pathsaathi/models/alarm_config.dart';
import 'package:pathsaathi/services/alarm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AlarmConfig and AlarmService Diagnostics', () {
    test('creates default standard AlarmConfig with valid defaults', () {
      final config = AlarmConfig.standard();
      expect(config.soundEnabled, isTrue);
      expect(config.soundName, equals('Default Chime'));
      expect(config.vibrationEnabled, isTrue);
      expect(config.snoozeDurationMinutes, equals(5));
      expect(config.repeatIntervalSeconds, equals(30));
      expect(config.maxRepeats, equals(3));
      expect(config.isDismissed, isFalse);
      expect(config.isSnoozed, isFalse);
    });

    test('serializes and deserializes AlarmConfig accurately', () {
      const original = AlarmConfig(
        soundEnabled: false,
        soundName: 'High Alert Bell',
        vibrationEnabled: true,
        snoozeDurationMinutes: 10,
        repeatIntervalSeconds: 15,
        maxRepeats: 1,
      );

      final json = original.toJson();
      final restored = AlarmConfig.fromJson(json);

      expect(restored, equals(original));
      expect(restored.soundEnabled, isFalse);
      expect(restored.soundName, equals('High Alert Bell'));
      expect(restored.maxRepeats, equals(1));
    });

    test('AlarmService availableSounds includes core presets', () {
      expect(AlarmService.availableSounds, contains('Default Chime'));
      expect(AlarmService.availableSounds, contains('High Alert Bell'));
      expect(AlarmService.availableSounds.length, greaterThanOrEqualTo(3));
    });

    test('AlarmService initial state is not active', () {
      final service = AlarmService();
      expect(service.isAlarmActive, isFalse);
      service.stopAlarm();
      expect(service.isAlarmActive, isFalse);
      service.dismiss();
      service.dispose();
    });
  });
}
