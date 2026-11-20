import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../models/contact_checkin_config.dart';
import '../models/journey.dart';
import '../models/stop.dart';
import '../services/eta_calculator.dart';
import '../services/journey_tracking_service.dart';
import '../services/messaging_service.dart';
import '../services/nearest_station_service.dart';
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

    if (_state.isMissedStop) {
      text = 'MISSED STOP WARNING';
      bg = Colors.red.shade100;
      fg = Colors.red.shade900;
      icon = Icons.warning_amber_rounded;
    } else if (_state.isPaused) {
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
            if (_state.estimatedDurationRemaining != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule, size: 14, color: colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Est. Arrival: ${EtaCalculator.formatEta(_state.estimatedDurationRemaining)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_state.lastReading?.isDeadReckoning == true) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tune, size: 12, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      'Tunnel Dead Reckoning Projection',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.bold,
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
      case MessageDeliveryStatus.whatsAppOpened:
        statusTitle = 'WHATSAPP OPENED';
        statusDescription = 'WhatsApp chat opened with prefilled alert message.';
        icon = Icons.chat_bubble_outline;
        statusColor = Colors.teal;
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
                if (_state.escalationCountdownSeconds != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withAlpha(80)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_outlined, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Auto-Escalation Countdown: ${_state.escalationCountdownSeconds}s\nIf unacknowledged, SOS alert will be sent with live coordinates.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: Colors.red.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => _showEmergencySosSheet(stop),
                  icon: const Icon(Icons.emergency_share, size: 16),
                  label: const Text('EMERGENCY SOS: Send Location Now'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
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

  void _showEmergencySosSheet(Stop? currentStop) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EmergencySosSheet(
        trackingService: widget.trackingService,
        currentStop: currentStop,
      ),
    );
  }
}

/// Interactive modal sheet managing the Emergency SOS countdown,
/// automatic transmission, status confirmation, and WhatsApp dispatch.
class _EmergencySosSheet extends StatefulWidget {
  const _EmergencySosSheet({
    required this.trackingService,
    this.currentStop,
  });

  final JourneyTrackingService trackingService;
  final Stop? currentStop;

  @override
  State<_EmergencySosSheet> createState() => _EmergencySosSheetState();
}

class _EmergencySosSheetState extends State<_EmergencySosSheet> {
  int _countdown = 5;
  Timer? _countdownTimer;
  bool _isCountingDown = true;
  bool _isDispatching = false;
  MessageDeliveryStatus? _resultStatus;
  String _formattedMessage = '';
  String _contactName = '';
  String _contactPhone = '';
  bool _isDirectSms = false;

  @override
  void initState() {
    super.initState();
    _loadSosDetailsAndStartCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSosDetailsAndStartCountdown() async {
    final repo = widget.trackingService.repository;
    final profile = await repo.getUserProfile();
    final reading = widget.trackingService.lastReading;

    final effectiveContacts = widget.currentStop != null
        ? await widget.trackingService.getEffectiveContactsForStop(widget.currentStop!)
        : <ContactCheckInConfig>[];

    ContactCheckInConfig? target;
    if (effectiveContacts.isNotEmpty) {
      target = effectiveContacts.first;
    } else {
      target = profile.toDefaultContactConfig();
    }

    String? nearestLandmark;
    if (reading != null) {
      final stationResult = NearestStationService().calculateNearestStation(reading);
      if (stationResult.isNearby && stationResult.nearestStation != null) {
        nearestLandmark = '${stationResult.nearestStation!.name} (${stationResult.formattedDistance} away)';
      }
    }
    nearestLandmark ??= widget.currentStop?.name;

    final msg = profile.formatEmergencySosMessage(
      latitude: reading?.latitude,
      longitude: reading?.longitude,
      accuracyMeters: reading?.accuracyMeters,
      sampleAge: reading?.age(),
      nearestLandmark: nearestLandmark,
      timestamp: reading?.timestamp ?? DateTime.now(),
    );

    if (mounted) {
      setState(() {
        _formattedMessage = msg;
        _contactName = target?.contactName ?? profile.defaultContactName;
        _contactPhone = target?.phoneNumber ?? profile.defaultContactPhone;
        _isDirectSms = profile.isDirectSmsActive;
      });

      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_countdown > 1) {
          setState(() => _countdown--);
        } else {
          timer.cancel();
          setState(() {
            _countdown = 0;
            _isCountingDown = false;
          });
          _executeDispatch();
        }
      });
    }
  }

  Future<void> _executeDispatch() async {
    if (_isDispatching) return;
    setState(() {
      _isCountingDown = false;
      _isDispatching = true;
    });

    final status = await widget.trackingService.triggerDirectEmergencySos();
    if (mounted) {
      setState(() {
        _isDispatching = false;
        _resultStatus = status;
      });
    }
  }

  void _cancelSos() {
    _countdownTimer?.cancel();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Emergency SOS cancelled. No message was sent.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _sendViaWhatsApp() async {
    if (_contactPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No emergency contact phone number configured.')),
      );
      return;
    }

    final status = await widget.trackingService.messagingService.sendWhatsAppMessage(
      phoneNumber: _contactPhone,
      message: _formattedMessage,
    );

    if (mounted) {
      if (status == MessageDeliveryStatus.whatsAppOpened) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opening WhatsApp with emergency coordinates...'),
            backgroundColor: Colors.teal,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open WhatsApp. Ensure WhatsApp is installed on device.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top grab handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Banner
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.emergency, color: Colors.red.shade800, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EMERGENCY SOS ALERT',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade800,
                        ),
                      ),
                      Text(
                        _isCountingDown
                            ? 'Safety dispatch countdown active'
                            : (_isDispatching ? 'Transmitting coordinates...' : 'Alert Status Summary'),
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                if (!_isCountingDown && !_isDispatching)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // 1. COUNTDOWN STATE
            if (_isCountingDown) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.shade200, width: 1.5),
                ),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CircularProgressIndicator(
                            value: _countdown / 5.0,
                            strokeWidth: 6,
                            color: Colors.red.shade700,
                            backgroundColor: Colors.red.shade100,
                          ),
                        ),
                        Text(
                          '$_countdown',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Dispatching SOS in $_countdown seconds...',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'To: ${_contactName.isNotEmpty ? _contactName : "Emergency Contact"} (${_contactPhone.isNotEmpty ? _contactPhone : "Configured Number"})',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isDirectSms
                          ? 'Method: Direct Cellular SMS (Background)'
                          : 'Method: Native Android SMS Composer',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _isDirectSms ? Colors.green.shade800 : Colors.blue.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _cancelSos,
                      icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                      label: const Text('Cancel Alert', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        _countdownTimer?.cancel();
                        _executeDispatch();
                      },
                      icon: const Icon(Icons.send),
                      label: const Text('Send Immediately'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // 2. DISPATCHING STATE
            if (_isDispatching) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Colors.red),
                    SizedBox(height: 16),
                    Text(
                      'Dispatching Emergency Coordinates...',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Connecting to cellular radio and formatting satellite fix...',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],

            // 3. POST-DISPATCH CONFIRMATION STATE
            if (!_isCountingDown && !_isDispatching && _resultStatus != null) ...[
              _buildResultBanner(theme, colorScheme),
              const SizedBox(height: 14),

              // Contact detail
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(120),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_pin, size: 20, color: Colors.blueGrey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Recipient: ${_contactName.isNotEmpty ? _contactName : "Safety Contact"} ($_contactPhone)',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Formatted message preview box
              Text(
                'Exact Dispatched Content:',
                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 140),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _formattedMessage,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.grey.shade900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Copy message action
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _formattedMessage));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Emergency message copied to clipboard.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('Copy Message Text', style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(height: 10),

              // Action buttons: WhatsApp + Resend + Close
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _sendViaWhatsApp,
                      icon: const Icon(Icons.chat, size: 18),
                      label: const Text('Send via WhatsApp'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  if (_resultStatus == MessageDeliveryStatus.failed) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Retry Dispatch',
                      onPressed: _executeDispatch,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Close'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultBanner(ThemeData theme, ColorScheme colorScheme) {
    Color bg;
    Color fg;
    IconData icon;
    String title;
    String description;

    switch (_resultStatus) {
      case MessageDeliveryStatus.sentConfirmed:
        bg = Colors.green.shade50;
        fg = Colors.green.shade900;
        icon = Icons.check_circle;
        title = 'AUTOMATIC SMS SENT CONFIRMED';
        description =
            'Cellular carrier radio confirmed direct dispatch to your safety contact.';
        break;
      case MessageDeliveryStatus.composerOpened:
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade900;
        icon = Icons.send_outlined;
        title = 'SMS COMPOSER OPENED';
        description =
            'Android SMS app opened with pre-filled coordinates. Please tap Send in your SMS app to complete delivery.';
        break;
      case MessageDeliveryStatus.whatsAppOpened:
        bg = Colors.teal.shade50;
        fg = Colors.teal.shade900;
        icon = Icons.chat_bubble;
        title = 'WHATSAPP OPENED';
        description = 'Emergency message loaded into WhatsApp chat.';
        break;
      case MessageDeliveryStatus.failed:
      default:
        bg = Colors.red.shade50;
        fg = Colors.red.shade900;
        icon = Icons.error_outline;
        title = 'DISPATCH NOTICE / FAILED';
        description =
            'Could not transmit automatically or open SMS composer. Please check SIM readiness, network, or send via WhatsApp.';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: fg,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: fg.withAlpha(220),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

