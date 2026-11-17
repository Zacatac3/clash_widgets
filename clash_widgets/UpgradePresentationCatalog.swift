import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// One cached name/icon lookup for imported rows in the app and every widget.
/// Progress owns curated Home Village names and full asset paths; mapping.json
/// supplies entries outside Progress, including Builder Base.
struct UpgradePresentationCatalog {
    private struct File: Decodable {
        struct Section: Decodable {
            struct Group: Decodable {
                struct Item: Decodable {
                    let id: Int
                    let name: String
                    let image: String?
                    let imagePattern: String?
                }
                let assetFolder: String
                let items: [Item]
            }
            let groups: [Group]
        }
        let sections: [Section]
    }

    static let shared = UpgradePresentationCatalog(
        progressData: bundledData("progress_sections"),
        mappingData: bundledData("mapping"),
        assetData: bundledData("asset_map"))

    private(set) var namesByID: [Int: String] = [:]
    private var assetsByID: [Int: String] = [:]
    private var slugsByName: [String: String] = [:]

    init(progressData: Data?, mappingData: Data?, assetData: Data?) {
        let decoder = JSONDecoder()
        if let mappingData, let mapping = try? decoder.decode([String: String].self, from: mappingData) {
            for (id, name) in mapping {
                if let id = Int(id) { namesByID[id] = name }
            }
        }
        if let assetData, let assets = try? decoder.decode([String: String].self, from: assetData) {
            for (name, slug) in assets { slugsByName[Self.sanitize(name)] = slug }
        }
        if let progressData, let file = try? decoder.decode(File.self, from: progressData) {
            for group in file.sections.flatMap(\.groups) {
                for item in group.items {
                    namesByID[item.id] = item.name
                    if let image = item.image ?? item.imagePattern {
                        assetsByID[item.id] = "\(group.assetFolder)/\(image)"
                    }
                }
            }
        }
    }

    func displayName(for upgrade: BuildingUpgrade) -> String {
        // Weapon upgrades share the Town Hall ID but have their own label/icon.
        if upgrade.name == "Town Hall Weapon" { return upgrade.name }
        return upgrade.dataId.flatMap { namesByID[$0] } ?? upgrade.name
    }

    func iconCandidates(for upgrade: BuildingUpgrade) -> [String] {
        let folder: String
        switch upgrade.category {
        case .builderVillage: folder = "buildings_home"
        case .lab: folder = "lab"
        case .pets: folder = "pets"
        case .builderBase, .starLab: folder = "builder_base"
        }
        let name = displayName(for: upgrade)
        let slug = slugsByName[Self.sanitize(name)] ?? Self.sanitize(name)
        var paths: [String] = []
        if upgrade.name != "Town Hall Weapon", let asset = upgrade.dataId.flatMap({ assetsByID[$0] }) {
            paths.append(asset.replacingOccurrences(of: "{level}", with: String(max(1, upgrade.targetLevel))))
        }
        if upgrade.isSeasonalDefense == true || (103_000_000..<104_000_000).contains(upgrade.dataId ?? 0) {
            paths.append("crafted_defenses/\(slug)")
        }
        paths.append(contentsOf: ["\(folder)/\(slug)", slug, "\(folder)/\(Self.sanitize(upgrade.name))"])
        return paths
    }

    #if canImport(UIKit)
    func iconName(for upgrade: BuildingUpgrade) -> String {
        let paths = iconCandidates(for: upgrade)
        return paths.first { UIImage(named: $0) != nil } ?? paths[0]
    }
    #endif

    private static func sanitize(_ value: String) -> String {
        value.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_").trimmingCharacters(in: CharacterSet(charactersIn: "_")).lowercased()
    }

    private static func bundledData(_ name: String) -> Data? {
        for directory: String? in ["json", nil] {
            if let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: directory),
               let data = try? Data(contentsOf: url) { return data }
        }
        return nil
    }
}
