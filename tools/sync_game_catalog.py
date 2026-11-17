#!/usr/bin/env python3
"""Sync curated names/icons after CSV conversion. Use --check for a read-only audit.

Home Village entries are curated once in progress_sections.json. This command
updates the legacy maps/master list and derived hero/TH metadata. Builder Base
names remain curated in its master list until it has a Progress catalog.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads(path.read_text())


def number(value):
    return int(value) if str(value or "").strip() else 0


def synchronize(root=ROOT, check=False):
    data = root / "clash_widgets/json"
    assets = root / "clash_widgets/Assets.xcassets"
    catalog = read(data / "progress_sections.json")
    home = read(data / "master_lists/home_village_master_upgrades.json")
    builder = read(data / "master_lists/builder_base_master_upgrades.json")
    names = {}
    for master in (home, builder):
        for groups in master["sections"].values():
            for entries in groups.values():
                names.update({int(key): name for key, name in entries.items() if key.isdigit()})

    mapping = read(data / "mapping.json")
    asset_map = read(data / "asset_map.json")
    parsed = {path.stem: read(path) for path in (data / "parsed_json_files").glob("*.json")}
    hero_items = []
    seen = set()
    targets = {
        "troops": ("lab", "elixir_troops"), "dark_troops": ("lab", "dark_troops"),
        "squads": ("lab", "squads"), "siege_machines": ("lab", "siege_machines"),
        "spells": ("lab", "spells"), "heroes": ("buildings", "heroes"),
        "guardians": ("buildings", "guardians"), "pets": ("pets", "pet"),
        "traps": ("buildings", "traps"), "walls": ("walls", "home"),
        "crafted_defenses": ("buildings", "seasonal_defense"),
    }
    for section in catalog["sections"]:
        source = "seasonal_defense_archetypes" if section["id"] == "crafted_defenses" else section["levels"]
        entries = {entry.get("id"): entry for entry in parsed[source]}
        for group in section["groups"]:
            for item in group["items"]:
                game_id = item["id"]
                if game_id in seen:
                    raise ValueError(f"Duplicate Progress ID: {game_id}")
                seen.add(game_id)
                if game_id not in entries:
                    raise ValueError(f"{item['name']}: ID {game_id} is missing from {source}.json")
                for module in item.get("moduleIds", []):
                    if not any(entry.get("id") == module for entry in parsed[section["levels"]]):
                        raise ValueError(f"{item['name']}: missing module {module}")
                image = item.get("image", item.get("imagePattern", "").replace("{level}", "1"))
                image_set = assets / group["assetFolder"] / f"{image}.imageset"
                contents = read(image_set / "Contents.json")
                if not any((image_set / entry["filename"]).is_file()
                           for entry in contents["images"] if entry.get("filename")):
                    raise ValueError(f"{item['name']}: image file is missing")
                names[game_id] = item["name"]
                if item.get("image"):
                    asset_map[item["name"]] = item["image"]
                if section["id"] == "heroes":
                    hero_items.append((item, entries[game_id], f"{group['assetFolder']}/{image}"))
                if section["id"] == "buildings":
                    target = ("buildings", "defense" if group["id"] == "defense" else group["id"])
                else:
                    target = targets[section["id"]]
                groups = home["sections"].setdefault(target[0], {})
                existing = next((entries for entries in groups.values() if str(game_id) in entries), None)
                (existing if existing is not None else groups.setdefault(target[1], {}))[str(game_id)] = item["name"]

    mapping.update({str(key): name for key, name in names.items()})
    updates = {data / "mapping.json": mapping, data / "asset_map.json": asset_map}
    home["generatedFrom"] = ["json/progress_sections.json", "json/parsed_json_files/mini_levels.json"]
    updates[data / "master_lists/home_village_master_upgrades.json"] = home
    for path in (data / "json_maps").glob("*.json"):
        entries = read(path)
        for entry in entries.values():
            if isinstance(entry, dict) and number(entry.get("id")) in names:
                entry["displayName"] = names[number(entry["id"])]
        updates[path] = entries

    buildings = {entry["id"]: entry for entry in parsed["buildings"]}
    hero_hall = buildings[1000071]["levels"]
    heroes = []
    for item, entry, asset in hero_items:
        first = min(entry["levels"], key=lambda level: number(level["level"]))
        required_hall = number(first.get("RequiredHeroTavernLevel"))
        hall_unlock = min(number(level["townHallLevel"]) for level in hero_hall if level["level"] >= required_hall)
        heroes.append(dict(id=item["id"], displayName=item["name"], internalName=entry["internalName"],
                           unlockTownHall=max(hall_unlock, number(first.get("RequiredTownHallLevel"))), assetName=asset))
    updates[data / "heroes_config.json"] = heroes

    constants = read(data / "game_constants.json")
    town_halls = parsed["townhall_levels"]
    if not town_halls:
        raise ValueError("townhall_levels.json is empty; run the corrected CSV parser first")
    constants["max_town_hall_level"] = max(entry["townHallLevel"] for entry in town_halls)
    mini_levels = {entry["internalName"]: entry["levels"] for entry in parsed["mini_levels"]}
    active_supercharges = {}
    for game_id, building in buildings.items():
        levels = mini_levels.get(building.get("miniLevels"))
        if not levels or game_id not in names:
            continue
        unlock = max((number(level.get("RequiredTownHallLevel")) for level in levels), default=0)
        if unlock > constants["max_town_hall_level"]:
            continue
        name = names[game_id]
        slug = asset_map.get(name)
        if slug:
            active_supercharges[slug] = f"{name} Supercharge"
    home["sections"]["buildings"]["supercharges"] = active_supercharges
    wall_levels = buildings[1000010]["levels"]
    for town_hall in town_halls:
        th = town_hall["townHallLevel"]
        levels = [level["level"] for level in wall_levels if level["townHallLevel"] <= th]
        count = town_hall["counts"].get("Wall", 0)
        if levels and count:
            constants["wall_counts_by_th"][str(th)] = dict(max_wall_level=max(levels), total_walls=count)
    # Partial wall release caps are intentionally manual; never overwrite them.
    updates[data / "game_constants.json"] = constants

    changed = [path for path, value in updates.items() if read(path) != value]
    if not check:
        for path in changed:
            path.write_text(json.dumps(updates[path], indent=2, ensure_ascii=False) + "\n")
    return changed, len(seen)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Report drift without writing files")
    args = parser.parse_args()
    try:
        changed, count = synchronize(check=args.check)
    except (ValueError, KeyError, OSError) as error:
        parser.exit(2, f"Catalog validation failed; no files written: {error}\n")
    for path in changed:
        print(f"{'Out of sync' if args.check else 'Updated'}: {path.relative_to(ROOT)}")
    print(f"Validated {count} Progress entries; {len(changed)} {'out-of-sync' if args.check else 'updated'} files.")
    if args.check and changed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
