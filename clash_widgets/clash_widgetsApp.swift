//
//  clash_widgetsApp.swift
//  clash_widgets
//
//  Created by Zachary Buschmann on 1/7/26.
//

import SwiftUI
import WidgetKit
import GoogleMobileAds
import UserMessagingPlatform
import AppTrackingTransparency
import AdSupport
import Combine

@main
struct ClashboardApp: App {
    @StateObject private var iapManager = IAPManager.shared
    private let adConsentManager = AdConsentManager.shared
    
    init() {
        print("🚀 App Init Started")
        // Ensure test-device registration is cleared for production
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = []
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(iapManager)
                .onAppear {
                    // Request EU consent first
                    adConsentManager.gatherConsent()
                    
                    // Slight delay to ensure UI is ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        NSLog("🚀 [ADMOB_DEBUG] Requesting tracking...")
                        ATTrackingManager.requestTrackingAuthorization { status in
                            let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
                            NSLog("🚀 [ADMOB_DEBUG] IDFA: \(idfa)")
                            NSLog("🚀 [ADMOB_DEBUG] STATUS: \(status.rawValue)")
                            
                            // Ensure test device identifiers are empty for production
                            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = []
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

// MARK: - Ad Consent Manager (EU Compliance)
class AdConsentManager {
    static let shared = AdConsentManager()

    func gatherConsent() {
        let parameters = RequestParameters()
        
        // Uncomment for testing EU consent flow on simulator:
        // let debugSettings = DebugSettings()
        // debugSettings.testDeviceIdentifiers = ["YOUR_TEST_ID"]
        // debugSettings.geography = .EEA
        // parameters.debugSettings = debugSettings

        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
            if let error = error {
                NSLog("🚀 [UMP_ERROR] \(error.localizedDescription)")
                return
            }

            // This only shows if consent is required (e.g., first launch in EU)
            ConsentForm.loadAndPresentIfRequired(from: nil) { loadError in
                if let loadError = loadError {
                    NSLog("🚀 [UMP_LOAD_ERROR] \(loadError.localizedDescription)")
                    return
                }

                // Once consent is collected or not needed, start AdMob
                if ConsentInformation.shared.canRequestAds {
                    NSLog("🚀 [ADMOB_DEBUG] AdMob Initialized ✅ (after consent)")
                    MobileAds.shared.start()
                }
            }
        }
    }
}
