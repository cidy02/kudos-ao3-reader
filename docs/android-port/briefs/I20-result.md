# I20 — section filter sheet accent

Status: implemented, uncommitted on `claude/agent-ios-i20`; ready for Claude's
build, test, revert check and simulator shots in `~/kudos-ios-polish`.
This brief was created before code edits and updated after implementation.

Scope: iOS Library and Home section filter sheets only. Queue and Collection
palettes, tab bar and chrome wash tracking stay as they are. Per the task, no
build, commit, push, branch switch, AO3 request or TASKS.md edit will be made.

## Cause and intent

**Verdict: leak.** Paths below are relative to `kudos-ao3-reader/`.

- `Features/Library/LibraryView.swift:137` applies the first Reading Now work's
  `heroWash`. `UIComponents/HeroWash.swift:13–14,27–29` derives that work's
  palette, installs its accent and reports it as the current screen wash.
- `App/ContentView.swift:83–86` installs the current wash as the root accent;
  `:20–23,94–97,292–298` also forwards its readable ink to `UIWindow.tintColor`.
  Thus an unscoped presentation can inherit the hero's purple through SwiftUI's
  accent roles, with UIKit's window tint as fallback. This is a hero/ancestor
  leak, not evidence that a work card writes the window tint.
- Before this change, the presentations at
  `Features/Library/LibrarySectionListView.swift:251–257` and
  `Features/Home/HomeSectionListView.swift:219–225` supplied no accent to
  `LibraryFilterPanel`. Their scope washes wrap inner content instead
  (`LibrarySectionListView.swift:619,759,799`; `HomeSectionListView.swift:324,431`),
  so they do not scope the outer presentation. `UIComponents/SubjectSurface.swift:1357–1364`
  documents exactly this inward-only environment boundary.
- `UIComponents/FilterPanelPresentation.swift:35–50` selects a real iPhone
  sheet, but supplies no accent. `Features/Library/LibraryFilterPanel.swift:30–38`
  supplies no accent either: Done uses the inherited exact `.accentFill()`
  (`:64–71`), and Sort by / Rating are native pickers (`:85–90`).

**Intent evidence:** `App/ThemeManager.swift:57–64,66–92` assigns scope surfaces
(explicitly pushed Library/Home sections) the app accent and Sepia's warm brown.
Both section views' scope-palette comments agree (`LibrarySectionListView.swift:298–302`,
`HomeSectionListView.swift:59–64`). `HeroWash.swift:3–7` has an owner-dated
2026-10-03 instruction for Home/Library dashboard page controls. TASKS T-399
(`TASKS.md:70`, owner dated 2026-10-11 in the source) extends wash following to
tab/chrome buttons and Library dashboard chips. Neither says that section
filter sheets take a hero/work hue. `docs/REDESIGN_DECISIONS.md` contains no such
sheet colour decision. The newer task explicitly preserves chrome following.
I inspected `~/kudos-tools/pairs/tiles-r3/libraryfilters.png`: the iPhone's Done
fill and picker values are purple in all five columns, consistent with this
source trace. No runtime window-tint observation was made here; which inheritance
channel supplies each native widget remains a simulator detail.

## Change and regression check

- `Features/Library/LibraryFilterPanel.swift:3–12`: added the iOS-only
  `LibrarySectionFilterAccent` modifier. It uses the existing
  `.accentTint(themeManager.effectiveTint, on: themeManager.appTheme)` to supply
  both readable ink/native tint and the exact fill. The small shared modifier
  lets the unit test exercise the same accent installation as both callers.
- `LibrarySectionListView.swift:253–255` and `HomeSectionListView.swift:221–223`:
  apply that modifier **inside** each presented panel, guarded for iOS.
  This also covers the iPad inspector without changing macOS.
- Untouched: `ReadingQueueBrowser.swift:342–348,381` and
  `Collections.swift:417–419,572` retain their subject palettes. The shared
  `LibraryFilterPanel` body, the Library dashboard's separate presentation,
  root/window tint, wash reporting, tab bar and chrome are unchanged.

**Regression test:** added
`AccentInkTests.sectionFiltersChooseAppAccentOverAnInheritedHeroAccent`
(`KudosTests/AccentInkTests.swift:65–100`). It renders an environment probe beneath
the production modifier and a conflicting purple ancestor. It checks actual
`accentFill` / `accentInk` against the ThemeManager roles for default AO3 red
(including absent stored accent) and a custom muted teal in Light, Dark, Sepia
and OLED. It separately checks that Sepia uses its brown regardless of that
chosen accent. It restores the preferences after the test.

**Revert sensitivity, to run in Claude's lane:** replace the production modifier's
body at `LibraryFilterPanel.swift:9` with just `content`, leaving the test and
caller wiring intact. The probe then receives purple fill/ink from its ancestor:
the app-fill, app-ink and non-purple assertions fail. Restore line 9 and rerun
`AccentInkTests`. This is an expected result from the code, **not an executed
revert experiment**. The unit test covers the supplied accent roles; it does not
open either caller's actual sheet or inspect native picker rendering, so the
simulator checks below remain necessary.

**Checks performed:** targeted `swiftlint lint --quiet --no-cache` over the four
changed Swift files exited 0. It reported four existing long toolbar lines
(`LibrarySectionListView.swift:191,195`, `HomeSectionListView.swift:164,168`) and
the already oversized Library section type; no warning on added code.
`git diff --check` passed. No builds, tests, sign-in, network requests, git
mutations or TASKS.md edits were performed. Existing untracked Packages/Vendor
symlinks and other brief files were left untouched.

## Simulator handoff

Claude must compare Library → Reading Now with filters open (`libraryfilters`,
`-KudosDebugOpenFilters YES`, route `nav:library-section/readingNow`) in Dark,
Light, Sepia, OLED and Sepia at AX5. Check Done's fill, Sort by and Rating values:
app accent (default AO3 red), readable accent ink where appropriate, warm brown
in Sepia. Dark/OLED Done keeps the exact red while its picker values use the
lifted readable ink. Repeat all five columns for `hsec_reading` with filters
open. At AX5 verify Sort by, Rating and Done remain reachable and readable;
choose a sort/rating, confirm live filtering, dismiss and reopen.

Check Queue and Collection filter palettes and tab/chrome wash tracking remain
intact through opening/closing the sheets and pushing/popping the section.
Optionally choose a non-default app accent to confirm these two section panels
follow it while Sepia stays brown. No fresh simulator checks have been performed
in this worktree.
