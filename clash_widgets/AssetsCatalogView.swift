import SwiftUI

struct AssetRecord: Identifiable, Hashable {
    let id = UUID()
    let slug: String
    let displayName: String
    let dataId: Int?
    let imageExists: Bool
}

struct AssetsCatalogView: View {
    @State private var assets: [AssetRecord] = []
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(assets) { asset in
                        VStack(spacing: 6) {
                            Group {
                                #if canImport(UIKit)
                                if let ui = UIImage(named: asset.slug) {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFit()
                                } else if let ui2 = UIImage(named: "buildings_home/\(asset.slug)") {
                                    Image(uiImage: ui2)
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
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.secondarySystemBackground)))
                    }
                }
                .padding()
            }
            .navigationTitle("Assets Catalog")
            .onAppear(perform: loadAssets)
        }
    }

    // Loads mapping files (json_maps) and asset_map.json to build a list of assets and their IDs.
    private func loadAssets() {
        var records: [AssetRecord] = []

        // Load asset_map.json overrides first
        var assetOverrides: [String: String] = [:]
        if let url = Bundle.main.url(forResource: "asset_map", withExtension: "json") {
            if let data = try? Data(contentsOf: url), let dict = try? JSONDecoder().decode([String: String].self, from: data) {
                assetOverrides = dict
            }
        }

        // Scan known json_map files in upgrade_info/json_maps
        let fm = FileManager.default
        if let mapsURL = Bundle.main.url(forResource: "upgrade_info/json_maps", withExtension: nil) {
            // If subdir is present as resource directory, enumerate
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

                                    // If there's an asset_map override for the display name, use that slug
                                    let overridden = assetOverrides[display] ?? assetOverrides[Self.sanitize(display)]
                                    let finalSlug = overridden ?? slug
                                    let exists = Self.imageExists(named: finalSlug)

                                    let record = AssetRecord(slug: finalSlug, displayName: display, dataId: id, imageExists: exists)
                                    records.append(record)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Also add any asset_map.json entries that weren't covered above
        for (display, slug) in assetOverrides {
            if !records.contains(where: { $0.displayName == display }) {
                let exists = Self.imageExists(named: slug)
                records.append(AssetRecord(slug: slug, displayName: display, dataId: nil, imageExists: exists))
            }
        }

        // Sort: those with IDs first (ascending), then rest alphabetically
        records.sort { lhs, rhs in
            if let li = lhs.dataId, let ri = rhs.dataId { return li < ri }
            if lhs.dataId != nil { return true }
            if rhs.dataId != nil { return false }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        self.assets = records
    }

    private static func sanitize(_ s: String) -> String {
        return s.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
    }

    private static func imageExists(named name: String) -> Bool {
        #if canImport(UIKit)
        return UIImage(named: name) != nil || UIImage(named: "buildings_home/\(name)") != nil
        #else
        return false
        #endif
    }
}

#if DEBUG
struct AssetsCatalogView_Previews: PreviewProvider {
    static var previews: some View {
        AssetsCatalogView()
    }
}
#endif