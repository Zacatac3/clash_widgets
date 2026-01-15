//
//  ClashDashWidget.swift
//  ClashDashWidget
//
//  Created by Zachary Buschmann on 1/7/26.
//

import WidgetKit
import SwiftUI
import UIKit

struct SimpleEntry: TimelineEntry {
    let date: Date
    let upgrades: [BuildingUpgrade]
    let debugText: String
}

struct Provider: TimelineProvider {
    let appGroup = "group.Zachary-Buschmann.clash-widgets"

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), upgrades: [], debugText: "Placeholder")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let upgrades = loadUpgrades()
        let text = loadDebugText()
        let entry = SimpleEntry(date: Date(), upgrades: upgrades, debugText: text)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let upgrades = loadUpgrades()
        let text = loadDebugText()
        let entry = SimpleEntry(date: Date(), upgrades: upgrades, debugText: text)

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func loadUpgrades() -> [BuildingUpgrade] {
        if let state = PersistentStore.loadState() {
            return prioritized(upgrades: state.activeUpgrades)
        }

        let sharedDefaults = UserDefaults(suiteName: appGroup)
        guard let data = sharedDefaults?.data(forKey: "saved_upgrades"),
              let decoded = try? JSONDecoder().decode([BuildingUpgrade].self, from: data) else {
            return []
        }
        return prioritized(upgrades: decoded)
    }
    
    private func loadDebugText() -> String {
        if let state = PersistentStore.loadState() {
            let name = state.widgetDisplayName
            return name.isEmpty ? "No dash data" : name
        }
        let sharedDefaults = UserDefaults(suiteName: appGroup)
        return sharedDefaults?.string(forKey: "widget_simple_text") ?? "No dash data"
    }

    private func prioritized(upgrades: [BuildingUpgrade]) -> [BuildingUpgrade] {
        return Array(
            upgrades
                .filter { $0.category == .builderVillage }
                .sorted(by: { $0.endTime < $1.endTime })
                .prefix(6)
        )
    }
}

// MARK: - Views
struct ClashDashWidgetEntryView : View {
    var entry: Provider.Entry
    
