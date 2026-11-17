import SwiftUI
#if canImport(UIKit)
import UIKit
#if canImport(UIImageColors)
import UIImageColors
#endif
#endif

struct ProfileDetailView: View {
    @EnvironmentObject private var dataService: DataService
    @AppStorage("profileSettingsExpanded") private var profileSettingsExpanded = true
    @AppStorage("helperGemCostsExpanded") private var helperGemCostsExpanded = true
    @AppStorage("adsPreference") private var adsPreference: AdsPreference = .fullScreen
    @AppStorage("profileSectionOrder") private var profileSectionOrder = "profileSettings,helperGemCosts,heroShowcase,clanStats"
    @AppStorage("hiddenProfileSections") private var hiddenProfileSections = ""
    @State private var showProfileOrderSheet = false
    @State private var orderedProfileSections: [ProfileSection] = ProfileSection.defaultOrder
    @State private var hiddenSections: Set<String> = []
    #if canImport(UIImageColors)
    @State private var townHallPalette: UIImageColors?
    @State private var townHallPaletteLevel: Int = 0
    #endif
    @State private var heroExport: CoCExport?
    @State private var gradientConfigCache: [Int: [Int]]?
    @State private var cachedProfileGradientColors: [Color]?
    @State private var cachedGradientTownHallLevel: Int = 0
    private let labAssistantInternalName = "ResearchApprentice"
    private let builderApprenticeInternalName = "BuilderApprentice"
    private let alchemistInternalName = "Alchemist"
    
