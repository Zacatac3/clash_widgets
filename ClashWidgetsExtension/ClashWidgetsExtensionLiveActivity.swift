//
//  ClashWidgetsExtensionLiveActivity.swift
//  ClashWidgetsExtension
//
//  Created by Zachary Buschmann on 1/7/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct ClashWidgetsExtensionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct ClashWidgetsExtensionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClashWidgetsExtensionAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension ClashWidgetsExtensionAttributes {
    fileprivate static var preview: ClashWidgetsExtensionAttributes {
        ClashWidgetsExtensionAttributes(name: "World")
    }
}

extension ClashWidgetsExtensionAttributes.ContentState {
    fileprivate static var smiley: ClashWidgetsExtensionAttributes.ContentState {
        ClashWidgetsExtensionAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: ClashWidgetsExtensionAttributes.ContentState {
         ClashWidgetsExtensionAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: ClashWidgetsExtensionAttributes.preview) {
   ClashWidgetsExtensionLiveActivity()
} contentStates: {
    ClashWidgetsExtensionAttributes.ContentState.smiley
    ClashWidgetsExtensionAttributes.ContentState.starEyes
}
