import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';
import '../models/alarm_config.dart';

/// Service responsible for executing audible alarms and tactile vibrations
/// when arrival at a stop is confirmed.
class AlarmService {
  AlarmService({
    this.audioPlayer,
  });

  AudioPlayer? audioPlayer;
  Timer? _repeatTimer;
  Timer? _snoozeTimer;
  bool _isPlaying = false;
  int _currentRepeat = 0;
  AlarmConfig? _activeConfig;
  VoidCallback? _onAlarmFinished;

  AudioPlayer _getPlayer() {
    return audioPlayer ??= AudioPlayer();
  }

  bool get isAlarmActive => _isPlaying;

  /// Available alarm chime presets.
  static const List<String> availableSounds = [
    'Default Chime',
    'High Alert Bell',
    'Gentle Ripple',
    'Subtle Ping',
  ];

  /// Triggers the alarm sequence based on the stop's [config].
  Future<void> triggerAlarm({
    required AlarmConfig config,
    VoidCallback? onFinished,
  }) async {
    if (_isPlaying) {
      debugPrint('[AlarmService] Alarm already active; ignoring duplicate trigger.');
      return;
    }

    _activeConfig = config;
    _onAlarmFinished = onFinished;
    _isPlaying = true;
    _currentRepeat = 0;

    await _playAlertBurst(config);

    // Setup repeat timer if configured
    if (config.maxRepeats > 0) {
      _repeatTimer?.cancel();
      _repeatTimer = Timer.periodic(
        Duration(seconds: config.repeatIntervalSeconds),
        (timer) async {
          _currentRepeat++;
          if (_currentRepeat >= config.maxRepeats) {
            timer.cancel();
            _repeatTimer = null;
            _isPlaying = false;
            _onAlarmFinished?.call();
          } else {
            await _playAlertBurst(config);
          }
        },
      );
    }
  }

  /// Plays a single chime burst and tactile vibration.
  Future<void> _playAlertBurst(AlarmConfig config) async {
    // 1. Vibration
    if (config.vibrationEnabled) {
      try {
        final hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          // Distinct 2-burst pulse pattern: [wait, vibrate, wait, vibrate]
          await Vibration.vibrate(
            pattern: [0, 500, 200, 800],
            intensities: [0, 255, 0, 255],
          );
        }
      } catch (e) {
        debugPrint('[AlarmService] Vibration platform notice (handled): $e');
      }
    }

    // 2. Sound
    if (config.soundEnabled) {
      try {
        final player = _getPlayer();
        await player.stop();
        await player.setVolume(1.0);
        await player.play(
          AssetSource('sounds/arrival_chime.mp3'),
        );
      } catch (e) {
        // Handled cleanly in unit test or if sound file not present
        debugPrint('[AlarmService] Audio playback notice (handled): $e');
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

    debugPrint(
      '[AlarmService] Alarm snoozed for ${duration.inMinutes} minutes.',
    );
  }

  /// Dismisses and silences the active alarm permanently.
  void dismiss() {
    _snoozeTimer?.cancel();
    _snoozeTimer = null;
    stopAlarm();
    _activeConfig = null;
    debugPrint('[AlarmService] Alarm dismissed by user.');
  }

  /// Halts any currently sounding audio or vibration immediately.
  void stopAlarm() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _isPlaying = false;
    try {
      audioPlayer?.stop();
      Vibration.cancel().catchError((_) {});
    } catch (_) {}
  }

  void dispose() {
    stopAlarm();
    _snoozeTimer?.cancel();
    audioPlayer?.dispose();
    audioPlayer = null;
  }
}
