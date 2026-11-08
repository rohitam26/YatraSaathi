# YatraSaathi — Complete Technical Audit Report

**Date:** November 2026  
**Auditor:** Senior Flutter Developer, Android Engineer, Software Architect, QA Engineer, Security Auditor & ML Engineer  
**Project:** YatraSaathi (`pathsaathi`)  
**Repository Directory:** `E:\develop\pathsaathi`  
**Flutter SDK:** 3.47.8 • Dart SDK: 3.13.7  
**Android SDK:** 36.0.0 (API 37 Platform installed at `E:\Android\Sdk`)  
**Java JDK:** OpenJDK 25.0.3 (Android Studio JBR)

---

## 1. Executive Summary

YatraSaathi is architected as an offline-first, privacy-respecting multi-stop travel companion for Android. Its purpose is to monitor user progress towards upcoming transit stops via GPS, trigger loud arrival alerts (sound & vibration), and launch honest check-in messages (via compliant Android SMS composer intents) to reassure loved ones.

The current codebase possesses a solid architectural foundation in its domain models (`Journey`, `Stop`, `AlarmConfig`, `ContactCheckInConfig`, `GpsReading`, `ArrivalEvent`), Haversine distance calculator, rule-based `ArrivalDetector`, and local SharedPreferences persistence layer (`LocalJourneyRepository`), all covered by 28 passing unit and widget tests with zero Flutter analyzer warnings.

However, the hardware and platform integrations required for a production Android app are currently missing:
- No real GPS location stream acquisition from Android hardware.
- No Android foreground service or background location tracking mechanism.
- Zero Android permissions declared in `AndroidManifest.xml` (missing location, foreground service, notifications, vibration).
- No actual sound playback or haptic vibration triggering engine.
- No SMS/check-in dispatch mechanism (needs compliant Android SMS composer intent abstraction).
- No Machine Learning arrival confidence evaluation pipeline or Dart inference engine.
- Several required UI screens are missing (Active Tracking dashboard, Arrival Alert dialog/screen, Stop Configuration with Alarm & Contact settings, Journey Completion, Full Saved Journeys management, Settings, Permission Guidance, Privacy Policy).

---

## 2. Detailed Technical Audit by Area

