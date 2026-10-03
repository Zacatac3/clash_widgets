import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ProgressTabView: View {
    @EnvironmentObject private var dataService: DataService
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("progressSectionOrder") private var storedOrder = ""
    @AppStorage("hiddenProgressSections") private var storedHidden = ""
    @State private var showCraftedDefenses = false
    @State private var showSupercharges = false
    @State private var order: [String] = []
    @State private var hidden: Set<String> = []
    @State private var editingCards = false
    @State private var showingDisplayOptions = false
    @State private var showingExportPreview = false
    @State private var export: CoCExport?
    @State private var isLoadingExport = true
    @State private var decodedRawJSON: String?

    private var townHall: Int {
        if let level = dataService.cachedProfile?.townHallLevel, level > 0 { return level }
        return export.map { dataService.inferTownHallLevel(from: $0) } ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if isLoadingExport {
                            ProgressView("Loading progress…")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .progressCardStyle()
                        } else if export == nil {
                            Text("Import your village export to see progress.")
                                .font(.subheadline).foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .progressCardStyle()
                        } else {
                            ForEach(visibleSectionIDs, id: \.self) { id in
                                if let section = ProgressCatalog.sections.first(where: { $0.id == id }) {
                                    sectionCard(section).id(id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, export == nil ? 20 : 66)
                }
                .overlay(alignment: .topLeading) {
                    if export != nil {
                        categorySelector(proxy: proxy)
                    }
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Progress (Beta)")
                .toolbar {
                    if #available(iOS 26.0, *) {
                        progressToolbar
                    } else {
                        progressToolbarFallback
                    }
                }
            }
            .sheet(isPresented: $editingCards) {
                NavigationStack {
                    List {
                        Section("Cards") {
                            ForEach(editableSectionIDs, id: \.self) { id in
                                if let section = ProgressCatalog.sections.first(where: { $0.id == id }) {
                                    Toggle(section.title, isOn: Binding(
                                        get: { !hidden.contains(id) },
                                        set: { visible in
                                            if visible { hidden.remove(id) } else { hidden.insert(id) }
                                            storedHidden = hidden.sorted().joined(separator: ",")
                                        }
                                    ))
                                }
                            }
                            .onMove { offsets, destination in
                                var reordered = editableSectionIDs
                                reordered.move(fromOffsets: offsets, toOffset: destination)
                                var next = reordered.makeIterator()
                                order = order.map { editableSectionIDs.contains($0) ? (next.next() ?? $0) : $0 }
                                storedOrder = order.joined(separator: ",")
                            }
                        }
                        Section {
                            Button("Reset to Default") {
                                order = ProgressCatalog.sections.map(\.id)
                                hidden.removeAll()
                                storedOrder = order.joined(separator: ",")
                                storedHidden = ""
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .environment(\.editMode, .constant(.active))
                    .navigationTitle("Edit Progress Cards")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { editingCards = false } } }
                }
                .adaptivePanelPresentation()
            }
            .fullScreenCover(isPresented: $showingExportPreview) {
                if let export {
                    ProgressExportPreviewView(export: export, townHall: townHall,
                                           cachedEquipment: dataService.currentProfile?.cachedProfile?.heroEquipment ?? [],
                                           playerName: dataService.currentProfile.map { dataService.displayName(for: $0) } ?? "Player",
                                           playerTag: dataService.currentProfile?.cachedProfile?.tag
                                               ?? dataService.currentProfile?.tag ?? export.tag ?? "")
                }
            }
            .onAppear {
                let ids = ProgressCatalog.sections.map(\.id)
                let previousOrder = storedOrder.split(separator: ",").map(String.init)
                var saved: [String] = []
                for id in previousOrder {
                    let migratedID = id.hasPrefix("equipment_") ? "equipment" : id
                    if ids.contains(migratedID), !saved.contains(migratedID) { saved.append(migratedID) }
                }
                // Orders saved by the previous release include its old default positions.
                var previousDefault = ids
                if let equipmentIndex = previousDefault.firstIndex(of: "equipment"),
                   let heroesIndex = previousDefault.firstIndex(of: "heroes") {
                    previousDefault.remove(at: equipmentIndex)
                    previousDefault.insert("equipment", at: heroesIndex + 1)
                }
                if let superchargesIndex = previousDefault.firstIndex(of: "supercharges"),
                   let buildingsIndex = previousDefault.firstIndex(of: "buildings") {
                    previousDefault.remove(at: superchargesIndex)
                    previousDefault.insert("supercharges", at: buildingsIndex + 1)
                }
                if saved == previousDefault { saved = [] }
                var resolved = saved + ids.filter { !saved.contains($0) }
                if !saved.contains("supercharges"),
                   let currentIndex = resolved.firstIndex(of: "supercharges") {
                    resolved.remove(at: currentIndex)
                    let destination = resolved.firstIndex(of: "crafted_defenses") ?? resolved.endIndex
                    resolved.insert("supercharges", at: destination)
                }
                if !saved.contains("equipment"),
                   let equipmentIndex = resolved.firstIndex(of: "equipment"),
                   let guardiansIndex = resolved.firstIndex(of: "guardians") {
                    resolved.remove(at: equipmentIndex)
                    resolved.insert("equipment", at: guardiansIndex + 1)
                }
                order = resolved
                let previousHidden = Set(storedHidden.split(separator: ",").map(String.init))
                let equipmentHeroes = Set(EquipmentDataStore.shared.entries.map(\.hero))
                let previousEquipmentIDs = HeroConfigStore.shared.configs
                    .map(\.displayName)
                    .filter { equipmentHeroes.contains($0) }
                    .map { "equipment_\($0.slugifiedAssetName)" }
                hidden = previousHidden.filter { !$0.hasPrefix("equipment_") }
                if !previousEquipmentIDs.isEmpty && previousEquipmentIDs.allSatisfy(previousHidden.contains) {
                    hidden.insert("equipment")
                }
                let resolvedOrder = order.joined(separator: ",")
                let resolvedHidden = hidden.sorted().joined(separator: ",")
                if storedOrder != resolvedOrder { storedOrder = resolvedOrder }
                if storedHidden != resolvedHidden { storedHidden = resolvedHidden }
                loadDisplaySettings()
            }
            .task(id: dataService.currentProfile?.rawJSON) {
                let rawJSON = dataService.currentProfile?.rawJSON ?? ""
                if decodedRawJSON == rawJSON { return }
                guard !rawJSON.isEmpty else {
                    export = nil
                    isLoadingExport = false
                    decodedRawJSON = rawJSON
                    return
                }
                isLoadingExport = true
                export = nil
                await Task.yield()
                guard !Task.isCancelled else { return }
                export = dataService.decodeExport(from: rawJSON)
                decodedRawJSON = rawJSON
                isLoadingExport = false
            }
            .onChangeCompat(of: dataService.selectedProfileID) { _ in loadDisplaySettings() }
            .onChangeCompat(of: townHall) { _ in loadDisplaySettings() }
        }
    }

    private func updateDisplayOption(_ option: String, enabled: Bool) {
        if option == "supercharges" { showSupercharges = enabled }
        else { showCraftedDefenses = enabled }
        guard let id = dataService.selectedProfileID else { return }
        ProgressDisplaySettings.save(enabled, option: option, profileID: id)
    }

    private func categorySelector(proxy: ScrollViewProxy) -> some View {
        HStack {
            Menu {
                ForEach(visibleSectionIDs, id: \.self) { id in
                    if let section = ProgressCatalog.sections.first(where: { $0.id == id }) {
                        Button(section.title) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.12))
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "list.bullet")
                    Text("Category")
                    Image(systemName: "chevron.down").font(.caption2.bold())
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator).opacity(0.6)))
            }
        }
        .padding(.leading, 16)
        .padding(.top, 8)
    }

    private func loadDisplaySettings() {
        guard let id = dataService.selectedProfileID else { return }
        showSupercharges = ProgressDisplaySettings.value(for: "supercharges", profileID: id, townHall: townHall)
        showCraftedDefenses = ProgressDisplaySettings.value(for: "craftedDefenses", profileID: id, townHall: townHall)
    }

    private var displayOptionsButton: some View {
        Button { showingDisplayOptions = true } label: {
            Image(systemName: "eye")
                .environment(\.symbolVariants, .none)
        }
        .accessibilityLabel("Progress Display Options")
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
        .popover(isPresented: $showingDisplayOptions, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Display Options")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                displayOptionRow("Supercharges", option: "supercharges", isEnabled: showSupercharges)
                displayOptionRow("Crafted Defenses", option: "craftedDefenses", isEnabled: showCraftedDefenses)
            }
            .padding(12)
            .frame(width: 240)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func displayOptionRow(_ title: String, option: String, isEnabled: Bool) -> some View {
        Button {
            updateDisplayOption(option, enabled: !isEnabled)
        } label: {
            HStack {
                Text(title)
                Spacer()
                if isEnabled { Image(systemName: "checkmark") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isEnabled ? .isSelected : [])
    }

    private var reorderCardsButton: some View {
        Button { editingCards = true } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel("Reorder Progress Cards")
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
    }

    private var exportPreviewButton: some View {
        Button { showingExportPreview = true } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Share Progress")
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
        .disabled(export == nil)
    }

    @available(iOS 26.0, *)
    @ToolbarContentBuilder
    private var progressToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarLeading) {
            displayOptionsButton
            reorderCardsButton
        }
        ToolbarSpacer(.fixed, placement: .navigationBarLeading)
        ToolbarItem(placement: .navigationBarLeading) {
            exportPreviewButton
        }
        ToolbarSpacer(placement: .navigationBarLeading)
        ToolbarItem(placement: .navigationBarTrailing) {
            ProfileSwitcherMenu()
        }
    }

    @ToolbarContentBuilder
    private var progressToolbarFallback: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) { displayOptionsButton }
        ToolbarItem(placement: .navigationBarLeading) { reorderCardsButton }
        ToolbarItem(placement: .navigationBarLeading) { exportPreviewButton }
        ToolbarItem(placement: .navigationBarTrailing) { ProfileSwitcherMenu() }
    }

    private var editableSectionIDs: [String] {
        order.filter { id in
            (id != "crafted_defenses" || showCraftedDefenses)
                && (id != "supercharges" || showSupercharges)
        }
    }

    private var visibleSectionIDs: [String] {
        editableSectionIDs.filter { !hidden.contains($0) }
    }

    private func sectionCard(_ section: ProgressCatalog.Section) -> some View {
        if section.id == "supercharges" {
            return AnyView(superchargesCard)
        }
        if section.id == "equipment" {
            return AnyView(equipmentCard)
        }
        let inventory = export.map { section.inventory(in: $0) } ?? [:]
        return AnyView(VStack(alignment: .leading, spacing: 12) {
            Text(section.title).font(.headline)
            ForEach(section.groups, id: \.id) { group in
                if section.groups.count > 1 {
                    Text(group.title).font(.subheadline.bold())
                        .padding(.top, 4)
                }
                if section.id == "crafted_defenses" {
                    VStack(spacing: 0) {
                        ForEach(group.items) { item in
                            craftedDefenseRow(item)
                            if item.id != group.items.last?.id { Divider() }
                        }
                    }
                } else if section.isStructure {
                    VStack(spacing: 0) {
                        ForEach(group.items) { item in
                            let counts = inventory[item.id] ?? [:]
                            if section.id == "walls" && !counts.isEmpty {
                                ForEach(counts.keys.sorted(), id: \.self) { level in
                                    wallRow(item, level: level, count: counts[level] ?? 1)
                                }
                            } else {
                                structureRow(item, counts: counts)
                            }
                            if item.id != group.items.last?.id { Divider() }
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 8)], spacing: 12) {
                        ForEach(group.items) { item in
                            let counts = inventory[item.id] ?? [:]
                            tile(item, level: counts.keys.max() ?? 0, count: 1)
                        }
                    }
                }
            }
        }
        .progressCardStyle())
    }

    private func structureRow(_ item: ProgressCatalog.Item, counts: [Int: Int]) -> some View {
        let previewLevel = counts.keys.max() ?? 0
        return HStack(alignment: .top, spacing: 12) {
            ProgressStructureImage(name: item.assetName(for: previewLevel))
                .frame(width: 52, height: 52)
                .saturation(counts.isEmpty ? 0 : 1)
                .opacity(counts.isEmpty ? 0.35 : 1)
                .progressStructureIconStyle(colorScheme)
                .modifier(ProgressLevelPopover(item: item, townHall: townHall))
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(.subheadline.weight(.medium))
                if counts.isEmpty {
                    Text("None of this building to upgrade").font(.caption).foregroundColor(.secondary)
                } else {
                    ProgressBadgeFlow(spacing: 6) {
                        ForEach(counts.keys.sorted(), id: \.self) { level in
                            levelLine(level, count: counts[level] ?? 1, item: item)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private func wallRow(_ item: ProgressCatalog.Item, level: Int, count: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressStructureImage(name: item.assetName(for: level))
                .frame(width: 52, height: 52)
                .progressStructureIconStyle(colorScheme)
                .modifier(ProgressLevelPopover(item: item, townHall: townHall))
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(.subheadline.weight(.medium))
                levelLine(level, count: count, item: item)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private enum BadgeStyle { case normal, townHall, overall }

    private func levelLine(_ level: Int, count: Int, item: ProgressCatalog.Item) -> some View {
        let cap = item.maxLevel(at: townHall)
        let overall = item.levels.map(\.level).max() ?? 0
        let style: BadgeStyle = overall > 0 && level >= overall ? .overall
            : cap > 0 && level >= cap ? .townHall : .normal
        return HStack(spacing: 5) {
            numberBadge(level, style: style)
            if count > 1 { Text("×\(count)").font(.caption).fixedSize(horizontal: true, vertical: false) }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Level \(level)\(count > 1 ? ", \(count) copies" : "")")
    }

    private func numberBadge(_ level: Int, style: BadgeStyle) -> some View {
        let fill: Color = style == .overall ? Color(red: 1, green: 0.79, blue: 0.22)
            : style == .townHall ? (colorScheme == .dark
                ? Color(red: 0.13, green: 0.39, blue: 0.60)
                : Color(red: 0.39, green: 0.71, blue: 0.89)) : Color(.secondarySystemGroupedBackground)
        let edge: Color = style == .overall ? Color(red: 0.70, green: 0.44, blue: 0.04)
            : style == .townHall ? (colorScheme == .dark
                ? Color(red: 0.32, green: 0.63, blue: 0.83)
                : Color(red: 0.12, green: 0.42, blue: 0.65)) : Color(.separator)
        return Text("\(level)")
            .font(.caption.bold()).monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(style == .townHall ? (colorScheme == .dark ? .white : .black) : .primary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(fill, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(edge, lineWidth: 1.5))
            .fixedSize(horizontal: true, vertical: false)
    }

    private func superchargeCounts(for item: ProgressCatalog.Item) -> [Int: Int] {
        guard let definition = ProgressCatalog.superchargeDefinition(for: item),
              let export else { return [:] }
        let cap = item.maxLevel(at: townHall)
        var counts: [Int: Int] = [:]
        for building in export.buildings ?? [] where building.data == item.id {
            let charge = building.supercharge ?? 0
            if charge > 0 || (townHall >= definition.unlockTownHall && cap > 0 && (building.lvl ?? 0) >= cap) {
                counts[charge, default: 0] += building.cnt ?? 1
            }
        }
        return counts
    }

    private var superchargesCard: some View {
        let buildingGroups = ProgressCatalog.sections.first(where: { $0.id == "buildings" })?.groups ?? []
        let hasEligibleBuildings = buildingGroups.flatMap(\.items).contains { item in
            guard let definition = ProgressCatalog.superchargeDefinition(for: item) else { return false }
            return townHall >= definition.unlockTownHall || !superchargeCounts(for: item).isEmpty
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Supercharges").font(.headline)
            if !hasEligibleBuildings {
                Text("No supercharges available at this Town Hall.")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            ForEach(buildingGroups, id: \.id) { group in
                let eligible = group.items.filter { item in
                    guard let definition = ProgressCatalog.superchargeDefinition(for: item) else { return false }
                    return townHall >= definition.unlockTownHall || !superchargeCounts(for: item).isEmpty
                }
                if !eligible.isEmpty {
                    Text(group.title).font(.subheadline.bold()).padding(.top, 4)
                    VStack(spacing: 0) {
                        ForEach(eligible) { item in
                            superchargeRow(item)
                            if item.id != eligible.last?.id { Divider() }
                        }
                    }
                }
            }
        }
        .progressCardStyle()
    }

    private func superchargeRow(_ item: ProgressCatalog.Item) -> some View {
        let counts = superchargeCounts(for: item)
        let definition = ProgressCatalog.superchargeDefinition(for: item)
        let baseLevel = (export?.buildings ?? []).filter { $0.data == item.id }.compactMap(\.lvl).max() ?? 0
        return HStack(alignment: .top, spacing: 12) {
            ProgressStructureImage(name: item.assetName(for: baseLevel))
                .frame(width: 52, height: 52)
                .overlay(alignment: .topTrailing) {
                    Image("extras/supercharge").resizable().scaledToFit()
                        .frame(width: 22, height: 22).offset(x: 5, y: -5)
                }
                .saturation(counts.isEmpty ? 0 : 1)
                .opacity(counts.isEmpty ? 0.35 : 1)
                .progressStructureIconStyle(colorScheme)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(.subheadline.weight(.medium))
                if counts.isEmpty {
                    Text("Max this building to unlock").font(.caption).foregroundColor(.secondary)
                } else {
                    ProgressBadgeFlow(spacing: 6) {
                        ForEach(counts.keys.sorted(), id: \.self) { level in
                            HStack(spacing: 5) {
                                numberBadge(level, style: level > 0 && level >= (definition?.maxLevel ?? Int.max) ? .overall : .normal)
                                if (counts[level] ?? 0) > 1 { Text("×\(counts[level] ?? 0)").font(.caption) }
                            }
                            .accessibilityLabel("Supercharge level \(level), \(counts[level] ?? 0) copies")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func craftedDefenseRow(_ item: ProgressCatalog.Item) -> some View {
        let building = (export?.buildings ?? []).first { building in
            building.types?.contains(where: { $0.data == item.id }) == true
        }
        let modules = building?.types?.first(where: { $0.data == item.id })?.modules ?? []
        let levels = Dictionary(modules.map { ($0.data, $0.lvl ?? 1) }, uniquingKeysWith: max)
        return HStack(spacing: 12) {
            ProgressStructureImage(name: item.assetName(for: 1))
                .frame(width: 52, height: 52)
                .saturation(modules.isEmpty ? 0 : 1)
                .opacity(modules.isEmpty ? 0.35 : 1)
                .progressStructureIconStyle(colorScheme)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(.subheadline.weight(.medium))
                if modules.isEmpty {
                    Text("None of this building to upgrade").font(.caption).foregroundColor(.secondary)
                } else {
                    HStack(spacing: 6) {
                        ForEach(Array(item.moduleIds.enumerated()), id: \.element) { index, moduleID in
                            let level = levels[moduleID] ?? 0
                            numberBadge(level, style: level > 0 && level >= item.moduleMaximums[index] ? .overall : .normal)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func tile(_ item: ProgressCatalog.Item, level: Int, count: Int) -> some View {
        let cap = item.maxLevel(at: townHall)
        let overall = item.levels.map(\.level).max() ?? 0
        let gold = level > 0 && overall > 0 && level >= overall
        let blue = level > 0 && cap > 0 && level >= cap
        let fill: Color = gold ? Color(red: 1, green: 0.79, blue: 0.22)
            : blue ? Color(red: 0.65, green: 0.87, blue: 1) : Color(.secondarySystemGroupedBackground)
        let edge: Color = gold ? Color(red: 0.70, green: 0.44, blue: 0.04)
            : blue ? Color(red: 0.24, green: 0.57, blue: 0.78) : Color(.separator)
        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    Image(item.assetName(for: level)).resizable().scaledToFit()
                }
                .frame(width: 58, height: 58)
                .saturation(level == 0 ? 0 : 1)
                .opacity(level == 0 ? 0.4 : 1)
                if count > 1 {
                    Text("×\(count)").font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .modifier(ProgressLevelPopover(item: item, townHall: townHall))
            Text(level == 0 ? "—" : "\(level)")
                .font(.caption.bold()).monospacedDigit()
                .frame(minWidth: 28).padding(.horizontal, 4).padding(.vertical, 2)
                .background(fill, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(edge, lineWidth: 1.5))
            Text(item.name).font(.system(size: 10)).lineLimit(2)
                .multilineTextAlignment(.center).frame(height: 26, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var equipmentCard: some View {
        let equipment = EquipmentDataStore.shared.entries
        let heroes = HeroConfigStore.shared.configs.map(\.displayName)
            .filter { hero in equipment.contains { $0.hero == hero } }
        let exportLevels = ProgressCatalog.equipmentLevels(in: export)
        let profileLevels = Dictionary((dataService.currentProfile?.cachedProfile?.heroEquipment ?? [])
            .map { ($0.name.lowercased(), $0.level) }, uniquingKeysWith: max)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Equipment").font(.headline)
            ForEach(heroes, id: \.self) { hero in
                Text(hero).font(.subheadline.bold()).padding(.top, 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 8)], spacing: 12) {
                    ForEach(equipment.filter { $0.hero == hero }, id: \.name) { item in
                        let level = exportLevels[item.name.lowercased()] ?? profileLevels[item.name.lowercased()] ?? 0
                        equipmentTile(item, level: level)
                    }
                }
            }
        }
        .progressCardStyle()
    }

    private func equipmentTile(_ item: EquipmentMetadata, level: Int) -> some View {
        let isEpic = item.rarity == .epic
        let isMax = level > 0 && level >= item.rarity.maxLevel
        let fill = isEpic ? (colorScheme == .dark ? Color(red: 0.35, green: 0.18, blue: 0.29)
                                             : Color(red: 1, green: 0.84, blue: 0.92))
            : (colorScheme == .dark ? Color(red: 0.16, green: 0.30, blue: 0.39)
                                    : Color(red: 0.78, green: 0.91, blue: 1))
        let badgeFill = isMax ? Color(red: 1, green: 0.79, blue: 0.22) : Color(.secondarySystemGroupedBackground)
        let badgeEdge = isMax ? Color(red: 0.70, green: 0.44, blue: 0.04) : Color(.separator)
        return VStack(spacing: 4) {
            Image(item.assetName)
                .resizable().scaledToFit().frame(width: 58, height: 58)
                .saturation(level == 0 ? 0 : 1)
                .opacity(level == 0 ? 0.4 : 1)
                .background(fill, in: RoundedRectangle(cornerRadius: 10))
            Text(level == 0 ? "—" : "\(level)")
                .font(.caption.bold()).monospacedDigit()
                .foregroundColor(isMax ? .black : .primary)
                .frame(minWidth: 28).padding(.horizontal, 4).padding(.vertical, 2)
                .background(badgeFill, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(badgeEdge, lineWidth: 1.5))
            Text(item.name).font(.system(size: 10)).lineLimit(2)
                .multilineTextAlignment(.center).frame(height: 26, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(item.rarity.label), \(level == 0 ? "not unlocked" : "level \(level)"), overall max \(item.rarity.maxLevel)\(isMax ? ", overall maximum reached" : "")")
    }
}

private extension View {
    func progressStructureIconStyle(_ colorScheme: ColorScheme) -> some View {
        let fill = colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
        let edge = colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.035)
        return self.padding(4)
            .background(fill, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(edge, lineWidth: 1))
    }

    func progressCardStyle() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.tertiarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(.separator).opacity(0.6), lineWidth: 1))
    }
}

private struct ProgressStructureImage: View {
    let name: String

    var body: some View {
        #if canImport(UIKit)
        if let image = ProgressStructureImageCache.trimmedImage(named: name) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            Image(name).resizable().scaledToFit()
        }
        #else
        Image(name).resizable().scaledToFit()
        #endif
    }
}

private enum ProgressStructureImageCache {
    #if canImport(UIKit)
    private static let images = NSCache<NSString, UIImage>()

    static func trimmedImage(named name: String) -> UIImage? {
        let key = NSString(string: name)
        if let cached = images.object(forKey: key) { return cached }
        guard let source = UIImage(named: name) else { return nil }
        let trimmed = trimTransparentEdges(from: source)
        images.setObject(trimmed, forKey: key)
        return trimmed
    }

    private static func trimTransparentEdges(from image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage,
              let providerData = cgImage.dataProvider?.data,
              let pixels = CFDataGetBytePtr(providerData) else { return image }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        guard bytesPerPixel > 0 else { return image }

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * bytesPerRow + x * bytesPerPixel
                let alpha: UInt8
                switch cgImage.alphaInfo {
                case .premultipliedFirst, .first, .noneSkipFirst:
                    alpha = pixels[pixelIndex]
                case .premultipliedLast, .last, .noneSkipLast:
                    alpha = pixels[pixelIndex + bytesPerPixel - 1]
                case .alphaOnly:
                    alpha = pixels[pixelIndex]
                case .none:
                    return image
                @unknown default:
                    return image
                }
                if alpha > 5 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard minX <= maxX, minY <= maxY,
              let cropped = cgImage.cropping(to: CGRect(x: minX, y: minY,
                                                       width: maxX - minX + 1,
                                                       height: maxY - minY + 1)) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
    #endif
}

private struct ProgressBadgeFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = layout(subviews, width: bounds.width).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: .unspecified)
        }
    }

    private func layout(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
            frames.append(frame)
            widest = max(widest, frame.maxX)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (frames, CGSize(width: width.isFinite ? width : widest,
                               height: frames.isEmpty ? 0 : y + rowHeight))
    }
}

private struct ProgressLevelPopover: ViewModifier {
    let item: ProgressCatalog.Item
    let townHall: Int
    @ScaledMetric(relativeTo: .body) private var requiredSpace: CGFloat = 170
    @State private var isPresented = false
    @State private var arrowEdge: Edge = .top

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let frame = geometry.frame(in: .global)
                            let windowHeight = UIApplication.shared.connectedScenes
                                .compactMap { $0 as? UIWindowScene }
                                .flatMap(\.windows)
                                .first(where: \.isKeyWindow)?.bounds.height ?? frame.maxY
                            let spaceBelow = windowHeight - frame.maxY
                            arrowEdge = spaceBelow < requiredSpace && frame.minY > spaceBelow ? .bottom : .top
                            isPresented = true
                        }
                }
            }
            .accessibilityLabel("\(item.name), show maximum levels")
            .accessibilityAddTraits(.isButton)
            .popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.name).font(.headline)
                    let townHallMax = item.maxLevel(at: townHall)
                    Text("Town Hall \(townHall) max: \(townHallMax > 0 ? String(townHallMax) : "Not available")")
                    Text("Overall max: \(item.levels.map(\.level).max() ?? 0)")
                }
                .font(.subheadline)
                .padding(16)
                .frame(width: 230, alignment: .leading)
                .presentationCompactAdaptation(.popover)
            }
    }
}

enum ProgressCatalog {
    struct SuperchargeDefinition {
        let maxLevel: Int
        let unlockTownHall: Int
    }
    struct CatalogFile: Decodable {
        let schemaVersion: Int
        let sections: [Definition]
    }

    struct Definition: Decodable {
        let id: String
        let title: String
        let export: String
        let levels: String
        let groups: [GroupDefinition]
    }

    struct GroupDefinition: Decodable {
        let id: String
        let title: String
        let assetFolder: String
        let items: [ItemDefinition]
    }

    struct ItemDefinition: Decodable {
        let id: Int
        let name: String
        let image: String?
        let imagePattern: String?
        let moduleIds: [Int]?
    }

    struct Level {
        let level: Int
        let required: Int
        let requiredTownHall: Int
    }

    struct Item: Identifiable {
        let id: Int
        let name: String
        let category: String
        let folder: String
        let image: String?
        let imagePattern: String?
        let moduleIds: [Int]
        let moduleMaximums: [Int]
        let levels: [Level]
        let isStructure: Bool

        func maxLevel(at townHall: Int) -> Int {
            let facility = isStructure ? townHall : ProgressCatalog.facilityLevel(for: category, townHall: townHall)
            let maxAvailable = levels.filter { $0.required <= facility && $0.requiredTownHall <= townHall }
                .map(\.level).max() ?? 0
            return id == 1000001 ? min(maxAvailable, townHall) : maxAvailable
        }

        func assetName(for level: Int) -> String {
            if let imagePattern {
                let image = imagePattern.replacingOccurrences(of: "{level}", with: String(max(1, min(level, 19))))
                return "\(folder)/\(image)"
            }
            return "\(folder)/\(image ?? "town_hall")"
        }
    }

    struct Group {
        let id: String
        let title: String
        let items: [Item]
    }

    struct Section {
        let id: String
        let title: String
        let exportKey: String
        let groups: [Group]
        var isStructure: Bool { ["buildings", "traps", "walls"].contains(id) }

        func inventory(in export: CoCExport) -> [Int: [Int: Int]] {
            var result: [Int: [Int: Int]] = [:]
            func add(_ id: Int, _ level: Int, _ count: Int) {
                result[id, default: [:]][level, default: 0] += count
            }
            switch exportKey {
            case "units": (export.units ?? []).forEach { add($0.data, $0.lvl, 1) }
            case "siege_machines": (export.siegeMachines ?? []).forEach { add($0.data, $0.lvl, 1) }
            case "spells": (export.spells ?? []).forEach { add($0.data, $0.lvl, 1) }
            case "heroes": (export.heroes ?? []).forEach { add($0.data, $0.lvl, 1) }
            case "pets": (export.pets ?? []).forEach { add($0.data, $0.lvl, 1) }
            case "guardians": (export.guardians ?? []).forEach { add($0.data, $0.lvl ?? 1, 1) }
            case "buildings": (export.buildings ?? []).forEach { add($0.data, $0.lvl ?? 1, $0.cnt ?? 1) }
            case "traps": (export.traps ?? []).forEach { add($0.data, $0.lvl, $0.cnt ?? 1) }
            default: break
            }
            return result
        }
    }

    static let sections: [Section] = {
        guard let data = load("progress_sections", folder: "json"),
              let file = try? JSONDecoder().decode(CatalogFile.self, from: data) else { return [] }
        var sections = file.sections.map { definition in
            let parsed = parsedEntries(file: definition.levels)
            let groups = definition.groups.map { group in
                Group(id: group.id, title: group.title, items: group.items.map { entry in
                    let rawLevels = parsed[entry.id]?["levels"] as? [[String: Any]] ?? []
                    let levels = rawLevels.compactMap { raw -> Level? in
                        guard let number = integer(raw["level"]) else { return nil }
                        let required: Int
                        if ["buildings", "traps", "walls"].contains(definition.id) {
                            required = integer(raw["townHallLevel"] ?? raw["TownHallLevel"]) ?? 0
                        } else if definition.id == "heroes" {
                            required = integer(raw["RequiredHeroTavernLevel"]) ?? 0
                        } else if definition.id == "guardians" {
                            required = 18
                        } else {
                            required = integer(raw["LaboratoryLevel"]) ?? 0
                        }
                        let requiredTH = definition.id == "heroes" ? (integer(raw["RequiredTownHallLevel"]) ?? 0) : 0
                        return Level(level: number, required: required, requiredTownHall: requiredTH)
                    }
                    let moduleIds = entry.moduleIds ?? []
                    let moduleMaximums = moduleIds.map { moduleID in
                        (parsed[moduleID]?["levels"] as? [[String: Any]] ?? [])
                            .compactMap { integer($0["level"]) }.max() ?? 10
                    }
                    return Item(id: entry.id, name: entry.name, category: definition.id,
                                folder: group.assetFolder, image: entry.image, imagePattern: entry.imagePattern,
                                moduleIds: moduleIds, moduleMaximums: moduleMaximums, levels: levels,
                                isStructure: ["buildings", "traps", "walls"].contains(definition.id))
                })
            }
            return Section(id: definition.id, title: definition.title,
                           exportKey: definition.export, groups: groups)
        }
        let equipment = Section(id: "equipment", title: "Equipment", exportKey: "equipment", groups: [])
        if let guardiansIndex = sections.firstIndex(where: { $0.id == "guardians" }) {
            sections.insert(equipment, at: guardiansIndex + 1)
        }
        let supercharges = Section(id: "supercharges", title: "Supercharges", exportKey: "buildings", groups: [])
        let crafted = sections.firstIndex(where: { $0.id == "crafted_defenses" }).map { sections.remove(at: $0) }
        sections.append(supercharges)
        if let crafted { sections.append(crafted) }
        return sections
    }()

    private static let equipmentNamesByID: [String: String] = {
        guard let data = load("mapping", folder: "json"),
              let names = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return names
    }()

    static func equipmentLevels(in export: CoCExport?) -> [String: Int] {
        guard let equipment = export?.equipment else { return [:] }
        return Dictionary(equipment.compactMap { entry -> (String, Int)? in
            guard let name = equipmentNamesByID[String(entry.data)] else { return nil }
            return (name.lowercased(), entry.lvl)
        }, uniquingKeysWith: max)
    }

    private static let buildingFacilities: [Int: [[String: Any]]] = {
        let parsed = parsedEntries(file: "buildings")
        return [1000007, 1000068, 1000071].reduce(into: [:]) { result, id in
            result[id] = parsed[id]?["levels"] as? [[String: Any]] ?? []
        }
    }()

    private static let miniLevelsByBuilding: [String: [[String: Any]]] = {
        guard let data = load("mini_levels", folder: "parsed_json_files"),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        var result: [String: [[String: Any]]] = [:]
        for entry in entries {
            guard let internalName = entry["internalName"] as? String,
                  let levels = entry["levels"] as? [[String: Any]] else { continue }
            let buildingName = internalName.replacingOccurrences(of: " Mini Levels", with: "")
            result[normalized(buildingName)] = levels
        }
        return result
    }()

    static let maximumTownHallLevel: Int = {
        guard let data = load("game_constants", folder: "json"),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let level = values["max_town_hall_level"] as? Int else { return 0 }
        return level
    }()

    static func superchargeDefinition(for item: Item) -> SuperchargeDefinition? {
        guard let miniLevels = miniLevelsByBuilding[normalized(item.name)],
              let maxLevel = miniLevels.compactMap({ integer($0["level"]) }).max() else { return nil }
        let statedUnlock = miniLevels.compactMap { integer($0["RequiredTownHallLevel"]) }.first
        if let statedUnlock, statedUnlock > maximumTownHallLevel { return nil }
        let overall = item.levels.map(\.level).max() ?? 0
        let baseUnlock = item.levels.filter { $0.level == overall }.map(\.required).min() ?? 18
        let unlockTownHall = statedUnlock ?? baseUnlock
        guard maximumTownHallLevel > 0, unlockTownHall <= maximumTownHallLevel else { return nil }
        return SuperchargeDefinition(maxLevel: maxLevel, unlockTownHall: unlockTownHall)
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private static func facilityLevel(for category: String, townHall: Int) -> Int {
        if category == "guardians" { return townHall }
        let id = category == "pets" ? 1000068 : category == "heroes" ? 1000071 : 1000007
        return (buildingFacilities[id] ?? []).filter { (integer($0["townHallLevel"]) ?? Int.max) <= townHall }
            .compactMap { integer($0["level"]) }.max() ?? 0
    }

    private static func parsedEntries(file: String) -> [Int: [String: Any]] {
        guard let data = load(file, folder: "parsed_json_files"),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        return Dictionary(entries.compactMap { entry -> (Int, [String: Any])? in
            guard let id = entry["id"] as? Int else { return nil }
            return (id, entry)
        }, uniquingKeysWith: { first, _ in first })
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let text = value as? String { return Int(text) }
        return nil
    }

    private static func load(_ name: String, folder: String) -> Data? {
        for base in DataService.candidateFolderURLs(named: folder) {
            if let data = try? Data(contentsOf: base.appendingPathComponent("\(name).json")) { return data }
        }
        return nil
    }
}

enum ProgressDisplaySettings {
    static func markNewProfile(_ id: UUID) {
        UserDefaults.standard.set(true, forKey: "progressDisplayNewProfile.\(id.uuidString)")
    }

    static func value(for option: String, profileID: UUID, townHall: Int) -> Bool {
        let defaults = UserDefaults.standard
        if let saved = defaults.object(forKey: key(option, profileID)) as? Bool { return saved }
        let isNew = defaults.bool(forKey: "progressDisplayNewProfile.\(profileID.uuidString)")
        if !isNew {
            let legacyKey = option == "supercharges" ? "progressShowSupercharges" : "progressShowCraftedDefenses"
            if let legacyValue = defaults.object(forKey: legacyKey) as? Bool { return legacyValue }
        }
        let maximum = ProgressCatalog.maximumTownHallLevel
        return maximum > 0 && townHall >= maximum
    }

    static func save(_ enabled: Bool, option: String, profileID: UUID) {
        UserDefaults.standard.set(enabled, forKey: key(option, profileID))
    }

    private static func key(_ option: String, _ profileID: UUID) -> String {
        "progressDisplay.\(profileID.uuidString).\(option)"
    }
}
