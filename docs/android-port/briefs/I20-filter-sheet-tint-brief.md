# I20 — the iPhone's Library filter sheet takes a work's colour

**Agent:** Codex. **Worktree:** `~/kudos-agent-ios`, branch `claude/agent-ios-i20` (from the iOS lane's
`d3e66077`). iOS only. Read-only reference for Android: `~/kudos-android-lane`.

## The fault (round 3, 2026-10-24)

Tile `~/kudos-tools/pairs/tiles-r3/libraryfilters.png` (top row iPhone, bottom row Android; Dark, Light,
Sepia, OLED, Sepia at AX5). The screen is Library → Reading Now with its filter sheet open
(`-KudosDebugOpenFilters YES`, route `nav:library-section/readingNow`).

- The iPhone's sheet is **purple** in every column: Done's fill, the Sort by and Rating values. Purple is
  neither the app accent (the simulator stores none, so it's AO3 red `#990000`) nor Sepia's brown.
- Purple matches the first work on the page (Sodium Lights, Doctor Who; see
  `~/kudos-tools/pairs/tiles-a76/sec_reading.png`, whose cards wash in each work's hue while the page's own
  wash and chips are red, brown in Sepia).
- iOS's own rules say otherwise: `App/ThemeManager.swift:57-61` ("Sepia keeps its cohesive warm brown"),
  `:66-92` (scope-level surfaces, such as the pushed Library sections, draw from `scopePalette`, the app
  accent; brown in Sepia). Android follows those rules (red; brown in Sepia: A100, Android `432c34f8`).

Codex's A100 note (`~/kudos-android-lane/docs/android-port/briefs/A100-result.md`, §1) traced the iOS
presentation: `Features/Library/LibrarySectionListView.swift:251-254`, `Features/Home/HomeSectionListView.swift:219-222`,
`Features/Library/LibraryView.swift:137, 185-195`, `UIComponents/HeroWash.swift:26-29`,
`App/ContentView.swift:83-86, 292-298` ("app chrome follows the current wash"),
`UIComponents/SubjectSurface.swift:1357-1364`, `UIComponents/AccentInk.swift:58-66`.

## What to do

1. Find, with file:line, where the sheet's purple comes from (a guess to test: the window/UIKit tint that
   follows "the current wash" picks up a card's or a hero's hue, and the sheet inherits it).
2. Decide from the code and comments whether it is intended. Evidence that it is intended would be an
   owner-dated comment or a `DECISIONS.md` / TASKS row that says sheets take the hero's or a work's hue.
   If it's intended, change nothing and say why: Android will follow instead.
3. If it's a leak: make the Library section's and the Home section's filter sheets draw their controls
   from the app's palette (`effectiveTint` / `accentInk`; brown in Sepia), as their page's scope does.
   Queue and Collection filter sheets keep their own palettes (`ReadingQueueBrowser.swift:381`,
   `Collections.swift:572`): don't change them. Don't change the tab bar's or chrome's following of the
   wash (owner, 2026-10-12: "the tab bar and chrome buttons take the colour of the screen on top").
4. A test that fails with the fix reverted, if the code allows one (a unit test on the tint the sheet
   is given is enough; no UI test).

## Rules

- iOS only, in this worktree. Do not commit, push, switch branches, build, sign in, contact
  archiveofourown.org, or edit `TASKS.md`. There are no `Packages` or `Vendor` here: nothing builds;
  Claude builds, gates and shoots in `~/kudos-ios-polish`.
- Keep the change as small as the cause allows.

## Output

Write `docs/android-port/briefs/I20-result.md` first and keep it current: the cause (file:line), intended
or leak and the evidence, the change, the test and how it fails when reverted, and what Claude must check
on the simulator (the five columns of `libraryfilters`, and `hsec_reading` with its filters open).
