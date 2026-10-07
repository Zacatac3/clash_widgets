import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct DashboardView: View {
    @EnvironmentObject private var dataService: DataService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var remoteContent = RemoteContentService.shared
    @State private var startupPopupSuppressed = false
    @State private var presentedNews: RemoteNews?
    @State private var didPresentNewsThisLaunch = false
    @State private var importStatus: String?
    @AppStorage("hasSeenClashboardOnboarding") private var hasSeenOnboarding = false
    @AppStorage("lastSeenAppVersion") private var lastSeenAppVersion = ""
    @AppStorage("lastSeenBuildNumber") private var lastSeenBuildNumber = ""
    @AppStorage("hasShownWhatsNewFirstColdBoot") private var hasShownWhatsNewFirstColdBoot = false
    @AppStorage("hasShownFirstImportTip") private var hasShownFirstImportTip = false
    @AppStorage("homeSectionOrder") private var homeSectionOrder = "builders,pets,lab,builderBase,starLab,walls,clanWar,helpers"
    @AppStorage("hiddenHomeSections") private var hiddenHomeSections = ""
    @AppStorage("ipadHomeCardsResetForV111") private var didApplyIPadHomeCardsResetForV111 = false
    @AppStorage("ipadRestoreClassicDashboardLayout") private var iPadRestoreClassicDashboardLayout = false
    @AppStorage("adsPreference") private var adsPreference: AdsPreference = .fullScreen
    @State private var showInfoSheet = false
    @State private var infoSheetPage: InfoSheetPage = .welcome
    @State private var showHomeOrderSheet = false
    @State private var showBoostSheet = false
    @State private var orderedSections: [HomeSection] = HomeSection.defaultOrder
    @State private var hiddenSections: Set<String> = []
    @State private var didRunStartupSheets = false
    @State private var showFirstImportTip = false
    private static let boostBadgeImageCache = NSCache<NSString, UIImage>()

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                dashboardList(width: geometry.size.width)
            }
            .sheet(item: $presentedNews) { item in
                RemoteNewsSheet(item: item).adaptivePanelPresentation()
            }
            .onReceive(remoteContent.$now) { _ in presentLatestNewsIfEligible() }
            .sheet(isPresented: $showInfoSheet) {
                InfoSheetView(selectedPage: $infoSheetPage, sections: defaultWhatsNewSections())
                    .adaptivePanelPresentation()
            }
            .sheet(isPresented: $showHomeOrderSheet) {
                HomeSectionOrderSheet(
                    order: $orderedSections,
                    hidden: $hiddenSections,
                    showRestoreClassicToggle: isPadDevice,
                    restoreClassicLayout: $iPadRestoreClassicDashboardLayout
                )
                .adaptivePanelPresentation()
            }
            .sheet(isPresented: $showBoostSheet) {
                BoostView(dataService: dataService)
                    .adaptivePanelPresentation()
            }
            .sheet(isPresented: $showFirstImportTip) {
                FirstImportTipSheet(isPresented: $showFirstImportTip)
                    .adaptivePanelPresentation()
            }
            .onAppear {
                applyIPadDashboardHardResetIfNeeded()
                orderedSections = parseHomeSectionOrder()
                hiddenSections = parseHiddenSections()
                
                if !hiddenSections.contains("clanWar") {
                    DispatchQueue.global(qos: .userInitiated).async {
                        DispatchQueue.main.async {
                            dataService.refreshCurrentWarStatus(force: false)
                        }
                    }
                }
                
                if !didRunStartupSheets {
                    if !hasSeenOnboarding {
                        hasSeenOnboarding = true
                        infoSheetPage = .welcome
                        showInfoSheet = true
                        startupPopupSuppressed = true
                    } else if !hasShownWhatsNewFirstColdBoot {
                        infoSheetPage = .whatsNew
                        showInfoSheet = true
                        startupPopupSuppressed = true
                        hasShownWhatsNewFirstColdBoot = true
                        markWhatsNewSeen()
                    } else if shouldShowWhatsNew {
                        infoSheetPage = .whatsNew
                        showInfoSheet = true
                        startupPopupSuppressed = true
                        markWhatsNewSeen()
                    }
                    didRunStartupSheets = true
                    presentLatestNewsIfEligible()
                }
            }
            .onChangeCompat(of: orderedSections) { newValue in
                persistHomeSectionOrder(newValue)
            }
            .onChangeCompat(of: hiddenSections) { newValue in
                persistHiddenSections(newValue)
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
                } else if let status = importStatus {
                    let (message, color) = parseImportStatus(status)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(color)
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        )
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private func dashboardList(width: CGFloat) -> some View {
        List {
            Section("Selected Profile") {
                selectedProfileSection
            }

            if !remoteContent.visibleEvents.isEmpty {
                Section("Events") {
                    ForEach(remoteContent.visibleEvents) { event in
                        NavigationLink { RemoteEventDetailView(event: event) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.presentation.title).font(.headline)
                                HStack {
                                    Text(remoteContent.now < event.start ? "Starts in" : "Ends in")
                                    Text(remoteContent.now < event.start ? event.start : event.end, style: .timer).monospacedDigit()
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if shouldUseTwoColumnModules(width: width) {
                Section {
                    modulesTwoColumnLayout
                }
            } else {
                ForEach(orderedSections, id: \.self) { section in
                    sectionView(for: section)
                }
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

    private var modulesTwoColumnLayout: some View {
        let visibleSections = orderedSections.filter { shouldShow(section: $0) }
        let split = splitModulesForColumns(visibleSections)

        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 12) {
                ForEach(split.left, id: \.self) { section in
                    moduleCard(for: section)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            VStack(spacing: 12) {
                ForEach(split.right, id: \.self) { section in
                    moduleCard(for: section)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(.vertical, 4)
    }

    private func shouldUseTwoColumnModules(width: CGFloat) -> Bool {
        horizontalSizeClass == .regular && width >= 900 && !(isPadDevice && iPadRestoreClassicDashboardLayout)
    }

    private var isPadDevice: Bool {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    private func applyIPadDashboardHardResetIfNeeded() {
        guard isPadDevice, shouldApplyIPadHomeCardsResetForV111() else { return }

        let defaultOrderRaw = HomeSection.defaultOrder.map { $0.rawValue }.joined(separator: ",")
        homeSectionOrder = defaultOrderRaw
        hiddenHomeSections = ""
        orderedSections = HomeSection.defaultOrder
        hiddenSections = []
        iPadRestoreClassicDashboardLayout = false
        didApplyIPadHomeCardsResetForV111 = true
    }

    private func shouldApplyIPadHomeCardsResetForV111() -> Bool {
        guard !didApplyIPadHomeCardsResetForV111 else { return false }
        let currentVersion = appVersion
        guard !currentVersion.isEmpty else { return true }
        return isVersion(currentVersion, atLeast: "1.1.1")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private func boostBadgeImage(for boostType: BoostType) -> Image {
        let cacheKey = NSString(string: boostType.assetPath)
        if let cached = Self.boostBadgeImageCache.object(forKey: cacheKey) {
            return Image(uiImage: cached)
        }

        guard let source = UIImage(named: boostType.assetPath) else {
            return Image(boostType.assetPath)
        }

        let processed: UIImage
        if boostType == .builderApprentice || boostType == .labAssistant {
            processed = trimTransparentEdges(from: source)
        } else {
            processed = source
        }

        Self.boostBadgeImageCache.setObject(processed, forKey: cacheKey)
        return Image(uiImage: processed)
    }

    private func isVersion(_ current: String, atLeast minimum: String) -> Bool {
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let minimumParts = minimum.split(separator: ".").compactMap { Int($0) }
        let count = max(currentParts.count, minimumParts.count)

        for index in 0..<count {
            let currentValue = index < currentParts.count ? currentParts[index] : 0
            let minimumValue = index < minimumParts.count ? minimumParts[index] : 0
            if currentValue > minimumValue { return true }
            if currentValue < minimumValue { return false }
        }

        return true
    }

    private func shouldShow(section: HomeSection) -> Bool {
        guard !hiddenSections.contains(section.rawValue) else { return false }

        switch section {
        case .clanWar:
            return dataService.currentWar != nil || dataService.warStatusMessage != nil
        case .helpers:
            return !helperCooldowns.isEmpty
        case .builders:
            return totalBuilders > 0
        case .lab:
            return displayedTownHallLevel >= 3
        case .pets:
            return displayedTownHallLevel >= 14
        case .walls:
            return displayedTownHallLevel >= 2
        case .builderBase:
            return displayedTownHallLevel >= 6
        case .starLab:
            return displayedBuilderHallLevel >= 6
        }
    }

    private func sectionWeight(_ section: HomeSection) -> Int {
        switch section {
        case .clanWar:
            return 4
        case .helpers:
            return 3
        case .builders:
            return max(2, builderVillageUpgrades.count + idleBuilders)
        case .lab:
            return max(2, labUpgrades.count + 1)
        case .pets:
            return max(2, petUpgrades.count + 1)
        case .walls:
            return 4
        case .builderBase:
            return max(2, builderBaseUpgrades.count + idleBuilderBaseBuilders)
        case .starLab:
            return max(2, starLabUpgrades.count + 1)
        }
    }

    private func splitModulesForColumns(_ sections: [HomeSection]) -> (left: [HomeSection], right: [HomeSection]) {
        var left: [HomeSection] = []
        var right: [HomeSection] = []
        var leftWeight = 0
        var rightWeight = 0

        for section in sections {
            let weight = sectionWeight(section)
            if leftWeight <= rightWeight {
                left.append(section)
                leftWeight += weight
            } else {
                right.append(section)
                rightWeight += weight
            }
        }

        return (left, right)
    }

    @ViewBuilder
    private func moduleCard(for section: HomeSection) -> some View {
        DashboardModuleCard(title: section.title) {
            switch section {
            case .clanWar:
                clanWarCardContent
            case .helpers:
                helperCooldownSummaryRow
            case .builders:
                VStack(spacing: 8) {
                    ForEach(builderVillageUpgrades) { upgrade in
                        BuilderRow(upgrade: upgrade)
                    }
                    if idleBuilders > 0 {
                        ForEach(0..<idleBuilders, id: \.self) { index in
                            IdleBuilderRow(builderIndex: busyBuilders + index + 1)
                        }
                    }
                }
            case .lab:
                if !labUpgrades.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(labUpgrades) { upgrade in
                            BuilderRow(upgrade: upgrade)
                        }
                    }
                } else {
                    IdleStatusRow(title: "Laboratory", status: "Idle")
                }
            case .pets:
                if !petUpgrades.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(petUpgrades) { upgrade in
                            BuilderRow(upgrade: upgrade)
                        }
                    }
                } else {
                    IdleStatusRow(title: "Pet House", status: "Idle")
                }
            case .walls:
                wallProgressSummary
            case .builderBase:
                if busyBuilderBaseBuilders > 0 || idleBuilderBaseBuilders > 0 {
                    VStack(spacing: 8) {
                        ForEach(builderBaseUpgrades) { upgrade in
                            BuilderRow(upgrade: upgrade)
                        }
                        if idleBuilderBaseBuilders > 0 {
                            ForEach(0..<idleBuilderBaseBuilders, id: \.self) { index in
                                IdleBuilderRow(
                                    builderIndex: busyBuilderBaseBuilders + index + 1,
                                    titlePrefix: "Builder Base Builder",
                                    iconName: "resources/master_builder"
                                )
                            }
                        }
                    }
                } else {
                    IdleStatusRow(title: "Builder Base", status: "Idle")
                }
            case .starLab:
                if !starLabUpgrades.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(starLabUpgrades) { upgrade in
                            BuilderRow(upgrade: upgrade)
                        }
                    }
                } else {
                    IdleStatusRow(title: "Star Laboratory", status: "Idle")
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

            if let error = dataService.refreshErrorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }

            if let profile = dataService.currentProfile, !profile.activeBoosts.isEmpty {
                let activeBoosts = profile.activeBoosts.filter { $0.endTime > Date() }
                if !activeBoosts.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(activeBoosts, id: \.type) { boost in
                            if let boostType = boost.boostType {
                                VStack(spacing: 2) {
                                    boostBadgeImage(for: boostType)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 32, height: 32)
                                        .padding(6)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                    
                                    TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                                        Text(formatBoostTimeRemaining(boost.endTime))
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            VStack(spacing: 8) {
                Button(action: pasteAndImport) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                        Text("Import Data")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .accessibilityLabel("Import Village Data")
                .frame(maxWidth: .infinity)

                Button(action: {
                    if let url = URL(string: "clashofclans://action=OpenMoreSettings") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "gearshape")
                        Text("Open Game Settings")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 4)
    }

    private enum HomeSection: String, CaseIterable, Identifiable {
        case clanWar
        case helpers
        case builders
        case lab
        case pets
        case walls
        case builderBase
        case starLab

        var id: String { rawValue }

        var title: String {
            switch self {
            case .clanWar: return "Clan War"
            case .helpers: return "Helpers"
            case .builders: return "Home Village Builders"
            case .lab: return "Laboratory"
            case .pets: return "Pets"
            case .walls: return "Walls"
            case .builderBase: return "Builder Base"
            case .starLab: return "Star Laboratory"
            }
        }

        static let defaultOrder: [HomeSection] = [.builders, .pets, .lab, .builderBase, .starLab, .walls, .clanWar, .helpers]
    }

    private struct HelperCooldownDisplay: Identifiable {
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

    @available(iOS 26.0, *)
    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Button {
                infoSheetPage = .welcome
                showInfoSheet = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .overlay(alignment: .topTrailing) {
                        if remoteContent.unreadPopup != nil {
                            Circle().fill(Color.accentColor).frame(width: 6, height: 6).offset(x: 3, y: -3)
                        }
                    }
            }
            .accessibilityLabel("Welcome, What’s New, and News")
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            
            Button {
                orderedSections = parseHomeSectionOrder()
                showHomeOrderSheet = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("Reorder Home Cards")
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            
            Button {
                showBoostSheet = true
            } label: {
                Image(systemName: "flask")
            }
            .accessibilityLabel("Boosts Menu")
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
        
        ToolbarSpacer(placement: .navigationBarLeading)

        ToolbarItem(placement: .navigationBarTrailing) {
            ProfileSwitcherMenu()
        }
    }

    @ToolbarContentBuilder
    private var dashboardToolbarFallback: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                infoSheetPage = .welcome
                showInfoSheet = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .overlay(alignment: .topTrailing) {
                        if remoteContent.unreadPopup != nil {
                            Circle().fill(Color.accentColor).frame(width: 6, height: 6).offset(x: 3, y: -3)
                        }
                    }
            }
            .accessibilityLabel("Welcome, What’s New, and News")
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }

        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                orderedSections = parseHomeSectionOrder()
                showHomeOrderSheet = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("Reorder Home Cards")
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
        
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                showBoostSheet = true
            } label: {
                Image(systemName: "flask")
            }
            .accessibilityLabel("Boosts Menu")
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            ProfileSwitcherMenu()
        }
    }

    @ViewBuilder
    private func sectionView(for section: HomeSection) -> some View {
        switch section {
        case .clanWar:
            if !hiddenSections.contains(section.rawValue) {
                clanWarCard
            }
        case .helpers:
            if !hiddenSections.contains(section.rawValue) && !helperCooldowns.isEmpty {
                Section(section.title) {
                    helperCooldownSummaryRow
                }
            }
        case .builders:
            if !hiddenSections.contains(section.rawValue) && totalBuilders > 0 {
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
            if !hiddenSections.contains(section.rawValue) && displayedTownHallLevel >= 3 {
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
            if !hiddenSections.contains(section.rawValue) && displayedTownHallLevel >= 14 {
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
        case .walls:
            if !hiddenSections.contains(section.rawValue) && displayedTownHallLevel >= 2 {
                Section(section.title) {
                    wallProgressSummary
                }
            }
        case .builderBase:
            if !hiddenSections.contains(section.rawValue) && displayedTownHallLevel >= 6 {
                Section(section.title) {
                    if busyBuilderBaseBuilders > 0 || idleBuilderBaseBuilders > 0 {
                        ForEach(builderBaseUpgrades) { upgrade in
                            BuilderRow(upgrade: upgrade)
                        }
                        if idleBuilderBaseBuilders > 0 {
                            ForEach(0..<idleBuilderBaseBuilders, id: \.self) { index in
                                IdleBuilderRow(
                                    builderIndex: busyBuilderBaseBuilders + index + 1,
                                    titlePrefix: "Builder Base Builder",
                                    iconName: "resources/master_builder"
                                )
                            }
                        }
                    } else {
                        IdleStatusRow(title: "Builder Base", status: "Idle")
                    }
                }
            }
        case .starLab:
            if !hiddenSections.contains(section.rawValue) && displayedBuilderHallLevel >= 6 {
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

    @ViewBuilder
    private var clanWarCard: some View {
        if let war = dataService.currentWar {
            Section("Clan War") {
                clanWarCardContent
            }
        } else if let message = dataService.warStatusMessage {
            Section("Clan War") {
                clanWarCardContent
            }
        }
    }

    @ViewBuilder
    private var clanWarCardContent: some View {
        if let war = dataService.currentWar {
            VStack(alignment: .leading, spacing: 10) {
                if let clan = war.clan, let opponent = war.opponent {
                    HStack(alignment: .top) {
                        HStack(spacing: 10) {
                            ClanBadgeView(urlString: clan.badgeUrls.small, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(clan.name)
                                    .font(.subheadline)
                                    .bold()
                                Text("Stars: \(clan.stars ?? 0)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        HStack(spacing: 10) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(opponent.name)
                                    .font(.subheadline)
                                    .bold()
                                Text("Stars: \(opponent.stars ?? 0)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            ClanBadgeView(urlString: opponent.badgeUrls.small, size: 36)
                        }
                    }
                } else {
                    Text("Status: \(war.state.capitalized)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                let phase = warPhase(for: war)
                warProgressBar(phase: phase)

                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    HStack {
                        if let label = warPhaseTimerLabel(for: war, referenceDate: context.date) {
                            Text(label)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(phase.label)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if let winner = warWinnerLabel(for: war, phase: phase.kind) {
                            Text(winner)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .bold()
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        } else if let message = dataService.warStatusMessage {
            if message.lowercased().contains("clan war league") {
                HStack(spacing: 12) {
                    Image("profile/cwl")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clan War League")
                            .font(.subheadline)
                            .bold()
                        Text(message)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            } else {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func warProgressBar(phase: WarPhaseInfo) -> some View {
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
    }

    private struct WarPhaseInfo {
        enum Kind { case preparation, battle, ended, unknown }
        let kind: Kind
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
            return WarPhaseInfo(kind: .preparation, label: "Preparation Day", progress: progress)
        }
        if let start, let end, now >= start, now < end {
            let total = max(end.timeIntervalSince(start), 1)
            let progress = min(max(now.timeIntervalSince(start) / total, 0), 1)
            return WarPhaseInfo(kind: .battle, label: "Battle Day", progress: progress)
        }
        if let end, now >= end {
            return WarPhaseInfo(kind: .ended, label: "War Ended", progress: 1)
        }
        return WarPhaseInfo(kind: .unknown, label: "War Status", progress: 0)
    }

    private func warWinnerLabel(for war: WarDetails, phase: WarPhaseInfo.Kind) -> String? {
        guard phase == .ended else { return nil }
        guard let clan = war.clan, let opponent = war.opponent else { return nil }
        let clanStars = clan.stars ?? 0
        let oppStars = opponent.stars ?? 0
        if clanStars != oppStars {
            return clanStars > oppStars ? "Winner: \(clan.name)" : "Winner: \(opponent.name)"
        }
        let clanDestruction = clan.destructionPercentage ?? 0
        let oppDestruction = opponent.destructionPercentage ?? 0
        if clanDestruction != oppDestruction {
            return clanDestruction > oppDestruction ? "Winner: \(clan.name)" : "Winner: \(opponent.name)"
        }
        return "War Tied"
    }

    private func parseWarDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return formatter.date(from: value)
    }

    private func warPhaseTimerLabel(for war: WarDetails, referenceDate: Date) -> String? {
        let start = parseWarDate(war.startTime)
        let end = parseWarDate(war.endTime)

        if let _ = parseWarDate(war.preparationStartTime), let start, referenceDate < start {
            let remaining = max(Int(start.timeIntervalSince(referenceDate)), 0)
            let hours = remaining / 3600
            let minutes = (remaining % 3600) / 60
            return String(format: "Prep ends in %dh %dm", hours, minutes)
        }
        if let start, let end, referenceDate >= start, referenceDate < end {
            let remaining = max(Int(end.timeIntervalSince(referenceDate)), 0)
            let hours = remaining / 3600
            let minutes = (remaining % 3600) / 60
            return String(format: "Battle ends in %dh %dm", hours, minutes)
        }
        return nil
    }

    private var helperCooldowns: [HelperCooldownDisplay] {
        let rawHelpers = dataService.currentHelperCooldowns()
        let mapped = rawHelpers.compactMap { helper -> HelperCooldownDisplay? in
            switch helper.id {
            case 93000000:
                return HelperCooldownDisplay(id: helper.id, name: "Builder's Apprentice", iconName: "profile/apprentice_builder", level: helper.level, cooldownSeconds: helper.cooldownSeconds, expiresAt: helper.expiresAt)
            case 93000001:
                return HelperCooldownDisplay(id: helper.id, name: "Lab Assistant", iconName: "profile/lab_assistant", level: helper.level, cooldownSeconds: helper.cooldownSeconds, expiresAt: helper.expiresAt)
            case 93000002:
                return HelperCooldownDisplay(id: helper.id, name: "Alchemist", iconName: "profile/alchemist", level: helper.level, cooldownSeconds: helper.cooldownSeconds, expiresAt: helper.expiresAt)
            default:
                return nil
            }
        }
        return mapped.sorted { $0.id < $1.id }
    }

    private var helperCooldownSummaryRow: some View {
        let maxRemaining = helperCooldowns.map { $0.remainingSeconds() }.max() ?? 0
        let totalSeconds = 23 * 60 * 60
        let helpersReady = maxRemaining <= 0

        if maxRemaining > 0 && maxRemaining <= 3600 {
            return AnyView(TimelineView(.periodic(from: Date(), by: 1)) { context in
                let remaining = helperCooldowns.map { $0.remainingSeconds(referenceDate: context.date) }.max() ?? 0
                let clamped = max(min(remaining, totalSeconds), 0)
                let progress = max(0, min(1, 1 - (Double(clamped) / Double(totalSeconds))))
                let topText = helperCooldowns.max(by: { $0.remainingSeconds(referenceDate: context.date) < $1.remainingSeconds(referenceDate: context.date) })?.cooldownText(referenceDate: context.date) ?? (clamped <= 0 ? "Helper ready to work" : "0s")

                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        VStack {
                            Image("buildings_home/helper_hut")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 44, height: 44)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text("Helper Cooldown")
                                    .font(.headline)
                                    .lineLimit(1)
                                Spacer()
                                if clamped <= 0 {
                                    Button {
                                        dataService.startHelperCooldownsForCurrentProfile()
                                    } label: {
                                        Text("Refresh")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            Text(topText)
                                .font(.subheadline)
                                .foregroundColor(clamped > 0 ? .orange : .green)

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

                }
            })
        }

        let cooldownSeconds = helperCooldowns.map { $0.remainingSeconds() }.max() ?? 0
        let remaining = max(min(cooldownSeconds, totalSeconds), 0)
        let progress = max(0, min(1, 1 - (Double(remaining) / Double(totalSeconds))))
        let topText = helperCooldowns.max(by: { $0.remainingSeconds() < $1.remainingSeconds() })?.cooldownText() ?? (remaining <= 0 ? "Helper ready to work" : "0s")

        return AnyView(VStack(spacing: 8) {
            HStack(spacing: 12) {
                VStack {
                    Image("buildings_home/helper_hut")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Helper Cooldown")
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        if helpersReady {
                            Button {
                                dataService.startHelperCooldownsForCurrentProfile()
                            } label: {
                                Text("Refresh")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Text(topText)
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

        }
        .padding(.vertical, 4))
    }

    private func formatHelperCooldown(_ seconds: Int) -> String {
        if seconds <= 0 { return "Helper ready to work" }
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

    private var totalBuilderBaseBuilders: Int {
        if displayedBuilderHallLevel <= 0 { return 0 }
        return displayedBuilderHallLevel >= 6 ? 2 : 1
    }

    private var busyBuilderBaseBuilders: Int {
        builderBaseUpgrades.count
    }

    private var idleBuilderBaseBuilders: Int {
        max(totalBuilderBaseBuilders - busyBuilderBaseBuilders, 0)
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

    private func parseHiddenSections() -> Set<String> {
        let raw = hiddenHomeSections.split(separator: ",").map { String($0) }
        return Set(raw)
    }

    private func persistHiddenSections(_ hidden: Set<String>) {
        hiddenHomeSections = hidden.sorted().joined(separator: ",")
    }

    private struct HomeSectionOrderSheet: View {
        @Binding var order: [HomeSection]
        @Binding var hidden: Set<String>
        let showRestoreClassicToggle: Bool
        @Binding var restoreClassicLayout: Bool
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                List {
                    if showRestoreClassicToggle {
                        Section("Layout") {
                            Toggle("Restore Classic Layout", isOn: $restoreClassicLayout)
                            Text("When enabled, Home uses the original single-column layout on iPad.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Section("Visible Cards") {
                        ForEach(order, id: \.self) { section in
                            HStack {
                                Text(section.title)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { !hidden.contains(section.rawValue) },
                                    set: { isVisible in
                                        if isVisible {
                                            hidden.remove(section.rawValue)
                                        } else {
                                            hidden.insert(section.rawValue)
                                        }
                                    }
                                ))
                            }
                        }
                        .onMove { offsets, destination in
                            order.move(fromOffsets: offsets, toOffset: destination)
                        }
                    }
                    Section {
                        Button("Reset to Default") {
                            order = HomeSection.defaultOrder
                            hidden.removeAll()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .environment(\.editMode, .constant(.active))
                .navigationTitle("Edit Home Cards")
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

    private func formatBoostTimeRemaining(_ endTime: Date) -> String {
        let remaining = endTime.timeIntervalSinceNow
        guard remaining > 0 else { return "0s" }
        
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
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
    
    private var currentTagText: String {
        dataService.playerTag.isEmpty ? "No tag saved" : "#\(dataService.playerTag)"
    }

    private var displayedTownHallLevel: Int {
        return dataService.getTownHallLevel(from: .home)
    }

    private var displayedBuilderHallLevel: Int {
        return dataService.getTownHallLevel(from: .builder)
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

    private struct WallLevelProgress: Identifiable {
        var id: Int { level }
        let level: Int
        let currentCount: Int
        let maxCountForTH: Int
        let upgradesRemaining: Int
        let costPerLevel: Int
        let totalCostForLevel: Int
    }

    private var wallProgressData: [WallLevelProgress] {
        guard let profile = dataService.currentProfile else { return [] }
        
        let th = displayedTownHallLevel
        
        guard let export = dataService.decodeExport(from: profile.rawJSON) else { return [] }
        
        guard let thLimitsData = loadTownHallLimits(),
              let buildingCosts = loadBuildingCosts() else {
            return []
        }
        
        let maxWallCount = (thLimitsData[th]?["Wall"] as? NSNumber)?.intValue ?? 0
        if maxWallCount <= 0 { return [] }
        
        var wallsByLevel: [Int: Int] = [:]
        if let buildings = export.buildings {
            for building in buildings {
                guard building.data == 1000010, let level = building.lvl else { continue }
                let count = max(building.cnt ?? 1, 1)
                wallsByLevel[level, default: 0] += count
            }
        }
        
        if wallsByLevel.isEmpty { return [] }
        
        var progress: [WallLevelProgress] = []
        let maxWallLevel = wallMaxLevelForTH(th)
        
        for level in 1...maxWallLevel {
            let currentCount = wallsByLevel[level] ?? 0
            let nextLevel = level + 1
            let nextLevelThRequirement = buildingCosts[nextLevel]?.thRequirement ?? Int.max
            let canUpgradeAtCurrentTH = level < maxWallLevel && nextLevelThRequirement <= th
            let cost = canUpgradeAtCurrentTH ? (buildingCosts[nextLevel]?.cost ?? 0) : 0
            let upgradesRemaining = canUpgradeAtCurrentTH ? currentCount : 0
            let totalCostForLevel = cost * upgradesRemaining

            let wallProgress = WallLevelProgress(
                level: level,
                currentCount: currentCount,
                maxCountForTH: maxWallCount,
                upgradesRemaining: upgradesRemaining,
                costPerLevel: cost,
                totalCostForLevel: totalCostForLevel
            )
            progress.append(wallProgress)
        }
        
        return progress
    }

    private func wallMaxLevelForTH(_ th: Int) -> Int {
        if let buildingCosts = loadBuildingCosts() {
            let allowedLevels = buildingCosts
                .filter { $0.value.thRequirement <= th }
                .map { $0.key }
            if let maxAllowed = allowedLevels.max() {
                return maxAllowed
            }
        }

        if let wallCounts = loadWallCountsFromGameConstants(),
           let entry = wallCounts[th] {
            return entry.maxWallLevel
        }

        switch th {
        case 2...3: return 3
        case 4...5: return 6
        case 6: return 6
        case 7: return 7
        case 8: return 8
        case 9: return 10
        case 10: return 11
        case 11: return 12
        case 12...13: return 13
        case 14: return 15
        case 15: return 16
        case 16: return 17
        case 17: return 18
        default: return 19
        }
    }

    private func parsedJSONURL(forResource name: String) -> URL? {
        let bundle = Bundle.main
        let subdirectories: [String?] = [
            "json/parsed_json_files",
            "parsed_json_files",
            "upgrade_info/parsed_json_files",
            "json"
        ]

        for subdirectory in subdirectories {
            if let url = bundle.url(forResource: name, withExtension: "json", subdirectory: subdirectory) {
                return url
            }
        }
        return bundle.url(forResource: name, withExtension: "json")
    }

    private func loadTownHallLimits() -> [Int: [String: Any]]? {
        if let url = parsedJSONURL(forResource: "townhall_levels"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           !json.isEmpty {
            var result: [Int: [String: Any]] = [:]
            for entry in json {
                if let thLevel = entry["townHallLevel"] as? Int,
                   let counts = entry["counts"] as? [String: Any] {
                    result[thLevel] = counts
                }
            }
            if !result.isEmpty {
                return result
            }
        }

        guard let wallCounts = loadWallCountsFromGameConstants() else {
            return nil
        }
        var result: [Int: [String: Any]] = [:]
        for (thLevel, entry) in wallCounts {
            result[thLevel] = ["Wall": entry.totalWalls]
        }
        return result.isEmpty ? nil : result
    }

    private func loadWallCountsFromGameConstants() -> [Int: (maxWallLevel: Int, totalWalls: Int)]? {
        guard let url = parsedJSONURL(forResource: "game_constants") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let wallCounts = json["wall_counts_by_th"] as? [String: Any] else {
            return nil
        }

        var result: [Int: (maxWallLevel: Int, totalWalls: Int)] = [:]
        for (key, value) in wallCounts {
            guard let thLevel = Int(key),
                  let entry = value as? [String: Any] else { continue }
            let maxWallLevel = (entry["max_wall_level"] as? Int)
                ?? (entry["max_wall_level"] as? NSNumber)?.intValue
                ?? 0
            let totalWalls = (entry["total_walls"] as? Int)
                ?? (entry["total_walls"] as? NSNumber)?.intValue
                ?? 0
            guard maxWallLevel > 0, totalWalls > 0 else { continue }
            result[thLevel] = (maxWallLevel: maxWallLevel, totalWalls: totalWalls)
        }
        return result.isEmpty ? nil : result
    }

    private func loadBuildingCosts() -> [Int: (cost: Int, thRequirement: Int)]? {
        guard let url = parsedJSONURL(forResource: "buildings") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        
        var result: [Int: (cost: Int, thRequirement: Int)] = [:]
        for building in json {
            if let id = building["id"] as? Int, id == 1000010,
               let levels = building["levels"] as? [[String: Any]] {
                for levelInfo in levels {
                    if let level = levelInfo["level"] as? Int,
                       let cost = levelInfo["buildCost"] as? Int,
                       let thReq = levelInfo["townHallLevel"] as? Int {
                        result[level] = (cost: cost, thRequirement: thReq)
                    }
                }
            }
        }
        return result
    }

    private var wallProgressSummary: some View {
        let th = displayedTownHallLevel
        let maxWallLevel = wallMaxLevelForTH(th)
        let allWallData = wallProgressData
        let wallData = allWallData
            .filter { $0.level < maxWallLevel }
            .sorted { $0.level < $1.level }
        let wallDataByLevel = Dictionary(uniqueKeysWithValues: wallData.map { ($0.level, $0) })
        let totalWalls = wallData.reduce(0) { $0 + $1.currentCount }
        let maxWallCountForTH = allWallData.first?.maxCountForTH ?? totalWalls
        let currentAtMaxWallLevel = allWallData.first(where: { $0.level == maxWallLevel })?.currentCount ?? 0
        let highestLevelUnlockedWallCap = dataService.highestWallLevelUnlockedCount(
            for: maxWallLevel,
            totalWallCount: maxWallCountForTH
        )
        let topTierRemaining = max(highestLevelUnlockedWallCap - currentAtMaxWallLevel, 0)

        var cumulativeCount = 0
        var cumulativeRows: [(level: Int, currentCount: Int, remaining: Int, costPerWall: Int, totalCost: Int)] = []

        if totalWalls > 0 {
            let minLevelWithWalls = wallDataByLevel
                .filter { $0.value.currentCount > 0 }
                .map { $0.key }
                .min() ?? 1

            for level in minLevelWithWalls..<maxWallLevel {
                let currentCount = wallDataByLevel[level]?.currentCount ?? 0
                let costPerWall = wallDataByLevel[level]?.costPerLevel ?? 0
                cumulativeCount += currentCount

                let remainingForLevel: Int
                if level == maxWallLevel - 1 {
                    remainingForLevel = max(highestLevelUnlockedWallCap - currentAtMaxWallLevel, 0)
                } else {
                    remainingForLevel = cumulativeCount
                }

                let levelTotalCost = remainingForLevel * costPerWall
                cumulativeRows.append((
                    level: level,
                    currentCount: currentCount,
                    remaining: remainingForLevel,
                    costPerWall: costPerWall,
                    totalCost: levelTotalCost
                ))
            }

            if topTierRemaining > 0 && !cumulativeRows.contains(where: { $0.level == maxWallLevel - 1 }) {
                let topTierCurrentCount = allWallData.first(where: { $0.level == maxWallLevel - 1 })?.currentCount ?? 0
                let topTierCostPerWall = wallDataByLevel[maxWallLevel - 1]?.costPerLevel ?? 0
                cumulativeRows.append((
                    level: maxWallLevel - 1,
                    currentCount: topTierCurrentCount,
                    remaining: topTierRemaining,
                    costPerWall: topTierCostPerWall,
                    totalCost: topTierRemaining * topTierCostPerWall
                ))
                cumulativeRows.sort { $0.level < $1.level }
            }
        }

        let totalCost = cumulativeRows.reduce(0) { $0 + $1.totalCost }
        let goldPassBoost = dataService.currentProfile?.goldPassBoost ?? 0
        let boostedTotalCost = applyGoldPassDiscount(to: totalCost, boostPercentage: goldPassBoost)
        
        return VStack(alignment: .leading, spacing: 12) {
            if cumulativeRows.isEmpty {
                Text("All walls maxed out!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(cumulativeRows, id: \.level) { wallLevel in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            HStack(spacing: 8) {
                                Image("resources/wall_\(wallLevel.level)")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Wall Level \(wallLevel.level)")
                                        .font(.headline)
                                    if wallLevel.level == maxWallLevel - 1 {
                                        Text("\(currentAtMaxWallLevel)/\(highestLevelUnlockedWallCap) max • \(wallLevel.remaining) remaining")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("\(wallLevel.currentCount) walls • \(wallLevel.remaining) remaining")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            let boostedLevelCost = applyGoldPassDiscount(to: wallLevel.totalCost, boostPercentage: goldPassBoost)
                            let boostedPerWallCost = applyGoldPassDiscount(to: wallLevel.costPerWall, boostPercentage: goldPassBoost)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(formatCost(boostedLevelCost))
                                    .font(.headline)
                                    .foregroundColor(.accentColor)
                                Text("\(boostedPerWallCost.formattedCompact())/wall")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Divider()
                
                HStack {
                    Text("Total Cost to Max All Walls")
                        .font(.headline)
                    Spacer()
                    Text(formatCost(boostedTotalCost))
                        .font(.headline)
                        .foregroundColor(.accentColor)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func formatCost(_ cost: Int) -> String {
        let value = Double(cost)
        
        if value >= 1_000_000_000 {
            let billions = value / 1_000_000_000
            if billions >= 100 {
                return String(format: "%.0fB", billions)
            } else if billions >= 10 {
                return String(format: "%.1fB", billions)
            } else {
                return String(format: "%.2fB", billions)
            }
        } else if value >= 1_000_000 {
            let millions = value / 1_000_000
            if millions >= 100 {
                return String(format: "%.0fM", millions)
            } else if millions >= 10 {
                return String(format: "%.1fM", millions)
            } else {
                return String(format: "%.2fM", millions)
            }
        } else if value >= 1_000 {
            return String(format: "%.0fK", value / 1_000)
        } else {
            return "\(Int(value))"
        }
    }

    private func applyGoldPassDiscount(to cost: Int, boostPercentage: Int) -> Int {
        let discountFactor = Double(100 - max(0, min(100, boostPercentage))) / 100.0
        let eventFactor = remoteContent.wallFactor(townHall: dataService.getTownHallLevel(from: .home))
        return Int(Double(cost) * discountFactor * eventFactor)
    }

    private func pasteAndImport() {
        #if canImport(UIKit)
        guard let input = clipboardTextFromPasteboard(),
              !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            importStatus = "Clipboard was empty. Copy your village export first."
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                importStatus = nil
            }
            return
        }
        switch dataService.importClipboardToMatchingProfile(input: input) {
        case .success(_, let upgradesCount, let switched):
            importStatus = switched
            ? "Imported \(upgradesCount) upgrades and switched profiles"
            : "Imported \(upgradesCount) upgrades"
            
            if !hasShownFirstImportTip {
                hasShownFirstImportTip = true
                showFirstImportTip = true
            }
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
    
    private func parseImportStatus(_ status: String) -> (String, Color) {
        if status.contains("not found") {
            return (status, Color(.systemRed))
        } else if status.contains("Could not parse") {
            return (status, Color(.systemRed))
        } else if status.contains("Clipboard was empty") {
            return (status, Color(.systemRed))
        } else {
            return (status, Color(.systemGreen))
        }
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

    private func presentLatestNewsIfEligible() {
        guard didRunStartupSheets, remoteContent.launchRefreshResolved,
              !startupPopupSuppressed, !didPresentNewsThisLaunch,
              !showInfoSheet, !showHomeOrderSheet, !showBoostSheet, !showFirstImportTip,
              let latest = remoteContent.unreadPopup else { return }
        didPresentNewsThisLaunch = true
        presentedNews = latest
    }

    private var shouldShowWhatsNew: Bool {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard !version.isEmpty else { return false }
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return version != lastSeenAppVersion || build != lastSeenBuildNumber
    }

    private func markWhatsNewSeen() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        guard !version.isEmpty || !build.isEmpty else { return }
        lastSeenAppVersion = version
        lastSeenBuildNumber = build
    }
}

private struct DashboardModuleCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
