# YatraSaathi — LinkedIn Project Launch Kit

This document contains publication-ready LinkedIn launch materials for introducing **YatraSaathi** as a personal mobile engineering project.

---

## 1. Primary LinkedIn Launch Post (Full Technical Showcase)

I often found myself worrying about missing my stop while travelling.

Whether commuting on packed suburban trains, catching a late-night bus after a long day, or navigating unfamiliar transit networks, staying awake and alert just to avoid missing an interchange is exhausting. At the same time, remembering to send a message home upon safe arrival is something easily forgotten in the rush of disembarking.

Most navigation tools demand continuous screen time, drain battery rapidly, and rely heavily on cloud accounts and remote telemetry.

To solve this everyday transit dilemma with clean engineering, I built **YatraSaathi** — an offline-first, GPS-powered journey companion and arrival alert application for Android, built with Flutter and Dart.

---

### What YatraSaathi Does:
- **Multi-Stop Route Planning:** Set intermediate stops and final destinations with custom alert radii (200m to 2km).
- **Interactive OpenStreetMap Integration:** Pinpoint locations visually with pan/zoom and reverse geocoding fallback—no manual coordinate entry needed.
- **Hardware-Level Arrival Ringtones:** Triggers loud alarms routed via Android's `STREAM_ALARM` audio context, cutting through noisy transit even when the device is silenced.
- **Automated Safety Check-Ins:** Automatically prepares personalized check-in messages for designated emergency contacts upon arrival, opening your native SMS client for one-tap dispatch.
- **100% On-Device Privacy:** Zero tracking servers, zero third-party telemetry, and no account requirements. All itineraries and contacts stay in private local storage.

---

### Key Engineering Challenges & Architecture:
Building an arrival detection engine that performs reliably in moving transit required solving several subtle technical hurdles:

1. **Filtering GPS Sensor Noise:**
   Raw mobile GPS readings in transit fluctuate heavily near high-rises and railway overhead wiring. I implemented accuracy gating that discards readings with horizontal uncertainty $> 65\text{ m}$, preventing erratic false alarms while miles away from the station.

2. **Dwell-Time & Multi-Sample Validation:**
   Passing near a station on an express route shouldn't trigger an arrival alert. The detection engine requires consecutive validated readings inside the radius combined with minimum dwell-time verification ($4\text{s}$ to $10\text{s}$) before confirming arrival.

3. **Background Reliability on Modern Android:**
   To keep monitoring while the device screen is off, YatraSaathi utilizes an Android Foreground Service (`FOREGROUND_SERVICE_LOCATION`) paired with a high-priority notification channel and wake locks for reliable execution across Android 10 through Android 14+.

4. **Telephony Compliance:**
   To respect user autonomy and comply with Google Play permissions policies, the app uses a native SMS intent workflow as its default, ensuring users retain full control over messages leaving their device.

---

### Verification & Testing:
Engineering reliability was the primary goal from day one:
- **Static Analysis:** `flutter analyze` passes with **0 issues found**.
- **Automated Test Suite:** **90 / 90 tests passing** across unit, widget, and end-to-end integration test suites covering Haversine calculations, state machines, audio previews, and edge-case GPS drift.
- **Hardware Validated:** Debugged and tested on physical Android devices.

---

### Explore the Code:
The complete codebase, documentation, and architecture audits are open source under the MIT License on GitHub:
👉 https://github.com/rohitam26/YatraSaathi-

I would love to hear feedback, architectural suggestions, or contributions from fellow mobile engineers and Flutter enthusiasts!

#Flutter #Dart #AndroidDevelopment #GPS #MobileAppDevelopment #SoftwareEngineering #BuildInPublic

---

## 2. Short Alternative Version (Concise & Fast-Paced)

I often found myself worrying about missing my stop while travelling—especially on long bus and train journeys where staying glued to a screen isn't practical.

To solve this, I designed and built **YatraSaathi**: an offline-first, GPS-powered arrival alarm and safety check-in companion for Android (built with Flutter & Dart).

### Key Features:
📍 Multi-stop route planning with interactive OpenStreetMap pin-picking.  
🔔 Dedicated transit alarm system using Android `STREAM_ALARM` to cut through noisy transit environments even in silent mode.  
🛡️ Safety check-in workflow preparing one-tap SMS messages to family upon arrival.  
🔒 Privacy-first: 100% on-device GPS processing with zero remote telemetry or cloud databases.  

### Engineering Highlights:
- Spherical Haversine distance tracking with dynamic GPS accuracy filtering ($< 65\text{ m}$).
- Multi-sample dwell-time verification to prevent false arrival triggers on express trains.
- Android foreground service integration for reliable background operation with the screen off.
- 90/90 passing automated tests and clean `flutter analyze` score.

Check out the full repository and architecture details on GitHub:
👉 https://github.com/rohitam26/YatraSaathi-

Feedback and thoughts are welcome!

#Flutter #Dart #AndroidDevelopment #MobileAppDevelopment #SoftwareEngineering #BuildInPublic

---

## 3. Recommended LinkedIn Image Carousel / Document Sequence

If publishing as a multi-slide PDF document or image gallery (which typically achieves 2-3x higher engagement on LinkedIn), organize slides in this order:

- **Slide 1: Title & Hero Banner**
  - Text: *YatraSaathi — Never Miss Your Transit Stop Again*
  - Visual: Mockup or collage of Home Dashboard & Active Tracking view.
  - Subtitle: *An offline-first GPS journey companion built with Flutter & Dart.*

- **Slide 2: The Everyday Transit Problem**
  - Bullet points: Distractions during transit, fear of oversleeping, battery drain from active GPS maps, forgetting arrival check-ins.

- **Slide 3: Core Capabilities & Architecture**
  - Diagram: GPS Input $\rightarrow$ Accuracy Filter ($< 65\text{m}$) $\rightarrow$ Dwell Verification $\rightarrow$ `STREAM_ALARM` Audio $\rightarrow$ Native SMS Intent.

- **Slide 4: Interactive Route & Map Picker**
  - Screenshot: `02-journey-creation.png` & `03-map-picker.png`.
  - Highlight: OpenStreetMap integration with zoom, pan, and geocoding search.

- **Slide 5: Arrival Alerts & Ringtone Previews**
  - Screenshot: `05-arrival-alert.png` & `07-ringtone-selection.png`.
  - Highlight: Android alarm stream audio with 3 original local ringtones and snooze controls.

- **Slide 6: Verification, Privacy & Open Source**
  - Metric badges: 90/90 tests passing • 0 Analyzer warnings • 100% on-device processing • MIT Licensed.
  - Link: `github.com/rohitam26/YatraSaathi-`.

---

## 4. Suggested First Comment

Post this immediately after publishing the post to provide direct links without hurting LinkedIn feed algorithm reach:

> 🔗 **GitHub Repository:**  
> Check out the open-source code, test suites, and setup guide here:  
> https://github.com/rohitam26/YatraSaathi-  
>  
> The project includes 90 automated tests covering state machines, geocoding fallbacks, and GPS noise filtering. Feel free to star the repo ⭐ or open an issue if you have suggestions!
