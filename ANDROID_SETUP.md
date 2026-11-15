# YatraSaathi — Android Setup & Deployment Guide

This guide details the prerequisites, build configuration, permissions setup, and installation steps for YatraSaathi on Android devices.

---

## 1. Development & Build Prerequisites

- **Flutter SDK:** 3.47.8 or higher
- **Dart SDK:** 3.13.7
- **Android SDK:** API 34+ (Build Tools 36.0.0+)
- **Java JDK:** OpenJDK 17 or 21 (or Android Studio JBR)
- **Android Gradle Plugin / Kotlin:** JVM 17 target compatibility configured in `android/app/build.gradle.kts`.

---

## 2. Android Manifest Configuration

The application manifest (`android/app/src/main/AndroidManifest.xml`) defines all required permissions and services:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Location Permissions -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />

    <!-- Foreground Service (Android 10+ and 14+) -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />

    <!-- Hardware & Notification Permissions -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.VIBRATE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />

    <application
        android:label="YatraSaathi"
        android:icon="@mipmap/ic_launcher">

        <!-- Geolocator Foreground Service -->
        <service
            android:name="com.baseflow.geolocator.GeolocatorLocationService"
            android:enabled="true"
            android:exported="false"
            android:foregroundServiceType="location" />
    </application>

    <!-- Native SMS Intent Queries (Android 11+) -->
    <queries>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="sms" />
        </intent>
        <intent>
            <action android:name="android.intent.action.SENDTO" />
            <data android:scheme="smsto" />
        </intent>
    </queries>
</manifest>
```

---

## 3. How to Build the Android APK

### Debug Build
```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```
**Output Location:**
`build\app\outputs\flutter-apk\app-debug.apk`

### Installing on Connected Physical Device or Emulator
```powershell
# List connected devices
flutter devices

# Install debug APK
flutter install

# Or install manually via ADB
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

---

## 4. First-Time Device Permissions Configuration

1. **Location Access:**
   - On first launch, start a journey or navigate to the **Permissions Guide** (Shield icon in AppBar).
   - Tap **"Request Location Permission"**.
   - Select **"While using the app"** (or **"Always allow"** if prompted for background tracking).
2. **Notification Permission (Android 13+):**
   - When prompted by the system, tap **"Allow"** to ensure arrival notifications and foreground tracking notifications can be shown in the status bar.
3. **Battery Optimization (OEM Specific):**
   - Certain Android vendors (Xiaomi MIUI/HyperOS, Samsung OneUI, OnePlus OxygenOS) aggressively terminate background services.
   - For long transit journeys, open Android Settings > Apps > YatraSaathi > Battery > Select **"Unrestricted"**.

---

## 5. Technical Limitations & Platform Constraints

- **Process Force-Stop:** If the user manually swipes away or force-stops YatraSaathi from Android's Recents screen, Android terminates the process and foreground service. No app can bypass this OS security policy.
- **Device Reboot:** Tracking will pause on reboot. The user must relaunch YatraSaathi and tap "Start" on their saved journey.
- **Silent Mode / Do Not Disturb:** If the phone is switched to Silent mode or DND is active, system audio rules apply. Haptic vibration will still pulse.

