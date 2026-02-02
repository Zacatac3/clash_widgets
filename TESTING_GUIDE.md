# QOL Features Testing Guide

## Quick Reference - Where to Find Each Feature

### 1. Priority Notifications Toggle
**Location:** Settings Tab → Notifications Section
**Setting Name:** "Priority Notifications"
**Description:** Allow notifications to break through focus modes.

**How to Test:**
1. Go to Settings → Notifications
2. Enable "Enable Notifications" if not already enabled
3. Toggle "Priority Notifications" ON
4. Create an upgrade with expected finish time
5. Enable Do Not Disturb on device
6. Verify notification still appears when upgrade completes

---

### 2. Taller Import Button
**Location:** Dashboard → Selected Profile Section

**How to Test:**
1. Go to Dashboard tab
2. Look at the "Import Data" button
3. Verify it's significantly taller than "Open Game Settings" button
4. Button should have `.padding(.vertical, 16)` applied
5. Font size should be `.headline`

**Visual Comparison:**
- Import Data button: Much taller, more prominent
- Open Game Settings button: Smaller, secondary importance

---

### 3. Swapped Checkmark and Menu Button
**Location:** Settings Tab → Profiles Section (any profile row)

**How to Test:**
1. Go to Settings tab
2. Create 2+ profiles
3. Expand the profiles list
4. Look at a profile row
5. From right to left, you should see: Menu button (⋮) → Checkmark (✓)
6. Tap profile row to switch → checkmark should move

**Order Verification:**
- Right side: Checkmark appears FIRST (left-most)
- Next to it: Menu button (⋮)

---

### 4. Profile Names in Notifications
**Location:** Notification body when 2+ profiles exist

**How to Test:**
1. Create 2+ profiles with different names/tags
2. Add upgrades to each profile
3. Create an upgrade in first profile
4. Switch to second profile and create upgrade there
5. Wait for notification to trigger
6. Check notification body

**Expected Format:**
- Single profile: "Building Name finished upgrading to level X."
- Multiple profiles: "Building Name finished upgrading to level X [Profile Name]"

---

### 5. First Import Modal
**Location:** Appears automatically after first import (home screen import button)

**How to Test:**
1. On fresh app install or after clearing app data
2. Delete all existing profiles
3. Add a new profile
4. Use "Import Data" button on Dashboard
5. Paste valid JSON export from Clash of Clans
6. Modal should appear with clipboard tips

**Modal Contents:**
- Title: "Tired of \"Allow Paste\"?"
- 3 numbered steps with icons
- "Got It" button to dismiss

**Important:** Modal only shows once per device - check `hasShownFirstImportTip` in AppStorage if needed to reset.

---

### 6. Open Clash of Clans Toggle
**Location:** Settings Tab → Notifications Section
**Setting Name:** "Open Clash of Clans"
**Description:** Tapping a notification will redirect you to the Clash of Clans app.

**How to Test:**
1. Go to Settings → Notifications
2. Enable "Enable Notifications" if needed
3. Toggle "Open Clash of Clans" ON
4. Create an upgrade with expected completion
5. Let upgrade complete (notification fires)
6. Tap the notification
7. Clash of Clans app should open automatically

**Note:** Works best with actual CoC app installed. On simulator, you'll get "Cannot open..." error.

---

### 7. Profile Switching on Notification Tap
**Location:** Auto-triggered when notification is tapped (with proper setup)

**How to Test:**
1. Create 2+ profiles with different names
2. Add upgrades to different profiles
3. Go to Settings → Notifications
4. Enable "Enable Notifications"
5. Let an upgrade complete (notification fires for one profile)
6. Note which profile it's for
7. Switch to a different profile in the app
8. Tap the notification from the lock screen or notification center
9. App should automatically switch back to the profile that has the completed upgrade

**Verification:**
- Check the "Selected Profile" section - should show the profile from notification
- Profile display name should match the notification context

---

## Settings Organization

All new notification features are found under:
**Settings Tab → Notifications Section**

```
Notifications Section:
├── Enable Notifications [Toggle]
├── [Category toggles if enabled]
│   ├── Builders
│   ├── Laboratory
│   ├── Pet House
│   ├── Builder Base
│   └── Helpers
├── ──────────────── [Divider]
├── Priority Notifications [Toggle] ← NEW
└── Open Clash of Clans [Toggle] ← NEW
```

---

## Edge Cases to Test

1. **Single Profile Scenario:**
   - Profile name should NOT appear in notifications
   - App redirect should work normally

2. **Multiple Profiles:**
   - Each notification should show the owning profile name
   - Tapping notification should switch to correct profile
   - App redirect should open CoC and app should remain on switched profile

3. **Toggle Changes:**
   - Disabling "Open Clash of Clans" should prevent auto-open
   - Disabling "Priority Notifications" should revert to normal interrupt level
   - Changes should persist across app restarts

4. **First Import Modal:**
   - Should only appear once
   - Should appear regardless of profile count
   - Should be dismissible without action

5. **Focus Mode:**
   - With Priority enabled: notifications appear through Focus Mode
   - With Priority disabled: notifications respect Focus Mode

---

## Code References for Developers

### Models.swift
- `NotificationSettings` struct (lines ~55-82)
- New fields: `priorityNotificationsEnabled`, `autoOpenClashOfClansEnabled`

### NotificationManager.swift
- `setProfileContext()` method for storing profile info
- `setNotificationSettings()` for notification level setting
- `makeRequest()` updated to include profile name and interruption level

### ContentView.swift
- `FirstImportTipSheet` struct (lines ~6008+)
- Settings section (lines ~3810-3830)
- Import button styling (lines ~1711-1745)
- Profile row layout (lines ~4100-4160)

### clash_widgetsApp.swift
- `AppDelegate` class with `UNUserNotificationCenterDelegate` (lines ~17-65)
- `@UIApplicationDelegateAdaptor` in ClashboardApp

### DataService.swift
- `handleProfileSwitchFromNotification()` method
- Notification listener setup in `init()`
- Profile context passing in `scheduleUpgradeNotifications()`

---

## Known Limitations

1. App redirect only works if Clash of Clans app is installed
2. Profile switching requires notification to contain valid UUID
3. Priority notifications require iOS 15+
4. First import modal cannot be re-triggered without clearing AppStorage
