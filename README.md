## ClashDash Widgets

ClashDash is an iOS app with a WidgetKit extension that tracks Clash of Clans upgrade timers and builder/lab/pet house availability at a glance.

### Features
- Multi-profile support (store multiple player tags and switch between them).
- Clash of Clans profile refresh via the official API.
- Import/export support for the game’s JSON export to track ongoing upgrades.
- Widget showing builder availability and upgrade progress.
- Local persistence with app group storage shared between app and widget.
- Optional notifications for upgrade completion.

### Wishlist/to-do
- add assets for all buildings (currently incomplete)
- add tab for equipment
- fix widget looks on certaind device sizes
- add support for goblin builder / researcher
- fix star lab missing
- integrate full upgrade times so progress bars can be accurate (currently relative to import, so 100% is when value was imported)
- add "over view" (4x4) widget which displayer all current upgrades in both villages
- make profile page more useful
- add "progress tracker" which shows a progress bar for each town hall displaying percent of upgrades complete for said town hall 
- **obfuscate key**

### App + Widget Architecture
- App target: `clash_widgets` (SwiftUI UI, data management, settings).
- Widget target: `ClashDashWidget` (WidgetKit timeline + rendering).
- Shared storage: App Group `group.Zachary-Buschmann.clash-widgets`.

### Key Files
- App entry point: [clash_widgets/clash_widgetsApp.swift](clash_widgets/clash_widgetsApp.swift)
- Main UI: [clash_widgets/ContentView.swift](clash_widgets/ContentView.swift)
- Data layer: [clash_widgets/DataService.swift](clash_widgets/DataService.swift)
- Models: [clash_widgets/Models.swift](clash_widgets/Models.swift)
- Persistence: [clash_widgets/PersistentStore.swift](clash_widgets/PersistentStore.swift)
- Widget: [ClashDashWidget/ClashDashWidget.swift](ClashDashWidget/ClashDashWidget.swift)

### Assets & Mapping
Asset images for buildings, heroes, pets, and lab items live under [clash_widgets/Assets.xcassets](clash_widgets/Assets.xcassets). Upgrade data relies on a mapping of game IDs to names in [clash_widgets/upgrade_info/mapping.json](clash_widgets/upgrade_info/mapping.json) with raw data in [clash_widgets/upgrade_info/raw.json](clash_widgets/upgrade_info/raw.json).

### Local Data Storage
The app stores profiles, upgrades, and preferences to an app group container so the widget can read shared data. The widget falls back to `UserDefaults` data if needed.

### Setup
1. Open the folder [clash_widgets.xcodeproj](clash_widgets.xcodeproj) in Xcode (the rest is not needed for building the app).
2. Select a simulator running iOS 17+, or your personal device within xcode.
3. Build the app target and widget target.
4. Add the “ClashDash” widget to your Home Screen to view builder timers.

### API Key Note
The app currently initializes the `DataService` with a hard-coded API key in [clash_widgets/ContentView.swift](clash_widgets/ContentView.swift). This key is being used through royale API and their proxy.
Because the app is fully on-device and has no server backend, the API key has to ship in the app bundle to work out of the box. That means it can be extracted, so please do not abuse it.

### Development Tools
Utility scripts and data files live under [tools](tools) and [json_files](json_files), these are not needed for the app and for personal use, not needed for install.

### Disclaimer
Clash of Clans is a trademark of Supercell. This project is a fan-made utility and is not affiliated with or endorsed by Supercell.
