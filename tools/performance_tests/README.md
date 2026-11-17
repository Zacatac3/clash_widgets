# Performance regression checks

Run from the repository root:

```sh
python3 tools/performance_tests/run.py
```

The test uses the production service with isolated defaults. It verifies zero
idle `objectWillChange` notifications over 3.2 seconds, updates at event start
and expiry, cancellation after event removal, scheduled news publication, and
no polling when there are no future boundaries. Countdown labels use local
`TimelineView`s rather than a shared one-second publisher.

To reproduce the old idle behavior using a saved source file:

```sh
python3 tools/performance_tests/run.py --service-source /tmp/old-RemoteContentService.swift --baseline
```

## Controlled simulator comparison

A temporary iOS 26.3 simulator harness hosted a SwiftUI scroll view observing
the actual service and sent 180 offsets at 60 Hz. It instrumented the production
scroll modifier and benchmarked the production widget image helpers with the
same Archer Tower asset. Only the user-interaction guard was bypassed for the
programmatic scroll samples.

| Measurement | Before | After |
| --- | ---: | ---: |
| Observing screen evaluations during ~3 seconds of scrolling | 3 | 0 |
| Scroll geometry callbacks | 180 | 180 |
| Scroll modifier body evaluations during scrolling | 0 | 0 |
| Processing the same icon 100 times | 0.500 s | 0.013 s |

The scroll modifier alone did not reproduce extra body evaluations, so its
implementation remains unchanged. The fixes remove periodic shared-service
notifications and cache trimmed images with a bounded `NSCache` in the app
and widget extension. Event availability still updates at actual boundaries.

These are controlled simulator measurements, not whole-app frame-rate, battery,
or device-temperature measurements. Check scrolling and heat on a physical
phone with the updated build.

## Conservative optimization regression checks

```sh
python3 tools/performance_tests/run_optimizations.py
python3 tools/catalog_tests/run.py
python3 tools/import_timer_tests/run.py
python3 tools/multi_account_tests/run.py
python3 tools/performance_tests/run.py
```

`run_optimizations.py` extracts production methods and compares their results
with the frozen pre-change implementations in `reference_loaders.swift`.
Resource resolution and the boost manager's persistence dependency are stubbed;
the actual parsing, filtering, costs, cache handling and boost timer run.

Coverage:

- All bundled upgrade durations/indexing, duplicate file/folder precedence,
  malformed and missing files.
- Identical wall tables; zero resource lookups on 300 warm table accesses.
- Identical helper costs for 304 Town Hall/helper-level combinations, including
  changed player levels after the cache is warm.
- Export cache hits, changed content/profiles, invalid input and recovery.
- Identical equipment groups/hero order across 48 filter combinations.
- Zero idle boost notifications/writes, active one-second cadence, expiry,
  persistence, cancellation, timer restart and undo-only expiry.

The duration-loading timing printed by the harness is a 20-load mean on the
host Mac, not an end-to-end application or device launch benchmark.

For actual UIKit image helpers, build the app for the simulator, then run:

```sh
python3 tools/performance_tests/run_image_checks.py /tmp/clashboard-performance-build/Build/Products/Debug-iphonesimulator/Clashboard.app
```

This installs a temporary isolated harness on a booted Apple Silicon simulator,
uses the built app's asset catalog, and uninstalls the harness afterward. It checks
TH13/TH18 badge dimensions, aspect ratio, orientation, caching and fallback at
1x/2x/3x; 40 concurrent Progress requests; and cancellation. It does not install
or change the user's Clashboard app/data.

Full Debug and Release simulator builds passed for both app and widget targets.
These tests do not prove zero regressions in every UI interaction or quantify
physical-device battery consumption. See the audit's remaining profiling work.
