import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - Boost Models

enum BoostType: String, Codable, CaseIterable, Identifiable {
    case builderPotion = "builder_potion"
    case researchPotion = "research_potion"
    case petPotion = "pet_potion"
    case labAssistant = "lab_assistant"
    case builderApprentice = "builder_apprentice"
    case builderBite = "builder_bite"
    case studySoup = "study_soup"
    case clockTowerPotion = "clock_tower_potion"
    case clockTower = "clock_tower"
    
    var id: String { rawValue }
    
    var requiresTargetSelection: Bool {
        self == .builderApprentice
    }
    
    var requiresClockTowerLevel: Bool {
        self == .clockTower
    }
    
    var displayName: String {
        switch self {
        case .builderPotion: return "Builder Potion"
        case .researchPotion: return "Research Potion"
        case .petPotion: return "Pet Potion"
        case .labAssistant: return "Lab Assistant"
        case .builderApprentice: return "Builder's Apprentice"
        case .builderBite: return "Builder Bite"
        case .studySoup: return "Study Soup"
        case .clockTowerPotion: return "Clock Tower Potion"
        case .clockTower: return "Clock Tower"
        }
    }
    
    var assetPath: String {
        switch self {
        case .builderPotion: return "extras/builder_potion"
        case .researchPotion: return "extras/research_potion"
        case .petPotion: return "extras/pet_potion"
        case .labAssistant: return "profile/lab_assistant"
        case .builderApprentice: return "profile/apprentice_builder"
        case .builderBite: return "extras/Builder_Bite"
        case .studySoup: return "extras/Study_Soup"
        case .clockTowerPotion: return "extras/clock_tower_potion"
        case .clockTower: return "builder_base/clock_tower"
        }
    }
    
    var isPlaceholder: Bool {
        return false
    }
    
    // Boost multipliers (as percentages: 10x = +900%, 2x = +100%)
    // For level-based boosts, this returns 0 and the actual multiplier is calculated from profile level
    func speedMultiplier(level: Int = 0) -> Double {
        switch self {
        case .builderPotion: return 9.0  // +900% = 10x
        case .researchPotion: return 23.0  // +2300% = 24x
        case .petPotion: return 23.0  // +2300% = 24x
        case .builderBite: return 1.0  // +100% = 2x
        case .studySoup: return 3.0  // +300% = 4x
        case .labAssistant, .builderApprentice:
            // Level-based: level 8 = 9x multiplier = 8x boost (level + 1)
            return Double(level)  // This is the boost percentage (level 8 = +800%)
        case .clockTowerPotion, .clockTower:
            return 9.0  // +900% = 10x speed
        }
    }
    
    func durationSeconds(clockTowerLevel: Int = 0) -> TimeInterval {
        switch self {
        case .builderPotion, .researchPotion, .petPotion, .builderBite, .studySoup, .labAssistant, .builderApprentice:
            return 3600  // 1 hour
        case .clockTowerPotion:
            return 1800  // 30 minutes
        case .clockTower:
            // 14 minutes at level 1, +2 minutes per level (level 1 = 14, level 10 = 32)
            let minutes = max(1, clockTowerLevel)
            return TimeInterval((14 + (minutes - 1) * 2) * 60)
        }
    }
    
    // Which upgrade categories this boost affects
    var affectedCategories: Set<UpgradeCategory> {
        switch self {
        case .builderPotion, .builderBite, .builderApprentice:
            return [.builderVillage]
        case .researchPotion, .labAssistant:
            return [.lab]
        case .petPotion:
            return [.pets]
        case .studySoup:
            return [.lab, .pets]
        case .clockTowerPotion, .clockTower:
            return [.builderBase]
        }
    }
    
    // Clock tower boosts don't stack with each other, they extend duration instead
    var isClockTowerBoost: Bool {
        self == .clockTower || self == .clockTowerPotion
    }
}

