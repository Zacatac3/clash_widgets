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
#if canImport(ControlCenter)
import ControlCenter
#endif

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

// MARK: - Closest Upgrade Widget Intent
enum UpgradeTypeSelection: String, AppEnum, CaseDisplayRepresentable {
    case builders = "builders"
    case lab = "lab"
    case pets = "pets"
    case builderBase = "builderBase"
    case starLab = "starLab"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Upgrade Type"
    static var caseDisplayRepresentations: [UpgradeTypeSelection: DisplayRepresentation] = [
        .builders: DisplayRepresentation(title: LocalizedStringResource("Builders")),
        .lab: DisplayRepresentation(title: LocalizedStringResource("Lab")),
        .pets: DisplayRepresentation(title: LocalizedStringResource("Pet House")),
        .builderBase: DisplayRepresentation(title: LocalizedStringResource("Builder Base Builders")),
        .starLab: DisplayRepresentation(title: LocalizedStringResource("Star Lab"))
    ]
}

struct ClosestUpgradeIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Closest Upgrade"
    static let description: IntentDescription = "Show the closest upgrade to finishing"

    @Parameter(title: "Type", description: "Select upgrade type")
    var upgradeType: UpgradeTypeSelection?

    @Parameter(title: "Profile", description: "Select a profile or leave empty for automatic")
    var selectedProfile: ProfileSelection?
}

