import Foundation
import Combine
import WidgetKit

class DataService: ObservableObject {
    static let appGroup = "group.Zachary-Buschmann.clash-widgets"

    private let apiKey: String?
    private let persistenceQueue = DispatchQueue(label: "com.zacharybuschmann.clashdash.persistence", qos: .utility)
    private var suppressPersistence = false
    private var refreshedProfilesThisLaunch: Set<UUID> = []
    private var activeRefreshTask: URLSessionDataTask?

    @Published var profiles: [PlayerAccount] = []
    @Published var selectedProfileID: UUID? {
        didSet {
            guard !suppressPersistence else { return }
            applyCurrentProfile()
            persistChanges(reloadWidgets: true)
            refreshCurrentProfileIfNeeded(force: false)
        }
    }
    @Published var profileName: String = "New Profile" {
        didSet {
            guard !suppressPersistence else { return }
            updateCurrentProfile { $0.displayName = profileName }
            persistChanges(reloadWidgets: false)
        }
    }
    @Published var activeUpgrades: [BuildingUpgrade] = [] {
        didSet {
            guard !suppressPersistence else { return }
            updateCurrentProfile { $0.activeUpgrades = activeUpgrades }
            persistChanges(reloadWidgets: true)
        }
    }
    @Published var playerTag: String = "" {
        didSet {
            guard !suppressPersistence else { return }
            updateCurrentProfile { $0.tag = playerTag }
            persistChanges(reloadWidgets: false)
        }
    }
    @Published var rawJSON: String = "" {
        didSet {
            guard !suppressPersistence else { return }
            updateCurrentProfile { $0.rawJSON = rawJSON }
            persistChanges(reloadWidgets: false)
        }
    }
    @Published var lastImportDate: Date? {
        didSet {
            guard !suppressPersistence else { return }
            updateCurrentProfile { $0.lastImportDate = lastImportDate }
            persistChanges(reloadWidgets: false)
        }
    }
    @Published var cachedProfile: PlayerProfile? {
        didSet {
            guard !suppressPersistence else { return }
            updateCurrentProfile {
                $0.cachedProfile = cachedProfile
                if let name = cachedProfile?.name, !name.isEmpty {
                    $0.displayName = name
                }
            }
            if let name = cachedProfile?.name, !name.isEmpty {
                profileName = name
            }
            persistChanges(reloadWidgets: false)
        }
    }
    @Published var isRefreshingProfile = false
    @Published var refreshErrorMessage: String?
    @Published var appearancePreference: AppearancePreference = .device {
        didSet {
            guard !suppressPersistence else { return }
            persistChanges(reloadWidgets: true)
        }
    }

    private var upgradeDurations: [Int: [Double]] = [:]
    private lazy var mapping: [Int: String] = Self.loadNameMapping()

    var currentProfile: PlayerAccount? {
        if let id = selectedProfileID,
           let profile = profiles.first(where: { $0.id == id }) {
            return profile
        }
        return profiles.first
    }

    init(apiKey: String? = nil) {
        self.apiKey = apiKey
        loadFromStorage()
        loadUpgradeDurations()
        saveToStorage()
        DispatchQueue.main.async { [weak self] in
            self?.refreshCurrentProfileIfNeeded(force: false)
        }
    }

