import SwiftUI
import GoogleMobileAds
import Combine
import StoreKit
#if canImport(UIKit)
import UIKit
import AppTrackingTransparency
#if !targetEnvironment(simulator)
#if canImport(UIImageColors)
import UIImageColors
#endif
#endif
#endif
#if canImport(WebKit)
import WebKit
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

#if canImport(UIKit)
private func clipboardTextFromPasteboard() -> String? {
    let pasteboard = UIPasteboard.general
    let candidates: [(String, [String.Encoding])] = [
        ("public.utf8-plain-text", [.utf8]),
        ("public.utf16-plain-text", [.utf16, .utf16LittleEndian, .utf16BigEndian]),
        ("public.utf32-plain-text", [.utf32, .utf32LittleEndian, .utf32BigEndian]),
        ("public.text", [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian])
    ]

    for (type, encodings) in candidates {
        if let data = pasteboard.data(forPasteboardType: type) {
            for encoding in encodings {
                if let decoded = String(data: data, encoding: encoding), !decoded.isEmpty {
                    return decoded
                }
            }
        }
    }

    return pasteboard.string
}
#endif
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var iapManager: IAPManager
    @StateObject private var dataService: DataService
    @State private var selectedTab: Tab = .dashboard
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

    // Replaced modal onboarding flow with a dedicated onboarding tab.
    // Control which screen is visible using `selectedTab` (see Tab.onboarding).
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
                        ToolbarItem(placement: .navigationBarLeading) {
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
                    }
                    .environmentObject(dataService)
                    .navigationTitle("Get Started")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .preferredColorScheme(dataService.appearancePreference.preferredColorScheme)
                .environmentObject(dataService)
                .onAppear {
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
                        .tag(Tab.dashboard)

                    ProfileDetailView()
                        .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                        .tag(Tab.profile)

                    EquipmentView()
                        .tabItem { Label("Equipment", systemImage: "shield.lefthalf.filled") }
                        .tag(Tab.equipment)

                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(Tab.settings)
                }
                .preferredColorScheme(dataService.appearancePreference.preferredColorScheme)
                .environmentObject(dataService)
                .sheet(isPresented: $showGoldPassResetPrompt) {
                    GoldPassResetPrompt()
                        .environmentObject(dataService)
                }
                .onAppear {
                    dataService.pruneCompletedUpgrades()
                    handleGoldPassResetIfNeeded()
                    presentLaunchInterstitialIfNeeded()
                    initialSetupTag = dataService.playerTag
                    selectedTab = .dashboard
                    onboardingLocked = false
                }
                .monitorScenePhase(scenePhase) { phase in
                    switch phase {
                    case .active, .background:
                        dataService.pruneCompletedUpgrades()
                        if phase == .active {
                            handleGoldPassResetIfNeeded()
                            presentLaunchInterstitialIfNeeded()
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
                    interstitialManager.load()
                }
            } else {
                attemptPresentLaunchAd(retries: retries - 1)
            }
        }
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

        let currentReset = calendar.date(from: resetComponents) ?? date
        if date >= currentReset {
            return currentReset
        }
        return calendar.date(byAdding: .month, value: -1, to: currentReset) ?? currentReset
    }

    private enum Tab: Hashable {
        case onboarding
        case dashboard
        case profile
        case equipment
        case progress
        case palette
        case settings
    }
}

private struct WhatsNewItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

private enum AdsPreference: String, CaseIterable, Identifiable {
    case fullScreen
    case banner

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fullScreen:
            return "Full Screen"
        case .banner:
            return "Banner"
        }
    }
}

private enum InfoSheetPage: String, CaseIterable, Identifiable {
    case welcome = "Welcome"
    case whatsNew = "What’s New"

    var id: String { rawValue }
}

private func defaultWhatsNewItems() -> [WhatsNewItem] {
    loadWhatsNewItems()
}

private func loadWhatsNewItems() -> [WhatsNewItem] {
    // Try to load a `features.txt` from the app bundle first. If not present,
    // fall back to the repository copy embedded below.
    if let url = Bundle.main.url(forResource: "features", withExtension: "txt"),
       let data = try? Data(contentsOf: url),
       let text = String(data: data, encoding: .utf8) {
        return parseFeaturesText(text)
    }

    let fallback = """
    Features of the app:
    - Upgrade tracking via JSON export, done with one button press
    - Home Screen Widgets for builders, Lab/pets, and builder base as well as helpers cooldowns
    - Multiple profile support
    - Notification Support (Profile specific)
    - API Sync for enhanced profile information
    - Rich equipment tracking with upgrade costs and totals to max, adapts to custom filters
    - Gold Pass Support, as well as monthly reminder to set gold pass boost
    - customizability, rearrange the home tab to your needs
    - Fededback form for reporting bugs and glitches, as well as for requesting features
    """

    return parseFeaturesText(fallback)
}

private func parseFeaturesText(_ text: String) -> [WhatsNewItem] {
    var items: [WhatsNewItem] = []

    // First box: keep a friendly note about the first build
    items.append(.init(title: "Welcome — First Build", detail: "Thanks for trying the first build of Clashboard. Quickly track upgrades and export profile JSON with a single tap."))

    let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
    for line in lines {
        guard line.hasPrefix("-") else { continue }
        let entry = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = entry.lowercased()

        let item: WhatsNewItem
        if lower.contains("upgrade") {
            item = .init(title: "Upgrade Tracking", detail: "Track upgrades and export progress as JSON with a single action.")
        } else if lower.contains("widget") || lower.contains("home screen") {
            item = .init(title: "Home Screen Widgets", detail: "Widgets for builders, lab/pets, builder base, and helper cooldowns keep info at a glance.")
        } else if lower.contains("multiple profile") || lower.contains("profiles") {
            item = .init(title: "Multiple Profiles", detail: "Manage and switch between multiple player profiles effortlessly.")
        } else if lower.contains("notification") {
            item = .init(title: "Profile Notifications", detail: "Profile-specific notifications let you know when upgrades complete.")
        } else if lower.contains("api sync") || lower.contains("api") {
            item = .init(title: "API Sync", detail: "Sync with the API for richer, up-to-date profile data.")
        } else if lower.contains("equipment") {
            item = .init(title: "Equipment Tracking", detail: "Track equipment upgrades, costs, and totals, adapted to your filters.")
        } else if lower.contains("gold pass") {
            item = .init(title: "Gold Pass Support", detail: "Set Gold Pass boosts per profile and receive monthly reminders.")
        } else if lower.contains("customiz") || lower.contains("rearrange") {
            item = .init(title: "Customizable Home", detail: "Rearrange the home tab to match your workflow and preferences.")
        } else if lower.contains("feedback") || lower.contains("fedeback") {
            item = .init(title: "Feedback", detail: "Send bug reports or feature requests through the in-app feedback form.")
        } else {
            item = .init(title: String(entry.prefix(40)), detail: entry)
        }

        items.append(item)
    }

    return items
}

