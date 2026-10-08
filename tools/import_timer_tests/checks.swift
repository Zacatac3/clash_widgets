let importNow = Date()
let originalFixture = RemoteEvent.fiveMinuteTest(at: importNow.addingTimeInterval(-60))
let decoder = JSONDecoder()
let encoder = JSONEncoder()
let liveEvent = originalFixture
let devEvent = RemoteContentEnvironment.development.scopedEvent(originalFixture)

for timestamp in [0, Int(importNow.timeIntervalSince1970) - 86400 * 300,
                  Int(importNow.timeIntervalSince1970), Int(importNow.timeIntervalSince1970) + 86400] {
    // Different service instances represent independently imported accounts.
    for _ in 0..<3 {
        let service = DataService()
        let raw = """
        {"timestamp":\(timestamp),
         "buildings":[{"data":1000008,"lvl":10,"timer":1080},
                      {"data":1000009,"lvl":20,"supercharge":1,"timer":1080},
                      {"data":1000097,"types":[{"data":103000011,"modules":[{"data":102000033,"lvl":7,"timer":1080}]}]}],
         "buildings2":[{"data":1000044,"lvl":10,"timer":1080}],
         "traps":[{"data":12000000,"lvl":5,"timer":1080}],
         "traps2":[{"data":12000001,"lvl":5,"timer":1080}],
         "heroes":[{"data":28000000,"lvl":50,"timer":1080}],
         "heroes2":[{"data":28000001,"lvl":20,"timer":1080}],
         "units":[{"data":4000000,"lvl":10,"timer":1080}],
         "units2":[{"data":4000001,"lvl":10,"timer":1080}],
         "pets":[{"data":73000000,"lvl":5,"timer":1080}],
         "spells":[{"data":26000000,"lvl":5,"timer":1080}],
         "siege_machines":[{"data":4000051,"lvl":3,"timer":1080}]}
        """
        let export = try decoder.decode(CoCExport.self, from: Data(raw.utf8))
        let upgrades = service.imported(export)
        precondition(upgrades.count == 13, "All upgrade categories must be exercised")
        for var upgrade in upgrades {
            let importedEnd = upgrade.endTime
            precondition(upgrade.remainingSeconds(activeBoosts: [], referenceDate: Date()) > 1070,
                         "Positive imported timers must survive stale/future timestamps")
            // Repeated development/live switches must not compound discounts.
            for event in [devEvent, liveEvent, devEvent, liveEvent] {
                _ = upgrade.applyRemoteEvent(event, at: Date(), townHall: 18, goldPassBoost: 0)
            }
            let adjustedEnd = upgrade.endTime
            let atExpiry = liveEvent.end
            precondition(upgrade.remainingSeconds(activeBoosts: [], referenceDate: atExpiry) > 0,
                         "The short event ending must not finish these upgrades")
            precondition(!upgrade.applyRemoteEvent(liveEvent, at: atExpiry, townHall: 18, goldPassBoost: 0))
            precondition(upgrade.endTime == adjustedEnd, "Expiry must preserve the discounted deadline")
            if upgrade.category == .builderBase || upgrade.category == .starLab ||
               upgrade.isSeasonalDefense == true || upgrade.superchargeTargetLevel != nil {
                precondition(adjustedEnd == importedEnd, "Excluded upgrades must remain unchanged")
            }
            let restored = try decoder.decode(BuildingUpgrade.self, from: encoder.encode(upgrade))
            precondition(restored.endTime == adjustedEnd && restored.remainingSeconds(activeBoosts: [], referenceDate: atExpiry) > 0,
                         "Saved and restored timers must remain usable")
        }
        // A new import after an expired event gets no inherited event discount.
        let expired = RemoteEvent.fiveMinuteTest(at: Date().addingTimeInterval(-3600))
        for var upgrade in service.imported(export) {
            precondition(!upgrade.applyRemoteEvent(expired, at: Date(), townHall: 18, goldPassBoost: 0))
            precondition(upgrade.remainingSeconds(activeBoosts: [], referenceDate: Date()) > 1070)
        }
    }
}
print("Import regression checks passed: all categories, old/current/future timestamps, multiple profiles, repeated dev/live discounts, expiry, restart serialization and post-event reimport.")
