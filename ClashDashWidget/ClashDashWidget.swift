//
//  ClashDashWidget.swift
//  ClashDashWidget
//
//  Created by Zachary Buschmann on 1/7/26.
//

import WidgetKit
import SwiftUI

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
        let sharedDefaults = UserDefaults(suiteName: appGroup)
        guard let data = sharedDefaults?.data(forKey: "saved_upgrades"),
              let decoded = try? JSONDecoder().decode([BuildingUpgrade].self, from: data) else {
            return []
        }
        // Only show builder-related upgrades in the widget and cap to 6 items
        let builderRelated = decoded.filter { $0.category == .builderVillage || $0.category == .builderBase }
        let sorted = builderRelated.sorted(by: { $0.endTime < $1.endTime })
        return Array(sorted.prefix(6))
    }
    
    private func loadDebugText() -> String {
        let sharedDefaults = UserDefaults(suiteName: appGroup)
        return sharedDefaults?.string(forKey: "widget_simple_text") ?? "No dash data"
    }
}

// MARK: - Views
struct ClashDashWidgetEntryView : View {
    var entry: Provider.Entry
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(spacing: 4) {
            // Header
            HStack {
                Text("Builders")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Text(entry.debugText)
                    .font(.system(size: 8))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            // 3x2 Grid for 6 Builders
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0..<6) { index in
                    builderCell(for: index)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            
            Spacer(minLength: 0)
        }
        .widgetURL(URL(string: "clashdash://refresh"))
    }
    
    @ViewBuilder
    private func builderCell(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if index < entry.upgrades.count {
                let upgrade = entry.upgrades[index]
                Text(upgrade.name)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                Text(upgrade.timeRemaining)
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
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
        .padding(6)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(6)
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

