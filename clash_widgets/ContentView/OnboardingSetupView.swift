import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private struct ProfileSetupPane: View {
    @EnvironmentObject private var dataService: DataService
    @Binding var playerTag: String
    let title: String
    let subtitle: String
    let submitTitle: String
    let showCancel: Bool
    let onCancel: (() -> Void)?
    let onSubmit: (ProfileSetupSubmission) -> Void
    let seedFromExistingProfile: Bool
    let showOnboardingInstructions: Bool

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

    @State private var step: Int = 1

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if step == 1 {
                        if showOnboardingInstructions {
                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack(alignment: .center, spacing: 12) {
                                        Image(systemName: "doc.on.clipboard.fill")
                                            .foregroundColor(.white)
                                            .padding(8)
                                            .background(Circle().fill(Color.accentColor))
                                        Text("Getting Started")
                                            .font(.headline)
                                    }

                                    VStack(alignment: .leading, spacing: 14) {
                                        HStack(alignment: .top, spacing: 12) {
                                            Circle()
                                                .fill(Color.accentColor)
                                                .frame(width: 28, height: 28)
                                                .overlay(Text("1").font(.subheadline).foregroundColor(.white))
                                            Text("1. Open the Clash of Clans Settings (or use the \"Open Game Settings\" button)")
                                                .font(.body)
                                        }

                                        HStack(alignment: .top, spacing: 12) {
                                            Circle()
                                                .fill(Color.accentColor)
                                                .frame(width: 28, height: 28)
                                                .overlay(Text("2").font(.subheadline).foregroundColor(.white))
                                            Text("2. Within 'More Settings', scroll to the bottom and press the \"Copy\" button inside 'Data Export'")
                                                .font(.body)
                                        }

                                        HStack(alignment: .top, spacing: 12) {
                                            Circle()
                                                .fill(Color.accentColor)
                                                .frame(width: 28, height: 28)
                                                .overlay(Text("3").font(.subheadline).foregroundColor(.white))
                                            Text("3. Press the Paste & Import Village Data button below")
                                                .font(.body)
                                        }
                                    }

                                    Image("images/onboarding_help")
                                        .resizable()
                                        .scaledToFit()
                                        .cornerRadius(8)
                                        .frame(maxHeight: 300)
                                }
                                .padding(16)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(UIColor { trait in
                                    trait.userInterfaceStyle == .dark ? UIColor.secondarySystemBackground : UIColor.systemGray5
                                })))
                                .accessibilityIdentifier("onboarding.getting_started_card")
                                .foregroundColor(.primary)

#if canImport(UIKit)
                                Button {
                                    importVillageDataFromClipboard()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "plus")
                                        Text("Paste & Import Village Data")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .font(.headline)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.accentColor)
