# BRANDING MIGRATION STRATEGY: STOP Vanthachu
**Project:** STOP Vanthachu (formerly YatraSaathi)  
**Tagline:** Never Miss Your Stop. Travel with Confidence.  
**Document Version:** 1.0.0  
**Effective Date:** November 2026

---

## 1. Context & Purpose

The journey tracking and transit safety companion originally developed under the working name **YatraSaathi** has evolved into a production-grade application named **STOP Vanthachu**.

The new name directly communicates the app's core value proposition: alerting transit commuters in Tamil Nadu, India, and commuters everywhere the precise moment their stop arrives, ensuring they never miss a stop while sleeping, reading, or commuting.

This document details:
1. The separation between user-facing presentation and internal technical identifiers.
2. The exact migration map across all application layers.
3. Backward compatibility safeguards for existing user data.

---

## 2. Technical Identifiers vs. User-Facing Branding

A core architectural tenet of this migration is: **Do NOT break installed applications, local database schemas, or platform channel contracts.**

| Entity | Old Identifier | Migrated Identity | Migration Rationale |
|---|---|---|---|
| **User-Facing App Name** | `YatraSaathi` | `STOP Vanthachu` | Displayed on Android launcher, task switcher, splash screen, and AppBar. |
| **Official Tagline** | `Your journey. Your check-ins. Your peace of mind.` | `Never Miss Your Stop. Travel with Confidence.` | Communicates confidence, vigilance, and safety. |
| **Android Application ID** | `com.example.pathsaathi` | **PRESERVED** (`com.example.pathsaathi`) | Preserves OS sandbox data, application updates, and signing keys without requiring uninstall/reinstall. |
| **Dart Package Identifier** | `pathsaathi` | **PRESERVED** (`pathsaathi`) | Prevents breaking `package:pathsaathi/...` imports across the test and source trees. |
| **Android MethodChannel** | `com.example.pathsaathi/direct_sms` | **PRESERVED** (`com.example.pathsaathi/direct_sms`) | Ensures flawless communication between Flutter and `MainActivity.kt` without risking native crashes. |
| **Notification Channel ID** | `yatrasaathi_arrival_v3` | **PRESERVED** (`yatrasaathi_arrival_v3`) | Android OS retains notification channel settings by channel ID. Changing the ID would reset custom user ringtone permissions in Android system settings. |
| **Notification Channel Name** | `Arrival Alerts & Alarms` | `STOP Vanthachu Arrival Alerts` | User-visible name in Android Notification Settings. |
| **Tracking Channel ID** | `yatrasaathi_tracking_service` | **PRESERVED** (`yatrasaathi_tracking_service`) | Preserves background service channel identity. |
| **Tracking Channel Name** | `Live Journey Tracking` | `STOP Vanthachu Live Tracking` | User-visible name in Android Notification Settings. |
| **Storage Key: Journeys** | `yatrasaathi_saved_journeys_v1` | **PRESERVED** | Preserves all journeys previously saved by the user. |
| **Storage Key: Active Journey** | `yatrasaathi_active_journey_id_v1` | **PRESERVED** | Preserves state if updating during an active trip. |
| **Storage Key: Profile** | `yatrasaathi_user_profile_v1` | **PRESERVED** | Preserves user contact preferences and emergency details. |
| **Storage Key: Contacts** | `yatrasaathi_safety_contacts_v1` | **PRESERVED** | Preserves the user's emergency contacts list. |
| **Default SMS Check-in Text** | `... - Sent via YatraSaathi` | `... - Sent via STOP Vanthachu` | Brand-aligned SMS message body sent to loved ones. |

---

## 3. Detailed Component Migration Map

### 3.1 Android Native Configuration
- **File:** `android/app/src/main/AndroidManifest.xml`
  - Changed `<application android:label="YatraSaathi" ...>` to `<application android:label="STOP Vanthachu" ...>`.
  - Ensures the launcher icon and multitasking switcher display **STOP Vanthachu**.

### 3.2 Flutter Application UI
- **File:** `lib/main.dart`
  - MaterialApp title: `'STOP Vanthachu'`.
  - AppBar title: `'STOP Vanthachu'`.
  - Greeting header: `'STOP Vanthachu'` with tagline `'Never Miss Your Stop. Travel with Confidence.'`.
  - Class alias: `typedef StopVanthachuApp = YatraSaathiApp;` ensuring backward compatibility for tests and new entry points.
