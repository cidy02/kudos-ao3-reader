# Duo5 — reader survives a change of size

**Round 2 handoff to Claude; startup page-bar fix and regression test written, recheck outstanding.**
Codex, 2026-10-24, `~/kudos-agent-ios2`, `claude/agent-ios-duo5`, base
`d9e0d44f` (T-446). This result file was written before source edits.

No build, simulator run, commit, push, branch switch, sign-in, or AO3 request was
performed. TASKS.md, project.pbxproj, macOS, and Duo4's shelf/card files are untouched.
The pre-existing untracked briefs are preserved. Claude supplied the missing
`READIUM_MIGRATION_NOTES.md`; it was read and checked against the current code and
locally checked-out Readium source rather than treating its June POC notes as current.

## Round 2 — ordinary page turns after opening

Claude reports that round 1 builds and six reader suites pass (92 tests) in
`~/kudos-ios-polish`. On the iPhone 17 simulator, paged counts reflowed **4 → 5 → 4**
and scrolled counts **3 → 4 → 3**, text/controls cleared the Island side, and the
passage survived the round trip. Those are Claude's results for round 1, not a
runtime claim for this follow-up patch.

Claude also restored the **final-attempt bypass** in `acceptLayoutPageCount` and
changed the two resize-test samples to `isFinalAttempt: false`. Both changes are
preserved. The bounded last tick uses an actual viewport measurement when the
height will not converge; it does not derive a count from progression/positions.
The comments beside the scheduler now describe that existing exception correctly.

The regression is visible in Claude's
`~/kudos-tools/out/duo/pagebar-cmp.png` (Duo5: “Page …”, base: “Page 4 of 4”) and
`~/kudos-tools/out/duo/rotate-mid2.png` (m1, before rotation). Both images were
inspected here. The displayed progress is also stale (25% versus base 38%).

**Cause found in code:** `open` seeds `currentLocator` before the first navigator
settle. The round 1 geometry handler treated any second host report as a resize
of an established viewport and could capture that seed during opening. Its
restore hold swallows same-href location callbacks; while the restore task owns
the viewport, layout/digit measurements are also skipped. Readium can reject a
jump during its initial load, so an opening inset update could unnecessarily
enter the restore retry loop instead of allowing the normal opening stream.
Separately, a same-href callback with `pageBarReady == false` did nothing: once a
bounded measurement sequence had expired without a usable sample, page turns
could never rearm it. This explains why changing chapters or rotating could
recover a bar that ordinary turns could not. The exact first host report that
occurred in the captured run was not logged; this is a source-level causal path,
not a claim to have collected a runtime geometry trace here.

**Fix:** a locator hold now requires an existing host box, an actual accepted
navigator location, and a previously trusted visual page count. That last fact
is latched across temporary metric clears, so an established reader still keeps
its passage if a real resize happens while the page bar is remeasuring. A seeded
locator or a skeleton timeout alone is insufficient. Opening geometry still updates the box
and schedules measurement, but does not start a competing locator restore. A
same-href settle with an unready bar rearms layout measurement once the geometry
task has released the viewport. A replacement schedule invalidates older ticks
without resetting the pending agreement sample. Ready same-href turns continue
to use the original digit-only refresh. Established viewport resizes still hold
the exact locator and use clear + scheduled remeasurement.

Round 2 source changes: `ReadiumBook.swift:197` / `:198` (actual-location and
established-measure flags), `:212` (hold eligibility), `:395` (latch the first
accepted measure), `:557` / `:558` (reset on open), `:739` (mark an accepted
location), `:756` (unready same-href recovery), `:798` (replace stale retry
generations).
The existing measure generation has a read-only internal getter so the regression
test can assert that the actual scheduler was invoked, without a test-only counter.

New test: `KudosTests/ReadiumReaderTests.swift:481`,
`startupInsetSettlingDoesNotSwallowOrdinaryPageTurns`:

- Seed portrait geometry and the first same-href locator, before a trusted count.
- Supply the later Island/home-bar inset report without changing width/height.
- Deliver two page-turn locators while the geometry task is pending. Both must
  advance `currentLocator` and reach the persistence callback, rather than being
  swallowed by a resize hold.
- Let the quiet task finish, then deliver another same-href settle with an unready
  bar. The real layout scheduler's generation must advance.
- Feed one non-final sample, deliver another settle/recovery, then feed the second
  agreeing sample. The bar becomes **Page 4 of 4**; recovery must not clear the
  first agreement. This part checks model acceptance, not live WebKit sampling.
