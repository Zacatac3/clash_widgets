# Refactor Instructions (ContentView + DataService)

## Goals
- Split monolithic files into focused, domain-based files.
- Preserve **identical runtime behavior** (no feature removals, no logic changes).
- Keep app/widget parity for timing and shared storage behavior.

## Ownership Map

### ContentView family
- `clash_widgets/ContentView.swift`
  - Root app shell only: app-level state, tab container, onboarding gate, scene-phase hooks, launch ad trigger, widget import handoff.
- `clash_widgets/ContentView+Onboarding.swift`
  - Onboarding flow and setup submission helpers.
- `clash_widgets/DashboardView.swift`
  - Home/dashboard tab UI and related helpers.
- `clash_widgets/ProfileDetailView.swift`
  - Profile tab UI and related helpers.
- `clash_widgets/SettingsView.swift`
  - Settings tab UI, including feedback and maintenance sections.
- `clash_widgets/EquipmentTabView.swift`
  - Equipment tab wrapper and tab-specific UI composition.
- `clash_widgets/BoostView.swift`
  - Boost manager/editor views and supporting helpers.
- `clash_widgets/ContentView+Ads.swift`
  - Ad-specific views/helpers currently embedded in ContentView.
- `clash_widgets/ContentView+DebugMenu.swift`
  - Debug-only or developer-facing utility views/menu targets.
- `clash_widgets/ContentView+Compat.swift`
  - Compatibility wrappers and cross-version helper modifiers.

### DataService family
- `clash_widgets/DataService.swift`
  - Core type declaration, published state, static keys/constants, init/bootstrap, shared core utilities only.
- `clash_widgets/DataService+Profiles.swift`
  - Profile CRUD/selection/display/tag checks.
- `clash_widgets/DataService+Persistence.swift`
  - Load/save, app-group snapshot sync, ensure/default profile helpers.
- `clash_widgets/DataService+API.swift`
  - API refresh/fetch and request/cooldown limit paths.
- `clash_widgets/DataService+Notifications.swift`
  - Notification auth and scheduling.
- `clash_widgets/DataService+Import.swift`
  - Clipboard decode/sanitize/import and conversion pipeline.
- `clash_widgets/DataService+Durations.swift`
  - Duration/indexing/mapping loading helpers.
- `clash_widgets/DataService+Helpers.swift`
  - Helper cooldowns/level constraints/data loading.
- `clash_widgets/DataService+BoostTiming.swift`
  - Boost-aware remaining-time math and pruning.
- Existing extension files remain valid (`DataService+Parsing.swift`, `DataService+Progress.swift`).

## Behavioral Invariants (Must Not Change)
- Preserve ordering of side effects in state update paths:
  - mutate profile/state -> persist -> notification/widget updates (as currently implemented per path).
- Do not change app-group keys or UserDefaults keys.
- Keep widget data contracts intact (`PersistentStore`, app-group payloads, widget profile selection).
- Keep boost-aware timing parity between app and widget code paths.
- Keep notification profile context behavior (profile id/name propagation and tap-to-switch support).

## Debug UI Policy
- Debug utilities must be isolated in `ContentView+DebugMenu.swift`.
- Access pattern: hidden via **triple tap** on the feedback caption text
  - “Report bugs, glitches, or share ideas.” in Settings.
- Keep debug tools available, but not prominently visible in normal UX.

## Xcode Project Wiring Requirement
- Any new Swift file must be added to `clash_widgets.xcodeproj/project.pbxproj` under the app target’s Sources build phase.
- Do not leave duplicate type declarations across old/new files.

## Refactor Process Rules
- Move code first, then adjust references.
- Keep signatures and access control unchanged unless required by file boundary.
- Prefer same-type extensions (`extension ContentView`, `extension DataService`) for minimal risk.
- Avoid opportunistic cleanup unrelated to the split.

## Verification Checklist (after each refactor slice)
- App builds for `clash_widgets` scheme.
- Widget builds for `ClashDashWidget` scheme.
- Onboarding submission still creates/updates profile state correctly.
- Widget import request handling still works.
- Notification scheduling behavior unchanged.
- War/clan/profile refresh cooldown paths unchanged.
- Hidden debug menu is reachable via requested triple-tap gesture.
