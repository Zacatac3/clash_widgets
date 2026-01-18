#!/usr/bin/env python3
import csv
import json
import os
from typing import Any, Dict, List, Optional


WORKSPACE_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DEFAULT_INPUT_CSV = os.path.join(
    WORKSPACE_ROOT, "data_extraction", "extraxted_data", "buildings.csv"
)
DEFAULT_OUTPUT_JSON = os.path.join(
    WORKSPACE_ROOT, "data_extraction", "parsed_json_files", "buildings.json"
)
DEFAULT_MAP_JSON = os.path.join(
    WORKSPACE_ROOT, "data_extraction", "json_maps", "buildings_json_map.json"
)


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


def read_csv_rows(csv_path: str) -> List[Dict[str, str]]:
    with open(csv_path, newline="", encoding="utf-8") as csv_file:
        reader = csv.reader(csv_file)
        try:
            headers = next(reader)
        except StopIteration:
            return []

        # Skip the types row if present.
        try:
            next(reader)
        except StopIteration:
            return []

        rows: List[Dict[str, str]] = []
        for raw in reader:
            if not raw:
                continue
            if len(raw) < len(headers):
                raw = raw + [""] * (len(headers) - len(raw))
            row = {headers[i]: raw[i].strip() for i in range(len(headers))}
            rows.append(row)
        return rows


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


def update_buildings_map(
    map_path: str, buildings: List[Dict[str, Any]]
) -> Dict[str, Dict[str, Any]]:
    map_data = load_json_map(map_path)
    for building in buildings:
        internal_name = building.get("internalName", "").strip()
        if not internal_name:
            continue
        if internal_name not in map_data:
            map_data[internal_name] = {
                "internalName": internal_name,
                "id": building.get("id"),
            }
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


def main() -> None:
    rows = read_csv_rows(DEFAULT_INPUT_CSV)
    buildings = build_buildings_json(rows)
    write_buildings_json(DEFAULT_OUTPUT_JSON, buildings)
    update_buildings_map(DEFAULT_MAP_JSON, buildings)


if __name__ == "__main__":
    main()
