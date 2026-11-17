#!/usr/bin/env python3
"""Read-only TH19 asset/data checklist. --strict also fails on pending game data.

Artwork labels and expected source files live in data_extraction/th19_preparation.json.
An OK staging result is not release approval; confirm the new export schema in-game.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def contains_id(value, game_id):
    if not isinstance(value, dict):
        return False
    return str(game_id) in value or any(contains_id(child, game_id) for child in value.values())


def asset_errors(catalog, name):
    """Validate the actual namespaced name and every referenced image file."""
    image_set = catalog / (name + ".imageset")
    contents = image_set / "Contents.json"
    if not contents.is_file():
        return [f"{name}: missing imageset/Contents.json"]
    errors = []
    namespaces = []
    for folder in reversed(image_set.parents):
        if folder == catalog or catalog not in folder.parents:
            continue
        metadata = folder / "Contents.json"
        if metadata.is_file() and read_json(metadata).get("properties", {}).get("provides-namespace"):
            namespaces.append(folder.name)
    compiled_name = "/".join(namespaces + [image_set.stem])
    if compiled_name != name:
        errors.append(f"{name}: compiles as {compiled_name}; check folder namespace")
    filenames = [item["filename"] for item in read_json(contents).get("images", []) if item.get("filename")]
    if not filenames:
        errors.append(f"{name}: no image filenames")
    for filename in filenames:
        path = image_set / filename
        if not path.is_file() or path.stat().st_size == 0:
            errors.append(f"{name}: missing/empty image {filename}")
    return errors


def audit(root=ROOT):
    manifest = read_json(root / "data_extraction/th19_preparation.json")
    data = root / "clash_widgets/json"
    catalog = root / "clash_widgets/Assets.xcassets"
    asset_map = read_json(data / "asset_map.json")
    mapping = read_json(data / "mapping.json")
    master = read_json(data / "master_lists/home_village_master_upgrades.json")
    progress = read_json(data / "progress_sections.json")
    progress_items = [(item, group) for section in progress["sections"]
                      for group in section["groups"] for item in group["items"]]
    errors, pending = [], []
    for item in manifest["items"]:
        name, asset = item["name"], item["asset"]
        errors.extend(asset_errors(catalog, asset))
        if "minimumLevel" not in item and asset_map.get(name) != asset.split("/")[-1]:
            errors.append(f"{name}: asset_map.json does not point to {asset}")
        game_id = item["id"]
        if game_id is None:
            pending.append(f"{name}: confirm source category, public name and game ID")
            continue
        parsed = read_json(data / "parsed_json_files" / (item["dataFile"] + ".json"))
        entry = next((entry for entry in parsed if entry.get("id") == game_id), None)
        if not entry:
            pending.append(f"{name}: ID {game_id} missing from {item['dataFile']}.json")
            continue
        if "minimumLevel" in item:
            if not any(level["level"] >= item["minimumLevel"] for level in entry["levels"]):
                pending.append(f"{name}: level {item['minimumLevel']} not in parsed data")
            continue
        if mapping.get(str(game_id)) != name:
            pending.append(f"{name}: confirm mapping.json name for ID {game_id}")
        json_map = read_json(data / "json_maps" / (item["dataFile"] + "_json_map.json"))
        if not any(entry.get("id") == game_id and entry.get("displayName") == name
                   for entry in json_map.values()):
            pending.append(f"{name}: confirm JSON-map displayName for ID {game_id}")
        if not contains_id(master, game_id):
            pending.append(f"{name}: missing from Home Village master list")
        matches = [(entry, group) for entry, group in progress_items if entry["id"] == game_id]
        if not any(f"{group['assetFolder']}/{entry.get('image', '')}" == asset
                   and entry["name"] == name for entry, group in matches):
            pending.append(f"{name}: missing/mismatched Progress entry and icon")

    for asset in manifest["requiredAssets"]:
        pending.extend(asset_errors(catalog, asset))
    town_hall = manifest["townHall"]
    constants = read_json(data / "game_constants.json")
    counts = read_json(data / "parsed_json_files/townhall_levels.json")
    if constants["max_town_hall_level"] < town_hall:
        pending.append(f"game_constants.json: max_town_hall_level is still {constants['max_town_hall_level']}")
    town_hall_counts = next((entry for entry in counts if entry["townHallLevel"] == town_hall), None)
    if not town_hall_counts:
        pending.append(f"townhall_levels.json: no TH{town_hall} counts/unlocks")
    wall_config = constants["wall_counts_by_th"].get(str(town_hall))
    if not wall_config:
        pending.append(f"game_constants.json: confirm TH{town_hall} wall level/count")
    elif town_hall_counts and wall_config["total_walls"] != town_hall_counts["counts"].get("Wall"):
        pending.append(f"game_constants.json: TH{town_hall} wall count differs from parsed data")
    wall_level = next(item["minimumLevel"] for item in manifest["items"] if "minimumLevel" in item)
    if wall_config and wall_config["max_wall_level"] != wall_level:
        pending.append(f"game_constants.json: confirm TH{town_hall} maximum wall level (artwork expects {wall_level})")
    if str(wall_level) not in constants.get("highest_wall_level_unlock_caps", {}):
        pending.append(f"game_constants.json: confirm level {wall_level} launch wall unlock cap")
    return manifest, errors, pending


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strict", action="store_true", help="Exit nonzero for pending data/art as well as broken staged assets")
    args = parser.parse_args()
    try:
        manifest, errors, pending = audit()
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"Readiness audit could not complete: {error}\n")
    print(f"TH{manifest['townHall']} preparation: {len(manifest['items'])} staged assets checked")
    for problem in errors:
        print(f"ERROR {problem}")
    for problem in pending:
        print(f"WAIT  {problem}")
    print(f"{len(errors)} staging errors; {len(pending)} pending confirmations. "
          "Run --strict when completing the launch checklist.")
    raise SystemExit(1 if errors or (args.strict and pending) else 0)


if __name__ == "__main__":
    main()
