import SwiftUI
import UIKit
import Foundation

struct BuilderRow: View {
    let upgrade: BuildingUpgrade
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            VStack {
                Image(iconName(for: upgrade))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                Text("Lv \(upgrade.targetLevel - 1) → \(upgrade.targetLevel)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(upgrade.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(upgrade.timeRemaining)
                    .font(.subheadline)
                    .foregroundColor(.orange)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green)
                            .frame(width: geo.size.width * CGFloat(progressFraction(for: upgrade)), height: 8)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(.vertical, 4)
    }

    private func progressFraction(for upgrade: BuildingUpgrade) -> Double {
        let total = max(upgrade.totalDuration, 1)
        let elapsed = Date().timeIntervalSince(upgrade.startTime)
        if elapsed <= 0 { return 0 }
        return min(max(elapsed / total, 0.0), 1.0)
    }

    private func iconName(for upgrade: BuildingUpgrade) -> String {
        let folder: String
        switch upgrade.category {
        case .builderVillage: folder = "buildings_home"
        case .lab: folder = "lab"
        case .pets: folder = "pets"
        case .builderBase: folder = "builder_base"
        }

        func sanitize(_ s: String) -> String {
            return s.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .joined(separator: "_")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        }

        let nameLower = sanitize(upgrade.name.lowercased())
        let nameOriginal = sanitize(upgrade.name)

        var variations: [String] = []
        if let override = AssetNameResolver.shared.assetSlug(for: upgrade.name) {
            variations.append("\(folder)/\(override)")
        }

        // Try precise path and variants with different capitalization
        variations.append(contentsOf: [
            "\(folder)/\(nameOriginal)",
            "\(folder)/\(nameLower)",
            "\(folder)_\(nameOriginal)",
            "\(folder)_\(nameLower)",
            nameOriginal,
            nameLower
        ])

        for variant in variations {
            if UIImage(named: variant) != nil {
                return variant
            }
        }
        
        return "\(folder)/\(nameLower)" // Default fallback
    }
}

private final class AssetNameResolver {
    static let shared = AssetNameResolver()

    private let overrides: [String: String]

    private init() {
        overrides = AssetNameResolver.loadOverrides()
    }

    func assetSlug(for displayName: String) -> String? {
        let key = AssetNameResolver.sanitize(displayName)
        return overrides[key]
    }

    private static func loadOverrides() -> [String: String] {
        func read(from url: URL) -> [String: String]? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String] else { return nil }
            var sanitized: [String: String] = [:]
            for (rawKey, value) in json {
                sanitized[sanitize(rawKey)] = value
            }
            return sanitized
        }

        let bundle = Bundle.main
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: DataService.appGroup)
        let candidates: [URL?] = [
            bundle.url(forResource: "asset_map", withExtension: "json"),
            container?.appendingPathComponent("asset_map.json")
        ]

        for candidate in candidates {
            if let url = candidate, let overrides = read(from: url) {
                return overrides
            }
        }

        return [:]
    }

    private static func sanitize(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }
}