struct ActiveBoost: Codable, Equatable, Identifiable {
    var id: UUID
    var type: String
    var startTime: Date
    var endTime: Date
    var targetUpgradeId: UUID?  // For builder's apprentice - which upgrade this boost applies to
    var helperLevel: Int?  // For level-based boosts (lab assistant, builder's apprentice)
    
    init(id: UUID = UUID(), type: String, startTime: Date, endTime: Date, targetUpgradeId: UUID? = nil, helperLevel: Int? = nil) {
        self.id = id
        self.type = type
        self.startTime = startTime
        self.endTime = endTime
        self.targetUpgradeId = targetUpgradeId
        self.helperLevel = helperLevel
    }
    
    var boostType: BoostType? {
        BoostType(rawValue: type)
    }
}

struct InstantBoostEndTimeSnapshot: Codable {
    let upgradeID: UUID
    let previousEndTime: Date
}

struct InstantBoostUndoAction: Codable, Identifiable {
    var id: UUID
    var type: String
    var appliedAt: Date
    var expiresAt: Date
    var endTimeSnapshots: [InstantBoostEndTimeSnapshot]
    var removedUpgrades: [BuildingUpgrade]

    init(
        id: UUID = UUID(),
        type: String,
        appliedAt: Date,
        expiresAt: Date,
        endTimeSnapshots: [InstantBoostEndTimeSnapshot],
        removedUpgrades: [BuildingUpgrade]
    ) {
        self.id = id
        self.type = type
        self.appliedAt = appliedAt
        self.expiresAt = expiresAt
        self.endTimeSnapshots = endTimeSnapshots
        self.removedUpgrades = removedUpgrades
    }

    var boostType: BoostType? {
        BoostType(rawValue: type)
    }
}

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
    case starLab
    case pets
    case builderBase
}

struct NotificationSettings: Codable, Equatable {
    var notificationsEnabled: Bool = false
    var builderNotificationsEnabled: Bool = true
    var labNotificationsEnabled: Bool = true
    var petNotificationsEnabled: Bool = true
    var builderBaseNotificationsEnabled: Bool = true
    // Helper specific notifications (helpers ready to work)
    var helperNotificationsEnabled: Bool = true
    // Clan war notifications (1 hour before prep ends and 1 hour before battle ends)
    var clanWarNotificationsEnabled: Bool = false
    // Global notification settings (not profile-specific)
    var autoOpenClashOfClansEnabled: Bool = false
    var notificationOffsetMinutes: Int = 0

    static var `default`: NotificationSettings { 
        var settings = NotificationSettings()
        // When creating default settings (e.g., new profile or enabling notifications),
        // all notifications should be ON by default except clan war
        settings.notificationsEnabled = true
        settings.builderNotificationsEnabled = true
        settings.labNotificationsEnabled = true
        settings.petNotificationsEnabled = true
        settings.builderBaseNotificationsEnabled = true
        settings.helperNotificationsEnabled = true
        settings.clanWarNotificationsEnabled = false
        return settings
    }

    func allows(category: UpgradeCategory) -> Bool {
        switch category {
        case .builderVillage:
            return builderNotificationsEnabled
        case .lab:
            return labNotificationsEnabled
        case .starLab:
            return builderBaseNotificationsEnabled
        case .pets:
            return petNotificationsEnabled
        case .builderBase:
            return builderBaseNotificationsEnabled
        }
    }
}

internal enum MainTab: Hashable {
    case onboarding
    case dashboard
    case profile
    case equipment
    case progress
    case palette
    case assetsCatalog
    case settings
}

enum AdsPreference: String, CaseIterable, Identifiable {
    case fullScreen
    case banner

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fullScreen:
            return "Full Screen"
        case .banner:
            return "Banner"
        }
    }
}

internal enum InfoSheetPage: String, CaseIterable, Identifiable {
    case welcome = "Welcome"
    case whatsNew = "What’s New"
    case news = "News"
    var id: String { rawValue }
}

