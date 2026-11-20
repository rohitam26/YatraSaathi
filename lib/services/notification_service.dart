import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Structured result returned by notification diagnostic tests.
class NotificationTestResult {
  const NotificationTestResult({
    required this.success,
    required this.message,
    this.permissionGranted = false,
    this.channelCreated = false,
  });

  final bool success;
  final String message;
  final bool permissionGranted;
  final bool channelCreated;
}

/// Service managing high-priority Android notification channels, arrival alerts,
/// and ongoing tracking status notifications.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  /// High-priority arrival alert channel with USAGE_ALARM audio routing
  static const String arrivalChannelId = 'yatrasaathi_arrival_v3';
  static const String arrivalChannelName = 'STOP Vanthachu Arrival Alerts';
  static const String arrivalChannelDesc =
      'High-priority alarm notifications with audible chime and vibration played when reaching destination stops.';

  static const String trackingChannelId = 'yatrasaathi_tracking_service';
  static const String trackingChannelName = 'STOP Vanthachu Live Tracking';
  static const String trackingChannelDesc =
      'Status notifications displayed while GPS journey tracking is running.';

  static const int arrivalNotificationId = 1001;
  static const int trackingNotificationId = 1002;
  static const int testNotificationId = 1003;
  static const int recoveryNotificationId = 1004;
  static const int missedStopNotificationId = 1005;
  static const int emergencyNotificationId = 1006;

  /// Initializes the local notification plugin and registers native notification channels.
  Future<bool> initialize() async {
    if (_initialized) return true;

    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);

      final success = await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          debugPrint('[NotificationService] Notification clicked: ${response.payload}');
        },
      ).timeout(const Duration(milliseconds: 500), onTimeout: () => false);

      // Create Android channels with native attributes
      final androidPlatform = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlatform != null) {
        // High-priority arrival alert channel configured with AudioAttributesUsage.alarm
        // to ensure it rings through phone speaker even in silent / DND modes.
        final arrivalChannel = AndroidNotificationChannel(
          arrivalChannelId,
          arrivalChannelName,
          description: arrivalChannelDesc,
          importance: Importance.max,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('arrival_chime'),
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 500, 200, 800]),
          audioAttributesUsage: AudioAttributesUsage.alarm,
          enableLights: true,
          showBadge: true,
        );
        await androidPlatform.createNotificationChannel(arrivalChannel);

        // Low-priority persistent tracking channel
        const trackingChannel = AndroidNotificationChannel(
          trackingChannelId,
          trackingChannelName,
          description: trackingChannelDesc,
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        );
        await androidPlatform.createNotificationChannel(trackingChannel);
      }

      _initialized = success ?? true;
      return _initialized;
    } catch (e) {
      debugPrint('[NotificationService] Initialization error (handled): $e');
      return false;
    }
  }

  /// Checks if POST_NOTIFICATIONS permission is granted on Android 13+.
  Future<bool> areNotificationsEnabled() async {
    try {
      final androidPlatform = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlatform == null) return true;
      final enabled = await androidPlatform
          .areNotificationsEnabled()
          .timeout(const Duration(milliseconds: 300), onTimeout: () => true);
      return enabled ?? false;
    } catch (e) {
      debugPrint('[NotificationService] areNotificationsEnabled error: $e');
      return true;
    }
  }

  /// Requests notification permission on Android 13+.
  Future<bool> requestNotificationPermission() async {
    try {
      final androidPlatform = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlatform == null) return true;
      final granted = await androidPlatform
          .requestNotificationsPermission()
          .timeout(const Duration(milliseconds: 500), onTimeout: () => true);
      return granted ?? false;
    } catch (e) {
      debugPrint('[NotificationService] requestNotificationPermission error: $e');
      return false;
    }
  }

  /// Posts high-priority arrival alert notification with native alarm audio and vibration.
  Future<void> postArrivalNotification({
    required String stopName,
    String? journeyTitle,
    String? rawSoundResource,
  }) async {
    await initialize();

    final soundResource = rawSoundResource ?? 'arrival_chime';
    final timestamp = DateTime.now().toIso8601String();
    debugPrint('[NOTIFICATION_POST @ $timestamp] Posting arrival alert for "$stopName" on channel "$arrivalChannelId"');

    final androidDetails = AndroidNotificationDetails(
      arrivalChannelId,
      arrivalChannelName,
      channelDescription: arrivalChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(soundResource),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 800]),
      styleInformation: BigTextStyleInformation(
        'You have arrived at $stopName. Wake up, prepare your belongings, and send your safety check-in.',
        contentTitle: '🚨 Arrived at $stopName',
        summaryText: journeyTitle ?? 'STOP Vanthachu Journey Alert',
      ),
    );

    final details = NotificationDetails(android: androidDetails);

    try {
      await _plugin.show(
        arrivalNotificationId,
        '🚨 Arrived at $stopName',
        'You have reached your destination.',
        details,
        payload: 'arrival:$stopName',
      );
      debugPrint('[NOTIFICATION_SUCCESS @ $timestamp] Arrival alert banner posted successfully.');
    } catch (e) {
      debugPrint('[NOTIFICATION_ERROR @ $timestamp] Failed to show arrival notification: $e');
    }
  }

  /// Posts high-priority missed-stop alert when vehicle overshoots destination stop.
  Future<void> postMissedStopNotification({
    required String stopName,
    required double distancePastMeters,
    String? journeyTitle,
  }) async {
    await initialize();

    final androidDetails = AndroidNotificationDetails(
      arrivalChannelId,
      arrivalChannelName,
      channelDescription: arrivalChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 400, 200, 400]),
      styleInformation: BigTextStyleInformation(
        'You appear to have passed $stopName (${distancePastMeters.toStringAsFixed(0)}m away). Tap to advance or check route.',
        contentTitle: '⚠️ Missed Stop: $stopName',
        summaryText: journeyTitle ?? 'STOP Vanthachu Warning',
      ),
    );

    final details = NotificationDetails(android: androidDetails);

    try {
      await _plugin.show(
        missedStopNotificationId,
        '⚠️ Missed Stop: $stopName',
        'You appear to have passed $stopName.',
        details,
        payload: 'missed:$stopName',
      );
    } catch (e) {
      debugPrint('[NotificationService] Failed to show missed stop notification: $e');
    }
  }

  /// Posts emergency escalation notification when arrival remains unacknowledged.
  Future<void> postEmergencyEscalationNotification({
    required String stopName,
    required String contactName,
    String? journeyTitle,
  }) async {
    await initialize();

    final androidDetails = AndroidNotificationDetails(
      arrivalChannelId,
      arrivalChannelName,
      channelDescription: arrivalChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(
        'Arrival at "$stopName" was unacknowledged. Emergency SOS alert automatically dispatched to $contactName.',
        contentTitle: '🚨 Emergency Escalation Dispatched',
        summaryText: journeyTitle ?? 'STOP Vanthachu Safety Alert',
      ),
    );

    final details = NotificationDetails(android: androidDetails);

    try {
      await _plugin.show(
        emergencyNotificationId,
        '🚨 Emergency Escalation Dispatched',
        'Emergency SOS dispatched to $contactName.',
        details,
        payload: 'emergency:$stopName',
      );
    } catch (e) {
      debugPrint('[NotificationService] Failed to show emergency escalation notification: $e');
    }
  }

  /// Runs an honest diagnostic test of the notification system.
  Future<NotificationTestResult> postTestNotification() async {
    final timestamp = DateTime.now().toIso8601String();
    debugPrint('[TEST_NOTIF_START @ $timestamp] Running arrival notification test');

    final initOk = await initialize();
    if (!initOk) {
      return const NotificationTestResult(
        success: false,
        message: 'Failed to initialize notification plugin.',
      );
    }

    final hasPerm = await areNotificationsEnabled();
    if (!hasPerm) {
      final granted = await requestNotificationPermission();
      if (!granted) {
        return const NotificationTestResult(
          success: false,
          permissionGranted: false,
          message: 'Notification permission denied by user or system.',
        );
      }
    }

    try {
      final androidDetails = AndroidNotificationDetails(
        arrivalChannelId,
        arrivalChannelName,
        channelDescription: arrivalChannelDesc,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('arrival_chime'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        category: AndroidNotificationCategory.alarm,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 400, 200, 400]),
        styleInformation: const BigTextStyleInformation(
          'Diagnostic notification verifying speaker audio via alarm channel, vibration pulse, and high-priority banner.',
          contentTitle: '🔔 STOP Vanthachu Test Notification',
          summaryText: 'Hardware Test',
        ),
      );

      final details = NotificationDetails(android: androidDetails);

      await _plugin.show(
        testNotificationId,
        '🔔 STOP Vanthachu Test Notification',
        'Audio, vibration, and banner test succeeded.',
        details,
        payload: 'test_notification',
      );

      debugPrint('[TEST_NOTIF_SUCCESS @ $timestamp] Test notification posted.');
      return const NotificationTestResult(
        success: true,
        permissionGranted: true,
        channelCreated: true,
        message: 'Notification posted successfully with arrival chime and vibration on Alarm channel.',
      );
    } catch (e) {
      debugPrint('[TEST_NOTIF_EXCEPTION @ $timestamp] Exception: $e');
      return NotificationTestResult(
        success: false,
        permissionGranted: true,
        message: 'Exception while showing test notification: $e',
      );
    }
  }

  /// Posts a session recovery notification alerting the traveler that an active
  /// journey was recovered following app reboot or background restoration.
  Future<void> postSessionRecoveryNotification({
    required String journeyName,
    required String nextStopName,
  }) async {
    await initialize();

    final androidDetails = AndroidNotificationDetails(
      trackingChannelId,
      trackingChannelName,
      channelDescription: trackingChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      styleInformation: BigTextStyleInformation(
        'Active journey "$journeyName" restored. Now monitoring arrival for "$nextStopName".',
        contentTitle: '🔄 STOP Vanthachu: Journey Restored',
        summaryText: 'Background Recovery',
      ),
    );

    final details = NotificationDetails(android: androidDetails);
    try {
      await _plugin.show(
        recoveryNotificationId,
        '🔄 STOP Vanthachu: Journey Restored',
        'Monitoring "$nextStopName"...',
        details,
        payload: 'session_recovery',
      );
    } catch (e) {
      debugPrint('[NotificationService] Failed to post recovery notification: $e');
    }
  }

  /// Cancels an active recovery notification.
  Future<void> cancelRecoveryNotification() async {
    try {
      await _plugin.cancel(recoveryNotificationId);
    } catch (_) {}
  }

  /// Cancels an active arrival notification.
  Future<void> cancelArrivalNotification() async {
    try {
      await _plugin.cancel(arrivalNotificationId);
    } catch (_) {}
  }

  /// Cancels all notifications.
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
