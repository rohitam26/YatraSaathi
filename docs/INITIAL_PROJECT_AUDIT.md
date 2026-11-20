# INITIAL PROJECT AUDIT: STOP Vanthachu (formerly YatraSaathi)
**Date:** November 2026  
**Auditor:** Principal Software Architect & QA Engineer  
**Workspace:** `E:\develop\pathsaathi`  
**Application ID:** `com.example.pathsaathi`  
**Target Milestone:** Milestone 1 — Complete Repository Audit, Baseline Verification, and Complete Rebranding

---

## 1. Executive Summary & Purpose

This document provides a comprehensive technical audit of the mobile transit companion application originally known as **YatraSaathi**, now being transitioned to **STOP Vanthachu** ("Never Miss Your Stop. Travel with Confidence.").

The application is an offline-first, privacy-respecting transit journey monitoring and passenger safety companion designed primarily for Android. It assists bus passengers, train commuters, metro travellers, and long-distance riders in tracking their upcoming transit stops, triggering high-reliability audible and tactile alarms upon arrival, and facilitating automated safety check-in messages to emergency contacts.

Before executing feature expansions (Milestones 2–14), this audit establishes an evidence-based technical baseline of the repository, documenting:
1. Architectural structure and module responsibilities.
2. Verified working, partially implemented, experimental, and missing capabilities.
3. Android native integration, foreground service configurations, and platform channel implementations.
4. Technical debt, security considerations, and privacy guarantees.
5. Exact baseline verification metrics (static analysis, unit/widget tests, debug build status).

---

## 2. Baseline Verification Results (Pre-Modification)

The baseline health of the existing repository was empirically verified prior to code modifications:

| Verification Stage | Command Executed | Result | Details |
|---|---|---|---|
| **Static Code Analysis** | `flutter analyze` | **PASSED (0 Issues)** | `No issues found! (ran in 132.4s)`. Zero errors, zero warnings, zero linter hints across all Dart files. |
| **Automated Test Suite** | `flutter test` | **PASSED (90/90 Tests)** | `00:30 +90: All tests passed!`. Zero test failures, zero skipped tests across unit, integration, and UI widget suites. |
| **Android Debug Build** | `flutter build apk --debug` | **PASSED (Exit Code 0)** | Built `build\app\outputs\flutter-apk\app-debug.apk` in 72.5 seconds using Gradle 9.3.1 and Java 17 desugaring. |

---

## 3. Architecture & Codebase Inspection

The application is implemented in Flutter/Dart with native Kotlin integration on Android. The codebase is organized into modular layers:

```
lib/
├── main.dart                          # Application entry point, theme setup, home dashboard
├── models/                            # Domain entities with JSON serialization
│   ├── alarm_config.dart              # Alarm preferences (sound, volume, snooze, vibration)
│   ├── arrival_event.dart             # Immutable record of confirmed arrival telemetry
│   ├── contact_checkin_config.dart    # Per-stop SMS recipient and message override
│   ├── gps_reading.dart               # Geodetic coordinates, accuracy, speed, heading, timestamp
│   ├── journey.dart                   # Journey aggregate root with ordered Stop list and lifecycle state
│   ├── safety_contact.dart            # Emergency contact model with primary designation
│   ├── stop.dart                      # Individual destination stop with arrival radius and alarm config
│   └── user_profile.dart              # Global passenger identity and default safety settings
├── services/                          # Core business logic and hardware abstractions
│   ├── alarm_service.dart             # Audible audio playback, tactile vibration, preview player
│   ├── arrival_confidence_ml.dart     # Experimental on-device logistic regression inference
│   ├── arrival_detector.dart          # Deterministic multi-criteria arrival detection engine
│   ├── direct_sms_service.dart        # Platform channel wrapper for Android SmsManager
│   ├── distance_calculator.dart       # Great-circle Haversine distance calculation
│   ├── geocoding_service.dart         # Photon & Nominatim OpenStreetMap search & reverse geocoding
│   ├── journey_repository.dart        # Local persistence via SharedPreferences
│   ├── journey_tracking_service.dart  # Central orchestrator: GPS stream + detection + alarms + SMS
│   ├── location_engine.dart           # Fused location provider coordinator and telemetry state
│   ├── location_service.dart          # Geolocator platform wrapper & foreground notification setup
│   └── notification_service.dart      # Android notification channels (USAGE_ALARM audio routing)
└── ui/                                # Presentation layer (Material 3)
    ├── active_journey_screen.dart     # Real-time monitoring, progress gauge, Developer Test Mode
    ├── arrival_alert_dialog.dart      # High-visibility arrival dialog (snooze, dismiss, check-in)
    ├── first_launch_onboarding_screen.dart # First-run permission onboarding and privacy consent
    ├── journey_completion_screen.dart # Final stop completion summary
    ├── journey_planner_screen.dart    # Multi-stop planner with reorderable list
    ├── journey_wizard_screen.dart     # Step-by-step creation wizard with map picker
    ├── permission_guidance_screen.dart# Transparent Android permission status and rationale
    ├── privacy_info_screen.dart       # Local-first privacy architecture breakdown
    ├── safety_contacts_screen.dart    # Contact manager (add, edit, delete, set primary)
    ├── saved_journeys_screen.dart     # Saved journey library with search filter and quick launch
    ├── settings_screen.dart           # Passenger safety profile, default sounds, technical tuning
    ├── stop_config_dialog.dart        # Tabbed stop editor (Location, Radius, Alarm, Check-In)
    ├── tracking_diagnostics_screen.dart # Live GPS sensor telemetry and satellite fix monitor
    └── widgets/                       # Reusable UI components
```

