import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

enum AppearancePreference: String, Codable, CaseIterable, Identifiable {
    case device
    case dark
    case light

    static let storageKey = "appearance_preference"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = (try? container.decode(String.self)) ?? "device"
        if value == "navy" {
            self = .device
        } else {
            self = AppearancePreference(rawValue: value) ?? .device
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

#if canImport(SwiftUI)
extension AppearancePreference {
    /// Returns the color scheme override SwiftUI should apply for the current preference.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .device:
            return nil
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }
}
#endif

enum UpgradeCategory: String, Codable {
    case builderVillage
    case lab
    case pets
    case builderBase
}

struct NotificationSettings: Codable, Equatable {
    var notificationsEnabled: Bool = false
    var builderNotificationsEnabled: Bool = true
    var labNotificationsEnabled: Bool = true
    var petNotificationsEnabled: Bool = true
    var builderBaseNotificationsEnabled: Bool = true

    static var `default`: NotificationSettings { NotificationSettings() }

    func allows(category: UpgradeCategory) -> Bool {
        switch category {
        case .builderVillage:
            return builderNotificationsEnabled
        case .lab:
            return labNotificationsEnabled
        case .pets:
            return petNotificationsEnabled
        case .builderBase:
            return builderBaseNotificationsEnabled
        }
    }
}

// Combined model for UI
struct BuildingUpgrade: Identifiable, Codable {
    let id: UUID
    let dataId: Int?
    let name: String
    let targetLevel: Int
    let superchargeLevel: Int?
    let superchargeTargetLevel: Int?
    let endTime: Date
    let category: UpgradeCategory
    let startTime: Date
    let totalDuration: TimeInterval
    
    init(id: UUID = UUID(), dataId: Int? = nil, name: String, targetLevel: Int, superchargeLevel: Int? = nil, superchargeTargetLevel: Int? = nil, endTime: Date, category: UpgradeCategory, startTime: Date = Date(), totalDuration: TimeInterval = 0) {
        self.id = id
        self.dataId = dataId
        self.name = name
        self.targetLevel = targetLevel
        self.superchargeLevel = superchargeLevel
        self.superchargeTargetLevel = superchargeTargetLevel
        self.endTime = endTime
        self.category = category
        self.startTime = startTime
        self.totalDuration = totalDuration
    }

    private enum CodingKeys: String, CodingKey {
        case id, dataId, name, targetLevel, superchargeLevel, superchargeTargetLevel, endTime, category, startTime, totalDuration
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.dataId = try container.decodeIfPresent(Int.self, forKey: .dataId)
        self.name = try container.decode(String.self, forKey: .name)
        self.targetLevel = try container.decode(Int.self, forKey: .targetLevel)
        self.superchargeLevel = try container.decodeIfPresent(Int.self, forKey: .superchargeLevel)
        self.superchargeTargetLevel = try container.decodeIfPresent(Int.self, forKey: .superchargeTargetLevel)
        self.endTime = try container.decode(Date.self, forKey: .endTime)
        self.category = try container.decodeIfPresent(UpgradeCategory.self, forKey: .category) ?? .builderVillage
        self.startTime = try container.decodeIfPresent(Date.self, forKey: .startTime) ?? Date()
        self.totalDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .totalDuration) ?? max(0, endTime.timeIntervalSince(Date()))
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(dataId, forKey: .dataId)
        try container.encode(name, forKey: .name)
        try container.encode(targetLevel, forKey: .targetLevel)
        try container.encodeIfPresent(superchargeLevel, forKey: .superchargeLevel)
        try container.encodeIfPresent(superchargeTargetLevel, forKey: .superchargeTargetLevel)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(category, forKey: .category)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(totalDuration, forKey: .totalDuration)
    }

    var levelDisplayText: String {
        if let target = superchargeTargetLevel {
            let current = superchargeLevel ?? max(target - 1, 0)
            return "SC \(current) → \(target)"
        }
        return "Lv \(targetLevel - 1) → \(targetLevel)"
    }

    var showsSuperchargeIcon: Bool {
        superchargeTargetLevel != nil
    }
    
