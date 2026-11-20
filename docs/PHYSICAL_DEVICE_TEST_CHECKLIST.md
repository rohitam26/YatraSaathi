# STOP Vanthachu — Physical Device Field Testing Protocol & Checklist

> **Document Type:** Field Quality Assurance & Physical Hardware Verification Protocol  
> **Target Application:** STOP Vanthachu (`com.example.pathsaathi`)  
> **Minimum Supported OS:** Android 8.0 (Oreo, API 26)  
> **Target Tested OS:** Android 13 (Tiramisu), Android 14 (Upside Down Cake), Android 15 (Vanilla Ice Cream)  
> **Recommended Test Hardware:** At least one Stock Android device (Pixel/Motorola) and at least one OEM device with aggressive memory management (Samsung Galaxy, Xiaomi Redmi/POCO, OnePlus/OPPO).

---

## 1. Overview and Objectives

Automated unit tests and simulated GPS feeds verify algorithmic correctness, state machine transitions, and error handling. However, travel safety applications depend on physical realities:
1. Real satellite triangulation in urban canyons and tunnels.
2. OEM proprietary power management daemon kill policies.
3. Android audio stream routing under hardware headphone jacks and Bluetooth profiles.
4. Physical cellular SIM radio readiness and SMS carrier dispatch.

This protocol provides a reproducible, step-by-step testing sequence that field QA engineers must execute on physical hardware before certifying STOP Vanthachu for **Classification A (Production-Ready)**.

---

## 2. Field Test Checklist Summary

| Test ID | Test Category | Target Condition | Success Criteria | Field Result |
|:---:|---|---|---|:---:|
| **TC-01** | **Screen-Locked Transit** | Physical bus or train commute ($>5\text{ km}$) with screen locked | Arrival alarm rings at target stop within configured radius | [ ] PASS / [ ] FAIL |
| **TC-02** | **Audio Routing (Headphones)** | Wired 3.5mm jack or Bluetooth earbuds active | Alarm sounds through phone loudspeaker (`STREAM_ALARM`) | [ ] PASS / [ ] FAIL |
| **TC-03** | **Silent & DND Override** | Device ringer in Silent mode and DND active | Alarm sounds loudly over internal speaker | [ ] PASS / [ ] FAIL |
| **TC-04** | **Tunnel Dead Reckoning** | Railway tunnel / subway underground passage ($>30\text{s}$) | Proximity continues updating via dead reckoning; no false alarm | [ ] PASS / [ ] FAIL |
| **TC-05** | **Process Kill & Cold Restore** | Swipe away from Recent Apps drawer while tracking | Reopening app restores active journey and resume tracking | [ ] PASS / [ ] FAIL |
| **TC-06** | **Battery Consumption** | 2-hour intercity transit with adaptive polling | Battery drain $< 4\%$ per hour on modern battery | [ ] PASS / [ ] FAIL |
| **TC-07** | **Emergency Escalation** | Alarm left unacknowledged for 180 seconds | Countdown banner elapses and initiates emergency dispatch | [ ] PASS / [ ] FAIL |
| **TC-08** | **OEM Background Killer** | Samsung One UI or Xiaomi HyperOS device ($>30\text{ min}$) | Foreground service remains active; notification persists | [ ] PASS / [ ] FAIL |
| **TC-09** | **Emergency SOS & Countdown** | Press SOS button in active tracking screen | 5s countdown modal displays with cancel option; confirms dispatch | [ ] PASS / [ ] FAIL |
| **TC-10** | **GPS Nearest Station** | Open app in Guindy, Tambaram, or outside transit zone | Shows genuine proximity & distance; never false-claims "Near Central" | [ ] PASS / [ ] FAIL |
| **TC-11** | **WhatsApp Contact Validation** | Input 10-digit Indian numbers with or without +91 / 0 | Format accepted without false "not registered on WhatsApp" error | [ ] PASS / [ ] FAIL |
| **TC-12** | **Offline Map & Airplane Mode** | View journey map and switch to Airplane Mode | Cached tiles render smoothly without blank grids or app crashes | [ ] PASS / [ ] FAIL |

