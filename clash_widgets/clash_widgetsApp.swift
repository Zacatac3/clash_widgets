//
//  clash_widgetsApp.swift
//  clash_widgets
//
//  Created by Zachary Buschmann on 1/7/26.
//

import SwiftUI
import WidgetKit

@main
struct clash_widgetsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // Force a widget refresh whenever the app is opened via the widget
                    WidgetCenter.shared.reloadAllTimelines()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Also refresh when app comes to foreground normally
                    WidgetCenter.shared.reloadAllTimelines()
                }
        }
    }
}