    var timeRemaining: String {
        let remaining = endTime.timeIntervalSinceNow
        if remaining <= 0 { return "Complete" }
        
        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            let seconds = (Int(remaining) % 60)
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            let seconds = max(Int(remaining.rounded()), 0)
            return "\(seconds)s"
        }
    }

    func timeRemaining(referenceDate: Date) -> String {
        let remaining = endTime.timeIntervalSince(referenceDate)
        if remaining <= 0 { return "Complete" }

        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            let seconds = (Int(remaining) % 60)
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            let seconds = max(Int(remaining.rounded()), 0)
            return "\(seconds)s"
        }
    }
}

// Deep JSON Export Models
struct CoCExport: Codable {
    let tag: String?
    let timestamp: Int
    let helpers: [ExportHelper]?
    let guardians: [ExportGuardian]?
    let buildings: [Building]?
    let buildings2: [Building]? 
    let traps: [Trap]?
    let traps2: [Trap]?
    let heroes: [ExportHero]?
    let heroes2: [ExportHero]?
    let pets: [ExportPet]?
    let units: [ExportUnit]?
    let units2: [ExportUnit]?
    let spells: [ExportSpell]?
}

struct ExportGuardian: Codable {
    let data: Int
    let lvl: Int?
    let timer: Int?
}

struct Building: Codable {
    let data: Int // dataId from mapping.json
    let lvl: Int?
    let timer: Int? // Presence of timer = active upgrade
    let cnt: Int?
    let supercharge: Int?
    let types: [BuildingType]?
}

struct BuildingType: Codable {
    let data: Int
    let modules: [BuildingModule]?
}

struct BuildingModule: Codable {
    let data: Int
    let lvl: Int?
    let timer: Int?
}

struct Trap: Codable {
    let data: Int
    let lvl: Int
    let timer: Int?
    let cnt: Int?
}

struct ExportHero: Codable {
    let data: Int
    let lvl: Int
    let timer: Int?
}

struct ExportPet: Codable {
    let data: Int
    let lvl: Int
    let timer: Int?
}

struct ExportUnit: Codable {
    let data: Int
    let lvl: Int
    let timer: Int?
}

struct ExportSpell: Codable {
    let data: Int
    let lvl: Int
    let timer: Int?
}

struct ExportHelper: Codable {
    let data: Int
    let lvl: Int
    let helperCooldown: Int?

    private enum CodingKeys: String, CodingKey {
        case data
        case lvl
        case helperCooldown = "helper_cooldown"
    }
}

struct HelperCooldownEntry: Identifiable, Codable {
    let id: Int
    let level: Int
    let cooldownSeconds: Int
}

struct ParsedBuildingLevel: Codable {
    let level: Int
    let buildTimeSeconds: Int?
    let buildResource: String?
    let buildCost: Int?
    let townHallLevel: Int?
}

struct ParsedBuilding: Codable {
    let id: Int
    let internalName: String
    let levels: [ParsedBuildingLevel]
}

struct ParsedMiniLevel: Codable {
    let internalName: String
    let levels: [ParsedMiniLevelLevel]
}

struct ParsedMiniLevelLevel: Codable {
    let level: Int
    let buildTimeSeconds: Int?
}

struct RemainingBuildingUpgrade: Identifiable {
    let id: Int
    let name: String
    let currentLevel: Int
    let targetLevel: Int
    let buildTimeSeconds: Int
    let buildResource: String
    let buildCost: Int
}

struct ResourceTotals: Codable {
    var gold: Int = 0
    var elixir: Int = 0
    var darkElixir: Int = 0

    mutating func add(resource: String, amount: Int) {
        let key = resource.lowercased()
        if key.contains("dark") {
            darkElixir += amount
        } else if key.contains("elixir") {
            elixir += amount
        } else if key.contains("gold") {
            gold += amount
        }
    }

    static func + (lhs: ResourceTotals, rhs: ResourceTotals) -> ResourceTotals {
        var total = ResourceTotals()
        total.gold = lhs.gold + rhs.gold
        total.elixir = lhs.elixir + rhs.elixir
        total.darkElixir = lhs.darkElixir + rhs.darkElixir
        return total
    }

    var totalValue: Int {
        gold + elixir + darkElixir
    }
}

struct CategoryProgress: Identifiable {
    let id: String
    let title: String
    let remainingTime: TimeInterval
    let totalTime: TimeInterval
    let remainingCost: ResourceTotals
    let totalCost: ResourceTotals

