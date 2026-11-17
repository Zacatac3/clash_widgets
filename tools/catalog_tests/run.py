"""Exercise production hero limits, imports and app/widget presentation lookups.

Run: python3 tools/catalog_tests/run.py
"""
from pathlib import Path
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "clash_widgets/ContentView/ProgressView.swift").read_text()
catalog = source[source.index("enum ProgressCatalog {"):source.index("enum ProgressDisplaySettings {")]
source = (root / "clash_widgets/DataService.swift").read_text()
building_names = source[source.index("    func loadBuildingNameToIdData()"):source.index("    func loadParsedUnits(")]
stub = '''import Foundation
final class DataService {
    static func candidateFolderURLs(named folder: String) -> [URL] {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        return [folder == "json" ? root : root.appendingPathComponent(folder)]
    }
'''
with tempfile.TemporaryDirectory(prefix="clashboard-catalog-tests-") as temporary:
    main = Path(temporary) / "main.swift"
    main.write_text(stub + building_names + "\n}\n" + catalog + "\n" +
                    (root / "tools/catalog_tests/checks.swift").read_text())
    executable = Path(temporary) / "checks"
    subprocess.run(["xcrun", "swiftc", "-module-cache-path", "/tmp/clashboard-swift-module-cache",
                    str(root / "clash_widgets/Models.swift"),
                    str(root / "clash_widgets/UpgradePresentationCatalog.swift"),
                    str(main), "-o", str(executable)], check=True)
    subprocess.run([str(executable), str(root / "clash_widgets/json")], check=True)

    # Exercise sync/check against disposable data; icon validation reads the real
    # asset catalog through a symlink, and never writes to it.
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("sync_catalog", root / "tools/sync_game_catalog.py")
    sync = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sync)
    fixture = Path(temporary) / "fixture"
    data = fixture / "clash_widgets/json"
    shutil.copytree(root / "clash_widgets/json", data)
    (fixture / "clash_widgets/Assets.xcassets").symlink_to(root / "clash_widgets/Assets.xcassets", target_is_directory=True)
    assert sync.synchronize(fixture, check=True)[0] == []
    # Modify only JSON and launch the same production catalog executable again.
    heroes_path = data / "parsed_json_files/heroes.json"
    heroes = json.loads(heroes_path.read_text())
    king = next(hero for hero in heroes if hero["id"] == 28000000)
    new_level = dict(king["levels"][-1], level=116)
    king["levels"].append(new_level)
    heroes_path.write_text(json.dumps(heroes))
    buildings_path = data / "parsed_json_files/buildings.json"
    buildings = json.loads(buildings_path.read_text())
    next(building for building in buildings if building["id"] == 1000019)["miniLevels"] = "Hidden Tesla Mini Levels"
    buildings_path.write_text(json.dumps(buildings))
    subprocess.run([str(executable), str(data), "--future-json"], check=True)
    # Restore production JSON for the independent sync checks below.
    shutil.copy2(root / "clash_widgets/json/parsed_json_files/heroes.json", heroes_path)
    shutil.copy2(root / "clash_widgets/json/parsed_json_files/buildings.json", buildings_path)
    catalog_path = data / "progress_sections.json"
    catalog_data = json.loads(catalog_path.read_text())
    squad = next(section for section in catalog_data["sections"] if section["id"] == "squads")["groups"][0]["items"][0]
    squad["name"] = "Renamed Squad Fixture"
    catalog_path.write_text(json.dumps(catalog_data))
    mapping_before = (data / "mapping.json").read_bytes()
    assert sync.synchronize(fixture, check=True)[0]
    assert (data / "mapping.json").read_bytes() == mapping_before
    sync.synchronize(fixture)
    assert json.loads((data / "mapping.json").read_text())["4000195"] == squad["name"]
    assert json.loads((data / "master_lists/home_village_master_upgrades.json").read_text())["sections"]["lab"]["squads"]["4000195"] == squad["name"]
    assert json.loads((data / "game_constants.json").read_text())["highest_wall_level_unlock_caps"]["20"] == 150
    assert sync.synchronize(fixture, check=True)[0] == []
    squad["id"] = 999999999
    catalog_path.write_text(json.dumps(catalog_data))
    mapping_before = (data / "mapping.json").read_bytes()
    try:
        sync.synchronize(fixture)
        raise AssertionError("Unknown Progress IDs must fail validation")
    except ValueError:
        pass
    assert (data / "mapping.json").read_bytes() == mapping_before
    print("PASS: catalog sync propagates one edit, check stays read-only, preserves wall caps, rejects invalid IDs before writing")
