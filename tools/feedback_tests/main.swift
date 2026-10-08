import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
let now = Date(timeIntervalSince1970: 1_800_000_000)
func upgrade(_ id: Int, _ target: Int, _ category: UpgradeCategory = .builderVillage) -> BuildingUpgrade {
    BuildingUpgrade(dataId: id, name: "Test", targetLevel: target, endTime: now.addingTimeInterval(10_000), category: category, startTime: now.addingTimeInterval(-3600))
}
func root(_ json: String?) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: json!.data(using: .utf8)!) as! [String: Any]
}
let raw = #"{"buildings":[{"data":1,"lvl":4,"timer":500,"custom":"preserved"},{"data":1,"lvl":4,"timer":700}],"units":[{"data":2,"lvl":8,"timer":100}]}"#
var building = upgrade(1, 5)
building.sourceExportTimer = 700
let finished = root(building.updatingExport(raw, completed: true))
let buildings = finished["buildings"] as! [[String: Any]]
check(buildings[0]["timer"] as? Int == 500, "Completing a duplicate must preserve the other timer")
check(buildings[0]["custom"] as? String == "preserved", "Unknown fields must survive")
check(buildings[1]["lvl"] as? Int == 5 && buildings[1]["timer"] == nil, "Completion must advance the selected level")
let canceled = root(building.updatingExport(raw, completed: false))["buildings"] as! [[String: Any]]
check(canceled[1]["lvl"] as? Int == 4 && canceled[1]["timer"] == nil, "Cancel must preserve the old level")
check(upgrade(2, 9, .lab).updatingExport(raw, completed: true) != nil, "Lab completion must match lab inventory")
let seasonalJSON = #"{"buildings":[{"data":99,"types":[{"data":103000001,"modules":[{"data":102000001,"lvl":3,"timer":700},{"data":102000002,"lvl":4}]}]}]}"#
let seasonal = BuildingUpgrade(dataId: 103000001, name: "Crafted", targetLevel: 4, endTime: now, category: .builderVillage, isSeasonalDefense: true)
let crafted = try! JSONDecoder().decode(CoCExport.self, from: seasonal.updatingExport(seasonalJSON, completed: true)!.data(using: .utf8)!)
check(crafted.buildings![0].types![0].modules![0].lvl == 4, "Crafted completion must advance a module")
let sc = BuildingUpgrade(dataId: 1, name: "Test", targetLevel: 21, superchargeLevel: 1, superchargeTargetLevel: 2, endTime: now, category: .builderVillage)
let charged = root(sc.updatingExport(#"{"buildings":[{"data":1,"lvl":20,"supercharge":1,"timer":500}]}"#, completed: true))["buildings"] as! [[String: Any]]
check(charged[0]["lvl"] as? Int == 20 && charged[0]["supercharge"] as? Int == 2, "Supercharge must preserve the base level")
let weapon = BuildingUpgrade(dataId: 1000001, name: "Town Hall Weapon", targetLevel: 4, endTime: now, category: .builderVillage)
let hall = root(weapon.updatingExport(#"{"buildings":[{"data":1000001,"lvl":17,"weapon":3,"timer":100}]}"#, completed: true))["buildings"] as! [[String: Any]]
check(hall[0]["lvl"] as? Int == 17 && hall[0]["weapon"] as? Int == 4, "Weapon completion must preserve Town Hall level")
let boost = ActiveBoost(type: BoostType.builderPotion.rawValue, startTime: now.addingTimeInterval(-100), endTime: now.addingTimeInterval(100))
check(building.remainingSeconds(activeBoosts: [boost], referenceDate: now) == 9100, "Elapsed boost credit must be included")
check(building.projectedCompletionDate(activeBoosts: [boost], referenceDate: now).timeIntervalSince(now) == 8200, "Projection must include elapsed and future boost credit")
check(building.projectedCompletionDate(activeBoosts: [], referenceDate: now) == building.endTime, "Another account's boosts must not affect this timer")
check(upgrade(404, 2).updatingExport(raw, completed: true) == nil, "An unmatched upgrade must not alter Progress")
let roundTrip = try! JSONDecoder().decode(BuildingUpgrade.self, from: JSONEncoder().encode(building))
check(roundTrip.sourceExportTimer == 700, "Source timer must persist")
print("Feedback regression tests passed")

var tabScroll = TabBarScrollDirectionTracker()
check(tabScroll.update(offset: 1500, viewportHeight: 800) == nil, "Initial position must not change the tab bar")
check(tabScroll.update(offset: 1464, viewportHeight: 800) == nil, "36 points must not expand the tab bar")
check(tabScroll.update(offset: 1300, viewportHeight: 800) == nil, "A quarter viewport must no longer expand the bar")
check(tabScroll.update(offset: 1101, viewportHeight: 800) == nil, "Expansion must wait for half a viewport")
check(tabScroll.update(offset: 1100, viewportHeight: 800) == true, "400 points of content travel must expand an 800-point viewport")
check(tabScroll.update(offset: 1101, viewportHeight: 800) == false, "Downward movement must immediately restore native collapse timing")
check(tabScroll.update(offset: 1000, viewportHeight: 800) == nil, "Direction reversal must start a fresh expansion distance")
tabScroll.reset()
check(tabScroll.update(offset: 1500, viewportHeight: 1200) == nil, "Reset must ignore a programmatic jump")
check(tabScroll.update(offset: 1100, viewportHeight: 1200) == nil, "Taller viewports must require more content travel")
check(tabScroll.update(offset: 900, viewportHeight: 1200) == true, "A 1200-point viewport must expand after 600 points")
check(tabScroll.update(offset: 0, viewportHeight: 1200) == true, "At the top the bar must be expanded")
print("Tab bar scroll-direction checks passed")