    let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        VStack(spacing: 8) {
            // No header: compact top spacing
            Spacer().frame(height: 6)

            // 3x2 Grid for 6 Builders (3 columns x 2 rows)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<6) { index in
                    builderCell(for: index)
                        .frame(minHeight: 56)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            
            // Status line (always visible) — moved closer to grid
            HStack {
                Spacer()
                if entry.upgrades.count >= 6 {
                    Text("All Builders Busy")
                        .font(.caption2)
                        .foregroundColor(Color.green)
                        .bold()
                } else {
                    let free = 6 - entry.upgrades.count
                    let noun = free == 1 ? "builder" : "builders"
                    Text("\(free) \(noun) free!")
                        .font(.caption2)
                        .foregroundColor(Color.orange)
                        .bold()
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .padding(.vertical, 6)
        .widgetURL(URL(string: "clashdash://refresh"))
    }
    
    @ViewBuilder
    private func builderCell(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
                if index < entry.upgrades.count {
                let upgrade = entry.upgrades[index]

                // icon + level
                HStack(spacing: 6) {
                    Image(iconName(for: upgrade))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(upgrade.name)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                        Text("Lv \(upgrade.targetLevel - 1) → \(upgrade.targetLevel)")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }

                // time remaining
                Text(upgrade.timeRemaining)
                    .font(.system(size: 9))
                    .foregroundColor(.orange)

                // progress bar (thin)
                ProgressView(value: progressFraction(for: upgrade))
                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
                    .frame(height: 4)
            } else {
                Text("Builder \(index + 1)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.gray.opacity(0.5))
                Text("Available")
                    .font(.system(size: 10))
                    .foregroundColor(.green.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func progressFraction(for upgrade: BuildingUpgrade) -> Double {
        let total = max(upgrade.totalDuration, 1)
        let elapsed = Date().timeIntervalSince(upgrade.startTime)
        if elapsed <= 0 { return 0 }
        return min(max(elapsed / total, 0.0), 1.0)
    }

    private func iconName(for upgrade: BuildingUpgrade) -> String {
        let folder: String
        switch upgrade.category {
        case .builderVillage: folder = "buildings_home"
        case .lab: folder = "lab"
        case .pets: folder = "pets"
        case .builderBase: folder = "builder_base"
        }

        func sanitize(_ s: String) -> String {
            return s.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .joined(separator: "_")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        }

        let nameLower = sanitize(upgrade.name.lowercased())
        let nameOriginal = sanitize(upgrade.name)
        
        let variations = [
            "\(folder)/\(nameOriginal)",
            "\(folder)/\(nameLower)",
            "\(folder)_\(nameOriginal)",
            "\(folder)_\(nameLower)",
            nameOriginal,
            nameLower
        ]
        
        for variant in variations {
            if UIImage(named: variant) != nil {
                return variant
            }
        }
        return "\(folder)/\(nameLower)"
    }
}

struct ClashDashWidget: Widget {
    let kind: String = "ClashDashWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                ClashDashWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                ClashDashWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Clash Builders")
        .description("Track your building upgrades.")
        .supportedFamilies([.systemMedium])
    }
}

#Preview(as: .systemMedium) {
    ClashDashWidget()
} timeline: {
    SimpleEntry(date: Date(), upgrades: [], debugText: "Preview")
}


// MARK: - Small Widgets

struct LabPetProvider: TimelineProvider {
    let appGroup = "group.Zachary-Buschmann.clash-widgets"

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), upgrades: [], debugText: "LabPet")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let upgrades = loadUpgrades()
        let entry = SimpleEntry(date: Date(), upgrades: upgrades, debugText: "LabPet")
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let upgrades = loadUpgrades()
        let entry = SimpleEntry(date: Date(), upgrades: upgrades, debugText: "LabPet")
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadUpgrades() -> [BuildingUpgrade] {
        if let state = PersistentStore.loadState() {
            return filtered(upgrades: state.activeUpgrades)
        }

        let sharedDefaults = UserDefaults(suiteName: appGroup)
        guard let data = sharedDefaults?.data(forKey: "saved_upgrades"),
              let decoded = try? JSONDecoder().decode([BuildingUpgrade].self, from: data) else {
            return []
        }
        return filtered(upgrades: decoded)
    }

    private func filtered(upgrades: [BuildingUpgrade]) -> [BuildingUpgrade] {
        let filtered = upgrades.filter { $0.category == .lab || $0.category == .pets }
            .sorted(by: { $0.endTime < $1.endTime })
        return Array(filtered.prefix(2))
    }
}

struct LabPetWidgetEntryView: View {
    var entry: LabPetProvider.Entry
    let maxSlots = 2

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<maxSlots, id: \.self) { index in
                cell(for: index)
            }

