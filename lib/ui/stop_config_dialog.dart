import 'package:flutter/material.dart';
import '../models/alarm_config.dart';
import '../models/contact_checkin_config.dart';
import '../models/stop.dart';
import '../services/alarm_service.dart';

/// Modal dialog for adding or editing a stop, including its arrival radius,
/// sound/vibration alarm configuration, and contact check-in details.
class StopConfigDialog extends StatefulWidget {
  const StopConfigDialog({
    super.key,
    this.existingStop,
    required this.order,
    this.isFinalDestination = false,
  });

  final Stop? existingStop;
  final int order;
  final bool isFinalDestination;

  static Future<Stop?> show(
    BuildContext context, {
    Stop? existingStop,
    required int order,
    bool isFinalDestination = false,
  }) {
    return showDialog<Stop>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StopConfigDialog(
        existingStop: existingStop,
        order: order,
        isFinalDestination: isFinalDestination,
      ),
    );
  }

  @override
  State<StopConfigDialog> createState() => _StopConfigDialogState();
}

class _StopConfigDialogState extends State<StopConfigDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _formKey = GlobalKey<FormState>();

  // Location fields
  late final TextEditingController _nameController;
  late final TextEditingController _latController;
  late final TextEditingController _lonController;
  late final TextEditingController _radiusController;

  // Alarm fields
  late bool _soundEnabled;
  late String _selectedSound;
  late bool _vibrationEnabled;
  late int _repeatCount;
  late int _snoozeMinutes;

  // Contact fields
  late bool _enableCheckIn;
  late final TextEditingController _contactNameController;
  late final TextEditingController _phoneNumberController;
  late final TextEditingController _customMessageController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    final stop = widget.existingStop;
    _nameController = TextEditingController(text: stop?.name ?? '');
    _latController = TextEditingController(
      text: stop != null ? stop.latitude.toString() : '',
    );
    _lonController = TextEditingController(
      text: stop != null ? stop.longitude.toString() : '',
    );
    _radiusController = TextEditingController(
      text: stop != null ? stop.radiusMeters.toStringAsFixed(0) : '500',
    );

    // Alarm config
    final alarm = stop?.alarmConfig ?? const AlarmConfig();
    _soundEnabled = alarm.soundEnabled;
    _selectedSound = alarm.soundName;
    _vibrationEnabled = alarm.vibrationEnabled;
    _repeatCount = alarm.maxRepeats;
    _snoozeMinutes = alarm.snoozeDurationMinutes;

    // Contact config
    final contact = stop?.contacts.isNotEmpty == true ? stop!.contacts.first : null;
    _enableCheckIn = contact != null;
    _contactNameController = TextEditingController(
      text: contact?.contactName ?? '',
    );
    _phoneNumberController = TextEditingController(
      text: contact?.phoneNumber ?? '',
    );
    _customMessageController = TextEditingController(
      text: contact?.customMessage ?? 'I have reached my stop safely.',
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _latController.dispose();
    _lonController.dispose();
    _radiusController.dispose();
    _contactNameController.dispose();
    _phoneNumberController.dispose();
    _customMessageController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final lat = double.parse(_latController.text.trim());
    final lon = double.parse(_lonController.text.trim());
    final radius = double.parse(_radiusController.text.trim());

    final alarmConfig = AlarmConfig(
      soundEnabled: _soundEnabled,
      soundName: _selectedSound,
      vibrationEnabled: _vibrationEnabled,
      maxRepeats: _repeatCount,
      snoozeDurationMinutes: _snoozeMinutes,
    );

    final contacts = <ContactCheckInConfig>[];
    if (_enableCheckIn &&
        _contactNameController.text.trim().isNotEmpty &&
        _phoneNumberController.text.trim().isNotEmpty) {
      contacts.add(
        ContactCheckInConfig(
          id: widget.existingStop?.contacts.isNotEmpty == true
              ? widget.existingStop!.contacts.first.id
              : 'contact_${DateTime.now().millisecondsSinceEpoch}',
          contactName: _contactNameController.text.trim(),
          phoneNumber: _phoneNumberController.text.trim(),
          customMessage: _customMessageController.text.trim(),
        ),
      );
    }

    final stop = Stop(
      id: widget.existingStop?.id ??
          'stop_${DateTime.now().millisecondsSinceEpoch}_${widget.order}',
      name: _nameController.text.trim(),
      latitude: lat,
      longitude: lon,
      radiusMeters: radius,
      order: widget.order,
      isFinalDestination: widget.isFinalDestination,
      alarmConfig: alarmConfig,
      contacts: contacts,
    );

    Navigator.of(context).pop(stop);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existingStop != null;

    return AlertDialog(
      title: Text(isEditing ? 'Configure Stop' : 'Add Stop'),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: 440,
        height: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.place_outlined), text: 'Location'),
                  Tab(icon: Icon(Icons.alarm_outlined), text: 'Alarm'),
                  Tab(icon: Icon(Icons.sms_outlined), text: 'Check-In'),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildLocationTab(theme),
                    _buildAlarmTab(theme),
                    _buildContactTab(theme),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check, size: 18),
          label: Text(isEditing ? 'Save Changes' : 'Add Stop'),
        ),
      ],
    );
  }

  Widget _buildLocationTab(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Stop Name',
              hintText: 'e.g. Rajiv Chowk Station',
              prefixIcon: Icon(Icons.label_outline),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter stop name' : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _latController,
                  decoration: const InputDecoration(
                    labelText: 'Latitude',
                    hintText: '28.6328',
                    prefixIcon: Icon(Icons.my_location),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: (v) {
                    final num = double.tryParse(v ?? '');
                    if (num == null || num < -90 || num > 90) {
                      return 'Range: -90 to 90';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _lonController,
                  decoration: const InputDecoration(
                    labelText: 'Longitude',
                    hintText: '77.2195',
                    prefixIcon: Icon(Icons.location_searching),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: (v) {
                    final num = double.tryParse(v ?? '');
                    if (num == null || num < -180 || num > 180) {
                      return 'Range: -180 to 180';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _radiusController,
            decoration: const InputDecoration(
              labelText: 'Arrival Radius (meters)',
              hintText: '500',
              prefixIcon: Icon(Icons.radar),
              helperText: 'Triggers alert when GPS fix enters this boundary',
            ),
            keyboardType: TextInputType.number,
            validator: (v) {
              final num = double.tryParse(v ?? '');
              if (num == null || num <= 0) return 'Must be > 0';
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAlarmTab(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Sound Alert'),
            subtitle: const Text('Play audible chime upon arrival'),
            value: _soundEnabled,
            onChanged: (val) => setState(() => _soundEnabled = val),
          ),
          if (_soundEnabled) ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedSound,
              decoration: const InputDecoration(
                labelText: 'Sound Chime',
                prefixIcon: Icon(Icons.music_note),
              ),
              items: AlarmService.availableSounds
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedSound = val);
              },
            ),
            const SizedBox(height: 12),
          ],
          SwitchListTile(
            title: const Text('Tactile Vibration'),
            subtitle: const Text('Vibrate phone with alert pulse'),
            value: _vibrationEnabled,
            onChanged: (val) => setState(() => _vibrationEnabled = val),
          ),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('Repeat Alert'),
            subtitle: Text('Repeats $_repeatCount times if not dismissed'),
            trailing: DropdownButton<int>(
              value: _repeatCount,
              items: const [
                DropdownMenuItem(value: 0, child: Text('Once only')),
                DropdownMenuItem(value: 1, child: Text('Repeat 1x')),
                DropdownMenuItem(value: 3, child: Text('Repeat 3x')),
                DropdownMenuItem(value: 5, child: Text('Repeat 5x')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _repeatCount = val);
              },
            ),
          ),
          ListTile(
            title: const Text('Snooze Duration'),
            subtitle: Text('$_snoozeMinutes minutes'),
            trailing: DropdownButton<int>(
              value: _snoozeMinutes,
              items: const [
                DropdownMenuItem(value: 3, child: Text('3 mins')),
                DropdownMenuItem(value: 5, child: Text('5 mins')),
                DropdownMenuItem(value: 10, child: Text('10 mins')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _snoozeMinutes = val);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactTab(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: const Text('Arrival Check-In Message'),
            subtitle: const Text('Prepare SMS check-in when reached'),
            value: _enableCheckIn,
            onChanged: (val) => setState(() => _enableCheckIn = val),
          ),
          if (_enableCheckIn) ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _contactNameController,
              decoration: const InputDecoration(
                labelText: 'Contact Name',
                hintText: 'e.g. Mom / Spouse',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) {
                if (_enableCheckIn && (v == null || v.trim().isEmpty)) {
                  return 'Enter contact name';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneNumberController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                hintText: 'e.g. +91 9876543210',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              keyboardType: TextInputType.phone,
              validator: (v) {
                if (_enableCheckIn && (v == null || v.trim().isEmpty)) {
                  return 'Enter phone number';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _customMessageController,
              decoration: const InputDecoration(
                labelText: 'Custom Check-In Message',
                hintText: 'I have arrived safely at this stop.',
                prefixIcon: Icon(Icons.message_outlined),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(10.0),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Complies with Android SMS policy. Opens SMS composer prefilled; you tap Send.',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
