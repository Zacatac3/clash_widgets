# Performance audit — 2026-11-16

Scope: current working tree, including pre-existing uncommitted performance changes. The initial audit did not modify application source; the follow-up below implements targeted fixes. This is source inspection plus isolated macOS checks, not a physical-device launch/energy profile.

## Implementation follow-up

Implemented after the audit, preserving the existing screen layout, category-jump behavior, countdown formatting, persistence ordering, notification behavior, and original export artwork:

- Parse duration tables and indexing from the same JSON reads, preserving last-wins duration overrides and first-wins indexing precedence.
- Cache immutable bundled wall tables and helper definitions. Player levels, discounts, and derived costs remain reactive.
- Cache the last decoded player export by exact input string, including invalid input; content changes invalidate naturally.
- Serialize Progress image preparation off the main thread, reuse cached results for concurrent requests, and skip queued work when its view task is cancelled.
- Load Town Hall badge thumbnails off the main thread at the actual display scale. Original assets remain intact. Simulator checks measured 144×144 / 82,944-byte cached bitmaps at 3x, versus 4096×4096 source dimensions; this is not a measurement of total application memory savings.
- Stop the boost-manager timer when both boost and undo lists are empty. Avoid no-op published array mutations on active ticks; retain the one-second active countdown cadence. Cache trimmed helper icons in the boost sheet.
- Calculate Equipment groups once per section render and ore totals once per summary render. Preserve ordering and filters while removing redundant per-group sorts.

Validation: Debug and Release simulator builds; differential duration/wall/helper/export/equipment checks; actual boost timer lifecycle checks; simulator image checks; existing catalog, import, multi-account/persistence, and remote-content idle regression suites. Commands and details are in `tools/performance_tests/README.md`.

Deliberately left for a measured follow-up:

- Replacing Progress's layout with lazy containers can change category-jump positioning and scroll geometry. Its image work is now bounded/cancellable, but the layout itself remains unchanged.
- Moving all DataService initialization off-thread requires a readiness/lifecycle change. Duplicate duration parsing was removed without exposing partially initialized state.
- Builder-row timer cadence remains unchanged to preserve exact countdown/boost timing and progress-bar updates.
- Persistence coalescing and widget-reload deduplication remain unchanged because their ordering affects background transitions and widget freshness.
- Ad SDK startup, full-screen layout cost, and actual device energy remain unprofiled. No claim is made that these changes eliminate the reported 3–5 second stalls.

The findings below describe the original audit snapshot, before these fixes.

## Findings, in recommended investigation order

### 1. Progress creates its entire screen on first visit

`clash_widgets/ContentView/ProgressView.swift:39` uses a regular VStack around all sections; structure groups also use regular VStacks, and the tile grid is a custom Layout. The catalog contains 150 items, plus separately rendered equipment. Each structure image starts a detached user-initiated image-processing task (`:782`). Although pixel trimming is off the main thread, eager view creation can start a burst of concurrent image work and state updates for content below the viewport. Cancellation of the view task does not automatically cancel its detached task.

Suggested change: make section/row creation lazy and bound image-processing concurrency. Preserve category jump behavior, scrolling, and screenshot export; verify those explicitly before replacing the layout. Downsample icons to their actual display size and cache those results.

### 2. Oversized source images are used for tiny badges

TH13 and TH18 assets are 4096×4096 PNGs. `ContentView.swift:502` loads Town Hall assets with UIImage(named:) and displays them at 48 points. Settings uses this badge for profile rows (`SettingsView.swift:403`). A full 4-byte-per-pixel decode of either image is 64 MiB; this is a pixel-size calculation, not measured runtime allocation. The profile palette path also loads the image before dispatching color extraction to a background queue (`ProfileDetailView.swift:408`).

Suggested change: provide small badge variants or downsample before rendering. Keep high-resolution originals for outputs that need them. Measure image decode and texture upload during first visits; source dimensions alone do not prove the observed stall.

### 3. Synchronous catalog work occurs during startup and first rendering

`DataService.swift:239` synchronously loads saved state, upgrade durations, parsed buildings, Town Hall limits, name mappings, mini levels, helper levels, and cached war/clan data during initialization. Duration loading parses the same nine source files separately for durations and indexing (`:1627`, `:1705`). `ProgressCatalog.sections` (`ProgressView.swift:1060`) synchronously initializes the full catalog on first access; Profile's hero showcase also accesses this catalog (`ProfileDetailView.swift:898`).

Suggested change: build an immutable catalog snapshot once off the UI thread and publish readiness. Preserve file precedence and initialization dependencies. Do not simply dispatch methods on the mutable DataService instance concurrently.

The export decode calls after `Task.yield()` in Profile and Progress remain synchronous work in their UI tasks. Yielding postpones the work; it does not move decoding to a worker.

