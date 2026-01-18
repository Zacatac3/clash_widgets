#!/usr/bin/env python3
import json
import os

WORKSPACE_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MAP_PATH = os.path.join(
    WORKSPACE_ROOT, "clash_widgets", "upgrade_info", "json_maps", "buildings_json_map.json"
)


def main() -> None:
    if not os.path.exists(MAP_PATH):
        raise FileNotFoundError(f"Missing map file: {MAP_PATH}")

    with open(MAP_PATH, "r", encoding="utf-8") as file:
        data = json.load(file)

    if not isinstance(data, dict):
        raise ValueError("Expected top-level JSON object in buildings_json_map.json")

    for _, entry in data.items():
        if not isinstance(entry, dict):
            continue
        display_name = entry.get("displayName")
        internal_name = entry.get("internalName")
        entry["displayName"] = internal_name
        entry["internalName"] = display_name

    with open(MAP_PATH, "w", encoding="utf-8") as file:
        json.dump(data, file, indent=2, ensure_ascii=False)
        file.write("\n")


if __name__ == "__main__":
    main()
