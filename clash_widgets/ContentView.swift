import SwiftUI
#if canImport(UIKit)
import UIKit
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

    private static let apiKeyParts = [
        "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzUxMiIsImtpZCI6IjI4YTMxOGY3LTAwMDAtYTFlYi03ZmExLTJjNzQzM2M2Y2NhNSJ9",
        ".eyJpc3MiOiJzdXBlcmNlbGwiLCJhdWQiOiJzdXBlcmNlbGw6Z2FtZWFwaSIsImp0aSI6IjdiNTg2ZGE4LTk5YTMtNDE0MS1hMmQwLTA0YjgxMTVjNGE1ZCIsImlhdCI6MTc2NzgzMjMwNiwic3ViIjoiZGV2ZWxvcGVyL2IzMzM2MjZkLTlkNjYtZmNjZS0wNTQ2LTNkOGJjZTYzOTBjYyIsInNjb3BlcyI6WyJjbGFzaCJdLCJsaW1pdHMiOlt7InRpZXIiOiJkZXZlbG9wZXIvc2lsdmVyIiwidHlwZSI6InRocm90dGxpbmcifSx7ImNpZHJzIjpbIjQ1Ljc5LjIxOC43OSIsIjE3Mi41OC4xMjYuMTAzIl0sInR5cGUiOiJjbGllbnQifV19",
        ".soreABdHMlQOLiDX6QgkKjGhyhfbR_63adhoQAhyy7IsTk6ZmbK-QO39Q3hcyA8r0RjjNVOoArVJlJ4kz7Z95Q"
    ]

    private static func apiKey() -> String {
        apiKeyParts.joined()
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.dashboard)

            ProfileDetailView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(Tab.profile)

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
        case settings
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
                } else {
                    if !builderVillageUpgrades.isEmpty {
                        Section("Home Village Builders") {
                            ForEach(builderVillageUpgrades) { upgrade in
                                BuilderRow(upgrade: upgrade)
                            }
                        }
                    }

                    if !labUpgrades.isEmpty {
                        Section("Laboratory") {
                            ForEach(labUpgrades) { upgrade in
                                BuilderRow(upgrade: upgrade)
                            }
                        }
                    }

                    if !petUpgrades.isEmpty {
                        Section("Pets") {
                            ForEach(petUpgrades) { upgrade in
                                BuilderRow(upgrade: upgrade)
                            }
                        }
                    }

                    if !builderBaseUpgrades.isEmpty {
                        Section("Builder Base") {
                            ForEach(builderBaseUpgrades) { upgrade in
                                BuilderRow(upgrade: upgrade)
                            }
                        }
                    }

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

private struct AddProfileSheet: View {
    @EnvironmentObject private var dataService: DataService
    @Environment(\.dismiss) private var dismiss

    @State private var playerTag: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Player Tag") {
                    TextField("e.g. #9C082CCU8", text: $playerTag)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("Only the tag is required. ClashDash will pull the latest name and stats automatically when you save.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("New Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        dataService.addProfile(tag: playerTag)
                        dismiss()
                    }
                    .disabled(playerTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
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
    }

    @State private var step: FlowStep = .intro
    @State private var statusMessage: String?
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
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(step == .intro ? "Welcome" : "Add Your Tag")
            .animation(.easeInOut, value: step)
            .onAppear { scheduleFocusIfNeeded() }
            .onChangeCompat(of: step) { _ in scheduleFocusIfNeeded() }
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
                onComplete(normalizedTag)
            } label: {
                Text("Save Tag & Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(normalizedTag.isEmpty)

            Spacer()
            Text("Need to start over later? Use Settings → Reset to Factory Defaults.")
                .font(.caption2)
                .foregroundColor(.secondary)
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

