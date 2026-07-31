# Human-must-verify checklist — reader redesign polish (T-150)

Working branch: `from-keen-cori-d0a989` (uncommitted WIP in the main checkout,
never the `com.cidy02.Kudos.NewReader` A/B identity). This file tracks
everything from `report_and_handoff.md` §4/§6 that genuinely needs a human's
eyes on a physical device — timing, visual perception, live AO3 auth, or
real multi-device hardware — none of which a simulator or a unit test can
stand in for. Everything *not* on this list was fixed and is covered by an
automated test or a code-level correctness argument recorded in
`report_and_handoff.md` / `TASKS.md` (T-150).

Installed to your iPhone (`com.cidy02.Kudos`) after this batch. Check items
off as you confirm them; leave notes inline if something looks off so the
next session can act on specifics instead of re-discovering them.

## Page bar (C3/C4 — dual-agree state machine)

- [ ] Open a work mid-chapter → shows "Page …" briefly, then the correct
      swipe-scale count (not a Readium position-list number like "2 of 13")
- [ ] Chapter next/back (fan menu or edge tap) → no wrong-then-right digit
      flash; slider doesn't jump to 0 mid-measure
- [ ] Same-chapter page turn (swipe and edge tap) → digit settles once, cleanly
- [ ] Scrub the chapter-local slider → visual page shown matches where you land
- [ ] **Specifically watch for a page bar that stays on "Page …" for several
      seconds and never resolves** — this would mean the new bounded-retry
      dual-agree gate (C4 fix) is failing to converge on your device/network;
      previously a rare case would have shown an unconfirmed number instead of
      staying honest, so "stuck longer than before" is possible even though
      it's the intended tradeoff. If you see it stay unresolved for more than
      ~5-6 seconds on any chapter turn, that's a real bug — note the work/chapter.
- [ ] A **vertically scrolled** chapter whose page count should shrink (e.g.
      after a font-size decrease) — confirm the bar eventually updates to the
      smaller count rather than staying inflated (C3 fix)

## Layout / padding (C2/C6)

- [ ] Top/bottom dead space isn't double-stacked (Dynamic Island + first line
      of text; last line + home indicator) — this was the original "airy
      chrome" bug you reported and screenshotted; confirm it stays fixed
- [ ] Toggling chrome (tap to hide/show) does not visibly shift the text or
      thrash the page count

## TTS

- [ ] Start read-aloud → mini player appears in the bottom card; hide chrome →
      mini player goes standalone; show chrome → recouples into the card
- [ ] Lock the phone / open Control Center while reading aloud — Now Playing
      shows title/artist, play/pause, **and** a duration/elapsed readout paced
      by the TTS rate (not the silent-reading estimate). Change the Read Aloud
      speed and confirm the total time moves the right way (faster → shorter).
      The model is an approximation (~160 wpm at 1.0×) — sanity-check that it's
      in the right ballpark for a chapter you know, not that it's exact.
- [ ] Tap Stop on the mini player, then check Lock Screen / Control Center —
      the transport widget should be gone entirely, not stuck showing a dead
      session (T2)
- [ ] Settings → Read Aloud → "Open Settings for More Voices" — now opens this
      app's own Settings page, which is as far as iOS lets a third-party app
      navigate. (The private `App-prefs:` deep links were removed: on iOS 26.5
      they reported *success* while landing on Settings → Apps, which is worse
      than not trying.) Confirm the footer's manual path reads correctly for
      your iOS: **Settings → Accessibility → Read & Speak → Voices →
      (Language) → Voice**.

## Annotations / highlights

- [ ] Highlight text → recolor → delete → confirm the Highlights list (Contents
      sheet) updates correctly
- [ ] If you have iCloud/folder sync configured on a second device, or can
      simulate it: create the *same* highlight (same passage) independently on
      two devices, sync, and confirm only one highlight survives with the
      newer edit winning (ANN-8) — this is the one item here that's hard to
      fully exercise without a second real device or manually crafted backup
      files; the merge logic itself is unit-tested (`ReadingAnnotationBackupTests`)
      but the end-to-end multi-device path isn't

## Title pill → Work Details (A2)

- [ ] While reading, tap the title/author pill at the top → Work Details opens
      as a sheet over the reader (expected) → tap "Read"/"Continue Reading" in
      that sheet → it should simply dismiss back to the reader you were
      already in, **not** open a second reader on top

## Find in Work (search)

- [ ] Search a generic word likely to appear early in the book (e.g. "the") —
      confirm "This Chapter (Ch. N)" still appears promptly near the top of
      results, not buried after Preface/Summary/Chapter 1 hits
- [ ] Search a specific phrase — confirm grouping still reads correctly:
      This Chapter first, then remaining chapters ascending
- [ ] Swipe a result row → confirm Go / Bookmark / Copy actions work as expected

## Kudos / comments (live AO3, always manual)

- [ ] Give kudos from inside the reader on a real logged-in session — button
      shows outline-only before, filled AO3-red after
- [ ] From the afterword, tap "drop by the Archive and comment" — confirm it
      opens the in-app Comments sheet for *this* work (not a browser), and that
      the original AO3 link still exists as a fallback somewhere reachable

