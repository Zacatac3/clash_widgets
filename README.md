## Clashboard Widgets

Clashboard is an iOS app with a WidgetKit extension that tracks Clash of Clans upgrade timers and builder/lab/pet house availability at a glance.

### Features
- Multi-profile support (store multiple player tags and switch between them).
- Clash of Clans profile refresh via the official API.
- Import/export support for the game’s JSON export to track ongoing upgrades.
- Widget showing builder availability and upgrade progress.
- Local persistence with app group storage shared between app and widget.
- Optional notifications for upgrade completion.

### Wishlist/to-do
- fix widget looks on certaind device sizes
- add "over view" (4x4) widget which displayer all current upgrades in both villages
- add "progress tracker" which shows a progress bar for each town hall displaying percent of upgrades complete for said town hall 
- Implement backend for remote updates without pushing new build to app store

### App + Widget Architecture
- App target: `clash_widgets` (SwiftUI UI, data management, settings).
- Widget target: `ClashboardWidget` (WidgetKit timeline + rendering).
- Shared storage: App Group `group.Zachary-Buschmann.clash-widgets`.


### Assets & Mapping
Asset images for buildings, heroes, pets, and lab items live under [clash_widgets/Assets.xcassets](clash_widgets/Assets.xcassets). Upgrade data relies on a mapping of game IDs to names in [clash_widgets/upgrade_info/mapping.json](clash_widgets/upgrade_info/mapping.json) with raw data in [clash_widgets/upgrade_info/raw.json](clash_widgets/upgrade_info/raw.json).

### Local Data Storage
The app stores profiles, upgrades, and preferences to an app group container so the widget can read shared data. The widget falls back to `UserDefaults` data if needed.

### Development Tools
Utility scripts and data files live under [tools](tools) and [json_files](json_files), these are not needed for the app and for personal use, not needed for install.

### Disclaimer
Clash of Clans is a trademark of Supercell. This project is a fan-made utility and is not affiliated with or endorsed by Supercell.
