# Master Upgrade Lists (Seed)

This folder contains curated lists of available upgrades. The app's Master List debug view reads them. For the full update workflow, see [UPDATE_GUIDE.md](../UPDATE_GUIDE.md).

## Files

- `home_village_master_upgrades.json`: `buildings`, `lab`, `pets`, and `walls`; excludes equipment (`900xxxxx` IDs).
- `builder_base_master_upgrades.json`: `buildings`, `star_lab`, and `walls`.
- `profile_upgrade_state_template.json`
  - Template for local, per-profile upgrade state used by future planner/calculation features.

## JSON shape

The current files contain nested ID to display-name objects (and some slug to name objects for supercharges):

```json
{
  "sections": {
    "buildings": {
      "defense": { "1000008": "Cannon" },
      "supercharges": { "gold_mine": "Gold Mine Supercharge" }
    }
  }
}
```

## Update workflow (new game patch)

1. Add new IDs/names to the correct village file and section.
2. Use the existing slug key format for `supercharges`; keep equipment out of these files.
3. Keep one entry per upgradeable item. Runtime quantities should not become duplicate catalog entries.

## Notes

- These lists are curated and should be checked against in-game availability after major updates.
- The dashboard builds its live upgrade rows from imported game data; these files do not supply its icons.
