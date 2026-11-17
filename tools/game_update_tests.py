#!/usr/bin/env python3
"""Regression checks for CSV preview isolation and preparation audit failures.

Run: python3 tools/game_update_tests.py
"""
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]


def fingerprints(directory):
    return {str(path.relative_to(directory)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in directory.rglob("*") if path.is_file()}


class GameUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="clashboard-game-update-tests-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        extraction = self.root / "data_extraction"
        extraction.mkdir()
        shutil.copy2(ROOT / "data_extraction/clash_csv_to_json.py", extraction)
        shutil.copy2(ROOT / "data_extraction/th19_preparation.json", extraction)
        shutil.copytree(ROOT / "data_extraction/extraxted_data", extraction / "extraxted_data",
                        ignore=shutil.ignore_patterns("previous version"))
        self.data = self.root / "clash_widgets/json"
        for folder in ["parsed_json_files", "json_maps", "master_lists"]:
            shutil.copytree(ROOT / "clash_widgets/json" / folder, self.data / folder)
        for filename in ["asset_map.json", "mapping.json", "progress_sections.json", "game_constants.json"]:
            shutil.copy2(ROOT / "clash_widgets/json" / filename, self.data / filename)

    def parser(self, *args):
        return subprocess.run([sys.executable, str(self.root / "data_extraction/clash_csv_to_json.py"), *args],
                              capture_output=True, text=True)

    def test_preview_reports_new_content_without_writing_outputs(self):
        inputs = self.root / "data_extraction/extraxted_data"
        buildings = inputs / "buildings.csv"
        with buildings.open(newline="") as source:
            headers = next(csv.reader(source))
        with buildings.open("a", newline="") as output:
            writer = csv.DictWriter(output, fieldnames=headers)
            writer.writerow({"Name": "TH19PreviewFixture", "BuildingLevel": "1", "TownHallLevel": "19"})
        before = fingerprints(self.data)
        result = self.parser("--input-dir", str(inputs), "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("+ TH19PreviewFixture", result.stdout)
        self.assertEqual(fingerprints(self.data), before)

    def test_missing_late_input_fails_before_any_output_is_written(self):
        (self.root / "data_extraction/extraxted_data/weapons.csv").unlink()
        before = fingerprints(self.data)
        result = self.parser()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("weapons.csv", result.stderr)
        self.assertEqual(fingerprints(self.data), before)

    def test_invalid_csv_fails_before_any_output_is_written(self):
        (self.root / "data_extraction/extraxted_data/guardians.csv").write_bytes(b"\xff\x00encrypted")
        before = fingerprints(self.data)
        result = self.parser()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("guardians.csv", result.stderr)
        self.assertEqual(fingerprints(self.data), before)

    def test_staging_audit_detects_missing_image_and_wrong_namespace(self):
        spec = importlib.util.spec_from_file_location("readiness", ROOT / "tools/check_th19_readiness.py")
        audit = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(audit)
        manifest = audit.read_json(self.root / "data_extraction/th19_preparation.json")
        # Seed an unfinished update so the audit must report confirmations too.
        manifest["items"][0]["id"] = None
        (self.root / "data_extraction/th19_preparation.json").write_text(json.dumps(manifest))
        constants = audit.read_json(self.data / "game_constants.json")
        constants["max_town_hall_level"] = 18
        constants["highest_wall_level_unlock_caps"].pop("20", None)
        (self.data / "game_constants.json").write_text(json.dumps(constants))
        catalog = self.root / "clash_widgets/Assets.xcassets"
        for item in manifest["items"]:
            relative = Path(item["asset"] + ".imageset")
            shutil.copytree(ROOT / "clash_widgets/Assets.xcassets" / relative, catalog / relative)
            shutil.copy2(ROOT / "clash_widgets/Assets.xcassets" / relative.parent / "Contents.json",
                         catalog / relative.parent / "Contents.json")
        _, errors, pending = audit.audit(self.root)
        self.assertEqual(errors, [])
        self.assertTrue(any("max_town_hall_level is still 18" in issue for issue in pending))
        self.assertTrue(any("level 20" in issue for issue in pending))
        image_set = catalog / "buildings_home/guardian_shrine.imageset"
        (image_set / "guardian_shrine.png").unlink()
        (catalog / "lab/Contents.json").write_text(json.dumps({"properties": {"provides-namespace": False}}))
        _, errors, _ = audit.audit(self.root)
        self.assertTrue(any("missing/empty image guardian_shrine.png" in issue for issue in errors))
        self.assertTrue(any("compiles as" in issue for issue in errors))

    def test_townhall_counts_survive_removed_marker_and_inherit_blanks(self):
        result = self.parser()
        self.assertEqual(result.returncode, 0, result.stderr)
        levels = json.loads((self.data / "parsed_json_files/townhall_levels.json").read_text())
        self.assertEqual([entry["townHallLevel"] for entry in levels], list(range(1, 20)))
        th19 = levels[-1]["counts"]
        self.assertEqual(th19["Wall"], 350)
        self.assertEqual(th19["Army Camp"], 4)
        self.assertEqual(th19["Squad Barracks"], 1)
        self.assertEqual(th19["Guardian Building"], 1)
        self.assertEqual(th19["Spiky Tower"], 2)
        self.assertEqual(th19["Firecracker Tower"], 2)
        self.assertNotIn("WarPrizeResourceCap", th19)
        buildings = json.loads((self.data / "parsed_json_files/buildings.json").read_text())
        firecracker = next(entry for entry in buildings if entry["id"] == 1000108)
        self.assertEqual(firecracker["levels"][1]["townHallLevel"], 19)
        self.assertEqual(firecracker["levels"][1]["buildResource"], "Gold")
        self.assertEqual(next(entry for entry in buildings if entry["id"] == 1000019)["miniLevels"], "")
        self.assertEqual(next(entry for entry in buildings if entry["id"] == 1000013)["miniLevels"], "Mortar Mini Levels")

    def test_changed_townhall_schema_fails_before_replacing_any_data(self):
        csv_path = self.root / "data_extraction/extraxted_data/townhall_levels.csv"
        csv_path.write_text(csv_path.read_text().replace('"Wall"', '"RenamedWallColumn"', 1))
        before = fingerprints(self.data)
        result = self.parser()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("townhall_levels.csv", result.stderr)
        self.assertEqual(fingerprints(self.data), before)

    def test_production_swift_wall_images_and_configured_limits(self):
        # Exercise the production catalog and cap resolver with synthetic future constants.
        source = (ROOT / "clash_widgets/ContentView/ProgressView.swift").read_text()
        catalog = source[source.index("enum ProgressCatalog {"):source.index("enum ProgressDisplaySettings {")]
        source = (ROOT / "clash_widgets/DataService.swift").read_text()
        caps = source[source.index("    private static let highestWallLevelUnlockedCountsByWallLevel:"):
                      source.index("\n    var currentProfile:")]
        resolver = source[source.index("    func highestWallLevelUnlockedCount("):
                          source.index("    private func nextTownHallWeaponUpgrade(")]
        constants = json.loads((self.data / "game_constants.json").read_text())
        constants["highest_wall_level_unlock_caps"]["20"] = 150
        constants["max_town_hall_level"] = 19
        (self.data / "game_constants.json").write_text(json.dumps(constants))
        main = self.root / "main.swift"
        main.write_text('''import Foundation
final class DataService {
    static func candidateFolderURLs(named folder: String) -> [URL] {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        return folder == "json" ? [root] : [root.appendingPathComponent(folder)]
    }
''' + caps + resolver + "\n}\n" + catalog + '''
let service = DataService()
precondition(service.highestWallLevelUnlockedCount(for: 19, totalWallCount: 325) == 325)
precondition(service.highestWallLevelUnlockedCount(for: 20, totalWallCount: 325) == 150)
precondition(service.highestWallLevelUnlockedCount(for: 20, totalWallCount: 100) == 100)
precondition(service.highestWallLevelUnlockedCount(for: 21, totalWallCount: 325) == 325)
precondition(service.highestWallLevelUnlockedCount(for: 20, totalWallCount: -1) == 0)
precondition(ProgressCatalog.maximumTownHallLevel == 19)
let wall = ProgressCatalog.sections.flatMap { $0.groups }.flatMap { $0.items }.first { $0.id == 1000010 }!
precondition(wall.assetName(for: 19) == "resources/wall_19")
precondition(wall.assetName(for: 20) == "resources/wall_20")
precondition(wall.assetName(for: 21) == "resources/wall_21")
precondition(wall.assetName(for: 0) == "resources/wall_1")
''')
        executable = self.root / "checks"
        subprocess.run(["xcrun", "swiftc", "-module-cache-path", "/tmp/clashboard-swift-module-cache",
                        str(ROOT / "clash_widgets/Models.swift"),
                        str(ROOT / "clash_widgets/RemoteContentModels.swift"),
                        str(main), "-o", str(executable)], check=True)
        subprocess.run([str(executable), str(self.data)], check=True)


if __name__ == "__main__":
    unittest.main()
