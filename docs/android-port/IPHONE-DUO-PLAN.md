# Kudos on iPhone Duo: the restructure plan

*Claude-Code, 2026-10-24 23:00, for the owner ("create a thorough plan to restructure the app to fit iPhone
Duo"). It builds on Codex's screen-by-screen plan (`briefs/Duo7-plan.md`), the Apple research Claude-CLI
checked (`briefs/Duo2-result.md`), the layout audit (`briefs/Duo3-result.md`), and the rounds already landed.
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
  - One hosted test fails (`sectionPushAndDeepLinkRenderInTheDetailAndCompactRowsReturnOnCollapse`).
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
- **T-451 round 5:** Codex review R456, fixes, gate, then land.
- **Duo9:**
  - Codex fixes the hosted test and tap-checks every inspector caller (root Library filter, collections,
    queue browser, Account works lists, Search and Browse).
  - Then review R457, gate and land.

*Done when:* both have landed on polish and integrate; the reader keeps its page through rotate, unfold and
Book pose; the Library, Settings and Account splits collapse and expand without losing a path.

**Phase 2: foundations.**
- The layout context (4.1), the split-host pattern written down and tested (4.2), the containers (4.3),
  the presentation policy and sheet audit (4.4), and `@SceneStorage` continuity (4.5).
- The verification harness:
  - a shot list per state, driven by `duo-pose` and Device Hub;
  - hosted size-class tests;
  - a performance baseline.

*Done when:* the screens landed so far (Home, Work Detail, the Duo9 splits) use the shared pieces with no
change visible to a reader, and the harness can shoot any screen in C, P, L and B.

**Phase 3: the reader (Duo10).**
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

**Phase 5: conversations and writing.**
- **Inbox and Comments:** a Mail-style list beside the thread, with a passive "select a conversation"
  state; nothing is fetched until it's chosen.
- **Writing:** Notes-style drafts and chapters beside a readable editor, keeping one controller.

**Phase 6: chrome and the rest.**
- The rail, toolbars and overflow (round 6).
- Onboarding and What's New, the in-app AO3 browser, and the remaining sheets.

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
| **Testing limits:** Device Hub captures simulated touches (quit it for AXe taps); poses come only from our scripts; no physical Duo | Hosted tests plus simulator shots; owner device checks listed at the end |
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