---

## 3. Step-by-Step Test Execution Procedures

### Test Case 01: Screen-Locked Transit Journey
- **Purpose:** Verify that `GeolocatorLocationService`, Android Foreground Service, and `WAKE_LOCK` maintain tracking and wake the display upon arrival.
- **Pre-Conditions:**
  1. Install release APK (`app-release.apk`) on test phone.
  2. Grant **Location** ("Allow all the time") and **Notifications** permissions.
  3. Plan a journey with a stop set to your real destination (e.g. radius: 500m).
- **Execution Steps:**
  1. Start tracking the journey on the phone.
  2. Verify ongoing notification appears in Android notification shade: *"STOP Vanthachu Journey Active"*.
  3. Lock the phone (screen black). Place phone in pocket or bag.
  4. Travel to destination via bus, train, or car.
- **Pass Criteria:**
  - Upon crossing the 500m radius and dwelling for $>4$ seconds, phone vibrates and plays the selected ringtone at full volume.
  - Screen wakes up, displaying the full-screen `ArrivalAlertDialog` modal with Snooze and Dismiss buttons.

---

### Test Case 02: Audio Routing with Headphones (Loudspeaker Priority)
- **Purpose:** Ensure a sleeping passenger wearing headphones still hears the alarm through the phone's primary loudspeaker.
- **Pre-Conditions:**
  1. Connect wired 3.5mm earphones or pair Bluetooth earbuds (e.g., Galaxy Buds, AirPods).
  2. Start music playback to verify headphones receive audio.
- **Execution Steps:**
  1. Open STOP Vanthachu &rarr; **Settings** &rarr; **Arrival Ringtone**.
  2. Tap "Preview" on **Classic Ring** or **Urgent Arrival Alarm**.
  3. Observe audio output source.
  4. Trigger a simulated arrival or physical arrival.
- **Pass Criteria:**
  - The arrival alarm sounds loudly from the **built-in phone loudspeaker** (via `isSpeakerphoneOn: true` and `STREAM_ALARM`).
  - Audio also routes to headphones if OEM supports dual output, but must never be trapped exclusively in quiet earbuds.

---

### Test Case 03: Silent Mode and Do Not Disturb (DND) Override
- **Purpose:** Ensure alarm sounds when traveler puts phone on silent mode before sleeping.
- **Execution Steps:**
  1. Toggle Android volume slider to **Silent** (or Vibrate).
  2. Turn on system **Do Not Disturb (DND)** mode.
  3. Verify phone does not make notification sounds for regular incoming texts.
  4. In STOP Vanthachu, trigger ringtone preview or test arrival.
- **Pass Criteria:**
  - Ringtone sounds at configured alarm volume through phone speaker.
  - *Note:* If the user has explicitly selected "Block alarms" in custom OEM DND settings, note whether the OS policy silences the audio.

---

### Test Case 04: Tunnel and Cellular Dead Zone (Dead Reckoning)
- **Purpose:** Validate that GPS satellite loss in underground metro or railway tunnels does not trigger false alerts or crash the tracking state.
- **Execution Steps:**
  1. Board an underground metro or enter a known mountain/railway tunnel.
  2. Monitor the Active Journey screen.
  3. When GPS satellites drop out (GPS icon turns yellow/amber), observe the telemetry banner.
- **Pass Criteria:**
  - Telemetry badge displays `"Dead Reckoning (Tunnel Mode)"`.
  - Vehicle position projects smoothly along the entry velocity vector for up to 180 seconds.
  - Proximity distance estimates update without jumping erratically.
  - **No false arrival alarm triggers** while `isDeadReckoning: true`.
  - When vehicle exits tunnel and acquires valid GPS lock, system smoothly reconciles position.

---

