import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/contact_checkin_config.dart';
import '../models/journey.dart';
import '../models/stop.dart';
import '../services/journey_tracking_service.dart';
import '../services/messaging_service.dart';
import 'arrival_alert_dialog.dart';
import 'journey_completion_screen.dart';
import 'widgets/journey_map_view.dart';

/// Redesigned live transit companion cockpit.
///
/// Features an interactive route map, prominent target stop card,
/// live distance countdown, real-time telemetry, and clear transit states.
class ActiveJourneyScreen extends StatefulWidget {
  const ActiveJourneyScreen({
    super.key,
    required this.trackingService,
  });

  final JourneyTrackingService trackingService;

  @override
  State<ActiveJourneyScreen> createState() => _ActiveJourneyScreenState();
}

class _ActiveJourneyScreenState extends State<ActiveJourneyScreen> {
  late TrackingSessionState _state;
  StreamSubscription<TrackingSessionState>? _subscription;
  Timer? _tickerTimer;
  bool _alertModalOpen = false;

  @override
  void initState() {
    super.initState();
    _state = widget.trackingService.currentState;
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _subscription = widget.trackingService.stateStream.listen((newState) {
      if (!mounted) return;
      setState(() {
        _state = newState;
      });

      // Handle transition to arrival alert
      if (newState.state == TrackingState.alertTriggered && !_alertModalOpen) {
        final stop = newState.currentStop ??
            newState.activeJourney?.nextActiveStop ??
            newState.activeJourney?.nextStop;
        if (stop != null) {
          _alertModalOpen = true;
          ArrivalAlertDialog.show(
            context,
            stop: stop,
            trackingService: widget.trackingService,
            onDismiss: () {
              _alertModalOpen = false;
            },
            onContinueNext: () {
              _alertModalOpen = false;
              widget.trackingService.advanceToNextStop();
            },
          );
        }
      }

      // Handle journey completion
      if (newState.state == TrackingState.journeyCompleted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => JourneyCompletionScreen(
              journey: newState.activeJourney ??
                  Journey(
                    id: 'temp',
                    name: 'Journey',
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  ),
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  String _formatTimestamp(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatDistance(double? meters) {
    if (meters == null) return '--';
    if (meters >= 1000) {
      return '${(meters / 1000.0).toStringAsFixed(1)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final journey = _state.activeJourney;
    // Guaranteed fallback: check state, then active stop, then first unreached stop
    final currentStop = _state.currentStop ??
        journey?.nextActiveStop ??
        journey?.nextStop;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          journey?.name ?? 'Live Tracking',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _state.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            ),
            tooltip: _state.isPaused ? 'Resume Journey' : 'Pause Journey',
            onPressed: () {
              if (_state.isPaused) {
                widget.trackingService.resumeTracking();
              } else {
                widget.trackingService.pauseTracking();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
            tooltip: 'Cancel Journey',
            onPressed: () => _confirmCancel(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Live Interactive Map View
              if (journey != null && journey.stops.isNotEmpty) ...[
                JourneyMapView(
                  stops: journey.stops,
                  activeStop: currentStop,
                  userPosition: _state.lastReading != null
                      ? LatLng(
                          _state.lastReading!.latitude,
                          _state.lastReading!.longitude,
                        )
                      : null,
                  height: 220,
                ),
                const SizedBox(height: 16),
              ],

              // 2. Prominent Target Stop Card (No "No active stop" bug!)
              _buildTargetStopCard(theme, colorScheme, currentStop),
              const SizedBox(height: 16),

              // 3. Status Banner
              _buildStatusPill(theme, colorScheme),
              const SizedBox(height: 16),

              // 4. ML Arrival Confidence Card
              _buildConfidenceCard(theme, colorScheme, currentStop),
              const SizedBox(height: 16),

              // 5. GPS Telemetry Info
              _buildTelemetryCard(theme, colorScheme),
              const SizedBox(height: 16),

              // 5b. Safety Check-In Status & Trigger
              _buildCheckInCard(theme, colorScheme, currentStop),
              const SizedBox(height: 20),

              // 5c. Developer Test Mode (Debug Only)
              if (kDebugMode && journey != null && journey.stops.isNotEmpty) ...[
                _buildDeveloperTestCard(theme, colorScheme, journey),
                const SizedBox(height: 20),
              ],

              // 6. Journey Stops Progression
              Text(
                'Journey Progress',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (journey != null)
                _buildStopsList(theme, colorScheme, journey, currentStop),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: (_state.state == TrackingState.alertTriggered ||
                _state.state == TrackingState.arrivalConfirmed ||
                currentStop?.isReached == true)
            ? FilledButton.icon(
                onPressed: () => widget.trackingService.advanceToNextStop(),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(
                  currentStop?.isFinalDestination == true
                      ? 'Finish Journey'
                      : 'Acknowledge & Next Stop',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              )
            : OutlinedButton.icon(
                onPressed: () => _confirmManualArrival(currentStop),
                icon: const Icon(Icons.touch_app_outlined),
                label: const Text('Manual Arrival Override'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
      ),
    );
  }

  void _confirmManualArrival(Stop? stop) {
    if (stop == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Arrival?'),
        content: Text(
          'Confirm that you have arrived at "${stop.name}"? This will trigger your arrival alert and prepare check-in messages immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Not Yet'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.trackingService.confirmArrivalManually();
            },
            child: const Text('Yes, I Have Arrived'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(ThemeData theme, ColorScheme colorScheme) {
    String text;
    Color bg;
    Color fg;
    IconData icon;

    if (_state.isPaused) {
      text = 'JOURNEY PAUSED';
      bg = Colors.amber.shade100;
      fg = Colors.amber.shade900;
      icon = Icons.pause_circle_outline;
    } else if (_state.lastReading == null) {
      text = 'ACQUIRING GPS SIGNAL...';
      bg = Colors.blue.shade100;
      fg = Colors.blue.shade900;
      icon = Icons.gps_not_fixed;
    } else if (_state.lastReading!.accuracyMeters > 50) {
      text = 'GPS ACCURACY WEAK (${_state.lastReading!.accuracyMeters.toStringAsFixed(0)}m)';
      bg = Colors.orange.shade100;
      fg = Colors.orange.shade900;
      icon = Icons.signal_cellular_alt_1_bar;
    } else if (_state.isPotentialArrival) {
      text = 'APPROACHING ARRIVAL ZONE';
      bg = Colors.teal.shade100;
      fg = Colors.teal.shade900;
      icon = Icons.near_me;
    } else {
      text = 'MONITORING GPS • TRACKING ACTIVE';
      bg = Colors.green.shade100;
      fg = Colors.green.shade900;
      icon = Icons.gps_fixed;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetStopCard(
    ThemeData theme,
    ColorScheme colorScheme,
    Stop? stop,
  ) {
    final distanceStr = _formatDistance(_state.distanceToStopMeters);
    final isInside = _state.distanceToStopMeters != null &&
        stop != null &&
        _state.distanceToStopMeters! <= stop.radiusMeters;

    final stopName = stop?.name ?? 'Locating next stop...';
    final radiusStr = stop != null ? '${stop.radiusMeters.toStringAsFixed(0)} m' : '--';

    return Card(
      elevation: 3,
      color: isInside
          ? Colors.green.withAlpha(30)
          : colorScheme.primaryContainer.withAlpha(70),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isInside ? Colors.green : colorScheme.primary,
          width: 2.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  isInside ? Icons.pin_drop : Icons.navigation,
                  color: isInside ? Colors.green : colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  isInside ? 'INSIDE ARRIVAL ZONE' : 'NEXT TARGET STOP',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: isInside ? Colors.green.shade800 : colorScheme.primary,
                  ),
                ),
                const Spacer(),
                if (stop != null)
                  Chip(
                    label: Text(
                      stop.isFinalDestination
                          ? 'Final Destination'
                          : 'Stop ${stop.order + 1}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              stopName,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  distanceStr,
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: isInside ? Colors.green : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'remaining',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.radar, size: 16, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Alert radius: $radiusStr',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 14),
                Icon(
                  stop?.alarmConfig.soundEnabled == true
                      ? Icons.volume_up
                      : Icons.volume_off,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  stop?.alarmConfig.soundEnabled == true ? 'Alarm on' : 'Muted',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfidenceCard(
    ThemeData theme,
    ColorScheme colorScheme,
    Stop? currentStop,
  ) {
    final conf = _state.confidenceScore;
    final percentage = conf != null ? conf.percentage : 0;
    final isHigh = conf?.isHighConfidence ?? false;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: colorScheme.secondary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Arrival Confidence',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Experimental ML Model',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: percentage / 100.0,
                      minHeight: 10,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      color: isHigh ? Colors.green : colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$percentage%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isHigh ? Colors.green : colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              conf != null
                  ? conf.summary
                  : (_state.lastReading == null
                      ? 'Confidence calibrating as GPS readings accumulate...'
                      : 'Evaluating distance, speed, and dwell time towards upcoming stop.'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryCard(ThemeData theme, ColorScheme colorScheme) {
    final reading = _state.lastReading;
    final speedKmh = reading?.speedKmh;
    final accuracy = reading?.accuracyMeters;
    final age = reading?.age();
    final ageStr = age != null
        ? (age.inSeconds < 60 ? '${age.inSeconds}s ago' : '${age.inMinutes}m ago')
        : 'Acquiring fix...';

    final hasFix = reading != null;
    final isAccurate = accuracy != null && accuracy <= 80.0;
    final gpsStatusText = !hasFix
        ? 'Acquiring Satellite Lock'
        : (!isAccurate ? 'Signal Degraded (±${accuracy?.toStringAsFixed(0) ?? '--'}m)' : 'GPS High Accuracy Lock');
    final gpsStatusColor = !hasFix
        ? Colors.amber
        : (!isAccurate ? Colors.orange : Colors.green);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  !hasFix ? Icons.satellite_alt_outlined : Icons.check_circle_outline,
                  size: 16,
                  color: gpsStatusColor,
                ),
                const SizedBox(width: 8),
                Text(
                  gpsStatusText,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: gpsStatusColor,
                  ),
                ),
                const Spacer(),
                if (reading != null)
                  Text(
                    'Fix: ${_formatTimestamp(reading.timestamp)} ($ageStr)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTelemetryItem(
                  theme,
                  Icons.speed,
                  speedKmh != null ? '${speedKmh.toStringAsFixed(0)} km/h' : '--',
                  'Speed',
                ),
                _buildTelemetryItem(
                  theme,
                  Icons.my_location,
                  accuracy != null ? '±${accuracy.toStringAsFixed(1)} m' : '--',
                  'Accuracy',
                ),
                _buildTelemetryItem(
                  theme,
                  Icons.timer_outlined,
                  ageStr,
                  'Fix Freshness',
                ),
                _buildTelemetryItem(
                  theme,
                  Icons.timeline,
                  _state.state.name.toUpperCase(),
                  'State',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckInCard(ThemeData theme, ColorScheme colorScheme, Stop? stop) {
    final status = _state.messageStatus;
    String statusTitle;
    String statusDescription;
    IconData icon;
    Color statusColor;

    switch (status) {
      case MessageDeliveryStatus.notTriggered:
        statusTitle = 'WAITING FOR ARRIVAL';
        statusDescription = 'Safety check-in SMS composer will be prepared when you reach this stop.';
        icon = Icons.hourglass_top_outlined;
        statusColor = colorScheme.onSurfaceVariant;
        break;
      case MessageDeliveryStatus.pending:
        statusTitle = 'DISPATCHING SMS...';
        statusDescription = 'Sending check-in message via cellular carrier radio...';
        icon = Icons.sync_outlined;
        statusColor = Colors.amber;
        break;
      case MessageDeliveryStatus.readyToSend:
        statusTitle = 'CHECK-IN READY';
        statusDescription = 'Arrival verified. Tap below to open Android SMS composer with recipient and message pre-filled.';
        icon = Icons.mark_chat_unread_outlined;
        statusColor = Colors.orange;
        break;
      case MessageDeliveryStatus.composerOpened:
        statusTitle = 'COMPOSER OPENED';
        statusDescription = 'Android SMS app opened with pre-filled check-in text. Send the message or tap to reopen.';
        icon = Icons.send_outlined;
        statusColor = Colors.blue;
        break;
      case MessageDeliveryStatus.sentConfirmed:
        statusTitle = 'SENT CONFIRMED';
        statusDescription = 'Check-in message dispatched.';
        icon = Icons.check_circle_outline;
        statusColor = Colors.green;
        break;
      case MessageDeliveryStatus.failed:
        statusTitle = 'NOTICE / FAILED';
        statusDescription = 'Could not launch SMS composer or invalid phone number. Tap below to retry.';
        icon = Icons.error_outline;
        statusColor = Colors.red;
        break;
      case MessageDeliveryStatus.userCancelled:
        statusTitle = 'CANCELLED / SKIPPED';
        statusDescription = 'Check-in was skipped by passenger.';
        icon = Icons.cancel_outlined;
        statusColor = Colors.grey;
        break;
    }

    return FutureBuilder<List<ContactCheckInConfig>>(
      future: stop != null
          ? widget.trackingService.getEffectiveContactsForStop(stop)
          : Future.value([]),
      builder: (context, snapshot) {
        final contacts = snapshot.data ?? [];

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icon, color: statusColor, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Safety Check-In Status',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: statusColor.withAlpha(80)),
                      ),
                      child: Text(
                        statusTitle,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  statusDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (contacts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Text(
                    'Assigned Emergency Recipients (${contacts.length}):',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...contacts.map((c) {
                    final cleanPhone = c.phoneNumber.trim();
                    final masked = cleanPhone.length > 4
                        ? '••••••${cleanPhone.substring(cleanPhone.length - 4)}'
                        : cleanPhone;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          const Icon(Icons.person_pin_outlined, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${c.contactName} ($masked)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => widget.trackingService
                                .triggerCheckInForCurrentStop(targetContact: c),
                            icon: const Icon(Icons.send_rounded, size: 14),
                            label: Text(
                              status == MessageDeliveryStatus.composerOpened
                                  ? 'Reopen'
                                  : 'Open SMS',
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ] else ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () =>
                        widget.trackingService.triggerCheckInForCurrentStop(),
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: Text(
                      status == MessageDeliveryStatus.composerOpened
                          ? 'Reopen SMS Composer'
                          : 'Open SMS Composer',
                    ),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
                if (status == MessageDeliveryStatus.readyToSend ||
                    status == MessageDeliveryStatus.composerOpened)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => widget.trackingService.cancelCheckIn(),
                      child: const Text('Skip Check-In', style: TextStyle(fontSize: 11)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTelemetryItem(
    ThemeData theme,
    IconData icon,
    String value,
    String label,
  ) {
    return Column(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(height: 6),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildStopsList(
    ThemeData theme,
    ColorScheme colorScheme,
    Journey journey,
    Stop? activeStop,
  ) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: journey.stops.length,
      itemBuilder: (context, index) {
        final stop = journey.stops[index];
        final isReached = stop.isReached;
        final isCurrent = activeStop?.id == stop.id;

        return Card(
          elevation: isCurrent ? 2 : 0,
          color: isCurrent
              ? colorScheme.primaryContainer.withAlpha(50)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isCurrent ? colorScheme.primary : Colors.grey.withAlpha(60),
            ),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isReached
                  ? Colors.green
                  : (isCurrent ? colorScheme.primary : Colors.grey),
              child: Icon(
                isReached
                    ? Icons.check
                    : (isCurrent ? Icons.pin_drop : Icons.place_outlined),
                color: Colors.white,
                size: 18,
              ),
            ),
            title: Text(
              stop.name,
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                decoration: isReached ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: Text(
              isReached
                  ? 'Reached'
                  : (isCurrent
                      ? 'Target Stop (${stop.radiusMeters.toStringAsFixed(0)}m alert zone)'
                      : 'Upcoming'),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (kDebugMode && !isReached)
                  TextButton.icon(
                    onPressed: () => _handleSimulateTestArrival(stop),
                    icon: const Icon(Icons.science_outlined, size: 14, color: Colors.purple),
                    label: const Text('Test', style: TextStyle(fontSize: 11, color: Colors.purple)),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                if (isCurrent)
                  const Chip(
                    label: Text(
                      'ACTIVE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    backgroundColor: Colors.transparent,
                    side: BorderSide(color: Colors.green),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDeveloperTestCard(
    ThemeData theme,
    ColorScheme colorScheme,
    Journey journey,
  ) {
    return Card(
      elevation: 2,
      color: Colors.purple.withAlpha(15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.purple.withAlpha(80), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.science_outlined, color: Colors.purple, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Developer Test Mode',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.purple,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.purple.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.purple.withAlpha(100)),
                  ),
                  child: const Text(
                    'DEBUG ONLY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Simulate arrival events through the real arrival pipeline (alarm chime, vibration, notification & stop-specific SMS check-in) without moving.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ...journey.stops.map((stop) {
              final isReached = stop.isReached;
              final contactCount = stop.contacts.length;
              final label = 'Test Arrival: Stop ${stop.order + 1} (${stop.name})';

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: OutlinedButton.icon(
                  onPressed: isReached
                      ? null
                      : () => _handleSimulateTestArrival(stop),
                  icon: Icon(
                    isReached ? Icons.check : Icons.play_arrow_rounded,
                    size: 18,
                    color: isReached ? Colors.grey : Colors.purple,
                  ),
                  label: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isReached ? Colors.grey : Colors.purple,
                          ),
                        ),
                      ),
                      if (contactCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$contactCount contact${contactCount > 1 ? 's' : ''}',
                            style: const TextStyle(fontSize: 10, color: Colors.green),
                          ),
                        ),
                    ],
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: isReached ? Colors.grey.withAlpha(60) : Colors.purple.withAlpha(120),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSimulateTestArrival(Stop stop) async {
    final success = await widget.trackingService.simulateDeveloperTestArrival(targetStop: stop);
    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stop "${stop.name}" was already alerted or cannot be tested.'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _confirmCancel() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Journey?'),
        content: const Text(
          'Are you sure you want to stop tracking this journey?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Keep Tracking'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(context).pop();
              widget.trackingService.cancelTracking();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel Journey'),
          ),
        ],
      ),
    );
  }
}
