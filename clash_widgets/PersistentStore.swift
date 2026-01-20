import Foundation

struct PersistentStore {
    static let appGroupIdentifier = "group.Zachary-Buschmann.clash-widgets"
    private static let directoryName = "ClashDashData"
    private static let fileName = "app_state.json"

    struct AppState: Codable {
        var profiles: [PlayerAccount]
        var selectedProfileID: UUID?
        var appearancePreference: AppearancePreference
        var notificationSettings: NotificationSettings?

        init(
            profiles: [PlayerAccount],
            selectedProfileID: UUID?,
            appearancePreference: AppearancePreference = .device,
            notificationSettings: NotificationSettings? = nil
        ) {
            self.profiles = profiles
            self.selectedProfileID = selectedProfileID
            self.appearancePreference = appearancePreference
            self.notificationSettings = notificationSettings
        }

        private enum CodingKeys: String, CodingKey {
            case profiles
            case selectedProfileID
            case appearancePreference
            case notificationSettings
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.profiles = try container.decode([PlayerAccount].self, forKey: .profiles)
            self.selectedProfileID = try container.decodeIfPresent(UUID.self, forKey: .selectedProfileID)
            self.appearancePreference = try container.decodeIfPresent(AppearancePreference.self, forKey: .appearancePreference) ?? .device
            self.notificationSettings = try container.decodeIfPresent(NotificationSettings.self, forKey: .notificationSettings)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(profiles, forKey: .profiles)
            try container.encodeIfPresent(selectedProfileID, forKey: .selectedProfileID)
            try container.encode(appearancePreference, forKey: .appearancePreference)
            try container.encodeIfPresent(notificationSettings, forKey: .notificationSettings)
        }

        var currentProfile: PlayerAccount? {
            if let id = selectedProfileID,
               let match = profiles.first(where: { $0.id == id }) {
                return match
            }
            return profiles.first
        }

        var activeUpgrades: [BuildingUpgrade] {
            currentProfile?.activeUpgrades ?? []
        }

        var widgetDisplayName: String {
            if let name = currentProfile?.displayName, !name.isEmpty {
                return name
            }
            if let tag = currentProfile?.tag, !tag.isEmpty {
                return "#\(tag)"
            }
            return "ClashDash"
        }
    }

    static func saveState(_ state: AppState) throws {
        guard let targetURL = stateFileURL() else { throw StorageError.containerUnavailable }
        let directory = targetURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        do {
            try data.write(to: targetURL, options: [.atomic])
        } catch {
            throw StorageError.writeFailed(error)
        }
    }

    static func loadState() -> AppState? {
        guard let url = stateFileURL(), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            if let state = try? decoder.decode(AppState.self, from: data) {
                return state
            }
            if let legacy = try? decoder.decode(LegacyAppState.self, from: data) {
                let profile = PlayerAccount(
                    displayName: legacy.playerTag.isEmpty ? "Profile 1" : legacy.playerTag,
                    tag: legacy.playerTag,
                    rawJSON: legacy.rawJSON,
                    lastImportDate: legacy.lastImportDate,
                    activeUpgrades: legacy.activeUpgrades ?? []
                )
                    return AppState(
                        profiles: [profile],
                        selectedProfileID: profile.id,
                        appearancePreference: .device,
                        notificationSettings: .default
                    )
            }
            return nil
        } catch {
            #if DEBUG
            print("PersistentStore load failed: \(error)")
            #endif
            return nil
        }
    }

    private struct LegacyAppState: Codable {
        var widgetText: String
        var playerTag: String
        var rawJSON: String
        var lastImportDate: Date?
        var activeUpgrades: [BuildingUpgrade]?
    }

    static func clearState() {
        guard let url = stateFileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func stateFileURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }
        return containerURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    enum StorageError: Error {
        case containerUnavailable
        case writeFailed(Error)
    }
}
