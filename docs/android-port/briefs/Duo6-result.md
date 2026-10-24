# Duo6 — choose layout by size class

Status: source ready for Claude's build/test/device gate, 2026-10-24, in
`claude/agent-ios-duo6` from `e8036a77`. Changes remain uncommitted as requested.
This brief was written before source changes and updated for handoff.

## Contract and scope

On iOS, wide behavior requires **both** horizontal and vertical size classes to
be `.regular`; every other combination (including an unspecified class) uses
the compact behavior. Read size classes from the deciding SwiftUI view's
environment and share one pure predicate. Offer the existing spread toggle and
honor its stored value only in a wide layout. Present filters as an inspector
only in a wide layout, and as a sheet otherwise. macOS behavior stays unchanged.

The stored `readerMode` and `readerTwoPage` values must survive size-class
transitions. The preference-change token must include the effective wide-layout
decision so an already-open reader updates when its environment changes.

Only the reader's environment declarations, former idiom predicate, preferences
mapping call and preferences token are in scope in `ReadiumReaderView.swift`.
Duo5 owns reader geometry, safe areas, remeasure and chrome padding. Fold/Book
pose, reserved regions, division gutter and queue-browser split remain deferred.

## Changes

Source references are relative to `kudos-ao3-reader/`; tests/docs are relative
to the repository root. Line numbers describe this uncommitted handoff.

| File:line | Change |
|---|---|
| `UIComponents/WideLayout.swift:6` (new) | One pure `WideLayout.isAvailable(horizontal:vertical:)` predicate. True only for regular/regular; nil falls back to compact behavior. Entire helper is iOS-only. |
| `Settings/SettingsView.swift:99,108,125` | `ReaderLayoutSection` reads both environment classes and uses the predicate to offer the existing spread toggle and select its footer. Its disabled rule, binding and both stored reader settings remain intact. macOS still returns true. Removed the now-unused UIKit import; corrected the host-width comments at `:13,95`. |
| `Features/ReaderReadium/ReadiumReaderView.swift:84,1437,1477` | Reads this reader's environment, replaces `isPhone` with the shared decision, and passes `twoPageEnabled && wideLayoutAvailable` to the mapper. No screen, window or device query. |
| `Features/ReaderReadium/ReadiumReaderView.swift:1499` | Adds the wide-layout decision to `preferencesToken`. The existing observer at `:383` re-applies preferences on class transitions without writing either setting or reopening the book. These are the only four edited reader regions; Duo5's geometry/chrome regions are untouched. |
| `Features/ReaderReadium/ReadiumReaderStyleMapper.swift:13,25` | Takes the effective `twoPageSpread` Boolean instead of a column enum. Paged mode maps it to `.auto`/`.one`; Scroll still sends nil. `.auto` preserves Readium's existing width-based spread fitting; this does not force `.two`. All callers were updated (the reader and tests). |
| `UIComponents/FilterPanelPresentation.swift:29,40` | Reads both environment classes at the presentation host. Regular/regular gets the existing inspector; every other iOS case gets the existing real sheet with its original detents and drag indicator. macOS inspector is unchanged. Comments at `:3,6,24,59` now explain size-class fallback rather than device idiom. |
| `KudosTests/WideLayoutTests.swift:8` (new) | Five pure predicate tests cover the four class combinations and unspecified fallback. |
| `KudosTests/ReadiumReaderTests.swift:24,48,63` | Updates the existing typography caller and adds two mapper methods (three executions including parameterized Scroll cases). |
| `docs/REGRESSION_TEST_MATRIX.md:7` | Records automated coverage and the remaining device checks. |

No `@AppStorage` key/default/binding changed. Neither `readerMode` nor
`readerTwoPage` is assigned during a size-class transition; a stored spread-on
preference becomes effective again when the reader returns to regular/regular.
This is verified by source inspection; runtime persistence is a device check.

## Tests and expected regression failures

**Added, not executed:** five helper tests and two mapper test methods (eight
total executions). Neither Swift Testing nor mutation tests ran in this
worktree. The failures below are predictions for Claude to verify.

