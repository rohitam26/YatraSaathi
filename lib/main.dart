import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/journey.dart';
import 'services/alarm_service.dart';
import 'services/journey_repository.dart';
import 'services/journey_tracking_service.dart';
import 'services/location_service.dart';
import 'services/nearest_station_service.dart';
import 'ui/active_journey_screen.dart';
import 'ui/first_launch_onboarding_screen.dart';
import 'ui/journey_wizard_screen.dart';
import 'ui/permission_guidance_screen.dart';
import 'ui/privacy_info_screen.dart';
import 'ui/safety_contacts_screen.dart';
import 'ui/saved_journeys_screen.dart';
import 'ui/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YatraSaathiApp());
}

/// The root application widget for STOP Vanthachu (formerly YatraSaathi).
typedef StopVanthachuApp = YatraSaathiApp;

class YatraSaathiApp extends StatefulWidget {
  const YatraSaathiApp({
    super.key,
    this.repository,
    this.trackingService,
  });

  final JourneyRepository? repository;
  final JourneyTrackingService? trackingService;

  @override
  State<YatraSaathiApp> createState() => _YatraSaathiAppState();
}

class _YatraSaathiAppState extends State<YatraSaathiApp> {
  bool _isLoading = true;
  bool _hasCompletedOnboarding = true;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final completed =
        prefs.getBool(FirstLaunchOnboardingScreen.prefKeyCompleted) ?? false;
    if (mounted) {
      setState(() {
        _hasCompletedOnboarding = completed;
        _isLoading = false;
      });
    }
  }

  void _onOnboardingComplete() {
    setState(() {
      _hasCompletedOnboarding = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'STOP Vanthachu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.light,
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.dark,
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
      ),
      themeMode: ThemeMode.system,
      home: _isLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (!_hasCompletedOnboarding
              ? FirstLaunchOnboardingScreen(
                  onCompleted: _onOnboardingComplete,
                )
              : HomeScreen(
                  repository: widget.repository,
                  trackingService: widget.trackingService,
                )),
    );
  }
}