## Known, deliberately not fixed this pass

- **A4** — now down to a **single** lint error (`file_length`) from the original
  three; the large tuple and the over-long struct body are both fixed. See the
  audit section at the bottom of this file for what was done and for the
  scoped plan for the remaining file split.

**ANN-2 is now decided and implemented** (you chose recolor, 2026-07-28):
re-highlighting a passage with a *different* colour recolours it in place;
the *same* colour still toggles it off. Worth a quick on-device confirm that
both directions feel right.

## Fixed this pass, confirmed via build/test only (lower risk, spot-check if convenient)

- macOS build was actually broken by the WIP (`Color(.systemBackground)` and
  `.toolbar(.hidden, for: .navigationBar)` are iOS-only APIs, used unguarded
  in `WorkCardActions.swift`'s reader-restoration skeleton) — fixed with
  `#if os(macOS)` guards. If you use the Mac app, worth a glance at the
  Library "restoring EPUB" skeleton screen once, though it's a low-traffic path.

---

# Audit pass (2026-07-28) — findings

Sanity-check audit of this branch's changes, focused on the high-risk areas
(page-bar state machine, live scrub, annotations, KudosBackup/iCloud sync).

## Bugs found and fixed

1. **ANN-8 note salvage didn't stamp `lastModifiedAt`** (`KudosBackup.swift`,
   `dedupeSamePassageAnnotations`) — real sync data-loss bug. When the dedup
   rescued a note from the losing duplicate onto the winner, it left the
   winner's `lastModifiedAt` untouched, so the *next* merge would see a
   "newer" remote copy of that winner (still note-less) and overwrite the
   rescued note — silently undoing the salvage. Now calls `markModified()`.

2. **Live scrub piled up unstructured Tasks** — the cause of the sluggishness
   reported on-device. `go(to:)` spawns a `Task` per call, so one navigation
   per page crossed meant a fast drag queued a backlog that kept resolving
   after the finger had moved on (and a late one could land last, leaving the
   wrong page showing). Replaced with `scrubToProgressionInCurrentResource`,
   which keeps at most one navigation in flight and redirects it to the newest
   thumb position — flat cost regardless of drag speed. Also dropped the fixed
   90 ms time gate, which only added lag now that backpressure is handled
   properly, and suppressed the debounced progress write during a drag.

3. **`isScrubbing` could latch on and silently stop persisting progress** — it
   gates the debounced progress write, so a drag that never delivers
   `onEditingChanged(false)` (view torn down mid-gesture, slider disabled
   mid-drag) would leave it stuck true for the rest of the session. Added a
   release in `onDisappear`.

4. **`addBookmark` could stack duplicates at one spot** — it never checked for
   an existing bookmark. Now guards on resolved `position`, matching how
   `bookmarkAtCurrentPosition` decides the button's filled state.

5. **ANN-9 was implemented but untested** — and could not have been tested
   where it looked like it should be: `PersistenceSyncTests`' schema omits
   `ReadingAnnotation`, so `hardDelete`'s fetch throws there and is swallowed
   by `try?`. A cascade test written against that container would have passed
   no matter what the cascade did. Real test now added to
   `ReadingAnnotationBackupTests`, which has the right schema.

6. **A doc comment I wrote earlier stated something false** — it claimed
   `positionsByReadingOrder` can have fewer entries than the spine. Readium
   builds it as `readingOrder.map { ... ?? [] }` (verified in
   `PositionsService.swift` / `EPUBPositionsService.swift`), so it is always
   1:1, empties included. The href-based fix was still correct, but for a
   different reason (position-range vs. href derivation disagree for locators
   with no `position`, which is exactly what search results are). Corrected.

7. **Redundant seek on drag start** — the first tiny drag inside the starting
   page fired a seek to the page already showing, which in scrolled mode
   snapped the text to that page's top edge. Now seeded with the current page.

## Known, not fixed — flagged for judgement

*(Worked through 2026-07-28 on request — outcomes below.)*

- **`WorkLifecycle.hardDelete` is O(all annotations) per work** — **deliberately
  left as-is**, and it's worth writing down why so this isn't re-litigated.
  Three fixes were considered and rejected: (a) adding an `annotations` inverse
  relationship to `SavedWork` would give O(1) traversal, but it's a SwiftData
  schema change against a store holding real user data, and a failed migration
  means an app that won't open — far worse than the cost it saves; (b) a
  `#Predicate`-filtered fetch queries the store, whereas the current
  fetch-all-then-filter reliably sees *pending* unsaved inserts — so the
  "optimisation" would be subtly **less** correct for annotations created in the
  same transaction; (c) hoisting one fetch out of `sweepExpired`'s loop and
  passing it in means later iterations hold references to already-deleted
  SwiftData objects, and touching `$0.work?.id` on a deleted model is a fault
  risk. Meanwhile the actual cost is zero in the common case: `hardDelete` is
  only called for works whose 90-day window has *lapsed*, so a normal launch
  sweep calls it zero times. Simple and correct beats fast and fragile here.