### Detailed Component Analysis

#### 3.1 Sensor Acquisition & Telemetry (`location_service.dart`, `location_engine.dart`)
- **Implementation:** Wraps `geolocator` plugin version `13.0.2`.
- **Foreground Service:** Uses `AndroidSettings` with `ForegroundNotificationConfig` to maintain continuous high-accuracy GPS polling when minimized, screen locked, or under Android Doze mode.
- **Diagnostics:** `LocationEngine` maintains telemetry state (`LocationEngineStatus`: `acquiringFix`, `fixAvailable`, `accuracyPoor`, `trackingActive`, `trackingInterrupted`, `serviceDisabled`, `permissionMissing`) and features a 35-second watchdog timer detecting stale location fixes.

#### 3.2 Deterministic Arrival Detection Engine (`arrival_detector.dart`)
The core arrival detector is purely deterministic and rule-based. It mandates 7 validation checks before confirming an arrival:
1. **Active Stop Validation:** Ensures journey is actively in progress and targets `nextActiveStop`.
2. **Monitored Stop Synchronization:** Automatically clears sample buffers when advancing stops.
3. **Duplicate Suppression:** Checks if `activeStop.isReached` or already recorded in `_handledStopIds`.
4. **Coordinate Boundary Check:** Rejects invalid latitude/longitude ranges (`[-90, 90]`, `[-180, 180]`).
5. **Freshness Watchdog:** Enforces `maxSampleAge` (default 45s), rejecting stale fixes.
6. **Accuracy Threshold:** Enforces `maxAcceptableAccuracyMeters` (default 80.0m), rejecting cellar/tower noise.
7. **Haversine Distance & Multi-Sample Dwell Verification:** Requires distance within stop radius, accumulated over `consecutiveReadingsRequired` (minimum 2, default 2–3) AND sustained dwell duration `minDwellTime` (default 4–10 seconds).

#### 3.3 Audio Playback & Haptics (`alarm_service.dart`, `notification_service.dart`)
- **Audio Routing:** Configures `audioplayers` with `AudioContextAndroid` specifying `usageType: AndroidUsageType.alarm` and `isSpeakerphoneOn: true` to bypass silent mode and ring through phone speakers.
- **Ringtone Presets:** Bundles 7 audio assets (`classic_ring.wav`, `urgent_alarm.wav`, `gentle_chime.wav`, `arrival_chime.wav`, `bell_alert.wav`, `gentle_ripple.wav`, `subtle_ping.wav`) both in Flutter assets (`assets/sounds/`) and Android native raw resources (`android/app/src/main/res/raw/`).
- **Tactile Haptics:** Uses `vibration` plugin with customizable pulse patterns (urgent, gentle, continuous).
- **Notification Channels:** Configures `NotificationService` with `yatrasaathi_arrival_v3` (importance `max`, `audioAttributesUsage: AudioAttributesUsage.alarm`, fullScreenIntent).

#### 3.4 Messaging & Safety Check-ins (`messaging_service.dart`, `direct_sms_service.dart`, `MainActivity.kt`)
- **Two-Tier Architecture:**
  1. *Play Store Compliant Fallback (Default):* Uses `url_launcher` with `sms:` URI scheme to launch the native Android SMS composer pre-filled with recipient and personalized stop message. Zero restricted permissions required.
  2. *Direct Cellular Transmission (Privately Distributed Builds):* Integrates with Android `SmsManager` via native MethodChannel `com.example.pathsaathi/direct_sms`. Verifies `SEND_SMS` permission, checks active SIM card status via `TelephonyManager`, registers an unexported `BroadcastReceiver` listening for carrier radio transmission acknowledgment, and enforces a 15-second watchdog timer.

