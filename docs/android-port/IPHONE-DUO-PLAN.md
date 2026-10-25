# Kudos on iPhone Duo: the restructure plan

*Claude-Code, 2026-10-24 23:00, for the owner ("create a thorough plan to restructure the app to fit iPhone
Duo"). It builds on Codex's screen-by-screen plan (`briefs/Duo7-plan.md`), the Apple research Claude-CLI
checked (`briefs/Duo2-result.md`), the layout audit (`briefs/Duo3-result.md`), the rounds already landed, and
Claude-CLI's state digest of what those rounds taught (`briefs/Duo-state-digest.md`, 22:47).
It replaces the round-by-round list as the Duo's plan. The Living Prompt (§0, §10) runs it.*

## 0. In one page

**The goal, in the owner's words.** *"Optimize the app for the iPhone Duo … make use of its larger size and
layout. Make it feel like a native Apple app."* *"Make it feel like Apple designed and shipped it. Take
inspiration from other first-party Apple apps where appropriate. But remember: lose no functionality."*

**The shape of it.** Kudos stays the app people know on the iPhone and on the Duo's cover. When the Duo
opens, the same app opens out the way Apple's own apps do:

| Area | Model app | What it becomes |
|---|---|---|
| Home | Books | Continue Reading beside what comes next |
| Library and Settings | Files, Settings | Places listed beside the page you chose |
| Work Detail | Music | An album page: identity and actions on one side, the work's content on the other |
| Reader | Books | A readable single page, or two pages with the fold as the gutter |
| Comments and Inbox | Mail | The list beside the conversation |
| Writing | Notes | Drafts and chapters beside the editor |

Every layout is chosen by the space the app has, not by "is this a Duo". So the iPad gets the same
improvements, and Split View on the Duo's inner display works too.

**Nothing is lost.** Every action, figure, line of text, state and setting stays reachable in every pose.
Each round lists everything on its screens before it starts, and it doesn't land until every item is
still there.

**Order.**
0. Finish verifying Android parity (tonight). Anything it reopens is fixed first.
1. Land the two pieces already built (the reader keeping its place; Settings/Files-style navigation).
2. Lay the foundations every screen shares.
3. Rebuild the screens family by family: reader, library depth and discovery, conversations and writing,
   chrome.
4. Check Split View and continuity.
5. A full verification pass, like the one that closed Android parity.

**On its own branch** (owner, 22:58: *"let's do the work in a branch in case we wish to revert or revise"*).
All Duo work goes on `claude/iphone-duo`. Nothing reaches the iOS polish or integrate branches until you
choose to merge it. See §12.

**Your part.** Nothing blocks on you. Design calls are mine (owner, 11:50) and recorded in `DECISIONS.md`
with how to reverse them; new features go to `FEATURE-IDEAS.md` for your yes or no. Screenshots of each
family come to you before the Duo is called done.

## 1. Rules (they apply to every round)

1. **Native first.** Use the system's own components before anything custom:
   - **Navigation and panels:** `TabView(.sidebarAdaptable)`, `NavigationSplitView`, inspectors.
   - **Toolbars and lists:** `ToolbarOverflowMenu`, `Form`, `List`, `.searchable`.
   - **Interaction:** context menus, swipe actions, system sheets and popovers.

   Then Kudos's existing elements (`Subject*`, `cardRow`, the canonical cards). Each screen names the Apple
   app it learns from (Books, Music, Files, Settings, Mail, Notes, News, Podcasts, Photos) and behaves the way
   that app does: selection highlights, where the controls sit, how a list collapses back to a stack.
2. **Lose no functionality.** Every action, figure, badge, privacy control, line of text and setting stays
   reachable in every state, in no more taps than today. Each round starts with an inventory of the
   screens it touches, and the review checks it item by item. Density stays the same or grows; a cleaner
   look that hides information is a regression (AGENTS.md).
3. **Usability and readability decide.**
   - Prose has a readable measure: about 55–75 characters per line, from the real font.
   - Nothing sits on or crosses the fold: no text, card, slider or tap target.
   - Controls go where Apple puts them.
   - Text never shrinks to fit a layout; with large text, fewer panes appear instead.
4. **Space, not device.** Size classes and measured usable regions (safe areas, the side rail, the fold's
   `ReservedRegion`) choose the layout. There are no idiom checks (the code has none since T-448), so the
   iPad and Split View get the same behaviour.
5. **Continuity.** Folding, unfolding, rotating, changing pose or resizing in Split View keeps your place:
   the selection, the scroll position, the reader's page, the editor's text and undo, an open sheet.
6. **What stays.** The cover and the ordinary iPhone keep today's layouts, unless a change is the same on
   all of them. macOS keeps its own reader and is only changed when built and checked.
7. **No new AO3 traffic.** A wider screen never loads a page, a thread or a preview the user didn't open.
8. **Written down.** Each design call goes in `DECISIONS.md` with how to reverse it. A new feature (one
   that isn't a layout of something existing) is proposed in `FEATURE-IDEAS.md` and built only after the
   owner approves.

## 2. The device, and the states Kudos must handle

Measured on the simulator (Duo1) and Apple's pages (Duo2). Kudos is built with the iOS 27.1 SDK, so it gets
the whole screen and the system's vertical bars.

| State | Size (points) | Size class | System behaviour | What Kudos must do |
|---|---|---|---|---|
| **C** cover | 466 × 678 | compact width | Tab bar and toolbar on a vertical rail at the right | Keep the iPhone layout; keep content clear of the rail (T-447) |
| **P** inner, portrait | 669 × 951 | regular / regular | Horizontal bars | Readable single columns; two panes only where both stay useful |
| **L** inner, landscape | 951 × 669 | regular / regular | Vertical rail | Two useful panes; more items per row, not bigger ones |
| **B** Book pose | as L, with a fold | regular / regular | `ReservedRegion` of kind `.division`, about 40 pt | Content on either side of the fold; nothing across it |
| **S** Split View | variable widths | compact or regular | Each app's bars on its outer edge | The same rules, reading the actual width and safe areas |

What the system does on its own: moving bars to the side, aligning a `NavigationSplitView`'s columns to the
fold, size-class changes. What it can't do for Kudos: custom content. That means shelves, grids, cards, the
reader's pages, the editor, and anything drawn with `GeometryReader`.

## 3. Where it stands

**Landed** (polish and integrate, pushed):
- **T-447:** on the cover, horizontal rows stay clear of the side rail and cards fit their space.
- **T-448:** layout chosen by size class, not idiom; the two-page spread setting and the filter inspector
  reach the inner display.
- **T-449, then T-450:** the reader survives a size change. T-450 removed T-449's hold-and-restore layer
  after reviews R449 and R450 found it could undo the reader's own navigation; Readium owns the position.
- **T-452 (round 1):** Home and the Library dashboard composed for the inner display, with the shared
  `AdaptiveContentRegions` (usable panes from the safe area, the rail and the fold).
- **T-454:** in Book pose, Home shows both next works.
- **T-455 (round 4a):** Work Detail laid out like an album page when its own container fits two readable
  regions.

**Built, not landed** (uncommitted in `~/kudos-ios-polish`, backed up in `~/kudos-tools/out/backups/`):
- **T-451, round 5:** paged reading keeps its place through a rotation or unfold. It needs adversarial
  review R456 before it lands; R449, R450 and R453–R455 each found P1s.
- **Duo9, round 2:** Settings/Files-style local navigation (Library locations beside a section, Settings
  categories beside a page, Account destinations beside a page).
  - The filter inspector regression is fixed: the panel draws its own header in an inspector instead of
    nesting a `NavigationStack`.
  - One hosted test fails (`sectionPushAndDeepLinkRenderInTheDetailAndCompactRowsReturnOnCollapse`, Codex's
    fixture): 172 tests in 16 suites, 3 issues, all in that test.
  - Its worktree (`~/kudos-agent-ios`) is based on T-452, so T-454 and T-455 exist only on polish. Its own
    files match the staged copy byte for byte.
  - The other inspector callers still need tap checks.

**Briefed, not started:** Duo10, round 3 (the reader's measure and a fold-aligned spread).

**Not yet covered by any round** (this plan adds them):
- Queues and collections as a real split.
- Search and Browse results, and Reading Insights and Recently Deleted on the big screen.
- AO3 collections and challenge pages; Inbox, Comments and Writing.
- The rail's toolbars and overflow; sheets and other presentations.
- Split View multitasking; state that survives a scene being rebuilt (the app has no `@SceneStorage`).
- Onboarding and What's New; the in-app AO3 browser.
- A Duo verification pass.
- **From Duo3, owned by no round:**
  - #12, the root download banner over the tab container (`App/ContentView.swift:60`);
  - #10, the subject headers and stat strips on Author, Series, Fandom and tag pages and collection detail;
  - #6, Account's large-text fallback (Duo9 collapses at every accessibility size).
- **Uncovered screens:** Author profile pages and their works scope and sort; the rich rows of Account's
  Bookmarks, History and Subscriptions at width.
- **Each Settings page's own layout:** the 14 pages inside the split, of which only the frame is done.
- **Presentations near the fold:** alerts, confirmation dialogs and menus anchoring there; the reader's
  own sheets (Display, Contents, Read Aloud, Find) in Book pose; the keyboard in Book pose.
- **Chrome over a split:** the system's tab sidebar expanding over a local split, and the portrait
  floating bar over split content.
- **The iPad:** T-452's Home and T-455's Work Detail have never been seen on an iPad.

## 4. The restructure: what every screen shares

These are the structural changes. Screens then use them instead of each doing its own geometry.

### 4.1 One layout context

`AdaptiveContentRegions` (T-452) becomes the one source of layout facts, published to the environment at
each destination's root:
- the state (C, P, L, B, S);
- the usable rectangle after safe areas and the rail;
- the panes either side of an active fold, and the fold's own frame and margins;
- the size classes and the Dynamic Type size;
- a "does this fit" helper (minimum pane widths, readable measure).

Every adaptive decision reads it, and nothing else measures the window. It is unit-tested for asymmetric
safe areas, a shifted fold, an inactive region, a width too small for two panes, and large text.

### 4.2 Navigation: keep the system root, add local splits

- **The root stays** `TabView(.sidebarAdaptable)` with Home, Library, Browse, Account and Search, as
  Music, Books and TV do. Its rail and sidebar are the system's.
- **One local split per place-list destination**, as a `NavigationSplitView` host:
  - Library locations;
  - Queues and Collections;
  - Account destinations;
  - Settings categories;
  - Inbox and Comments;
  - Writing drafts and chapters.
- **Only one split is visible at a time.** Opening a nested organizer (Settings from Account, Queues from
  Library) replaces the leading list, the way Settings does, so there are never three columns.
- **Compact width collapses** each host to today's stack, with today's routes.
- **Host rules learned the hard way** (Duo9; they apply to every screen that moves into a host):
  - **No nested stack in an inspector.** An inspector never contains a `NavigationStack`,
    `.navigationTitle` or `.toolbar`: they take over the owner page, and the pushed section pops. It
    draws its own header row (`filterPanelChrome`). A compact "inspector" is a real `.sheet`.
  - **Stable presenter bindings.** Presenters take only stable bindings (`$isPresented` or
    `.constant(false)`). A `Binding(get:set:)` built fresh each render looped forever: the Library root
    ran at about 100% CPU, and a hosted test hung for 40 minutes.
  - **No presenters that switch branches** by size class: a branch switch recreates the owner's
    `NavigationStack` and drops its path. Use one modifier chain for both size classes.
  - **A hosted test per presenter in each host** (inspector, sheet, confirmation) that opens it and checks
    the path survives. That would have caught both Duo9 bugs before a simulator run.
- **`AppRouter` stays the one route model.** Deep links, per-tab paths and the Back history survive
  collapse and expand, and host tests cover all three.

### 4.3 Content containers

Built once in `UIComponents/` and used everywhere:
- `ReadableColumn`: a measure cap for prose and forms.
- Two-region pages: `ArrangementView` where it fits; otherwise measured side-by-side regions.
- A region-aware grid:
  - order stays row-major, with stable IDs;
  - columns stay clear of the fold;
  - VoiceOver reads in the same order.
- Shelves paged per pane, so a card is never clipped at the fold.

`CarouselCardGrid` and `HorizontalScrollViewport` are reused, not replaced.

### 4.4 Presentation policy

One place decides how each kind of presentation appears in each state:
- **Filters and refinements:** an inspector at regular width, a sheet at compact.
- **Small pickers:** popovers.
- **Forms:** form sheets.
- **Full screen:** only the reader.

The rule Duo9 learned is written in: never nest a `NavigationStack` inside an inspector. The panel draws its
own header (`filterPanelChrome`). Every sheet in the app is audited against this policy.

### 4.5 Continuity

- Split selections, the selected tab and list positions are kept with `@SceneStorage` (new). Unfolding,
  Split View resizing or the system rebuilding the scene then lands where the reader was.
- The reader's position stays with Readium (T-450, T-451).
- The editor keeps one `WritingTextController` through every layout change, so selection, undo and
  recovery survive.

Tests drive size and pose changes without a relaunch.

### 4.6 The rail, toolbars and overflow

- Every toolbar action gets a real title and symbol, so the system can show it in a vertical rail or in
  overflow.
- Each screen has one `ToolbarOverflowMenu` (no second custom "…" menu).
- Compression is chosen per task: tab-bar first while browsing, toolbar items first while editing or
  selecting.
- Controls belong to their pane. The search field stays usable when bars go vertical.

### 4.7 Performance and accessibility

**Performance.**
- Bigger panes mean more cells at once: lazy containers only, and no layout that re-renders itself.
  Duo9 found such a loop, which pinned the main thread at 100% on the Library root.
- Each round takes an Instruments pass on the Duo: scroll, open, fold and unfold.

**Accessibility.**
- VoiceOver reads leading pane before trailing pane, in visual order.
- Large text collapses panes before anything shrinks.
- Reduce Motion is respected in transitions, and rail items keep the large content viewer.

## 5. Screen by screen

Status: ✅ landed · 🔨 built, not landed · 📝 briefed · ⬜ not started. Detail and file lists are in Duo7's
screen sections; this table is the target and the phase.

| Area | Apple model | Cover / iPhone | Inner portrait | Inner landscape and Book pose | Status · phase |
|---|---|---|---|---|---|
| Home | Books, Music Home | unchanged | hero beside next works when they fit | hero in one pane, neighbours in the other; shelves paged per pane | ✅ T-452, T-454 |
| Library dashboard and sections | Books Library, Files | unchanged | locations + section when both fit | locations beside the section; grids gain columns | 🔨 Duo9 · phase 1 |
| Queues, local collections | Music playlists | unchanged | grid; collapsible list | list beside the queue (Up Next, In Line, reorder intact) | ⬜ · phase 4 |
| Browse | News, Music categories | unchanged | category groups in two columns when they fit | category and recent cards in panes; fandom lists stay one readable list | ⬜ · phase 4 |
| Search and results | Music Search, Files | unchanged | rich two-column results when cards fit | two result columns, one when the inspector opens; pagination and order kept | ⬜ · phase 4 |
| Work Detail | Music album | unchanged | one centered readable column | identity, Read and stats beside summary, tags and series | ✅ T-455 |
| Reader | Books | unchanged | one page at a readable measure | two pages with the fold as gutter (paged, spread on); one pane for Scroll and large text | 🔨 T-451 · 📝 Duo10 · phases 1, 3 |
| Comments, Inbox | Mail | unchanged | list + thread when both fit | list beside the thread; composer stays a system presentation | ⬜ · phase 5 |
| Writing | Notes | unchanged | readable editor; collapsible list | drafts or chapters beside the editor; one controller | ⬜ · phase 5 |
| Account hub and pages | Settings, Files | unchanged | destinations + page when both fit | destinations beside the page | 🔨 Duo9 · phase 1 |
| AO3 collections, challenges | Files, Settings forms | unchanged | readable forms | index beside the collection; forms at a readable width | ⬜ · phase 4 |
| Settings | Settings | unchanged | categories + page | categories beside the page | 🔨 Duo9 · phase 1 |
| Reading Insights | Fitness summary | unchanged | figures in two regions | figures in two regions, all kept | ⬜ · phase 4 |
| Recently Deleted | Photos, Notes Recently Deleted | unchanged | readable list | readable list in its pane | ⬜ · phase 4 |
| Sheets (filters, add to queue, bookmark, …) | system | unchanged | presentation policy | presentation policy | ⬜ · phase 2 |
| Rail, toolbars, overflow | system | labels | horizontal bars | vertical rail, one overflow | ⬜ · phase 6 |
| Onboarding, What's New | Apple's welcome sheets | unchanged | centered sheet | centered sheet | ⬜ · phase 6 |
| In-app AO3 browser | Safari View | unchanged | full width | full width, toolbar in the rail | ⬜ · phase 6 |

## 6. Phases

Each phase lists its work and what has to be true before it's done. Rounds inside a phase run in parallel
where their files don't overlap.

**Phase 0: Android parity verification (tonight; blocks everything else).**
- The five checks in Living Prompt §0, including a fresh pass of every screen on both phones.
- Anything reopened is fixed before Duo work starts.

**Phase 1: land what's built.**
- **T-451: reversed, not landed (2026-10-25).** R456 → round 6 ("detect the reset") → R458 still found a P1: a
  chosen chapter start can't be told apart from Readium's reset. The stop rule recorded before round 6 applied
  (DECISIONS, 2026-10-25). The reader stays as T-450 left it, and Readium owns the position.
- **Duo9:**
  - Codex fixes the hosted test and tap-checks every inspector caller (root Library filter, collections,
    queue browser, Account works lists, Search and Browse).
  - Then review R457 and the gate.
  - It lands in three commits (Settings, then Library, then Account) so each can be reverted alone. That's
    the digest's "smaller rounds": Duo9 changed four areas at once and needed four rounds of fixes.

*Done when:* both have landed on polish and integrate; the reader keeps its page through rotate, unfold and
Book pose; the Library, Settings and Account splits collapse and expand without losing a path.

**Phase 2: foundations, the shot harness first.**
- **The shot harness, before any more screens** (the digest: two false findings came from the harness, not
  the app):
  - routes that apply once (`takeRoute`);
  - an auto-open flag for each presenter;
  - the rotate hook;
  - a launch helper that waits for content;
  - scripts that make, install on, tap and delete a temporary 27.0 iPad, so every round also sees an iPad
    and the ordinary iPhone.
- The layout context (4.1), the split-host pattern written down and tested (4.2), the containers (4.3),
  the presentation policy and sheet audit (4.4), and `@SceneStorage` continuity (4.5).
- The verification harness:
  - a shot list per state, driven by `duo-pose` and Device Hub;
  - hosted size-class tests;
  - a performance baseline.

*Done when:* the screens landed so far (Home, Work Detail, the Duo9 splits) use the shared pieces with no
change visible to a reader, and the harness can shoot any screen in C, P, L and B.

**Phase 3: the reader (Duo10).**
- **It starts on T-450's landed, reviewed baseline** (Readium owns the position), with a review slot reserved.
  The rule from T-449 and T-450: never override a position the reader chose.
- **First: the unfold keeps the reader's place through Readium's own reload.** Paged mode falls back to the
  chapter's start on a same-orientation resize (the Duo's unfold, iPad Split View), because Readium reloads at
  its `currentLocation` only on a spread change. The public route: from the container's `viewWillTransition`,
  submit the preferences with `offsetFirstPage` toggled and then the originals. That forces one coalesced
  `_reloadSpreads()` at Readium's own `currentLocation`, the path rotation takes, with no app restore logic.
  Review and device check. The upstream PR is the clean long-term fix (DECISIONS, 2026-10-25).
  **Checks before it's trusted** (Claude-CLI, 2026-10-25):
  1. **Net no change still reloads.** From source, yes: the coalesced async block calls `invalidatePaginationView`
     with no diff of its own (`EPUBNavigatorViewModel.setNeedsInvalidatePagination`). A test confirms it.
  2. **`offsetFirstPage` never takes effect.** From source, the second submit restores it before the async reload
     lays out, and CSS isn't committed while an invalidation is pending. Still check spread-on at the inner
     landscape width (951 pt), so the reader can't move a page.
  3. **Persistence:** the toggled value never reaches the app's preferences store or sync, even if interrupted
     between the two submits.
  4. **Timing:** `viewWillTransition` fires before the new size applies. The device check must show the reload
     lands after the size settles (not at the old size, then mapped back to the start). Split View's live drag
     must give one reload, not one per frame.
  5. **A just-chosen place:** `go(to:)` via Contents, then unfold within 300 ms. If Readium reloads at the old
     place, that's its own rotation behaviour too: parity with rotation, not a new fault. The owner entry says so.
- One navigator.
- The spread's gutter is the fold.
- Chrome sits in one pane.
- Scroll, large-text and fixed-layout fallbacks are explicit.
- Measure the CSS first, then the smallest app-side bridge; no toolkit fork.

*Done when:* paged reading with the spread on shows two readable pages around the fold in L and B, every
fallback is whole in one pane, and position, speech and selection survive every transition.

**Phase 4: library depth and discovery.**
- Queues and collections as a Music-style split.
- Search and Browse results (round 4b).
- AO3 collections and challenge pages.
- Reading Insights and Recently Deleted.
- Author profiles, Series, Fandom and tag pages: their subject headers and stat strips (Duo3 #10).
- Account's Bookmarks, History and Subscriptions rows at width.
- Each Settings page's own layout inside the split.

**Phase 5: conversations and writing.**
- **Inbox and Comments:** a Mail-style list beside the thread, with a passive "select a conversation"
  state; nothing is fetched until it's chosen.
- **Writing:** Notes-style drafts and chapters beside a readable editor, keeping one controller.

**Phase 6: chrome and the rest.**
- The rail, toolbars and overflow (round 6).
- Onboarding and What's New, the in-app AO3 browser, and the remaining sheets.
- The root download banner (Duo3 #12).
- Alerts, confirmation dialogs and menus near the fold.
- The reader's own sheets in Book pose.
- The system tab sidebar over a local split, and the portrait floating bar over split content.
- Account's large-text fallback (Duo3 #6).

**Phase 7: Split View and continuity.**
- Kudos beside another app at every system width, on both sides.
- Every transition with a selection, a sheet, the reader and the editor open.

**Phase 8: the Duo verification pass.**
- Every screen in C, P, L, B and a Split View width.
- Four themes and the largest text.
- Two independent judges, and the "lose no functionality" inventory.
- Fix rounds until clean, then the owner's screenshot gate.

**Phase 9: ready to ship** (the owner's steps stay the owner's).
- The iPad regression pass; the macOS build.
- Duo screenshots for App Store Connect, prepared for the owner. Duo screenshots earn the "optimized for
  iPhone Duo" badge now and are required for submissions from April 2027.
- **Android:** Android foldables and tablets aren't in scope. Whether Android gets the same large-screen
  layouts is the owner's call; it goes to `FEATURE-IDEAS.md`. Android phones stay at parity, because phone
  layouts don't change.

## 7. How every round runs

1. **Brief.** Codex gets the screens, the Apple model, this plan's rules and the before-inventory of every
   action and figure.
2. **Build.** Codex implements in its own worktree, with tests that fail when their change is reverted.
3. **Review (mandatory).** An adversarial review by Claude-CLI, or by Codex's second slot when Claude-CLI
   built the round. Every reader and layout review so far found P1s.
4. **Gate.**
   - The iOS suites, then the full suite (only the known 10 failures).
   - The macOS build.
   - SwiftLint with no new warnings.
5. **See it.**
   - Shots in C, P, L and B (and Split View from phase 7) in four themes and the largest text, judged
     against the target.
   - The inventory is checked item by item.
6. **Land.**
   - Commit on the polish branch, cherry-pick to integrate, push both.
   - A TASKS row, and a `DECISIONS.md` entry for each design call.

No round claims a screen is right without having seen it on the Duo.

## 8. The Duo matrix

Like Android's §7, a table in the Living Prompt tracks each screen family across C, P, L, B and S.

A row turns ✅ when:
- its screens have been seen in every state, four themes and the largest text, with nothing that differs
  from the target;
- its inventory is complete;
- its transitions keep place.

Phase 8 closes the matrix.

## 9. Risks

| Risk | How it's handled |
|---|---|
| **The reader:** Readium's bundled CSS media queries keep one column; the page count drifts; speech or selection lose focus | One navigator; measure the computed CSS before changing it; a whole-pane fallback is always available; review R-series before landing |
| **Navigation:** paths lost on collapse; nested stacks (the inspector bug); deep links | One split visible at a time; host tests for collapse, expand and deep links |
| **Performance:** render loops; large lists | Lazy containers; an Instruments pass each round; the Duo9 lesson written into the host pattern |
| **Lost information or actions** | The before/after inventory each round; the AGENTS.md density rule |
| **Testing limits:** Device Hub captures simulated touches, so taps, swipes, the keyboard and drag can't be checked in any Duo pose; poses come only from our scripts; no physical Duo | Geometry and hosted tests stand in for Book-pose interaction; taps checked on a temporary iPad; the owner's device checks are listed |
| **Shared components ripple to the iPad and iPhone** (the card clamp, the filter chrome, the region helper) | An ordinary iPhone and a temporary iPad in every round's checks |
| **Disk** (about 26 GB free; idle simulators use about 27 GB) | Delete only temporary simulators we made; the owner's are an open question |
| **Agents:** Gemini out until about 10-27/10-29, Grok out of balance, Codex has usage windows | Codex implements; Claude-CLI and Claude-Code review and judge |

## 10. Who does what

- **Codex (two slots):** implementation, one family per slot, files never overlapping.
- **Claude-CLI:**
  - adversarial reviews and Duo verification on the simulator; it built rounds 1–5 and knows the Duo
    tools;
  - takes briefs from Claude-Code.
- **Claude-Code:** orchestration, judging pairs, gates, landing, keeping this plan and the Living Prompt
  current.
- **Sonnet (agy account 2):** small, exact items, when its quota allows.
- **Gemini:** long reads and research when its quota returns.

## 11. Done, for the Duo

- Every row of the Duo matrix ✅: every screen in C, P, L, B and Split View, four themes, the largest text.
- Nothing lost, by inventory.
- Every transition keeps place.
- The iPhone and cover unchanged except deliberate shared improvements; the iPad gains the same wide
  layouts and passes a regression pass; macOS builds.
- Gates green, reviews closed with no open P1 or P2.
- The owner's screenshot gate passed.
- `DECISIONS.md` complete, and a short owner summary of the Duo work.

## 12. Branches: everything revertible

Owner, 22:58: *"let's do the work in a branch in case we wish to revert or revise"*.

- **`claude/iphone-duo`** (from polish `1e5d3d44`, pushed): every Duo round lands here. It also carries the
  staged T-451 round 5 and Duo9, uncommitted until they pass their reviews.
- **`claude/polish-loop`** takes only non-Duo iOS fixes, such as anything the parity verification finds on
  the iPhone.
- **`integrate/cloud-redesign` gets no Duo commits** until the owner merges the Duo branch.
- **Revertible in steps:**
  - each round is its own commit or commits, so a round can be reverted alone;
  - each phase ends with a tag (`duo-phase-1`, …), to compare or roll back to;
  - Duo9 lands as three commits.
- **Already on polish** (and integrate): the Duo work before this rule, T-447 to T-455. If the owner
  wants any of it gone, it is undone with revert commits. History is never rewritten and nothing is
  force-pushed.
- **Agents** keep their own branches (`claude/agent-ios-*`) and worktrees. Their work reaches
  `claude/iphone-duo` only through Claude-Code's landing.
- **Android** stays on `android/redesign-parity`. `main` is never touched.
