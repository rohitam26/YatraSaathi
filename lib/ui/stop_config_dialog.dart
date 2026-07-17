import 'package:flutter/material.dart';
import '../models/alarm_config.dart';
import '../models/contact_checkin_config.dart';
import '../models/safety_contact.dart';
import '../models/stop.dart';
import '../models/user_profile.dart';
import '../services/alarm_service.dart';
import '../services/geocoding_service.dart';
import 'widgets/map_location_picker.dart';

/// Redesigned consumer-friendly modal for adding or editing a stop.
///
/// Ordinary users can search or tap on an interactive map. Coordinates are
/// captured and stored automatically without requiring manual lat/lon input.
class StopConfigDialog extends StatefulWidget {
  const StopConfigDialog({
    super.key,
    this.existingStop,
    required this.order,
    this.isFinalDestination = false,
    this.defaultProfile,
    this.availableContacts,
  });

  final Stop? existingStop;
  final int order;
  final bool isFinalDestination;
  final UserProfile? defaultProfile;
  final List<SafetyContact>? availableContacts;

  static Future<Stop?> show(
    BuildContext context, {
    Stop? existingStop,
    required int order,
    bool isFinalDestination = false,
    UserProfile? defaultProfile,
    List<SafetyContact>? availableContacts,
  }) {
    return showDialog<Stop>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StopConfigDialog(
        existingStop: existingStop,
        order: order,
        isFinalDestination: isFinalDestination,
        defaultProfile: defaultProfile,
        availableContacts: availableContacts,
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

  // Location fields (internal coordinates, hidden from ordinary view)
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late double _latitude;
  late double _longitude;
  late double _radiusMeters;
  bool _hasLocation = false;

  // Search
  final TextEditingController _searchController = TextEditingController();
  final GeocodingService _geocoding = GeocodingService();
  bool _isSearching = false;
  List<GeocodedPlace> _searchResults = [];

  // Alarm fields
  late bool _soundEnabled;
  late String _selectedSound;
  late bool _vibrationEnabled;
  late int _repeatCount;
  late int _snoozeMinutes;

  // Contact fields
  late bool _checkInEnabled;
  late final TextEditingController _contactNameController;
  late final TextEditingController _contactPhoneController;
  late final TextEditingController _messageController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    final stop = widget.existingStop;
    _nameController = TextEditingController(text: stop?.name ?? '');
    _addressController = TextEditingController(
      text: stop != null
          ? 'Saved coordinates: ${stop.latitude.toStringAsFixed(4)}, ${stop.longitude.toStringAsFixed(4)}'
          : '',
    );
    _latitude = stop?.latitude ?? 13.0827; // Default Chennai
    _longitude = stop?.longitude ?? 80.2707;
    _radiusMeters = stop?.radiusMeters ?? 500.0;
    _hasLocation = stop != null;

    final alarm = stop?.alarmConfig ?? const AlarmConfig();
    _soundEnabled = alarm.soundEnabled;
    _selectedSound = alarm.soundName;
    _vibrationEnabled = alarm.vibrationEnabled;
    _repeatCount = alarm.maxRepeats;
    _snoozeMinutes = alarm.snoozeDurationMinutes;

    final checkIn = (stop?.contacts.isNotEmpty ?? false)
        ? stop!.contacts.first
        : null;
    if (checkIn != null) {
      _checkInEnabled = true;
      _contactNameController = TextEditingController(text: checkIn.contactName);
      _contactPhoneController = TextEditingController(text: checkIn.phoneNumber);
      _messageController = TextEditingController(text: checkIn.customMessage);
    } else if (widget.defaultProfile != null &&
        widget.defaultProfile!.hasDefaultContact) {
      _checkInEnabled = widget.defaultProfile!.autoCheckInOnArrival;
      _contactNameController =
          TextEditingController(text: widget.defaultProfile!.defaultContactName);
      _contactPhoneController = TextEditingController(
          text: widget.defaultProfile!.formattedContactPhone);
      _messageController =
          TextEditingController(text: widget.defaultProfile!.defaultMessage);
    } else {
      _checkInEnabled = false;
      _contactNameController = TextEditingController();
      _contactPhoneController = TextEditingController();
      _messageController = TextEditingController(
        text: 'Hi! I have safely reached my stop. - Sent via YatraSaathi',
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _searchController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _messageController.dispose();
    _geocoding.dispose();
    super.dispose();
  }

  Future<void> _openMapPicker() async {
    final picked = await MapLocationPicker.pickLocation(
      context,
      initialLatitude: _hasLocation ? _latitude : null,
      initialLongitude: _hasLocation ? _longitude : null,
      initialPlaceName: _nameController.text.trim(),
    );

    if (picked != null && mounted) {
      setState(() {
        _latitude = picked.latitude;
        _longitude = picked.longitude;
        _hasLocation = true;
        if (_nameController.text.trim().isEmpty ||
            _nameController.text.startsWith('Stop ')) {
          _nameController.text = picked.name;
        }
        _addressController.text = picked.address;
        _searchResults = [];
        _searchController.clear();
      });
    }
  }

  void _onSearchLocation(String query) async {
    if (query.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearching = true);
    final results = await _geocoding.searchPlaces(query);
    if (mounted) {
      setState(() {
        _isSearching = false;
        _searchResults = results;
      });
    }
  }

  void _selectSearchResult(GeocodedPlace place) {
    FocusScope.of(context).unfocus();
    setState(() {
      _latitude = place.latitude;
      _longitude = place.longitude;
      _hasLocation = true;
      _nameController.text = place.name;
      _addressController.text = place.address;
      _searchResults = [];
      _searchController.clear();
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    if (!_hasLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose a location on the map or search above.'),
          backgroundColor: Colors.orange,
        ),
      );
      _tabController.animateTo(0);
      return;
    }

    final alarmConfig = AlarmConfig(
      soundEnabled: _soundEnabled,
      soundName: _selectedSound,
      vibrationEnabled: _vibrationEnabled,
      maxRepeats: _repeatCount,
      snoozeDurationMinutes: _snoozeMinutes,
    );

    final contacts = <ContactCheckInConfig>[];
    if (_checkInEnabled && _contactPhoneController.text.trim().isNotEmpty) {
      contacts.add(
        ContactCheckInConfig(
          id: 'contact_${DateTime.now().millisecondsSinceEpoch}',
          contactName: _contactNameController.text.trim().isNotEmpty
              ? _contactNameController.text.trim()
              : 'Emergency Contact',
          phoneNumber: _contactPhoneController.text.trim(),
          customMessage: _messageController.text.trim(),
        ),
      );
    }

    final stop = Stop(
      id: widget.existingStop?.id ??
          'stop_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameController.text.trim(),
      latitude: _latitude,
      longitude: _longitude,
      radiusMeters: _radiusMeters,
      order: widget.order,
      isFinalDestination: widget.isFinalDestination,
      alarmConfig: alarmConfig,
      contacts: contacts,
      isReached: widget.existingStop?.isReached ?? false,
      reachedAt: widget.existingStop?.reachedAt,
    );

    Navigator.of(context).pop(stop);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isEditing = widget.existingStop != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 680),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                child: Row(
                  children: [
                    Icon(
                      widget.isFinalDestination
                          ? Icons.flag_rounded
                          : Icons.pin_drop_rounded,
                      color: widget.isFinalDestination
                          ? Colors.deepOrange
                          : colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isEditing
                            ? 'Edit ${widget.existingStop?.name}'
                            : (widget.isFinalDestination
                                ? 'Add Final Destination'
                                : 'Add Stop ${widget.order + 1}'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Tab Bar
              TabBar(
                controller: _tabController,
                labelColor: colorScheme.primary,
                tabs: const [
                  Tab(icon: Icon(Icons.place_outlined), text: 'Location'),
                  Tab(icon: Icon(Icons.alarm_outlined), text: 'Alarm'),
                  Tab(icon: Icon(Icons.sms_outlined), text: 'Check-In'),
                ],
              ),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildLocationTab(theme, colorScheme),
                    _buildAlarmTab(theme, colorScheme),
                    _buildCheckInTab(theme, colorScheme),
                  ],
                ),
              ),

              // Footer Actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: colorScheme.outlineVariant),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.check),
                      label: Text(isEditing ? 'Save Changes' : 'Add Stop'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationTab(ThemeData theme, ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stop Name Field
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Stop Name *',
              hintText: 'e.g. Tambaram Railway Station, Office, Home',
              prefixIcon: const Icon(Icons.label_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Please enter a stop name' : null,
          ),
          const SizedBox(height: 14),

          // Map & Search Controls (No manual lat/long!)
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _openMapPicker,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Choose on Map'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Place Search Input
          TextField(
            controller: _searchController,
            onChanged: _onSearchLocation,
            decoration: InputDecoration(
              labelText: 'Search location or address',
              hintText: 'Type to search OpenStreetMap...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _isSearching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: Padding(
                        padding: EdgeInsets.all(12.0),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          // Search Suggestions Dropdown
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 6),
            Card(
              elevation: 3,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final place = _searchResults[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.pin_drop_outlined, size: 20),
                      title: Text(
                        place.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        place.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _selectSearchResult(place),
                    );
                  },
                ),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Selected Location Card
          Card(
            color: _hasLocation
                ? colorScheme.primaryContainer.withAlpha(50)
                : Colors.orange.withAlpha(20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: _hasLocation ? colorScheme.primary : Colors.orange,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    _hasLocation ? Icons.check_circle : Icons.info_outline,
                    color: _hasLocation ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hasLocation ? 'Location Set' : 'Location Required',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _hasLocation
                              ? (_addressController.text.isNotEmpty
                                  ? _addressController.text
                                  : 'Lat: ${_latitude.toStringAsFixed(4)}, Lon: ${_longitude.toStringAsFixed(4)}')
                              : 'Tap "Choose on Map" or search above to select coordinates.',
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                final latCtrl = TextEditingController(text: _hasLocation ? _latitude.toStringAsFixed(5) : '');
                final lonCtrl = TextEditingController(text: _hasLocation ? _longitude.toStringAsFixed(5) : '');
                final setCoords = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Enter Coordinates Manually'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: latCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Latitude (-90 to +90)', border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: lonCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Longitude (-180 to +180)', border: OutlineInputBorder()),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Set')),
                    ],
                  ),
                );
                if (setCoords == true && mounted) {
                  final lat = double.tryParse(latCtrl.text.trim());
                  final lon = double.tryParse(lonCtrl.text.trim());
                  if (lat != null && lon != null && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
                    setState(() {
                      _latitude = lat;
                      _longitude = lon;
                      _hasLocation = true;
                      _addressController.text = 'Manual coordinates: ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
                    });
                  }
                }
              },
              icon: const Icon(Icons.pin_drop_outlined, size: 16),
              label: const Text('Manual coordinates fallback', style: TextStyle(fontSize: 12)),
            ),
          ),

