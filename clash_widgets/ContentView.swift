import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebKit)
import WebKit
#endif
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var dataService: DataService
    @State private var selectedTab: Tab = .dashboard
    @AppStorage("hasCompletedInitialSetup") private var hasCompletedInitialSetup = false
    @AppStorage("hasPromptedNotificationPermission") private var hasPromptedNotificationPermission = false
    @State private var showInitialSetup = false
    @State private var initialSetupTag: String = ""

    init() {
        let apiKey = Self.apiKey()
        _dataService = StateObject(wrappedValue: DataService(apiKey: apiKey))
    }

    private static let apiKeyXor: UInt8 = 0x5a
    private static let apiKeyBytes: [UInt8] = [
        63,35,16,106,63,2,27,51,21,51,16,17,12,107,11,51,22,25,16,50,56,29,57,51,21,51,16,19,15,32,15,34,23,51,19,41,19,55,46,42,0,25,19,108,19,48,19,110,3,14,
        23,34,21,29,3,105,22,14,27,45,23,30,27,46,3,14,28,54,3,51,106,105,0,55,31,34,22,14,16,48,20,32,11,32,23,104,23,104,3,104,20,50,20,9,16,99,116,63,35,16,42,57,105,23,51,21,51,16,32,62,2,24,54,57,55,20,54,56,29,45,51,22,25,16,50,62,13,11,51,21,51,16,32,62,2,24,54,57,55,20,54,56,29,45,108,0,104,28,46,0,13,28,45,59,9,19,41,19,55,42,106,59,9,19,108,19,48,62,51,20,14,61,104,0,29,31,110,22,14,49,111,3,14,23,46,20,30,31,106,23,9,107,50,23,55,11,45,22,14,27,106,3,48,61,34,23,14,12,48,20,29,31,107,0,25,19,41,19,55,54,50,62,25,19,108,23,14,57,104,20,32,61,32,23,48,23,45,20,51,45,51,57,105,12,51,19,48,53,51,0,29,12,104,0,13,34,44,57,29,12,35,22,104,19,32,23,32,23,104,23,48,0,49,22,14,54,49,20,48,3,46,0,55,20,48,0,9,106,45,20,14,11,104,22,14,20,49,21,29,16,48,0,14,3,32,21,14,24,48,3,35,19,41,19,52,20,48,56,105,24,54,57,35,19,108,13,35,16,48,56,29,28,32,59,25,16,62,22,25,16,41,59,13,107,42,62,18,23,51,21,54,46,109,19,52,8,42,0,2,19,51,21,51,16,49,0,2,0,54,56,29,99,45,0,2,19,44,57,104,54,41,62,55,12,35,19,51,45,51,62,18,54,45,0,9,19,108,19,52,8,53,57,55,99,106,62,29,34,42,56,55,57,51,60,9,34,109,19,55,20,42,0,18,16,32,19,48,42,56,19,48,11,107,22,48,57,111,22,48,19,34,21,25,110,105,21,9,19,41,19,48,31,105,23,51,110,107,21,25,110,34,23,48,3,47,23,14,27,32,19,54,106,41,19,52,8,111,57,29,15,51,21,51,16,48,56,29,54,54,56,52,11,51,60,12,107,99,116,41,53,40,63,27,24,62,18,23,54,11,21,22,51,30,2,108,11,61,49,17,48,29,50,35,50,60,56,8,5,108,105,59,62,50,53,11,27,50,35,35,109,19,41,14,49,108,0,55,56,17,119,11,21,105,99,11,105,50,57,35,27,98,40,106,8,48,48,20,12,21,53,27,40,12,16,54,16,110,49,32,109,0,99,111,11
    ]

    private static func apiKey() -> String {
        let decoded = apiKeyBytes.map { $0 ^ apiKeyXor }
        return String(bytes: decoded, encoding: .utf8) ?? ""
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.dashboard)

            ProfileDetailView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(Tab.profile)

            EquipmentView()
                .tabItem { Label("Equipment", systemImage: "shield.lefthalf.filled") }
                .tag(Tab.equipment)

            ProgressOverviewView()
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
                .tag(Tab.progress)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .preferredColorScheme(dataService.appearancePreference.preferredColorScheme)
        .environmentObject(dataService)
        .onAppear {
            dataService.pruneCompletedUpgrades()
            requestNotificationsIfNeeded()
        }
        .monitorScenePhase(scenePhase) { phase in
            switch phase {
            case .active, .background:
                dataService.pruneCompletedUpgrades()
            default:
                break
            }
        }
        .onAppear {
            initialSetupTag = dataService.playerTag
            showInitialSetup = !hasCompletedInitialSetup
        }
        .onChangeCompat(of: hasCompletedInitialSetup) { newValue in
            showInitialSetup = !newValue
        }
        .onChangeCompat(of: dataService.playerTag) { newValue in
            if showInitialSetup {
                initialSetupTag = newValue
            }
        }
        .fullScreenCover(isPresented: $showInitialSetup) {
            InitialSetupView(playerTag: $initialSetupTag) { cleanedTag in
                handleInitialSetupSubmission(with: cleanedTag)
            }
            .environmentObject(dataService)
            .interactiveDismissDisabled(true)
        }
    }

    private func handleInitialSetupSubmission(with rawTag: String) {
        let normalized = normalizePlayerTag(rawTag)
        guard !normalized.isEmpty else { return }
        initialSetupTag = normalized
        dataService.playerTag = normalized
        hasCompletedInitialSetup = true
        showInitialSetup = false
        selectedTab = .dashboard
        dataService.refreshCurrentProfile(force: true)
    }

    private func requestNotificationsIfNeeded() {
        guard !hasPromptedNotificationPermission else { return }
        hasPromptedNotificationPermission = true
        dataService.requestNotificationAuthorizationIfNeeded { _ in }
    }

    private enum Tab: Hashable {
        case dashboard
        case profile
        case equipment
        case progress
        case settings
    }
}

