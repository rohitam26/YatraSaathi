import 'package:flutter/material.dart';
import '../models/contact_checkin_config.dart';
import '../models/journey.dart';
import '../models/safety_contact.dart';
import '../models/stop.dart';
import '../models/user_profile.dart';
import '../services/alarm_service.dart';
import '../services/journey_repository.dart';
import 'stop_config_dialog.dart';
import 'widgets/journey_map_view.dart';
import 'widgets/map_location_picker.dart';

/// 5-Step progressive Journey Creation Wizard designed for intuitive,
/// non-technical passenger experience.
class JourneyWizardScreen extends StatefulWidget {
  const JourneyWizardScreen({
    super.key,
    this.existingJourney,
    required this.repository,
  });

  final Journey? existingJourney;
  final JourneyRepository repository;

  @override
  State<JourneyWizardScreen> createState() => _JourneyWizardScreenState();
}

class _JourneyWizardScreenState extends State<JourneyWizardScreen> {
  int _currentStep = 0;
  final _formKeyStep1 = GlobalKey<FormState>();

  // Step 1: Details
  late final TextEditingController _journeyNameController;
  late final TextEditingController _startLocationController;
  late final TextEditingController _finalDestController;
  double? _startLat;
  double? _startLon;
  double? _destLat;
  double? _destLon;

  // Step 2: Stops
  final List<Stop> _stops = [];

  // Step 3: Global / Default Alarm Config
  bool _defaultSoundEnabled = true;
  String _defaultSound = 'Default Chime';
  bool _defaultVibrationEnabled = true;
  int _defaultRepeatCount = 3;
  int _defaultSnoozeMinutes = 5;

  // Step 4: Safety Check-in Contact
  bool _checkInEnabled = true;
  final TextEditingController _contactNameController = TextEditingController();
  final TextEditingController _contactPhoneController = TextEditingController();
  final TextEditingController _checkInMessageController = TextEditingController(
    text: 'Hi! I have safely reached my stop. - Sent via YatraSaathi',
  );

  UserProfile? _userProfile;
  List<SafetyContact> _safetyContacts = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSafetyContacts();
    final existing = widget.existingJourney;

    _journeyNameController = TextEditingController(
      text: existing?.name ?? '',
    );
    _startLocationController = TextEditingController(
      text: existing != null && existing.stops.isNotEmpty
          ? existing.stops.first.name
          : '',
    );
    _finalDestController = TextEditingController(
      text: existing != null && existing.stops.length > 1
          ? existing.stops.last.name
          : '',
    );

