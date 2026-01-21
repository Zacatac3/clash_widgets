import Foundation

struct PlayerAccount: Identifiable, Codable, Equatable {
    var id: UUID
    var displayName: String
    var tag: String
    var rawJSON: String
    var lastImportDate: Date?
    var activeUpgrades: [BuildingUpgrade]
    var cachedProfile: PlayerProfile?
    var apiProfileJSON: String
    var lastAPIFetchDate: Date?
    var notificationSettings: NotificationSettings
    var builderCount: Int
    var builderApprenticeLevel: Int
    var labAssistantLevel: Int
    var alchemistLevel: Int
    var goldPassBoost: Int
    var goldPassReminderEnabled: Bool

    init(
        id: UUID = UUID(),
        displayName: String = "New Profile",
        tag: String = "",
        rawJSON: String = "",
        lastImportDate: Date? = nil,
        activeUpgrades: [BuildingUpgrade] = [],
        cachedProfile: PlayerProfile? = nil,
        apiProfileJSON: String = "",
        lastAPIFetchDate: Date? = nil,
        notificationSettings: NotificationSettings = .default,
        builderCount: Int = 5,
        builderApprenticeLevel: Int = 0,
        labAssistantLevel: Int = 0,
        alchemistLevel: Int = 0,
        goldPassBoost: Int = 0,
        goldPassReminderEnabled: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.tag = tag
        self.rawJSON = rawJSON
        self.lastImportDate = lastImportDate
        self.activeUpgrades = activeUpgrades
        self.cachedProfile = cachedProfile
        self.apiProfileJSON = apiProfileJSON
        self.lastAPIFetchDate = lastAPIFetchDate
        self.notificationSettings = notificationSettings
        self.builderCount = builderCount
        self.builderApprenticeLevel = builderApprenticeLevel
        self.labAssistantLevel = labAssistantLevel
        self.alchemistLevel = alchemistLevel
        self.goldPassBoost = goldPassBoost
        self.goldPassReminderEnabled = goldPassReminderEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case tag
        case rawJSON
        case lastImportDate
        case activeUpgrades
        case cachedProfile
        case apiProfileJSON
        case lastAPIFetchDate
        case notificationSettings
        case builderCount
        case builderApprenticeLevel
        case labAssistantLevel
        case alchemistLevel
        case goldPassBoost
        case goldPassReminderEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? "New Profile"
        self.tag = try container.decodeIfPresent(String.self, forKey: .tag) ?? ""
        self.rawJSON = try container.decodeIfPresent(String.self, forKey: .rawJSON) ?? ""
        self.lastImportDate = try container.decodeIfPresent(Date.self, forKey: .lastImportDate)
        self.activeUpgrades = try container.decodeIfPresent([BuildingUpgrade].self, forKey: .activeUpgrades) ?? []
        self.cachedProfile = try container.decodeIfPresent(PlayerProfile.self, forKey: .cachedProfile)
        self.apiProfileJSON = try container.decodeIfPresent(String.self, forKey: .apiProfileJSON) ?? ""
        self.lastAPIFetchDate = try container.decodeIfPresent(Date.self, forKey: .lastAPIFetchDate)
        self.notificationSettings = try container.decodeIfPresent(NotificationSettings.self, forKey: .notificationSettings) ?? .default
        self.builderCount = try container.decodeIfPresent(Int.self, forKey: .builderCount) ?? 5
        self.builderApprenticeLevel = try container.decodeIfPresent(Int.self, forKey: .builderApprenticeLevel) ?? 0
        self.labAssistantLevel = try container.decodeIfPresent(Int.self, forKey: .labAssistantLevel) ?? 0
        self.alchemistLevel = try container.decodeIfPresent(Int.self, forKey: .alchemistLevel) ?? 0
        self.goldPassBoost = try container.decodeIfPresent(Int.self, forKey: .goldPassBoost) ?? 0
        self.goldPassReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .goldPassReminderEnabled) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(tag, forKey: .tag)
        try container.encode(rawJSON, forKey: .rawJSON)
        try container.encodeIfPresent(lastImportDate, forKey: .lastImportDate)
        try container.encode(activeUpgrades, forKey: .activeUpgrades)
        try container.encodeIfPresent(cachedProfile, forKey: .cachedProfile)
        try container.encode(apiProfileJSON, forKey: .apiProfileJSON)
        try container.encodeIfPresent(lastAPIFetchDate, forKey: .lastAPIFetchDate)
        try container.encode(notificationSettings, forKey: .notificationSettings)
        try container.encode(builderCount, forKey: .builderCount)
        try container.encode(builderApprenticeLevel, forKey: .builderApprenticeLevel)
        try container.encode(labAssistantLevel, forKey: .labAssistantLevel)
        try container.encode(alchemistLevel, forKey: .alchemistLevel)
        try container.encode(goldPassBoost, forKey: .goldPassBoost)
        try container.encode(goldPassReminderEnabled, forKey: .goldPassReminderEnabled)
    }
}

extension PlayerAccount {
    static func == (lhs: PlayerAccount, rhs: PlayerAccount) -> Bool {
        lhs.id == rhs.id
    }
}
