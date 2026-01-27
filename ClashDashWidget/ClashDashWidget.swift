//
//  ClashDashWidget.swift
//  ClashDashWidget
//
//  Created by Zachary Buschmann on 1/7/26.
//

import WidgetKit
import SwiftUI
import UIKit
import AppIntents

// MARK: - Widget Configuration Intent
// MARK: - Profile Selection Options (compile-time static for AppEnum)
enum ProfileSelection: String, AppEnum, CaseDisplayRepresentable {
    case automatic = "automatic"
    case profile1 = "profile1"
    case profile2 = "profile2"
    case profile3 = "profile3"
    case profile4 = "profile4"
    case profile5 = "profile5"
    case profile6 = "profile6"
    case profile7 = "profile7"
    case profile8 = "profile8"
    case profile9 = "profile9"
    case profile10 = "profile10"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Profile"
    
    // Compile-time static display representations (no runtime computation allowed)
    static var caseDisplayRepresentations: [ProfileSelection: DisplayRepresentation] = [
        .automatic: DisplayRepresentation(title: LocalizedStringResource("Last Opened Profile")),
        .profile1: DisplayRepresentation(title: LocalizedStringResource("Profile 1")),
        .profile2: DisplayRepresentation(title: LocalizedStringResource("Profile 2")),
        .profile3: DisplayRepresentation(title: LocalizedStringResource("Profile 3")),
        .profile4: DisplayRepresentation(title: LocalizedStringResource("Profile 4")),
        .profile5: DisplayRepresentation(title: LocalizedStringResource("Profile 5")),
        .profile6: DisplayRepresentation(title: LocalizedStringResource("Profile 6")),
        .profile7: DisplayRepresentation(title: LocalizedStringResource("Profile 7")),
        .profile8: DisplayRepresentation(title: LocalizedStringResource("Profile 8")),
        .profile9: DisplayRepresentation(title: LocalizedStringResource("Profile 9")),
        .profile10: DisplayRepresentation(title: LocalizedStringResource("(unused)"))
    ]
    
    static var allCasesFiltered: [ProfileSelection] {
        var cases: [ProfileSelection] = [.automatic]
        let allCases: [ProfileSelection] = [.profile1, .profile2, .profile3, .profile4, .profile5, .profile6, .profile7, .profile8, .profile9, .profile10]
        
        // Only add cases for profiles that exist
        if let state = PersistentStore.loadState() {
            for (index, _) in state.profiles.enumerated() {
                guard index < allCases.count else { break }
                cases.append(allCases[index])
            }
        }
        
        return cases
    }
    
    func profileID() -> UUID? {
        if self == .automatic {
            return nil // Automatic uses current profile
        }
        
        // Get the index of this case (0 = automatic, 1 = profile1, etc.)
        let allCases: [ProfileSelection] = [.automatic, .profile1, .profile2, .profile3, .profile4, .profile5, .profile6, .profile7, .profile8, .profile9, .profile10]
        guard let index = allCases.firstIndex(of: self), index > 0 else { return nil }
        
        // Get the (index - 1)th profile from persistent store
        if let state = PersistentStore.loadState(), index - 1 < state.profiles.count {
            return state.profiles[index - 1].id
        }
        
        return nil
    }
}

