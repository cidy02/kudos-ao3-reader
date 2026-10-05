# Brief 3aq result: three screens at large text

**Landing note (Claude, 2026-10-05).** Landed as written; the tests were changed, not the
screens. They asked each text whether it "has visual overflow" using Robolectric's stand-in for
text layout, which does not wrap lines; the class now uses real text measurement, and asks what
actually cuts text (a height it does not fit, a line limit exceeded, an ellipsis), because a
short label sized to its glyphs reports overflow when there is none. Gate green (1,501 tests).
Seen on the emulator at font scale 2.0 and at 1.0: the Inbox, the AO3 Collections list and the
local Collections grid. At 2.0 everything stacks and wraps and nothing is cut; at 1.0 the three
screens are as they were. Android differs from iOS here on purpose (iOS keeps the Inbox byline
on one line and the covers as a scaled mosaic): it is in `DECISIONS.md`.

## Reference read before editing

Read-only iOS reference: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`.
Searched the matching views for `dynamicTypeSize.isAccessibilitySize` and
`ViewThatFits`:

- `Features/Account/AccountInboxViews.swift`, `AccountInboxItemRow.byline`:
  the reference still puts name, participant badge, Replied and date in an
  HStack; name/date are one line. `subjectControl` caps the work title at two
  lines. There is no accessibility-size or ViewThatFits branch in this file.
- `Features/Account/AO3CollectionsList.swift`, `AO3CollectionCard`: title and
  summary have unlimited lines at accessibility sizes, with vertical fixedSize.
  Its eyebrow/status and facts/date still use HStacks; no ViewThatFits fallback.
- `Features/Library/Collections.swift`, `CollectionCard`, and
  `UIComponents/StackedWorkCover.swift`: the carousel width and height scale
  together. The mosaic stays 2×2 with a fixed proportional height, two-line
  titles (minimum scale 0.85) and one-line authors. No accessibility stacking
  branch or ViewThatFits appears in these matching views.

Thus this checkout does not contain all the iOS reflow described in the brief.
Android follows the brief's explicit stacking/no-shrinking/no-text-height
requirements, reusing `isAccessibilityFontScale()` (`fontScale > 1.3f`) from
brief 4a. Ordinary-size branches preserve existing arrangements.

## Android implementation

### Inbox

`account/AccountInboxPane.kt`, `InboxByline`: above 1.3, the unread marker and
wrapping name form the first line, followed by the participant badge, Replied
chip and wrapping timestamp on separate lines. New chips use `SubjectChip`,
the subject palette and tokens; Author/Me keep their descriptive accessibility
labels. The original byline (including its original badge styling) is unchanged
at ordinary sizes.

`InboxSubjectLine` also stacks the chapter chip before the wrapping work title;
non-chapter subjects wrap without a cap. `InboxItemCard` lifts the excerpt cap
at accessibility sizes. Names, subjects, dates and excerpts have explicit line
heights and no text-containing fixed heights. `InboxItemCard` is now internal
so tests can render the actual production row without an authenticated client.

**Difference from iOS at large sizes:** Android stacks the byline and chapter
context, and lifts the subject/excerpt caps. The reference retains horizontal
rows and caps. These deliberate differences fix Android's crowded identity and
clipped text at font scale 2.0; no facts or controls are removed.

### AO3 Collections

`account/AO3CollectionsScreen.kt`, `AO3CollectionCard`: above 1.3, kicker and
each state chip occupy separate lines. Title, summary and byline wrap without
line caps, with explicit line heights. The facts wrap in their own line and
the update date follows below instead of reserving horizontal width. The
decorative folder and chevron remain beside the header; all text heights are
content-driven. Ordinary-size header, stats row and text limits are unchanged.

`ui/subject/SubjectComponents.kt`, `SubjectKicker`: an optional `maxLines`
parameter lets this card's long maintainer kicker wrap. Its default stays one,
preserving every other caller and this card's ordinary layout.

**Difference from iOS at large sizes:** unlimited title/summary match iOS. The
stacked kicker/chips and facts/date, wrapping kicker and unlimited byline go
further than the reference HStacks so Android's enlarged text does not compete
for the same row width. Both state chips and every stats fact remain visible.

### Local Collections

`library/CollectionsScreen.kt` uses a single grid column above 1.3, retaining
the existing adaptive grid at ordinary sizes.
`library/LibrarySubjectComponents.kt`, `CollectionCard`/`MosaicWorkTile`, use
the window width minus the existing 16dp gutters at accessibility sizes. The
same four preview slots become a vertical stack; filled tiles lose their
fixed mosaic height and weighted spacers. Tile titles/authors and the collection
name wrap without caps or shrinking, with explicit line heights. The existing
tile palettes and components are reused; new accessibility ink reads tokens.
Empty decorative slots retain fixed geometry because they contain no text.
At ordinary sizes the 164dp cover, 221dp mosaic, 2×2 tiles, fonts, colors and
line limits remain the existing ones.

**Difference from iOS at large sizes:** iOS retains a proportionally scaled,
fixed-height 2×2 mosaic and truncated/shrinkable titles. Android instead gives
the four titles and authors full-width, naturally growing tiles, because a
fixed miniature grid clips those sp-scaled labels at 2.0. Preview ordering,
placeholder slots and collection counts are retained. The shared collection
card also gains this behavior in the Library dashboard carousel.

## Tests written (not run)

`android/app/src/test/java/io/github/cidy02/kudos/ui/subject/LargeTextScreensTest.kt`
contains six Compose/Robolectric tests: one per screen at 2.0 and one at 1.0.
The test application is plain `Application`; qualifiers are
`w411dp-h2400dp`, and every test asserts the root is 411dp wide. Font scale is
provided through `LocalDensity`, the actual source of the shared breakpoint
and sp conversion.

- Inbox renders the real `InboxItemCard` in a LazyColumn at the page's existing
  gutter width, checking name, participant badge, Replied, date, chapter,
  work title and excerpt. Its 1.0 test pins the byline and chapter rows.
- AO3 Collections renders the real `AO3CollectionCard` in a LazyColumn at the
  page's existing gutter width. The 2.0 fixture checks a long maintainer kicker,
  both state chips, long title, byline, long summary, all stats and date. Its
  1.0 test pins the kicker/chip row, facts/date row and two-line caps.
- Local Collections renders the full `CollectionsScreen` with real in-memory
  Room/WorkRepository/LibraryRepository data. The 2.0 test checks all four long
  titles and authors, collection name/count and the second grid card below.
  The 1.0 test pins the 2×2 mosaic, two-card grid and original cover width.

Each large-size text assertion checks `assertIsDisplayed`, compares its full
measured bounds against its semantics parent, visible bounds and all layout
parents (including non-semantic tiles/Rows/Columns), and checks TextLayoutResult
for overflow/ellipsized lines. Long fixtures must actually wrap beyond the old
caps. The tall window keeps these lazy items composed without scroll-dependent
assertions. Fixtures have no remote image URLs or network clients.

## Verification and handoff

- `git diff --check`: clean.
- Read the real model, repository, theme/component and caller symbols used;
  inspected cached Compose 1.11.3 APIs for parent coordinates and text-layout
  assertions. No dependencies, backup formats or Room schemas changed.
- **Not run:** Gradle compilation, these six tests, the broader Android suite,
  emulator rendering or screenshot comparisons. These remain for Claude; none
  of the tests is claimed passing and ordinary-size pixel parity is unverified.
- Claude should run `:app:assembleDebug` and `:app:testDebugUnitTest` (including
  `io.github.cidy02.kudos.ui.subject.LargeTextScreensTest`), then inspect all three
  pages at 1.0 and 2.0 in Light/Dark/OLED/Sepia using offline fixtures/demo data.
  Full Inbox/AO3 page chrome, scrolling/selection and dashboard carousel visuals
  remain manual checks; their row/card tests do not initialize remote pages.
- No Gradle, Xcode, network, sign-in, commit, push, branch switch or TASKS.md edit
  was performed. No helper scripts, stubs or `.orig` files were added. All work
  is left uncommitted on `android/agent-gemini-3aq` for Claude's verification.
