import Foundation
import UserNotifications
import SwiftUI
import Combine

final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private static let identifierPrefix = "com.zacharybuschmann.clashdash.upgrade."
    
    // Store settings and profile info for notification generation
    private var currentNotificationSettings: NotificationSettings?
    private var allProfiles: [PlayerAccount]?
    private var currentProfileID: UUID?

    func ensureAuthorization(promptIfNeeded: Bool, completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                guard promptIfNeeded else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async { completion(granted) }
                }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { completion(true) }
            default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
    
    func setProfileContext(allProfiles: [PlayerAccount], currentProfileID: UUID?) {
        self.allProfiles = allProfiles
        self.currentProfileID = currentProfileID
    }
    
    func setNotificationSettings(_ settings: NotificationSettings) {
        self.currentNotificationSettings = settings
    }

    func syncNotifications(for upgrades: [BuildingUpgrade], settings: NotificationSettings) {
        guard settings.notificationsEnabled else {
            removeAllUpgradeNotifications()
            return
        }
        setNotificationSettings(settings)
        
        let filteredUpgrades = upgrades.filter { settings.allows(category: $0.category) && $0.endTime > Date() }
        syncNotifications(for: filteredUpgrades)
    }

    func syncNotifications(for upgrades: [BuildingUpgrade]) {
        guard !upgrades.isEmpty else {
            removeAllUpgradeNotifications()
            return
        }

        ensureAuthorization(promptIfNeeded: false) { granted in
            guard granted else {
                self.removeAllUpgradeNotifications()
                return
            }

            let desiredRequests = upgrades.map { self.makeRequest(for: $0) }
            self.center.getPendingNotificationRequests { existing in
                let managed = existing.filter { $0.identifier.hasPrefix(Self.identifierPrefix) }
                let managedIdentifiers = Set(managed.map { $0.identifier })
                let desiredIdentifiers = Set(desiredRequests.map { $0.identifier })

                let identifiersToRemove = Array(managedIdentifiers.subtracting(desiredIdentifiers))
                if !identifiersToRemove.isEmpty {
                    self.center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
                }

                let existingSet = managedIdentifiers
                let newRequests = desiredRequests.filter { !existingSet.contains($0.identifier) }
                for request in newRequests {
                    self.center.add(request)
                }
            }
        }
    }

    func scheduleDebugNotification() {
        ensureAuthorization(promptIfNeeded: true) { granted in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Test Notification"
            content.body = "If you see this, upgrade alerts are working."
            content.sound = .default
            content.threadIdentifier = "debug"

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let identifier = Self.identifierPrefix + "debug." + UUID().uuidString
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            self.center.add(request)
        }
    }

    func removeAllUpgradeNotifications() {
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .filter { $0.identifier.hasPrefix(Self.identifierPrefix) }
                .map { $0.identifier }
            guard !identifiers.isEmpty else { return }
            self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    private func makeRequest(for upgrade: BuildingUpgrade) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Upgrade Complete"
        
        var bodyText = "\(upgrade.name) finished upgrading to level \(upgrade.targetLevel)."
        
        // Add profile name if multiple profiles exist - format: "Username: upgrade x completed"
        if let profiles = allProfiles, profiles.count > 1, let profileID = currentProfileID,
           let profile = profiles.first(where: { $0.id == profileID }) {
            let profileName = profile.displayName.isEmpty ? "#\(profile.tag)" : profile.displayName
            bodyText = "\(profileName): \(upgrade.name) finished upgrading to level \(upgrade.targetLevel)."
        }
        
        content.body = bodyText
        content.sound = .default
        content.threadIdentifier = Self.threadIdentifier(for: upgrade.category)
        
        // Store profile ID for handling notification tap
        if let profileID = currentProfileID {
            content.userInfo["profileID"] = profileID.uuidString
        }
        
        // Include target URL for auto-redirect if enabled
        if let settings = currentNotificationSettings, settings.autoOpenClashOfClansEnabled {
            content.userInfo["targetURL"] = "clashofclans://"
        }

        // Apply notification offset (pre-notify N minutes before completion)
        let offsetSeconds = Double((currentNotificationSettings?.notificationOffsetMinutes ?? 0) * 60)
        let interval = max(upgrade.endTime.timeIntervalSinceNow - offsetSeconds, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let identifier = Self.identifier(for: upgrade.id)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private static func identifier(for upgradeID: UUID) -> String {
        identifierPrefix + upgradeID.uuidString
    }

    private static func threadIdentifier(for category: UpgradeCategory) -> String {
        switch category {
        case .builderVillage:
            return "builder_village"
        case .lab:
            return "laboratory"
        case .starLab:
            return "star_lab"
        case .pets:
            return "pet_house"
        case .builderBase:
            return "builder_base"
        }
    }

    // MARK: - Helper notifications

    private static let helperIdentifierPrefix = "com.zacharybuschmann.clashdash.helper."

    struct HelperNotificationRequest {
        let identifier: String
        let title: String
        let body: String
        let date: Date
    }

    func syncHelperNotifications(for requests: [HelperNotificationRequest]) {
        guard !requests.isEmpty else {
            removeAllHelperNotifications()
            return
        }

        ensureAuthorization(promptIfNeeded: false) { granted in
            guard granted else {
                self.removeAllHelperNotifications()
                return
            }

            let desired = requests.map { self.makeRequest(for: $0) }
            self.center.getPendingNotificationRequests { existing in
                let managed = existing.filter { $0.identifier.hasPrefix(Self.helperIdentifierPrefix) }
                let managedIdentifiers = Set(managed.map { $0.identifier })
                let desiredIdentifiers = Set(desired.map { $0.identifier })

                let identifiersToRemove = Array(managedIdentifiers.subtracting(desiredIdentifiers))
                if !identifiersToRemove.isEmpty {
                    self.center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
                }

                let existingSet = managedIdentifiers
                let newRequests = desired.filter { !existingSet.contains($0.identifier) }
                for request in newRequests {
                    self.center.add(request)
                }
            }
        }
    }

    private func makeRequest(for helper: HelperNotificationRequest) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = helper.title
        content.body = helper.body
        content.sound = .default
        content.threadIdentifier = "helpers"

        let interval = max(helper.date.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        return UNNotificationRequest(identifier: helper.identifier, content: content, trigger: trigger)
    }

    func removeAllHelperNotifications() {
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .filter { $0.identifier.hasPrefix(Self.helperIdentifierPrefix) }
                .map { $0.identifier }
            guard !identifiers.isEmpty else { return }
            self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }
}