- **File:** `lib/ui/first_launch_onboarding_screen.dart`
  - Rebranded welcome header: `"Welcome to STOP Vanthachu"`.
  - Rebranded privacy explanation: `"STOP Vanthachu uses your location to detect when you reach your journey stops..."`.
  - Rebranded notification guidance: `"Allows STOP Vanthachu to wake you with high-priority chimes..."`.
  - Rebranded background guidance: `"Background Tracking: When a journey is active, STOP Vanthachu runs a foreground service..."`.
- **File:** `lib/ui/settings_screen.dart`
  - Default check-in message template updated to `... - Sent via STOP Vanthachu`.
- **File:** `lib/ui/privacy_info_screen.dart`
  - Updated to `"STOP Vanthachu requires no user account..."` and `"In strict compliance with Google Play Developer policies, STOP Vanthachu never attempts to silently send background SMS..."`.
- **File:** `lib/ui/permission_guidance_screen.dart`
  - Updated to `"STOP Vanthachu processes GPS coordinates exclusively on your device..."`.
- **File:** `lib/ui/safety_contacts_screen.dart`
  - Empty state text updated to `"...STOP Vanthachu prepares an automated check-in message for them."`.
- **File:** `lib/ui/journey_wizard_screen.dart`
  - Updated guidance: `"Upon arrival, STOP Vanthachu opens your SMS app prefilled with this message."`.
  - Default check-in text: `"Hi! I have safely reached my stop. - Sent via STOP Vanthachu"`.
- **File:** `lib/ui/stop_config_dialog.dart`
  - Alert radius prompt: `"How far before the stop should STOP Vanthachu alert you?"`.
  - Default message: `" - Sent via STOP Vanthachu"`.

### 3.3 Core Services & Models
- **File:** `lib/models/user_profile.dart`
  - Default message: `'Hi! I have safely reached my stop. - Sent via STOP Vanthachu'`.
  - `formatPersonalizedMessage`: interpolates `' - Sent via STOP Vanthachu'`.
- **File:** `lib/services/messaging_service.dart`
  - `formatDefaultMessage`: returns message with `'- Sent via STOP Vanthachu'`.
- **File:** `lib/services/journey_tracking_service.dart`
  - Foreground notification title updated to `'STOP Vanthachu: ${journey.name}'`.
- **File:** `lib/services/location_service.dart`
  - Default notification title updated to `'STOP Vanthachu Journey Active'`.
- **File:** `lib/services/notification_service.dart`
  - Summary text: `'STOP Vanthachu Journey Alert'`.
  - Test notification title: `'🔔 STOP Vanthachu Test Notification'`.
  - Channel names: `'STOP Vanthachu Arrival Alerts'`, `'STOP Vanthachu Live Tracking'`.
- **File:** `lib/services/geocoding_service.dart`
  - HTTP User-Agent: `'STOPVanthachu-App/1.0 (info@stopvanthachu.app)'`.

---

## 4. Test Suite Harmonization

All test assertions verifying user-facing string representations have been synchronized with the new branding:
- `test/widget_test.dart`: Updated to assert `find.text('STOP Vanthachu')`.
- `test/first_launch_onboarding_test.dart`: Updated to assert `Welcome to STOP Vanthachu` and `STOP Vanthachu uses your location`.
- `test/messaging_service_test.dart`: Updated to assert `contains('STOP Vanthachu')`.
- `test/arrival_and_profile_integration_test.dart`: Updated to assert `contains('Sent via STOP Vanthachu')`.
- `test/developer_test_mode_test.dart`: Updated to assert `contains('Sent via STOP Vanthachu')`.
- `test/real_device_reliability_test.dart`: Updated to assert `contains('Sent via STOP Vanthachu')`.

---

## 5. Verification Checklist

- [x] No lingering user-facing occurrences of "YatraSaathi" in UI screens.
- [x] Internal technical identifiers safely preserved.
- [x] All 90+ automated tests passing.
- [x] Static analyzer clean with 0 issues.
- [x] Android debug APK builds cleanly.
