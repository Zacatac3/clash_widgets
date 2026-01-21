import Foundation

extension DataService {
    func townHallProgressRows() -> [TownHallProgress] {
        guard let export = currentExport() else { return [] }
        let townHallLevels = cachedTownHallLevels ?? loadTownHallLevelsData() ?? []
        let buildingNameToId = cachedBuildingNameToId ?? loadBuildingNameToIdData() ?? [:]
        let parsedBuildings = cachedParsedBuildings ?? loadParsedBuildingsData() ?? []
        let parsedBuildingsById = makeParsedBuildingsByIdMap(parsedBuildings)

        let labUnits = loadParsedUnits(fileName: "characters.json")
        let labSpells = loadParsedUnits(fileName: "spells.json")
        let pets = loadParsedUnits(fileName: "pets.json")
        let heroes = loadParsedUnits(fileName: "heroes.json")

        let currentBuildingCounts = countsByLevel(from: export.buildings)
        let currentWallCounts = countsByLevel(from: export.buildings)
        let currentUnitLevels = levelsById(from: export.units)
        let currentSpellLevels = levelsById(from: export.spells)
        let currentPetLevels = levelsById(from: export.pets)
        let currentHeroLevels = levelsById(from: export.heroes)

        let labBuildingId = buildingNameToId["laboratory"]
        let petHouseId = buildingNameToId["pet shop"] ?? buildingNameToId["pet house"]

        return townHallLevels.sorted { $0.level < $1.level }.map { th in
            let labCapLevel = labBuildingId.flatMap { id in
                parsedBuildingsById[id].flatMap { buildingCapLevel($0, townHall: th.level) }
            } ?? 0
            let petHouseCap = petHouseId.flatMap { id in
                parsedBuildingsById[id].flatMap { buildingCapLevel($0, townHall: th.level) }
            } ?? 0

            let buildingTotals = buildingCategoryTotals(
                townHall: th,
                parsedBuildingsById: parsedBuildingsById,
                buildingNameToId: buildingNameToId,
                currentCountsById: currentBuildingCounts,
                includeWalls: false
            )

            let wallTotals = buildingCategoryTotals(
                townHall: th,
                parsedBuildingsById: parsedBuildingsById,
                buildingNameToId: buildingNameToId,
                currentCountsById: currentWallCounts,
                includeWalls: true
            )

            let labTotals = labCategoryTotals(
                capLabLevel: labCapLevel,
                units: labUnits,
                spells: labSpells,
                currentUnitLevels: currentUnitLevels,
                currentSpellLevels: currentSpellLevels
            )

            let petTotals = petCategoryTotals(
                capPetHouseLevel: petHouseCap,
                pets: pets,
                currentPetLevels: currentPetLevels,
                enabled: th.level >= 14
            )

            let heroTotals = heroCategoryTotals(
                townHallLevel: th.level,
                heroes: heroes,
                currentHeroLevels: currentHeroLevels,
                enabled: th.level >= 7
            )

            var categories: [CategoryProgress] = [
                CategoryProgress(
                    id: "buildings",
                    title: "Buildings",
                    remainingTime: buildingTotals.remainingTime,
                    totalTime: buildingTotals.totalTime,
                    remainingCost: buildingTotals.remainingCost,
                    totalCost: buildingTotals.totalCost
                ),
                CategoryProgress(
                    id: "walls",
                    title: "Walls",
                    remainingTime: wallTotals.remainingTime,
                    totalTime: wallTotals.totalTime,
                    remainingCost: wallTotals.remainingCost,
                    totalCost: wallTotals.totalCost
                )
            ]

            if th.level >= 7 {
                categories.append(
                    CategoryProgress(
                        id: "heroes",
                        title: "Heroes",
                        remainingTime: heroTotals.remainingTime,
                        totalTime: heroTotals.totalTime,
                        remainingCost: heroTotals.remainingCost,
                        totalCost: heroTotals.totalCost
                    )
                )
            }

            if th.level >= 3 {
                categories.append(
                    CategoryProgress(
                        id: "lab",
                        title: "Lab",
                        remainingTime: labTotals.remainingTime,
                        totalTime: labTotals.totalTime,
                        remainingCost: labTotals.remainingCost,
                        totalCost: labTotals.totalCost
                    )
                )
            }

            if th.level >= 14 {
                categories.append(
                    CategoryProgress(
                        id: "pets",
                        title: "Pets",
                        remainingTime: petTotals.remainingTime,
                        totalTime: petTotals.totalTime,
                        remainingCost: petTotals.remainingCost,
                        totalCost: petTotals.totalCost
                    )
                )
            }

            return TownHallProgress(id: th.level, level: th.level, categories: categories)
        }
    }

