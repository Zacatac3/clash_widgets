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

    func syncNotifications(for upgrades: [BuildingUpgrade], settings: NotificationSettings) {
        guard settings.notificationsEnabled else {
            removeAllUpgradeNotifications()
            return
        }
        setNotificationSettings(settings)
        
        let filteredUpgrades = upgrades.filter { settings.allows(category: $0.category) && $0.endTime > Date() }
        syncNotifications(for: filteredUpgrades)
    }

    func syncNotifications(for upgrades: [BuildingUpgrade], activeBoosts: [ActiveBoost] = []) {
        guard !upgrades.isEmpty else {
            removeAllUpgradeNotifications()
            return
        }

        ensureAuthorization(promptIfNeeded: false) { granted in
            guard granted else {
                self.removeAllUpgradeNotifications()
                return
            }

            let desiredRequests = upgrades.map { self.makeRequest(for: $0, activeBoosts: activeBoosts) }
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
        if let profiles = allProfiles, profiles.count > 1, let name = profileName {
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

    private func makeRequest(for upgrade: BuildingUpgrade, activeBoosts: [ActiveBoost] = []) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Upgrade Complete"
        
        var bodyText = "\(upgrade.name) finished upgrading to level \(upgrade.targetLevel)."
        
        // Add profile name if multiple profiles exist - format: "Username: upgrade x completed"
        if let profiles = allProfiles, profiles.count > 1, let profileID = currentProfileID,
           let profile = profiles.first(where: { $0.id == profileID }) {
            let resolvedName = [
                profile.displayName,
                profile.cachedProfile?.name
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "Profile"
            bodyText = "\(resolvedName): \(upgrade.name) finished upgrading to level \(upgrade.targetLevel)."
        }
        
        content.body = bodyText
        content.sound = .default
        content.threadIdentifier = Self.threadIdentifier(for: upgrade.category)
        
        // Store profile ID for handling notification tap
        if let profileID = currentProfileID {
            content.userInfo["profileID"] = profileID.uuidString
        }
        
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
        let identifier = Self.identifier(for: upgrade.id)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }
    
    /// Calculate the effective completion date accounting for active and future boosts
    /// This projects forward in time to determine WHEN the upgrade will actually complete
    private func effectiveCompletionDate(for upgrade: BuildingUpgrade, activeBoosts: [ActiveBoost]) -> Date {
        let now = Date()
        var remainingWork = max(0, upgrade.endTime.timeIntervalSince(now))
        
        // If no boosts or no work remaining, use raw endTime
        guard !activeBoosts.isEmpty, remainingWork > 0 else {
            return upgrade.endTime
        }
        
        // Filter boosts that affect this upgrade's category
        let relevantBoosts = activeBoosts.compactMap { boost -> ActiveBoost? in
            guard let boostType = boost.boostType,
                  boostType.affectedCategories.contains(upgrade.category),
                  boost.endTime > now else { return nil }
            // For targeted boosts, only include if it targets this upgrade
            if boostType == .builderApprentice || boostType == .labAssistant {
                if let targetId = boost.targetUpgradeId, targetId != upgrade.id { return nil }
            }
            return boost
        }.sorted { $0.endTime < $1.endTime }
        
        if relevantBoosts.isEmpty { return upgrade.endTime }
        
        // Simulate time passing and calculate when work completes
        var currentTime = now
        
        // Build timeline of future boost transitions
        var transitions: [Date] = [now]
        for boost in relevantBoosts {
            if boost.startTime > now {
                transitions.append(boost.startTime)
            }
            transitions.append(boost.endTime)
        }
        transitions = Array(Set(transitions)).sorted()
        
        // Process each time segment
        for idx in 0..<(transitions.count - 1) {
            let segmentStart = transitions[idx]
            let segmentEnd = transitions[idx + 1]
            
            // Calculate effective speed multiplier for this segment
            var speedMultiplier = 1.0
            var clockTowerApplied = false
            
            for boost in relevantBoosts {
                guard let boostType = boost.boostType else { continue }
                // Check if this boost is active during this segment
                if boost.startTime <= segmentStart && boost.endTime > segmentStart {
                    let level = boost.helperLevel ?? 0
                    if boostType.isClockTowerBoost {
                        if !clockTowerApplied {
                            speedMultiplier += boostType.speedMultiplier(level: level)
                            clockTowerApplied = true
                        }
                    } else {
                        speedMultiplier += boostType.speedMultiplier(level: level)
                    }
                }
            }
            
            // How much real time passes in this segment
            let realTime = segmentEnd.timeIntervalSince(segmentStart)
            // How much work gets done (boosted time)
            let workDone = realTime * speedMultiplier
            
            if workDone >= remainingWork {
                // Upgrade completes during this segment
                let timeNeeded = remainingWork / speedMultiplier
                return segmentStart.addingTimeInterval(timeNeeded)
            }
            
            remainingWork -= workDone
            currentTime = segmentEnd
        }
        
        // If we still have work after all boosts expire, add unboosted time
        return currentTime.addingTimeInterval(remainingWork)
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

