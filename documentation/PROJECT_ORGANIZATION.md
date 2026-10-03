# Clashboard organization and file audit

Audit date: October 3, 2026. Recommendations only: no existing files were moved, renamed, or removed. Evidence: current Swift references, Xcode targets/build phases and schemes, utility scripts, and the most recent successful simulator build's `Clashboard.app` bundle. “No references found” is a static finding, not a claim that historical data has no value. Dynamically generated asset names prevent a reliable unused-image list from a simple text search.

## Recommended approach

Keep all Swift files, asset catalogs, project files, entitlements, and live game-data paths in place for this cleanup. First organize Xcode with **virtual groups**, then organize development documents, samples, and historical exports outside the app resource folder. Split large source files in a later, separate refactor.

Virtual groups have no filesystem path of their own. When grouping existing references, preserve each file's resolved path and target membership; use navigator-only groups and adjust reference paths if necessary. Avoid Xcode's folder-moving options. Build both targets after any project-reference change.

Suggested Xcode navigator hierarchy (not physical directories):

```text
Clashboard
  App
    clash_widgetsApp.swift
    ContentView.swift
    ContentView+Compat.swift
  Features
    Dashboard          DashboardView.swift, BuilderRow.swift
    Progress           ProgressView.swift, ProgressScreenshotView.swift
    Equipment          EquipmentTabView.swift
    Profiles           ProfileDetailView.swift
    Onboarding         OnboardingSetupView.swift
    Boosts             BoostView.swift
    Settings           SettingsView.swift, existing Settings page files
    Help               HelpAndWhatsNewView.swift
  Services
    Data               DataService.swift and DataService+*.swift
    Notifications      NotificationManager.swift
    Monetization       IAPManager.swift, AdsView.swift
  Shared with Widget
    Models.swift
    PlayerAccount.swift
    PersistentStore.swift
  Developer Tools
    ContentView+DebugMenu.swift
  Resources
    existing json folder reference and Assets.xcassets
    generate_screenshot_backgrounds.sh build script
Widget Extension
  ClashDashWidget.swift, ClashDashWidgetBundle.swift
  existing widget assets and configuration
```

`ContentView/` currently means much more than the root screen. Virtual feature groups make that clearer without renaming it. `Models.swift`, `PlayerAccount.swift`, and `PersistentStore.swift` are compiled into **both** targets; preserving that membership matters.

Suggested physical structure for future non-Swift cleanup:

```text
repository/
  clash_widgets/                 existing app source/resources: leave in place
  ClashDashWidget/               existing widget source/resources: leave in place
  clash_widgets.xcodeproj/        leave in place
  clash_widgetsUITests/           retain and wire into a test target later
  docs/
    PROJECT_ORGANIZATION.md
    architecture/                refactor instructions and implementation notes
    releases/                    release procedure and development planning notes
  tools/                         small standalone utilities
  data_extraction/               keep pipeline scripts and current input paths
    extraxted_data/               keep spelling/path until pipeline migration
      previous version/          historical input: preserve for comparison
  fixtures/
    player/                      json_files player exports and samples
    clan/                        misc_files clan/war samples
    notes/                       RTF experiments and research
  archive/
    game-data/                   json_backup moved outside the bundled json folder
    legacy/                      unused templates and old scripts worth preserving
```

The proposed `fixtures/` relocation needs an Xcode-reference adjustment for `misc_files/clan_stats.json`, which is explicitly copied into the app today. Other sample files have no runtime references found. Retain old exports elsewhere if you need them; they need not stay beside the source.

## Required or actively used paths

