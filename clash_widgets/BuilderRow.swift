import SwiftUI
import UIKit
import Foundation

// In-file AssetResolver for app target (keeps resolver available to app code regardless of project file membership)
final class AppAssetResolver {
    static let shared = AppAssetResolver()
    private var idMap: [Int: String] = [:]

    private init() {
        loadMaps()
    }

    private func loadMaps() {
        let names = ["buildings_json_map", "seasonal_defense_modules_json_map", "seasonal_defense_archetypes_json_map", "spells_json_map", "pets_json_map", "heroes_json_map", "weapons_json_map"]
        for name in names {
            if let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "upgrade_info/json_maps"),
               let data = try? Data(contentsOf: url),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (_, v) in root {
                    if let entry = v as? [String: Any], let id = entry["id"] as? Int, let internalName = entry["internalName"] as? String {
                        idMap[id] = internalName
                    }
                }
            }
        }
        // Load asset_map.json overrides if present in app group
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Zachary-Buschmann.clash-widgets"),
           let overridesData = try? Data(contentsOf: container.appendingPathComponent("asset_map.json")),
           let dict = try? JSONDecoder().decode([String: String].self, from: overridesData) {
            // populate overrides for quick lookup by sanitized key
            for (k, v) in dict { idMap[Int.max - k.hashValue] = v }
        }
    }

    func assetSlug(for name: String) -> String? {
        // Fallback to reading asset_map.json in app group
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Zachary-Buschmann.clash-widgets"),
           let overridesData = try? Data(contentsOf: container.appendingPathComponent("asset_map.json")),
           let dict = try? JSONDecoder().decode([String: String].self, from: overridesData) {
            let key = Self.sanitize(name)
            return dict[name] ?? dict[key]
        }
        return nil
    }

    func assetName(for upgrade: BuildingUpgrade) -> String {
        if let dataId = upgrade.dataId, let internalName = idMap[dataId] {
            return Self.sanitize(internalName)
        }
        return Self.sanitize(upgrade.name)
    }

    private static func sanitize(_ s: String) -> String {
        return s.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
    }
}


struct BuilderRow: View {
    @EnvironmentObject private var dataService: DataService
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
                Text(upgrade.levelDisplayText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(formatBoostedDuration(boostedTotalDuration(for: upgrade)))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(upgrade.name)
                        .font(.headline)
                        .lineLimit(1)
                    if upgrade.showsSuperchargeIcon {
                        Image("extras/supercharge")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    }
                }

                timeRemainingView

                // Progress bar
                ZStack(alignment: .topTrailing) {
                    progressBarView
                    if upgrade.usesGoblin {
                        Image("profile/goblin_builder")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .offset(y: -36)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var progressBarView: some View {
        let remainingSeconds = upgrade.endTime.timeIntervalSinceNow
        if remainingSeconds > 0 && remainingSeconds <= 3600 {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green)
                            .frame(width: geo.size.width * CGFloat(progressFraction(for: upgrade, referenceDate: context.date)), height: 8)
                    }
                }
                .frame(height: 8)
            }
        } else {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green)
                        .frame(width: geo.size.width * CGFloat(progressFraction(for: upgrade, referenceDate: Date())), height: 8)
                }
            }
            .frame(height: 8)
        }
    }

    @ViewBuilder
    private var timeRemainingView: some View {
        let remainingSeconds = effectiveRemainingSeconds(for: upgrade, referenceDate: Date())
        if remainingSeconds > 0 && remainingSeconds <= 3600 {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                Text(formatRemaining(effectiveRemainingSeconds(for: upgrade, referenceDate: context.date)))
                    .font(.subheadline)
                    .foregroundColor(.orange)
            }
        } else {
            Text(formatRemaining(remainingSeconds))
                .font(.subheadline)
                .foregroundColor(.orange)
        }
    }

    private func progressFraction(for upgrade: BuildingUpgrade, referenceDate: Date) -> Double {
        let total = boostedTotalDuration(for: upgrade)
        let remaining = effectiveRemainingSeconds(for: upgrade, referenceDate: referenceDate)
        let elapsed = max(total - remaining, 0)
        return min(max(elapsed / total, 0.0), 1.0)
    }

    private func boostedTotalDuration(for upgrade: BuildingUpgrade) -> TimeInterval {
        let boost = max(0, min(100, dataService.goldPassBoost))
        let factor = max(0.0, 1.0 - (Double(boost) / 100.0))
        return max(upgrade.totalDuration * factor, 1)
    }

    private func effectiveRemainingSeconds(for upgrade: BuildingUpgrade, referenceDate: Date) -> TimeInterval {
        let total = boostedTotalDuration(for: upgrade)
        let actualRemaining = max(0, upgrade.endTime.timeIntervalSince(referenceDate))
        return min(actualRemaining, total)
    }

    private func formatRemaining(_ seconds: TimeInterval) -> String {
        let remaining = Int(max(seconds, 0))
        if remaining <= 0 { return "Complete" }

        let days = remaining / 86400
        let hours = (remaining % 86400) / 3600
        let minutes = (remaining % 3600) / 60
        let secs = remaining % 60

        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }

    private func formatBoostedDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m \(secs)s"
    }

    private func iconName(for upgrade: BuildingUpgrade) -> String {
        let folder: String
        switch upgrade.category {
        case .builderVillage: folder = "buildings_home"
        case .lab: folder = "lab"
        case .starLab: folder = "builder_base"
        case .pets: folder = "pets"
        case .builderBase: folder = "builder_base"
        }

        // Use unified ID-based asset resolver for consistent asset loading
        let assetName = AppAssetResolver.shared.assetName(for: upgrade)
        
        var variations: [String] = []
        // First try with ID-resolved asset name
        variations.append("\(folder)/\(assetName)")
        
        // Then try asset map override
        if let override = AppAssetResolver.shared.assetSlug(for: upgrade.name) {
            variations.append("\(folder)/\(override)")
        }

        // Then try direct asset name
        variations.append(assetName)
        
        // Try variants with different capitalization
        let nameOriginal = upgrade.name.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        variations.append(contentsOf: [
            "\(folder)/\(nameOriginal)",
            "\(folder)/\(assetName)",
            nameOriginal
        ])

        for variant in variations {
            if UIImage(named: variant) != nil {
                return variant
            }
        }
        
        return "\(folder)/\(assetName)" // Default fallback
    }
}

struct IdleBuilderRow: View {
    let builderIndex: Int

    var body: some View {
        HStack(spacing: 12) {
            Image("profile/home_builder")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                Text("Builder \(builderIndex)")
                    .font(.headline)
                Text("Idle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
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