#endif

                                Button {
                                    if let url = URL(string: "clashofclans://action=OpenMoreSettings") {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "gearshape")
                                        Text("Open Game Settings")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                }
                                .buttonStyle(.bordered)

                                if let statusMessage {
                                    Text(statusMessage)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                if didImportJSON {
                                    VStack(spacing: 12) {
                                        HStack(spacing: 12) {
                                            if let thImage = townHallImage(for: previewTownHallLevel) {
                                                Image(uiImage: thImage)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 60, height: 60)
                                            } else {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color(.secondarySystemBackground))
                                                    .frame(width: 60, height: 60)
                                            }

                                            VStack(alignment: .leading, spacing: 4) {
                                                if let tag = importedTag, !tag.isEmpty {
                                                    Text(tag)
                                                        .font(.headline)
                                                        .lineLimit(1)
                                                } else {
                                                    Text("Player Tag")
                                                        .font(.headline)
                                                        .foregroundColor(.secondary)
                                                }
                                                Text("Town Hall \(previewTownHallLevel)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }

                                            Spacer()
                                        }
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                                    }
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                }
                            }
                        } else {
#if canImport(UIKit)
                            Button {
                                importVillageDataFromClipboard()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus")
                                    Text("Paste & Import Village Data")
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .font(.headline)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.accentColor)
#endif

                            Button {
                                if let url = URL(string: "clashofclans://action=OpenMoreSettings") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "gearshape")
                                    Text("Open Game Settings")
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                            }
                            .buttonStyle(.bordered)

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

                            if didImportJSON {
                                VStack(spacing: 12) {
                                    HStack(spacing: 12) {
                                        if let thImage = townHallImage(for: previewTownHallLevel) {
                                            Image(uiImage: thImage)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 60, height: 60)
                                        } else {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(.secondarySystemBackground))
                                                .frame(width: 60, height: 60)
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            if let tag = importedTag, !tag.isEmpty {
                                                Text(tag)
                                                    .font(.headline)
                                                    .lineLimit(1)
                                            } else {
                                                Text("Player Tag")
                                                    .font(.headline)
                                                    .foregroundColor(.secondary)
                                            }
                                            Text("Town Hall \(previewTownHallLevel)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()
                                    }
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }
                        }
                    } else {
                        settingsFields

                        VStack(alignment: .leading, spacing: 16) {
                            Section("Notifications") {
                                Toggle("Enable Notifications", isOn: notificationBindingLocal(\.notificationsEnabled))
                                    .tint(.accentColor)

                                if notificationSettings.notificationsEnabled {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Toggle("Builders", isOn: notificationBindingLocal(\.builderNotificationsEnabled))
                                            .tint(.accentColor)
                                        Toggle("Laboratory", isOn: notificationBindingLocal(\.labNotificationsEnabled))
                                            .tint(.accentColor)
                                        Toggle("Pet House", isOn: notificationBindingLocal(\.petNotificationsEnabled))
                                            .tint(.accentColor)
                                        Toggle("Builder Base", isOn: notificationBindingLocal(\.builderBaseNotificationsEnabled))
                                            .tint(.accentColor)
                                        Toggle("Helpers", isOn: notificationBindingLocal(\.helperNotificationsEnabled))
                                            .tint(.accentColor)
                                        Toggle("Clan War", isOn: notificationBindingLocal(\.clanWarNotificationsEnabled))
                                            .tint(.accentColor)
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
                .padding(EdgeInsets(top: showOnboardingInstructions ? 4 : 20, leading: 20, bottom: 20, trailing: 20))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(showOnboardingInstructions ? "" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step == 2 {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Back") { step = 1 }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if step == 1 {
                        step = 2
                    } else {
                        submitProfile()
                    }
                } label: {
                    Text(step == 1 ? "Next" : submitTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Color(.systemGroupedBackground))
                .disabled(step == 1 && !canContinue)
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

            if seedFromExistingProfile {
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
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    private func submitProfile() {
        clampBuilderCount()
        if let rawJSON = pendingImportRawJSON,
           let export = dataService.decodeExport(from: rawJSON) {
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
        }
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
            builderCount = dataService.builderCount
            builderApprenticeLevel = dataService.builderApprenticeLevel
            labAssistantLevel = dataService.labAssistantLevel
            alchemistLevel = dataService.alchemistLevel
            goldPassBoost = dataService.goldPassBoost
            notificationSettings = dataService.notificationSettings
        } else {
            builderCount = 5
            builderApprenticeLevel = 0
            labAssistantLevel = 0
            alchemistLevel = 0
            goldPassBoost = 0
            notificationSettings = NotificationSettings.default
        }
        clampBuilderCount()
        clampHelperLevels()
    }

    private func clampBuilderCount() {
        if builderCount > maxBuilders { builderCount = maxBuilders }
        if builderCount < 2 { builderCount = 2 }
    }

    private func clampHelperLevels() {
        if labAssistantMaxLevel > 0 && labAssistantLevel > labAssistantMaxLevel {
            labAssistantLevel = labAssistantMaxLevel
        }

        if builderApprenticeMaxLevel > 0 && builderApprenticeLevel > builderApprenticeMaxLevel {
            builderApprenticeLevel = builderApprenticeMaxLevel
        }

        if alchemistMaxLevel > 0 && alchemistLevel > alchemistMaxLevel {
            alchemistLevel = alchemistMaxLevel
        }
    }

    private func sliderRow(title: String, value: Binding<Int>, maxLevel: Int, unlockedAt: Int, iconName: String? = nil) -> some View {
        LevelSliderRow(title: title, value: value, maxLevel: maxLevel, iconName: iconName)
    }

    private func townHallImage(for level: Int) -> UIImage? {
        #if canImport(UIKit)
        guard level > 0 else { return nil }
        let candidates = [
            "town_hall/th\(level)",
            "town_hall/TownHall_\(level)",
            "town_hall/TownHall"
        ]
        for name in candidates {
            if let image = UIImage(named: name) {
                return image
            }
        }
        #endif
        return nil
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

        statusMessage = "Imported your player data successfully."
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

struct AddProfileSheet: View {
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
            subtitle: " ",
            submitTitle: "Continue",
            showCancel: true,
            onCancel: { dismiss() },
            onSubmit: { submission in saveProfile(submission) },
            seedFromExistingProfile: false,
            showOnboardingInstructions: false
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
        LevelSliderRow(title: title, value: value, maxLevel: maxLevel, iconName: iconName)
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

struct ProfileEditorSheet: View {
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

struct InitialSetupView: View {
    @Binding var playerTag: String
    let onComplete: (ProfileSetupSubmission) -> Void

    var body: some View {
        ProfileSetupPane(
            playerTag: $playerTag,
            title: "Set up Your Profile",
            subtitle: "Follow the steps to sync your village data.",
            submitTitle: "Continue",
            showCancel: false,
            onCancel: nil,
            onSubmit: onComplete,
            seedFromExistingProfile: false,
            showOnboardingInstructions: true
        )
    }
}

func normalizePlayerTag(_ rawTag: String) -> String {
    let uppercase = rawTag
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased()
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    let filteredScalars = uppercase.unicodeScalars.filter { allowed.contains($0) }
    var view = String.UnicodeScalarView()
    view.append(contentsOf: filteredScalars)
    return String(view)
}
