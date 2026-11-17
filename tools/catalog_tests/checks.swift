let root = URL(fileURLWithPath: CommandLine.arguments[1])
if CommandLine.arguments.contains("--future-json") {
    let king = ProgressCatalog.heroItems.first { $0.id == 28000000 }!
    precondition(king.maxLevel(at: 19) == 116, "New JSON hero levels must work without changing Swift")
    precondition(ProgressCatalog.heroes(in: nil, fallback: [], townHall: 19).first?.maxLevel == 116)
    let tesla = ProgressCatalog.sections.flatMap(\.groups).flatMap(\.items).first { $0.id == 1000019 }!
    precondition(ProgressCatalog.superchargeDefinition(for: tesla) != nil, "A future explicit JSON link must enable supercharges")
    print("PASS: future hero levels and supercharge reactivation follow JSON without code edits")
    exit(0)
}
let expected19 = [28000000: 115, 28000001: 115, 28000006: 100, 28000002: 90, 28000004: 60, 28000007: 30]
let expected18 = [28000000: 110, 28000001: 110, 28000006: 95, 28000002: 85, 28000004: 55, 28000007: 25]
for item in ProgressCatalog.heroItems {
    precondition(item.maxLevel(at: 19) == expected19[item.id], "TH19 hero cap: \(item.name)")
    precondition(item.maxLevel(at: 18) == expected18[item.id], "TH18 hero cap: \(item.name)")
}
let export = try JSONDecoder().decode(CoCExport.self, from: Data(#"{"heroes":[{"data":28000000,"lvl":110},{"data":28000007,"lvl":25}],"units":[{"data":4000195,"lvl":2},{"data":4000206,"lvl":1}]}"#.utf8))
let api = [HeroProfile(name: "Barbarian King", level: 109, maxLevel: 110, village: "home", equipment: nil),
           HeroProfile(name: "Archer Queen", level: 110, maxLevel: 110, village: "home", equipment: nil)]
let profileHeroes = ProgressCatalog.heroes(in: export, fallback: api, townHall: 19)
precondition(profileHeroes.map(\.name) == ProgressCatalog.heroItems.map(\.name))
precondition(profileHeroes.first { $0.name == "Barbarian King" }?.level == 110)
precondition(profileHeroes.first { $0.name == "Archer Queen" }?.level == 110)
precondition(profileHeroes.first { $0.name == "Grand Warden" }?.level == 0)
precondition(profileHeroes.first { $0.name == "Dragon Duke" }?.maxLevel == 30)
precondition(ProgressCatalog.heroes(in: nil, fallback: api, townHall: 19).first?.level == 109)
precondition(ProgressCatalog.heroes(in: nil, fallback: [], townHall: 1).isEmpty)

let items = ProgressCatalog.sections.flatMap(\.groups).flatMap(\.items)
let squads = ProgressCatalog.sections.first { $0.id == "squads" }!
precondition(squads.groups.flatMap(\.items).map(\.id) == Array(4000195...4000206))
for (index, item) in squads.groups.flatMap(\.items).enumerated() {
    precondition(item.maxLevel(at: index + 7) == 0)
    precondition(item.maxLevel(at: index + 8) > 0)
}
precondition(squads.inventory(in: export)[4000195]?[2] == 1)
for id in [1000105, 1000107, 1000108] {
    let item = items.first { $0.id == id }!
    precondition(item.maxLevel(at: 18) == 0)
    precondition(item.maxLevel(at: 19) > 0)
}
let spell = items.first { $0.id == 26000153 }!
precondition(spell.maxLevel(at: 16) == 0)
precondition(spell.maxLevel(at: 17) == 2)
precondition(spell.maxLevel(at: 18) == 3)
precondition(spell.maxLevel(at: 19) == 4)

let remainingSupercharges: Set<Int> = [1000013, 1000032, 1000027, 1000067, 1000077, 1000089, 1000086, 1000102]
let activeSupercharges = Set(items.filter { ProgressCatalog.superchargeDefinition(for: $0) != nil }.map(\.id))
precondition(activeSupercharges == remainingSupercharges)
for id in [1000012, 1000019, 1000021, 1000084, 1000079, 1000085, 1000015, 1000004, 1000002, 1000023, 1000011] {
    let item = items.first { $0.id == id }!
    precondition(ProgressCatalog.superchargeDefinition(for: item) == nil)
    let stale = try JSONDecoder().decode(CoCExport.self, from: JSONSerialization.data(withJSONObject:
        ["buildings": [["data": id, "lvl": item.maxLevel(at: 19), "supercharge": 2]]]))
    precondition(ProgressCatalog.superchargeCounts(for: item, in: stale, townHall: 19).isEmpty)
}
let mortar = items.first { $0.id == 1000013 }!
let mortarDefinition = ProgressCatalog.superchargeDefinition(for: mortar)!
let eligible = try JSONDecoder().decode(CoCExport.self, from: JSONSerialization.data(withJSONObject:
    ["buildings": [["data": mortar.id, "lvl": mortarDefinition.requiredBuildingLevel, "cnt": 2],
                   ["data": mortar.id, "lvl": mortarDefinition.requiredBuildingLevel, "supercharge": 1],
                   ["data": mortar.id, "lvl": mortarDefinition.requiredBuildingLevel - 1, "supercharge": 1]]]))
precondition(ProgressCatalog.superchargeCounts(for: mortar, in: eligible, townHall: 19) == [0: 2, 1: 1])
precondition(ProgressCatalog.superchargeCounts(for: mortar, in: eligible, townHall: mortarDefinition.unlockTownHall - 1).isEmpty)

let presentation = UpgradePresentationCatalog(
    progressData: try Data(contentsOf: root.appendingPathComponent("progress_sections.json")),
    mappingData: try Data(contentsOf: root.appendingPathComponent("mapping.json")),
    assetData: try Data(contentsOf: root.appendingPathComponent("asset_map.json")))
func upgrade(_ id: Int, _ oldName: String, _ category: UpgradeCategory = .builderVillage) throws -> BuildingUpgrade {
    // Reuse Codable defaults so this check also covers previously saved row names.
    let json: [String: Any] = ["id": UUID().uuidString, "dataId": id, "name": oldName,
                              "category": category.rawValue, "targetLevel": 2,
                              "startTime": 0, "endTime": 100, "totalDuration": 100]
    return try JSONDecoder().decode(BuildingUpgrade.self, from: JSONSerialization.data(withJSONObject: json))
}
let shrine = try upgrade(1000105, "Guardian Building")
precondition(presentation.displayName(for: shrine) == "Guardian Shrine")
precondition(presentation.iconCandidates(for: shrine).first == "buildings_home/guardian_shrine")
let pekka = try upgrade(4000204, "PEKKA Etitan Squad", .lab)
precondition(presentation.displayName(for: pekka) == "P.E.K.K.A Titan Squad")
precondition(presentation.iconCandidates(for: pekka).first == "lab/p_e_k_k_a_titan_squad")
let hero = try upgrade(28000006, "Minion Hero")
precondition(presentation.iconCandidates(for: hero).first == "heroes/minion_prince")
let weapon = try upgrade(1000001, "Town Hall Weapon")
precondition(presentation.displayName(for: weapon) == "Town Hall Weapon")
precondition(presentation.iconCandidates(for: weapon).first == "buildings_home/town_hall_weapon")
let bb = try upgrade(1000053, "bb_Battle Machine", .builderBase)
precondition(presentation.iconCandidates(for: bb).first == "builder_base/battle_machine")
let names = DataService().loadBuildingNameToIdData()!
precondition(names["cannon"] == 1000008)
precondition(names["bb cannon"] == 1000044)
precondition(names["guardian building"] == 1000105)
precondition(names["guardian shrine"] == 1000105)
print("PASS: shared TH18/19 hero caps, import/API precedence, squad/spell unlocks, new buildings, app/widget names/icons, village name collisions")
