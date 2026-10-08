# Events and news: quick publishing guide

Edit `remote/` for live content or `remote_dev/` for testing. Both use the same JSON structure. The app reads three files:

| File | Purpose |
| --- | --- |
| `latest_event.json` | All upcoming/active event definitions and their modifiers. |
| `news_feed.json` | News articles, including older articles for the archive. |
| `latest_news.json` | The ID of the newest article in `news_feed.json`. |

Use `schemaVersion: 1` in every file. Dates must be UTC strings such as `2030-06-01T08:00:00Z`. The dates below are placeholders; replace them before publishing.

## Events

With no events, use:

```json
{"schemaVersion": 1, "events": []}
```

An event with a countdown, details and a 50% reduction:

```json
{
  "schemaVersion": 1,
  "events": [{
    "id": "summer-jam-2030-v1",
    "enabled": true,
    "start": "2030-06-01T08:00:00Z",
    "end": "2030-06-08T08:00:00Z",
    "icon": {"source": "bundle", "value": "extras/builder_potion"},
    "presentation": {
      "title": "Summer Jam",
      "summary": "Eligible upgrades and walls receive a 50% reduction.",
      "sections": [{"title": "Details", "body": "Describe eligible upgrades, exclusions and dates here."}]
    },
    "modifiers": [
      {"categories": ["builderVillage", "lab", "pets"], "timeMultiplier": 0.5, "excludeSupercharges": true},
      {"categories": ["walls"], "wallCostMultiplier": 0.5}
    ]
  }]
}
```

- Give each distinct event a unique, stable `id`. Keep it stable for text edits; processed timer reductions are not reapplied just because a file is fetched again.
- `enabled: false` hides/disables an event. Enabled events appear before `start` with a start countdown, apply modifiers from `start` until `end`, then disappear.
- `timeMultiplier: 0.5` means half the duration; `0.8` means 20% shorter. Supported categories are `builderVillage`, `lab`, `pets`, `builderBase`, `starLab`, and `walls`.
- Optional `townHallMin` / `townHallMax` restrict a modifier to a Town Hall range. Add separate modifiers for different ranges. Optional `dataIDs` and `excludedDataIDs` target specific game items.
- Set `excludeSupercharges: true` when appropriate. Crafted Defense modules are excluded from timer modifiers by the current app implementation. Wall modifiers affect wall costs; other resource costs and collector bonuses are not simulated.
- Gold Pass combines with event reductions. Existing eligible timers are capped at the discounted full duration; their remaining time is not blindly halved. At expiry, wall prices return to normal, while already discounted upgrade deadlines stay reduced.

## News

`news_feed.json`:

```json
{
  "schemaVersion": 1,
  "entries": [{
    "id": "summer-jam-announcement-2030-v1",
    "published": "2030-05-31T08:00:00Z",
    "showAsPopup": true,
    "presentation": {
      "title": "Summer Jam is coming",
      "summary": "A short introduction to the announcement.",
      "sections": [{"title": "What to expect", "body": "Write the article text here."}]
    }
  }]
}
```

`latest_news.json` must point to that newest article:

```json
{"schemaVersion": 1, "id": "summer-jam-announcement-2030-v1"}
```

Use a new unique article ID for a new announcement. `showAsPopup: false` keeps it in News without a launch popup. Future-dated articles wait until their publication date. The app's What's New screen takes priority on an updated build; an unread news popup can appear on a later launch. News is independent of events: removing an event does not remove its news article.

For no news, set `entries` to `[]` and the latest pointer `id` to `null`.

## Images and publishing

The event's optional `icon` appears on the left of the Home event row. Both `presentation` and individual sections may also have an optional `image`. All use the same shape:

- Bundled: `{"source": "bundle", "value": "extras/builder_potion"}`. Any image already bundled in the installed app works. Use its catalog name, including namespace prefixes such as `changelog/share_progress`; omit filename extensions. The validator checks names directly against the asset catalog.
- Remote: `{"source": "remote", "value": "https://raw.githubusercontent.com/Zacatac3/clash_widgets/main/remote/images/builder.png"}`. Use a public HTTPS URL and replace `/remote/` with `/remote_dev/` for test artwork.

Validate before committing:

```sh
python3 tools/validate_remote_content.py
python3 tools/validate_remote_content.py remote_dev
```

Commit and push the JSON and images to the configured branch (`main` by default). Local edits do not reach installed apps. Use Debug → **Grab Remote Dev Files** for immediate testing, or **Grab Remote Files Now** for live content. Use disposable profiles because applied timer changes persist.

Normally the app refreshes once per 24 hours. The first launch of a new version/build bypasses that cooldown and downloads all three files. Failed event requests retain the event cache and permit another attempt after 15 minutes. A valid empty event list clears removed events immediately, even if news cannot refresh. Manual Debug remote refreshes pause the separate local test overlay, leaving only downloaded events visible. Live and dev caches/build-refresh markers are separate. New installs default to Live. Later supported JSON changes do not require an app build.

For a longer test checklist, see [REMOTE_CONTENT.md](REMOTE_CONTENT.md).
