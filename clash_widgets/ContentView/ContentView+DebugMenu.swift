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

            if let url = Bundle.main.url(forResource: "upgrade_info/mapping", withExtension: "json") {
                if let data = try? Data(contentsOf: url), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    for (k, v) in dict {
                        if let id = Int(k), let disp = v as? String {
                            displayToId[disp] = id
                        }
                    }
                }
            }

            if let mapsURL = Bundle.main.url(forResource: "upgrade_info/json_maps", withExtension: nil) {
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
            if let url = Bundle.main.url(forResource: "asset_map", withExtension: "json") {
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

            if let url = Bundle.main.url(forResource: "upgrade_info/mapping", withExtension: "json") {
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
    private enum Tab: String, CaseIterable, Identifiable {
        case home = "Home"
        case builder = "Builder"
        var id: String { rawValue }
    }

    private struct MasterListFile: Decodable {
        let village: String
        let sections: [String: [String: [MasterListEntry]]]
    }

    private struct MasterListEntry: Decodable, Hashable {
        let key: String
        let id: Int?
        let name: String
        let upgradeKind: String
        let buildingType: String?
        let sourceInternalName: String?
    }

    private struct GroupedEntries: Identifiable {
        var id: String { "\(domain)::\(subcategory)" }
        let domain: String
        let subcategory: String
        let entries: [MasterListEntry]
    }

    @State private var selectedTab: Tab = .home
    @State private var homeList: MasterListFile?
    @State private var builderList: MasterListFile?
    @State private var loadError: String?
    @State private var assetLookupByFolder: [String: [String: String]] = [:]

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
                if assetLookupByFolder.isEmpty {
                    buildAssetIndex()
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: MasterListEntry) -> some View {
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
                    Text(entry.upgradeKind)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func groupsForSelectedTab() -> [GroupedEntries] {
        let list = (selectedTab == .home ? homeList : builderList)
        guard let list else { return [] }

        var output: [GroupedEntries] = []
        for (domain, subgroups) in list.sections {
            for (subcategory, entries) in subgroups {
                output.append(GroupedEntries(domain: domain, subcategory: subcategory, entries: entries.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })))
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
        } else {
            loadError = "Could not locate one or both files in upgrade_info/master_lists."
        }
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

    private func sanitize(_ value: String) -> String {
        value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
    }

    private func candidateSlugs(for entry: MasterListEntry) -> [String] {
        var values: [String] = []
        values.append(sanitize(entry.name))
        if let sourceInternalName = entry.sourceInternalName, !sourceInternalName.isEmpty {
            values.append(sanitize(sourceInternalName))
            values.append(sanitize(sourceInternalName.replacingOccurrences(of: " Mini Levels", with: "")))
        }
        if let id = entry.id {
            values.append("id_\(id)")
        }
        return Array(Set(values)).filter { !$0.isEmpty }
    }

    #if canImport(UIKit)
    private func imageForEntry(_ entry: MasterListEntry, village: Tab) -> UIImage? {
        let slugs = candidateSlugs(for: entry)

        if village == .builder {
            for slug in slugs {
                if let assetName = assetLookupByFolder["builder_base"]?[slug],
                   let image = UIImage(named: "builder_base/\(assetName)") ?? UIImage(named: assetName) {
                    return image
                }
            }
            return nil
        }

        for (folder, folderLookup) in assetLookupByFolder where folder != "builder_base" {
            for slug in slugs {
                if let assetName = folderLookup[slug],
                   let image = UIImage(named: "\(folder)/\(assetName)") ?? UIImage(named: assetName) {
                    return image
                }
            }
        }

        for slug in slugs {
            if let image = UIImage(named: slug) {
                return image
            }
        }

        return nil
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