    if (existing != null) {
      _stops.addAll(existing.stops);
      if (existing.stops.isNotEmpty) {
        final first = existing.stops.first;
        _startLat = first.latitude;
        _startLon = first.longitude;
      }
      if (existing.stops.length > 1) {
        final last = existing.stops.last;
        _destLat = last.latitude;
        _destLon = last.longitude;
      }
      if (existing.stops.isNotEmpty) {
        final alarm = existing.stops.first.alarmConfig;
        _defaultSoundEnabled = alarm.soundEnabled;
        _defaultSound = alarm.soundName;
        _defaultVibrationEnabled = alarm.vibrationEnabled;
        _defaultRepeatCount = alarm.maxRepeats;
        _defaultSnoozeMinutes = alarm.snoozeDurationMinutes;

        if (existing.stops.first.contacts.isNotEmpty) {
          final contact = existing.stops.first.contacts.first;
          _contactNameController.text = contact.contactName;
          _contactPhoneController.text = contact.phoneNumber;
          _checkInMessageController.text = contact.customMessage;
          _checkInEnabled = true;
        }
      }
    } else {
      _loadDefaultSafetyProfile();
    }
  }

  Future<void> _loadDefaultSafetyProfile() async {
    try {
      final profile = await widget.repository.getUserProfile();
      if (!mounted) return;
      setState(() {
        _userProfile = profile;
        if (profile.hasDefaultContact) {
          _contactNameController.text = profile.defaultContactName;
          _contactPhoneController.text = profile.formattedContactPhone;
          _checkInMessageController.text = profile.defaultMessage;
          _checkInEnabled = profile.autoCheckInOnArrival;
        }
      });
    } catch (_) {}
  }

  Future<void> _loadSafetyContacts() async {
    try {
      final contacts = await widget.repository.getSafetyContacts();
      if (!mounted) return;
      setState(() {
        _safetyContacts = contacts;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _journeyNameController.dispose();
    _startLocationController.dispose();
    _finalDestController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _checkInMessageController.dispose();
    super.dispose();
  }

  // --- Map Picker Triggers for Step 1 ---
  Future<void> _pickStartLocation() async {
    final picked = await MapLocationPicker.pickLocation(
      context,
      initialLatitude: _startLat,
      initialLongitude: _startLon,
      initialPlaceName: _startLocationController.text.trim(),
    );
    if (picked != null) {
      setState(() {
        _startLocationController.text = picked.name;
        _startLat = picked.latitude;
        _startLon = picked.longitude;
      });
    }
  }

  Future<void> _pickDestLocation() async {
    final picked = await MapLocationPicker.pickLocation(
      context,
      initialLatitude: _destLat,
      initialLongitude: _destLon,
      initialPlaceName: _finalDestController.text.trim(),
    );
    if (picked != null) {
      setState(() {
        _finalDestController.text = picked.name;
        _destLat = picked.latitude;
        _destLon = picked.longitude;
      });
    }
  }

  // --- Step 2: Add and Manage Stops ---
  Future<void> _addNewStop() async {
    final newStop = await StopConfigDialog.show(
      context,
      order: _stops.length,
      isFinalDestination: false,
      defaultProfile: _userProfile,
      availableContacts: _safetyContacts,
    );
    if (newStop != null) {
      setState(() {
        _stops.add(newStop);
        _reindexStops();
      });
    }
  }

  Future<void> _editStop(int index) async {
    final stop = _stops[index];
    final updated = await StopConfigDialog.show(
      context,
      existingStop: stop,
      order: index,
      isFinalDestination: index == _stops.length - 1 && _stops.length > 1,
      defaultProfile: _userProfile,
      availableContacts: _safetyContacts,
    );
    if (updated != null) {
      setState(() {
        _stops[index] = updated;
        _reindexStops();
      });
    }
  }

  void _removeStop(int index) {
    setState(() {
      _stops.removeAt(index);
      _reindexStops();
    });
  }

  void _reindexStops() {
    for (int i = 0; i < _stops.length; i++) {
      final isLast = i == _stops.length - 1;
      _stops[i] = _stops[i].copyWith(
        order: i,
        isFinalDestination: isLast && _stops.length > 1,
      );
    }
  }

  // --- Ensure Start & End from Step 1 are in _stops ---
  void _syncStep1ToStops() {
    if (_startLocationController.text.trim().isNotEmpty && _startLat != null) {
      // Check if first stop exists
      if (_stops.isEmpty) {
        _stops.add(
          Stop(
            id: 'stop_start_${DateTime.now().millisecondsSinceEpoch}',
            name: _startLocationController.text.trim(),
            latitude: _startLat!,
            longitude: _startLon!,
            radiusMeters: 500,
            order: 0,
            isFinalDestination: false,
          ),
        );
      } else {
        _stops[0] = _stops[0].copyWith(
          name: _startLocationController.text.trim(),
          latitude: _startLat!,
          longitude: _startLon!,
        );
      }
    }

    if (_finalDestController.text.trim().isNotEmpty && _destLat != null) {
      if (_stops.length <= 1) {
        _stops.add(
          Stop(
            id: 'stop_dest_${DateTime.now().millisecondsSinceEpoch}',
            name: _finalDestController.text.trim(),
            latitude: _destLat!,
            longitude: _destLon!,
            radiusMeters: 500,
            order: _stops.length,
            isFinalDestination: true,
          ),
        );
      } else {
        final lastIdx = _stops.length - 1;
        _stops[lastIdx] = _stops[lastIdx].copyWith(
          name: _finalDestController.text.trim(),
          latitude: _destLat!,
          longitude: _destLon!,
          isFinalDestination: true,
        );
      }
    }

    _reindexStops();
  }

  // --- Final Save & Return ---
  Future<void> _saveAndReturn() async {
    setState(() => _isSaving = true);

    // Apply default contact check-in to stops that don't have custom contacts
    final finalizedStops = _stops.map((stop) {
      var updated = stop;
      // Default contact check-in if configured in Step 4 and stop has no custom contacts
      if (_checkInEnabled &&
          _contactPhoneController.text.trim().isNotEmpty &&
          stop.contacts.isEmpty) {
        updated = updated.copyWith(
          contacts: [
            ContactCheckInConfig(
              id: 'contact_${DateTime.now().millisecondsSinceEpoch}_${stop.order}',
              contactName: _contactNameController.text.trim().isNotEmpty
                  ? _contactNameController.text.trim()
                  : 'Emergency Contact',
              phoneNumber: _contactPhoneController.text.trim(),
              customMessage: _checkInMessageController.text.trim(),
            ),
          ],
        );
      }
      return updated;
    }).toList();

    final journeyName = _journeyNameController.text.trim().isNotEmpty
        ? _journeyNameController.text.trim()
        : 'Journey to ${_finalDestController.text.trim().isNotEmpty ? _finalDestController.text.trim() : "Destination"}';

    final journey = Journey(
      id: widget.existingJourney?.id ??
          'journey_${DateTime.now().millisecondsSinceEpoch}',
      name: journeyName,
      status: JourneyStatus.planning,
      stops: finalizedStops,
      createdAt: widget.existingJourney?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await widget.repository.saveJourney(journey);

    if (mounted) {
      setState(() => _isSaving = false);
      Navigator.of(context).pop(journey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingJourney != null ? 'Edit Journey' : 'Plan a Journey',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Stepper(
        type: StepperType.horizontal,
        currentStep: _currentStep,
        onStepTapped: (step) => setState(() => _currentStep = step),
        onStepContinue: () {
          if (_currentStep == 0) {
            if (!_formKeyStep1.currentState!.validate()) return;
            _syncStep1ToStops();
          }
          if (_currentStep < 4) {
            setState(() => _currentStep++);
          } else {
            _saveAndReturn();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep--);
          } else {
            Navigator.of(context).pop();
          }
        },
        controlsBuilder: (context, details) {
          final isLast = _currentStep == 4;
          return Padding(
            padding: const EdgeInsets.only(top: 24.0),
            child: Row(
              children: [
                if (_currentStep > 0) ...[
                  OutlinedButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Back'),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : details.onStepContinue,
                    icon: Icon(isLast ? Icons.check_circle : Icons.arrow_forward),
                    label: Text(isLast ? 'Save Journey' : 'Next Step'),
                  ),
                ),
              ],
            ),
          );
        },
        steps: [
          // Step 1: Journey Details
          Step(
            title: const Text('Details'),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: _buildStep1(theme, colorScheme),
          ),
          // Step 2: Stops Management
          Step(
            title: const Text('Stops'),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
            content: _buildStep2(theme, colorScheme),
          ),
          // Step 3: Arrival Alerts
          Step(
            title: const Text('Alerts'),
            isActive: _currentStep >= 2,
            state: _currentStep > 2 ? StepState.complete : StepState.indexed,
            content: _buildStep3(theme, colorScheme),
          ),
          // Step 4: Safety Check-in
          Step(
            title: const Text('Safety'),
            isActive: _currentStep >= 3,
            state: _currentStep > 3 ? StepState.complete : StepState.indexed,
            content: _buildStep4(theme, colorScheme),
          ),
          // Step 5: Review & Confirm
          Step(
            title: const Text('Review'),
            isActive: _currentStep >= 4,
            state: StepState.indexed,
            content: _buildStep5(theme, colorScheme),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // STEP 1: JOURNEY DETAILS
  // -------------------------------------------------------------
  Widget _buildStep1(ThemeData theme, ColorScheme colorScheme) {
    return Form(
      key: _formKeyStep1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Name Your Journey',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Give your journey an easily recognizable name.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _journeyNameController,
            decoration: InputDecoration(
              labelText: 'Journey Name *',
              hintText: 'e.g. Office Commute, Chennai to Bangalore',
              prefixIcon: const Icon(Icons.directions_bus_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Please name your journey' : null,
          ),
          const SizedBox(height: 20),

          // Starting Location
          Text(
            'Starting Point',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _startLocationController,
                  decoration: InputDecoration(
                    labelText: 'Starting Point',
                    hintText: 'e.g. Home, Chennai Central Station',
                    prefixIcon: const Icon(Icons.my_location),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: const Icon(Icons.map_outlined),
                tooltip: 'Pick on map',
                onPressed: _pickStartLocation,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Final Destination
          Text(
            'Final Destination',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _finalDestController,
                  decoration: InputDecoration(
                    labelText: 'Destination *',
                    hintText: 'e.g. Tambaram Railway Station, Office',
                    prefixIcon: const Icon(Icons.flag_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please specify a final destination'
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: const Icon(Icons.map_outlined),
                tooltip: 'Pick on map',
                onPressed: _pickDestLocation,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // STEP 2: STOPS MANAGEMENT
  // -------------------------------------------------------------
  Widget _buildStep2(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Journey Stops (${_stops.length})',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _addNewStop,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add Stop'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Reorder stops or tap to configure their map location and arrival radius.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),

        if (_stops.isEmpty)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(
                child: Text('No stops added yet. Tap "Add Stop" to choose locations.'),
              ),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _stops.length,
            onReorderItem: (oldIndex, newIndex) {
              setState(() {
                final item = _stops.removeAt(oldIndex);
                _stops.insert(newIndex, item);
                _reindexStops();
              });
            },
            itemBuilder: (context, index) {
              final stop = _stops[index];
              final isLast = index == _stops.length - 1 && _stops.length > 1;

              return Card(
                key: ValueKey(stop.id),
                margin: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isLast
                        ? Colors.deepOrange
                        : colorScheme.primaryContainer,
                    foregroundColor: isLast
                        ? Colors.white
                        : colorScheme.onPrimaryContainer,
                    child: isLast
                        ? const Icon(Icons.flag, size: 18)
                        : Text('${index + 1}'),
                  ),
                  title: Text(
                    stop.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Alert: ${stop.radiusMeters.toStringAsFixed(0)}m radius • '
                    '${stop.alarmConfig.soundEnabled ? "Sound on" : "Muted"}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editStop(index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _removeStop(index),
                      ),
                      const Icon(Icons.drag_handle, color: Colors.grey),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // -------------------------------------------------------------
  // STEP 3: ALERT CONFIGURATION
  // -------------------------------------------------------------
  Widget _buildStep3(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Arrival Alert Preferences',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Configure how your phone alerts you when you reach every stop.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),

        SwitchListTile(
          title: const Text('Audible Chime'),
          subtitle: const Text('Plays clear audio alert when within stop radius'),
          value: _defaultSoundEnabled,
          onChanged: (v) => setState(() => _defaultSoundEnabled = v),
        ),
        if (_defaultSoundEnabled) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _defaultSound,
            decoration: InputDecoration(
              labelText: 'Alert Chime Sound',
              prefixIcon: const Icon(Icons.music_note),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            items: AlarmService.availableSounds.map((snd) {
              return DropdownMenuItem(
                value: snd,
                child: Text(snd.replaceAll('_', ' ').toUpperCase()),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) setState(() => _defaultSound = v);
            },
          ),
        ],

        const Divider(height: 24),
        SwitchListTile(
          title: const Text('Tactile Vibration'),
          subtitle: const Text('Vibrates phone for pocket notification'),
          value: _defaultVibrationEnabled,
          onChanged: (v) => setState(() => _defaultVibrationEnabled = v),
        ),

        const Divider(height: 24),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _defaultRepeatCount,
                decoration: InputDecoration(
                  labelText: 'Alert Repeats',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: [1, 2, 3, 5]
                    .map((c) => DropdownMenuItem(value: c, child: Text('$c times')))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _defaultRepeatCount = v);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _defaultSnoozeMinutes,
                decoration: InputDecoration(
                  labelText: 'Snooze',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: [3, 5, 10]
                    .map((m) => DropdownMenuItem(value: m, child: Text('$m mins')))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _defaultSnoozeMinutes = v);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // STEP 4: SAFETY CONTACT & CHECK-IN
  // -------------------------------------------------------------
  Widget _buildStep4(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Safety Check-In & Emergency Contact',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Notify loved ones when you safely reach your stops. '
          'Upon arrival, YatraSaathi opens your SMS app prefilled with this message.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),

        SwitchListTile(
          title: const Text('Enable Arrival Check-In'),
          subtitle: const Text('Automatically prepare safety SMS upon arrival'),
          value: _checkInEnabled,
          onChanged: (v) => setState(() => _checkInEnabled = v),
        ),

        if (_checkInEnabled) ...[
          if (_safetyContacts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Select from Saved Safety Contacts:',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _safetyContacts.map((contact) {
                return ActionChip(
                  avatar: Icon(
                    contact.isPrimary ? Icons.star : Icons.person_outline,
                    size: 16,
                    color: contact.isPrimary ? Colors.amber[800] : null,
                  ),
                  label: Text('${contact.name} (${contact.relationship})'),
                  onPressed: () {
                    setState(() {
                      _contactNameController.text = contact.name;
                      _contactPhoneController.text = contact.formattedPhoneNumber;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          TextFormField(
            controller: _contactNameController,
            decoration: InputDecoration(
              labelText: 'Contact Name',
              hintText: 'e.g. Mom, Partner, Friend',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _contactPhoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Contact Phone Number',
              hintText: 'e.g. +91 98765 43210',
              prefixIcon: const Icon(Icons.phone_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _checkInMessageController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Check-In Message Template',
              prefixIcon: const Icon(Icons.message_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Message Preview
          Card(
            color: colorScheme.surfaceContainerHighest.withAlpha(80),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.visibility_outlined,
                          size: 16, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Live SMS Preview',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _checkInMessageController.text.trim().isNotEmpty
                        ? _checkInMessageController.text.trim()
                        : 'Hi! I have safely reached my stop. - Sent via YatraSaathi',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Honest delivery: Opens in Android SMS app with one tap.',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------
  // STEP 5: REVIEW & CONFIRM
  // -------------------------------------------------------------
  Widget _buildStep5(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Review Your Complete Journey',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Inspect your route map and stop configurations before saving.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),

        // Interactive Journey Route Map
        if (_stops.isNotEmpty) ...[
          JourneyMapView(
            stops: _stops,
            height: 220,
          ),
          const SizedBox(height: 14),
        ],

        // Journey Summary Card
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.route, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _journeyNameController.text.trim().isNotEmpty
                            ? _journeyNameController.text.trim()
                            : 'Planned Journey',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                _buildReviewRow(
                  Icons.trip_origin,
                  'Start',
                  _startLocationController.text.trim().isNotEmpty
                      ? _startLocationController.text.trim()
                      : (_stops.isNotEmpty ? _stops.first.name : 'Not set'),
                ),
                const SizedBox(height: 8),
                _buildReviewRow(
                  Icons.flag,
                  'Destination',
                  _finalDestController.text.trim().isNotEmpty
                      ? _finalDestController.text.trim()
                      : (_stops.length > 1 ? _stops.last.name : 'Not set'),
                ),
                const SizedBox(height: 8),
                _buildReviewRow(
                  Icons.format_list_numbered,
                  'Stops Count',
                  '${_stops.length} stop(s) configured',
                ),
                const SizedBox(height: 8),
                _buildReviewRow(
                  Icons.alarm,
                  'Alerts',
                  _defaultSoundEnabled
                      ? 'Sound on (${_defaultSound.replaceAll("_", " ")})'
                      : 'Muted',
                ),
                if (_checkInEnabled &&
                    _contactPhoneController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildReviewRow(
                    Icons.sms,
                    'Check-In Contact',
                    '${_contactNameController.text.trim()} (${_contactPhoneController.text.trim()})',
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

