import SwiftUI
import Combine
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

private class BoostManager: ObservableObject {
    @Published var activeBoosts: [ActiveBoost] = []
    @Published var instantUndoActions: [InstantBoostUndoAction] = []
    
    private weak var dataService: DataService?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    init(dataService: DataService) {
        self.dataService = dataService
        loadActiveBoosts()
        startTimer()
        
        dataService.$selectedProfileID
            .sink { [weak self] _ in
                self?.loadActiveBoosts()
            }
            .store(in: &cancellables)
    }
    
    deinit {
        timer?.invalidate()
    }
    
    func activateBoost(_ type: BoostType, targetUpgradeId: UUID? = nil, helperLevel: Int? = nil, durationOverride: TimeInterval? = nil) {
        guard let dataService = dataService else { return }
        let now = Date()
        let startTime = now
        let clockLevel = dataService.clockTowerLevel
        let duration = max(1, durationOverride ?? type.durationSeconds(clockTowerLevel: clockLevel))
        let endTime = now.addingTimeInterval(duration)
        var newBoost = ActiveBoost(type: type.rawValue, startTime: startTime, endTime: endTime)
        newBoost.targetUpgradeId = targetUpgradeId
        newBoost.helperLevel = helperLevel
        
        if type.isClockTowerBoost {
            if let existingIndex = activeBoosts.firstIndex(where: { $0.boostType?.isClockTowerBoost == true }) {
                let remaining = max(0, activeBoosts[existingIndex].endTime.timeIntervalSince(now))
                newBoost.endTime = now.addingTimeInterval(remaining + duration)
                activeBoosts.remove(at: existingIndex)
            }
            activeBoosts.append(newBoost)
        }
        else if type.requiresTargetSelection {
            if let targetUpgradeId,
               let existingIndex = activeBoosts.firstIndex(where: { $0.type == type.rawValue && $0.targetUpgradeId == targetUpgradeId }) {
                let currentEndTime = activeBoosts[existingIndex].endTime
                let newEndTime = max(currentEndTime, now).addingTimeInterval(duration)
                activeBoosts[existingIndex].endTime = newEndTime
                activeBoosts[existingIndex].helperLevel = helperLevel
            } else {
                activeBoosts.append(newBoost)
            }
        }
        else {
            if let existingIndex = activeBoosts.firstIndex(where: { $0.type == type.rawValue }) {
                let currentEndTime = activeBoosts[existingIndex].endTime
                let newStartTime = activeBoosts[existingIndex].startTime
                let newEndTime = max(currentEndTime, now).addingTimeInterval(duration)
                activeBoosts[existingIndex].startTime = newStartTime
                activeBoosts[existingIndex].endTime = newEndTime
                activeBoosts[existingIndex].helperLevel = helperLevel
            } else {
                activeBoosts.append(newBoost)
            }
        }
        
        saveActiveBoosts()
    }

