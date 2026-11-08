import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/arrival_event.dart';
import '../models/gps_reading.dart';
import '../models/journey.dart';
import '../models/stop.dart';
import 'alarm_service.dart';
import 'arrival_confidence_ml.dart';
import 'arrival_detector.dart';
import 'journey_repository.dart';
import 'location_service.dart';
import 'messaging_service.dart';

/// Clear state machine representing the lifecycle of an active tracking session.
enum TrackingState {
  idle,
  monitoring,
  potentialArrival,
  arrivalConfirmed,
  alertTriggered,
  stopCompleted,
  journeyCompleted,
  paused,
  cancelled,
}

/// Comprehensive state snapshot emitted during active tracking.
@immutable
class TrackingSessionState {
  const TrackingSessionState({
    required this.state,
    this.activeJourney,
    this.currentStop,
    this.lastReading,
    this.distanceToStopMeters,
    this.arrivalResult,
    this.confidenceScore,
    this.messageStatus = MessageDeliveryStatus.notTriggered,
    this.statusMessage = 'Tracking is idle.',
  });

  final TrackingState state;
  final Journey? activeJourney;
  final Stop? currentStop;
  final GpsReading? lastReading;
  final double? distanceToStopMeters;
  final ArrivalDetectionResult? arrivalResult;
  final ArrivalConfidenceScore? confidenceScore;
  final MessageDeliveryStatus messageStatus;
  final String statusMessage;

  bool get isMonitoring => state == TrackingState.monitoring;
  bool get isPotentialArrival => state == TrackingState.potentialArrival;
  bool get isAlertActive => state == TrackingState.alertTriggered;
  bool get isCompleted => state == TrackingState.journeyCompleted;
  bool get isPaused => state == TrackingState.paused;