    private enum ProfileSection: String, CaseIterable, Identifiable {
        case profileSettings
        case helperGemCosts
        case heroShowcase
        case clanStats
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .profileSettings: return "Profile Settings"
            case .helperGemCosts: return "Helper Gem Costs"
            case .heroShowcase: return "Heroes"
            case .clanStats: return "Clan Stats"
            }
        }
        
        static let defaultOrder: [ProfileSection] = [.profileSettings, .helperGemCosts, .heroShowcase, .clanStats]
    }

    var body: some View {
        NavigationStack {
            mainContent
                .trackTabBarScrollDirection()
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Profile")
            .sheet(isPresented: $showProfileOrderSheet) {
                ProfileSectionOrderSheet(order: $orderedProfileSections, hidden: $hiddenSections)
                    .adaptivePanelPresentation()
            }
            .toolbar {
                toolbarContent
            }
            .onAppear {
                handleOnAppear()
            }
            .task(id: dataService.currentProfile?.rawJSON) {
                let rawJSON = dataService.currentProfile?.rawJSON ?? ""
                heroExport = nil
                await Task.yield()
                guard !Task.isCancelled else { return }
                heroExport = dataService.decodeExport(from: rawJSON)
            }
            .onChangeCompat(of: orderedProfileSections) { newValue in
                persistProfileSectionOrder(newValue)
            }
            .onChangeCompat(of: hiddenSections) { newValue in
                persistHiddenProfileSections(newValue)
                refreshVisibleSectionData(hidden: newValue)
            }
            .onChangeCompat(of: townHallLevel) { _ in
                clampBuilderCount()
                clampHelperLevels()
                refreshProfileGradientPaletteIfNeeded(force: true)
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
    
    @ViewBuilder
    private var mainContent: some View {
        ScrollView {
            if resolvedProfile == nil {
                noProfilePlaceholder
                    .padding(.top, 80)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity)
            } else {
                profileContentStack
            }
        }
    }
    
    @ViewBuilder
    private var profileContentStack: some View {
        VStack(spacing: 20) {
            profileSummaryCard
            
            if adsPreference == .banner {
                bannerAdCard
            }
            
            ForEach(orderedProfileSections, id: \.self) { section in
                profileSectionView(for: section)
            }
        }
        .padding(.horizontal)
        .padding(.top, 20)
    }
    
    @ViewBuilder
    private var bannerAdCard: some View {
        VStack {
            BannerAdPlaceholder()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
        .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 1)
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
        
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                orderedProfileSections = parseProfileSectionOrder()
                showProfileOrderSheet = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("Reorder Profile Cards")
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            ProfileSwitcherMenu()
        }
    }
    
    private func handleOnAppear() {
        orderedProfileSections = parseProfileSectionOrder()
        hiddenSections = parseHiddenProfileSections()
        loadGradientConfig(force: false)  // Load config early (cached)
        
        // Load profile data in background to reduce lag
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async {
                dataService.refreshCurrentProfile(force: false)
            }
        }
        
        refreshVisibleSectionData(hidden: hiddenSections)
        refreshProfileGradientPaletteIfNeeded(force: false)
        clampHelperLevels()
    }

    private func refreshVisibleSectionData(hidden: Set<String>) {
        guard !hidden.contains("clanStats") else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async {
                dataService.refreshCurrentClanStats(force: false)
            }
        }
    }

    private var resolvedProfile: PlayerProfile? {
        dataService.cachedProfile
    }
    
    @ViewBuilder
    private func profileSectionView(for section: ProfileSection) -> some View {
        if !hiddenSections.contains(section.rawValue) {
            switch section {
            case .profileSettings:
                profileSettingsCard
            case .helperGemCosts:
                helperGemCostsCard
            case .heroShowcase:
                heroShowcase
            case .clanStats:
                clanStatsSection
            }
        }
    }
    
    private func parseProfileSectionOrder() -> [ProfileSection] {
        let raw = profileSectionOrder.split(separator: ",").map { String($0) }
        let parsed = raw.compactMap { ProfileSection(rawValue: $0) }
        if parsed.isEmpty { return ProfileSection.defaultOrder }
        let missing = ProfileSection.defaultOrder.filter { !parsed.contains($0) }
        return parsed + missing
    }
    
    private func persistProfileSectionOrder(_ order: [ProfileSection]) {
        profileSectionOrder = order.map { $0.rawValue }.joined(separator: ",")
    }
    
    private func parseHiddenProfileSections() -> Set<String> {
        let raw = hiddenProfileSections.split(separator: ",").map { String($0) }
        return Set(raw)
    }
    
    private func persistHiddenProfileSections(_ hidden: Set<String>) {
        hiddenProfileSections = hidden.sorted().joined(separator: ",")
    }

    private struct ProfileSectionOrderSheet: View {
        @Binding var order: [ProfileSection]
        @Binding var hidden: Set<String>
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                List {
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
                            order = ProfileSection.defaultOrder
                            hidden.removeAll()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .environment(\.editMode, .constant(.active))
                .navigationTitle("Edit Profile Cards")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
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
        #if canImport(UIKit) && canImport(UIImageColors)
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
        #if canImport(UIKit) && canImport(UIImageColors)
        if cachedGradientTownHallLevel == townHallLevel,
           let cached = cachedProfileGradientColors,
           cached.count >= 2 {
            return LinearGradient(
                colors: [cached[0], cached[1]],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        #endif
        return LinearGradient(colors: [.purple.opacity(0.8), .blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func refreshProfileGradientPaletteIfNeeded(force: Bool) {
        #if canImport(UIKit) && canImport(UIImageColors)
        let level = townHallLevel
        guard level > 0 else {
            cachedGradientTownHallLevel = 0
            cachedProfileGradientColors = nil
            return
        }

        if !force,
           cachedGradientTownHallLevel == level,
           cachedProfileGradientColors?.count == 2 {
            return
        }

        guard let image = townHallImage(for: level) else {
            cachedGradientTownHallLevel = 0
            cachedProfileGradientColors = nil
            return
        }

        let (colorIndex1, colorIndex2) = getGradientColorIndices(for: level)
        DispatchQueue.global(qos: .userInitiated).async {
            guard let palette = image.getColors(quality: .high) else { return }
            let colors: [UIColor] = [palette.primary, palette.secondary, palette.detail, palette.background]
                .compactMap { $0 }
            guard colorIndex1 < colors.count, colorIndex2 < colors.count else { return }
            let resolved: [Color] = [Color(colors[colorIndex1]), Color(colors[colorIndex2])]

            DispatchQueue.main.async {
                if townHallLevel == level {
                    cachedGradientTownHallLevel = level
                    cachedProfileGradientColors = resolved
                }
            }
        }
        #endif
    }
    
    private func getGradientColorIndices(for townHallLevel: Int) -> (Int, Int) {
        // Load config from file if not cached or if cache is empty
        if gradientConfigCache == nil || gradientConfigCache?.isEmpty == true {
            loadGradientConfig(force: true)
        }
        
        // Try to get configured indices for this level
        if let config = gradientConfigCache,
           let indices = config[townHallLevel], indices.count >= 2 {
            return (indices[0], indices[1])
        }

        // Default: colors 2 (detail) and 3 (background)
        return (2, 3)
    }
    
    private func loadGradientConfig(force: Bool = false) {
        if !force, gradientConfigCache != nil { return }

        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: "gradient_config", withExtension: "json", subdirectory: "json"),
            Bundle.main.url(forResource: "gradient_config", withExtension: "json"),
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("gradient_config.json")
        ]

        for path in candidateURLs {
            guard let url = path,
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let config = parseGradientConfig(from: json) else {
                continue
            }
            gradientConfigCache = config
            return
        }

        gradientConfigCache = nil
    }

    private func parseGradientConfig(from json: [String: Any]) -> [Int: [Int]]? {
        var config: [Int: [Int]] = [:]
        for (key, value) in json {
            guard let thLevel = Int(key) else { continue }
            if let array = value as? [Int], array.count >= 2 {
                config[thLevel] = [array[0], array[1]]
            } else if let array = value as? [NSNumber], array.count >= 2 {
                config[thLevel] = [array[0].intValue, array[1].intValue]
            }
        }
        return config.isEmpty ? nil : config
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
        #if canImport(UIKit)
        let level = townHallLevel
        guard level > 0 else {
            townHallPalette = nil
            townHallPaletteLevel = 0
            return
        }
        if townHallPaletteLevel == level, townHallPalette != nil { return }
        townHallPaletteLevel = level
        let image = townHallImage(for: level)
        
        guard let image = image else {
            print("[DEBUG TH Palette] Failed to load town hall image for level \(level)")
            townHallPalette = nil
            return
        }
        
        print("[DEBUG TH Palette] Image loaded, size: \(image.size), scale: \(image.scale)")
        let capturedLevel = level
        DispatchQueue.global(qos: .userInitiated).async {
            let palette = image.getColors()
            print("[DEBUG TH Palette] Got colors for level \(capturedLevel): \(palette != nil ? "YES" : "NO")")
            DispatchQueue.main.async {
                if self.townHallPaletteLevel == capturedLevel {
                    self.townHallPalette = palette
                }
            }
        }
        #endif
    }

    private func leagueAssetName(for league: String) -> String? {
        let trimmed = league.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let firstWord = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        let normalized = firstWord.lowercased()
        // All Legend tiers share the bundled Legend League icon.
        if normalized == "legend" {
            return "leagues/legend_league"
        }
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
                    LevelSliderRow(title: "Lab Assistant", value: $dataService.labAssistantLevel, maxLevel: labAssistantMaxLevel, iconName: "profile/lab_assistant")
                }

                if builderApprenticeMaxLevel > 0 {
                    LevelSliderRow(title: "Builder's Apprentice", value: $dataService.builderApprenticeLevel, maxLevel: builderApprenticeMaxLevel, iconName: "profile/apprentice_builder")
                }

                if alchemistMaxLevel > 0 {
                    LevelSliderRow(title: "Alchemist", value: $dataService.alchemistLevel, maxLevel: alchemistMaxLevel, iconName: "profile/alchemist")
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

    private var helperGemCostsCard: some View {
        let helpers = loadHelperGemCosts()
        guard !helpers.isEmpty else { return AnyView(EmptyView()) }
        
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    helperGemCostsExpanded.toggle()
                } label: {
                    HStack {
                        Text("Helper Gem Costs")
                            .font(.headline)
                        Spacer()
                        Image(systemName: helperGemCostsExpanded ? "chevron.up" : "chevron.down")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if helperGemCostsExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(helpers, id: \.id) { helper in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(helper.iconName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 32, height: 32)
                                    Text(helper.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text("Lv \(helper.currentLevel)/\(helper.maxLevel)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                }

                                if helper.remainingLevels > 0 {
                                    Text("Remaining levels: \(helper.remainingLevels)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    VStack(spacing: 6) {
                                        ForEach(helper.remainingLevelCosts, id: \.level) { level in
                                            HStack {
                                                Text("Lvl \(level.level):")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Spacer()
                                                HStack(spacing: 4) {
                                                    Image("profile/gem")
                                                        .resizable()
                                                        .scaledToFit()
                                                        .frame(width: 12, height: 12)
                                                    Text("\(level.cost)")
                                                        .font(.caption)
                                                }
                                                Text("TH \(level.requiredTH)")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                    }

                                    HStack {
                                        Text("Total")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Spacer()
                                        HStack(spacing: 4) {
                                            Image("profile/gem")
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 14, height: 14)
                                            Text("\(helper.remainingTotalCost)")
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                } else {
                                    Text("Max level")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                        }

                        HStack {
                            Text("Total")
                                .font(.headline)
                                .fontWeight(.bold)
                            Spacer()
                            HStack(spacing: 4) {
                                Image("profile/gem")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16, height: 16)
                                Text("\(helpers.reduce(0) { $0 + $1.remainingTotalCost })")
                                    .font(.headline)
                                    .fontWeight(.bold)
                            }
                        }
                        .padding(.vertical, 8)
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
        )
    }

    // Only bundled definitions are cached; profile levels and costs remain reactive.
    private static let helperDefinitions: [HelperData] = {
        guard let jsonPath = Bundle.main.path(forResource: "villager_apprentices", ofType: "json", inDirectory: "json/parsed_json_files"),
              let jsonData = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)),
              let helpers = try? JSONDecoder().decode([HelperData].self, from: jsonData) else {
            return []
        }
        return helpers
    }()

    private func loadHelperGemCosts() -> [HelperGemCostInfo] {
        guard townHallLevel >= 9 else { return [] }

        let helpers = Self.helperDefinitions

        var result: [HelperGemCostInfo] = []
        
        // Map helpers to their profile levels and icons
        let helperMapping: [(internalName: String, displayName: String, category: String, iconName: String, currentLevelKeyPath: KeyPath<DataService, Int>)] = [
            ("BuilderApprentice", "Builder's Apprentice", "Archer Queen", "profile/apprentice_builder", \DataService.builderApprenticeLevel),
            ("ResearchApprentice", "Lab Assistant", "Lab", "profile/lab_assistant", \DataService.labAssistantLevel),
            ("Alchemist", "Alchemist", "Lab", "profile/alchemist", \DataService.alchemistLevel)
        ]

        for mapping in helperMapping {
            guard let helperData = helpers.first(where: { $0.internalName == mapping.internalName }) else { continue }
            
            // Get current helper level from dataService profile settings
            let currentLevel = dataService[keyPath: mapping.currentLevelKeyPath]
            let isUnlocked = currentLevel > 0
            
            let availableLevels = helperData.levels.filter { Int($0.RequiredTownHallLevel) ?? 0 <= townHallLevel }
            guard !availableLevels.isEmpty else { continue }
            
            let maxLevel = availableLevels.last?.level ?? 0
            let remainingLevels = max(0, maxLevel - currentLevel)
            
            // Only include levels after current level
            let remainingLevelCosts = availableLevels
                .filter { $0.level > currentLevel }
                .map { level -> HelperLevelInfo in
                    HelperLevelInfo(
                        level: level.level,
                        cost: Int(level.Cost) ?? 0,
                        requiredTH: Int(level.RequiredTownHallLevel) ?? 9
                    )
                }
            
            let remainingTotalCost = remainingLevelCosts.reduce(0) { $0 + $1.cost }
            
            result.append(HelperGemCostInfo(
                id: mapping.internalName,
                displayName: mapping.displayName,
                category: mapping.category,
                iconName: mapping.iconName,
                currentLevel: currentLevel,
                maxLevel: maxLevel,
                isUnlocked: isUnlocked,
                remainingLevels: remainingLevels,
                remainingLevelCosts: remainingLevelCosts,
                remainingTotalCost: remainingTotalCost
            ))
        }
        
        return result
    }

    private var heroShowcase: some View {
        // Get heroes from export (JSON import) first, fallback to API
        let heroesToDisplay = getHeroesForDisplay()
        
        guard !heroesToDisplay.isEmpty else {
            return AnyView(EmptyView())
        }
        
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                Text("Hero Levels")
                    .font(.headline)
                ForEach(heroesToDisplay, id: \.name) { hero in
                    let actualMaxLevel = hero.maxLevel
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
                            Text("Level \(hero.level) / \(actualMaxLevel)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        ProgressView(value: Double(min(hero.level, actualMaxLevel)), total: Double(max(1, actualMaxLevel)))
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
        ProgressCatalog.heroItems.first { $0.name.caseInsensitiveCompare(heroName) == .orderedSame }?
            .assetName(for: 1)
    }

    private func getHeroesForDisplay() -> [HeroProfile] {
        ProgressCatalog.heroes(in: heroExport, fallback: resolvedProfile?.heroes ?? [], townHall: townHallLevel)
    }

    private var clanStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let clanStats = dataService.currentClanStats {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(clanStats.name)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text(clanStats.tag)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    ClanBadgeView(urlString: clanStats.badgeUrls.small, size: 48)
                }

                HStack {
                    infoPill(title: "Members", value: "\(clanStats.members ?? 0)")
                    infoPill(title: "Level", value: "\(clanStats.clanLevel)")
                    infoPill(title: "War League", value: clanStats.warLeague?.name ?? "–")
                }
                HStack {
                    infoPill(title: "War Wins", value: "\(clanStats.warWins ?? 0)")
                    infoPill(title: "Streak", value: "\(clanStats.warWinStreak ?? 0)")
                    infoPill(title: "Capital Hall", value: "\(clanStats.clanCapital?.capitalHallLevel ?? 0)")
                }
            } else if let message = dataService.clanStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Clan stats unavailable")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }


    private var activeProfileName: String {
        dataService.profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (dataService.currentProfile.map { dataService.displayName(for: $0) } ?? "Profile") : dataService.profileName
    }

    private var townHallLevel: Int {
        resolvedProfile?.townHallLevel ?? heroExport.map { dataService.inferTownHallLevel(from: $0) } ?? 0
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

        if labMax > 0 && dataService.labAssistantLevel > labMax {
            dataService.labAssistantLevel = labMax
        }

        if builderMax > 0 && dataService.builderApprenticeLevel > builderMax {
            dataService.builderApprenticeLevel = builderMax
        }

        if alchemistMax > 0 && dataService.alchemistLevel > alchemistMax {
            dataService.alchemistLevel = alchemistMax
        }
    }

    private func sliderRow(title: String, value: Binding<Int>, maxLevel: Int, iconName: String? = nil) -> some View {
        LevelSliderRow(title: title, value: value, maxLevel: maxLevel, iconName: iconName)
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
