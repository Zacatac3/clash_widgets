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

    init(
        id: UUID = UUID(),
        displayName: String = "New Profile",
        tag: String = "",
        rawJSON: String = "",
        lastImportDate: Date? = nil,
        activeUpgrades: [BuildingUpgrade] = [],
        cachedProfile: PlayerProfile? = nil,
        apiProfileJSON: String = "",
        lastAPIFetchDate: Date? = nil
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
    }
}

extension PlayerAccount {
    static func == (lhs: PlayerAccount, rhs: PlayerAccount) -> Bool {
        lhs.id == rhs.id
    }
}
