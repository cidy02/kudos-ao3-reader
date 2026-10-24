# A100 — round 3 result

Implementation ready for Claude's gate on `android/agent-codex-a100` (base `edf3d2fd`).
This file was created before code edits and updated after implementation. All Android paths below
are relative to `android/app/src/`; all iOS paths are relative to the read-only
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` source root.

## 1. Library filter sheet tint

**Verdict:** Library / pushed Library sections and Home sections use the app palette for their
filter sheet, independently of the hero wash. Queue and collection filters keep their own page
palettes. A98's palette parameter remains useful for those two explicit overrides; it was the
implicit use of the hero-modified local tokens that was wrong for the first two callers.

**iOS evidence and reasoning:**

- `UIComponents/FilterPanelPresentation.swift:35–50`: iPhone uses a real `.sheet`; iPad/macOS
  use an inspector. The wrapper itself chooses no tint.
- `Features/Library/LibraryFilterPanel.swift:19–27` creates its own NavigationStack without
  choosing an accent. Its Done button uses `.borderedProminent` / `.accentFill()` at `:53–60`;
  Sort / Rating are native Pickers at `:73–79`.
- `Features/Library/LibraryView.swift:137` applies the hero wash to page content, before the
  filter presentation at `:185–195`. `UIComponents/HeroWash.swift:26–29` puts the hero tint on
  that wrapped content. `Features/Library/LibrarySectionListView.swift:251–254` and
  `Features/Home/HomeSectionListView.swift:219–222` present the same panel without an outer
  `.screenTint(...)` override.
- The supplied `tiles-r2/libraryfilters.png`, visually inspected: iPhone's sheet has purple
  picker values and Done fill while the underlying page is red/pink. Together with the modifier
  placement above, this supports using the app palette for these sheets. There is no explicit
  app-accent reset in the iOS presentation wrapper itself; the screenshot supplies the observed
  iPhone presentation behavior, rather than assuming all SwiftUI environment values propagate
  identically into every sheet/inspector.
- **Queue exception:** `Features/Library/ReadingQueueBrowser.swift:341–348` presents its panel,
  then `:381` applies `.screenTint(subjectPalette)` outside the presentation.
- **Collection exception:** `Features/Library/Collections.swift:416–419` presents its panel,
  then `:572` applies `.screenTint(palette)` outside the presentation.
- `UIComponents/SubjectSurface.swift:1357–1364` explicitly documents why a screen attaches
  `screenTint` outside its sheets. `UIComponents/AccentInk.swift:58–66` installs readable
  tint/accentInk separately from exact accentFill, and `.accentFill()` uses the latter.
- App chrome follows the current wash at `App/ContentView.swift:83–86`, with the UIKit fallback
  at `:292–298`; this does not erase the presentation-site distinction above.
  `App/ThemeManager.swift:52–64,90–92` defines the app palette and its readable ink.

**Sepia evidence caveat:** the tile's iPhone Sepia sheet also looks purple. The current source
explicitly substitutes a brown app tint (`Features/Reader/ReaderStyle.swift:145–148`,
`App/ThemeManager.swift:59–60,90–92`). Android therefore preserves its existing equivalent Sepia
app-palette behavior; no fixed purple is introduced. Claude should check that column against a
fresh iOS build. This source/tile discrepancy is not claimed resolved by a device observation.

**Android changes:**

- `main/java/io/github/cidy02/kudos/ui/subject/KudosTokens.kt:164–165`: `LocalAppPalette` holds
  the app palette independently of hero/page tint replacements.
- `main/java/io/github/cidy02/kudos/ui/theme/Theme.kt:149–153`: provides that palette from the
  existing theme-derived scope palette, preserving custom accent and theme changes.
- `main/java/io/github/cidy02/kudos/library/LibraryFilterPanel.kt:83`: defaults to the app
  palette, while retaining explicit page-palette overrides and its existing SubjectPaletteTheme.
- `main/java/io/github/cidy02/kudos/library/LibraryScreen.kt:572` and
  `main/java/io/github/cidy02/kudos/home/HomeSectionListScreen.kt:525`: explicitly pass the
  preserved app palette. MainScaffold can still tint page content/chrome with the hero.
- Retained, unchanged: Queue's `palette = palette` at
  `main/java/io/github/cidy02/kudos/library/QueuePageScreen.kt:469` and Collection's at
  `main/java/io/github/cidy02/kudos/library/CollectionDetailScreen.kt:582`.

## 2. Author Load More ink

**Verdict:** use primary ink for Load More / Loading… in the shared pagination row; keep the
page counter secondary.

**iOS evidence:** `Features/Authors/AuthorProfileContentSections.swift:87–100` supplies a plain
Load More / Loading… Text and a secondary Page counter inside the button/card row. The inspected
`tiles-a97b/authorbookmarks.png` confirms primary ink in Light/Sepia. The card modifier
(`UIComponents/AppThemeSurface.swift:270–290,344–361`) adds row chrome without an accent text style.

**Android change:** `main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:1166`
explicitly uses `LocalKudosTokens.current.primaryInk`. This one shared row serves Works (`:974`),
Series (`:1026`), and Bookmarks (`:1064`), including the card variants. Pagination callbacks,
loading disablement, error/retry row, and secondary counter retain their existing behavior.

## Regression tests and revert sensitivity

New: `test/java/io/github/cidy02/kudos/app/BriefA100ContentTest.kt`.
These are runnable tests awaiting Claude's gate, **not reported as passed**. Revert outcomes below
are derived from the assertions/code; no revert experiment or Gradle command was run here.

- `librarySectionFiltersUseTheAppPaletteDespiteTheHeroTint` (`:164`) and
  `homeSectionFiltersUseTheAppPaletteDespiteTheHeroTint` (`:165`): open each real caller from
  its real toolbar under a conflicting page tint, with a non-default purple app accent.
  In four themes × two text sizes, check Default and Any rating's actual TextLayoutResult ink,
  absence of ellipsized lines, and Done's actual background modifier colour. Choose Title live
  and dismiss with Done. Reverting the app-palette routing makes the ink/fill use the hostile
  hero tint; those assertions fail. Reverting only Theme's new provider makes the custom-accent
  assertions fail because the composition local falls back to the default red palette.
- `queueFiltersKeepTheQueuePalette` (`:166`): same real-sheet checks with a hue-derived queue
  palette. This guards the retained A98 override: removing Queue's explicit palette makes the
  picker/fill assertions fail against the app palette.
- `collectionFiltersKeepThePickedCollectionPalette` (`:167`): same checks with a picked blue
  collection colour, including Sepia. Removing Collection's explicit palette makes the
  picker/fill assertions fail. These two tests protect unchanged behavior, not a new A100 fix.
- `loadMoreUsesPrimaryInkWithAndWithoutACardAndStillPagesAndDisablesWhileLoading` (`:169`):
  renders the shared row with/without its card (covering the three tabs' row configurations),
  in four themes × two text sizes. Checks primary Load More / Loading… text, secondary Page
  counter, no ellipsized lines, exactly one action per enabled tap, disabled loading taps doing
  nothing, and hiding at the final page. Reverting `:1166` restores Material's accent for the
  label, failing primary-ink assertions (in particular Light and Sepia).
- **A98 library test updated** at
  `test/java/io/github/cidy02/kudos/app/BriefA98ContentTest.kt:175–199`, renamed
  `libraryChoicesUseTheAppPaletteUnlessExplicitlyOverriddenAndStillApplyLive`. It now places
  the panel inside a conflicting SubjectPaletteTheme, tests the default app palette and explicit
  page override separately, and retains live sort/apply checks. Reverting the panel default to
  `LocalKudosTokens.current.scopePalette` fails the implicit-app branch. Its theme loop waits
  for idle before reading expected tokens. Other A98 tests were not changed.

## Verification / handoff

- Inspected both supplied tiles; inspected iOS source and every Android filter/pagination caller.
- `git diff --check` passes. Static review only; builds, tests, runtime modifier inspection and
  fresh screenshot comparisons remain Claude's work. Every new theme loop waits for idle before
  reading tokens; truncation assertions use `isLineEllipsized`, never `hasVisualOverflow`.
- No Gradle, commits, pushes, branch switches, sign-in, AO3 traffic, iOS edits, or TASKS.md edits.
  The pre-existing untracked `A100-round3-brief.md` is untouched.
