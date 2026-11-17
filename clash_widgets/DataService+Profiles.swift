import Foundation
import SwiftUI

extension DataService {
    func moveProfiles(from offsets: IndexSet, to destination: Int) {
        profiles.move(fromOffsets: offsets, toOffset: destination)
        persistChanges(reloadWidgets: true)
    }

    func toggleWidgetPriority(_ id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        guard profiles[index].isWidgetPriority || profiles.filter(\.isWidgetPriority).count < 6 else { return }
        profiles[index].isWidgetPriority.toggle()
        persistChanges(reloadWidgets: true)
    }

    func selectProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        if selectedProfileID != id {
            selectedProfileID = id
        }
    }

    func displayName(for profile: PlayerAccount) -> String {
        if let cachedName = profile.cachedProfile?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !cachedName.isEmpty {
            return cachedName
        }
        let trimmed = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return profile.tag.isEmpty ? "Profile" : profile.tag
    }

    func clearData() {
        activeUpgrades = []
        rawJSON = ""
        lastImportDate = nil
    }
}
