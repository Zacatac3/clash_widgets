import SwiftUI

struct DebugSettingsPage: View {
    @EnvironmentObject private var dataService: DataService

    var body: some View {
        Form {
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
}