    func applyBoostInstantly(_ type: BoostType, targetUpgradeId: UUID? = nil, helperLevel: Int? = nil, durationOverride: TimeInterval? = nil) {
        guard let dataService = dataService else { return }

        let now = Date()
        let duration = max(1, durationOverride ?? type.durationSeconds(clockTowerLevel: dataService.clockTowerLevel))
        let resolvedHelperLevel = resolvedLevel(for: type, explicitLevel: helperLevel, dataService: dataService)
        let savedSeconds = duration * type.speedMultiplier(level: resolvedHelperLevel)
        guard savedSeconds > 0 else { return }

        var updatedUpgrades = dataService.activeUpgrades
        var didChange = false
        var previousEndTimes: [UUID: Date] = [:]

        for index in updatedUpgrades.indices {
            let upgrade = updatedUpgrades[index]
            guard type.affectedCategories.contains(upgrade.category) else { continue }

            if type == .builderApprentice || type == .labAssistant {
                guard let targetUpgradeId, upgrade.id == targetUpgradeId else { continue }
            }

            let remaining = max(0, upgrade.endTime.timeIntervalSince(now))
            guard remaining > 0 else { continue }

            let reduction = min(savedSeconds, remaining)
            if reduction > 0 {
                previousEndTimes[upgrade.id] = upgrade.endTime
                updatedUpgrades[index].endTime = upgrade.endTime.addingTimeInterval(-reduction)
                didChange = true
            }
        }

        guard didChange else { return }
        dataService.activeUpgrades = updatedUpgrades
        dataService.pruneCompletedUpgrades(referenceDate: now)

        let currentUpgradeIDs = Set(dataService.activeUpgrades.map { $0.id })
        let removedUpgrades = updatedUpgrades.filter { !currentUpgradeIDs.contains($0.id) }
        let endTimeSnapshots = previousEndTimes.map {
            InstantBoostEndTimeSnapshot(upgradeID: $0.key, previousEndTime: $0.value)
        }

        let undoAction = InstantBoostUndoAction(
            id: UUID(),
            type: type.rawValue,
            appliedAt: now,
            expiresAt: now.addingTimeInterval(5 * 60),
            endTimeSnapshots: endTimeSnapshots,
            removedUpgrades: removedUpgrades
        )
        instantUndoActions.append(undoAction)
        trimExpiredUndoActions(referenceDate: now)
        saveBoostState(reloadWidgets: true, scheduleNotifications: false)
    }

    func undoInstantBoost(_ action: InstantBoostUndoAction) {
        guard let dataService = dataService else { return }

        let now = Date()
        guard action.expiresAt > now else {
            instantUndoActions.removeAll { $0.id == action.id }
            saveBoostState(reloadWidgets: false, scheduleNotifications: false)
            return
        }

        var upgrades = dataService.activeUpgrades
        var upgradeIDs = Set(upgrades.map { $0.id })
        var didRestore = false

        for removed in action.removedUpgrades {
            if !upgradeIDs.contains(removed.id) {
                upgrades.append(removed)
                upgradeIDs.insert(removed.id)
                didRestore = true
            }
        }

        for snapshot in action.endTimeSnapshots {
            guard let index = upgrades.firstIndex(where: { $0.id == snapshot.upgradeID }) else { continue }
            if upgrades[index].endTime != snapshot.previousEndTime {
                upgrades[index].endTime = snapshot.previousEndTime
                didRestore = true
            }
        }

        if didRestore {
            dataService.activeUpgrades = upgrades
        }

        instantUndoActions.removeAll { $0.id == action.id }
        saveBoostState(reloadWidgets: true, scheduleNotifications: false)
    }

    func undoTimeRemainingText(for action: InstantBoostUndoAction, referenceDate: Date = Date()) -> String {
        let remaining = max(0, Int(action.expiresAt.timeIntervalSince(referenceDate)))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%dm %02ds", minutes, seconds)
    }

    private func resolvedLevel(for type: BoostType, explicitLevel: Int?, dataService: DataService) -> Int {
        if let explicitLevel {
            return explicitLevel
        }

        switch type {
        case .builderApprentice:
            return dataService.builderApprenticeLevel
        case .labAssistant:
            return dataService.labAssistantLevel
        default:
            return 0
        }
    }
    
    func cancelBoost(_ boost: ActiveBoost) {
        activeBoosts.removeAll { $0.id == boost.id }
        saveActiveBoosts()
    }
    
    func getBoostMultiplier(for category: UpgradeCategory) -> Double {
        var totalMultiplier = 1.0
        
        for boost in activeBoosts {
            guard let boostType = boost.boostType,
                  boost.endTime > Date(),
                  boostType.affectedCategories.contains(category) else {
                continue
            }
            let level = boost.helperLevel ?? 0
            totalMultiplier += boostType.speedMultiplier(level: level)
        }
        
        return totalMultiplier
    }
    
