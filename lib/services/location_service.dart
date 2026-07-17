import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/gps_reading.dart';

/// Status of device location services and runtime permissions.
enum LocationPermissionState {
  granted,
  whileInUse,
  always,
  denied,
  deniedForever,
  serviceDisabled,
}

/// Service managing GPS sensor acquisition, permission workflows,
/// and Android foreground service lifecycle.
class LocationService {
  LocationService({
    GeolocatorPlatform? geolocator,
  }) : _geolocator = geolocator ?? GeolocatorPlatform.instance;

  final GeolocatorPlatform _geolocator;
  StreamSubscription<Position>? _positionSubscription;

  /// Checks whether device GPS hardware is enabled and location permission is granted.
  Future<LocationPermissionState> checkPermissionState() async {
    final isEnabled = await _geolocator.isLocationServiceEnabled();
    if (!isEnabled) {
      return LocationPermissionState.serviceDisabled;
    }

    final permission = await _geolocator.checkPermission();
    switch (permission) {
      case LocationPermission.always:
        return LocationPermissionState.always;
      case LocationPermission.whileInUse:
        return LocationPermissionState.whileInUse;
      case LocationPermission.denied:
        return LocationPermissionState.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionState.deniedForever;
      case LocationPermission.unableToDetermine:
        return LocationPermissionState.denied;
    }
  }

  /// Prompts the user to grant location permissions.
  Future<LocationPermissionState> requestPermission() async {
    final isEnabled = await _geolocator.isLocationServiceEnabled();
    if (!isEnabled) {
      return LocationPermissionState.serviceDisabled;
    }

    var permission = await _geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _geolocator.requestPermission();
    }

    switch (permission) {
      case LocationPermission.always:
        return LocationPermissionState.always;
      case LocationPermission.whileInUse:
        return LocationPermissionState.whileInUse;
      case LocationPermission.denied:
        return LocationPermissionState.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionState.deniedForever;
      case LocationPermission.unableToDetermine:
        return LocationPermissionState.denied;
    }
  }

  /// Opens native Android OS application settings screen.
  Future<bool> openAppSettings() async {
    return _geolocator.openAppSettings();
  }

  /// Opens native Android OS location settings screen.
  Future<bool> openLocationSettings() async {
    return _geolocator.openLocationSettings();
  }

  /// Acquires a single current GPS location fix.
  Future<GpsReading?> getCurrentReading() async {
    try {
      final pos = await _geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return _mapPositionToReading(pos);
    } catch (e) {
      debugPrint('[LocationService] Failed to acquire current location: $e');
      return null;
    }
  }

  /// Subscribes to continuous GPS location updates with Android foreground service
  /// notification for reliable background transit monitoring.
  Stream<GpsReading> startLocationStream({
    int distanceFilterMeters = 0,
    int intervalSeconds = 4,
    String notificationTitle = 'YatraSaathi Journey Active',
    String notificationText = 'Monitoring arrival at upcoming stops in the background',
  }) {
    LocationSettings settings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android Foreground Service configuration ensures tracking continues
      // when app is minimized, screen is locked, or user switches applications.
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
        intervalDuration: Duration(seconds: intervalSeconds),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: notificationTitle,
          notificationText: notificationText,
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else {
      settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
      );
    }

    return _geolocator
        .getPositionStream(locationSettings: settings)
        .map(_mapPositionToReading);
  }

  /// Converts platform [Position] to validated domain [GpsReading].
  GpsReading _mapPositionToReading(Position pos) {
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
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }
}

