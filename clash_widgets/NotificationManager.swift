import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private static let identifierPrefix = "com.zacharybuschmann.clashdash.upgrade."

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

    func syncNotifications(for upgrades: [BuildingUpgrade], settings: NotificationSettings) {
        guard settings.notificationsEnabled else {
            removeAllUpgradeNotifications()
            return
        }
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
        content.body = "\(upgrade.name) finished upgrading to level \(upgrade.targetLevel)."
        content.sound = .default
        content.threadIdentifier = Self.threadIdentifier(for: upgrade.category)

        let interval = max(upgrade.endTime.timeIntervalSinceNow, 1)
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
        case .pets:
            return "pet_house"
        case .builderBase:
            return "builder_base"
        }
    }
}
