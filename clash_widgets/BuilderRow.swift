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
        // 1) Prefer runtime app-group overrides (used for temporary overrides during debugging)
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Zachary-Buschmann.clash-widgets"),
           let overridesData = try? Data(contentsOf: container.appendingPathComponent("asset_map.json")),
           let dict = try? JSONDecoder().decode([String: String].self, from: overridesData) {
            let key = Self.sanitize(name)
            if let v = dict[name] ?? dict[key] { return v }
        }

        // 2) Fallback to the bundled asset_map.json (stable mapping shipped with the app)
        if let bundleURL = Bundle.main.url(forResource: "asset_map", withExtension: "json"),
           let data = try? Data(contentsOf: bundleURL),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
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
    @AppStorage("globalShowFullTimerPrecision") private var globalShowFullTimerPrecision = false
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
    }

    @ViewBuilder
    private var timeRemainingView: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            Text(formatRemaining(effectiveRemainingSeconds(for: upgrade, referenceDate: context.date)))
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
        let goldPassFactor = max(0.0, 1.0 - (Double(boost) / 100.0))
        let goldPassBoosted = upgrade.totalDuration * goldPassFactor
        
        return max(goldPassBoosted, 1)
    }

    private func effectiveRemainingSeconds(for upgrade: BuildingUpgrade, referenceDate: Date) -> TimeInterval {
        let baseRemaining = max(0, upgrade.endTime.timeIntervalSince(referenceDate))
        guard let profile = dataService.currentProfile else { return baseRemaining }

        let start = upgrade.startTime
        let now = referenceDate
        if now <= start { return baseRemaining }

        let relevantBoosts = profile.activeBoosts.compactMap { boost -> ActiveBoost? in
            guard let boostType = boost.boostType,
                  boostType.affectedCategories.contains(upgrade.category) else { return nil }
            if boostType == .builderApprentice || boostType == .labAssistant {
                if let targetId = boost.targetUpgradeId, targetId != upgrade.id { return nil }
            }
            return boost
        }
        if relevantBoosts.isEmpty { return baseRemaining }

        var timePoints: [Date] = [start, now]
        for boost in relevantBoosts {
            let s = max(start, boost.startTime)
            let e = min(now, boost.endTime)
            if s < e {
                timePoints.append(s)
                timePoints.append(e)
            }
        }
        let sortedPoints = Array(Set(timePoints)).sorted()
        if sortedPoints.count <= 1 { return baseRemaining }

        var extraElapsed: TimeInterval = 0
        for idx in 0..<(sortedPoints.count - 1) {
            let segmentStart = sortedPoints[idx]
            let segmentEnd = sortedPoints[idx + 1]
            if segmentEnd <= segmentStart { continue }

            var totalExtra: Double = 0
            var clockTowerApplied = false
            for boost in relevantBoosts {
                guard let boostType = boost.boostType else { continue }
                let s = max(start, boost.startTime)
                let e = min(now, boost.endTime)
                if segmentStart < s || segmentStart >= e { continue }

                let level = boost.helperLevel ?? 0
                if boostType.isClockTowerBoost {
                    if !clockTowerApplied {
                        totalExtra += boostType.speedMultiplier(level: level)
                        clockTowerApplied = true
                    }
                } else {
                    totalExtra += boostType.speedMultiplier(level: level)
                }
            }
            extraElapsed += segmentEnd.timeIntervalSince(segmentStart) * totalExtra
        }

        let adjustedRemaining = baseRemaining - extraElapsed
        return max(0, adjustedRemaining)
    }


    private func formatRemaining(_ seconds: TimeInterval) -> String {
        let remaining = Int(max(seconds, 0))
        if remaining <= 0 { return "Complete" }

        let days = remaining / 86400
        let hours = (remaining % 86400) / 3600
        let minutes = (remaining % 3600) / 60
        let secs = remaining % 60
        
        if globalShowFullTimerPrecision {
            if days > 0 { return "\(days)d \(hours)h \(minutes)m \(secs)s" }
            if hours > 0 { return "\(hours)h \(minutes)m \(secs)s" }
            if minutes > 0 { return "\(minutes)m \(secs)s" }
            return "\(secs)s"
        }

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
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

        // Sanitize display name: convert to lowercase and replace non-alphanumerics with underscores
        let sanitizedName = Self.sanitize(upgrade.name)
        
        var variations: [String] = []
        
        // SPECIAL CASE: seasonal defenses (IDs 103000000-104000000) should try crafted_defenses folder first
        if upgrade.isSeasonalDefense == true || (upgrade.dataId ?? 0 >= 103_000_000 && upgrade.dataId ?? 0 < 104_000_000) {
            variations.append("crafted_defenses/\(sanitizedName)")
        }
        
        // Try category-specific folder
        variations.append("\(folder)/\(sanitizedName)")
        
        // Try direct sanitized name
        variations.append(sanitizedName)

        for variant in variations {
            if UIImage(named: variant) != nil {
                return variant
            }
        }
        
        return "\(folder)/\(sanitizedName)" // Default fallback
    }
    
    private static func sanitize(_ s: String) -> String {
        return s.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
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