struct WidgetProfileIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Profile"
    static let description: IntentDescription = "Choose which profile this widget displays"
    
    @Parameter(title: "Profile", description: "Select a profile or leave empty for automatic")
    var selectedProfile: ProfileSelection?
    
    func perform() async throws -> some IntentResult {
        let appGroup = "group.Zachary-Buschmann.clash-widgets"
        if let defaults = UserDefaults(suiteName: appGroup) {
            if let profile = selectedProfile, profile != .automatic {
                // Save the selected profile index
                defaults.set(profile.rawValue, forKey: "widget_profile_selection")
            } else {
                // Clear profile selection (use automatic)
                defaults.removeObject(forKey: "widget_profile_selection")
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
        return .result()
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let upgrades: [BuildingUpgrade]
    let builderCount: Int
    let goldPassBoost: Int
    let builderHallLevel: Int
    let debugText: String

    init(date: Date, upgrades: [BuildingUpgrade], builderCount: Int = 5, goldPassBoost: Int = 0, builderHallLevel: Int = 0, debugText: String) {
        self.date = date
        self.upgrades = upgrades
        self.builderCount = builderCount
        self.goldPassBoost = goldPassBoost
        self.builderHallLevel = builderHallLevel
        self.debugText = debugText
    }
}

struct Provider: AppIntentTimelineProvider {
    typealias Intent = WidgetProfileIntent
    typealias Entry = SimpleEntry
    
    let appGroup = "group.Zachary-Buschmann.clash-widgets"

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), upgrades: [], builderCount: 5, goldPassBoost: 0, debugText: "Placeholder")
    }

    func snapshot(for configuration: WidgetProfileIntent, in context: Context) async -> SimpleEntry {
        let (upgrades, builderCount, goldPassBoost) = loadUpgrades(for: configuration)
        let text = loadDebugText(for: configuration)
        return SimpleEntry(date: Date(), upgrades: upgrades, builderCount: builderCount, goldPassBoost: goldPassBoost, debugText: text)
    }

    func timeline(for configuration: WidgetProfileIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let (upgrades, builderCount, goldPassBoost) = loadUpgrades(for: configuration)
        let text = loadDebugText(for: configuration)
        let entry = SimpleEntry(date: Date(), upgrades: upgrades, builderCount: builderCount, goldPassBoost: goldPassBoost, debugText: text)

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        return timeline
    }
    
    private func loadUpgrades(for configuration: WidgetProfileIntent) -> ([BuildingUpgrade], Int, Int) {
        if let state = PersistentStore.loadState() {
            // Determine which profile to use
            let profileToUse: PlayerAccount?
            
            // First check if a profile is selected in the configuration
            var selectedProfileID: UUID? = nil
            if let selectedProfile = configuration.selectedProfile,
               selectedProfile != .automatic,
               let profileID = selectedProfile.profileID() {
                selectedProfileID = profileID
            } else {
                // If no profile selected, try to read from UserDefaults (saved preference)
                let appGroup = "group.Zachary-Buschmann.clash-widgets"
                if let defaults = UserDefaults(suiteName: appGroup),
                   let savedSelection = defaults.string(forKey: "widget_profile_selection") {
                    // Reconstruct the ProfileSelection from saved rawValue
                    if let savedProfile = ProfileSelection(rawValue: savedSelection),
                       savedProfile != .automatic,
                       let profileID = savedProfile.profileID() {
                        selectedProfileID = profileID
                    }
                }
            }
            
            // Load the selected profile or use current
            if let selectedID = selectedProfileID {
                profileToUse = state.profiles.first(where: { $0.id == selectedID })
            } else {
                profileToUse = state.currentProfile
            }
            
            let baseCount = max(profileToUse?.builderCount ?? 5, 0)
            let activeUpgrades = profileToUse?.activeUpgrades ?? []
            let goblinActive = activeUpgrades.contains { $0.category == .builderVillage && $0.usesGoblin }
            let count = baseCount + (goblinActive ? 1 : 0)
            let boost = max(profileToUse?.goldPassBoost ?? 0, 0)
            return (prioritized(upgrades: activeUpgrades, builderCount: count), count, boost)
        }

        let appGroup = "group.Zachary-Buschmann.clash-widgets"
        let sharedDefaults = UserDefaults(suiteName: appGroup)
        guard let data = sharedDefaults?.data(forKey: "saved_upgrades"),
                    let decoded = try? JSONDecoder().decode([BuildingUpgrade].self, from: data) else {
                return ([], 5, 0)
        }
        let goblinActive = decoded.contains { $0.category == .builderVillage && $0.usesGoblin }
        let count = 5 + (goblinActive ? 1 : 0)
        return (prioritized(upgrades: decoded, builderCount: count), count, 0)
    }
    
    private func loadDebugText(for configuration: WidgetProfileIntent) -> String {
        if let state = PersistentStore.loadState() {
            // Determine which profile to use
            let profileToUse: PlayerAccount?
            
            // First check if a profile is selected in the configuration
            var selectedProfileID: UUID? = nil
            if let selectedProfile = configuration.selectedProfile,
               selectedProfile != .automatic,
               let profileID = selectedProfile.profileID() {
                selectedProfileID = profileID
            } else {
                // If no profile selected, try to read from UserDefaults (saved preference)
                let appGroup = "group.Zachary-Buschmann.clash-widgets"
                if let defaults = UserDefaults(suiteName: appGroup),
                   let savedSelection = defaults.string(forKey: "widget_profile_selection") {
                    // Reconstruct the ProfileSelection from saved rawValue
                    if let savedProfile = ProfileSelection(rawValue: savedSelection),
                       savedProfile != .automatic,
                       let profileID = savedProfile.profileID() {
                        selectedProfileID = profileID
                    }
                }
            }
            
            // Load the selected profile or use current
            if let selectedID = selectedProfileID {
                profileToUse = state.profiles.first(where: { $0.id == selectedID })
            } else {
                profileToUse = state.currentProfile
            }
            
            if let name = profileToUse?.displayName, !name.isEmpty {
                return name
            }
            if let tag = profileToUse?.tag, !tag.isEmpty {
                return "#\(tag)"
            }
            return "Clashboard"
        }
        let appGroup = "group.Zachary-Buschmann.clash-widgets"
        let sharedDefaults = UserDefaults(suiteName: appGroup)
        return sharedDefaults?.string(forKey: "widget_simple_text") ?? "No dash data"
    }

    private func prioritized(upgrades: [BuildingUpgrade], builderCount: Int) -> [BuildingUpgrade] {
        // Hard limit to 6 builders displayed in widget to prevent layout overflow
        let displayLimit = min(builderCount, 6)
        return Array(
            upgrades
                .filter { $0.category == .builderVillage }
                .sorted(by: { $0.endTime < $1.endTime })
                .prefix(max(displayLimit, 0))
        )
    }
}

