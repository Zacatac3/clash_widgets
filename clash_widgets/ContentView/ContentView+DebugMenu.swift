import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UIImageColors)
import UIImageColors
#endif

// MARK: - Assets Catalog View
struct AssetsCatalogView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case byId = "By ID"
        case byAsset = "By Asset"
        case byMapping = "By Mapping"
        var id: String { rawValue }
    }

    enum MappingSort: String, CaseIterable, Identifiable {
        case id = "ID"
        case alpha = "A–Z"
        var id: String { rawValue }
    }

    @State private var assets: [AssetRecord] = []
    @State private var assetsByAssetName: [AssetRecord] = []
    @State private var assetsByMapping: [AssetRecord] = []
    @State private var selectedMode: Mode = .byMapping
    @State private var assetSubfolders: [String] = []
    @State private var slugToImagesetURL: [String: URL] = [:]
    @State private var mappingSort: MappingSort = .id

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        NavigationStack {
            VStack {
                HStack(spacing: 12) {
                    Text("By Mapping")
                        .font(.headline)
                        .padding(.horizontal)

                    Picker("Sort", selection: $mappingSort) {
                        ForEach(MappingSort.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)

                    Spacer()
                }

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(mappingItemsSorted()) { asset in
                            VStack(spacing: 6) {
                                Group {
                                    #if canImport(UIKit)
                                    if let ui = uiImageForAsset(asset.slug) {
                                        Image(uiImage: ui)
                                            .resizable()
                                            .scaledToFit()
                                    } else {
                                        Image(systemName: "photo")
                                            .resizable()
                                            .scaledToFit()
                                            .foregroundColor(.secondary)
                                    }
                                    #else
                                    Image(asset.slug)
                                        .resizable()
                                        .scaledToFit()
                                    #endif
                                }
                                .frame(height: 48)

                                VStack(spacing: 2) {
                                    if let id = asset.dataId {
                                        Text("#\(id)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("")
                                            .font(.caption2)
                                    }
                                    Text(asset.displayName)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Assets Catalog")
            .onAppear(perform: buildAssetLists)
        }
    }

    private func mappingItemsSorted() -> [AssetRecord] {
        switch mappingSort {
        case .id:
            return assetsByMapping.sorted { lhs, rhs in
                if let li = lhs.dataId, let ri = rhs.dataId { return li < ri }
                if lhs.dataId != nil { return true }
                if rhs.dataId != nil { return false }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        case .alpha:
            return assetsByMapping.sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }
    }

    private func currentItems(for mode: Mode) -> [AssetRecord] {
        switch mode {
        case .byId: return assets
        case .byAsset: return assetsByAssetName
        case .byMapping: return mappingItemsSorted()
        }
    }

    private func buildAssetLists() {
        DispatchQueue.global(qos: .userInitiated).async {
            var displayToId: [String: Int] = [:]
            var slugToEntry: [String: (display: String, id: Int?)] = [:]

            if let url = Bundle.main.url(forResource: "json/mapping", withExtension: "json") {
                if let data = try? Data(contentsOf: url), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    for (k, v) in dict {
                        if let id = Int(k), let disp = v as? String {
                            displayToId[disp] = id
                        }
                    }
                }
            }

            if let mapsURL = Bundle.main.url(forResource: "json/json_maps", withExtension: nil) {
                let fm = FileManager.default
                if let enumerator = fm.enumerator(at: mapsURL, includingPropertiesForKeys: nil) {
                    for case let fileURL as URL in enumerator {
                        if fileURL.pathExtension == "json" {
                            if let data = try? Data(contentsOf: fileURL),
                               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                for (_, v) in root {
                                    if let entry = v as? [String: Any] {
                                        let display = (entry["displayName"] as? String) ?? (entry["internalName"] as? String) ?? "Unnamed"
                                        let internalName = (entry["internalName"] as? String) ?? display
                                        let id = (entry["id"] as? Int)
                                        let slug = Self.sanitize(internalName)
                                        slugToEntry[slug] = (display: display, id: id ?? displayToId[display])
                                    }
                                }
                            }
                        }
                    }
                }
            }

            var assetOverrides: [String: String] = [:]
            if let url = Bundle.main.url(forResource: "asset_map", withExtension: "json", subdirectory: "json")
                ?? Bundle.main.url(forResource: "asset_map", withExtension: "json") {
                if let data = try? Data(contentsOf: url), let dict = try? JSONDecoder().decode([String: String].self, from: data) {
                    assetOverrides = dict
                    for (display, slug) in dict {
                        let s = Self.sanitize(slug)
                        slugToEntry[s] = (display: display, id: displayToId[display])
                    }
                }
            }

            var byIdRecords: [AssetRecord] = []
            for (slug, (display, id)) in slugToEntry {
                let exists = Self.imageExistsOnDisk(named: slug)
                byIdRecords.append(AssetRecord(slug: slug, displayName: display, dataId: id, imageExists: exists))
            }

            byIdRecords.sort { lhs, rhs in
                if let li = lhs.dataId, let ri = rhs.dataId { return li < ri }
                if lhs.dataId != nil { return true }
                if rhs.dataId != nil { return false }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

            var foundAssets: [String] = []
            let fm = FileManager.default
            var candidateRoots: [URL] = []

            if let resourceURL = Bundle.main.resourceURL {
                candidateRoots.append(resourceURL)
                candidateRoots.append(resourceURL.deletingLastPathComponent())
            }
            if let cwd = URL(string: FileManager.default.currentDirectoryPath) {
                candidateRoots.append(cwd)
            }
            if let env = ProcessInfo.processInfo.environment["PWD"], let pwd = URL(string: env) {
                candidateRoots.append(pwd)
            }

            candidateRoots.append(URL(fileURLWithPath: "./clash_widgets/Assets.xcassets", isDirectory: true))
            candidateRoots.append(URL(fileURLWithPath: "./ClashDashWidget/Assets.xcassets", isDirectory: true))

            var byAssetRecords: [AssetRecord] = []
            var slugToImagesetURLLocal: [String: URL] = [:]
            let excludedFoldersSet = Set(["leagues", "resources", "town_hall", "profile", "images"].map { $0.lowercased() })

            var detectedFolders = Set<String>()
            var slugToFolders: [String: Set<String>] = [:]
            for root in candidateRoots {
                if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
                    for case let fileURL as URL in enumerator {
                        if fileURL.pathExtension == "imageset" {
                            let name = fileURL.deletingPathExtension().lastPathComponent
                            let slug = Self.sanitize(name)
                            if foundAssets.contains(slug) { continue }
                            foundAssets.append(slug)

                            let parentFolder = fileURL.deletingLastPathComponent().lastPathComponent
                            if parentFolder != "Assets.xcassets" && !parentFolder.isEmpty {
                                detectedFolders.insert(parentFolder)
                                slugToFolders[slug.lowercased(), default: []].insert(parentFolder.lowercased())
                            }

                            slugToImagesetURLLocal[slug.lowercased()] = fileURL

                            let mapped = slugToEntry[slug]
                            let display = mapped?.display ?? slug.replacingOccurrences(of: "_", with: " ").capitalized
                            let id = mapped?.id
                            let exists = Self.imageExistsOnDisk(named: slug)
                            let record = AssetRecord(slug: slug, displayName: display, dataId: id, imageExists: exists)
                            byAssetRecords.append(record)
                        }
                    }
                }
            }

            let fallbackSlugs = Set(byIdRecords.map { $0.slug } + byAssetRecords.map { $0.slug })
            for slug in fallbackSlugs where !foundAssets.contains(slug) {
                if Self.imageExistsInBundle(named: slug) {
                    var recorded = false
                    for folder in detectedFolders {
                        if UIImage(named: "\(folder)/\(slug)") != nil {
                            slugToFolders[slug.lowercased(), default: []].insert(folder.lowercased())
                            recorded = true
                            break
                        }
                    }

                    if !recorded {
                        for ex in excludedFoldersSet {
                            if UIImage(named: "\(ex)/\(slug)") != nil {
                                slugToFolders[slug.lowercased(), default: []].insert(ex)
                                recorded = true
                                break
                            }
                        }
                    }

                    let mapped = slugToEntry[slug]
                    let display = mapped?.display ?? slug.replacingOccurrences(of: "_", with: " ").capitalized
                    let id = mapped?.id
                    let record = AssetRecord(slug: slug, displayName: display, dataId: id, imageExists: true)
                    byAssetRecords.append(record)
                }
            }

            var byMappingRecords: [AssetRecord] = []

            if let url = Bundle.main.url(forResource: "json/mapping", withExtension: "json") {
                if let data = try? Data(contentsOf: url), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let sortedKeys = dict.keys.compactMap { Int($0) }.sorted()

                    let excludedFolders = Set(["leagues", "resources", "town_hall", "profile", "images"].map { $0.lowercased() })

                    var idToSlugs: [Int: [String]] = [:]
                    for (slug, entry) in slugToEntry {
                        if let id = entry.id {
                            idToSlugs[id, default: []].append(slug)
                        }
                    }

                    func findFolderForSlug(_ slug: String) -> String? {
                        if let folders = slugToFolders[slug.lowercased()], !folders.isEmpty {
                            for f in folders where !excludedFolders.contains(f) { return f }
                            return folders.first
                        }

                        for folder in assetSubfolders {
                            let lower = folder.lowercased()
                            if excludedFolders.contains(lower) { continue }
                            if UIImage(named: "\(folder)/\(slug)") != nil { return folder.lowercased() }
                        }

                        for ex in excludedFolders {
                            if UIImage(named: "\(ex)/\(slug)") != nil { return ex }
                        }

                        let fm = FileManager.default
                        let candidates: [URL?] = [
                            Bundle.main.resourceURL,
                            URL(fileURLWithPath: "./clash_widgets/Assets.xcassets", isDirectory: true),
                            URL(fileURLWithPath: "./ClashDashWidget/Assets.xcassets", isDirectory: true)
                        ]
                        for rootOptional in candidates {
                            guard let root = rootOptional else { continue }
                            if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
                                for case let fileURL as URL in enumerator {
                                    if fileURL.pathExtension == "imageset" && fileURL.deletingPathExtension().lastPathComponent.lowercased() == slug.lowercased() {
                                        let parent = fileURL.deletingLastPathComponent().lastPathComponent.lowercased()
                                        return parent
                                    }
                                }
                            }
                        }

                        return nil
                    }

                    func slugHasImage(_ s: String) -> Bool {
                        let lower = s.lowercased()
                        if slugToImagesetURLLocal[lower] != nil { return true }
                        if Self.imageExistsOnDisk(named: s) || Self.imageExistsInBundle(named: s) { return true }
                        for folder in assetSubfolders {
                            let lowerF = folder.lowercased()
                            if excludedFolders.contains(lowerF) { continue }
                            if UIImage(named: "\(folder)/\(s)") != nil { return true }
                        }
                        return false
                    }

                    for key in sortedKeys {
                        let display = dict[String(key)] as? String ?? ""
                        let slugFromOverride = assetOverrides[display]
                        let mappingSlug = Self.sanitize(slugFromOverride ?? display)

                        var chosenSlug: String? = nil

                        if key >= 103_000_000 && key < 104_000_000 {
                            if let url = slugToImagesetURLLocal[mappingSlug], url.deletingLastPathComponent().lastPathComponent.lowercased() == "crafted_defenses" {
                                chosenSlug = mappingSlug
                            }
                            if chosenSlug == nil, UIImage(named: "crafted_defenses/\(mappingSlug)") != nil {
                                chosenSlug = mappingSlug
                            }
                            if chosenSlug == nil {
                                let craftedPath = URL(fileURLWithPath: "./clash_widgets/Assets.xcassets/crafted_defenses/\(mappingSlug).imageset")
                                if FileManager.default.fileExists(atPath: craftedPath.path) {
                                    chosenSlug = mappingSlug
                                }
                            }
                        }

                        if chosenSlug == nil, slugHasImage(mappingSlug) {
                            chosenSlug = mappingSlug
                        }

                        if chosenSlug == nil, let candidates = idToSlugs[key] {
                            for cand in candidates {
                                if slugHasImage(cand) {
                                    chosenSlug = cand
                                    break
                                }
                            }
                        }

                        if chosenSlug == nil, let candidates = idToSlugs[key] {
                            for cand in candidates {
                                let lower = cand.lowercased()
                                let suffixes = ["hpmodule","attackmodule","effectmodule","module"]
                                for suffix in suffixes where lower.hasSuffix(suffix) {
                                    let base = String(lower.dropLast(suffix.count))
                                    if base.isEmpty { continue }
                                    if let archEntry = slugToEntry[base], let archId = archEntry.id {
                                        if let archDisplay = dict[String(archId)] as? String {
                                            let archMappingSlug = Self.sanitize(archDisplay)
                                            if slugHasImage(archMappingSlug) {
                                                chosenSlug = archMappingSlug
                                                break
                                            }
                                        }
                                    }
                                }
                                if chosenSlug != nil { break }
                            }
                        }

                        if let finalSlug = chosenSlug {
                            let folder = findFolderForSlug(finalSlug)
                            if let f = folder {
                                let lower = f.lowercased()
                                if excludedFolders.contains(lower) && lower != "crafted_defenses" {
                                    continue
                                }
                            }
                            byMappingRecords.append(AssetRecord(slug: finalSlug, displayName: display, dataId: key, imageExists: true))
                        } else {
                            byMappingRecords.append(AssetRecord(slug: mappingSlug, displayName: display, dataId: key, imageExists: false))
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                self.assetSubfolders = Array(detectedFolders).sorted()
                self.slugToImagesetURL = slugToImagesetURLLocal
                self.assets = byIdRecords
                self.assetsByAssetName = Array(Set(self.assetsByAssetName)).sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                self.assetsByMapping = byMappingRecords
            }
        }
    }

    private static func sanitize(_ s: String) -> String {
        return s.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
    }

    private func uiImageForAsset(_ slug: String) -> UIImage? {
        #if canImport(UIKit)
        let lowerSlug = slug.lowercased()
        let excluded = Set(["leagues", "resources", "town_hall", "profile", "images"].map { $0.lowercased() })

        for folder in assetSubfolders {
            let lower = folder.lowercased()
            if excluded.contains(lower) { continue }
            if let img = UIImage(named: "\(folder)/\(slug)") { return img }
        }

        if let imagesetURL = slugToImagesetURL[lowerSlug] {
            let fm = FileManager.default
            if let items = try? fm.contentsOfDirectory(at: imagesetURL, includingPropertiesForKeys: nil) {
                for item in items {
                    let ext = item.pathExtension.lowercased()
                    if ext == "png" || ext == "jpg" || ext == "jpeg" {
                        if let data = try? Data(contentsOf: item), let img = UIImage(data: data) {
                            return img
                        }
                    }
                }
            }
        }

        if let plain = UIImage(named: slug) {
            var foundExcluded = false
            for ex in excluded {
                if UIImage(named: "\(ex)/\(slug)") != nil {
                    foundExcluded = true
                    break
                }
            }
            if !foundExcluded { return plain }
        }

        let fm = FileManager.default
        let candidates: [URL] = [
            URL(fileURLWithPath: "./clash_widgets/Assets.xcassets", isDirectory: true),
            URL(fileURLWithPath: "./ClashDashWidget/Assets.xcassets", isDirectory: true),
            Bundle.main.resourceURL ?? URL(fileURLWithPath: "./")
        ]
        for root in candidates {
            if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension == "imageset" && fileURL.deletingPathExtension().lastPathComponent.lowercased() == lowerSlug {
                        if let items = try? fm.contentsOfDirectory(at: fileURL, includingPropertiesForKeys: nil) {
                            for item in items {
                                let ext = item.pathExtension.lowercased()
                                if ext == "png" || ext == "jpg" || ext == "jpeg" {
                                    if let data = try? Data(contentsOf: item), let img = UIImage(data: data) {
                                        return img
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        return nil
        #else
        return nil
        #endif
    }

    private static func imageExistsInBundle(named name: String) -> Bool {
        #if canImport(UIKit)
        if UIImage(named: name) != nil { return true }
        if UIImage(named: "buildings_home/\(name)") != nil { return true }

        let fm = FileManager.default
        let candidateRoots: [URL?] = [Bundle.main.resourceURL, URL(fileURLWithPath: "./clash_widgets/Assets.xcassets", isDirectory: true), URL(fileURLWithPath: "./ClashDashWidget/Assets.xcassets", isDirectory: true)]
        for rootOptional in candidateRoots {
            guard let root = rootOptional else { continue }
            if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension == "imageset" && fileURL.deletingPathExtension().lastPathComponent.lowercased() == name.lowercased() {
                        return true
                    }
                }
            }
        }
        return false
        #else
        return false
        #endif
    }

    private static func imageExistsOnDisk(named name: String) -> Bool {
        let fm = FileManager.default
        let candidates: [URL?] = [
            URL(fileURLWithPath: "./clash_widgets/Assets.xcassets", isDirectory: true),
            URL(fileURLWithPath: "./ClashDashWidget/Assets.xcassets", isDirectory: true),
            Bundle.main.resourceURL
        ]
        for rootOptional in candidates {
            guard let root = rootOptional else { continue }
            if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension == "imageset" && fileURL.deletingPathExtension().lastPathComponent.lowercased() == name.lowercased() {
                        return true
                    }
                }
            }
        }
        return false
    }
}

struct AssetRecord: Identifiable, Hashable {
    let id = UUID()
    let slug: String
    let displayName: String
    let dataId: Int?
    let imageExists: Bool
}

struct MasterListDebugView: View {
    @EnvironmentObject private var dataService: DataService

    private enum Tab: String, CaseIterable, Identifiable {
        case home = "Home"
        case builder = "Builder"
        var id: String { rawValue }
    }

    private enum ScopeMode: String, CaseIterable, Identifiable {
        case all = "All"
        case remaining = "Remaining"
        var id: String { rawValue }
    }

    private struct MasterListFile: Decodable {
        let village: String
        let sections: [String: [String: MasterListSubcategoryEntries]]
    }

    private struct MasterListSubcategoryEntries: Decodable {
        let entries: [MasterListEntry]

        init(from decoder: Decoder) throws {
            if let map = try? [String: String](from: decoder) {
                self.entries = map.map { key, value in
                    MasterListEntry(key: key, id: Int(key), name: value)
                }
                return
            }

            if let legacy = try? [LegacyEntry](from: decoder) {
                self.entries = legacy.map {
                    MasterListEntry(key: $0.key, id: $0.id ?? Int($0.key), name: $0.name)
                }
                return
            }

            self.entries = []
        }

        private struct LegacyEntry: Decodable {
            let key: String
            let id: Int?
            let name: String
        }
    }

    private struct MasterListEntry: Hashable {
        let key: String
        let id: Int?
        let name: String
    }

    private struct LevelDetail: Identifiable {
        let id: String
        let levelLabel: String
        let costText: String
        let resourceIcon: String?
        let timeText: String
    }

    private struct GroupedEntries: Identifiable {
        var id: String { "\(domain)::\(subcategory)" }
        let domain: String
        let subcategory: String
        let entries: [FlattenedEntry]
    }

    private struct FlattenedEntry: Identifiable, Hashable {
        var id: String { "\(domain)::\(subcategory)::\(entry.key)" }
        let domain: String
        let subcategory: String
        let entry: MasterListEntry
    }

    private struct LevelRange {
        let min: Int
        let max: Int
    }

    private struct SeasonalModuleInfo {
        let id: Int
        let displayName: String
        let archetypeId: Int
    }

    @State private var selectedTab: Tab = .home
    @State private var scopeMode: ScopeMode = .all
    @State private var homeList: MasterListFile?
    @State private var builderList: MasterListFile?
    @State private var loadError: String?
    @State private var assetLookupByFolder: [String: [String: String]] = [:]
    @State private var assetOverrides: [String: String] = [:]
    @State private var expandedKeys: Set<String> = []
    @State private var loadingDetailKeys: Set<String> = []
    @State private var levelDetailsByKey: [String: [LevelDetail]] = [:]
    @State private var superchargeInternalByDisplayName: [String: String] = [:]
    @State private var guardianCharacterIDByGuardianID: [Int: Int] = [:]
    @State private var seasonalModuleArchetypeByID: [Int: String] = [:]
    @State private var seasonalModulesByArchetypeID: [Int: [SeasonalModuleInfo]] = [:]
    @State private var currentHomeLevelsByID: [Int: LevelRange] = [:]
    @State private var currentBuilderLevelsByID: [Int: LevelRange] = [:]
    @State private var cachedRemainingVisibility: [String: Bool] = [:]

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Picker("Village", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Picker("Scope", selection: $scopeMode) {
                    ForEach(ScopeMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if let loadError {
                    ContentUnavailableView(
                        "Failed to Load Master Lists",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else {
                    List {
                        ForEach(groupsForSelectedTab()) { group in
                            Section("\(pretty(group.domain)) • \(pretty(group.subcategory))") {
                                ForEach(Array(group.entries.enumerated()), id: \.offset) { _, entry in
                                    row(for: entry)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Master List")
            .onAppear {
                if homeList == nil || builderList == nil {
                    loadMasterLists()
                }
                if guardianCharacterIDByGuardianID.isEmpty {
                    loadGuardianCharacterBridgeMap()
                }
                if seasonalModuleArchetypeByID.isEmpty {
                    loadSeasonalDefenseAssetMap()
                }
                if assetOverrides.isEmpty {
                    loadAssetOverrides()
                }
                if assetLookupByFolder.isEmpty {
                    buildAssetIndex()
                }
                loadProfileSnapshot()
            }
            .onChange(of: dataService.selectedProfileID) { _, _ in
                loadProfileSnapshot()
                cachedRemainingVisibility.removeAll()
            }
            .onChange(of: selectedTab) { _, _ in
                cachedRemainingVisibility.removeAll()
            }
            .onChange(of: scopeMode) { _, _ in
                cachedRemainingVisibility.removeAll()
            }
        }
    }

    @ViewBuilder
    private func row(for flattened: FlattenedEntry) -> some View {
        let entry = flattened.entry
        let uniqueKey = flattened.id

        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedKeys.contains(uniqueKey) },
                set: { newValue in
                    if newValue {
                        expandedKeys.insert(uniqueKey)
                        loadLevelDetailsIfNeeded(for: flattened)
                    } else {
                        expandedKeys.remove(uniqueKey)
                    }
                }
            )
        ) {
            if loadingDetailKeys.contains(uniqueKey) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading level details…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else if let rows = levelDetailsByKey[uniqueKey], !rows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rows) { row in
                        HStack(spacing: 8) {
                            Text(row.levelLabel)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(width: 64, alignment: .leading)
                            Text(row.costText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            if let resourceIcon = row.resourceIcon {
                                resourceIconView(named: resourceIcon)
                            }
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(row.timeText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("No per-level data found.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }
        } label: {
            HStack(spacing: 12) {
                Group {
                    #if canImport(UIKit)
                    if let uiImage = imageForEntry(entry, village: selectedTab) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.secondary)
                    }
                    #else
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.secondary)
                    #endif
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.subheadline)
                    HStack(spacing: 8) {
                        Text(entry.key)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let id = entry.id {
                            Text("#\(id)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text(pretty(flattened.subcategory))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func loadLevelDetailsIfNeeded(for flattened: FlattenedEntry) {
        let uniqueKey = flattened.id
        if levelDetailsByKey[uniqueKey] != nil { return }
        if loadingDetailKeys.contains(uniqueKey) { return }

        loadingDetailKeys.insert(uniqueKey)

        DispatchQueue.global(qos: .userInitiated).async {
            let details = findLevelDetails(for: flattened)
            DispatchQueue.main.async {
                levelDetailsByKey[uniqueKey] = details
                loadingDetailKeys.remove(uniqueKey)
            }
        }
    }

    private func findLevelDetails(for flattened: FlattenedEntry) -> [LevelDetail] {
        if flattened.subcategory == "seasonal_defense",
           let archetypeID = flattened.entry.id,
           let modules = seasonalModulesByArchetypeID[archetypeID],
           !modules.isEmpty {
            return seasonalArchetypeLevelDetails(for: modules)
        }

        guard let matched = findParsedMatch(for: flattened) else { return [] }
        return parseLevelDetails(from: matched.object, sourceFileName: matched.fileName)
    }

    private func seasonalArchetypeLevelDetails(for modules: [SeasonalModuleInfo]) -> [LevelDetail] {
        let ordered = modules.sorted { lhs, rhs in
            seasonalModuleSortRank(lhs.displayName) < seasonalModuleSortRank(rhs.displayName)
        }

        var output: [LevelDetail] = []
        for module in ordered {
            let moduleEntry = MasterListEntry(key: String(module.id), id: module.id, name: module.displayName)
            let moduleFlattened = FlattenedEntry(domain: "buildings", subcategory: "seasonal_defense_module", entry: moduleEntry)

            guard let matched = findParsedMatch(for: moduleFlattened) else { continue }
            let moduleRows = parseLevelDetails(from: matched.object, sourceFileName: matched.fileName)
                .map { row in
                    LevelDetail(
                        id: "\(module.id)-\(row.id)",
                        levelLabel: "\(seasonalModuleShortLabel(module.displayName)) \(row.levelLabel)",
                        costText: row.costText,
                        resourceIcon: row.resourceIcon,
                        timeText: row.timeText
                    )
                }
            output.append(contentsOf: moduleRows)
        }

        return output
    }

    private func seasonalModuleSortRank(_ name: String) -> Int {
        let lowered = name.lowercased()
        if lowered.contains("hp") { return 0 }
        if lowered.contains("dps") || lowered.contains("attack") { return 1 }
        if lowered.contains("special") || lowered.contains("effect") { return 2 }
        return 3
    }

    private func seasonalModuleShortLabel(_ name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("hp") { return "HP" }
        if lowered.contains("dps") || lowered.contains("attack") { return "DPS" }
        if lowered.contains("special") || lowered.contains("effect") { return "Special" }
        return "Module"
    }

    private func findParsedMatch(for flattened: FlattenedEntry) -> (object: [String: Any], fileName: String)? {
        let entry = flattened.entry
        let folders = DataService.candidateFolderURLs(named: "parsed_json_files")
        let candidateFiles = [
            "buildings.json",
            "characters.json",
            "heroes.json",
            "pets.json",
            "spells.json",
            "traps.json",
            "mini_levels.json",
            "seasonal_defense_modules.json",
            "guardians.json",
            "weapons.json"
        ]

        for folder in folders {
            for fileName in candidateFiles {
                let fileURL = folder.appendingPathComponent(fileName)
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                guard let root = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else { continue }

                for object in root where matches(entry: entry, parsedObject: object, flattened: flattened) {
                    return (object, fileName)
                }
            }
        }

        return nil
    }

    private func matches(entry: MasterListEntry, parsedObject: [String: Any], flattened: FlattenedEntry) -> Bool {
        if let entryId = entry.id {
            if let parsedId = parsedObject["id"] as? Int, parsedId == entryId {
                return true
            }
            if let parsedId = parsedObject["id"] as? String, Int(parsedId) == entryId {
                return true
            }
            if let parsedId = parsedObject["id"] as? Double, Int(parsedId) == entryId {
                return true
            }

            if flattened.subcategory == "guardians",
               let characterID = guardianCharacterIDByGuardianID[entryId] {
                if let parsedId = parsedObject["id"] as? Int, parsedId == characterID {
                    return true
                }
                if let parsedId = parsedObject["id"] as? String, Int(parsedId) == characterID {
                    return true
                }
                if let parsedId = parsedObject["id"] as? Double, Int(parsedId) == characterID {
                    return true
                }
            }
        }

        let parsedInternal = normalizeLookupName(parsedObject["internalName"] as? String)
        let parsedName = normalizeLookupName(parsedObject["name"] as? String)

        if flattened.subcategory == "supercharges" {
            let lookupName = normalizeLookupName(entry.name)
            if let internalName = superchargeInternalByDisplayName[lookupName],
               parsedInternal == normalizeLookupName(internalName) {
                return true
            }
        }

        let normalizedEntryName = normalizeLookupName(entry.name)
        if !normalizedEntryName.isEmpty {
            if parsedInternal == normalizedEntryName || parsedName == normalizedEntryName {
                return true
            }
        }

        let normalizedKey = normalizeLookupName(entry.key)
        if !normalizedKey.isEmpty {
            if parsedInternal == normalizedKey || parsedName == normalizedKey {
                return true
            }
        }

        let compactEntryName = normalizeLookupName(entry.name.replacingOccurrences(of: " Supercharge", with: ""))
        if !compactEntryName.isEmpty,
           (parsedInternal == compactEntryName || parsedName == compactEntryName) {
            return true
        }

        if flattened.subcategory == "supercharges",
           !compactEntryName.isEmpty,
           parsedInternal.contains(compactEntryName) {
            return true
        }

        return false
    }

    private func parseLevelDetails(from parsedObject: [String: Any], sourceFileName: String) -> [LevelDetail] {
        guard let levels = parsedObject["levels"] as? [[String: Any]], !levels.isEmpty else { return [] }

        var output: [LevelDetail] = []
        let currentLevelDurationFiles: Set<String> = ["characters.json", "heroes.json", "pets.json", "spells.json"]
        let isCurrentLevelIndexed = currentLevelDurationFiles.contains(sourceFileName)

        var lastResourceRaw: String?
        for (idx, levelObj) in levels.enumerated() {
            let level = intValue(levelObj["level"]) ?? (idx + 1)
            let costValue = intValue(levelObj["buildCost"]) ?? intValue(levelObj["BuildCost"]) ?? intValue(levelObj["UpgradeCost"]) ?? 0
            let resourceValue: String? = {
                let candidates = [
                    stringValue(levelObj["buildResource"]),
                    stringValue(levelObj["BuildResource"]),
                    stringValue(levelObj["UpgradeResource"])
                ]
                for candidate in candidates {
                    if let candidate, !candidate.isEmpty {
                        return candidate
                    }
                }
                return nil
            }()

            if let resourceValue = resourceValue, !resourceValue.isEmpty {
                lastResourceRaw = resourceValue
            }

            let effectiveResourceRaw = resourceValue?.isEmpty == false ? resourceValue : lastResourceRaw
            let nextLevel = isCurrentLevelIndexed ? (level + 1) : level
            let levelLabel = isCurrentLevelIndexed ? "To Lv \(nextLevel)" : "Lv \(nextLevel)"

            let seconds = intValue(levelObj["buildTimeSeconds"]) ?? intValue(levelObj["upgradeTimeSeconds"]) ?? buildSecondsFromRaw(levelObj)

            if costValue <= 0 && seconds <= 0 {
                continue
            }

            output.append(
                LevelDetail(
                    id: "\(level)-\(idx)",
                    levelLabel: levelLabel,
                    costText: formatCost(costValue),
                    resourceIcon: iconName(forResource: effectiveResourceRaw),
                    timeText: formatDuration(seconds)
                )
            )
        }

        return output
    }

    private func buildSecondsFromRaw(_ levelObj: [String: Any]) -> Int {
        let d = intValue(levelObj["BuildTimeD"]) ?? 0
        let h = intValue(levelObj["BuildTimeH"]) ?? intValue(levelObj["UpgradeTimeH"]) ?? 0
        let m = intValue(levelObj["BuildTimeM"]) ?? intValue(levelObj["UpgradeTimeM"]) ?? 0
        let s = intValue(levelObj["BuildTimeS"]) ?? 0
        return (d * 86400) + (h * 3600) + (m * 60) + s
    }

    private func intValue(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String, let i = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return i }
        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        if let s = value as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds <= 0 { return "0s" }
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }

    private func formatCost(_ value: Int) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        switch absValue {
        case 1_000_000_000...:
            return "\(sign)" + String(format: "%.2fB", Double(absValue) / 1_000_000_000)
        case 1_000_000...:
            return "\(sign)" + String(format: "%.2fM", Double(absValue) / 1_000_000)
        case 1_000...:
            return "\(sign)" + String(format: "%.1fK", Double(absValue) / 1_000)
        default:
            return "\(value)"
        }
    }

    private func groupsForSelectedTab() -> [GroupedEntries] {
        let list = (selectedTab == .home ? homeList : builderList)
        guard let list else { return [] }

        var output: [GroupedEntries] = []
        for (domain, subgroups) in list.sections {
            for (subcategory, wrappedEntries) in subgroups {
                let flattened = wrappedEntries.entries
                    .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
                    .map { entry in
                        FlattenedEntry(domain: domain, subcategory: subcategory, entry: entry)
                    }
                    .filter { shouldShowEntry($0) }
                output.append(GroupedEntries(domain: domain, subcategory: subcategory, entries: flattened))
            }
        }

        return output.sorted {
            if $0.domain == $1.domain {
                return $0.subcategory.localizedCaseInsensitiveCompare($1.subcategory) == .orderedAscending
            }
            return $0.domain.localizedCaseInsensitiveCompare($1.domain) == .orderedAscending
        }
    }

    private func pretty(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func loadMasterLists() {
        let decoder = JSONDecoder()

        func loadFile(named fileName: String) -> MasterListFile? {
            let folders = DataService.candidateFolderURLs(named: "master_lists")
            for folder in folders {
                let url = folder.appendingPathComponent(fileName)
                if let data = try? Data(contentsOf: url), let parsed = try? decoder.decode(MasterListFile.self, from: data) {
                    return parsed
                }
            }
            return nil
        }

        if let home = loadFile(named: "home_village_master_upgrades.json"),
           let builder = loadFile(named: "builder_base_master_upgrades.json") {
            homeList = home
            builderList = builder
            loadError = nil
            loadMiniLevelMap()
            loadProfileSnapshot()
        } else {
            loadError = "Could not locate one or both files in json/master_lists."
        }
    }

    private func shouldShowEntry(_ flattened: FlattenedEntry) -> Bool {
        guard scopeMode == .remaining else { return true }

        if let cached = cachedRemainingVisibility[flattened.id] {
            return cached
        }

        let visible = computeIsRemaining(for: flattened)
        cachedRemainingVisibility[flattened.id] = visible
        return visible
    }

    private func computeIsRemaining(for flattened: FlattenedEntry) -> Bool {
        let entry = flattened.entry
        guard let entryID = entry.id else {
            return true
        }

        if flattened.subcategory == "seasonal_defense",
           let modules = seasonalModulesByArchetypeID[entryID],
           !modules.isEmpty {
            for module in modules {
                let current = currentHomeLevelsByID[module.id]?.max ?? 0
                if let maxLevel = maxAvailableLevelForModuleId(module.id), current < maxLevel {
                    return true
                }
            }
            return false
        }

        let currentLevel = currentLevelForEntry(flattened, entryID: entryID)
        guard let currentLevel else {
            return true
        }

        guard let maxLevel = maxAvailableLevelForEntry(flattened) else {
            return true
        }

        return currentLevel < maxLevel
    }

    private func currentLevelForEntry(_ flattened: FlattenedEntry, entryID: Int) -> Int? {
        let levels = (selectedTab == .home ? currentHomeLevelsByID : currentBuilderLevelsByID)

        let resolvedID: Int
        if flattened.subcategory == "guardians",
           let characterID = guardianCharacterIDByGuardianID[entryID] {
            resolvedID = characterID
        } else {
            resolvedID = entryID
        }

        guard let range = levels[resolvedID] else { return nil }

        let useMinLevel = flattened.domain == "buildings"
            && flattened.subcategory != "heroes"
            && flattened.subcategory != "guardians"
            && flattened.subcategory != "supercharges"

        return useMinLevel ? range.min : range.max
    }

    private func maxAvailableLevelForEntry(_ flattened: FlattenedEntry) -> Int? {
        if flattened.subcategory == "seasonal_defense",
           let entryID = flattened.entry.id,
           let modules = seasonalModulesByArchetypeID[entryID],
           !modules.isEmpty {
            return modules.compactMap { maxAvailableLevelForModuleId($0.id) }.max()
        }

        guard let matched = findParsedMatch(for: flattened) else { return nil }
        guard let levels = matched.object["levels"] as? [[String: Any]], !levels.isEmpty else { return nil }

        let townHall = selectedTab == .home
            ? max(1, dataService.getTownHallLevel(from: .home))
            : max(1, dataService.getTownHallLevel(from: .builder))

        let filtered = levels.filter { levelObj in
            if let requiredTH = intValue(levelObj["TownHallLevel"]) ?? intValue(levelObj["townHallLevel"]) {
                return requiredTH <= townHall
            }
            return true
        }

        let candidateLevels = (filtered.isEmpty ? levels : filtered).compactMap { levelObj in
            intValue(levelObj["level"])
        }
        return candidateLevels.max()
    }

    private func maxAvailableLevelForModuleId(_ moduleId: Int) -> Int? {
        let moduleEntry = MasterListEntry(key: String(moduleId), id: moduleId, name: String(moduleId))
        let moduleFlattened = FlattenedEntry(domain: "buildings", subcategory: "seasonal_defense_module", entry: moduleEntry)
        guard let matched = findParsedMatch(for: moduleFlattened),
              let levels = matched.object["levels"] as? [[String: Any]],
              !levels.isEmpty else { return nil }

        let townHall = max(1, dataService.getTownHallLevel(from: .home))
        let filtered = levels.filter { levelObj in
            if let requiredTH = intValue(levelObj["TownHallLevel"]) ?? intValue(levelObj["townHallLevel"]) {
                return requiredTH <= townHall
            }
            return true
        }
        return (filtered.isEmpty ? levels : filtered).compactMap { intValue($0["level"]) }.max()
    }

    private func loadProfileSnapshot() {
        guard let raw = dataService.currentProfile?.rawJSON,
              !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let export = try? JSONDecoder().decode(CoCExport.self, from: data) else {
            currentHomeLevelsByID = [:]
            currentBuilderLevelsByID = [:]
            return
        }

        currentHomeLevelsByID = mergedLevels([
            levelsFromBuildings(export.buildings),
            levelsFromBuildings(export.traps?.map { Building(data: $0.data, lvl: $0.lvl, weapon: nil, timer: $0.timer, cnt: $0.cnt, supercharge: nil, extra: $0.extra, types: nil) }),
            levelsFromUnits(export.units),
            levelsFromUnits(export.siegeMachines?.map { ExportUnit(data: $0.data, lvl: $0.lvl, timer: $0.timer, extra: $0.extra) }),
            levelsFromHeroes(export.heroes),
            levelsFromPets(export.pets),
            levelsFromSpells(export.spells),
            levelsFromGuardians(export.guardians)
        ])

        currentBuilderLevelsByID = mergedLevels([
            levelsFromBuildings(export.buildings2),
            levelsFromBuildings(export.traps2?.map { Building(data: $0.data, lvl: $0.lvl, weapon: nil, timer: $0.timer, cnt: $0.cnt, supercharge: nil, extra: $0.extra, types: nil) }),
            levelsFromUnits(export.units2),
            levelsFromHeroes(export.heroes2)
        ])
    }

    private func mergedLevels(_ maps: [[Int: LevelRange]]) -> [Int: LevelRange] {
        var output: [Int: LevelRange] = [:]
        for map in maps {
            for (id, range) in map {
                if let existing = output[id] {
                    output[id] = LevelRange(min: min(existing.min, range.min), max: max(existing.max, range.max))
                } else {
                    output[id] = range
                }
            }
        }
        return output
    }

    private func levelsFromBuildings(_ list: [Building]?) -> [Int: LevelRange] {
        guard let list else { return [:] }
        var grouped: [Int: [Int]] = [:]
        for item in list {
            guard let lvl = item.lvl else { continue }
            grouped[item.data, default: []].append(lvl)

            if let types = item.types {
                for type in types {
                    if let modules = type.modules {
                        for module in modules {
                            if let moduleLevel = module.lvl {
                                grouped[module.data, default: []].append(moduleLevel)
                            }
                        }
                    }
                }
            }
        }
        var output: [Int: LevelRange] = [:]
        for (id, levels) in grouped {
            guard let minLevel = levels.min(), let maxLevel = levels.max() else { continue }
            output[id] = LevelRange(min: minLevel, max: maxLevel)
        }
        return output
    }

    private func levelsFromUnits(_ list: [ExportUnit]?) -> [Int: LevelRange] {
        guard let list else { return [:] }
        var output: [Int: LevelRange] = [:]
        for item in list {
            output[item.data] = mergeRange(existing: output[item.data], level: item.lvl)
        }
        return output
    }

    private func levelsFromHeroes(_ list: [ExportHero]?) -> [Int: LevelRange] {
        guard let list else { return [:] }
        var output: [Int: LevelRange] = [:]
        for item in list {
            output[item.data] = mergeRange(existing: output[item.data], level: item.lvl)
        }
        return output
    }

    private func levelsFromPets(_ list: [ExportPet]?) -> [Int: LevelRange] {
        guard let list else { return [:] }
        var output: [Int: LevelRange] = [:]
        for item in list {
            output[item.data] = mergeRange(existing: output[item.data], level: item.lvl)
        }
        return output
    }

    private func levelsFromSpells(_ list: [ExportSpell]?) -> [Int: LevelRange] {
        guard let list else { return [:] }
        var output: [Int: LevelRange] = [:]
        for item in list {
            output[item.data] = mergeRange(existing: output[item.data], level: item.lvl)
        }
        return output
    }

    private func levelsFromGuardians(_ list: [ExportGuardian]?) -> [Int: LevelRange] {
        guard let list else { return [:] }
        var output: [Int: LevelRange] = [:]
        for item in list {
            guard let lvl = item.lvl else { continue }
            output[item.data] = mergeRange(existing: output[item.data], level: lvl)
            if let characterID = guardianCharacterIDByGuardianID[item.data] {
                output[characterID] = mergeRange(existing: output[characterID], level: lvl)
            }
        }
        return output
    }

    private func mergeRange(existing: LevelRange?, level: Int) -> LevelRange {
        guard let existing else {
            return LevelRange(min: level, max: level)
        }
        return LevelRange(min: min(existing.min, level), max: max(existing.max, level))
    }

    private func loadMiniLevelMap() {
        guard superchargeInternalByDisplayName.isEmpty else { return }
        let folders = DataService.candidateFolderURLs(named: "json_maps")

        for folder in folders {
            let url = folder.appendingPathComponent("mini_levels_json_map.json")
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: [String: Any]] else { continue }

            var lookup: [String: String] = [:]
            for value in raw.values {
                guard let display = value["displayName"] as? String,
                      let internalName = value["internalName"] as? String else { continue }
                lookup[normalizeLookupName(display)] = internalName
            }
            superchargeInternalByDisplayName = lookup
            return
        }
    }

    private func loadGuardianCharacterBridgeMap() {
        guard guardianCharacterIDByGuardianID.isEmpty else { return }
        let folders = DataService.candidateFolderURLs(named: "json_maps")

        var guardianDisplayByID: [Int: String] = [:]
        var characterIDByDisplay: [String: Int] = [:]

        for folder in folders {
            let guardiansURL = folder.appendingPathComponent("guardians_json_map.json")
            if let data = try? Data(contentsOf: guardiansURL),
               let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: [String: Any]] {
                for value in raw.values {
                    guard let guardianID = intValue(value["id"]),
                          let display = value["displayName"] as? String else { continue }
                    guardianDisplayByID[guardianID] = normalizeLookupName(display)
                }
            }

            let charactersURL = folder.appendingPathComponent("characters_json_map.json")
            if let data = try? Data(contentsOf: charactersURL),
               let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: [String: Any]] {
                for value in raw.values {
                    guard let characterID = intValue(value["id"]),
                          let display = value["displayName"] as? String else { continue }
                    characterIDByDisplay[normalizeLookupName(display)] = characterID
                }
            }
        }

        var bridge: [Int: Int] = [:]
        for (guardianID, display) in guardianDisplayByID {
            if let characterID = characterIDByDisplay[display] {
                bridge[guardianID] = characterID
            }
        }

        guardianCharacterIDByGuardianID = bridge
    }

    private func loadSeasonalDefenseAssetMap() {
        guard seasonalModuleArchetypeByID.isEmpty else { return }

        let folders = DataService.candidateFolderURLs(named: "json_maps")

        var archetypeDisplayByInternal: [String: String] = [:]
        var archetypeIDByInternal: [String: Int] = [:]
        var moduleArchetypeByID: [Int: String] = [:]
        var modulesByArchetypeID: [Int: [SeasonalModuleInfo]] = [:]

        for folder in folders {
            let archetypesURL = folder.appendingPathComponent("seasonal_defense_archetypes_json_map.json")
            if let data = try? Data(contentsOf: archetypesURL),
               let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: [String: Any]] {
                for value in raw.values {
                    guard let internalName = value["internalName"] as? String,
                          let displayName = value["displayName"] as? String,
                          let archetypeID = intValue(value["id"]) else { continue }
                    archetypeDisplayByInternal[internalName] = displayName
                    archetypeIDByInternal[internalName] = archetypeID
                }
            }

            let modulesURL = folder.appendingPathComponent("seasonal_defense_modules_json_map.json")
            if let data = try? Data(contentsOf: modulesURL),
               let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: [String: Any]] {
                for value in raw.values {
                    guard let id = intValue(value["id"]),
                          let internalName = value["internalName"] as? String else { continue }

                    let archetypeInternal = internalName
                        .replacingOccurrences(of: "HPModule", with: "")
                        .replacingOccurrences(of: "AttackModule", with: "")
                        .replacingOccurrences(of: "EffectModule", with: "")

                    if let display = archetypeDisplayByInternal[archetypeInternal] {
                        moduleArchetypeByID[id] = display
                    }

                    if let archetypeID = archetypeIDByInternal[archetypeInternal],
                       let moduleDisplay = value["displayName"] as? String {
                        let info = SeasonalModuleInfo(id: id, displayName: moduleDisplay, archetypeId: archetypeID)
                        modulesByArchetypeID[archetypeID, default: []].append(info)
                    }
                }
            }
        }

        seasonalModuleArchetypeByID = moduleArchetypeByID
        seasonalModulesByArchetypeID = modulesByArchetypeID
    }

    private func buildAssetIndex() {
        let fm = FileManager.default
        let roots: [URL] = [
            URL(fileURLWithPath: "./clash_widgets/Assets.xcassets", isDirectory: true),
            URL(fileURLWithPath: "./ClashDashWidget/Assets.xcassets", isDirectory: true)
        ]

        var lookup: [String: [String: String]] = [:]
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "imageset" else { continue }
                let folder = fileURL.deletingLastPathComponent().lastPathComponent.lowercased()
                let assetName = fileURL.deletingPathExtension().lastPathComponent
                let slug = sanitize(assetName)
                lookup[folder, default: [:]][slug] = assetName
            }
        }
        assetLookupByFolder = lookup
    }

    private func loadAssetOverrides() {
        if let url = Bundle.main.url(forResource: "asset_map", withExtension: "json", subdirectory: "json")
            ?? Bundle.main.url(forResource: "asset_map", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            assetOverrides = decoded
            return
        }

        let localURL = URL(fileURLWithPath: "./json/asset_map.json")
        if let data = try? Data(contentsOf: localURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            assetOverrides = decoded
        }
    }

    private func sanitize(_ value: String) -> String {
        value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
    }

    private func candidateAssetNames(for entry: MasterListEntry) -> [String] {
        var values: [String] = []

        func appendVariants(for raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            var baseForms: [String] = [trimmed]
            baseForms.append(trimmed.replacingOccurrences(of: " Altar", with: ""))
            baseForms.append(trimmed.replacingOccurrences(of: " Mini Levels", with: ""))
            baseForms.append(trimmed.replacingOccurrences(of: " Supercharge", with: ""))
            if let paren = trimmed.firstIndex(of: "(") {
                baseForms.append(String(trimmed[..<paren]).trimmingCharacters(in: .whitespacesAndNewlines))
            }

            for base in baseForms where !base.isEmpty {
                values.append(base)
                values.append(base.lowercased())
                values.append(base.replacingOccurrences(of: " ", with: "_"))
                values.append(base.replacingOccurrences(of: " ", with: "_").lowercased())
                values.append(base.replacingOccurrences(of: " ", with: ""))
                values.append(sanitize(base))
            }
        }

        appendVariants(for: entry.name)
        appendVariants(for: entry.key)

        if let id = entry.id,
           let seasonalArchetype = seasonalModuleArchetypeByID[id] {
            appendVariants(for: seasonalArchetype)
        }

        if let override = assetOverrides[entry.name] {
            appendVariants(for: override)
        }
        if let override = assetOverrides[entry.key] {
            appendVariants(for: override)
        }

        return Array(Set(values)).filter { !$0.isEmpty }
    }

    #if canImport(UIKit)
    private func imageForEntry(_ entry: MasterListEntry, village: Tab) -> UIImage? {
        let candidates = candidateAssetNames(for: entry)

        if village == .builder {
            for candidate in candidates {
                if let image = UIImage(named: "builder_base/\(candidate)") ?? UIImage(named: candidate) {
                    return image
                }
            }

            for candidate in candidates {
                let slug = sanitize(candidate)
                if let assetName = assetLookupByFolder["builder_base"]?[slug],
                   let image = UIImage(named: "builder_base/\(assetName)") ?? UIImage(named: assetName) {
                    return image
                }
            }
            return nil
        }

        let preferredHomeFolders = [
            "buildings_home", "lab", "pets", "heroes", "crafted_defenses", "extras", "town_hall"
        ]

        for folder in preferredHomeFolders {
            for candidate in candidates {
                if let image = UIImage(named: "\(folder)/\(candidate)") {
                    return image
                }
                let slug = sanitize(candidate)
                if let assetName = assetLookupByFolder[folder]?[slug],
                   let image = UIImage(named: "\(folder)/\(assetName)") {
                    return image
                }
            }
        }

        for (folder, folderLookup) in assetLookupByFolder where folder != "builder_base" {
            for candidate in candidates {
                if let image = UIImage(named: "\(folder)/\(candidate)") {
                    return image
                }
                let slug = sanitize(candidate)
                if let assetName = folderLookup[slug], let image = UIImage(named: "\(folder)/\(assetName)") {
                    return image
                }
            }
        }

        for candidate in candidates {
            if UIImage(named: "builder_base/\(candidate)") != nil { continue }
            if let image = UIImage(named: candidate) {
                return image
            }
        }

        return nil
    }

    private func normalizeLookupName(_ value: String?) -> String {
        guard let value else { return "" }
        return value
            .lowercased()
            .replacingOccurrences(of: "mini levels", with: "")
            .replacingOccurrences(of: "supercharge", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private func iconName(forResource rawResource: String?) -> String? {
        guard let rawResource else { return nil }
        let normalized = rawResource
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")

        if normalized.contains("builder") && normalized.contains("gold") { return "builder_gold" }
        if normalized.contains("builder") && normalized.contains("elixir") { return "builder_elixir" }
        if normalized.contains("gold2") { return "builder_gold" }
        if normalized.contains("elixir2") { return "builder_elixir" }
        if normalized.contains("dark") && normalized.contains("elixir") { return "dark_elixir" }
        if normalized.contains("gold") { return "gold" }
        if normalized.contains("elixir") { return "elixir" }
        return nil
    }

    @ViewBuilder
    private func resourceIconView(named name: String) -> some View {
        #if canImport(UIKit)
        if let image = UIImage(named: "resources/\(name)") ?? UIImage(named: name) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "questionmark.circle")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        #else
        Image(systemName: "questionmark.circle")
            .font(.caption2)
            .foregroundColor(.secondary)
        #endif
    }
    #endif
}

struct ProgressOverviewView: View {
    @EnvironmentObject private var dataService: DataService
    @State private var rows: [TownHallProgress] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(rows) { row in
                    Section {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(row.categories) { category in
                                    categoryRow(category: category, townHall: row.level)
                                }
                            }
                            .padding(.vertical, 6)
                        } label: {
                            townHallRow(row)
                        }
                    }
                }

                if !rows.isEmpty {
                    cumulativeSection(title: "Remaining to Current TH", rows: rows.filter { $0.level <= currentTownHall })
                    cumulativeSection(title: "Remaining to Max TH", rows: rows)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Progress")
            .onAppear(perform: reload)
            .refreshable { reload() }
        }
    }

    private var currentTownHall: Int {
        dataService.getTownHallLevel(from: .home)
    }

    private func reload() {
        rows = dataService.townHallProgressRows()
    }

    private func townHallRow(_ row: TownHallProgress) -> some View {
        HStack(spacing: 12) {
            TownHallBadgeView(level: row.level)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("TH \(row.level)")
                        .font(.headline)
                    Spacer()
                    Text(String(format: "%.0f%%", row.overallCompletion * 100))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                ProgressView(value: row.overallCompletion)
                    .progressViewStyle(.linear)
            }
        }
        .padding(.vertical, 4)
    }

    private func categoryRow(category: CategoryProgress, townHall: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                resourceImage(categoryIconName(category.id, townHall: townHall))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                Text(category.title)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.0f%%", category.completion * 100))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ProgressView(value: category.completion)
                .progressViewStyle(.linear)

            HStack(spacing: 10) {
                resourcePill(icon: "gold", value: category.remainingCost.gold)
                resourcePill(icon: "elixir", value: category.remainingCost.elixir)
                resourcePill(icon: "dark_elixir", value: category.remainingCost.darkElixir)
                Spacer()
                timePill(seconds: Int(category.remainingTime))
            }
        }
        .padding(.vertical, 6)
    }

    private func cumulativeSection(title: String, rows: [TownHallProgress]) -> some View {
        let totals = cumulativeTotals(rows: rows)
        return Section(title) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    resourcePill(icon: "gold", value: totals.costs.gold)
                    resourcePill(icon: "elixir", value: totals.costs.elixir)
                    resourcePill(icon: "dark_elixir", value: totals.costs.darkElixir)
                }
                HStack(spacing: 12) {
                    timeSummary(title: "Builder", seconds: totals.builderTime)
                    timeSummary(title: "Lab", seconds: totals.labTime)
                    timeSummary(title: "Pets", seconds: totals.petTime)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func cumulativeTotals(rows: [TownHallProgress]) -> (costs: ResourceTotals, builderTime: TimeInterval, labTime: TimeInterval, petTime: TimeInterval) {
        var costs = ResourceTotals()
        var builderTime: TimeInterval = 0
        var labTime: TimeInterval = 0
        var petTime: TimeInterval = 0

        for row in rows {
            for category in row.categories {
                costs = costs + category.remainingCost
                switch category.id {
                case "buildings": builderTime += category.remainingTime
                case "lab": labTime += category.remainingTime
                case "pets": petTime += category.remainingTime
                default: break
                }
            }
        }

        return (costs, builderTime, labTime, petTime)
    }

    private func timeSummary(title: String, seconds: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                resourceImage("clock")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                Text(formatDuration(Int(seconds)))
                    .font(.caption)
            }
        }
    }

    private func resourcePill(icon: String, value: Int) -> some View {
        HStack(spacing: 2) {
            resourceImage(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
            Text(formatCompactNumber(value))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func timePill(seconds: Int) -> some View {
        HStack(spacing: 2) {
            resourceImage("clock")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
            Text(formatDuration(seconds))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func categoryIconName(_ id: String, townHall: Int) -> String {
        switch id {
        case "buildings": return "builder"
        case "lab": return "lab"
        case "walls": return "wall_\(townHall)"
        case "heroes": return "heroes/Barbarian_King"
        case "pets": return "pet_house"
        default: return "builder"
        }
    }

    private func resourceImage(_ name: String) -> Image {
        #if canImport(UIKit)
        if let image = UIImage(named: name) ?? UIImage(named: "resources/\(name)") {
            return Image(uiImage: image)
        }
        if let last = name.split(separator: "/").last.map(String.init),
           let image = UIImage(named: last) ?? UIImage(named: "resources/\(last)") {
            return Image(uiImage: image)
        }
        return Image(systemName: "questionmark.square")
        #else
        return Image("resources/\(name)")
        #endif
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds <= 0 { return "00d 00h" }
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        return String(format: "%02dd %02dh", days, hours)
    }

    private func formatCompactNumber(_ value: Int) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        switch absValue {
        case 1_000_000_000...:
            return "\(sign)" + String(format: "%.1fB", Double(absValue) / 1_000_000_000)
        case 1_000_000...:
            return "\(sign)" + String(format: "%.1fM", Double(absValue) / 1_000_000)
        case 1_000...:
            return "\(sign)" + String(format: "%.1fK", Double(absValue) / 1_000)
        default:
            return "\(value)"
        }
    }
}

struct TownHallPaletteView: View {
    private let maxTownHallLevel = 18
    @AppStorage("townHallGradientConfig") private var townHallGradientConfigJSON: String = "{}"

    var body: some View {
        NavigationStack {
            List {
                #if canImport(UIKit) && canImport(UIImageColors)
                ForEach(1...maxTownHallLevel, id: \.self) { level in
                    Section {
                        TownHallPaletteRow(
                            level: level,
                            onColorChange: { c1, c2 in
                                setGradientColors(for: level, colorIndex1: c1, colorIndex2: c2)
                            }
                        )
                    }
                }
                #else
                Section {
                    Text("Town Hall palettes require UIImageColors on iOS.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                #endif
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Town Hall Palettes")
        }
    }

    private func setGradientColors(for townHallLevel: Int, colorIndex1: Int, colorIndex2: Int) {
        var config: [Int: [Int]] = [:]
        if let jsonData = townHallGradientConfigJSON.data(using: .utf8) {
            config = (try? JSONDecoder().decode([Int: [Int]].self, from: jsonData)) ?? [:]
        }
        config[townHallLevel] = [colorIndex1, colorIndex2]
        if let jsonData = try? JSONEncoder().encode(config),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            townHallGradientConfigJSON = jsonString
        }
    }
}

#if canImport(UIKit) && canImport(UIImageColors)
private struct TownHallPaletteRow: View {
    let level: Int
    let onColorChange: (Int, Int) -> Void
    @State private var palette: UIImageColors?
    @State private var selectedColor1: Int = 2
    @State private var selectedColor2: Int = 3

    var body: some View {
        let image = townHallImage(for: level)
        let displayImage = image ?? UIImage(systemName: "questionmark.square")
        let swatches = paletteColors

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                if let displayImage {
                    Image(uiImage: displayImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemBackground)))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("TH \(level)")
                        .font(.headline)

                    if !swatches.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(swatches.indices, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(swatches[index]))
                                    .frame(width: 28, height: 28)
                            }
                        }
                    } else {
                        Text("No colors detected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)

            if !swatches.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gradient Colors")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Color 1")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Picker("", selection: $selectedColor1) {
                                Text("Primary (0)").tag(0)
                                Text("Secondary (1)").tag(1)
                                Text("Detail (2)").tag(2)
                                Text("Background (3)").tag(3)
                            }
                            .pickerStyle(.menu)
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Color 2")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Picker("", selection: $selectedColor2) {
                                Text("Primary (0)").tag(0)
                                Text("Secondary (1)").tag(1)
                                Text("Detail (2)").tag(2)
                                Text("Background (3)").tag(3)
                            }
                            .pickerStyle(.menu)
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .onChange(of: selectedColor1) { _, newValue in
                    onColorChange(newValue, selectedColor2)
                }
                .onChange(of: selectedColor2) { _, newValue in
                    onColorChange(selectedColor1, newValue)
                }

                if !swatches.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gradient Preview")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(swatches[selectedColor1]),
                                        Color(swatches[selectedColor2])
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 60)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear(perform: loadPalette)
    }

    private var paletteColors: [UIColor] {
        if let palette {
            return [palette.primary, palette.secondary, palette.detail, palette.background]
                .compactMap { $0 }
        }
        return []
    }

    private func loadPalette() {
        guard palette == nil else { return }
        let image = townHallImage(for: level)
        DispatchQueue.global(qos: .userInitiated).async {
            let colors = image?.getColors(quality: .high)
            DispatchQueue.main.async {
                palette = colors
            }
        }
    }

    private func townHallImage(for level: Int) -> UIImage? {
        guard level > 0 else { return nil }
        let padded = String(format: "%02d", level)
        let candidates = [
            "town_hall/th\(level)",
            "town_hall/\(level)",
            "town_hall/th_\(padded)",
            "town_hall/\(padded)"
        ]
        for name in candidates {
            if let image = UIImage(named: name) {
                return image
            }
        }
        return nil
    }
}
#endif
