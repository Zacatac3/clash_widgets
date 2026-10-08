import Foundation
import Combine
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
import CryptoKit

@MainActor
final class RemoteContentService: ObservableObject {
    static let shared = RemoteContentService()
    @Published private(set) var environment: RemoteContentEnvironment = .live
    @Published private(set) var remoteEvents: [RemoteEvent] = []
    @Published private(set) var testEvent: RemoteEvent?
    @Published private(set) var localTestEnabled = true
    @Published private(set) var testProfileID: UUID?
    private(set) var profileBeforeTest: UUID?
    var events: [RemoteEvent] { remoteEvents.map { environment.scopedEvent($0) } + (environment == .live && localTestEnabled ? (testEvent.map { [$0] } ?? []) : []) }
    @Published private(set) var news: [RemoteNews] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var launchRefreshResolved = false
    @Published private(set) var eventsUpdatedInLastRefresh = false
    @Published private(set) var now = Date()
    private let defaults: UserDefaults
    private let session: URLSession
    private let configuredBaseURL: URL?
    private var timer: AnyCancellable?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    // Set this Info.plist key before shipping. No credentials belong in a public feed.
    var baseURL: URL? {
        let bundledURL = (Bundle.main.object(forInfoDictionaryKey: "RemoteContentBaseURL") as? String).flatMap(URL.init(string:))
        guard let url = configuredBaseURL ?? bundledURL, url.scheme == "https", url.host != nil else { return nil }
        return environment.baseURL(liveURL: url)
    }
    var visibleEvents: [RemoteEvent] { events.filter { $0.isVisible(at: now) }.sorted { $0.start < $1.start } }
    var latestNews: RemoteNews? { news.first { $0.published <= now } }
    var unreadPopup: RemoteNews? {
        guard let item = latestNews, item.showAsPopup,
              defaults.string(forKey: environment.cacheKey("lastSeenNews")) != item.id else { return nil }
        return item
    }

