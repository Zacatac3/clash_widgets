import Foundation

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let example = try decoder.decode(RemoteEventFeed.self, from: Data(contentsOf: URL(fileURLWithPath: "remote/examples/hammer_jam.json")))
try example.validate()
let sample = example.events[0]
let event = RemoteEvent(id: sample.id, enabled: true, start: sample.start, end: sample.end, icon: sample.icon, presentation: sample.presentation, modifiers: sample.modifiers)
let start = event.start
let day: TimeInterval = 86400
func factor(now: Date, tracked: Date? = nil, end: Date? = nil, category: String = "builderVillage", applied: Set<String> = [], seasonal: Bool = false) -> Double? {
    remoteEventTimeFactor(event: event, now: now, trackedSince: tracked ?? start.addingTimeInterval(-day),
        currentEnd: end ?? start.addingTimeInterval(16 * day), category: category, dataID: 1,
        townHall: 15, appliedIDs: applied, seasonal: seasonal)
}
assert(event.isVisible(at: start.addingTimeInterval(-day)))
assert(!event.isActive(at: start.addingTimeInterval(-1)))
assert(event.isActive(at: start))
assert(!event.isActive(at: event.end))
assert(!event.isVisible(at: event.end))
assert(factor(now: start) == 0.5)
assert(factor(now: event.end.addingTimeInterval(day)) == nil, "Entirely skipped events must not replay")
assert(factor(now: start, tracked: start) == 0.5, "Imports during an event still receive the full-duration cap")
assert(factor(now: start, end: start.addingTimeInterval(-1)) == nil)
assert(factor(now: start, applied: [event.id]) == nil, "Repeat reconciliation must not halve twice")
assert(factor(now: start, seasonal: true) == nil)
assert(factor(now: start, category: "builderBase") == nil)
let original = start.addingTimeInterval(16 * day)
let adjusted = remoteEventAdjustedEnd(originalEnd: original, eventStart: start, baseDuration: 10 * day, goldPassFactor: 0.8, eventFactor: 0.5)
assert(adjusted == start.addingTimeInterval(4 * day))
assert(adjusted.timeIntervalSince(start.addingTimeInterval(6 * 3600)) == 3.75 * day, "Late launches use event start, not launch time")
let shortEnd = start.addingTimeInterval(day)
assert(remoteEventAdjustedEnd(originalEnd: shortEnd, eventStart: start, baseDuration: 10 * day, goldPassFactor: 1, eventFactor: 0.5) == shortEnd, "Do not lengthen shorter upgrades")
let restricted = RemoteModifier(categories: ["lab"], dataIDs: [7], excludedDataIDs: [8], townHallMin: 12, townHallMax: 14, timeMultiplier: 0.7, wallCostMultiplier: nil, excludeSupercharges: nil)
assert(restricted.matches(category: "lab", dataID: 7, townHall: 12))
assert(!restricted.matches(category: "lab", dataID: 7, townHall: 15))
assert(!restricted.matches(category: "lab", dataID: 8, townHall: 12))
for path in ["remote/latest_event.json", "remote/examples/hammer_jam.json"] {
    try decoder.decode(RemoteEventFeed.self, from: Data(contentsOf: URL(fileURLWithPath: path))).validate()
}
for path in ["remote/news_feed.json", "remote/examples/news_feed.json"] {
    try decoder.decode(RemoteNewsFeed.self, from: Data(contentsOf: URL(fileURLWithPath: path))).validate()
}
let invalidRule = RemoteModifier(categories: ["lab"], dataIDs: nil, excludedDataIDs: nil, townHallMin: nil, townHallMax: nil, timeMultiplier: 0, wallCostMultiplier: nil, excludeSupercharges: nil)
let invalid = RemoteEvent(id: "bad", enabled: true, start: start, end: event.end, icon: nil, presentation: event.presentation, modifiers: [invalidRule])
do {
    try RemoteEventFeed(schemaVersion: 1, events: [invalid]).validate()
    fatalError("Unsafe multipliers must be rejected")
} catch RemoteContentError.invalidPayload {}
print("Remote content checks passed: lifecycle, skipped/imported events, idempotence, Gold Pass, late launch, exclusions, schema and sample feeds.")

