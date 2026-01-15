import Foundation

enum UpgradeCategory: String, Codable {
    case builderVillage
    case lab
    case pets
    case builderBase
}

// Combined model for UI
struct BuildingUpgrade: Identifiable, Codable {
    let id: UUID
    let name: String
    let targetLevel: Int
    let endTime: Date
    let category: UpgradeCategory
    
    init(id: UUID = UUID(), name: String, targetLevel: Int, endTime: Date, category: UpgradeCategory) {
        self.id = id
        self.name = name
        self.targetLevel = targetLevel
        self.endTime = endTime
        self.category = category
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, targetLevel, endTime, category
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.targetLevel = try container.decode(Int.self, forKey: .targetLevel)
        self.endTime = try container.decode(Date.self, forKey: .endTime)
        self.category = try container.decodeIfPresent(UpgradeCategory.self, forKey: .category) ?? .builderVillage
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(targetLevel, forKey: .targetLevel)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(category, forKey: .category)
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
        } else {
            return "\(minutes)m"
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
    let expLevel: Int
    let trophies: Int
    let bestTrophies: Int
    let clan: Clan?
    let heroes: [HeroProfile]?
    let troops: [TroopProfile]?
    let spells: [SpellProfile]?
}

struct Clan: Codable {
    let tag: String
    let name: String
    let clanLevel: Int
    let badgeUrls: BadgeUrls
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
