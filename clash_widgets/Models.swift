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
    let name: String
    let targetLevel: Int
    let endTime: Date
    let category: UpgradeCategory
    let startTime: Date
    let totalDuration: TimeInterval
    
    init(id: UUID = UUID(), name: String, targetLevel: Int, endTime: Date, category: UpgradeCategory, startTime: Date = Date(), totalDuration: TimeInterval = 0) {
        self.id = id
        self.name = name
        self.targetLevel = targetLevel
        self.endTime = endTime
        self.category = category
        self.startTime = startTime
        self.totalDuration = totalDuration
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, targetLevel, endTime, category, startTime, totalDuration
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.targetLevel = try container.decode(Int.self, forKey: .targetLevel)
        self.endTime = try container.decode(Date.self, forKey: .endTime)
        self.category = try container.decodeIfPresent(UpgradeCategory.self, forKey: .category) ?? .builderVillage
        self.startTime = try container.decodeIfPresent(Date.self, forKey: .startTime) ?? Date()
        self.totalDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .totalDuration) ?? max(0, endTime.timeIntervalSince(Date()))
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(targetLevel, forKey: .targetLevel)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(category, forKey: .category)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(totalDuration, forKey: .totalDuration)
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

struct Building: Codable {
    let data: Int // dataId from mapping.json
    let lvl: Int
    let timer: Int? // Presence of timer = active upgrade
    let cnt: Int?
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
