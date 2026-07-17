import 'package:flutter/material.dart';
import '../services/location_service.dart';

/// Screen providing transparent explanations for why each Android permission
/// is requested and granting one-click access to system settings.
class PermissionGuidanceScreen extends StatefulWidget {
  const PermissionGuidanceScreen({
    super.key,
    this.locationService,
  });

  final LocationService? locationService;

  @override
  State<PermissionGuidanceScreen> createState() => _PermissionGuidanceScreenState();
}

class _PermissionGuidanceScreenState extends State<PermissionGuidanceScreen> {
  late final LocationService _locationService;
  LocationPermissionState _permissionState = LocationPermissionState.denied;

  @override
  void initState() {
    super.initState();
    _locationService = widget.locationService ?? LocationService();
    _refreshState();
  }

  Future<void> _refreshState() async {
    final state = await _locationService.checkPermissionState();
    if (mounted) {
      setState(() => _permissionState = state);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Android Permissions Guide',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: colorScheme.primaryContainer.withAlpha(80),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 36, color: colorScheme.primary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Privacy-First Permissions',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'YatraSaathi processes GPS coordinates exclusively on your device. Zero telemetry is sent to any external server.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildPermissionItem(
            theme: theme,
            icon: Icons.my_location,
            title: 'Precise GPS Location',
            permissionName: 'ACCESS_FINE_LOCATION',
            description:
                'Calculates Haversine distance to upcoming transit stops. Rejects inaccurate cell tower fixes to prevent premature false alarms.',
            statusText: _permissionState == LocationPermissionState.always ||
                    _permissionState == LocationPermissionState.whileInUse
                ? 'Granted'
                : 'Not Granted',
            isGranted: _permissionState == LocationPermissionState.always ||
                _permissionState == LocationPermissionState.whileInUse,
          ),
          _buildPermissionItem(
            theme: theme,
            icon: Icons.run_circle_outlined,
            title: 'Foreground Location Service',
            permissionName: 'FOREGROUND_SERVICE_LOCATION',
            description:
                'Maintains continuous GPS monitoring when your phone is locked or you switch to other apps during your commute.',
            statusText: 'Configured in Manifest',
            isGranted: true,
          ),
          _buildPermissionItem(
            theme: theme,
            icon: Icons.notifications_active_outlined,
            title: 'System Notifications (Android 13+)',
            permissionName: 'POST_NOTIFICATIONS',
            description:
                'Displays the persistent tracking status bar notification and loud arrival alerts when your stop is reached.',
            statusText: 'Required for Android 13+',
            isGranted: true,
          ),
          _buildPermissionItem(
            theme: theme,
            icon: Icons.vibration,
            title: 'Haptic Vibration',
            permissionName: 'VIBRATE',
            description:
                'Pulses phone motor upon arrival so you are alerted even if your phone is in your pocket or bag.',
            statusText: 'Granted by default',
            isGranted: true,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              await _locationService.requestPermission();
              await _refreshState();
            },
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Request Location Permission'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _locationService.openAppSettings(),
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Open Android System Settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionItem({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String permissionName,
    required String description,
    required String statusText,
    required bool isGranted,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isGranted
                        ? Colors.green.withAlpha(30)
                        : Colors.orange.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isGranted ? Colors.green.shade800 : Colors.orange.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              permissionName,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            Text(description, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

