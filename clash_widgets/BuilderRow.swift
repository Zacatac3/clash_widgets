import SwiftUI
import UIKit
import Foundation

private final class AppAssetResolver {
    static let shared = AppAssetResolver()
    private let namesByID: [Int: String]
    private let slugsByName: [String: String]

    private init() {
        namesByID = Self.loadNames()
        slugsByName = Self.loadSlugs()
    }

    func displayName(for upgrade: BuildingUpgrade) -> String {
        guard let id = upgrade.dataId,
              (upgrade.isSeasonalDefense == true || (103_000_000..<104_000_000).contains(id)),
              let name = namesByID[id] else { return upgrade.name }
        return name
    }

    func assetSlug(for upgrade: BuildingUpgrade) -> String {
        let name = displayName(for: upgrade)
        return slugsByName[Self.sanitize(name)] ?? Self.sanitize(name)
    }

    private static func loadNames() -> [Int: String] {
        let urls: [URL?] = DataService.candidateFolderURLs(named: "json").map {
            $0.appendingPathComponent("mapping.json")
        } + [
            Bundle.main.url(forResource: "mapping", withExtension: "json", subdirectory: "json"),
            Bundle.main.url(forResource: "mapping", withExtension: "json")
        ]
        for url in urls {
            guard let url,
                  let data = try? Data(contentsOf: url),
                  let raw = try? JSONDecoder().decode([String: String].self, from: data) else { continue }
            return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
                Int(key).map { ($0, value) }
            })
        }
        return [:]
    }

    private static func loadSlugs() -> [String: String] {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: DataService.appGroup)
        let urls: [URL?] = [
            Bundle.main.url(forResource: "asset_map", withExtension: "json", subdirectory: "json"),
            Bundle.main.url(forResource: "asset_map", withExtension: "json"),
            container?.appendingPathComponent("asset_map.json")
        ]
        var slugs: [String: String] = [:]
        for url in urls {
            guard let url,
                  let data = try? Data(contentsOf: url),
                  let raw = try? JSONDecoder().decode([String: String].self, from: data) else { continue }
            for (name, slug) in raw {
                let key = Self.sanitize(name)
                if slugs[key] == nil {
                    slugs[key] = slug
                }
            }
        }
        return slugs
    }

    private static func sanitize(_ s: String) -> String {
        s.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
    }
}


struct BuilderRow: View {
    @EnvironmentObject private var dataService: DataService
    @AppStorage("globalShowFullTimerPrecision") private var globalShowFullTimerPrecision = false
    let upgrade: BuildingUpgrade
    @State private var showingCompletionError = false

    var body: some View {
        rowContent
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    dataService.finishTrackedUpgrade(upgrade.id, completed: false)
                } label: {
                    Label("Cancel", systemImage: "trash")
                }
                Button {
                    completeUpgrade()
                } label: {
                    Label("Complete", systemImage: "checkmark")
                }
                .tint(.blue)
            }
            .contextMenu {
                Button { completeUpgrade() } label: {
                    Label("Complete Upgrade", systemImage: "checkmark")
                }
                Button(role: .destructive) {
                    dataService.finishTrackedUpgrade(upgrade.id, completed: false)
                } label: {
                    Label("Cancel Upgrade", systemImage: "trash")
                }
            }
            .alert("Unable to Update Progress", isPresented: $showingCompletionError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Import a fresh village export so this upgrade can be matched to its Progress entry.")
            }
    }

    private func completeUpgrade() {
        if !dataService.finishTrackedUpgrade(upgrade.id, completed: true) {
            showingCompletionError = true
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            // Icon
            VStack {
                upgradeIconView
                    .frame(width: 36, height: 36)
                Text(upgrade.levelDisplayText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                upgradeDurationLabel
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(AppAssetResolver.shared.displayName(for: upgrade))
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
    private var upgradeIconView: some View {
        #if canImport(UIKit)
        let resolvedName = iconName(for: upgrade)
        if let uiImage = UIImage(named: resolvedName) {
            Image(uiImage: trimTransparentEdges(from: uiImage))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(resolvedName)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        }
        #else
        Image(iconName(for: upgrade))
            .interpolation(.none)
            .resizable()
            .scaledToFit()
        #endif
    }

    #if canImport(UIKit)
    private func trimTransparentEdges(from image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage,
              let dataProvider = cgImage.dataProvider,
              let pixelData = dataProvider.data else {
            return image
        }

        let data = CFDataGetBytePtr(pixelData)
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var foundContent = false

        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * bytesPerRow + x * bytesPerPixel
                let alpha: UInt8
                switch cgImage.alphaInfo {
                case .premultipliedFirst, .first, .noneSkipFirst:
                    alpha = data?[pixelIndex] ?? 0
                case .premultipliedLast, .last, .noneSkipLast:
                    alpha = data?[pixelIndex + bytesPerPixel - 1] ?? 0
                case .none, .alphaOnly:
                    alpha = 255
                @unknown default:
                    alpha = 255
                }

                if alpha > 0 {
                    foundContent = true
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard foundContent,
              minX <= maxX,
              minY <= maxY,
              let croppedCGImage = cgImage.cropping(to: CGRect(
                x: minX,
                y: minY,
                width: maxX - minX + 1,
                height: maxY - minY + 1
              )) else {
            return image
        }

        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
    #endif

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

    @ViewBuilder
    private var upgradeDurationLabel: some View {
        let duration = formatBoostedDuration(boostedTotalDuration(for: upgrade))
        if let factor = upgrade.remoteEventTimeMultiplier, factor < 1 {
            let original = formatBoostedDuration(upgrade.durationBeforeRemoteEvent(goldPassBoost: dataService.goldPassBoost))
            VStack(spacing: 2) {
                Text(original)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                Text(duration)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
            }
            .font(.caption2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Event-reduced duration: \(duration), originally \(original)")
        } else {
            Text(duration)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func boostedTotalDuration(for upgrade: BuildingUpgrade) -> TimeInterval {
        upgrade.effectiveTotalDuration(goldPassBoost: dataService.goldPassBoost)
    }

    private func effectiveRemainingSeconds(for upgrade: BuildingUpgrade, referenceDate: Date) -> TimeInterval {
        upgrade.remainingSeconds(activeBoosts: dataService.currentProfile?.activeBoosts ?? [], referenceDate: referenceDate)
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

        let assetSlug = AppAssetResolver.shared.assetSlug(for: upgrade)
        
        var variations: [String] = []
        
        // SPECIAL CASE: seasonal defenses (IDs 103000000-104000000) should try crafted_defenses folder first
        if upgrade.isSeasonalDefense == true || (upgrade.dataId ?? 0 >= 103_000_000 && upgrade.dataId ?? 0 < 104_000_000) {
            variations.append("crafted_defenses/\(assetSlug)")
        }
        
        // Try category-specific folder
        variations.append("\(folder)/\(assetSlug)")
        
        // Try direct sanitized name
        variations.append(assetSlug)

        for variant in variations {
            if UIImage(named: variant) != nil {
                return variant
            }
        }
        
        return "\(folder)/\(assetSlug)" // Default fallback
    }
}

struct IdleBuilderRow: View {
    let builderIndex: Int
    let titlePrefix: String
    let iconName: String

    init(builderIndex: Int, titlePrefix: String = "Builder", iconName: String = "profile/home_builder") {
        self.builderIndex = builderIndex
        self.titlePrefix = titlePrefix
        self.iconName = iconName
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(titlePrefix) \(builderIndex)")
                    .font(.headline)
                Text("Idle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
