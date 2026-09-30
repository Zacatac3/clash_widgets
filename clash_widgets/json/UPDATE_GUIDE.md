# Updating game data, names, and icons

The app bundles this `json/` folder as an Xcode folder reference. Use these files in this order when a game update adds an upgrade or asset.

## What each file controls

| File | Edit when | Effect |
| --- | --- | --- |
| `parsed_json_files/<type>.json` | Generated from a new CSV | Levels, upgrade times, costs, and internal names. Do not hand edit; the parser replaces it. |
| `json_maps/<type>_json_map.json` | A new or renamed CSV entry needs a human readable `displayName` | ID/internal name lookup. The parser creates new entries and preserves `displayName` for entries it matches by ID. Review its diff report after every run. |
| `mapping.json` | A game ID needs a canonical display name | ID to name lookup for imported upgrades. For seasonal defenses, this takes precedence over the JSON map in the app dashboard. |
| `asset_map.json` | A display name does not naturally match its image set name | Display name to image slug. The app builder rows and Asset Map debug screen read the bundled file. This file does not add an image by itself. |
| `../Assets.xcassets/<folder>/<slug>.imageset/` | A new icon is needed | Add the image and its `Contents.json`. The folder and slug must match the image name requested by the screen. |
| `master_lists/home_village_master_upgrades.json` or `master_lists/builder_base_master_upgrades.json` | The curated list of available upgrades changes | Add/remove the ID and name in the matching village, section, and category. These lists power the Master List debug view; they do not supply dashboard icons. |
| `equipment_data.json` | Hero equipment is added or its hero/rarity changes | Controls entries in the Equipment tab. Equipment is excluded from the village master lists. |

**Name path for an app builder row:** game ID → JSON map `displayName` (usually), or `mapping.json` (seasonal defenses and fallbacks) → display name → `asset_map.json` (or a slug made from the name) → image set. The builder row tries `crafted_defenses/<slug>` first for seasonal defense IDs (`103xxxxxx`), then its category folder. Its bundled `mapping.json` and `asset_map.json` take priority over older app group copies. Existing saved seasonal rows are relabeled by ID when the dashboard draws them; other saved names are not rewritten.

## Update checklist by type

Start with decrypted UTF-8 CSVs in `../../data_extraction/extraxted_data/`. The directory name really is `extraxted_data`. `../../data_extraction/process_logic.sh` is an earlier extraction step: it expects a `logic/` folder in its current directory, strips the file header, runs `sce`, and writes decrypted CSVs to `processed_csvs/`. Copy the resulting CSVs into `extraxted_data/` before running `python3 data_extraction/clash_csv_to_json.py` from the repository root. That parser processes **all** expected CSVs, replaces the generated JSON files, updates the JSON maps, and prints added/removed/renamed entries. Review its output and diff before editing the hand maintained files below.

