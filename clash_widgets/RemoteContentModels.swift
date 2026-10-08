import Foundation

struct RemoteImage: Codable {
    let source: String
    let value: String
}

struct RemoteSection: Codable {
    let title: String
    let body: String
    let image: RemoteImage?
}

struct RemotePresentation: Codable {
    let title: String
    let summary: String
    let image: RemoteImage?
    let sections: [RemoteSection]
}

struct RemoteModifier: Codable {
    // Categories use UpgradeCategory raw values; dataIDs permit resource-specific subsets.
    let categories: [String]
    let dataIDs: [Int]?
    let excludedDataIDs: [Int]?
    let townHallMin: Int?
    let townHallMax: Int?
    let timeMultiplier: Double?
    let wallCostMultiplier: Double?
    let excludeSupercharges: Bool?

    func matches(category: String, dataID: Int?, townHall: Int, isSupercharge: Bool = false) -> Bool {
        guard categories.contains(category), townHall >= (townHallMin ?? 1),
              townHall <= (townHallMax ?? Int.max) else { return false }
        if excludeSupercharges == true && isSupercharge { return false }
        if let ids = dataIDs, !ids.contains(dataID ?? -1) { return false }
        if let ids = excludedDataIDs, ids.contains(dataID ?? -1) { return false }
        return true
    }
}

struct RemoteEvent: Codable, Identifiable {
    let id: String
    let enabled: Bool
    let start: Date
    let end: Date
    let icon: RemoteImage?
    let presentation: RemotePresentation
    let modifiers: [RemoteModifier]

    func isActive(at now: Date) -> Bool { enabled && start <= now && now < end }
    func isVisible(at now: Date) -> Bool { enabled && now < end }
}

struct RemoteEventFeed: Codable {
    let schemaVersion: Int
    let events: [RemoteEvent]

    func validate() throws {
        guard schemaVersion == 1, events.count <= 30,
              Set(events.map(\.id)).count == events.count else { throw RemoteContentError.invalidPayload }
        for event in events {
            guard !event.id.isEmpty, event.start < event.end else { throw RemoteContentError.invalidPayload }
            for rule in event.modifiers {
                let supported = ["builderVillage", "lab", "pets", "builderBase", "starLab", "walls"]
                guard !rule.categories.isEmpty, rule.categories.allSatisfy({ supported.contains($0) }),
                      (rule.townHallMin ?? 1) > 0,
                      (rule.townHallMax ?? Int.max) >= (rule.townHallMin ?? 1) else { throw RemoteContentError.invalidPayload }
                for value in [rule.timeMultiplier, rule.wallCostMultiplier].compactMap({ $0 }) {
                    guard value.isFinite, value > 0, value <= 1 else { throw RemoteContentError.invalidPayload }
                }
            }
        }
    }
}

struct RemoteNews: Codable, Identifiable {
    let id: String
    let published: Date
    let showAsPopup: Bool
    let presentation: RemotePresentation
}

struct RemoteNewsFeed: Codable {
    let schemaVersion: Int
    let entries: [RemoteNews]

    func validate() throws {
        guard schemaVersion == 1, entries.count <= 500,
              entries.allSatisfy({ !$0.id.isEmpty }),
              Set(entries.map(\.id)).count == entries.count else { throw RemoteContentError.invalidPayload }
    }
}

struct LatestRemoteNews: Codable {
    let schemaVersion: Int
    let id: String?
}

enum RemoteContentError: Error { case invalidPayload, invalidURL, httpStatus }

// Existing upgrades are capped at an event-adjusted full duration at the start boundary.
// Never multiply their current remaining time, and never lengthen them at event end.
func remoteEventAdjustedEnd(originalEnd: Date, eventStart: Date,
                            baseDuration: TimeInterval, goldPassFactor: Double,
                            eventFactor: Double, priorBoostCredit: TimeInterval = 0) -> Date {
    // Downstream boost calculations subtract this credit, so retain it in the raw end.
    min(originalEnd, eventStart.addingTimeInterval(max(0, baseDuration * goldPassFactor * eventFactor) + max(0, priorBoostCredit)))
}

func remoteEventTimeFactor(event: RemoteEvent, now: Date, trackedSince: Date,
                           currentEnd: Date, category: String, dataID: Int?,
                           townHall: Int, appliedIDs: Set<String>, seasonal: Bool, supercharge: Bool = false) -> Double? {
    guard event.isActive(at: now), trackedSince <= now, currentEnd > max(event.start, trackedSince),
          !appliedIDs.contains(event.id), !seasonal else { return nil }
    return event.modifiers.filter {
        $0.matches(category: category, dataID: dataID, townHall: townHall, isSupercharge: supercharge)
    }.compactMap(\.timeMultiplier).min()
}

// Shared by the Home event card and details. Clamp at zero after the boundary.
func remoteEventCountdown(until deadline: Date, at now: Date) -> String {
    let seconds = Int(max(0, deadline.timeIntervalSince(now)).rounded(.up))
    return String(format: "%02d Days %02d:%02d:%02d", seconds / 86400,
                  (seconds % 86400) / 3600, (seconds % 3600) / 60, seconds % 60)
}

