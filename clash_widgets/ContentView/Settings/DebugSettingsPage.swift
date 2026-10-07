import SwiftUI

struct DebugSettingsPage: View {
    @EnvironmentObject private var dataService: DataService
    @ObservedObject private var remoteContent = RemoteContentService.shared
    @State private var manualRefreshInProgress = false
    @State private var remoteRefreshStatus: String?
    @State private var remoteRefreshFailed = false

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await grabRemoteFiles() }
                } label: {
                    HStack {
                        Label("Grab Remote Files Now", systemImage: "arrow.down.doc")
                        Spacer()
                        if manualRefreshInProgress || remoteContent.isRefreshing {
                            ProgressView()
                        }
                    }
                }
                .disabled(manualRefreshInProgress || remoteContent.isRefreshing)

                if let remoteRefreshStatus {
                    Text(remoteRefreshStatus)
                        .font(.caption)
                        .foregroundStyle(remoteRefreshFailed ? Color.red : Color.secondary)
                }
                Text("Cached: \(remoteContent.events.count) events · \(remoteContent.news.count) news articles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(remoteContent.baseURL?.absoluteString ?? "Remote content URL is not configured.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } header: {
                Text("Remote Content")
            } footer: {
                Text("Downloads the events, latest-news pointer, and full news feed, bypassing the daily check and retry delay.")
            }

            Section("Debug") {
                NavigationLink("Town Hall Palettes") {
                    TownHallPaletteView()
                }
                NavigationLink("Progress Overview") {
                    ProgressOverviewView()
                        .environmentObject(dataService)
                }
                NavigationLink("Assets Catalog") {
                    AssetsCatalogView()
                }
                NavigationLink("Master List") {
                    MasterListDebugView()
                }
            }
        }
        .navigationTitle("Debug")
    }

    @MainActor
    private func grabRemoteFiles() async {
        guard !manualRefreshInProgress, !remoteContent.isRefreshing else { return }
        guard remoteContent.baseURL != nil else {
            remoteRefreshFailed = true
            remoteRefreshStatus = "RemoteContentBaseURL is missing or is not a valid HTTPS URL."
            return
        }
        manualRefreshInProgress = true
        remoteRefreshStatus = nil
        defer { manualRefreshInProgress = false }

        await remoteContent.refreshIfNeeded(force: true, downloadFullFeed: true)
        if let error = remoteContent.lastError {
            remoteRefreshFailed = true
            remoteRefreshStatus = error
        } else {
            dataService.reconcileRemoteEvents(remoteContent.events, at: Date())
            remoteRefreshFailed = false
            remoteRefreshStatus = "Remote files refreshed successfully."
        }
    }
}
