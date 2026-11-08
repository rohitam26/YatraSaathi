import 'dart:async';
import 'package:flutter/material.dart';
import '../models/journey.dart';
import '../services/journey_tracking_service.dart';
import 'arrival_alert_dialog.dart';
import 'journey_completion_screen.dart';

/// Screen displaying real-time GPS telemetry, arrival distance countdown,
/// ML arrival confidence gauge, and journey controls during active transit.
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
  StreamSubscription<TrackingSessionState>? _subscription;
  late TrackingSessionState _state;
  bool _alertModalOpen = false;

  @override
  void initState() {
    super.initState();
    _state = widget.trackingService.currentState;
    _subscription = widget.trackingService.stateStream.listen((newState) {
      if (!mounted) return;
      setState(() {
        _state = newState;
      });

      // Handle transition to alert
      if (newState.state == TrackingState.alertTriggered && !_alertModalOpen) {
        final stop = newState.currentStop;
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

      // Handle completion
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
    _subscription?.cancel();
    super.dispose();
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
    final currentStop = _state.currentStop;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          journey?.name ?? 'Active Tracking',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _state.isPaused ? Icons.play_arrow : Icons.pause,
            ),
            tooltip: _state.isPaused ? 'Resume' : 'Pause',
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
              // Target Stop Card
              _buildTargetStopCard(theme, colorScheme, currentStop),
              const SizedBox(height: 16),

              // ML Arrival Confidence Card
              _buildConfidenceCard(theme, colorScheme),
              const SizedBox(height: 16),

              // GPS Telemetry Info
              _buildTelemetryCard(theme, colorScheme),
              const SizedBox(height: 20),

              // Journey Stops Progression
              Text(
                'Journey Stops',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (journey != null)
                _buildStopsList(theme, colorScheme, journey),
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
        child: FilledButton.icon(
          onPressed: () => widget.trackingService.advanceToNextStop(),
          icon: const Icon(Icons.check_circle_outline),
          label: Text(
            currentStop?.isFinalDestination == true
                ? 'Finish Journey'
                : 'Acknowledge & Next Stop',
          ),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTargetStopCard(
    ThemeData theme,
    ColorScheme colorScheme,
    dynamic stop,
  ) {
    final distanceStr = _formatDistance(_state.distanceToStopMeters);
    final isInside = _state.distanceToStopMeters != null &&
        stop != null &&
        _state.distanceToStopMeters! <= stop.radiusMeters;

    return Card(
      elevation: 2,
      color: isInside
          ? Colors.green.withAlpha(30)
          : colorScheme.primaryContainer.withAlpha(80),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isInside ? Colors.green : colorScheme.primary,
          width: 1.5,
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
                  isInside ? 'INSIDE ARRIVAL ZONE' : 'TARGET STOP',
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
                          ? 'Final'
                          : 'Stop ${stop.order + 1}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              stop?.name ?? 'No active stop',
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
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Arrival radius: ${stop?.radiusMeters.toStringAsFixed(0) ?? 500}m',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfidenceCard(ThemeData theme, ColorScheme colorScheme) {
    final conf = _state.confidenceScore;
    final percentage = conf?.percentage ?? 0;
    final isHigh = conf?.isHighConfidence ?? false;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(100)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.psychology_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Arrival Confidence (ML)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Experimental',
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
                      color: isHigh ? Colors.green : colorScheme.primary,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$percentage%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isHigh ? Colors.green : colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              conf?.summary ?? _state.statusMessage,
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
    final accuracyStr = reading != null
        ? '±${reading.accuracyMeters.toStringAsFixed(1)}m'
        : 'Acquiring GPS...';
    final speedStr = reading?.speedMps != null
        ? '${(reading!.speedMps! * 3.6).toStringAsFixed(1)} km/h'
        : '--';

    return Row(
      children: [
        Expanded(
          child: Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant.withAlpha(80)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.gps_fixed, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text('GPS Accuracy', style: theme.textTheme.labelSmall),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    accuracyStr,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant.withAlpha(80)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.speed, size: 16, color: colorScheme.secondary),
                      const SizedBox(width: 6),
                      Text('Speed', style: theme.textTheme.labelSmall),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    speedStr,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStopsList(
    ThemeData theme,
    ColorScheme colorScheme,
    Journey journey,
  ) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: journey.stops.length,
      itemBuilder: (context, index) {
        final stop = journey.stops[index];
        final isCurrent = stop.id == _state.currentStop?.id;
        final isPassed = stop.isReached;

        Color badgeColor = colorScheme.surfaceContainerHighest;
        Color textColor = colorScheme.onSurface;
        Widget? trailing;

        if (isPassed) {
          badgeColor = Colors.green.withAlpha(40);
          textColor = Colors.green.shade800;
          trailing = const Icon(Icons.check_circle, color: Colors.green);
        } else if (isCurrent) {
          badgeColor = colorScheme.primary;
          textColor = colorScheme.onPrimary;
          trailing = Chip(
            label: const Text('Target'),
            backgroundColor: colorScheme.primaryContainer,
            labelStyle: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: colorScheme.onPrimaryContainer,
            ),
            padding: EdgeInsets.zero,
          );
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isCurrent
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withAlpha(60),
              width: isCurrent ? 1.5 : 1.0,
            ),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: badgeColor,
              foregroundColor: textColor,
              child: isPassed
                  ? const Icon(Icons.check, size: 18)
                  : Text('${index + 1}'),
            ),
            title: Text(
              stop.name,
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                decoration: isPassed ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: Text(
              'Radius: ${stop.radiusMeters.toStringAsFixed(0)}m ${stop.isFinalDestination ? "• Final" : ""}',
            ),
            trailing: trailing,
          ),
        );
      },
    );
  }

  void _confirmCancel() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Active Journey?'),
        content: const Text(
          'Background GPS tracking will stop and alarms will be silenced.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Continue Tracking'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(ctx).pop();
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

