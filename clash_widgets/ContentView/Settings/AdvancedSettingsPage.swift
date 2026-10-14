import SwiftUI

struct AdvancedSettingsPage: View {
    let onResetLayout: () -> Void
    let onFactoryReset: () -> Void
    @State private var showResetLayoutConfirmation = false
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section("Layout") {
                Button(role: .destructive) {
                    showResetLayoutConfirmation = true
                } label: {
                    Label("Reset Home/Profile Layout", systemImage: "rectangle.3.group.bubble")
                }

                Text("Resets home/profile card order & visibility and clears hidden equipment. Leaves all profile data and settings intact.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Maintenance") {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Reset to Factory Defaults", systemImage: "arrow.uturn.backward")
                        .symbolRenderingMode(.monochrome)
                }
            }
        }
        .navigationTitle("Advanced")
        .alert("Reset Clashboard?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive, action: onFactoryReset)
        } message: {
            Text("All profiles, timers, and settings will be erased. You'll need to import your village or enter your player tag again.")
        }
        .alert("Reset Layout?", isPresented: $showResetLayoutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Layout", role: .destructive, action: onResetLayout)
        } message: {
            Text("This resets home/profile card order and visibility, plus hidden equipment. Your profiles and tracked data stay intact.")
        }
    }
}
