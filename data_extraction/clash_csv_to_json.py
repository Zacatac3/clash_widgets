#!/usr/bin/env python3
import csv
import json
import os
from typing import Any, Dict, List, Optional


WORKSPACE_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DATA_EXTRACTION_DIR = os.path.join(WORKSPACE_ROOT, "data_extraction")
EXTRACTED_DIR = os.path.join(DATA_EXTRACTION_DIR, "extraxted_data")
PARSED_DIR = os.path.join(
    WORKSPACE_ROOT, "clash_widgets", "upgrade_info", "parsed_json_files"
)
MAPS_DIR = os.path.join(
    WORKSPACE_ROOT, "clash_widgets", "upgrade_info", "json_maps"
)

DEFAULT_INPUT_CSV = os.path.join(EXTRACTED_DIR, "buildings.csv")
DEFAULT_OUTPUT_JSON = os.path.join(PARSED_DIR, "buildings.json")
DEFAULT_MAP_JSON = os.path.join(MAPS_DIR, "buildings_json_map.json")


def safe_int(value: str) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def parse_build_time_seconds(row: Dict[str, str]) -> int:
    days = safe_int(row.get("BuildTimeD", ""))
    hours = safe_int(row.get("BuildTimeH", ""))
    minutes = safe_int(row.get("BuildTimeM", ""))
    seconds = safe_int(row.get("BuildTimeS", ""))
    return days * 86400 + hours * 3600 + minutes * 60 + seconds


def parse_upgrade_time_seconds(
    hours_value: str, minutes_value: Optional[str] = None
) -> int:
    hours = safe_int(hours_value)
    minutes = safe_int(minutes_value) if minutes_value is not None else 0
    return hours * 3600 + minutes * 60


def read_csv_rows(csv_path: str) -> List[Dict[str, str]]:
    rows, _ = read_csv_rows_with_headers(csv_path)
    return rows


def read_csv_rows_with_headers(csv_path: str) -> tuple[List[Dict[str, str]], List[str]]:
    with open(csv_path, newline="", encoding="utf-8") as csv_file:
        reader = csv.reader(csv_file)
        try:
            headers = next(reader)
        except StopIteration:
            return [], []

        # Skip the types row if present.
        try:
            next(reader)
        except StopIteration:
            return [], headers

        rows: List[Dict[str, str]] = []
        for raw in reader:
            if not raw:
                continue
            if len(raw) < len(headers):
                raw = raw + [""] * (len(headers) - len(raw))
            row = {headers[i]: raw[i].strip() for i in range(len(headers))}
            rows.append(row)
        return rows, headers


def build_buildings_json(rows: List[Dict[str, str]]) -> List[Dict[str, Any]]:
    buildings: List[Dict[str, Any]] = []
    current: Optional[Dict[str, Any]] = None
    non_blank_index = -1

    for row in rows:
        name = row.get("Name", "").strip()
        if name:
            non_blank_index += 1
            building_id = 1_000_000 + non_blank_index
            current = {
                "id": building_id,
                "internalName": name,
                "tid": row.get("TID", "").strip(),
                "buildingClass": row.get("BuildingClass", "").strip(),
                "levels": [],
            }
            buildings.append(current)

        if current is None:
            continue

        level_entry = {
            "level": safe_int(row.get("BuildingLevel", "")),
            "exportName": row.get("ExportName", "").strip(),
            "buildTimeSeconds": parse_build_time_seconds(row),
            "buildResource": row.get("BuildResource", "").strip(),
            "buildCost": safe_int(row.get("BuildCost", "")),
            "townHallLevel": safe_int(row.get("TownHallLevel", "")),
        }
        current["levels"].append(level_entry)

    return buildings


