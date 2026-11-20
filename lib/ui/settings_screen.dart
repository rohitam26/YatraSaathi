import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../services/alarm_service.dart';
import '../services/direct_sms_service.dart';
import '../services/journey_repository.dart';
import '../services/offline_map_service.dart';
import 'permission_guidance_screen.dart';
import 'privacy_info_screen.dart';
import 'safety_contacts_screen.dart';
import 'tracking_diagnostics_screen.dart';

/// Comprehensive settings screen providing passenger safety profile management,
/// arrival alert preferences, and diagnostic controls.
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

  // User Safety Profile
  final TextEditingController _userNameController = TextEditingController();
  final TextEditingController _userPhoneController = TextEditingController();
  String _countryCode = '+91';
  final TextEditingController _defaultContactName = TextEditingController();
  final TextEditingController _defaultContactPhone = TextEditingController();
  String _defaultContactRelation = 'Emergency Contact';
  final TextEditingController _defaultMessage = TextEditingController(
    text: 'Hi! I have safely reached my stop. - Sent via STOP Vanthachu',
  );
  bool _autoCheckInOnArrival = true;
  bool _enableDirectSms = false;
  bool _directSmsConsentGiven = false;
  final DirectSmsService _directSmsService = const DirectSmsService();
  final OfflineMapService _offlineMapService = OfflineMapService();
  String _cachedTileStats = 'Calculating...';

  // Passenger Defaults
  String _defaultSound = 'Default Chime';
  String _vibrationPattern = 'urgent';
  double _defaultRadius = 500.0;

  // Advanced Technical Parameters
  int _consecutiveReadings = 3;
  int _minDwellSeconds = 10;
  double _maxAccuracyMeters = 80.0;
  bool _advancedExpanded = false;

  @override
  void initState() {
    super.initState();
    _alarmService = widget.alarmService ?? AlarmService();
    _loadPreferences();
    _refreshCacheStats();
  }

  Future<void> _refreshCacheStats() async {
    final stats = await _offlineMapService.getCacheStats();
    if (mounted) {
      setState(() {
        _cachedTileStats = '${stats["count"]} tiles (${stats["formattedSize"]})';
      });
    }
  }

  @override
  void dispose() {
    _userNameController.dispose();
    _userPhoneController.dispose();
    _defaultContactName.dispose();
    _defaultContactPhone.dispose();
    _defaultMessage.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final profile = await widget.repository.getUserProfile();
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;
    setState(() {
      _userNameController.text = profile.userName;
      _userPhoneController.text = profile.userPhone;
      _countryCode = profile.countryCode.isNotEmpty ? profile.countryCode : '+91';
      _defaultContactName.text = profile.defaultContactName;
      _defaultContactPhone.text = profile.defaultContactPhone;
      _defaultContactRelation = profile.defaultContactRelation.isNotEmpty
          ? profile.defaultContactRelation
          : 'Emergency Contact';
      _defaultMessage.text = profile.defaultMessage;
      _autoCheckInOnArrival = profile.autoCheckInOnArrival;
      _enableDirectSms = profile.enableDirectSms;
      _directSmsConsentGiven = profile.directSmsConsentGiven;

      _defaultSound = prefs.getString('pref_default_sound') ?? 'Default Chime';
      _vibrationPattern =
          prefs.getString('pref_vibration_pattern') ?? 'urgent';
      _defaultRadius = prefs.getDouble('pref_default_radius') ?? 500.0;
      _consecutiveReadings = prefs.getInt('pref_consecutive_readings') ?? 3;
      _minDwellSeconds = prefs.getInt('pref_min_dwell_seconds') ?? 10;
      _maxAccuracyMeters = prefs.getDouble('pref_max_accuracy') ?? 80.0;
    });
  }

  Future<void> _handleDirectSmsToggle(bool enabled) async {
    if (!enabled) {
      setState(() => _enableDirectSms = false);
      await _savePreferences();
      return;
    }

    final consent = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security, color: Colors.indigo),
            SizedBox(width: 8),
            Text('Enable Direct Emergency SMS?'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Automated Emergency SMS dispatches safety alerts directly in the background using your device cellular SIM without requiring manual app interaction during an emergency.',
              style: TextStyle(fontSize: 13),
            ),
            SizedBox(height: 10),
            Text(
              '• Carrier charges apply according to your standard mobile SMS plan.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 6),
            Text(
              '• Includes live coordinates, accuracy, and Google Maps link.',
              style: TextStyle(fontSize: 12),
            ),
            SizedBox(height: 6),
            Text(
              '• If SMS permission is revoked or cellular SIM is unavailable, native SMS composer is used as automatic fallback.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('I Agree & Enable'),
          ),
        ],
      ),
    );

    if (consent != true) {
      return;
    }

    // Check SIM readiness
    final simStatus = await _directSmsService.getSimStatus();
    if (!simStatus.isAvailable && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notice: No active cellular SIM detected. Automated SMS may fail until a SIM is inserted.'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    // Request runtime SEND_SMS permission
    final granted = await _directSmsService.requestPermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SEND_SMS permission was denied. Direct SMS cannot be enabled.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _enableDirectSms = true;
        _directSmsConsentGiven = true;
      });
      await _savePreferences(showSnackbar: true);
    }
  }

  Future<void> _savePreferences({bool showSnackbar = false}) async {
    final profile = UserProfile(
      userName: _userNameController.text.trim(),
      userPhone: _userPhoneController.text.trim(),
      countryCode: _countryCode,
      defaultContactName: _defaultContactName.text.trim(),
      defaultContactPhone: _defaultContactPhone.text.trim(),
      defaultContactRelation: _defaultContactRelation,
      defaultMessage: _defaultMessage.text.trim(),
      autoCheckInOnArrival: _autoCheckInOnArrival,
      enableDirectSms: _enableDirectSms,
      directSmsConsentGiven: _directSmsConsentGiven,
    );
    await widget.repository.saveUserProfile(profile);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pref_default_sound', _defaultSound);
    await prefs.setString('pref_vibration_pattern', _vibrationPattern);
    await prefs.setDouble('pref_default_radius', _defaultRadius);
    await prefs.setInt('pref_consecutive_readings', _consecutiveReadings);
    await prefs.setInt('pref_min_dwell_seconds', _minDwellSeconds);
    await prefs.setDouble('pref_max_accuracy', _maxAccuracyMeters);

    if (showSnackbar && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Safety Profile and preferences saved successfully.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleTestSound() async {
    final result = await _alarmService.testArrivalSound(soundName: _defaultSound);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _handleTestVibration() async {
    final result = await _alarmService.testVibration();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _handleTestNotification() async {
    final result = await _alarmService.testArrivalNotification();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Local Data?'),
        content: const Text(
          'This will permanently delete your safety profile, all saved journeys and contact preferences from this device.',
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      _userNameController.clear();
      _userPhoneController.clear();
      _defaultContactName.clear();
      _defaultContactPhone.clear();
      _defaultMessage.text =
          'Hi! I have safely reached my stop. - Sent via STOP Vanthachu';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All local data cleared successfully.')),
        );
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Preferences'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save Settings',
            onPressed: () => _savePreferences(showSnackbar: true),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Section 1: Default Safety Contact & Check-In
          _buildSectionHeader('Default Safety Contact & Check-In'),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.shield, color: colorScheme.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MY SAFETY PROFILE',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Configured once, auto-populated on new journeys',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // Passenger's Own Identity
                  Text(
                    'Your Details (Identifies you to contacts)',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _userNameController,
                    decoration: const InputDecoration(
                      labelText: 'Your Name',
                      hintText: 'e.g. Rahul Sharma',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _savePreferences(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        width: 105,
                        child: DropdownButtonFormField<String>(
                          initialValue: _countryCode,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Code',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: '+91', child: Text('+91')),
                            DropdownMenuItem(value: '+1', child: Text('+1')),
                            DropdownMenuItem(value: '+44', child: Text('+44')),
                            DropdownMenuItem(value: '+61', child: Text('+61')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _countryCode = v);
                              _savePreferences();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _userPhoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Your Mobile Number',
                            hintText: '98765 43210',
                            prefixIcon: Icon(Icons.phone_android),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => _savePreferences(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // SMS SIM Clarification Callout
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Android SIM Notice: Check-in SMS messages are dispatched via your Android SMS app using your active SIM card. Entering your mobile number here formats your identification in the prefilled message.',
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Emergency Contact Info
                  Text(
                    'Default Safety / Emergency Contact',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _defaultContactName,
                          decoration: const InputDecoration(
                            labelText: 'Contact Name',
                            hintText: 'e.g. Mom, Partner, Friend',
                            prefixIcon: Icon(Icons.contact_phone_outlined),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => _savePreferences(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: _defaultContactRelation,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Relation',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Emergency Contact', child: Text('Emergency')),
                            DropdownMenuItem(value: 'Parent', child: Text('Parent')),
                            DropdownMenuItem(value: 'Partner', child: Text('Partner')),
                            DropdownMenuItem(value: 'Sibling', child: Text('Sibling')),
                            DropdownMenuItem(value: 'Friend', child: Text('Friend')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _defaultContactRelation = v);
                              _savePreferences();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _defaultContactPhone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Contact Phone Number',
                      hintText: 'e.g. +91 98765 43210',
                      prefixIcon: Icon(Icons.phone),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _savePreferences(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _defaultMessage,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Default Check-In Message Template',
                      prefixIcon: Icon(Icons.sms_outlined),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _savePreferences(),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Prepare SMS check-in on arrival'),
                    subtitle: const Text('Opens Android SMS composer with pre-filled message upon arrival'),
                    value: _autoCheckInOnArrival,
                    onChanged: (val) {
                      setState(() => _autoCheckInOnArrival = val);
                      _savePreferences();
                    },
                  ),
                  const Divider(height: 20),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Direct Emergency SMS Dispatch'),
                    subtitle: const Text(
                      'Sends SMS in background via Android telephony radio without opening composer. Requires cellular SIM and explicit user permission.',
                    ),
                    value: _enableDirectSms,
                    onChanged: (val) => _handleDirectSmsToggle(val),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => SafetyContactsScreen(
                            repository: widget.repository,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.contacts_outlined),
                    label: const Text('Manage Multiple Safety Contacts'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _savePreferences(showSnackbar: true),
                    icon: const Icon(Icons.save),
                    label: const Text('Save Safety Profile'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Section 2: Passenger Arrival Alert Defaults
          _buildSectionHeader('Arrival Alert Defaults'),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _defaultSound,
                    decoration: const InputDecoration(
                      labelText: 'Default Chime Sound',
                      prefixIcon: Icon(Icons.music_note_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: AlarmService.availableSounds.map((snd) {
                      return DropdownMenuItem(
                        value: snd,
                        child: Text(snd.replaceAll('_', ' ').toUpperCase()),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _defaultSound = v);
                        _savePreferences();
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<double>(
                    initialValue: _defaultRadius,
                    decoration: const InputDecoration(
                      labelText: 'Default Alert Radius',
                      prefixIcon: Icon(Icons.radar_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 200.0, child: Text('200 m (Walking)')),
                      DropdownMenuItem(value: 500.0, child: Text('500 m (Standard)')),
                      DropdownMenuItem(value: 1000.0, child: Text('1.0 km (Train/Express)')),
                      DropdownMenuItem(value: 2000.0, child: Text('2.0 km (Highway)')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _defaultRadius = v);
                        _savePreferences();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Section 3: Privacy & System Permissions
          _buildSectionHeader('Privacy & System Permissions'),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.security_outlined),
                  title: const Text('Privacy & Offline Storage'),
                  subtitle: const Text('100% offline data handling'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const PrivacyInfoScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.satellite_alt_outlined),
                  title: const Text('Live GPS & Tracking Diagnostics'),
                  subtitle: const Text('Real-time fix accuracy, telemetry and hardware status'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const TrackingDiagnosticsScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.perm_device_information_outlined),
                  title: const Text('System Permissions Guide'),
                  subtitle: const Text('Location, background & notifications'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const PermissionGuidanceScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section 3b: Offline Map Storage
          _buildSectionHeader('Offline Map Storage'),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.offline_pin_outlined, color: Colors.teal),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Persistent Tile Cache',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _cachedTileStats,
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh cache size',
                        onPressed: _refreshCacheStats,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await _offlineMapService.clearTileCache();
                      await _refreshCacheStats();
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Offline tile cache cleared.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('Clear Cached Map Tiles'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Section 4: Advanced Settings (Collapsible)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ExpansionTile(
              initiallyExpanded: _advancedExpanded,
              onExpansionChanged: (val) => setState(() => _advancedExpanded = val),
              leading: const Icon(Icons.tune_outlined),
              title: const Text('Advanced Settings & Diagnostics'),
              subtitle: const Text('Technical GPS sensitivity and hardware testing'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: _consecutiveReadings,
                        decoration: const InputDecoration(
                          labelText: 'Required Consecutive GPS Samples',
                          border: OutlineInputBorder(),
                        ),
                        items: [1, 2, 3, 5]
                            .map((c) => DropdownMenuItem(value: c, child: Text('$c samples')))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _consecutiveReadings = v);
                            _savePreferences();
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: _minDwellSeconds,
                        decoration: const InputDecoration(
                          labelText: 'Minimum Dwell Duration',
                          border: OutlineInputBorder(),
                        ),
                        items: [5, 10, 30, 60]
                            .map((s) => DropdownMenuItem(value: s, child: Text('$s seconds')))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _minDwellSeconds = v);
                            _savePreferences();
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<double>(
                        initialValue: _maxAccuracyMeters,
                        decoration: const InputDecoration(
                          labelText: 'GPS Accuracy Filter Threshold',
                          border: OutlineInputBorder(),
                        ),
                        items: [50.0, 80.0, 100.0, 150.0]
                            .map((a) => DropdownMenuItem(value: a, child: Text('±${a.toStringAsFixed(0)} m')))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _maxAccuracyMeters = v);
                            _savePreferences();
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Hardware Diagnostics',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _handleTestSound,
                              icon: const Icon(Icons.volume_up),
                              label: const Text('Test Chime'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _handleTestVibration,
                              icon: const Icon(Icons.vibration),
                              label: const Text('Test Vibration'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _handleTestNotification,
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const Text('Test Arrival Notification (Speaker + Vibration)'),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(foregroundColor: Colors.red),
                        onPressed: _clearAllData,
                        child: const Text('Clear All Local Data'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
