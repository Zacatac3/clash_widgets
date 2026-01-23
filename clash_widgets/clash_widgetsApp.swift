//
//  clash_widgetsApp.swift
//  clash_widgets
//
//  Created by Zachary Buschmann on 1/7/26.
//

import SwiftUI
import WidgetKit
import GoogleMobileAds
import AppTrackingTransparency
import AdSupport

@main
struct ClashboardApp: App {
    @StateObject private var iapManager = IAPManager.shared
    
    init() {
        print("🚀 App Init Started")
        // Start Google Mobile Ads early so ad views don't request before initialization.
        // Ensure test-device registration is cleared for production
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = []
        
        MobileAds.shared.start { _ in
            NSLog("🚀 [ADMOB_DEBUG] AdMob Initialized ✅ (init)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(iapManager)
                .onAppear {
                    // Slight delay to ensure UI is ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        NSLog("🚀 [ADMOB_DEBUG] Requesting tracking...")
                        ATTrackingManager.requestTrackingAuthorization { status in
                            let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
                            NSLog("🚀 [ADMOB_DEBUG] IDFA: \(idfa)")
                            NSLog("🚀 [ADMOB_DEBUG] STATUS: \(status.rawValue)")
                            
                            // Ensure test device identifiers are empty for production
                            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = []

                            // AdMob already started in init; we keep ATT handling here.
                        }
                    }
                }
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
