# October 2026 Supercharge time comparison

Source: user-provided “Supercharge Reductions — October 2026” image. Baseline: `clash_widgets/json/parsed_json_files/mini_levels.json` in this checkout. These are comparisons to bundled data, not verification of installed app versions or live game data.

| Building | Supercharge level | Bundled time | Image time | Required multiplier | Time reduction |
| --- | --- | --- | --- | --- | --- |
| Multi Gear Tower | 1 | 6d | 2d 10h | 0.4027777778 | 59.7222% |
| Multi Gear Tower | 2 | 7d | 2d 19h | 0.3988095238 | 60.1190% |
| Ricochet Cannon | 1 | 6d | 2d 10h | 0.4027777778 | 59.7222% |
| Ricochet Cannon | 2 | 7d | 2d 19h | 0.3988095238 | 60.1190% |
| Multi Archer Tower | 1 | 6d | 2d 10h | 0.4027777778 | 59.7222% |
| Multi Archer Tower | 2 | 7d | 2d 19h | 0.3988095238 | 60.1190% |
| Air Defense | 1 | 2d 18h | 1d 2h | 0.3939393939 | 60.6061% |
| Air Defense | 2 | 4d 6h | 1d 17h | 0.4019607843 | 59.8039% |
| Builders Hut | 1 | 4d | 1d 14h | 0.3958333333 | 60.4167% |
| Builders Hut | 2 | 6d | 2d 10h | 0.4027777778 | 59.7222% |
| Hidden Tesla | 1 | 4d 12h | 1d 19h | 0.3981481481 | 60.1852% |
| Hidden Tesla | 2 | 6d 12h | 2d 14h | 0.3974358974 | 60.2564% |
| X-Bow | 1 | 5d 12h | 2d 5h | 0.4015151515 | 59.8485% |
| X-Bow | 2 | 7d 12h | 3d | 0.4000000000 | 60.0000% |
| Gold Mine | 1 | 2d | 9h 30m | 0.1979166667 | 80.2083% |
| Gold Mine | 2 | 3d | 14h 30m | 0.2013888889 | 79.8611% |
| Gold Mine | 3 | 4d | 19h | 0.1979166667 | 80.2083% |
| Elixir Collector | 1 | 2d | 9h 30m | 0.1979166667 | 80.2083% |
| Elixir Collector | 2 | 3d | 14h 30m | 0.2013888889 | 79.8611% |
| Elixir Collector | 3 | 4d | 19h | 0.1979166667 | 80.2083% |
| Dark Elixir Drill | 1 | 3d | 14h 30m | 0.2013888889 | 79.8611% |
| Dark Elixir Drill | 2 | 4d | 19h | 0.1979166667 | 80.2083% |
| Dark Elixir Drill | 3 | 5d | 1d | 0.2000000000 | 80.0000% |

## Remote configuration limitation

No Supercharge timer modifiers were added. The current engine only receives a building data ID and a Supercharge boolean for matching; it cannot select a Supercharge target level or require a Supercharge. The lowest matching multiplier wins, including the regular 0.5 Hammer Jam rule. A building-ID rule would therefore also affect regular upgrades and cannot represent the distinct ratios above. Unknown JSON fields do not add matching capabilities to installed apps.

The supplied image labels these as October reductions. It does not establish whether they stack with Hammer Jam or the intended effective date. The image times are recorded directly without a further 50% reduction. Cost reductions are not executable through this engine except for walls.

Exact level-specific timer support requires a code change and an app update; a JSON-only event cannot implement it safely.
