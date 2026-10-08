import Foundation
import Combine
import SwiftUI
import UIKit
import CryptoKit

@MainActor
final class RemoteContentService: ObservableObject {
    static let shared = RemoteContentService()
    @Published private(set) var environment: RemoteContentEnvironment = .live
    @Published private(set) var remoteEvents: [RemoteEvent] = []
    @Published private(set) var testEvent: RemoteEvent?
    @Published private(set) var testProfileID: UUID?
    private(set) var profileBeforeTest: UUID?
    var events: [RemoteEvent] { remoteEvents.map { environment.scopedEvent($0) } + (environment == .live ? (testEvent.map { [$0] } ?? []) : []) }
    @Published private(set) var news: [RemoteNews] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var launchRefreshResolved = false
    @Published private(set) var now = Date()
    private let defaults: UserDefaults
    private var timer: AnyCancellable?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    // Set this Info.plist key before shipping. No credentials belong in a public feed.
    var baseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RemoteContentBaseURL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return environment.baseURL(liveURL: url)
    }
    var visibleEvents: [RemoteEvent] { events.filter { $0.isVisible(at: now) }.sorted { $0.start < $1.start } }
    var latestNews: RemoteNews? { news.first { $0.published <= now } }
    var unreadPopup: RemoteNews? {
        guard let item = latestNews, item.showAsPopup,
              defaults.string(forKey: environment.cacheKey("lastSeenNews")) != item.id else { return nil }
        return item
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        environment = defaults.string(forKey: "remoteContent.environment").flatMap(RemoteContentEnvironment.init(rawValue:)) ?? .live
        loadEnvironmentCache()
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
        if !force {
            if hasCache, let lastSuccess, now.timeIntervalSince(lastSuccess) >= 0,
               now.timeIntervalSince(lastSuccess) < 86400 { return }
            // Brief backoff for offline/invalid responses; don't wait a day after failure.
            if let lastAttempt, now.timeIntervalSince(lastAttempt) >= 0,
               now.timeIntervalSince(lastAttempt) < 900 { return }
        }
        isRefreshing = true
        defaults.set(now, forKey: environment.cacheKey("lastAttempt"))
        defer { isRefreshing = false }
        do {
            async let eventData = fetch(baseURL.appendingPathComponent("latest_event.json"))
            async let latestData = fetch(baseURL.appendingPathComponent("latest_news.json"))
            let (eventBytes, latestBytes) = try await (eventData, latestData)
            let eventFeed = try decoder.decode(RemoteEventFeed.self, from: eventBytes)
            try eventFeed.validate()
            let latest = try decoder.decode(LatestRemoteNews.self, from: latestBytes)
            guard latest.schemaVersion == 1 else { throw RemoteContentError.invalidPayload }
            var feed = RemoteNewsFeed(schemaVersion: 1, entries: news)
            if downloadFullFeed || !hasCache || (latest.id != nil && !news.contains(where: { $0.id == latest.id })) {
                feed = try decoder.decode(RemoteNewsFeed.self, from: await fetch(baseURL.appendingPathComponent("news_feed.json")))
                try feed.validate()
                if let id = latest.id, !feed.entries.contains(where: { $0.id == id }) { throw RemoteContentError.invalidPayload }
            }
            // Commit together so a partially published or malformed feed preserves the cache.
            let newsBytes = try encoder.encode(feed)
            defaults.set(eventBytes, forKey: environment.cacheKey("events"))
            defaults.set(newsBytes, forKey: environment.cacheKey("news"))
            remoteEvents = eventFeed.events
            news = feed.entries.sorted { $0.published > $1.published }
            defaults.set(Date(), forKey: environment.cacheKey("lastSuccess"))
            lastError = nil
        } catch {
            lastError = "Unable to refresh news and events. Saved content is still available."
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 2_000_000 else { throw RemoteContentError.httpStatus }
        return data
    }

    func eventApplies(_ event: RemoteEvent, to profileID: UUID?) -> Bool {
        guard environment == .live, let testEvent else { return true }
        if event.id == testEvent.id { return profileID == testProfileID }
        return profileID != testProfileID
    }

    func visibleEvents(for profileID: UUID?) -> [RemoteEvent] {
        visibleEvents.filter { eventApplies($0, to: profileID) }
    }

    func beginEventTest(_ event: RemoteEvent, profileID: UUID, previousProfileID: UUID?) throws {
        try RemoteEventFeed(schemaVersion: 1, events: [event]).validate()
        defaults.set(try encoder.encode(event), forKey: "remoteContent.testEvent")
        defaults.set(profileID.uuidString, forKey: "remoteContent.testProfile")
        defaults.set(previousProfileID?.uuidString, forKey: "remoteContent.profileBeforeTest")
        profileBeforeTest = previousProfileID
        testProfileID = profileID
        testEvent = event
        now = Date()
    }

    func endEventTest() {
        testEvent = nil
        testProfileID = nil
        profileBeforeTest = nil
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
