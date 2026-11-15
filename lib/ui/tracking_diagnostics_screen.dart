import 'dart:async';
import 'package:flutter/material.dart';
import '../models/gps_reading.dart';
import '../services/location_engine.dart';

/// Screen displaying authoritative live GPS tracking diagnostics, hardware status,
/// fix accuracy, update frequencies, and troubleshooting actions.
class TrackingDiagnosticsScreen extends StatefulWidget {
  const TrackingDiagnosticsScreen({
    super.key,
    this.locationEngine,
  });

  final LocationEngine? locationEngine;

  @override
  State<TrackingDiagnosticsScreen> createState() =>
      _TrackingDiagnosticsScreenState();
}

class _TrackingDiagnosticsScreenState extends State<TrackingDiagnosticsScreen> {
  late final LocationEngine _engine;
  StreamSubscription<LocationEngineStatus>? _statusSubscription;
  StreamSubscription<GpsReading>? _fixSubscription;

  LocationEngineStatus _currentStatus = LocationEngineStatus.acquiringFix;
  GpsReading? _latestReading;
  int _updateCount = 0;
  bool _isManualFixing = false;
  String? _statusMessage;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _engine = widget.locationEngine ?? LocationEngine();
    _currentStatus = _engine.currentStatus;
    _latestReading = _engine.latestFix;

    _statusSubscription = _engine.statusStream.listen((status) {
      if (mounted) {
        setState(() => _currentStatus = status);
      }
    });

    _fixSubscription = _engine.fixStream.listen((reading) {
      if (mounted) {
        setState(() {
          _latestReading = reading;
          _updateCount++;
        });
      }
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    _refreshStatus();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _statusSubscription?.cancel();
    _fixSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final status = await _engine.checkStatus();
    if (mounted) {
      setState(() {
        _currentStatus = status;
        _statusMessage = _statusDescription(status);
      });
    }
  }

  Future<void> _handleAcquireFix() async {
    setState(() => _isManualFixing = true);
    final reading = await _engine.acquireFreshFix();
    if (mounted) {
      setState(() {
        _isManualFixing = false;
        if (reading != null) {
          _latestReading = reading;
          _updateCount++;
          _statusMessage = 'Fresh GPS fix acquired successfully.';
        } else {
          _statusMessage = 'Failed to acquire fresh GPS fix.';
        }
      });
    }
  }

  String _statusDescription(LocationEngineStatus status) {
    switch (status) {
      case LocationEngineStatus.serviceDisabled:
        return 'Phone location hardware is turned OFF.';
      case LocationEngineStatus.permissionMissing:
        return 'Location permission is denied or missing.';
      case LocationEngineStatus.acquiringFix:
        return 'Searching for GPS satellite signals...';
      case LocationEngineStatus.fixAvailable:
        return 'Real GPS fix acquired with good accuracy.';
      case LocationEngineStatus.accuracyPoor:
        return 'GPS fix acquired, but accuracy is degraded (> 80m).';
      case LocationEngineStatus.trackingActive:
        return 'Active journey GPS tracking is streaming.';
      case LocationEngineStatus.trackingInterrupted:
        return 'No fresh GPS fix in > 15s (possible tunnel or indoors).';
      case LocationEngineStatus.locationUnavailable:
        return 'Location hardware or platform error.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reading = _latestReading;
    final fixAge = _engine.fixAge;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS & Tracking Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Status',
            onPressed: _refreshStatus,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // State Banner
          _buildStateBanner(theme),
          const SizedBox(height: 16),

          // Live Telemetry Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.satellite_alt_rounded, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Live GPS Telemetry',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (_isManualFixing)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const Divider(height: 24),
                  _buildDataRow(
                    'Coordinates',
                    reading != null
                        ? '${reading.latitude.toStringAsFixed(6)}°, ${reading.longitude.toStringAsFixed(6)}°'
                        : 'No GPS Fix',
                  ),
                  _buildDataRow(
                    'Accuracy',
                    reading != null
                        ? '±${reading.accuracyMeters.toStringAsFixed(1)} m ${reading.accuracyMeters <= 25 ? '✅ (Good)' : '⚠️ (Poor)'}'
                        : 'N/A',
                  ),
                  _buildDataRow(
                    'Fix Age',
                    fixAge != null
                        ? '${fixAge.inSeconds}s ago ${fixAge.inSeconds > 15 ? '⚠️ (Stale)' : '✅ (Fresh)'}'
                        : 'N/A',
                  ),
                  _buildDataRow(
                    'Speed',
                    reading != null && reading.speedMps != null
                        ? '${(reading.speedMps! * 3.6).toStringAsFixed(1)} km/h (${reading.speedMps!.toStringAsFixed(1)} m/s)'
                        : 'N/A',
                  ),
                  _buildDataRow(
                    'Fix Timestamp',
                    reading != null
                        ? '${reading.timestamp.hour.toString().padLeft(2, '0')}:${reading.timestamp.minute.toString().padLeft(2, '0')}:${reading.timestamp.second.toString().padLeft(2, '0')}'
                        : 'N/A',
                  ),
                  _buildDataRow(
                    'Bearing / Heading',
                    reading != null && reading.bearingDegrees != null
                        ? '${reading.bearingDegrees!.toStringAsFixed(1)}°'
                        : 'N/A',
                  ),
                  _buildDataRow(
                    'Updates In Session',
                    '$_updateCount fixes received',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Diagnostic Actions
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Diagnostic Actions',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _isManualFixing ? null : _handleAcquireFix,
                    icon: const Icon(Icons.gps_fixed),
                    label: const Text('Acquire Fresh Single Fix Now'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _engine.openLocationSettings(),
                    icon: const Icon(Icons.settings),
                    label: const Text('Open Device Location Settings'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _engine.openAppSettings(),
                    icon: const Icon(Icons.security),
                    label: const Text('Open App Permission Settings'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateBanner(ThemeData theme) {
    Color color;
    IconData icon;
    String label;

    switch (_currentStatus) {
      case LocationEngineStatus.trackingActive:
        color = Colors.green;
        icon = Icons.gps_fixed;
        label = 'Tracking Active — Real-time GPS fixes streaming';
        break;
      case LocationEngineStatus.fixAvailable:
        color = Colors.teal;
        icon = Icons.check_circle_outline;
        label = 'Fix Available — Hardware ready';
        break;
      case LocationEngineStatus.acquiringFix:
        color = Colors.blue;
        icon = Icons.satellite_alt;
        label = 'Acquiring GPS Satellite Fix...';
        break;
      case LocationEngineStatus.accuracyPoor:
        color = Colors.orange;
        icon = Icons.warning_amber_rounded;
        label = 'Accuracy Poor (> 80m) — Awaiting precise fix';
        break;
      case LocationEngineStatus.serviceDisabled:
        color = Colors.red;
        icon = Icons.location_off;
        label = 'Location Service Disabled in Phone Settings';
        break;
      case LocationEngineStatus.permissionMissing:
        color = Colors.red;
        icon = Icons.security_update_warning;
        label = 'Location Permission Missing / Denied';
        break;
      case LocationEngineStatus.trackingInterrupted:
        color = Colors.deepOrange;
        icon = Icons.signal_cellular_connected_no_internet_4_bar;
        label = 'Tracking Interrupted — No fresh fix in > 15s';
        break;
      case LocationEngineStatus.locationUnavailable:
        color = Colors.grey;
        icon = Icons.error_outline;
        label = 'Location Unavailable';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                if (_statusMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _statusMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
