# YatraSaathi — Privacy & Security Architecture

**Last Reviewed:** November 2026  
**Auditor:** Senior Security Auditor & Software Architect

---

## 1. Privacy Philosophy

YatraSaathi is engineered from first principles as an **offline-first, zero-knowledge** mobile application. Transit location coordinates, stop history, and personal contact numbers belong strictly to the traveler.

---

## 2. Key Privacy Guarantees

| Concern | YatraSaathi Guarantee | Technical Implementation |
| :--- | :--- | :--- |
| **Cloud Tracking** | **Zero Telemetry** | No network requests to any remote API. No telemetry servers, crash collectors, or external analytics SDKs. |
| **Account Identity** | **No Login / Account Required** | The app runs completely anonymously. No email, social login, or advertising ID is collected. |
| **Location History** | **Ephemeral In-Memory Evaluation** | GPS fixes are evaluated instantaneously for Haversine distance and station dwell time, then immediately discarded from RAM. |
| **Saved Journeys** | **Private Local Storage** | Stored exclusively inside Android's private app sandbox via `SharedPreferences`. |
| **Contact Details** | **PII Masking & Non-Disclosure** | Check-in phone numbers are masked in all console and diagnostic outputs (`***-***-1234`). |
| **Data Deletion** | **One-Tap Complete Wipe** | Users can delete individual journeys at any time or purge all data via Settings > "Clear All Saved Journeys". |

---

## 3. Honest Android SMS Compliance

### Google Play Policy Compliance
Google Play Developer policies strictly restrict access to the `SEND_SMS` permission. Apps that are not the default SMS handler on Android are prohibited from sending background SMS messages.

### YatraSaathi's Compliant Workflow
- When a traveler arrives at a stop with an enabled check-in contact, YatraSaathi prepares the message and launches the **native Android SMS Composer** via the standard `sms:<phone>?body=<encodedMessage>` URI intent.
- The traveler reviews the message and taps the native "Send" button.
- **Honest Status Tracking:** YatraSaathi marks the status as `COMPOSER_OPENED`. It **never** falsely logs `SENT_CONFIRMED` when only the composer was opened.

---

## 4. Minimum Permissions Rationale

1. **`ACCESS_FINE_LOCATION`:** Computes accurate Haversine distance to target stops.
2. **`ACCESS_COARSE_LOCATION`:** Required by Android framework alongside fine location.
3. **`ACCESS_BACKGROUND_LOCATION` / `FOREGROUND_SERVICE_LOCATION`:** Enables the foreground service to monitor location when the user locks their screen or switches apps.
4. **`POST_NOTIFICATIONS`:** Allows Android 13+ devices to show the ongoing journey tracking status and arrival alerts.
5. **`VIBRATE`:** Activates tactile phone vibration in transit when ambient noise is loud or phone is in a pocket.
6. **`WAKE_LOCK`:** Ensures processor remains awake during station arrival alert burst.

