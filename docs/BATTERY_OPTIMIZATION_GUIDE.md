# STOP Vanthachu — Android Battery Optimization & Background Reliability Guide

> **Tagline:** Never Miss Your Stop. Travel with Confidence.  
> **Target OS:** Android 8.0 (API 26) through Android 15 (API 35)

---

## 1. Why Background Optimization Settings Matter

Smart travel safety applications like **STOP Vanthachu** rely on continuous GPS location monitoring and timely audio alarms to wake sleeping travelers before their stop.

However, modern Android devices from manufacturers such as **Samsung, Xiaomi, OPPO, Vivo, and OnePlus** implement aggressive proprietary power-saving algorithms (often documented on [DontKillMyApp](https://dontkillmyapp.com)). By default, these operating system skins aggressively suspend background threads, throttle GPS fix intervals, and terminate active foreground services when the phone screen is locked or the device is left stationary.

If the operating system kills the monitoring service while you sleep, your alarm will not sound, and you could miss your stop.

This guide provides device-specific instructions to guarantee uninterrupted background transit monitoring for STOP Vanthachu.

---

## 2. STOP Vanthachu's Native Background Architecture

STOP Vanthachu is engineered with multi-layered defenses against OS termination:

| Component | Android Mechanism | Purpose |
|---|---|---|
| **Foreground Service** | `android:foregroundServiceType="location"` | Informs the OS that location tracking is vital and user-facing |
| **Ongoing Notification** | `FLAG_ONGOING_EVENT` + Notification Channel | Prevents the system from treating the app as cached background memory |
| **Wake Lock** | `android.permission.WAKE_LOCK` (via `foregroundNotificationConfig`) | Prevents the CPU from deep-sleeping when approaching destination geofences |
| **Alarm Audio Routing** | `AudioAttributes.USAGE_ALARM` | Ensures arrival chimes ring through phone speakers even if the phone is in silent or Do Not Disturb (DND) mode |
| **Cold-Start Auto-Recovery** | `restoreActiveSession()` on launch | If the system terminates the app, launching the app instantly restores active journey tracking without losing progress |

To ensure these mechanisms operate without manufacturer interference, apply the optimization steps below for your device.

---

## 3. Manufacturer-Specific Setup Instructions

---

### A. Samsung (One UI 4 / 5 / 6)

Samsung devices running One UI include **App Power Management** and **Sleeping Apps** features that silently stop background services after 15–30 minutes of screen-off time.

#### Step 1: Set App Battery Usage to "Unrestricted"
1. Open **Settings** on your phone.
2. Tap **Apps** &rarr; select **STOP Vanthachu**.
3. Tap **Battery**.
4. Select **Unrestricted** (do NOT choose *Optimized* or *Restricted*).

#### Step 2: Add to "Never Sleeping Apps"
1. Open **Settings** &rarr; **Device Care** (or *Battery and device care*).
2. Tap **Battery** &rarr; **Background usage limits**.
3. Turn **OFF** the toggle for *Put unused apps to sleep*.
4. Tap **Never sleeping apps**.
5. Tap the **+** (Add) icon in the top right corner.
6. Select **STOP Vanthachu** and tap **Add**.

#### Step 3: Disable Adaptive Battery (Optional for overnight train journeys)
- In **Device Care** &rarr; **Battery** &rarr; **More battery settings**, disable **Adaptive battery** if you frequently travel on long 6+ hour routes.

---

### B. Xiaomi / Redmi / POCO (MIUI 13 / 14 & HyperOS)

Xiaomi's custom Android skins terminate non-whitelisted apps aggressively within 10 minutes of screen timeout.

#### Step 1: Disable MIUI / HyperOS Battery Saver
1. Open **Settings** &rarr; **Apps** &rarr; **Manage apps**.
2. Select **STOP Vanthachu**.
3. Scroll down and tap **Battery saver**.
4. Select **No restrictions** *(Important: Do not leave at "Battery saver (recommended)")*.

#### Step 2: Enable Autostart
1. On the same **STOP Vanthachu** app info page, find the **Autostart** toggle.
2. Turn **Autostart** &rarr; **ON**.
3. Tap **OK** on the confirmation dialog.

#### Step 3: Lock App in the Recent Apps Overview
1. Open **STOP Vanthachu**.
2. Swipe up from the bottom (or tap the Square navigation button) to open the **Recent Apps** switcher.
3. Long-press the **STOP Vanthachu** app card.
4. Tap the **Lock icon** &rarr; a small padlock icon will appear next to the app title.  
   *(This prevents the OS from clearing STOP Vanthachu when you tap "Clear All" in recents).*

---

### C. OPPO / Realme (ColorOS & Realme UI)

ColorOS kills background tasks and freezes background location streams when the device goes into deep sleep.

#### Step 1: Allow Background Activity & Auto-Launch
1. Open **Settings** &rarr; **Apps** (or *App Management*).
2. Tap **App list** &rarr; select **STOP Vanthachu**.
3. Tap **Battery usage**.
4. Enable **Allow background activity**.
5. Enable **Allow auto-launch** and **Allow secondary launch**.

#### Step 2: Exclude from Battery Optimization
1. Go to **Settings** &rarr; **Battery** &rarr; **More battery settings**.
2. Tap **App battery management** &rarr; select **STOP Vanthachu**.
3. Enable **Allow background activity**.
4. Go back to **More battery settings** &rarr; tap **Optimize battery use**.
5. Find **STOP Vanthachu** and select **Don't optimize**.

#### Step 3: Lock App in Recent Tasks
1. Open the **Recent Tasks** screen.
2. Tap the **three vertical dots** (or pull down the card) on STOP Vanthachu.
3. Tap **Lock**.

---

### D. Vivo / iQOO (Funtouch OS & OriginOS)

Vivo devices have a background energy management system that silently cuts network and GPS fixes for apps not explicitly set to high background power usage.

#### Step 1: Unrestricted High Background Power Consumption
1. Open **Settings** &rarr; **Battery**.
2. Tap **Background power consumption management** (or *High background power consumption*).
3. Find and select **STOP Vanthachu**.
4. Select **Don't restrict background power usage** (or toggle ON *High background power consumption*).

#### Step 2: Enable Autostart
1. Open **Settings** &rarr; **More settings** (or *Applications and Permissions*).
2. Tap **Permission management** &rarr; **Autostart**.
3. Enable **STOP Vanthachu**.

#### Step 3: Lock in App Switcher
1. Open the multitasking overview.
2. Swipe down on the **STOP Vanthachu** card or tap the three dots and select **Lock**.

---

### E. OnePlus (OxygenOS 12 / 13 / 14)

Modern OxygenOS is based on the ColorOS engine and requires similar power management exemptions.

#### Step 1: Set Battery to "Unrestricted"
1. Open **Settings** &rarr; **Apps** &rarr; **App management**.
2. Select **STOP Vanthachu** &rarr; **Battery usage**.
3. Select **Unrestricted** (or toggle ON *Allow background activity*).

#### Step 2: Disable Sleep Standby Optimization (for Overnight Journeys)
1. Open **Settings** &rarr; **Battery** &rarr; **More settings** (or *Advanced settings*).
2. Tap **Optimize battery use** &rarr; select **STOP Vanthachu** &rarr; choose **Don't optimize**.
3. If you sleep overnight on sleeper buses or trains, turn OFF **Sleep standby optimization**.

---

### F. Google Pixel, Motorola & Clean Android Devices

Devices running stock Android or close-to-stock builds (Pixel, Motorola, Nothing OS, Nokia) respect standard Android Foreground Service protocols natively, but verifying battery settings is still good practice:

1. Long-press the **STOP Vanthachu** app icon on your home screen or app drawer.
2. Tap the **(i)** (App info) icon.
3. Tap **App battery usage** (or *Battery*).
4. Select **Unrestricted**.
5. Tap **Permissions** &rarr; **Location** &rarr; verify it is set to **Allow all the time** or **Allow only while using the app** (STOP Vanthachu's foreground service provides continuous background location under either option).

---

## 4. Pre-Journey Checklist for Travelers

Before going to sleep or putting your phone in your pocket during transit:

- [ ] **Start the Journey in the App:** Ensure the dashboard shows `Active` status and the persistent notification appears in your status bar (`Approaching <Your Stop>`).
- [ ] **Check Device Volume:** Make sure media and alarm volume are turned up to a comfortable level. STOP Vanthachu plays audio via the `USAGE_ALARM` audio stream, which rings through the main speaker.
- [ ] **Plug in Charger or Power Bank:** Continuous high-accuracy GPS (3-4 second polling) consumes approximately 4–7% battery per hour. Keep your phone connected to a power bank on journeys exceeding 4 hours.
- [ ] **Leave Notification Active:** Do not swipe away or force-close the persistent STOP Vanthachu status notification.

---

## 5. Troubleshooting Common Issues

### Issue: "Tracking stopped after my screen turned off"
- **Cause:** Battery optimization placed STOP Vanthachu into standby.
- **Solution:** Apply the manufacturer steps in Section 3 above. Set battery to *Unrestricted* and turn off *Put unused apps to sleep*.

### Issue: "I reopened the app after restart, did I lose my journey?"
- **Cause:** Device was rebooted or memory was cleared.
- **Solution:** STOP Vanthachu automatically runs session auto-recovery (`restoreActiveSession()`) on launch. When you reopen the app, your active journey, reached stops, and remaining target stop are restored seamlessly.

---

*Document Version: 1.0.0 — STOP Vanthachu Production Engineering*