| Path | Why it stays |
| --- | --- |
| `clash_widgets.xcodeproj/project.pbxproj` | Target membership, build phases, packages, configuration, and resource paths. |
| Shared schemes and `project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | Repeatable app/widget builds, StoreKit setup, dependency versions. |
| `clash-widgets-Info.plist` | Explicit app Info.plist input in Debug and Release. |
| `ClashDashWidget/Info.plist` | Explicit widget Info.plist input. |
| `clash_widgets/clash_widgets.entitlements` | Active app signing entitlements. |
| Root `ClashDashWidgetExtension.entitlements` | Active widget signing entitlements in both configurations. |
| `Products.storekit` | Both shared schemes reference it for local purchase testing. The project has two references to the same file; consolidate references later, keep the file. |
| `clash_widgets/Assets.xcassets` and `ClashDashWidget/Assets.xcassets` | Both catalogs currently feed the widget Resources phase; app catalog also feeds the app. Do not remove apparent duplicates without checking compiled names and widget use. |
| `clash_widgets/scripts/generate_screenshot_backgrounds.sh` | Required build phase generates `ScreenshotBackgrounds.txt` in the built app. This output is not a missing repository source file. |
| `clash_widgets/json/parsed_json_files/` | Upgrade costs, times, levels, counts, unlocks, helpers, seasonal defenses, and supercharges. Keep generated names/paths. |
| `clash_widgets/json/json_maps/` | Runtime naming plus parser-maintained display-name metadata and debug lookups. Keep filenames and curated names. |
| `mapping.json`, `asset_map.json` | ID/name and name/image resolution in multiple consumers. |
| `equipment_data.json`, `heroes_config.json`, `ore_costs.csv` | Equipment/hero definitions, ordering, icons, and costs. |
| `progress_sections.json` | Progress catalog configuration. |
| `game_constants.json` | Maximum Town Hall, wall counts, and other game-dependent rules. |
| `gradient_config.json` | Profile Town Hall gradient configuration. |
| `json/master_lists/home_village_master_upgrades.json` and `builder_base_master_upgrades.json` | Read by the Master List debug view. Debug-only does not mean unused. |
| `data_extraction/clash_csv_to_json.py` and current `extraxted_data/*.csv` | Active development pipeline produces parsed data/maps using explicit paths. Not needed at runtime. |
| `data_extraction/process_logic.sh` | Documented extraction step; expects `logic/` and writes `processed_csvs/` relative to the working directory, with external `sce`. |
| `json/UPDATE_GUIDE.md`, master-list README, root README and update procedure | Maintenance documentation; useful but need not be bundled. Keep relative links valid if relocated. |
| `.vscode/settings.json`, `buildServer.json` | Local editor/build-server setup. Not app resources. `buildServer.json` contains machine-specific absolute paths. |

The `json` directory is an Xcode **folder reference**. Everything in it is copied into the app, including backups and Markdown documents. A directory being bundled does not prove that the application reads it.

## Unused, legacy, and removal/archive candidates

| File/path | Evidence | Recommendation |
| --- | --- | --- |
| `clash_widgets/BannerAdView.swift` | Comment-only placeholder, absent from Sources. Actual implementation is in `ContentView/AdsView.swift`. | Remove later; no implementation to preserve. |
| `clash_widgets/InterstitialAdManager.swift` | Comment-only placeholder, absent from Sources. Actual implementation is in `ContentView/AdsView.swift`. | Remove later. |
| `clash_widgets/EquipmentView.swift` | Comment-only placeholder, absent from Sources. Current equipment UI is in `ContentView/EquipmentTabView.swift`. | Remove later. |
| `clash_widgets/ImageTrimmer.swift` | Absent from Sources; no callers of `ImageTrimmer`. Separate local trimming functions are still used in other files. | Archive/remove this file; do not remove the working local functions. |
| `clash_widgets/WidgetProfileIntent.swift` | Absent from both Sources phases. Active `WidgetProfileIntent` is defined in `ClashDashWidget.swift`; old file uses a different profile-selection representation/key. | Archive/remove old file; do not add it to Sources, which would conflict with the active declaration. |
| `clash_widgets/APIClient.swift` | Compiled, but no references to `APIClient` or calls to its `fetchPlayerProfile` found outside the declaration. Networking exists in DataService. | Candidate for removal in a separate change; remove project entries and build both targets. |
| `clash_widgets/SecurityHelper.swift` | Compiled, but no external references to `SecurityHelper` found. | Candidate for removal in a separate change, followed by a build. |
| `clash_widgets/ClashDashWidgetExtension.entitlements` | Identical to the root version; build settings select the root version. | Redundant copy; preserve root active file. |
| `clash_widgets/json/json_backup/` | Included in built app, no direct loader references to this backup folder found. About 1.2 MB. 7 files match current files; 18 differ or are unique. | Move to `archive/game-data/`, outside bundled resources. Preserve historical versions. |
| `clash_widgets/json/ingameunits.json` | Included in built app, no references to its name found in Swift/scripts. | Archive/remove candidate. |
| `clash_widgets/json/master_lists/profile_upgrade_state_template.json` | README describes a future planner template; no runtime reader found. Included in bundle. | Keep as a design template outside runtime resources. |
| `clash_widgets/upgrade_info/master_lists/home_village_master_upgrades.json` | Zero-byte file, outside the active bundled json folder. | Remove empty legacy remnant later. |
| `misc_files/clan_stats.json` | Explicit Xcode resource, present in built app, but no bundle reader for this sample found in Swift. Clan caching uses similarly named UserDefaults keys, not this file. | Unused-resource candidate; remove build reference before moving/removing. |
| Remaining `misc_files/*` | Sample JSON, RTF experiments, notes, and plugin XML; no runtime references found. `features.txt` is discussed separately below. | Organize as fixtures and notes, preserve useful examples. |
| `json_files/*` | Sample player exports and mapped-building CSV, no runtime or current parser references found. | Move to player fixtures/research data. |
| `data_extraction/extraxted_data/previous version/` | Historical CSV inputs; current parser reads the parent directory's current files. 3 match current files; 10 differ or are unique. | Keep history, clearly label it. No need to relocate unless updating documentation. |
| `data_extraction/swap_buildings_json_map.py` | Targets nonexistent `clash_widgets/upgrade_info/json_maps/buildings_json_map.json`. Swaps every entry's display/internal names. | Archive as a one-time migration. Do not simply repoint and run it on live data. |
| `tools/generate_asset_names.py` | Looks for an old inline mapping dictionary in DataService. Read-only execution currently prints `{}`. | Update to read `json/mapping.json`, or archive. |
| `Clash_widgets.ipa` and `Payload/` | Tracked historical distribution artifacts, approximately 50 MB each; no current build dependencies found. | Move outside source control or into release storage if historical binaries matter. Removing current files does not erase Git history. |
| `.VSCodeCounter/` | Tracked historical generated line-count reports, no build dependencies. | Remove/archive and ignore new reports. |
| `.DS_Store`, `__pycache__/`, `.venv/` | Finder metadata, Python bytecode, local environment. | Ignore regenerated files; remove tracked metadata from Git separately. `.venv` did not appear in the tracked-file check. |
| ColorKit Swift package | Linked by the project; no Swift imports or symbol references found. UIImageColors is actively used. | Review ColorKit for dependency removal separately; retain UIImageColors and Google Ads/UMP. |

Do not classify assets as unused using filename search alone: many names are derived from JSON, game levels, namespaces, and user-selected backgrounds.

## Wiring and documentation issues

1. **Changelog input is not bundled.** `HelpAndWhatsNewView.loadChangelog()` requests root-bundle `changelog.txt`. The root file is not in the Resources phase and was absent from the built bundle inspected. The view falls back to “Changelog not available.” Preserve the text and fix resource membership; it is not an unused-file candidate.
2. **Features text is not bundled.** `DataService+Parsing.swift` has a loader for root-bundle `features.txt`, while the repository file lives at `misc_files/features.txt` without a resource entry. The loader has hardcoded fallback content. Separately, the visible help flow calls `defaultWhatsNewSections()`; establish the desired source of truth before assuming this file drives current UI.
3. **UI test source is not wired.** `clash_widgetsUITests/OnboardingUITests.swift` exists, but the project has only app and widget targets, and the app scheme's TestAction lists no testables. Keep the test as intended coverage; create/wire a UI test target later.
4. **Old `upgrade_info` metadata remains.** Master-list `sourceFiles` metadata and the future profile-state template still mention `upgrade_info/...` paths. Actual debug loaders use `json/master_lists`. Update metadata/docs rather than moving working game data to those old paths.
5. **Placeholder comments are stale.** They say ads/equipment live in ContentView.swift; the active implementations are already in dedicated feature files.
6. **The gitignore is empty.** Add rules for Finder metadata, Python caches/environments, build outputs, Xcode user state, and generated reports. Keep shared schemes and Package.resolved tracked. Ignore rules do not untrack existing files.
7. **Project navigator duplicates exist.** Two Products.storekit references point at the same file. Consolidate references without removing the scheme's configuration file.

## Recommended sequence

1. Add/document navigator-only App, Features, Services, Shared, Resources, and Developer Tools groups, keeping Swift filesystem paths and target membership intact.
2. Add sensible ignore rules and stop tracking regenerable metadata/build artifacts in a dedicated cleanup commit.
3. Move bundled historical backups and future-only templates outside `clash_widgets/json`; retain all live data paths. Check the built resource tree afterward.
4. Consolidate non-runtime docs, fixtures, and one-time scripts, updating only their project references and relative documentation links where needed.
5. Fix changelog resource wiring and the UI test target in their own focused changes.
6. Remove compiled-but-unreferenced utilities and unnecessary package dependencies separately, verifying app and widget builds after each change.

## Later code boundaries, without doing them now

The largest files are `ClashDashWidget.swift` (~2,635 lines), `DataService.swift` (~2,509), `ContentView+DebugMenu.swift` (~2,102), `DashboardView.swift` (~1,744), and `ProfileDetailView.swift` (~1,356). Moving them would not by itself improve their responsibilities.

- Keep DataService as the observable coordinator; isolate networking, import, game catalogs, and boost timing behind focused helpers/extensions, following the existing refactor instructions. Preserve persistence/notification/widget side-effect order.
- ProgressView currently also owns ProgressCatalog. EquipmentTabView also owns EquipmentDataStore and HeroConfigStore. Longer term, these catalogs should be available independently of their screens.
- Centralize resource lookup policy before changing any live JSON paths; loaders currently have multiple bundle/app-group fallbacks.
- Consolidate image-trimming and asset-name resolution only after comparing behavior: several active implementations exist and are not automatically equivalent.
- Separate widget timeline providers from widget rendering in a later refactor; preserve app/widget timer parity and storage keys.
- Document boundaries between app-only services and the three shared model/storage source files rather than assuming files belong to only one target.

This audit did not change app behavior or run destructive cleanup scripts. It used the existing build artifact for bundle inspection; no new build was needed for this documentation-only addition.