def build_grouped_json(
    rows: List[Dict[str, str]],
    id_prefix: Optional[int],
    level_field: Optional[str],
    level_fields: List[str],
    time_field_hours: Optional[str] = None,
    time_field_minutes: Optional[str] = None,
    include_tid: bool = True,
) -> List[Dict[str, Any]]:
    items: List[Dict[str, Any]] = []
    current: Optional[Dict[str, Any]] = None
    non_blank_index = -1
    base_id = id_prefix * 1_000_000 if id_prefix is not None else None

    level_counter = 0
    for row in rows:
        name = row.get("Name", "").strip()
        if name:
            non_blank_index += 1
            level_counter = 0
            current = {
                "internalName": name,
                "levels": [],
            }
            if include_tid:
                current["tid"] = row.get("TID", "").strip()
            if base_id is not None:
                current["id"] = base_id + non_blank_index
            items.append(current)

        if current is None:
            continue

        if level_field:
            level_value = safe_int(row.get(level_field, ""))
        else:
            level_counter += 1
            level_value = level_counter

        level_entry: Dict[str, Any] = {"level": level_value}
        for field in level_fields:
            value = row.get(field, "").strip()
            if value == "":
                level_entry[field] = ""
            else:
                level_entry[field] = value

        if time_field_hours:
            level_entry["upgradeTimeSeconds"] = parse_upgrade_time_seconds(
                row.get(time_field_hours, ""),
                row.get(time_field_minutes, "") if time_field_minutes else None,
            )

        current["levels"].append(level_entry)

    return items


def load_json_map(map_path: str) -> Dict[str, Dict[str, Any]]:
    if not os.path.exists(map_path):
        return {}
    with open(map_path, "r", encoding="utf-8") as map_file:
        try:
            data = json.load(map_file)
        except json.JSONDecodeError:
            return {}
    if isinstance(data, dict):
        return data
    return {}


def update_id_map(
    map_path: str, items: List[Dict[str, Any]]
) -> Dict[str, Dict[str, Any]]:
    map_data = load_json_map(map_path)
    for item in items:
        internal_name = item.get("internalName", "").strip()
        if not internal_name:
            continue
        if internal_name not in map_data:
            map_data[internal_name] = {
                "displayName": internal_name,
                "internalName": internal_name,
            }
            if "id" in item:
                map_data[internal_name]["id"] = item.get("id")
        else:
            entry = map_data[internal_name]
            if isinstance(entry, dict):
                entry.setdefault("displayName", internal_name)
                entry.setdefault("internalName", internal_name)
                if "id" in item:
                    entry.setdefault("id", item.get("id"))
    os.makedirs(os.path.dirname(map_path), exist_ok=True)
    with open(map_path, "w", encoding="utf-8") as map_file:
        json.dump(map_data, map_file, indent=2, ensure_ascii=False)
        map_file.write("\n")
    return map_data


def write_buildings_json(output_path: str, buildings: List[Dict[str, Any]]) -> None:
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as out_file:
        json.dump(buildings, out_file, indent=2, ensure_ascii=False)
        out_file.write("\n")


def build_townhall_levels(rows: List[Dict[str, str]], headers: List[str]) -> List[Dict[str, Any]]:
    if "Troop Housing" not in headers:
        return []
    start_index = headers.index("Troop Housing")
    count_columns = headers[start_index:]

    levels: List[Dict[str, Any]] = []
    previous_counts: Dict[str, int] = {}

    for row in rows:
        name_value = row.get("Name", "").strip()
        town_hall_level = safe_int(name_value)
        if town_hall_level <= 0:
            continue

        counts: Dict[str, int] = {}
        for col in count_columns:
            raw = row.get(col, "").strip()
            if raw == "":
                counts[col] = previous_counts.get(col, 0)
            else:
                counts[col] = safe_int(raw)

        previous_counts = counts
        levels.append({
            "townHallLevel": town_hall_level,
            "counts": counts
        })

    return levels


