import Foundation

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let example = try decoder.decode(RemoteEventFeed.self, from: Data(contentsOf: URL(fileURLWithPath: "remote/examples/hammer_jam.json")))
try example.validate()
let sample = example.events[0]
let event = RemoteEvent(id: sample.id, enabled: true, start: sample.start, end: sample.end, presentation: sample.presentation, modifiers: sample.modifiers)
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
assert(factor(now: start, tracked: start) == nil, "An import during an event is authoritative")
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
let invalid = RemoteEvent(id: "bad", enabled: true, start: start, end: event.end, presentation: event.presentation, modifiers: [invalidRule])
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
let testDate = ISO8601DateFormatter().date(from: "2026-10-07T00:00:00Z")!
if let testEvent = liveFeed.events.first(where: { $0.id == "hammer-jam-test-2026-10-v1" }) {
    assert(testEvent.isActive(at: testDate))
    assert(testEvent.modifiers.first?.excludeSupercharges == true)
    assert(!testEvent.presentation.sections.isEmpty)
}
let liveNews = try decoder.decode(RemoteNewsFeed.self, from: Data(contentsOf: URL(fileURLWithPath: "remote/news_feed.json")))
let latest = try decoder.decode(LatestRemoteNews.self, from: Data(contentsOf: URL(fileURLWithPath: "remote/latest_news.json")))
if let latestID = latest.id { assert(liveNews.entries.contains { $0.id == latestID }) }
print("Active test feed checks passed: matching popup, event dates, detail sections, and Supercharge exclusion.")