  TrackingSessionState copyWith({
    TrackingState? state,
    Journey? activeJourney,
    Stop? currentStop,
    GpsReading? lastReading,
    double? distanceToStopMeters,
    ArrivalDetectionResult? arrivalResult,
    ArrivalConfidenceScore? confidenceScore,
    MessageDeliveryStatus? messageStatus,
    String? statusMessage,
  }) {
    return TrackingSessionState(
      state: state ?? this.state,
      activeJourney: activeJourney ?? this.activeJourney,
      currentStop: currentStop ?? this.currentStop,
      lastReading: lastReading ?? this.lastReading,
      distanceToStopMeters: distanceToStopMeters ?? this.distanceToStopMeters,
      arrivalResult: arrivalResult ?? this.arrivalResult,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      messageStatus: messageStatus ?? this.messageStatus,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

/// Orchestrates background GPS acquisition, rule-based arrival detection,
/// ML confidence estimation, alarm playback, and check-in messaging.
class JourneyTrackingService {
  JourneyTrackingService({
    required this.repository,
    LocationService? locationService,
    ArrivalDetector? arrivalDetector,
    AlarmService? alarmService,
    MessagingService? messagingService,
  })  : locationService = locationService ?? LocationService(),
        arrivalDetector = arrivalDetector ?? ArrivalDetector(),
        alarmService = alarmService ?? AlarmService(),
        messagingService = messagingService ?? const CompliantSmsMessagingService();

  final JourneyRepository repository;
  final LocationService locationService;
  final ArrivalDetector arrivalDetector;
  final AlarmService alarmService;
  final MessagingService messagingService;

  StreamSubscription<GpsReading>? _locationSubscription;
  final _stateController = StreamController<TrackingSessionState>.broadcast();
  TrackingSessionState _currentState = const TrackingSessionState(
    state: TrackingState.idle,
  );

  TrackingSessionState get currentState => _currentState;
  Stream<TrackingSessionState> get stateStream => _stateController.stream;

  /// Starts live monitoring for the given [journey].
  Future<bool> startTracking(Journey journey) async {
    // Stop any existing tracking
    await stopTracking();

    final startedJourney = journey.start();
    await repository.saveJourney(startedJourney);

    final activeStop = startedJourney.nextActiveStop;
    if (activeStop == null) {
      _updateState(
        _currentState.copyWith(
          state: TrackingState.journeyCompleted,
          activeJourney: startedJourney,
          statusMessage: 'Journey has no active stops remaining.',
        ),
      );
      return false;
    }

    arrivalDetector.reset();

    _updateState(
      TrackingSessionState(
        state: TrackingState.monitoring,
        activeJourney: startedJourney,
        currentStop: activeStop,
        statusMessage: 'Monitoring GPS for "${activeStop.name}"...',
      ),
    );

    // Subscribe to GPS stream with foreground service
    _locationSubscription = locationService
        .startLocationStream(
          distanceFilterMeters: 15,
          intervalSeconds: 5,
          notificationTitle: 'YatraSaathi: ${startedJourney.name}',
          notificationText: 'Approaching ${activeStop.name}',
        )
        .listen(
          (reading) => processGpsReading(reading),
          onError: (Object error) {
            debugPrint('[JourneyTrackingService] Location stream error: $error');
            _updateState(
              _currentState.copyWith(
                statusMessage: 'Location sensor notice: $error',
              ),
            );
          },
        );

    return true;
  }

  /// Processes an individual GPS reading through the arrival detection engine.
  /// (Called automatically by the GPS stream or directly by automated tests).
  void processGpsReading(GpsReading reading, {DateTime? evaluationTime}) {
    if (_currentState.state == TrackingState.paused ||
        _currentState.state == TrackingState.idle ||
        _currentState.state == TrackingState.cancelled ||
        _currentState.state == TrackingState.journeyCompleted) {
      return;
    }

    final journey = _currentState.activeJourney;
    final activeStop = journey?.nextActiveStop;

    if (journey == null || activeStop == null) {
      _updateState(
        _currentState.copyWith(
          state: TrackingState.journeyCompleted,
          statusMessage: 'No remaining active stops.',
        ),
      );
      return;
    }

    // 1. Evaluate deterministic arrival detector
    final result = arrivalDetector.evaluate(
      journey: journey,
      reading: reading,
      evaluationTime: evaluationTime,
    );

    // 2. Evaluate ML arrival confidence estimator
    final confidence = ArrivalConfidenceEstimator.estimateConfidence(
      distanceMeters: result.distanceMeters ?? 9999.0,
      radiusMeters: activeStop.radiusMeters,
      accuracyMeters: reading.accuracyMeters,
      sampleAge: reading.age(referenceTime: evaluationTime),
      speedMps: reading.speedMps ?? 0.0,
      consecutiveSamples: result.consecutiveSamples,
      dwellDuration: result.dwellDuration,
    );

    // 3. State Machine transitions
    if (result.isArrived) {
      _onArrivalConfirmed(journey, activeStop, reading, result, confidence);
    } else if (result.distanceMeters != null &&
        result.distanceMeters! <= activeStop.radiusMeters) {
      _updateState(
        _currentState.copyWith(
          state: TrackingState.potentialArrival,
          lastReading: reading,
          distanceToStopMeters: result.distanceMeters,
          arrivalResult: result,
          confidenceScore: confidence,
          statusMessage: result.reason,
        ),
      );
    } else {
      _updateState(
        _currentState.copyWith(
          state: TrackingState.monitoring,
          lastReading: reading,
          distanceToStopMeters: result.distanceMeters,
          arrivalResult: result,
          confidenceScore: confidence,
          statusMessage: result.reason,
        ),
      );
    }
  }

  /// Handles confirmed arrival: triggers sound/vibration and triggers check-in workflow.
  Future<void> _onArrivalConfirmed(
    Journey journey,
    Stop stop,
    GpsReading reading,
    ArrivalDetectionResult result,
    ArrivalConfidenceScore confidence,
  ) async {
    _updateState(
      _currentState.copyWith(
        state: TrackingState.arrivalConfirmed,
        lastReading: reading,
        distanceToStopMeters: result.distanceMeters,
        arrivalResult: result,
        confidenceScore: confidence,
        statusMessage: 'Arrival confirmed at "${stop.name}"!',
      ),
    );

    // 1. Trigger Arrival Alarm (Sound and Vibration)
    _updateState(_currentState.copyWith(state: TrackingState.alertTriggered));
    await alarmService.triggerAlarm(
      config: stop.alarmConfig,
      onFinished: () {
        debugPrint('[JourneyTrackingService] Alarm playback finished.');
      },
    );

    // 2. Trigger Per-Stop Contact Check-In workflow if contacts configured
    if (stop.contacts.isNotEmpty) {
      for (final contact in stop.contacts) {
        if (contact.phoneNumber.isNotEmpty) {
          final nextStop = journey.stops.length > stop.order + 1
              ? journey.stops[stop.order + 1].name
              : null;
          final msgText = contact.customMessage.isNotEmpty
              ? contact.customMessage
              : messagingService.formatDefaultMessage(
                  stopName: stop.name,
                  nextStopName: nextStop,
                );

          final status = await messagingService.sendCheckInMessage(
            contactName: contact.contactName,
            phoneNumber: contact.phoneNumber,
            stopName: stop.name,
            customMessage: msgText,
            journeyName: journey.name,
          );

          _updateState(_currentState.copyWith(messageStatus: status));
        }
      }
    }
  }

  /// Advances the journey to the next active stop after current stop is acknowledged.
  Future<void> advanceToNextStop() async {
    alarmService.dismiss();

    final journey = _currentState.activeJourney;
    final currentStop = _currentState.currentStop;
    if (journey == null || currentStop == null) return;

    final updatedJourney = journey.markStopReached(
      currentStop.id,
      DateTime.now(),
    );
    await repository.saveJourney(updatedJourney);

    final nextStop = updatedJourney.nextActiveStop;

    if (nextStop == null || updatedJourney.isCompleted) {
      _updateState(
        _currentState.copyWith(
          state: TrackingState.journeyCompleted,
          activeJourney: updatedJourney,
          currentStop: null,
          statusMessage: 'Journey "${journey.name}" completed!',
        ),
      );
      await stopTracking(keepActiveInRepo: false);
    } else {
      arrivalDetector.markStopHandled(currentStop.id);
      _updateState(
        _currentState.copyWith(
          state: TrackingState.monitoring,
          activeJourney: updatedJourney,
          currentStop: nextStop,
          statusMessage: 'Heading to next stop: "${nextStop.name}"...',
        ),
      );
    }
  }

  /// Pauses tracking session.
  Future<void> pauseTracking() async {
    final journey = _currentState.activeJourney?.pause();
    if (journey != null) {
      await repository.saveJourney(journey);
    }
    alarmService.stopAlarm();
    _updateState(
      _currentState.copyWith(
        state: TrackingState.paused,
        activeJourney: journey,
        statusMessage: 'Tracking paused.',
      ),
    );
  }

  /// Resumes a paused tracking session.
  Future<void> resumeTracking() async {
    final journey = _currentState.activeJourney?.resume();
    if (journey != null) {
      await repository.saveJourney(journey);
    }
    _updateState(
      _currentState.copyWith(
        state: TrackingState.monitoring,
        activeJourney: journey,
        statusMessage: 'Tracking resumed.',
      ),
    );
  }

  /// Cancels the tracking session.
  Future<void> cancelTracking() async {
    alarmService.dismiss();
    final journey = _currentState.activeJourney?.cancel();
    if (journey != null) {
      await repository.saveJourney(journey);
    }
    await stopTracking();
    _updateState(
      _currentState.copyWith(
        state: TrackingState.cancelled,
        activeJourney: journey,
        statusMessage: 'Journey cancelled.',
      ),
    );
  }

  /// Halts location stream and cleans up resources.
  Future<void> stopTracking({bool keepActiveInRepo = true}) async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    alarmService.stopAlarm();
    if (!keepActiveInRepo) {
      await repository.setActiveJourneyId(null);
    }
  }

  void _updateState(TrackingSessionState newState) {
    _currentState = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  void dispose() {
    stopTracking();
    alarmService.dispose();
    locationService.dispose();
    _stateController.close();
  }
}