def main() -> None:
    buildings_rows = read_csv_rows(DEFAULT_INPUT_CSV)
    buildings = build_buildings_json(buildings_rows)
    write_buildings_json(DEFAULT_OUTPUT_JSON, buildings)
    update_id_map(DEFAULT_MAP_JSON, buildings)

    characters_rows = read_csv_rows(os.path.join(EXTRACTED_DIR, "characters.csv"))
    characters = build_grouped_json(
        characters_rows,
        id_prefix=4,
        level_field="VisualLevel",
        level_fields=[
            "TID",
            "BarrackLevel",
            "LaboratoryLevel",
            "UpgradeTimeH",
            "UpgradeTimeM",
            "UpgradeResource",
            "UpgradeCost",
        ],
        time_field_hours="UpgradeTimeH",
        time_field_minutes="UpgradeTimeM",
    )
    write_buildings_json(os.path.join(PARSED_DIR, "characters.json"), characters)
    update_id_map(
        os.path.join(MAPS_DIR, "characters_json_map.json"), characters
    )

    pets_rows = read_csv_rows(os.path.join(EXTRACTED_DIR, "pets.csv"))
    pets = build_grouped_json(
        pets_rows,
        id_prefix=73,
        level_field="TroopLevel",
        level_fields=[
            "TID",
            "LaboratoryLevel",
            "UpgradeTimeH",
            "UpgradeResource",
            "UpgradeCost",
        ],
        time_field_hours="UpgradeTimeH",
        time_field_minutes="UpgradeTimeM",
    )
    write_buildings_json(os.path.join(PARSED_DIR, "pets.json"), pets)
    update_id_map(os.path.join(MAPS_DIR, "pets_json_map.json"), pets)

    spells_rows = read_csv_rows(os.path.join(EXTRACTED_DIR, "spells.csv"))
    spells = build_grouped_json(
        spells_rows,
        id_prefix=26,
        level_field="Level",
        level_fields=[
            "TID",
            "LaboratoryLevel",
            "UpgradeTimeH",
            "UpgradeResource",
            "UpgradeCost",
        ],
        time_field_hours="UpgradeTimeH",
    )
    write_buildings_json(os.path.join(PARSED_DIR, "spells.json"), spells)
    update_id_map(os.path.join(MAPS_DIR, "spells_json_map.json"), spells)

    heroes_rows = read_csv_rows(os.path.join(EXTRACTED_DIR, "heroes.csv"))
    heroes = build_grouped_json(
        heroes_rows,
        id_prefix=28,
        level_field="VisualLevel",
        level_fields=[
            "TID",
            "UpgradeTimeH",
            "UpgradeResource",
            "UpgradeCost",
            "RequiredTownHallLevel",
            "RequiredHeroTavernLevel",
        ],
        time_field_hours="UpgradeTimeH",
    )
    write_buildings_json(os.path.join(PARSED_DIR, "heroes.json"), heroes)
    update_id_map(os.path.join(MAPS_DIR, "heroes_json_map.json"), heroes)

    traps_rows = read_csv_rows(os.path.join(EXTRACTED_DIR, "traps.csv"))
    traps = build_grouped_json(
        traps_rows,
        id_prefix=12,
        level_field="Level",
        level_fields=[
            "TID",
            "ExportName",
            "BuildTimeD",
            "BuildTimeH",
            "BuildTimeM",
            "BuildResource",
            "BuildCost",
            "TownHallLevel",
        ],
        include_tid=True,
    )
    for trap in traps:
        for level in trap.get("levels", []):
            level["buildTimeSeconds"] = parse_build_time_seconds(
                {
                    "BuildTimeD": level.get("BuildTimeD", ""),
                    "BuildTimeH": level.get("BuildTimeH", ""),
                    "BuildTimeM": level.get("BuildTimeM", ""),
                    "BuildTimeS": "0",
                }
            )
    write_buildings_json(os.path.join(PARSED_DIR, "traps.json"), traps)
    update_id_map(os.path.join(MAPS_DIR, "traps_json_map.json"), traps)

    mini_rows = read_csv_rows(os.path.join(EXTRACTED_DIR, "mini_levels.csv"))
    mini_levels = build_grouped_json(
        mini_rows,
        id_prefix=None,
        level_field="Level",
        level_fields=[
            "RequiredTownHallLevel",
            "BuildTimeD",
            "BuildTimeH",
            "BuildTimeM",
            "BuildTimeS",
            "BuildResource",
            "BuildCost",
        ],
        include_tid=False,
    )
    for mini in mini_levels:
        for level in mini.get("levels", []):
            level["buildTimeSeconds"] = parse_build_time_seconds(
                {
                    "BuildTimeD": level.get("BuildTimeD", ""),
                    "BuildTimeH": level.get("BuildTimeH", ""),
                    "BuildTimeM": level.get("BuildTimeM", ""),
                    "BuildTimeS": level.get("BuildTimeS", ""),
                }
            )
    write_buildings_json(os.path.join(PARSED_DIR, "mini_levels.json"), mini_levels)
    update_id_map(os.path.join(MAPS_DIR, "mini_levels_json_map.json"), mini_levels)

    seasonal_rows = read_csv_rows(
        os.path.join(EXTRACTED_DIR, "seasonal_defense_modules.csv")
    )
    seasonal = build_grouped_json(
        seasonal_rows,
        id_prefix=102,
        level_field=None,
        level_fields=[
            "BuildTimeD",
            "BuildTimeH",
            "BuildTimeM",
            "BuildTimeS",
            "BuildResource",
            "BuildCost",
        ],
        include_tid=False,
    )
    for module in seasonal:
        for level in module.get("levels", []):
            level["buildTimeSeconds"] = parse_build_time_seconds(
                {
                    "BuildTimeD": level.get("BuildTimeD", ""),
                    "BuildTimeH": level.get("BuildTimeH", ""),
                    "BuildTimeM": level.get("BuildTimeM", ""),
                    "BuildTimeS": level.get("BuildTimeS", ""),
                }
            )
    write_buildings_json(
        os.path.join(PARSED_DIR, "seasonal_defense_modules.json"), seasonal
    )
    update_id_map(
        os.path.join(MAPS_DIR, "seasonal_defense_modules_json_map.json"),
        seasonal,
    )

    villager_rows = read_csv_rows(
        os.path.join(EXTRACTED_DIR, "villager_apprentices.csv")
    )
    villagers = build_grouped_json(
        villager_rows,
        id_prefix=None,
        level_field=None,
        level_fields=[
            "RequiredTownHallLevel",
            "Type",
            "BoostMultiplier",
            "CostResource",
            "Cost",
        ],
        include_tid=False,
    )
    write_buildings_json(
        os.path.join(PARSED_DIR, "villager_apprentices.json"), villagers
    )
    update_id_map(
        os.path.join(MAPS_DIR, "villager_apprentices_json_map.json"),
        villagers,
    )

    guardians_rows = read_csv_rows(os.path.join(EXTRACTED_DIR, "guardians.csv"))
    guardians = build_grouped_json(
        guardians_rows,
        id_prefix=107,
        level_field="Level",
        level_fields=[],
        include_tid=True,
    )
    write_buildings_json(os.path.join(PARSED_DIR, "guardians.json"), guardians)
    update_id_map(os.path.join(MAPS_DIR, "guardians_json_map.json"), guardians)

    weapons_rows = read_csv_rows(os.path.join(EXTRACTED_DIR, "weapons.csv"))
    weapons = build_grouped_json(
        weapons_rows,
        id_prefix=None,
        level_field="Level",
        level_fields=[
            "BuildTimeD",
            "BuildTimeH",
            "BuildTimeM",
            "BuildResource",
            "BuildCost",
        ],
        include_tid=False,
    )
    for weapon in weapons:
        for level in weapon.get("levels", []):
            level["buildTimeSeconds"] = parse_build_time_seconds(
                {
                    "BuildTimeD": level.get("BuildTimeD", ""),
                    "BuildTimeH": level.get("BuildTimeH", ""),
                    "BuildTimeM": level.get("BuildTimeM", ""),
                    "BuildTimeS": "0",
                }
            )
    write_buildings_json(os.path.join(PARSED_DIR, "weapons.json"), weapons)
    update_id_map(os.path.join(MAPS_DIR, "weapons_json_map.json"), weapons)

    townhall_rows, townhall_headers = read_csv_rows_with_headers(
        os.path.join(EXTRACTED_DIR, "townhall_levels.csv")
    )
    townhall_levels = build_townhall_levels(townhall_rows, townhall_headers)
    write_buildings_json(
        os.path.join(PARSED_DIR, "townhall_levels.json"), townhall_levels
    )


if __name__ == "__main__":
    main()
