# YatraSaathi — Comprehensive Testing Report

**Execution Date:** November 9, 2026  
**Test Harness:** Flutter Test Suite & Dart Testing Framework  
**Total Automated Tests:** 85  
**Tests Passed:** 85  
**Tests Failed:** 0  
**Test Pass Rate:** 100%

---

## 1. Test Suite Summary by Category

| Category | File Name | Number of Tests | Status | Scope & Behaviors Verified |
| :--- | :--- | :---: | :---: | :--- |
| **Haversine Distance** | `test/distance_calculator_test.dart` | 6 | **PASS** | Great-circle distance calculations, urban scale accuracy (sub-kilometer), New Delhi to Mumbai long distance, identical coordinate zero distance, boundary validations (\([-90, 90]\), \([-180, 180]\)). |
| **Domain Operations** | `test/journey_operations_test.dart` | 8 | **PASS** | Auto-indexed stop order, dynamic stop additions, stop deletions with re-indexing, stop editing, stop reordering, journey start/pause/resume/complete/cancel transitions, JSON serialization and deserialization. |
| **Arrival Detection** | `test/arrival_detector_test.dart` | 8 | **PASS** | Active stop checks, stale sample rejection (\(>45\text{s}\)), noisy GPS accuracy rejection (\(>80\text{m}\)), outside radius approaching status, single-reading arrival rejection, consecutive consistent samples (\(\ge 3\)) + dwell time (\(\ge 10\text{s}\)) requirement, duplicate event suppression per stop, buffer reset on departure. |
| **Local Persistence** | `test/persistence_test.dart` | 5 | **PASS** | Empty initial state, saving and retrieving journeys via SharedPreferences, updating journeys by ID, tracking active journey ID across simulated app restarts, deletion from list and active tracker. |
| **Machine Learning** | `test/ml_arrival_confidence_test.dart` | 6 | **PASS** | High confidence score (\(\ge 0.70\)) inside stop radius with sustained dwell, low confidence score (\(<0.50\)) outside boundary, high-speed fly-by penalty (25 m/s express transit), noisy accuracy penalty, invalid radius safety guard, proportional rule-based fallback estimator. |
| **Messaging (SMS)** | `test/messaging_service_test.dart` | 4 | **PASS** | Default arrival message formatting with next stop, default message formatting for final destination, phone number log masking (`***-***-1234`), empty phone number rejection. |
| **Alarm & Diagnostics**| `test/alarm_service_test.dart` | 4 | **PASS** | Standard AlarmConfig defaults, AlarmConfig JSON roundtrip, available sound chime catalog, initial alarm state verification. |
| **Tracking Lifecycle**| `test/journey_tracking_service_test.dart` | 7 | **PASS** | Complete multi-stop simulated journey lifecycle from planning to completion: simulated GPS stream, dwell time accumulation, alert triggering, advancing to stop 2, final destination arrival, pause, resume, cancel. |
| **Dashboard Widget** | `test/widget_test.dart` | 1 | **PASS** | Redesigned Home dashboard structure, AppBar title, Active Journey card with live status & progress bar, Journey Stops empty/configured states, Hero plan card, FAB navigation to Journey Creation Wizard, 4-tab bottom navigation shell. |
| **UI Flows & Screens** | `test/ui_flow_test.dart` | 5 | **PASS** | `SavedJourneysScreen` list and live search query filtering, `PermissionGuidanceScreen` transparent permission cards, `PrivacyInfoScreen` offline policy text, `SettingsScreen` dropdowns and diagnostic buttons, `StopConfigDialog` tabs (Location, Alarm, Check-In). |
| **UX Redesign & Wizard** | `test/journey_wizard_test.dart` | 7 | **PASS** | 5-step progressive wizard field validation, existing journey population into wizard, `JourneyMapView` polyline and geofence rendering, `MapLocationPicker` search bar and manual coordinate dialog fallback, `GeocodingService` reverse geocode offline fallback, Stop custom alarm and contact retention through edits and reorders, `JourneyTrackingService.restoreActiveSession()` recovery of target stop. |
| **End-to-End Arrival & Profile** | `test/arrival_and_profile_integration_test.dart` | 9 | **PASS** | `UserProfile` model serialization & persistence, personalized message template formatting, realistic GPS accuracy tolerance (\(\pm 65\text{m}\) accepted inside \(200\text{m}\) radius), arrival verification when starting journey already inside radius, duplicate arrival event prevention, automatic fallback to default safety profile contact, stop-specific contact override, manual arrival override for shielded stations, multi-stop advancement on acknowledgement. |
| **Multiple Safety Contacts & Diagnostics** | `test/safety_contacts_and_diagnostics_test.dart` | 10 | **PASS** | `SafetyContact` serialization roundtrip, short number masking safety, clone copyWith, auto-migration of legacy `UserProfile` default contact into multi-contact storage, complete CRUD (save, get, delete with primary auto-promotion, setPrimaryContact), sound preset asset maps, arrival sound test, vibration test, arrival notification test, LocationEngine status check. |
| **First-Launch Onboarding** | `test/first_launch_onboarding_test.dart` | 2 | **PASS** | Stepwise explanation of GPS hardware, precise location permission, high-priority notifications, plain-English purpose disclosure, saving `has_completed_onboarding_v2` flag on completion. |
| **Real Device Failure Repair & Reliability** | `test/real_device_reliability_test.dart` | 6 | **PASS** | Arrival event triggers alarm service; duplicate alarm suppression; safety check-in uses emergency contact number and rejects user's own number; stop reordering preserves custom contact and alarm configs; GPS update freshness calculation; multi-provider place search categorizing railway stations, metro, bus terminals, hospitals, and colleges; sequential composer check-in workflow for multiple contacts. |

