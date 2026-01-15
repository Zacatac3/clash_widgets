import Foundation
import Combine
import WidgetKit

class DataService: ObservableObject {
    static let appGroup = "group.Zachary-Buschmann.clash-widgets"
    
    @Published var widgetText: String = "" {
        didSet {
            saveToStorage()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    @Published var activeUpgrades: [BuildingUpgrade] = [] {
        didSet {
            saveToStorage()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    init() {
        loadFromStorage()
        // Ensure data is migrated to App Group on first launch
        saveToStorage()
    }
    
    private func saveToStorage() {
        let sharedDefaults = UserDefaults(suiteName: DataService.appGroup)
        sharedDefaults?.set(widgetText, forKey: "widget_simple_text")
        
        if let encoded = try? JSONEncoder().encode(activeUpgrades) {
            sharedDefaults?.set(encoded, forKey: "saved_upgrades")
            sharedDefaults?.synchronize() // Force write to disk for simulator
            
            // Fallback for app-only use
            UserDefaults.standard.set(encoded, forKey: "saved_upgrades")
        }
    }
    
    private func loadFromStorage() {
        let sharedDefaults = UserDefaults(suiteName: DataService.appGroup)
        self.widgetText = sharedDefaults?.string(forKey: "widget_simple_text") ?? ""
        
        let data = sharedDefaults?.data(forKey: "saved_upgrades") ?? UserDefaults.standard.data(forKey: "saved_upgrades")
        
        if let data = data,
           let decoded = try? JSONDecoder().decode([BuildingUpgrade].self, from: data) {
            self.activeUpgrades = decoded
        }
    }
    
    func clearData() {
        activeUpgrades = []
        UserDefaults(suiteName: DataService.appGroup)?.removeObject(forKey: "saved_upgrades")
        UserDefaults.standard.removeObject(forKey: "saved_upgrades")
    }

    private let mapping: [Int: String] = [
        1000097: "Crafted Defense",
        1000008: "Cannon",
        1000009: "Archer Tower",
        1000013: "Mortar",
        1000012: "Air Defense",
        1000011: "Wizard Tower",
        1000028: "Air Sweeper",
        1000019: "Hidden Tesla",
        1000032: "Bomb Tower",
        1000021: "X-Bow",
        1000027: "Inferno Tower",
        1000031: "Eagle Artillery",
        1000067: "Scattershot",
        1000015: "Builders Hut",
        1000072: "Spell Tower",
        1000077: "Monolith",
        1000089: "Firespitter",
        1000010: "Wall",
        1000084: "Multi-Archer Tower",
        1000085: "Ricochet Cannon",
        1000079: "Multi-Gear Tower",
        12000000: "Bomb",
        12000001: "Spring Trap",
        12000002: "Giant Bomb",
        12000005: "Air Bomb",
        12000006: "Seeking Air Mine",
        12000008: "Skeleton Trap",
        12000016: "Tornado Trap",
        12000020: "Giga Bomb",
        1000004: "Gold Mine",
        1000002: "Elixir Collector",
        1000005: "Gold Storage",
        1000003: "Elixir Storage",
        1000023: "Dark Elixir Drill",
        1000024: "Dark Elixir Storage",
        1000014: "Clan Castle",
        1000000: "Army Camp",
        1000006: "Barracks",
        1000026: "Dark Barracks",
        1000007: "Laboratory",
        1000020: "Spell Factory",
        1000071: "Hero Hall",
        1000029: "Dark Spell Factory",
        1000070: "Blacksmith",
        1000059: "Workshop",
        1000068: "Pet House",
        1000001: "Town Hall",
        28000000: "Barbarian King",
        28000001: "Archer Queen",
        28000006: "Minion Prince",
        28000002: "Grand Warden",
        28000004: "Royal Champion",
        4000051: "Wall Wrecker",
        4000052: "Battle Blimp",
        4000062: "Stone Slammer",
        4000075: "Siege Barracks",
        4000087: "Log Launcher",
        4000091: "Flame Flinger",
        4000092: "Battle Drill",
        4000135: "Troop Launcher",
        73000000: "L.A.S.S.I",
        73000001: "Electro Owl",
        73000002: "Mighty Yak",
        73000003: "Unicorn",
        73000004: "Phoenix",
        73000007: "Poison Lizard",
        73000008: "Diggy",
        73000009: "Frosty",
        73000010: "Spirit Fox",
        73000011: "Angry Jelly",
        73000016: "Sneezy",
        4000000: "Barbarian",
        4000001: "Archer",
        4000002: "Goblin",
        4000003: "Giant",
        4000004: "Wall Breaker",
        4000005: "Balloon",
        4000006: "Wizard",
        4000007: "Healer",
        4000008: "Dragon",
        4000009: "P.E.K.K.A",
        4000010: "Minion",
        4000011: "Hog Rider",
        4000012: "Valkyrie",
        4000013: "Golem",
        4000015: "Witch",
        4000017: "Lava Hound",
        4000022: "Bowler",
        4000023: "Baby Dragon",
        4000024: "Miner",
        4000053: "Yeti",
        4000058: "Ice Golem",
        4000059: "Electro Dragon",
        4000065: "Dragon Rider",
        4000082: "Headhunter",
        4000095: "Electro Titan",
        4000097: "Apprentice Warden",
        4000110: "Root Rider",
        4000123: "Druid",
        4000132: "Thrower",
        4000150: "Furnace",
        26000000: "Lightning Spell",
        26000001: "Healing Spell",
        26000002: "Rage Spell",
        26000003: "Jump Spell",
        26000005: "Freeze Spell",
        26000009: "Poison Spell",
        26000010: "Earthquake Spell",
        26000011: "Haste Spell",
        26000016: "Clone Spell",
        26000017: "Skeleton Spell",
        26000028: "Bat Spell",
        26000035: "Invisibility Spell",
        26000053: "Recall Spell",
        26000070: "Overgrowth Spell",
        26000098: "Revive Spell",
        26000109: "Ice Block Spell",
        28000003: "Battle Machine",
        28000005: "Battle Copter"
    ]

    func parseJSONFromClipboard(input: String) {
        let decoder = JSONDecoder()
        guard let data = input.data(using: .utf8) else { return }
        
        do {
            let decoded = try decoder.decode(CoCExport.self, from: data)
            var newUpgrades: [BuildingUpgrade] = []
            
            // Process main builder village structures
            if let buildings = decoded.buildings {
                let active = buildings.filter { $0.timer != nil }
                for b in active {
                    let name = mapping[b.data] ?? "Unknown Building (\(b.data))"
                    let upgrade = BuildingUpgrade(
                        name: name,
                        targetLevel: b.lvl + 1,
                        endTime: Date().addingTimeInterval(TimeInterval(b.timer ?? 0)),
                        category: .builderVillage
                    )
                    newUpgrades.append(upgrade)
                }
            }
            
            // Process builder base structures
            if let baseBuildings = decoded.buildings2 {
                let active = baseBuildings.filter { $0.timer != nil }
                for b in active {
                    let name = mapping[b.data] ?? "Unknown Builder Base Building (\(b.data))"
                    let upgrade = BuildingUpgrade(
                        name: name,
                        targetLevel: b.lvl + 1,
                        endTime: Date().addingTimeInterval(TimeInterval(b.timer ?? 0)),
                        category: .builderBase
                    )
                    newUpgrades.append(upgrade)
                }
            }

            // Process main developer village traps
            if let traps = decoded.traps {
                let active = traps.filter { $0.timer != nil }
                for t in active {
                    let name = mapping[t.data] ?? "Unknown Trap (\(t.data))"
                    let upgrade = BuildingUpgrade(
                        name: name,
                        targetLevel: t.lvl + 1,
                        endTime: Date().addingTimeInterval(TimeInterval(t.timer ?? 0)),
                        category: .builderVillage
                    )
                    newUpgrades.append(upgrade)
                }
            }

            // Process builder base traps
            if let baseTraps = decoded.traps2 {
                let active = baseTraps.filter { $0.timer != nil }
                for t in active {
                    let name = mapping[t.data] ?? "Unknown Builder Base Trap (\(t.data))"
                    let upgrade = BuildingUpgrade(
                        name: name,
                        targetLevel: t.lvl + 1,
                        endTime: Date().addingTimeInterval(TimeInterval(t.timer ?? 0)),
                        category: .builderBase
                    )
                    newUpgrades.append(upgrade)
                }
            }

            // Process main village heroes
            if let heroes = decoded.heroes {
                let active = heroes.filter { $0.timer != nil }
                for h in active {
                    let name = mapping[h.data] ?? "Unknown Hero (\(h.data))"
                    let upgrade = BuildingUpgrade(
                        name: name,
                        targetLevel: h.lvl + 1,
                        endTime: Date().addingTimeInterval(TimeInterval(h.timer ?? 0)),
                        category: .builderVillage
                    )
                    newUpgrades.append(upgrade)
                }
            }

            // Process builder base heroes
            if let baseHeroes = decoded.heroes2 {
                let active = baseHeroes.filter { $0.timer != nil }
                for h in active {
                    let name = mapping[h.data] ?? "Unknown Builder Base Hero (\(h.data))"
                    let upgrade = BuildingUpgrade(
                        name: name,
                        targetLevel: h.lvl + 1,
                        endTime: Date().addingTimeInterval(TimeInterval(h.timer ?? 0)),
                        category: .builderBase
                    )
                    newUpgrades.append(upgrade)
                }
            }

            // Process pets
            if let pets = decoded.pets {
                let active = pets.filter { $0.timer != nil }
                for p in active {
                    let name = mapping[p.data] ?? "Unknown Pet (\(p.data))"
                    let upgrade = BuildingUpgrade(
                        name: name,
                        targetLevel: p.lvl + 1,
                        endTime: Date().addingTimeInterval(TimeInterval(p.timer ?? 0)),
                        category: .pets
                    )
                    newUpgrades.append(upgrade)
                }
            }
            
            // Process units (Lab upgrades)
            if let units = decoded.units {
                let active = units.filter { $0.timer != nil }
                for u in active {
                    let name = mapping[u.data] ?? "Unknown Unit (\(u.data))"
                    let upgrade = BuildingUpgrade(
                        name: name,
                        targetLevel: u.lvl + 1,
                        endTime: Date().addingTimeInterval(TimeInterval(u.timer ?? 0)),
                        category: .lab
                    )
                    newUpgrades.append(upgrade)
                }
            }

            // Process builder base units (if any)
            if let baseUnits = decoded.units2 {
                let active = baseUnits.filter { $0.timer != nil }
                for u in active {
                    let name = mapping[u.data] ?? "Unknown Builder Base Unit (\(u.data))"
                    let upgrade = BuildingUpgrade(
                        name: name,
                        targetLevel: u.lvl + 1,
                        endTime: Date().addingTimeInterval(TimeInterval(u.timer ?? 0)),
                        category: .builderBase
                    )
                    newUpgrades.append(upgrade)
                }
            }
            
            // Process spells
            if let spells = decoded.spells {
                let active = spells.filter { $0.timer != nil }
                for s in active {
                    let name = mapping[s.data] ?? "Unknown Spell (\(s.data))"
                    let upgrade = BuildingUpgrade(
                        name: name,
                        targetLevel: s.lvl + 1,
                        endTime: Date().addingTimeInterval(TimeInterval(s.timer ?? 0)),
                        category: .lab
                    )
                    newUpgrades.append(upgrade)
                }
            }
            
            DispatchQueue.main.async {
                self.activeUpgrades = newUpgrades.sorted(by: { $0.endTime < $1.endTime })
            }
            
        } catch {
            print("Failed to decode export: \(error)")
        }
    }
}