### 4. Home repeatedly parses bundled data while constructing views

`DashboardView.swift:1550` computes wallMaxLevelForTH and wallProgressData. Those paths together call loadBuildingCosts three times, each reading and parsing the complete buildings JSON. The same render also reads Town Hall limits and decodes the player's raw export (`:1368`, `:1470`, `:1525`). Subsequent DataService/remote-content changes can repeat this work.

`ProfileDetailView.swift:780` similarly reads and decodes villager_apprentices.json whenever its helper-cost card is constructed.

Suggested change: cache immutable bundled tables; derive player-specific results from a decoded export keyed to profile/content revision. Keep current levels, Town Hall, and discount settings reactive.

### 5. Timer frequency exceeds the displayed precision

`BuilderRow.swift:194` and `:212` each use a one-second TimelineView, for the progress bar and countdown respectively. With full precision disabled, hour/day countdowns omit seconds, yet still reevaluate every second. Below one hour the current formatter intentionally shows seconds, so a blanket one-minute interval would be incorrect.

`BoostView.swift:250` wakes every second, checks both published arrays and sends objectWillChange unconditionally, even when the boost manager has no active work. Boost tiles also perform uncached pixel trimming in their view construction. This manager is associated with the boost sheet; it is not evidence of a permanent app-wide idle timer.

Suggested change: adapt countdown cadence to displayed precision and expiry boundaries, slow progress-bar refreshes, schedule boost expiry at actual boundaries, and cache boost images. Confirm hidden tabs/sheets stop unnecessary updates with a trace.

### 6. Persistence and widget refreshes can duplicate work

`DataService+Persistence.swift:5` queues state writes, but legacy defaults mirroring, upgrade encoding and synchronize() still run on the calling thread (`:30–40`). Property observers can invoke persistence repeatedly; for example cachedProfile also sets profileName, and both persist (`DataService.swift:80`). Foreground widget reloads are requested from both the app and ContentView (`clash_widgetsApp.swift:130`, `ContentView.swift:201`).

Suggested change: coalesce state snapshots and widget reload requests, avoid redundant defaults writes, and investigate notification rescheduling in the same trace. WidgetKit may coalesce requests itself; duplicate API calls are not proof of duplicate completed reloads.

### 7. Equipment repeatedly rebuilds the same derived collections

`EquipmentTabView.swift:186–290` recomputes equipment entries, filtering, sorting, grouping and ore totals through multiple computed-property accesses. The per-hero loop accesses groupedEntries again for each hero, and the summary accesses totalOreCost twice.

Suggested change: calculate one presentation snapshot per input revision/filter change. This is lower priority than first-render/image work; the data set is relatively small.

## Checks performed

- `python3 tools/performance_tests/run.py`: PASS. Zero shared-service objectWillChange notifications during 3.2 seconds idle; event start/expiry, cancellation, scheduled news and no polling after expiry also passed. The existing event-boundary scheduling fix is working in this harness.
- Extracted the production ProgressCatalog into a temporary Foundation-only Swift executable using the repository's Models.swift and current JSON. Cold catalog construction: **15.49 ms at -Onone**, **15.56 ms at -O**, 150 catalog items. One process sample per configuration, not a statistical benchmark.
- In that executable, 300 repeated reads/parses of buildings.json: mean **2.00 ms per three reads at -Onone**, **1.95 ms at -O**. This isolates JSON read/parse/filter work, not full wall-summary rendering.
- Inspected 360 PNG headers: 11 exceed one megapixel; the two Town Hall images above are 4096×4096.
- Project settings use **-Onone for Debug** and **-O for Release** (`project.pbxproj:554`, `:588`).

These results do not reproduce or explain a 3–5 second freeze across all tabs. They identify actual avoidable work and likely cold-render pressure without assigning an unmeasured root cause. Existing Progress image offloading, bounded image caches, and remote-content scheduling changes were present before this audit.

## Device verification needed

1. Compare the same saved data on the same device using Debug under Xcode, Debug launched independently, and Release launched independently. Separate process-cold launch from first launch after installation, without deleting user data.
2. Record first visit to Home, Profile, Progress, Equipment and Settings, then repeat the circuit. Capture a main-thread/time-profiler and hang trace across the stalls. Check image decoding, SwiftUI layout, catalog loading, persistence and ad initialization stacks.
3. After startup/network activity settles, record one minute idle on Home and Settings. Compare CPU/wakeups and energy before/after targeted fixes; a startup energy label alone does not establish sustained idle consumption.
4. Repeat with the existing ad-free state if available, and compare banner versus full-screen settings. Ad SDK/consent initialization is present at launch, but its cost was not measured here.
5. Validate category navigation, countdown expiry, profile switching, export previews and widget freshness after any implementation changes.
