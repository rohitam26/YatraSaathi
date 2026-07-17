import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/gps_reading.dart';
import 'location_service.dart';

/// Detailed, honest states representing real-world Android location conditions.
enum LocationEngineStatus {
  /// Runtime location permission is denied or not yet requested.
  permissionMissing,

  /// Device GPS hardware switch is turned off in Android system settings.
  serviceDisabled,

  /// Permission is granted and GPS hardware is active, waiting for the first fix.
  acquiringFix,

  /// Real GPS satellite fix is acquired and available.
  fixAvailable,

  /// GPS fix is available, but horizontal accuracy is degraded (e.g. > 80m).
  accuracyPoor,

  /// Active journey transit tracking is actively streaming with foreground service.
  trackingActive,

  /// Tracking was running, but GPS fixes stopped arriving (tunnels, indoor loss).
  trackingInterrupted,

  /// Platform or sensor error: location cannot be acquired.
  locationUnavailable,
}

/// Authoritative location engine coordinating Android Google Play Services
/// Fused Location Provider updates, runtime permission lifecycle, hardware
/// status checks, and fix telemetry diagnostics.
class LocationEngine {
  LocationEngine({
    GeolocatorPlatform? geolocator,
  }) : _geolocator = geolocator ?? GeolocatorPlatform.instance;

  final GeolocatorPlatform _geolocator;

  LocationEngineStatus _status = LocationEngineStatus.acquiringFix;
  GpsReading? _latestFix;
  DateTime? _lastFixTime;
  int _totalUpdatesReceived = 0;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _staleWatchdogTimer;

  final _statusController = StreamController<LocationEngineStatus>.broadcast();
  final _fixController = StreamController<GpsReading>.broadcast();

  LocationEngineStatus get currentStatus => _status;
  GpsReading? get latestFix => _latestFix;
  DateTime? get lastFixTime => _lastFixTime;
  int get totalUpdatesReceived => _totalUpdatesReceived;
  double? get latestAccuracy => _latestFix?.accuracyMeters;

  Duration? get fixAge {
    if (_lastFixTime == null) return null;
    return DateTime.now().difference(_lastFixTime!);
  }

  Stream<LocationEngineStatus> get statusStream => _statusController.stream;
  Stream<GpsReading> get fixStream => _fixController.stream;

