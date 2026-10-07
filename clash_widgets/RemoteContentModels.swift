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
    guard event.isActive(at: now), trackedSince < event.start, currentEnd > event.start,
          !appliedIDs.contains(event.id), !seasonal else { return nil }
    return event.modifiers.filter {
        $0.matches(category: category, dataID: dataID, townHall: townHall, isSupercharge: supercharge)
    }.compactMap(\.timeMultiplier).min()
}
