import SwiftUI
import CryptoKit
import GoogleMobileAds
import Combine
import StoreKit
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(UIKit)
import UIKit
import AppTrackingTransparency
#if canImport(UIImageColors)
import UIImageColors
#endif
#endif
#if canImport(WebKit)
import WebKit
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

#if canImport(UIKit)
#endif
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var iapManager: IAPManager
    @StateObject private var dataService: DataService
    @ObservedObject private var remoteContent = RemoteContentService.shared
    @State private var forceExpandedTabBar = false
    @State private var selectedTab: MainTab = .dashboard
    @AppStorage("hasCompletedInitialSetup") private var hasCompletedInitialSetup = false

    @AppStorage("hasPromptedAppTracking") private var hasPromptedAppTracking = false
    @AppStorage("lastGoldPassResetApplied") private var lastGoldPassResetApplied: Double = 0
    @State private var onboardingJustCompleted = false
    @State private var onboardingLocked = false // keep onboarding available until submission
    @AppStorage("lastGoldPassResetPrompt") private var lastGoldPassResetPrompt: Double = 0
    @AppStorage("firstLaunchTimestamp") private var firstLaunchTimestamp: Double = 0
    @AppStorage("adsPreference") private var adsPreference: AdsPreference = .fullScreen

    // Suppress full-screen interstitials for the initial run for a short window so
    // they are not the first thing users see after onboarding. Does not reset on
    // in-app factory reset (stored relative to first launch timestamp).
    private let interstitialSuppressionWindow: TimeInterval = 2 * 60 // 2 minutes

    // Ensure interstitials do not show more than once every 4 hours.
    @AppStorage("lastInterstitialShownAt") private var lastInterstitialShownAt: Double = 0

    // Replaced modal onboarding flow with a dedicated onboarding tab.
    // Control which screen is visible using `selectedTab` (see MainTab.onboarding).
    // `showInitialSetup` variable removed to improve interoperability with system prompts.
    @State private var initialSetupTag: String = ""
    @State private var showGoldPassResetPrompt = false
    @StateObject private var interstitialManager = InterstitialAdManager()
    @State private var hasShownLaunchAd = false
    @State private var isAttemptingLaunchAd = false

    init() {
        let apiKey = Self.apiKey()
        _dataService = StateObject(wrappedValue: DataService(apiKey: apiKey))
        // Request ATT first before showing onboarding.
        // If ATT hasn't been prompted yet, show an intermediate waiting view
        // that lets the user trigger ATT or skip it — this avoids requiring a restart
        // when ATT is pre-denied or disabled.
        let completed = UserDefaults.standard.bool(forKey: "hasCompletedInitialSetup")

        // Show onboarding immediately if ATT has already been prompted (or is determined).
        // On first launch (no completed setup) default to the Onboarding tab
        let shouldShowOnboardingInitially = !completed
        _selectedTab = State(initialValue: shouldShowOnboardingInitially ? .onboarding : .dashboard)
        _onboardingLocked = State(initialValue: shouldShowOnboardingInitially)

        // Initialize the first launch timestamp once (persisted across runs)
        let existingFirst = UserDefaults.standard.double(forKey: "firstLaunchTimestamp")
        if existingFirst <= 0 {
            let now = Date().timeIntervalSince1970
            UserDefaults.standard.set(now, forKey: "firstLaunchTimestamp")
            // also mirror to AppStorage-backed property
            // (it will be read into `firstLaunchTimestamp` on next view update)
        }
    }

    @State private var showOnboardingHelp = false
    @State private var onboardingHelpPage: InfoSheetPage = .welcome

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
        Group {
            if !hasCompletedInitialSetup {
                // Lock the UI to the onboarding flow until setup completes.
                NavigationStack {
                    InitialSetupView(playerTag: $initialSetupTag) { submission in
                        handleInitialSetupSubmission(submission)
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                onboardingHelpPage = .welcome
                                showOnboardingHelp = true
                            } label: {
                                Image(systemName: "questionmark.circle")
                            }
                            .accessibilityLabel("Show Help")
                        }
                    }
                    .sheet(isPresented: $showOnboardingHelp) {
                        HelpSheetView()
                            .adaptivePanelPresentation()
                    }
                    .environmentObject(dataService)
                    .navigationTitle("Get Started")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .preferredColorScheme(dataService.appearancePreference.preferredColorScheme)
                .environmentObject(dataService)
                .onAppear {
                    dataService.reconcileRemoteEvents(remoteContent.events, at: Date())
                    dataService.pruneCompletedUpgrades()
                    initialSetupTag = dataService.playerTag
                    onboardingLocked = true
                    selectedTab = .onboarding
                }
                .onChangeCompat(of: dataService.playerTag) { newValue in
                    if selectedTab == .onboarding {
                        initialSetupTag = newValue
                    }
                }
            } else {
                TabView(selection: $selectedTab) {
                    DashboardView()
                        .tabItem { Label("Home", systemImage: "house.fill") }
                        .tag(MainTab.dashboard)

                    ProfileDetailView()
                        .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                        .tag(MainTab.profile)

                    ProgressTabView()
                        .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
                        .tag(MainTab.progress)

                    EquipmentView()
                        .tabItem { Label("Equipment", systemImage: "shield.lefthalf.filled") }
                        .tag(MainTab.equipment)


                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(MainTab.settings)
                }
                .minimizeTabBarOnScrollIfAvailable(forceExpanded: forceExpandedTabBar)
                .environment(\.tabBarExpansionRequest, { expanded in
                    guard forceExpandedTabBar != expanded else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { forceExpandedTabBar = expanded }
                })
                .onChangeCompat(of: selectedTab) { _ in forceExpandedTabBar = false }
                .preferredColorScheme(dataService.appearancePreference.preferredColorScheme)
                .environmentObject(dataService)
                .sheet(isPresented: $showGoldPassResetPrompt) {
                    GoldPassResetPrompt()
                        .environmentObject(dataService)
                }
                .onAppear {
                    dataService.reconcileRemoteEvents(remoteContent.events, at: Date())
                    dataService.pruneCompletedUpgrades()
                    if dataService.profiles.contains(where: { $0.notificationSettings.notificationsEnabled }) {
                        dataService.requestNotificationAuthorizationIfNeeded { granted in
                            if granted { dataService.scheduleUpgradeNotifications() }
                        }
                    }
                    handleGoldPassResetIfNeeded()
                    presentLaunchInterstitialIfNeeded()
                    handleWidgetImportRequest()
                    initialSetupTag = dataService.playerTag
                    selectedTab = .dashboard
                    onboardingLocked = false
                }
                .monitorScenePhase(scenePhase) { phase in
                    switch phase {
                    case .active, .background:
                        dataService.pruneCompletedUpgrades()
                        if phase == .active {
                            dataService.reconcileRemoteEvents(remoteContent.events, at: Date())
                            Task { await remoteContent.refreshIfNeeded() }
                            handleGoldPassResetIfNeeded()
                            presentLaunchInterstitialIfNeeded()
                            handleWidgetImportRequest()
                            // Force widget refresh when app opens to sync boost timers
                            #if canImport(WidgetKit)
                            WidgetKit.WidgetCenter.shared.reloadAllTimelines()
                            #endif
                        } else {
                            hasShownLaunchAd = false
                        }
                    default:
                        break
                    }
                }
                .onChangeCompat(of: dataService.playerTag) { newValue in
                    if selectedTab == .onboarding {
                        initialSetupTag = newValue
                    }
                }
                // If ads are removed by a purchase elsewhere in the UI, clear any
                // loaded interstitials immediately to avoid a queued ad appearing.
                .onChangeCompat(of: iapManager.isAdsRemoved) { removed in
                    if removed {
                        interstitialManager.clearLoadedAd()
                        hasShownLaunchAd = true
                        NSLog("📵 [ADMOB_DEBUG] Ads removed – cleared loaded interstitials from ContentView observer")
                    }
                }
            }
        }
        .task { await remoteContent.refreshIfNeeded() }
        .onReceive(remoteContent.$now) { now in
            if scenePhase == .active { dataService.reconcileRemoteEvents(remoteContent.events, at: now) }
        }
    }

    private func presentLaunchInterstitialIfNeeded() {
        // Do not attempt to load/present ads until onboarding/initial setup is completed
        guard hasCompletedInitialSetup else { return }
        guard adsPreference == .fullScreen else { return }
        guard !iapManager.isAdsRemoved else { return }

        // Suppress interstitials for a short grace period after the very first app
        // launch so users don't see a full-screen ad immediately after onboarding.
        if firstLaunchTimestamp > 0 {
            let elapsed = Date().timeIntervalSince1970 - firstLaunchTimestamp
            if elapsed < interstitialSuppressionWindow {
                NSLog("📵 [ADMOB_DEBUG] Suppressing launch interstitial (first-run grace period: \(Int(interstitialSuppressionWindow))s) — elapsed \(Int(elapsed))s")
                return
            }
        }

        // Enforce global 4-hour throttling for launch interstitials.
        let now = Date().timeIntervalSince1970
        let fourHours: TimeInterval = 4 * 3600
        if now - lastInterstitialShownAt < fourHours {
            NSLog("📵 [ADMOB_DEBUG] Suppressing launch interstitial (throttled: last shown \(Int(now - lastInterstitialShownAt))s ago)")
            return
        }

        guard !hasShownLaunchAd, !isAttemptingLaunchAd else { return }

        isAttemptingLaunchAd = true
        interstitialManager.load()
        attemptPresentLaunchAd(retries: 20)
    }

    private func attemptPresentLaunchAd(retries: Int) {
        guard retries > 0 else {
            hasShownLaunchAd = true
            isAttemptingLaunchAd = false
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if interstitialManager.isReady,
               let root = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow })?.rootViewController {
                // Re-check that ads haven't been removed between load and present.
                guard !iapManager.isAdsRemoved else {
                    NSLog("📵 [ADMOB_DEBUG] Aborting interstitial presentation because ads were removed by purchase")
                    isAttemptingLaunchAd = false
                    interstitialManager.clearLoadedAd()
                    hasShownLaunchAd = true
                    return
                }

                interstitialManager.present(from: root) {
                    hasShownLaunchAd = true
                    isAttemptingLaunchAd = false
                    // Record the time the interstitial was shown to enforce the 4-hour limit.
                    self.lastInterstitialShownAt = Date().timeIntervalSince1970
                    interstitialManager.load()
                }
            } else {
                attemptPresentLaunchAd(retries: retries - 1)
            }
        }
    }

    private func handleWidgetImportRequest() {
        let defaults = UserDefaults(suiteName: DataService.appGroup)
        let requested = defaults?.bool(forKey: "widget_import_requested") ?? false
        guard requested else { return }
        defaults?.set(false, forKey: "widget_import_requested")
        _ = dataService.importClipboardFromPasteboardForWidget()
    }

    private func handleInitialSetupSubmission(_ submission: ProfileSetupSubmission) {
        let normalized = submission.tag
        guard !normalized.isEmpty || submission.rawJSON != nil else { return }
        initialSetupTag = normalized
        if let rawJSON = submission.rawJSON {
            dataService.parseJSONFromClipboard(input: rawJSON)
        }
        if !normalized.isEmpty {
            dataService.playerTag = normalized
            dataService.refreshCurrentProfile(force: true)
        }
        dataService.builderCount = submission.builderCount
        dataService.builderApprenticeLevel = submission.builderApprenticeLevel
        dataService.labAssistantLevel = submission.labAssistantLevel
        dataService.alchemistLevel = submission.alchemistLevel
        dataService.goldPassBoost = submission.goldPassBoost
        dataService.goldPassReminderEnabled = submission.goldPassBoost > 0

        // Apply any notification preferences selected during onboarding to
        // the current profile. If the user enabled notifications here, this
        // will trigger the permission prompt via DataService.
        dataService.notificationSettings = submission.notificationSettings

        hasCompletedInitialSetup = true
        // mark that we just completed onboarding to suppress immediate prompts
        onboardingJustCompleted = true
        onboardingLocked = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            onboardingJustCompleted = false
        }


        // After successful submission, ensure we switch to the main dashboard tab
        selectedTab = .dashboard
    }


    private func handleGoldPassResetIfNeeded(referenceDate: Date = Date()) {
        let resetDate = goldPassResetDate(for: referenceDate)
        let resetTime = resetDate.timeIntervalSince1970

        if referenceDate >= resetDate, lastGoldPassResetApplied < resetTime {
            lastGoldPassResetApplied = resetTime
            dataService.resetGoldPassBoostForAllProfiles()
        }

          if referenceDate >= resetDate,
              lastGoldPassResetPrompt < resetTime,
              dataService.profiles.contains(where: { $0.goldPassReminderEnabled }) {
            // Suppress the prompt if we just completed onboarding (to avoid a
            // jarring permission/finish flow) or if the app was first opened
            // less than 4 hours ago.
            guard !onboardingJustCompleted else { return }
            let firstSeen = firstLaunchTimestamp
            if firstSeen > 0 {
                let elapsed = referenceDate.timeIntervalSince1970 - firstSeen
                // 4 hours = 14400 seconds
                if elapsed < (4 * 3600) { return }
            }
            lastGoldPassResetPrompt = resetTime
            showGoldPassResetPrompt = true
        }
    }

    private func goldPassResetDate(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = calendar.dateComponents([.year, .month], from: date)

        var resetComponents = DateComponents()
        resetComponents.year = components.year
        resetComponents.month = components.month
        resetComponents.day = 1
        resetComponents.hour = 8
        resetComponents.minute = 0
        resetComponents.second = 0

        // Return the current month's reset (1st of the month at 08:00 UTC).
        // Previously this returned the previous month's reset when called before
        // the current reset time, which caused the prompt to fire early.
        return calendar.date(from: resetComponents) ?? date
    }
}