### Test Case 05: Process Death & Swipe-Away Recovery
- **Purpose:** Verify zero state loss when OS memory pressure terminates the process or user accidentally swipes app away.
- **Execution Steps:**
  1. Start an active multi-stop journey.
  2. Advance past stop 1 so stop 2 is active.
  3. Swipe STOP Vanthachu away from Android's Recent Apps switcher (force task kill).
  4. Re-open STOP Vanthachu by tapping the app icon from the home screen.
- **Pass Criteria:**
  - App displays recovery notification or automatically re-opens `ActiveJourneyScreen`.
  - Journey name, current active stop (Stop 2), alerted history, and target coordinates are completely restored without user re-entry.

---

### Test Case 06: Battery Consumption Profiling
- **Purpose:** Validate adaptive polling duty-cycle efficiency on physical hardware.
- **Execution Steps:**
  1. Fully charge test device to 100%.
  2. Start an active intercity journey with distance $>30\text{ km}$.
  3. Lock device and travel for 2 continuous hours.
  4. Check Android Settings &rarr; **Battery** &rarr; **Battery Usage**.
  5. Inspect dump via ADB: `adb shell dumpsys batterystats com.example.pathsaathi`.
- **Pass Criteria:**
  - Total battery consumed by STOP Vanthachu is $< 4\%$ per hour of active cruising.
  - Adaptive polling interval relaxes to $60\text{s}$ during cruising and accelerates to $3\text{s}$ within $2\text{ km}$ of destination.

---

### Test Case 07: Multi-Tier Emergency Escalation Workflow
- **Purpose:** Verify that unattended arrival alerts escalate safely to emergency contacts.
- **Pre-Conditions:**
  1. Configure an Emergency Contact with a real secondary test phone number.
  2. Enable Emergency Escalation in Settings (180s countdown).
- **Execution Steps:**
  1. Trigger arrival at destination stop.
  2. Do NOT dismiss or snooze the alarm. Leave phone on the table.
  3. Observe countdown banner: `"Emergency check-in dispatching in 180s... [Cancel]"`.
  4. Allow timer to expire.
- **Pass Criteria:**
  - At $t = 0\text{s}$, native SMS client opens with pre-populated emergency text (or direct SMS sends if opted in on developer build).
  - Passenger's own phone receives confirmation toast or notification.
  - Secondary phone receives check-in SMS containing station name and arrival timestamp.

---

### Test Case 08: OEM Aggressive Background Killer Whitelist
- **Purpose:** Validate background survival on heavily skinned OEM Android distributions (Samsung One UI, Xiaomi HyperOS, OnePlus OxygenOS).
- **Execution Steps:**
  1. On a Xiaomi or Samsung test device, apply standard instructions from `docs/BATTERY_OPTIMIZATION_GUIDE.md`:
     - Set Battery Usage to **"Unrestricted"**.
     - Enable **"Autostart"** (Xiaomi) / add to **"Never Sleeping Apps"** (Samsung).
  2. Start journey tracking.
  3. Lock screen and leave device undisturbed on a moving route for $>45\text{ minutes}$.
- **Pass Criteria:**
  - Ongoing foreground notification remains visible in status bar throughout test.
  - Service is not silently terminated by OEM daemon (`phantom_process_killer` or `Samsung DeviceCare`).
  - Alert triggers on time upon reaching destination.

---

### Test Case 09: Emergency SOS Direct SMS & Countdown Workflow
- **Purpose:** Verify that Emergency SOS triggers with a 5-second cancelable countdown, prevents duplicate sends on rapid taps, and confirms honest delivery status.
- **Execution Steps:**
  1. In Settings, enable **"Direct Emergency SMS Dispatch"** and accept informed consent dialog.
  2. Start an active journey and navigate to `ActiveJourneyScreen`.
  3. Tap **"EMERGENCY SOS: Send Location Now"**.
  4. Verify the modal sheet appears displaying a 5-second countdown with visual circular timer and "Cancel Alert" option.
  5. Test cancellation: Tap "Cancel Alert" within 5 seconds. Verify no message is sent and a snackbar confirms cancellation.
  6. Tap SOS again and let the countdown elapse to 0 (or tap "Send Immediately").
  7. Verify confirmation card displays:
     - Exact message text with live coordinates, accuracy, and Google Maps link.
     - Recipient contact name and number.
     - Delivery method: "Automatic Direct SMS" (or fallback to SMS Composer if direct SMS is unavailable).
     - Prominent "Send via WhatsApp" button.
