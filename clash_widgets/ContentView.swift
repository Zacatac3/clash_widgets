//
//  ContentView.swift
//  clash_widgets
//
//  Created by Zachary Buschmann on 1/7/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    private static let sharedDefaults = UserDefaults(suiteName: DataService.appGroup)

    @StateObject private var apiClient = APIClient()
    @StateObject private var dataService = DataService()
    
    @AppStorage("saved_player_tag", store: sharedDefaults) private var playerTag = ""
    @AppStorage("saved_import_json", store: sharedDefaults) private var jsonInput = ""
    @State private var showingImportSheet = false
    
    // Hardcoded API Key
    private let apiKey = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzUxMiIsImtpZCI6IjI4YTMxOGY3LTAwMDAtYTFlYi03ZmExLTJjNzQzM2M2Y2NhNSJ9.eyJpc3MiOiJzdXBlcmNlbGwiLCJhdWQiOiJzdXBlcmNlbGw6Z2FtZWFwaSIsImp0aSI6IjdiNTg2ZGE4LTk5YTMtNDE0MS1hMmQwLTA0YjgxMTVjNGE1ZCIsImlhdCI6MTc2NzgzMjMwNiwic3ViIjoiZGV2ZWxvcGVyL2IzMzM2MjZkLTlkNjYtZmNjZS0wNTQ2LTNkOGJjZTYzOTBjYyIsInNjb3BlcyI6WyJjbGFzaCJdLCJsaW1pdHMiOlt7InRpZXIiOiJkZXZlbG9wZXIvc2lsdmVyIiwidHlwZSI6InRocm90dGxpbmcifSx7ImNpZHJzIjpbIjQ1Ljc5LjIxOC43OSIsIjE3Mi41OC4xMjYuMTAzIl0sInR5cGUiOiJjbGllbnQifV19.soreABdHMlQOLiDX6QgkKjGhyhfbR_63adhoQAhyy7IsTk6ZmbK-QO39Q3hcyA8r0RjjNVOoArVJlJ4kz7Z95Q"
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Player Profile")) {
                    TextField("Player Tag", text: $playerTag)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                    
                    HStack {
                        Button(action: {
                            apiClient.fetchPlayerProfile(playerTag: playerTag, apiKey: apiKey)
                        }) {
                            if apiClient.isLoading {
                                ProgressView()
                            } else {
                                Text("Fetch Profile")
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            clearPlayerTag()
                            apiClient.playerProfile = nil
                        }) {
                            Text("Clear ID")
                                .foregroundColor(.red)
                        }
                    }
                    
                    if let profile = apiClient.playerProfile {
                        VStack(alignment: .leading) {
                            Text(profile.name)
                                .font(.headline)
                            Text("TH\(profile.townHallLevel) - \(profile.trophies) Trophies")
                                .font(.subheadline)
                            if let clan = profile.clan {
                                Text(clan.name)
                                    .font(.caption)
                            }
                        }
                    }
                    
                    if let error = apiClient.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section {
                    HStack {
                        Text("Builder Upgrades")
                            .font(.headline)
                        Spacer()
                        Button("Clear All") {
                            dataService.clearData()
                        }
                        .foregroundColor(.red)
                        .font(.caption)

                        Button("Import JSON") {
                            showingImportSheet = true
                        }
                        .font(.caption)
                    }
                }

                if dataService.activeUpgrades.isEmpty {
                    Section {
                        Text("No active upgrades tracked. Tap Import JSON and use the paste button to load your village export.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    if !builderVillageUpgrades.isEmpty {
                        Section(header: Text("Builder Village")) {
                            ForEach(builderVillageUpgrades) { upgrade in
                                BuilderRow(upgrade: upgrade)
                            }
                        }
                    }

                    if !labUpgrades.isEmpty {
                        Section(header: Text("Lab")) {
                            ForEach(labUpgrades) { upgrade in
                                BuilderRow(upgrade: upgrade)
                            }
                        }
                    }

                    if !petsUpgrades.isEmpty {
                        Section(header: Text("Pets")) {
                            ForEach(petsUpgrades) { upgrade in
                                BuilderRow(upgrade: upgrade)
                            }
                        }
                    }

                    if !builderBaseUpgrades.isEmpty {
                        Section(header: Text("Builder Base")) {
                            ForEach(builderBaseUpgrades) { upgrade in
                                BuilderRow(upgrade: upgrade)
                            }
                        }
                    }
                }
            }
            .navigationTitle("ClashDash")
            .sheet(isPresented: $showingImportSheet) {
                ImportView(jsonInput: $jsonInput) {
                    dataService.parseJSONFromClipboard(input: jsonInput)
                    showingImportSheet = false
                }
            }
        }
    }

    private var builderVillageUpgrades: [BuildingUpgrade] {
        dataService.activeUpgrades.filter { $0.category == .builderVillage }
    }

    private var labUpgrades: [BuildingUpgrade] {
        dataService.activeUpgrades.filter { $0.category == .lab }
    }

    private var petsUpgrades: [BuildingUpgrade] {
        dataService.activeUpgrades.filter { $0.category == .pets }
    }

    private var builderBaseUpgrades: [BuildingUpgrade] {
        dataService.activeUpgrades.filter { $0.category == .builderBase }
    }

    private func clearPlayerTag() {
        playerTag = ""
        Self.sharedDefaults?.removeObject(forKey: "saved_player_tag")
        UserDefaults.standard.removeObject(forKey: "saved_player_tag")
    }
}

struct ImportView: View {
    @Binding var jsonInput: String
    var onImport: () -> Void
    @Environment(\.presentationMode) var presentationMode
    @State private var pasteStatus = "Tap the button to pull JSON from your clipboard."
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("Paste your manual village export JSON below:")
                    .font(.subheadline)
                    .padding(.top)
                
                Button(action: pasteFromClipboard) {
                    Label("Paste JSON from Clipboard", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                
                Text(pasteStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                if !jsonInput.isEmpty {
                    ScrollView {
                        Text(jsonInput)
                            .font(.caption2)
                            .lineLimit(6)
                            .multilineTextAlignment(.leading)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal)
                    }
                    .frame(maxHeight: 160)
                } else {
                    Text("No JSON stored yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                
                Button(action: onImport) {
                    Text("Import Upgrades")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(jsonInput.isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
                .disabled(jsonInput.isEmpty)
                
                Spacer()
            }
            .navigationTitle("Import Village Data")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    private func pasteFromClipboard() {
        #if canImport(UIKit)
        let trimmed = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            pasteStatus = "Clipboard is empty."
            return
        }

        jsonInput = trimmed
        pasteStatus = "JSON loaded (\(trimmed.count) characters) from clipboard."
        #else
        pasteStatus = "Clipboard access is not available."
        #endif
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

