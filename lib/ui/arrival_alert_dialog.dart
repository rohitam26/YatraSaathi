import 'package:flutter/material.dart';
import '../models/contact_checkin_config.dart';
import '../models/stop.dart';
import '../services/journey_tracking_service.dart';
import '../services/messaging_service.dart';

/// Prominent modal dialog displayed immediately upon confirmed arrival at a stop.
class ArrivalAlertDialog extends StatefulWidget {
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
  State<ArrivalAlertDialog> createState() => _ArrivalAlertDialogState();
}

class _ArrivalAlertDialogState extends State<ArrivalAlertDialog> {
  List<ContactCheckInConfig> _contacts = [];
  final Set<String> _openedContactIds = <String>{};
  bool _isLoadingContacts = true;

  @override
  void initState() {
    super.initState();
    _loadEffectiveContacts();
  }

  Future<void> _loadEffectiveContacts() async {
    final contacts = await widget.trackingService.getEffectiveContactsForStop(widget.stop);
    if (mounted) {
      setState(() {
        _contacts = contacts;
        _isLoadingContacts = false;
      });
    }
  }

  Future<void> _handleOpenComposer(ContactCheckInConfig contact) async {
    final status = await widget.trackingService.triggerCheckInForCurrentStop(
      targetContact: contact,
    );
    if (mounted && status == MessageDeliveryStatus.composerOpened) {
      setState(() {
        _openedContactIds.add(contact.id);
      });
    }
  }

  String _maskPhone(String phone) {
    final clean = phone.trim();
    if (clean.length <= 4) return clean;
    final last4 = clean.substring(clean.length - 4);
    return '••••••$last4';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isFinal = widget.stop.isFinalDestination;
    final isTestMode = widget.trackingService.currentState.arrivalResult?.isTestMode == true ||
        widget.trackingService.currentState.arrivalResult?.event?.isTestMode == true;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: colorScheme.surface,
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isTestMode)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.purple.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple, width: 1.5),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.science_outlined, size: 16, color: Colors.purple),
                    SizedBox(width: 6),
                    Text(
                      'TEST MODE — SIMULATED ARRIVAL',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isTestMode ? Colors.purple.withAlpha(30) : Colors.amber.withAlpha(50),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_active,
                size: 56,
                color: isTestMode ? Colors.purple : Colors.amber,
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
              widget.stop.name,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isFinal
                  ? 'You have reached the final stop of your journey.'
                  : 'Stop ${widget.stop.order + 1} reached. Prepare to alight or prepare for your connection.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (!_isLoadingContacts && _contacts.isNotEmpty) ...[
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 18, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    'Safety Check-In (${_contacts.length} Contact${_contacts.length > 1 ? 's' : ''})',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ..._contacts.map((contact) {
                final isOpened = _openedContactIds.contains(contact.id);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isOpened ? Icons.check_circle_outline : Icons.sms_outlined,
                              color: isOpened ? Colors.blue : Colors.green,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${contact.contactName} (${_maskPhone(contact.phoneNumber)})',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (isOpened)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withAlpha(25),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Composer Opened',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          contact.customMessage,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _handleOpenComposer(contact),
                          icon: const Icon(Icons.send_rounded, size: 14),
                          label: Text(isOpened ? 'Reopen SMS Composer' : 'Open SMS Composer'),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  widget.trackingService.alarmService.snooze();
                  Navigator.of(context).pop();
                  widget.onDismiss();
                },
                child: const Text('Snooze'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  widget.trackingService.alarmService.dismiss();
                  Navigator.of(context).pop();
                  widget.onContinueNext();
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