extension BuildingUpgrade {
    // A discounted export already below the full-duration cap stays unchanged.
    // For imports during an event, use the import snapshot as the boundary; for
    // previously tracked upgrades, use the event start, including elapsed time.
    mutating func applyRemoteEvent(_ event: RemoteEvent, at now: Date, townHall: Int,
                                  goldPassBoost: Int, priorBoostCredit: TimeInterval = 0) -> Bool {
        guard totalDuration > 0,
              let factor = remoteEventTimeFactor(event: event, now: now,
                trackedSince: startTime, currentEnd: endTime, category: category.rawValue,
                dataID: dataId, townHall: townHall, appliedIDs: [],
                seasonal: isSeasonalDefense == true, supercharge: superchargeTargetLevel != nil) else { return false }
        if appliedRemoteEventIDs.contains(event.id), remoteEventTimeMultiplier != nil { return false }
        let snapshotFactor = min(remoteEventTimeMultiplier ?? 1, factor)
        var changed = remoteEventTimeMultiplier != snapshotFactor
        remoteEventTimeMultiplier = snapshotFactor
        if goldPassFactorAtImport == nil {
            goldPassFactorAtImport = 1 - Double(max(0, min(100, goldPassBoost))) / 100
            changed = true
        }
        // Backfill the displayed duration on upgrades adjusted by earlier builds.
        guard !appliedRemoteEventIDs.contains(event.id) else { return changed }
        let boundary = max(event.start, startTime)
        endTime = remoteEventAdjustedEnd(originalEnd: endTime, eventStart: boundary,
            baseDuration: totalDuration, goldPassFactor: goldPassFactorAtImport ?? 1,
            eventFactor: snapshotFactor, priorBoostCredit: priorBoostCredit)
        appliedRemoteEventIDs.insert(event.id)
        return true
    }
}

extension RemoteEvent {
    static func fiveMinuteTest(at now: Date, id: String = "local-event-test-" + UUID().uuidString) -> RemoteEvent {
        RemoteEvent(id: id, enabled: true, start: now.addingTimeInterval(30),
                    end: now.addingTimeInterval(330), icon: RemoteImage(source: "bundle", value: "profile/home_builder"),
                    presentation: RemotePresentation(title: "Hammer Jam Test", summary: "Synthetic local test: starts in 30 seconds and runs for 5 minutes.", image: nil,
                        sections: [RemoteSection(title: "What to Check", body: "Eligible timers drop from 20 to 10 minutes at the start (8 minutes with 20% Gold Pass). Builder Base, Supercharges, and Crafted Defenses stay unchanged. Wall costs drop by 50%. After 5 minutes the event disappears and wall costs return to normal. Discounted upgrades keep their reductions; new upgrades added afterward receive no event discount.", image: nil)]),
                    modifiers: [RemoteModifier(categories: ["builderVillage", "lab", "pets"], dataIDs: nil,
                        excludedDataIDs: nil, townHallMin: nil, townHallMax: nil,
                        timeMultiplier: 0.5, wallCostMultiplier: nil, excludeSupercharges: true),
                        RemoteModifier(categories: ["walls"], dataIDs: nil, excludedDataIDs: nil,
                            townHallMin: nil, townHallMax: nil, timeMultiplier: nil,
                            wallCostMultiplier: 0.5, excludeSupercharges: nil)])
    }
}


enum RemoteContentEnvironment: String, CaseIterable {
    case live
    case development

    var label: String { self == .live ? "Live" : "Development" }

    func cacheKey(_ name: String) -> String {
        self == .live ? "remoteContent.\(name)" : "remoteContent.dev.\(name)"
    }

    func baseURL(liveURL: URL) -> URL {
        self == .live ? liveURL : liveURL.deletingLastPathComponent().appendingPathComponent("remote_dev", isDirectory: true)
    }

    func scopedEvent(_ event: RemoteEvent) -> RemoteEvent {
        guard self == .development else { return event }
        return RemoteEvent(id: "dev:" + event.id, enabled: event.enabled, start: event.start, end: event.end,
                           icon: event.icon, presentation: event.presentation, modifiers: event.modifiers)
    }
}


enum RemoteContentRefreshPolicy {
    static func shouldRefresh(now: Date, force: Bool, hasCache: Bool,
                              lastSuccess: Date?, lastAttempt: Date?, currentBuild: String,
                              successfulBuild: String?, attemptedBuild: String?) -> Bool {
        if force { return true }
        let needsBuildRefresh = successfulBuild != currentBuild
        if !needsBuildRefresh, hasCache, let lastSuccess,
           (0..<86400).contains(now.timeIntervalSince(lastSuccess)) { return false }
        // Each new version/build gets an immediate attempt, then normal failure backoff.
        if attemptedBuild == currentBuild, let lastAttempt,
           (0..<900).contains(now.timeIntervalSince(lastAttempt)) { return false }
        return true
    }
}