    var completion: Double {
        if id == "walls" {
            let total = Double(max(totalCost.totalValue, 1))
            return max(0, min(1, 1 - (Double(remainingCost.totalValue) / total)))
        }
        guard totalTime > 0 else { return 1 }
        return max(0, min(1, 1 - (remainingTime / totalTime)))
    }
}

struct TownHallProgress: Identifiable {
    let id: Int
    let level: Int
    let categories: [CategoryProgress]

    var overallCompletion: Double {
        guard !categories.isEmpty else { return 0 }
        var weightedSum: Double = 0
        var weightTotal: Double = 0
        for category in categories {
            let weight = Double(max(category.totalCost.totalValue, 1))
            weightedSum += category.completion * weight
            weightTotal += weight
        }
        guard weightTotal > 0 else { return 0 }
        return weightedSum / weightTotal
    }

    var remainingCosts: ResourceTotals {
        categories.reduce(ResourceTotals()) { $0 + $1.remainingCost }
    }

    var remainingTime: TimeInterval {
        categories.map { $0.remainingTime }.reduce(0, +)
    }
}

struct TownHallLevelCounts: Codable {
    let level: Int
    let counts: [String: Int]
}

struct ParsedUnitLevelData {
    let level: Int
    let upgradeTimeSeconds: Int
    let upgradeCost: Int
    let upgradeResource: String
    let laboratoryLevel: Int
}

struct ParsedUnitData {
    let id: Int
    let name: String
    let levels: [ParsedUnitLevelData]

    var levelsByLevel: [Int: ParsedUnitLevelData] {
        var output: [Int: ParsedUnitLevelData] = [:]
        for level in levels {
            output[level.level] = level
        }
        return output
    }

    func maxLevel(forLabLevel labLevel: Int) -> Int {
        levels.filter { $0.laboratoryLevel <= labLevel && $0.level > 0 }
            .map { $0.level }
            .max() ?? 0
    }
}

// Official API Response Models
struct PlayerProfile: Codable {
    let tag: String
    let name: String
    let townHallLevel: Int
    let townHallWeaponLevel: Int?
    let expLevel: Int
    let trophies: Int
    let bestTrophies: Int
    let warStars: Int?
    let attackWins: Int?
    let defenseWins: Int?
    let builderHallLevel: Int?
    let builderBaseTrophies: Int?
    let bestBuilderBaseTrophies: Int?
    let donations: Int?
    let donationsReceived: Int?
    let clanCapitalContributions: Int?
    let clan: Clan?
    let leagueTier: LeagueTier?
    let builderBaseLeague: LeagueTier?
    let achievements: [PlayerAchievement]?
    let labels: [PlayerLabel]?
    let heroes: [HeroProfile]?
    let troops: [TroopProfile]?
    let spells: [SpellProfile]?
    let heroEquipment: [HeroEquipment]?
    let playerHouse: PlayerHouse?
}

struct Clan: Codable {
    let tag: String
    let name: String
    let clanLevel: Int
    let badgeUrls: BadgeUrls
}

struct LeagueTier: Codable {
    let id: Int
    let name: String
    let iconUrls: IconUrls?
}

struct IconUrls: Codable {
    let small: String?
    let medium: String?
    let large: String?
}

struct BadgeUrls: Codable {
    let small: String
    let medium: String
    let large: String
}

struct HeroProfile: Codable {
    let name: String
    let level: Int
    let maxLevel: Int
    let village: String
    let equipment: [HeroEquipment]?
}

struct TroopProfile: Codable {
    let name: String
    let level: Int
    let maxLevel: Int
    let village: String
}

struct SpellProfile: Codable {
    let name: String
    let level: Int
    let maxLevel: Int
    let village: String
}

struct HeroEquipment: Codable {
    let name: String
    let level: Int
    let maxLevel: Int
    let village: String
}

struct PlayerLabel: Codable, Identifiable {
    let id: Int
    let name: String
    let iconUrls: IconUrls?
}

struct PlayerAchievement: Codable, Identifiable {
    var id: String { name }
    let name: String
    let stars: Int
    let value: Int
    let target: Int
    let info: String
    let completionInfo: String?
    let village: String
}

struct PlayerHouse: Codable {
    let elements: [HouseElement]?
}

struct HouseElement: Codable, Identifiable {
    var id: Int { elementID }
    let type: String
    private let elementID: Int

    enum CodingKeys: String, CodingKey {
        case type
        case elementID = "id"
    }
}
