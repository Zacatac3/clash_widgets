import Foundation
import Combine
import WidgetKit

class DataService: ObservableObject {
    static let appGroup = "group.Zachary-Buschmann.clash-widgets"

    private let apiKey: String?
    private let persistenceQueue = DispatchQueue(label: "com.zacharybuschmann.clashdash.persistence", qos: .utility)
    private let notificationManager = NotificationManager.shared
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
            scheduleUpgradeNotifications()
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
    @Published var refreshCooldownMessage: String?
    @Published var appearancePreference: AppearancePreference = .device {
        didSet {
            guard !suppressPersistence else { return }
            persistChanges(reloadWidgets: true)
        }
    }
    @Published var notificationSettings: NotificationSettings = .default {
        didSet {
            guard !suppressPersistence else { return }
            updateCurrentProfile { $0.notificationSettings = notificationSettings }
            handleNotificationSettingsChange(from: oldValue)
        }
    }
    @Published var builderCount: Int = 5 {
        didSet {
            guard !suppressPersistence else { return }
            updateCurrentProfile { $0.builderCount = builderCount }
            persistChanges(reloadWidgets: false)
        }
    }
    @Published var builderApprenticeLevel: Int = 0 {
        didSet {
            guard !suppressPersistence else { return }
            updateCurrentProfile { $0.builderApprenticeLevel = builderApprenticeLevel }
            persistChanges(reloadWidgets: false)
        }
    }
    @Published var labAssistantLevel: Int = 0 {
        didSet {
            guard !suppressPersistence else { return }
            updateCurrentProfile { $0.labAssistantLevel = labAssistantLevel }
            persistChanges(reloadWidgets: false)
        }
    }
    @Published var alchemistLevel: Int = 0 {
        didSet {
            guard !suppressPersistence else { return }
            updateCurrentProfile { $0.alchemistLevel = alchemistLevel }
            persistChanges(reloadWidgets: false)
        }
    }
    @Published var goldPassBoost: Int = 0 {
        didSet {
            guard !suppressPersistence else { return }
            updateCurrentProfile { $0.goldPassBoost = goldPassBoost }
            persistChanges(reloadWidgets: false)
        }
    }