#### 3.5 Local Persistence (`journey_repository.dart`)
- Implemented via `LocalJourneyRepository` using `shared_preferences`.
- Stores JSON serialized strings under keys:
  - `yatrasaathi_saved_journeys_v1`
  - `yatrasaathi_active_journey_id_v1`
  - `yatrasaathi_user_profile_v1`
  - `yatrasaathi_safety_contacts_v1`
- Includes legacy key migration fallbacks (`pref_contact_name`, `pref_contact_phone`, `pref_checkin_msg`).

#### 3.6 Experimental Machine Learning (`arrival_confidence_ml.dart`, `ml/`)
- Contains an offline logistic regression inference engine estimating arrival confidence percentage ($0\% - 100\%$) based on:
  - Distance-to-radius ratio
  - GPS horizontal accuracy score
  - Timestamp freshness score
  - Vehicle speed score
  - Consecutive sample ratio
  - Dwell duration ratio
  - Recent speed variance
  - Convergence rate (approach velocity)
- Model weights were trained via `ml/train_arrival_model.py` with synthetic feature distributions.
- **Safety Boundary:** The ML model is strictly advisory and **never** triggers arrival alarms independently; the deterministic `ArrivalDetector` remains the sole authority.

---

## 4. Features Inventory & Status Matrix

| Category | Feature | Status | Implementation Details |
|---|---|---|---|
| **Journey Planning** | Multi-stop journey creation | **Working** | Wizard with starting point, intermediate stops, final destination. |
| **Journey Planning** | OpenStreetMap place search | **Working** | Photon & Nominatim geocoding with debounce and category parsing. |
| **Journey Planning** | Map location picker | **Working** | Interactive `flutter_map` with tap-to-pinpoint coordinate selection. |
| **Journey Planning** | Stop radius configuration | **Working** | Configurable radius per stop (100m–2000m) with preset chips. |
| **Tracking & Detection**| Continuous GPS tracking | **Working** | Foreground service with wake lock and ongoing notification. |
| **Tracking & Detection**| Haversine distance engine | **Working** | High-precision spherical distance calculation in meters. |
| **Tracking & Detection**| Multi-sample dwell validation | **Working** | Prevents false alarms on fleeting proximity; enforces dwell duration. |
| **Tracking & Detection**| Duplicate alert suppression | **Working** | Handled stop IDs set prevents repeated alarms for same stop. |
| **Tracking & Detection**| Active stop progression | **Working** | Advances to Stop 2 upon Stop 1 completion; finishes on final stop. |
| **Alarms & Alerts** | Dedicated ringtone playback | **Working** | 3 primary original tones + 4 legacy tones; speakerphone routing. |
| **Alarms & Alerts** | Ringtone preview & volume | **Working** | Interactive preview in Settings with volume slider. |
| **Alarms & Alerts** | Tactile vibration patterns | **Working** | Configurable vibration cadences with hardware diagnostic test. |
| **Alarms & Alerts** | Native high-priority notification | **Working** | USAGE_ALARM channel rings even during DND. |
| **Alarms & Alerts** | Snooze & dismiss controls | **Working** | Configurable snooze timer (3–15 min) and persistent stop alert dialog. |
| **Safety & Check-in** | Safety Contacts directory | **Working** | Add/edit/delete contacts, set primary contact. |
| **Safety & Check-in** | Personalized SMS templates | **Working** | Stop name, next stop name, passenger name interpolation. |
| **Safety & Check-in** | Native SMS composer launch | **Working** | Google Play compliant check-in without restricted permissions. |
| **Safety & Check-in** | Direct background SMS | **Working (Restricted)** | Native Kotlin SmsManager with SIM check and carrier receipt. |
| **Diagnostics & QA** | Developer Test Mode | **Working** | Simulates Stop 1 / Stop 2 arrivals through live downstream handler. |
| **Diagnostics & QA** | Telemetry diagnostics screen | **Working** | Live GPS coordinates, horizontal accuracy, fix age, sensor status. |
| **Background / Lifecycle**| Foreground service | **Working** | Android foreground service with persistent status notification. |
| **Background / Lifecycle**| Active session restore | **Partial** | Restores active journey on app resume; lacks `BOOT_COMPLETED` restart. |
| **Offline Capabilities** | Local-first journey logic | **Working** | Core tracking and arrival detection function without internet. |
| **Offline Capabilities** | Map tile offline caching | **Partial** | Tiles load over HTTP; network failure handled gracefully without crash, but no persistent tile cache. |
| **Advanced Travel** | Overshoot / missed-stop detection | **Missing** | To be implemented in Milestone 6. |
| **Advanced Travel** | ETA-based arrival alerts | **Missing** | To be implemented in Milestone 6. |
| **Advanced Travel** | Tunnel dead-zone assistance | **Missing** | To be implemented in Milestone 6. |
| **Advanced Travel** | Recurring commute schedules | **Missing** | To be implemented in Milestone 6. |
| **Audio Enhancements** | Headphone-aware audio routing | **Missing** | To be implemented in Milestone 7. |
| **Audio Enhancements** | Gradual volume ramp-up | **Missing** | To be implemented in Milestone 7. |
| **Safety Escalation** | Multi-tier escalation timer | **Missing** | To be implemented in Milestone 8. |
| **DevOps / CI** | Automated GitHub Actions CI/CD | **Missing** | To be implemented in Milestone 12. |