internal struct ProfileSetupSubmission {
    let tag: String
    let builderCount: Int
    let builderApprenticeLevel: Int
    let labAssistantLevel: Int
    let alchemistLevel: Int
    let goldPassBoost: Int
    let rawJSON: String?
    let notificationSettings: NotificationSettings
}

internal struct WhatsNewItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

internal struct WhatsNewSection: Identifiable {
    let id = UUID()
    let dateLabel: String
    let bullets: [String]
}

// MARK: - Helper Gem Cost Data Structures
struct HelperData: Codable {
    let internalName: String
    let levels: [HelperLevel]
}

struct HelperLevel: Codable {
    let level: Int
    let RequiredTownHallLevel: String
    let Cost: String
}

struct HelperLevelInfo {
    let level: Int
    let cost: Int
    let requiredTH: Int
}

struct HelperGemCostInfo: Identifiable {
    let id: String
    let displayName: String
    let category: String
    let iconName: String
    let currentLevel: Int
    let maxLevel: Int
    let isUnlocked: Bool
    let remainingLevels: Int
    let remainingLevelCosts: [HelperLevelInfo]
    let remainingTotalCost: Int
}

struct HelperGemInfo {
    let id: String
    let displayName: String
    let iconName: String
    let levels: [HelperLevelInfo]
    let totalCost: Int
}

// MARK: - Hero Models

struct HeroJSON: Codable {
    let internalName: String
    let levels: [HeroLevelJSON]
}

struct HeroLevelJSON: Codable {
    let level: Int
    let RequiredHeroTavernLevel: String
    let RequiredTownHallLevel: String
}

struct HeroMapping: Codable {
    let id: Int
    let internalName: String
    let displayName: String
}

/// Remote-configurable hero metadata. Lives in json/heroes_config.json.
/// Adding a new entry here is sufficient to surface a new hero in the heroes tab —
/// no app code changes required, as long as assets follow the same naming convention.
struct HeroConfig: Codable {
    let id: Int
    let displayName: String
    let internalName: String
    let unlockTownHall: Int
    /// Asset catalog path, e.g. "heroes/Barbarian_King". Required because asset
    /// naming is not fully consistent (some titles use TitleCase, others lowercase).
    let assetName: String?
}

enum AchievementFilter: String, CaseIterable, Identifiable {
    case all
    case incomplete
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .incomplete: return "Incomplete"
        case .completed: return "Completed"
        }
    }

    func shouldInclude(isComplete: Bool) -> Bool {
        switch self {
        case .all:
            return true
        case .completed:
            return isComplete
        case .incomplete:
            return !isComplete
        }
    }
}

enum EquipmentRarity: String {
    case common
    case epic

    var label: String { rawValue.capitalized }

    static func from(maxLevel: Int) -> EquipmentRarity {
        if maxLevel >= 27 {
            return .epic
        }
        return .common
    }

    var maxLevel: Int {
        switch self {
        case .common:
            return 18
        case .epic:
            return 27
        }
    }

    var sortRank: Int {
        switch self {
        case .common:
            return 0
        case .epic:
            return 1
        }
    }
}

enum EquipmentRarityFilter: String, CaseIterable, Identifiable {
    case all
    case common
    case epic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "All"
        case .common:
            return "Common"
        case .epic:
            return "Epic"
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
    var endTime: Date  // Mutable to allow boost adjustments
    var appliedRemoteEventIDs: Set<String> = []
    var goldPassFactorAtImport: Double?
    var remoteEventTimeMultiplier: Double?
    var sourceExportTimer: Int?
    let category: UpgradeCategory
    let startTime: Date
    let totalDuration: TimeInterval
    let isSeasonalDefense: Bool?
    
    let usesGoblin: Bool
    
