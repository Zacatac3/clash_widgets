import Foundation

extension DataService {
    // Imports are authoritative. Only timers tracked before a currently active
    // event are capped; events first encountered after their end are ignored.
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
                for event in active where !upgrade.appliedRemoteEventIDs.contains(event.id) {
                    guard upgrade.totalDuration > 0,
                          let factor = remoteEventTimeFactor(event: event, now: now,
                            trackedSince: upgrade.startTime, currentEnd: upgrade.endTime,
                            category: upgrade.category.rawValue, dataID: upgrade.dataId,
                            townHall: townHall, appliedIDs: upgrade.appliedRemoteEventIDs,
                            seasonal: upgrade.isSeasonalDefense == true,
                            supercharge: upgrade.superchargeTargetLevel != nil) else { continue }
                    let gold = upgrade.goldPassFactorAtImport ?? (1 - Double(max(0, min(100, profile.goldPassBoost))) / 100)
                    let relevantBoosts = profile.activeBoosts.filter { $0.endTime > now }
                    let rawRemainingAtStart = max(0, upgrade.endTime.timeIntervalSince(event.start))
                    let effectiveAtStart = effectiveRemainingSeconds(for: upgrade,
                        activeBoosts: relevantBoosts, referenceDate: event.start)
                    guard effectiveAtStart > 0 else { continue }
                    let priorBoostCredit = max(0, rawRemainingAtStart - effectiveAtStart)
                    upgrade.endTime = remoteEventAdjustedEnd(originalEnd: upgrade.endTime, eventStart: event.start,
                        baseDuration: upgrade.totalDuration, goldPassFactor: gold, eventFactor: factor, priorBoostCredit: priorBoostCredit)
                    upgrade.appliedRemoteEventIDs.insert(event.id)
                    changed = true
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
