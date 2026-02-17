# Master Upgrade Lists (Seed)

This folder contains curated, split master lists used as the source of truth for valid upgrades.

## Files

- `home_village_master_upgrades.json`
  - Includes `buildings`, `lab`, and `pets` domains.
  - Excludes equipment (`900xxxxx` ids).
  - Includes mini levels (supercharges), guardians, and seasonal defense modules as building upgrades.
- `builder_base_master_upgrades.json`
  - Includes `buildings` and `star_lab` domains.
  - Builder Base is intentionally separate from Home Village.
- `profile_upgrade_state_template.json`
  - Template for local, per-profile upgrade state used by future planner/calculation features.

## JSON shape

Master files are now grouped by large sections and subsections:

```json
{
  "sections": {
    "buildings": {
      "defense": [ ... ],
      "traps": [ ... ]
    },
    "lab": {
      "elixir_troops": [ ... ],
      "spells": [ ... ]
    },
    "pets": {
      "pet": [ ... ]
    }
  }
}
```

Builder Base follows the same pattern (`buildings` + `star_lab`).

Each leaf entry has:

- `key`: stable canonical key (prefer `id:<numericId>`; use `mini:<internalName>` for id-less mini levels)
- `id`: numeric ID when available, else `null`
- `name`: display label
- `upgradeKind`: `base`, `mini_level`, `seasonal_module`, or `guardian`
- `buildingType`: present for building rows (example: `defense`, `trap`, `wall`, `resource`, `army`, `hero`, `supercharge`)
- `sourceInternalName`: optional, used for mini-level mappings

## Update workflow (new game patch)

1. Add new ids/names into the correct village file.
2. Add the entry into the correct section/subsection (`sections.<domain>.<subcategory>`).
3. Keep `equipment` entries out of these files.
4. If an entry has no stable ID, add with `mini:<internalName>` key.
5. Keep one entry per upgradeable item/module; duplicates should be represented by quantity in runtime logic, not by duplicated rows.

## Notes

- This is a curated seed list and should be validated against in-game availability when major updates ship.
- Runtime calculations should only use entries present in these files to avoid counting removed/unused content.