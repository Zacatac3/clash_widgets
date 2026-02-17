import SwiftUI

struct AdvancedSettingsPage: View {
    let onResetLayout: () -> Void
    let onFactoryReset: () -> Void

    var body: some View {
        Form {
            Section("Layout") {
                Button(role: .destructive) {
                    onResetLayout()
                } label: {
                    Label("Reset Home/Profile Layout", systemImage: "rectangle.3.group.bubble")
                }

                Text("Resets home/profile card order & visibility and clears hidden equipment. Leaves all profile data and settings intact.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Maintenance") {
                Button(role: .destructive) {
                    onFactoryReset()
                } label: {
                    Label("Reset to Factory Defaults", systemImage: "arrow.uturn.backward")
                        .symbolRenderingMode(.monochrome)
                }
            }
        }
        .navigationTitle("Advanced")
    }
}
