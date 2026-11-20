import 'package:flutter_test/flutter_test.dart';
import 'package:pathsaathi/models/alarm_config.dart';
import 'package:pathsaathi/services/alarm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone 7: AlarmConfig & Gradual Ramp-Up Tests', () {
    test('creates default standard AlarmConfig with valid defaults', () {
      final config = AlarmConfig.standard();
      expect(config.soundEnabled, isTrue);
      expect(config.soundName, equals('Default Chime'));
      expect(config.vibrationEnabled, isTrue);
      expect(config.gradualVolumeRampUp, isFalse);
      expect(config.snoozeDurationMinutes, equals(5));
      expect(config.repeatIntervalSeconds, equals(30));
      expect(config.maxRepeats, equals(3));
      expect(config.isDismissed, isFalse);
      expect(config.isSnoozed, isFalse);
    });

    test('serializes and deserializes AlarmConfig with gradualVolumeRampUp accurately', () {
      const original = AlarmConfig(
        soundEnabled: true,
        soundName: 'Urgent Arrival Alarm',
        vibrationEnabled: true,
        volume: 0.9,
        gradualVolumeRampUp: true,
        snoozeDurationMinutes: 8,
        repeatIntervalSeconds: 20,
        maxRepeats: 4,
      );

      final json = original.toJson();
      final restored = AlarmConfig.fromJson(json);

      expect(restored, equals(original));
      expect(restored.soundEnabled, isTrue);
      expect(restored.soundName, equals('Urgent Arrival Alarm'));
      expect(restored.volume, closeTo(0.9, 0.01));
      expect(restored.gradualVolumeRampUp, isTrue);
      expect(restored.snoozeDurationMinutes, equals(8));
      expect(restored.maxRepeats, equals(4));
    });

    test('copyWith updates gradualVolumeRampUp correctly', () {
      const config = AlarmConfig(gradualVolumeRampUp: false);
      final updated = config.copyWith(gradualVolumeRampUp: true);
      expect(updated.gradualVolumeRampUp, isTrue);
    });
  });

  group('Milestone 7: AlarmService Audio Presets, Routing & Diagnostics', () {
    test('availableSounds contains all 7 verified ringtone presets with asset mappings', () {
      expect(AlarmService.availableSounds.length, equals(7));
      expect(AlarmService.availableSounds, contains(AlarmService.soundClassicRing));
      expect(AlarmService.availableSounds, contains(AlarmService.soundUrgentAlarm));
      expect(AlarmService.availableSounds, contains(AlarmService.soundGentleChime));
      expect(AlarmService.availableSounds, contains(AlarmService.soundDefaultChime));
      expect(AlarmService.availableSounds, contains(AlarmService.soundHighAlertBell));
      expect(AlarmService.availableSounds, contains(AlarmService.soundGentleRipple));
      expect(AlarmService.availableSounds, contains(AlarmService.soundSubtlePing));

      for (final sound in AlarmService.availableSounds) {
        expect(AlarmService.soundAssetMap[sound], isNotNull);
        expect(AlarmService.soundAssetMap[sound], endsWith('.wav'));
        expect(AlarmService.soundRawMap[sound], isNotNull);
        expect(AlarmService.soundDescriptions[sound], isNotEmpty);
      }
    });

    test('AlarmService lifecycle: initial state, stopAlarm, dismiss, snooze and safe dispose', () {
      final service = AlarmService();
      expect(service.isAlarmActive, isFalse);
      expect(service.isPreviewPlaying, isFalse);

      service.stopAlarm();
      expect(service.isAlarmActive, isFalse);

      service.snooze(overrideDuration: const Duration(minutes: 1));
      expect(service.isAlarmActive, isFalse);

      service.dismiss();
      expect(service.isAlarmActive, isFalse);

      // Safe dispose without ChangeNotifier.debugAssertNotDisposed exception
      service.dispose();
      // Calling stopAlarm or dismiss after dispose does not throw
      service.stopAlarm();
      service.dismiss();
    });
  });
}