          const SizedBox(height: 16),

          // Arrival Radius Selector (Friendly Chips!)
          Text(
            'Arrival Alert Distance',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'How far before the stop should YatraSaathi alert you?',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),

          Wrap(
            spacing: 8,
            children: [
              _buildRadiusChip(200, '200 m', 'Walking / Local'),
              _buildRadiusChip(500, '500 m', 'Standard Transit'),
              _buildRadiusChip(1000, '1.0 km', 'Train / Express'),
              _buildRadiusChip(2000, '2.0 km', 'Highway / Long-distance'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRadiusChip(double meters, String label, String subtitle) {
    final isSelected = (_radiusMeters - meters).abs() < 10;
    return ChoiceChip(
      label: Text('$label ($subtitle)'),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _radiusMeters = meters);
        }
      },
    );
  }

  Widget _buildAlarmTab(ThemeData theme, ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            title: const Text('Sound Alarm'),
            subtitle: const Text('Play an audible chime upon arrival'),
            value: _soundEnabled,
            onChanged: (val) => setState(() => _soundEnabled = val),
          ),
          if (_soundEnabled) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedSound,
              decoration: InputDecoration(
                labelText: 'Alarm Sound',
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
                if (v != null) setState(() => _selectedSound = v);
              },
            ),
          ],
          const Divider(height: 24),
          SwitchListTile(
            title: const Text('Tactile Vibration'),
            subtitle: const Text('Vibrate phone upon arrival'),
            value: _vibrationEnabled,
            onChanged: (val) => setState(() => _vibrationEnabled = val),
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _repeatCount,
                  decoration: InputDecoration(
                    labelText: 'Alarm Repeats',
                    prefixIcon: const Icon(Icons.repeat),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: [1, 2, 3, 5, 10]
                      .map((c) => DropdownMenuItem(value: c, child: Text('$c times')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _repeatCount = v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _snoozeMinutes,
                  decoration: InputDecoration(
                    labelText: 'Snooze Time',
                    prefixIcon: const Icon(Icons.snooze),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: [3, 5, 10]
                      .map((m) => DropdownMenuItem(value: m, child: Text('$m mins')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _snoozeMinutes = v);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCheckInTab(ThemeData theme, ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            title: const Text('Safety Check-In Message'),
            subtitle: const Text('Open prefilled SMS to loved one upon arrival'),
            value: _checkInEnabled,
            onChanged: (val) => setState(() => _checkInEnabled = val),
          ),
          if (widget.availableContacts != null && widget.availableContacts!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Pick from Saved Contacts:',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: widget.availableContacts!.map((contact) {
                      return ActionChip(
                        avatar: Icon(
                          contact.isPrimary ? Icons.star : Icons.person_outline,
                          size: 16,
                          color: contact.isPrimary ? Colors.amber[800] : null,
                        ),
                        label: Text('${contact.name} (${contact.relationship})'),
                        onPressed: () {
                          setState(() {
                            _checkInEnabled = true;
                            _contactNameController.text = contact.name;
                            _contactPhoneController.text = contact.formattedPhoneNumber;
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ] else if (widget.defaultProfile?.hasDefaultContact == true) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(Icons.shield, size: 16),
                  label: Text(
                    'Use Safety Profile (${widget.defaultProfile!.defaultContactName})',
                  ),
                  onPressed: () {
                    setState(() {
                      _checkInEnabled = true;
                      _contactNameController.text =
                          widget.defaultProfile!.defaultContactName;
                      _contactPhoneController.text =
                          widget.defaultProfile!.formattedContactPhone;
                      _messageController.text =
                          widget.defaultProfile!.defaultMessage;
                    });
                  },
                ),
              ),
            ),
          ],
          if (_checkInEnabled) ...[
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
                labelText: 'Phone Number *',
                hintText: 'e.g. +91 98765 43210',
                prefixIcon: const Icon(Icons.phone_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (v) {
                if (!_checkInEnabled) return null;
                if (v == null || v.trim().isEmpty) {
                  return 'Please enter a contact phone number';
                }
                final digits = v.replaceAll(RegExp(r'\D'), '');
                if (digits.length < 7) {
                  return 'Please enter a valid phone number';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _messageController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Custom Check-In Message',
                prefixIcon: const Icon(Icons.message_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Live Preview Card
            Card(
              color: colorScheme.surfaceContainerHighest.withAlpha(80),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.visibility_outlined,
                            size: 16, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'SMS Message Preview',
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
                      _messageController.text.trim().isNotEmpty
                          ? _messageController.text.trim()
                          : 'Hi! I have safely reached ${_nameController.text.trim().isNotEmpty ? _nameController.text.trim() : "my stop"}. - Sent via YatraSaathi',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Opens in your default Android SMS app upon arrival.',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
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