- **Pass Criteria:**
  - Emergency message accurately includes live coordinates, accuracy, Google Maps URL, and timestamp.
  - Tapping SOS repeatedly does not produce duplicate transmissions.

---

### Test Case 10: GPS Telemetry & Nearest-Station Proximity Accuracy
- **Purpose:** Ensure the app never claims the user is "Near Central" when in Guindy, Tambaram, or outside Chennai.
- **Execution Steps:**
  1. Launch STOP Vanthachu from Guindy, Tambaram, or a non-Central transit location.
  2. While GPS is acquiring, observe the proximity card on `HomeScreen`: verify it displays `"Finding your location..."` or `"Acquiring GPS fix..."` and NEVER displays `"Near Central"`.
  3. Once GPS fix is acquired:
     - If at Guindy Railway/Metro: card reads `"At Guindy Metro & Station"`.
     - If 1.5 km away: card reads `"Near Guindy Metro & Station (approx. 1.5 km)"`.
     - If in a distant area (> 3 km): card reads `"Nearest: [Station] (X km away) — Outside transit vicinity"`.
  4. Verify accuracy (e.g. `±12m`) and sample age (e.g. `5s ago`) are displayed.
- **Pass Criteria:**
  - Zero instances of false "Near Central" labels.
  - Real-time station updates on pull-to-refresh.

---

### Test Case 11: WhatsApp Contact Validation & Click-to-Chat Link
- **Purpose:** Verify phone number validation accepts standard Indian and international numbers without false "not registered on WhatsApp" errors.
- **Execution Steps:**
  1. Open `SafetyContactsScreen` and tap **"Add Contact"**.
  2. Test multiple valid input formats:
     - 10-digit Indian: `9876543210` or `6383679809`
     - With leading zero: `09876543210`
     - With country code: `+91 98765 43210` or `+91-9876543210`
     - International E.164: `+14155552671`
  3. Save contact and open the popup menu -> select **"Open WhatsApp Chat"**.
- **Pass Criteria:**
  - Valid formats are saved without error.
  - No false claims that the phone number does not exist on WhatsApp.
  - WhatsApp opens directly with prefilled check-in message.

---

### Test Case 12: Offline Map Persistence & Airplane Mode
- **Purpose:** Verify map tiles are persistently cached locally and render smoothly in Airplane Mode.
- **Execution Steps:**
  1. Plan a journey with multiple stops or view a saved journey route.
  2. Tap the **"Download Route Map for Offline Use"** cache button in the map view.
  3. Verify toast confirms caching completed (e.g. `Successfully cached 24 route map tiles...`).
  4. Put the Android phone into **Airplane Mode** (disable Wi-Fi and Cellular data).
  5. Close and reopen the app (cold start).
  6. Open the journey route map.
- **Pass Criteria:**
  - Route map displays previously cached tiles with `[Offline Cache Active]` badge.
  - Panning across route stops renders smoothly without blank gray grids.
  - Local station database search works 100% offline.

---

## 4. Hardware Field Sign-Off Form

| Field Test Date | Device Model & Manufacturer | Android OS Version | Test Route / Transit Mode | QA Lead Sign-Off |
|---|---|---|---|---|
| `____-__-__` | `____________________` | `Android _____` | `____________________` | `[ ] APPROVED` |
| `____-__-__` | `____________________` | `Android _____` | `____________________` | `[ ] APPROVED` |
