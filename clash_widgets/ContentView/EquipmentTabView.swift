import SwiftUI

struct EquipmentView: View {
    @EnvironmentObject private var dataService: DataService
    @State private var rarityFilter: EquipmentRarityFilter = .all
    @State private var selectedHeroFilter: String = EquipmentView.allHeroesLabel
    @State private var showLocked = true
    @State private var showHiddenEquipment = false
    @State private var showHideEquipmentSheet = false
    @AppStorage("adsPreference") private var adsPreference: AdsPreference = .fullScreen

    private static let allHeroesLabel = "All Heroes"
    private static let oreCostTable = OreCostTable.shared
    private static let equipmentMetadata = EquipmentDataStore.shared

    var body: some View {
        NavigationStack {
            List {
                if equipmentLocked {
                    equipmentLockedState
                } else if equipmentEntries.isEmpty {
                    emptyState
                } else {
                    summarySection
                    filtersSection
                    if adsPreference == .banner {
                        Section {
                            BannerAdPlaceholder()
                        }
                    }
                    equipmentSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Equipment")
            .sheet(isPresented: $showHideEquipmentSheet) {
                EquipmentVisibilitySheet(
                    entries: visibilityMenuEntries,
                    hiddenNames: dataService.hiddenEquipmentNames,
                    onSetHidden: { name, hidden in
                        dataService.setEquipmentHidden(named: name, hidden: hidden)
                    },
                    onReset: {
                        dataService.resetHiddenEquipment()
                    }
                )
                .adaptivePanelPresentation()
            }
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(summaryTitle)
                    .font(.headline)
                OreTotalsView(totals: totalOreCost, showStarry: totalOreCost.starry > 0)
            }
            .padding(.vertical, 4)
        }
    }

    private var summaryTitle: String {
        let isAllHeroes = selectedHeroFilter == Self.allHeroesLabel
        if isAllHeroes && showLocked {
            switch rarityFilter {
            case .all:
                return "Total to max all equipment"
            case .epic:
                return "Total to max all epic equipment"
            case .common:
                return "Total to max all common equipment"
            }
        }
        return "Total to max all displayed equipment"
    }

    private var filtersSection: some View {
        Section("Filters") {
            Picker("Rarity", selection: $rarityFilter) {
                ForEach(EquipmentRarityFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Picker("Hero", selection: $selectedHeroFilter) {
                ForEach(heroOptions, id: \.self) { hero in
                    Text(hero).tag(hero)
                }
            }

            Toggle("Show locked equipment", isOn: $showLocked)

            Toggle("Show hidden equipment", isOn: $showHiddenEquipment)

            Button {
                showHideEquipmentSheet = true
            } label: {
                HStack {
                    Text("Hide Equipment")
                    Spacer()
                    if hiddenEquipmentCount > 0 {
                        Text("\(hiddenEquipmentCount) hidden")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("All visible")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var equipmentSection: some View {
        ForEach(groupedHeroes, id: \.self) { hero in
            Section {
                ForEach(groupedEntries[hero] ?? []) { entry in
                    let totals = EquipmentView.oreCostTable
                        .totalCost(from: entry.level, to: entry.maxLevel)
                        .adjusted(for: entry.rarity)
                    EquipmentRow(entry: entry, totals: totals)
                        .opacity(entry.isHidden ? 0.6 : 1.0)
                }
            } header: {
                HeroSectionHeader(heroName: hero)
            }
        }
    }

    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No equipment data yet")
                    .font(.headline)
                Text("Sync your profile to load hero equipment levels.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var equipmentLockedState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("Equipment unlocks at Town Hall 8")
                    .font(.headline)
                Text("Reach Town Hall 8 to start managing hero equipment and ore costs.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var heroOptions: [String] {
        let heroes = equipmentEntries.map { $0.hero }.filter { !$0.isEmpty }
        let unique = Set(heroes)
        // Order by heroes_config.json unlock order, then alphabetical for unknowns
        let configOrder = HeroConfigStore.shared.configs.map { $0.displayName }
        let ordered = configOrder.filter { unique.contains($0) }
        let remaining = unique.subtracting(Set(configOrder)).sorted()
        return [Self.allHeroesLabel] + ordered + remaining
    }

    private var filteredEntries: [EquipmentEntry] {
        equipmentEntries
            .filter { entry in
                switch rarityFilter {
                case .all:
                    return true
                case .common:
                    return entry.rarity == .common
                case .epic:
                    return entry.rarity == .epic
                }
            }
            .filter { entry in
                guard selectedHeroFilter != Self.allHeroesLabel else { return true }
                return entry.hero == selectedHeroFilter
            }
            .filter { entry in
                showLocked || entry.isUnlocked
            }
            .filter { entry in
                showHiddenEquipment || !entry.isHidden
            }
            .sorted { lhs, rhs in
                if lhs.hero != rhs.hero {
                    return lhs.hero < rhs.hero
                }
                if lhs.rarity != rhs.rarity {
                    return lhs.rarity.sortRank < rhs.rarity.sortRank
                }
                return lhs.name < rhs.name
            }
    }

    private var groupedEntries: [String: [EquipmentEntry]] {
        Dictionary(grouping: filteredEntries, by: { $0.hero })
            .mapValues { entries in
                entries.sorted { lhs, rhs in
                    if lhs.rarity != rhs.rarity {
                        return lhs.rarity.sortRank < rhs.rarity.sortRank
                    }
                    return lhs.name < rhs.name
                }
            }
    }

    private var groupedHeroes: [String] {
        let available = Set(groupedEntries.keys.filter { !$0.isEmpty })
        // Order by heroes_config.json unlock order, then alphabetical for unknowns
        let configOrder = HeroConfigStore.shared.configs.map { $0.displayName }
        let ordered = configOrder.filter { available.contains($0) }
        let remaining = available.subtracting(Set(configOrder)).sorted()
        return ordered + remaining
    }

    private var totalOreCost: OreTotals {
        filteredEntries.reduce(OreTotals()) { partial, entry in
            let totals = EquipmentView.oreCostTable
                .totalCost(from: entry.level, to: entry.maxLevel)
                .adjusted(for: entry.rarity)
            return partial + totals
        }
    }

    private var hiddenEquipmentCount: Int {
        equipmentEntries.filter { $0.isHidden }.count
    }

    private var visibilityMenuEntries: [EquipmentEntry] {
        equipmentEntries.sorted { lhs, rhs in
            if lhs.hero != rhs.hero {
                return lhs.hero < rhs.hero
            }
            if lhs.rarity != rhs.rarity {
                return lhs.rarity.sortRank < rhs.rarity.sortRank
            }
            return lhs.name < rhs.name
        }
    }

    private var equipmentEntries: [EquipmentEntry] {
        let profile = dataService.currentProfile?.cachedProfile ?? dataService.cachedProfile
        guard let profile else { return [] }
        let hasEquipmentUnlocked = profile.townHallLevel >= 8
        let levelsByName = EquipmentDataStore.apiLevels(in: profile.heroEquipment ?? [])

        return EquipmentView.equipmentMetadata.entries.compactMap { metadata in
            let heroUnlockLevel = heroUnlockTownHall(metadata.hero)
            guard profile.townHallLevel >= heroUnlockLevel else {
                return nil
            }
            let lookupKey = metadata.name.lowercased()
            let apiLevel = levelsByName[lookupKey]
            let level = hasEquipmentUnlocked ? (apiLevel ?? 0) : 0
            let maxLevel = metadata.rarity.maxLevel
            let isUnlocked = hasEquipmentUnlocked && apiLevel != nil
            let isHidden = dataService.isEquipmentHidden(named: metadata.name)

            return EquipmentEntry(
                name: metadata.name,
                level: level,
                maxLevel: maxLevel,
                hero: metadata.hero,
                rarity: metadata.rarity,
                isUnlocked: isUnlocked,
                isHidden: isHidden
            )
        }
    }

    private func heroUnlockTownHall(_ heroName: String) -> Int {
        // Prefer config-driven values so new heroes work without code changes
        if let configValue = HeroConfigStore.shared.equipmentUnlockTownHall(for: heroName) {
            return configValue
        }
        // Hardcoded fallback
        switch heroName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "barbarian king":
            return 8
        case "archer queen":
            return 8
        case "minion prince":
            return 9
        case "grand warden":
            return 11
        case "royal champion":
            return 13
        case "dragon duke":
            return 15
        default:
            return 8
        }
    }

    private var equipmentLocked: Bool {
        let profile = dataService.currentProfile?.cachedProfile ?? dataService.cachedProfile
        guard let profile else { return false }
        return profile.townHallLevel > 0 && profile.townHallLevel < 8
    }
}

private struct EquipmentEntry: Identifiable {
    var id: String { name }
    let name: String
    let level: Int
    let maxLevel: Int
    let hero: String
    let rarity: EquipmentRarity
    let isUnlocked: Bool
    let isHidden: Bool

    var assetName: String {
        "equipment/\(name.slugifiedAssetName)"
    }

    var remainingLevels: Int {
        max(0, maxLevel - level)
    }
}

private struct EquipmentRow: View {
    let entry: EquipmentEntry
    let totals: OreTotals

    private var showStarry: Bool {
        // Show starry column only if this entry actually has a non-zero starry cost
        totals.starry > 0
    }

    private var levelCosts: [(level: Int, cost: OreTotals)] {
        guard entry.level < entry.maxLevel else { return [] }
        return (entry.level + 1...entry.maxLevel).compactMap { level in
            let cost = OreCostTable.levelCost(for: level)
                .adjusted(for: entry.rarity)
            return (level: level, cost: cost)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(entry.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .saturation(entry.isUnlocked ? 1 : 0)
                    .opacity(entry.isUnlocked ? 1 : 0.4)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemBackground)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.headline)
                    Text(entry.hero)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Lv \(entry.level)/\(entry.maxLevel)")
                        .font(.subheadline)
                    Text(entry.isHidden ? "Hidden" : (entry.isUnlocked ? "Unlocked" : "Locked"))
                        .font(.caption2)
                        .foregroundColor(entry.isHidden ? .orange : (entry.isUnlocked ? .green : .red))
                }
            }

            if entry.remainingLevels == 0 {
                Text("Max level")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Text("Remaining levels: \(entry.remainingLevels)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(spacing: 6) {
                    ForEach(levelCosts, id: \.level) { item in
                        HStack {
                            Text("Lvl \(item.level):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            OreTotalsView(totals: item.cost, showStarry: showStarry, compact: true)
                        }
                    }
                }

                Divider()

                HStack {
                    Text("Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    OreTotalsView(totals: totals, showStarry: showStarry, compact: true)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HeroSectionHeader: View {
    let heroName: String

    var body: some View {
        HStack(spacing: 10) {
            Image(heroAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
            Text(heroName)
                .font(.headline)
        }
        .padding(.vertical, 4)
    }

    private var heroAssetName: String {
        // Prefer config-driven asset names so heroes_config.json is the single source of truth
        if let config = HeroConfigStore.shared.configs.first(where: {
            $0.displayName.lowercased() == heroName.lowercased()
        }), let assetName = config.assetName {
            return assetName
        }
        // Hardcoded fallback
        switch heroName {
        case "Barbarian King":
            return "heroes/Barbarian_King"
        case "Archer Queen":
            return "heroes/Archer_Queen"
        case "Grand Warden":
            return "heroes/Grand_Warden"
        case "Royal Champion":
            return "heroes/Royal_Champion"
        case "Minion Prince":
            return "heroes/minion_prince"
        default:
            return "heroes/Barbarian_King"
        }
    }
}

private struct OreTotalsView: View {
    let totals: OreTotals
    var showStarry: Bool = true
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 10 : 16) {
            OreBadge(imageName: "equipment/shiny_ore", value: totals.shiny, compact: compact)
            OreBadge(imageName: "equipment/glowy_ore", value: totals.glowy, compact: compact)
            if showStarry {
                OreBadge(imageName: "equipment/starry_ore", value: totals.starry, compact: compact)
            }
        }
    }
}

private struct OreBadge: View {
    let imageName: String
    let value: Int
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 16 : 18, height: compact ? 16 : 18)
            Text(NumberFormatter.ore.string(from: NSNumber(value: value)) ?? "0")
                .font(compact ? .caption : .subheadline)
                .foregroundColor(.primary)
        }
        .padding(.vertical, compact ? 2 : 4)
        .padding(.horizontal, compact ? 6 : 8)
        .background(RoundedRectangle(cornerRadius: compact ? 8 : 10).fill(Color(.tertiarySystemBackground)))
    }
}

private struct OreTotals: Equatable {
    var shiny: Int = 0
    var glowy: Int = 0
    var starry: Int = 0

    static func + (lhs: OreTotals, rhs: OreTotals) -> OreTotals {
        OreTotals(
            shiny: lhs.shiny + rhs.shiny,
            glowy: lhs.glowy + rhs.glowy,
            starry: lhs.starry + rhs.starry
        )
    }

    func adjusted(for rarity: EquipmentRarity) -> OreTotals {
        switch rarity {
        case .common:
            // Common equipment costs only Shiny and Glowy ore — no Starry
            return OreTotals(shiny: shiny, glowy: glowy, starry: 0)
        case .epic:
            // Epic equipment costs Shiny, Glowy, and Starry ore
            return self
        }
    }
}

private struct OreCostTable {
    struct LevelCost {
        let level: Int
        let shiny: Int
        let glowy: Int
        let starry: Int
        let cumulativeShiny: Int
        let cumulativeGlowy: Int
        let cumulativeStarry: Int
    }

    let levels: [Int: LevelCost]
    let maxLevel: Int

    func totalCost(from currentLevel: Int, to maxLevel: Int) -> OreTotals {
        guard currentLevel < maxLevel else { return OreTotals() }
        let cappedMax = min(maxLevel, self.maxLevel)
        let cappedCurrent = max(0, min(currentLevel, cappedMax))

        if let maxCost = levels[cappedMax], let currentCost = levels[cappedCurrent] {
            return OreTotals(
                shiny: maxCost.cumulativeShiny - currentCost.cumulativeShiny,
                glowy: maxCost.cumulativeGlowy - currentCost.cumulativeGlowy,
                starry: maxCost.cumulativeStarry - currentCost.cumulativeStarry
            )
        }

        var totals = OreTotals()
        if cappedCurrent < cappedMax {
            for level in (cappedCurrent + 1)...cappedMax {
                if let cost = levels[level] {
                    totals.shiny += cost.shiny
                    totals.glowy += cost.glowy
                    totals.starry += cost.starry
                }
            }
        }
        return totals
    }

    static let shared = load()

    static func load() -> OreCostTable {
        // Try all candidate json folder locations (handles folder references and app group)
        for folder in DataService.candidateFolderURLs(named: "json") {
            let url = folder.appendingPathComponent("ore_costs.csv")
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8) {
                let result = parse(csv: text)
                if result.maxLevel > 0 { return result }  // only accept if it actually parsed ore data
            }
        }
        // Legacy direct bundle lookups
        if let url = Bundle.main.url(forResource: "ore_costs", withExtension: "csv", subdirectory: "json")
            ?? Bundle.main.url(forResource: "ore_costs", withExtension: "csv"),
           let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            let result = parse(csv: text)
            if result.maxLevel > 0 { return result }
        }
        // Fall back to embedded data (covers levels 1-27, sufficient for all current equipment)
        return parse(csv: defaultCSV)
    }

    static func levelCost(for level: Int) -> OreTotals {
        guard let cost = OreCostTable.shared.levels[level] else { return OreTotals() }
        return OreTotals(shiny: cost.shiny, glowy: cost.glowy, starry: cost.starry)
    }

    static func parse(csv: String) -> OreCostTable {
        let lines = csv
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
        guard lines.count > 1 else {
            return OreCostTable(levels: [:], maxLevel: 0)
        }

        var parsed: [Int: LevelCost] = [:]
        var maxLevel = 0

        for line in lines.dropFirst() {
            let columns = line.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard columns.count >= 7,
                  let level = Int(columns[0]),
                  let shiny = Int(columns[1]),
                  let glowy = Int(columns[2]),
                  let starry = Int(columns[3]),
                  let cumulativeShiny = Int(columns[4]),
                  let cumulativeGlowy = Int(columns[5]),
                  let cumulativeStarry = Int(columns[6])
            else { continue }

            parsed[level] = LevelCost(
                level: level,
                shiny: shiny,
                glowy: glowy,
                starry: starry,
                cumulativeShiny: cumulativeShiny,
                cumulativeGlowy: cumulativeGlowy,
                cumulativeStarry: cumulativeStarry
            )
            maxLevel = max(maxLevel, level)
        }

        return OreCostTable(levels: parsed, maxLevel: maxLevel)
    }

    private static let defaultCSV = """
Level,Shiny Ore Cost,Glowy Ore Cost,Starry Ore Cost,Cumulative Shiny,Cumulative Glowy,Cumulative Starry
1,0,0,0,0,0,0
2,120,0,0,120,0,0
3,240,20,0,360,20,0
4,400,0,0,760,20,0
5,600,0,0,1360,20,0
6,840,100,0,2200,120,0
7,1120,0,0,3320,120,0
8,1440,0,0,4760,120,0
9,1800,200,10,6560,320,10
10,1900,0,0,8460,320,10
11,2000,0,0,10460,320,10
12,2100,400,20,12560,720,30
13,2200,0,0,14760,720,30
14,2300,0,0,17060,720,30
15,2400,600,30,19460,1320,60
16,2500,0,0,21960,1320,60
17,2600,0,0,24560,1320,60
18,2700,600,50,27260,1920,110
19,2800,0,0,30060,1920,110
20,2900,0,0,32960,1920,110
21,3000,600,100,35960,2520,210
22,3100,0,0,39060,2520,210
23,3200,0,0,42260,2520,210
24,3300,600,120,45560,3120,330
25,3400,0,0,48960,3120,330
26,3500,0,0,52460,3120,330
27,3600,600,150,56060,3720,480
"""
}

struct EquipmentMetadata: Decodable, Hashable {
    let name: String
    let hero: String
    let rarity: EquipmentRarity

    var assetName: String { "equipment/\(name.slugifiedAssetName)" }

    private enum CodingKeys: String, CodingKey {
        case name
        case hero
        case rarity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.hero = try container.decode(String.self, forKey: .hero)
        let rarityRaw = (try? container.decode(String.self, forKey: .rarity)) ?? "common"
        self.rarity = EquipmentRarity(rawValue: rarityRaw.lowercased()) ?? .common
    }
}

private struct EquipmentDataFile: Decodable {
    let equipment: [EquipmentMetadata]
}

struct HeroConfigStore {
    let configs: [HeroConfig]

    static let shared = HeroConfigStore.load()

    static func load() -> HeroConfigStore {
        // Try all candidate json folder locations
        for folder in DataService.candidateFolderURLs(named: "json") {
            let url = folder.appendingPathComponent("heroes_config.json")
            if let data = try? Data(contentsOf: url),
               let configs = try? JSONDecoder().decode([HeroConfig].self, from: data) {
                return HeroConfigStore(configs: configs)
            }
        }
        // Legacy direct bundle lookups
        if let url = Bundle.main.url(forResource: "heroes_config", withExtension: "json", subdirectory: "json")
            ?? Bundle.main.url(forResource: "heroes_config", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let configs = try? JSONDecoder().decode([HeroConfig].self, from: data) {
            return HeroConfigStore(configs: configs)
        }
        return HeroConfigStore(configs: [])
    }

    /// Returns the minimum TH level at which this hero's equipment should be shown.
    /// Uses max(unlockTownHall, 8) since the equipment system starts at TH8.
    func equipmentUnlockTownHall(for heroName: String) -> Int? {
        guard let config = configs.first(where: {
            $0.displayName.lowercased() == heroName.lowercased()
        }) else { return nil }
        return max(config.unlockTownHall, 8)
    }
}

struct EquipmentDataStore {
    let entries: [EquipmentMetadata]

    static let shared = EquipmentDataStore.load()

    // The API lists owned equipment only; keep missing catalog entries at level zero.
    static func apiLevels(in equipment: [HeroEquipment]) -> [String: Int] {
        Dictionary(equipment.map { ($0.name.lowercased(), $0.level) }, uniquingKeysWith: max)
    }

    static func load() -> EquipmentDataStore {
        // Try all candidate json folder locations (handles folder references and app group)
        for folder in DataService.candidateFolderURLs(named: "json") {
            let url = folder.appendingPathComponent("equipment_data.json")
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(EquipmentDataFile.self, from: data) {
                return EquipmentDataStore(entries: decoded.equipment)
            }
        }
        // Legacy direct bundle lookups
        if let url = Bundle.main.url(forResource: "equipment_data", withExtension: "json", subdirectory: "json")
            ?? Bundle.main.url(forResource: "equipment_data", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(EquipmentDataFile.self, from: data) {
            return EquipmentDataStore(entries: decoded.equipment)
        }
        return EquipmentDataStore(entries: [])
    }
}

private extension NumberFormatter {
    static let ore: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

extension String {
    var slugifiedAssetName: String {
        let lowered = lowercased()
        let allowed = lowered.map { char -> Character in
            if char.isLetter || char.isNumber {
                return char
            }
            return "_"
        }
        let collapsed = String(allowed)
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return collapsed
    }
}

extension Int {
    func formattedCompact() -> String {
        if self >= 1_000_000 {
            return String(format: "%.1fM", Double(self) / 1_000_000)
        } else if self >= 1_000 {
            return String(format: "%.0fK", Double(self) / 1_000)
        } else {
            return "\(self)"
        }
    }
}

private struct EquipmentVisibilitySheet: View {
    let entries: [EquipmentEntry]
    let hiddenNames: Set<String>
    let onSetHidden: (String, Bool) -> Void
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var hiddenCount: Int {
        entries.filter { isHidden($0) }.count
    }

    private var groupedEntriesByHero: [(hero: String, entries: [EquipmentEntry])] {
        let grouped = Dictionary(grouping: entries, by: { $0.hero })
        return grouped
            .map { hero, items in
                let sortedItems = items.sorted { lhs, rhs in
                    if lhs.rarity != rhs.rarity {
                        return lhs.rarity.sortRank < rhs.rarity.sortRank
                    }
                    return lhs.name < rhs.name
                }
                return (hero: hero, entries: sortedItems)
            }
            .sorted { $0.hero < $1.hero }
    }

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Section {
                        Text("No equipment available for this profile yet.")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(groupedEntriesByHero, id: \.hero) { group in
                        Section(group.hero) {
                            ForEach(group.entries) { entry in
                                let hidden = isHidden(entry)
                                visibilityRow(for: entry, hidden: hidden)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Hide Equipment")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") {
                        onReset()
                    }
                    .tint(.red)
                    .disabled(hiddenCount == 0)
                }
            }
        }
    }

    @ViewBuilder
    private func visibilityRow(for entry: EquipmentEntry, hidden: Bool) -> some View {
        Button {
            onSetHidden(entry.name, !hidden)
        } label: {
            HStack(spacing: 10) {
                Image(entry.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .foregroundColor(.primary)
                }

                Spacer()

                Image(systemName: hidden ? "eye.slash.fill" : "eye.fill")
                    .foregroundColor(hidden ? .orange : .green)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func isHidden(_ entry: EquipmentEntry) -> Bool {
        hiddenNames.contains(entry.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
