# STOP Vanthachu — Strategic Engineering Roadmap

**Project:** STOP Vanthachu  
**Tagline:** Never Miss Your Stop. Travel with Confidence.  
**Version:** 1.0.0 (Current Release)  
**Target:** 2026–2027 Evolution

---

## 1. Release Milestone Map

```mermaid
timeline
    title STOP Vanthachu Strategic Release Roadmap
    v1.0.0 (Completed) : Complete Rebranding to STOP Vanthachu
                       : 10 Deterministic Arrival Rules
                       : Foreground Service & Auto-Recovery
                       : Adaptive GPS Polling Policy
                       : 32-Hub Offline Station Database
                       : Dead-Reckoning & Smoothed ETA
                       : Gentle Wake Volume Ramp-Up
                       : Multi-Tier Emergency SOS Escalation
                       : 134 Automated Tests Passing
    v1.1.0 (Q1 2027)   : Multi-Lingual Regional Audio (Tamil, Hindi, Telugu, Kannada)
                       : Offline Vector Tile Bundles (.mbtiles)
                       : BLE Beacon Support for Metro Platforms
    v1.2.0 (Q2 2027)   : GTFS Static Timetable Integration
                       : Automatic Commute Alarm Auto-Start
                       : Wear OS Companion App & Wrist Haptics
    v2.0.0 (Q3 2027)   : Full iOS Parity (CoreLocation & Live Activities)
                       : On-Device Voice Announcements
                       : Inter-City Coach Route Community Database
```

---

## 2. Release Objectives & Technical Scope

### 2.1 Version 1.1.0 — Multilingual Announcements & Offline Vector Maps
- **Regional Voice Announcements:** Synthesize arrival announcements in regional languages (Tamil, Hindi, Telugu, Kannada, Malayalam, Marathi, Bengali) using offline Android TTS engines.
- **Offline Vector Tile Support:** Package `.mbtiles` vector packages for popular Indian railway and suburban metro networks, completely eliminating network tile downloads during long journeys.
- **Underground BLE Beacon Positioning:** Integrate Bluetooth Low Energy (BLE) scanning for major underground metro networks (Chennai Metro, Delhi Metro, Namma Metro) to maintain 100% position accuracy even deep underground.

### 2.2 Version 1.2.0 — GTFS Timetables & Wear OS Companion
- **GTFS Static Schedule Integration:** Import open GTFS transit schedules to cross-reference physical GPS arrival with scheduled timetable stops.
- **Automated Commute Activation:** Automatically prompt the user to start tracking their daily commute based on time of day and departure location proximity.
- **Wear OS Smartwatch Companion:** Display live distance countdown and deliver high-priority wrist vibration patterns directly on Android Wear smartwatches.

### 2.3 Version 2.0.0 — iOS Parity & Cross-Platform Transit Community
- **iOS Platform Release:** Port background location architecture to Apple's `CoreLocation` framework with support for iOS Dynamic Island and Live Activities.
- **Crowd-Curated Transit Geofences:** Allow users to export and share validated station geofences via encrypted QR codes or peer-to-peer Wi-Fi Direct without centralized servers.
