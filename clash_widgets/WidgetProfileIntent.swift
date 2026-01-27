//
//  WidgetProfileIntent.swift
//  clash_widgets (shared)
//
//  Widget configuration intent for profile selection
//

import AppIntents
import WidgetKit
import Foundation

struct WidgetProfileIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Profile"
    static let description: IntentDescription = "Choose which profile this widget displays"
    
    @Parameter(title: "Profile", description: "Select a profile or leave empty for automatic")
    var selectedProfile: ProfileOption?
    
    func perform() async throws -> some IntentResult {
        if let profile = selectedProfile {
            // Save to shared UserDefaults
            let appGroup = "group.Zachary-Buschmann.clash-widgets"
            if let defaults = UserDefaults(suiteName: appGroup) {
                defaults.set(profile.id.uuidString, forKey: "widget_profile_id")
                WidgetCenter.shared.reloadAllTimelines()
            }
        } else {
            // Clear profile selection (use automatic)
            let appGroup = "group.Zachary-Buschmann.clash-widgets"
            if let defaults = UserDefaults(suiteName: appGroup) {
                defaults.removeObject(forKey: "widget_profile_id")
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        
        return .result()
    }
}

struct ProfileOption: AppEnum, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Profile"
    
    typealias RawValue = String
    
    let id: UUID
    let displayName: String
    
    var rawValue: String { id.uuidString }
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
    
    init(id: UUID, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
    
    // Implement Hashable and Equatable for AppEnum
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ProfileOption, rhs: ProfileOption) -> Bool {
        lhs.id == rhs.id
    }
    
    init?(rawValue: String) {
        guard let uuid = UUID(uuidString: rawValue) else { return nil }
        self.id = uuid
        
        // Try to find profile with this ID
        if let state = PersistentStore.loadState(),
           let profile = state.profiles.first(where: { $0.id == uuid }) {
            self.displayName = profile.displayName.isEmpty ? "#\(profile.tag)" : profile.displayName
        } else {
            // Automatic profile
            self.displayName = "Most Recent"
        }
    }
    
    static var allCases: [ProfileOption] = {
        var cases: [ProfileOption] = []
        
        // Add automatic option
        let automatic = ProfileOption(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID(),
            displayName: "Automatic (Last Opened)"
        )
        cases.append(automatic)
        
        // Load profiles from persistent store
        if let state = PersistentStore.loadState() {
            for profile in state.profiles {
                let option = ProfileOption(
                    id: profile.id,
                    displayName: profile.displayName.isEmpty ? "#\(profile.tag)" : profile.displayName
                )
                cases.append(option)
            }
        }
        
        return cases
    }()
    
    static var caseDisplayRepresentations: [ProfileOption: DisplayRepresentation] = {
        var reps: [ProfileOption: DisplayRepresentation] = [:]
        for option in allCases {
            reps[option] = option.displayRepresentation
        }
        return reps
    }()
}