    private var upgradeDurations: [Int: [Double]] = [:]
    private lazy var mapping: [Int: String] = Self.loadNameMapping()
    var cachedParsedBuildings: [ParsedBuilding]?
    var cachedTownHallLevels: [TownHallLevelCounts]?
    var cachedBuildingNameToId: [String: Int]?
    var cachedParsedUnits: [String: [Int: ParsedUnitData]] = [:]

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
        cachedParsedBuildings = loadParsedBuildingsData()
        cachedTownHallLevels = loadTownHallLevelsData()
        cachedBuildingNameToId = loadBuildingNameToIdData()
        saveToStorage()
        DispatchQueue.main.async { [weak self] in
            self?.refreshCurrentProfileIfNeeded(force: false)
        }
    }

    func remainingBuildingUpgrades(for townHallLevel: Int) -> [RemainingBuildingUpgrade] {
        guard townHallLevel > 0 else { return [] }
        guard let raw = currentProfile?.rawJSON, !raw.isEmpty else { return [] }
        guard let data = raw.data(using: .utf8),
              let export = try? JSONDecoder().decode(CoCExport.self, from: data) else { return [] }
        guard let buildingList = export.buildings, !buildingList.isEmpty else { return [] }

        let parsedBuildings = cachedParsedBuildings ?? loadParsedBuildingsData() ?? []
        let byId = makeParsedBuildingsByIdMap(parsedBuildings)

        var results: [RemainingBuildingUpgrade] = []
        for building in buildingList {
            guard let parsed = byId[building.data] else { continue }
            let available = parsed.levels.filter { level in
                guard let requiredTH = level.townHallLevel else { return true }
                return requiredTH <= townHallLevel
            }
            guard let maxAvailable = available.map({ $0.level }).max() else { continue }
            let currentLevel = building.lvl
            let targetLevel = currentLevel + 1
            guard currentLevel < maxAvailable else { continue }
            guard let nextLevel = available.first(where: { $0.level == targetLevel }) else { continue }

            let name = mapping[building.data] ?? parsed.internalName
            let buildTime = nextLevel.buildTimeSeconds ?? 0
            let buildResource = nextLevel.buildResource ?? ""
            let buildCost = nextLevel.buildCost ?? 0
            results.append(
                RemainingBuildingUpgrade(
                    id: building.data,
                    name: name,
                    currentLevel: currentLevel,
                    targetLevel: targetLevel,
                    buildTimeSeconds: buildTime,
                    buildResource: buildResource,
                    buildCost: buildCost
                )
            )
        }

        return results.sorted { $0.name < $1.name }
    }

    func loadParsedBuildingsData() -> [ParsedBuilding]? {
        let folders = Self.candidateFolderURLs(named: "parsed_json_files")
        let decoder = JSONDecoder()
        for folder in folders {
            let fileURL = folder.appendingPathComponent("buildings.json")
            if let data = try? Data(contentsOf: fileURL),
               let parsed = try? decoder.decode([ParsedBuilding].self, from: data) {
                return parsed
            }
        }
        return nil
    }

    func makeParsedBuildingsByIdMap(_ buildings: [ParsedBuilding]) -> [Int: ParsedBuilding] {
        var output: [Int: ParsedBuilding] = [:]
        for building in buildings {
            output[building.id] = building
        }
        return output
    }

    func loadTownHallLevelsData() -> [TownHallLevelCounts]? {
        let folders = Self.candidateFolderURLs(named: "parsed_json_files")
        for folder in folders {
            let fileURL = folder.appendingPathComponent("townhall_levels.json")
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            guard let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else { continue }
            let parsed = raw.compactMap { entry -> TownHallLevelCounts? in
                guard let level = entry["townHallLevel"] as? Int else { return nil }
                guard let countsRaw = entry["counts"] as? [String: Any] else { return nil }
                var counts: [String: Int] = [:]
                for (key, value) in countsRaw {
                    if let n = value as? Int {
                        counts[key] = n
                    } else if let n = value as? Double {
                        counts[key] = Int(n)
                    } else if let s = value as? String, let n = Int(s) {
                        counts[key] = n
                    }
                }
                return TownHallLevelCounts(level: level, counts: counts)
            }
            if !parsed.isEmpty {
                return parsed
            }
        }
        return nil
    }

    func loadBuildingNameToIdData() -> [String: Int]? {
        let folders = Self.candidateFolderURLs(named: "json_maps")
        for folder in folders {
            let fileURL = folder.appendingPathComponent("buildings_json_map.json")
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            guard let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { continue }
            var output: [String: Int] = [:]
            for (_, value) in raw {
                guard let entry = value as? [String: Any] else { continue }
                let idValue = entry["id"]
                let id: Int?
                if let n = idValue as? Int { id = n }
                else if let n = idValue as? Double { id = Int(n) }
                else if let s = idValue as? String { id = Int(s) }
                else { id = nil }
                guard let resolvedId = id else { continue }

                let display = (entry["displayName"] as? String)?.lowercased()
                let internalName = (entry["internalName"] as? String)?.lowercased()
                if let display, !display.isEmpty { output[display] = resolvedId }
                if let internalName, !internalName.isEmpty { output[internalName] = resolvedId }
            }
            if !output.isEmpty {
                return output
            }
        }
        return nil
    }

    func loadParsedUnits(fileName: String) -> [Int: ParsedUnitData] {
        if let cached = cachedParsedUnits[fileName] {
            return cached
        }
        let folders = Self.candidateFolderURLs(named: "parsed_json_files")
        for folder in folders {
            let fileURL = folder.appendingPathComponent(fileName)
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            guard let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else { continue }
            var output: [Int: ParsedUnitData] = [:]
            for entry in raw {
                guard let id = entry["id"] as? Int else { continue }
                let internalName = (entry["internalName"] as? String) ?? ""
                let levels = (entry["levels"] as? [[String: Any]] ?? []).compactMap { level -> ParsedUnitLevelData? in
                    guard let levelNumber = level["level"] as? Int else { return nil }
                    let time = parseInt(level["upgradeTimeSeconds"]) ?? 0
                    let cost = parseInt(level["UpgradeCost"]) ?? 0
                    let resource = (level["UpgradeResource"] as? String) ?? ""
                    let lab = parseInt(level["LaboratoryLevel"]) ?? parseInt(level["RequiredTownHallLevel"]) ?? 0
                    return ParsedUnitLevelData(
                        level: levelNumber,
                        upgradeTimeSeconds: time,
                        upgradeCost: cost,
                        upgradeResource: resource,
                        laboratoryLevel: lab
                    )
                }
                output[id] = ParsedUnitData(id: id, name: internalName, levels: levels)
            }
            cachedParsedUnits[fileName] = output
            return output
        }
        return [:]
    }

    func parseInt(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? Double { return Int(n) }
        if let s = value as? String { return Int(s) }
        return nil
    }

    func selectProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        if selectedProfileID != id {
            selectedProfileID = id
        }
    }

    @discardableResult
    func addProfile(
        tag: String,
        builderCount: Int = 5,
        builderApprenticeLevel: Int = 0,
        labAssistantLevel: Int = 0,
        alchemistLevel: Int = 0,
        goldPassBoost: Int = 0
    ) -> UUID {
        let normalizedTag = normalizeTag(tag)
        guard !normalizedTag.isEmpty else { return currentProfile?.id ?? UUID() }
        let profile = PlayerAccount(
            displayName: defaultProfileName(),
            tag: normalizedTag,
            builderCount: builderCount,
            builderApprenticeLevel: builderApprenticeLevel,
            labAssistantLevel: labAssistantLevel,
            alchemistLevel: alchemistLevel,
            goldPassBoost: goldPassBoost
        )
        profiles.append(profile)
        selectedProfileID = profile.id
        return profile.id
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

    func triggerDebugNotification() {
        guard notificationSettings.notificationsEnabled else { return }
        notificationManager.scheduleDebugNotification()
    }

    func requestNotificationAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        notificationManager.ensureAuthorization(promptIfNeeded: true) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    func resetToFactory() {
        notificationManager.removeAllUpgradeNotifications()
        refreshedProfilesThisLaunch.removeAll()

        suppressPersistence = true
        let freshProfile = PlayerAccount()
        profiles = [freshProfile]
        selectedProfileID = freshProfile.id
        appearancePreference = .device
        notificationSettings = freshProfile.notificationSettings
        builderCount = freshProfile.builderCount
        builderApprenticeLevel = freshProfile.builderApprenticeLevel
        labAssistantLevel = freshProfile.labAssistantLevel
        alchemistLevel = freshProfile.alchemistLevel
        profileName = freshProfile.displayName
        playerTag = ""
        rawJSON = ""
        lastImportDate = nil
        activeUpgrades = []
        cachedProfile = nil
        refreshErrorMessage = nil
        suppressPersistence = false

        applyCurrentProfile()
        PersistentStore.clearState()
        saveToStorage()
    }

    func refreshCurrentProfile(force: Bool = false) {
        refreshCurrentProfileIfNeeded(force: force)
    }

    func fetchProfilePreview(tag: String, completion: @escaping (PlayerProfile?) -> Void) {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            completion(nil)
            return
        }
        let normalizedTag = normalizeTag(tag)
        guard !normalizedTag.isEmpty else {
            completion(nil)
            return
        }
        guard let url = URL(string: "https://cocproxy.royaleapi.dev/v1/players/%23\(normalizedTag)") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard error == nil, let data else {
                    completion(nil)
                    return
                }
                do {
                    let profile = try JSONDecoder().decode(PlayerProfile.self, from: data)
                    completion(profile)
                } catch {
                    completion(nil)
                }
            }
        }.resume()
    }

    private func refreshCurrentProfileIfNeeded(force: Bool) {
        guard let apiKey = apiKey, !apiKey.isEmpty else { return }
        guard let profile = currentProfile else { return }
        guard !profile.tag.isEmpty else { return }

        if let lastFetch = profile.lastAPIFetchDate {
            let elapsed = Date().timeIntervalSince(lastFetch)
            let cooldown: TimeInterval = 180
            if elapsed < cooldown {
                let remaining = cooldown - elapsed
                let message = "Please wait \(formatCooldown(remaining)) to refresh again"
                showRefreshCooldown(message)
                return
            }
        }

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
        refreshCooldownMessage = nil

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
        refreshCooldownMessage = nil
        persistChanges(reloadWidgets: false)
    }

    private func showRefreshCooldown(_ message: String) {
        refreshCooldownMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            if self.refreshCooldownMessage == message {
                self.refreshCooldownMessage = nil
            }
        }
    }

    private func formatCooldown(_ remaining: TimeInterval) -> String {
        let totalSeconds = max(Int(remaining.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        }
        return String(format: "%ds", seconds)
    }

    private func persistChanges(reloadWidgets: Bool) {
        guard !suppressPersistence else { return }
        saveToStorage()
        if reloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func handleNotificationSettingsChange(from oldValue: NotificationSettings) {
        if notificationSettings.notificationsEnabled && !oldValue.notificationsEnabled {
            notificationManager.ensureAuthorization(promptIfNeeded: true) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.persistChanges(reloadWidgets: false)
                    self.scheduleUpgradeNotifications()
                } else {
                    DispatchQueue.main.async {
                        self.suppressPersistence = true
                        self.notificationSettings = oldValue
                        self.suppressPersistence = false
                    }
                }
            }
        } else {
            persistChanges(reloadWidgets: false)
            scheduleUpgradeNotifications()
        }
    }

    private func scheduleUpgradeNotifications() {
        notificationManager.syncNotifications(for: activeUpgrades, settings: notificationSettings)
    }

    private func saveToStorage() {
        ensureProfiles()
        let snapshot = PersistentStore.AppState(
            profiles: profiles,
            selectedProfileID: selectedProfileID,
            appearancePreference: appearancePreference,
            notificationSettings: nil
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
            if let legacySettings = state.notificationSettings,
               profiles.allSatisfy({ $0.notificationSettings == .default }) {
                profiles = profiles.map { profile in
                    var updated = profile
                    updated.notificationSettings = legacySettings
                    return updated
                }
            }
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
        defer {
            suppressPersistence = false
            scheduleUpgradeNotifications()
        }

        ensureProfiles()
        guard let profile = currentProfile else { return }

        profileName = profile.displayName
        playerTag = profile.tag
        rawJSON = profile.rawJSON
        lastImportDate = profile.lastImportDate
        activeUpgrades = profile.activeUpgrades
        cachedProfile = profile.cachedProfile
        notificationSettings = profile.notificationSettings
        builderCount = profile.builderCount
        builderApprenticeLevel = profile.builderApprenticeLevel
        labAssistantLevel = profile.labAssistantLevel
        alchemistLevel = profile.alchemistLevel
        goldPassBoost = profile.goldPassBoost
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
        if let parsed = Self.loadDurationsFromParsedJSON(), !parsed.isEmpty {
            upgradeDurations = parsed
            return
        }

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

    static func candidateFolderURLs(named folderName: String) -> [URL] {
        let bundle = Bundle.main
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: DataService.appGroup)
        var urls: [URL] = []

        if let url = bundle.url(forResource: folderName, withExtension: nil) {
            urls.append(url)
        }
        if let upgradeInfo = bundle.url(forResource: "upgrade_info", withExtension: nil) {
            urls.append(upgradeInfo.appendingPathComponent(folderName))
        }
        if let container = container {
            urls.append(container.appendingPathComponent(folderName))
            urls.append(container.appendingPathComponent("upgrade_info/\(folderName)"))
        }
        return urls
    }

    private static func loadDurationsFromParsedJSON() -> [Int: [Double]]? {
        let files: [(String, String)] = [
            ("buildings.json", "buildTimeSeconds"),
            ("characters.json", "upgradeTimeSeconds"),
            ("heroes.json", "upgradeTimeSeconds"),
            ("pets.json", "upgradeTimeSeconds"),
            ("spells.json", "upgradeTimeSeconds"),
            ("traps.json", "buildTimeSeconds"),
            ("weapons.json", "buildTimeSeconds"),
            ("mini_levels.json", "buildTimeSeconds"),
            ("seasonal_defense_modules.json", "buildTimeSeconds")
        ]

        var output: [Int: [Double]] = [:]
        let folders = candidateFolderURLs(named: "parsed_json_files")

        for folder in folders {
            for (fileName, durationKey) in files {
                let fileURL = folder.appendingPathComponent(fileName)
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                if let parsed = parseParsedDurationData(data: data, durationKey: durationKey) {
                    for (id, durations) in parsed where !durations.isEmpty {
                        output[id] = durations
                    }
                }
            }
        }

        return output.isEmpty ? nil : output
    }

    private static func parseParsedDurationData(
        data: Data,
        durationKey: String
    ) -> [Int: [Double]]? {
        guard let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else { return nil }
        var parsed: [Int: [Double]] = [:]

        for entry in raw {
            guard let idValue = entry["id"] else { continue }
            let id: Int?
            if let n = idValue as? Int { id = n }
            else if let n = idValue as? Double { id = Int(n) }
            else if let s = idValue as? String { id = Int(s) }
            else { id = nil }
            guard let resolvedId = id else { continue }

            guard let levels = entry["levels"] as? [[String: Any]] else { continue }
            var durations: [Double] = []
            for level in levels {
                let value = level[durationKey]
                if let n = value as? Double {
                    durations.append(n)
                } else if let n = value as? Int {
                    durations.append(Double(n))
                } else if let s = value as? String, let n = Double(s) {
                    durations.append(n)
                }
            }
            if !durations.isEmpty {
                parsed[resolvedId] = durations
            }
        }

        return parsed.isEmpty ? nil : parsed
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
            let inferredBuilderCount = upgrades.filter { $0.category == .builderVillage }.count
            let importTimestamp = Date()
            let normalizedTag = export.tag?.replacingOccurrences(of: "#", with: "").uppercased()

            suppressPersistence = true
            updateCurrentProfile { profile in
                profile.rawJSON = input
                profile.lastImportDate = importTimestamp
                profile.activeUpgrades = upgrades
                if inferredBuilderCount > profile.builderCount {
                    profile.builderCount = inferredBuilderCount
                }
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

    func previewImportUpgrades(input: String) -> [BuildingUpgrade]? {
        guard let data = input.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        guard let export = try? decoder.decode(CoCExport.self, from: data) else { return nil }
        return collectUpgrades(from: export)
            .sorted(by: { $0.endTime < $1.endTime })
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
            dataId: dataId,
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
        let index = min(max(level - 1, 0), durations.count - 1)
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

        var output: [Int: String] = [:]
        if let parsed = loadNameMappingFromJSONMaps(), !parsed.isEmpty {
            output.merge(parsed) { current, _ in current }
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
            output.merge(parsed) { current, _ in current }
        }

        return output
    }

    private static func loadNameMappingFromJSONMaps() -> [Int: String]? {
        let folders = candidateFolderURLs(named: "json_maps")
        var output: [Int: String] = [:]

        for folder in folders {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            let jsonFiles = files.filter { $0.pathExtension.lowercased() == "json" }
            for fileURL in jsonFiles {
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                guard let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { continue }
                for (_, value) in raw {
                    guard let entry = value as? [String: Any] else { continue }
                    let idValue = entry["id"]
                    let id: Int?
                    if let n = idValue as? Int { id = n }
                    else if let n = idValue as? Double { id = Int(n) }
                    else if let s = idValue as? String { id = Int(s) }
                    else { id = nil }
                    guard let resolvedId = id else { continue }

                    let display = (entry["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let internalName = (entry["internalName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = (display?.isEmpty == false ? display : internalName) ?? ""
                    guard !name.isEmpty else { continue }
                    output[resolvedId] = name
                }
            }
        }

        return output.isEmpty ? nil : output
    }

}
