import Foundation

// Only the app service shell is stubbed; profile actions, selection, models,
// boost calculations, and Codable migration are production implementations.
final class DataService {
    var profiles: [PlayerAccount] = []
    var selectedProfileID: UUID?
    var activeUpgrades: [BuildingUpgrade] = []
    var rawJSON = ""
    var lastImportDate: Date?
    var reloadCount = 0
    func persistChanges(reloadWidgets: Bool) { if reloadWidgets { reloadCount += 1 } }
}

let now = Date(timeIntervalSince1970: 1_800_000_000)
func upgrade(_ seconds: Double, category: UpgradeCategory = .builderVillage, goblin: Bool = false) -> BuildingUpgrade {
    BuildingUpgrade(name: "Archer Tower", targetLevel: 20, usesGoblin: goblin,
                    endTime: now.addingTimeInterval(seconds), category: category,
                    startTime: now.addingTimeInterval(-1000), totalDuration: 10000)
}
func account(_ name: String, _ upgrades: [BuildingUpgrade] = [], priority: Bool = false, builders: Int = 6) -> PlayerAccount {
    PlayerAccount(displayName: name, activeUpgrades: upgrades, builderCount: builders, isWidgetPriority: priority)
}
func selected(_ profiles: [PlayerAccount], onePerAccount: Bool = false,
              categories: Set<UpgradeCategory> = [.builderVillage], at date: Date = now) -> [MultiAccountUpgrades.Item] {
    MultiAccountUpgrades.items(profiles: profiles, categories: categories,
                              onePerAccount: onePerAccount, referenceDate: date)
}

let fast = account("Fast", (1...8).map { upgrade(Double($0) * 100) })
let slow = account("Slow", [upgrade(900)])
let closest = selected([fast, slow])
assert(closest.count == 6 && closest.allSatisfy { $0.profileID == fast.id })
assert(closest.map(\.completionDate) == closest.map(\.completionDate).sorted())
let distinct = selected([fast, slow], onePerAccount: true)
assert(distinct.count == 2 && Set(distinct.map(\.profileID)).count == 2)

let priority = account("Priority", [upgrade(9999)], priority: true)
let reserved = selected([fast, slow, priority])
assert(reserved.count == 6 && reserved.contains { $0.profileID == priority.id })
assert(reserved.filter { $0.profileID == fast.id }.count == 5)
let idle = account("Idle", priority: true)
assert(selected([fast, idle]).contains { $0.profileID == idle.id && $0.upgrade == nil })
let sixPriorities = (1...6).map { account("Priority \($0)", priority: true) }
let allReserved = selected([fast] + sixPriorities)
assert(allReserved.count == 6 && allReserved.allSatisfy(\.isPriority))

let mixed = account("Mixed", [upgrade(300), upgrade(100, category: .lab), upgrade(200, category: .pets),
                               upgrade(1, category: .builderBase), upgrade(2, category: .starLab)])
assert(selected([mixed]).map { $0.upgrade!.category } == [.builderVillage])
assert(selected([mixed], categories: [.lab, .pets]).map { $0.upgrade!.category } == [.lab, .pets])
assert(selected([mixed], categories: [.builderVillage, .lab, .pets]).count == 3)
assert(selected([mixed], categories: []).isEmpty)
assert(selected([priority], categories: [.lab]).first?.upgrade == nil)

let explicit = MultiAccountUpgrades.items(profiles: [fast, slow, priority], selectedProfileIDs: [slow.id], referenceDate: now)
assert(Set(explicit.map(\.profileID)) == [slow.id, priority.id])
assert(selected([]).isEmpty)
let tiedA = account("First", [upgrade(100)])
let tiedB = account("Second", [upgrade(100)])
assert(selected([tiedA, tiedB]).first?.profileID == tiedA.id)
assert(selected([tiedB, tiedA]).first?.profileID == tiedB.id)

let expired = account("Finished", [upgrade(-10), upgrade(10)])
assert(selected([expired]).count == 1)
assert(selected([expired], at: now.addingTimeInterval(11)).isEmpty)

// Boost-aware ranking must beat an earlier unboosted raw end date.
var boosted = account("Boosted", [upgrade(400)])
boosted.activeBoosts = [ActiveBoost(type: BoostType.builderPotion.rawValue,
                                   startTime: now.addingTimeInterval(-10), endTime: now.addingTimeInterval(1000))]
let unboosted = account("Normal", [upgrade(100)])
assert(selected([unboosted, boosted]).first?.profileID == boosted.id)
assert(selected([boosted], at: now.addingTimeInterval(60)).isEmpty)

// Only ongoing regular Home Village builders count as occupied.
let freeA = account("Free A", [upgrade(50), upgrade(-1), upgrade(10, category: .lab), upgrade(20, goblin: true)], priority: true, builders: 5)
let freeB = account("Free B", [upgrade(50)], priority: true, builders: 5)
assert(MultiAccountUpgrades.builderAvailability(profiles: [freeA, freeB], referenceDate: now)?.freeBuilders == 4)
assert(MultiAccountUpgrades.builderAvailability(profiles: [freeA, freeB], referenceDate: now)?.profileName == "Free A")
assert(MultiAccountUpgrades.builderAvailability(profiles: [freeB, freeA], referenceDate: now)?.profileName == "Free B")
let mostFree = account("Most Free", priority: true)
assert(MultiAccountUpgrades.builderAvailability(profiles: [freeA, mostFree], referenceDate: now)?.profileName == "Most Free")
assert(MultiAccountUpgrades.builderAvailability(profiles: [fast], referenceDate: now) == nil)
let busy = account("Busy", [upgrade(50)], priority: true, builders: 1)
assert(MultiAccountUpgrades.builderAvailability(profiles: [busy], referenceDate: now) == nil)
assert(MultiAccountUpgrades.builderAvailability(profiles: [busy], referenceDate: now.addingTimeInterval(51))?.freeBuilders == 1)

let service = DataService()
service.profiles = [fast, slow] + (1...5).map { account("Star \($0)", priority: true) }
service.selectedProfileID = slow.id
service.toggleWidgetPriority(fast.id)
assert(service.profiles.filter(\.isWidgetPriority).count == 6)
service.toggleWidgetPriority(slow.id)
assert(service.profiles.filter(\.isWidgetPriority).count == 6)
service.toggleWidgetPriority(fast.id)
service.toggleWidgetPriority(slow.id)
assert(service.profiles.first { $0.id == slow.id }!.isWidgetPriority)
service.moveProfiles(from: IndexSet(integer: 1), to: 0)
assert(service.profiles[0].id == slow.id && service.selectedProfileID == slow.id)
assert(service.reloadCount == 4)

let encoder = JSONEncoder()
let decoder = JSONDecoder()
let saved = PersistentStore.AppState(profiles: service.profiles, selectedProfileID: slow.id)
let restored = try decoder.decode(PersistentStore.AppState.self, from: encoder.encode(saved))
assert(restored.profiles.map(\.id) == service.profiles.map(\.id))
assert(restored.profiles[0].isWidgetPriority)
var legacy = try JSONSerialization.jsonObject(with: encoder.encode(priority)) as! [String: Any]
legacy.removeValue(forKey: "isWidgetPriority")
let migrated = try decoder.decode(PlayerAccount.self, from: JSONSerialization.data(withJSONObject: legacy))
assert(!migrated.isWidgetPriority && migrated.id == priority.id && migrated.activeUpgrades.count == 1)
print("Multi-account checks passed: ranking, filters, priority slots, boosts, completion, free builders, ordering, six-star cap, persistence, and migration.")