let withBoostCredit = remoteEventAdjustedEnd(originalEnd: original, eventStart: start,
    baseDuration: 10 * day, goldPassFactor: 0.8, eventFactor: 0.5, priorBoostCredit: day)
assert(withBoostCredit.addingTimeInterval(-day) == adjusted, "Prior potion/helper credit must not be subtracted twice")

assert(remoteEventTimeFactor(event: event, now: start, trackedSince: start.addingTimeInterval(-day),
    currentEnd: original, category: "builderVillage", dataID: 1, townHall: 15,
    appliedIDs: [], seasonal: false, supercharge: true) == nil,
    "A rule excluding Supercharges must preserve their timers")
let liveFeed = try decoder.decode(RemoteEventFeed.self, from: Data(contentsOf: URL(fileURLWithPath: "remote/latest_event.json")))
try liveFeed.validate()
assert(liveFeed.events.isEmpty, "The live event feed should default to no events")
let devFeed = try decoder.decode(RemoteEventFeed.self, from: Data(contentsOf: URL(fileURLWithPath: "remote_dev/latest_event.json")))
try devFeed.validate()
let liveNews = try decoder.decode(RemoteNewsFeed.self, from: Data(contentsOf: URL(fileURLWithPath: "remote/news_feed.json")))
let latest = try decoder.decode(LatestRemoteNews.self, from: Data(contentsOf: URL(fileURLWithPath: "remote/latest_news.json")))
if let latestID = latest.id { assert(liveNews.entries.contains { $0.id == latestID }) }
print("Live/default and development feed checks passed: empty live events, development schema and news pointer consistency.")

