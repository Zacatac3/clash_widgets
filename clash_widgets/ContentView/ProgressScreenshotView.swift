import SwiftUI
import UIKit
import CoreImage
import UniformTypeIdentifiers

struct ProgressExportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("progressScreenshotBackground") private var selectedBackground = "Classic"
    @State private var format = ExportFormat.square
    @State private var isExporting = false
    @State private var shareFiles: ShareFiles?
    @State private var exportDirectory: URL?
    @State private var exportError: String?
    @State private var copied = false
    @State private var pageIndex = 0
    @State private var pages: [Page] = []
    @State private var previewImages: [UIImage] = []
    @State private var previewRequest: PreviewRequest?
    @State private var loadedBackground: UIImage?
    @State private var loadedBackgroundRequest: BackgroundRequest?

    let export: CoCExport
    let contentRevision: String
    let townHall: Int
    let cachedEquipment: [HeroEquipment]
    let playerName: String
    let playerTag: String

    private let inset: CGFloat = 24
    private let spacing: CGFloat = 3
    private let maxLevelGold = Color(red: 0.98, green: 0.75, blue: 0.22)

    private var canvasScheme: ColorScheme { selectedBackground.isEmpty ? colorScheme : .dark }

    var body: some View {
        let size = format.size
        let request = BackgroundRequest(name: selectedBackground,
                                        width: Int(size.width), height: Int(size.height))
        let foregroundRequest = PreviewRequest(format: format, contentRevision: contentRevision,
                                               townHall: townHall, equipment: cachedEquipment.map { "\($0.name):\($0.level)" },
                                               hasBackground: !selectedBackground.isEmpty,
                                               scheme: canvasScheme == .dark ? "dark" : "light",
                                               playerName: playerName, playerTag: playerTag)
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Menu {
                        Picker("Background", selection: $selectedBackground) {
                            Text("No Background").tag("")
                            ForEach(ScreenshotBackgrounds.names, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    } label: {
                        selectorLabel(selectedBackground.isEmpty ? "No Background" : selectedBackground)
                    }
                    .accessibilityLabel("Choose Export Background")
                    Spacer(minLength: 0)
                    Menu {
                        Picker("Canvas", selection: $format) {
                            Section("Square") { Text(ExportFormat.square.title).tag(ExportFormat.square) }
                            Section("Portrait") {
                                Text(ExportFormat.portrait.title).tag(ExportFormat.portrait)
                                Text(ExportFormat.portraitThreeFour.title).tag(ExportFormat.portraitThreeFour)
                            }
                            Section("Landscape") {
                                Text(ExportFormat.landscapeFourThree.title).tag(ExportFormat.landscapeFourThree)
                                Text(ExportFormat.landscapeFiveFour.title).tag(ExportFormat.landscapeFiveFour)
                            }
                        }
                    } label: {
                        selectorLabel(format.title)
                    }
                    .accessibilityLabel("Choose Export Aspect Ratio")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .disabled(isExporting)
                .padding(.horizontal)

                GeometryReader { geometry in
                    let scale = max(0.01, min((geometry.size.width - 24) / size.width,
                                             geometry.size.height / size.height))
                    TabView(selection: $pageIndex) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, _ in
                            ZStack {
                                background
                                if previewRequest == foregroundRequest, previewImages.indices.contains(index) {
                                    Image(uiImage: previewImages[index]).resizable().scaledToFit()
                                } else {
                                    ProgressView("Preparing preview…")
                                }
                            }
                                .frame(width: size.width, height: size.height)
                                .clipped()
                                .scaleEffect(scale)
                                .frame(width: size.width * scale, height: size.height * scale)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
                VStack(spacing: 6) {
                    HStack(spacing: 7) {
                        ForEach(pages.indices, id: \.self) { index in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { pageIndex = index }
                            } label: {
                                Capsule()
                                    .fill(index == pageIndex ? Color.primary : Color.primary.opacity(0.28))
                                    .frame(width: index == pageIndex ? 17 : 6, height: 6)
                                    .frame(minWidth: 30, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Page \(index + 1) of \(pages.count)")
                            .accessibilityAddTraits(index == pageIndex ? .isSelected : [])
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .background(.regularMaterial, in: Capsule())
                    .disabled(isExporting)
                    Text(copied ? "Image copied to clipboard" : "Swipe to preview · Copy or share the current page")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Share Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.disabled(isExporting)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        exportPage(pages, share: false)
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .accessibilityLabel("Copy Current Page to Clipboard")
                    .disabled(isExporting || pages.isEmpty || !backgroundReady || previewRequest != foregroundRequest)

                    Button {
                        exportPage(pages, share: true)
                    } label: {
                        if isExporting {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .accessibilityLabel("Share Current Page")
                    .disabled(isExporting || pages.isEmpty || !backgroundReady || previewRequest != foregroundRequest)
                }
            }
        }
        .sheet(item: $shareFiles, onDismiss: cleanUpExport) { files in
            ProgressExportShareSheet(urls: files.urls)
        }
        .alert("Couldn’t Export", isPresented: Binding(get: { exportError != nil },
                                                      set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "Please try again.")
        }
        .interactiveDismissDisabled(isExporting)
        .onChangeCompat(of: pageIndex) { _ in copied = false }
        .onChangeCompat(of: format) { _ in
            pageIndex = 0
            copied = false
        }
        .onChangeCompat(of: contentRevision) { _ in pageIndex = 0; copied = false }
        .onChangeCompat(of: townHall) { _ in copied = false }
        .onChangeCompat(of: cachedEquipment.map { "\($0.name):\($0.level)" }) { _ in copied = false }
        .onChangeCompat(of: selectedBackground) { _ in copied = false }
        .task(id: foregroundRequest) {
            // Capture a consistent page set; UIKit image rendering stays on the main actor.
            // Yield between pages so the loading state and navigation can update.
            let currentPages = makePages(width: size.width, height: size.height)
            pages = currentPages
            var images: [UIImage] = []
            for page in currentPages {
                await Task.yield()
                guard !Task.isCancelled else { return }
                let renderer = ImageRenderer(content: foreground(page, size: size))
                renderer.proposedSize = ProposedViewSize(size)
                renderer.scale = 1440 / max(size.width, size.height)
                guard let image = renderer.uiImage else {
                    exportError = "The preview couldn’t be prepared. Please try again."
                    return
                }
                images.append(image)
            }
            guard !Task.isCancelled else { return }
            previewImages = images
            previewRequest = foregroundRequest
        }
        .task(id: request) {
            loadedBackground = nil
            loadedBackgroundRequest = nil
            guard !request.name.isEmpty, ScreenshotBackgrounds.names.contains(request.name) else { return }
            let image = await Task.detached(priority: .userInitiated) {
                ScreenshotBackgrounds.renderedImage(named: request.name,
                                                    size: CGSize(width: request.width, height: request.height))
            }.value
            guard !Task.isCancelled else { return }
            loadedBackground = image
            loadedBackgroundRequest = request
            if image == nil { exportError = "The selected background couldn’t be loaded. Choose another background." }
        }
        .onAppear {
            if !selectedBackground.isEmpty && !ScreenshotBackgrounds.names.contains(selectedBackground) {
                selectedBackground = "Classic"
            }
        }
    }

    private func selectorLabel(_ title: String) -> some View {
        HStack(spacing: 7) {
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.bold())
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(.regularMaterial, in: Capsule())
        .contentShape(Capsule())
    }

    private var backgroundReady: Bool {
        selectedBackground.isEmpty || (loadedBackgroundRequest == BackgroundRequest(
            name: selectedBackground, width: Int(format.size.width), height: Int(format.size.height))
            && loadedBackground != nil)
    }

    // Preview and image rendering always use this same fixed-size view.
    private func canvas(_ page: Page, size: CGSize) -> some View {
        foreground(page, size: size)
            .background { background.frame(width: size.width, height: size.height).clipped() }
    }

    private func foreground(_ page: Page, size: CGSize) -> some View {
        pageView(page)
            .frame(width: size.width, height: size.height)
            .clipped()
            .environment(\.colorScheme, canvasScheme)
            .dynamicTypeSize(.medium)
    }

    @MainActor
    private func exportPage(_ pages: [Page], share: Bool) {
        guard !isExporting, backgroundReady, pages.indices.contains(pageIndex) else { return }
        let page = pages[pageIndex]
        let pageNumber = pageIndex + 1
        let size = format.size
        isExporting = true
        copied = false
        Task { @MainActor in
            await Task.yield()
            defer { isExporting = false }
            do {
                let renderer = ImageRenderer(content: canvas(page, size: size))
                renderer.proposedSize = ProposedViewSize(size)
                renderer.scale = 1440 / max(size.width, size.height)
                renderer.isOpaque = true
                guard let image = renderer.uiImage, let jpeg = image.jpegData(compressionQuality: 0.85) else {
                    throw ExportFailure.rendering
                }
                if share {
                    cleanUpExport()
                    let directory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("Clashboard-Export-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    exportDirectory = directory
                    let title = page.kind == .units ? "Progress" : "Equipment"
                    let url = directory.appendingPathComponent("Clashboard-\(pageNumber)-\(title).jpg")
                    try jpeg.write(to: url, options: .atomic)
                    shareFiles = ShareFiles(urls: [url])
                } else {
                    UIPasteboard.general.setItems([[UTType.jpeg.identifier: jpeg]])
                    copied = true
                }
            } catch {
                cleanUpExport()
                exportError = "The image couldn’t be created. Please try again."
            }
        }
    }

    private func cleanUpExport() {
        if let exportDirectory { try? FileManager.default.removeItem(at: exportDirectory) }
        exportDirectory = nil
    }

    private enum ExportFailure: Error { case rendering }
    private struct ShareFiles: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    private enum ExportFormat: String, CaseIterable, Identifiable {
        case square, portrait, portraitThreeFour, landscapeFourThree, landscapeFiveFour
        var id: Self { self }
        var title: String {
            switch self {
            case .square: return "Square (1:1)"
            case .portrait: return "Portrait (4:5)"
            case .portraitThreeFour: return "Portrait (3:4)"
            case .landscapeFourThree: return "Landscape (4:3)"
            case .landscapeFiveFour: return "Landscape (5:4)"
            }
        }
        var size: CGSize {
            switch self {
            case .square: return CGSize(width: 720, height: 720)
            case .portrait: return CGSize(width: 720, height: 900)
            case .portraitThreeFour: return CGSize(width: 720, height: 960)
            case .landscapeFourThree: return CGSize(width: 960, height: 720)
            case .landscapeFiveFour: return CGSize(width: 900, height: 720)
            }
        }
    }

    private var background: some View {
        Group {
            if backgroundReady, let loadedBackground, !selectedBackground.isEmpty {
                Image(uiImage: loadedBackground)
                    .resizable()
                    .scaledToFill()
                    .overlay(Color.black.opacity(0.26))
            } else {
                Color(colorScheme == .dark ? .systemGroupedBackground : .systemBackground)
            }
        }
        .accessibilityHidden(true)
    }

    private func pageView(_ page: Page) -> some View {
        let grid = page.grid
        let gridWidth = CGFloat(grid.columns) * grid.tile + CGFloat(grid.columns - 1) * spacing
        let gridHeight = CGFloat(grid.rows) * grid.tile + CGFloat(grid.rows - 1) * spacing
        return VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CLASHBOARD")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .tracking(2.2)
                        .foregroundStyle(.secondary)
                    Text(page.kind == .units ? "PROGRESS" : "EQUIPMENT")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(playerTag)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .tracking(2.2)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                    Text(playerName)
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(width: gridWidth)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)

            ZStack(alignment: .topTrailing) {
                VStack(spacing: spacing) {
                    ForEach(0..<grid.rows, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<grid.columns, id: \.self) { column in
                                let slot = row * grid.columns + column
                                if grid.featured && row < 2 && column >= grid.columns - 2 {
                                    Color.clear.frame(width: grid.tile, height: grid.tile)
                                } else if let entryIndex = grid.entryIndex(for: slot), entryIndex < page.entries.count {
                                    tile(page.entries[entryIndex], size: grid.tile)
                                } else {
                                    Color.clear.frame(width: grid.tile, height: grid.tile)
                                }
                            }
                        }
                    }
                }
                if grid.featured {
                    townHallTile(size: grid.tile * 2 + spacing)
                }
            }
            .frame(width: gridWidth, height: gridHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Color.clear.frame(height: 24)
        }
        .foregroundStyle(selectedBackground.isEmpty ? Color.primary : Color.white)
    }

    private func tile(_ entry: Entry, size: CGFloat) -> some View {
        let fill: Color = {
            if entry.level == 0 {
                return selectedBackground.isEmpty ? Color.primary.opacity(0.055) : Color.black.opacity(0.42)
            }
            switch entry.kind {
            case .unit: return selectedBackground.isEmpty ? Color.primary.opacity(0.055) : Color.black.opacity(0.42)
            case .common: return Color(red: 0.47, green: 0.77, blue: 0.96).opacity(0.43)
            case .epic: return Color(red: 0.96, green: 0.53, blue: 0.75).opacity(0.43)
            }
        }()
        let shape = RoundedRectangle(cornerRadius: max(8, size * 0.17))
        return ZStack(alignment: .bottomLeading) {
            Image(entry.assetName)
                .resizable()
                .scaledToFit()
                .padding(2)
                .frame(width: size, height: size)
                .saturation(entry.level == 0 ? 0 : 1)
                .opacity(entry.level == 0 ? 0.45 : 1)
            levelBadge(entry, size: size)
                .padding(3)
        }
        .frame(width: size, height: size)
        .background(fill, in: shape)
        .overlay(shape.stroke(Color.white.opacity(selectedBackground.isEmpty ? 0.09 : 0.3), lineWidth: 1))
        .clipShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.name), \(entry.level == 0 ? "locked" : "level \(entry.level)")")
    }

    private func levelBadge(_ entry: Entry, size: CGFloat) -> some View {
        let atOverallMax = entry.level > 0 && entry.level >= entry.overallMax
        let atTownHallMax = entry.level > 0 && entry.townHallMax > 0 && entry.level >= entry.townHallMax
        let fill = atOverallMax ? maxLevelGold
            : atTownHallMax ? Color(red: 0.32, green: 0.69, blue: 0.93) : Color.black.opacity(0.86)
        return Text(entry.level == 0 ? "–" : "\(entry.level)")
            .font(.system(size: max(9, size * 0.22), weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(atOverallMax || atTownHallMax ? Color.black : Color.white)
            .padding(.horizontal, max(2, size * 0.06))
            .padding(.vertical, 1)
            .background(fill, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.5), lineWidth: 0.7))
    }

    private func townHallTile(size: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14)
        let atMax = ProgressCatalog.maximumTownHallLevel > 0
            && townHall == ProgressCatalog.maximumTownHallLevel
        return ZStack {
            shape.fill(selectedBackground.isEmpty ? Color.accentColor.opacity(0.12) : Color.black.opacity(0.5))
            Image("town_hall/th\(max(1, min(townHall, max(1, ProgressCatalog.maximumTownHallLevel))))")
                .resizable()
                .scaledToFit()
                .padding(7)
                .frame(width: size, height: size)
            VStack {
                Spacer()
                HStack {
                    Text("TH \(townHall)")
                        .font(.system(size: max(12, size * 0.13), weight: .heavy, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(atMax ? maxLevelGold : Color.black.opacity(0.82),
                                    in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(atMax ? Color.black : Color.white)
                    Spacer()
                }
                .padding(6)
            }
        }
        .frame(width: size, height: size)
        .overlay(shape.stroke(Color.white.opacity(0.35), lineWidth: 1))
        .clipShape(shape)
        .accessibilityLabel("Town Hall level \(townHall)")
    }

    private func makePages(width: CGFloat, height: CGFloat) -> [Page] {
        let gridHeight = max(180, height - 132)
        let unitEntries = makeUnitEntries()
        let equipmentEntries = makeEquipmentEntries()
        var pages: [Page] = []
        for (kind, entries, target) in [(Page.Kind.units, unitEntries, 1), (.equipment, equipmentEntries, 1)] {
            guard !entries.isEmpty else { continue }
            let grid = Grid.best(for: entries.count, targetPages: target,
                                 width: width - inset * 2, height: gridHeight, spacing: spacing,
                                 featured: townHall > 0)
            let count = Int(ceil(Double(entries.count) / Double(grid.capacity)))
            let perPage = Int(ceil(Double(entries.count) / Double(count)))
            for offset in stride(from: 0, to: entries.count, by: perPage) {
                pages.append(Page(kind: kind, entries: Array(entries[offset..<min(offset + perPage, entries.count)]), grid: grid))
            }
        }
        return pages
    }

    private func makeUnitEntries() -> [Entry] {
        let ids = ["troops", "dark_troops", "siege_machines", "spells", "heroes", "pets", "guardians"]
        return ids.compactMap { id in ProgressCatalog.sections.first(where: { $0.id == id }) }
            .flatMap { section -> [Entry] in
                let inventory = section.inventory(in: export)
                return section.groups.flatMap(\.items).map { item in
                    let level = inventory[item.id]?.keys.max() ?? 0
                    return Entry(name: item.name, assetName: item.assetName(for: level), level: level,
                                 townHallMax: item.maxLevel(at: townHall),
                                 overallMax: item.levels.map(\.level).max() ?? 0, kind: .unit)
                }
            }
    }

    private func makeEquipmentEntries() -> [Entry] {
        let equipment = EquipmentDataStore.shared.entries
        let cached = EquipmentDataStore.apiLevels(in: cachedEquipment)
        let orderedHeroes = HeroConfigStore.shared.configs
        let heroNames = orderedHeroes.map(\.displayName) + Set(equipment.map(\.hero)).subtracting(Set(orderedHeroes.map(\.displayName))).sorted()
        return heroNames.flatMap { hero -> [Entry] in
            let items = equipment.filter { $0.hero == hero }
            return items.map { item in
                let level = cached[item.name.lowercased()] ?? 0
                return Entry(name: item.name, assetName: item.assetName, level: level,
                             townHallMax: 0, overallMax: item.rarity.maxLevel,
                             kind: item.rarity == .epic ? .epic : .common)
            }
        }
    }

    private struct Entry {
        enum Kind { case unit, common, epic }
        let name: String
        let assetName: String
        let level: Int
        let townHallMax: Int
        let overallMax: Int
        let kind: Kind
    }

    private struct PreviewRequest: Equatable {
        let format: ExportFormat
        let contentRevision: String
        let townHall: Int
        let equipment: [String]
        let hasBackground: Bool
        let scheme: String
        let playerName: String
        let playerTag: String
    }

    private struct BackgroundRequest: Hashable {
        let name: String
        let width: Int
        let height: Int
    }

    private struct Page {
        enum Kind { case units, equipment }
        let kind: Kind
        let entries: [Entry]
        let grid: Grid
    }

    private struct Grid {
        let columns: Int
        let rows: Int
        let tile: CGFloat
        let featured: Bool

        var capacity: Int { max(1, columns * rows - (featured ? 4 : 0)) }

        func entryIndex(for slot: Int) -> Int? {
            guard !featured else {
                let row = slot / columns
                let column = slot % columns
                if row < 2 && column >= columns - 2 { return nil }
                let skipped = row == 0 ? 0 : row == 1 ? 2 : 4
                return slot - skipped
            }
            return slot
        }

        static func best(for count: Int, targetPages: Int, width: CGFloat, height: CGFloat,
                         spacing: CGFloat, featured: Bool) -> Grid {
            let minimum: CGFloat = 26
            let candidates = (4...20).flatMap { columns in
                (4...20).compactMap { rows -> Grid? in
                    let byWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
                    let byHeight = (height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
                    let tile = floor(min(byWidth, byHeight))
                    guard tile >= minimum else { return nil }
                    return Grid(columns: columns, rows: rows, tile: tile, featured: featured)
                }
            }
            let bySize = candidates.sorted {
                if $0.tile != $1.tile { return $0.tile > $1.tile }
                return $0.columns > $1.columns
            }
            if let fitting = bySize.first(where: { $0.capacity * targetPages >= count }) {
                return fitting
            }
            if let largest = candidates.max(by: { $0.capacity < $1.capacity }) {
                return largest
            }
            let columns = 4
            let tile = max(30, floor((width - CGFloat(columns - 1) * spacing) / CGFloat(columns)))
            let rows = max(2, Int(floor((height + spacing) / (tile + spacing))))
            return Grid(columns: columns, rows: rows, tile: tile, featured: featured && rows >= 4)
        }
    }
}

private enum ScreenshotBackgrounds {
    // CIContext creation is expensive; it is safe to reuse across background tasks.
    nonisolated private static let context = CIContext(options: [.cacheIntermediates: false])
    nonisolated private static let images = ProgressImageCache(totalCostLimit: 32 * 1024 * 1024)

    static let names: [String] = {
        guard let url = Bundle.main.url(forResource: "ScreenshotBackgrounds", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).map(String.init)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }()

    nonisolated static func renderedImage(named name: String, size: CGSize) -> UIImage? {
        let key = "\(name)|\(size.width)|\(size.height)" as NSString
        if let cached = images.image(forKey: key) { return cached }
        guard let source = UIImage(named: name), source.size.width > 0, source.size.height > 0,
              size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1440 / max(size.width, size.height)
        format.opaque = true
        let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let scale = max(size.width / source.size.width, size.height / source.size.height)
            let width = source.size.width * scale
            let height = source.size.height * scale
            source.draw(in: CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                                   width: width, height: height))
        }
        guard let input = CIImage(image: thumbnail) else { return thumbnail }
        let desaturated = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.55])
        let blurred = desaturated.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 5 * format.scale])
        guard let output = context.createCGImage(blurred.cropped(to: input.extent), from: input.extent) else {
            return thumbnail
        }
        let result = UIImage(cgImage: output, scale: format.scale, orientation: .up)
        images.insert(result, forKey: key, cost: output.bytesPerRow * output.height)
        return result
    }
}

private struct ProgressExportShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
