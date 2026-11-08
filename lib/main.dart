import 'package:flutter/material.dart';
import 'models/journey.dart';
import 'services/alarm_service.dart';
import 'services/journey_repository.dart';
import 'services/journey_tracking_service.dart';
import 'services/location_service.dart';
import 'ui/active_journey_screen.dart';
import 'ui/journey_planner_screen.dart';
import 'ui/permission_guidance_screen.dart';
import 'ui/privacy_info_screen.dart';
import 'ui/saved_journeys_screen.dart';
import 'ui/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YatraSaathiApp());
}

/// The root application widget for YatraSaathi.
class YatraSaathiApp extends StatelessWidget {
  const YatraSaathiApp({
    super.key,
    this.repository,
    this.trackingService,
  });

  final JourneyRepository? repository;
  final JourneyTrackingService? trackingService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YatraSaathi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: HomeScreen(
        repository: repository,
        trackingService: trackingService,
      ),
    );
  }
}

/// The home dashboard screen for YatraSaathi.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.repository,
    this.trackingService,
  });

  final JourneyRepository? repository;
  final JourneyTrackingService? trackingService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final JourneyRepository _repo;
  late final JourneyTrackingService _trackingService;
  Journey? _activeJourney;
  List<Journey> _savedJourneys = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? LocalJourneyRepository();
    _trackingService = widget.trackingService ??
        JourneyTrackingService(
          repository: _repo,
          locationService: LocationService(),
          alarmService: AlarmService(),
        );
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final journeys = await _repo.getJourneys();
    final active = await _repo.getActiveJourney();
    if (mounted) {
      setState(() {
        _savedJourneys = journeys;
        _activeJourney = active;
        _isLoading = false;
      });
    }
  }

  Future<void> _navigateToPlanner([Journey? journey]) async {
    final result = await Navigator.of(context).push<Journey>(
      MaterialPageRoute(
        builder: (context) => JourneyPlannerScreen(
          existingJourney: journey,
          repository: _repo,
        ),
      ),
    );

    if (result != null) {
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Journey "${result.name}" saved with ${result.totalStops} stops.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _startJourney(Journey journey) async {
    await _trackingService.startTracking(journey);
    await _loadData();

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ActiveJourneyScreen(
            trackingService: _trackingService,
          ),
        ),
      ).then((_) => _loadData());
    }
  }

  Future<void> _cancelActiveJourney() async {
    await _trackingService.cancelTracking();
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Active journey cancelled.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _openLiveTracking() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ActiveJourneyScreen(
          trackingService: _trackingService,
        ),
      ),
    ).then((_) => _loadData());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'YatraSaathi',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainerHighest,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Permissions Guide',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const PermissionGuidanceScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Privacy Info',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const PrivacyInfoScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(repository: _repo),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 20.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Active Journey Status Section
                      _buildActiveJourneyCard(theme, colorScheme),
                      const SizedBox(height: 20),

                      // Quick Actions
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _navigateToPlanner(),
                              icon: const Icon(Icons.add_road),
                              label: const Text('Create Journey'),
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => SavedJourneysScreen(
                                      repository: _repo,
                                      onStartJourney: _startJourney,
                                    ),
                                  ),
                                ).then((_) => _loadData());
                              },
                              icon: const Icon(Icons.folder_open_outlined),
                              label: const Text('All Journeys'),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Upcoming Stops Section
                      _buildUpcomingStopsSection(theme, colorScheme),
                      const SizedBox(height: 24),

                      // Saved Journeys list if available
                      if (_savedJourneys.isNotEmpty)
                        _buildSavedJourneysSection(theme, colorScheme),
                    ],
                  ),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToPlanner(),
        icon: const Icon(Icons.add),
        label: const Text('New Journey'),
        tooltip: 'Create Journey',
      ),
    );
  }

  Widget _buildActiveJourneyCard(ThemeData theme, ColorScheme colorScheme) {
    final active = _activeJourney;
    final isActive = active != null && active.isActive;
    final nextStop = active?.nextActiveStop;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(120)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.navigation_outlined,
                  color: isActive ? Colors.green : colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'Active Journey',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.green.withAlpha(40)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isActive ? 'Active' : 'Inactive',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isActive
                          ? Colors.green.shade800
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!isActive) ...[
              Text(
                'No active journey in progress.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'GPS arrival tracking is currently idle.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
                ),
              ),
            ] else ...[
              Text(
                active.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                nextStop != null
                    ? 'Target stop: ${nextStop.name} (Stop ${nextStop.order + 1}/${active.totalStops})'
                    : 'All stops reached.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _openLiveTracking,
                      icon: const Icon(Icons.radar, size: 18),
                      label: const Text('Live Tracking'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _cancelActiveJourney,
                    icon: const Icon(
                      Icons.stop_circle_outlined,
                      color: Colors.red,
                      size: 18,
                    ),
                    label: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingStopsSection(ThemeData theme, ColorScheme colorScheme) {
    final active = _activeJourney;
    final stops = active?.remainingStops ?? <dynamic>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.place_outlined, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Upcoming Stops',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (stops.isEmpty)
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colorScheme.outlineVariant.withAlpha(120)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 36.0,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: colorScheme.primaryContainer,
                      child: Icon(
                        Icons.map_outlined,
                        size: 32,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Stops Planned',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Plan a journey with multi-stop arrival alarms and automatic check-in messages.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: stops.length,
            itemBuilder: (context, index) {
              final stop = stops[index];
              final isCurrent = index == 0;

              return Card(
                key: ValueKey(stop.id),
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isCurrent
                        ? colorScheme.primary
                        : colorScheme.outlineVariant.withAlpha(80),
                    width: isCurrent ? 1.5 : 1.0,
                  ),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isCurrent
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    foregroundColor: isCurrent
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
                    child: Text('${stop.order + 1}'),
                  ),
                  title: Text(
                    stop.name,
                    style: TextStyle(
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    'Radius: ${stop.radiusMeters.toStringAsFixed(0)}m ${stop.isFinalDestination ? "• Final Destination" : ""}',
                  ),
                  trailing: isCurrent
                      ? Chip(
                          label: const Text('Target'),
                          labelStyle: TextStyle(
                            fontSize: 11,
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                          backgroundColor: colorScheme.primaryContainer,
                          padding: EdgeInsets.zero,
                        )
                      : null,
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildSavedJourneysSection(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.route_outlined, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Saved Journeys (${_savedJourneys.length})',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => SavedJourneysScreen(
                      repository: _repo,
                      onStartJourney: _startJourney,
                    ),
                  ),
                ).then((_) => _loadData());
              },
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _savedJourneys.length > 3 ? 3 : _savedJourneys.length,
          itemBuilder: (context, index) {
            final j = _savedJourneys[index];
            final isThisActive = j.id == _activeJourney?.id && j.isActive;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  j.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${j.totalStops} stops • Status: ${j.status.name}',
                ),
                trailing: isThisActive
                    ? const Chip(
                        label: Text('Active'),
                        backgroundColor: Colors.greenAccent,
                      )
                    : TextButton(
                        onPressed: () => _startJourney(j),
                        child: const Text('Start'),
                      ),
                onTap: () => _navigateToPlanner(j),
              ),
            );
          },
        ),
      ],
    );
  }
}