    private func loadActiveBoosts() {
        guard let dataService = dataService,
              let profile = dataService.currentProfile else {
            activeBoosts = []
            instantUndoActions = []
            return
        }
        
        let now = Date()
        activeBoosts = profile.activeBoosts.filter { $0.endTime > now }
        instantUndoActions = profile.instantBoostUndoActions.filter { $0.expiresAt > now }
        
        let didPruneActiveBoosts = activeBoosts.count != profile.activeBoosts.count
        let didPruneUndoActions = instantUndoActions.count != profile.instantBoostUndoActions.count
        if didPruneActiveBoosts || didPruneUndoActions {
            saveBoostState(reloadWidgets: false, scheduleNotifications: false)
        }
    }
    
    private func saveActiveBoosts() {
        saveBoostState()
    }

    private func saveBoostState(reloadWidgets: Bool = true, scheduleNotifications: Bool = true) {
        guard let dataService = dataService else { return }
        
        dataService.updateCurrentProfile { profile in
            profile.activeBoosts = self.activeBoosts
            profile.instantBoostUndoActions = self.instantUndoActions
        }
        dataService.persistChanges(reloadWidgets: reloadWidgets)
        if scheduleNotifications {
            dataService.scheduleUpgradeNotifications()
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkExpiredBoosts()
            self?.trimExpiredUndoActions(referenceDate: Date())
            self?.objectWillChange.send()
        }
    }
    
    private func checkExpiredBoosts() {
        let now = Date()
        let originalCount = activeBoosts.count
        activeBoosts.removeAll { $0.endTime <= now }
        
        if activeBoosts.count != originalCount {
            saveActiveBoosts()
        }
    }

    private func trimExpiredUndoActions(referenceDate: Date) {
        let originalCount = instantUndoActions.count
        instantUndoActions.removeAll { $0.expiresAt <= referenceDate }
        if instantUndoActions.count != originalCount {
            saveBoostState(reloadWidgets: false, scheduleNotifications: false)
        }
    }
}

fileprivate struct BoostActivationRequest {
    enum Mode {
        case timed
        case instant
    }

    let type: BoostType
    let mode: Mode
    let durationOverride: TimeInterval?
}

struct BoostView: View {
    @EnvironmentObject private var dataService: DataService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var boostManager: BoostManager
    @State private var showingBuilderSelection = false
    @State private var selectedBoostRequest: BoostActivationRequest?
    @State private var showingCustomDurationSheet = false
    @State private var customDurationBoostType: BoostType?
    @State private var customDurationHours: Int = 0
    @State private var customDurationMinutes: Int = 30
    
    init(dataService: DataService) {
        _boostManager = StateObject(wrappedValue: BoostManager(dataService: dataService))
    }
    
    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !boostManager.activeBoosts.isEmpty || !boostManager.instantUndoActions.isEmpty {
                        activeBoostsSection
                    }
                    