    init(defaults: UserDefaults = .standard, session: URLSession = .shared, baseURL: URL? = nil) {
        self.defaults = defaults
        self.session = session
        self.configuredBaseURL = baseURL
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        environment = defaults.string(forKey: "remoteContent.environment").flatMap(RemoteContentEnvironment.init(rawValue:)) ?? .live
        loadEnvironmentCache()
        localTestEnabled = defaults.object(forKey: "remoteContent.localTestEnabled") as? Bool ?? true
        if let data = defaults.data(forKey: "remoteContent.testEvent"),
           let event = try? decoder.decode(RemoteEvent.self, from: data),
           let rawID = defaults.string(forKey: "remoteContent.testProfile"), let profileID = UUID(uuidString: rawID) {
            testEvent = event
            testProfileID = profileID
            profileBeforeTest = defaults.string(forKey: "remoteContent.profileBeforeTest").flatMap(UUID.init(uuidString:))
        }
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] in self?.now = $0 }
    }

    private func loadEnvironmentCache() {
        remoteEvents = []
        news = []
        if let data = defaults.data(forKey: environment.cacheKey("events")),
           let feed = try? decoder.decode(RemoteEventFeed.self, from: data),
           (try? feed.validate()) != nil { remoteEvents = feed.events }
        if let data = defaults.data(forKey: environment.cacheKey("news")),
           let feed = try? decoder.decode(RemoteNewsFeed.self, from: data),
           (try? feed.validate()) != nil { news = feed.entries.sorted { $0.published > $1.published } }
    }

    @discardableResult
    func selectEnvironment(_ value: RemoteContentEnvironment) -> Bool {
        guard !isRefreshing else { return false }
        guard environment != value else { return true }
        environment = value
        defaults.set(value.rawValue, forKey: "remoteContent.environment")
        lastError = nil
        launchRefreshResolved = false
        now = Date()
        loadEnvironmentCache()
        return true
    }

    func markSeen(_ item: RemoteNews) {
        // Reading an older article must not make the latest article unread again.
        if item.id == latestNews?.id { defaults.set(item.id, forKey: environment.cacheKey("lastSeenNews")) }
        objectWillChange.send()
    }

    func refreshIfNeeded(force: Bool = false, downloadFullFeed: Bool = false) async {
        now = Date()
        guard !isRefreshing else { return }
        defer { launchRefreshResolved = true }
        guard let baseURL else { return }
        let lastAttempt = defaults.object(forKey: environment.cacheKey("lastAttempt")) as? Date
        let lastSuccess = defaults.object(forKey: environment.cacheKey("lastSuccess")) as? Date
        let hasCache = defaults.data(forKey: environment.cacheKey("events")) != nil && defaults.data(forKey: environment.cacheKey("news")) != nil
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let currentBuild = "\(version) (\(build))"
        let successfulBuild = defaults.string(forKey: environment.cacheKey("successfulBuild"))
        let needsBuildRefresh = successfulBuild != currentBuild
        guard RemoteContentRefreshPolicy.shouldRefresh(now: now, force: force, hasCache: hasCache,
            lastSuccess: lastSuccess, lastAttempt: lastAttempt, currentBuild: currentBuild,
            successfulBuild: successfulBuild,
            attemptedBuild: defaults.string(forKey: environment.cacheKey("attemptedBuild"))) else { return }
        isRefreshing = true
        eventsUpdatedInLastRefresh = false
        defaults.set(now, forKey: environment.cacheKey("lastAttempt"))
        defaults.set(currentBuild, forKey: environment.cacheKey("attemptedBuild"))
        defer { isRefreshing = false }
        do {
            let bypassServerCache = force || needsBuildRefresh
            async let eventData = fetch(baseURL.appendingPathComponent("latest_event.json"), bypassServerCache: bypassServerCache)
            async let latestData = fetch(baseURL.appendingPathComponent("latest_news.json"), bypassServerCache: bypassServerCache)
            let eventBytes = try await eventData
            let eventFeed = try decoder.decode(RemoteEventFeed.self, from: eventBytes)
            try eventFeed.validate()
            // A valid event feed is authoritative, including an empty events array.
            // Commit it before news so unrelated news failures cannot retain removed events.
            defaults.set(eventBytes, forKey: environment.cacheKey("events"))
            remoteEvents = eventFeed.events
            eventsUpdatedInLastRefresh = true
            let latest = try decoder.decode(LatestRemoteNews.self, from: await latestData)
            guard latest.schemaVersion == 1 else { throw RemoteContentError.invalidPayload }
            var feed = RemoteNewsFeed(schemaVersion: 1, entries: news)
            if downloadFullFeed || needsBuildRefresh || !hasCache || (latest.id != nil && !news.contains(where: { $0.id == latest.id })) {
                feed = try decoder.decode(RemoteNewsFeed.self, from: await fetch(baseURL.appendingPathComponent("news_feed.json"), bypassServerCache: bypassServerCache))
                try feed.validate()
                if let id = latest.id, !feed.entries.contains(where: { $0.id == id }) { throw RemoteContentError.invalidPayload }
            }
            // News is committed together with its pointer validation.
            let newsBytes = try encoder.encode(feed)
            defaults.set(newsBytes, forKey: environment.cacheKey("news"))
            news = feed.entries.sorted { $0.published > $1.published }
            defaults.set(Date(), forKey: environment.cacheKey("lastSuccess"))
            defaults.set(currentBuild, forKey: environment.cacheKey("successfulBuild"))
            lastError = nil
        } catch {
            lastError = eventsUpdatedInLastRefresh
                ? "Events updated (\(remoteEvents.count) downloaded). News could not be refreshed; saved news is still available."
                : "Unable to refresh events. Saved events and news are still available."
        }
    }

    private func fetch(_ url: URL, bypassServerCache: Bool = false) async throws -> Data {
        var requestURL = url
        if bypassServerCache, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "refresh", value: UUID().uuidString)]
            requestURL = components.url ?? url
        }
        var request = URLRequest(url: requestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if bypassServerCache { request.setValue("no-cache", forHTTPHeaderField: "Cache-Control") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 2_000_000 else { throw RemoteContentError.httpStatus }
        return data
    }

    func eventApplies(_ event: RemoteEvent, to profileID: UUID?) -> Bool {
        guard environment == .live, localTestEnabled, let testEvent else { return true }
        if event.id == testEvent.id { return profileID == testProfileID }
        return profileID != testProfileID
    }

    func visibleEvents(for profileID: UUID?) -> [RemoteEvent] {
        visibleEvents.filter { eventApplies($0, to: profileID) }
    }

    func useDownloadedEvents() {
        localTestEnabled = false
        defaults.set(false, forKey: "remoteContent.localTestEnabled")
    }

    func beginEventTest(_ event: RemoteEvent, profileID: UUID, previousProfileID: UUID?) throws {
        try RemoteEventFeed(schemaVersion: 1, events: [event]).validate()
        defaults.set(try encoder.encode(event), forKey: "remoteContent.testEvent")
        defaults.set(profileID.uuidString, forKey: "remoteContent.testProfile")
        defaults.set(previousProfileID?.uuidString, forKey: "remoteContent.profileBeforeTest")
        profileBeforeTest = previousProfileID
        testProfileID = profileID
        localTestEnabled = true
        defaults.set(true, forKey: "remoteContent.localTestEnabled")
        testEvent = event
        now = Date()
    }

    func endEventTest() {
        testEvent = nil
        testProfileID = nil
        profileBeforeTest = nil
        localTestEnabled = true
        defaults.removeObject(forKey: "remoteContent.localTestEnabled")
        defaults.removeObject(forKey: "remoteContent.testEvent")
        defaults.removeObject(forKey: "remoteContent.testProfile")
        defaults.removeObject(forKey: "remoteContent.profileBeforeTest")
    }

    func wallFactor(townHall: Int, profileID: UUID? = nil) -> Double {
        events.filter { $0.isActive(at: now) && eventApplies($0, to: profileID) }.flatMap(\.modifiers)
            .filter { $0.matches(category: "walls", dataID: nil, townHall: townHall) }
            .compactMap(\.wallCostMultiplier).min() ?? 1
    }

}

#if canImport(UIKit)
// HTTPS images use a bounded disk cache and render only after image decoding succeeds.
actor RemoteImageCache {
    static let shared = RemoteImageCache()
    func data(for url: URL) async throws -> Data {
        guard url.scheme == "https", url.host != nil else { throw RemoteContentError.invalidURL }
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RemoteContentImages", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = folder.appendingPathComponent(key)
        if let data = try? Data(contentsOf: file), UIImage(data: data) != nil { return data }
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 8_000_000, let decoded = UIImage(data: data),
              decoded.size.width <= 8192, decoded.size.height <= 8192 else { throw RemoteContentError.invalidPayload }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        if files.count >= 40 {
            let ordered = files.sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            for old in ordered.prefix(files.count - 39) { try? FileManager.default.removeItem(at: old) }
        }
        try data.write(to: file, options: .atomic)
        return data
    }
}

#endif
