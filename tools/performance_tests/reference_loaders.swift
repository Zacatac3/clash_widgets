// Frozen pre-optimization implementations for differential regression checks.
// Resource resolution and DataService dependencies are supplied by the harness.

// DURATION_REFERENCE
    private static func loadDurationsFromParsedJSON() -> [Int: [Double]]? {
        let files: [(String, String)] = [
            ("buildings.json", "buildTimeSeconds"),
            ("characters.json", "upgradeTimeSeconds"),
            ("heroes.json", "upgradeTimeSeconds"),
            ("pets.json", "upgradeTimeSeconds"),
            ("spells.json", "upgradeTimeSeconds"),
            ("traps.json", "buildTimeSeconds"),
            ("weapons.json", "buildTimeSeconds"),
            ("mini_levels.json", "buildTimeSeconds"),
            ("seasonal_defense_modules.json", "buildTimeSeconds")
        ]

        var output: [Int: [Double]] = [:]
        let folders = candidateFolderURLs(named: "parsed_json_files")

        for folder in folders {
            for (fileName, durationKey) in files {
                let fileURL = folder.appendingPathComponent(fileName)
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                if let parsed = parseParsedDurationData(data: data, durationKey: durationKey) {
                    for (id, durations) in parsed where !durations.isEmpty {
                        output[id] = durations
                    }
                }
            }
        }

        return output.isEmpty ? nil : output
    }

    private static func loadDurationIndexingFromParsedJSON() -> [Int: DurationIndexing]? {
        let files: [String] = [
            "buildings.json",
            "characters.json",
            "heroes.json",
            "pets.json",
            "spells.json",
            "traps.json",
            "weapons.json",
            "mini_levels.json",
            "seasonal_defense_modules.json"
        ]

        var output: [Int: DurationIndexing] = [:]
        let folders = candidateFolderURLs(named: "parsed_json_files")

        for folder in folders {
            for fileName in files {
                let fileURL = folder.appendingPathComponent(fileName)
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                guard let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else { continue }
                let indexing: DurationIndexing = currentLevelDurationFiles.contains(fileName) ? .currentLevel : .targetLevel
                for entry in raw {
                    guard let idValue = entry["id"] else { continue }
                    let id: Int?
                    if let n = idValue as? Int { id = n }
                    else if let n = idValue as? Double { id = Int(n) }
                    else if let s = idValue as? String { id = Int(s) }
                    else { id = nil }
                    guard let resolvedId = id else { continue }
                    if output[resolvedId] == nil {
                        output[resolvedId] = indexing
                    }
                }
            }
        }

        return output.isEmpty ? nil : output
    }

    private static func parseParsedDurationData(
        data: Data,
        durationKey: String
    ) -> [Int: [Double]]? {
        guard let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else { return nil }
        var parsed: [Int: [Double]] = [:]

        for entry in raw {
            guard let idValue = entry["id"] else { continue }
            let id: Int?
            if let n = idValue as? Int { id = n }
            else if let n = idValue as? Double { id = Int(n) }
            else if let s = idValue as? String { id = Int(s) }
            else { id = nil }
            guard let resolvedId = id else { continue }

            guard let levels = entry["levels"] as? [[String: Any]] else { continue }
            var durations: [Double] = []
            for level in levels {
                let value = level[durationKey]
                if let n = value as? Double {
                    durations.append(n)
                } else if let n = value as? Int {
                    durations.append(Double(n))
                } else if let s = value as? String, let n = Double(s) {
                    durations.append(n)
                }
            }
            if !durations.isEmpty {
                parsed[resolvedId] = durations
            }
        }

        return parsed.isEmpty ? nil : parsed
    }


