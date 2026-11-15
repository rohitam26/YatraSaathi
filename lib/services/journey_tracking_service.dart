import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/arrival_event.dart';
import '../models/contact_checkin_config.dart';
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

  final Set<String> _alertedStopIds = <String>{};
  final Set<String> _dispatchedMessageKeys = <String>{};
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
    _alertedStopIds.clear();

    final startedJourney = journey.start();
    await repository.saveJourney(startedJourney);

    final activeStop = startedJourney.nextActiveStop ?? startedJourney.nextStop;
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

    // Check / request runtime location permissions
    try {
      final perm = await locationService.checkPermissionState();
      if (perm == LocationPermissionState.denied ||
          perm == LocationPermissionState.deniedForever ||
          perm == LocationPermissionState.serviceDisabled) {
        await locationService.requestPermission();
      }
    } catch (_) {}

    _updateState(
      TrackingSessionState(
        state: TrackingState.monitoring,
        activeJourney: startedJourney,
        currentStop: activeStop,
        statusMessage: 'Monitoring GPS for "${activeStop.name}"...',
      ),
    );

    // Immediately acquire current GPS reading to eliminate startup latency
    locationService.getCurrentReading().then((initialReading) {
      if (initialReading != null && _currentState.isMonitoring) {
        processGpsReading(initialReading);
      }
    }).catchError((_) {});

    // Subscribe to continuous GPS stream with foreground service (target interval: 3s)
    _locationSubscription = locationService
        .startLocationStream(
          distanceFilterMeters: 0,
          intervalSeconds: 3,
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

  /// Restores an active tracking session from persistent storage on app launch or resume.
  Future<bool> restoreActiveSession() async {
    final active = await repository.getActiveJourney();
    if (active != null && (active.isActive || active.isPaused)) {
      final target = active.nextActiveStop ?? active.nextStop;
      if (target == null) return false;

      _updateState(
        TrackingSessionState(
          state: active.isPaused ? TrackingState.paused : TrackingState.monitoring,
          activeJourney: active,
          currentStop: target,
          statusMessage: active.isPaused
              ? 'Journey paused. Tap resume to continue.'
              : 'Monitoring GPS for "${target.name}"...',
        ),
      );

      if (active.isActive) {
        _locationSubscription?.cancel();

        locationService.getCurrentReading().then((initialReading) {
          if (initialReading != null && _currentState.isMonitoring) {
            processGpsReading(initialReading);
          }
        }).catchError((_) {});

        _locationSubscription = locationService
            .startLocationStream(
              distanceFilterMeters: 0,
              intervalSeconds: 3,
              notificationTitle: 'YatraSaathi: ${active.name}',
              notificationText: 'Approaching ${target.name}',
            )
            .listen(
              (reading) => processGpsReading(reading),
              onError: (Object error) {
                debugPrint('[JourneyTrackingService] Location stream error: $error');
              },
            );
      }
      return true;
    }
    return false;
  }

  /// Processes an individual GPS reading through the arrival detection engine.
  /// (Called automatically by the GPS stream or directly by automated tests).
  Future<void> processGpsReading(GpsReading reading, {DateTime? evaluationTime}) async {
    if (_currentState.state == TrackingState.paused ||
        _currentState.state == TrackingState.idle ||
        _currentState.state == TrackingState.cancelled ||
        _currentState.state == TrackingState.journeyCompleted) {
      return;
    }

    final journey = _currentState.activeJourney;
    final activeStop = journey?.nextActiveStop ?? journey?.nextStop;

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
      await _onArrivalConfirmed(journey, activeStop, reading, result, confidence);
    } else if (result.distanceMeters != null &&
        result.distanceMeters! <= activeStop.radiusMeters) {
      _updateState(
        _currentState.copyWith(
          state: TrackingState.potentialArrival,
          currentStop: activeStop,
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
          currentStop: activeStop,
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
    // Prevent duplicate triggers for the same stop
    if (_alertedStopIds.contains(stop.id)) {
      debugPrint('[JourneyTrackingService] Arrival already handled for stop ${stop.id}');
      return;
    }
    _alertedStopIds.add(stop.id);

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

    // 1. Trigger Arrival Alarm (Sound and Vibration + Native Notification)
    _updateState(_currentState.copyWith(state: TrackingState.alertTriggered));
    await alarmService.triggerAlarm(
      config: stop.alarmConfig,
      stopName: stop.name,
      journeyTitle: journey.name,
      onFinished: () {
        debugPrint('[JourneyTrackingService] Alarm playback finished.');
      },
    );

    // 2. Prepare Per-Stop Contact Check-In workflow (or fallback to user profile default)
    final effectiveContacts = await getEffectiveContactsForStop(stop);
    if (effectiveContacts.isNotEmpty) {
      _updateState(_currentState.copyWith(messageStatus: MessageDeliveryStatus.readyToSend));

      bool shouldAutoOpen = true;
      try {
        final profile = await repository.getUserProfile();
        shouldAutoOpen = profile.autoCheckInOnArrival;
      } catch (_) {}

      if (shouldAutoOpen) {
        // Automatically open SMS composer for the primary/assigned contact
        final primaryContact = effectiveContacts.first;
        await triggerCheckInForCurrentStop(targetContact: primaryContact);
      }
    }
  }

  /// Explicitly confirms arrival manually when GPS is degraded or shielded.
  Future<void> confirmArrivalManually() async {
    final journey = _currentState.activeJourney;
    final activeStop = journey?.nextActiveStop ?? journey?.nextStop;
    if (journey == null || activeStop == null) return;

    final reading = _currentState.lastReading ??
        GpsReading(
          latitude: activeStop.latitude,
          longitude: activeStop.longitude,
          accuracyMeters: 5.0,
          timestamp: DateTime.now(),
        );

    arrivalDetector.markStopHandled(activeStop.id);

    final event = ArrivalEvent(
      id: 'manual_arrival_${DateTime.now().millisecondsSinceEpoch}_${activeStop.id}',
      journeyId: journey.id,
      stopId: activeStop.id,
      stopName: activeStop.name,
      timestamp: DateTime.now(),
      triggerReading: reading,
      distanceMeters: 0.0,
      dwellDuration: Duration.zero,
    );

    final result = ArrivalDetectionResult(
      status: ArrivalStatus.arrived,
      reading: reading,
      activeStop: activeStop,
      distanceMeters: 0.0,
      reason: 'Manual arrival confirmed by passenger at "${activeStop.name}".',
      event: event,
    );

    const confidence = ArrivalConfidenceScore(
      score: 1.0,
      isHighConfidence: true,
      summary: 'Manual arrival confirmed by passenger.',
      featureContributions: {'manual_override': 1.0},
    );

    await _onArrivalConfirmed(journey, activeStop, reading, result, confidence);
  }

  /// Developer Test Mode: Simulates an arrival event for [targetStop] (or current active stop)
  /// through the exact same downstream arrival handler [_onArrivalConfirmed].
  ///
  /// Distinguishing qualities:
  /// - Marked explicitly with [isTestMode = true] (never recorded as real GPS arrival).
  /// - Does not modify device coordinates or bypass real GPS sensors.
  /// - Strictly available in debug builds ([kDebugMode]).
  /// - Prevents duplicate alerts for the same stop.
  Future<bool> simulateDeveloperTestArrival({Stop? targetStop}) async {
    assert(kDebugMode, 'Developer Test Mode is only available in debug builds.');
    if (!kDebugMode) {
      debugPrint('[DeveloperTestMode] Blocked: Developer Test Mode is disabled in production builds.');
      return false;
    }

    final journey = _currentState.activeJourney;
    if (journey == null) {
      debugPrint('[DeveloperTestMode] Cannot simulate arrival: No active journey.');
      return false;
    }

    final stop = targetStop ??
        _currentState.currentStop ??
        journey.nextActiveStop ??
        journey.nextStop;

    if (stop == null) {
      debugPrint('[DeveloperTestMode] Cannot simulate arrival: Target stop not found.');
      return false;
    }

    // Prevent duplicate alert
    if (_alertedStopIds.contains(stop.id)) {
      debugPrint('[DeveloperTestMode] Stop "${stop.name}" was already alerted. Duplicate alert prevented.');
      return false;
    }

    final simulatedReading = GpsReading(
      latitude: stop.latitude,
      longitude: stop.longitude,
      accuracyMeters: 5.0,
      timestamp: DateTime.now(),
    );

    final event = ArrivalEvent(
      id: 'test_arrival_${DateTime.now().millisecondsSinceEpoch}_${stop.id}',
      journeyId: journey.id,
      stopId: stop.id,
      stopName: stop.name,
      timestamp: DateTime.now(),
      triggerReading: simulatedReading,
      distanceMeters: 0.0,
      dwellDuration: const Duration(seconds: 5),
      isTestMode: true,
    );

    final result = ArrivalDetectionResult(
      status: ArrivalStatus.arrived,
      reading: simulatedReading,
      activeStop: stop,
      distanceMeters: 0.0,
      dwellDuration: const Duration(seconds: 5),
      consecutiveSamples: 2,
      reason: 'TEST MODE: Developer simulated arrival for stop "${stop.name}".',
      event: event,
      isTestMode: true,
    );

    const confidence = ArrivalConfidenceScore(
      score: 1.0,
      isHighConfidence: true,
      summary: 'TEST MODE: Developer simulated arrival.',
      featureContributions: {'developer_test_mode': 1.0},
    );

    debugPrint('[DeveloperTestMode] Dispatched test arrival for stop "${stop.name}" (Order: ${stop.order + 1}, Final: ${stop.isFinalDestination})');

    // Update monitored stop in state if needed
    if (_currentState.currentStop?.id != stop.id) {
      _updateState(_currentState.copyWith(currentStop: stop));
    }

    // Invokes the same downstream arrival handler as real GPS arrivals
    await _onArrivalConfirmed(journey, stop, simulatedReading, result, confidence);
    return true;
  }

  /// Retrieves the effective safety contacts for [stop], falling back to [UserProfile] default.
  Future<List<ContactCheckInConfig>> getEffectiveContactsForStop(Stop stop) async {
    if (stop.contacts.isNotEmpty) {
      return stop.contacts;
    }
    try {
      final profile = await repository.getUserProfile();
      if (profile.hasDefaultContact) {
        final journey = _currentState.activeJourney;
        final nextStop = (journey != null && journey.stops.length > stop.order + 1)
            ? journey.stops[stop.order + 1].name
            : null;
        final defaultContact = profile.toDefaultContactConfig(
          stopName: stop.name,
          nextStopName: nextStop,
        );
        if (defaultContact != null) {
          return [defaultContact];
        }
      }
    } catch (_) {}
    return [];
  }

  /// Cancels check-in for the current stop and records honest userCancelled status.
  void cancelCheckIn() {
    _updateState(_currentState.copyWith(messageStatus: MessageDeliveryStatus.userCancelled));
    debugPrint('[JourneyTrackingService] Check-in cancelled by passenger.');
  }

  /// Dispatches the check-in SMS for the current active stop.
  /// If [targetContact] is specified, dispatches specifically to that recipient (sequential workflow).
  Future<MessageDeliveryStatus> triggerCheckInForCurrentStop({
    ContactCheckInConfig? targetContact,
  }) async {
    final journey = _currentState.activeJourney;
    final stop = _currentState.currentStop ??
        journey?.nextActiveStop ??
        journey?.nextStop;
    if (journey == null || stop == null) return MessageDeliveryStatus.notTriggered;

    ContactCheckInConfig? contact = targetContact;
    if (contact == null) {
      final contacts = await getEffectiveContactsForStop(stop);
      if (contacts.isNotEmpty) {
        contact = contacts.first;
      }
    }

    if (contact == null || contact.phoneNumber.trim().isEmpty) {
      _updateState(_currentState.copyWith(messageStatus: MessageDeliveryStatus.failed));
      return MessageDeliveryStatus.failed;
    }

    // Prevent duplicate SMS dispatches to the same contact at the same stop
    final messageKey = '${journey.id}_${stop.id}_${contact.id}_${contact.phoneNumber.trim()}';
    if (_dispatchedMessageKeys.contains(messageKey)) {
      debugPrint('[JourneyTrackingService] Duplicate check-in suppressed for contact "${contact.contactName}" at stop "${stop.name}".');
      return _currentState.messageStatus;
    }

    // Safety validation: Ensure passenger's own phone number is NOT mistakenly used
    // as emergency recipient! The emergency contact's number MUST be used.
    bool useDirectSms = false;
    try {
      final profile = await repository.getUserProfile();
      final cleanUserPhone = profile.userPhone.replaceAll(RegExp(r'\D'), '');
      final cleanRecipient = contact.phoneNumber.replaceAll(RegExp(r'\D'), '');
      if (cleanUserPhone.isNotEmpty &&
          cleanRecipient.isNotEmpty &&
          cleanUserPhone == cleanRecipient) {
        debugPrint(
          '[JourneyTrackingService] REJECTED: User mobile number ($cleanRecipient) matches emergency contact. Must use emergency contact number.',
        );
        _updateState(_currentState.copyWith(messageStatus: MessageDeliveryStatus.failed));
        return MessageDeliveryStatus.failed;
      }

      // Check if Direct Background SMS is permitted & configured
      if (profile.isDirectSmsActive) {
        if (contact.sendDirectSms || profile.isContactOptedInForDirectSms(contact.id)) {
          useDirectSms = true;
        }
      }
    } catch (_) {}

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
      sendDirect: useDirectSms,
    );

    if (status == MessageDeliveryStatus.sentConfirmed ||
        status == MessageDeliveryStatus.composerOpened) {
      _dispatchedMessageKeys.add(messageKey);
    }

    _updateState(_currentState.copyWith(messageStatus: status));
    return status;
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
    final target = journey?.nextActiveStop ?? journey?.nextStop;
    _updateState(
      _currentState.copyWith(
        state: TrackingState.paused,
        activeJourney: journey,
        currentStop: target,
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
    final target = journey?.nextActiveStop ?? journey?.nextStop;
    _updateState(
      _currentState.copyWith(
        state: TrackingState.monitoring,
        activeJourney: journey,
        currentStop: target,
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
    _dispatchedMessageKeys.clear();
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