| Area | Feature / Subsystem | Status | Technical Audit Findings & Remediation Plan |
| :--- | :--- | :--- | :--- |
| **A** | Application Architecture | **PARTIALLY IMPLEMENTED** | Models and repositories are cleanly decoupled and immutable. Needs a reactive tracking orchestrator/service to bind GPS, arrival detection, alarms, and SMS. |
| **B** | Navigation & Screen Functionality | **PARTIALLY IMPLEMENTED** | `HomeScreen` and `JourneyPlannerScreen` exist. Missing: `ActiveJourneyTrackingScreen`, `ArrivalAlertScreen`, `StopDetailConfigDialog`, `JourneyCompletedScreen`, `SettingsScreen`, `PermissionsGuideScreen`, `PrivacyScreen`. |
| **C** | Journey Creation & Editing | **PARTIALLY IMPLEMENTED** | Creation works with title and stops. Stop editing is missing (users can only delete or reorder, not edit stop coordinates, radius, alarms, or contacts). |
| **D** | Multi-Stop Management | **PARTIALLY IMPLEMENTED** | Sequential auto-indexing, final destination flagging, and reordering work in memory. Stop-level alarm and contact configuration UI are missing. |
| **E** | Local Data Persistence | **COMPLETE AND VERIFIED** | `LocalJourneyRepository` correctly serializes/deserializes journeys to `SharedPreferences` JSON, tracks active journey ID, handles malformed data gracefully. Verified by 5 passing tests. |
| **F** | GPS Location Acquisition | **NOT IMPLEMENTED** | No hardware GPS integration. Need `geolocator` plugin compatible with Flutter 3.47 and Android 14/15. |
| **G** | Arrival Detection | **COMPLETE (LOGIC) / PARTIAL (SYSTEM)** | `ArrivalDetector` has robust multi-reading consistency, dwell time enforcement, accuracy filtering, and duplicate event suppression. Needs real-time stream integration. |
| **H** | Background Location Tracking | **NOT IMPLEMENTED** | No Android foreground service configured. Need Android foreground service with persistent notification, type `location`, and proper lifecycle management. |
| **I** | Android Permissions | **BROKEN / MISSING** | `AndroidManifest.xml` contains zero permissions. Missing: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS`, `VIBRATE`. |
| **J** | Arrival Alarms | **UI / MODEL ONLY** | `AlarmConfig` model exists. No audio playback engine, snooze logic, repeat interval timer, or full-screen arrival alerts. |
| **K** | Sound and Vibration | **NOT IMPLEMENTED** | No audio or vibration plugin in `pubspec.yaml`. Need `audioplayers` or platform notification sound and `vibration` plugin. |
| **L** | Contact Management | **MODEL ONLY** | `ContactCheckInConfig` exists in models, but there is no UI to add or view contacts per stop. |
| **M** | SMS / Check-In Functionality | **MODEL ONLY** | Cannot send silent SMS due to Google Play policy restrictions. Must implement compliant Android SMS composer intent via `url_launcher` with honest status tracking (`COMPOSER_OPENED`, not `SENT_CONFIRMED`). |
| **N** | ML Arrival Confidence | **NOT IMPLEMENTED** | No ML model, training script, synthetic dataset generator, or Dart inference engine exists. |
| **O** | Privacy and Security | **PARTIALLY IMPLEMENTED** | Local-first design is respected. No external telemetry or cloud leakage. Need explicit privacy policy documentation and permission rationale screen. |
| **P** | Battery Consumption | **NOT IMPLEMENTED** | Needs smart GPS sampling (distance filter: 10–25m, interval: 5–10s when far, higher frequency when approaching active stop radius). |
| **Q** | Error Handling | **PARTIALLY IMPLEMENTED** | Model assertions are strong. Needs GPS disabled, location permission denied/permanently denied, and background restriction handling. |
| **R** | UI Responsiveness & Accessibility | **PARTIALLY IMPLEMENTED** | Material 3 light/dark theme configured. Missing empty/error states on secondary screens, high contrast alerts, and accessible dismiss buttons. |
| **S** | Unit and Widget Tests | **PARTIALLY IMPLEMENTED** | 28 tests passing. Missing tests for stop editing, active journey tracking, alarm triggers, SMS composer launching, ML confidence scoring, and all new screens. |
| **T** | Android Release Configuration | **PARTIALLY IMPLEMENTED** | Application label is `pathsaathi` (should display `YatraSaathi`). `build.gradle.kts` is set up with JVM 17. Target SDK and foreground service declarations need updating. |

---

## 3. Defects, Security, and Compliance Deficiencies

1. **Google Play SMS Policy Compliance:**
   - Play Store prohibits background SMS (`SEND_SMS`) for general travel apps unless they are default SMS handlers.
   - Any attempt to silently send SMS would lead to Play Store suspension or immediate runtime permission rejection on Android 10+.
   - **Resolution:** Implement Option B (System SMS Composer intent via `sms:` URI scheme) with honest status reporting (`COMPOSER_OPENED`, `USER_DISMISSED`, `FAILED`).

2. **Android 14+ Foreground Service Policy:**
   - On Android 14 (API 34+), foreground services must declare a specific `foregroundServiceType` (`location`) in `AndroidManifest.xml` and request `FOREGROUND_SERVICE_LOCATION`. Failing to do so throws a `SecurityException` at runtime.
   - **Resolution:** Declare `FOREGROUND_SERVICE_LOCATION` and appropriate service metadata in `AndroidManifest.xml`.

3. **Android 13+ Notification Permission:**
   - Android 13 (API 33+) requires explicit runtime `POST_NOTIFICATIONS` permission before any notification or foreground service notification can be displayed.
   - **Resolution:** Add permission check and explanatory UI dialog before initiating active journey tracking.

4. **GPS Accuracy & Stale Reading Hazards:**
   - Urban environments (metro, underground, high-rises) cause multi-path GPS drift and stale cell-tower fixes.
   - Single-sample triggers cause false-positive alarms miles away from actual stops.
   - **Resolution:** Preserve and enforce the existing `ArrivalDetector` multi-reading buffer (minimum 3 consistent readings within radius) and minimum dwell time (10s).

5. **Stop Configuration Gap:**
   - Currently, adding a stop in `JourneyPlannerScreen` only captures name, latitude, longitude, and radius.
   - Users cannot configure arrival alarms (sound, vibration, repeats) or contact check-in details (contact name, phone number, custom message) for that stop.
   - **Resolution:** Build a comprehensive `StopConfigSheet`/Dialog allowing full customization of coordinates, radius, alarm parameters, and check-in contacts.

---

## 4. Remediation and Implementation Plan

- **Phase 2 (Journey Management):** Complete full stop editing, stop configuration dialog, deletion, reordering, validation, and multi-journey state management.
- **Phase 3 & 4 (Location & Background Tracking):** Add `geolocator`, configure Android foreground service, implement reactive `JourneyTrackingService`, handle all permission states (granted, denied, permanently denied, service disabled).
- **Phase 5 (Arrival Alarm System):** Implement audio/vibration alert engine, full-screen arrival alert dialog, snooze/dismiss actions, and notification triggers.
- **Phase 6 (Contact & Check-In Messaging):** Implement compliant SMS composer dispatch service via `url_launcher` with honest status state machine.
- **Phase 7 (ML Arrival Confidence):** Build reproducible Python ML training pipeline with synthetic journey data, evaluate metrics (precision, recall, F1, confusion matrix), document experimental status, and implement pure Dart arrival confidence scoring engine with rule-based fallback.
- **Phase 8 (UI & UX Polish):** Complete all 14 screens/dialogs with polished Material 3 design, light/dark themes, and accessible typography.
- **Phase 9 (Privacy & Security):** Audit data flow, ensure 100% offline storage, mask phone numbers in logs, draft `PRIVACY.md`.
- **Phase 10 (Testing):** Write comprehensive unit, repository, widget, and mock integration tests covering all new functionality.
- **Phase 11 (Android Build):** Update `AndroidManifest.xml`, configure app title, build Android debug APK, verify artifact generation.
- **Phase 12 (Documentation):** Generate `README.md`, `PROJECT_AUDIT.md`, `IMPLEMENTATION_STATUS.md`, `ARCHITECTURE.md`, `TESTING_REPORT.md`, `PRIVACY.md`, `ANDROID_SETUP.md`.

