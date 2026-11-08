import 'package:flutter/material.dart';
import '../models/journey.dart';
import '../services/journey_repository.dart';
import 'journey_planner_screen.dart';

/// Screen displaying all saved journeys with search, filter, edit,
/// direct start, and deletion capabilities.
class SavedJourneysScreen extends StatefulWidget {
  const SavedJourneysScreen({
    super.key,
    required this.repository,
    this.onStartJourney,
  });

  final JourneyRepository repository;
  final ValueChanged<Journey>? onStartJourney;

  @override
  State<SavedJourneysScreen> createState() => _SavedJourneysScreenState();
}

class _SavedJourneysScreenState extends State<SavedJourneysScreen> {
  List<Journey> _journeys = [];
  List<Journey> _filteredJourneys = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadJourneys();
    _searchController.addListener(_filter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadJourneys() async {
    setState(() => _isLoading = true);
    final list = await widget.repository.getJourneys();
    if (mounted) {
      setState(() {
        _journeys = list;
        _filter();
        _isLoading = false;
      });
    }
  }

  void _filter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredJourneys = List.from(_journeys);
      } else {
        _filteredJourneys = _journeys.where((j) {
          return j.name.toLowerCase().contains(query) ||
              (j.description?.toLowerCase().contains(query) ?? false);
        }).toList();
      }
    });
  }

  Future<void> _deleteJourney(Journey journey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Journey?'),
        content: Text('Are you sure you want to delete "${journey.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.repository.deleteJourney(journey.id);
      await _loadJourneys();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${journey.name}".')),
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
          'Saved Journeys',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SearchBar(
                controller: _searchController,
                hintText: 'Search journeys...',
                leading: const Icon(Icons.search),
                trailing: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _searchController.clear(),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredJourneys.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.route_outlined,
                                size: 56,
                                color: colorScheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchController.text.isEmpty
                                    ? 'No saved journeys yet.'
                                    : 'No matching journeys found.',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Plan a journey with multi-stop arrival alarms.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: _filteredJourneys.length,
                          itemBuilder: (context, index) {
                            final j = _filteredJourneys[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color:
                                      colorScheme.outlineVariant.withAlpha(80),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            j.name,
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colorScheme
                                                .surfaceContainerHighest,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            j.status.name.toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (j.description != null &&
                                        j.description!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        j.description!,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    Text(
                                      '${j.totalStops} stops • Created ${j.createdAt.day}/${j.createdAt.month}/${j.createdAt.year}',
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: colorScheme.outline,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.red,
                                          ),
                                          onPressed: () => _deleteJourney(j),
                                          tooltip: 'Delete',
                                        ),
                                        TextButton.icon(
                                          onPressed: () async {
                                            await Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    JourneyPlannerScreen(
                                                  existingJourney: j,
                                                  repository: widget.repository,
                                                ),
                                              ),
                                            );
                                            _loadJourneys();
                                          },
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 18,
                                          ),
                                          label: const Text('Edit'),
                                        ),
                                        const SizedBox(width: 8),
                                        FilledButton.icon(
                                          onPressed: () {
                                            widget.onStartJourney?.call(j);
                                            Navigator.of(context).pop();
                                          },
                                          icon: const Icon(
                                            Icons.play_arrow,
                                            size: 18,
                                          ),
                                          label: const Text('Start'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => JourneyPlannerScreen(
                repository: widget.repository,
              ),
            ),
          );
          _loadJourneys();
        },
        icon: const Icon(Icons.add),
        label: const Text('New Journey'),
      ),
    );
  }
}