// MARK: - Views
struct ClashDashWidgetEntryView : View {
    var entry: Provider.Entry
    
    var columns: [GridItem] {
        // 4 builders → 2x2 grid, 5-6 builders → 3 columns
        let columnCount = entry.builderCount == 4 ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount)
    }

    var body: some View {
        VStack(spacing: 2) {
            // Dynamic grid: 2x2 for 4 builders, 3x2 for 5-6 builders
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<max(min(entry.builderCount, 6), 0), id: \.self) { index in
                    builderCell(for: index)
                        .frame(minHeight: 68)
                }
            }
            .padding(.horizontal, 6)
            
            // Status line (always visible) - with extra padding on bottom to avoid widget edge
            HStack {
                Spacer()
                if entry.upgrades.count >= entry.builderCount {
                    Text("All Builders Busy")
                        .font(.caption2)
                        .foregroundColor(Color.green)
                        .bold()
                        .lineLimit(1)
                } else {
                    let free = max(entry.builderCount - entry.upgrades.count, 0)
                    let noun = free == 1 ? "builder" : "builders"
                    Text("\(free) \(noun) free!")
                        .font(.caption2)
                        .foregroundColor(Color.orange)
                        .bold()
                        .lineLimit(1)
                }
                Spacer()
            }
            .frame(minHeight: 16)
            .padding(.bottom, 8)
        }
        .padding(12)
        .widgetURL(URL(string: "clashdash://refresh"))
    }
    
    @ViewBuilder
    private func builderCell(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if index < entry.upgrades.count {
                let upgrade = entry.upgrades[index]

                // Name spans full width at top
                HStack(spacing: 2) {
                    Text(upgrade.name)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    if upgrade.showsSuperchargeIcon {
                        Image("extras/supercharge")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 8, height: 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Icon on left, Level + Time on right (same row)
                HStack(spacing: 6) {
                    Image(iconName(for: upgrade))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text(upgrade.levelDisplayText)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        Text(upgrade.timeRemaining)
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                    
                    Spacer()
                }

                // progress bar (thin)
                ProgressView(value: progressFraction(for: upgrade))
                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
                    .frame(height: 4)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green.opacity(0.7))
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Builder \(index + 1)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.gray.opacity(0.6))
                        Text("Available")
                            .font(.system(size: 8))
                            .foregroundColor(.green.opacity(0.7))
                    }
                    
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private func progressFraction(for upgrade: BuildingUpgrade) -> Double {
        goldPassProgressFraction(for: upgrade, boost: entry.goldPassBoost)
    }

    private func iconName(for upgrade: BuildingUpgrade) -> String {
        let folder: String
        switch upgrade.category {
        case .builderVillage: folder = "buildings_home"
        case .lab: folder = "lab"
        case .starLab: folder = "lab"
        case .pets: folder = "pets"
        case .builderBase: folder = "builder_base"
        }

        func sanitize(_ s: String) -> String {
            return s.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .joined(separator: "_")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                .lowercased()
        }

        let sanitizedName = sanitize(upgrade.name)
        
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
}

struct ClashDashWidget: Widget {
    let kind: String = "ClashDashWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                ClashDashWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                ClashDashWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Clash Builders")
        .description("Track Building Upgrades with the widget. Check Settings > Profiles to see which profile number corresponds to your accounts.")
        .supportedFamilies([.systemMedium])
    }
}

