# Boost Timer Synchronization Fix - Implementation Summary

## Problem Overview
The app was experiencing significant drift between boost timers shown in the app versus those displayed in widgets and notifications. When users activated potions or other boosts, the timers would be off by over an hour in some cases. Additionally:
- Notifications weren't accounting for boosted times
- Boosted upgrades wouldn't clear properly after completion
- Widget timers didn't reflect active boosts

## Root Cause
The issue stemmed from three separate systems calculating time differently:
1. **App UI** (BuilderRow.swift): Used `effectiveRemainingSeconds()` to account for boosts
2. **Widgets** (ClashDashWidget.swift): Only used raw `endTime` without boost calculations
3. **Notifications** (NotificationManager.swift): Scheduled based on raw `endTime` 
4. **Completion Check** (DataService.swift): Used raw `endTime` comparison for pruning

## Solution Implemented

### 1. Widget Timer Synchronization
**Files Modified:** `ClashDashWidget/ClashDashWidget.swift`

- Added `effectiveRemainingSeconds()` and `effectiveCompletionDate()` functions to calculate boost-adjusted times
- Updated `SimpleEntry` to include `activeBoosts: [ActiveBoost]` array
- Modified `Provider.loadUpgrades()` to load and pass active boosts from the profile
- Implemented dynamic widget refresh policy:
  - **Active boosts + near completion (≤60s)**: Refresh every 30 seconds
  - **Active boosts + soon (≤5 min)**: Refresh every minute
  - **Active boosts + normal**: Refresh every 5 minutes
  - **No boosts + near completion**: Refresh every minute
  - **No boosts + normal**: Refresh every 15 minutes (standard)

This ensures widgets respect Apple's refresh guidelines while providing accurate timers during critical moments.

### 2. Notification Scheduling Fix
**Files Modified:** `clash_widgets/NotificationManager.swift`, `clash_widgets/DataService.swift`

- Added `effectiveCompletionDate()` to calculate true completion time with boosts
- Updated `makeRequest(for:activeBoosts:)` to accept active boosts parameter
- Modified `syncNotifications()` to pass active boosts to notification scheduling
- Updated `scheduleUpgradeNotifications()` in DataService to collect and pass active boosts from all profiles
- Notifications now reschedule when boosts are activated/cancelled via `saveActiveBoosts()`

### 3. Completion Check Fix
**Files Modified:** `clash_widgets/DataService.swift`

- Completely rewrote `pruneCompletedUpgrades()` to use boost-aware time calculations
- Added `effectiveRemainingSeconds()` method to DataService (same logic as BuilderRow and widgets)
- Upgrades now only clear when their **true boosted time** has elapsed, not just raw endTime

### 4. Widget Refresh Triggers
**Files Modified:** `clash_widgets/ContentView.swift`

- Imported `WidgetKit` framework
- Updated `saveActiveBoosts()` to:
  - Call `persistChanges(reloadWidgets: true)` instead of false
  - Reschedule notifications with new boost data
- Added widget refresh when app becomes active (scene phase monitoring)
- Boost expiration check also triggers widget reload

## Technical Details

### Boost Calculation Algorithm
All three systems now use the same algorithm:

```swift
1. Start with base remaining time: upgrade.endTime - now
2. Build timeline of boost periods from upgrade.startTime to now
3. For each time segment:
   a. Calculate which boosts were active during that segment
   b. Sum the boost multipliers (respecting clock tower non-stacking rule)
   c. Multiply segment duration by total multiplier to get "extra elapsed"
4. Subtract extra elapsed from base remaining
5. Return max(0, adjusted remaining)
```

This ensures consistent behavior across:
- App timer display
- Widget timer display  
- Notification scheduling
- Completion detection

### Widget Refresh Policy
The dynamic refresh policy balances accuracy with battery efficiency:
- Widgets refresh more frequently only when needed (boosts active or near completion)
- Respects Apple's widget budget system
- Forces immediate refresh when user opens the app (tapping widget)

### Notification Rescheduling
Notifications automatically reschedule when:
- A boost is activated (via `saveActiveBoosts()`)
- A boost is cancelled
- A boost expires
- The app becomes active (scene phase change)

## Testing Recommendations

1. **Activate a builder potion (10x for 1 hour)**
   - Verify widget timer matches app timer
   - Verify notification is scheduled for boosted completion time
   - Wait for upgrade to complete and verify notification fires
   - Reopen app and verify upgrade clears from list

2. **Test widget refresh**
   - Activate boost with active upgrade
   - Check widget timer (should match app)
   - Close app and wait 1-2 minutes
   - Check widget again (should have updated)
   - Open app by tapping widget
   - Verify widget immediately refreshes

3. **Test notification timing**
   - Start an upgrade that will take 2+ hours
   - Activate a potion
   - Check notification in Settings > Notifications (should be rescheduled)
   - Wait for boosted completion time
   - Verify notification fires at correct time

4. **Test completion clearing**
   - Have an upgrade with 5 minutes remaining
   - Activate 10x potion (should complete in ~30 seconds)
   - Wait for boosted completion
   - Close and reopen app
   - Verify upgrade is removed from list

## Files Modified Summary

1. `ClashDashWidget/ClashDashWidget.swift` - Added boost calculation, dynamic refresh
2. `clash_widgets/NotificationManager.swift` - Boost-aware notification scheduling
3. `clash_widgets/DataService.swift` - Boost-aware pruning, public notification method
4. `clash_widgets/ContentView.swift` - Widget refresh triggers, WidgetKit import
5. `changelog.txt` - Documented changes

## No Breaking Changes
- All changes are backward compatible
- No database/model structure changes
- Works correctly with and without active boosts
- No user-facing UI changes (only fixes timer accuracy)
