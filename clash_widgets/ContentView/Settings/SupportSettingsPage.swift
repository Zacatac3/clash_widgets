import SwiftUI
import StoreKit

struct SupportSettingsPage: View {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL

    let onOpenFeedback: () -> Void
    let onRevealDebug: () -> Void
    let appStoreReviewURL: URL?

    var body: some View {
        Form {
            Section("Feedback") {
                Button {
                    onOpenFeedback()
                } label: {
                    Label("Open Feedback Form", systemImage: "doc.text.magnifyingglass")
                }

                Text("Report bugs, glitches, or share ideas.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 3) { onRevealDebug() }
            }

            Section("App Store") {
                Button {
                    requestReview()
                } label: {
                    Label("Leave an In-App Review", systemImage: "star.bubble")
                }

                if let appStoreReviewURL {
                    Button {
                        openURL(appStoreReviewURL)
                    } label: {
                        Label("Open App Store Review Page", systemImage: "arrow.up.forward.app")
                    }
                }

                Text("If Apple shows the in-app prompt, you can leave a rating without leaving Clashboard.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Support")
    }
}