private func goldPassProgressFraction(for upgrade: BuildingUpgrade, boost: Int, referenceDate: Date = Date()) -> Double {
    let total = goldPassBoostedTotalDuration(for: upgrade, boost: boost)
    let remaining = goldPassEffectiveRemaining(for: upgrade, referenceDate: referenceDate, totalDuration: total)
    let elapsed = max(total - remaining, 0)
    return min(max(elapsed / total, 0.0), 1.0)
}

private func goldPassBoostedTotalDuration(for upgrade: BuildingUpgrade, boost: Int) -> TimeInterval {
    let clamped = max(0, min(100, boost))
    let factor = max(0.0, 1.0 - (Double(clamped) / 100.0))
    return max(upgrade.totalDuration * factor, 1)
}

private func goldPassEffectiveRemaining(for upgrade: BuildingUpgrade, referenceDate: Date, totalDuration: TimeInterval) -> TimeInterval {
    let actualRemaining = max(0, upgrade.endTime.timeIntervalSince(referenceDate))
    return min(actualRemaining, totalDuration)
}

#Preview(as: .systemMedium) {
    ClashDashWidget()
} timeline: {
    SimpleEntry(date: Date(), upgrades: [], builderCount: 5, debugText: "Preview")
}


// MARK: - Small Widgets

struct LabPetProvider: AppIntentTimelineProvider {
    typealias Intent = WidgetProfileIntent
    typealias Entry = SimpleEntry
    
    let appGroup = "group.Zachary-Buschmann.clash-widgets"

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), upgrades: [], builderCount: 5, debugText: "LabPet")
    }

    func snapshot(for configuration: WidgetProfileIntent, in context: Context) async -> SimpleEntry {
        let upgrades = loadUpgrades(for: configuration)
        return SimpleEntry(date: Date(), upgrades: upgrades, builderCount: 5, debugText: "LabPet")
    }

    func timeline(for configuration: WidgetProfileIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let upgrades = loadUpgrades(for: configuration)
        let entry = SimpleEntry(date: Date(), upgrades: upgrades, builderCount: 5, debugText: "LabPet")
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func loadUpgrades(for configuration: WidgetProfileIntent) -> [BuildingUpgrade] {
        if let state = PersistentStore.loadState() {
            // Determine which profile to use
            let profileToUse: PlayerAccount?
            
            // First check if a profile is selected in the configuration
            var selectedProfileID: UUID? = nil
            if let selectedProfile = configuration.selectedProfile,
               selectedProfile != .automatic,
               let profileID = selectedProfile.profileID() {
                selectedProfileID = profileID
            } else {
                // If no profile selected, try to read from UserDefaults (saved preference)
                let appGroup = "group.Zachary-Buschmann.clash-widgets"
                if let defaults = UserDefaults(suiteName: appGroup),
                   let savedSelection = defaults.string(forKey: "widget_profile_selection") {
                    if let savedProfile = ProfileSelection(rawValue: savedSelection),
                       savedProfile != .automatic,
                       let profileID = savedProfile.profileID() {
                        selectedProfileID = profileID
                    }
                }
            }
            
            // Load the selected profile or use current
            if let selectedID = selectedProfileID {
                profileToUse = state.profiles.first(where: { $0.id == selectedID })
            } else {
                profileToUse = state.currentProfile
            }
            
            let upgrades = profileToUse?.activeUpgrades ?? []
            return filtered(upgrades: upgrades)
        }

        let sharedDefaults = UserDefaults(suiteName: appGroup)
        guard let data = sharedDefaults?.data(forKey: "saved_upgrades"),
              let decoded = try? JSONDecoder().decode([BuildingUpgrade].self, from: data) else {
            return []
        }
        return filtered(upgrades: decoded)
    }

    private func filtered(upgrades: [BuildingUpgrade]) -> [BuildingUpgrade] {
        let filtered = upgrades.filter { $0.category == .lab || $0.category == .pets }
            .sorted(by: { $0.endTime < $1.endTime })
        return Array(filtered.prefix(2))
    }
}