// WALL_REFERENCE
    private func loadTownHallLimits() -> [Int: [String: Any]]? {
        if let url = parsedJSONURL(forResource: "townhall_levels"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           !json.isEmpty {
            var result: [Int: [String: Any]] = [:]
            for entry in json {
                if let thLevel = entry["townHallLevel"] as? Int,
                   let counts = entry["counts"] as? [String: Any] {
                    result[thLevel] = counts
                }
            }
            if !result.isEmpty {
                return result
            }
        }

        guard let wallCounts = loadWallCountsFromGameConstants() else {
            return nil
        }
        var result: [Int: [String: Any]] = [:]
        for (thLevel, entry) in wallCounts {
            result[thLevel] = ["Wall": entry.totalWalls]
        }
        return result.isEmpty ? nil : result
    }

    private func loadWallCountsFromGameConstants() -> [Int: (maxWallLevel: Int, totalWalls: Int)]? {
        guard let url = parsedJSONURL(forResource: "game_constants") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let wallCounts = json["wall_counts_by_th"] as? [String: Any] else {
            return nil
        }

        var result: [Int: (maxWallLevel: Int, totalWalls: Int)] = [:]
        for (key, value) in wallCounts {
            guard let thLevel = Int(key),
                  let entry = value as? [String: Any] else { continue }
            let maxWallLevel = (entry["max_wall_level"] as? Int)
                ?? (entry["max_wall_level"] as? NSNumber)?.intValue
                ?? 0
            let totalWalls = (entry["total_walls"] as? Int)
                ?? (entry["total_walls"] as? NSNumber)?.intValue
                ?? 0
            guard maxWallLevel > 0, totalWalls > 0 else { continue }
            result[thLevel] = (maxWallLevel: maxWallLevel, totalWalls: totalWalls)
        }
        return result.isEmpty ? nil : result
    }

    private func loadBuildingCosts() -> [Int: (cost: Int, thRequirement: Int)]? {
        guard let url = parsedJSONURL(forResource: "buildings") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        
        var result: [Int: (cost: Int, thRequirement: Int)] = [:]
        for building in json {
            if let id = building["id"] as? Int, id == 1000010,
               let levels = building["levels"] as? [[String: Any]] {
                for levelInfo in levels {
                    if let level = levelInfo["level"] as? Int,
                       let cost = levelInfo["buildCost"] as? Int,
                       let thReq = levelInfo["townHallLevel"] as? Int {
                        result[level] = (cost: cost, thRequirement: thReq)
                    }
                }
            }
        }
        return result
    }


// HELPER_REFERENCE
    private func loadHelperGemCosts() -> [HelperGemCostInfo] {
        guard townHallLevel >= 9 else { return [] }
        
        guard let jsonPath = Bundle.main.path(forResource: "villager_apprentices", ofType: "json", inDirectory: "json/parsed_json_files"),
              let jsonData = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)),
              let helpers = try? JSONDecoder().decode([HelperData].self, from: jsonData) else {
            return []
        }

        var result: [HelperGemCostInfo] = []
        
        // Map helpers to their profile levels and icons
        let helperMapping: [(internalName: String, displayName: String, category: String, iconName: String, currentLevelKeyPath: KeyPath<DataService, Int>)] = [
            ("BuilderApprentice", "Builder's Apprentice", "Archer Queen", "profile/apprentice_builder", \DataService.builderApprenticeLevel),
            ("ResearchApprentice", "Lab Assistant", "Lab", "profile/lab_assistant", \DataService.labAssistantLevel),
            ("Alchemist", "Alchemist", "Lab", "profile/alchemist", \DataService.alchemistLevel)
        ]

        for mapping in helperMapping {
            guard let helperData = helpers.first(where: { $0.internalName == mapping.internalName }) else { continue }
            
            // Get current helper level from dataService profile settings
            let currentLevel = dataService[keyPath: mapping.currentLevelKeyPath]
            let isUnlocked = currentLevel > 0
            
            let availableLevels = helperData.levels.filter { Int($0.RequiredTownHallLevel) ?? 0 <= townHallLevel }
            guard !availableLevels.isEmpty else { continue }
            
            let maxLevel = availableLevels.last?.level ?? 0
            let remainingLevels = max(0, maxLevel - currentLevel)
            
            // Only include levels after current level
            let remainingLevelCosts = availableLevels
                .filter { $0.level > currentLevel }
                .map { level -> HelperLevelInfo in
                    HelperLevelInfo(
                        level: level.level,
                        cost: Int(level.Cost) ?? 0,
                        requiredTH: Int(level.RequiredTownHallLevel) ?? 9
                    )
                }
            
            let remainingTotalCost = remainingLevelCosts.reduce(0) { $0 + $1.cost }
            
            result.append(HelperGemCostInfo(
                id: mapping.internalName,
                displayName: mapping.displayName,
                category: mapping.category,
                iconName: mapping.iconName,
                currentLevel: currentLevel,
                maxLevel: maxLevel,
                isUnlocked: isUnlocked,
                remainingLevels: remainingLevels,
                remainingLevelCosts: remainingLevelCosts,
                remainingTotalCost: remainingTotalCost
            ))
        }
        
        return result
    }


// EQUIPMENT_REFERENCE
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

