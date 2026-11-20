# Privacy Policy for STOP Vanthachu

**Effective Date:** March 15, 2026  
**Last Updated:** November 19, 2026  
**Application Name:** STOP Vanthachu  
**Package Name:** `com.example.pathsaathi`  
**Repository:** [https://github.com/rohitam26/YatraSaathi](https://github.com/rohitam26/YatraSaathi)

---

## 1. Introduction

STOP Vanthachu ("the Application", "we", "our") is an open-source, mobile travel companion built with Flutter for Android. The application is designed to help travellers and commuters monitor their journeys, prevent missed transit stops through loud arrival alarms, and easily send safety check-in messages to designated family members and emergency contacts.

We strongly value your privacy. This Privacy Policy provides a transparent, detailed explanation of what information STOP Vanthachu accesses, how that data is processed locally on your device, what minimal network communications occur, and your rights and controls as a user.

---

## 2. Scope of the Policy

This policy applies exclusively to the STOP Vanthachu mobile application (package `com.example.pathsaathi`) and its open-source codebase. STOP Vanthachu is not backed by any private cloud servers, centralized databases, user account systems, or analytics dashboards. 

---

## 3. Information the Application Accesses

Depending on the features you configure and the permissions you grant, STOP Vanthachu accesses:
1. **Device Geographic Location:** High-accuracy GPS coordinates, accuracy estimates, bearing, speed, and timestamps.
2. **Passenger Profile & Contact Details:** Your chosen display name, mobile phone number, emergency contacts' names, phone numbers, and custom check-in message templates.
3. **Transit Itinerary Data:** Journey names, destination coordinates, stop addresses, and alert radii.
4. **Hardware Features:** Audio speakers (via `STREAM_ALARM`), vibration hardware, wake locks, and system notification channels.

---

## 4. Location Information

### 4.1 On-Device Processing
- **Real-Time GPS Tracking:** While a journey is active, STOP Vanthachu requests device location updates to compute the distance remaining between your physical location and upcoming stops using the spherical Haversine formula.
- **GPS Noise & Accuracy Filtering:** Location samples with horizontal uncertainty greater than 65 metres are discarded to prevent erratic arrival triggers.
- **Dwell-Time Verification:** Arrival is confirmed only when multiple consecutive GPS readings place you within the configured stop radius (e.g. 200 m, 500 m, 1 km, or 2 km) and satisfy minimum dwell time thresholds.
- **Zero Telemetry / No Location Leakage:** **Your physical GPS coordinates are processed entirely on your device.** Your live location is never transmitted to, logged on, or shared with any developer server, third-party analytics provider, or advertising platform.

### 4.2 Background Location & Foreground Service
To reliably alert you while your device screen is turned off or while using other applications, STOP Vanthachu runs an Android Foreground Service (`FOREGROUND_SERVICE_LOCATION`). A persistent, high-visibility notification appears in your Android notification drawer whenever background tracking is active. You can pause or cancel tracking at any moment directly from the active journey screen or notification.

---

## 5. Journey and Destination Information

When you create or save a journey:
- Stop titles, geocoordinates, custom alert radii, selected ringtones, and assigned contacts are stored locally on your device using Android SharedPreferences (`shared_preferences`).
- Saved journeys remain on your device until you edit or delete them. They are never synchronized to any cloud database.

---

## 6. Personal Profile and Safety Contacts

In the Settings and Safety Profile screens, you may optionally provide:
- Your name and mobile number.
- One or more emergency contacts (contact name, phone number, relationship label such as Parent, Partner, Sibling, or Friend).
- A personalized check-in message template.

**Storage & Access:**
- All safety profile information is stored exclusively in private local device storage (`SharedPreferences`).
- STOP Vanthachu does not automatically read your entire device address book; you manually enter or select specific contacts you wish to designate for safety check-ins.

---

## 7. SMS and Safety Check-In Messages

STOP Vanthachu supports two distinct messaging modes:

### 7.1 Native SMS Composer Workflow (Default & Play Store Compliant)
- When arrival at a destination is detected, the application generates a pre-filled check-in text (e.g. *"I have safely reached Central Station. - Sent via STOP Vanthachu"*) and invokes the native Android SMS application using an `sms:` intent (`url_launcher`).
- **You retain full control:** The native SMS app opens on your screen with the designated recipient and message pre-populated. **No message is sent automatically without your explicit action to press "Send" in your SMS client.**
- Standard SMS/MMS carrier rates apply as determined by your mobile carrier.

### 7.2 Direct SMS Background Service (Private / Sideload Builds Only)
- For users running private or self-compiled APK builds where automatic background check-ins without screen interaction are desired, the application includes an optional direct dispatch pipeline using Android's native `SmsManager`.
- This feature requires explicit runtime permissions (`android.permission.SEND_SMS` and `android.permission.READ_PHONE_STATE`).
- Direct SMS is **disabled by default** and only activates if explicitly toggled on by the user within settings.
- Message dispatch depends on carrier signal and SIM availability. STOP Vanthachu logs local status (`sent`, `failed`, `pending`) for diagnostic display but does not guarantee delivery.

---

## 8. Map, Geocoding and Third-Party Services

STOP Vanthachu integrates standard open-source web APIs to display map tiles and provide location search:

| Service / Provider | Purpose | Data Transmitted | Privacy Policy |
| :--- | :--- | :--- | :--- |
| **OpenStreetMap Tile Servers** (`tile.openstreetmap.org`) | Renders map imagery in the location picker and journey view. | IP address, HTTP User-Agent header, requested tile coordinates ($z, x, y$). | [OpenStreetMap Foundation Privacy Policy](https://wiki.osmfoundation.org/wiki/Privacy_Policy) |
| **Photon by Komoot** (`photon.komoot.io`) | Primary search for place names and landmarks in the journey wizard. | Search query text (e.g. city or station name), approximate bounding coordinates. | [Komoot Privacy Policy](https://www.komoot.com/privacy) |
| **Nominatim (OSM)** (`nominatim.openstreetmap.org`) | Fallback place search and reverse geocoding (converting tapped pin coordinates into readable address text). | Search query string or tapped latitude/longitude coordinate pair, User-Agent header. | [Nominatim Usage & Privacy Policy](https://operations.osmfoundation.org/policies/nominatim/) |

*Note:* These external requests occur only when actively searching for a place or viewing the map picker. When tracking an active journey in the background, no geocoding requests are made.

---

## 9. Local Data Storage

All persistent application data is stored locally in the application's private sandbox on your Android device:
- Stored using Android `SharedPreferences`.
- Includes journey routes, stops, user settings, volume/alarm preferences, and safety contacts.
- Data is accessible only to the STOP Vanthachu application and is wiped when you clear application data or uninstall the app.

---

## 10. Data Sharing and Disclosure

- **No Third-Party Analytics:** We do not include Google Analytics, Firebase Analytics, Flurry, Mixpanel, or any tracking SDK.
- **No Advertising Networks:** We do not display advertisements and do not integrate AdMob, Unity Ads, or any ad trackers.
- **No Sale of Data:** We do not sell, rent, monetize, or trade any user information.
- **No Commercial Disclosure:** We have no access to your data and therefore cannot share it with third parties.

---

## 11. Data Retention and Deletion

You have complete control over your data:
- **In-App Deletion:** You can delete individual saved journeys, remove emergency contacts, or edit your passenger profile at any time in the app settings.
- **Complete Deletion:** Clearing application storage in your Android device settings (`Settings > Apps > STOP Vanthachu > Storage > Clear Data`) or uninstalling STOP Vanthachu permanently removes all saved journeys, profiles, and preferences from the device.

---

## 12. Permissions and User Control

STOP Vanthachu declares and requests the following Android permissions:

| Permission | Android Identifier | Purpose & Justification |
| :--- | :--- | :--- |
| **Fine Location** | `ACCESS_FINE_LOCATION` | Required to calculate real-time distance to upcoming stops with GPS accuracy. |
| **Coarse Location** | `ACCESS_COARSE_LOCATION` | Used as initial coarse estimate while GPS locks onto satellite signals. |
| **Background Location** | `ACCESS_BACKGROUND_LOCATION` | Required to continue monitoring transit progress when the screen is off or another app is open. |
| **Foreground Service** | `FOREGROUND_SERVICE` & `FOREGROUND_SERVICE_LOCATION` | Complies with Android 10+ and Android 14+ requirements to run the tracking service visibly with a notification. |
| **Post Notifications** | `POST_NOTIFICATIONS` | Required on Android 13+ to display the tracking notification and high-priority arrival alerts. |
| **Vibration** | `VIBRATE` | Triggers tactile vibration alert patterns upon arriving at a destination. |
| **Wake Lock** | `WAKE_LOCK` | Briefly wakes the device screen when an arrival alarm triggers so the user sees the alert modal. |
| **Modify Audio** | `MODIFY_AUDIO_SETTINGS` | Configures audio stream routing (`STREAM_ALARM`) to ensure alarms are audible in transit. |
| **Send SMS (Optional)** | `SEND_SMS` | Only used if direct automated SMS check-in is explicitly enabled by the user in private builds. |
| **Phone State (Optional)** | `READ_PHONE_STATE` | Only used in direct SMS mode to verify cellular SIM readiness before attempting dispatch. |

You can grant or revoke any permission at any time through Android's system settings. Revoking location permissions will disable active GPS tracking and arrival alarms.

---

## 13. Children's Privacy

STOP Vanthachu does not knowingly collect, store, or solicit personal information from children under the age of 13. The application operates offline-first and contains no age-verification mechanisms or remote account creation.

---

## 14. Security Practices

- **Sandboxed Storage:** All user configuration is stored in private application sandboxes managed by the Android operating system.
- **No Remote Attack Surface:** Because STOP Vanthachu does not host public API servers or user databases, your travel itineraries and contact information cannot be exposed through server-side breaches.
- **HTTPS Encryption:** All external requests for map tiles and place search queries are transmitted using encrypted HTTPS.

---

## 15. Changes to This Privacy Policy

If we update STOP Vanthachu with new features affecting privacy or data handling, this policy will be revised accordingly. The updated version will be committed to the public GitHub repository with an updated "Last Updated" date.

---

## 16. Contact Information & Open-Source Inquiries

STOP Vanthachu is an open-source project maintained by its developers. If you have questions, feedback, or privacy concerns regarding this application, please reach out:

- **Project Maintainer:** Rohit ([@rohitam26](https://github.com/rohitam26))
- **Email:** `[Your Contact Email Placeholder — e.g., rohitam256@gmail.com]`
- **Repository Issues:** [https://github.com/rohitam26/YatraSaathi/issues](https://github.com/rohitam26/YatraSaathi/issues)
- **Source Code:** [https://github.com/rohitam26/YatraSaathi](https://github.com/rohitam26/YatraSaathi)