private struct InfoSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedPage: InfoSheetPage
    let items: [WhatsNewItem]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Info Pages", selection: $selectedPage) {
                    ForEach(InfoSheetPage.allCases) { page in
                        Text(page.rawValue).tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                TabView(selection: $selectedPage) {
                    HelpSheetContent()
                        .tag(InfoSheetPage.welcome)
                    WhatsNewContent(items: items)
                        .tag(InfoSheetPage.whatsNew)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Help & What’s New")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct WhatsNewContent: View {
    let items: [WhatsNewItem]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("What’s New")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)

                LazyVStack(spacing: 12) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.headline)
                            Text(item.detail)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                }
            }
            .padding()
        }
    }
}

private struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    let items: [WhatsNewItem]

    var body: some View {
        NavigationStack {
            WhatsNewContent(items: items)
            .navigationTitle("What’s New")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        dismiss()
                    }
                }
            }
        }
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

#if canImport(UIKit)
private extension UIImage {
    var averageColor: UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extent = inputImage.extent
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return UIColor(
            red: CGFloat(bitmap[0]) / 255.0,
            green: CGFloat(bitmap[1]) / 255.0,
            blue: CGFloat(bitmap[2]) / 255.0,
            alpha: CGFloat(bitmap[3]) / 255.0
        )
    }

    func croppedToOpaquePixels(alphaThreshold: UInt8 = 8) -> UIImage? {
        guard let cgImage = cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var found = false

        for y in 0..<height {
            let rowOffset = y * bytesPerRow
            for x in 0..<width {
                let alpha = pixelData[rowOffset + (x * bytesPerPixel) + 3]
                if alpha > alphaThreshold {
                    if x < minX { minX = x }
                    if y < minY { minY = y }
                    if x > maxX { maxX = x }
                    if y > maxY { maxY = y }
                    found = true
                }
            }
        }

        guard found else { return nil }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }
}

private extension UIColor {
    func adjustedBrightness(by delta: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        if getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            let newBrightness = min(max(brightness + delta, 0), 1)
            return UIColor(hue: hue, saturation: saturation, brightness: newBrightness, alpha: alpha)
        }

        var white: CGFloat = 0
        if getWhite(&white, alpha: &alpha) {
            let newWhite = min(max(white + delta, 0), 1)
            return UIColor(white: newWhite, alpha: alpha)
        }

        return self
    }

    func adjustedSaturation(by delta: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        if getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            let newSaturation = min(max(saturation + delta, 0), 1)
            return UIColor(hue: hue, saturation: newSaturation, brightness: brightness, alpha: alpha)
        }
        return self
    }
}
#endif

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

private struct TownHallPaletteView: View {
    private let maxTownHallLevel = 17

