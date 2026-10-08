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

Each event requires `id`, `enabled`, `start`, `end`, `presentation`, and `modifiers`. An optional top-level `icon` uses the image schema below and appears on the left of its Home event card (48 × 48 points). It is separate from `presentation.image`, which is the detail-page artwork. Older feeds can omit `icon`. Dates must be UTC in `YYYY-MM-DDTHH:MM:SSZ` format. Before `start` it is upcoming; from `start` up to but excluding `end` it is active; at/after `end` it disappears. This uses the device clock and cached timestamps, without a network request at the boundary. Home and detail countdowns use `xx Days hh:mm:ss` (for example `02 Days 03:04:05`).

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

- Imports during an active event receive the discounted full-duration cap at their import timestamp. Already discounted remaining times below that cap stay unchanged; the app never simply halves an exported remaining timer.
- A timer tracked before an active event can be capped at `event.start + baseDuration × Gold Pass at import × event factor`. If its existing end is earlier, keep it. Late launches use the event start timestamp, not the time the app was opened. Existing potion/helper credit is retained for the downstream boost calculations.
- The event multiplier is persisted on each upgrade and used by duration labels and app/widget progress bars, including after the event ends. Applied event IDs are persisted alongside the adjusted end date, so repeated launches cannot halve it repeatedly. Existing saves decode with default values. For legacy upgrades without a stored Gold Pass snapshot, the profile's current selection is used.
- The app does not restore the original duration when the event ends. It ignores events first encountered after they have ended, matching the simplified proposal. **There is no reconstruction of an entirely missed event. Reimport Clash data to correct stale timers in that case.**
- Reconciliation handles all saved villages and persists the result to app-group storage, reloads widgets, and reschedules notifications. The app checks local state while open and on return to the foreground. It does not run a background service: widgets/notifications cannot be guaranteed to reflect a newly started event while the app has never opened since its start. Open the app to sync them.
- Event rules are data, not downloadable code. New mechanics, automatic resource mapping, new calculation categories, new bundled assets, or changes to the native layouts require an app build.

## Images

The event card icon can be configured independently:

```json
{ "icon": { "source": "remote", "value": "https://raw.githubusercontent.com/Zacatac3/clash_widgets/main/remote/images/builder.png" } }
```

The Hammer Jam test uses the existing `remote/images/builder.png`. If its icon cannot load, the card displays a calendar symbol while keeping its title and countdown.

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

The app renders saved content immediately. On launch/foreground it fetches the events and latest-news pointer if the last successful refresh was at least 24 hours ago. It downloads the full news feed only if the latest ID is missing locally or there is no initial cache. Failed fetches retain the cache and allow a retry after 15 minutes. Pull to refresh bypasses both intervals. In Settings → Debug, **Grab Remote Files Now** also bypasses both intervals and always downloads all three JSON files, including the full news feed even if its latest ID is already cached. It reports success/failure, shows cache counts and the source URL, and immediately reconciles the refreshed events. New content is not a push notification and may take a day to reach an active installation, or longer if the app is not opened/offline. Publish event dates at least a couple of days early.

Run before publishing:

```sh
python3 tools/validate_remote_content.py
```

A GitHub Actions workflow runs the same validation for feed changes. This validates JSON consistency; it does not verify that the game rules or remote image URLs are correct.

Run the shared Swift timer/schema checks from the repository root:

```sh
xcrun swiftc -module-cache-path /tmp/clashboard-swift-module-cache clash_widgets/Models.swift clash_widgets/RemoteContentModels.swift tools/remote_content_tests/main.swift -o /tmp/clashboard-remote-tests
/tmp/clashboard-remote-tests
```

The normal Xcode app build covers the native screens and app/widget model compatibility.

## Current active test

`remote/latest_event.json` includes `hammer-jam-test-2026-10-v1`, enabled from October 6 at 08:00 UTC through October 20 at 08:00 UTC (4:00 AM Eastern on both dates). The matching latest announcement is `hammer-jam-test-announcement-2026-10-v1`.

Publish all three live JSON files together to test remote fetching, then open Help (?) → News and pull to refresh. No feed is bundled automatically: local edits alone do not reach the app. The Supercharge exclusion support added with this test requires running the updated app build. New or edited content afterward can be changed through JSON.