    init(id: UUID = UUID(), dataId: Int? = nil, name: String, targetLevel: Int, superchargeLevel: Int? = nil, superchargeTargetLevel: Int? = nil, usesGoblin: Bool = false, endTime: Date, category: UpgradeCategory, startTime: Date = Date(), totalDuration: TimeInterval = 0, isSeasonalDefense: Bool? = false) {
        self.id = id
        self.dataId = dataId
        self.name = name
        self.targetLevel = targetLevel
        self.superchargeLevel = superchargeLevel
        self.superchargeTargetLevel = superchargeTargetLevel
        self.usesGoblin = usesGoblin
        self.endTime = endTime
        self.category = category
        self.startTime = startTime
        self.totalDuration = totalDuration
        self.isSeasonalDefense = isSeasonalDefense
    }

    private enum CodingKeys: String, CodingKey {
        case id, dataId, name, targetLevel, superchargeLevel, superchargeTargetLevel, usesGoblin, endTime, category, startTime, totalDuration, isSeasonalDefense, appliedRemoteEventIDs, goldPassFactorAtImport, remoteEventTimeMultiplier, sourceExportTimer
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.dataId = try container.decodeIfPresent(Int.self, forKey: .dataId)
        self.name = try container.decode(String.self, forKey: .name)
        self.targetLevel = try container.decode(Int.self, forKey: .targetLevel)
        self.superchargeLevel = try container.decodeIfPresent(Int.self, forKey: .superchargeLevel)
        self.superchargeTargetLevel = try container.decodeIfPresent(Int.self, forKey: .superchargeTargetLevel)
        self.usesGoblin = try container.decodeIfPresent(Bool.self, forKey: .usesGoblin) ?? false
        self.appliedRemoteEventIDs = try container.decodeIfPresent(Set<String>.self, forKey: .appliedRemoteEventIDs) ?? []
        self.goldPassFactorAtImport = try container.decodeIfPresent(Double.self, forKey: .goldPassFactorAtImport)
        self.remoteEventTimeMultiplier = try container.decodeIfPresent(Double.self, forKey: .remoteEventTimeMultiplier)
        self.sourceExportTimer = try container.decodeIfPresent(Int.self, forKey: .sourceExportTimer)
        self.endTime = try container.decode(Date.self, forKey: .endTime)
        self.category = try container.decodeIfPresent(UpgradeCategory.self, forKey: .category) ?? .builderVillage
        self.startTime = try container.decodeIfPresent(Date.self, forKey: .startTime) ?? Date()
        self.totalDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .totalDuration) ?? max(0, endTime.timeIntervalSince(Date()))
        self.isSeasonalDefense = try container.decodeIfPresent(Bool.self, forKey: .isSeasonalDefense)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(dataId, forKey: .dataId)
        try container.encode(name, forKey: .name)
        try container.encode(targetLevel, forKey: .targetLevel)
        try container.encodeIfPresent(superchargeLevel, forKey: .superchargeLevel)
        try container.encodeIfPresent(superchargeTargetLevel, forKey: .superchargeTargetLevel)
        try container.encode(usesGoblin, forKey: .usesGoblin)
        try container.encode(appliedRemoteEventIDs, forKey: .appliedRemoteEventIDs)
        try container.encodeIfPresent(goldPassFactorAtImport, forKey: .goldPassFactorAtImport)
        try container.encodeIfPresent(remoteEventTimeMultiplier, forKey: .remoteEventTimeMultiplier)
        try container.encodeIfPresent(sourceExportTimer, forKey: .sourceExportTimer)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(category, forKey: .category)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(totalDuration, forKey: .totalDuration)
        try container.encodeIfPresent(isSeasonalDefense, forKey: .isSeasonalDefense)
    }

    func durationBeforeRemoteEvent(goldPassBoost: Int) -> TimeInterval {
        let currentGold = 1 - Double(max(0, min(100, goldPassBoost))) / 100
        let gold = remoteEventTimeMultiplier == nil ? currentGold : (goldPassFactorAtImport ?? currentGold)
        return max(totalDuration * gold, 1)
    }

    func effectiveTotalDuration(goldPassBoost: Int) -> TimeInterval {
        max(durationBeforeRemoteEvent(goldPassBoost: goldPassBoost) * (remoteEventTimeMultiplier ?? 1), 1)
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
struct CoCExport: Decodable {
    let tag: String?
    let timestamp: Int?
    let helpers: [ExportHelper]?
    let guardians: [ExportGuardian]?
    let buildings: [Building]?
    let buildings2: [Building]?
    let traps: [Trap]?
    let traps2: [Trap]?
    let heroes: [ExportHero]?
    let heroes2: [ExportHero]?
    let pets: [ExportPet]?
    let siegeMachines: [ExportSiegeMachine]?
    let units: [ExportUnit]?
    let units2: [ExportUnit]?
    let spells: [ExportSpell]?
    let equipment: [ExportUnit]?

    private enum CodingKeys: String, CodingKey {
        case tag
        case timestamp
        case helpers
        case guardians
        case buildings
        case buildings2
        case traps
        case traps2
        case heroes
        case heroes2
        case pets
        case siegeMachines = "siege_machines"
        case units
        case units2
        case spells
        case equipment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tag = try container.decodeIfPresent(String.self, forKey: .tag)

        if let value = try? container.decodeIfPresent(Int.self, forKey: .timestamp) {
            timestamp = value
        } else if let value = try? container.decodeIfPresent(Double.self, forKey: .timestamp) {
            timestamp = Int(value)
        } else if let value = try? container.decodeIfPresent(String.self, forKey: .timestamp), let intValue = Int(value) {
            timestamp = intValue
        } else {
            timestamp = nil
        }

        helpers = try container.decodeIfPresent([ExportHelper].self, forKey: .helpers)
        guardians = try container.decodeIfPresent([ExportGuardian].self, forKey: .guardians)
        buildings = try container.decodeIfPresent([Building].self, forKey: .buildings)
        buildings2 = try container.decodeIfPresent([Building].self, forKey: .buildings2)
        traps = try container.decodeIfPresent([Trap].self, forKey: .traps)
        traps2 = try container.decodeIfPresent([Trap].self, forKey: .traps2)
        heroes = try container.decodeIfPresent([ExportHero].self, forKey: .heroes)
        heroes2 = try container.decodeIfPresent([ExportHero].self, forKey: .heroes2)
        pets = try container.decodeIfPresent([ExportPet].self, forKey: .pets)
        siegeMachines = try container.decodeIfPresent([ExportSiegeMachine].self, forKey: .siegeMachines)
        units = try container.decodeIfPresent([ExportUnit].self, forKey: .units)
        units2 = try container.decodeIfPresent([ExportUnit].self, forKey: .units2)
        spells = try container.decodeIfPresent([ExportSpell].self, forKey: .spells)
        equipment = try container.decodeIfPresent([ExportUnit].self, forKey: .equipment)
    }

}

struct ExportGuardian: Codable {
    let data: Int
    let lvl: Int?
    let timer: Int?
    let extra: Bool?
}

struct Building: Codable {
    let data: Int // dataId from mapping.json
    let lvl: Int?
    let weapon: Int?
    let timer: Int? // Presence of timer = active upgrade
    let cnt: Int?
    let supercharge: Int?
    let extra: Bool?
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
    let extra: Bool?
}

struct Trap: Codable {
    let data: Int
    let lvl: Int
    let timer: Int?
    let cnt: Int?
    let extra: Bool?
}

struct ExportHero: Codable {
    let data: Int
    let lvl: Int
    let timer: Int?
    let extra: Bool?
}

struct ExportPet: Codable {
    let data: Int
    let lvl: Int
    let timer: Int?
    let extra: Bool?
}

struct ExportSiegeMachine: Codable {
    let data: Int
    let lvl: Int
    let timer: Int?
    let extra: Bool?
}

struct ExportUnit: Codable {
    let data: Int
    let lvl: Int
    let timer: Int?
    let extra: Bool?
}

struct ExportSpell: Codable {
    let data: Int
    let lvl: Int
    let timer: Int?
    let extra: Bool?
}

struct ExportHelper: Decodable {
    let data: Int
    let lvl: Int
    let helperCooldown: Int?

    private enum CodingKeys: String, CodingKey {
        case data
        case lvl
        case helperCooldown = "helper_cooldown"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(Int.self, forKey: .data)
        lvl = try container.decode(Int.self, forKey: .lvl)
        helperCooldown = try container.decodeIfPresent(Int.self, forKey: .helperCooldown)
    }

}

struct HelperCooldownEntry: Identifiable, Codable {
    let id: Int
    let level: Int
    let cooldownSeconds: Int
    let expiresAt: Date?

    func remainingSeconds(referenceDate: Date = Date()) -> Int {
        if let expiresAt = expiresAt {
            return max(0, Int(expiresAt.timeIntervalSince(referenceDate)))
        }
        return max(0, cooldownSeconds)
    }
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

// MARK: - Clan War Models
struct WarDetails: Codable {
    let state: String
    let teamSize: Int
    let attacksPerMember: Int?
    let battleModifier: String?
    let preparationStartTime: String?
    let startTime: String?
    let endTime: String?
    let clan: WarClan?
    let opponent: WarClan?
}

struct WarClan: Codable {
    let tag: String
    let name: String
    let badgeUrls: BadgeUrls
    let clanLevel: Int
    let attacks: Int?
    let stars: Int?
    let destructionPercentage: Double?
    let members: [WarMember]?
}

struct WarMember: Codable {
    let tag: String
    let name: String
    let townhallLevel: Int?
    let mapPosition: Int?
    let attacks: [WarAttack]?
    let opponentAttacks: Int?
    let bestOpponentAttack: WarAttack?
}

struct WarAttack: Codable {
    let attackerTag: String?
    let defenderTag: String?
    let stars: Int?
    let destructionPercentage: Int?
    let order: Int?
    let duration: Int?
}

// MARK: - Clan Stats Models
struct ClanStats: Codable {
    let tag: String
    let name: String
    let type: String?
    let description: String?
    let location: ClanLocation?
    let isFamilyFriendly: Bool?
    let badgeUrls: BadgeUrls
    let clanLevel: Int
    let clanPoints: Int?
    let clanBuilderBasePoints: Int?
    let clanCapitalPoints: Int?
    let clanCapital: ClanCapital?
    let capitalLeague: ClanLeague?
    let requiredTrophies: Int?
    let warFrequency: String?
    let warWinStreak: Int?
    let warWins: Int?
    let warTies: Int?
    let warLosses: Int?
    let warLeague: ClanLeague?
    let members: Int?
}

struct ClanLocation: Codable {
    let id: Int?
    let name: String?
    let isCountry: Bool?
    let countryCode: String?
}

struct ClanLeague: Codable {
    let id: Int?
    let name: String?
}

struct ClanCapital: Codable {
    let capitalHallLevel: Int?
}

// MARK: - Clan War League Models
struct WarLeagueGroup: Codable {
    let state: String?
    let season: String?
    let rounds: [WarLeagueRound]?
}

struct WarLeagueRound: Codable {
    let warTags: [String]?
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

// Edit only the tracked export item, preserving unrelated timers and unknown JSON fields.
extension BuildingUpgrade {
    func updatingExport(_ rawJSON: String, completed: Bool) -> String? {
        guard let dataId, let data = rawJSON.data(using: .utf8),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let keys: [String]
        switch category {
        case .builderVillage: keys = ["buildings", "traps", "heroes", "guardians"]
        case .builderBase: keys = ["buildings2", "traps2", "heroes2"]
        case .lab: keys = ["units", "spells", "siege_machines"]
        case .starLab: keys = ["units2"]
        case .pets: keys = ["pets"]
        }
        func updated(_ item: [String: Any]) -> [String: Any] {
            var result = item
            result.removeValue(forKey: "timer")
            result.removeValue(forKey: "extra")
            if completed {
                if let target = superchargeTargetLevel { result["supercharge"] = target }
                else if name == "Town Hall Weapon" { result["weapon"] = targetLevel }
                else { result["lvl"] = targetLevel }
            }
            return result
        }
        for key in keys {
            guard var items = root[key] as? [[String: Any]] else { continue }
            if isSeasonalDefense == true {
                for i in items.indices {
                    guard var types = items[i]["types"] as? [[String: Any]] else { continue }
                    for t in types.indices where (types[t]["data"] as? Int) == dataId {
                        guard var modules = types[t]["modules"] as? [[String: Any]],
                              let m = modules.firstIndex(where: {
                                  ($0["lvl"] as? Int) == targetLevel - 1 && ($0["timer"] as? Int ?? 0) > 0
                                    && (sourceExportTimer == nil || ($0["timer"] as? Int) == sourceExportTimer)
                              }) else { continue }
                        modules[m] = updated(modules[m])
                        types[t]["modules"] = modules
                        items[i]["types"] = types
                        root[key] = items
                        return Self.serializeExport(root)
                    }
                }
            } else if let i = items.firstIndex(where: {
                ($0["data"] as? Int) == dataId && ($0["timer"] as? Int ?? 0) > 0
                    && (superchargeTargetLevel != nil || ($0[name == "Town Hall Weapon" ? "weapon" : "lvl"] as? Int) == targetLevel - 1)
                    && (sourceExportTimer == nil || ($0["timer"] as? Int) == sourceExportTimer)
                    && (superchargeLevel == nil || ($0["supercharge"] as? Int) == superchargeLevel)
                    && ($0["extra"] as? Bool ?? false) == usesGoblin
            }) {
                let count = items[i]["cnt"] as? Int ?? 1
                if completed && count > 1 && superchargeTargetLevel == nil {
                    var finished = updated(items[i])
                    finished["cnt"] = 1
                    items[i]["cnt"] = count - 1
                    items.append(finished)
                } else { items[i] = updated(items[i]) }
                root[key] = items
                return Self.serializeExport(root)
            }
        }
        return nil
    }

    private static func serializeExport(_ root: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension BuildingUpgrade {
    func remainingSeconds(activeBoosts: [ActiveBoost], referenceDate: Date) -> TimeInterval {
        let baseRemaining = max(0, endTime.timeIntervalSince(referenceDate))

        let start = startTime
        let now = referenceDate
        if now <= start { return baseRemaining }

        // Filter boosts that affect this upgrade's category
        let relevantBoosts = activeBoosts.compactMap { boost -> ActiveBoost? in
            guard let boostType = boost.boostType,
                  boostType.affectedCategories.contains(category) else { return nil }
            if boostType == .builderApprentice || boostType == .labAssistant {
                if let targetId = boost.targetUpgradeId, targetId != id { return nil }
            }
            return boost
        }
        if relevantBoosts.isEmpty { return baseRemaining }

        // Build timeline of boost periods
        var timePoints: [Date] = [start, now]
        for boost in relevantBoosts {
            let s = max(start, boost.startTime)
            let e = min(now, boost.endTime)
            if s < e {
                timePoints.append(s)
                timePoints.append(e)
            }
        }
        let sortedPoints = Array(Set(timePoints)).sorted()
        if sortedPoints.count <= 1 { return baseRemaining }

        // Calculate extra elapsed time from boosts
        var extraElapsed: TimeInterval = 0
        for idx in 0..<(sortedPoints.count - 1) {
            let segmentStart = sortedPoints[idx]
            let segmentEnd = sortedPoints[idx + 1]
            if segmentEnd <= segmentStart { continue }

            var totalExtra: Double = 0
            var clockTowerApplied = false
            for boost in relevantBoosts {
                guard let boostType = boost.boostType else { continue }
                let s = max(start, boost.startTime)
                let e = min(now, boost.endTime)
                if segmentStart < s || segmentStart >= e { continue }

                let level = boost.helperLevel ?? 0
                if boostType.isClockTowerBoost {
                    if !clockTowerApplied {
                        totalExtra += boostType.speedMultiplier(level: level)
                        clockTowerApplied = true
                    }
                } else {
                    totalExtra += boostType.speedMultiplier(level: level)
                }
            }
            extraElapsed += segmentEnd.timeIntervalSince(segmentStart) * totalExtra
        }

        let adjustedRemaining = baseRemaining - extraElapsed
        return max(0, adjustedRemaining)
    }
}

extension BuildingUpgrade {
    func projectedCompletionDate(activeBoosts: [ActiveBoost], referenceDate: Date) -> Date {
        let now = referenceDate
        var remainingWork = remainingSeconds(activeBoosts: activeBoosts, referenceDate: now)

        // With no remaining work or boosts, no further projection is needed.
        guard !activeBoosts.isEmpty, remainingWork > 0 else {
            return now.addingTimeInterval(remainingWork)
        }

        // Filter boosts that affect this upgrade's category
        let relevantBoosts = activeBoosts.compactMap { boost -> ActiveBoost? in
            guard let boostType = boost.boostType,
                  boostType.affectedCategories.contains(category),
                  boost.endTime > now else { return nil }
            // For targeted boosts, only include if it targets this upgrade
            if boostType == .builderApprentice || boostType == .labAssistant {
                if let targetId = boost.targetUpgradeId, targetId != id { return nil }
            }
            return boost
        }.sorted { $0.endTime < $1.endTime }

        if relevantBoosts.isEmpty { return now.addingTimeInterval(remainingWork) }

        // Simulate time passing and calculate when work completes
        var currentTime = now

        // Build timeline of future boost transitions
        var transitions: [Date] = [now]
        for boost in relevantBoosts {
            if boost.startTime > now {
                transitions.append(boost.startTime)
            }
            transitions.append(boost.endTime)
        }
        transitions = Array(Set(transitions)).sorted()

        // Process each time segment
        for idx in 0..<(transitions.count - 1) {
            let segmentStart = transitions[idx]
            let segmentEnd = transitions[idx + 1]

            // Calculate effective speed multiplier for this segment
            var speedMultiplier = 1.0
            var clockTowerApplied = false

            for boost in relevantBoosts {
                guard let boostType = boost.boostType else { continue }
                // Check if this boost is active during this segment
                if boost.startTime <= segmentStart && boost.endTime > segmentStart {
                    let level = boost.helperLevel ?? 0
                    if boostType.isClockTowerBoost {
                        if !clockTowerApplied {
                            speedMultiplier += boostType.speedMultiplier(level: level)
                            clockTowerApplied = true
                        }
                    } else {
                        speedMultiplier += boostType.speedMultiplier(level: level)
                    }
                }
            }

            // How much real time passes in this segment
            let realTime = segmentEnd.timeIntervalSince(segmentStart)
            // How much work gets done (boosted time)
            let workDone = realTime * speedMultiplier

            if workDone >= remainingWork {
                // Upgrade completes during this segment
                let timeNeeded = remainingWork / speedMultiplier
                return segmentStart.addingTimeInterval(timeNeeded)
            }

            remainingWork -= workDone
            currentTime = segmentEnd
        }

        // If we still have work after all boosts expire, add unboosted time
        return currentTime.addingTimeInterval(remainingWork)
    }
}


// Expansion requires half a viewport of upward content travel; collapse remains native.
struct TabBarScrollDirectionTracker {
    private var previousOffset: Double?
    private var upwardDistance: Double = 0

    mutating func reset() {
        previousOffset = nil
        upwardDistance = 0
    }

    mutating func update(offset: Double, viewportHeight: Double) -> Bool? {
        defer { previousOffset = offset }
        guard let previousOffset else { return nil }
        if offset <= 0 { upwardDistance = 0; return true }
        let delta = offset - previousOffset
        guard abs(delta) > 0.1 else { return nil }
        if delta > 0 {
            upwardDistance = 0
            // Release forced expansion immediately, allowing iOS to choose collapse timing.
            return false
        }
        upwardDistance += -delta
        guard upwardDistance >= max(1, viewportHeight) * 0.5 else { return nil }
        upwardDistance = 0
        return true
    }
}
