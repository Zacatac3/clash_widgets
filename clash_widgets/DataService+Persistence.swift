import Foundation
import WidgetKit

extension DataService {
    func saveToStorage(reloadWidgets: Bool = false) {
        ensureProfiles()
        let snapshot = PersistentStore.AppState(
            profiles: profiles,
            selectedProfileID: selectedProfileID,
            appearancePreference: appearancePreference,
            notificationSettings: nil
        )

        persistenceQueue.async {
            do {
                try PersistentStore.saveState(snapshot)
            } catch {
                #if DEBUG
                print("Failed to persist state file: \(error)")
                #endif
            }

            if reloadWidgets {
                DispatchQueue.main.async {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }

        let sharedDefaults = UserDefaults(suiteName: DataService.appGroup)
        guard let current = snapshot.currentProfile else { return }
        sharedDefaults?.set(current.displayName, forKey: "widget_simple_text")
        sharedDefaults?.set(current.tag, forKey: "saved_player_tag")
        sharedDefaults?.set(current.rawJSON, forKey: "saved_raw_json")
        sharedDefaults?.set(current.lastImportDate, forKey: "last_import_date")

        if let encoded = try? JSONEncoder().encode(current.activeUpgrades) {
            sharedDefaults?.set(encoded, forKey: "saved_upgrades")
            sharedDefaults?.synchronize()
            UserDefaults.standard.set(encoded, forKey: "saved_upgrades")
        }
    }

    func loadFromStorage() {
        suppressPersistence = true
        defer {
            suppressPersistence = false
            applyCurrentProfile()
        }

        if let state = PersistentStore.loadState() {
            profiles = state.profiles
            selectedProfileID = state.selectedProfileID
            appearancePreference = state.appearancePreference
            if let legacySettings = state.notificationSettings,
               profiles.allSatisfy({ $0.notificationSettings == .default }) {
                profiles = profiles.map { profile in
                    var updated = profile
                    updated.notificationSettings = legacySettings
                    return updated
                }
            }
        } else {
            let sharedDefaults = UserDefaults(suiteName: DataService.appGroup)
            let storedName = sharedDefaults?.string(forKey: "widget_simple_text") ?? ""
            let tag = sharedDefaults?.string(forKey: "saved_player_tag") ?? ""
            let raw = sharedDefaults?.string(forKey: "saved_raw_json") ?? ""
            let lastDate = sharedDefaults?.object(forKey: "last_import_date") as? Date
            var upgrades: [BuildingUpgrade] = []
            if let data = sharedDefaults?.data(forKey: "saved_upgrades") ?? UserDefaults.standard.data(forKey: "saved_upgrades"),
               let decoded = try? JSONDecoder().decode([BuildingUpgrade].self, from: data) {
                upgrades = decoded
            }
            let profile = PlayerAccount(
                displayName: storedName.isEmpty ? (tag.isEmpty ? "Profile 1" : tag) : storedName,
                tag: tag,
                rawJSON: raw,
                lastImportDate: lastDate,
                activeUpgrades: upgrades
            )
            profiles = [profile]
            selectedProfileID = profile.id
        }

        ensureProfiles()
        if selectedProfileID == nil {
            selectedProfileID = profiles.first?.id
        }
    }

    func applyCurrentProfile() {
        suppressPersistence = true
        defer {
            suppressPersistence = false
            scheduleUpgradeNotifications()
        }

        ensureProfiles()
        guard let profile = currentProfile else { return }

        profileName = profile.displayName
        playerTag = profile.tag
        rawJSON = profile.rawJSON
        lastImportDate = profile.lastImportDate
        activeUpgrades = profile.activeUpgrades
        cachedProfile = profile.cachedProfile
        notificationSettings = profile.notificationSettings
        builderCount = profile.builderCount
        builderApprenticeLevel = profile.builderApprenticeLevel
        labAssistantLevel = profile.labAssistantLevel
        alchemistLevel = profile.alchemistLevel
        clockTowerLevel = profile.clockTowerLevel
        goldPassBoost = profile.goldPassBoost
        hiddenEquipmentNames = profile.hiddenEquipmentNames
        goldPassReminderEnabled = profile.goldPassReminderEnabled
    }

    func persistChanges(reloadWidgets: Bool) {
        guard !suppressPersistence else { return }
        saveToStorage(reloadWidgets: reloadWidgets)
    }

    func ensureProfiles() {
        guard profiles.isEmpty else { return }
        let profile = PlayerAccount()
        profiles = [profile]
        selectedProfileID = profile.id
    }

    func defaultProfileName() -> String {
        let base = "Profile"
        var suffix = profiles.count + 1
        let existing = Set(profiles.map { $0.displayName })
        var candidate = "\(base) \(suffix)"
        while existing.contains(candidate) {
            suffix += 1
            candidate = "\(base) \(suffix)"
        }
        return candidate
    }
}
