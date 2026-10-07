# Remote news and events

The app can now read native news articles and event configuration from a public HTTPS folder. The default URL in `clash-widgets-Info.plist` is:

`https://raw.githubusercontent.com/Zacatac3/clash_widgets/main/remote`

## Your initial setup

1. Decide where to host the three feed files. The default uses this repository's `main` branch. **The repository and branch must be publicly readable without signing in.** If this repository is private, create a separate public content repository, copy `remote/` there, and change `RemoteContentBaseURL` in `clash-widgets-Info.plist` before building. No GitHub token is needed or should be put in the app.
2. Commit and push the implementation and the live files in `remote/` (currently populated with test content). If using another host, publish the three files there. `remote/examples/` is documentation only; the app never reads it.
3. Confirm the base URL plus `/latest_event.json`, `/latest_news.json`, and `/news_feed.json` returns raw JSON without authentication. `main` is the configured branch; change the URL if you use a different branch.
4. Run the app on a device or simulator, complete setup, then open **Home → Help (?) → News**. Pull to refresh forces a check, which is useful while testing.
5. Publish a temporary news article with a unique ID, a past UTC `published` date, and `showAsPopup: true`. Restart the app on an already seen build to test the popup. Reading/dismissing it marks it seen. With a new build, What’s New takes priority and news stays unread until the next launch. Verify the image, article, and countdowns on iPhone and iPad.
6. Test a short event against a test village/export before publishing real rules. Check timers, wall costs, widgets after opening the app, and notifications.
7. Ship **one new app build** containing this infrastructure. Older installed builds cannot use it. Subsequent supported content changes require only publishing the JSON/images.

Nothing has been pushed to GitHub or released by this implementation. The live feed files now contain an enabled Hammer Jam test (October 6–20, 2026) and a matching announcement. These are test dates, not confirmed game dates; publish them only when you intend to test tracker adjustments. The example under `remote/examples/` stays disabled.

## Publishing news

News lives in the third tab of the Welcome/What’s New sheet. Home begins with Selected Profile, followed by an Events section only when enabled upcoming/active events exist, then the reorderable cards. Expired and disabled events do not leave an empty section.

- Copy the structure in `remote/examples/news_feed.json`. Put new entries in the live `news_feed.json` while keeping previous entries for the archive.
- Each entry requires a stable unique string `id`, UTC `published`, `showAsPopup`, and `presentation`. `presentation` requires `title`, `summary`, and `sections` (which can be empty). Sections require `title` and `body`; images are optional.
- Set `latest_news.json` to `{ "schemaVersion": 1, "id": "your-new-entry-id" }`. The ID must match the newest article in the feed. Use `null` for an initially empty feed.
- **Publish the feed and images first, then the latest pointer**, preferably in one commit. If publishing isn't atomic, the app rejects a pointer whose entry is absent and keeps its previous cache.
- Give an edited announcement a **new ID** if devices should download the change. The latest pointer is deliberately a cheap ID check; editing an already cached entry under the same ID will not trigger a feed download.
- Only the newest article published by the current date can popup. Older missing articles are downloaded together and appear in the archive. `showAsPopup: false` adds an article without an automatic sheet. Avoid future-dated articles; publish when ready.
- Welcome/What’s New suppresses news popups for the rest of that launch. What’s New now checks both version and build number. Closing it does not stack a news modal immediately afterward.

## Publishing events

`latest_event.json` contains `{ "schemaVersion": 1, "events": [...] }`. Although its name is singular, it supports multiple simultaneous current/upcoming events, including information-only events with `modifiers: []`.

Copy `remote/examples/hammer_jam.json`, confirm the actual rules, supply a permanent unique ID, replace dates/copy, and set `enabled: true`. Keep event IDs stable across routine text edits; never reuse an ID for next year's event. Set `enabled: false` or remove an event to hide it and stop future modifiers. Already adjusted tracked timers stay adjusted; changes do not undo historical timer effects.

Each event requires `id`, `enabled`, `start`, `end`, `presentation`, and `modifiers`. Dates must be UTC in `YYYY-MM-DDTHH:MM:SSZ` format. Before `start` it is upcoming; from `start` up to but excluding `end` it is active; at/after `end` it disappears. This uses the device clock and cached timestamps, without a network request at the boundary.

Supported modifier fields:

| Field | Meaning |
| --- | --- |
| `categories` | Required array: `builderVillage`, `lab`, `pets`, `builderBase`, `starLab`, or `walls` |
| `timeMultiplier` | Optional duration factor in `(0, 1]`, e.g. `0.5` for half duration |
| `wallCostMultiplier` | Optional wall cost factor in `(0, 1]`; use category `walls` |
| `townHallMin`, `townHallMax` | Optional inclusive Town Hall bounds; defaults to all known Town Halls |
| `dataIDs` | Optional allow-list of exact exported upgrade IDs |
| `excludedDataIDs` | Optional deny-list of exported upgrade IDs |
| `excludeSupercharges` | Optional boolean; set `true` to exclude Supercharge upgrades from that rule |