// Helper cooldown small widget
struct HelperCooldownStatus: Identifiable {
    let id: Int
    let name: String
    let iconName: String
    let level: Int
    let cooldownSeconds: Int
    let expiresAt: Date?

    func remainingSeconds(referenceDate: Date = Date()) -> Int {
        if let expiresAt = expiresAt {
            return max(0, Int(expiresAt.timeIntervalSince(referenceDate)))
        }
        return max(0, cooldownSeconds)
    }

    func cooldownText(referenceDate: Date = Date()) -> String {
        let remaining = remainingSeconds(referenceDate: referenceDate)
        if remaining <= 0 { return "Helper ready to work" }
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }
}

struct HelperCooldownWidgetEntry: TimelineEntry {
    let date: Date
    let helpers: [HelperCooldownStatus]
}

struct HelperCooldownProvider: AppIntentTimelineProvider {
    typealias Intent = WidgetProfileIntent
    typealias Entry = HelperCooldownWidgetEntry
    
    let appGroup = "group.Zachary-Buschmann.clash-widgets"

    func placeholder(in context: Context) -> HelperCooldownWidgetEntry {
        HelperCooldownWidgetEntry(date: Date(), helpers: placeholderHelpers())
    }

    func snapshot(for configuration: WidgetProfileIntent, in context: Context) async -> HelperCooldownWidgetEntry {
        HelperCooldownWidgetEntry(date: Date(), helpers: loadHelpers(for: configuration))
    }

    func timeline(for configuration: WidgetProfileIntent, in context: Context) async -> Timeline<HelperCooldownWidgetEntry> {
        let entry = HelperCooldownWidgetEntry(date: Date(), helpers: loadHelpers(for: configuration))

        // Schedule next update based on active helper cooldowns so the widget stays responsive.
        let remainingValues = entry.helpers.map { $0.remainingSeconds() }
        let minRemaining = remainingValues.min() ?? -1
        let nextUpdate: Date
        if minRemaining < 0 {
            // No active helpers: refresh every 15 minutes
            nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        } else if minRemaining <= 30 {
            // Near expiry (within 30 seconds): refresh every 30 seconds to respect widget budget
            nextUpdate = Date().addingTimeInterval(30)
        } else {
            // Active but not urgent: refresh every 5 minutes to respect widget refresh budget
            nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        }

        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func loadHelpers(for configuration: WidgetProfileIntent) -> [HelperCooldownStatus] {
        if let state = PersistentStore.loadState() {
            // Determine which profile to use
            let profileToUse: PlayerAccount?
            
            // First check if a profile is selected in the configuration
            var selectedProfileID: UUID? = nil
            if let selectedProfile = configuration.selectedProfile,
               selectedProfile != .automatic,
               let profileID = selectedProfile.profileID() {
                selectedProfileID = profileID
            } else {
                // If no profile selected, try to read from UserDefaults (saved preference)
                let appGroup = "group.Zachary-Buschmann.clash-widgets"
                if let defaults = UserDefaults(suiteName: appGroup),
                   let savedSelection = defaults.string(forKey: "widget_profile_selection") {
                    if let savedProfile = ProfileSelection(rawValue: savedSelection),
                       savedProfile != .automatic,
                       let profileID = savedProfile.profileID() {
                        selectedProfileID = profileID
                    }
                }
            }
            
            // Load the selected profile or use current
            if let selectedID = selectedProfileID {
                profileToUse = state.profiles.first(where: { $0.id == selectedID })
            } else {
                profileToUse = state.currentProfile
            }
            
            if let rawJSON = profileToUse?.rawJSON, !rawJSON.isEmpty,
               let helpers = parseHelpers(rawJSON: rawJSON) {
                return helpers
            }
        }
        let sharedDefaults = UserDefaults(suiteName: appGroup)
        if let rawJSON = sharedDefaults?.string(forKey: "saved_raw_json"), !rawJSON.isEmpty,
           let helpers = parseHelpers(rawJSON: rawJSON) {
            return helpers
        }
        return []
    }

    private func parseHelpers(rawJSON: String) -> [HelperCooldownStatus]? {
        guard let data = rawJSON.data(using: .utf8),
              let export = try? JSONDecoder().decode(CoCExport.self, from: data) else {
            return nil
        }
        let helpers = export.helpers ?? []

        // Derive an export timestamp if available so helper expiry can be calculated
        let exportDate: Date
        if let ts = export.timestamp {
            exportDate = Date(timeIntervalSince1970: TimeInterval(ts))
        } else {
            exportDate = Date()
        }

        let mapped = helpers.compactMap { helper -> HelperCooldownStatus? in
            let rawSeconds = max(helper.helperCooldown ?? 0, 0)
            let expiresAt = exportDate.addingTimeInterval(TimeInterval(rawSeconds))
            let remaining = max(0, Int(expiresAt.timeIntervalSinceNow))

            switch helper.data {
            case 93000000:
                return HelperCooldownStatus(id: helper.data, name: "Builder's Apprentice", iconName: "profile/apprentice_builder", level: helper.lvl, cooldownSeconds: remaining, expiresAt: expiresAt)
            case 93000001:
                return HelperCooldownStatus(id: helper.data, name: "Lab Assistant", iconName: "profile/lab_assistant", level: helper.lvl, cooldownSeconds: remaining, expiresAt: expiresAt)
            case 93000002:
                return HelperCooldownStatus(id: helper.data, name: "Alchemist", iconName: "profile/alchemist", level: helper.lvl, cooldownSeconds: remaining, expiresAt: expiresAt)
            default:
                return nil
            }
        }
        return mapped.sorted { $0.id < $1.id }
    }

    private func placeholderHelpers() -> [HelperCooldownStatus] {
        [
            HelperCooldownStatus(id: 93000000, name: "Builder's Apprentice", iconName: "profile/apprentice_builder", level: 1, cooldownSeconds: 0, expiresAt: nil),
            HelperCooldownStatus(id: 93000001, name: "Lab Assistant", iconName: "profile/lab_assistant", level: 1, cooldownSeconds: 0, expiresAt: nil),
            HelperCooldownStatus(id: 93000002, name: "Alchemist", iconName: "profile/alchemist", level: 1, cooldownSeconds: 0, expiresAt: nil)
        ]
    }
}

struct HelperCooldownWidgetEntryView: View {
    var entry: HelperCooldownWidgetEntry