- Deliver a ready page turn: its locator advances, readiness/count remain, and
  the full-measure generation does not change (the existing digit path owns it).

Expected mutation failures, **not executed here**: restore round 1's geometry-only
hold condition and the locator/persistence assertions fail; remove the unready
same-href recovery and the generation assertion fails; clear pending metrics when
rearming and the two-sample readiness assertion fails. Keep the internal getter
when applying those behavioral mutations. The earlier four-case real-resize
model test now also clears the previously trusted metrics before resizing. It
still asserts that transient locators are held: temporarily unready metrics must
not turn an established reader back into the startup case.

**First simulator check for this patch:** launch Night Market in Paged with the
same local fixture/resume state as the comparison; do not pass the rotate hook.
Wait **12 seconds**, swipe left twice in the same chapter, then tap to show
chrome. Expect **Page 4 of 4** and the current chapter progress immediately as on
the base comparison, with an enabled seek slider. Wait another 5 seconds and
check it is still ready. Turn back once and forward once and confirm X follows.
Repeat after a cold open and a saved-position reopen. Then repeat Claude's
rotation pass: paged **4 → 5 → 4**, scrolled **3 → 4 → 3**, preserved passage,
chrome shown/hidden and Read Aloud. The longer sequence below remains applicable.

Round 2 checks here: full no-cache lint (app + changed test file), targeted lint,
mechanical invariants, and `git diff --check` pass; only pre-existing warning
categories remain. The new test and behavioral mutations have not been run.

No build/test execution, simulator/app control, commit, push, branch switch, or
TASKS.md edit was performed for round 2. A read-only `simctl list devices booted`
query failed under the sandbox's CoreSimulator/XPC restrictions; no simulator
state was changed. Round 2 still needs Claude's build, targeted tests, mutation
check and no-rotation screenshot before claiming the regression is visually fixed.

## Changes and reasons

Paths below are relative to the repository root.

| File:line | Change and reason |
|---|---|
| `kudos-ao3-reader/Features/ReaderReadium/ReaderDismissDrag.swift:196` | The peel container reports layout and safe-area changes. After the current layout turn, it reads **its own bounds**, converts **its attached window's safe frame** into host coordinates, and forwards all four exclusions (`:216`). This avoids both a global key-window lookup and the child hosting controller's deliberately suppressed safe areas. Reports are coalesced and delivered outside SwiftUI's update/layout pass. |
| `kudos-ao3-reader/Features/ReaderReadium/ReaderPageBoxGeometry.swift:17` (new) | A small geometry value replaces the height-only freeze. A difference **greater than 1 pt** in width, height, or any inset invalidates the box. Invalid/pre-layout dimensions and <=1 pt noise retain the previous box. Valid zero insets replace stale nonzero values. A top-only disappearance of the status inset retains the previous top while chrome is hidden or transitioning; a real size/other-inset change accepts the complete new safe area, even with chrome hidden. |
| `kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift:967` | The whole existing page/chrome surface is padded to the host's safe width (`:986`) **before** its full-bleed theme background. This includes prose, loading skeleton, top bar, fan and its pills/actions, highlight colour bar, position/seek card, and both forms of the Read Aloud mini-player. No controls or metadata were removed, and existing interior margins remain. `ReaderPageBoxGeometry.horizontalInsets(in:)` (`:10`) maps physical left/right correctly in either layout direction. |
| `kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift:203` | Host geometry seeds the box, replacing `UIScreen.main.bounds.height` and the old height-only refresh. A meaningful change immediately clears old metrics and cancels/replaces a 220 ms quiet-period task. Once quiet, it refreshes the existing spread insets, restores the held locator through Readium without animation, then runs the existing **clear + scheduled remeasure**. A busy/loading navigator that rejects the restore is retried at 220 ms intervals with the locator still held; a replacement resize, close, or reopen cancels the task. The initial host seed also refreshes insets, so a pre-layout zero query cannot leave the first page uncorrected. |
| `kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift:730` | During reflow, same-href location callbacks cannot overwrite the held passage or send a transient pixel-offset locator to persistence. The original locator survives a burst of geometry updates. A different-href navigation releases that hold so a deliberate chapter change can win. Transient viewport callbacks cannot mark a held resize as completed (`:1081`). No progress-to-page guess or book reopen is used to restore position. |
| `kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift:881` | Layout/digit measurements wait while the resize task owns the viewport. Generation invalidation rejects older samples, including ones already awaiting JavaScript. The new count is measured from the new visible viewport, so clearing permits either growth or shrinkage. The user-scroll bridge remains touch-armed and cannot first-publish a count. A competing injected JS resize listener is unnecessary: UIKit host size/safe-frame changes own this invalidation. |
| `kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift:980` | Existing two-sample agreement and scroll jitter tolerance are retained, including Claude's restored final-attempt escape hatch for the bounded last tick. Vertical shrink keeps its agreement guard. `acceptLayoutPageCount` is internal to test the real non-final guard; no count is fabricated from progression. |
| `kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift:1261` | Vertical insets use the same host geometry. The existing line-grid snap, bottom-room formula, text style, and Customize margins are retained. Horizontal delegate insets remain zero **because the navigator itself now occupies the safe width**. |
| `kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift:165` | A 0.6 s chrome-transition grace period also preserves the top inset when showing chrome lays out once before UIKit has restored its status bar. This complements the hidden-chrome freeze; genuine nonzero top changes and real geometry changes still invalidate. |
| `kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift:249`, `ReadiumReaderView.swift:422` | Cancel the stored resize task/locator hold on disappearance and before reopening. An old resize must not restore a position into a replacement open. A successful restore also lifts the initial page skeleton if the first location arrived during the hold. |

