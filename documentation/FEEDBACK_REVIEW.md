# Feedback review — October 7, 2026

Reviewed entries dated March 1, 2026 onward. Older entries were excluded as requested. No respondent contact information is included here.

## Implemented

- **Wrong account in upgrade notifications:** each scheduled upgrade now carries its own account ID, display name, and boosts. Switching accounts cannot relabel another account's alerts or apply its boosts.
- **Stale scheduled notifications:** changed names, timing, notification offsets, and redirect preferences replace existing pending upgrade alerts. Old identifiers are removed during synchronization.
- **Missing iOS notification permission:** after setup, profiles with notifications enabled request system authorization if it has never been requested. Notification settings show a Settings link when iOS blocks alerts.
- **Cancel/complete upgrades:** native SwiftUI `swipeActions` on actual List rows (including two-column module lists) replace the initial custom drag controls. Swipe left on an upgrade to reveal red Cancel and blue Complete actions. Cancel removes the tracked timer while retaining its level. Complete updates the matching imported inventory entry, including Supercharges, Town Hall weapons, and Crafted Defense modules, so Progress reflects completion. These actions affect the local tracker; reimporting replaces local inventory with the new export. Unmatched completion is blocked with a fresh-import message.
- **Progress controls:** one customization button opens the card visibility/reorder sheet. Share retains a separate toolbar container. A single Enable Temporary Content toggle enables both Supercharges and Crafted Defenses; prior separate preferences are merged using whichever was enabled.
- **Timers late after import:** timer deadlines use the export timestamp when available instead of restarting the exported remaining duration at import time. This fixes import-delay drift; it does not infer later in-game boosts or changes.
- **Static upgrade countdowns in widgets:** upgrade rows use system countdown text, including lock-screen rows, with projected completion dates that include elapsed and future boost credit. Widget content changes after completion still depend on iOS timeline refresh.
- **Misleading helper multiplier labels:** helper descriptions show additional hours saved rather than combining the helper contribution with the ordinary builder/lab speed.
- **False wall completion message:** unavailable wall inventory no longer displays All walls maxed out.
- **Clipboard text around JSON:** import sanitization can extract the JSON object when clipboard text includes a prefix or suffix.

## Already present or not a small bug fix

- Progress, max-level indicators, card visibility/reordering, Builder Base Star Laboratory tracking, clan-war widgets, and recent unit/equipment support already have implementations. Reports from older app versions do not establish a current failure.
- Automatic game synchronization, upgrade planning/recommendations, an overview across accounts, and new widget combinations are feature work and were not added in this pass.
- Gearing-up support needs a real active gear-up export to identify its timer and builder assignment reliably; it was not guessed from completed `gear_up` flags.
- The builder-count request mixes permanent and temporary builder capacity; no arbitrary cap increase was made.
- Recurring helper assignment and generic Crafted Defense fallback artwork were not added in this pass.

## Verification

- Model regression harness: `tools/feedback_tests/main.swift` covers correct duplicate-item selection, cancellation, completion, lab inventory, Crafted Defense modules, Supercharges, Town Hall weapons, persisted source timers, unknown JSON fields, unmatched entries, and elapsed/future boost projections.
- Existing remote event and Hammer Jam regression harness rerun.
- Simulator build checks the app and widget targets.
- Physical-device testing is still needed for swipe gesture feel, notification delivery, and system widget countdown rendering.

The Debug menu also now includes an isolated five-minute Hammer Jam fixture with a 30-second lead-in, restart persistence, optional Gold Pass, an additional during/after-event import, and cleanup. See `REMOTE_CONTENT.md` for the lifecycle and staging-feed test checklist.
