# YatraSaathi

> **Your journey. Your check-ins. Your peace of mind.**

YatraSaathi is a local-first, privacy-focused multi-stop transit companion for Android. It ensures that commuters and long-distance travelers never miss their transit stops by monitoring real-time GPS progress, filtering out sensor noise, triggering loud audible and tactile alarms, and opening native SMS check-in messages to reassure loved ones.

---

## Key Features

1. **Multi-Stop Journey Planning:**
   - Create journeys with custom names, descriptions, intermediate transit stops, and a final destination.
   - Configure individual arrival radii (default 500m) for each stop.
   - Reorder, edit, and delete stops dynamically with automatic sequential index management.

2. **Deterministic GPS Arrival Detection:**
   - Mathematical Haversine spherical distance calculation.
   - Rejects stale GPS samples (\(>45\text{s}\)) and noisy fixes (\(>50\text{m}\) accuracy error).
   - Requires multiple consecutive consistent observations (\(\ge 3\) readings) within the radius.
   - Enforces a minimum station dwell period (\(\ge 10\text{s}\)) to differentiate actual stops from express transit fly-bys.
   - Suppresses duplicate arrival alarms for the same stop.

3. **Background Tracking on Android:**
   - Runs as an Android Foreground Service with a persistent status bar notification (`foregroundServiceType="location"`).
   - Continues monitoring when the screen is locked, the application is minimized, or another app is in use.

4. **Multi-Stop Alarm System:**
   - Per-stop alarm configuration (audible chime selection, tactile vibration pulses).
   - Repeat count and repeat interval timers.
   - Interactive Snooze and Dismiss actions.

5. **Compliant Contact Check-In Messaging:**
   - Per-stop contact name, phone number, and customizable arrival messages.
   - Complies fully with Google Play SMS policies: opens Android's native SMS composer prefilled with recipient and message, leaving final delivery confirmation in user control.
   - Honest status logging (`COMPOSER_OPENED`, not `SENT_CONFIRMED`) and automatic phone number masking (`***-***-1234`).

6. **On-Device ML Arrival Confidence:**
   - Evaluates 8 kinematic and geospatial features: distance ratio, GPS accuracy, sample freshness, vehicle speed, consecutive sample ratio, dwell ratio, speed stability, and convergence rate.
   - Generates an interpretable probability score (\(0.0 \dots 1.0\)) with transparent reasoning.
   - Pure Dart offline inference with automatic rule-based fallback.

7. **100% Offline & Privacy-First:**
   - Zero remote servers, zero cloud databases, zero telemetry, zero analytics, zero user logins.
   - Private local data storage via `SharedPreferences`.

---

## Project Structure

```
pathsaathi/
├── android/                   # Android native configuration, manifest & Gradle scripts
├── lib/
│   ├── main.dart             # App entrypoint & Home Dashboard
│   ├── models/
│   │   ├── alarm_config.dart
│   │   ├── arrival_event.dart
│   │   ├── contact_checkin_config.dart
│   │   ├── gps_reading.dart
│   │   ├── journey.dart
│   │   └── stop.dart
│   ├── services/
│   │   ├── alarm_service.dart
│   │   ├── arrival_confidence_ml.dart
│   │   ├── arrival_detector.dart
│   │   ├── distance_calculator.dart
│   │   ├── journey_repository.dart
│   │   ├── journey_tracking_service.dart
│   │   ├── location_service.dart
│   │   └── messaging_service.dart
│   └── ui/
│       ├── active_journey_screen.dart
│       ├── arrival_alert_dialog.dart
│       ├── journey_completion_screen.dart
│       ├── journey_planner_screen.dart
│       ├── permission_guidance_screen.dart
│       ├── privacy_info_screen.dart
│       ├── saved_journeys_screen.dart
│       ├── settings_screen.dart
│       └── stop_config_dialog.dart
├── ml/
│   ├── README.md             # ML pipeline documentation & evaluation report
│   ├── model_weights.json    # Exported model weights and bias
│   └── train_arrival_model.py# Reproducible Python training script
├── test/                     # 51 unit, repository, widget, and integration tests
├── pubspec.yaml              # Flutter dependencies and assets
├── ARCHITECTURE.md           # Full architectural specification & state diagrams
├── PROJECT_AUDIT.md          # Complete technical audit report
├── IMPLEMENTATION_STATUS.md  # Detailed feature matrix & completion records
├── TESTING_REPORT.md         # Comprehensive test results breakdown
├── PRIVACY.md                # Privacy and security audit documentation
└── ANDROID_SETUP.md          # Android SDK, Gradle, and release deployment instructions
```

---

## Getting Started

### 1. Run Automated Tests
```powershell
flutter test
```
All 51 automated tests covering distance calculations, models, persistence, arrival detection, ML confidence, messaging, tracking state machines, and UI widgets will execute and pass.

### 2. Run Static Analysis
```powershell
flutter analyze
```
Verifies 0 errors, 0 warnings, and 0 lints across the entire codebase.

### 3. Build the Android APK
```powershell
flutter build apk --debug
```

### 4. Install APK on Android Device
```powershell
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```
