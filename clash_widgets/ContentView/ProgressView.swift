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

    private var export: CoCExport? {
        dataService.currentProfile.flatMap { dataService.decodeExport(from: $0.rawJSON) }
    }

    private var townHall: Int {
        if let level = dataService.cachedProfile?.townHallLevel, level > 0 { return level }
        return dataService.currentProfile.map { dataService.inferTownHallLevel(from: $0.rawJSON) } ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    if export != nil {
                        HStack {
                            Menu {
                                ForEach(visibleSectionIDs, id: \.self) { id in
                                    if let section = ProgressCatalog.sections.first(where: { $0.id == id }) {
                                        Button(section.title) {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                proxy.scrollTo(id, anchor: .top)
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "list.bullet")
                                    Text("Category")
                                    Image(systemName: "chevron.down")
                                        .font(.caption2.bold())
                                }
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator).opacity(0.6)))
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .background(Color(.systemGroupedBackground))
                    }
                    ScrollView {
                        VStack(spacing: 16) {
                            if export == nil {
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
                        .padding(.top, 20)
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
                            ForEach(order, id: \.self) { id in
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
                                order.move(fromOffsets: offsets, toOffset: destination)
                                storedOrder = order.joined(separator: ",")
                            }
                        }
                    }
                    .environment(\.editMode, .constant(.active))
                    .navigationTitle("Edit Progress Cards")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { editingCards = false } } }
                }
                .adaptivePanelPresentation()
            }
            .onAppear {
                let ids = ProgressCatalog.sections.map(\.id)
                let saved = storedOrder.split(separator: ",").map(String.init).filter { ids.contains($0) }
                var resolved = saved + ids.filter { !saved.contains($0) }
                if !saved.contains("supercharges"),
                   let currentIndex = resolved.firstIndex(of: "supercharges"),
                   let buildingsIndex = resolved.firstIndex(of: "buildings") {
                    resolved.remove(at: currentIndex)
                    resolved.insert("supercharges", at: buildingsIndex + 1)
                }
                order = resolved
                hidden = Set(storedHidden.split(separator: ",").map(String.init))
                loadDisplaySettings()
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

    private func loadDisplaySettings() {
        guard let id = dataService.selectedProfileID else { return }
        showSupercharges = ProgressDisplaySettings.value(for: "supercharges", profileID: id, townHall: townHall)
        showCraftedDefenses = ProgressDisplaySettings.value(for: "craftedDefenses", profileID: id, townHall: townHall)
    }

    private var displayOptionsButton: some View {
        Button { showingDisplayOptions = true } label: {
            Image(systemName: "eye.fill")
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

    @available(iOS 26.0, *)
    @ToolbarContentBuilder
    private var progressToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarLeading) {
            displayOptionsButton
            reorderCardsButton
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
        ToolbarItem(placement: .navigationBarTrailing) { ProfileSwitcherMenu() }
    }

    private var visibleSectionIDs: [String] {
        order.filter { id in
            !hidden.contains(id) && (id != "crafted_defenses" || showCraftedDefenses)
                && (id != "supercharges" || showSupercharges)
        }
    }

    private func sectionCard(_ section: ProgressCatalog.Section) -> some View {
        if section.id == "supercharges" {
            return AnyView(superchargesCard)
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
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Image(item.assetName(for: previewLevel))
                    .resizable().scaledToFit()
                    .frame(width: 52, height: 52)
                    .saturation(counts.isEmpty ? 0 : 1)
                    .opacity(counts.isEmpty ? 0.35 : 1)
                Text(item.name).font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
            }
            if counts.isEmpty {
                Text("None of this building to upgrade").font(.caption).foregroundColor(.secondary)
                    .padding(.leading, 64)
            } else {
                ForEach(counts.keys.sorted(), id: \.self) { level in
                    levelLine(level, count: counts[level] ?? 1, item: item)
                        .padding(.leading, 64)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func wallRow(_ item: ProgressCatalog.Item, level: Int, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(item.assetName(for: level)).resizable().scaledToFit()
                .frame(width: 52, height: 52)
            Text(item.name).font(.subheadline.weight(.medium))
            Spacer()
            levelLine(level, count: count, item: item)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private enum BadgeStyle { case normal, townHall, overall }

    private func levelLine(_ level: Int, count: Int, item: ProgressCatalog.Item) -> some View {
        let cap = item.maxLevel(at: townHall)
        let overall = item.levels.map(\.level).max() ?? 0
        let style: BadgeStyle = overall > 0 && level >= overall ? .overall
            : cap > 0 && level >= cap ? .townHall : .normal
        return HStack(spacing: 5) {
            numberBadge(level, style: style)
            if count > 1 { Text("×\(count)").font(.caption) }
        }
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
            .foregroundColor(style == .townHall ? (colorScheme == .dark ? .white : .black) : .primary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(fill, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(edge, lineWidth: 1.5))
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
            Image(item.assetName(for: baseLevel)).resizable().scaledToFit()
                .frame(width: 52, height: 52)
                .overlay(alignment: .topTrailing) {
                    Image("extras/supercharge").resizable().scaledToFit()
                        .frame(width: 22, height: 22).offset(x: 5, y: -5)
                }
                .saturation(counts.isEmpty ? 0 : 1)
                .opacity(counts.isEmpty ? 0.35 : 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(.subheadline.weight(.medium))
                if counts.isEmpty {
                    Text("Max this building to unlock").font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(counts.keys.sorted(), id: \.self) { level in
                        HStack(spacing: 5) {
                            numberBadge(level, style: level > 0 && level >= (definition?.maxLevel ?? Int.max) ? .townHall : .normal)
                            if (counts[level] ?? 0) > 1 { Text("×\(counts[level] ?? 0)").font(.caption) }
                        }
                        .accessibilityLabel("Supercharge level \(level), \(counts[level] ?? 0) copies")
                    }
                }
            }
            Spacer(minLength: 0)
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
            Image(item.assetName(for: 1)).resizable().scaledToFit()
                .frame(width: 52, height: 52)
                .saturation(modules.isEmpty ? 0 : 1)
                .opacity(modules.isEmpty ? 0.35 : 1)
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
            Text(level == 0 ? "—" : "\(level)")
                .font(.caption.bold()).monospacedDigit()
                .frame(minWidth: 28).padding(.horizontal, 4).padding(.vertical, 2)
                .background(fill, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(edge, lineWidth: 1.5))
            Text(item.name).font(.system(size: 10)).lineLimit(2)
                .multilineTextAlignment(.center).frame(height: 26, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(level == 0 ? "not unlocked" : "level \(level)")\(count > 1 ? ", \(count) copies" : "")\(gold ? ", overall maximum" : blue ? ", Town Hall maximum" : "")")
    }
}

private extension View {
    func progressCardStyle() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.tertiarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(.separator).opacity(0.6), lineWidth: 1))
    }
}

private enum ProgressCatalog {
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
        let supercharges = Section(id: "supercharges", title: "Supercharges", exportKey: "buildings", groups: [])
        if let buildingsIndex = sections.firstIndex(where: { $0.id == "buildings" }) {
            sections.insert(supercharges, at: buildingsIndex + 1)
        }
        return sections
    }()

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
