# Duo5c — remove resize hold-and-restore

Written before code edits, then updated with the finished diff and source checks.
Branch: `claude/agent-ios-duo5c`, based on `64979c71`. Implementation is ready for
Claude's build/test/device gates; no runtime verification is claimed.

Paths below are relative to this worktree:

- **Book**: `kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift`
- **View**: `kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift`
- **Geometry**: `kudos-ao3-reader/Features/ReaderReadium/ReaderPageBoxGeometry.swift`
- **Host**: `kudos-ao3-reader/Features/ReaderReadium/ReaderDismissDrag.swift`
- **Tests**: `KudosTests/ReadiumReaderTests.swift`

## Scope

Removed (old references are at `64979c71`; new references are in the working diff):

- Locator capture and restore loop, including repeated `go(to:)`, restore-driven
  first-page presentation and the post-SDK-await cancellation check (old
  **Book:212,230–242**). The resize task now has only one await, its cancellable
  220 ms sleep, before synchronous inset refresh and metric scheduling
  (**Book:200–228**). It never reads or writes `currentLocator`.
- Same-href callback suppression (old **Book:730–739**); callbacks now flow straight
  from the existing dismiss gate to first-page presentation and locator handling
  (**Book:701–731**).
- Resize-only viewport/completion suppression (old **Book:1081**); the original
  dismiss gate remains (**Book:1042**).
- `pageBoxResizeLocator`, `hasReceivedNavigatorLocator`, `hasMeasuredPageBox` and
  their capture/set/reset/clear sites (old **Book:196–198,252,395,557–558**).
- The hold assertions in the old width-change test (**Tests:432** now checks only
  metrics, geometry debounce/cancellation and the last reported locator).

Kept:

- Text, loading skeleton and every control share the same horizontal safe padding;
  the background follows the padding and stays full-bleed (**View:968–987**).
  Direction-aware side insets remain in **Geometry:10**. View/Geometry unchanged.
- The host reports both dimensions and converted safe insets after layout and safe
  area changes (**Host:196–224**); host-based page box and chrome/status-bar
  protection remain in **Book:167–174,191–205**, **Geometry:17–36**. No screen seed.
- Immediate invalidation plus post-quiet clear/remeasure (**Book:208–221**), the
  measurement-only wait gate (**Book:845**), same-href unready-bar recovery
  (**Book:720**), and ordinary ready-state digit refresh (**Book:712,737**).
  Location/persistence callbacks do not wait for measurement.
- The bounded measurement retries and last-attempt escape hatch, including the
  two-sample requirement for vertical shrink (**Book:780,944–1000**), unchanged.
- DEBUG `-KudosDebugRotate` (**`kudos-ao3-reader/App/DemoLibrary.swift:359`**, call at
  **`kudos-ao3-reader/App/ContentView.swift:75`**), unchanged.

Only Book, Tests and this result were edited. No new UI or navigation layer.

## Location/persistence comparison

Compared directly with
`git show 97187d9a^:kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift`.

The `locationDidChange` method (**Book:686**) is text-identical to that reference
after excluding the retained same-href unready-bar branch (**Book:720–723**). The
position path is the original dismiss gate → first-page presentation → href/metric
handling → `currentLocator = locator` → scrub gate → `onLocatorChange`. Both
same-href and different-href callbacks are accepted during resize; the existing
scrub/dismiss exceptions are unchanged. `viewportDidChange` is text-identical to
the reference. Forward/back, link/locator commands, chapter progression seeks,
live scrub and the forced-inset refresh helpers also match that reference.

The sole delegate difference schedules page measurements when the bar is unready
and no geometry debounce is pending. It neither changes nor delays the locator or
persistence callback. Geometry debouncing/measurement invalidation is retained
from T-449 because the page count and seek denominator need the new size.

The persistence path is unchanged: **View:1383** serializes the reported locator
and calls `ReadiumProgressPersistence.note` (**`kudos-ao3-reader/Features/ReaderReadium/ReadiumProgressPersistence.swift:75`**).
Its debounced write callback (**View:1376**) calls the existing model write helper
(**View:765**, **`kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderPersistence.swift:10`**).
Mandatory flush (**View:913**) records the book's latest accepted locator before
asking `locatorForFlush`; it retains the existing successful-dismiss protection.
No held resize locator, cached text anchor or restoration command intervenes.