| Test:line | Contract and expected failure when regressed |
|---|---|
| `WideLayoutTests.regularWidthAndHeightAllowWideLayout:8` | Regular/regular is true. Returning false (the former phone restriction's effect on Duo inner) fails this expectation. |
| `WideLayoutTests.compactWidthUsesCompactLayout:12` | Compact/regular is false. Checking only vertical class or replacing AND with OR fails. |
| `WideLayoutTests.compactHeightUsesCompactLayoutEvenWithRegularWidth:16` | Regular/compact is false. Checking only horizontal class or replacing AND with OR fails; this protects the Pro Max landscape case. |
| `WideLayoutTests.bothCompactUsesCompactLayout:20` | Compact/compact is false. An unconditional wide result fails. |
| `WideLayoutTests.unspecifiedSizeClassesUseCompactLayout:24` | Nil/regular, regular/nil and nil/nil are false. Treating an absent class as regular fails. |
| `ReadiumReaderTests.pagedColumnsHonorSpreadDecision:48` | True maps to `.auto`, false to `.one`. Forcing the old phone result `.one` fails the true case; ignoring a disabled spread fails the false case. |
| `ReadiumReaderTests.scrollModeNeverForcesColumns:63` | Both effective spread values leave columns nil and `scroll` true. Removing the Scroll guard fails both cases. |

The pure tests do **not** prove SwiftUI environment propagation, toggle visibility,
presentation type, or live navigator invalidation. Replacing a view's call to the
predicate with an idiom gate while leaving the helper intact would evade these
tests. The device checks below catch those reversions: Duo inner must offer and
honor spread/use an inspector; compact iPad must use a sheet; removing the token
dependency is caught by resizing an already-open paged reader. No unit test claims
to exercise that UI wiring.

## Checks performed here

- Targeted `swiftlint lint --quiet --no-cache` on all seven changed/new Swift
  files: exit 0. The five warnings are pre-existing (two Settings large tuples;
  reader file/type length and `filter.first`). Linted temporary HEAD copies of
  those two files to confirm the same warning rules existed before this change.
  No diagnostics in the helper, mapper, filter modifier or tests.
- `Scripts/check-invariants.sh`: passed.
- `git diff --check`: passed; new helper, tests and brief also checked for trailing
  whitespace and a final newline.
- Reviewed the complete diff, mapper callers, platform guards, stored bindings
  and live preference observer. No project-file edit or dependency addition.

Not run: builds, Swift Testing, mutation execution, full verification harness,
simulator screenshots, human UI gate or independent adversarial review. Claude
must perform those applicable integration gates; this report does not claim the
UI has been seen or the new Swift code compiled.

## Claude's device checks

Use local EPUBs and loaded/demo filter content; no sign-in or AO3 traffic is
needed. Build on the integration worktree and run the added tests plus the
required project gates before claiming completion. New Swift files are included
by synchronized groups; do not edit `project.pbxproj` for them. When carrying this
patch alongside Duo5, preserve only the four named reader hunks above.

- **iPhone 17**, portrait and landscape: spread toggle remains hidden; Paged
  mode remains one column even with `readerTwoPage` already true. Filters are
  a real sheet with existing detents, drag indicator, Apply/Reset and working
  Browse category navigation. Include a regular-width/compact-height Pro Max
  landscape check if available.
- **iPad full screen**, both orientations: spread toggle remains available,
  disabled in Scroll mode; Paged + spread on permits Readium's existing automatic
  spread, spread off gives one column. Filters remain an inspector. Also narrow
  the multitasking window: compact behavior applies; widening restores the
  stored preference. Check both Settings > Reader and the in-reader options.
  Repeat with the options sheet at medium and large detents to confirm the
  environment delivered to that form; record the classes if it differs from
  the reader's layout. Check filter dismissal and Browse category navigation
  in the narrow window, and again after widening.
- **Duo cover**: compact behavior as on iPhone. **Duo inner display**, both
  orientations (supplied regular/regular assumption): existing toggle is offered,
  Paged + spread on permits automatic spread, and filters use an inspector.
  Open/close the display with the reader already open: effective columns update
  without resetting layout/spread settings or the reading location. Resize with
  the filter panel open and closed; confirm navigation remains usable afterward.

For each device, cover Paged + spread off/on and Scroll (with stored spread on),
then reopen the reader/settings to confirm values persist. Include Light/Dark/
Sepia and normal/AX5 in the visual gate; existing controls, metadata, density,
detents, Apply/Reset and dismissal must remain usable. Fold/Book pose, reserved
regions, gutter placement and queue-browser split are explicitly outside this
verification; do not infer their readiness from a regular/regular result.

No visual correctness is claimed here. No build, commit, push, branch switch,
sign-in, AO3 request or `TASKS.md` edit is authorized for this worktree. Existing
untracked `Packages`, `Vendor` and other briefs are left alone. Local migration
notes were absent; the copy in `~/kudos-agent-ios2/READIUM_MIGRATION_NOTES.md` was
read without modification.