- **`ReadiumProgressPersistenceTests/meaningfulChangeInsideWindowArmsTrailingWrite`
  was wall-clock flaky** — **fixed**. It slept a fixed 2.2 s and asserted once,
  so a loaded machine that delayed the real ~2 s timer failed it spuriously.
  Now polls up to 10 s for the trailing write. It still tests the real behaviour
  ("a meaningful change eventually arms a trailing write"), just not on a
  stopwatch. Its sibling `noiseDoesNotArmATrailingWrite` keeps its fixed sleep
  on purpose: it asserts an *absence*, and load can only delay a write, never
  invent one, so it isn't susceptible to the same failure.

- **A4 lint debt: 3 errors → 1.** Fixed the **large tuple** (the 5-wide
  `frozenScrolls` tuple became a named `FrozenScroll` struct — `bounces` and
  `alwaysBounce` are adjacent `Bool`s that positional access could silently
  transpose) and **type body length** (moved three coherent groups — speech
  skip/hold-seek + scrub + kudos, the Contents/Display sheet, and the annotation
  lookups — into a `ReadiumReaderView` extension **in the same file**, so every
  `private` member stays reachable and no access level or behaviour changed).
  Verified nothing was dropped by diffing the declaration list before/after.

  **`file_length` remains** (2,468 vs 1,400) and is the one item genuinely left.
  Same-file extensions don't reduce it — it needs whole types moved to new
  files, and the only split that gets under the limit is all three of
  `ReadiumBook` (~750 counted lines), the dismiss-peel UIKit layer, and
  `ReadiumNavigatorContainer`. `report_and_handoff.md` sequences peel/navigator
  **last** as the riskiest, so doing all three at once is exactly the ordering
  it warns against. Scouted so the next session starts with a plan, not
  archaeology: `ReadiumBook` needs only 3 members widened `fileprivate` →
  `internal` (`clearVisualPageMetrics`, `schedulePageBarRemeasure`,
  `applyVisualPageFromUserScroll`), `publishPageBar` can actually *tighten* to
  `private`, and `VisualPageMessageBridge` must move with it (it's file-private
  and used only by `ReadiumBook`). The `ReaderTheme` / `Locator` extensions are
  internal and don't couple.

- **`dedupeSamePassageAnnotations` only runs when the archive contains
  annotations** (`restoreAnnotations` early-returns otherwise). Intentional —
  no new marks merged means no new duplicates — but worth knowing if a dedup
  is ever expected from a bare restore.

---

# Swipe stutter — diagnosis (2026-07-28)

Reported as a brief hang on swipe, on **both** comments and search-result cards.
Two independent causes, both regressions from the swipe work itself.

## Search results — eager library index per card

`RemoteWorkContextMenuModifier.existingLocalWork` builds a `WorkIdentityIndex`
over the **entire** saved-works library (three dictionaries, plus URL/ID string
parsing per work). That was always there, but it only ever ran inside the
`.contextMenu { }` closure, which SwiftUI builds lazily — i.e. only when the
menu is actually opened, so it cost nothing while scrolling.

Adding swipe, I passed `isSaved` / `isQueuedForLater` as **parameters** to a
`ViewModifier`. Parameters are evaluated eagerly, so every card now paid a
full-library index build on every body pass. Fixed by keeping that lookup where
it was — referenced only inside the lazily-built action closures.

## Comments — nested ForEach defeating List laziness

The restructure left a `ForEach` whose *inner* `ForEach`'s data was computed
inside the outer closure:

    ForEach(displayThreads) { root in
        let items = CommentConversationBuilder.items(...)   // allocates
        ForEach(Array(items.enumerated()), ...) { ... }     // allocates again
    }

SwiftUI has to run that outer closure for **every** conversation to know how
many rows exist, so the whole page rebuilt a prefix array, an items array, an
`enumerated()` array and N enum cases on every body pass — and a swipe
re-evaluates the body continuously. It also defeated `List` row laziness, which
the pre-restructure one-row-per-conversation layout had for free.

Fixed by precomputing the page into a flat `[CommentConversationRowItem]` in the
model, rebuilt only when the threads or expansion state actually change, so the
view renders a single lazy `ForEach` and allocates nothing per pass. Expansion
state (`expandedRootIDs` / `visibleReplyCounts`) moved into the model with it,
since that's what has to trigger the rebuild.

## Two bugs caught while making that change

- `forceExpand` (the "Thread"/"Parent Thread" jump) must lift the 20-reply
  chunk cap, not just mark the thread expanded. `scrollTo` silently no-ops on
  an id that was never materialized, so a jump to reply #40 would have failed
  to scroll — the old `startsExpanded` flag bypassed chunking for exactly this
  reason.
- `resetForContextChange` and the account-switch path cleared `displayThreads`
  but not `conversationRows`. Since the list now renders the latter, the
  previous scope's — or previous **account's** — comments would have stayed on
  screen. Both now go through one `clearRenderedThreads()`.

## Still unverified

Whether the stutter is actually gone is a device check; both causes are
mechanism-level (work per layout pass) rather than something a test asserts.
