import SwiftUI

struct AppBehaviorSettingsPage: View {
    @EnvironmentObject private var dataService: DataService
    @AppStorage("globalShowFullTimerPrecision") private var globalShowFullTimerPrecision = false

    var body: some View {
        Form {
            Section("Profile-Specific") {
                Toggle("Monthly Gold Pass reminder", isOn: $dataService.goldPassReminderEnabled)
                    .tint(.accentColor)
                Text("Profile-specific: At season reset (08:00 UTC), Clashboard asks you to confirm Gold Pass boost for the currently selected profile.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Global") {
                Toggle("Show full timer precision", isOn: $globalShowFullTimerPrecision)
                    .tint(.accentColor)
                Text("Global: Displays full countdown to the nearest second on all timers.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Paste Settings") {
                Button {
                    openAppSettings()
                } label: {
                    Label("Open App Settings", systemImage: "gearshape")
                }

                Text("Global: To stop the paste prompt, go to Settings → Apps → Clashboard → Paste From Other Apps and set it to Allow.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("App Behavior")
    }

    private func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}