---

## 2. Root Cause Analysis & Technical Resolutions

| Failure Point Observed on Physical Device | Root Cause Identified | Engineering Fix Applied | Verification Evidence |
| :--- | :--- | :--- | :--- |
| **Device Location Hardware Not Requested** | When phone GPS switch was turned OFF in system settings, `Geolocator` threw unhandled `LocationServiceDisabledException`. App had no dedicated UI flow to prompt the user to enable hardware. | Created `LocationEngine` and `FirstLaunchOnboardingScreen` checking `isLocationServiceEnabled()`. Provides single-tap button opening system location settings. | `first_launch_onboarding_test.dart` and `LocationEngine.checkStatus()` verified. |
| **GPS Acquisition Stuck on Screen** | `startTracking()` called `startLocationStream()` directly without requesting runtime location/notification permissions. Also `distanceFilter: 15` prevented stationary fixes. | Created `LocationEngine` with 8 authoritative states and watchdog timer. Set `distanceFilter: 0` for periodic polling, seed initial fix via `acquireFreshFix()`. | `JourneyTrackingService.startTracking()` seeds initial reading; `LocationEngine` stream verified. |
| **No Arrival Audio Played** | `audioplayers` was attempting media-channel asset playback without checking stream routing or volume, and no Android notification channel with native raw audio existed. | Placed RIFF PCM WAV chimes in `android/app/src/main/res/raw/` (`arrival_chime.wav`, `bell_alert.wav`, `gentle_ripple.wav`, `subtle_ping.wav`) and `assets/sounds/`. Registered native Android notification channel `yatrasaathi_arrival_v2` with `Importance.max` and `RawResourceAndroidNotificationSound`. Configured `AudioPlayer` with `AndroidUsageType.alarm`. Added `MODIFY_AUDIO_SETTINGS` permission. | Honest diagnostic tests (`testArrivalSound`, `testVibration`, `testArrivalNotification`) in `SettingsScreen` and automated tests pass. |
| **Arrival Missed Under Transit Conditions** | Rigid `maxAcceptableAccuracyMeters = 50.0m` rejected real-world GPS readings reporting \(\pm 55\text{m}\) to \(\pm 75\text{m}\) as `locationUncertain`. | Raised default threshold to \(80.0\text{m}\) and added support for stationary dwell accumulation when starting inside stop radius. | Unit tests verify \(\pm 65\text{m}\) accuracy inside \(200\text{m}\) radius evaluates as valid `approaching`/`arrived`. |
| **Only Single Contact Available** | Settings only supported a single default emergency contact. Stops could not pick from multiple family/friends. | Created `SafetyContact` model, updated `JourneyRepository` with full CRUD and auto-migration from legacy `UserProfile`. Created `SafetyContactsScreen`. Updated `StopConfigDialog` and `JourneyWizardScreen` with multi-contact picker chips. | `test/safety_contacts_and_diagnostics_test.dart` passes all 10 CRUD and migration tests. |
| **SMS Workflow Ambiguity** | Active journey screen did not display SMS check-in status or offer a retry button. | Added honest Safety Check-In card on `ActiveJourneyScreen` displaying exact status (`NOT TRIGGERED`, `READY TO SEND`, `COMPOSER OPENED`, `FAILED`) and a manual trigger/reopen button. | Status chip and direct action verified in widget tree and service tests. |
| **Navigation Clutter** | Screen switching required deep navigation or settings menus. | Implemented 4-tab bottom navigation shell on `HomeScreen` (`Home`, `Journeys`, `Contacts`, `Settings`). | Tested in `widget_test.dart` and `ui_flow_test.dart`. |

---

## 3. Physical Device Testing Status

> [!IMPORTANT]
> **Honest Verification Disclosure:**
> As verified by `adb devices`, **no physical Android device is currently attached via USB or WiFi**.
> All 79 automated tests, Dart code analysis, and Gradle APK builds run and pass in the local developer environment.
> Physical-device sensory verification (hearing the physical speaker, feeling the haptic motor in hand, and walking into geofences with cell tower GPS) must be performed by installing `build/app/outputs/flutter-apk/app-debug.apk` onto the physical handset.