    var body: some View {
        NavigationStack {
            List {
                #if canImport(UIKit) && !targetEnvironment(simulator) && canImport(UIImageColors)
                ForEach(1...maxTownHallLevel, id: \.self) { level in
                    Section {
                        TownHallPaletteRow(level: level)
                    }
                }
                #else
                Section {
                    Text("Town Hall palettes require UIImageColors on iOS.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                #endif
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Town Hall Palettes")
        }
    }

    #if canImport(UIKit) && !targetEnvironment(simulator) && canImport(UIImageColors)
    private struct TownHallPaletteRow: View {
        let level: Int
        @State private var palette: UIImageColors?

        var body: some View {
            let image = townHallImage(for: level)
            let displayImage = image ?? UIImage(systemName: "questionmark.square")
            let swatches = paletteColors

            return HStack(alignment: .center, spacing: 12) {
                if let displayImage {
                    Image(uiImage: displayImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemBackground)))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("TH \(level)")
                        .font(.headline)

                    if !swatches.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(swatches.indices, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(swatches[index]))
                                    .frame(width: 28, height: 28)
                            }
                        }
                    } else {
                        Text("No colors detected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .onAppear(perform: loadPalette)
        }

        private var paletteColors: [UIColor] {
            if let palette {
                return [palette.primary, palette.secondary, palette.detail, palette.background]
                    .compactMap { $0 }
            }
            return []
        }

        private func loadPalette() {
            #if canImport(UIImageColors)
            guard palette == nil else { return }
            let image = townHallImage(for: level)
            DispatchQueue.global(qos: .userInitiated).async {
                let colors = image?.getColors(quality: .high)
                DispatchQueue.main.async {
                    palette = colors
                }
            }
            #endif
        }

        private func townHallImage(for level: Int) -> UIImage? {
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
        }
    }
    #endif
}

private struct DashboardView: View {
    @EnvironmentObject private var dataService: DataService
    @State private var importStatus: String?
    @AppStorage("hasSeenClashboardOnboarding") private var hasSeenOnboarding = false
    @AppStorage("lastSeenAppVersion") private var lastSeenAppVersion = ""
    @AppStorage("lastSeenBuildNumber") private var lastSeenBuildNumber = ""
    @AppStorage("hasShownWhatsNewFirstColdBoot") private var hasShownWhatsNewFirstColdBoot = false
    @AppStorage("homeSectionOrder") private var homeSectionOrder = "builders,lab,pets,helpers,builderBase,starLab"
    @AppStorage("adsPreference") private var adsPreference: AdsPreference = .fullScreen
    @State private var showInfoSheet = false
    @State private var infoSheetPage: InfoSheetPage = .welcome
    @State private var showHomeOrderSheet = false
    @State private var orderedSections: [HomeSection] = HomeSection.defaultOrder
    @State private var didRunStartupSheets = false

    var body: some View {
        NavigationStack {
            dashboardList
            .sheet(isPresented: $showInfoSheet) {
                InfoSheetView(selectedPage: $infoSheetPage, items: defaultWhatsNewItems())
            }
            .sheet(isPresented: $showHomeOrderSheet) {
                HomeSectionOrderSheet(order: $orderedSections)
            }
            .onAppear {
                orderedSections = parseHomeSectionOrder()
                // Prefer showing the onboarding 'Welcome' for first-time users.
                // What's New should automatically appear only:
                //  - once after the very first cold boot of the app (first run after
                //    install) and never again because of navigation, and
                //  - on subsequent runs when the app *version* changes.
                // Use `didRunStartupSheets` to ensure this logic only runs once per
                // app session so returning from Settings won't re-trigger it.
                if !didRunStartupSheets {
                    if !hasSeenOnboarding {
                        hasSeenOnboarding = true
                        infoSheetPage = .welcome
                        showInfoSheet = true
                    } else if !hasShownWhatsNewFirstColdBoot {
                        // First cold boot after install — show Whats New once and
                        // record that we've shown it for this install.
                        infoSheetPage = .whatsNew
                        showInfoSheet = true
                        hasShownWhatsNewFirstColdBoot = true
                        markWhatsNewSeen()
                    } else if shouldShowWhatsNew {
                        infoSheetPage = .whatsNew
                        showInfoSheet = true
                        markWhatsNewSeen()
                    }
                    didRunStartupSheets = true
                }
            }
            .onChangeCompat(of: orderedSections) { newValue in
                persistHomeSectionOrder(newValue)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Clashboard")
            .toolbar {
                if #available(iOS 26.0, *) {
                    dashboardToolbar
                } else {
                    dashboardToolbarFallback
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

    private var dashboardList: some View {
        List {
            Section("Selected Profile") {
                selectedProfileSection
            }

            if adsPreference == .banner {
                Section {
                    BannerAdPlaceholder()
                }
            }

            if dataService.activeUpgrades.isEmpty {
                Section {
                    Text("No active upgrades tracked. Paste your exported JSON to start tracking timers.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            ForEach(orderedSections, id: \.self) { section in
                sectionView(for: section)
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
    }

    private var selectedProfileSection: some View {
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

    private enum HomeSection: String, CaseIterable, Identifiable {
        case helpers
        case builders
        case lab
        case pets
        case builderBase
        case starLab

        var id: String { rawValue }

        var title: String {
            switch self {
            case .helpers: return "Helpers"
            case .builders: return "Home Village Builders"
            case .lab: return "Laboratory"
            case .pets: return "Pets"
            case .builderBase: return "Builder Base"
            case .starLab: return "Star Laboratory"
            }
        }

        static let defaultOrder: [HomeSection] = [.builders, .lab, .pets, .helpers, .builderBase, .starLab]
    }

    private struct HelperCooldownDisplay: Identifiable {
        let id: Int
        let name: String
        let iconName: String
        let level: Int
        let cooldownSeconds: Int

        var cooldownText: String {
            if cooldownSeconds <= 0 { return "Ready" }
            let hours = cooldownSeconds / 3600
            let minutes = (cooldownSeconds % 3600) / 60
            let seconds = cooldownSeconds % 60
            if hours > 0 { return "\(hours)h \(minutes)m" }
            if minutes > 0 { return "\(minutes)m \(seconds)s" }
            return "\(seconds)s"
        }
    }

    @available(iOS 26.0, *)
    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
        // Group left-side buttons together
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Button {
                // Default to the Welcome page when the user explicitly requests help.
                infoSheetPage = .welcome
                showInfoSheet = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .accessibilityLabel("Show Help")
            
            Button {
                orderedSections = parseHomeSectionOrder()
                showHomeOrderSheet = true
            } label: {
                Image(systemName: "arrow.up.and.down.circle")
            }
            .accessibilityLabel("Reorder Home Cards")
        }
        
        // Spacer to separate button groups visually
        ToolbarSpacer(placement: .navigationBarLeading)

        // Import button - separate on right
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: pasteAndImport) {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Import Village Data")
        }
    }

    @ToolbarContentBuilder
    private var dashboardToolbarFallback: some ToolbarContent {
        // What's New button - separate container on left
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                // Default to the Welcome page when the user explicitly requests help.
                infoSheetPage = .welcome
                showInfoSheet = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .accessibilityLabel("Show Help")
        }

        // Reorder Home Cards button - separate container on left
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                orderedSections = parseHomeSectionOrder()
                showHomeOrderSheet = true
            } label: {
                Image(systemName: "arrow.up.and.down.circle")
            }
            .accessibilityLabel("Reorder Home Cards")
        }

        // Import button - separate on right
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: pasteAndImport) {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Import Village Data")
        }
    }

    @ViewBuilder
    private func sectionView(for section: HomeSection) -> some View {
        switch section {
        case .helpers:
            if !helperCooldowns.isEmpty {
                Section(section.title) {
                    helperCooldownSummaryRow
                }
            }
        case .builders:
            if totalBuilders > 0 {
                Section(section.title) {
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
        case .lab:
            if displayedTownHallLevel >= 3 {
                Section(section.title) {
                    if !labUpgrades.isEmpty {
                        ForEach(labUpgrades) { upgrade in
                            BuilderRow(upgrade: upgrade)
                        }
                    } else {
                        IdleStatusRow(title: "Laboratory", status: "Idle")
                    }
                }
            }
        case .pets:
            if displayedTownHallLevel >= 14 {
                Section(section.title) {
                    if !petUpgrades.isEmpty {
                        ForEach(petUpgrades) { upgrade in
                            BuilderRow(upgrade: upgrade)
                        }
                    } else {
                        IdleStatusRow(title: "Pet House", status: "Idle")
                    }
                }
            }
        case .builderBase:
            if displayedTownHallLevel >= 6 {
                Section(section.title) {
                    if !builderBaseUpgrades.isEmpty {
                        ForEach(builderBaseUpgrades) { upgrade in
                            BuilderRow(upgrade: upgrade)
                        }
                    } else {
                        IdleStatusRow(title: "Builder Base", status: "Idle")
                    }
                }
            }
        case .starLab:
            if displayedBuilderHallLevel >= 6 {
                Section(section.title) {
                    if !starLabUpgrades.isEmpty {
                        ForEach(starLabUpgrades) { upgrade in
                            BuilderRow(upgrade: upgrade)
                        }
                    } else {
                        IdleStatusRow(title: "Star Laboratory", status: "Idle")
                    }
                }
            }
        }
    }

    private var helperCooldowns: [HelperCooldownDisplay] {
        let rawHelpers = dataService.currentHelperCooldowns()
        let mapped = rawHelpers.compactMap { helper -> HelperCooldownDisplay? in
            switch helper.id {
            case 93000000:
                return HelperCooldownDisplay(id: helper.id, name: "Builder's Apprentice", iconName: "profile/apprentice_builder", level: helper.level, cooldownSeconds: helper.cooldownSeconds)
            case 93000001:
                return HelperCooldownDisplay(id: helper.id, name: "Lab Assistant", iconName: "profile/lab_assistant", level: helper.level, cooldownSeconds: helper.cooldownSeconds)
            case 93000002:
                return HelperCooldownDisplay(id: helper.id, name: "Alchemist", iconName: "profile/alchemist", level: helper.level, cooldownSeconds: helper.cooldownSeconds)
            default:
                return nil
            }
        }
        return mapped.sorted { $0.id < $1.id }
    }

    private var helperCooldownSummaryRow: some View {
        let cooldownSeconds = helperCooldowns.map { $0.cooldownSeconds }.max() ?? 0
        let totalSeconds = 23 * 60 * 60
        let remaining = max(min(cooldownSeconds, totalSeconds), 0)
        let progress = max(0, min(1, 1 - (Double(remaining) / Double(totalSeconds))))

        return HStack(spacing: 12) {
            VStack {
                Image("buildings_home/helper_s_hut")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Helper Cooldown")
                    .font(.headline)
                    .lineLimit(1)

                Text(formatHelperCooldown(remaining))
                    .font(.subheadline)
                    .foregroundColor(remaining > 0 ? .orange : .green)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green)
                            .frame(width: geo.size.width * CGFloat(progress), height: 8)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatHelperCooldown(_ seconds: Int) -> String {
        if seconds <= 0 { return "Ready" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }

    private var totalBuilders: Int {
        max(dataService.builderCount, 0) + (goblinBuilderActive ? 1 : 0)
    }

    private var goblinBuilderActive: Bool {
        builderVillageUpgrades.contains { $0.usesGoblin }
    }

    private var busyBuilders: Int {
        builderVillageUpgrades.count
    }

    private var idleBuilders: Int {
        max(totalBuilders - busyBuilders, 0)
    }

    private func parseHomeSectionOrder() -> [HomeSection] {
        let raw = homeSectionOrder.split(separator: ",").map { String($0) }
        let parsed = raw.compactMap { HomeSection(rawValue: $0) }
        if parsed.isEmpty { return HomeSection.defaultOrder }
        let missing = HomeSection.defaultOrder.filter { !parsed.contains($0) }
        return parsed + missing
    }

    private func persistHomeSectionOrder(_ order: [HomeSection]) {
        homeSectionOrder = order.map { $0.rawValue }.joined(separator: ",")
    }

    private struct HomeSectionOrderSheet: View {
        @Binding var order: [HomeSection]
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                List {
                    ForEach(order, id: \.self) { section in
                        Text(section.title)
                    }
                    .onMove { offsets, destination in
                        order.move(fromOffsets: offsets, toOffset: destination)
                    }
                }
                .environment(\.editMode, .constant(.active))
                .navigationTitle("Reorder Home Cards")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    private var activeProfileName: String {
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

    private var displayedBuilderHallLevel: Int {
        if let cached = dataService.cachedProfile?.builderHallLevel {
            return cached
        }
        return dataService.currentProfile?.cachedProfile?.builderHallLevel ?? 0
    }

    private var builderVillageUpgrades: [BuildingUpgrade] {
        dataService.activeUpgrades.filter { $0.category == .builderVillage }
    }

    private var labUpgrades: [BuildingUpgrade] {
        dataService.activeUpgrades.filter { $0.category == .lab }
    }

    private var starLabUpgrades: [BuildingUpgrade] {
        dataService.activeUpgrades.filter { $0.category == .starLab }
    }

    private var petUpgrades: [BuildingUpgrade] {
        dataService.activeUpgrades.filter { $0.category == .pets }
    }

    private var builderBaseUpgrades: [BuildingUpgrade] {
        dataService.activeUpgrades.filter { $0.category == .builderBase }
    }

    private func pasteAndImport() {
        #if canImport(UIKit)
        guard let input = clipboardTextFromPasteboard() else { return }
        switch dataService.importClipboardToMatchingProfile(input: input) {
        case .success(_, let upgradesCount, let switched):
            importStatus = switched
            ? "Imported \(upgradesCount) upgrades and switched profiles"
            : "Imported \(upgradesCount) upgrades"
        case .missingProfile(let tag):
            importStatus = "Profile #\(tag) not found. Add it in Settings first."
        case .invalidJSON:
            importStatus = "Could not parse clipboard data."
        }
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

    private var shouldShowWhatsNew: Bool {
        // Only show "What's New" when the *version* (CFBundleShortVersionString)
        // changes — ignore build number changes to avoid showing the popup for
        // incremental Xcode builds or unrelated app events (IAP, restores, etc.).
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard !version.isEmpty else { return false }
        return version != lastSeenAppVersion
    }

    private func markWhatsNewSeen() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        guard !version.isEmpty || !build.isEmpty else { return }
        lastSeenAppVersion = version
        lastSeenBuildNumber = build
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
    @AppStorage("profileSettingsExpanded") private var profileSettingsExpanded = true
    @AppStorage("adsPreference") private var adsPreference: AdsPreference = .fullScreen
    #if !targetEnvironment(simulator) && canImport(UIImageColors)
    @State private var townHallPalette: UIImageColors?
    @State private var townHallPaletteLevel: Int = 0
    #endif
    private let labAssistantInternalName = "ResearchApprentice"
    private let builderApprenticeInternalName = "BuilderApprentice"
    private let alchemistInternalName = "Alchemist"

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
                        if adsPreference == .banner {
                            VStack {
                                BannerAdPlaceholder()
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
                            .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 1)
                        }
                        profileSettingsCard
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
                loadTownHallPaletteIfNeeded()
                clampHelperLevels()
            }
            .onChangeCompat(of: townHallLevel) { _ in
                clampBuilderCount()
                clampHelperLevels()
                loadTownHallPaletteIfNeeded()
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
        let builderHall = resolvedProfile?.builderHallLevel ?? 0
        let builderTrophies = resolvedProfile?.builderBaseTrophies ?? 0
        let warStars = resolvedProfile?.warStars ?? 0
        let lastSync = dataService.currentProfile?.lastAPIFetchDate

        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 12) {
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

                HStack {
                    infoPill(title: "Builder Hall", value: builderHall > 0 ? "\(builderHall)" : "–")
                    infoPill(title: "Builder Trophies", value: builderTrophies > 0 ? "\(builderTrophies)" : "–")
                    infoPill(title: "War Stars", value: warStars > 0 ? "\(warStars)" : "–")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let lastSync {
                    Text("Last synced \(lastSync, style: .relative) ago")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            if let leagueAsset = leagueAssetName(for: league) {
                Image(leagueAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .padding(12)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            profileGradient(for: thLevel)
        )
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder
    private var profileGradientSwatches: some View {
        #if canImport(UIKit) && !targetEnvironment(simulator) && canImport(UIImageColors)
                    if let palette = townHallPalette {
                        let swatches = [palette.primary, palette.secondary, palette.detail, palette.background]
                                .compactMap { $0 }
            VStack(alignment: .leading, spacing: 8) {
                Text("Dominant Colors")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    ForEach(swatches.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(swatches[index]))
                            .frame(width: 36, height: 36)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #endif
    }

    private func profileGradient(for townHallLevel: Int) -> LinearGradient {
        #if canImport(UIKit)
        if let image = townHallImage(for: townHallLevel) {
            #if !targetEnvironment(simulator) && canImport(UIImageColors)
            if let palette = townHallPalette {
                let primaryColor = palette.detail ?? palette.background ?? palette.primary ?? palette.secondary ?? UIColor.systemBlue
                let secondaryColor = palette.background ?? palette.detail ?? primaryColor
                let primary = primaryColor
                    .adjustedSaturation(by: 0.28)
                    .adjustedBrightness(by: 0.14)
                let secondary = secondaryColor
                    .adjustedSaturation(by: 0.24)
                    .adjustedBrightness(by: 0.02)
                return LinearGradient(
                    colors: [Color(primary).opacity(0.95), Color(secondary).opacity(0.95)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            #endif

            if let average = image.averageColor {
                let primary = average
                    .adjustedSaturation(by: 0.22)
                    .adjustedBrightness(by: 0.18)
                let secondary = average
                    .adjustedSaturation(by: 0.18)
                    .adjustedBrightness(by: -0.06)
                return LinearGradient(
                    colors: [Color(primary).opacity(0.92), Color(secondary).opacity(0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        #endif
        return LinearGradient(colors: [.purple.opacity(0.8), .blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func townHallImage(for level: Int) -> UIImage? {
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

    private func loadTownHallPaletteIfNeeded() {
        #if canImport(UIKit) && !targetEnvironment(simulator) && canImport(UIImageColors)
        let level = townHallLevel
        guard level > 0 else {
            townHallPalette = nil
            townHallPaletteLevel = 0
            return
        }
        if townHallPaletteLevel == level, townHallPalette != nil { return }
        townHallPaletteLevel = level
        let image = townHallImage(for: level)
        DispatchQueue.global(qos: .userInitiated).async {
            let palette = image?.getColors(quality: .high)
            DispatchQueue.main.async {
                if townHallPaletteLevel == level {
                    townHallPalette = palette
                }
            }
        }
        #endif
    }

    private func leagueAssetName(for league: String) -> String? {
        let trimmed = league.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.localizedCaseInsensitiveCompare("Unranked") == .orderedSame { return nil }
        if trimmed.localizedCaseInsensitiveCompare("Legend League") == .orderedSame {
            return "leagues/legend_league"
        }
        let firstWord = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        let normalized = firstWord.lowercased()
        let allowed = CharacterSet.alphanumerics
        let mapped = normalized.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let collapsed = String(mapped)
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        guard !collapsed.isEmpty else { return nil }
        return "leagues/\(collapsed)"
    }


    private var profileSettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                profileSettingsExpanded.toggle()
            } label: {
                HStack {
                    Text("Profile Settings")
                        .font(.headline)
                    Spacer()
                    Image(systemName: profileSettingsExpanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if profileSettingsExpanded {
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

                if labAssistantMaxLevel > 0 {
                    sliderRow(title: "Lab Assistant", value: $dataService.labAssistantLevel, maxLevel: labAssistantMaxLevel, iconName: "profile/lab_assistant")
                }

                if builderApprenticeMaxLevel > 0 {
                    sliderRow(title: "Builder's Apprentice", value: $dataService.builderApprenticeLevel, maxLevel: builderApprenticeMaxLevel, iconName: "profile/apprentice_builder")
                }

                if alchemistMaxLevel > 0 {
                    sliderRow(title: "Alchemist", value: $dataService.alchemistLevel, maxLevel: alchemistMaxLevel, iconName: "profile/alchemist")
                }

                if townHallLevel >= 7 {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(profileGoldPassIconName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                            HStack(spacing: 6) {
                                Text(profileGoldPassTitle)
                                    .font(.body)
                                TimelineView(.periodic(from: .now, by: 60.0)) { timelineContext in
                                    Text(timeUntilGoldPassReset(from: timelineContext.date))
                                        .font(.callout)
                                        .foregroundColor(.secondary)
                                }
                            }
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.tertiarySystemBackground)))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
            .stroke(Color(.separator).opacity(0.6), lineWidth: 1)
        )
    }

    private var heroShowcase: some View {
        guard let heroes = resolvedProfile?.heroes, !heroes.isEmpty else {
            return AnyView(EmptyView())
        }
        let excludedHeroes: Set<String> = [
            "battle machine",
            "battle copter"
        ]
        let filteredHeroes = heroes.filter { hero in
            !excludedHeroes.contains(hero.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        guard !filteredHeroes.isEmpty else {
            return AnyView(EmptyView())
        }
        let orderedNames = [
            "Barbarian King",
            "Archer Queen",
            "Grand Warden",
            "Royal Champion",
            "Minion Prince"
        ]
        let sortedHeroes = filteredHeroes.sorted { lhs, rhs in
            let leftIndex = orderedNames.firstIndex(of: lhs.name) ?? orderedNames.count
            let rightIndex = orderedNames.firstIndex(of: rhs.name) ?? orderedNames.count
            if leftIndex == rightIndex {
                return lhs.level > rhs.level
            }
            return leftIndex < rightIndex
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                Text("Hero Levels")
                    .font(.headline)
                ForEach(sortedHeroes, id: \.name) { hero in
                    HStack {
                        if let assetName = heroAssetName(hero.name) {
                            Image(assetName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)
                                .frame(width: 32, height: 32)
                        }
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
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.tertiarySystemBackground)))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(.separator).opacity(0.6), lineWidth: 1)
            )
        )
    }

    private func heroAssetName(_ heroName: String) -> String? {
        let trimmed = heroName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowercased = trimmed.lowercased()
        switch lowercased {
        case "barbarian king":
            return "heroes/Barbarian_King"
        case "archer queen":
            return "heroes/Archer_Queen"
        case "grand warden":
            return "heroes/Grand_Warden"
        case "royal champion":
            return "heroes/Royal_Champion"
        case "minion prince":
            return "heroes/minion_prince"
        default:
            return nil
        }
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
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color(.tertiarySystemBackground)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color(.separator).opacity(0.6), lineWidth: 1)
                    )
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

    private var labAssistantMaxLevel: Int {
        dataService.helperMaxLevel(internalName: labAssistantInternalName, townHallLevel: townHallLevel)
    }

    private var builderApprenticeMaxLevel: Int {
        dataService.helperMaxLevel(internalName: builderApprenticeInternalName, townHallLevel: townHallLevel)
    }

    private var alchemistMaxLevel: Int {
        dataService.helperMaxLevel(internalName: alchemistInternalName, townHallLevel: townHallLevel)
    }

    private func clampBuilderCount() {
        if dataService.builderCount > maxBuilders {
            dataService.builderCount = maxBuilders
        }
        if dataService.builderCount < 2 {
            dataService.builderCount = 2
        }
    }

    private func clampHelperLevels() {
        let labMax = labAssistantMaxLevel
        let builderMax = builderApprenticeMaxLevel
        let alchemistMax = alchemistMaxLevel

        if labMax == 0 {
            dataService.labAssistantLevel = 0
        } else if dataService.labAssistantLevel > labMax {
            dataService.labAssistantLevel = labMax
        }

        if builderMax == 0 {
            dataService.builderApprenticeLevel = 0
        } else if dataService.builderApprenticeLevel > builderMax {
            dataService.builderApprenticeLevel = builderMax
        }

        if alchemistMax == 0 {
            dataService.alchemistLevel = 0
        } else if dataService.alchemistLevel > alchemistMax {
            dataService.alchemistLevel = alchemistMax
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

    private func timeUntilGoldPassReset(from date: Date) -> String {
        let resetDate = nextGoldPassResetDate(for: date)
        let diff = Int(resetDate.timeIntervalSince(date))
        
        if diff <= 0 { return "Resetting..." }
        
        let days = diff / 86400
        let hours = (diff % 86400) / 3600
        let minutes = (diff % 3600) / 60
        let seconds = diff % 60
        
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m \(seconds)s"
        }
    }

    private func nextGoldPassResetDate(for date: Date) -> Date {
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

        let resetThisMonth = calendar.date(from: resetComponents) ?? date
        if date < resetThisMonth {
            return resetThisMonth
        } else {
            return calendar.date(byAdding: .month, value: 1, to: resetThisMonth) ?? resetThisMonth
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
    @EnvironmentObject var iapManager: IAPManager
    @State private var showAddProfile = false
    @State private var profileToEdit: PlayerAccount?
    @State private var showResetConfirmation = false
    @State private var showFeedbackForm = false
    @State private var isPurchasing = false
    @State private var isRestoringPurchases = false
    @State private var restoreResultMessage: String = ""
    @State private var showRestoreResultAlert = false
    @State private var iapErrorMessage: String?
    @State private var showIAPErrorAlert = false
    @AppStorage("hasCompletedInitialSetup") private var hasCompletedInitialSetup = false
    @AppStorage("profilesSectionExpanded") private var profilesSectionExpanded = true
    @AppStorage("adsPreference") private var adsPreference: AdsPreference = .fullScreen

    private var canCollapseProfiles: Bool {
        dataService.profiles.count >= 2
    }

    var body: some View {
        NavigationStack {
            Form {
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

                    ForEach(profilesToShow) { profile in
                        profileRow(profile)
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

                    Text("Notification preferences are saved per profile.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Paste Settings") {
                    Button {
                        openAppSettings()
                    } label: {
                        Label("Open App Settings", systemImage: "gearshape")
                    }

                    Text("To stop the paste prompt, go to Settings → Apps → Clashboard → Paste From Other Apps and set it to Allow.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Gold Pass") {
                    Toggle("Monthly Gold Pass reminder", isOn: $dataService.goldPassReminderEnabled)
                        .tint(.accentColor)
                    Text("At the season reset (08:00 UTC), Clashboard will ask you to confirm your Gold Pass boost for this profile unless this is disabled.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                }

                Section("Ads") {
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
                                        // Purchase succeeded; we rely on the ContentView observer of
                                        // `iapManager.isAdsRemoved` to clear any loaded interstitials.
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

                        // Show loading / error / retry UI for product loading
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
                            // Only show restore UI when ads haven't been removed on this
                            // device/account — if the entitlement is already present
                            // (e.g. recognized via App Store across devices) there's no
                            // point in offering Restore.
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
                    InlineWebView(url: url)
                        .ignoresSafeArea()
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
            .alert("Purchase Error", isPresented: $showIAPErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(iapErrorMessage ?? "Purchase failed. Please try again later.")
            }
        }
    }

    private let feedbackFormURLString = "https://forms.gle/E7h9kETSokcZLior7"

    private var feedbackFormURL: URL? {
        URL(string: feedbackFormURLString)
    }

    // Localized IAP price text. Prefer the App Store product's `displayPrice` when
    // available; otherwise fall back to a localized currency string for a default
    // amount so the UI doesn't show a hard-coded USD price.
    private var iapPriceText: String {
        if let display = iapManager.products.first?.displayPrice {
            return display
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: 2.99)) ?? "$2.99"
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

    private func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
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
                    // Use a compact ellipsis icon for the row menu. We add a small
                    // background to keep the control row-local and avoid the iPad
                    // automatically promoting it into the navigation toolbar.
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
                        .contentShape(Rectangle())
                        .accessibilityLabel("More options")
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

private struct ProfileSetupSubmission {
    let tag: String
    let builderCount: Int
    let builderApprenticeLevel: Int
    let labAssistantLevel: Int
    let alchemistLevel: Int
    let goldPassBoost: Int
    let rawJSON: String?
    let notificationSettings: NotificationSettings
}

// Simple SwiftUI wrapper for a GAD banner view.
struct BannerAdView: UIViewRepresentable {
    var adUnitID: String = "ca-app-pub-4499177240533852/7133262169"
    @AppStorage("hasCompletedInitialSetup") private var hasCompletedInitialSetup = false

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator
        let rootVC = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController
        banner.rootViewController = rootVC
        // Only load banner ads after the initial onboarding/setup is complete
        if hasCompletedInitialSetup {
            banner.load(Request())
        } else {
            NSLog("📵 [ADMOB_DEBUG] Skipping banner load until onboarding complete")
        }

        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, BannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            NSLog("🚀 [ADMOB_DEBUG] Banner Loaded Successfully ✅")
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            NSLog("🚀 [ADMOB_DEBUG] Banner Failed: \(error.localizedDescription) ❌")
        }
    }
}

// Small in-app debug reporter for ad behavior


final class InterstitialAdManager: NSObject, ObservableObject {
    private var interstitial: InterstitialAd?
    @Published var isReady = false
    private var onDismiss: (() -> Void)?

    // LOAD PRODUCTION INTERSTITIAL
    func load(adUnitID: String? = nil) {
        let chosenID = adUnitID ?? "ca-app-pub-4499177240533852/2764621791"

        let request = Request()
        InterstitialAd.load(with: chosenID, request: request, completionHandler: { [weak self] ad, error in
            if let ad = ad {
                NSLog("🚀 [ADMOB_DEBUG] Interstitial Loaded Successfully ✅")
                self?.interstitial = ad
                self?.isReady = true
            } else {
                NSLog("🚀 [ADMOB_DEBUG] Interstitial Failed: \(error?.localizedDescription ?? "Unknown error") ❌")
                self?.isReady = false
            }
        }
        )
    }

    func present(from root: UIViewController, onDismiss: @escaping () -> Void) {
        guard let interstitial = interstitial else {
            onDismiss()
            return
        }
        self.onDismiss = onDismiss
        interstitial.fullScreenContentDelegate = self
        interstitial.present(from: root)
    }

    /// Clear any loaded interstitial and reset ready state. Call this when ads become disabled
    /// (for example, immediately after a successful purchase) to prevent a queued ad from showing.
    func clearLoadedAd() {
        interstitial = nil
        isReady = false
        onDismiss = nil
    }
}

extension InterstitialAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        onDismiss?()
        isReady = false
        interstitial = nil
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        onDismiss?()
        isReady = false
        interstitial = nil
    }
}

private struct BannerAdPlaceholder: View {
    @EnvironmentObject var iapManager: IAPManager
    @AppStorage("hasCompletedInitialSetup") private var hasCompletedInitialSetup = false
    
    var body: some View {
        if !iapManager.isAdsRemoved && hasCompletedInitialSetup {
            BannerAdView()
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
    }
}

private struct ProfileSetupPane: View {
    @EnvironmentObject private var dataService: DataService
    @Binding var playerTag: String
    let title: String
    let subtitle: String
    let submitTitle: String
    let showCancel: Bool
    let onCancel: (() -> Void)?
    let onSubmit: (ProfileSetupSubmission) -> Void
    /// When false, seed fields with clean defaults instead of copying values from
    /// the currently-selected profile. Use this for the "Add Profile" flow.
    let seedFromExistingProfile: Bool

    @State private var builderCount: Int = 5
    @State private var builderApprenticeLevel: Int = 0
    @State private var labAssistantLevel: Int = 0
    @State private var alchemistLevel: Int = 0
    @State private var goldPassBoost: Int = 0
    @State private var previewTownHallLevel: Int = 0
    @State private var statusMessage: String?
    @State private var pendingImportRawJSON: String?
    @State private var didImportJSON = false
    @State private var didSeedSettings = false
    @State private var showOptionalTag = false
    @State private var importedTag: String?

    // Notification settings for this profile during setup
    @State private var notificationSettings: NotificationSettings = .default

    private enum HelperId {
        static let builderApprentice = 93000000
        static let labAssistant = 93000001
        static let alchemist = 93000002
    }

    private var normalizedTag: String {
        normalizePlayerTag(playerTag)
    }

    private var canContinue: Bool {
        didImportJSON || pendingImportRawJSON != nil || !normalizedTag.isEmpty
    }

    private var showSettings: Bool {
        didImportJSON || pendingImportRawJSON != nil || !normalizedTag.isEmpty
    }

    private var townHallLevel: Int {
        previewTownHallLevel
    }

    private var maxBuilders: Int {
        townHallLevel == 0 ? 6 : (townHallLevel < 10 ? 5 : 6)
    }

    private var labAssistantMaxLevel: Int {
        dataService.helperMaxLevel(internalName: "ResearchApprentice", townHallLevel: townHallLevel)
    }

    private var builderApprenticeMaxLevel: Int {
        dataService.helperMaxLevel(internalName: "BuilderApprentice", townHallLevel: townHallLevel)
    }

    private var alchemistMaxLevel: Int {
        dataService.helperMaxLevel(internalName: "Alchemist", townHallLevel: townHallLevel)
    }

    private var goldPassBoostLabel: String {
        goldPassBoost == 0 ? "None" : "\(goldPassBoost)%"
    }

    private var goldPassTitle: String {
        goldPassBoost == 0 ? "Free Pass" : "Gold Pass"
    }

    // Helper to expose a binding to the local notification settings struct
    private func notificationBindingLocal(_ keyPath: WritableKeyPath<NotificationSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { notificationSettings[keyPath: keyPath] },
            set: { notificationSettings[keyPath: keyPath] = $0 }
        )
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

#if canImport(UIKit)
                    Button {
                        importVillageDataFromClipboard()
                    } label: {
                        Label("Paste & Import Village Data", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
#endif

                    DisclosureGroup(isExpanded: $showOptionalTag) {
                        TextField("e.g. #2CJJRQJ0", text: $playerTag)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                            .onChangeCompat(of: playerTag) { newValue in
                                let sanitized = sanitizeInput(newValue)
                                if sanitized != newValue {
                                    playerTag = sanitized
                                }
                            }
                        Text("Optional. Not required for setup.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } label: {
                        Text("Optional: Player Tag")
                            .font(.headline)
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if showSettings {
                        settingsFields
                        // Profile-specific notification preferences (match Settings UI)
                        VStack(alignment: .leading, spacing: 16) {
                            Section("Notifications") {
                                Toggle("Enable Notifications", isOn: notificationBindingLocal(\.notificationsEnabled))
                                    .tint(.accentColor)

                                if notificationSettings.notificationsEnabled {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Toggle("Builders", isOn: notificationBindingLocal(\.builderNotificationsEnabled))
                                        Toggle("Laboratory", isOn: notificationBindingLocal(\.labNotificationsEnabled))
                                        Toggle("Pet House", isOn: notificationBindingLocal(\.petNotificationsEnabled))
                                        Toggle("Builder Base", isOn: notificationBindingLocal(\.builderBaseNotificationsEnabled))
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                } else {
                                    Text("Allow alerts to be reminded when an upgrade finishes.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Text("Notification preferences are saved per profile.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onCancel?() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    submitProfile()
                } label: {
                    Text(submitTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Color(.systemGroupedBackground))
                .disabled(!canContinue)
            }
            .onAppear { seedSettingsIfNeeded() }
            .onChangeCompat(of: townHallLevel) { _ in
                clampBuilderCount()
                clampHelperLevels()
            }
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

            if labAssistantMaxLevel > 0 {
                sliderRow(title: "Lab Assistant", value: $labAssistantLevel, maxLevel: labAssistantMaxLevel, unlockedAt: 9, iconName: "profile/lab_assistant")
            }

            if builderApprenticeMaxLevel > 0 {
                sliderRow(title: "Builder's Apprentice", value: $builderApprenticeLevel, maxLevel: builderApprenticeMaxLevel, unlockedAt: 10, iconName: "profile/apprentice_builder")
            }

            if alchemistMaxLevel > 0 {
                sliderRow(title: "Alchemist", value: $alchemistLevel, maxLevel: alchemistMaxLevel, unlockedAt: 11, iconName: "profile/alchemist")
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    private func submitProfile() {
        clampBuilderCount()
        clampHelperLevels()
        let submission = ProfileSetupSubmission(
            tag: (importedTag ?? normalizedTag),
            builderCount: builderCount,
            builderApprenticeLevel: builderApprenticeLevel,
            labAssistantLevel: labAssistantLevel,
            alchemistLevel: alchemistLevel,
            goldPassBoost: goldPassBoost,
            rawJSON: pendingImportRawJSON,
            notificationSettings: notificationSettings
        )
        onSubmit(submission)
    }

    private func seedSettingsIfNeeded() {
        guard !didSeedSettings else { return }
        didSeedSettings = true
        if seedFromExistingProfile {
            // Seed values from currently selected profile (existing behavior)
            builderCount = dataService.builderCount
            builderApprenticeLevel = dataService.builderApprenticeLevel
            labAssistantLevel = dataService.labAssistantLevel
            alchemistLevel = dataService.alchemistLevel
            goldPassBoost = dataService.goldPassBoost
            notificationSettings = dataService.notificationSettings
        } else {
            // Start fresh for a new profile — do not copy values from the last
            // profile the user edited/created.
            builderCount = 5
            builderApprenticeLevel = 0
            labAssistantLevel = 0
            alchemistLevel = 0
            goldPassBoost = 0
            notificationSettings = .default
        }
        clampBuilderCount()
        clampHelperLevels()
    }

    private func clampBuilderCount() {
        if builderCount > maxBuilders { builderCount = maxBuilders }
        if builderCount < 2 { builderCount = 2 }
    }

    private func clampHelperLevels() {
        if labAssistantMaxLevel == 0 {
            labAssistantLevel = 0
        } else if labAssistantLevel > labAssistantMaxLevel {
            labAssistantLevel = labAssistantMaxLevel
        }

        if builderApprenticeMaxLevel == 0 {
            builderApprenticeLevel = 0
        } else if builderApprenticeLevel > builderApprenticeMaxLevel {
            builderApprenticeLevel = builderApprenticeMaxLevel
        }

        if alchemistMaxLevel == 0 {
            alchemistLevel = 0
        } else if alchemistLevel > alchemistMaxLevel {
            alchemistLevel = alchemistMaxLevel
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

#if canImport(UIKit)
    private func importVillageDataFromClipboard() {
        guard let input = clipboardTextFromPasteboard(), !input.isEmpty else {
            statusMessage = "Clipboard was empty—copy your export from Clash first."
            return
        }

        guard let export = dataService.decodeExport(from: input) else {
            statusMessage = "Could not parse the clipboard data."
            return
        }

        pendingImportRawJSON = input
        didImportJSON = true
        goldPassBoost = 0

        let helperLevels = dataService.helperLevels(from: export)
        if let level = helperLevels[HelperId.builderApprentice] {
            builderApprenticeLevel = level
        }
        if let level = helperLevels[HelperId.labAssistant] {
            labAssistantLevel = level
        }
        if let level = helperLevels[HelperId.alchemist] {
            alchemistLevel = level
        }

        if let exportTag = export.tag?.trimmingCharacters(in: .whitespacesAndNewlines), !exportTag.isEmpty {
            let normalized = normalizePlayerTag(exportTag)
            importedTag = normalized
            playerTag = normalized
        }

        let inferredTownHall = dataService.inferTownHallLevel(from: export)
        if inferredTownHall > 0 {
            previewTownHallLevel = inferredTownHall
        }

        if let upgrades = dataService.previewImportUpgrades(input: input) {
            let inferredBuilderCount = upgrades.filter { $0.category == .builderVillage && !$0.usesGoblin }.count
            if inferredBuilderCount > builderCount {
                builderCount = inferredBuilderCount
            }
        }

        clampBuilderCount()
        clampHelperLevels()

        statusMessage = "Imported your JSON. Adjust the settings below if needed."
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

private struct AddProfileSheet: View {
    @EnvironmentObject private var dataService: DataService
    @Environment(\.dismiss) private var dismiss
    @State private var playerTag: String = ""
    @State private var showDuplicateTagAlert = false
    @State private var duplicateTagValue = ""
    @State private var showProfileLimitAlert = false

    var body: some View {
        ProfileSetupPane(
            playerTag: $playerTag,
            title: "New Profile",
            subtitle: "Paste your exported village JSON to auto-fill timers and helper levels.",
            submitTitle: "Continue",
            showCancel: true,
            onCancel: { dismiss() },
            onSubmit: { submission in saveProfile(submission) },
            seedFromExistingProfile: false
        )
        .alert("Profile already exists", isPresented: $showDuplicateTagAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A profile with tag #\(duplicateTagValue) already exists. Choose a different tag or switch to that profile.")
        }
        .alert("Profile limit reached", isPresented: $showProfileLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can store up to 20 profiles. Delete one before adding another.")
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

    private func saveProfile(_ submission: ProfileSetupSubmission) {
        if dataService.profiles.count >= 20 {
            showProfileLimitAlert = true
            return
        }
        let resolvedTag: String = {
            if !submission.tag.isEmpty {
                return submission.tag
            }
            if let rawJSON = submission.rawJSON,
               let export = dataService.decodeExport(from: rawJSON),
               let exportTag = export.tag, !exportTag.isEmpty {
                return normalizePlayerTag(exportTag)
            }
            return ""
        }()

        if dataService.hasProfile(withTag: resolvedTag) {
            duplicateTagValue = resolvedTag
            showDuplicateTagAlert = true
            return
        }
        let newProfileId = dataService.addProfile(
            tag: resolvedTag,
            displayName: "",
            builderCount: submission.builderCount,
            builderApprenticeLevel: submission.builderApprenticeLevel,
            labAssistantLevel: submission.labAssistantLevel,
            alchemistLevel: submission.alchemistLevel,
            goldPassBoost: submission.goldPassBoost,
            goldPassReminderEnabled: submission.goldPassBoost > 0,
            notificationSettings: submission.notificationSettings
        )

        // Ensure the runtime `notificationSettings` is updated for the selected profile
        dataService.notificationSettings = submission.notificationSettings

        if let rawJSON = submission.rawJSON {
            dataService.selectProfile(newProfileId)
            dataService.parseJSONFromClipboard(input: rawJSON)
        }

        dataService.selectProfile(newProfileId)
        dataService.builderCount = submission.builderCount
        dataService.builderApprenticeLevel = submission.builderApprenticeLevel
        dataService.labAssistantLevel = submission.labAssistantLevel
        dataService.alchemistLevel = submission.alchemistLevel
        dataService.goldPassBoost = submission.goldPassBoost
        dataService.goldPassReminderEnabled = submission.goldPassBoost > 0

        dismiss()
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
            HelpSheetContent()
            .navigationTitle("Welcome to Clashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct HelpSheetContent: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Welcome to Clashboard")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)

                helpCard(title: "Quick Start", description: "Import your exported village JSON from Clash of Clans to get started.")

                helpCard(title: "IMPORTANT NOTE ⚠️", bullets: [
                    "This app is currently still in development",
                    "Bear with me for these initial releases, as some things will likely be broken or missing",
                    "If anything unexpected happens, please report it via the feedback form in Settings"
                ])

                helpCard(title: "Importing Data", bullets: [
                    "Copy the exported JSON from Clash of Clans",
                    "Tap the + button on the Home tab",
                    "Choose Paste & Import to sync timers and helper levels",
                    "Profile Settings can be adjusted after import"
                ])

                helpCard(title: "Managing Profiles", bullets: [
                    "Tap the switch icon next to your profile name to change players, or use the profile menu in Settings",
                    "Tap Edit within Settings to rename or update tags",
                    "Swipe left on a profile row in Settings to delete"
                ])

                helpCard(title: "Widgets", bullets: [
                    "Add Clashboard widgets from the iOS Home Screen",
                    "Widgets read the latest data each time you import",
                    "Open the app after timers finish to import updated data"
                ])
                helpCard(title: "Disable Allow Paste Popup", description: "To stop the paste prompt, go to  Settings → Apps → Clashboard → Paste From Other Apps and set it to Allow.")
            }
            .padding()
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
    @Binding var playerTag: String
    let onComplete: (ProfileSetupSubmission) -> Void

    var body: some View {
        ProfileSetupPane(
            playerTag: $playerTag,
            title: "Set up your profile",
            subtitle: "Paste your exported village JSON to auto-fill timers and helper levels.",
            submitTitle: "Continue",
            showCancel: false,
            onCancel: nil,
            onSubmit: onComplete,
            seedFromExistingProfile: true
        )
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
    @AppStorage("adsPreference") private var adsPreference: AdsPreference = .fullScreen

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
                    if adsPreference == .banner {
                        Section {
                            BannerAdPlaceholder()
                        }
                    }
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

