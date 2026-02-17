import Foundation

extension DataService {
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