**Why constrain the navigator rather than return left/right delegate insets:** the
locally pinned Readium `EPUBReflowableSpreadView.setupWebView` pins its web view's
leading/trailing edges to the spread. Its `updateContentInset` consumes only top
and bottom in paged mode, and clears the web scroll-view inset. Merely returning
left/right at the former `ReadiumBook.swift:1234` would not protect paged text.
Readium's `Scripts/src/utils.js` resize observer snaps pixel offsets, and its
`snapCurrentPosition` exits in scroll mode; retaining the app's locator alone
would not guarantee the visible passage. The settled restore uses the existing
Readium locator API. The speech engine/session is not restarted or reconfigured.

## Tests and checks

Six new `@Test` methods (nine cases including the four-case parameterized test)
are in the existing iOS-only `ReadiumReaderTests` suite. **They have not been
compiled or executed here**, per the no-build rule. The failure descriptions below
are mutation expectations for Claude to verify, not claimed executed results.
Keep the new internal test seam when applying behavioral reverts.

| Test:line in `KudosTests/ReadiumReaderTests.swift` | Coverage / expected failure when behavior is reverted |
|---|---|
| `pageBoxUsesBothDimensionsAndMeaningfulInsetChanges:325` | Width-only, height-only, same-size side exclusions, valid zero replacements, asymmetric physical insets in LTR/RTL. Removing width from the key leaves 466 instead of 951; ignoring safe changes leaves old insets; treating zero as “use old” fails the zero assertion. |
| `pageBoxKeepsStatusBarClearanceButAcceptsRotationWithChromeHidden:356` | Cover 466×678 → inner landscape 951×669 → inner portrait 669×951, including side-only reserved-area changes. Removing status protection changes the top from 62 to zero; keeping all old safe insets on a real transition leaves portrait clearance in landscape. |
| `pageBoxIgnoresPrelayoutAndOnePointNoise:383` | Initial host seed; zero width/height; exactly 1 pt tolerated, >1 pt accepted. Removing the size guard clobbers the valid box with a zero dimension; removing tolerance accepts the 1 pt jitter. |
| `aSameHrefWidthChangeSchedulesRemeasureAndKeepsTheLocator:407` | Previously trusted count 12, temporarily cleared before resizing; same-href width-only update; old metrics clear, task exists, transient progression 0.1 cannot replace the saved 0.4 locator/fragments or emit a persistence write; the next height update cancels the first task. After settling, measured counts 8 and 24 are accepted only after two samples, for both horizontal and vertical samples. Removing resize scheduling/clear leaves the old count or no task; removing the locator hold loses the locator and emits a write; accepting the first non-final sample fails the readiness assertion. |
| `aSameSizeInsetChangeSchedulesButStatusBarHideDoesNot:455` | A top-only status-bar hide and the first showing-chrome layout keep top 62 and schedule nothing. A same-size side-exclusion change schedules a task; explicit teardown cancels it. Ignoring safe-area-only changes leaves the task nil; removing the chrome grace schedules a spurious resize when showing chrome. |
| `startupInsetSettlingDoesNotSwallowOrdinaryPageTurns:481` | Round 2 regression: opening inset settling permits two same-href page/persistence updates; an unready settle rearms measurement, agreement survives recovery, and ready page turns retain the digit-only path. Behavioral mutation expectations are detailed above. |