## Tests and regression sensitivity

- **Tests:432**, `aSameHrefWidthChangeSchedulesRemeasure`: adapts the hold test,
  retaining four cases (counts 8/24 × horizontal/vertical). Checks immediate metric
  clearing, cancellation of a superseded geometry sleeper, completed remeasure
  scheduling and publication after agreeing fresh samples. Removing geometry
  invalidation leaves the old ready count and fails the nil/not-ready assertions;
  removing cancellation fails `superseded.isCancelled`.
- **Tests:473**, `sameHrefLocationDuringResizeReachesCurrentLocatorAndPersistence`:
  starts with a delivered locator and measured bar, then resizes and sends two
  same-href locators before any await. Requires the first to reach `currentLocator`,
  the real persistence bridge and its eligible write callback. The second must
  advance the locator/bridge and be immediately flushable inside the debounce
  window. Reinstating T-449's hold and callback gate leaves the initial locator,
  no writes and no latest flush value, violating these assertions. This exercises
  the persistence bridge, not a SwiftData disk round trip or the SwiftUI lifecycle.
- **Tests:529**, `resizeDoesNotIssueARestoreGoTo`: source regression for no resize
  `go(to:)`, no resize first-page mark, and no hold field. Restoring the original
  method fails its first two assertions; restoring the hold also fails the third.
  Readium's concrete `go(to:)` methods are public, not overridable, so this avoids
  adding a production navigation seam for a deleted call. It requires the checkout
  at compiled `#filePath`, like existing `WritingTagPickerTests` source checks;
  it is not an SDK/WebKit runtime navigation spy.
- **Tests:545**, `finalLayoutAttemptKeepsItsFallbackButVerticalShrinkStillNeedsAgreement`:
  disagreeing first samples stay unready until the final-attempt fallback, then a
  vertical shrink still requires two samples even on final attempts. Removing the
  fallback fails readiness/count 24; bypassing shrink agreement fails the first
  shrink assertion.
- Geometry tests (**Tests:350,381,408**), meaningful-inset/status-bar test
  (**Tests:558**) and startup/page-turn/rearm test (**Tests:584**) remain verbatim.
  The startup test still checks immediate callback publication, recovery of an
  unready same-href bar without losing an agreeing sample, and ready-state turns
  retaining their measured count and measurement generation.

## Checks performed

`git diff --check` passes. A read-only Python source comparison passes for the
pre-T-449 delegate/navigation equivalence above, removed hold-only state, unchanged
View/persistence/geometry/host/debug/TASKS files, unchanged retry/fallback code and
the retained tests. The no-restore source predicate was also evaluated against
the original HEAD entirely in memory: it passes the working source and rejects
the original. No source files were temporarily reverted.

Swift tests, lint, builds, simulator and Duo checks were **not run**, per the task's
handoff boundary; behavioral test failures on reversion above are source reasoning,
not observed Swift mutation-test results. No sign-in, AO3 contact, branch changes,
commits, pushes, signing or `TASKS.md` edits. Pre-existing untracked brief files were
left intact. Next: Claude runs the iOS gates and the checks below.

## Simulator/device steps for Claude (not performed here)

1. Build/gate in the iOS lane. Open an already-local long chapter in paged mode;
   turn pages twice, then rotate using DEBUG `-KudosDebugRotate "12 landscape 26
   portrait"`. Repeat in scrolled mode. Wait without touching after each resize:
   text should present, page count/seek scale should settle to the new size, and
   later page turns should publish immediately without clearing the denominator.
2. During rotation, swipe/scroll, seek within the same chapter, choose a bookmark
   or Contents target (including a not-yet-loaded chapter), and follow a local EPUB
   link. Confirm the app never jumps back over the chosen navigation.
3. Close/reopen and background/foreground immediately after a resize callback;
   confirm the saved location matches the latest Readium position. Repeat with
   Read Aloud following, rapid rotations, and a slow local chapter load.
4. Check portrait/landscape with chrome shown/hidden: side-safe text, skeleton and
   every control, full-bleed background, stable status-bar top clearance. Repeat
   on Duo fold/unfold (including width-only changes) and iPad window resizing.
5. Include a chapter with a fixed-height image and a paragraph spanning several
   screens. This pass restores pre-T-449 position behavior; it does not promise
   that Readium itself preserves an exact text anchor through every reflow.
