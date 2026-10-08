import Foundation

extension DataService {
    // Cap eligible timers at their discounted full duration, including imports
    // during an event. Already discounted shorter exports are left intact.
    @MainActor
    func reconcileRemoteEvents(_ events: [RemoteEvent], at now: Date) {
        let active = events.filter { $0.isActive(at: now) }.sorted { $0.start < $1.start }
        guard !active.isEmpty else { return }
        var updated = profiles
        var changed = false
        for index in updated.indices {
            let profile = updated[index]
            let townHall = profile.cachedProfile?.townHallLevel ?? inferTownHallLevel(from: profile.rawJSON)
            for upgradeIndex in updated[index].activeUpgrades.indices {
                var upgrade = updated[index].activeUpgrades[upgradeIndex]
                for event in active where RemoteContentService.shared.eventApplies(event, to: profile.id) {
                    let boundary = max(event.start, upgrade.startTime)
                    let relevantBoosts = profile.activeBoosts.filter { $0.endTime > now }
                    let rawRemainingAtBoundary = max(0, upgrade.endTime.timeIntervalSince(boundary))
                    let effectiveAtBoundary = effectiveRemainingSeconds(for: upgrade,
                        activeBoosts: relevantBoosts, referenceDate: boundary)
                    guard effectiveAtBoundary > 0 else { continue }
                    let priorBoostCredit = max(0, rawRemainingAtBoundary - effectiveAtBoundary)
                    if upgrade.applyRemoteEvent(event, at: now, townHall: townHall,
                        goldPassBoost: profile.goldPassBoost, priorBoostCredit: priorBoostCredit) {
                        changed = true
                    }
                }
                updated[index].activeUpgrades[upgradeIndex] = upgrade
            }
        }
        guard changed else { return }
        profiles = updated
        applyCurrentProfile()
        pruneCompletedUpgrades(referenceDate: now)
        saveToStorage(reloadWidgets: true)
    }

}

extension DataService {
    @MainActor
    func startFiveMinuteEventTest(goldPass: Bool) throws {
        guard profiles.count < 20 else { throw RemoteContentError.invalidPayload }
        let now = Date()
        let event = RemoteEvent.fiveMinuteTest(at: now)
        var settings = NotificationSettings.default
        settings.notificationsEnabled = false
        var profile = PlayerAccount(displayName: "Event Test (Synthetic)", notificationSettings: settings,
                                    builderCount: 6, goldPassBoost: goldPass ? 20 : 0)
        let export: [String: Any] = [
            "timestamp": Int(now.timeIntervalSince1970),
            "buildings": [["data": 1000001, "lvl": 18], ["data": 1000008, "lvl": 10, "timer": 1080],
                ["data": 1000009, "lvl": 20, "supercharge": 1, "timer": 1080],
                ["data": 1000010, "lvl": 17, "cnt": 100],
                ["data": 1000097, "types": [["data": 103000011, "modules": [["data": 102000033, "lvl": 7, "timer": 1080]]]]]],
            "buildings2": [["data": 1000034, "lvl": 10], ["data": 1000044, "lvl": 10, "timer": 1080]],
            "units": [["data": 4000000, "lvl": 10, "timer": 1080]],
            "pets": [["data": 73000000, "lvl": 5, "timer": 1080]]
        ]
        let data = try JSONSerialization.data(withJSONObject: export, options: [.sortedKeys])
        profile.rawJSON = String(decoding: data, as: UTF8.self)
        profile.lastImportDate = now
        func timer(_ id: Int, _ name: String, _ level: Int, _ category: UpgradeCategory,
                   supercharge: Bool = false, crafted: Bool = false) -> BuildingUpgrade {
            var upgrade = BuildingUpgrade(dataId: id, name: name, targetLevel: level + 1,
                superchargeLevel: supercharge ? 1 : nil, superchargeTargetLevel: supercharge ? 2 : nil,
                endTime: now.addingTimeInterval(1080), category: category, startTime: now,
                totalDuration: 1200, isSeasonalDefense: crafted)
            upgrade.goldPassFactorAtImport = goldPass ? 0.8 : 1
            upgrade.sourceExportTimer = 1080
            return upgrade
        }
        profile.activeUpgrades = [timer(1000008, "Cannon", 10, .builderVillage),
            timer(4000000, "Barbarian", 10, .lab), timer(73000000, "L.A.S.S.I", 5, .pets),
            timer(1000044, "Cannon", 10, .builderBase),
            timer(1000009, "Archer Tower", 20, .builderVillage, supercharge: true),
            timer(103000011, "Crafted Defense", 7, .builderVillage, crafted: true)]
        try RemoteContentService.shared.beginEventTest(event, profileID: profile.id, previousProfileID: selectedProfileID)
        profiles.append(profile)
        selectedProfileID = profile.id
        saveToStorage(reloadWidgets: true)
    }

    @MainActor
    func addEventTestUpgrade() throws {
        guard let testID = RemoteContentService.shared.testProfileID,
              let index = profiles.firstIndex(where: { $0.id == testID }),
              let data = profiles[index].rawJSON.data(using: .utf8),
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RemoteContentError.invalidPayload
        }
        let now = Date()
        var items = root["heroes"] as? [[String: Any]] ?? []
        guard items.isEmpty else { throw RemoteContentError.invalidPayload }
        items.append(["data": 28000000, "lvl": 50, "timer": 1080])
        root["heroes"] = items
        profiles[index].rawJSON = String(decoding: try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]), as: UTF8.self)
        var upgrade = BuildingUpgrade(dataId: 28000000, name: "Barbarian King", targetLevel: 51,
            endTime: now.addingTimeInterval(1080), category: .builderVillage, startTime: now, totalDuration: 1200)
        upgrade.sourceExportTimer = 1080
        upgrade.goldPassFactorAtImport = 1 - Double(profiles[index].goldPassBoost) / 100
        profiles[index].activeUpgrades.append(upgrade)
        selectedProfileID = testID
        applyCurrentProfile()
        reconcileRemoteEvents(RemoteContentService.shared.events, at: now)
        saveToStorage(reloadWidgets: true)
    }

    @MainActor
    func removeEventTest() {
        let testID = RemoteContentService.shared.testProfileID
        let previousID = RemoteContentService.shared.profileBeforeTest
        // Delete the fixture before restoring regular event eligibility.
        if let testID { deleteProfile(testID) }
        RemoteContentService.shared.endEventTest()
        if let previousID, profiles.contains(where: { $0.id == previousID }) { selectedProfileID = previousID }
        saveToStorage(reloadWidgets: true)
    }
}
