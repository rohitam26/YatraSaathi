import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';
import '../models/alarm_config.dart';
import 'notification_service.dart';

/// Result object describing the outcome of an arrival sound test.
class SoundTestResult {
  const SoundTestResult({
    required this.success,
    required this.message,
    this.assetPath,
  });

  final bool success;
  final String message;
  final String? assetPath;
}

/// Result object describing the outcome of a vibration hardware test.
class VibrationTestResult {
  const VibrationTestResult({
    required this.success,
    required this.hasVibrator,
    required this.message,
  });

  final bool success;
  final bool hasVibrator;
  final String message;
}

/// Service responsible for executing audible arrival ringtones, tactile vibrations,
/// preview audio playback, and posting native high-priority notification channel alerts.
class AlarmService extends ChangeNotifier {
  AlarmService({
    this.audioPlayer,
    this._previewPlayer,
    NotificationService? notificationService,
  })  : notificationService = notificationService ?? NotificationService();

  AudioPlayer? audioPlayer;
  AudioPlayer? _previewPlayer;
  final NotificationService notificationService;

  Timer? _repeatTimer;
  Timer? _snoozeTimer;
  Timer? _vibrationLoopTimer;
  bool _isPlaying = false;
  int _currentRepeat = 0;
  AlarmConfig? _activeConfig;
  VoidCallback? _onAlarmFinished;

  // Dedicated preview state
  String? _previewingSound;
  double _previewVolume = 1.0;

  /// The 3 primary original ringtones plus backwards-compatible sound presets.
  static const String soundClassicRing = 'Classic Ring';
  static const String soundUrgentAlarm = 'Urgent Arrival Alarm';
  static const String soundGentleChime = 'Gentle Chime';
  static const String soundDefaultChime = 'Default Chime';
  static const String soundHighAlertBell = 'High Alert Bell';
  static const String soundGentleRipple = 'Gentle Ripple';
  static const String soundSubtlePing = 'Subtle Ping';

  static const List<String> availableSounds = [
    soundClassicRing,
    soundUrgentAlarm,
    soundGentleChime,
    soundDefaultChime,
    soundHighAlertBell,
    soundGentleRipple,
    soundSubtlePing,
  ];

  static const Map<String, String> soundDescriptions = {
    soundClassicRing: 'Classic Ring — Telephone bell cadence with dual-frequency modulation',
    soundUrgentAlarm: 'Urgent Arrival Alarm — Rapid alert siren pulses for noisy environments',
    soundGentleChime: 'Gentle Chime — Melodic pentatonic chime arpeggio with soft decay',
    soundDefaultChime: 'Default Chime — Soft arrival melody',
    soundHighAlertBell: 'High Alert Bell — Prominent bell chime',
    soundGentleRipple: 'Gentle Ripple — Low ambient alert',
    soundSubtlePing: 'Subtle Ping — Single clean sonar pulse',
  };

  static const Map<String, String> soundAssetMap = {
    soundClassicRing: 'sounds/classic_ring.wav',
    soundUrgentAlarm: 'sounds/urgent_alarm.wav',
    soundGentleChime: 'sounds/gentle_chime.wav',
    soundDefaultChime: 'sounds/arrival_chime.wav',
    soundHighAlertBell: 'sounds/bell_alert.wav',
    soundGentleRipple: 'sounds/gentle_ripple.wav',
    soundSubtlePing: 'sounds/subtle_ping.wav',
  };

  static const Map<String, String> soundRawMap = {
    soundClassicRing: 'classic_ring',
    soundUrgentAlarm: 'urgent_alarm',
    soundGentleChime: 'gentle_chime',
    soundDefaultChime: 'arrival_chime',
    soundHighAlertBell: 'bell_alert',
    soundGentleRipple: 'gentle_ripple',
    soundSubtlePing: 'subtle_ping',
  };

  bool get isAlarmActive => _isPlaying;
  bool get isPreviewPlaying => _previewingSound != null;
  String? get currentPreviewSound => _previewingSound;
  double get previewVolume => _previewVolume;

