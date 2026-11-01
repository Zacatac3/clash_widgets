# Events and news: quick publishing guide

Edit `remote/` for live content or `remote_dev/` for testing. Both use the same JSON structure. The app reads three files:

| File | Purpose |
| --- | --- |
| `latest_event.json` | All upcoming/active event definitions and their modifiers. |
| `news_feed.json` | News articles, including older articles for the archive. |
| `latest_news.json` | The ID of the newest article in `news_feed.json`. |

Use `schemaVersion: 1` for news and legacy events. Use `schemaVersion: 2` for event feeds with advanced selectors or cost multipliers. Dates must be UTC strings such as `2030-06-01T08:00:00Z`. The dates below are placeholders; replace them before publishing.

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
- Set `excludeSupercharges: true` when appropriate. Crafted Defense modules are excluded from timer modifiers by the current app implementation. Wall modifiers affect wall costs. Version 2 cost modifiers are also displayed in Supercharge upgrade details; other regular resource costs and collector bonuses are not simulated.
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

The app refreshes on every fresh launch, on the first foreground open each local calendar day, and on later foreground returns after a six-hour cooldown. Manual refresh always fetches. Duplicate launch callbacks do not fetch twice. All admitted refreshes bypass CDN caches. The first daily attempt bypasses failures from yesterday; subsequent failures retry after 15 minutes. The first launch of a new version/build bypasses that cooldown and downloads all three files. Failed event requests retain the event cache and permit another attempt after 15 minutes. A valid empty event list clears removed events immediately, even if news cannot refresh. Manual Debug remote refreshes pause the separate local test overlay, leaving only downloaded events visible. Live and dev caches/build-refresh markers are separate. New installs default to Live. Later supported JSON changes do not require an app build.

For a longer test checklist, see [REMOTE_CONTENT.md](REMOTE_CONTENT.md).

## Advanced event rules (requires the updated app)

Use `schemaVersion: 2` in `latest_event.json` when any rule uses `onlySupercharges`, `superchargeLevels`, `costMultiplier`, or `priority`. Earlier apps reject version 2 and retain their last valid cached events; they do not apply these new rules. After installing the supporting build, later rule changes only require publishing JSON.

A building-specific, Supercharge-only rule giving 60% off costs and 60% off time:

```json
{
  "categories": ["builderVillage"],
  "dataIDs": [1000079],
  "onlySupercharges": true,
  "timeMultiplier": 0.4,
  "costMultiplier": 0.4
}
```

`1000079` is Multi-Gear Tower. Use the normal exported building ID, not a synthetic Supercharge ID. Omit `dataIDs` to match every building in the selected categories.

Different reductions for each **target Supercharge level**, e.g. upgrading 0→1 versus 1→2:

```json
[
  {"categories": ["builderVillage"], "dataIDs": [1000079], "onlySupercharges": true, "superchargeLevels": [1], "timeMultiplier": 0.4, "costMultiplier": 0.4, "priority": 1},
  {"categories": ["builderVillage"], "dataIDs": [1000079], "onlySupercharges": true, "superchargeLevels": [2], "timeMultiplier": 0.7, "costMultiplier": 0.5, "priority": 1}
]
```

`superchargeLevels` itself requires a Supercharge, so it never matches a regular building upgrade. Lists must contain positive integers. Do not combine a Supercharge selector with `excludeSupercharges: true`. Omitting both selectors preserves legacy behavior: regular upgrades and Supercharges can match unless explicitly excluded.

Within one event, the highest matching `priority` wins **separately for time and cost** (default 0); equal-priority rules use the lowest multiplier. This lets a priority-1 Supercharge rule specify 30% off even when a broad priority-0 rule gives 50% off. Across separate events the lowest factor still wins. Gold Pass multiplies with the selected event factor. Multipliers are the amount remaining: 60% off = `0.4`, not `0.6`.

Use exact ratios when the announced times are rounded independently. In the supplied October reference, Multi-Gear Tower level 1 goes from 144h to 58h (`58 / 144 = 0.4027777777777778`), and level 2 from 168h to 67h (`67 / 168 = 0.39880952380952384`). They should not both use `0.4`. See [the disabled complete example](../remote/examples/supercharge_overrides.json); its cost multipliers are illustrative, not transcribed image costs.

### Different Town Hall discounts

Town Hall ranges are inclusive and refer to the **player's Town Hall**, not the upgrade's required unlock Town Hall. For 40% off through TH16 and 20% off at TH17–18:

```json
[
  {"categories": ["builderVillage", "lab", "pets"], "townHallMax": 16, "timeMultiplier": 0.6, "costMultiplier": 0.6, "excludeSupercharges": true},
  {"categories": ["builderVillage", "lab", "pets"], "townHallMin": 17, "townHallMax": 18, "timeMultiplier": 0.8, "costMultiplier": 0.8, "excludeSupercharges": true},
  {"categories": ["walls"], "townHallMax": 16, "wallCostMultiplier": 0.6},
  {"categories": ["walls"], "townHallMin": 17, "townHallMax": 18, "wallCostMultiplier": 0.8}
]
```

Ranges combine with building IDs and Supercharge selectors. Set a maximum explicitly if future Town Halls should not inherit the discount. Resource-specific events still require an explicit building/unit ID list.

### Displays and timer behavior

Time rules apply to tracked upgrades and their app/widget duration labels. Progress → Supercharges → **Upgrade costs and times** shows each target level's cost and duration with current event and Gold Pass factors. Prices revert on expiry; tracked deadlines retain already-applied reductions. `costMultiplier` does not change resource balances or historical spending. Other regular upgrade cost screens and max-time/cost totals retain their existing behavior; walls use `wallCostMultiplier`.

Already processed timers are not reapplied when a rule changes under the same event ID. Configure exact rules before activation. A fresh event ID can apply a new cap, but never lengthens a deadline. Seasonal Crafted Defenses remain excluded from timer rules.