                    boostsGrid
                }
                .transaction { $0.animation = nil }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Boosts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingBuilderSelection) {
                if let activationRequest = selectedBoostRequest {
                    BuilderSelectionView(activationRequest: activationRequest, boostManager: boostManager, dataService: dataService)
                        .adaptivePanelPresentation()
                }
            }
            .sheet(isPresented: $showingCustomDurationSheet) {
                if let boostType = customDurationBoostType {
                    BoostCustomDurationSheet(
                        boostType: boostType,
                        initialHours: customDurationHours,
                        initialMinutes: customDurationMinutes,
                        onApply: { duration in
                            handleBoostActivation(
                                BoostActivationRequest(type: boostType, mode: .timed, durationOverride: duration)
                            )
                        }
                    )
                    .adaptivePanelPresentation()
                }
            }
        }
    }
    
    private var activeBoostsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Boosts")
                .font(.headline)
                .padding(.horizontal, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(boostManager.activeBoosts) { boost in
                    if let boostType = boost.boostType {
                        HStack {
                            if let uiImage = UIImage(named: boostType.assetPath),
                               boostType == .builderApprentice || boostType == .labAssistant {
                                let trimmedImage = trimTransparentEdges(from: uiImage)
                                Image(uiImage: trimmedImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                            } else {
                                Image(boostType.assetPath)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(boostType.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    if let upgradeId = boost.targetUpgradeId,
                                       let upgrade = dataService.currentProfile?.activeUpgrades.first(where: { $0.id == upgradeId }) {
                                        Text("(\(upgrade.name))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    if let level = boost.helperLevel {
                                        Text("Lv\(level)")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                
                                Text("Ends in \(timeRemaining(for: boost))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(role: .destructive) {
                                boostManager.cancelBoost(boost)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.title3)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    }
                }

                if !boostManager.instantUndoActions.isEmpty {
                    if !boostManager.activeBoosts.isEmpty {
                        Divider()
                            .padding(.vertical, 4)
                    }

                    ForEach(boostManager.instantUndoActions) { action in
                        if let boostType = action.boostType {
                            HStack {
                                if let uiImage = UIImage(named: boostType.assetPath),
                                   boostType == .builderApprentice || boostType == .labAssistant {
                                    let trimmedImage = trimTransparentEdges(from: uiImage)
                                    Image(uiImage: trimmedImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 32, height: 32)
                                } else {
                                    Image(boostType.assetPath)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 32, height: 32)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(boostType.displayName) applied instantly")
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    Text("Applied \(action.appliedAt, style: .relative) ago")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button("Undo") {
                                    boostManager.undoInstantBoost(action)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
            )
        }
    }
    
    private var boostsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available Boosts")
                .font(.headline)
                .padding(.horizontal, 4)

            Text("Press and hold for more options")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(availableBoostTypes, id: \.self) { boostType in
                    boostCard(for: boostType)
                }
            }
        }
    }

    private var availableBoostTypes: [BoostType] {
        BoostType.allCases.filter(isBoostUnlocked)
    }

    private func isBoostUnlocked(_ boostType: BoostType) -> Bool {
        switch boostType {
        case .petPotion:
            return dataService.getTownHallLevel(from: .home) >= 14
        case .builderApprentice:
            let unlockTH = dataService.helperUnlockTownHall(internalName: "BuilderApprentice") ?? 10
            return dataService.getTownHallLevel(from: .home) >= unlockTH
        case .labAssistant:
            let unlockTH = dataService.helperUnlockTownHall(internalName: "ResearchApprentice") ?? 9
            return dataService.getTownHallLevel(from: .home) >= unlockTH
        default:
            return true
        }
    }
    
    @ViewBuilder
    private func boostCard(for boostType: BoostType) -> some View {
        Button {
            if !boostType.isPlaceholder {
                handleBoostActivation(BoostActivationRequest(type: boostType, mode: .timed, durationOverride: nil))
            }
        } label: {
            VStack(spacing: 12) {
                if let uiImage = UIImage(named: boostType.assetPath),
                   boostType == .builderApprentice || boostType == .labAssistant {
                    let trimmedImage = trimTransparentEdges(from: uiImage)
                    Image(uiImage: trimmedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                } else {
                    Image(boostType.assetPath)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                }
                
                Text(boostType.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                if boostType.isPlaceholder {
                    Text("Coming Soon")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    boostDescriptionText(for: boostType)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator), lineWidth: 1)
            )
            .opacity(boostType.isPlaceholder ? 0.6 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(boostType.isPlaceholder)
        .contextMenu {
            if !boostType.isPlaceholder {
                Button {
                    handleBoostActivation(BoostActivationRequest(type: boostType, mode: .instant, durationOverride: nil))
                } label: {
                    Label("Apply Full Boost Now", systemImage: "bolt.fill")
                }

                Button {
                    prepareCustomDuration(for: boostType)
                } label: {
                    Label("Set Custom Duration", systemImage: "timer")
                }
            }
        }
    }
    
    @ViewBuilder
    private func boostDescriptionText(for boostType: BoostType) -> some View {
        switch boostType {
        case .labAssistant:
            let level = dataService.labAssistantLevel
            let multiplier = level + 1
            Text("\(multiplier)x for 1hr (Lv\(level))")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .builderApprentice:
            let level = dataService.builderApprenticeLevel
            let multiplier = level + 1
            Text("\(multiplier)x for 1hr (Lv\(level))")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .clockTower:
            let level = max(1, dataService.clockTowerLevel)
            let minutes = Int(boostType.durationSeconds(clockTowerLevel: level) / 60)
            Text("10x for \(minutes)m (Lv\(level))")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .clockTowerPotion:
            Text("10x for 30m")
                .font(.caption2)
                .foregroundColor(.secondary)
        default:
            let multiplier = boostType.speedMultiplier(level: 0) + 1.0
            let duration = boostType.durationSeconds(clockTowerLevel: 0) / 60
            if duration >= 60 {
                Text("\(Int(multiplier))x for \(Int(duration/60))hr")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("\(Int(multiplier))x for \(Int(duration))m")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func handleBoostActivation(_ activationRequest: BoostActivationRequest) {
        let boostType = activationRequest.type
        switch boostType {
        case .labAssistant:
            let labUpgrades = dataService.currentProfile?.activeUpgrades.filter { $0.category == .lab } ?? []
            if labUpgrades.count == 1 {
                let targetUpgradeId = labUpgrades.first?.id
                applyActivationRequest(
                    activationRequest,
                    targetUpgradeId: targetUpgradeId,
                    helperLevel: dataService.labAssistantLevel
                )
            } else if labUpgrades.count >= 2 {
                selectedBoostRequest = activationRequest
                showingBuilderSelection = true
            } else {
                applyActivationRequest(activationRequest, helperLevel: dataService.labAssistantLevel)
            }
        case .builderApprentice:
            selectedBoostRequest = activationRequest
            showingBuilderSelection = true
        default:
            applyActivationRequest(activationRequest)
        }
    }

    private func applyActivationRequest(
        _ request: BoostActivationRequest,
        targetUpgradeId: UUID? = nil,
        helperLevel: Int? = nil
    ) {
        switch request.mode {
        case .timed:
            boostManager.activateBoost(
                request.type,
                targetUpgradeId: targetUpgradeId,
                helperLevel: helperLevel,
                durationOverride: request.durationOverride
            )
        case .instant:
            boostManager.applyBoostInstantly(
                request.type,
                targetUpgradeId: targetUpgradeId,
                helperLevel: helperLevel,
                durationOverride: request.durationOverride
            )
        }
    }

    private func prepareCustomDuration(for boostType: BoostType) {
        let defaultDuration = Int(boostType.durationSeconds(clockTowerLevel: dataService.clockTowerLevel))
        let totalMinutes = max(1, defaultDuration / 60)
        customDurationHours = min(23, totalMinutes / 60)
        customDurationMinutes = totalMinutes % 60
        if customDurationHours == 0 && customDurationMinutes == 0 {
            customDurationMinutes = 1
        }
        customDurationBoostType = boostType
        showingCustomDurationSheet = true
    }
    
    private func timeRemaining(for boost: ActiveBoost) -> String {
        let remaining = max(0, boost.endTime.timeIntervalSince(Date()))
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
}

private struct BuilderSelectionView: View {
    let activationRequest: BoostActivationRequest
    @ObservedObject var boostManager: BoostManager
    @ObservedObject var dataService: DataService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                if activationRequest.type == .builderApprentice {
                    builderSelectionSection
                } else if activationRequest.type == .labAssistant {
                    labSelectionSection
                }
            }
            .navigationTitle("Select Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private var builderSelectionSection: some View {
        Section {
            if let upgrades = dataService.currentProfile?.activeUpgrades.filter({ $0.category == .builderVillage }),
               !upgrades.isEmpty {
                ForEach(Array(upgrades.enumerated()), id: \.element.id) { index, upgrade in
                    Button {
                        let level = dataService.builderApprenticeLevel
                        switch activationRequest.mode {
                        case .timed:
                            boostManager.activateBoost(
                                activationRequest.type,
                                targetUpgradeId: upgrade.id,
                                helperLevel: level,
                                durationOverride: activationRequest.durationOverride
                            )
                        case .instant:
                            boostManager.applyBoostInstantly(
                                activationRequest.type,
                                targetUpgradeId: upgrade.id,
                                helperLevel: level,
                                durationOverride: activationRequest.durationOverride
                            )
                        }
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(upgrade.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text("Builder #\(index + 1)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
            } else {
                Text("No active builder upgrades")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Select Builder")
        } footer: {
            let level = dataService.builderApprenticeLevel
            let multiplier = level + 1
            Text("Builder's Apprentice (Level \(level)) provides a \(multiplier)x speed boost for 1 hour to one builder.")
        }
    }
    
    private var labSelectionSection: some View {
        Section {
            if let upgrades = dataService.currentProfile?.activeUpgrades.filter({ $0.category == .lab }),
               !upgrades.isEmpty {
                ForEach(upgrades) { upgrade in
                    Button {
                        let level = dataService.labAssistantLevel
                        switch activationRequest.mode {
                        case .timed:
                            boostManager.activateBoost(
                                activationRequest.type,
                                targetUpgradeId: upgrade.id,
                                helperLevel: level,
                                durationOverride: activationRequest.durationOverride
                            )
                        case .instant:
                            boostManager.applyBoostInstantly(
                                activationRequest.type,
                                targetUpgradeId: upgrade.id,
                                helperLevel: level,
                                durationOverride: activationRequest.durationOverride
                            )
                        }
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(upgrade.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text("Lab Upgrade")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
            } else {
                Text("No active lab upgrades")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Select Lab Upgrade")
        } footer: {
            let level = dataService.labAssistantLevel
            let multiplier = level + 1
            Text("Lab Assistant (Level \(level)) provides a \(multiplier)x speed boost for 1 hour to one lab upgrade.")
        }
    }
}

private struct BoostCustomDurationSheet: View {
    let boostType: BoostType
    let initialHours: Int
    let initialMinutes: Int
    let onApply: (TimeInterval) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hours: Int
    @State private var minutes: Int

    init(
        boostType: BoostType,
        initialHours: Int,
        initialMinutes: Int,
        onApply: @escaping (TimeInterval) -> Void
    ) {
        self.boostType = boostType
        self.initialHours = initialHours
        self.initialMinutes = initialMinutes
        self.onApply = onApply
        _hours = State(initialValue: initialHours)
        _minutes = State(initialValue: initialMinutes)
    }

    private var totalMinutes: Int {
        (hours * 60) + minutes
    }

    private var canApply: Bool {
        totalMinutes > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Picker("Hours", selection: $hours) {
                            ForEach(0...23, id: \.self) { value in
                                Text("\(value) h").tag(value)
                            }
                        }
                        .pickerStyle(.wheel)

                        Picker("Minutes", selection: $minutes) {
                            ForEach(0...59, id: \.self) { value in
                                Text("\(value) m").tag(value)
                            }
                        }
                        .pickerStyle(.wheel)
                    }
                    .frame(height: 140)
                } header: {
                    Text("Duration")
                } footer: {
                    Text("Choose how long to run \(boostType.displayName.lowercased()).")
                }

                Section {
                    Button("Apply Custom Duration") {
                        onApply(TimeInterval(totalMinutes * 60))
                        dismiss()
                    }
                    .disabled(!canApply)
                }
            }
            .navigationTitle("Custom Duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
