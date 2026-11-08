import 'package:flutter/material.dart';
import '../models/stop.dart';
import '../services/journey_tracking_service.dart';

/// Prominent modal dialog displayed immediately upon confirmed arrival at a stop.
class ArrivalAlertDialog extends StatelessWidget {
  const ArrivalAlertDialog({
    super.key,
    required this.stop,
    required this.trackingService,
    required this.onDismiss,
    required this.onContinueNext,
  });

  final Stop stop;
  final JourneyTrackingService trackingService;
  final VoidCallback onDismiss;
  final VoidCallback onContinueNext;

  static Future<void> show(
    BuildContext context, {
    required Stop stop,
    required JourneyTrackingService trackingService,
    required VoidCallback onDismiss,
    required VoidCallback onContinueNext,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ArrivalAlertDialog(
        stop: stop,
        trackingService: trackingService,
        onDismiss: onDismiss,
        onContinueNext: onContinueNext,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isFinal = stop.isFinalDestination;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: colorScheme.surface,
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withAlpha(50),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_active,
              size: 56,
              color: Colors.amber,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isFinal ? 'Final Destination Reached!' : 'You Have Arrived!',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            stop.name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isFinal
                ? 'You have reached the final stop of your journey.'
                : 'Stop ${stop.order + 1} reached. Prepare to alight or prepare for your connection.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (stop.contacts.isNotEmpty)
            Card(
              color: colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.sms_outlined, color: Colors.green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Check-In Contact: ${stop.contacts.first.contactName}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  trackingService.alarmService.snooze();
                  Navigator.of(context).pop();
                  onDismiss();
                },
                child: const Text('Snooze'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  trackingService.alarmService.dismiss();
                  Navigator.of(context).pop();
                  onContinueNext();
                },
                child: Text(isFinal ? 'Finish Journey' : 'Next Stop'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