| Update | CSV → generated parsed file / JSON map | Hand maintained files and action | App image folder |
| --- | --- | --- | --- |
| Home Village buildings and defenses | `buildings.csv` → `buildings.json` / `buildings_json_map.json` | Add ID/name to `mapping.json`; add ID/name under the proper `sections.buildings` category in `home_village_master_upgrades.json`; add `asset_map.json` entry if the slug differs. | `buildings_home/` |
| Traps and walls | `traps.csv` → `traps.json` / `traps_json_map.json` for traps; `buildings.csv` for walls | Update `mapping.json` and the village master list (`sections.buildings.traps` or `sections.walls`). Add an asset override if needed. | Usually `buildings_home/` or `builder_base/`; wall art may live in `resources/` and have a separate screen lookup. |
| Troops and siege machines | `characters.csv` → `characters.json` / `characters_json_map.json` | Update `mapping.json`; add to `sections.lab` (Home Village) or `sections.star_lab` (Builder Base). Add asset override when needed. | `lab/` or `builder_base/` |
| Spells | `spells.csv` → `spells.json` / `spells_json_map.json` | Update `mapping.json` and `sections.lab.spells`; add asset override when needed. | `lab/` |
| Heroes and guardians | `heroes.csv` or `guardians.csv` → corresponding parsed file / JSON map | Update `mapping.json` and `sections.buildings.heroes` or `.guardians`. For a new hero, also add ID, display name, unlock Town Hall, and profile icon path to `heroes_config.json`. | Builder row: `buildings_home/`; profile hero icon: `heroes/` |
| Pets | `pets.csv` → `pets.json` / `pets_json_map.json` | Update `mapping.json`, `sections.pets.pet`, and asset override if needed. | `pets/` |
| Supercharges | `mini_levels.csv` → `mini_levels.json` / `mini_levels_json_map.json` | Check the mini level internal name and add/remove its building name in `sections.buildings.supercharges`; update `mapping.json` for the underlying building ID if new. The row uses the building icon plus `extras/supercharge`. | Underlying building's `buildings_home/` image |
| Seasonal defenses | `seasonal_defense_archetypes.csv` and `seasonal_defense_modules.csv` → matching parsed files / JSON maps | Verify archetype ID (`103...`) and module ID (`102...`). Add the **archetype ID** and chosen public name to `mapping.json` and `sections.buildings.seasonal_defense`. Add public name → slug to `asset_map.json`. Check module times/costs in the generated module file. | `crafted_defenses/` |
| Town Hall weapon levels | `weapons.csv` → `weapons.json` / `weapons_json_map.json` | Review weapon levels and costs; update the Town Hall entry in the master list only if the upgrade catalog changes. The active builder row currently labels this `Town Hall Weapon` in code. | `buildings_home/town_hall_weapon` |
| Town Hall counts/unlocks | `townhall_levels.csv` → `townhall_levels.json` (no JSON map) | Review counts and any new Town Hall rules in app code when required. | None unless a new Town Hall icon is added. |
| Hero equipment | No CSV in this parser | Add the equipment ID/name to `mapping.json` if imported IDs need naming. Add `{name, hero, rarity}` to `equipment_data.json`; the `name` must match the profile equipment name. Update `ore_costs.csv` only when costs change. The Equipment tab derives its image slug from `equipment_data.json` name; it does **not** use `asset_map.json`. | `equipment/` |

The current master list files use nested ID → name objects, for example `sections.buildings.seasonal_defense` contains `"103000011": "Hot Candle"`. `sections.buildings.supercharges` instead uses building slugs as keys. Use the existing entries as the format reference.

### Seasonal defense example

For `103000011`, the dashboard currently resolves `mapping.json` name `Hot Candle` → `asset_map.json` slug `hot_candle` → `Assets.xcassets/crafted_defenses/hot_candle.imageset`. The `seasonal_defense_archetypes_json_map.json` entry can still contain the game/internal name `Inferno Candle`; its `displayName` is also used by debug and fallback lookups, so keep it understandable, but the dashboard uses the mapped public name when the archetype ID exists in `mapping.json`.

### Widget and other screens

The WidgetKit extension has its **own** `ClashDashWidget/Assets.xcassets` and currently derives builder icons from the stored upgrade name in `ClashDashWidget/ClashDashWidget.swift`; it does not use the app builder row's `asset_map.json` resolver. Add a widget image set and update widget name resolution when a new icon must appear there. A working icon in the app or Asset Map debug screen does not prove the widget has it. Profile hero art uses `heroes_config.json`; Equipment tab art uses `equipment_data.json` names; those are separate paths.

## Quick checks

1. Confirm each new ID and chosen name in `mapping.json`, and each display name/slug pair in `asset_map.json` where needed.
2. Confirm the matching `.imageset/Contents.json` names an existing image. With a namespaced catalog folder, the compiled asset name is `<folder>/<slug>`.
3. Review the parser's diff report for unexpected removals or changed IDs, especially seasonal archetypes (their IDs are generated from CSV order).
4. Build and run the app after changing bundled JSON or assets. Check the relevant app screen, Asset Map debug screen, and widget separately if the widget should show the item.