    var body: some View {
        let cooldownSeconds = entry.helpers.map { $0.cooldownSeconds }.max() ?? 0
        let totalSeconds = 23 * 60 * 60
        let remaining = max(min(cooldownSeconds, totalSeconds), 0)
        let progress = max(0, min(1, 1 - (Double(remaining) / Double(totalSeconds))))

        return VStack(spacing: 6) {
            HStack {
                Spacer()
                Image("buildings_home/helper_hut")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                Spacer()
            }

            Text("Helper's Hut")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)

            if remaining > 0 && remaining <= 3600 {
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    let remainingNow = entry.helpers.map { helper in
                        helper.remainingSeconds(referenceDate: context.date)
                    }.max() ?? 0
                    let clamped = max(min(remainingNow, totalSeconds), 0)
                    let progressNow = max(0, min(1, 1 - (Double(clamped) / Double(totalSeconds))))

                    VStack(spacing: 3) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 6)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.green)
                                    .frame(width: geo.size.width * CGFloat(progressNow), height: 6)
                            }
                        }
                        .frame(height: 6)

                        // Status on separate line
                        Text(entry.helpers.first?.cooldownText(referenceDate: context.date) ?? (clamped <= 0 ? "Ready to Work" : "0s"))
                            .font(.system(size: 10))
                            .foregroundColor(clamped > 0 ? .orange : .green)
                    }
                }
            } else {
                VStack(spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green)
                                .frame(width: geo.size.width * CGFloat(progress), height: 6)
                        }
                    }
                    .frame(height: 6)

                    // Status on separate line
                    Text(formatHelperCooldown(remaining))
                        .font(.system(size: 10))
                        .foregroundColor(remaining > 0 ? .orange : .green)
                }
            }

            if entry.helpers.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text("No helper data")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .widgetURL(URL(string: "clashdash://refresh"))
    }

    private func formatHelperCooldown(_ seconds: Int) -> String {
        if seconds <= 0 { return "Ready to Work" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }
}

struct HelperCooldownWidget: Widget {
    let kind: String = "HelperCooldownWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: HelperCooldownProvider()) { entry in
            if #available(iOS 17.0, *) {
                HelperCooldownWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                HelperCooldownWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Helper Cooldowns")
        .description("Track helper cooldown timers. Check Settings > Profiles to see which profile number corresponds to your accounts.")
        .supportedFamilies([.systemSmall])
    }
}