/// The home dashboard screen for STOP Vanthachu.
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
  int _currentTabIndex = 0;
  NearestStationResult? _nearestStationResult;
  bool _isLoadingLocation = false;

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
    // Restore active session state in tracking service if one exists
    await _trackingService.restoreActiveSession();
    final journeys = await _repo.getJourneys();
    final active = await _repo.getActiveJourney();
    if (mounted) {
      setState(() {
        _savedJourneys = journeys;
        _activeJourney = active;
        _isLoading = false;
      });
    }
    _refreshNearestStation();
  }

  Future<void> _refreshNearestStation() async {
    if (_isLoadingLocation) return;
    setState(() => _isLoadingLocation = true);
    try {
      final reading = await _trackingService.locationService.getCurrentReading();
      final result = NearestStationService().calculateNearestStation(reading);
      if (mounted) {
        setState(() {
          _nearestStationResult = result;
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _nearestStationResult = NearestStationResult.unavailable(
            reason: 'Location fix unavailable. Please check GPS settings.',
          );
          _isLoadingLocation = false;
        });
      }
    }
  }

  Future<void> _navigateToPlanner([Journey? journey]) async {
    final result = await Navigator.of(context).push<Journey>(
      MaterialPageRoute(
        builder: (context) => JourneyWizardScreen(
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

  Future<void> _resumeActiveJourney() async {
    await _trackingService.resumeTracking();
    await _loadData();
    if (mounted) {
      _openLiveTracking();
    }
  }

  Future<void> _pauseActiveJourney() async {
    await _trackingService.pauseTracking();
    await _loadData();
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

    Widget bodyWidget;
    switch (_currentTabIndex) {
      case 1:
        bodyWidget = SavedJourneysScreen(
          repository: _repo,
          onStartJourney: _startJourney,
        );
        break;
      case 2:
        bodyWidget = SafetyContactsScreen(
          repository: _repo,
        );
        break;
      case 3:
        bodyWidget = SettingsScreen(
          repository: _repo,
        );
        break;
      case 0:
      default:
        bodyWidget = SafeArea(
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
                        // Warm Greeting Header
                        _buildGreetingHeader(theme, colorScheme),
                        const SizedBox(height: 14),

                        // Real-time Station Proximity Card (No false "Near Central" defaults)
                        _buildNearbyStationCard(theme, colorScheme),
                        const SizedBox(height: 16),

                        // Prominent Hero Card to Plan a Journey
                        _buildHeroPlanCard(theme, colorScheme),
                        const SizedBox(height: 20),

                        // Active Journey Status Section (No "No active stop" bug!)
                        _buildActiveJourneyCard(theme, colorScheme),
                        const SizedBox(height: 20),

                        // Quick Actions
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: () => _navigateToPlanner(),
                                icon: const Icon(Icons.add_road),
                                label: const Text('New Journey'),
                                style: FilledButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  setState(() => _currentTabIndex = 1);
                                },
                                icon: const Icon(Icons.folder_open_outlined),
                                label: Text('Saved (${_savedJourneys.length})'),
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
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
        );
        break;
    }

    return Scaffold(
      appBar: _currentTabIndex == 0
          ? AppBar(
              title: const Text(
                'STOP Vanthachu',
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
                    setState(() => _currentTabIndex = 3);
                  },
                ),
              ],
            )
          : null,
      body: bodyWidget,
      floatingActionButton: _currentTabIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => _navigateToPlanner(),
              icon: const Icon(Icons.add),
              label: const Text('Plan Journey'),
              tooltip: 'Create New Journey',
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) {
          setState(() => _currentTabIndex = index);
          if (index == 0) _loadData();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Journeys',
          ),
          NavigationDestination(
            icon: Icon(Icons.contacts_outlined),
            selectedIcon: Icon(Icons.contacts),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildGreetingHeader(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.directions_transit, color: colorScheme.primary, size: 26),
            const SizedBox(width: 8),
            Text(
              'STOP Vanthachu',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Never Miss Your Stop. Travel with Confidence.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildNearbyStationCard(ThemeData theme, ColorScheme colorScheme) {
    final result = _nearestStationResult;
    final isAcquiring = _isLoadingLocation && result == null;

    Color badgeColor;
    IconData icon;
    if (result == null || result.proximityType == StationProximityType.unavailable) {
      badgeColor = Colors.blueGrey;
      icon = Icons.gps_not_fixed;
    } else if (result.proximityType == StationProximityType.atStation) {
      badgeColor = Colors.green;
      icon = Icons.train;
    } else if (result.proximityType == StationProximityType.nearStation) {
      badgeColor = Colors.blue;
      icon = Icons.near_me;
    } else {
      badgeColor = Colors.orange;
      icon = Icons.explore_outlined;
    }

    final title = result?.displayTitle ?? (isAcquiring ? 'Finding your location...' : 'Acquiring GPS fix...');
    final subtitle = result?.displaySubtitle ?? 'Waiting for high-accuracy satellite fix';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: badgeColor.withAlpha(35),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: badgeColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: _isLoadingLocation
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  tooltip: 'Refresh Location',
                  onPressed: _refreshNearestStation,
                ),
              ],
            ),
            if (result?.reading != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(100),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.satellite_alt_outlined, size: 12, color: Colors.blueGrey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Accuracy: ±${result!.reading!.accuracyMeters.toStringAsFixed(0)}m  •  Fix: ${result.reading!.age().inSeconds}s ago',
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeroPlanCard(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 2,
      color: colorScheme.primaryContainer.withAlpha(90),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.primary.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  child: const Icon(Icons.map_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Where are you traveling today?',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Search places or tap on interactive maps',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _navigateToPlanner(),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Plan a Journey'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveJourneyCard(ThemeData theme, ColorScheme colorScheme) {
    final active = _activeJourney;
    final isRunning = active != null && (active.isActive || active.isPaused);
    final isPaused = active?.isPaused ?? false;
    final nextStop = active?.nextActiveStop ?? active?.nextStop;

    final totalStops = active?.totalStops ?? 0;
    final reachedStops = active?.stops.where((s) => s.isReached).length ?? 0;
    final progress = totalStops > 0 ? (reachedStops / totalStops) : 0.0;

    return Card(
      elevation: isRunning ? 3 : 0,
      color: isRunning
          ? (isPaused
              ? Colors.amber.shade50.withAlpha(50)
              : colorScheme.surfaceContainerLow)
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isRunning
              ? (isPaused ? Colors.amber : Colors.green)
              : colorScheme.outlineVariant.withAlpha(120),
          width: isRunning ? 2.0 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isRunning
                      ? (isPaused
                          ? Icons.pause_circle_outline
                          : Icons.navigation_outlined)
                      : Icons.explore_off_outlined,
                  color: isRunning
                      ? (isPaused ? Colors.amber.shade800 : Colors.green)
                      : colorScheme.outline,
                  size: 24,
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
                    color: isRunning
                        ? (isPaused
                            ? Colors.amber.withAlpha(40)
                            : Colors.green.withAlpha(40))
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isRunning ? (isPaused ? 'Paused' : 'Active') : 'Idle',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isRunning
                          ? (isPaused
                              ? Colors.amber.shade900
                              : Colors.green.shade800)
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!isRunning) ...[
              Text(
                'No journey currently being tracked.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Plan a journey or select a saved route to start GPS monitoring.',
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
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.trip_origin, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    active.startLocationName,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward, size: 12, color: Colors.grey),
                  const SizedBox(width: 6),
                  const Icon(Icons.flag, size: 14, color: Colors.deepOrange),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      active.destinationName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Target Stop Callout
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withAlpha(60),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.pin_drop, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'NEXT STOP',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            nextStop?.name ?? 'Locating stop...',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${totalStops - reachedStops} left',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  color: Colors.green,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 14),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _openLiveTracking,
                      icon: const Icon(Icons.radar, size: 18),
                      label: const Text('Live Tracking'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isPaused)
                    IconButton.filledTonal(
                      onPressed: _resumeActiveJourney,
                      icon: const Icon(Icons.play_arrow),
                      tooltip: 'Resume Tracking',
                    )
                  else
                    IconButton.filledTonal(
                      onPressed: _pauseActiveJourney,
                      icon: const Icon(Icons.pause),
                      tooltip: 'Pause Tracking',
                    ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: _cancelActiveJourney,
                    icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
                    tooltip: 'Cancel Journey',
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
    final stops = active?.stops ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Journey Stops',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (stops.isNotEmpty)
              Text(
                '${stops.length} configured',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (stops.isEmpty)
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colorScheme.outlineVariant.withAlpha(120),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
              child: Center(
                child: Text('No upcoming stops configured.'),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: stops.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final stop = stops[index];
              final isReached = stop.isReached;
              final isCurrent = active?.nextStop?.id == stop.id;

              return Card(
                elevation: isCurrent ? 2 : 0,
                color: isCurrent
                    ? colorScheme.primaryContainer.withAlpha(40)
                    : colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isCurrent ? colorScheme.primary : Colors.transparent,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: isReached
                        ? Colors.green
                        : (isCurrent
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest),
                    foregroundColor: isReached || isCurrent
                        ? Colors.white
                        : colorScheme.onSurfaceVariant,
                    child: isReached
                        ? const Icon(Icons.check, size: 14)
                        : Text(
                            '${index + 1}',
                            style: const TextStyle(fontSize: 11),
                          ),
                  ),
                  title: Text(
                    stop.name,
                    style: TextStyle(
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                      decoration: isReached ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  subtitle: Text(
                    'Alert: ${stop.radiusMeters.toStringAsFixed(0)}m radius',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: isCurrent
                      ? const Chip(
                          label: Text(
                            'TARGET',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Saved Journeys',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
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
        const SizedBox(height: 4),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _savedJourneys.take(3).length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final journey = _savedJourneys[index];
            return Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const Icon(Icons.route_outlined),
                title: Text(
                  journey.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('${journey.totalStops} stops configured'),
                trailing: FilledButton.tonal(
                  onPressed: () => _startJourney(journey),
                  child: const Text('Start'),
                ),
                onTap: () => _navigateToPlanner(journey),
              ),
            );
          },
        ),
      ],
    );
  }
}