The test follows the reductions and collector bonus described in [Supercell’s November 2025 announcement](https://supercell.com/en/games/clashofclans/blog/news/hammer-jam-kickstarts-the-november-season/). Only timer and wall-cost rules are calculated by Clashboard; collector bonuses and other resource cost reductions are informational. Disable or remove the test event when finished. Already applied timer changes are preserved, so use a test village or reimport actual Clash data afterward.

## Five-minute lifecycle test (no publishing required)

Use **Settings → Debug → Event Testing → Start 5-Minute Hammer Jam Test** in the updated app. This creates and selects **Event Test (Synthetic)**. It has synthetic 20-minute timers and a partial wall inventory. Notifications are off for this fixture. The event and profile persist through restarts. The test event applies only to this profile; regular feeds continue to apply only to real profiles.

| Stage | What to verify |
| --- | --- |
| First 30 seconds | Home shows an upcoming test event and a live start countdown. Timers have no event strikethrough or discount. Wall prices use the normal multiplier. |
| Event starts | Cannon, Barbarian research and L.A.S.S.I timers are capped at 10 minutes from the event start. Their full durations show 20 minutes crossed out above 10 minutes. With optional 20% Gold Pass, the full-duration label changes from 16 minutes to 8 minutes. |
| Exclusions | Builder Base Cannon, Archer Tower Supercharge and Crafted Defense module do not receive an event multiplier or strikethrough. |
| During the five minutes | Open the event details. Restart the app and confirm no second reduction. Optionally use **Add Test Upgrade During / After Event** to simulate importing a Barbarian King upgrade during the event; it receives the same cap. |
| Exact event end | Home's event card disappears. Wall prices return to normal. Previously reduced timer deadlines and labels remain reduced. They do not double again. |
| After expiry | If the extra test upgrade was not added earlier, use **Add Test Upgrade During / After Event** now. Barbarian King keeps its normal imported countdown and has no event strikethrough. |
| Cleanup | **Remove Test and Test Profile** removes the synthetic profile and local event, and restores the previously selected real profile if still present. |

Run twice to check importing during the event and importing after expiry (the extra-upgrade button adds one hero per test). Run again with Gold Pass enabled. Use the fixture to test native red Cancel / blue Complete swipe actions; completing Cannon, Barbarian, L.A.S.S.I, or the Crafted Defense module advances that item's Progress entry. Enable Temporary Content in Progress to inspect Supercharges and Crafted Defenses.

This local test exercises the app's actual event reconciliation, persistence, Home card, detail page, countdowns and wall calculations. It does **not** test HTTP downloads, news popups, or the contents of a separately published feed. For those, use the remote workflow below.

### Remote publishing check

For an actual short remote event, use a fresh event ID and UTC `start` / `end` dates five minutes apart, with enough lead time to publish and fetch before `start`. Keep the same modifiers and icon as the event you want to test. Run the validator, publish the feed, then use **Grab Remote Files Now** and confirm success while the event is still upcoming. A normal restart may use the daily cache, so do not rely on restarting to fetch a five-minute event.

Publishing to the configured production feed affects other app installations too. Use the separate `remote_dev` feed through **Grab Remote Dev Files** for remote testing (see below). Test with disposable exported village data: reductions already applied to an upgrade are retained after event removal or expiry, and changing the event ID may make it a new event.

For malformed JSON/schema, leave a valid feed cached, publish the invalid payload on staging, and force-refresh: the refresh should report failure while the valid cache remains available. Restore the valid feed afterward. Also check the news pointer and full feed together, remote icon loading, offline cache behavior, per-Town-Hall rules, disabled events, and overlapping events. The Swift regression harness covers exact time boundaries, Gold Pass, exclusions, idempotence, skipped events, imported upgrades, and restart persistence.

## Separate development feed

`remote_dev/` now mirrors `remote/` in the same repository. Its JSON uses the same schema, and its image URLs point to `/remote_dev/images/`. Default app installations keep using `/remote`.

1. Edit the event/news payloads in `remote_dev/`. Give each new test event a fresh ID and suitable UTC dates.
2. Run `python3 tools/validate_remote_content.py remote_dev`, then commit and push that folder.
3. In the updated app, use **Settings → Debug → Grab Remote Dev Files**, directly below the live refresh button. Wait for the Development success message and check the active URL.
4. Inspect Home/News and test the event. Home displays **Development Feed Active**. The selected feed persists through restarts and normal refreshes.
5. Use **Grab Remote Files Now** to return to Live.

The two environments have independent event/news caches, last-attempt/last-success times, and last-seen news IDs. Existing live cache keys remain compatible with older builds. Development event IDs receive an internal `dev:` prefix so a copied test event ID does not mark the live event as already processed. An invalid/unavailable development feed keeps its own cached content; it does not overwrite or fall back to the live cache.

Only installations explicitly selecting Development use this folder. Test events still modify the local tracker on that installation, and switching feeds does not undo applied timer reductions. Use disposable profiles or reimport real village data afterward. If the synthetic five-minute fixture exists, its local event is paused in Development so that fixture can receive the downloaded dev events instead.

GitHub Actions validates both folders independently. No new app build is needed for later dev payload changes after installing the build containing this environment switch.
