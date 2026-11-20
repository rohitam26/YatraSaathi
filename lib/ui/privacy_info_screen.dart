import 'package:flutter/material.dart';

/// Screen explaining STOP Vanthachu's 100% local-first privacy architecture,
/// data retention policy, and transparent SMS messaging handling.
class PrivacyInfoScreen extends StatelessWidget {
  const PrivacyInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Privacy & Security',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.green.withAlpha(25),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.green.withAlpha(80)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 36, color: Colors.green),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      '100% Offline & Local-First. Your transit history never leaves your device.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildSection(
            theme: theme,
            icon: Icons.cloud_off_outlined,
            title: 'Zero Remote Cloud Storage',
            body:
                'STOP Vanthachu requires no user account, email login, or external server. All saved journeys, stop coordinates, and alarm preferences are serialized exclusively in private application storage on your phone.',
          ),
          _buildSection(
            theme: theme,
            icon: Icons.location_off_outlined,
            title: 'Local Real-Time GPS Processing',
            body:
                'Location coordinates acquired from your GPS hardware are evaluated strictly in real-time on your processor using the Haversine distance algorithm and on-device ML model. Telemetry coordinates are discarded immediately after evaluation.',
          ),
          _buildSection(
            theme: theme,
            icon: Icons.sms_outlined,
            title: 'Transparent Android SMS Compliance',
            body:
                'In strict compliance with Google Play Developer policies, STOP Vanthachu never attempts to silently send background SMS messages without your knowledge. When arrival check-in is triggered, the native Android SMS composer opens with your preconfigured message, leaving final delivery confirmation in your control.',
          ),
          _buildSection(
            theme: theme,
            icon: Icons.delete_outline,
            title: 'User-Controlled Data Deletion',
            body:
                'You maintain total ownership of your travel data. You can delete individual journeys at any time or wipe all stored history with a single tap in the Settings menu.',
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
