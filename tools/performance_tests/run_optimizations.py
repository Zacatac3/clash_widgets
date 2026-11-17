"""Differential checks against pre-optimization code, plus actual BoostManager timers.
Run from repository root: python3 tools/performance_tests/run_optimizations.py
Only resource resolution and BoostManager's persistence dependency are stubbed.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
reference = (root / 'tools/performance_tests/reference_loaders.swift').read_text()
service = (root / 'clash_widgets/DataService.swift').read_text()
def between(s, start, end):
    return s[s.index(start):s.index(end)]
def public(s):
    return s.replace('private ', '')

duration_reference = between(reference, '// DURATION_REFERENCE', '// WALL_REFERENCE')
wall_reference = between(reference, '// WALL_REFERENCE', '// HELPER_REFERENCE')
helper_reference = between(reference, '// HELPER_REFERENCE', '// EQUIPMENT_REFERENCE')
duration_current = between(service, '    private static func loadDurationsFromParsedJSON()', '    private func parseUpgradeDurationsJSON')
wall_source = (root / 'clash_widgets/ContentView/DashboardView.swift').read_text()
wall_current = between(wall_source, '    private static let loadTownHallLimitsCache', '    private var wallProgressSummary:')
helper_source = (root / 'clash_widgets/ContentView/ProfileDetailView.swift').read_text()
helper_current = between(helper_source, '    private static let helperDefinitions', '    private var heroShowcase:')
export_current = between(service, '    private var lastDecodedExportInput:', '    enum ClipboardImportResult')
sanitizer = between(service, '    private func sanitizedClipboardData(', '    private func collectUpgrades(')
header = '''import Foundation
import Combine
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let fixture = URL(fileURLWithPath: CommandLine.arguments[2])
enum DurationIndexing: String { case currentLevel, targetLevel }
let currentLevelDurationFiles: Set<String> = ["characters.json", "heroes.json", "pets.json", "spells.json"]
var folders = [root.appendingPathComponent("parsed_json_files")]
func candidateFolderURLs(named: String) -> [URL] { folders }
class DataService {
 var builderApprenticeLevel = 0
 var labAssistantLevel = 0
 var alchemistLevel = 0
}
enum TestBundle {
 static var reads = 0
 static func path(forResource: String, ofType: String, inDirectory: String) -> String? {
  reads += 1
  return root.appendingPathComponent("parsed_json_files/" + forResource + "." + ofType).path
 }
}
'''
code = header
for name, src in [('ReferenceDuration', duration_reference), ('CurrentDuration', duration_current)]:
    code += 'struct ' + name + ' {\n' + public(src) + '\n}\n'
for name, src, static in [('ReferenceWall', wall_reference, ''), ('CurrentWall', wall_current, 'static ')]:
    code += 'struct ' + name + ''' {
 static var reads = 0
 ''' + static + '''func parsedJSONURL(forResource name: String) -> URL? {
 Self.reads += 1
 return root.appendingPathComponent(name == "game_constants" ? name + ".json" : "parsed_json_files/" + name + ".json")
 }
''' + public(src) + '\n}\n'
for name, src in [('ReferenceHelper', helper_reference), ('CurrentHelper', helper_current)]:
    code += 'struct ' + name + ''' {
 let townHallLevel: Int
 let dataService: DataService
''' + public(src.replace('Bundle.main.path', 'TestBundle.path')) + '\n}\n'
code += 'class ExportDecoder {\n' + public(export_current + sanitizer) + '\n}\n'
code += r'''
func checkDurations() {
 let old = ReferenceDuration.loadDurationsFromParsedJSON()
 let new = CurrentDuration.loadDurationsFromParsedJSON()
 precondition(old == new?.durations)
 if old != nil {
  let indexing = ReferenceDuration.loadDurationIndexingFromParsedJSON() ?? [:]
  precondition(indexing.mapValues(\.rawValue) == new!.indexing.mapValues(\.rawValue))
 }
}
checkDurations()
let baselineStart = ProcessInfo.processInfo.systemUptime
for _ in 0..<20 {
 _ = ReferenceDuration.loadDurationsFromParsedJSON()
 _ = ReferenceDuration.loadDurationIndexingFromParsedJSON()
}
let baselineMS = (ProcessInfo.processInfo.systemUptime - baselineStart) * 1000 / 20
let optimizedStart = ProcessInfo.processInfo.systemUptime
for _ in 0..<20 { _ = CurrentDuration.loadDurationsFromParsedJSON() }
let optimizedMS = (ProcessInfo.processInfo.systemUptime - optimizedStart) * 1000 / 20
print(String(format: "Duration tables mean over 20 loads: baseline %.2f ms, optimized %.2f ms (macOS harness)", baselineMS, optimizedMS))
// Duplicate IDs across files/folders: durations are last-wins, indexing is first-wins.
try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
try Data(#"[{"id":"42","levels":[{"buildTimeSeconds":"12"}]},{"id":43}]"#.utf8).write(to: fixture.appendingPathComponent("buildings.json"))
try Data(#"[{"id":42,"levels":[{"upgradeTimeSeconds":24}]}]"#.utf8).write(to: fixture.appendingPathComponent("characters.json"))
try Data("invalid JSON".utf8).write(to: fixture.appendingPathComponent("pets.json"))
folders.append(fixture)
checkDurations()
precondition(CurrentDuration.loadDurationsFromParsedJSON()!.durations[42] == [24])
precondition(CurrentDuration.loadDurationsFromParsedJSON()!.indexing[42] == .targetLevel)
folders = [fixture.appendingPathComponent("missing")]
precondition(CurrentDuration.loadDurationsFromParsedJSON() == nil)
print("PASS: all production durations/indexing match baseline; overrides, malformed and missing files")

let oldWall = ReferenceWall(), newWall = CurrentWall()
precondition(NSDictionary(dictionary: oldWall.loadTownHallLimits()!) == NSDictionary(dictionary: newWall.loadTownHallLimits()!))
let oldCosts = oldWall.loadBuildingCosts()!, newCosts = newWall.loadBuildingCosts()!
precondition(oldCosts.keys.sorted() == newCosts.keys.sorted())
for (key, value) in oldCosts { precondition(value == newCosts[key]!) }
let oldCounts = oldWall.loadWallCountsFromGameConstants()!, newCounts = newWall.loadWallCountsFromGameConstants()!
for (key, value) in oldCounts { precondition(value == newCounts[key]!) }
let reads = CurrentWall.reads
for _ in 0..<100 { _ = newWall.loadBuildingCosts(); _ = newWall.loadTownHallLimits(); _ = newWall.loadWallCountsFromGameConstants() }
precondition(CurrentWall.reads == reads)
print("PASS: wall tables identical, zero resource lookups across 300 warm loads")

func helperSignature(_ entries: [HelperGemCostInfo]) -> [String] {
 entries.map { e in
  "\(e.id)|\(e.currentLevel)|\(e.maxLevel)|\(e.isUnlocked)|\(e.remainingLevels)|\(e.remainingTotalCost)|" +
  e.remainingLevelCosts.map { "\($0.level):\($0.cost):\($0.requiredTH)" }.joined(separator: ",")
 }
}
let dataService = DataService()
for th in 1...19 {
 for level in 0...15 {
  dataService.builderApprenticeLevel = level
  dataService.labAssistantLevel = max(0, level - 2)
  dataService.alchemistLevel = max(0, level - 3)
  precondition(helperSignature(ReferenceHelper(townHallLevel: th, dataService: dataService).loadHelperGemCosts()) == helperSignature(CurrentHelper(townHallLevel: th, dataService: dataService).loadHelperGemCosts()))
 }
}
let helperReads = TestBundle.reads
_ = CurrentHelper(townHallLevel: 19, dataService: dataService).loadHelperGemCosts()
precondition(TestBundle.reads == helperReads)
print("PASS: helper costs match baseline across 304 TH/level combinations and stay reactive")

let decoder = ExportDecoder()
for raw in [##"{"tag":"#A","buildings":[{"data":1000010,"lvl":12,"cnt":42}]}"##, ##"{"tag":"#B"}"##, "invalid", "", ##"prefix {"tag":"#C"} suffix"##, ##"{"tag":"#A"}"##] {
 let expected = decoder.sanitizedClipboardData(from: raw).flatMap { try? JSONDecoder().decode(CoCExport.self, from: $0) }
 for _ in 0..<3 {
  let actual = decoder.decodeExport(from: raw)
  precondition(actual?.tag == expected?.tag)
  precondition(actual?.buildings?.first?.lvl == expected?.buildings?.first?.lvl)
  precondition((actual == nil) == (expected == nil))
 }
}
print("PASS: decoded export cache handles repeat reads, edits, profile switches and invalid input")
'''.replace('\\.', r'\.')

equipment_source = (root / 'clash_widgets/ContentView/EquipmentTabView.swift').read_text()
equipment_current = between(equipment_source, '    private var filteredEntries:', '    private var totalOreCost:')
equipment_reference = reference[reference.index('// EQUIPMENT_REFERENCE'):]
entry = between(equipment_source, 'private struct EquipmentEntry:', 'private struct EquipmentRow:')
code += between(equipment_source, 'extension String {', 'extension Int {')
code += public(entry) + """
struct HeroConfigStore {
 static let shared = HeroConfigStore()
 let configs = [Config(displayName: "Archer Queen"), Config(displayName: "Barbarian King")]
 struct Config { let displayName: String }
}
"""
for name, src in [('OldEquipment', equipment_reference), ('NewEquipment', equipment_current)]:
    code += 'struct ' + name + """ {
 static let allHeroesLabel = "All Heroes"
 let equipmentEntries: [EquipmentEntry]
 let rarityFilter: EquipmentRarityFilter
 let selectedHeroFilter: String
 let showLocked: Bool
 let showHiddenEquipment: Bool
""" + public(src) + '\n}\n'
code += r'''
let entries = (0..<48).reversed().map { i in
 EquipmentEntry(name: "Item \(i)", level: i % 27, maxLevel: 27,
 hero: ["Archer Queen", "Barbarian King", "Future Hero", ""][i % 4],
 rarity: i % 3 == 0 ? .epic : .common, isUnlocked: i % 2 == 0, isHidden: i % 5 == 0)
}
for rarity in EquipmentRarityFilter.allCases {
 for hero in ["All Heroes", "Archer Queen", "Future Hero", "Unknown"] {
  for locked in [true, false] {
   for hidden in [true, false] {
    let old = OldEquipment(equipmentEntries: entries, rarityFilter: rarity, selectedHeroFilter: hero, showLocked: locked, showHiddenEquipment: hidden)
    let new = NewEquipment(equipmentEntries: entries, rarityFilter: rarity, selectedHeroFilter: hero, showLocked: locked, showHiddenEquipment: hidden)
    precondition(old.groupedEntries.mapValues { $0.map(\.name) } == new.groupedEntries.mapValues { $0.map(\.name) })
    precondition(old.groupedHeroes == new.groupedHeroes(in: new.groupedEntries))
   }
  }
 }
}
print("PASS: equipment grouping/order matches baseline across 48 filter combinations")
'''

boost_source = (root / 'clash_widgets/ContentView/BoostView.swift').read_text()
boost = between(boost_source, 'private class BoostManager:', 'fileprivate struct BoostActivationRequest')
boost_code = '''import Foundation
import Combine
class DataService {
 @Published var selectedProfileID: UUID? = UUID()
 var currentProfile: PlayerAccount? = PlayerAccount()
 var clockTowerLevel = 1
 var builderApprenticeLevel = 1
 var labAssistantLevel = 1
 var activeUpgrades: [BuildingUpgrade] = []
 var saves = 0
 func updateCurrentProfile(_ change: (inout PlayerAccount) -> Void) { change(&currentProfile!) }
 func persistChanges(reloadWidgets: Bool) { saves += 1 }
 func scheduleUpgradeNotifications() {}
 func pruneCompletedUpgrades(referenceDate: Date) { activeUpgrades.removeAll { $0.endTime <= referenceDate } }
}
''' + boost + '''
let service = DataService()
private let manager = BoostManager(dataService: service)
var changes = 0
let observation = manager.objectWillChange.sink { changes += 1 }
func run(_ duration: Double) { RunLoop.main.run(until: Date().addingTimeInterval(duration)) }
run(1.2)
precondition(changes == 0 && service.saves == 0, "Idle boost manager must do no polling/publication/persistence")
manager.activateBoost(.builderPotion, durationOverride: 2)
precondition(manager.activeBoosts.count == 1)
let activeChanges = changes
run(1.1)
precondition(changes == activeChanges + 1, "Active countdown gets exactly one tick, with no no-op Published mutations")
run(1.2)
precondition(manager.activeBoosts.isEmpty && service.currentProfile!.activeBoosts.isEmpty)
let expiredChanges = changes, expiredSaves = service.saves
run(1.2)
precondition(changes == expiredChanges && service.saves == expiredSaves, "Clock stops after expiry")
manager.activateBoost(.builderPotion, durationOverride: 60)
manager.cancelBoost(manager.activeBoosts[0])
let cancelledChanges = changes
run(1.2)
precondition(changes == cancelledChanges, "Clock stops after cancellation")
manager.instantUndoActions = [InstantBoostUndoAction(id: UUID(), type: BoostType.builderPotion.rawValue,
 appliedAt: Date(), expiresAt: Date().addingTimeInterval(0.2), endTimeSnapshots: [], removedUpgrades: [])]
run(1.2)
precondition(manager.instantUndoActions.isEmpty)
let undoChanges = changes
run(1.2)
precondition(changes == undoChanges, "Undo-only clock stops after expiry")
withExtendedLifetime(observation) {}
print("PASS: boost clock idle, active cadence, expiry/persistence, cancellation and undo-only expiry")
'''
with tempfile.TemporaryDirectory(prefix='clashboard-optimization-tests-') as temp:
    temp = Path(temp)
    for name, source, extra in [('data', code, []), ('boost', boost_code, ['clash_widgets/PlayerAccount.swift'])]:
        main = temp / 'main.swift'
        main.write_text(source)
        exe = temp / name
        subprocess.run(['xcrun', 'swiftc', '-module-cache-path', '/tmp/clashboard-swift-module-cache',
                        'clash_widgets/Models.swift', *extra, str(main), '-o', str(exe)], cwd=root, check=True)
        subprocess.run([str(exe), str(root / 'clash_widgets/json'), str(temp / 'fixture')], cwd=root, check=True)