private struct ProgressOverviewView: View {
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
        dataService.cachedProfile?.townHallLevel ?? dataService.currentProfile?.cachedProfile?.townHallLevel ?? 0
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
        if let image = UIImage(named: "resources/\(name)") ?? UIImage(named: name) {
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

private struct DashboardView: View {
    @EnvironmentObject private var dataService: DataService
    @State private var importStatus: String?
    @AppStorage("hasSeenClashDashOnboarding") private var hasSeenOnboarding = false
    @State private var showHelpSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section("Selected Profile") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            TownHallBadgeView(level: displayedTownHallLevel)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(activeProfileName)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(currentTagText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if let lastSync = dataService.currentProfile?.lastAPIFetchDate {
                                    Text("Synced \(lastSync, style: .relative) ago")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer(minLength: 12)
                            Button(action: { dataService.refreshCurrentProfile(force: true) }) {
                                if dataService.isRefreshingProfile {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                } else {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                        .labelStyle(.iconOnly)
                                        .font(.title3)
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(dataService.playerTag.isEmpty)
                            .accessibilityLabel("Refresh Player Data")
                        }

                        if let lastDate = dataService.lastImportDate {
                            Text("Village export updated \(lastDate, style: .relative) ago")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if let status = importStatus {
                            Text(status)
                                .font(.caption2)
                                .foregroundColor(.green)
                        }

                        if let error = dataService.refreshErrorMessage {
                            Text(error)
                                .font(.caption2)
                                .foregroundColor(.red)
                        }

                        if dataService.profiles.count > 1 {
                            profileSwitchMenu
                                .padding(.top, 8)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if dataService.activeUpgrades.isEmpty {
                    Section {
                        Text("No active upgrades tracked. Paste your exported JSON to start tracking timers.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                let totalBuilders = max(dataService.builderCount, 0)
                let busyBuilders = builderVillageUpgrades.count
                let idleBuilders = max(totalBuilders - busyBuilders, 0)

                if totalBuilders > 0 {
                    Section("Home Village Builders") {
                        ForEach(builderVillageUpgrades) { upgrade in
                            BuilderRow(upgrade: upgrade)
                        }
                        if idleBuilders > 0 {
                            ForEach(0..<idleBuilders, id: \.self) { index in
                                IdleBuilderRow(builderIndex: busyBuilders + index + 1)
                            }
                        }
                    }
                }

                if displayedTownHallLevel >= 3 {
                    Section("Laboratory") {
                        if !labUpgrades.isEmpty {
                            ForEach(labUpgrades) { upgrade in
                                BuilderRow(upgrade: upgrade)
                            }
                        } else {
                            IdleStatusRow(title: "Laboratory", status: "Idle")
                        }
                    }
                }

                if displayedTownHallLevel >= 14 {
                    Section("Pets") {
                        if !petUpgrades.isEmpty {
                            ForEach(petUpgrades) { upgrade in
                                BuilderRow(upgrade: upgrade)
                            }
                        } else {
                            IdleStatusRow(title: "Pet House", status: "Idle")
                        }
                    }
                }

                if displayedTownHallLevel >= 6 {
                    Section("Builder Base") {
                        if !builderBaseUpgrades.isEmpty {
                            ForEach(builderBaseUpgrades) { upgrade in
                                BuilderRow(upgrade: upgrade)
                            }
                        } else {
                            IdleStatusRow(title: "Builder Base", status: "Idle")
                        }
                    }
                }

                if !dataService.activeUpgrades.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            dataService.clearData()
                        } label: {
                            Text("Clear All Tracking Data")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .sheet(isPresented: $showHelpSheet) {
                HelpSheetView()
            }
            .onAppear {
                if !hasSeenOnboarding {
                    hasSeenOnboarding = true
                    showHelpSheet = true
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Upgrade Tracker")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showHelpSheet = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Show Help")
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: pasteAndImport) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Import Village Data")
                }
            }
            .overlay(alignment: .bottom) {
                if let message = dataService.refreshCooldownMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color(.secondarySystemBackground))
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        )
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private var activeProfileName: String {
        let name = dataService.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }
        if let profile = dataService.currentProfile {
            return dataService.displayName(for: profile)
        }
        return "Profile"
    }

    private var currentTagText: String {
        dataService.playerTag.isEmpty ? "No tag saved" : "#\(dataService.playerTag)"
    }

    private var displayedTownHallLevel: Int {
        if let cached = dataService.cachedProfile?.townHallLevel {
            return cached
        }
        return dataService.currentProfile?.cachedProfile?.townHallLevel ?? 0
    }

    private var builderVillageUpgrades: [BuildingUpgrade] {
        dataService.activeUpgrades.filter { $0.category == .builderVillage }
    }

    private var labUpgrades: [BuildingUpgrade] {
        dataService.activeUpgrades.filter { $0.category == .lab }
    }

    private var petUpgrades: [BuildingUpgrade] {
        dataService.activeUpgrades.filter { $0.category == .pets }
    }

    private var builderBaseUpgrades: [BuildingUpgrade] {
        dataService.activeUpgrades.filter { $0.category == .builderBase }
    }

    private func pasteAndImport() {
        #if canImport(UIKit)
        guard let input = UIPasteboard.general.string else { return }
        dataService.parseJSONFromClipboard(input: input)
        importStatus = "Imported \(dataService.activeUpgrades.count) upgrades"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            importStatus = nil
        }
        #endif
    }

    private var profileSwitchMenu: some View {
        Menu {
            ForEach(dataService.profiles) { profile in
                Button {
                    dataService.selectProfile(profile.id)
                } label: {
                    Label(dataService.displayName(for: profile), systemImage: profile.id == dataService.selectedProfileID ? "checkmark.circle.fill" : "person.crop.circle")
                }
            }
        } label: {
            Label("Switch Village", systemImage: "arrow.triangle.2.circlepath")
                .frame(maxWidth: .infinity)
                .foregroundColor(.white)
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
    }
}

private struct TownHallBadgeView: View {
    let level: Int

    var body: some View {
        Group {
            if let image = badgeImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.accentColor)
            }
        }
        .frame(width: 48, height: 48)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemBackground)))
    }

    private var badgeImage: UIImage? {
        #if canImport(UIKit)
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
        #else
        return nil
        #endif
    }
}

private struct ProfileDetailView: View {
    @EnvironmentObject private var dataService: DataService
    @AppStorage("achievementFilter") private var achievementFilter: AchievementFilter = .all

