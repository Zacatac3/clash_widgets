# Copilot instructions for Clashboard (clash_widgets)

## Big picture
- Two targets: app target clash_widgets (SwiftUI app) and widget target ClashDashWidget (WidgetKit). See [clash_widgets/clash_widgetsApp.swift](../clash_widgets/clash_widgetsApp.swift) and [ClashDashWidget/ClashDashWidget.swift](../ClashDashWidget/ClashDashWidget.swift).
- Data flow centers on `DataService` (ObservableObject) which owns profiles, upgrades, notifications, and persistence. Changes typically call `persistChanges(reloadWidgets:)` and update shared app-group storage. See [clash_widgets/DataService.swift](../clash_widgets/DataService.swift).
- Shared state is stored in the app group container and read by widgets via `PersistentStore`. App group identifier: group.Zachary-Buschmann.clash-widgets. See [clash_widgets/PersistentStore.swift](../clash_widgets/PersistentStore.swift) and [ClashDashWidget/ClashDashWidget.swift](../ClashDashWidget/ClashDashWidget.swift).
- Widgets read profile selection from app group UserDefaults key widget_profile_selection and fall back to the “current profile” in saved state. See [ClashDashWidget/ClashDashWidget.swift](../ClashDashWidget/ClashDashWidget.swift).

## Project-specific patterns
- Boosted timer math must be consistent across app UI, widget timelines, notifications, and pruning. The boost-aware helpers live in `DataService` and are mirrored in the widget provider. If you change upgrade timing logic, update both app and widget paths. See [clash_widgets/DataService.swift](../clash_widgets/DataService.swift) and [ClashDashWidget/ClashDashWidget.swift](../ClashDashWidget/ClashDashWidget.swift).
- Notifications include profile context for multi-profile setups. `NotificationManager` stores profile context via `setProfileContext()` and includes profileID in `userInfo` to support auto-switch on tap. See [clash_widgets/NotificationManager.swift](../clash_widgets/NotificationManager.swift) and [clash_widgets/clash_widgetsApp.swift](../clash_widgets/clash_widgetsApp.swift).
- Global notification preferences (pre-notify offset, auto-open Clash of Clans) live in UserDefaults keys globalNotificationOffsetMinutes and globalAutoOpenClashOfClans. See [clash_widgets/NotificationManager.swift](../clash_widgets/NotificationManager.swift).
- API key is obfuscated via XOR in `ContentView` and passed into `DataService` during init; avoid moving this unless you also update the decoding logic. See [clash_widgets/ContentView/ContentView.swift](../clash_widgets/ContentView/ContentView.swift).

## Data & assets
- Upgrade data and mappings are loaded from JSON under upgrade_info. Mapping of game IDs to display names is in [clash_widgets/upgrade_info/mapping.json](../clash_widgets/upgrade_info/mapping.json); parsed data is consumed in `DataService` extension files. See [clash_widgets/DataService+Parsing.swift](../clash_widgets/DataService+Parsing.swift) and [clash_widgets/DataService+Progress.swift](../clash_widgets/DataService+Progress.swift).
- Images are organized in asset catalogs under [clash_widgets/Assets.xcassets](../clash_widgets/Assets.xcassets) and [ClashDashWidget/Assets.xcassets](../ClashDashWidget/Assets.xcassets). When adding new assets, keep naming consistent with mapping JSON.

## External integrations
- AdMob + UMP consent flow are initialized in the app scene. See [clash_widgets/clash_widgetsApp.swift](../clash_widgets/clash_widgetsApp.swift).
- Widgets and the app share data via app-group storage; avoid direct cross-target imports beyond that boundary.

## Build/test workflow
- Xcode project: open [clash_widgets.xcodeproj](../clash_widgets.xcodeproj). Schemes include clash_widgets (app) and ClashDashWidget (widget). UI tests live under [clash_widgetsUITests](../clash_widgetsUITests).
- There is an xcode-build-server config at [buildServer.json](../buildServer.json) if you need a build server for editor tooling.

## File organization principles
- Prefer smaller, focused files over large multi-purpose files.
- When a file starts getting large or hard to navigate, split it into subfiles by feature/domain (for example, separate view sections, parsing logic, and helpers).
- When implementing a standalone feature (for example, a new tab, major screen, or self-contained component), create a new file instead of appending to an existing large file.
- Keep shared models/services in dedicated files and keep UI files focused on presentation/composition.
- Treat avoiding very large files (for example, multi-thousand-line single files) as a guiding maintenance principle for this repo.

## Where to look for feature behavior
- App state + persistence: [clash_widgets/DataService.swift](../clash_widgets/DataService.swift), [clash_widgets/PersistentStore.swift](../clash_widgets/PersistentStore.swift)
- Widgets: [ClashDashWidget/ClashDashWidget.swift](../ClashDashWidget/ClashDashWidget.swift)
- Notifications: [clash_widgets/NotificationManager.swift](../clash_widgets/NotificationManager.swift), [clash_widgets/clash_widgetsApp.swift](../clash_widgets/clash_widgetsApp.swift)
- UI flows & onboarding: [clash_widgets/ContentView/ContentView.swift](../clash_widgets/ContentView/ContentView.swift)
