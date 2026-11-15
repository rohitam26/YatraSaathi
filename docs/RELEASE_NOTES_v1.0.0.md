# YatraSaathi v1.0.0 — Initial Stable Release Notes

**Release Version:** `v1.0.0`  
**Target Platform:** Android (API level 26 through API 35+)  
**Build Artifact:** `app-release.apk` (55.93 MB / 58,646,203 bytes)  
**SHA-256 Checksum:** `979FD63D949ED95CA04C139E8319CDDE94CF2147EEC1C1BD33FAD75BB4014EA2`  
**Licence:** MIT License (Copyright (c) 2026 Rohita)  
**Repository:** [https://github.com/rohitam26/YatraSaathi-](https://github.com/rohitam26/YatraSaathi-)

---

## 1. Release Overview

YatraSaathi v1.0.0 represents the first production-ready, stable release of the multi-stop journey companion and arrival alert application. Built with Flutter, YatraSaathi is designed to give commuters and long-distance travellers peace of mind by preventing missed transit stops through high-priority audible alarms, interactive OpenStreetMap route planning, and privacy-first safety check-in messaging.

---

## 2. Key Features Included in v1.0.0

### Multi-Stop Journey Planning & Interactive Map
- **OpenStreetMap Location Picker:** Visual destination selection with interactive map panning, zooming, draggable pin placement, and search functionality.
- **Geocoding & Offline Fallback:** Integrated place search powered by Komoot Photon with automatic OpenStreetMap Nominatim reverse geocoding and graceful offline fallback handling.
- **Configurable Stop Radii:** Custom alert radius selection per stop ($200\text{ m}$, $500\text{ m}$, $1\text{ km}$, $2\text{ km}$).
- **Stop Organization:** Dynamic stop reordering and customizable stop-specific alarm/contact overrides.

### Deterministic GPS Arrival Detection Engine
- **Spherical Haversine Distance Engine:** Accurate real-time proximity calculation between live GPS coordinates and destination targets.
- **GPS Noise & Accuracy Filtering:** Rejection of low-confidence location samples (horizontal accuracy $> 65\text{ m}$) to prevent false alarms near tall buildings or railway power infrastructure.
- **Dwell-Time & Multi-Sample Gating:** Minimum consecutive fix requirements ($2$ to $3$ readings) and dwell thresholds ($4\text{s}$ to $10\text{s}$) to avoid false triggers while passing stations on express trains.
- **Duplicate Alert Suppression:** Internal latching prevents repeat alarms for the same stop.

### High-Priority Audio Ringtone System
- **Android `STREAM_ALARM` Context:** Audio playback configured specifically to route through device speakers and alert the user even in noisy transit or silent mode.
- **Original Packaged Ringtones:** Includes 3 local `.wav` ringtone compositions:
  - *Classic Ring* (dual-frequency telephone bell cadence)
  - *Urgent Arrival Alarm* (rapid siren pulses for loud transit)
  - *Gentle Chime* (soothing pentatonic arpeggio)
- **Instant Auditioning:** In-app play/pause preview with a dedicated volume slider.
- **Full-Screen Alert Modal:** Displays repeating alarm animation, Snooze ($5\text{ min}$), and Dismiss controls.

### Passenger Safety Profile & Check-In Workflows
- **Emergency Contact Management:** Manage multiple contacts with relationship tags (Parent, Partner, Sibling, Friend).
- **Native SMS Intent Workflow (Play Store Compliant):** Pre-fills the native Android SMS client with the contact number and safe arrival text upon reaching destinations.
- **Direct SMS Sideload Mode (Optional):** Supports background SMS dispatch via Android `SmsManager` for private, self-compiled builds when explicit runtime permissions (`SEND_SMS`) are granted by the user.

---

## 3. Technology Stack & Dependencies

- **Framework:** Flutter `3.47.8` (Dart SDK `3.13.7`)
- **Android Target:** Android SDK 34 / Java OpenJDK 25.0.3
- **Location Services:** `geolocator ^13.0.2` with foreground service integration
- **Mapping:** `flutter_map ^7.0.2`, `latlong2 ^0.9.1`, `http ^1.2.2`
- **Audio & Haptics:** `audioplayers ^6.1.0`, `vibration ^2.1.0`
- **Notifications:** `flutter_local_notifications ^18.0.1`
- **Local Persistence:** `shared_preferences ^2.5.6`
- **Intents:** `url_launcher ^6.3.1`

---

## 4. Verification & Quality Assurance

- **Static Analysis:** `flutter analyze` reports **0 issues found** (0 errors, 0 warnings, 0 linter issues).
- **Automated Test Suite:** **90 / 90 tests passed** (`flutter test`) across model persistence, arrival detection rules, ringtone auditioning, SMS dispatch fallbacks, and UI flows.
- **Compilation:** Clean production release APK built using Gradle `assembleRelease` with icon tree-shaking and resource optimization.

---

## 5. Installation Instructions

### Installing the APK on Android
1. Download `app-release.apk` from the GitHub Release assets.
2. Open the downloaded file on your Android device.
3. If prompted, permit your browser or file manager to "Install unknown apps".
4. Follow the system prompt to complete installation.
5. On first launch, follow the onboarding guide to grant Location and Notification permissions.

---

## 6. Known Verified Limitations

- **Map Tile Caching:** Map tiles require an active internet connection to download initially. While cached tiles remain accessible, full offline browsing requires prior tile caching.
- **GPS Satellite Acquisition:** Cold-start GPS locks indoors or inside underground metro tunnels may take additional time until line-of-sight satellite fixes are acquired.
- **Google Play SMS Telephony Policy:** Direct background SMS sending requires the user to manually send via their native SMS client on standard builds to comply with Google Play permissions guidelines. Direct `SmsManager` execution is reserved for private/sideload builds.

---

## 7. Licensing & Attribution

YatraSaathi is free and open-source software distributed under the terms of the **MIT License** (`Copyright (c) 2026 Rohita`). Map data is provided courtesy of © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors.