func building(trackedAt: Date, remainingDays: Double, baseDays: Double = 10,
              category: UpgradeCategory = .builderVillage, supercharge: Int? = nil,
              seasonal: Bool = false) -> BuildingUpgrade {
    BuildingUpgrade(dataId: 1, name: "Test Building", targetLevel: 10,
        superchargeTargetLevel: supercharge,
        endTime: trackedAt.addingTimeInterval(remainingDays * day), category: category,
        startTime: trackedAt, totalDuration: baseDays * day, isSeasonalDefense: seasonal)
}
let lateLaunch = start.addingTimeInterval(6 * 3600)
var previouslyTracked = building(trackedAt: start.addingTimeInterval(-2 * day), remainingDays: 10)
assert(previouslyTracked.applyRemoteEvent(event, at: lateLaunch, townHall: 15, goldPassBoost: 0))
assert(previouslyTracked.endTime == start.addingTimeInterval(5 * day))
assert(previouslyTracked.endTime.timeIntervalSince(lateLaunch) == 4.75 * day)
assert(previouslyTracked.effectiveTotalDuration(goldPassBoost: 0) == 5 * day)
let onceAdjustedEnd = previouslyTracked.endTime
assert(!previouslyTracked.applyRemoteEvent(event, at: lateLaunch, townHall: 15, goldPassBoost: 0))
assert(previouslyTracked.endTime == onceAdjustedEnd)
var importedDuringEvent = building(trackedAt: lateLaunch, remainingDays: 8)
assert(importedDuringEvent.applyRemoteEvent(event, at: lateLaunch, townHall: 15, goldPassBoost: 20))
assert(importedDuringEvent.endTime == lateLaunch.addingTimeInterval(4 * day))
assert(importedDuringEvent.effectiveTotalDuration(goldPassBoost: 20) == 4 * day)
var alreadyDiscounted = building(trackedAt: lateLaunch, remainingDays: 2)
let exportedEnd = alreadyDiscounted.endTime
assert(alreadyDiscounted.applyRemoteEvent(event, at: lateLaunch, townHall: 15, goldPassBoost: 20))
assert(alreadyDiscounted.endTime == exportedEnd, "Fresh already-discounted exports must not be halved again")
assert(alreadyDiscounted.effectiveTotalDuration(goldPassBoost: 20) == 4 * day)
var excludedSC = building(trackedAt: start.addingTimeInterval(-day), remainingDays: 8, supercharge: 1)
assert(!excludedSC.applyRemoteEvent(event, at: lateLaunch, townHall: 15, goldPassBoost: 0))
var excludedCrafted = building(trackedAt: start.addingTimeInterval(-day), remainingDays: 8, seasonal: true)
assert(!excludedCrafted.applyRemoteEvent(event, at: lateLaunch, townHall: 15, goldPassBoost: 0))
var excludedBB = building(trackedAt: start.addingTimeInterval(-day), remainingDays: 8, category: .builderBase)
assert(!excludedBB.applyRemoteEvent(event, at: lateLaunch, townHall: 15, goldPassBoost: 0))
var skipped = building(trackedAt: start.addingTimeInterval(-day), remainingDays: 30, baseDays: 30)
assert(!skipped.applyRemoteEvent(event, at: event.end, townHall: 15, goldPassBoost: 0))
let saved = try JSONEncoder().encode(importedDuringEvent)
var restored = try JSONDecoder().decode(BuildingUpgrade.self, from: saved)
assert(restored.remoteEventTimeMultiplier == 0.5)
assert(!restored.applyRemoteEvent(event, at: lateLaunch, townHall: 15, goldPassBoost: 20))
assert(restored.endTime == importedDuringEvent.endTime)
assert(restored.effectiveTotalDuration(goldPassBoost: 20) == 4 * day)
var legacyJSON = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
legacyJSON.removeValue(forKey: "remoteEventTimeMultiplier")
var legacy = try JSONDecoder().decode(BuildingUpgrade.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
assert(legacy.applyRemoteEvent(event, at: lateLaunch, townHall: 15, goldPassBoost: 20))
assert(legacy.endTime == importedDuringEvent.endTime, "Backfill duration without shortening twice")
assert(legacy.remoteEventTimeMultiplier == 0.5)
assert(remoteEventCountdown(until: start.addingTimeInterval(2 * day + 3 * 3600 + 4 * 60 + 5), at: start) == "02 Days 03:04:05")
assert(remoteEventCountdown(until: start.addingTimeInterval(-1), at: start) == "00 Days 00:00:00")
assert(remoteEventCountdown(until: start.addingTimeInterval(0.1), at: start) == "00 Days 00:00:01")
print("Building timer regressions passed: existing/late/imported timers, display durations, Gold Pass, exclusions, repeat application, persisted state, legacy backfill, and countdown formatting.")


// Exercise both boundaries of the same short test used by the Debug menu.
let shortStart = Date(timeIntervalSince1970: 1_800_000_000)
let shortEvent = RemoteEvent.fiveMinuteTest(at: shortStart, id: "short-lifecycle-test")
try RemoteEventFeed(schemaVersion: 1, events: [shortEvent]).validate()
precondition(shortEvent.isVisible(at: shortStart) && !shortEvent.isActive(at: shortStart))
precondition(shortEvent.isActive(at: shortEvent.start))
precondition(!shortEvent.isActive(at: shortEvent.end) && !shortEvent.isVisible(at: shortEvent.end))
var shortUpgrade = BuildingUpgrade(dataId: 1000008, name: "Cannon", targetLevel: 11,
    endTime: shortStart.addingTimeInterval(1080), category: .builderVillage,
    startTime: shortStart, totalDuration: 1200)
precondition(!shortUpgrade.applyRemoteEvent(shortEvent, at: shortStart, townHall: 18, goldPassBoost: 0))
precondition(shortUpgrade.applyRemoteEvent(shortEvent, at: shortEvent.start, townHall: 18, goldPassBoost: 0))
precondition(shortUpgrade.endTime == shortEvent.start.addingTimeInterval(600))
let discountedEnd = shortUpgrade.endTime
precondition(!shortUpgrade.applyRemoteEvent(shortEvent, at: shortEvent.end, townHall: 18, goldPassBoost: 0))
precondition(shortUpgrade.endTime == discountedEnd && shortUpgrade.remoteEventTimeMultiplier == 0.5)
var afterEnd = BuildingUpgrade(dataId: 1000008, name: "Cannon", targetLevel: 11,
    endTime: shortEvent.end.addingTimeInterval(1080), category: .builderVillage,
    startTime: shortEvent.end, totalDuration: 1200)
precondition(!afterEnd.applyRemoteEvent(shortEvent, at: shortEvent.end, townHall: 18, goldPassBoost: 0))
precondition(afterEnd.remoteEventTimeMultiplier == nil)
let savedShortUpgrade = try JSONDecoder().decode(BuildingUpgrade.self, from: JSONEncoder().encode(shortUpgrade))
precondition(savedShortUpgrade.endTime == discountedEnd && savedShortUpgrade.remoteEventTimeMultiplier == 0.5)
print("Five-minute event lifecycle passed: countdown, exact boundaries, expiry, retained discounts, post-event imports and restart persistence.")


let liveEnvironment = RemoteContentEnvironment.live
let devEnvironment = RemoteContentEnvironment.development
let liveFeedURL = URL(string: "https://raw.githubusercontent.com/Zacatac3/clash_widgets/main/remote")!
precondition(liveEnvironment.baseURL(liveURL: liveFeedURL) == liveFeedURL)
precondition(devEnvironment.baseURL(liveURL: liveFeedURL).path == "/Zacatac3/clash_widgets/main/remote_dev")
precondition(devEnvironment.baseURL(liveURL: liveFeedURL.appendingPathComponent("", isDirectory: true)).path == "/Zacatac3/clash_widgets/main/remote_dev")
let isolatedDefaults = UserDefaults(suiteName: "clashboard-remote-environment-tests-" + UUID().uuidString)!
for name in ["events", "news", "lastSeenNews", "lastAttempt", "lastSuccess"] {
    precondition(liveEnvironment.cacheKey(name) != devEnvironment.cacheKey(name))
    isolatedDefaults.set("live-value", forKey: liveEnvironment.cacheKey(name))
    isolatedDefaults.set("dev-value", forKey: devEnvironment.cacheKey(name))
    precondition(isolatedDefaults.string(forKey: liveEnvironment.cacheKey(name)) == "live-value")
    precondition(isolatedDefaults.string(forKey: devEnvironment.cacheKey(name)) == "dev-value")
    isolatedDefaults.removeObject(forKey: liveEnvironment.cacheKey(name))
    isolatedDefaults.removeObject(forKey: devEnvironment.cacheKey(name))
}
precondition(liveEnvironment.scopedEvent(shortEvent).id == shortEvent.id)
precondition(devEnvironment.scopedEvent(shortEvent).id != shortEvent.id)
precondition(devEnvironment.scopedEvent(shortEvent).modifiers.first?.timeMultiplier == 0.5)
print("Development feed checks passed: URL selection, cache/read-state isolation, backwards-compatible live keys and event identity isolation.")


let refreshNow = Date(timeIntervalSince1970: 1_800_000_000)
func refreshDecision(build: String = "1.3 (10)", successful: String? = "1.3 (10)",
                     attempted: String? = "1.3 (10)", attemptAge: Double = 60,
                     successAge: Double = 60, force: Bool = false, hasCache: Bool = true) -> Bool {
    RemoteContentRefreshPolicy.shouldRefresh(now: refreshNow, force: force, hasCache: hasCache,
        lastSuccess: refreshNow.addingTimeInterval(-successAge),
        lastAttempt: refreshNow.addingTimeInterval(-attemptAge), currentBuild: build,
        successfulBuild: successful, attemptedBuild: attempted)
}
precondition(!refreshDecision(), "Same build must respect daily cache")
precondition(refreshDecision(build: "1.3 (11)"), "New build must bypass recent successful refresh and retry cooldown")
precondition(refreshDecision(build: "1.4 (10)"), "Version changes must refresh even if build number is reused")
precondition(refreshDecision(successful: nil, attempted: nil), "First install and migration must fetch immediately")
precondition(!refreshDecision(successful: "1.2 (9)"), "Failed new-build refresh must back off for 15 minutes")
precondition(refreshDecision(successful: "1.2 (9)", attemptAge: 900), "Failed new-build refresh must retry after backoff despite yesterday's cache")
precondition(refreshDecision(force: true), "Manual refresh must bypass cooldown")
precondition(refreshDecision(attemptAge: 86400, successAge: 86400), "Same build must refresh after a day")
precondition(RemoteContentEnvironment.live.cacheKey("successfulBuild") != RemoteContentEnvironment.development.cacheKey("successfulBuild"))
print("Build-update refresh checks passed: install, new build/version, successful cooldown, failure retry and environment isolation.")