    func selectProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        if selectedProfileID != id {
            selectedProfileID = id
        }
    }

    func addProfile(tag: String) {
        let normalizedTag = normalizeTag(tag)
        guard !normalizedTag.isEmpty else { return }
        let profile = PlayerAccount(displayName: defaultProfileName(), tag: normalizedTag)
        profiles.append(profile)
        selectedProfileID = profile.id
    }

    func deleteProfile(_ id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles.remove(at: index)

        if profiles.isEmpty {
            let fallback = PlayerAccount()
            profiles = [fallback]
            selectedProfileID = fallback.id
        } else if selectedProfileID == id {
            selectedProfileID = profiles.first?.id
        } else {
            persistChanges(reloadWidgets: true)
        }
    }

    func updateProfile(_ id: UUID, displayName: String, tag: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let normalizedTag = normalizeTag(tag)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        var mutableProfile = profiles[index]
        if trimmedName.isEmpty {
            mutableProfile.displayName = normalizedTag.isEmpty ? defaultProfileName() : normalizedTag
        } else {
            mutableProfile.displayName = trimmedName
        }
        mutableProfile.tag = normalizedTag
        profiles[index] = mutableProfile

        if id == selectedProfileID {
            suppressPersistence = true
            profileName = mutableProfile.displayName
            playerTag = normalizedTag
            suppressPersistence = false
            refreshCurrentProfile(force: true)
        }

        persistChanges(reloadWidgets: true)
    }

    func displayName(for profile: PlayerAccount) -> String {
        if !profile.displayName.isEmpty {
            return profile.displayName
        }
        return profile.tag.isEmpty ? "Profile" : profile.tag
    }

    func clearData() {
        activeUpgrades = []
        rawJSON = ""
        lastImportDate = nil
    }

    func pruneCompletedUpgrades(referenceDate: Date = Date()) {
        let remaining = activeUpgrades.filter { $0.endTime > referenceDate }
        if remaining.count != activeUpgrades.count {
            activeUpgrades = remaining
        }
    }

    func recoverFromBackup() {
        if !rawJSON.isEmpty {
            parseJSONFromClipboard(input: rawJSON)
        }
    }

    func refreshCurrentProfile(force: Bool = false) {
        refreshCurrentProfileIfNeeded(force: force)
    }

    private func refreshCurrentProfileIfNeeded(force: Bool) {
        guard let apiKey = apiKey, !apiKey.isEmpty else { return }
        guard let profile = currentProfile else { return }
        guard !profile.tag.isEmpty else { return }

        if force {
            refreshedProfilesThisLaunch.remove(profile.id)
        }

        if refreshedProfilesThisLaunch.contains(profile.id) { return }
        refreshedProfilesThisLaunch.insert(profile.id)
        performProfileRefresh(for: profile, apiKey: apiKey)
    }

    private func performProfileRefresh(for profile: PlayerAccount, apiKey: String) {
        let normalizedTag = normalizeTag(profile.tag)
        guard !normalizedTag.isEmpty else { return }
        guard let url = URL(string: "https://cocproxy.royaleapi.dev/v1/players/%23\(normalizedTag)") else {
            refreshErrorMessage = "Invalid player tag."
            return
        }

        var request = URLRequest(url: url)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        activeRefreshTask?.cancel()
        isRefreshingProfile = true
        refreshErrorMessage = nil

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRefreshingProfile = false

                if let error = error as NSError?, error.code == NSURLErrorCancelled {
                    return
                }

                if let error = error {
                    self.refreshErrorMessage = error.localizedDescription
                    return
                }

                guard let data = data else {
                    self.refreshErrorMessage = "Player data was empty."
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    let response = try decoder.decode(PlayerProfile.self, from: data)
                    let rawJSON = String(data: data, encoding: .utf8) ?? ""
                    self.storeProfileResponse(response, rawJSON: rawJSON, normalizedTag: normalizedTag)
                } catch {
                    self.refreshErrorMessage = "Failed to decode player profile."
                }
            }
        }

        activeRefreshTask = task
        task.resume()
    }

    private func storeProfileResponse(_ response: PlayerProfile, rawJSON: String, normalizedTag: String) {
        suppressPersistence = true
        cachedProfile = response
        suppressPersistence = false

        updateCurrentProfile { profile in
            profile.cachedProfile = response
            profile.apiProfileJSON = rawJSON
            profile.lastAPIFetchDate = Date()
            profile.tag = normalizedTag
            if profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || profile.displayName == profile.tag {
                profile.displayName = response.name
            }
        }

        profileName = response.name
        playerTag = normalizedTag
        refreshErrorMessage = nil
        persistChanges(reloadWidgets: false)
    }

    private func persistChanges(reloadWidgets: Bool) {
        guard !suppressPersistence else { return }
        saveToStorage()
        if reloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func saveToStorage() {
        ensureProfiles()
        let snapshot = PersistentStore.AppState(
            profiles: profiles,
            selectedProfileID: selectedProfileID,
            appearancePreference: appearancePreference
        )

        persistenceQueue.async {
            do {
                try PersistentStore.saveState(snapshot)
            } catch {
                #if DEBUG
                print("Failed to persist state file: \(error)")
                #endif
            }
        }

        let sharedDefaults = UserDefaults(suiteName: DataService.appGroup)
        guard let current = snapshot.currentProfile else { return }
        sharedDefaults?.set(current.displayName, forKey: "widget_simple_text")
        sharedDefaults?.set(current.tag, forKey: "saved_player_tag")
        sharedDefaults?.set(current.rawJSON, forKey: "saved_raw_json")
        sharedDefaults?.set(current.lastImportDate, forKey: "last_import_date")

        if let encoded = try? JSONEncoder().encode(current.activeUpgrades) {
            sharedDefaults?.set(encoded, forKey: "saved_upgrades")
            sharedDefaults?.synchronize()
            UserDefaults.standard.set(encoded, forKey: "saved_upgrades")
        }
    }

    private func loadFromStorage() {
        suppressPersistence = true
        defer {
            suppressPersistence = false
            applyCurrentProfile()
        }

        if let state = PersistentStore.loadState() {
            profiles = state.profiles
            selectedProfileID = state.selectedProfileID
            appearancePreference = state.appearancePreference
        } else {
            let sharedDefaults = UserDefaults(suiteName: DataService.appGroup)
            let storedName = sharedDefaults?.string(forKey: "widget_simple_text") ?? ""
            let tag = sharedDefaults?.string(forKey: "saved_player_tag") ?? ""
            let raw = sharedDefaults?.string(forKey: "saved_raw_json") ?? ""
            let lastDate = sharedDefaults?.object(forKey: "last_import_date") as? Date
            var upgrades: [BuildingUpgrade] = []
            if let data = sharedDefaults?.data(forKey: "saved_upgrades") ?? UserDefaults.standard.data(forKey: "saved_upgrades"),
               let decoded = try? JSONDecoder().decode([BuildingUpgrade].self, from: data) {
                upgrades = decoded
            }
            let profile = PlayerAccount(
                displayName: storedName.isEmpty ? (tag.isEmpty ? "Profile 1" : tag) : storedName,
                tag: tag,
                rawJSON: raw,
                lastImportDate: lastDate,
                activeUpgrades: upgrades
            )
            profiles = [profile]
            selectedProfileID = profile.id
        }

        ensureProfiles()
        if selectedProfileID == nil {
            selectedProfileID = profiles.first?.id
        }
    }

    private func applyCurrentProfile() {
        suppressPersistence = true
        defer { suppressPersistence = false }

        ensureProfiles()
        guard let profile = currentProfile else { return }

        profileName = profile.displayName
        playerTag = profile.tag
        rawJSON = profile.rawJSON
        lastImportDate = profile.lastImportDate
        activeUpgrades = profile.activeUpgrades
        cachedProfile = profile.cachedProfile
    }

    private func updateCurrentProfile(_ mutate: (inout PlayerAccount) -> Void) {
        ensureProfiles()
        guard var profile = currentProfile,
              let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        mutate(&profile)
        profiles[index] = profile
    }

    private func ensureProfiles() {
        guard profiles.isEmpty else { return }
        let profile = PlayerAccount()
        profiles = [profile]
        selectedProfileID = profile.id
    }

    private func defaultProfileName() -> String {
        let base = "Profile"
        var suffix = profiles.count + 1
        let existing = Set(profiles.map { $0.displayName })
        var candidate = "\(base) \(suffix)"
        while existing.contains(candidate) {
            suffix += 1
            candidate = "\(base) \(suffix)"
        }
        return candidate
    }

    private func normalizeTag(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
    }

    private func loadUpgradeDurations() {
        if let path = Bundle.main.path(forResource: "raw", ofType: "json", inDirectory: "upgrade_info"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            parseUpgradeDurationsJSON(data: data)
            return
        }

        if let folderURL = Bundle.main.url(forResource: "upgrade_info", withExtension: nil) {
            let fileURL = folderURL.appendingPathComponent("raw.json")
            if let data = try? Data(contentsOf: fileURL) {
                parseUpgradeDurationsJSON(data: data)
                return
            }
        }

        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: DataService.appGroup) {
            let fileURL = containerURL.appendingPathComponent("upgrade_info/raw.json")
            if let data = try? Data(contentsOf: fileURL) {
                parseUpgradeDurationsJSON(data: data)
            }
        }
    }

    private func parseUpgradeDurationsJSON(data: Data) {
        do {
            if let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                var parsed: [Int: [Double]] = [:]
                for (key, value) in dict {
                    if let id = Int(key), let arr = value as? [Any] {
                        var secs: [Double] = []
                        for v in arr {
                            if let n = v as? Double {
                                secs.append(n)
                            } else if let n = v as? Int {
                                secs.append(Double(n))
                            } else if let s = v as? String, let n = Double(s) {
                                secs.append(n)
                            }
                        }
                        if !secs.isEmpty {
                            parsed[id] = secs
                        }
                    }
                }
                if !parsed.isEmpty {
                    self.upgradeDurations = parsed
                }
            }
        } catch {
            print("Failed to parse upgrade durations: \(error)")
        }
    }

    func parseJSONFromClipboard(input: String) {
        guard let data = input.data(using: .utf8) else { return }
        let decoder = JSONDecoder()

        do {
            let export = try decoder.decode(CoCExport.self, from: data)
            let upgrades = collectUpgrades(from: export)
                .sorted(by: { $0.endTime < $1.endTime })
            let importTimestamp = Date()
            let normalizedTag = export.tag?.replacingOccurrences(of: "#", with: "").uppercased()

            suppressPersistence = true
            updateCurrentProfile { profile in
                profile.rawJSON = input
                profile.lastImportDate = importTimestamp
                profile.activeUpgrades = upgrades
                if let normalizedTag = normalizedTag, !normalizedTag.isEmpty {
                    profile.tag = normalizedTag
                    if profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        profile.displayName = normalizedTag
                    }
                }
            }
            suppressPersistence = false

            applyCurrentProfile()
            persistChanges(reloadWidgets: true)
        } catch {
            print("Failed to parse clipboard JSON: \(error)")
        }
    }

    private func collectUpgrades(from export: CoCExport) -> [BuildingUpgrade] {
        var upgrades: [BuildingUpgrade] = []
        let referenceDate = Date()

        if let list = export.buildings {
            upgrades.append(contentsOf: convert(list, category: .builderVillage, fallbackPrefix: "Building", referenceDate: referenceDate))
        }
        if let list = export.buildings2 {
            upgrades.append(contentsOf: convert(list, category: .builderBase, fallbackPrefix: "Builder Base Building", referenceDate: referenceDate))
        }
        if let list = export.traps {
            upgrades.append(contentsOf: convert(list, category: .builderVillage, fallbackPrefix: "Trap", referenceDate: referenceDate))
        }
        if let list = export.traps2 {
            upgrades.append(contentsOf: convert(list, category: .builderBase, fallbackPrefix: "Builder Base Trap", referenceDate: referenceDate))
        }
        if let list = export.heroes {
            upgrades.append(contentsOf: convert(list, category: .builderVillage, fallbackPrefix: "Hero", referenceDate: referenceDate))
        }
        if let list = export.heroes2 {
            upgrades.append(contentsOf: convert(list, category: .builderBase, fallbackPrefix: "Builder Base Hero", referenceDate: referenceDate))
        }
        if let list = export.pets {
            upgrades.append(contentsOf: convert(list, category: .pets, fallbackPrefix: "Pet", referenceDate: referenceDate))
        }
        if let list = export.units {
            upgrades.append(contentsOf: convert(list, category: .lab, fallbackPrefix: "Unit", referenceDate: referenceDate))
        }
        if let list = export.units2 {
            upgrades.append(contentsOf: convert(list, category: .lab, fallbackPrefix: "Secondary Unit", referenceDate: referenceDate))
        }
        if let list = export.spells {
            upgrades.append(contentsOf: convert(list, category: .lab, fallbackPrefix: "Spell", referenceDate: referenceDate))
        }

        return upgrades
    }

    private func convert(_ items: [Building], category: UpgradeCategory, fallbackPrefix: String, referenceDate: Date) -> [BuildingUpgrade] {
        convert(items, category: category, fallbackPrefix: fallbackPrefix, referenceDate: referenceDate) { item in
            (item.data, item.lvl, item.timer)
        }
    }

    private func convert(_ items: [Trap], category: UpgradeCategory, fallbackPrefix: String, referenceDate: Date) -> [BuildingUpgrade] {
        convert(items, category: category, fallbackPrefix: fallbackPrefix, referenceDate: referenceDate) { item in
            (item.data, item.lvl, item.timer)
        }
    }

    private func convert(_ items: [ExportHero], category: UpgradeCategory, fallbackPrefix: String, referenceDate: Date) -> [BuildingUpgrade] {
        convert(items, category: category, fallbackPrefix: fallbackPrefix, referenceDate: referenceDate) { item in
            (item.data, item.lvl, item.timer)
        }
    }

    private func convert(_ items: [ExportPet], category: UpgradeCategory, fallbackPrefix: String, referenceDate: Date) -> [BuildingUpgrade] {
        convert(items, category: category, fallbackPrefix: fallbackPrefix, referenceDate: referenceDate) { item in
            (item.data, item.lvl, item.timer)
        }
    }

    private func convert(_ items: [ExportUnit], category: UpgradeCategory, fallbackPrefix: String, referenceDate: Date) -> [BuildingUpgrade] {
        convert(items, category: category, fallbackPrefix: fallbackPrefix, referenceDate: referenceDate) { item in
            (item.data, item.lvl, item.timer)
        }
    }

    private func convert(_ items: [ExportSpell], category: UpgradeCategory, fallbackPrefix: String, referenceDate: Date) -> [BuildingUpgrade] {
        convert(items, category: category, fallbackPrefix: fallbackPrefix, referenceDate: referenceDate) { item in
            (item.data, item.lvl, item.timer)
        }
    }

    private func convert<T>(_ items: [T], category: UpgradeCategory, fallbackPrefix: String, referenceDate: Date, extractor: (T) -> (Int, Int, Int?)) -> [BuildingUpgrade] {
        items.compactMap { item in
            let (dataId, level, timer) = extractor(item)
            guard let timer = timer, timer > 0 else { return nil }
            return buildUpgrade(
                dataId: dataId,
                currentLevel: level,
                remainingSeconds: TimeInterval(timer),
                category: category,
                fallbackPrefix: fallbackPrefix,
                referenceDate: referenceDate
            )
        }
    }

    private func buildUpgrade(
        dataId: Int,
        currentLevel: Int,
        remainingSeconds: TimeInterval,
        category: UpgradeCategory,
        fallbackPrefix: String,
        referenceDate: Date
    ) -> BuildingUpgrade {
        let canonical = durationFor(dataId: dataId, fromLevel: currentLevel)
        let totalDuration = max(canonical ?? remainingSeconds, remainingSeconds)
        let end = referenceDate.addingTimeInterval(remainingSeconds)
        let start = end.addingTimeInterval(-totalDuration)

        return BuildingUpgrade(
            name: mapping[dataId] ?? "\(fallbackPrefix) (\(dataId))",
            targetLevel: currentLevel + 1,
            endTime: end,
            category: category,
            startTime: start,
            totalDuration: totalDuration
        )
    }

    private func durationFor(dataId: Int, fromLevel level: Int) -> TimeInterval? {
        guard let durations = upgradeDurations[dataId], !durations.isEmpty else { return nil }
        let index = min(max(level, 0), durations.count - 1)
        return durations[index]
    }

    private static func loadNameMapping() -> [Int: String] {
        func parse(data: Data) -> [Int: String]? {
            guard
                let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                !raw.isEmpty
            else { return nil }

            var output: [Int: String] = [:]
            for (key, value) in raw {
                guard let id = Int(key), let name = value as? String, !name.isEmpty else { continue }
                output[id] = name
            }
            return output.isEmpty ? nil : output
        }

        let bundle = Bundle.main
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: DataService.appGroup)
        let candidates: [URL?] = [
            bundle.url(forResource: "mapping", withExtension: "json", subdirectory: "upgrade_info"),
            bundle.url(forResource: "upgrade_info", withExtension: nil)?.appendingPathComponent("mapping.json"),
            bundle.url(forResource: "mapping", withExtension: "json"),
            container?.appendingPathComponent("upgrade_info/mapping.json")
        ]

        for candidate in candidates {
            guard let url = candidate, let data = try? Data(contentsOf: url), let parsed = parse(data: data) else { continue }
            return parsed
        }

        return [:]
    }

}