The delegate test double has an empty in-memory publication and never loads or
requests content. It tests scheduling/hold/acceptance logic, **not** UIKit safe-frame
conversion, actual WKWebView layout samples, or the concrete navigator's restore.
Those remain the simulator checks below. Existing `ReaderTimeEstimateTests`
(page-box arithmetic), `ReaderPageMetricsTests`, `ReaderChapterScrubTests`,
`ReaderPageSampleTests`, and `ReadiumProgressPersistenceTests` should also run.

Executed here:

- `Scripts/check-invariants.sh` — **PASS**.
- `git diff --check` — **PASS**.
- `swiftlint lint --quiet --no-cache kudos-ao3-reader` — **PASS**, existing warnings.
- Targeted no-cache lint of all changed Swift files, the new geometry file, and
  `ReadiumReaderTests.swift` — **PASS**. The changed reader files have the same five
  warning categories/locations as baseline (file/type length and the existing
  `.filter(...).first`); the new helper and tests have none. Baseline was linted
  from `git show HEAD:<file>` copies in `/tmp`, without altering the worktree.
- `Scripts/lint.sh` — its normal cached run exited 1 because the sandbox denied a
  SwiftLint cache plist write outside the worktree. The complete no-cache run
  above avoids that write and passed. No approval or permission change is needed.

Claude: build/test/gate in `~/kudos-ios-polish`, run the new tests and behavioral
mutations there, then the applicable normal gate. Round 1 results reported by
Claude are recorded above; round 2 has not been built or run here. No adversarial review or human screenshot gate has
been completed here.

## Exact simulator steps for Claude

Use the iPhone 17 simulator with its device bezel/Island visible, rotation unlocked
in the simulator and in the reader's fan (open padlock). Keep the same font, size,
line height, and margin throughout each rotation comparison. Use the existing local
Night Market sample and **real `demo_work.epub`**, not a placeholder download or
bare `sample.epub`. Its launch route is supported by
`App/DemoLibrary.swift:625`; fixture installation is at `:576`.

