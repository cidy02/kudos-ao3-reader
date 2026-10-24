# Duo4 — cover shelves and container card clamp

## Round 2 — dashboard double inset and wash regression

Source fix ready for Claude's next build/shots. Claude reports that the round-1
diff builds and all six test methods pass in `~/kudos-ios-polish`, and iPhone 17
matches its baselines. Duo cover Queues clips near 380pt, but Home/Library rows
clip near 298pt; Library also exposes a white block in its wash. I viewed
`cover-duo4/home-light.png`, `library-light.png` and `cmp-lib-queues.png` in
`~/kudos-tools/out/duo/`. No round-2 build or simulator run was performed here.

**Cause:** the old `HorizontalScrollViewport` subtracted the inherited lateral
safe inset twice: once in the mask's `.padding(.trailing, proxy.safeAreaInsets.trailing)`
and again from local width for card sizing. The dashboard's vertical ScrollView
already supplies its children a usable layout width, while the nested mask proxy
can still report the inherited rail inset. The old report's claim that these
insets must be zero in an already-constrained parent was incorrect. The screenshots'
early cutoff agrees with subtracting that inset from an already-usable width.
This is a source/screenshot diagnosis; no live geometry logging was performed.

`TabDashboardShell` itself does **not** add a rail offset: its `body` has only
vertical page padding (`UIComponents/TabDashboardShell.swift:25`). It is a loading
replacement, not an ancestor of the loaded Home/Library content. The loaded
dashboards likewise put these rows in a vertical ScrollView
(`Features/Home/HomeView.swift:150`, `Features/Library/LibraryView.swift:466`).
Queues is hosted in List rows instead, explaining why
the erroneous geometry assumption did not produce the same extra cutoff there.

The second mistake was attaching `.mask` to the entire horizontal ScrollView.
That clips its viewport composite, including scroll-background rendering, rather
than restricting the mask to the cards/chips. The new scope excludes all scroll
and page background rendering. `HeroWash` remains outside the scrolling-content
mask and unchanged (`UIComponents/HeroWash.swift:18`). The exact framework
compositing behavior behind the supplied white block was not instrumented.

