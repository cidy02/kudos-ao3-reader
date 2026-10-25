# R451 — adversarial review of Duo5c

What this change does: Duo5c deletes the app's resize locator hold, callback
suppression and restore navigation. Readium again owns position through reflow;
the host geometry, side-safe padding and page-count remeasurement remain.

**Verdict: land. No confirmed P1, P2 or P3 defect found in this source review.**
This is not evidence that builds/tests pass or that resize presentation is correct
on a device. Those gates remain with Claude under the review's read-only rules.

## Target and evidence

Reviewed the actual working tree on `claude/agent-ios-duo5c`, HEAD/base
`64979c71f444d7ecc75301215d1f63b228844e02`, against both HEAD and the pre-T-449
reference `97187d9a^`. The two live Swift diffs match the corresponding sections
of `~/kudos-tools/out/backups/Duo5c.patch`. Read the Duo5c brief/result and R449/R450,
then checked their claims against source. All line references below are to this
working tree unless explicitly marked SDK or pre-T-449.

Paths used below:

- **Book:** `kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift`
- **View:** `kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift`
- **Persistence:** `kudos-ao3-reader/Features/ReaderReadium/ReadiumProgressPersistence.swift`
- **Host:** `kudos-ao3-reader/Features/ReaderReadium/ReaderDismissDrag.swift`
- **Container:** `kudos-ao3-reader/Features/ReaderReadium/ReadiumNavigatorContainer.swift`
- **Geometry:** `kudos-ao3-reader/Features/ReaderReadium/ReaderPageBoxGeometry.swift`
- **Tests:** `KudosTests/ReadiumReaderTests.swift`

Also inspected the local Readium checkout at
`~/Library/Developer/Xcode/DerivedData/kudos-polish/SourcePackages/checkouts/swift-toolkit`.
Its revision, `de07026e9f825a5791f27a7ac4cd6bb1a784ab8d`, matches `Package.resolved`.
SDK references are relative to its `Sources/` directory.

## Findings

None requiring a fix. In particular, there is no remaining resize-owned locator,
navigation-intent latch, anchor task, restoration retry or resize callback gate.
The retained task and flags concern measurement or existing dismiss/scrub behavior.
The sequences below explain why the earlier position-loss findings do not carry
over; they are source traces, not runtime reproductions.

| Sequence examined | Result and exact boundary |
| --- | --- |
| Established chapter A → resize → same-href callback B before the 220 ms sleeper finishes | `Book:701–731` accepts B into `currentLocator` and calls `onLocatorChange` synchronously, subject only to the original dismiss/scrub rules. The sleeper does not read or write the locator (`Book:200–228`). No resize-specific persistence delay. |
| Contents/bookmark/Find/Read Aloud selects B while resize is pending; or resize occurs while chapter B loads | The original commands dispatch directly (`Book:610–634`; `View:847,1635,1669,342`). Geometry never snapshots A and never issues a competing jump. A later different-href callback clears/restarts only metrics (`Book:707–711`). No old-chapter restore can win. SDK acceptance/load behavior remains the original behavior. |
| Native swipe/scroll or EPUB content link during resize | There is no hold gate in either locator or viewport ingestion (`Book:701,1044`). Native input/link navigation need not register app intent to escape a hold. The Duo5b command queue/pending-intent mechanism is absent. |
| Repeated size/inset reports → explicit navigation → last geometry sleeper finishes | Each meaningful report cancels its predecessor, clears metrics and starts one cancellable sleep (`Book:206–221`). After sleeping, work is synchronous: refresh insets, drop the task handle, clear metrics, schedule measurements. There is no SDK navigation await that could finish later and restore an obsolete passage. |
| Close/disappear or reopen during the geometry debounce | Close flushes the latest accepted locator before the original exit latch (`View:893–943`). Disappear cancels the geometry task before its final flush (`View:423–435`); `open` cancels it before resetting the book (`Book:519–533`). A canceled sleeper returns from its throwing sleep before acquiring a strong book reference. No held locator substitutes for the flush value. |
| Background/inactive while resize is pending; Read Aloud continues following | The existing immediate flush remains (`View:405–421,913–943`), and speech follow still calls the original `go(to:)` wrapper (`View:338–342`). The geometry task is not suspended merely by backgrounding, but can only refresh insets and measurements. Later SDK callbacks use the unchanged persistence debounce. No app restoration competes with speech. |
| Seek-slider drag/release overlaps a resize | Geometry clears readiness, temporarily disabling the slider (`View:1148–1151`; `ReaderPositionCard.swift:131`). Live seeks and release retain their original ready-state checks and position-list fallback (`View:1830–1844,1866–1900`). `currentLocator` still advances during scrubbing; only streamed writes are skipped, exactly as before (`Book:725–731`). Close/background flush reads it directly. Actual UIKit cancellation/release delivery during a resize remains a device check. |

The retained `isLocatorIngestionBlocked` is **only** the pre-existing dismiss
interaction/exit latch (`Book:149–161`); resize never raises it. The
`pageBoxRemeasureTask == nil` conditions at `Book:720,845` gate scheduling/sampling,
not navigation, locator acceptance or persistence. `isScrubbing` is likewise an
existing user-interaction gate, not a remnant of the resize hold.

I rejected a candidate “resize during canceled peel leaves the bar unready”
finding: the custom dismiss recognizer is not installed in this tree
(`Container:149–168`). Its freeze handlers cannot establish that production
sequence. No finding is based on calling those dormant handlers directly.

## Is the position path exactly pre-T-449?

**The locator/persistence path is restored; the geometry/measurement behavior is
deliberately different.** An in-memory source comparison established:

- `locationDidChange` is text-identical to pre-T-449 after removing the retained
  unready-bar rearm branch (`Book:720–723`). That branch schedules metrics before
  the same synchronous locator assignment/callback; it introduces no await.
- `viewportDidChange`, forward/back, link/locator/spine navigation, progression
  seek, live scrub and the settled-digit refresh method are text-identical.
- `ReadiumProgressPersistence.swift`, `ReadiumReaderPersistence.swift` and
  `ReadiumNavigatorContainer.swift` are byte-identical to pre-T-449. The View's
  locator-to-persistence wiring (`View:1376–1390`), flush (`View:913–943`), speech
  follow and slider-release methods are also unchanged.
- All three hold-only fields are gone: `pageBoxResizeLocator`,
  `hasReceivedNavigatorLocator`, `hasMeasuredPageBox`. No Duo5b navigation layer
  was introduced. The resize method has no `currentLocator` access, `go(to:)`
  or first-page presentation mark.

What remains different is intentional: host-based width/height/insets replace
the global screen/window seed, side-safe padding changes the navigator's usable
width, and geometry clears/rearms page measurement (`Host:196–224`;
`Geometry:17–36`; `View:969–987`; `Book:200–221,1224–1243`). The delayed refresh
does enter the SDK, but its `safeAreaInsetsDidChange` only reapplies content insets:
scroll-view insets in scroll mode, WebView top/bottom constraints in paged mode
(`SDK Navigator/EPUB/EPUBReflowableSpreadView.swift:71–74,99–112`). It does not
dispatch a navigation command. Measurements evaluate a read-only page-sampling
script and publish metrics (`Book:808–830,840–906`).

Thus equal SDK callbacks follow the old position path. This does **not** prove
that the SDK produces an identical passage through every newly sized viewport.
Readium's own pending-location scroll remains
(`SDK Navigator/EPUB/EPUBReflowableSpreadView.swift:147–165`), and the earlier
mixed-image/long-paragraph limitations are not cured by deleting the app layer.
They are not new Duo5c position-preservation claims.

## Do ordinary page turns publish the bar at once?

They publish the **locator/persistence notification immediately**, retain a ready
bar and keep its denominator. Same-resource ready callbacks do not clear metrics
or increment `pageBarMeasureGeneration` (`Book:712–731`). The same-size geometry
guard does not start a sleeper (`Book:206`).

“At once” is not literally synchronous for the **page digit**: the original
touch-armed JavaScript trailing report waits 140 ms (`Book:1177–1185`), while the
Swift settled-digit refresh waits 220 ms (`Book:737–752`). These paths predate
T-449. Following a genuine resize, the bar is deliberately unready until fresh
measurements agree; its initial normal schedule begins after the 220 ms quiet
period, with 250/450 ms samples (`Book:211–221,762–773`). That is measurement
latency, not delayed position persistence.

The rearm replaces older measurement generations while preserving an already
accepted pending count (`Book:762–765,968–977`). It cannot suppress a locator.
I did not establish a production callback-starvation regression: the pinned SDK
itself debounces scroll progression notifications by 300 ms
(`SDK Navigator/EPUB/EPUBReflowableSpreadView.swift:396–410`), and the first
measurement tick is 250 ms. This is source reasoning, not a timing guarantee under
load. The bounded final-attempt fallback and vertical-shrink agreement logic are
unchanged (`Book:780–795,944–1026`).

## Do the tests cover what was removed?

Yes for the removed callback suppression and a direct restoration call; not as an
end-to-end WebView/persistence test.

- `Tests:473–525` establishes a delivered locator and measured bar, resizes, then
  delivers two same-href callbacks before yielding. It checks the latest book
  locator, the real persistence bridge, its first eligible write and the second
  callback's immediate flush value, then waits for the geometry task and checks
  the latest locator again. Reinstating T-449's hold/gate would fail the locator
  and persistence assertions. No synthetic fragment anchor is needed here.
- `Tests:529–543` checks the resize method's source for a direct `go(to:)`, a
  first-page mark and the original hold field. Restoring the original method
  fails these predicates. It is a source guard: an indirect navigation helper
  under a new name could evade it. The delegate fake is never installed as
  `book.navigator` (`Tests:642–648`), so no runtime navigation spy is exercised.
  That limitation is accurately disclosed in the implementation result.
- `Tests:432–470` covers immediate invalidation, superseded sleeper cancellation,
  remeasurement scheduling and fresh count acceptance for grow/shrink and both
  axes. Count samples are injected through `acceptLayoutPageCount`; the test
  does not measure an actual document.
- `Tests:545–555` checks final-attempt fallback and the retained two-sample
  vertical shrink rule. `Tests:558–581` covers status-bar/inset scheduling.
- `Tests:584–637` checks startup callback delivery, unready-bar recovery with a
  preserved agreeing sample, and ready ordinary turns retaining count and
  generation. It **does not assert that a turn updates `visualPage`**, and cannot
  prove the displayed digit changes without a WebView. It also injects count
  samples directly rather than exercising scheduled JavaScript evaluation.

None of these tests performs actual Contents/native-link/TTS navigation during
reflow, a resize with the slider held down, a SwiftData disk save/reopen, or a
scene-phase lifecycle transition. The smallest additional validation is Claude's
local EPUB device/simulator pass: ordinary turns with visible digits; resize plus
each navigation route; slider release followed by normal scrolling; close/reopen
and background flush during the debounce; slow load without input. A new
production navigation abstraction is not required merely to test a deleted call.

No Swift tests, builds, lint, mutation runs, simulator/device actions, sign-in or
AO3 traffic were performed. No branch changes, commits, pushes or task-board/source
edits. Only `docs/android-port/briefs/R451-result.md` was written. No code fix is
required by this review; runtime presentation and exact SDK passage retention
remain unverified.
