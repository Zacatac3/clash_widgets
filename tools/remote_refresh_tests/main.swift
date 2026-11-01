import Foundation

final class FeedStubProtocol: URLProtocol {
    static let lock = NSLock()
    static var requests: [URLRequest] = []
    static var eventPayload = Data()
    static var newsPayload = Data(#"{"schemaVersion":1,"entries":[]}"#.utf8)
    static var failNews = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let events = Self.eventPayload
        let failNews = Self.failNews
        let news = Self.newsPayload
        Self.lock.unlock()
        let path = request.url!.lastPathComponent
        let status = path != "latest_event.json" && failNews ? 500 : 200
        let data: Data
        switch path {
        case "latest_event.json": data = events
        case "latest_news.json": data = Data(#"{"schemaVersion":1,"id":null}"#.utf8)
        default: data = news
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@main
struct RefreshChecks {
    @MainActor
    static func main() async throws {
        let name = "clashboard-refresh-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedStubProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let oldFeed = RemoteEventFeed(schemaVersion: 1, events: [.fiveMinuteTest(at: Date())])
        let oldBytes = try encoder.encode(oldFeed)
        let emptyBytes = Data(#"{"schemaVersion":1,"events":[]}"#.utf8)
        defaults.set(oldBytes, forKey: "remoteContent.events")
        FeedStubProtocol.eventPayload = emptyBytes
        FeedStubProtocol.failNews = true
        let service = RemoteContentService(defaults: defaults, session: session, baseURL: URL(string: "https://example.com/remote")!)
        precondition(service.remoteEvents.count == 1)
        await service.refreshIfNeeded(force: true, downloadFullFeed: true)
        precondition(service.remoteEvents.isEmpty, "Removed events must disappear even when news fails")
        precondition(service.eventsUpdatedInLastRefresh && service.lastError != nil)
        precondition(defaults.data(forKey: "remoteContent.events") == emptyBytes, "Empty feed must replace cached events")
        let restarted = RemoteContentService(defaults: defaults, session: session, baseURL: URL(string: "https://example.com/remote")!)
        precondition(restarted.remoteEvents.isEmpty, "Removed events must not reappear after restart")
        precondition(FeedStubProtocol.requests.allSatisfy { $0.url?.query?.contains("refresh=") == true }, "Forced fetches must bypass shared CDN caches")
        precondition(FeedStubProtocol.requests.allSatisfy { $0.value(forHTTPHeaderField: "Cache-Control") == "no-cache" })

        defaults.set(oldBytes, forKey: "remoteContent.events")
        FeedStubProtocol.eventPayload = Data(#"{"schemaVersion":99,"events":[]}"#.utf8)
        FeedStubProtocol.failNews = false
        let invalid = RemoteContentService(defaults: defaults, session: session, baseURL: URL(string: "https://example.com/remote")!)
        await invalid.refreshIfNeeded(force: true, downloadFullFeed: true)
        precondition(invalid.remoteEvents.count == 1 && !invalid.eventsUpdatedInLastRefresh, "Invalid event responses must preserve the valid cache")

        FeedStubProtocol.eventPayload = emptyBytes
        await invalid.refreshIfNeeded(force: true, downloadFullFeed: true)
        precondition(invalid.remoteEvents.isEmpty && invalid.lastError == nil)
        try invalid.beginEventTest(.fiveMinuteTest(at: Date()), profileID: UUID(), previousProfileID: nil)
        precondition(invalid.events.count == 1, "Explicit local test must still work")
        invalid.useDownloadedEvents()
        precondition(invalid.events.isEmpty && invalid.testEvent != nil, "Manual remote mode must hide the local overlay while preserving cleanup metadata")
        let remoteOnlyRestart = RemoteContentService(defaults: defaults, session: session, baseURL: URL(string: "https://example.com/remote")!)
        precondition(remoteOnlyRestart.events.isEmpty, "Paused local tests must not reappear after restart")
        let now = Date()
        let presentation = RemotePresentation(title: "News test", summary: "Test", image: nil, sections: [])
        let liveArticle = RemoteNews(id: "live-published", published: now.addingTimeInterval(-3600), showAsPopup: true, presentation: presentation)
        let scheduledArticle = RemoteNews(id: "live-scheduled", published: now.addingTimeInterval(3600), showAsPopup: true, presentation: presentation)
        FeedStubProtocol.newsPayload = try encoder.encode(RemoteNewsFeed(schemaVersion: 1, entries: [liveArticle, scheduledArticle]))
        await invalid.refreshIfNeeded(force: true, downloadFullFeed: true)
        precondition(invalid.news.count == 2 && invalid.latestNews?.id == liveArticle.id,
                     "Scheduled news must be downloaded but not visible before publication")
        invalid.markSeen(liveArticle)
        precondition(invalid.unreadPopup == nil && invalid.news.contains { $0.id == liveArticle.id },
                     "Reading news must suppress only its popup, not remove it from the archive")
        precondition(invalid.selectEnvironment(.development))
        let devArticle = RemoteNews(id: "dev-published", published: now.addingTimeInterval(-3600), showAsPopup: true, presentation: presentation)
        FeedStubProtocol.newsPayload = try encoder.encode(RemoteNewsFeed(schemaVersion: 1, entries: [devArticle]))
        await invalid.refreshIfNeeded(force: true, downloadFullFeed: true)
        precondition(invalid.latestNews?.id == devArticle.id && invalid.unreadPopup?.id == devArticle.id)
        precondition(invalid.selectEnvironment(.live))
        precondition(invalid.latestNews?.id == liveArticle.id && invalid.unreadPopup == nil,
                     "Returning to live must restore live news and its independent read state")
        FeedStubProtocol.newsPayload = try encoder.encode(RemoteNewsFeed(schemaVersion: 1, entries: [liveArticle, scheduledArticle]))
        await invalid.refreshIfNeeded(force: true, downloadFullFeed: true)
        let newsRestart = RemoteContentService(defaults: defaults, session: session, baseURL: URL(string: "https://example.com/remote")!)
        precondition(newsRestart.latestNews?.id == liveArticle.id && newsRestart.news.count == 2,
                     "Live news must survive a forced refresh and restart after switching feeds")
        precondition(newsRestart.unreadPopup == nil, "Seen news must remain read after restart")
        defaults.removeObject(forKey: "remoteContent.seenNewsIDs")
        defaults.set(liveArticle.id, forKey: "remoteContent.lastSeenNews")
        precondition(newsRestart.unreadPopup == nil, "Legacy read markers must suppress existing news")
        let olderArticle = RemoteNews(id: "older-article", published: now.addingTimeInterval(-7200), showAsPopup: true, presentation: presentation)
        newsRestart.markSeen(olderArticle)
        defaults.removeObject(forKey: "remoteContent.lastSeenNews")
        precondition(newsRestart.unreadPopup == nil, "Saving history must retain the migrated ID")
        let newerArticle = RemoteNews(id: "newer-article", published: now.addingTimeInterval(-60), showAsPopup: true, presentation: presentation)
        FeedStubProtocol.newsPayload = try encoder.encode(RemoteNewsFeed(schemaVersion: 1, entries: [olderArticle, liveArticle, newerArticle]))
        await newsRestart.refreshIfNeeded(force: true, downloadFullFeed: true)
        precondition(newsRestart.unreadPopup?.id == newerArticle.id, "New article IDs must still produce popups")
        newsRestart.markSeen(newerArticle)
        newsRestart.markSeen(olderArticle)
        precondition(newsRestart.unreadPopup == nil, "Opening older articles must not rearm the latest popup")
        defaults.set("old-build", forKey: "remoteContent.successfulBuild")
        defaults.set("old-build", forKey: "remoteContent.attemptedBuild")
        await newsRestart.refreshIfNeeded()
        precondition(defaults.string(forKey: "remoteContent.successfulBuild") != "old-build")
        precondition(newsRestart.unreadPopup == nil, "Build refreshes must preserve read history")
        FeedStubProtocol.newsPayload = try encoder.encode(RemoteNewsFeed(schemaVersion: 1, entries: [liveArticle, olderArticle]))
        await newsRestart.refreshIfNeeded(force: true, downloadFullFeed: true)
        precondition(newsRestart.latestNews?.id == liveArticle.id && newsRestart.unreadPopup == nil,
                     "Seen articles must not pop up when they become latest again")
        FeedStubProtocol.newsPayload = try encoder.encode(RemoteNewsFeed(schemaVersion: 1, entries: [olderArticle]))
        await newsRestart.refreshIfNeeded(force: true, downloadFullFeed: true)
        let historyRestart = RemoteContentService(defaults: defaults, session: session, baseURL: URL(string: "https://example.com/remote")!)
        precondition(historyRestart.latestNews?.id == olderArticle.id && historyRestart.unreadPopup == nil,
                     "Archive reads must stay read when they later become latest")
        precondition(historyRestart.selectEnvironment(.development))
        await historyRestart.refreshIfNeeded(force: true, downloadFullFeed: true)
        precondition(historyRestart.unreadPopup?.id == olderArticle.id, "Read history must be isolated by environment")
        let coldLaunchService = RemoteContentService(defaults: defaults, session: session,
            baseURL: URL(string: "https://example.com/remote")!)
        let beforeLaunch = FeedStubProtocol.requests.count
        await coldLaunchService.refreshIfNeeded()
        precondition(FeedStubProtocol.requests.count > beforeLaunch, "A fresh launch must fetch despite recent success")
        precondition(FeedStubProtocol.requests.suffix(2).allSatisfy { $0.url?.query?.contains("refresh=") == true })
        let afterLaunch = FeedStubProtocol.requests.count
        await coldLaunchService.refreshIfNeeded()
        precondition(FeedStubProtocol.requests.count == afterLaunch, "Duplicate launch/foreground callbacks must respect cooldown")
        await coldLaunchService.refreshIfNeeded(force: true)
        precondition(FeedStubProtocol.requests.count > afterLaunch, "Manual refresh must always fetch")
        // A partial snapshot must end only the deleted event, not keep it alive
        // until its original end timestamp or require an entirely empty feed.
        do {
            let removalSuite = "clashboard-event-removal-" + UUID().uuidString
            let removalDefaults = UserDefaults(suiteName: removalSuite)!
            defer { removalDefaults.removePersistentDomain(forName: removalSuite) }
            let start = Date().addingTimeInterval(-3600)
            let end = Date().addingTimeInterval(86400)
            let scRule = try JSONDecoder().decode(RemoteModifier.self, from: Data(
                #"{"categories":["builderVillage"],"dataIDs":[1000027,1000077],"onlySupercharges":true,"timeMultiplier":0.4,"costMultiplier":0.4}"#.utf8))
            let hammer = RemoteEvent(id: "hammer-stays", enabled: true, start: start, end: end,
                icon: nil, presentation: presentation, modifiers: [])
            let supercharges = RemoteEvent(id: "supercharges-removed", enabled: true, start: start, end: end,
                icon: nil, presentation: presentation, modifiers: [scRule])
            let twoEvents = try encoder.encode(RemoteEventFeed(schemaVersion: 2, events: [hammer, supercharges]))
            let hammerOnly = try encoder.encode(RemoteEventFeed(schemaVersion: 1, events: [hammer]))
            FeedStubProtocol.failNews = false
            FeedStubProtocol.eventPayload = twoEvents
            let live = RemoteContentService(defaults: removalDefaults, session: session,
                baseURL: URL(string: "https://example.com/remote")!)
            await live.refreshIfNeeded(force: true)
            precondition(live.currentEvent(id: supercharges.id) != nil)
            precondition(live.visibleEvents.map(\.id).contains(supercharges.id))
            precondition(live.upgradeFactor(category: "builderVillage", dataID: 1000027, townHall: 18,
                superchargeLevel: 1, cost: true) == 0.4)
            // Removal remains authoritative when the independent news fetch fails.
            FeedStubProtocol.eventPayload = hammerOnly
            FeedStubProtocol.failNews = true
            await live.refreshIfNeeded(force: true)
            precondition(live.eventsUpdatedInLastRefresh && live.lastError != nil)
            precondition(live.currentEvent(id: supercharges.id) == nil, "Open detail must stop its countdown immediately")
            precondition(live.currentEvent(id: hammer.id) != nil)
            precondition(live.visibleEvents.map(\.id) == [hammer.id])
            precondition(live.upgradeFactor(category: "builderVillage", dataID: 1000027, townHall: 18,
                superchargeLevel: 1, cost: true) == 1, "Removed event effects end just as on normal expiry")
            let restart = RemoteContentService(defaults: removalDefaults, session: session,
                baseURL: URL(string: "https://example.com/remote")!)
            precondition(restart.currentEvent(id: supercharges.id) == nil)
            // Keep the test in dev, then return to live. Neither environment may
            // resurrect the other's cached event or a detail's original snapshot.
            precondition(restart.selectEnvironment(.development))
            FeedStubProtocol.eventPayload = twoEvents
            FeedStubProtocol.failNews = false
            await restart.refreshIfNeeded(force: true)
            precondition(restart.currentEvent(id: "dev:" + supercharges.id) != nil)
            precondition(restart.currentEvent(id: supercharges.id) == nil)
            precondition(restart.selectEnvironment(.live))
            precondition(restart.currentEvent(id: "dev:" + supercharges.id) == nil)
            precondition(restart.currentEvent(id: supercharges.id) == nil)
            FeedStubProtocol.eventPayload = hammerOnly
            await restart.refreshIfNeeded(force: true)
            precondition(restart.visibleEvents.map(\.id) == [hammer.id])
            // Updating dates/disabled status also changes an already open detail.
            let disabled = RemoteEvent(id: hammer.id, enabled: false, start: start, end: end,
                icon: nil, presentation: presentation, modifiers: [])
            FeedStubProtocol.eventPayload = try encoder.encode(RemoteEventFeed(schemaVersion: 1, events: [disabled]))
            await restart.refreshIfNeeded(force: true)
            precondition(restart.currentEvent(id: hammer.id) == nil && restart.visibleEvents.isEmpty)
            let expired = RemoteEvent(id: hammer.id, enabled: true, start: start,
                end: Date().addingTimeInterval(-1), icon: nil, presentation: presentation, modifiers: [])
            FeedStubProtocol.eventPayload = try encoder.encode(RemoteEventFeed(schemaVersion: 1, events: [expired]))
            await restart.refreshIfNeeded(force: true)
            precondition(restart.currentEvent(id: hammer.id) == nil)
            print("Partial event removal passed: live card/detail ending, expired/disabled events, cost expiry, independent news failure, persisted removal and live/dev switching.")
        }
        print("Cold-launch integration passed: immediate fetch, server-cache bypass, duplicate callback suppression and manual refresh.")
        print("Lifetime news history checks passed: migration, new articles, older reads, build refresh, feed rollback, restart and environment isolation.")
        print("Remote refresh integration checks passed: authoritative removal, independent news failures, restart cache, invalid response fallback and forced cache bypass.")
        print("News checks passed: scheduled publication, archive/read state, dev/live cache switching, forced live refresh and restart.")
    }
}
