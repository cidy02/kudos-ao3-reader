# Duo7 — a plan to make Kudos feel like one of Apple's own apps on iPhone Duo

**Agent:** Codex. **Worktree:** `~/kudos-agent-gemini2` (write only the plan file). Read-only on the iOS
source: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` at the lane's tip (T-450 work in progress in the
reader; read it, don't plan around fixing it).

## The owner's ask (2026-10-24)

*"optimize the app for the iPhone duo as well, make use of it's larger size and layout. make it feel like a
native apple app"*

## What we know

- Apple's guidance, checked against Apple's pages and the 27.1 SDK:
  `~/kudos-android-lane/docs/android-port/briefs/Duo2-result.md` (read its "Checked by" header first: what is
  primary and what is secondary). Cover 466×678 pt (compact width); inner 669×951 portrait and 951×669
  landscape, regular/regular; bars on a vertical side rail on the cover and inner landscape; the fold a
  ~40 pt `ReservedRegion` (`.division`), active in Book pose; `ArrangementView` /
  `UIArrangementViewController`, `NavigationSplitView`, inspectors, `onHingeChange`, `toolbarVerticalEdge`;
  "on the inner display your app should look like a natural extension of its iPad layout"; toolbar items
  with both a symbol and a title.
- Your Duo3 audit (`~/kudos-android-lane/docs/android-port/briefs/Duo3-result.md`): what breaks; T-447
  (shelves under the rail, card clamp), T-448 (size classes, not idiom: spread and inspector), T-449/T-450
  (the reader through a size change) have landed or are landing.
- How Kudos looks today: on the cover `~/kudos-tools/out/duo/cover-sheet-*.png`, `cover2-*.png`; on an iPad
  `~/kudos-tools/out/duo/duo6/ipad-*.png` (Kudos already has iPad layouts: find them, and what decides them).

## How Kudos looks on the inner display today (Claude-CLI, 2026-10-24 11:40)

Shots (polish `97187d9a` + Duo5b, Light): `~/kudos-tools/out/duo/inner/` (`land-*` 951×669, `port-*` 669×951,
`book-*` Partially Open), sheets `~/kudos-tools/out/duo/inner-land-{1,2,3}.png`, `inner-port.png`,
`inner-book.png`. Claude-CLI can change the pose itself now (`~/kudos-tools/duo-pose Open|Closed|Partially
Open|Rotate Right`), so every round can be checked on the inner display and in Book pose.
- Every screen is the phone layout stretched: lists and forms run edge to edge at 951 pt (Settings, AO3
  Preferences, Inbox, More on AO3); Home's Continue Reading card spans the width with an empty middle;
  shelves leave most of the width blank; the TabView (`.sidebarAdaptable`, `App/ContentView.swift:421–439`)
  is the vertical rail in landscape and the floating bar in portrait.
- Book pose: nothing avoids the fold: Home's hero card and Library's shelves run across it.
- The reader, Work Detail and Comments with longer waits: `~/kudos-tools/out/duo/inner-slow.png`. The reader in
  landscape is one column with ~800 pt lines even with `-readerTwoPage YES` (paged): no spread, and a measure far
  too long to read; in Book pose the text runs straight across the fold. Work Detail and Comments are the phone
  layout stretched.
- macOS already has a `NavigationSplitView` sidebar (`App/ContentView.swift:391–410`); iOS has no list–detail
  split anywhere.

**Owner, 2026-10-24 11:50:** the Duo redesign's decisions are Claude-CLI's, judged first on **usability and
readability**. So don't park anything as an owner question: give a recommendation with its reason for each
choice (including the root: the system TabView's rail or a sidebar), and Claude-CLI decides.

Claude-CLI's first read of the direction (test it, don't take it as given):
1. **List–detail splits** where Apple's iPad apps use them: Settings (like iPad Settings), Account's pages,
   Library's sections and collections, Inbox/Comments (thread list | thread). `NavigationSplitView` pads around
   the fold for free (Duo2). Whether the root should become a sidebar on the inner display, or the system's
   TabView rail stays, is Claude-CLI's call: say what Apple's apps do and recommend.
2. **Content that reflows instead of stretching**: Home's hero beside its neighbours instead of full width;
   shelves as multi-row grids; lists at a readable width or in two columns; Search results as a grid.
3. **Work Detail in two columns** (the work's card, stats and actions | summary, tags, chapters), split on the
   fold in Book pose (`ArrangementView` or reserved regions).
4. **The reader**: one column with a readable measure in portrait; a two-page spread in landscape and Book
   pose (T-448 now allows it) with the gutter on the fold and the chrome off it.
5. Vertical bars: toolbar items with symbol and title (HIG); overflow order.

## What to plan

For every main area (Home, Library and its sections, Browse, Search, Account and its pages, Work Detail,
the reader, Comments, Writing, Settings, queues and collections), and for each Duo state (cover; inner
portrait; inner landscape; Book pose):
1. What Apple's own apps do with that kind of screen on a large regular/regular phone or iPad (Books,
   Music, Notes, Mail, Files, News): the native pattern to follow, named as a SwiftUI/UIKit component.
2. What Kudos has today for the iPad, and whether the Duo gets it just by size class once nothing chooses
   by idiom; what's missing.
3. The change, as files and the components to use; how it keeps the cover, the iPhone and the iPad
   unchanged (or the same everywhere); that no information or density is lost (AGENTS.md); anything that
   would be a *new* control or screen (list those separately, each with its reason).
4. The reader in particular: one page or a two-page spread on the inner display; the spread's gutter on the
   fold in Book pose (`ReservedRegion`); chrome kept off the fold; what Readium's pinned version allows.
5. The tab bar: Apple's `TabView` with `.sidebarAdaptable` (or what the app has) on the inner display; how
   that meets the vertical rail.

End with **rounds**: 4–6 implementation briefs in order of what makes the Duo feel native soonest, each
with its files, its risks, and what Claude must check in which pose. Mark every claim about an Apple API
that you didn't confirm in the 27.1 SDK on this Mac (`xcrun --show-sdk-path`).

## Apple's apps as the model (owner, 2026-10-24 11:55)

Name, for each screen, the Apple app whose pattern it follows (Books for the reader and library, Music for
detail pages and shelves, Mail or Messages for list–thread, Notes or Files for list–detail, Settings for
Settings, News or Podcasts for discovery), and how that app behaves on a large regular/regular screen. Where
an Apple app suggests a **feature** Kudos doesn't have, for every platform rather than a Duo layout, don't
plan it: list it in a separate section **"Feature ideas for the owner"** (what it does, the Apple app it
comes from, why it helps a reader, rough cost, AO3 traffic if any). Claude-CLI moves those into
`docs/android-port/FEATURE-IDEAS.md` for the owner to approve or deny.

## Output

`docs/android-port/briefs/Duo7-plan.md` in this worktree, written first and kept current.

## Rules

Read-only. Do not edit any source, commit, push, switch branches, build, sign in, contact
archiveofourown.org, or edit `TASKS.md`.