struct LabPetWidgetEntryView: View {
    var entry: LabPetProvider.Entry
    let maxSlots = 2

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<maxSlots, id: \.self) { index in
                cell(for: index)
            }

            HStack {
                Spacer()
                if entry.upgrades.count >= maxSlots {
                    Text("All Busy")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.green)
                } else {
                    let free = maxSlots - entry.upgrades.count
                    Text("\(free) free")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.orange)
                }
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(12)
        .widgetURL(URL(string: "clashdash://refresh"))
    }

    @ViewBuilder
    private func cell(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if index < entry.upgrades.count {
                let upgrade = entry.upgrades[index]
                HStack(spacing: 6) {
                    Image(iconName(for: upgrade))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 3) {
                            Text(upgrade.name)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            if upgrade.showsSuperchargeIcon {
                                Image("extras/supercharge")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 8, height: 8)
                            }
                        }
                        Text(upgrade.levelDisplayText)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }

                // Time remaining on separate line
                Text(upgrade.timeRemaining)
                    .font(.system(size: 10))
                    .foregroundColor(.orange)

                ProgressView(value: progressFraction(for: upgrade))
                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
                    .frame(height: 3)
            } else {
                HStack {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("Available")
                        .font(.system(size: 11))
                        .foregroundColor(.green.opacity(0.7))
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func progressFraction(for upgrade: BuildingUpgrade) -> Double {
        goldPassProgressFraction(for: upgrade, boost: entry.goldPassBoost)
    }

    private func iconName(for upgrade: BuildingUpgrade) -> String {
        let folder: String
        switch upgrade.category {
        case .builderVillage: folder = "buildings_home"
        case .lab: folder = "lab"
        case .starLab: folder = "lab"
        case .pets: folder = "pets"
        case .builderBase: folder = "builder_base"
        }

        func sanitize(_ s: String) -> String {
            return s.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .joined(separator: "_")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                .lowercased()
        }

        let sanitizedName = sanitize(upgrade.name)
        
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
}

struct LabPetWidget: Widget {
    let kind: String = "LabPetWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: LabPetProvider()) { entry in
            if #available(iOS 17.0, *) {
                LabPetWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                LabPetWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Lab & Pets")
        .description("Track your laboratory and pet house upgrades. Check Settings > Profiles to see which profile number corresponds to your accounts.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    LabPetWidget()
} timeline: {
    SimpleEntry(date: Date(), upgrades: [], builderCount: 5, debugText: "Preview")
}

// Builder Base small widget (up to 3 slots)
struct BuilderBaseProvider: AppIntentTimelineProvider {
    typealias Intent = WidgetProfileIntent
    typealias Entry = SimpleEntry
    
    let appGroup = "group.Zachary-Buschmann.clash-widgets"

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), upgrades: [], builderCount: 5, debugText: "BuilderBase")
    }

    func snapshot(for configuration: WidgetProfileIntent, in context: Context) async -> SimpleEntry {
        let (upgrades, builderHallLevel) = loadUpgrades(for: configuration)
        return SimpleEntry(date: Date(), upgrades: upgrades, builderCount: 5, builderHallLevel: builderHallLevel, debugText: "BuilderBase")
    }

    func timeline(for configuration: WidgetProfileIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let (upgrades, builderHallLevel) = loadUpgrades(for: configuration)
        let entry = SimpleEntry(date: Date(), upgrades: upgrades, builderCount: 5, builderHallLevel: builderHallLevel, debugText: "BuilderBase")
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func loadUpgrades(for configuration: WidgetProfileIntent) -> ([BuildingUpgrade], Int) {
        let (decoded, builderHallLevel) = loadUpgradesAndBuilderHall(for: configuration)
        let builderSlots = builderHallLevel >= 6 ? 2 : 1
        let labSlots = builderHallLevel >= 6 ? 1 : 0

        let builderUpgrades = decoded
            .filter { $0.category == .builderBase }
            .sorted(by: { $0.endTime < $1.endTime })
        let labUpgrades = decoded
            .filter { $0.category == .starLab }
            .sorted(by: { $0.endTime < $1.endTime })

        let selectedBuilders = Array(builderUpgrades.prefix(builderSlots))
        let selectedLab = Array(labUpgrades.prefix(labSlots))
        return (selectedBuilders + selectedLab, builderHallLevel)
    }

    private func loadUpgradesAndBuilderHall(for configuration: WidgetProfileIntent) -> ([BuildingUpgrade], Int) {
        if let state = PersistentStore.loadState() {
            // Determine which profile to use
            let profileToUse: PlayerAccount?
            
            // First check if a profile is selected in the configuration
            var selectedProfileID: UUID? = nil
            if let selectedProfile = configuration.selectedProfile,
               selectedProfile != .automatic,
               let profileID = selectedProfile.profileID() {
                selectedProfileID = profileID
            } else {
                // If no profile selected, try to read from UserDefaults (saved preference)
                let appGroup = "group.Zachary-Buschmann.clash-widgets"
                if let defaults = UserDefaults(suiteName: appGroup),
                   let savedSelection = defaults.string(forKey: "widget_profile_selection") {
                    if let savedProfile = ProfileSelection(rawValue: savedSelection),
                       savedProfile != .automatic,
                       let profileID = savedProfile.profileID() {
                        selectedProfileID = profileID
                    }
                }
            }
            
            // Load the selected profile or use current
            if let selectedID = selectedProfileID {
                profileToUse = state.profiles.first(where: { $0.id == selectedID })
            } else {
                profileToUse = state.currentProfile
            }
            
            let builderHall = profileToUse?.cachedProfile?.builderHallLevel ?? 0
            return (profileToUse?.activeUpgrades ?? [], builderHall)
        }

        let sharedDefaults = UserDefaults(suiteName: appGroup)
        guard let data = sharedDefaults?.data(forKey: "saved_upgrades"),
              let decoded = try? JSONDecoder().decode([BuildingUpgrade].self, from: data) else {
            return ([], 0)
        }
        return (decoded, 0)
    }
}

struct BuilderBaseWidgetEntryView: View {
    var entry: BuilderBaseProvider.Entry
    var maxSlots: Int { entry.builderHallLevel >= 6 ? 3 : 1 }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<maxSlots, id: \.self) { index in
                cell(for: index)
            }

            HStack {
                Spacer()
                if entry.upgrades.count >= maxSlots {
                    Text("All Busy")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.green)
                } else {
                    let free = maxSlots - entry.upgrades.count
                    Text("\(free) free")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.orange)
                }
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(12)
        .widgetURL(URL(string: "clashdash://refresh"))
    }

    @ViewBuilder
    private func cell(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if index < entry.upgrades.count {
                let upgrade = entry.upgrades[index]
                HStack(spacing: 6) {
                    Image(iconName(for: upgrade))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 3) {
                            Text(upgrade.name)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            if upgrade.showsSuperchargeIcon {
                                Image("extras/supercharge")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 8, height: 8)
                            }
                        }
                        Text(upgrade.levelDisplayText)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }

                // Time remaining on separate line
                Text(upgrade.timeRemaining)
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
                    .bold()

                ProgressView(value: progressFraction(for: upgrade))
                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
                    .frame(height: 2)
            } else {
                HStack {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.gray.opacity(0.4))
                    Text("Available")
                        .font(.system(size: 10))
                        .foregroundColor(.green.opacity(0.6))
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func progressFraction(for upgrade: BuildingUpgrade) -> Double {
        goldPassProgressFraction(for: upgrade, boost: entry.goldPassBoost)
    }

    private func iconName(for upgrade: BuildingUpgrade) -> String {
        let folder: String
        switch upgrade.category {
        case .builderVillage: folder = "buildings_home"
        case .lab: folder = "lab"
        case .starLab: folder = "lab"
        case .pets: folder = "pets"
        case .builderBase: folder = "builder_base"
        }

        func sanitize(_ s: String) -> String {
            return s.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .joined(separator: "_")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                .lowercased()
        }

        let sanitizedName = sanitize(upgrade.name)
        
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
}

struct BuilderBaseWidget: Widget {
    let kind: String = "BuilderBaseWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: BuilderBaseProvider()) { entry in
            if #available(iOS 17.0, *) {
                BuilderBaseWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                BuilderBaseWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Builder Base")
        .description("Track your Builder Base builders and Star Laboratory upgrades. Check Settings > Profiles to see which profile number corresponds to your accounts.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    BuilderBaseWidget()
} timeline: {
    SimpleEntry(date: Date(), upgrades: [], builderCount: 5, debugText: "Preview")
}