private struct GoldPassResetPrompt: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataService: DataService

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Gold Pass Status")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("A new season just started. Confirm your Gold Pass boost for this month.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(reminderProfiles) { profile in
                            goldPassCard(for: profile)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Gold Pass")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var reminderProfiles: [PlayerAccount] {
        dataService.profiles.filter { $0.goldPassReminderEnabled }
    }

    private func goldPassCard(for profile: PlayerAccount) -> some View {
        let boost = profile.goldPassBoost
        let boostLabel = boost == 0 ? "None" : "\(boost)%"
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(boost == 0 ? "profile/free_pass" : "profile/gold_pass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dataService.displayName(for: profile))
                        .font(.headline)
                    Text(boost == 0 ? "Free Pass" : "Gold Pass")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(boostLabel)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Slider(
                value: Binding(
                    get: { goldPassBoostToSliderValue(boost) },
                    set: { dataService.updateGoldPassBoost(for: profile.id, boost: sliderValueToGoldPassBoost($0)) }
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
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
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


struct TownHallBadgeView: View {
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

struct ClanBadgeView: View {
    let urlString: String?
    let size: CGFloat
    @State private var cachedImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image = cachedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "shield")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
        .onAppear { loadBadgeIfNeeded() }
        .onChangeCompat(of: urlString) { _ in loadBadgeIfNeeded() }
    }

    private func loadBadgeIfNeeded() {
        guard !isLoading else { return }
        guard let urlString, let url = URL(string: urlString) else {
            cachedImage = nil
            return
        }

        if let cached = ClanBadgeCache.shared.image(for: urlString) {
            cachedImage = cached
            return
        }

        isLoading = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                defer { isLoading = false }
                guard let data, let image = UIImage(data: data) else { return }
                ClanBadgeCache.shared.store(image: image, data: data, for: urlString)
                cachedImage = image
            }
        }.resume()
    }
}

final class ClanBadgeCache {
    static let shared = ClanBadgeCache()
    private let cache = NSCache<NSString, UIImage>()
    private let baseURL: URL?

    private init() {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Zachary-Buschmann.clash-widgets") {
            let dir = container.appendingPathComponent("clan_badges", isDirectory: true)
            if !FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            baseURL = dir
        } else {
            baseURL = nil
        }
    }

    func image(for urlString: String) -> UIImage? {
        if let cached = cache.object(forKey: urlString as NSString) { return cached }
        guard let fileURL = fileURL(for: urlString),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: urlString as NSString)
        return image
    }

    func store(image: UIImage, data: Data, for urlString: String) {
        cache.setObject(image, forKey: urlString as NSString)
        guard let fileURL = fileURL(for: urlString) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func fileURL(for urlString: String) -> URL? {
        guard let baseURL else { return nil }
        let key = sha256(urlString)
        return baseURL.appendingPathComponent("\(key).png")
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}


struct LevelSliderRow: View {
    let title: String
    @Binding var value: Int
    let maxLevel: Int
    let iconName: String?
    @State private var draftValue: Double = 0
    @State private var isEditing = false

    var body: some View {
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
                Text("Lv \(Int(draftValue))/\(maxLevel)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Slider(
                value: $draftValue,
                in: 0...Double(maxLevel),
                step: 1,
                onEditingChanged: { editing in
                    isEditing = editing
                    if !editing {
                        value = Int(draftValue)
                    }
                }
            )
        }
        .onAppear {
            draftValue = Double(value)
        }
        .onChangeCompat(of: value) { newValue in
            if !isEditing {
                draftValue = Double(newValue)
            }
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

struct ProfileSwitcherMenu: View {
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct IdleStatusRow: View {
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