From `~/kudos-ios-polish`, after Claude's normal build/install, launch the installed
Debug app as follows (replace the UDID and bundle id with that build's values):

```sh
xcrun simctl launch <udid> <bundle-id> \
  -KudosDemoLibrary YES -hasCompletedOnboarding YES \
  -KudosFixtureDir /Users/cidy02/kudos-ios-polish/KudosTests/Fixtures \
  -KudosDebugRoute 'read:Night Market' -readerMode scroll
```

If the app is already running, terminate it before using launch arguments. The demo
mode blocks AO3 requests and installs the local EPUB; no sign-in/download is needed.
For the paged run repeat this launch with `-readerMode paged` (or select **Paged**
in the reader's Themes & Settings sheet). Do not relaunch between rotations within
a run: this is a **live, same-chapter** resize test.

1. **Portrait, scrolled, baseline.** Open Contents and enter a long story chapter
   in the fixture. Scroll to a distinctive paragraph about one third through it,
   away from the chapter boundaries. Record the chapter label, passage, percent,
   and settled `Page X of N`; keep a screenshot. Tap the page to show chrome.
   Expect the current top/position controls and all metadata to be present, with
   the existing density. The background fills behind the Island and home bar.

2. **Scrolled, chrome up, portrait → landscape left.** Rotate once without
   scrolling, turning a page, touching settings, or choosing a chapter. Let the
   layout settle. Expect the same chapter and passage to remain visible; a
   different line break/top offset is normal. Prose, close/title, fan button,
   position card, slider and colour bar stay inside the **side** safe regions.
   No full-width white/black strip appears at a padded edge. Open the fan and
   check its longest pills and round actions as well as the closed fan button.
   During remeasure, `Page …` and a temporarily disabled seek slider are expected;
   the old denominator must not remain usable. Once ready, both X and N come from
   the new layout. Normally the front-loaded agreement is ready roughly 0.7 s
   after the last geometry change (220 ms quiet + 250/450 ms samples); allow the
   bounded later retries on slow layout, never demand a guessed number.

3. **Scrolled, chrome up, return to portrait.** Rotate back without a reading
   gesture or settings/chapter change. Expect the original passage and a
   denominator consistent with the original portrait layout. The count may
   shrink on one direction and grow on the reverse; require both directions to
   recompute. After each settle, scroll by about one viewport, show chrome if
   needed, and verify X changes on the current scale. Drag the seek thumb to a
   distinctive mid-chapter point and release: it must land there with a matching
   page label and no correction to the previous orientation's scale.

4. **Scrolled, chrome down.** Return to another distinctive mid-chapter passage,
   hide chrome, rotate to landscape and back, then show chrome after each settle.
   Expect passage/chapter/percent continuity and refreshed counts even though no
   chrome was visible during resize. Repeat with **landscape right** so the side
   exclusions exchange sides. In each orientation, toggle chrome several times
   without moving the page: first ink and page count must stay stable; top/fan
   controls must not jump toward the edge while the status bar animates.

5. **Paged, chrome up.** Switch to Paged, choose the same long chapter, and turn
   several pages into it. Record a visible sentence plus X/N. Rotate portrait →
   landscape → portrait mid-chapter with chrome up, without a page turn during
   the rotation. Expect the saved passage to be on the reflowed page (the page's
   first word/X can differ), no jump to chapter start, safe side clearance, and
   the same temporary `Page …`/disabled-slider behavior followed by an agreed
   count. Repeat landscape right. Do **not** expect a two-page spread: existing
   spread/idiom behavior was deliberately left in place.

6. **Paged, chrome down and seek scale.** Hide chrome on another mid-chapter page,
   rotate out and back, then reveal it. Expect the same passage and a count for
   that orientation. Turn forward once and backward once: X follows actual pages
   and returns; N remains stable. Drag the seek thumb to about one quarter, then
   three quarters of the chapter. Release at each point and turn once: the
   displayed X, thumb scale, and actual page turns agree with the new N. Repeat
   after the reverse rotation to cover both increasing and decreasing N. Do not
   substitute a font or chapter change for the resize: those already remeasure.

7. **Read Aloud in both modes.** At a mid-chapter passage, start Read Aloud from
   the fan with an already available voice (the system fallback is sufficient;
   no pack download). With chrome up, rotate portrait → landscape → portrait
   while speech plays. Expect continuous audio, the same speech session/voice,
   and normal sentence following; the integrated mini-player and position card
   stay clear of both side exclusions. Hide chrome while still speaking and
   repeat both rotations: the standalone mini-player stays fully reachable,
   including play/pause, skip and Stop. Show chrome again and verify fresh X/N.
   Audio must not restart the chapter or replay the opening on rotation. Pause,
   inspect the current passage, rotate once more and resume: it resumes speech,
   rather than creating a replacement session.

8. **Resume and a resize burst.** With speech stopped, rotate out and back rapidly
   twice at a recorded passage, then wait for the last orientation to settle.
   Expect no stale count flashing in from an earlier orientation. Close the
   reader immediately after another settled resize and reopen Night Market
   normally from its work page/Library (avoid a fresh forced launch route).
   Expect the saved passage/chapter, with the current orientation's freshly
   measured count. Repeat once in each reading mode. Also change chapter just
   after a rotation and confirm the chosen chapter wins over the resize hold.

Capture at least portrait/landscape in each mode with chrome up, one fan-open
landscape, and the coupled/standalone Read Aloud mini-player in landscape. Record
actual X/N before/after in both directions and the visible passage, not only a
screenshot with controls. If the fixture's N happens to match in both orientations,
use a longer existing fixture chapter or larger text **before** starting a new
comparison; prove an N growth and shrink without changing settings mid-comparison.

## Remaining questions / gates

- No product decision is needed to continue. The missing notes are resolved.
- Claude verified round 1 rotation/passage/side-clearance results above. Round 2
  still requires the no-rotation reproduction and a repeat rotation pass; speech
  follow timing and page/seek behavior require the longer simulator sequence.
  The unit test uses a delegate-only double and cannot establish those runtime
  properties.
- The restore retries Readium's existing locator API while it is busy. Claude
  should specifically watch rapid rotations while Read Aloud follows a new
  sentence and rotations during a chapter load. While no restore has succeeded,
  the saved passage stays protected and the page bar stays unready; teardown
  cancels the retry. Its concrete UIKit timing has not been verified here.
- Duo cover/inner hardware sizes, fold/hinge transitions, Book pose and two-page
  spreads remain outside this task. Arithmetic tests use the supplied sizes;
  there is no claim that a simulator rotation verifies a real fold.
- All changed files remain uncommitted for Claude to review, build, gate and
  integrate from this branch/worktree. No port to macOS is intended.
