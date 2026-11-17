import Foundation
import Combine

@main
struct PerformanceChecks {
    @MainActor
    static func main() async throws {
        let suite = "clashboard-performance-checks-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = RemoteContentService(defaults: defaults)
        var invalidations = 0
        let observation = service.objectWillChange.sink { invalidations += 1 }
        try await Task.sleep(for: .milliseconds(3200))
        print("Shared service invalidations while idle over 3.2s: \(invalidations)")
        if CommandLine.arguments.contains("--baseline") {
            precondition(invalidations >= 3, "The baseline should reproduce the global one-second redraw")
            withExtendedLifetime(observation) {}
            return
        }
        precondition(invalidations == 0, "Idle content must not invalidate the app or hidden tabs every second")

        let presentation = RemotePresentation(title: "Boundary test", summary: "", image: nil, sections: [])
        let start = Date().addingTimeInterval(0.2)
        let end = start.addingTimeInterval(0.3)
        let event = RemoteEvent(id: "clock-boundary-test", enabled: true, start: start, end: end,
                                icon: nil, presentation: presentation, modifiers: [])
        try service.beginEventTest(event, profileID: UUID(), previousProfileID: nil)
        precondition(service.visibleEvents.count == 1 && !service.events[0].isActive(at: service.now))
        var clockTicks = 0
        let clock = service.$now.dropFirst().sink { _ in clockTicks += 1 }
        try await Task.sleep(for: .milliseconds(350))
        precondition(service.events[0].isActive(at: service.now), "Event activation must update on its boundary")
        precondition(clockTicks == 1)
        try await Task.sleep(for: .milliseconds(350))
        precondition(service.visibleEvents.isEmpty, "Event expiry must remove cards and discounts on its boundary")
        precondition(clockTicks == 2, "An event should publish at start and end, not continuously")
        try await Task.sleep(for: .milliseconds(1100))
        precondition(clockTicks == 2, "The clock must stop when no future boundary remains")
        service.endEventTest()

        let future = RemoteEvent(id: "cancelled", enabled: true, start: Date().addingTimeInterval(0.2),
                                 end: Date().addingTimeInterval(0.4), icon: nil,
                                 presentation: presentation, modifiers: [])
        try service.beginEventTest(future, profileID: UUID(), previousProfileID: nil)
        service.endEventTest()
        let ticksAfterRemoval = clockTicks
        try await Task.sleep(for: .milliseconds(550))
        precondition(clockTicks == ticksAfterRemoval, "Removing an event must cancel its pending wake-up")

        let publication = Date(timeIntervalSince1970: ceil(Date().timeIntervalSince1970) + 1)
        let article = RemoteNews(id: "scheduled", published: publication, showAsPopup: true, presentation: presentation)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try encoder.encode(RemoteNewsFeed(schemaVersion: 1, entries: [article])), forKey: "remoteContent.news")
        let newsService = RemoteContentService(defaults: defaults)
        precondition(newsService.latestNews == nil)
        var newsTicks = 0
        let newsClock = newsService.$now.dropFirst().sink { _ in newsTicks += 1 }
        try await Task.sleep(for: .seconds(max(0, publication.timeIntervalSinceNow) + 0.15))
        precondition(newsService.latestNews?.id == article.id && newsService.unreadPopup?.id == article.id,
                     "Scheduled news and popups must still appear at publication time")
        precondition(newsTicks == 1)

        let disabled = RemoteEvent(id: "disabled", enabled: false, start: Date().addingTimeInterval(1),
                                   end: Date().addingTimeInterval(2), icon: nil, presentation: presentation, modifiers: [])
        precondition(RemoteContentClockSchedule.nextUpdate(events: [disabled], news: [], after: Date()) == nil)
        precondition(RemoteContentClockSchedule.nextUpdate(events: [event], news: [article], after: publication) == nil)
        withExtendedLifetime((observation, clock, newsClock)) {}
        print("Performance checks passed: no idle redraws, exact event boundaries, cancelled wake-ups, scheduled news, and no polling after expiry.")
    }
}
