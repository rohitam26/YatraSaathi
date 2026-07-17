import 'package:flutter/material.dart';
import '../models/journey.dart';
import '../models/stop.dart';
import '../services/journey_repository.dart';
import 'stop_config_dialog.dart';

/// Screen for creating or editing a multi-stop journey.
class JourneyPlannerScreen extends StatefulWidget {
  const JourneyPlannerScreen({
    super.key,
    this.existingJourney,
    this.repository,
  });

  final Journey? existingJourney;
  final JourneyRepository? repository;

  @override
  State<JourneyPlannerScreen> createState() => _JourneyPlannerScreenState();
}

class _JourneyPlannerScreenState extends State<JourneyPlannerScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late List<Stop> _stops;
  late final JourneyRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? LocalJourneyRepository();
    _nameController = TextEditingController(
      text: widget.existingJourney?.name ?? '',
    );
    _descController = TextEditingController(
      text: widget.existingJourney?.description ?? '',
    );
    _stops = List<Stop>.from(widget.existingJourney?.stops ?? <Stop>[]);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _showAddStopDialog() async {
    final newStop = await StopConfigDialog.show(
      context,
      order: _stops.length,
      isFinalDestination: _stops.isNotEmpty,
    );

    if (newStop != null) {
      setState(() {
        _stops.add(newStop);
      });
    }
  }

  Future<void> _editStop(int index) async {
    if (index < 0 || index >= _stops.length) return;
    final updatedStop = await StopConfigDialog.show(
      context,
      existingStop: _stops[index],
      order: index,
      isFinalDestination: index == _stops.length - 1 && _stops.length > 1,
    );

    if (updatedStop != null) {
      setState(() {
        _stops[index] = updatedStop;
      });
    }
  }

  void _removeStop(int index) {
    setState(() {
      _stops.removeAt(index);
    });
  }

  void _reorderStops(int oldIndex, int newIndex) {
    setState(() {
      var target = newIndex;
      if (target > oldIndex) {
        target -= 1;
      }
      final item = _stops.removeAt(oldIndex);
      _stops.insert(target, item);
    });
  }

  Future<void> _saveJourney() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final now = DateTime.now();
    final journeyId =
        widget.existingJourney?.id ?? 'journey_${now.millisecondsSinceEpoch}';

    final journey = Journey(
      id: journeyId,
      name: _nameController.text.trim(),
      description:
          _descController.text.trim().isEmpty
              ? null
              : _descController.text.trim(),
      createdAt: widget.existingJourney?.createdAt ?? now,
      updatedAt: now,
      status: widget.existingJourney?.status ?? JourneyStatus.planning,
      stops: _stops,
      activeStopIndex: widget.existingJourney?.activeStopIndex ?? -1,
    );

    await _repo.saveJourney(journey);

    if (mounted) {
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
          widget.existingJourney == null ? 'Create Journey' : 'Edit Journey',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton.icon(
            onPressed: _saveJourney,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Journey Title',
                        hintText: 'e.g. Daily Metro Commute',
                        prefixIcon: Icon(Icons.route_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter a journey title';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descController,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        hintText: 'e.g. Home to Office via Yellow Line',
                        prefixIcon: Icon(Icons.description_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'Stops (${_stops.length})',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _showAddStopDialog,
                      icon: const Icon(Icons.add_location_alt, size: 18),
                      label: const Text('Add Stop'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child:
                    _stops.isEmpty
                        ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_location_outlined,
                                  size: 48,
                                  color: colorScheme.outline,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No stops added yet.',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tap "Add Stop" above to configure intermediate stops and destination.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        : ReorderableListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: _stops.length,
                          // ignore: deprecated_member_use
                          onReorder: _reorderStops,
                          itemBuilder: (context, index) {
                            final stop = _stops[index];
                            final isLast = index == _stops.length - 1;

                            return Card(
                              key: ValueKey(stop.id),
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              child: ListTile(
                                onTap: () => _editStop(index),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      isLast
                                          ? colorScheme.primary
                                          : colorScheme.surfaceContainerHighest,
                                  foregroundColor:
                                      isLast
                                          ? colorScheme.onPrimary
                                          : colorScheme.onSurface,
                                  child: Text('${index + 1}'),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        stop.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (isLast && _stops.length > 1)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'Final',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${stop.latitude.toStringAsFixed(4)}, ${stop.longitude.toStringAsFixed(4)} • Radius: ${stop.radiusMeters.toStringAsFixed(0)}m',
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (stop.alarmConfig.soundEnabled)
                                          Padding(
                                            padding: const EdgeInsets.only(right: 6),
                                            child: Icon(
                                              Icons.volume_up,
                                              size: 15,
                                              color: colorScheme.primary,
                                            ),
                                          ),
                                        if (stop.alarmConfig.vibrationEnabled)
                                          Padding(
                                            padding: const EdgeInsets.only(right: 6),
                                            child: Icon(
                                              Icons.vibration,
                                              size: 15,
                                              color: colorScheme.secondary,
                                            ),
                                          ),
                                        if (stop.contacts.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(right: 6),
                                            child: Icon(
                                              Icons.sms,
                                              size: 15,
                                              color: Colors.green.shade700,
                                            ),
                                          ),
                                        Text(
                                          'Tap to edit',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: colorScheme.outline,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _removeStop(index),
                                  tooltip: 'Remove Stop',
                                ),
                              ),
                            );
                          },
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