**Fix:** `UIComponents/HorizontalScrollViewport.swift:43` establishes a named,
non-scrolling layout container around the row. Its bounds are the width supplied
by the parent; no safe inset is subtracted from those bounds. Inside the ScrollView,
only `scrollView.content` receives the mask (`:45`). The mask resolves that
ancestor's bounds into the moving content's coordinates with `GeometryProxy.bounds(of:)`
(`:48`), so the clipping edge stays at the viewport when the row scrolls or bounces.
No per-scroll offset state, rail constant or device check is needed. See Apple's
[bounds conversion contract](https://developer.apple.com/documentation/swiftui/geometryproxy/bounds(of:)).

The same container width minus the existing card gutters feeds the clamp (`:67`);
the grid also stops subtracting inherited safe insets from its already-padded
local bounds (`:103`). Content margins, horizontal gutters, 6pt shelf padding,
vertical shadow allowance and all 18 call sites are unchanged. On iPhone 17 this
uses the same full-width container as round 1, so its already-approved appearance
should remain unchanged. Round-2 visual approval is still pending.

Added two geometry tests at `KudosTests/CarouselCardSizingTests.swift:67,79`:
an already-usable 380pt fixture stays 380pt, with expansion only vertically for
shadows; and the clip follows supplied content-coordinate offsets (including
bounce). Shrinking that rectangle again fails the first test; pinning its origin
instead of following the viewport fails the offset cases. These additions have
not been run. They do not prove the runtime coordinate-space/wash behavior.

Round-2 checks here: targeted no-cache SwiftLint on the helper/tests, mechanical
invariants and `git diff --check` all pass. No build, commit, push, branch switch,
TASKS edit, sign-in or AO3 request. Only the helper, its tests and the two existing
reporting docs changed in this round.

**Priority re-shoot:** Home and Library at rest and at each shelf/chip row's end
on Duo cover, normal text and AX5. Their clip edges should now align with the
usable edge demonstrated by Queues (about 380pt in the supplied shots), rather
than 298pt; no empty band beside a cut card, and Library's wash must remain
continuous behind the rows and rail. Re-shoot Queues as a control, the loading
shell, and iPhone 17 against the same baselines. Check while dragging/bouncing,
last-item taps and top/bottom shadows. Re-run the expanded sizing suite (now eight
methods on iOS). The full original handoff checklist remains below.

Status: round-2 source ready for Claude's build/test/screenshot gate on
`claude/agent-ios-duo4` (2026-10-24). This brief was created before source changes.
No build, simulator run, commit, push, branch switch, TASKS edit, sign-in or AO3
request was performed. Existing untracked Packages, Vendor and other briefs were
left alone. The changes remain uncommitted, as requested.

## Scope and approach

Audited all 18 original horizontal shelf/chip `ScrollView` call sites and all
`ScaledCarouselCardSize` consumers. All 18 now use the shared viewport modifier;
the six compact-grid construction sites share a measured-width grid. No rail
constant, device name, idiom check, extra UI, metadata removal or density change.
The new viewport/measurement behavior is `#if os(iOS)`; macOS keeps its original
clipping, screen clamp, column formula, spacing and equal-height choices.

Reader, fold/Book pose, inner-display layout, download banner, toolbar placement,
networking, models and persistence were not changed. The writing change is only
the existing formatting-chip scroller's viewport, not its text engine.

## Changes

Source references below are relative to `kudos-ao3-reader/`, except tests/docs.

### Shared geometry and clamp

| File:line | Change and reason |
|---|---|
| `UIComponents/HorizontalScrollViewport.swift:43` (new) | The layout container receives usable width from its parent and defines a named coordinate space. The scrolling-content mask converts those bounds to its own coordinates; it does not subtract inherited safe insets again. The page/scroll background is outside the mask. |
| `UIComponents/HorizontalScrollViewport.swift:63` | `.contentMargins(.horizontal, 0, for: .scrollContent)` leaves safe-area insetting to SwiftUI. Existing HStack padding supplies the same design gutter as before. The end-of-scroll position therefore includes system lateral clearance plus that gutter, allowing the last item to finish inside the mask. This needs runtime confirmation against the 27.1 rail. |
| `UIComponents/HorizontalScrollViewport.swift:64,75` | Only the four shadowed shelves disable scroll clipping, and all four remain inside the horizontal content mask. Its **vertical-only** 32pt expansion accommodates the current 8pt-radius, 3–4pt-offset card shadows (three radii plus offset); it is not a rail estimate. Existing 6pt vertical shelf padding and section spacing remain unchanged. Chip rows keep native clipping and add the same horizontal content mask. |
| `UIComponents/HorizontalScrollViewport.swift:67` | Measures the layout container width minus the caller's two existing card gutters; passes that usable card width through `carouselCardAvailableWidth`. This measures the viewport, never the scrolling HStack's total content width, and does not subtract safe insets from already-usable bounds. |
| `UIComponents/CarouselCardStyle.swift:74` | `ScaledCarouselCardSize` reads the measured width. iOS no longer reads `UIScreen.main.bounds`; both dimensions retain one proportional clamp ratio. Until the first measurement it uses the natural scaled size, rather than a guessed screen/rail size. The horizontal mask already applies during that initial layout. |
| `UIComponents/CarouselCardStyle.swift:99` | The grid can compute its column width with the same given-width arithmetic before supplying the width to its child cards. |
| `UIComponents/CarouselCardStyle.swift:108` | Pure `clampRatio(scaledWidth:availableWidth:)`: never enlarges a fitting card, shrinks an oversized one to the given width, and clamps nonpositive available space to zero. |
| `UIComponents/HorizontalScrollViewport.swift:87` | `CarouselCardGrid` measures inside the caller's padding, shares that width with its cards and column calculation, and retains `adaptiveCardColumns`' existing 2pt rounding tolerance and 12/14pt gaps. It preserves which callers use equal heights and no longer subtracts inherited safe insets from the local width. |
| `UIComponents/WorkCardSizing.swift:87` | Equal-height groups reset when usable width changes, including the first measurement, so a pre-clamp height cannot remain as a permanent floor. Existing Dynamic Type resets remain. This avoids stale tall cards after the measured clamp settles. |

The safe-area/content-margin contract comes from Apple's
[contentMargins documentation](https://developer.apple.com/documentation/swiftui/view/contentmargins(_:for:))
and its [scrollClipDisabled documentation](https://developer.apple.com/documentation/swiftui/view/scrollclipdisabled(_:)).
The mask is necessary because scroll content margins position content but do not
by themselves prevent an overflowing shelf from painting behind a lateral bar.

### Every horizontal row

Each listed call applies the shared horizontal mask and safe-area-aware scroll
margin described above. No per-screen rail arithmetic was added.

| File:line | Covered surface |
|---|---|
| `UIComponents/WorkCarouselSection.swift:99` | All Home/Library work shelves, Home's Reading Queues deck shelf, Library Collections, Home collection shelves and canonical subscription shelves; preserves shadows, 16pt card gutters. |
| `Features/Home/HomeView.swift:441` | Separate Continue Reading strip; preserves shadows, 16pt card gutters and the existing −8pt top inset. |
| `Features/Search/MediaBrowserView.swift:290` | Jump Back In fandom-card shelf; preserves shadows and `CardListMetrics.sideMargin`. |
| `UIComponents/TabDashboardShell.swift:73,92` | Loading fandom-chip row and loading card shelves; avoids a rail overlap while real Home/Library content mounts. |
| `Features/Library/LibraryView.swift:633` | Library fandom quick filters, including trailing Reset. |
| `Features/Library/ReadingQueueOrganizer.swift:190` | Queues' All / tag / Untagged chips, with their existing counts. |
| `UIComponents/SubjectScreen.swift:295` | Shared active-filter rails: section lists, queue browser, Search results, Inbox and AO3 Collections. |
| `UIComponents/FlowLayout.swift:125` | Non-accessibility branch of `AccessibilityChipRail`: subscriptions, named subscriptions, author scope/sort/filter chips and AO3 Collections. The accessibility wrapping branch is unchanged. |
| `Features/Library/FavoriteAuthorFilterRail.swift:20,53` | Shared single-select pills (queue All/Unread/Offline/WIP, favorite works/tags) and favorite Authors' quick filters. |
| `Features/Search/FandomFamilyRows.swift:271` | Fandom A–Z / Most works / Group variants chips. |
| `Features/Bookmarks/AO3HistoryWorksBrowser.swift:236` | AO3 History filter pills and Reset. |
| `Features/Bookmarks/AO3MarkedForLaterWorksBrowser.swift:472` | AO3 Marked for Later filter pills and Reset. |
| `Features/Bookmarks/AO3BookmarksWorksBrowser.swift:371` | AO3 Bookmarks filter pills and Reset. |
| `Features/Account/AO3CollectionItemsView.swift:303` | Collection Works/Bookmarks tab pills and Reset. |
| `Features/WorkDetail/WorkDetailSections.swift:533` | My Copy's suggested-tag chips. |
| `Features/Writing/WritingTextEditor.swift:283` | Formatting tags; retains its existing disabled state, spacing and accessibility help. |

### Compact grids following the clamp

These now use `CarouselCardGrid` instead of separately reading a screen-clamped
size for `LazyVGrid` columns. Their existing outside padding and card content
are unchanged; the shared grid measures the width **inside** that padding.

| File:line | Covered grid |
|---|---|
| `Features/Home/HomeSectionListView.swift:421` | Home section works. |
| `Features/Library/LibrarySectionListView.swift:797` | Library section/bucket works. |
| `Features/Library/ReadingQueueBrowser.swift:670` | Queue works, including selection/reorder overlays. No queue split-layout change. |
| `UIComponents/LibraryEntityGridView.swift:32` | Collections; retains equal heights. |
| `Features/Account/AccountComponents.swift:530,567` | Account works and bookmarks; both retain equal heights. |

`WorkSummaryCardSurface`, `ReadingQueueCard`, `CollectionCard` and its
`StackedWorkCover` already embed the shared size helper, so they inherit the
measured host width without card-specific changes. Removed redundant parent
size/column properties from the six grid sites.

### iPhone 17 before/after

For **every row above**, the full-width phone viewport is unchanged, so
the content mask ends at the same screen/container edges the row already reached. The
existing gutters, spacing, labels, counts, backgrounds, card aspect ratio and
vertical shadow room remain. A fitting 164pt card stays 164pt; scroll-end gutters
remain the same. The grid retains the existing column/gap formula and equal-height
choices. At large text, a full-width host clamps to its own width minus the same
gutters rather than to screen width minus 32; those agree on the usual full-width
portrait phone. A narrower host now intentionally clamps sooner.

Claude reports round-1 iPhone 17 screenshots unchanged against baseline. I did
not take those screenshots; round-2 appearance is an expectation pending his
next shots. Confirm initial layout at AX5 as well as the settled state because
card-width geometry arrives through `onGeometryChange`.

## Evidence and tests

The original Duo overlap is from Claude's supplied `cover-notes.md`; the round-1
dashboard regression is visible in his supplied round-2 evidence, viewed here.
Claude reports the initial build and six sizing methods green. No Swift code was
compiled and no test/mutation was run in this worktree in either round.

`KudosTests/CarouselCardSizingTests.swift:7` now has eight Swift Testing methods
(18 cases on iOS; seven methods / 17 cases on macOS). Claude ran the original six
methods; the two new geometry methods are pending:

| Test:line | Contract and expected failure when regressed |
|---|---|
| `ordinaryCardsKeepTheirExistingSize:9` | Given 343/361/434/800pt, baseline width/height do not change. Removing the upper ratio cap would enlarge cards and fail these expectations. |
| `largeCardsFitTheGivenContainer:19` | A 720pt scaled width shrinks to each supplied 180/278/343/434pt container; the height keeps sqrt(2):1. Ignoring the given width, or substituting one full-screen width for all cases, fails at least the smaller-container width expectations. |
| `aNarrowContainerCanClampEvenAnUnscaledCard:29` | A 164pt card in 120pt becomes 120pt. Keeping the old screen allowance in place of the argument fails this case on a normal phone. |
| `wideningTheContainerRestoresTheScaledSizeWithoutEnlargingIt:34` | A 320pt card clamps to 210pt and returns to 320pt in 600pt, never growing to 600pt. Omitting clamping or the ratio cap fails. |
| `noSpaceNeverProducesANegativeSize:42` | Zero/negative available space produces ratio zero. Removing the lower bound fails the negative-space case. |
| `theSizeHelperReadsItsContainerWidth:47` | Uses the existing ImageRenderer/probe test pattern to exercise the real `ScaledCarouselCardSize` DynamicProperty at AX5 with 120/278/343pt environment widths. Restoring `UIScreen.main.bounds.width - 32` while keeping the pure helper would fail the 120pt expectation. Also checks both dimensions retain the same ratio. |
| `theClipUsesTheAlreadyUsableViewportWidth:67` | Given a 380pt usable viewport, the content mask stays 380pt wide and adds shadow room only vertically. Subtracting another inset from the clip fails the edge expectation. |
| `theClipFollowsTheViewportInMovingContent:79` | Given viewport origins −16/0/164/1000 in content coordinates, the mask keeps the supplied origin/width. Resetting the origin to zero fails scrolling/bounce cases. |

The probe covers environment-to-size wiring, **not** proof that viewport geometry
reaches that environment. Claude must verify the measurement wiring, terminal
scroll offsets, mask rendering/shadows and equal-height reset on the simulator.
Expected revert failures above are predictions for that gate, not claimed
executed mutation results.

Checks performed here:

- `Scripts/check-invariants.sh`: passed.
- `git diff --check`: passed.
- `Scripts/lint.sh`: cache write failed under the workspace permission boundary;
  diagnostic was inability to save SwiftLint's cache plist, not a source error.
- `swiftlint lint --quiet --no-cache kudos-ao3-reader`: exit 0, existing source
  warnings; no diagnostics in the new helper or changed sizing helper.
- Targeted no-cache SwiftLint on the new helper and test file: exit 0, no warnings.
- `docs/REGRESSION_TEST_MATRIX.md:11` records the new coverage and manual residue.

Not run here: app/test builds, Swift Testing, full verification harness, simulator
screenshots, human UI gate or independent adversarial review. Claude's round-1
results are attributed above; no round-2 compilation or visual-correctness claim
is made.

## Claude's simulator handoff

In `~/kudos-ios-polish`, build and run `CarouselCardSizingTests` plus the required
project gates. Carry the two new Swift files, all listed source changes, the
regression-matrix row and this brief; synchronized groups need no pbxproj edit.

On **both iPhone 17 and Duo cover (466×678 pt)**, use local/demo fixtures with more
items than fit. Capture the same baseline and changed states at normal text and
AX5; include Light and Dark so faint/clipped shadows are visible.

1. **Home:** Continue Reading with several strip works; Reading Queues with at
   least three decks; every populated work/subscription/collection shelf. Shoot
   at rest and at the last item, with the rail visible. Last card/deck and its
   action target must clear every rail button; top/bottom shadows must stay soft.
2. **Library:** Reading Now, other populated work shelves and Collections;
   long fandom rail with Reset. Shoot each at rest and at its terminal offset.
3. **Queues organizer:** enough tagged queues for overflowing All/tag/Untagged
   chips. Shoot first/last, then tap the last chip and confirm counts/selection.
4. **Browse Media / Fandom list:** populated Jump Back In shelf first/last;
   A–Z / Most works / Group variants rail first/last.
5. **Shared rails:** Library/Home section filters; Favorites Works/Authors/Tags;
   queue detail's filter and All/Unread/Offline/WIP pills; Search active filters;
   AO3 History, Marked for Later, Bookmarks, Subscriptions and named subscriptions;
   author scope/sort/filter; Collections filters and collection Works/Bookmarks;
   Inbox filters. Use already-loaded fixtures; no sign-in/network is needed for
   this task. At AX5, confirm `AccessibilityChipRail` still wraps as before.
6. **Work Details → My Copy** with suggested tags, and **writing editor** with
   its formatting strip: first/last chip visible and tappable, keyboard up/down.
7. **All six compact grids:** Home section, Library section, queue work grid,
   Collections grid, Account works and Account bookmarks. Check normal column
   counts/spacing and AX5 one-card fit; keep title/author/metadata. Exercise queue
   select/reorder once to confirm its overlay targets stayed aligned.
8. **Loading shell:** relaunch/switch into Home/Library with slow fixture loading;
   capture skeleton shelves/chips before real content mounts, and confirm no
   brief rail overlap or persistent excess card height on initial AX5 layout.

For each overflowing row, verify no content paints into the rail at rest **or
while dragging**, the last item can settle wholly inside the usable edge, and
tapping it does not hit a rail control. On iPhone 17 compare gutter placement,
card width, visible metadata, section height and shadows against baseline;
appearance should be unchanged. Also change Dynamic Type down from AX5 without
leaving Home to check equal-height groups shrink again. No inner-display, fold,
reader, toolbar or banner verification is claimed by this handoff.