            HStack {
                Spacer()
                if entry.upgrades.count >= maxSlots {
                    Text("All Busy")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.green)
                } else {
                    let free = maxSlots - entry.upgrades.count
                    Text("\(free) free")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.orange)
                }
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(6)
        .widgetURL(URL(string: "clashdash://refresh"))
    }

    @ViewBuilder
    private func cell(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if index < entry.upgrades.count {
                let upgrade = entry.upgrades[index]
                HStack(spacing: 6) {
                    Image(iconName(for: upgrade))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(upgrade.name)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Text("Lv \(upgrade.targetLevel - 1) → \(upgrade.targetLevel)")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(upgrade.timeRemaining)
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }

                ProgressView(value: progressFraction(for: upgrade))
                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
                    .frame(height: 3)
            } else {
                HStack {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("Available")
                        .font(.system(size: 11))
                        .foregroundColor(.green.opacity(0.7))
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func progressFraction(for upgrade: BuildingUpgrade) -> Double {
        let total = max(upgrade.totalDuration, 1)
        let elapsed = Date().timeIntervalSince(upgrade.startTime)
        if elapsed <= 0 { return 0 }
        return min(max(elapsed / total, 0.0), 1.0)
    }

    private func iconName(for upgrade: BuildingUpgrade) -> String {
        let folder: String
        switch upgrade.category {
        case .builderVillage: folder = "buildings_home"
        case .lab: folder = "lab"
        case .pets: folder = "pets"
        case .builderBase: folder = "builder_base"
        }

        func sanitize(_ s: String) -> String {
            return s.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .joined(separator: "_")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        }

        let nameLower = sanitize(upgrade.name.lowercased())
        let nameOriginal = sanitize(upgrade.name)
        
        let variations = [
            "\(folder)/\(nameOriginal)",
            "\(folder)/\(nameLower)",
            "\(folder)_\(nameOriginal)",
            "\(folder)_\(nameLower)",
            nameOriginal,
            nameLower
        ]
        
        for variant in variations {
            if UIImage(named: variant) != nil {
                return variant
            }
        }
        return "\(folder)/\(nameLower)"
    }
}

struct LabPetWidget: Widget {
    let kind: String = "LabPetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LabPetProvider()) { entry in
            if #available(iOS 17.0, *) {
                LabPetWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                LabPetWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Lab & Pets")
        .description("Track your laboratory and pet house upgrades.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    LabPetWidget()
} timeline: {
    SimpleEntry(date: Date(), upgrades: [], debugText: "Preview")
}

// Builder Base small widget (up to 3 slots)
struct BuilderBaseProvider: TimelineProvider {
    let appGroup = "group.Zachary-Buschmann.clash-widgets"

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), upgrades: [], debugText: "BuilderBase")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let upgrades = loadUpgrades()
        let entry = SimpleEntry(date: Date(), upgrades: upgrades, debugText: "BuilderBase")
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let upgrades = loadUpgrades()
        let entry = SimpleEntry(date: Date(), upgrades: upgrades, debugText: "BuilderBase")
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadUpgrades() -> [BuildingUpgrade] {
        let sharedDefaults = UserDefaults(suiteName: appGroup)
        guard let data = sharedDefaults?.data(forKey: "saved_upgrades"),
              let decoded = try? JSONDecoder().decode([BuildingUpgrade].self, from: data) else {
            return []
        }
        return Array(
            decoded
                .filter { $0.category == .builderBase }
                .sorted(by: { $0.endTime < $1.endTime })
                .prefix(3)
        )
    }
}

struct BuilderBaseWidgetEntryView: View {
    var entry: BuilderBaseProvider.Entry
    let maxSlots = 3

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<maxSlots, id: \.self) { index in
                cell(for: index)
            }

            HStack {
                Spacer()
                if entry.upgrades.count >= maxSlots {
                    Text("All Busy")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.green)
                } else {
                    let free = maxSlots - entry.upgrades.count
                    Text("\(free) free")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.orange)
                }
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(6)
        .widgetURL(URL(string: "clashdash://refresh"))
    }

    @ViewBuilder
    private func cell(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if index < entry.upgrades.count {
                let upgrade = entry.upgrades[index]
                HStack(spacing: 6) {
                    Image(iconName(for: upgrade))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(upgrade.name)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                        Text("Lv \(upgrade.targetLevel - 1) → \(upgrade.targetLevel)")
                            .font(.system(size: 7))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(upgrade.timeRemaining)
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                        .bold()
                }

                ProgressView(value: progressFraction(for: upgrade))
                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
                    .frame(height: 2)
            } else {
                HStack {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.gray.opacity(0.4))
                    Text("Available")
                        .font(.system(size: 10))
                        .foregroundColor(.green.opacity(0.6))
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func progressFraction(for upgrade: BuildingUpgrade) -> Double {
        let total = max(upgrade.totalDuration, 1)
        let elapsed = Date().timeIntervalSince(upgrade.startTime)
        if elapsed <= 0 { return 0 }
        return min(max(elapsed / total, 0.0), 1.0)
    }

    private func iconName(for upgrade: BuildingUpgrade) -> String {
        let folder: String
        switch upgrade.category {
        case .builderVillage: folder = "buildings_home"
        case .lab: folder = "lab"
        case .pets: folder = "pets"
        case .builderBase: folder = "builder_base"
        }

        func sanitize(_ s: String) -> String {
            return s.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .joined(separator: "_")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        }

        let nameLower = sanitize(upgrade.name.lowercased())
        let nameOriginal = sanitize(upgrade.name)
        
        let variations = [
            "\(folder)/\(nameOriginal)",
            "\(folder)/\(nameLower)",
            "\(folder)_\(nameOriginal)",
            "\(folder)_\(nameLower)",
            nameOriginal,
            nameLower
        ]
        
        for variant in variations {
            if UIImage(named: variant) != nil {
                return variant
            }
        }
        return "\(folder)/\(nameLower)"
    }
}

struct BuilderBaseWidget: Widget {
    let kind: String = "BuilderBaseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BuilderBaseProvider()) { entry in
            if #available(iOS 17.0, *) {
                BuilderBaseWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                BuilderBaseWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Builder Base")
        .description("Track your Builder Base upgrades.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    BuilderBaseWidget()
} timeline: {
    SimpleEntry(date: Date(), upgrades: [], debugText: "Preview")
}

