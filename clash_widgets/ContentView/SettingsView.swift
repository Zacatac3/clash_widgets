import SwiftUI
import StoreKit

struct SettingsView: View {
    @EnvironmentObject private var dataService: DataService
    @EnvironmentObject var iapManager: IAPManager
    @State private var showAddProfile = false
    @State private var profileToEdit: PlayerAccount?
    @State private var showResetConfirmation = false
    @State private var showResetLayoutConfirmation = false
    @State private var showFeedbackForm = false
    @State private var isPurchasing = false
    @State private var isRestoringPurchases = false
    @State private var restoreResultMessage: String = ""
    @State private var showRestoreResultAlert = false
    @State private var iapErrorMessage: String?
    @State private var showIAPErrorAlert = false
    @State private var showDebugMenu = false
    @AppStorage("hasCompletedInitialSetup") private var hasCompletedInitialSetup = false
    @AppStorage("profilesSectionExpanded") private var profilesSectionExpanded = true
    @AppStorage("adsPreference") private var adsPreference: AdsPreference = .fullScreen

    private var canCollapseProfiles: Bool {
        dataService.profiles.count >= 2
    }

    var body: some View {
        NavigationStack {
            Form {
                profilesSection

                Section("Appearance") {
                    Picker("Dark Mode", selection: $dataService.appearancePreference) {
                        Text("Dark").tag(AppearancePreference.dark)
                        Text("Light").tag(AppearancePreference.light)
                        Text("Device").tag(AppearancePreference.device)
                    }
                    .pickerStyle(.segmented)
                }

                iapSection

                Section("More Settings") {
                    NavigationLink {
                        NotificationSettingsPage()
                            .environmentObject(dataService)
                    } label: {
                        settingsLinkRow(title: "Notifications", systemImage: "bell.badge")
                    }

                    NavigationLink {
                        AppBehaviorSettingsPage()
                            .environmentObject(dataService)
                    } label: {
                        settingsLinkRow(title: "App Behavior", systemImage: "gearshape.2")
                    }

                    NavigationLink {
                        SupportSettingsPage(
                            onOpenFeedback: { showFeedbackForm = true },
                            onRevealDebug: {
                                showDebugMenu.toggle()
                            },
                            appStoreReviewURL: appStoreReviewURL
                        )
                    } label: {
                        settingsLinkRow(title: "Support & Feedback", systemImage: "questionmark.bubble")
                    }

                    if showDebugMenu {
                        NavigationLink {
                            DebugSettingsPage()
                                .environmentObject(dataService)
                        } label: {
                            settingsLinkRow(title: "Debug", systemImage: "ladybug")
                        }
                    }

                    NavigationLink {
                        AdvancedSettingsPage(
                            onResetLayout: { showResetLayoutConfirmation = true },
                            onFactoryReset: { showResetConfirmation = true }
                        )
                        .environmentObject(dataService)
                    } label: {
                        settingsLinkRow(title: "Advanced", systemImage: "wrench.and.screwdriver")
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: profilesSectionExpanded)
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
                    NavigationStack {
                        InlineWebView(url: url)
                            .ignoresSafeArea()
                            .navigationTitle("Feedback")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { showFeedbackForm = false }
                                }
                            }
                    }
                } else {
                    Text("Set feedback form URL in SettingsView.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .alert("Reset Clashboard?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    hasCompletedInitialSetup = false
                    dataService.resetToFactory()
                }
            } message: {
                Text("All profiles, timers, and settings will be erased. You'll need to enter your player tag again before using the app.")
            }
            .alert("Reset Layout?", isPresented: $showResetLayoutConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset Layout", role: .destructive) {
                    dataService.resetLayoutPreferences()
                }
            } message: {
                Text("This only resets home/profile card order and visibility, plus hidden equipment. Your profiles and tracked data stay intact.")
            }
            .alert("Purchase Error", isPresented: $showIAPErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(iapErrorMessage ?? "Purchase failed. Please try again later.")
            }
        }
    }

    private let feedbackFormURLString = "https://forms.gle/E7h9kETSokcZLior7"
    private let appStoreReviewURLString: String? = "https://apps.apple.com/us/app/clashboard/id6758178681?action=write-review"

    private var feedbackFormURL: URL? {
        URL(string: feedbackFormURLString)
    }

    private var appStoreReviewURL: URL? {
        guard let appStoreReviewURLString else { return nil }
        return URL(string: appStoreReviewURLString)
    }

    @ViewBuilder
    private var profilesSection: some View {
        Section("Profiles") {
            if canCollapseProfiles {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        profilesSectionExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text(profilesSectionExpanded ? "Show current profile" : "Show all profiles")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: profilesSectionExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            let profilesToShow: [PlayerAccount] = {
                let expanded = profilesSectionExpanded || !canCollapseProfiles
                if expanded {
                    return sortedProfiles
                }
                if let current = dataService.currentProfile {
                    return [current]
                }
                return []
            }()

            ForEach(Array(profilesToShow.enumerated()), id: \.element.id) { _, profile in
                profileRow(profile, profileNumber: getProfileNumber(profile))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            .animation(.easeInOut(duration: 0.2), value: profilesSectionExpanded)

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
    }

    @ViewBuilder
    private var iapSection: some View {
        Section("Ads & Premium") {
            if iapManager.isAdsRemoved {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Ad-Free Premium Active")
                        .fontWeight(.medium)
                }
            } else {
                Picker("Ad Experience", selection: $adsPreference) {
                    ForEach(AdsPreference.allCases) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
                .pickerStyle(.segmented)

                Text("Choose between a single full-screen ad on launch or smaller banner ads inside the app.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    Task {
                        isPurchasing = true
                        do {
                            let success = try await iapManager.purchase()
                            isPurchasing = false
                            if !success {
                                iapErrorMessage = "Purchase cancelled or did not complete."
                                showIAPErrorAlert = true
                            } else {
                                NSLog("🚀 [IAP] Purchase succeeded — clearing Ads via observer")
                            }
                        } catch {
                            isPurchasing = false
                            iapErrorMessage = error.localizedDescription
                            showIAPErrorAlert = true
                        }
                    }
                } label: {
                    HStack {
                        Text("Unlock Ad-Free")
                        Spacer()
                        if isPurchasing {
                            ProgressView()
                        } else if iapManager.products.first?.displayPrice == nil {
                            Text("Loading…")
                                .bold()
                        } else {
                            Text(iapPriceText)
                                .bold()
                        }
                    }
                }
                .disabled(isPurchasing || iapManager.products.isEmpty)

                if iapManager.isLoadingProducts {
                    Text("Loading price…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let error = iapManager.productsError {
                    HStack {
                        Text("Price unavailable: \(error)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Retry") {
                            Task { await iapManager.loadProducts() }
                        }
                        .font(.caption2)
                    }
                } else if iapManager.products.isEmpty {
                    Button("Retry Price") {
                        Task { await iapManager.loadProducts() }
                    }
                    .font(.caption2)
                }

                HStack {
                    if !iapManager.isAdsRemoved {
                        if isRestoringPurchases {
                            ProgressView()
                                .scaleEffect(0.9)
                                .padding(.trailing, 6)
                            Text("Restoring…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Button("Restore Purchases") {
                                Task {
                                    isRestoringPurchases = true
                                    let success = await iapManager.restorePurchasesAndReturnSuccess()
                                    isRestoringPurchases = false
                                    restoreResultMessage = success ? "Restore succeeded — ads removed if you owned it." : (iapManager.productsError ?? "No purchases found or restore cancelled.")
                                    showRestoreResultAlert = true
                                }
                            }
                            .font(.caption)
                        }
                    }
                    Spacer()
                }
                .alert("Restore Purchases", isPresented: $showRestoreResultAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(restoreResultMessage)
                }
            }
        }
    }

    private func settingsLinkRow(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
    }

    private var iapPriceText: String {
        if let display = iapManager.products.first?.displayPrice {
            return display
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: 2.99)) ?? "$2.99"
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

    private func getProfileNumber(_ profile: PlayerAccount) -> Int? {
        let allProfiles = dataService.profiles
        if let index = allProfiles.firstIndex(where: { $0.id == profile.id }) {
            return index + 1
        }
        return nil
    }

    private func isCurrentProfile(_ profile: PlayerAccount) -> Bool {
        profile.id == dataService.selectedProfileID
    }

    @ViewBuilder
    private func profileRow(_ profile: PlayerAccount, profileNumber: Int?) -> some View {
        let isCurrent = isCurrentProfile(profile)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    TownHallBadgeView(level: townHallLevel(for: profile))
                    if let profileNum = profileNumber {
                        Text("Profile #\(profileNum)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color(.quaternarySystemFill)))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)

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

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }

                Menu {
                    Button {
                        profileToEdit = profile
                    } label: {
                        Label("Edit Profile", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        dataService.deleteProfile(profile.id)
                    } label: {
                        Label("Delete Profile", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
                        .contentShape(Rectangle())
                        .accessibilityLabel("More options")
                }
                .buttonStyle(.borderless)
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
        .contextMenu {
            Button {
                profileToEdit = profile
            } label: {
                Label("Edit Profile", systemImage: "pencil")
            }

            Button(role: .destructive) {
                dataService.deleteProfile(profile.id)
            } label: {
                Label("Delete Profile", systemImage: "trash")
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
