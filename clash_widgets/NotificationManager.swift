import Foundation
import UserNotifications
import SwiftUI
import Combine

final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private static let identifierPrefix = "com.zacharybuschmann.clashdash.upgrade."
    private static let warIdentifierPrefix = "com.zacharybuschmann.clashdash.war."
    
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

    struct UpgradeNotificationRequest {
        let upgrade: BuildingUpgrade
        let profileID: UUID
        let profileName: String
        let activeBoosts: [ActiveBoost]
    }

    private var upgradeSyncRevision = 0

    func syncNotifications(for requests: [UpgradeNotificationRequest]) {
        upgradeSyncRevision += 1
        let revision = upgradeSyncRevision
        // Capture ownership and alert content before asynchronous permission checks.
        let desired = requests.map { makeRequest(for: $0) }
        ensureAuthorization(promptIfNeeded: false) { granted in
            guard revision == self.upgradeSyncRevision else { return }
            guard granted else { return }
            self.center.getPendingNotificationRequests { existing in
                DispatchQueue.main.async {
                    guard revision == self.upgradeSyncRevision else { return }
                    let managed = existing.filter { $0.identifier.hasPrefix(Self.identifierPrefix) }
                    let wanted = Set(desired.map(\.identifier))
                    self.center.removePendingNotificationRequests(withIdentifiers:
                        managed.filter { !wanted.contains($0.identifier) }.map(\.identifier))
                    for request in desired {
                        let previous = managed.first { $0.identifier == request.identifier }
                        let oldDate = (previous?.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
                        let newDate = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
                        let dateChanged = oldDate == nil || newDate == nil || abs(oldDate!.timeIntervalSince(newDate!)) > 2
                        if previous?.content.body != request.content.body
                            || !(NSDictionary(dictionary: previous?.content.userInfo ?? [:]).isEqual(to: request.content.userInfo))
                            || dateChanged {
                            self.center.add(request)
                        }
                    }
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
    
    func removeAllWarNotifications() {
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .filter { $0.identifier.hasPrefix(Self.warIdentifierPrefix) }
                .map { $0.identifier }
            guard !identifiers.isEmpty else { return }
            self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }
    
    func syncWarNotifications(for war: WarDetails?, settings: NotificationSettings, profileID: UUID?, profileName: String?) {
        guard settings.notificationsEnabled, settings.clanWarNotificationsEnabled else {
            removeAllWarNotifications()
            return
        }
        
        guard let war = war, let start = parseWarDate(war.startTime), let end = parseWarDate(war.endTime) else {
            removeAllWarNotifications()
            return
        }
        
        ensureAuthorization(promptIfNeeded: false) { granted in
            guard granted else {
                self.removeAllWarNotifications()
                return
            }
            
            let now = Date()
            var requests: [UNNotificationRequest] = []
            
            // Notification 1 hour before prep ends (which is when battle starts)
            let oneHourBeforeBattle = start.addingTimeInterval(-3600)
            if oneHourBeforeBattle > now {
                requests.append(self.makeWarNotificationRequest(
                    identifier: "prep_ending",
                    title: "War Preparation Ending Soon",
                    body: "Battle day starts in 1 hour!",
                    triggerDate: oneHourBeforeBattle,
                    profileID: profileID,
                    profileName: profileName
                ))
            }
            
            // Notification 1 hour before battle ends
            let oneHourBeforeBattleEnds = end.addingTimeInterval(-3600)
            if oneHourBeforeBattleEnds > now {
                requests.append(self.makeWarNotificationRequest(
                    identifier: "battle_ending",
                    title: "War Battle Day Ending Soon",
                    body: "Battle day ends in 1 hour!",
                    triggerDate: oneHourBeforeBattleEnds,
                    profileID: profileID,
                    profileName: profileName
                ))
            }
            
            // Remove old war notifications and add new ones
            self.removeAllWarNotifications()
            for request in requests {
                self.center.add(request)
            }
        }
    }
    
    private func makeWarNotificationRequest(
        identifier: String,
        title: String,
        body: String,
        triggerDate: Date,
        profileID: UUID?,
        profileName: String?
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        
        var bodyText = body
        if let profiles = allProfiles,
           profiles.count > 1,
           let name = sanitizedNotificationProfileName(profileName, profileTag: profileTag(for: profileID)) {
            bodyText = "\(name): \(body)"
        }
        content.body = bodyText
        content.sound = .default
        content.threadIdentifier = "clanwar"
        
        if let profileID = profileID {
            content.userInfo["profileID"] = profileID.uuidString
        }
        
        let interval = max(triggerDate.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        
        let fullIdentifier = Self.warIdentifierPrefix + identifier + "." + (profileID?.uuidString ?? "default")
        return UNNotificationRequest(identifier: fullIdentifier, content: content, trigger: trigger)
    }
    
    private func parseWarDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return formatter.date(from: value)
    }

    private func makeRequest(for request: UpgradeNotificationRequest) -> UNNotificationRequest {
        let upgrade = request.upgrade
        let activeBoosts = request.activeBoosts
        let content = UNMutableNotificationContent()
        content.title = "Upgrade Complete"
        
        var bodyText = "\(upgrade.name) finished upgrading to level \(upgrade.targetLevel)."
        
        bodyText = "\(request.profileName): \(bodyText)"
        content.body = bodyText
        content.sound = .default
        content.threadIdentifier = Self.threadIdentifier(for: upgrade.category)
        content.userInfo["profileID"] = request.profileID.uuidString

        // Include target URL for auto-redirect if enabled (global setting)
        let autoOpenClash = UserDefaults.standard.bool(forKey: "globalAutoOpenClashOfClans")
        if autoOpenClash {
            content.userInfo["targetURL"] = "clashofclans://"
        }

        // Calculate completion time accounting for active boosts
        let completionTime = effectiveCompletionDate(for: upgrade, activeBoosts: activeBoosts)
        
        // Apply notification offset (pre-notify N minutes before completion) (global setting)
        let offsetMinutes = UserDefaults.standard.integer(forKey: "globalNotificationOffsetMinutes")
        let offsetSeconds = Double(offsetMinutes * 60)
        let interval = max(completionTime.timeIntervalSinceNow - offsetSeconds, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let identifier = Self.identifierPrefix + request.profileID.uuidString + "." + upgrade.id.uuidString
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }
    
    /// Calculate the effective completion date accounting for active and future boosts
    /// This projects forward in time to determine WHEN the upgrade will actually complete
    private func effectiveCompletionDate(for upgrade: BuildingUpgrade, activeBoosts: [ActiveBoost]) -> Date {
        upgrade.projectedCompletionDate(activeBoosts: activeBoosts, referenceDate: Date())
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
        let profileID: UUID?
        let profileName: String?
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
        var bodyText = helper.body
        if let profiles = allProfiles,
           profiles.count > 1,
           let name = sanitizedNotificationProfileName(helper.profileName, profileTag: profileTag(for: helper.profileID)) {
            bodyText = "\(name): \(bodyText)"
        }
        content.body = bodyText
        content.sound = .default
        content.threadIdentifier = "helpers"

        if let profileID = helper.profileID {
            content.userInfo["profileID"] = profileID.uuidString
        }

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

    private func resolvedNotificationProfileName(for profile: PlayerAccount) -> String {
        [profile.displayName, profile.cachedProfile?.name]
            .compactMap { sanitizedNotificationProfileName($0, profileTag: profile.tag) }
            .first ?? "Profile"
    }

    private func profileTag(for profileID: UUID?) -> String? {
        guard let profileID,
              let profile = allProfiles?.first(where: { $0.id == profileID }) else {
            return nil
        }
        return profile.tag
    }

    private func sanitizedNotificationProfileName(_ name: String?, profileTag: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalizedName = normalizedTagValue(trimmed)
        let normalizedTag = normalizedTagValue(profileTag)
        if !normalizedTag.isEmpty && normalizedName == normalizedTag {
            return nil
        }

        return trimmed
    }

    private func normalizedTagValue(_ raw: String?) -> String {
        guard let raw else { return "" }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let uppercase = raw.uppercased()
        let filtered = uppercase.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(filtered))
    }
}

