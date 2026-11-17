import Foundation

/// Selection shared by both sizes of the multi-account widget.
enum MultiAccountUpgrades {
    static let limit = 6

    struct Item: Identifiable {
        var id: String { profileID.uuidString + ":" + (upgrade?.id.uuidString ?? "idle") }
        let profileID: UUID
        let profileName: String
        let profileOrder: Int
        let isPriority: Bool
        let upgrade: BuildingUpgrade?
        let activeBoosts: [ActiveBoost]
        let goldPassBoost: Int
        let completionDate: Date
    }

    struct BuilderAvailability {
        let profileName: String
        let freeBuilders: Int
    }

    static func displayName(for profile: PlayerAccount) -> String {
        for name in [profile.cachedProfile?.name, profile.displayName, profile.tag] {
            if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return "Profile"
    }

    static func items(
        profiles: [PlayerAccount],
        selectedProfileIDs: Set<UUID> = [],
        categories: Set<UpgradeCategory> = [.builderVillage],
        onePerAccount: Bool = false,
        referenceDate: Date
    ) -> [Item] {
        // Reserve one slot per priority account, even if it has no matching upgrade.
        let priorityIDs = Set(profiles.filter(\.isWidgetPriority).prefix(limit).map(\.id))
        var candidates: [Item] = []
        var reserved: [Item] = []

        for (order, profile) in profiles.enumerated() {
            let priority = priorityIDs.contains(profile.id)
            guard selectedProfileIDs.isEmpty || selectedProfileIDs.contains(profile.id) || priority else { continue }
            let upgrades = profile.activeUpgrades.filter {
                categories.contains($0.category) && $0.remainingSeconds(activeBoosts: profile.activeBoosts, referenceDate: referenceDate) > 0
            }
            let accountItems = upgrades.map { upgrade in
                Item(profileID: profile.id, profileName: displayName(for: profile), profileOrder: order,
                     isPriority: priority, upgrade: upgrade, activeBoosts: profile.activeBoosts,
                     goldPassBoost: profile.goldPassBoost,
                     completionDate: upgrade.projectedCompletionDate(activeBoosts: profile.activeBoosts, referenceDate: referenceDate))
            }.sorted { comesFirst($0, $1) }

            if priority {
                reserved.append(accountItems.first ?? Item(
                    profileID: profile.id, profileName: displayName(for: profile), profileOrder: order,
                    isPriority: true, upgrade: nil, activeBoosts: [], goldPassBoost: profile.goldPassBoost,
                    completionDate: .distantFuture))
            }
            candidates.append(contentsOf: onePerAccount ? Array(accountItems.prefix(1)) : accountItems)
        }

        let reservedIDs = Set(reserved.map(\.id))
        let remaining = candidates.filter { !reservedIDs.contains($0.id) }.sorted { comesFirst($0, $1) }
        return (reserved + remaining.prefix(max(0, limit - reserved.count))).sorted { comesFirst($0, $1) }
    }

    static func builderAvailability(profiles: [PlayerAccount], referenceDate: Date) -> BuilderAvailability? {
        var best: BuilderAvailability?
        for profile in profiles.filter(\.isWidgetPriority).prefix(limit) {
            // The temporary Goblin Builder does not occupy a regular builder slot.
            let busy = profile.activeUpgrades.filter {
                $0.category == .builderVillage && !$0.usesGoblin &&
                $0.remainingSeconds(activeBoosts: profile.activeBoosts, referenceDate: referenceDate) > 0
            }.count
            let free = max(0, profile.builderCount - busy)
            // Keep the earlier profile when counts tie.
            if free > (best?.freeBuilders ?? 0) {
                best = BuilderAvailability(profileName: displayName(for: profile), freeBuilders: free)
            }
        }
        return best
    }

    private static func comesFirst(_ lhs: Item, _ rhs: Item) -> Bool {
        if lhs.completionDate != rhs.completionDate { return lhs.completionDate < rhs.completionDate }
        if lhs.profileOrder != rhs.profileOrder { return lhs.profileOrder < rhs.profileOrder }
        return lhs.id < rhs.id
    }
}