  void _setStatus(LocationEngineStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      if (!_statusController.isClosed) {
        _statusController.add(newStatus);
      }
    }
  }

  /// Checks device location hardware switch and runtime permissions.
  Future<LocationEngineStatus> checkStatus() async {
    try {
      final isEnabled = await _geolocator.isLocationServiceEnabled();
      if (!isEnabled) {
        _setStatus(LocationEngineStatus.serviceDisabled);
        return LocationEngineStatus.serviceDisabled;
      }

      final permission = await _geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _setStatus(LocationEngineStatus.permissionMissing);
        return LocationEngineStatus.permissionMissing;
      }

      if (_latestFix != null) {
        final status = (_latestFix!.accuracyMeters > 80.0)
            ? LocationEngineStatus.accuracyPoor
            : LocationEngineStatus.fixAvailable;
        _setStatus(status);
        return status;
      }

      _setStatus(LocationEngineStatus.acquiringFix);
      return LocationEngineStatus.acquiringFix;
    } catch (e) {
      debugPrint('[LocationEngine] checkStatus handled platform notice: $e');
      _setStatus(LocationEngineStatus.locationUnavailable);
      return LocationEngineStatus.locationUnavailable;
    }
  }

  /// Prompts the user to grant precise location permissions.
  Future<LocationPermissionState> requestPermission() async {
    final isEnabled = await _geolocator.isLocationServiceEnabled();
    if (!isEnabled) {
      _setStatus(LocationEngineStatus.serviceDisabled);
      return LocationPermissionState.serviceDisabled;
    }

    var permission = await _geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _geolocator.requestPermission();
    }

    switch (permission) {
      case LocationPermission.always:
        await checkStatus();
        return LocationPermissionState.always;
      case LocationPermission.whileInUse:
        await checkStatus();
        return LocationPermissionState.whileInUse;
      case LocationPermission.denied:
        _setStatus(LocationEngineStatus.permissionMissing);
        return LocationPermissionState.denied;
      case LocationPermission.deniedForever:
        _setStatus(LocationEngineStatus.permissionMissing);
        return LocationPermissionState.deniedForever;
      case LocationPermission.unableToDetermine:
        _setStatus(LocationEngineStatus.permissionMissing);
        return LocationPermissionState.denied;
    }
  }

  /// Opens the native Android OS system location settings screen.
  Future<bool> openLocationSettings() async {
    return _geolocator.openLocationSettings();
  }

  /// Opens the native Android OS application settings screen.
  Future<bool> openAppSettings() async {
    return _geolocator.openAppSettings();
  }

  /// Acquires a single fresh GPS location fix with timeout.
  Future<GpsReading?> acquireFreshFix({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      final status = await checkStatus();
      if (status == LocationEngineStatus.serviceDisabled ||
          status == LocationEngineStatus.permissionMissing) {
        return null;
      }

      _setStatus(LocationEngineStatus.acquiringFix);
      final position = await _geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );

      final reading = _mapPosition(position);
      _onFixReceived(reading);
      return reading;
    } catch (e) {
      debugPrint('[LocationEngine] Fresh fix acquisition notice: $e');
      if (_latestFix == null) {
        _setStatus(LocationEngineStatus.locationUnavailable);
      }
      return null;
    }
  }

  /// Starts continuous high-accuracy location monitoring with Android Foreground Service.
  Stream<GpsReading> startTracking({
    required String notificationTitle,
    required String notificationText,
    int intervalSeconds = 4,
  }) {
    _positionSubscription?.cancel();
    _staleWatchdogTimer?.cancel();

    LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0, // 0 ensures updates arrive on interval even when stationary
        intervalDuration: Duration(seconds: intervalSeconds),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: notificationTitle,
          notificationText: notificationText,
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );
    }

    _setStatus(LocationEngineStatus.acquiringFix);

    _positionSubscription = _geolocator
        .getPositionStream(locationSettings: settings)
        .listen(
          (pos) {
            final reading = _mapPosition(pos);
            _onFixReceived(reading);
            _setStatus(LocationEngineStatus.trackingActive);
            if (!_fixController.isClosed) {
              _fixController.add(reading);
            }
          },
          onError: (Object error) {
            debugPrint('[LocationEngine] Stream error: $error');
            _setStatus(LocationEngineStatus.trackingInterrupted);
          },
        );

    // Watchdog timer: checks every 10 seconds if fixes are stale (>35 seconds)
    _staleWatchdogTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_status == LocationEngineStatus.trackingActive && fixAge != null) {
        if (fixAge! > const Duration(seconds: 35)) {
          _setStatus(LocationEngineStatus.trackingInterrupted);
        }
      }
    });

    // Immediately trigger a one-shot current reading to eliminate startup latency
    acquireFreshFix().then((fix) {
      if (fix != null && _status == LocationEngineStatus.acquiringFix) {
        _setStatus(LocationEngineStatus.trackingActive);
        if (!_fixController.isClosed) {
          _fixController.add(fix);
        }
      }
    }).catchError((_) {});

    return fixStream;
  }

  void _onFixReceived(GpsReading reading) {
    _latestFix = reading;
    _lastFixTime = DateTime.now();
    _totalUpdatesReceived++;
  }

  /// Stops continuous location tracking and halts the foreground service.
  Future<void> stopTracking() async {
    _staleWatchdogTimer?.cancel();
    _staleWatchdogTimer = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await checkStatus();
  }

  GpsReading _mapPosition(Position pos) {
    return GpsReading(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracyMeters: pos.accuracy,
      timestamp: pos.timestamp,
      speedMps: pos.speed >= 0 ? pos.speed : null,
      bearingDegrees: pos.heading >= 0 ? pos.heading : null,
    );
  }

  void dispose() {
    stopTracking();
    _statusController.close();
    _fixController.close();
  }
}