// MARK: - Import Clipboard Intent (Lock Screen Action)
struct ImportClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Import Clipboard"
    static let description = IntentDescription("Import village data from clipboard")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        let appGroup = "group.Zachary-Buschmann.clash-widgets"
        if let defaults = UserDefaults(suiteName: appGroup) {
            defaults.set(true, forKey: "widget_import_requested")
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Widget Rendering Mode for Tinted/Clear Modes
// Use desaturated rendering mode to prevent images from becoming solid accent color blobs
struct SimpleEntry: TimelineEntry {
    let date: Date
    let upgrades: [BuildingUpgrade]
    let builderCount: Int
    let goldPassBoost: Int
    let builderHallLevel: Int
    let debugText: String
    let profileName: String
    let townHallLevel: Int
    let activeBoosts: [ActiveBoost]  // Track active boosts for accurate timer calculations

    init(date: Date, upgrades: [BuildingUpgrade], builderCount: Int = 5, goldPassBoost: Int = 0, builderHallLevel: Int = 0, debugText: String, profileName: String = "", townHallLevel: Int = 0, activeBoosts: [ActiveBoost] = []) {
        self.date = date
        self.upgrades = upgrades
        self.builderCount = builderCount
        self.goldPassBoost = goldPassBoost
        self.builderHallLevel = builderHallLevel
        self.debugText = debugText
        self.profileName = profileName
        self.townHallLevel = townHallLevel
        self.activeBoosts = activeBoosts
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
        let (upgrades, builderCount, goldPassBoost, activeBoosts) = loadUpgrades(for: configuration)
        let text = loadDebugText(for: configuration)
        let (profileName, townHallLevel) = loadProfileInfo(for: configuration)
        return SimpleEntry(date: Date(), upgrades: upgrades, builderCount: builderCount, goldPassBoost: goldPassBoost, debugText: text, profileName: profileName, townHallLevel: townHallLevel, activeBoosts: activeBoosts)
    }

    func timeline(for configuration: WidgetProfileIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let (upgrades, builderCount, goldPassBoost, activeBoosts) = loadUpgrades(for: configuration)
        let text = loadDebugText(for: configuration)
        let (profileName, townHallLevel) = loadProfileInfo(for: configuration)
        let entry = SimpleEntry(date: Date(), upgrades: upgrades, builderCount: builderCount, goldPassBoost: goldPassBoost, debugText: text, profileName: profileName, townHallLevel: townHallLevel, activeBoosts: activeBoosts)

        // Dynamic refresh policy based on active boosts and urgency
        let nextUpdate: Date
        let now = Date()
        
        // Check if any boosts are active that affect these upgrades
        let hasActiveBoosts = activeBoosts.contains { $0.endTime > now }
        
        // Find the closest upgrade completion time (accounting for boosts)
        var minRemaining: TimeInterval = .infinity
        for upgrade in upgrades {
            let remaining = effectiveRemainingSeconds(for: upgrade, activeBoosts: activeBoosts, referenceDate: now)
            if remaining > 0 && remaining < minRemaining {
                minRemaining = remaining
            }
        }
        
        if hasActiveBoosts {
            // When boosts are active, refresh more frequently to keep timers accurate
            if minRemaining <= 60 {
                // Very close to completion: refresh every 30 seconds
                nextUpdate = now.addingTimeInterval(30)
            } else if minRemaining <= 300 {
                // Within 5 minutes: refresh every minute
                nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: now)!
            } else {
                // Active boost but not urgent: refresh every 5 minutes
                nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: now)!
            }
        } else {
            // No boosts active, check urgency based on raw time
            if minRemaining <= 300 {
                // Within 5 minutes of completion: refresh every minute
                nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: now)!
            } else {
                // Standard refresh: every 15 minutes
                nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: now)!
            }
        }
        
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
    
    private func loadUpgrades(for configuration: WidgetProfileIntent) -> ([BuildingUpgrade], Int, Int, [ActiveBoost]) {
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
            let activeBoosts = profileToUse?.activeBoosts ?? []
            let goblinActive = activeUpgrades.contains { $0.category == .builderVillage && $0.usesGoblin }
            let count = baseCount + (goblinActive ? 1 : 0)
            let boost = max(profileToUse?.goldPassBoost ?? 0, 0)
            return (prioritized(upgrades: activeUpgrades, builderCount: count), count, boost, activeBoosts)
        }

        let appGroup = "group.Zachary-Buschmann.clash-widgets"
        let sharedDefaults = UserDefaults(suiteName: appGroup)
        guard let data = sharedDefaults?.data(forKey: "saved_upgrades"),
                    let decoded = try? JSONDecoder().decode([BuildingUpgrade].self, from: data) else {
                return ([], 5, 0, [])
        }
        let goblinActive = decoded.contains { $0.category == .builderVillage && $0.usesGoblin }
        let count = 5 + (goblinActive ? 1 : 0)
        return (prioritized(upgrades: decoded, builderCount: count), count, 0, [])
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

    private func loadProfileInfo(for configuration: WidgetProfileIntent) -> (profileName: String, townHallLevel: Int) {
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
            
            let profileName = profileToUse?.displayName ?? (profileToUse?.tag ?? "Profile")
            let townHall = profileToUse?.cachedProfile?.townHallLevel ?? 0
            return (profileName, townHall)
        }
        return ("Profile", 0)
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
            // Center align bottom row for exactly 5 builders
            .frame(maxWidth: .infinity, alignment: entry.builderCount == 5 ? .center : .leading)
            .padding(.horizontal, 6)
            
            // Status line (always visible) - with extra padding on bottom to avoid widget edge
            HStack {
                Spacer()
                if entry.upgrades.count >= entry.builderCount {
                    let statusText = "All Builders Busy"
                    if !entry.profileName.isEmpty {
                        Text(statusText + " • " + entry.profileName)
                            .font(.caption2)
                            .foregroundColor(Color.green)
                            .bold()
                            .lineLimit(1)
                    } else {
                        Text(statusText)
                            .font(.caption2)
                            .foregroundColor(Color.green)
                            .bold()
                            .lineLimit(1)
                    }
                } else {
                    let free = max(entry.builderCount - entry.upgrades.count, 0)
                    let noun = free == 1 ? "builder" : "builders"
                    let statusText = "\(free) \(noun) free"
                    if !entry.profileName.isEmpty {
                        Text(statusText + " • " + entry.profileName)
                            .font(.caption2)
                            .foregroundColor(Color.orange)
                            .bold()
                            .lineLimit(1)
                    } else {
                        Text(statusText + "!")
                            .font(.caption2)
                            .foregroundColor(Color.orange)
                            .bold()
                            .lineLimit(1)
                    }
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
                        Text(formatBoostedTimeRemaining(for: upgrade, activeBoosts: entry.activeBoosts))
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
        boostedProgressFraction(for: upgrade, activeBoosts: entry.activeBoosts, goldPassBoost: entry.goldPassBoost)
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

// MARK: - Lock Screen Closest Upgrade Widget
struct ClosestUpgradeEntry: TimelineEntry {
    let date: Date
    let upgrade: BuildingUpgrade?
    let typeLabel: String
    let activeBoosts: [ActiveBoost]  // Track active boosts for accurate timer calculations
}

struct ClosestUpgradeProvider: AppIntentTimelineProvider {
    typealias Intent = ClosestUpgradeIntent
    typealias Entry = ClosestUpgradeEntry

    func placeholder(in context: Context) -> ClosestUpgradeEntry {
        ClosestUpgradeEntry(date: Date(), upgrade: nil, typeLabel: "Builders", activeBoosts: [])
    }

    func snapshot(for configuration: ClosestUpgradeIntent, in context: Context) async -> ClosestUpgradeEntry {
        let upgrade = loadClosestUpgrade(for: configuration)
        let activeBoosts = loadActiveBoosts(for: configuration)
        return ClosestUpgradeEntry(date: Date(), upgrade: upgrade, typeLabel: label(for: configuration.upgradeType ?? .builders), activeBoosts: activeBoosts)
    }

    func timeline(for configuration: ClosestUpgradeIntent, in context: Context) async -> Timeline<ClosestUpgradeEntry> {
        let upgrade = loadClosestUpgrade(for: configuration)
        let activeBoosts = loadActiveBoosts(for: configuration)
        let entry = ClosestUpgradeEntry(date: Date(), upgrade: upgrade, typeLabel: label(for: configuration.upgradeType ?? .builders), activeBoosts: activeBoosts)
        
        // Adjust refresh rate based on boost activity
        let hasActiveBoosts = !activeBoosts.isEmpty
        let minutes = hasActiveBoosts ? 1 : 15  // Refresh every 1 min with boosts, 15 min otherwise
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: minutes, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func loadClosestUpgrade(for configuration: ClosestUpgradeIntent) -> BuildingUpgrade? {
        guard let state = PersistentStore.loadState() else { return nil }

        let profileToUse: PlayerAccount?
        var selectedProfileID: UUID? = nil
        if let selectedProfile = configuration.selectedProfile,
           selectedProfile != .automatic,
           let profileID = selectedProfile.profileID() {
            selectedProfileID = profileID
        } else {
            let appGroup = "group.Zachary-Buschmann.clash-widgets"
            if let defaults = UserDefaults(suiteName: appGroup),
               let savedSelection = defaults.string(forKey: "widget_profile_selection"),
               let savedProfile = ProfileSelection(rawValue: savedSelection),
               savedProfile != .automatic,
               let profileID = savedProfile.profileID() {
                selectedProfileID = profileID
            }
        }

        if let selectedID = selectedProfileID {
            profileToUse = state.profiles.first(where: { $0.id == selectedID })
        } else {
            profileToUse = state.currentProfile
        }

        let upgrades = profileToUse?.activeUpgrades ?? []
        let type = configuration.upgradeType ?? .builders
        let filtered = upgrades.filter { matchesType($0, type: type) }
        return filtered.sorted(by: { $0.endTime < $1.endTime }).first
    }
    
    private func loadActiveBoosts(for configuration: ClosestUpgradeIntent) -> [ActiveBoost] {
        guard let state = PersistentStore.loadState() else { return [] }

        let profileToUse: PlayerAccount?
        var selectedProfileID: UUID? = nil
        if let selectedProfile = configuration.selectedProfile,
           selectedProfile != .automatic,
           let profileID = selectedProfile.profileID() {
            selectedProfileID = profileID
        } else {
            let appGroup = "group.Zachary-Buschmann.clash-widgets"
            if let defaults = UserDefaults(suiteName: appGroup),
               let savedSelection = defaults.string(forKey: "widget_profile_selection"),
               let savedProfile = ProfileSelection(rawValue: savedSelection),
               savedProfile != .automatic,
               let profileID = savedProfile.profileID() {
                selectedProfileID = profileID
            }
        }

        if let selectedID = selectedProfileID {
            profileToUse = state.profiles.first(where: { $0.id == selectedID })
        } else {
            profileToUse = state.currentProfile
        }

        return profileToUse?.activeBoosts ?? []
    }

    private func matchesType(_ upgrade: BuildingUpgrade, type: UpgradeTypeSelection) -> Bool {
        switch type {
        case .builders:
            return upgrade.category == .builderVillage
        case .lab:
            return upgrade.category == .lab
        case .pets:
            return upgrade.category == .pets
        case .builderBase:
            return upgrade.category == .builderBase
        case .starLab:
            return upgrade.category == .starLab
        }
    }

    private func label(for type: UpgradeTypeSelection) -> String {
        switch type {
        case .builders: return "Builders"
        case .lab: return "Lab"
        case .pets: return "Pet House"
        case .builderBase: return "Builder Base"
        case .starLab: return "Star Lab"
        }
    }
}

struct ClosestUpgradeWidgetEntryView: View {
    var entry: ClosestUpgradeEntry

    var body: some View {
        if let upgrade = entry.upgrade {
            HStack(spacing: 8) {
                Image(iconName(for: upgrade))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.typeLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(upgrade.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(formatBoostedTimeRemaining(for: upgrade, activeBoosts: entry.activeBoosts))
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    ProgressView(value: progressFraction(for: upgrade))
                        .progressViewStyle(.linear)
                }
                Spacer()
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.typeLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("No active upgrades")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
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

        if upgrade.isSeasonalDefense == true || (upgrade.dataId ?? 0 >= 103_000_000 && upgrade.dataId ?? 0 < 104_000_000) {
            variations.append("crafted_defenses/\(sanitizedName)")
        }
        variations.append("\(folder)/\(sanitizedName)")
        variations.append(sanitizedName)

        for variant in variations {
            if UIImage(named: variant) != nil { return variant }
        }
        return "\(folder)/\(sanitizedName)"
    }

    private func progressFraction(for upgrade: BuildingUpgrade) -> Double {
        boostedProgressFraction(for: upgrade, activeBoosts: entry.activeBoosts, goldPassBoost: 0)
    }
}

struct ClosestUpgradeWidget: Widget {
    let kind: String = "ClosestUpgradeWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ClosestUpgradeIntent.self, provider: ClosestUpgradeProvider()) { entry in
            if #available(iOS 17.0, *) {
                ClosestUpgradeWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                ClosestUpgradeWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Closest Upgrade")
        .description("Shows the closest upgrade to finishing for a selected type and profile.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Lock Screen Import Toggle Widget
// Import action is exposed as a Control (not a widget)

// MARK: - Clan War Lock Screen Widget
struct WarStatusEntry: TimelineEntry {
    let date: Date
    let war: WarDetails?
}

struct WarStatusProvider: AppIntentTimelineProvider {
    typealias Intent = WidgetProfileIntent
    
    func placeholder(in context: Context) -> WarStatusEntry {
        WarStatusEntry(date: Date(), war: nil)
    }

    func snapshot(for configuration: WidgetProfileIntent, in context: Context) -> WarStatusEntry {
        WarStatusEntry(date: Date(), war: loadWar(for: configuration))
    }

    func timeline(for configuration: WidgetProfileIntent, in context: Context) async -> Timeline<WarStatusEntry> {
        let entry = WarStatusEntry(date: Date(), war: loadWar(for: configuration))
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func loadWar(for configuration: WidgetProfileIntent) -> WarDetails? {
        let defaults = UserDefaults(suiteName: "group.Zachary-Buschmann.clash-widgets")
        
        // Get the profile ID to load war data for
        let profileID: UUID? = {
            if let selected = configuration.selectedProfile, selected != .automatic {
                return selected.profileID()
            }
            return nil
        }()
        
        // If specific profile is selected, load its war data
        if let profileID = profileID,
           let state = PersistentStore.loadState(),
           let profile = state.profiles.first(where: { $0.id == profileID }),
           let warData = defaults?.data(forKey: "war_json_\(profile.tag)") {
            return try? JSONDecoder().decode(WarDetails.self, from: warData)
        }
        
        // Otherwise, fall back to current war data
        guard let data = defaults?.data(forKey: "current_war_json") else { return nil }
        return try? JSONDecoder().decode(WarDetails.self, from: data)
    }
}

struct WarStatusWidgetEntryView: View {
    var entry: WarStatusEntry

    var body: some View {
        if let war = entry.war,
           let clan = war.clan,
           let opponent = war.opponent {
            let phase = warPhase(for: war)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(clan.name)
                        .font(.caption)
                        .bold()
                    Spacer()
                    Text("\(clan.stars ?? 0)-\(opponent.stars ?? 0)")
                        .font(.caption)
                        .bold()
                }
                ProgressView(value: phase.progress)
                    .progressViewStyle(.linear)
                
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    if let timer = warTimerLabel(for: war, referenceDate: context.date) {
                        Text(timer)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text(phase.label)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } else {
            Text("No war data")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private struct WarPhaseInfo {
        let label: String
        let progress: Double
    }

    private func warPhase(for war: WarDetails) -> WarPhaseInfo {
        let now = Date()
        let prepStart = parseWarDate(war.preparationStartTime)
        let start = parseWarDate(war.startTime)
        let end = parseWarDate(war.endTime)

        if let prepStart, let start, now < start {
            let total = max(start.timeIntervalSince(prepStart), 1)
            let progress = min(max(now.timeIntervalSince(prepStart) / total, 0), 1)
            return WarPhaseInfo(label: "Preparation", progress: progress)
        }
        if let start, let end, now >= start, now < end {
            let total = max(end.timeIntervalSince(start), 1)
            let progress = min(max(now.timeIntervalSince(start) / total, 0), 1)
            return WarPhaseInfo(label: "Battle", progress: progress)
        }
        if let end, now >= end {
            return WarPhaseInfo(label: "Ended", progress: 1)
        }
        return WarPhaseInfo(label: "Status", progress: 0)
    }

    private func warTimerLabel(for war: WarDetails, referenceDate: Date) -> String? {
        let now = referenceDate
        let start = parseWarDate(war.startTime)
        let end = parseWarDate(war.endTime)

        if let _ = parseWarDate(war.preparationStartTime), let start, now < start {
            let remaining = start.timeIntervalSince(now)
            return formatTimeRemaining(remaining, label: "Prep")
        }
        if let start, let end, now >= start, now < end {
            let remaining = end.timeIntervalSince(now)
            return formatTimeRemaining(remaining, label: "Battle")
        }
        if let end, now >= end {
            return "War Ended"
        }
        return nil
    }

    private func formatTimeRemaining(_ seconds: TimeInterval, label: String) -> String {
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if days > 0 {
            return "\(label) - \(days)d \(hours)h"
        } else if hours > 0 {
            return "\(label) - \(hours)h \(minutes)m"
        } else {
            return "\(label) - \(minutes)m"
        }
    }

    private func parseWarDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return formatter.date(from: value)
    }
}

struct WarStatusWidget: Widget {
    let kind: String = "WarStatusWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: WarStatusProvider()) { entry in
            if #available(iOS 17.0, *) {
                WarStatusWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                WarStatusWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Clan War Status")
        .description("Shows the current clan war status and progress.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Lock Screen War Widget (2x2 variant)
struct WarStatusSmallWidgetEntryView: View {
    var entry: WarStatusEntry

    var body: some View {
        if let war = entry.war,
           let clan = war.clan,
           let opponent = war.opponent {
            let phase = warPhase(for: war)
            VStack(alignment: .center, spacing: 3) {
                HStack(spacing: 2) {
                    Text(String(clan.name.prefix(1)))
                        .font(.caption2)
                        .bold()
                    Spacer()
                    Text("\(clan.stars ?? 0)-\(opponent.stars ?? 0)")
                        .font(.caption2)
                        .bold()
                    Spacer()
                    Text(String(opponent.name.prefix(1)))
                        .font(.caption2)
                        .bold()
                }
                ProgressView(value: phase.progress)
                    .progressViewStyle(.linear)
                    .frame(height: 4)
                
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    if let timer = warTimerLabel(for: war, referenceDate: context.date) {
                        Text(timer)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text(phase.label)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(6)
        } else {
            Text("No war")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private struct WarPhaseInfo {
        let label: String
        let progress: Double
    }

    private func warPhase(for war: WarDetails) -> WarPhaseInfo {
        let now = Date()
        let prepStart = parseWarDate(war.preparationStartTime)
        let start = parseWarDate(war.startTime)
        let end = parseWarDate(war.endTime)

        if let prepStart, let start, now < start {
            let total = max(start.timeIntervalSince(prepStart), 1)
            let progress = min(max(now.timeIntervalSince(prepStart) / total, 0), 1)
            return WarPhaseInfo(label: "Prep", progress: progress)
        }
        if let start, let end, now >= start, now < end {
            let total = max(end.timeIntervalSince(start), 1)
            let progress = min(max(now.timeIntervalSince(start) / total, 0), 1)
            return WarPhaseInfo(label: "Battle", progress: progress)
        }
        if let end, now >= end {
            return WarPhaseInfo(label: "Ended", progress: 1)
        }
        return WarPhaseInfo(label: "Status", progress: 0)
    }

    private func warTimerLabel(for war: WarDetails, referenceDate: Date) -> String? {
        let now = referenceDate
        let start = parseWarDate(war.startTime)
        let end = parseWarDate(war.endTime)

        if let _ = parseWarDate(war.preparationStartTime), let start, now < start {
            let remaining = start.timeIntervalSince(now)
            return formatTimeRemaining(remaining)
        }
        if let start, let end, now >= start, now < end {
            let remaining = end.timeIntervalSince(now)
            return formatTimeRemaining(remaining)
        }
        return nil
    }

    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func parseWarDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return formatter.date(from: value)
    }
}

struct WarStatusSmallWidget: Widget {
    let kind: String = "WarStatusSmallWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: WarStatusProvider()) { entry in
            if #available(iOS 17.0, *) {
                WarStatusSmallWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                WarStatusSmallWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Clan War (Compact)")
        .description("Shows clan war in a compact 2x2 lock screen format.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Control Center Import Control (iOS 18+)
#if canImport(ControlCenter)
@available(iOS 18.0, *)
struct ImportClipboardControlProvider: AppIntentControlValueProvider {
    typealias Intent = ImportClipboardIntent
    typealias Value = Bool

    func value(for configuration: ImportClipboardIntent) async throws -> Bool {
        false
    }
}

@available(iOS 18.0, *)
struct ImportClipboardControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: "ImportClipboardControl",
            provider: ImportClipboardControlProvider()
        ) { _ in
            ControlWidgetButton(intent: ImportClipboardIntent()) {
                ZStack {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 22, weight: .semibold))
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                        .offset(x: 10, y: 10)
                }
            }
        }
        .displayName("Import Clipboard")
        .description("Paste & import your village data.")
    }
}
#endif

// MARK: - Boost-Aware Time Calculations

/// Calculate effective remaining time accounting for active boosts (potions, clock tower, helpers)
/// This ensures widget timers match the boosted times shown in the app
private func effectiveRemainingSeconds(for upgrade: BuildingUpgrade, activeBoosts: [ActiveBoost], referenceDate: Date) -> TimeInterval {
    let baseRemaining = max(0, upgrade.endTime.timeIntervalSince(referenceDate))
    
    let start = upgrade.startTime
    let now = referenceDate
    if now <= start { return baseRemaining }
    
    // Filter boosts that affect this upgrade's category
    let relevantBoosts = activeBoosts.compactMap { boost -> ActiveBoost? in
        guard let boostType = boost.boostType,
              boostType.affectedCategories.contains(upgrade.category) else { return nil }
        // For targeted boosts (builder's apprentice), only include if it targets this upgrade
        if boostType == .builderApprentice || boostType == .labAssistant {
            if let targetId = boost.targetUpgradeId, targetId != upgrade.id { return nil }
        }
        return boost
    }
    
    if relevantBoosts.isEmpty { return baseRemaining }
    
    // Build timeline of boost periods
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
    
    // Calculate extra elapsed time from boosts
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

/// Get the actual completion time accounting for boosts
private func effectiveCompletionDate(for upgrade: BuildingUpgrade, activeBoosts: [ActiveBoost], referenceDate: Date = Date()) -> Date {
    let boostedRemaining = effectiveRemainingSeconds(for: upgrade, activeBoosts: activeBoosts, referenceDate: referenceDate)
    return referenceDate.addingTimeInterval(boostedRemaining)
}

/// Format time remaining with boost calculations applied
private func formatBoostedTimeRemaining(for upgrade: BuildingUpgrade, activeBoosts: [ActiveBoost], referenceDate: Date = Date()) -> String {
    let remaining = effectiveRemainingSeconds(for: upgrade, activeBoosts: activeBoosts, referenceDate: referenceDate)
    if remaining <= 0 { return "Complete" }
    
    let days = Int(remaining) / 86400
    let hours = (Int(remaining) % 86400) / 3600
    let minutes = (Int(remaining) % 3600) / 60
    
    if days > 0 {
        return "\(days)d \(hours)h"
    } else if hours > 0 {
        return "\(hours)h \(minutes)m"
    } else if minutes > 0 {
        let seconds = (Int(remaining) % 60)
        return String(format: "%dm %02ds", minutes, seconds)
    } else {
        let seconds = max(Int(remaining.rounded()), 0)
        return "\(seconds)s"
    }
}

/// Calculate boost-aware progress fraction for progress bars
/// Uses the boosted remaining time to show accurate progress when potions/helpers are active
private func boostedProgressFraction(for upgrade: BuildingUpgrade, activeBoosts: [ActiveBoost], goldPassBoost: Int = 0, referenceDate: Date = Date()) -> Double {
    // Get the boost-adjusted remaining time
    let boostedRemaining = effectiveRemainingSeconds(for: upgrade, activeBoosts: activeBoosts, referenceDate: referenceDate)
    
    // Calculate the effective total duration (with gold pass applied)
    let goldPassFactor = max(0.0, 1.0 - (Double(max(0, min(100, goldPassBoost))) / 100.0))
    let effectiveTotal = max(upgrade.totalDuration * goldPassFactor, 1)
    
    // Calculate elapsed time based on boosted remaining
    let elapsed = max(effectiveTotal - boostedRemaining, 0)
    
    return min(max(elapsed / effectiveTotal, 0.0), 1.0)
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
        let (upgrades, activeBoosts) = loadUpgradesAndBoosts(for: configuration)
        let (profileName, _) = loadProfileInfo(for: configuration)
        return SimpleEntry(date: Date(), upgrades: upgrades, builderCount: 5, debugText: "LabPet", profileName: profileName, townHallLevel: 0, activeBoosts: activeBoosts)
    }

    func timeline(for configuration: WidgetProfileIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let (upgrades, activeBoosts) = loadUpgradesAndBoosts(for: configuration)
        let (profileName, _) = loadProfileInfo(for: configuration)
        let entry = SimpleEntry(date: Date(), upgrades: upgrades, builderCount: 5, debugText: "LabPet", profileName: profileName, townHallLevel: 0, activeBoosts: activeBoosts)
        
        // Adjust refresh rate based on boost activity
        let hasActiveBoosts = !activeBoosts.isEmpty
        let minutes = hasActiveBoosts ? 1 : 15  // Refresh every 1 min with boosts, 15 min otherwise
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: minutes, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func loadUpgradesAndBoosts(for configuration: WidgetProfileIntent) -> ([BuildingUpgrade], [ActiveBoost]) {
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
            let activeBoosts = profileToUse?.activeBoosts ?? []
            return (filtered(upgrades: upgrades), activeBoosts)
        }

        let sharedDefaults = UserDefaults(suiteName: appGroup)
        guard let data = sharedDefaults?.data(forKey: "saved_upgrades"),
              let decoded = try? JSONDecoder().decode([BuildingUpgrade].self, from: data) else {
            return ([], [])
        }
        return (filtered(upgrades: decoded), [])
    }

    private func loadUpgrades(for configuration: WidgetProfileIntent) -> [BuildingUpgrade] {
        return loadUpgradesAndBoosts(for: configuration).0
    }

    private func filtered(upgrades: [BuildingUpgrade]) -> [BuildingUpgrade] {
        let filtered = upgrades.filter { $0.category == .lab || $0.category == .pets }
            .sorted(by: { $0.endTime < $1.endTime })
        return Array(filtered.prefix(2))
    }

    private func loadProfileInfo(for configuration: WidgetProfileIntent) -> (profileName: String, townHallLevel: Int) {
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
            
            let profileName = profileToUse?.displayName ?? (profileToUse?.tag ?? "Profile")
            let townHall = profileToUse?.cachedProfile?.townHallLevel ?? 0
            return (profileName, townHall)
        }
        return ("Profile", 0)
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
    let profileName: String
}

struct HelperCooldownProvider: AppIntentTimelineProvider {
    typealias Intent = WidgetProfileIntent
    typealias Entry = HelperCooldownWidgetEntry
    
    let appGroup = "group.Zachary-Buschmann.clash-widgets"

    func placeholder(in context: Context) -> HelperCooldownWidgetEntry {
        HelperCooldownWidgetEntry(date: Date(), helpers: placeholderHelpers(), profileName: "")
    }

    func snapshot(for configuration: WidgetProfileIntent, in context: Context) async -> HelperCooldownWidgetEntry {
        let profileName = loadProfileName(for: configuration)
        return HelperCooldownWidgetEntry(date: Date(), helpers: loadHelpers(for: configuration), profileName: profileName)
    }

    func timeline(for configuration: WidgetProfileIntent, in context: Context) async -> Timeline<HelperCooldownWidgetEntry> {
        let profileName = loadProfileName(for: configuration)
        let entry = HelperCooldownWidgetEntry(date: Date(), helpers: loadHelpers(for: configuration), profileName: profileName)

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

    private func loadProfileName(for configuration: WidgetProfileIntent) -> String {
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
            
            return profileToUse?.displayName ?? (profileToUse?.tag ?? "Profile")
        }
        return ""
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
            
            // Profile name at bottom
            if !entry.profileName.isEmpty {
                Text(entry.profileName)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
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

// MARK: - Clan War Home Screen Widget (2x2)
struct ClanWarWidgetEntry: TimelineEntry {
    let date: Date
    let war: WarDetails?
    let isInCWL: Bool
    let profileName: String
}

struct ClanWarWidgetProvider: AppIntentTimelineProvider {
    typealias Intent = WidgetProfileIntent
    typealias Entry = ClanWarWidgetEntry
    
    func placeholder(in context: Context) -> ClanWarWidgetEntry {
        ClanWarWidgetEntry(date: Date(), war: nil, isInCWL: false, profileName: "")
    }

    func snapshot(for configuration: WidgetProfileIntent, in context: Context) -> ClanWarWidgetEntry {
        let (war, isInCWL) = loadWarData(for: configuration)
        let profileName = loadProfileName(for: configuration)
        return ClanWarWidgetEntry(date: Date(), war: war, isInCWL: isInCWL, profileName: profileName)
    }

    func timeline(for configuration: WidgetProfileIntent, in context: Context) async -> Timeline<ClanWarWidgetEntry> {
        let (war, isInCWL) = loadWarData(for: configuration)
        let profileName = loadProfileName(for: configuration)
        let entry = ClanWarWidgetEntry(date: Date(), war: war, isInCWL: isInCWL, profileName: profileName)
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func loadWarData(for configuration: WidgetProfileIntent) -> (war: WarDetails?, isInCWL: Bool) {
        let defaults = UserDefaults(suiteName: "group.Zachary-Buschmann.clash-widgets")
        guard let state = PersistentStore.loadState() else { return (nil, false) }
        
        // Determine which profile to use
        var profileToUse: PlayerAccount? = nil
        
        // First check if a profile is selected in the configuration
        if let selectedProfile = configuration.selectedProfile,
           selectedProfile != .automatic,
           let profileID = selectedProfile.profileID() {
            profileToUse = state.profiles.first(where: { $0.id == profileID })
        } else {
            // If no profile selected, try to read from UserDefaults (saved preference)
            if let savedSelection = defaults?.string(forKey: "widget_profile_selection") {
                if let savedProfile = ProfileSelection(rawValue: savedSelection),
                   savedProfile != .automatic,
                   let profileID = savedProfile.profileID() {
                    profileToUse = state.profiles.first(where: { $0.id == profileID })
                }
            }
        }
        
        // Fall back to current profile if needed
        if profileToUse == nil {
            profileToUse = state.currentProfile
        }
        
        var war: WarDetails? = nil
        var isInCWL = false
        
        // Load war data using the profile's tag as cache key
        if let profile = profileToUse, !profile.tag.isEmpty {
            // Try profile-specific war data first
            let cacheKey = "war_json_\(profile.tag)"
            if let data = defaults?.data(forKey: cacheKey) {
                war = try? JSONDecoder().decode(WarDetails.self, from: data)
            }
            
            // Check CWL status for this profile
            let cwlKey = "is_in_cwl_\(profile.tag)"
            isInCWL = defaults?.bool(forKey: cwlKey) ?? false
        } else {
            // Fallback to generic current war data
            if let data = defaults?.data(forKey: "current_war_json") {
                war = try? JSONDecoder().decode(WarDetails.self, from: data)
            }
            isInCWL = defaults?.bool(forKey: "is_in_cwl") ?? false
        }
        
        return (war, isInCWL)
    }

    private func loadProfileName(for configuration: WidgetProfileIntent) -> String {
        guard let state = PersistentStore.loadState() else { return "" }
        
        // Determine which profile to use
        var profileToUse: PlayerAccount? = nil
        
        // First check if a profile is selected in the configuration
        if let selectedProfile = configuration.selectedProfile,
           selectedProfile != .automatic,
           let profileID = selectedProfile.profileID() {
            profileToUse = state.profiles.first(where: { $0.id == profileID })
        } else {
            // If no profile selected, try to read from UserDefaults (saved preference)
            let defaults = UserDefaults(suiteName: "group.Zachary-Buschmann.clash-widgets")
            if let savedSelection = defaults?.string(forKey: "widget_profile_selection") {
                if let savedProfile = ProfileSelection(rawValue: savedSelection),
                   savedProfile != .automatic,
                   let profileID = savedProfile.profileID() {
                    profileToUse = state.profiles.first(where: { $0.id == profileID })
                }
            }
        }
        
        // Fall back to current profile if needed
        if profileToUse == nil {
            profileToUse = state.currentProfile
        }
        
        return profileToUse?.displayName ?? (profileToUse?.tag ?? "Profile")
    }
}

struct ClanWarWidgetEntryView: View {
    var entry: ClanWarWidgetEntry

    var body: some View {
        if entry.isInCWL {
            // Show CWL message
            VStack(alignment: .center, spacing: 8) {
                Text("Clan War League")
                    .font(.headline)
                    .bold()
                Spacer()
                Text("Currently in Clan War League")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if let war = entry.war,
                  let clan = war.clan,
                  let opponent = war.opponent {
            // Show current war details
            VStack(alignment: .leading, spacing: 10) {
                // Teams comparison with badges
                HStack(alignment: .top, spacing: 8) {
                    // Our Clan
                    VStack(alignment: .center, spacing: 6) {
                        // Badge image or colored circle fallback
                        if !clan.badgeUrls.small.isEmpty {
                            AsyncImage(url: URL(string: clan.badgeUrls.small)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 44, height: 44)
                                case .failure, .empty:
                                    Circle()
                                        .fill(Color.blue.opacity(0.3))
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            Text(String(clan.name.prefix(2)))
                                                .font(.caption)
                                                .bold()
                                        )
                                @unknown default:
                                    Circle()
                                        .fill(Color.blue.opacity(0.3))
                                        .frame(width: 44, height: 44)
                                }
                            }
                        } else {
                            Circle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(String(clan.name.prefix(2)))
                                        .font(.caption)
                                        .bold()
                                )
                        }
                        Text(clan.name)
                            .font(.caption)
                            .lineLimit(1)
                        Text("★ \(clan.stars ?? 0)")
                            .font(.caption2)
                            .bold()
                    }
                    
                    // VS
                    VStack(spacing: 4) {
                        Text("VS")
                            .font(.caption2)
                            .bold()
                        Text("\(war.teamSize)v\(war.teamSize)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Opponent
                    VStack(alignment: .center, spacing: 6) {
                        // Badge image or colored circle fallback
                        if !opponent.badgeUrls.small.isEmpty {
                            AsyncImage(url: URL(string: opponent.badgeUrls.small)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 44, height: 44)
                                case .failure, .empty:
                                    Circle()
                                        .fill(Color.red.opacity(0.3))
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            Text(String(opponent.name.prefix(2)))
                                                .font(.caption)
                                                .bold()
                                        )
                                @unknown default:
                                    Circle()
                                        .fill(Color.red.opacity(0.3))
                                        .frame(width: 44, height: 44)
                                }
                            }
                        } else {
                            Circle()
                                .fill(Color.red.opacity(0.3))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(String(opponent.name.prefix(2)))
                                        .font(.caption)
                                        .bold()
                                )
                        }
                        Text(opponent.name)
                            .font(.caption)
                            .lineLimit(1)
                        Text("★ \(opponent.stars ?? 0)")
                            .font(.caption2)
                            .bold()
                    }
                }
                
                // War phase progress bar
                let phase = warPhase(for: war)
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green)
                                .frame(width: geo.size.width * CGFloat(phase.progress), height: 8)
                        }
                    }
                    .frame(height: 8)
                    
                    // Timer and phase label
                    TimelineView(.periodic(from: Date(), by: 1)) { context in
                        HStack {
                            if let timer = warTimerLabel(for: war, referenceDate: context.date) {
                                Text(timer)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(phase.label)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if let percentage = warDestructionPercentage(for: war) {
                                Text("\(percentage)% destroyed")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // Profile name at bottom
                if !entry.profileName.isEmpty {
                    HStack {
                        Text(entry.profileName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            .padding(12)
        } else {
            VStack(alignment: .center, spacing: 8) {
                Text("Clan War")
                    .font(.headline)
                    .bold()
                Spacer()
                Text("No active war")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !entry.profileName.isEmpty {
                    Text(entry.profileName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func warDestructionPercentage(for war: WarDetails) -> Int? {
        guard let clan = war.clan, let opponent = war.opponent else { return nil }
        let clanDest = Int(clan.destructionPercentage ?? 0)
        let oppDest = Int(opponent.destructionPercentage ?? 0)
        return max(clanDest, oppDest)
    }

    private struct WarPhaseInfo {
        let label: String
        let progress: Double
    }

    private func warPhase(for war: WarDetails) -> WarPhaseInfo {
        let now = Date()
        let prepStart = parseWarDate(war.preparationStartTime)
        let start = parseWarDate(war.startTime)
        let end = parseWarDate(war.endTime)

        if let prepStart, let start, now < start {
            let total = max(start.timeIntervalSince(prepStart), 1)
            let progress = min(max(now.timeIntervalSince(prepStart) / total, 0), 1)
            return WarPhaseInfo(label: "Preparation", progress: progress)
        }
        if let start, let end, now >= start, now < end {
            let total = max(end.timeIntervalSince(start), 1)
            let progress = min(max(now.timeIntervalSince(start) / total, 0), 1)
            return WarPhaseInfo(label: "Battle", progress: progress)
        }
        if let end, now >= end {
            return WarPhaseInfo(label: "Ended", progress: 1)
        }
        return WarPhaseInfo(label: "Status", progress: 0)
    }

    private func warTimerLabel(for war: WarDetails, referenceDate: Date) -> String? {
        let now = referenceDate
        let start = parseWarDate(war.startTime)
        let end = parseWarDate(war.endTime)

        if let _ = parseWarDate(war.preparationStartTime), let start, now < start {
            let remaining = start.timeIntervalSince(now)
            return formatTimeRemaining(remaining)
        }
        if let start, let end, now >= start, now < end {
            let remaining = end.timeIntervalSince(now)
            return formatTimeRemaining(remaining)
        }
        return nil
    }

    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func parseWarDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return formatter.date(from: value)
    }
}

struct ClanWarWidget: Widget {
    let kind: String = "ClanWarWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: ClanWarWidgetProvider()) { entry in
            if #available(iOS 17.0, *) {
                ClanWarWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                ClanWarWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Clan War")
        .description("Shows current clan war status, opponent, and war timer.")
        .supportedFamilies([.systemMedium])
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
            
            // Profile name at bottom
            if !entry.profileName.isEmpty {
                Text(entry.profileName)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
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
                Text(formatBoostedTimeRemaining(for: upgrade, activeBoosts: entry.activeBoosts))
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
        boostedProgressFraction(for: upgrade, activeBoosts: entry.activeBoosts, goldPassBoost: entry.goldPassBoost)
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
        let (upgrades, builderHallLevel, activeBoosts) = loadUpgradesAndBoosts(for: configuration)
        let (profileName, _) = loadProfileInfo(for: configuration)
        return SimpleEntry(date: Date(), upgrades: upgrades, builderCount: 5, builderHallLevel: builderHallLevel, debugText: "BuilderBase", profileName: profileName, townHallLevel: 0, activeBoosts: activeBoosts)
    }

    func timeline(for configuration: WidgetProfileIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let (upgrades, builderHallLevel, activeBoosts) = loadUpgradesAndBoosts(for: configuration)
        let (profileName, _) = loadProfileInfo(for: configuration)
        let entry = SimpleEntry(date: Date(), upgrades: upgrades, builderCount: 5, builderHallLevel: builderHallLevel, debugText: "BuilderBase", profileName: profileName, townHallLevel: 0, activeBoosts: activeBoosts)
        
        // Adjust refresh rate based on boost activity
        let hasActiveBoosts = !activeBoosts.isEmpty
        let minutes = hasActiveBoosts ? 1 : 15  // Refresh every 1 min with boosts, 15 min otherwise
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: minutes, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func loadUpgradesAndBoosts(for configuration: WidgetProfileIntent) -> ([BuildingUpgrade], Int, [ActiveBoost]) {
        let (decoded, builderHallLevel, activeBoosts) = loadUpgradesBuilderHallAndBoosts(for: configuration)
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
        return (selectedBuilders + selectedLab, builderHallLevel, activeBoosts)
    }

    private func loadUpgrades(for configuration: WidgetProfileIntent) -> ([BuildingUpgrade], Int) {
        let (upgrades, builderHallLevel, _) = loadUpgradesAndBoosts(for: configuration)
        return (upgrades, builderHallLevel)
    }

    private func loadUpgradesBuilderHallAndBoosts(for configuration: WidgetProfileIntent) -> ([BuildingUpgrade], Int, [ActiveBoost]) {
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
            let activeBoosts = profileToUse?.activeBoosts ?? []
            return (profileToUse?.activeUpgrades ?? [], builderHall, activeBoosts)
        }

        let sharedDefaults = UserDefaults(suiteName: appGroup)
        guard let data = sharedDefaults?.data(forKey: "saved_upgrades"),
              let decoded = try? JSONDecoder().decode([BuildingUpgrade].self, from: data) else {
            return ([], 0, [])
        }
        return (decoded, 0, [])
    }

    private func loadUpgradesAndBuilderHall(for configuration: WidgetProfileIntent) -> ([BuildingUpgrade], Int) {
        let (upgrades, builderHallLevel, _) = loadUpgradesBuilderHallAndBoosts(for: configuration)
        return (upgrades, builderHallLevel)
    }

    private func loadProfileInfo(for configuration: WidgetProfileIntent) -> (profileName: String, townHallLevel: Int) {
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
            
            let profileName = profileToUse?.displayName ?? (profileToUse?.tag ?? "Profile")
            let townHall = profileToUse?.cachedProfile?.townHallLevel ?? 0
            return (profileName, townHall)
        }
        return ("Profile", 0)
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
            
            // Profile name at bottom
            if !entry.profileName.isEmpty {
                Text(entry.profileName)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
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
                Text(formatBoostedTimeRemaining(for: upgrade, activeBoosts: entry.activeBoosts))
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
        boostedProgressFraction(for: upgrade, activeBoosts: entry.activeBoosts, goldPassBoost: entry.goldPassBoost)
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

