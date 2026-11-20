import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/location_engine.dart';
import '../services/notification_service.dart';

/// Screen displayed on first launch or when essential permissions/services are missing.
class FirstLaunchOnboardingScreen extends StatefulWidget {
  const FirstLaunchOnboardingScreen({
    super.key,
    this.locationEngine,
    this.notificationService,
    this.onCompleted,
  });

  final LocationEngine? locationEngine;
  final NotificationService? notificationService;
  final VoidCallback? onCompleted;

  static const String prefKeyCompleted = 'has_completed_onboarding_v2';

  @override
  State<FirstLaunchOnboardingScreen> createState() =>
      _FirstLaunchOnboardingScreenState();
}

class _FirstLaunchOnboardingScreenState
    extends State<FirstLaunchOnboardingScreen> with WidgetsBindingObserver {
  late final LocationEngine _locationEngine;
  late final NotificationService _notificationService;

  bool _isChecking = true;
  bool _serviceEnabled = false;
  bool _locationPermissionGranted = false;
  bool _notificationPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locationEngine = widget.locationEngine ?? LocationEngine();
    _notificationService = widget.notificationService ?? NotificationService();
    _evaluateStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _evaluateStatus();
    }
  }

  Future<void> _evaluateStatus() async {
    setState(() => _isChecking = true);
    try {
      final status = await _locationEngine.checkStatus();
      final notifOk = await _notificationService.areNotificationsEnabled();

      if (mounted) {
        setState(() {
          _isChecking = false;
          _serviceEnabled = status != LocationEngineStatus.serviceDisabled;
          _locationPermissionGranted =
              status != LocationEngineStatus.permissionMissing &&
              status != LocationEngineStatus.serviceDisabled;
          _notificationPermissionGranted = notifOk;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  Future<void> _handleEnableGps() async {
    await _locationEngine.openLocationSettings();
  }

  Future<void> _handleRequestLocation() async {
    await _locationEngine.requestPermission();
    await _evaluateStatus();
  }

  Future<void> _handleRequestNotifications() async {
    await _notificationService.requestNotificationPermission();
    await _evaluateStatus();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(FirstLaunchOnboardingScreen.prefKeyCompleted, true);
    if (widget.onCompleted != null) {
      widget.onCompleted!();
    } else if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isReady = _serviceEnabled && _locationPermissionGranted;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup & Permissions'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isChecking
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // App icon & Title
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.explore_rounded,
                        size: 40,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Welcome to STOP Vanthachu',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Never Miss Your Stop. Travel with Confidence.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Plain English Purpose Notice
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: theme.colorScheme.primary,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'STOP Vanthachu uses your location to detect when you reach your journey stops and activate your arrival alerts. '
                              'Your location data is processed locally on your phone and is never uploaded to any remote server.',
                              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    'REQUIRED SYSTEM PERMISSIONS',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Step 1: GPS Service
                  _buildStepTile(
                    title: '1. GPS Hardware Service',
                    description: _serviceEnabled
                        ? 'Device location services are enabled.'
                        : 'Location hardware is currently disabled. Tap to open system location settings.',
                    isComplete: _serviceEnabled,
                    buttonLabel: 'Enable GPS',
                    onAction: _handleEnableGps,
                    icon: Icons.location_on,
                  ),
                  const SizedBox(height: 12),

                  // Step 2: Location Permission
                  _buildStepTile(
                    title: '2. Precise Location Permission',
                    description: _locationPermissionGranted
                        ? 'Location permission granted.'
                        : 'Required to track distance and confirm arrival at your destination stops.',
                    isComplete: _locationPermissionGranted,
                    buttonLabel: 'Grant Permission',
                    onAction: _handleRequestLocation,
                    icon: Icons.my_location,
                  ),
                  const SizedBox(height: 12),

                  // Step 3: Notifications
                  _buildStepTile(
                    title: '3. Arrival Notifications',
                    description: _notificationPermissionGranted
                        ? 'Notification alerts enabled.'
                        : 'Allows STOP Vanthachu to wake you with high-priority chimes when you arrive.',
                    isComplete: _notificationPermissionGranted,
                    buttonLabel: 'Allow Alerts',
                    onAction: _handleRequestNotifications,
                    icon: Icons.notifications_active,
                  ),
                  const SizedBox(height: 16),

                  // Background Notice
                  Card(
                    elevation: 0,
                    color: Colors.amber.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.battery_charging_full, color: Colors.amber, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Background Tracking: When a journey is active, STOP Vanthachu runs a foreground service so alarms trigger even if your screen is off or the phone is in your bag.',
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Action Button
                  FilledButton.icon(
                    onPressed: isReady ? _completeOnboarding : null,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(isReady ? 'Get Started' : 'Enable Required Permissions Above'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!isReady)
                    TextButton(
                      onPressed: _completeOnboarding,
                      child: const Text('Continue anyway (Limited Functionality)'),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildStepTile({
    required String title,
    required String description,
    required bool isComplete,
    required String buttonLabel,
    required VoidCallback onAction,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isComplete ? Colors.green.withValues(alpha: 0.4) : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: isComplete ? Colors.green : theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Icon(
                  isComplete ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isComplete ? Colors.green : theme.colorScheme.outline,
                  size: 22,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (!isComplete) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: onAction,
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  ),
                  child: Text(buttonLabel),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