---

## 5. Android Platform & Configuration Inspection

### 5.1 Android Manifest (`android/app/src/main/AndroidManifest.xml`)
- **Package:** `com.example.pathsaathi`
- **Application Label:** Currently hardcoded as `android:label="YatraSaathi"`. (Target for rebranding: `STOP Vanthachu`).
- **Declared Permissions:**
  - `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`
  - `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION` (Android 14+ requirement)
  - `POST_NOTIFICATIONS` (Android 13+ requirement)
  - `VIBRATE`, `WAKE_LOCK`, `MODIFY_AUDIO_SETTINGS`
  - `SEND_SMS`, `READ_PHONE_STATE` (Used exclusively by Direct SMS in private builds)
- **Service Declarations:**
  - `com.baseflow.geolocator.GeolocatorLocationService` with `android:foregroundServiceType="location"`
- **Intent Queries:**
  - `PROCESS_TEXT`, `android.intent.action.VIEW` (`scheme="sms"`), `android.intent.action.SENDTO` (`scheme="smsto"`).

### 5.2 Gradle & Java Configuration
- **Application ID:** `com.example.pathsaathi`
- **Core Library Desugaring:** Enabled (`com.android.tools:desugar_jdk_libs:2.1.4`) with `JavaVersion.VERSION_17`.
- **Kotlin Target:** JVM 17.

---

## 6. Technical Debt, Security & Privacy Evaluation

1. **Unencrypted Local Storage:** Journey details and emergency contact phone numbers are serialized as plain JSON in `SharedPreferences`. While sandboxed to the application on Android, sensitive contact numbers should eventually leverage encrypted storage.
2. **OpenStreetMap Tile Usage Policy:** `flutter_map` currently fetches tiles directly from `https://tile.openstreetmap.org/`. A custom User-Agent identifying STOP Vanthachu must be strictly supplied to respect OSM Fair Use policies.
3. **Nominatim Geocoding Rate Limits:** The geocoding service contains a 1 req/sec rate limit, but lacks retry backoff on 429/503 responses.
4. **Google Play SMS Policy:** The `SEND_SMS` permission prevents standard publishing on Google Play Store without SMS/Call Log permission declaration exception. The application cleanly isolates Direct SMS behind opt-in consent and provides the native SMS composer as the default compliant path.
5. **No Telemetry Exfiltration:** Verification confirms zero analytics SDKs, zero crash reporters sending location data, and zero external tracking.

---

## 7. Rebranding Requirements for Milestone 1

To transform YatraSaathi into **STOP Vanthachu**:
- **Display Name:** `STOP Vanthachu` across UI and Android Launcher.
- **Tagline:** `Never Miss Your Stop. Travel with Confidence.`
- **Notification Branding:** Channel names and notification summaries rebranded to `STOP Vanthachu`.
- **Default Message Templates:** `... - Sent via STOP Vanthachu`.
- **Technical Identifiers Preserved:**
  - Android package name: `com.example.pathsaathi`
  - MethodChannel: `com.example.pathsaathi/direct_sms`
  - SharedPreferences storage keys: `yatrasaathi_saved_journeys_v1`, etc. (retained to ensure zero data loss on updates).
  - Internal Dart package name: `pathsaathi`.