  AudioPlayer? _getAlarmPlayer() {
    if (audioPlayer != null) return audioPlayer;
    try {
      final player = AudioPlayer();
      try {
        player.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              isSpeakerphoneOn: true,
              stayAwake: true,
              contentType: AndroidContentType.sonification,
              usageType: AndroidUsageType.alarm,
              audioFocus: AndroidAudioFocus.gainTransient,
            ),
          ),
        );
      } catch (e) {
        debugPrint('[AlarmService] AudioContext configuration handled: $e');
      }
      return audioPlayer = player;
    } catch (e) {
      debugPrint('[AlarmService] AudioPlayer initialization notice: $e');
      return null;
    }
  }

  AudioPlayer? _getPreviewPlayer() {
    if (_previewPlayer != null) return _previewPlayer;
    try {
      final player = AudioPlayer();
      player.onPlayerComplete.listen((_) {
        _previewingSound = null;
        notifyListeners();
      });
      return _previewPlayer = player;
    } catch (e) {
      debugPrint('[AlarmService] Preview player initialization notice: $e');
      return null;
    }
  }

  /// Sets the preview volume and updates active preview if playing.
  Future<void> setPreviewVolume(double volume) async {
    _previewVolume = volume.clamp(0.0, 1.0);
    final player = _getPreviewPlayer();
    if (player != null) {
      try {
        await player.setVolume(_previewVolume);
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Immediately starts playing a ringtone preview.
  /// Stops any currently playing preview before starting the new sound.
  Future<void> startPreview(String soundName, {double? volume}) async {
    // 1. Stop any current preview immediately
    await stopPreview();

    final assetPath = soundAssetMap[soundName] ?? 'sounds/classic_ring.wav';
    final vol = (volume ?? _previewVolume).clamp(0.0, 1.0);
    _previewVolume = vol;

    debugPrint('[AlarmService] Starting preview of "$soundName" ($assetPath) at ${(vol * 100).toInt()}% volume');

    try {
      final player = _getPreviewPlayer();
      if (player == null) return;

      await player.stop();
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(vol);

      _previewingSound = soundName;
      notifyListeners();

      await player.play(AssetSource(assetPath));
    } catch (e) {
      debugPrint('[AlarmService] Preview playback handled: $e');
      _previewingSound = null;
      notifyListeners();
    }
  }

  /// Stops any currently playing audio preview.
  Future<void> stopPreview() async {
    if (_previewingSound != null) {
      _previewingSound = null;
      notifyListeners();
    }
    try {
      await _previewPlayer?.stop();
    } catch (_) {}
  }

  /// Triggers the full arrival alert sequence (ringtone + vibration + notification).
  Future<void> triggerAlarm({
    required AlarmConfig config,
    String? stopName,
    String? journeyTitle,
    VoidCallback? onFinished,
  }) async {
    final timestamp = DateTime.now().toIso8601String();
    if (_isPlaying) {
      debugPrint('[AlarmService @ $timestamp] Alarm already active; ignoring duplicate trigger.');
      return;
    }

    // Stop any preview when real alarm triggers
    await stopPreview();

    _activeConfig = config;
    _onAlarmFinished = onFinished;
    _isPlaying = true;
    _currentRepeat = 0;

    debugPrint(
      '[ALARM_TRIGGER @ $timestamp] Starting arrival alarm for "$stopName" '
      '(ringtone: "${config.soundName}", sound: ${config.soundEnabled}, '
      'vol: ${(config.volume * 100).toInt()}%, loop: ${config.repeatUntilDismissed}, vib: ${config.vibrationEnabled})',
    );

    // 1. Post native notification with chime on the high-priority alarm channel
    if (stopName != null) {
      final rawSound = soundRawMap[config.soundName] ?? 'classic_ring';
      await notificationService.postArrivalNotification(
        stopName: stopName,
        journeyTitle: journeyTitle,
        rawSoundResource: rawSound,
      );
    }

    // 2. Play ringtone and start vibration
    await _startRingtonePlayback(config);

    if (config.vibrationEnabled) {
      _startVibrationLoop();
    }

    // 3. If NOT looping continuously, schedule repeat timer
    if (!config.repeatUntilDismissed && config.maxRepeats > 0) {
      _repeatTimer?.cancel();
      _repeatTimer = Timer.periodic(
        Duration(seconds: config.repeatIntervalSeconds),
        (timer) async {
          _currentRepeat++;
          if (_currentRepeat >= config.maxRepeats) {
            timer.cancel();
            _repeatTimer = null;
            _isPlaying = false;
            _stopVibrationLoop();
            _onAlarmFinished?.call();
          } else {
            await _startRingtonePlayback(config);
          }
        },
      );
    }

    notifyListeners();
  }

  Future<void> _startRingtonePlayback(AlarmConfig config) async {
    if (!config.soundEnabled) return;

    try {
      final player = _getAlarmPlayer();
      if (player != null) {
        await player.stop().timeout(const Duration(seconds: 1), onTimeout: () {});
        await player.setVolume(config.volume.clamp(0.0, 1.0));
        await player.setReleaseMode(
          config.repeatUntilDismissed ? ReleaseMode.loop : ReleaseMode.stop,
        );

        final assetPath = soundAssetMap[config.soundName] ?? 'sounds/classic_ring.wav';
        debugPrint('[ALARM_SOUND] Playing AssetSource("$assetPath") via STREAM_ALARM (loop: ${config.repeatUntilDismissed})');
        await player.play(AssetSource(assetPath)).timeout(
          const Duration(seconds: 4),
          onTimeout: () {
            debugPrint('[AlarmService] Audio play timeout handled.');
          },
        );
      }
    } catch (e) {
      debugPrint('[AlarmService] Audio playback notice (handled): $e');
    }
  }

  void _startVibrationLoop() {
    _stopVibrationLoop();
    _executeVibration();
    // Re-pulse vibration every 3 seconds while alarm is active
    _vibrationLoopTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_isPlaying && (_activeConfig?.vibrationEnabled ?? false)) {
        _executeVibration();
      } else {
        _stopVibrationLoop();
      }
    });
  }

  void _stopVibrationLoop() {
    _vibrationLoopTimer?.cancel();
    _vibrationLoopTimer = null;
    try {
      Vibration.cancel().catchError((_) {});
    } catch (_) {}
  }

  /// Helper to reliably execute vibration on Android across devices with or without amplitude control.
  Future<bool> _executeVibration({List<int> pattern = const [0, 500, 200, 800]}) async {
    try {
      final hasVibrator = await Vibration.hasVibrator().timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );
      if (hasVibrator != true) {
        return false;
      }

      final hasCustom = await Vibration.hasCustomVibrationsSupport().timeout(
        const Duration(seconds: 1),
        onTimeout: () => false,
      );

      if (hasCustom == true) {
        await Vibration.vibrate(
          pattern: pattern,
          intensities: List.generate(pattern.length, (i) => i.isEven ? 0 : 255),
        ).timeout(const Duration(seconds: 3));
      } else {
        await Vibration.vibrate(pattern: pattern).timeout(const Duration(seconds: 3));
      }
      return true;
    } catch (e) {
      debugPrint('[AlarmService] Pattern vibration exception: $e. Retrying single pulse.');
      try {
        await Vibration.vibrate(duration: 800).timeout(const Duration(seconds: 2));
        return true;
      } catch (e2) {
        debugPrint('[AlarmService] Fallback vibration also failed: $e2');
        return false;
      }
    }
  }

  /// Snoozes the alarm for the configured duration.
  void snooze({Duration? overrideDuration}) {
    final duration =
        overrideDuration ??
        Duration(minutes: _activeConfig?.snoozeDurationMinutes ?? 5);

    stopAlarm();

    _snoozeTimer?.cancel();
    _snoozeTimer = Timer(duration, () {
      if (_activeConfig != null) {
        triggerAlarm(config: _activeConfig!);
      }
    });

    debugPrint('[AlarmService] Alarm snoozed for ${duration.inMinutes} minutes.');
    notifyListeners();
  }

  /// Dismisses and silences the active alarm permanently and dismisses notification.
  void dismiss() {
    _snoozeTimer?.cancel();
    _snoozeTimer = null;
    stopAlarm();
    _activeConfig = null;
    notificationService.cancelArrivalNotification();
    debugPrint('[AlarmService] Alarm dismissed by user.');
    notifyListeners();
  }

  /// Halts any currently sounding audio or vibration immediately.
  void stopAlarm() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _stopVibrationLoop();
    _isPlaying = false;
    try {
      audioPlayer?.stop();
    } catch (_) {}
    notifyListeners();
  }

  /// Diagnostic: Plays a test audio burst without vibrating and reports honest result.
  Future<SoundTestResult> testArrivalSound({String soundName = 'Classic Ring'}) async {
    final timestamp = DateTime.now().toIso8601String();
    final assetPath = soundAssetMap[soundName] ?? 'sounds/classic_ring.wav';
    debugPrint('[TEST_CHIME_START @ $timestamp] Testing chime "$soundName" ($assetPath)');

    try {
      final player = _getAlarmPlayer();
      if (player == null) {
        return SoundTestResult(
          success: false,
          message: 'AudioPlayer could not be initialized on this device.',
          assetPath: assetPath,
        );
      }

      await player.stop().timeout(const Duration(seconds: 1), onTimeout: () {});
      await player.setVolume(1.0).timeout(const Duration(seconds: 1), onTimeout: () {});
      await player.setReleaseMode(ReleaseMode.stop);

      await player.play(AssetSource(assetPath)).timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          debugPrint('[AlarmService] Play call reached timeout threshold.');
        },
      );

      final state = player.state;
      debugPrint('[TEST_CHIME_STATE @ $timestamp] Player state after play: $state');

      return SoundTestResult(
        success: true,
        message: 'Playing "$soundName" via Android ALARM audio stream at 100% volume.',
        assetPath: assetPath,
      );
    } catch (e) {
      debugPrint('[TEST_CHIME_ERROR @ $timestamp] Audio playback failed: $e');
      return SoundTestResult(
        success: false,
        message: 'Audio playback failed: $e (verify volume and speaker)',
        assetPath: assetPath,
      );
    }
  }

  /// Diagnostic: Tests vibration hardware and returns honest diagnostic result.
  Future<VibrationTestResult> testVibration() async {
    try {
      final hasVibrator = await Vibration.hasVibrator().timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );
      if (hasVibrator != true) {
        return const VibrationTestResult(
          success: false,
          hasVibrator: false,
          message: 'This device does not report hardware vibration support.',
        );
      }

      final success = await _executeVibration();
      return VibrationTestResult(
        success: success,
        hasVibrator: true,
        message: success
            ? 'Vibration motor activated successfully.'
            : 'Vibration call did not complete properly.',
      );
    } catch (e) {
      return VibrationTestResult(
        success: false,
        hasVibrator: false,
        message: 'Vibration hardware test failed: $e',
      );
    }
  }

  /// Diagnostic: Tests posting an arrival alert notification on the high-priority alarm channel.
  Future<NotificationTestResult> testArrivalNotification() async {
    return notificationService.postTestNotification();
  }

  @override
  void dispose() {
    stopAlarm();
    stopPreview();
    _snoozeTimer?.cancel();
    _repeatTimer?.cancel();
    _stopVibrationLoop();
    try {
      audioPlayer?.dispose();
      audioPlayer = null;
    } catch (_) {}
    try {
      _previewPlayer?.dispose();
      _previewPlayer = null;
    } catch (_) {}
    super.dispose();
  }
}