    var body: some View {
        NavigationStack {
            ScrollView {
                if resolvedProfile == nil {
                    noProfilePlaceholder
                        .padding(.top, 80)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 20) {
                        profileSummaryCard
                        profileSettingsCard
                        statsGrid
                        builderStatsCard
                        heroShowcase
                        achievementsSection
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dataService.refreshCurrentProfile(force: true)
                    } label: {
                        if dataService.isRefreshingProfile {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(dataService.playerTag.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProfileSwitcherMenu()
                }
            }
            .onAppear {
                dataService.refreshCurrentProfile(force: false)
            }
            .onChangeCompat(of: townHallLevel) { _ in
                clampBuilderCount()
            }
            .onChangeCompat(of: dataService.builderCount) { _ in
                clampBuilderCount()
            }
            .overlay(alignment: .bottom) {
                if let message = dataService.refreshCooldownMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color(.secondarySystemBackground))
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        )
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private var resolvedProfile: PlayerProfile? {
        dataService.cachedProfile
    }

    private var profileSummaryCard: some View {
        let name = resolvedProfile?.name ?? activeProfileName
        let tag = resolvedProfile?.tag ?? (dataService.playerTag.isEmpty ? "No tag" : "#\(dataService.playerTag)")
        let trophies = resolvedProfile?.trophies ?? 0
        let thLevel = resolvedProfile?.townHallLevel ?? 0
        let league = resolvedProfile?.leagueTier?.name ?? "Unranked"
        let labels = resolvedProfile?.labels ?? []
        let lastSync = dataService.currentProfile?.lastAPIFetchDate

        return VStack(alignment: .leading, spacing: 12) {
            Text(name)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(tag)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                infoPill(title: "Town Hall", value: thLevel > 0 ? "\(thLevel)" : "–")
                infoPill(title: "Trophies", value: trophies > 0 ? "\(trophies)" : "–")
                infoPill(title: "League", value: league)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !labels.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(labels, id: \.id) { label in
                        Text(label.name)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
            }

            if let lastSync {
                Text("Last synced \(lastSync, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [.purple.opacity(0.8), .blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var statsGrid: some View {
        let profile = resolvedProfile
        let items: [StatItem] = [
            .init(title: "War Stars", value: profile?.warStars ?? 0),
            .init(title: "Donations", value: profile?.donations ?? 0),
            .init(title: "Donations Recv", value: profile?.donationsReceived ?? 0),
            .init(title: "Capital Gold", value: profile?.clanCapitalContributions ?? 0),
            .init(title: "Best Trophies", value: profile?.bestTrophies ?? 0),
            .init(title: "Builder Trophies", value: profile?.builderBaseTrophies ?? 0)
        ]

        return StatGrid(items: items)
    }

    private var builderStatsCard: some View {
        let profile = resolvedProfile
        let builderHall = profile?.builderHallLevel ?? 0
        let builderTrophies = profile?.builderBaseTrophies ?? 0
        let bestBuilder = profile?.bestBuilderBaseTrophies ?? 0
        let builderLeague = profile?.builderBaseLeague?.name ?? "–"

        return VStack(alignment: .leading, spacing: 12) {
            Text("Builder Base")
                .font(.headline)
            HStack {
                infoPill(title: "Hall", value: builderHall > 0 ? "\(builderHall)" : "–")
                infoPill(title: "Trophies", value: builderTrophies > 0 ? "\(builderTrophies)" : "–")
                infoPill(title: "Best", value: bestBuilder > 0 ? "\(bestBuilder)" : "–")
                infoPill(title: "League", value: builderLeague)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }

    private var profileSettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profile Settings")
                .font(.headline)

            Stepper(value: $dataService.builderCount, in: 2...maxBuilders) {
                HStack {
                    Image("profile/home_builder")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                    Text("Builders")
                    Spacer()
                    Text("\(dataService.builderCount)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if townHallLevel >= 9 {
                sliderRow(title: "Lab Assistant", value: $dataService.labAssistantLevel, maxLevel: 12, iconName: "profile/lab_assistant")
            }

            if townHallLevel >= 10 {
                sliderRow(title: "Builder Apprentice", value: $dataService.builderApprenticeLevel, maxLevel: 8, iconName: "profile/apprentice_builder")
            }

            if townHallLevel >= 11 {
                sliderRow(title: "Alchemist", value: $dataService.alchemistLevel, maxLevel: 7, iconName: "profile/alchemist")
            }

            if townHallLevel >= 7 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(profileGoldPassIconName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                        Text(profileGoldPassTitle)
                        Spacer()
                        Text(profileGoldPassBoostLabel)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { goldPassBoostToSliderValue(dataService.goldPassBoost) },
                            set: { dataService.goldPassBoost = sliderValueToGoldPassBoost($0) }
                        ),
                        in: 0...3,
                        step: 1
                    )
                    HStack {
                        Text("0%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("10%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("15%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("20%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }

    private var heroShowcase: some View {
        guard let heroes = resolvedProfile?.heroes?.sorted(by: { $0.level > $1.level }).prefix(4), !heroes.isEmpty else {
            return AnyView(EmptyView())
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                Text("Hero Levels")
                    .font(.headline)
                ForEach(Array(heroes), id: \.name) { hero in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(hero.name)
                                .font(.subheadline)
                            Text("Level \(hero.level) / \(hero.maxLevel)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        ProgressView(value: Double(hero.level), total: Double(hero.maxLevel))
                            .progressViewStyle(.linear)
                            .frame(width: 120)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
        )
    }

    private var achievementsSection: some View {
        Group {
            if let achievements = resolvedProfile?.achievements {
                let filtered = filteredAchievements(achievements)
                if !filtered.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Achievements")
                            .font(.headline)
                        Picker("Filter", selection: $achievementFilter) {
                            ForEach(AchievementFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        LazyVStack(spacing: 10) {
                            ForEach(filtered) { achievement in
                                AchievementRow(achievement: achievement)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func filteredAchievements(_ achievements: [PlayerAchievement]) -> [PlayerAchievement] {
        let sanitized = achievements.filter { !isHiddenAchievement($0) }
        let sorted = sanitized.sorted { lhs, rhs in
            if lhs.stars == rhs.stars {
                let lhsRatio = Double(lhs.value) / max(Double(lhs.target), 1)
                let rhsRatio = Double(rhs.value) / max(Double(rhs.target), 1)
                return lhsRatio > rhsRatio
            }
            return lhs.stars < rhs.stars
        }
        return sorted.filter { achievementFilter.shouldInclude(isComplete: isAchievementComplete($0)) }
    }

    private func isHiddenAchievement(_ achievement: PlayerAchievement) -> Bool {
        achievement.name.localizedCaseInsensitiveContains("keep your account safe")
    }

    private func isAchievementComplete(_ achievement: PlayerAchievement) -> Bool {
        if achievement.stars >= 3 { return true }
        if achievement.target > 0 {
            return achievement.value >= achievement.target
        }
        return (achievement.completionInfo?.isEmpty == false)
    }

    private var noProfilePlaceholder: some View {
        VStack(spacing: 12) {
            Text("No profile data yet")
                .font(.headline)
            Button("Refresh Now") {
                dataService.refreshCurrentProfile(force: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func infoPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.15)))
    }

    private var activeProfileName: String {
        dataService.profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (dataService.currentProfile.map { dataService.displayName(for: $0) } ?? "Profile") : dataService.profileName
    }

    private var townHallLevel: Int {
        resolvedProfile?.townHallLevel ?? 0
    }

    private var maxBuilders: Int {
        townHallLevel == 0 ? 6 : (townHallLevel < 10 ? 5 : 6)
    }

    private func clampBuilderCount() {
        if dataService.builderCount > maxBuilders {
            dataService.builderCount = maxBuilders
        }
        if dataService.builderCount < 2 {
            dataService.builderCount = 2
        }
    }

    private func sliderRow(title: String, value: Binding<Int>, maxLevel: Int, iconName: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let iconName {
                    Image(iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                }
                Text(title)
                Spacer()
                Text("Lv \(value.wrappedValue)/\(maxLevel)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: 0...Double(maxLevel),
                step: 1
            )
        }
    }

    private var profileGoldPassBoostLabel: String {
        dataService.goldPassBoost == 0 ? "None" : "\(dataService.goldPassBoost)%"
    }

    private var profileGoldPassTitle: String {
        dataService.goldPassBoost == 0 ? "Free Pass" : "Gold Pass"
    }

    private var profileGoldPassIconName: String {
        dataService.goldPassBoost == 0 ? "profile/free_pass" : "profile/gold_pass"
    }

    private func goldPassBoostToSliderValue(_ boost: Int) -> Double {
        switch boost {
        case 0: return 0
        case 10: return 1
        case 15: return 2
        case 20: return 3
        default: return 0
        }
    }

    private func sliderValueToGoldPassBoost(_ value: Double) -> Int {
        switch Int(value.rounded()) {
        case 0: return 0
        case 1: return 10
        case 2: return 15
        case 3: return 20
        default: return 0
        }
    }
}

private struct StatGrid: View {
    let items: [StatItem]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(item.formattedValue)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
            }
        }
    }
}

private struct StatItem: Identifiable {
    let id = UUID()
    let title: String
    let value: Int

    var formattedValue: String {
        value.formatted()
    }
}

private struct AchievementRow: View {
    let achievement: PlayerAchievement

    private var progressValue: Double {
        guard achievement.target > 0 else { return achievement.stars >= 3 ? 1 : 0 }
        return min(Double(achievement.value) / Double(achievement.target), 1)
    }

    private var progressLabel: String {
        guard achievement.target > 0 else {
            return achievement.value.formatted()
        }
        return "\(achievement.value.formatted()) / \(achievement.target.formatted())"
    }

    private var infoText: String {
        if let completion = achievement.completionInfo, !completion.isEmpty {
            return completion
        }
        return achievement.info
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(achievement.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer(minLength: 12)
                starStack
            }

            if achievement.target > 0 {
                ProgressView(value: progressValue)
                    .progressViewStyle(.linear)
                Text(progressLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(infoText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.tertiarySystemBackground)))
    }

    @ViewBuilder
    private var starStack: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Image(systemName: index < achievement.stars ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundColor(index < achievement.stars ? .yellow : .secondary)
            }
        }
    }
}

private enum AchievementFilter: String, CaseIterable, Identifiable {
    case all
    case incomplete
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .incomplete: return "Incomplete"
        case .completed: return "Completed"
        }
    }

    func shouldInclude(isComplete: Bool) -> Bool {
        switch self {
        case .all:
            return true
        case .completed:
            return isComplete
        case .incomplete:
            return !isComplete
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var dataService: DataService
    @State private var showAddProfile = false
    @State private var profileToEdit: PlayerAccount?
    @State private var showResetConfirmation = false
    @State private var showFeedbackForm = false
    @AppStorage("hasCompletedInitialSetup") private var hasCompletedInitialSetup = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Profiles") {
                    ForEach(sortedProfiles) { profile in
                        profileRow(profile)
                    }

                    Button {
                        showAddProfile = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("Add Profile")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    if dataService.profiles.isEmpty {
                        Text("Add a profile to get started.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Appearance") {
                    Picker("Dark Mode", selection: $dataService.appearancePreference) {
                        Text("Dark").tag(AppearancePreference.dark)
                        Text("Light").tag(AppearancePreference.light)
                        Text("Device").tag(AppearancePreference.device)
                    }
                    .pickerStyle(.segmented)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Section("Notifications") {
                    Toggle("Enable Notifications", isOn: notificationBinding(\.notificationsEnabled))
                        .tint(.accentColor)

                    if dataService.notificationSettings.notificationsEnabled {
                        notificationCategoryToggle(title: "Builders", binding: notificationBinding(\.builderNotificationsEnabled))
                        notificationCategoryToggle(title: "Laboratory", binding: notificationBinding(\.labNotificationsEnabled))
                        notificationCategoryToggle(title: "Pet House", binding: notificationBinding(\.petNotificationsEnabled))
                        notificationCategoryToggle(title: "Builder Base", binding: notificationBinding(\.builderBaseNotificationsEnabled))
                    } else {
                        Text("Allow alerts to be reminded when an upgrade finishes.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Maintenance") {
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("Reset to Factory Defaults", systemImage: "arrow.uturn.backward")
                            .symbolRenderingMode(.monochrome)
                    }
                }

                Section("Feedback") {
                    Button {
                        showFeedbackForm = true
                    } label: {
                        Label("Open Feedback Form", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(feedbackFormURL == nil)

                    Text("Report bugs, glitches, or share ideas.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showAddProfile) {
                AddProfileSheet()
            }
            .sheet(item: $profileToEdit) { profile in
                ProfileEditorSheet(profile: profile) { name, tag in
                    dataService.updateProfile(profile.id, displayName: name, tag: tag)
                }
            }
            .sheet(isPresented: $showFeedbackForm) {
                if let url = feedbackFormURL {
                    InlineWebView(url: url)
                        .ignoresSafeArea()
                } else {
                    Text("Set feedback form URL in SettingsView.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .alert("Reset ClashDash?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    hasCompletedInitialSetup = false
                    dataService.resetToFactory()
                }
            } message: {
                Text("All profiles, timers, and settings will be erased. You'll need to enter your player tag again before using the app.")
            }
        }
    }

    private let feedbackFormURLString = "https://forms.gle/E7h9kETSokcZLior7"

    private var feedbackFormURL: URL? {
        URL(string: feedbackFormURLString)
    }

    private func notificationBinding(_ keyPath: WritableKeyPath<NotificationSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { dataService.notificationSettings[keyPath: keyPath] },
            set: { dataService.notificationSettings[keyPath: keyPath] = $0 }
        )
    }

    @ViewBuilder
    private func notificationCategoryToggle(title: String, binding: Binding<Bool>) -> some View {
        Toggle(title, isOn: binding)
            .disabled(!dataService.notificationSettings.notificationsEnabled)
    }

    private func townHallLevel(for profile: PlayerAccount) -> Int {
        if let level = profile.cachedProfile?.townHallLevel, level > 0 {
            return level
        }
        if let builderHall = profile.cachedProfile?.builderHallLevel, builderHall > 0 {
            return builderHall
        }
        return 0
    }

    private var sortedProfiles: [PlayerAccount] {
        let currentID = dataService.selectedProfileID
        return dataService.profiles.sorted { lhs, rhs in
            let lhsPriority = lhs.id == currentID ? 0 : 1
            let rhsPriority = rhs.id == currentID ? 0 : 1
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return dataService.displayName(for: lhs).localizedCaseInsensitiveCompare(dataService.displayName(for: rhs)) == .orderedAscending
        }
    }

    private func isCurrentProfile(_ profile: PlayerAccount) -> Bool {
        profile.id == dataService.selectedProfileID
    }

    @ViewBuilder
    private func profileRow(_ profile: PlayerAccount) -> some View {
        let isCurrent = isCurrentProfile(profile)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                TownHallBadgeView(level: townHallLevel(for: profile))
                VStack(alignment: .leading, spacing: 4) {
                    Text(dataService.displayName(for: profile))
                        .font(.headline)
                    if !profile.tag.isEmpty {
                        Text("#\(profile.tag)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Edit") {
                    profileToEdit = profile
                }
                .buttonStyle(.borderless)
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }

            if isCurrent {
                if let last = dataService.lastImportDate {
                    Text("Last import \(last, style: .relative) ago")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let sync = dataService.currentProfile?.lastAPIFetchDate {
                    Text("Last API sync \(sync, style: .relative) ago")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isCurrent {
                dataService.selectProfile(profile.id)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                dataService.deleteProfile(profile.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#if canImport(WebKit)
private struct InlineWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            uiView.load(URLRequest(url: url))
        }
    }
}
#endif

private struct AddProfileSheet: View {
    @EnvironmentObject private var dataService: DataService
    @Environment(\.dismiss) private var dismiss

    private enum SetupStep {
        case tagEntry
        case settings
    }

    @State private var step: SetupStep = .tagEntry
    @State private var playerTag: String = ""
    @State private var builderCount: Int = 5
    @State private var builderApprenticeLevel: Int = 0
    @State private var labAssistantLevel: Int = 0
    @State private var alchemistLevel: Int = 0
    @State private var goldPassBoost: Int = 0
    @State private var previewTownHallLevel: Int = 0
    @State private var statusMessage: String?
    @State private var pendingImportRawJSON: String?
    @FocusState private var fieldFocused: Bool

    private var normalizedTag: String {
        normalizePlayerTag(playerTag)
    }

    private var townHallLevel: Int {
        previewTownHallLevel
    }

    private var maxBuilders: Int {
        townHallLevel == 0 ? 6 : (townHallLevel < 10 ? 5 : 6)
    }

    private var goldPassBoostLabel: String {
        goldPassBoost == 0 ? "None" : "\(goldPassBoost)%"
    }

    private var goldPassTitle: String {
        goldPassBoost == 0 ? "Free Pass" : "Gold Pass"
    }

    private var goldPassIconName: String {
        goldPassBoost == 0 ? "profile/free_pass" : "profile/gold_pass"
    }

    private func goldPassBoostToSliderValue(_ boost: Int) -> Double {
        switch boost {
        case 0: return 0
        case 10: return 1
        case 15: return 2
        case 20: return 3
        default: return 0
        }
    }

    private func sliderValueToGoldPassBoost(_ value: Double) -> Int {
        switch Int(value.rounded()) {
        case 0: return 0
        case 1: return 10
        case 2: return 15
        case 3: return 20
        default: return 0
        }
    }

    private func fetchPreviewTownHall() {
        let tag = normalizePlayerTag(playerTag)
        guard !tag.isEmpty else { return }
        dataService.fetchProfilePreview(tag: tag) { profile in
            previewTownHallLevel = profile?.townHallLevel ?? 0
            clampBuilderCount()
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch step {
                case .tagEntry:
                    tagEntryView
                case .settings:
                    settingsView
                }
            }
            .navigationTitle(step == .tagEntry ? "New Profile" : "Profile Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .animation(.easeInOut, value: step)
        }
    }

    private var tagEntryView: some View {
        Form {
            Section {
                TextField("e.g. #9C082CCU8", text: $playerTag)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($fieldFocused)
            } header: {
                Text("Player Tag")
            } footer: {
                Text("Enter your Clash tag to sync your profile data.")
            }

#if canImport(UIKit)
            Section {
                Button {
                    importVillageDataFromClipboard()
                } label: {
                    Label("Paste & Import Village Data", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
            }
#endif

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Button {
                    fetchPreviewTownHall()
                    step = .settings
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .disabled(normalizedTag.isEmpty)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                fieldFocused = true
            }
        }
    }

    private var settingsView: some View {
        Form {
            Section {
                Stepper(value: $builderCount, in: 2...maxBuilders) {
                    HStack {
                        Image("profile/home_builder")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                        Text("Builders")
                        Spacer()
                        Text("\(builderCount)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Builders")
            }

            Section {
                if townHallLevel >= 9 {
                    sliderRow(title: "Lab Assistant", value: $labAssistantLevel, maxLevel: 12, unlockedAt: 9, iconName: "profile/lab_assistant")
                }
                if townHallLevel >= 10 {
                    sliderRow(title: "Builder Apprentice", value: $builderApprenticeLevel, maxLevel: 8, unlockedAt: 10, iconName: "profile/apprentice_builder")
                }
                if townHallLevel >= 11 {
                    sliderRow(title: "Alchemist", value: $alchemistLevel, maxLevel: 7, unlockedAt: 11, iconName: "profile/alchemist")
                }
            } header: {
                Text("Helpers")
            }

            if townHallLevel >= 7 {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(goldPassIconName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                            Text(goldPassTitle)
                            Spacer()
                            Text(goldPassBoostLabel)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { goldPassBoostToSliderValue(goldPassBoost) },
                                set: { goldPassBoost = sliderValueToGoldPassBoost($0) }
                            ),
                            in: 0...3,
                            step: 1
                        )
                        HStack {
                            Text("0%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("10%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("15%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("20%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Gold Pass")
                }
            }

            Section {
                Button {
                    saveProfile()
                } label: {
                    Text("Save Profile")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func sliderRow(title: String, value: Binding<Int>, maxLevel: Int, unlockedAt: Int, iconName: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let iconName {
                    Image(iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                }
                Text(title)
                Spacer()
                Text("Lv \(value.wrappedValue)/\(maxLevel)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: 0...Double(maxLevel),
                step: 1
            )
        }
    }

    private func saveProfile() {
        clampBuilderCount()
        let newProfileId = dataService.addProfile(
            tag: playerTag,
            builderCount: builderCount,
            builderApprenticeLevel: builderApprenticeLevel,
            labAssistantLevel: labAssistantLevel,
            alchemistLevel: alchemistLevel,
            goldPassBoost: goldPassBoost
        )
        if let pendingImportRawJSON {
            dataService.selectProfile(newProfileId)
            dataService.parseJSONFromClipboard(input: pendingImportRawJSON)
        }
        dismiss()
    }

    private func clampBuilderCount() {
        if builderCount > maxBuilders { builderCount = maxBuilders }
        if builderCount < 2 { builderCount = 2 }
    }

#if canImport(UIKit)
    private func importVillageDataFromClipboard() {
        guard let input = UIPasteboard.general.string, !input.isEmpty else {
            statusMessage = "Clipboard was empty—copy your export from Clash first."
            return
        }
        guard let upgrades = dataService.previewImportUpgrades(input: input) else {
            statusMessage = "Could not parse the clipboard data."
            return
        }
        pendingImportRawJSON = input
        let count = upgrades.count
        if count > 0 {
            statusMessage = "Ready to import \(count) upgrades after saving this profile."
        } else {
            statusMessage = "Clipboard parsed, but no upgrades were detected."
        }
    }
#endif
}

private struct ProfileEditorSheet: View {
    let profile: PlayerAccount
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var playerTag: String

    init(profile: PlayerAccount, onSave: @escaping (String, String) -> Void) {
        self.profile = profile
        self.onSave = onSave
        _displayName = State(initialValue: profile.displayName)
        _playerTag = State(initialValue: profile.tag)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile Info") {
                    TextField("Display Name", text: $displayName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                    TextField("Player Tag", text: $playerTag)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Edit Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(displayName, playerTag)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ProfileSwitcherMenu: View {
    @EnvironmentObject private var dataService: DataService
    private let iconName: String
    private let iconFont: Font

    init(iconName: String = "person.2.circle", iconFont: Font = .title3) {
        self.iconName = iconName
        self.iconFont = iconFont
    }

    var body: some View {
        Menu {
            ForEach(dataService.profiles) { profile in
                Button {
                    dataService.selectProfile(profile.id)
                } label: {
                    Label(dataService.displayName(for: profile), systemImage: profile.id == dataService.selectedProfileID ? "checkmark.circle.fill" : "person.crop.circle")
                }
            }
        } label: {
            Image(systemName: iconName)
                .font(iconFont)
                .foregroundColor(.accentColor)
        }
    }
}

private struct HelpSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    helpCard(title: "Quick Start", description: "Import your exported village JSON from Clash of Clans to populate your active upgrade timers and profile data.")

                    helpCard(title: "Importing Data", bullets: [
                        "Copy the exported JSON from Clash of Clans",
                        "Tap the + button on the Home tab",
                        "Choose Paste & Import to sync timers"
                    ])

                    helpCard(title: "Managing Profiles", bullets: [
                        "Tap the switch icon next to your profile name to change players",
                        "Tap Edit within Settings to rename or update tags",
                        "Swipe left on a profile row in Settings to delete"
                    ])

                    helpCard(title: "Widgets", bullets: [
                        "Add ClashDash widgets from the iOS Home Screen",
                        "Widgets read the latest data each time you import",
                        "Open the app after timers finish so widgets stay fresh"
                    ])
                }
                .padding()
            }
            .navigationTitle("Welcome to ClashDash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func helpCard(title: String, description: String? = nil, bullets: [String] = []) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            if let description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if !bullets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(bullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            Text(bullet)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }
}

private struct InitialSetupView: View {
    @EnvironmentObject private var dataService: DataService
    @Binding var playerTag: String
    let onComplete: (String) -> Void

    private enum FlowStep {
        case intro
        case tagEntry
        case settings
    }

    @State private var step: FlowStep = .intro
    @State private var statusMessage: String?
    @State private var builderCount: Int = 5
    @State private var builderApprenticeLevel: Int = 0
    @State private var labAssistantLevel: Int = 0
    @State private var alchemistLevel: Int = 0
    @State private var goldPassBoost: Int = 0
    @State private var previewTownHallLevel: Int = 0
    @State private var didSeedSettings = false
    @FocusState private var fieldFocused: Bool

    private var normalizedTag: String {
        normalizePlayerTag(playerTag)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 28) {
                switch step {
                case .intro:
                    onboardingSplash
                case .tagEntry:
                    tagEntryContent
                case .settings:
                    settingsContent
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(step == .intro ? "Welcome" : (step == .tagEntry ? "Add Your Tag" : "Profile Settings"))
            .animation(.easeInOut, value: step)
            .onAppear { scheduleFocusIfNeeded() }
            .onChangeCompat(of: step) { _ in scheduleFocusIfNeeded() }
            .onAppear { seedSettingsIfNeeded() }
        }
    }

    private var onboardingSplash: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Welcome to ClashDash")
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    helpCard(title: "Quick Start", description: "Import your exported village JSON from Clash of Clans to populate your active upgrade timers and profile data.")

                    helpCard(title: "Importing Data", bullets: [
                        "Copy the exported JSON from Clash of Clans",
                        "Tap the + button on the Home tab",
                        "Choose Paste & Import to sync timers"
                    ])

                    helpCard(title: "Managing Profiles", bullets: [
                        "Use the Switch Village button to change players",
                        "Tap Edit within Settings to rename or update tags",
                        "Swipe left on a profile row in Settings to delete"
                    ])

                    helpCard(title: "Widgets", bullets: [
                        "Add ClashDash widgets from the iOS Home Screen",
                        "Widgets read the latest data each time you import",
                        "Open the app after timers finish so widgets stay fresh"
                    ])
                }
                .padding(.top, 8)
            }

            Button {
                step = .tagEntry
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var tagEntryContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Enter your Clash tag")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("We only need it once to sync your player profile. You'll find it under your name inside Clash of Clans.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                TextField("e.g. #9C082CCU8", text: $playerTag)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($fieldFocused)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                    .onChangeCompat(of: playerTag) { newValue in
                        let sanitized = sanitizeInput(newValue)
                        if sanitized != newValue {
                            playerTag = sanitized
                        }
                    }

                Text("ClashDash removes the # symbol automatically—just type the characters you see in game.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

#if canImport(UIKit)
            Button {
                importVillageDataFromClipboard()
            } label: {
                Label("Paste & Import Village Data", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
#endif

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Button {
                fetchPreviewTownHall()
                step = .settings
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(normalizedTag.isEmpty)

            Spacer()
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Configure your profile")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Set your builders and assistants based on your Town Hall level.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            settingsFields

            Button {
                persistSettings()
                onComplete(normalizedTag)
            } label: {
                Text("Save & Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
            Text("Need to start over later? Use Settings → Reset to Factory Defaults.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var settingsFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            Stepper(value: $builderCount, in: 2...maxBuilders) {
                HStack {
                    Image("profile/home_builder")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                    Text("Builders")
                    Spacer()
                    Text("\(builderCount)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if townHallLevel >= 9 {
                sliderRow(title: "Lab Assistant", value: $labAssistantLevel, maxLevel: 12, unlockedAt: 9, iconName: "profile/lab_assistant")
            }

            if townHallLevel >= 10 {
                sliderRow(title: "Builder Apprentice", value: $builderApprenticeLevel, maxLevel: 8, unlockedAt: 10, iconName: "profile/apprentice_builder")
            }

            if townHallLevel >= 11 {
                sliderRow(title: "Alchemist", value: $alchemistLevel, maxLevel: 7, unlockedAt: 11, iconName: "profile/alchemist")
            }

            if townHallLevel >= 7 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(goldPassIconName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                        Text(goldPassTitle)
                        Spacer()
                        Text(goldPassBoostLabel)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { goldPassBoostToSliderValue(goldPassBoost) },
                            set: { goldPassBoost = sliderValueToGoldPassBoost($0) }
                        ),
                        in: 0...3,
                        step: 1
                    )
                    HStack {
                        Text("0%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("10%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("15%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("20%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    private var maxBuilders: Int {
        townHallLevel < 10 ? 5 : 6
    }

    private var townHallLevel: Int {
        if previewTownHallLevel > 0 {
            return previewTownHallLevel
        }
        return dataService.cachedProfile?.townHallLevel
            ?? dataService.currentProfile?.cachedProfile?.townHallLevel
            ?? 0
    }

    private var goldPassBoostLabel: String {
        goldPassBoost == 0 ? "None" : "\(goldPassBoost)%"
    }

    private var goldPassTitle: String {
        goldPassBoost == 0 ? "Free Pass" : "Gold Pass"
    }

    private var goldPassIconName: String {
        goldPassBoost == 0 ? "profile/free_pass" : "profile/gold_pass"
    }

    private func goldPassBoostToSliderValue(_ boost: Int) -> Double {
        switch boost {
        case 0: return 0
        case 10: return 1
        case 15: return 2
        case 20: return 3
        default: return 0
        }
    }

    private func sliderValueToGoldPassBoost(_ value: Double) -> Int {
        switch Int(value.rounded()) {
        case 0: return 0
        case 1: return 10
        case 2: return 15
        case 3: return 20
        default: return 0
        }
    }

    private func seedSettingsIfNeeded() {
        guard !didSeedSettings else { return }
        didSeedSettings = true
        builderCount = dataService.builderCount
        builderApprenticeLevel = dataService.builderApprenticeLevel
        labAssistantLevel = dataService.labAssistantLevel
        alchemistLevel = dataService.alchemistLevel
        goldPassBoost = dataService.goldPassBoost
        clampBuilderCount()
    }

    private func fetchPreviewTownHall() {
        let tag = normalizePlayerTag(playerTag)
        guard !tag.isEmpty else { return }
        dataService.fetchProfilePreview(tag: tag) { profile in
            previewTownHallLevel = profile?.townHallLevel ?? 0
            clampBuilderCount()
        }
    }

    private func clampBuilderCount() {
        if builderCount > maxBuilders { builderCount = maxBuilders }
        if builderCount < 2 { builderCount = 2 }
    }

    private func persistSettings() {
        clampBuilderCount()
        dataService.builderCount = builderCount
        dataService.builderApprenticeLevel = builderApprenticeLevel
        dataService.labAssistantLevel = labAssistantLevel
        dataService.alchemistLevel = alchemistLevel
        dataService.goldPassBoost = goldPassBoost
    }

    private func sliderRow(title: String, value: Binding<Int>, maxLevel: Int, unlockedAt: Int, iconName: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let iconName {
                    Image(iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                }
                Text(title)
                Spacer()
                Text("Lv \(value.wrappedValue)/\(maxLevel)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: 0...Double(maxLevel),
                step: 1
            )
        }
    }

    @ViewBuilder
    private func helpCard(title: String, description: String? = nil, bullets: [String] = []) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            if let description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if !bullets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(bullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            Text(bullet)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    private func scheduleFocusIfNeeded() {
        guard step == .tagEntry else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            fieldFocused = true
        }
    }

#if canImport(UIKit)
    private func importVillageDataFromClipboard() {
        guard let input = UIPasteboard.general.string, !input.isEmpty else {
            statusMessage = "Clipboard was empty—copy your export from Clash first."
            return
        }
        dataService.parseJSONFromClipboard(input: input)
        let count = dataService.activeUpgrades.count
        if count > 0 {
            statusMessage = "Imported \(count) upgrades from your clipboard."
        } else {
            statusMessage = "Processed the clipboard data, but no upgrades were detected."
        }
    }
#endif

    private func sanitizeInput(_ raw: String) -> String {
        let uppercase = raw.uppercased()
        let allowed = CharacterSet(charactersIn: "#ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var sanitized = String(uppercase.filter { char in
            guard let scalar = char.unicodeScalars.first else { return false }
            return allowed.contains(scalar)
        })

        if let hashIndex = sanitized.firstIndex(of: "#"), hashIndex != sanitized.startIndex {
            sanitized.remove(at: hashIndex)
            sanitized.insert("#", at: sanitized.startIndex)
        }

        if sanitized.count > 15 {
            sanitized = String(sanitized.prefix(15))
        }

        return sanitized
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

private struct IdleStatusRow: View {
    let title: String
    let status: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pause.circle")
                .font(.title2)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(status)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct EquipmentView: View {
    @EnvironmentObject private var dataService: DataService
    @State private var rarityFilter: EquipmentRarityFilter = .all
    @State private var selectedHeroFilter: String = EquipmentView.allHeroesLabel
    @State private var showLocked = true

    private static let allHeroesLabel = "All Heroes"
    private static let oreCostTable = OreCostTable.shared
    private static let equipmentMetadata = EquipmentDataStore.shared

    var body: some View {
        NavigationStack {
            List {
                if equipmentLocked {
                    equipmentLockedState
                } else if equipmentEntries.isEmpty {
                    emptyState
                } else {
                    summarySection
                    filtersSection
                    equipmentSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Equipment")
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(summaryTitle)
                    .font(.headline)
                OreTotalsView(totals: totalOreCost, showStarry: totalOreCost.starry > 0)
            }
            .padding(.vertical, 4)
        }
    }

    private var summaryTitle: String {
        let isAllHeroes = selectedHeroFilter == Self.allHeroesLabel
        if isAllHeroes && showLocked {
            switch rarityFilter {
            case .all:
                return "Total to max all equipment"
            case .epic:
                return "Total to max all epic equipment"
            case .common:
                return "Total to max all common equipment"
            }
        }
        return "Total to max all displayed equipment"
    }

    private var filtersSection: some View {
        Section("Filters") {
            Picker("Rarity", selection: $rarityFilter) {
                ForEach(EquipmentRarityFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Picker("Hero", selection: $selectedHeroFilter) {
                ForEach(heroOptions, id: \.self) { hero in
                    Text(hero).tag(hero)
                }
            }

            Toggle("Show locked equipment", isOn: $showLocked)
        }
    }

    private var equipmentSection: some View {
        ForEach(groupedHeroes, id: \.self) { hero in
            Section {
                ForEach(groupedEntries[hero] ?? []) { entry in
                    let totals = EquipmentView.oreCostTable
                        .totalCost(from: entry.level, to: entry.maxLevel)
                        .adjusted(for: entry.rarity)
                    EquipmentRow(entry: entry, totals: totals)
                }
            } header: {
                HeroSectionHeader(heroName: hero)
            }
        }
    }

    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No equipment data yet")
                    .font(.headline)
                Text("Sync your profile to load hero equipment levels.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var equipmentLockedState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("Equipment unlocks at Town Hall 8")
                    .font(.headline)
                Text("Reach Town Hall 8 to start managing hero equipment and ore costs.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var heroOptions: [String] {
        let heroes = equipmentEntries
            .map { $0.hero }
            .filter { !$0.isEmpty }
        let unique = Array(Set(heroes)).sorted()
        return [Self.allHeroesLabel] + unique
    }

    private var filteredEntries: [EquipmentEntry] {
        equipmentEntries
            .filter { entry in
                switch rarityFilter {
                case .all:
                    return true
                case .common:
                    return entry.rarity == .common
                case .epic:
                    return entry.rarity == .epic
                }
            }
            .filter { entry in
                guard selectedHeroFilter != Self.allHeroesLabel else { return true }
                return entry.hero == selectedHeroFilter
            }
            .filter { entry in
                showLocked || entry.isUnlocked
            }
            .sorted { lhs, rhs in
                if lhs.hero != rhs.hero {
                    return lhs.hero < rhs.hero
                }
                if lhs.rarity != rhs.rarity {
                    return lhs.rarity.sortRank < rhs.rarity.sortRank
                }
                return lhs.name < rhs.name
            }
    }

    private var groupedEntries: [String: [EquipmentEntry]] {
        Dictionary(grouping: filteredEntries, by: { $0.hero })
            .mapValues { entries in
                entries.sorted { lhs, rhs in
                    if lhs.rarity != rhs.rarity {
                        return lhs.rarity.sortRank < rhs.rarity.sortRank
                    }
                    return lhs.name < rhs.name
                }
            }
    }

    private var groupedHeroes: [String] {
        let heroes = groupedEntries.keys.filter { !$0.isEmpty }.sorted()
        return heroes
    }

    private var totalOreCost: OreTotals {
        filteredEntries.reduce(OreTotals()) { partial, entry in
            let totals = EquipmentView.oreCostTable
                .totalCost(from: entry.level, to: entry.maxLevel)
                .adjusted(for: entry.rarity)
            return partial + totals
        }
    }

    private var equipmentEntries: [EquipmentEntry] {
        let profile = dataService.currentProfile?.cachedProfile ?? dataService.cachedProfile
        guard let profile else { return [] }
        let hasEquipmentUnlocked = profile.townHallLevel >= 8
        let equipmentList: [HeroEquipment] = profile.heroEquipment ?? []
        let levelsByName = Dictionary(
            uniqueKeysWithValues: equipmentList.map { ($0.name.lowercased(), $0) }
        )

        return EquipmentView.equipmentMetadata.entries.compactMap { metadata in
            let heroUnlockLevel = heroUnlockTownHall(metadata.hero)
            guard profile.townHallLevel >= heroUnlockLevel else {
                return nil
            }
            let lookupKey = metadata.name.lowercased()
            let equipment = levelsByName[lookupKey]
            let level = hasEquipmentUnlocked ? (equipment?.level ?? 0) : 0
            let maxLevel = metadata.rarity.maxLevel
            let isUnlocked = hasEquipmentUnlocked && equipment != nil

            return EquipmentEntry(
                name: metadata.name,
                level: level,
                maxLevel: maxLevel,
                hero: metadata.hero,
                rarity: metadata.rarity,
                isUnlocked: isUnlocked
            )
        }
    }

    private func heroUnlockTownHall(_ heroName: String) -> Int {
        let normalized = heroName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "barbarian king":
            return 8
        case "archer queen":
            return 8
        case "minion prince":
            return 9
        case "grand warden":
            return 11
        case "royal champion":
            return 13
        default:
            return 8
        }
    }

    private var equipmentLocked: Bool {
        let profile = dataService.currentProfile?.cachedProfile ?? dataService.cachedProfile
        guard let profile else { return false }
        return profile.townHallLevel > 0 && profile.townHallLevel < 8
    }
}

private struct EquipmentEntry: Identifiable {
    var id: String { name }
    let name: String
    let level: Int
    let maxLevel: Int
    let hero: String
    let rarity: EquipmentRarity
    let isUnlocked: Bool

    var assetName: String {
        "equipment/\(name.slugifiedAssetName)"
    }

    var remainingLevels: Int {
        max(0, maxLevel - level)
    }
}

private enum EquipmentRarity: String {
    case common
    case epic

    var label: String { rawValue.capitalized }

    static func from(maxLevel: Int) -> EquipmentRarity {
        if maxLevel >= 27 {
            return .epic
        }
        return .common
    }

    var maxLevel: Int {
        switch self {
        case .common:
            return 18
        case .epic:
            return 27
        }
    }

    var sortRank: Int {
        switch self {
        case .common:
            return 0
        case .epic:
            return 1
        }
    }
}

private enum EquipmentRarityFilter: String, CaseIterable, Identifiable {
    case all
    case common
    case epic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "All"
        case .common:
            return "Common"
        case .epic:
            return "Epic"
        }
    }
}

private struct EquipmentRow: View {
    let entry: EquipmentEntry
    let totals: OreTotals

    private var showStarry: Bool {
        entry.rarity == .epic
    }

    private var levelCosts: [(level: Int, cost: OreTotals)] {
        guard entry.level < entry.maxLevel else { return [] }
        return (entry.level + 1...entry.maxLevel).compactMap { level in
            let cost = OreCostTable.levelCost(for: level)
                .adjusted(for: entry.rarity)
            return (level: level, cost: cost)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(entry.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemBackground)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.headline)
                    Text(entry.hero)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Lv \(entry.level)/\(entry.maxLevel)")
                        .font(.subheadline)
                    Text(entry.isUnlocked ? "Unlocked" : "Locked")
                        .font(.caption2)
                        .foregroundColor(entry.isUnlocked ? .green : .red)
                }
            }

            if entry.remainingLevels == 0 {
                Text("Max level")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Text("Remaining levels: \(entry.remainingLevels)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(spacing: 6) {
                    ForEach(levelCosts, id: \.level) { item in
                        HStack {
                            Text("Lvl \(item.level):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            OreTotalsView(totals: item.cost, showStarry: showStarry, compact: true)
                        }
                    }
                }

                Divider()

                HStack {
                    Text("Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    OreTotalsView(totals: totals, showStarry: showStarry, compact: true)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HeroSectionHeader: View {
    let heroName: String

    var body: some View {
        HStack(spacing: 10) {
            Image(heroAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
            Text(heroName)
                .font(.headline)
        }
        .padding(.vertical, 4)
    }

    private var heroAssetName: String {
        switch heroName {
        case "Barbarian King":
            return "heroes/Barbarian_King"
        case "Archer Queen":
            return "heroes/Archer_Queen"
        case "Grand Warden":
            return "heroes/Grand_Warden"
        case "Royal Champion":
            return "heroes/Royal_Champion"
        case "Minion Prince":
            return "heroes/minion_prince"
        default:
            return "heroes/Barbarian_King"
        }
    }
}

private struct OreTotalsView: View {
    let totals: OreTotals
    var showStarry: Bool = true
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 10 : 16) {
            OreBadge(imageName: "equipment/shiny_ore", value: totals.shiny, compact: compact)
            OreBadge(imageName: "equipment/glowy_ore", value: totals.glowy, compact: compact)
            if showStarry {
                OreBadge(imageName: "equipment/starry_ore", value: totals.starry, compact: compact)
            }
        }
    }
}

private struct OreBadge: View {
    let imageName: String
    let value: Int
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 16 : 18, height: compact ? 16 : 18)
            Text(NumberFormatter.ore.string(from: NSNumber(value: value)) ?? "0")
                .font(compact ? .caption : .subheadline)
                .foregroundColor(.primary)
        }
        .padding(.vertical, compact ? 2 : 4)
        .padding(.horizontal, compact ? 6 : 8)
        .background(RoundedRectangle(cornerRadius: compact ? 8 : 10).fill(Color(.tertiarySystemBackground)))
    }
}

private struct OreTotals: Equatable {
    var shiny: Int = 0
    var glowy: Int = 0
    var starry: Int = 0

    static func + (lhs: OreTotals, rhs: OreTotals) -> OreTotals {
        OreTotals(
            shiny: lhs.shiny + rhs.shiny,
            glowy: lhs.glowy + rhs.glowy,
            starry: lhs.starry + rhs.starry
        )
    }

    func adjusted(for rarity: EquipmentRarity) -> OreTotals {
        switch rarity {
        case .common:
            return OreTotals(shiny: shiny, glowy: glowy, starry: 0)
        case .epic:
            return self
        }
    }
}

private struct OreCostTable {
    struct LevelCost {
        let level: Int
        let shiny: Int
        let glowy: Int
        let starry: Int
        let cumulativeShiny: Int
        let cumulativeGlowy: Int
        let cumulativeStarry: Int
    }

    let levels: [Int: LevelCost]
    let maxLevel: Int

    func totalCost(from currentLevel: Int, to maxLevel: Int) -> OreTotals {
        guard currentLevel < maxLevel else { return OreTotals() }
        let cappedMax = min(maxLevel, self.maxLevel)
        let cappedCurrent = max(0, min(currentLevel, cappedMax))

        if let maxCost = levels[cappedMax], let currentCost = levels[cappedCurrent] {
            return OreTotals(
                shiny: maxCost.cumulativeShiny - currentCost.cumulativeShiny,
                glowy: maxCost.cumulativeGlowy - currentCost.cumulativeGlowy,
                starry: maxCost.cumulativeStarry - currentCost.cumulativeStarry
            )
        }

        var totals = OreTotals()
        if cappedCurrent < cappedMax {
            for level in (cappedCurrent + 1)...cappedMax {
                if let cost = levels[level] {
                    totals.shiny += cost.shiny
                    totals.glowy += cost.glowy
                    totals.starry += cost.starry
                }
            }
        }
        return totals
    }

    static let shared = load()

    static func load() -> OreCostTable {
        if let url = Bundle.main.url(forResource: "ore_costs", withExtension: "csv", subdirectory: "json_files")
            ?? Bundle.main.url(forResource: "ore_costs", withExtension: "csv"),
           let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            return parse(csv: text)
        }

        return parse(csv: defaultCSV)
    }

    static func levelCost(for level: Int) -> OreTotals {
        guard let cost = OreCostTable.shared.levels[level] else { return OreTotals() }
        return OreTotals(shiny: cost.shiny, glowy: cost.glowy, starry: cost.starry)
    }

    static func parse(csv: String) -> OreCostTable {
        let lines = csv
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
        guard lines.count > 1 else {
            return OreCostTable(levels: [:], maxLevel: 0)
        }

        var parsed: [Int: LevelCost] = [:]
        var maxLevel = 0

        for line in lines.dropFirst() {
            let columns = line.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard columns.count >= 7,
                  let level = Int(columns[0]),
                  let shiny = Int(columns[1]),
                  let glowy = Int(columns[2]),
                  let starry = Int(columns[3]),
                  let cumulativeShiny = Int(columns[4]),
                  let cumulativeGlowy = Int(columns[5]),
                  let cumulativeStarry = Int(columns[6])
            else { continue }

            parsed[level] = LevelCost(
                level: level,
                shiny: shiny,
                glowy: glowy,
                starry: starry,
                cumulativeShiny: cumulativeShiny,
                cumulativeGlowy: cumulativeGlowy,
                cumulativeStarry: cumulativeStarry
            )
            maxLevel = max(maxLevel, level)
        }

        return OreCostTable(levels: parsed, maxLevel: maxLevel)
    }

    private static let defaultCSV = """
Level,Shiny Ore Cost,Glowy Ore Cost,Starry Ore Cost,Cumulative Shiny,Cumulative Glowy,Cumulative Starry
1,0,0,0,0,0,0
2,120,0,0,120,0,0
3,240,20,0,360,20,0
4,400,0,0,760,20,0
5,600,0,0,1360,20,0
6,840,100,0,2200,120,0
7,1120,0,0,3320,120,0
8,1440,0,0,4760,120,0
9,1800,200,10,6560,320,10
10,1900,0,0,8460,320,10
11,2000,0,0,10460,320,10
12,2100,400,20,12560,720,30
13,2200,0,0,14760,720,30
14,2300,0,0,17060,720,30
15,2400,600,30,19460,1320,60
16,2500,0,0,21960,1320,60
17,2600,0,0,24560,1320,60
18,2700,600,50,27260,1920,110
19,2800,0,0,30060,1920,110
20,2900,0,0,32960,1920,110
21,3000,600,100,35960,2520,210
22,3100,0,0,39060,2520,210
23,3200,0,0,42260,2520,210
24,3300,600,120,45560,3120,330
25,3400,0,0,48960,3120,330
26,3500,0,0,52460,3120,330
27,3600,600,150,56060,3720,480
"""
}

private struct EquipmentMetadata: Decodable, Hashable {
    let name: String
    let hero: String
    let rarity: EquipmentRarity

    private enum CodingKeys: String, CodingKey {
        case name
        case hero
        case rarity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.hero = try container.decode(String.self, forKey: .hero)
        let rarityRaw = (try? container.decode(String.self, forKey: .rarity)) ?? "common"
        self.rarity = EquipmentRarity(rawValue: rarityRaw.lowercased()) ?? .common
    }
}

private struct EquipmentDataFile: Decodable {
    let equipment: [EquipmentMetadata]
}

private struct EquipmentDataStore {
    let entries: [EquipmentMetadata]

    static let shared = EquipmentDataStore.load()

    static func load() -> EquipmentDataStore {
        if let url = Bundle.main.url(forResource: "equipment_data", withExtension: "json", subdirectory: "json_files")
            ?? Bundle.main.url(forResource: "equipment_data", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(EquipmentDataFile.self, from: data) {
            return EquipmentDataStore(entries: decoded.equipment)
        }
        return EquipmentDataStore(entries: [])
    }
}

private extension NumberFormatter {
    static let ore: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

private extension String {
    var slugifiedAssetName: String {
        let lowered = lowercased()
        let allowed = lowered.map { char -> Character in
            if char.isLetter || char.isNumber {
                return char
            }
            return "_"
        }
        let collapsed = String(allowed)
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return collapsed
    }
}

fileprivate func normalizePlayerTag(_ rawTag: String) -> String {
    let uppercase = rawTag
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased()
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    let filteredScalars = uppercase.unicodeScalars.filter { allowed.contains($0) }
    var view = String.UnicodeScalarView()
    view.append(contentsOf: filteredScalars)
    return String(view)
}

private extension View {
    @ViewBuilder
    func monitorScenePhase(_ scenePhase: ScenePhase, handler: @escaping (ScenePhase) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            onChange(of: scenePhase) { _, newPhase in
                handler(newPhase)
            }
        } else {
            onChange(of: scenePhase) { newPhase in
                handler(newPhase)
            }
        }
    }

    @ViewBuilder
    func onChangeCompat<Value: Equatable>(of value: Value, perform action: @escaping (Value) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            onChange(of: value) { newValue in
                action(newValue)
            }
        }
    }
}

