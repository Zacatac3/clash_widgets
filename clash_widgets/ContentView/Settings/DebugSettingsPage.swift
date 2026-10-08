import SwiftUI

struct DebugSettingsPage: View {
    @EnvironmentObject private var dataService: DataService
    @ObservedObject private var remoteContent = RemoteContentService.shared
    @State private var manualRefreshInProgress = false
    @State private var remoteRefreshStatus: String?
    @State private var remoteRefreshFailed = false
    @State private var testGoldPass = false
    @State private var testError: String?

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await grabRemoteFiles(from: .live) }
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

                Button {
                    Task { await grabRemoteFiles(from: .development) }
                } label: {
                    Label("Grab Remote Dev Files", systemImage: "testtube.2")
                }
                .disabled(manualRefreshInProgress || remoteContent.isRefreshing)

                Text("Active feed: \(remoteContent.environment.label)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(remoteContent.environment == .development ? Color.orange : Color.secondary)

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
                Text("Each button switches this installation to that feed and downloads all three files. Development uses /remote_dev with separate caches. Grab Remote Files Now returns to Live. The selected feed survives restarts. Event timer reductions already applied locally are retained when switching; use a disposable test profile.")
            }

            Section("Event Testing") {
                if let event = remoteContent.testEvent {
                    Text(remoteContent.environment == .development ? "Local event paused — Development feed active" : (remoteContent.now < event.start ? "Waiting to start" : (event.isActive(at: remoteContent.now) ? "Active" : "Ended")))
                        .font(.headline)
                    Text(remoteEventCountdown(until: remoteContent.now < event.start ? event.start : event.end, at: remoteContent.now))
                        .monospacedDigit()
                    Button("Switch to Test Profile") {
                        if let id = remoteContent.testProfileID { dataService.selectedProfileID = id }
                    }
                    Button("Add Test Upgrade During / After Event") {
                        do { try dataService.addEventTestUpgrade() }
                        catch { testError = "The extra test upgrade is already present, or the test profile was removed. Remove the test and start again." }
                    }
                    Button("Remove Test and Test Profile", role: .destructive) {
                        dataService.removeEventTest()
                        testError = nil
                    }
                    Text("At expiry: event card disappears, wall prices return to normal, existing discounts remain. Add an upgrade after expiry to check it receives no discount.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Toggle("Test with 20% Gold Pass", isOn: $testGoldPass)
                    Button("Start 5-Minute Hammer Jam Test") {
                        do { try dataService.startFiveMinuteEventTest(goldPass: testGoldPass); testError = nil }
                        catch { testError = "Unable to start the test. Make room for a test profile (maximum 20 profiles)." }
                    }
                    Text("Creates a separate synthetic profile. Starts in 30 seconds, then runs for 5 minutes using the normal event engine. Real profiles and remote files are unaffected. The test survives app restarts until you remove it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let testError { Text(testError).foregroundStyle(.red).font(.caption) }
                if remoteContent.environment == .development {
                    Text("Development feeds replace the local five-minute event while active. You can use the synthetic test profile to inspect downloaded development events.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Check eligible builders, lab and pets against excluded Builder Base, Supercharges and Crafted Defenses. Base durations are 20 minutes; the 50% event changes eligible full durations to 10 minutes (8 with Gold Pass).")
                    .font(.caption).foregroundStyle(.secondary)
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
    private func grabRemoteFiles(from environment: RemoteContentEnvironment) async {
        guard !manualRefreshInProgress, !remoteContent.isRefreshing else { return }
        guard remoteContent.selectEnvironment(environment) else { return }
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
            remoteRefreshStatus = "\(environment.label) remote files refreshed successfully."
        }
    }
}
