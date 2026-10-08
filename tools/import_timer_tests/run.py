"""Exercise DataService's actual import conversion with deterministic lookup stubs.

Run from the repository root: python3 tools/import_timer_tests/run.py
Only catalog lookups are stubbed; conversion and event/timer math are production code.
"""
from pathlib import Path
import subprocess
import tempfile

source = Path("clash_widgets/DataService.swift").read_text()
conversion = source[source.index("    private func collectUpgrades("):source.index("    private func durationFor(")]
stub = """
import Foundation
final class DataService {
    var mapping: [Int: String] = [:]
    var goldPassBoost = 0
    var seasonalDefenseModuleNameOverrides: [Int: String] = [:]
    struct Weapon { let buildTimeSeconds: Int }
    func nextTownHallWeaponUpgrade(townHallLevel: Int, weaponLevel: Int) -> Weapon? { nil }
    func durationFor(dataId: Int, fromLevel: Int, buildingName: String,
                     superchargeTargetLevel: Int?) -> TimeInterval? { 1200 }
    func imported(_ export: CoCExport) -> [BuildingUpgrade] { collectUpgrades(from: export) }
"""
with tempfile.TemporaryDirectory(prefix="clashboard-import-tests-") as directory:
    main = Path(directory) / "main.swift"
    main.write_text(stub + conversion + "\n}\n" + Path("tools/import_timer_tests/checks.swift").read_text())
    executable = Path(directory) / "checks"
    subprocess.run([
        "xcrun", "swiftc", "-module-cache-path", "/tmp/clashboard-swift-module-cache",
        "clash_widgets/Models.swift", "clash_widgets/RemoteContentModels.swift",
        str(main), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True)