    private func currentExport() -> CoCExport? {
        guard let raw = currentProfile?.rawJSON, !raw.isEmpty else { return nil }
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CoCExport.self, from: data)
    }

    private func levelsById(from list: [ExportUnit]?) -> [Int: Int] {
        guard let list else { return [:] }
        var output: [Int: Int] = [:]
        for item in list {
            output[item.data] = max(output[item.data] ?? 0, item.lvl)
        }
        return output
    }

    private func levelsById(from list: [ExportSpell]?) -> [Int: Int] {
        guard let list else { return [:] }
        var output: [Int: Int] = [:]
        for item in list {
            output[item.data] = max(output[item.data] ?? 0, item.lvl)
        }
        return output
    }

    private func levelsById(from list: [ExportPet]?) -> [Int: Int] {
        guard let list else { return [:] }
        var output: [Int: Int] = [:]
        for item in list {
            output[item.data] = max(output[item.data] ?? 0, item.lvl)
        }
        return output
    }

    private func levelsById(from list: [ExportHero]?) -> [Int: Int] {
        guard let list else { return [:] }
        var output: [Int: Int] = [:]
        for item in list {
            output[item.data] = max(output[item.data] ?? 0, item.lvl)
        }
        return output
    }

    private func countsByLevel(from list: [Building]?) -> [Int: [Int: Int]] {
        guard let list else { return [:] }
        var output: [Int: [Int: Int]] = [:]
        for item in list {
            guard let level = item.lvl else { continue }
            let count = max(item.cnt ?? 1, 1)
            var levels = output[item.data] ?? [:]
            levels[level, default: 0] += count
            output[item.data] = levels
        }
        return output
    }

    private func buildingCapLevel(_ building: ParsedBuilding, townHall: Int) -> Int? {
        let filtered = building.levels.filter { level in
            guard let required = level.townHallLevel else { return true }
            return required <= townHall
        }
        return filtered.map { $0.level }.max()
    }

    private func buildingCategoryTotals(
        townHall: TownHallLevelCounts,
        parsedBuildingsById: [Int: ParsedBuilding],
        buildingNameToId: [String: Int],
        currentCountsById: [Int: [Int: Int]],
        includeWalls: Bool
    ) -> (remainingTime: TimeInterval, totalTime: TimeInterval, remainingCost: ResourceTotals, totalCost: ResourceTotals) {
        var remainingTime: TimeInterval = 0
        var totalTime: TimeInterval = 0
        var remainingCost = ResourceTotals()
        var totalCost = ResourceTotals()

        for (name, requiredCount) in townHall.counts {
            let lower = name.lowercased()
            let isWall = lower.contains("wall")
            if includeWalls != isWall { continue }
            guard let id = buildingNameToId[lower], let building = parsedBuildingsById[id] else { continue }

            let capLevel = buildingCapLevel(building, townHall: townHall.level) ?? 0
            if capLevel == 0 { continue }

            let countsByLevel = currentCountsById[id] ?? [:]
            let currentTotal = countsByLevel.values.reduce(0, +)
            let missingCount = max(requiredCount - currentTotal, 0)

            func sumFrom(level: Int, count: Int) -> (time: TimeInterval, cost: ResourceTotals) {
                var time: TimeInterval = 0
                var cost = ResourceTotals()
                guard count > 0 else { return (0, cost) }
                if level >= capLevel { return (0, cost) }
                for target in (level + 1)...capLevel {
                    guard let entry = levelMap(building: building)[target] else { continue }
                    let entryTime = TimeInterval(entry.buildTimeSeconds ?? 0)
                    time += entryTime * Double(count)
                    let entryCost = entry.buildCost ?? 0
                    let entryResource = entry.buildResource ?? ""
                    if entryCost > 0, !entryResource.isEmpty {
                        cost.add(resource: entryResource, amount: entryCost * count)
                    }
                }
                return (time, cost)
            }

            for (level, count) in countsByLevel {
                let remain = sumFrom(level: level, count: count)
                remainingTime += remain.time
                remainingCost = remainingCost + remain.cost

                let total = sumFrom(level: 0, count: count)
                totalTime += total.time
                totalCost = totalCost + total.cost
            }

            if missingCount > 0 {
                let remain = sumFrom(level: 0, count: missingCount)
                remainingTime += remain.time
                remainingCost = remainingCost + remain.cost
                totalTime += remain.time
                totalCost = totalCost + remain.cost
            }
        }

        return (remainingTime, totalTime, remainingCost, totalCost)
    }

    private func levelMap(building: ParsedBuilding) -> [Int: ParsedBuildingLevel] {
        var output: [Int: ParsedBuildingLevel] = [:]
        for level in building.levels {
            output[level.level] = level
        }
        return output
    }

    private func labCategoryTotals(
        capLabLevel: Int,
        units: [Int: ParsedUnitData],
        spells: [Int: ParsedUnitData],
        currentUnitLevels: [Int: Int],
        currentSpellLevels: [Int: Int]
    ) -> (remainingTime: TimeInterval, totalTime: TimeInterval, remainingCost: ResourceTotals, totalCost: ResourceTotals) {
        var remainingTime: TimeInterval = 0
        var totalTime: TimeInterval = 0
        var remainingCost = ResourceTotals()
        var totalCost = ResourceTotals()

        func apply(units: [Int: ParsedUnitData], currentLevels: [Int: Int]) {
            for (id, unit) in units {
                let capLevel = unit.maxLevel(forLabLevel: capLabLevel)
                guard capLevel > 0 else { continue }
                let currentLevel = currentLevels[id] ?? 0
                let totals = unitTotals(unit: unit, currentLevel: currentLevel, capLevel: capLevel)
                remainingTime += totals.remainingTime
                totalTime += totals.totalTime
                remainingCost = remainingCost + totals.remainingCost
                totalCost = totalCost + totals.totalCost
            }
        }

        apply(units: units, currentLevels: currentUnitLevels)
        apply(units: spells, currentLevels: currentSpellLevels)

        return (remainingTime, totalTime, remainingCost, totalCost)
    }

    private func petCategoryTotals(
        capPetHouseLevel: Int,
        pets: [Int: ParsedUnitData],
        currentPetLevels: [Int: Int],
        enabled: Bool
    ) -> (remainingTime: TimeInterval, totalTime: TimeInterval, remainingCost: ResourceTotals, totalCost: ResourceTotals) {
        guard enabled, capPetHouseLevel > 0 else {
            return (0, 0, ResourceTotals(), ResourceTotals())
        }
        var remainingTime: TimeInterval = 0
        var totalTime: TimeInterval = 0
        var remainingCost = ResourceTotals()
        var totalCost = ResourceTotals()

        for (id, pet) in pets {
            let capLevel = pet.maxLevel(forLabLevel: capPetHouseLevel)
            guard capLevel > 0 else { continue }
            let currentLevel = currentPetLevels[id] ?? 0
            let totals = unitTotals(unit: pet, currentLevel: currentLevel, capLevel: capLevel)
            remainingTime += totals.remainingTime
            totalTime += totals.totalTime
            remainingCost = remainingCost + totals.remainingCost
            totalCost = totalCost + totals.totalCost
        }

        return (remainingTime, totalTime, remainingCost, totalCost)
    }

    private func heroCategoryTotals(
        townHallLevel: Int,
        heroes: [Int: ParsedUnitData],
        currentHeroLevels: [Int: Int],
        enabled: Bool
    ) -> (remainingTime: TimeInterval, totalTime: TimeInterval, remainingCost: ResourceTotals, totalCost: ResourceTotals) {
        guard enabled, townHallLevel > 0 else {
            return (0, 0, ResourceTotals(), ResourceTotals())
        }
        var remainingTime: TimeInterval = 0
        var totalTime: TimeInterval = 0
        var remainingCost = ResourceTotals()
        var totalCost = ResourceTotals()

        for (id, hero) in heroes {
            let capLevel = hero.maxLevel(forLabLevel: townHallLevel)
            guard capLevel > 0 else { continue }
            let currentLevel = currentHeroLevels[id] ?? 0
            let totals = unitTotals(unit: hero, currentLevel: currentLevel, capLevel: capLevel)
            remainingTime += totals.remainingTime
            totalTime += totals.totalTime
            remainingCost = remainingCost + totals.remainingCost
            totalCost = totalCost + totals.totalCost
        }

        return (remainingTime, totalTime, remainingCost, totalCost)
    }

    private func unitTotals(
        unit: ParsedUnitData,
        currentLevel: Int,
        capLevel: Int
    ) -> (remainingTime: TimeInterval, totalTime: TimeInterval, remainingCost: ResourceTotals, totalCost: ResourceTotals) {
        var remainingTime: TimeInterval = 0
        var totalTime: TimeInterval = 0
        var remainingCost = ResourceTotals()
        var totalCost = ResourceTotals()

        if capLevel <= 1 { return (0, 0, ResourceTotals(), ResourceTotals()) }

        for level in 1..<(capLevel) {
            if let entry = unit.levelsByLevel[level] {
                let entryTime = TimeInterval(entry.upgradeTimeSeconds)
                totalTime += entryTime
                if entry.upgradeCost > 0, !entry.upgradeResource.isEmpty {
                    totalCost.add(resource: entry.upgradeResource, amount: entry.upgradeCost)
                }
                if level >= currentLevel {
                    remainingTime += entryTime
                    if entry.upgradeCost > 0, !entry.upgradeResource.isEmpty {
                        remainingCost.add(resource: entry.upgradeResource, amount: entry.upgradeCost)
                    }
                }
            }
        }

        return (remainingTime, totalTime, remainingCost, totalCost)
    }
}
