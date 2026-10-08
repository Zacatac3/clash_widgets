import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private func inlineImageMaxWidth(for pageWidth: CGFloat, sizeClass: UserInterfaceSizeClass?) -> CGFloat {
    (sizeClass == .regular || pageWidth >= 400) ? pageWidth * 0.6 : .infinity
}

struct InfoSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedPage: InfoSheetPage
    let sections: [WhatsNewSection]

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
                    WhatsNewContent(sections: sections)
                        .tag(InfoSheetPage.whatsNew)
                    RemoteNewsListView()
                        .tag(InfoSheetPage.news)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle(selectedPage.rawValue)
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
    let sections: [WhatsNewSection]

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showMissingChangelogAlert = false
    @AppStorage("fullChangelogURL") private var fullChangelogURL: String = "https://zacatac3.github.io/changelog"

    var body: some View {
        GeometryReader { geometry in
          ScrollView {
            VStack(spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("What’s New")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Full Changelog") {
                        if let url = URL(string: fullChangelogURL), !fullChangelogURL.isEmpty {
                            UIApplication.shared.open(url)
                        } else {
                            showMissingChangelogAlert = true
                        }
                    }
                    .buttonStyle(.bordered)
                }

                LazyVStack(spacing: 12) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.dateLabel)
                                .font(.headline)

                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(section.bullets, id: \.self) { bullet in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•")
                                        Text(bullet)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }

                                    if let inlineImageName = whatsNewInlineImageName(for: bullet, in: section) {
                                        whatsNewInlineImage(name: inlineImageName, maxWidth: inlineImageMaxWidth(for: geometry.size.width, sizeClass: horizontalSizeClass))
                                            .padding(.top, 2)
                                    }
                                }
                            }
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
        .alert("Changelog URL not configured", isPresented: $showMissingChangelogAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Set the full changelog URL in Settings to enable this link.")
        }
    }

    private func whatsNewInlineImageName(for bullet: String, in section: WhatsNewSection) -> String? {
        if section.dateLabel.contains("1.3") {
            let normalized = bullet.lowercased()
            if normalized.contains("share progress") {
                return "share_progress"
            }
            if normalized.contains("new progress tab") || normalized.contains("progress (beta)") {
                return "progress"
            }
        }
        if section.dateLabel.contains("2/24/2026") {
            let normalized = bullet.lowercased()
            if normalized.contains("boost") && normalized.contains("custom") {
                return "custom_boosts"
            }
            if normalized.contains("hide") && normalized.contains("equipment") {
                return "equipment"
            }
            if normalized.contains("dragon duke") {
                return "duke"
            }
        }

        guard section.dateLabel.contains("2/8/2026") else { return nil }
        let normalized = bullet.lowercased()
        if normalized.contains("lock screen") {
            return "lock_screen"
        }
        if normalized.contains("current war") {
            return "war_section"
        }
        if normalized.contains("boost") {
            return "boosts"
        }
        return nil
    }

    @ViewBuilder
    private func whatsNewInlineImage(name: String, maxWidth: CGFloat) -> some View {
        #if canImport(UIKit)
        if let uiImage = resolveWhatsNewImage(name: name) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: maxWidth)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        #endif
    }

    #if canImport(UIKit)
    private func resolveWhatsNewImage(name: String) -> UIImage? {
        if let image = UIImage(named: "changelog/\(name)")
            ?? UIImage(named: "images/\(name)")
            ?? UIImage(named: name) {
            return image
        }

        let exts = ["png", "jpg", "jpeg", "webp"]
        let subdirectories = ["assets/changelog", "changelog", "assets"]
        for subdirectory in subdirectories {
            for ext in exts {
                if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory),
                   let image = UIImage(contentsOfFile: url.path) {
                    return image
                }
            }
        }
        return nil
    }
    #endif
}

private struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    let sections: [WhatsNewSection]

    var body: some View {
        NavigationStack {
            WhatsNewContent(sections: sections)
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

private struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var changelogEntries: [ChangelogEntry] = []

    private enum ChangelogEntry: Identifiable {
        case heading(String)
        case sectionTitle(String)
        case bullet(String)
        case paragraph(String)
        case image(String)

        var id: String {
            switch self {
            case .heading(let text):
                return "heading:\(text)"
            case .sectionTitle(let text):
                return "section:\(text)"
            case .bullet(let text):
                return "bullet:\(text)"
            case .paragraph(let text):
                return "paragraph:\(text)"
            case .image(let name):
                return "image:\(name)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
              ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(changelogEntries.enumerated()), id: \.offset) { _, entry in
                        switch entry {
                        case .heading(let text):
                            Text(text)
                                .font(.title3.weight(.bold))
                                .padding(.top, 8)
                        case .sectionTitle(let text):
                            Text(text)
                                .font(.headline)
                                .padding(.top, 6)
                        case .bullet(let text):
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                Text(text)
                            }
                            .font(.body)
                        case .paragraph(let text):
                            Text(text)
                                .font(.body)
                                .foregroundColor(.secondary)
                        case .image(let imageName):
                            changelogInlineImage(name: imageName, maxWidth: inlineImageMaxWidth(for: geometry.size.width, sizeClass: horizontalSizeClass))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
              }
            }
            .navigationTitle("Changelog")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                loadChangelog()
            }
        }
    }

    private func loadChangelog() {
        if let url = Bundle.main.url(forResource: "changelog", withExtension: "txt"),
           let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            changelogEntries = parseChangelogEntries(text)
        } else {
            changelogEntries = [.paragraph("Changelog not available.")]
        }
    }

    private func parseChangelogEntries(_ text: String) -> [ChangelogEntry] {
        let lines = text.components(separatedBy: .newlines)
        var entries: [ChangelogEntry] = []
        var lastEntryWasBullet = false

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                lastEntryWasBullet = false
                continue
            }

            if line.first?.isNumber == true && line.contains(" - ") {
                entries.append(.heading(line))
                lastEntryWasBullet = false
                continue
            }

            if line.hasPrefix("*") && line.hasSuffix("*") {
                let title = line.trimmingCharacters(in: CharacterSet(charactersIn: "*"))
                entries.append(.sectionTitle(title))
                lastEntryWasBullet = false
                continue
            }

            if line.hasPrefix("-") {
                let bullet = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                let inferredImage = changelogImageName(forBullet: bullet)

                entries.append(.bullet(bullet))
                if let inferredImage {
                    entries.append(.image(inferredImage))
                }
                lastEntryWasBullet = true
                continue
            }

            if lastEntryWasBullet, let markerImage = changelogImageName(fromMarkerLine: line) {
                entries.append(.image(markerImage))
                continue
            }

            if let standaloneMarkerImage = changelogImageName(fromMarkerLine: line) {
                if let lastIndex = entries.indices.last,
                   case .bullet = entries[lastIndex] {
                    entries.append(.image(standaloneMarkerImage))
                } else {
                    entries.append(.paragraph(line))
                }
                continue
            }

            entries.append(.paragraph(line))
            lastEntryWasBullet = false
        }

        return entries
    }

    private func changelogImageName(forBullet bullet: String) -> String? {
        let normalized = bullet.lowercased()
        if normalized.contains("lock screen") {
            return "lock_screen"
        }
        if normalized.contains("current war") {
            return "war_section"
        }
        if normalized.contains("customiz") && normalized.contains("boost") {
            return "custom_boosts"
        }
        if normalized.contains("boost") {
            return "boosts"
        }
        return nil
    }

    private func changelogImageName(fromMarkerLine line: String) -> String? {
        let lowercased = line.lowercased()
        let cleaned: String

        if lowercased.hasPrefix("image:") {
            cleaned = String(line.dropFirst("image:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if lowercased.hasPrefix("img:") {
            cleaned = String(line.dropFirst("img:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if lowercased.hasPrefix("[image:") && line.hasSuffix("]") {
            cleaned = String(line.dropFirst("[image:".count).dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            cleaned = line
        }

        let name = cleaned
            .replacingOccurrences(of: "images/", with: "")
            .replacingOccurrences(of: "changelog/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-*[]() "))
            .replacingOccurrences(of: ".png", with: "")
            .replacingOccurrences(of: ".jpg", with: "")
            .replacingOccurrences(of: ".jpeg", with: "")
            .replacingOccurrences(of: ".webp", with: "")

        let knownImageNames: Set<String> = ["lock_screen", "war_section", "boosts", "custom_boosts", "equipment", "duke", "progress", "share_progress"]
        return knownImageNames.contains(name) ? name : nil
    }

    @ViewBuilder
    private func changelogInlineImage(name: String, maxWidth: CGFloat) -> some View {
        #if canImport(UIKit)
        if let uiImage = resolveChangelogImage(name: name) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: maxWidth)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
                Text(name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #else
        EmptyView()
        #endif
    }

    #if canImport(UIKit)
    private func resolveChangelogImage(name: String) -> UIImage? {
        let cleanedName = name
            .replacingOccurrences(of: "images/", with: "")
            .replacingOccurrences(of: "changelog/", with: "")
            .replacingOccurrences(of: ".png", with: "")
            .replacingOccurrences(of: ".jpg", with: "")
            .replacingOccurrences(of: ".jpeg", with: "")
            .replacingOccurrences(of: ".webp", with: "")

        if let assetImage = UIImage(named: "images/\(cleanedName)")
            ?? UIImage(named: "changelog/\(cleanedName)")
            ?? UIImage(named: cleanedName)
            ?? UIImage(named: name) {
            return assetImage
        }

        let extensions = ["png", "jpg", "jpeg", "webp"]
        let subdirectories = ["assets/changelog", "changelog", "assets"]

        for subdirectory in subdirectories {
            for fileExtension in extensions {
                if let url = Bundle.main.url(forResource: cleanedName, withExtension: fileExtension, subdirectory: subdirectory),
                   let image = UIImage(contentsOfFile: url.path) {
                    return image
                }
            }
        }

        return nil
    }
    #endif
}

struct HelpSheetView: View {
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

struct HelpSheetContent: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to Clashboard")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("Follow these steps to sync your village data.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader(title: "Getting Started", icon: "arrow.down.doc.fill")

                    stepRow(number: "1", text: "Press the Open Game settings button or Open Clash of Clans and go to Settings.")
                    stepRow(number: "2", text: "In More Settings, scroll to the bottom, and tap Export JSON Data.")
                    stepRow(number: "3", text: "Return here and tap Paste and Import Data.")
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(title: "Fixing 'Allow Paste' Popups", icon: "doc.on.clipboard")
                    Text("To stop the manual paste prompt, enable 'Allow' in System Settings.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Button(action: {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Label("Open App Settings", systemImage: "gearshape.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundColor(.white)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.accentColor.opacity(0.3), lineWidth: 1))

                helpCard(title: "Managing Profiles", icon: "person.2.fill", bullets: [
                    "Switch players by tapping the Switch Profile button in the top-right.",
                    "Edit or rename profiles within the Settings menu.",
                    "Delete a profile by swiping left on its row in Settings."
                ])

                helpCard(title: "Live Widgets", icon: "square.grid.2x2.fill", bullets: [
                    "Add Clashboard widgets to your Home Screen for quick tracking.",
                    "Widgets refresh every time you import fresh data.",
                    "Import again once an upgrade finishes to keep timers accurate."
                ])

                VStack(alignment: .center, spacing: 8) {
                    Text("Disclaimer")
                        .font(.headline)
                    Text("Clashboard is still in active development. If something breaks, please use the Feedback Form in Settings.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(title)
                .font(.headline)
        }
    }

    @ViewBuilder
    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.blue))
            Text(text)
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private func helpCard(title: String, icon: String? = nil, description: String? = nil, bullets: [String] = []) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                Text(title)
                    .font(.headline)
            }
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

struct FirstImportTipSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)

                    VStack(spacing: 8) {
                        Text("Tired of \"Allow Paste\"?")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("We understand! To avoid the constant paste permission popup:")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "1.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open Settings")
                                .fontWeight(.semibold)
                            Text("Go to Settings → Apps → Clashboard")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "2.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Find Paste Setting")
                                .fontWeight(.semibold)
                            Text("Look for \"Paste From Other Apps\"")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "3.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Set to Allow")
                                .fontWeight(.semibold)
                            Text("Change the setting to \"Allow\" and you're done!")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.quaternarySystemFill)))

                Spacer()

                VStack(spacing: 8) {
                    Button(action: openAppSettings) {
                        Text("Open App Settings")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    Button(action: { isPresented = false }) {
                        Text("Got It")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                }
            }
            .padding()
            .navigationTitle("Paste Tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Dismiss") {
                        isPresented = false
                    }
                }
            }
        }
    }

    private func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}