Use separate rules for different Town Hall reductions. **Resource-conditioned Summer Jam rules currently require explicit `dataIDs` for the affected upgrades. There is no automatic resource-name selector.** Use IDs from the bundled mappings and verify against exports. Walls have no single exported upgrade ID, so wall rules should use category and Town Hall bounds only. Seasonal crafted defenses are excluded from timer shortening. Apply any other official exclusions explicitly.

When multiple rules/events match, the smallest factor wins; event reductions do not multiply with each other. Gold Pass and the chosen event factor multiply. Only displayed wall costs support event cost reductions today; other upgrade costs and ore costs are unaffected.

## Timer behavior and limits

- Imported remaining seconds are authoritative. Imports during an active event are not shortened a second time.
- A timer tracked before an active event can be capped at `event.start + baseDuration × Gold Pass at import × event factor`. If its existing end is earlier, keep it. Late launches use the event start timestamp, not the time the app was opened. Existing potion/helper credit is retained for the downstream boost calculations.
- Applied event IDs are persisted on each upgrade, alongside its adjusted end date, so repeated launches cannot halve it repeatedly. Existing saves decode with default values. For legacy upgrades without a stored Gold Pass snapshot, the profile's current selection is used.
- The app does not restore the original duration when the event ends. It ignores events first encountered after they have ended, matching the simplified proposal. **There is no reconstruction of an entirely missed event. Reimport Clash data to correct stale timers in that case.**
- Reconciliation handles all saved villages and persists the result to app-group storage, reloads widgets, and reschedules notifications. The app checks local state while open and on return to the foreground. It does not run a background service: widgets/notifications cannot be guaranteed to reflect a newly started event while the app has never opened since its start. Open the app to sync them.
- Event rules are data, not downloadable code. New mechanics, automatic resource mapping, new calculation categories, new bundled assets, or changes to the native layouts require an app build.

## Images

A `presentation` or section can include:

```json
{ "image": { "source": "remote", "value": "https://raw.githubusercontent.com/Zacatac3/clash_widgets/main/remote/images/rewards-v1.png" } }
```

Upload reward graphics to `remote/images/` or another HTTPS host. Use a new filename or URL whenever you replace an image; the app caches by URL. Images are limited to 8 MB and 8192 pixels per dimension, with a disk cache of up to 40 images. Failed or unknown images are omitted while article text remains readable. Full absolute HTTPS URLs let you migrate images to another host later without an app release.

Bundled images use `source: "bundle"` with one of the current allowed names:

- `extras/builder_potion`
- `extras/research_potion`
- `extras/pet_potion`
- `profile/gold_pass`
- `profile/free_pass`
- `changelog/home_example`
- `changelog/progress`
- `changelog/equipment`

To add more, ship the asset and extend the allow-list in `RemoteContentView.swift` and the publishing validator. There are no bundled Hammer Jam or Summer Jam banners yet; use a remote graphic if desired.

## Refreshing and validation

The app renders saved content immediately. On launch/foreground it fetches the events and latest-news pointer if the last successful refresh was at least 24 hours ago. It downloads the full news feed only if the latest ID is missing locally or there is no initial cache. Failed fetches retain the cache and allow a retry after 15 minutes. Pull to refresh bypasses both intervals. New content is not a push notification and may take a day to reach an active installation, or longer if the app is not opened/offline. Publish event dates at least a couple of days early.

Run before publishing:

```sh
python3 tools/validate_remote_content.py
```

A GitHub Actions workflow runs the same validation for feed changes. This validates JSON consistency; it does not verify that the game rules or remote image URLs are correct.

Run the shared Swift timer/schema checks from the repository root:

```sh
xcrun swiftc -module-cache-path /tmp/clashboard-swift-module-cache clash_widgets/RemoteContentModels.swift tools/remote_content_tests/main.swift -o /tmp/clashboard-remote-tests
/tmp/clashboard-remote-tests
```

The normal Xcode app build covers the native screens and app/widget model compatibility.

## Current active test

`remote/latest_event.json` includes `hammer-jam-test-2026-10-v1`, enabled from October 6 at 08:00 UTC through October 20 at 08:00 UTC (4:00 AM Eastern on both dates). The matching latest announcement is `hammer-jam-test-announcement-2026-10-v1`.

Publish all three live JSON files together to test remote fetching, then open Help (?) → News and pull to refresh. No feed is bundled automatically: local edits alone do not reach the app. The Supercharge exclusion support added with this test requires running the updated app build. New or edited content afterward can be changed through JSON.

The test follows the reductions and collector bonus described in [Supercell’s November 2025 announcement](https://supercell.com/en/games/clashofclans/blog/news/hammer-jam-kickstarts-the-november-season/). Only timer and wall-cost rules are calculated by Clashboard; collector bonuses and other resource cost reductions are informational. Disable or remove the test event when finished. Already applied timer changes are preserved, so use a test village or reimport actual Clash data afterward.
