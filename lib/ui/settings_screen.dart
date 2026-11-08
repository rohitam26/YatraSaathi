import 'package:flutter/material.dart';
import '../models/alarm_config.dart';
import '../services/alarm_service.dart';
import '../services/journey_repository.dart';

/// Screen allowing configuration of arrival detection sensitivity,
/// default alarm preferences, and local data management.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    this.alarmService,
  });

  final JourneyRepository repository;
  final AlarmService? alarmService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AlarmService _alarmService;
  int _consecutiveReadings = 3;
  int _minDwellSeconds = 10;
  double _maxAccuracyMeters = 50.0;

  @override
  void initState() {
    super.initState();
    _alarmService = widget.alarmService ?? AlarmService();
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Local Data?'),
        content: const Text(
          'This will permanently delete all saved journeys and history from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.repository.clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All local data cleared.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Text(
            'Arrival Detection Parameters',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('Required Consecutive GPS Samples'),
            subtitle: const Text(
              'Prevents single-point multipath anomalies from triggering alarms',
            ),
            trailing: DropdownButton<int>(
              value: _consecutiveReadings,
              items: const [
                DropdownMenuItem(value: 2, child: Text('2 readings')),
                DropdownMenuItem(value: 3, child: Text('3 readings (Recommended)')),
                DropdownMenuItem(value: 5, child: Text('5 readings')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _consecutiveReadings = val);
              },
            ),
          ),
          ListTile(
            title: const Text('Minimum Station Dwell Time'),
            subtitle: const Text(
              'Requires staying in stop radius to confirm train/bus arrival',
            ),
            trailing: DropdownButton<int>(
              value: _minDwellSeconds,
              items: const [
                DropdownMenuItem(value: 5, child: Text('5 seconds')),
                DropdownMenuItem(value: 10, child: Text('10 seconds (Default)')),
                DropdownMenuItem(value: 20, child: Text('20 seconds')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _minDwellSeconds = val);
              },
            ),
          ),
          ListTile(
            title: const Text('Max GPS Accuracy Error Allowed'),
            subtitle: Text('Rejects readings with accuracy error > ±${_maxAccuracyMeters.toStringAsFixed(0)}m'),
            trailing: DropdownButton<double>(
              value: _maxAccuracyMeters,
              items: const [
                DropdownMenuItem(value: 30.0, child: Text('±30m (Strict)')),
                DropdownMenuItem(value: 50.0, child: Text('±50m (Standard)')),
                DropdownMenuItem(value: 80.0, child: Text('±80m (Relaxed)')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _maxAccuracyMeters = val);
              },
            ),
          ),
          const Divider(height: 32),
          Text(
            'Hardware & Alert Diagnostics',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.vibration),
            title: const Text('Test Vibration'),
            subtitle: const Text('Triggers standard transit pulse pattern'),
            onTap: () {
              _alarmService.triggerAlarm(
                config: const AlarmConfig(soundEnabled: false, vibrationEnabled: true),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.volume_up_outlined),
            title: const Text('Test Audio Alert'),
            subtitle: const Text('Plays alarm chime sound burst'),
            onTap: () {
              _alarmService.triggerAlarm(
                config: const AlarmConfig(soundEnabled: true, vibrationEnabled: false),
              );
            },
          ),
          const Divider(height: 32),
          Text(
            'Local Data Management',
            style: theme.textTheme.titleSmall?.copyWith(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Clear All Saved Journeys', style: TextStyle(color: Colors.red)),
            subtitle: const Text('Wipes local SharedPreferences storage completely'),
            onTap: _clearAllData,
          ),
        ],
      ),
    );
  }
}
