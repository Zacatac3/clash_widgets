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
    var builderCount: Int
    var builderApprenticeLevel: Int
    var labAssistantLevel: Int
    var alchemistLevel: Int
    var goldPassBoostPercent: Int

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
        builderCount: Int = 5,
        builderApprenticeLevel: Int = 0,
        labAssistantLevel: Int = 0,
        alchemistLevel: Int = 0,
        goldPassBoostPercent: Int = 10
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
        self.builderCount = builderCount
        self.builderApprenticeLevel = builderApprenticeLevel
        self.labAssistantLevel = labAssistantLevel
        self.alchemistLevel = alchemistLevel
        self.goldPassBoostPercent = goldPassBoostPercent
    }
}

extension PlayerAccount {
    static func == (lhs: PlayerAccount, rhs: PlayerAccount) -> Bool {
        lhs.id == rhs.id
    }
}
