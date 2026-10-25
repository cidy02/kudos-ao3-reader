# iPhone Duo: state digest for IPHONE-DUO-PLAN.md (Claude-CLI, 2026-10-24 22:47)

Read-only digest of the Duo work Claude-CLI ran on 10-24, for Claude-Code's plan. Sources: polish and integrate git
logs, `TASKS.md`, LIVING-PROMPT §12 (10-24 entries), `DECISIONS.md` (10-24 entries), the briefs/results named below
(lane `~/kudos-android-lane/docs/android-port/briefs/` unless another worktree is named), and what I saw on the
simulators. Paths are under `kudos-ao3-reader/` unless they start with `~` or `KudosTests/`.

## 1. What landed

All on polish `claude/polish-loop` and cherry-picked to `integrate/cloud-redesign`, both pushed.

| Task | Duo item | Polish / integrate | What it did | Review |
|---|---|---|---|---|
| T-446 | I20 | `d9e0d44f` / `5ce78e2f` | Library and Home section filter sheets take `effectiveTint` (they inherited the hero wash's accent through the root tint). Parity item, not Duo. | — |
| T-447 | Duo4 | `e8036a77` / `800c10f0` | Cover (466×678): all 18 horizontal rows behind one `horizontalScrollViewport` mask so they end at the side rail; the card clamp measures its container, not the screen (History's AX5 card whole). Round 2 fixed a doubled dashboard inset and a wash cut. `CarouselCardSizingTests` 8. | — |
| T-448 | Duo6 | `de1a36ae` / `25e14c37` | The spread toggle and the filter inspector follow `UIComponents/WideLayout.swift` `isAvailable` (regular width and height), not the idiom; a narrow iPad window now gets the sheet. Checked on a temporary iPad Pro 11 (27.0). | — |
| T-449 | Duo5 (+ Duo5b in polish only) | `97187d9a` / `85c072ed` | Reader keeps side safe areas, seeds its page box from the host geometry, remeasures the page count on reflow (Duo3 findings 7, 9, 16), plus a hold-and-restore layer for the locator through a resize. Round 2 fixed page turns swallowed by an opening host report. | R449: 3 P1 + 1 P2; R450 (on Duo5b): 5 P1 + 1 P2 |
| T-450 | Duo5c | `b4752bd5` / `16efff40` | Removed T-449's hold-and-restore; Readium owns the position through a resize again (T-449's geometry parts kept). | R451: land, no findings |
| T-452 | Duo8, round 1 | `663eaa90` / `3e58f9c2` | New `UIComponents/AdaptiveContentRegions.swift` (safe area, rail, active `.division`/`.occlusion` reserved regions → usable panes); Home's hero beside the next works; pane-paged shelves; nothing on the fold in Book pose; region tests fail with reservations ignored. | — |
| T-454 | follow-up | `65bcd8b2` / `e657de21` | Book pose Home showed one of two next works: a single pane fitting one column paged one card at a time; it now uses the compact scroll (`UIComponents/HorizontalScrollViewport.swift`, `DashboardCardShelf`). | — |
| T-455 | Duo11, round 4a | `1e5d3d44` / `1963567c` | `Features/WorkDetail/WorkDetailLayout.swift`: two regions when Work Detail's own container fits (2 × 340 pt + 24 pt gutter, ≥ 480 pt tall; 480 pt regions at AX sizes; 720 pt readable cap); leading identity/Read/stats/actions, trailing summary/tags/facts/comments/series/My copy, separate scrolls; Book pose regions either side of the fold. `AdaptiveContentRegions.init(viewport:)` extracted. 62 tests. Not seen: iPad, a long-summary work. | not needed (no position) |

Not landed: T-451 (staged), Duo9 (staged), Duo10 (brief only). Duo1 (simulator + Device Hub driving) and Duo2/Duo3/Duo7
(research, audit, plan) are documents/tools, not commits.

**The reviews and their P1s** (results in `~/kudos-agent-ios2/docs/android-port/briefs/`):
- **R449** (T-449): an explicit same-chapter jump (bookmark, Contents, scrub, Read Aloud) during the resize window is
  restored away; a resize while a chosen chapter loads restores the previous chapter; the held locator is a pixel
  fraction that points at another passage after reflow. P2: a failed reload leaves the hold waiting forever.
- **R450** (Duo5b, the R449 fixes): a page-spanning paragraph restores to its start; native page/scroll gestures and
  content links lose to the hold; a same-page seek disables preservation indefinitely; "idle" isn't Readium's pending
  initial scroll finishing; retry exhaustion protects the locator only until the late load reports. → the layer was
  removed (T-450).
- **R451** (Duo5c): land, nothing found.
- **R452** (T-451 round 1, `spread .never`): pass; but the visible chapter-start reset remained.
- **R453** (T-451 round 2): P1 a resize while a Contents/link jump to an unloaded chapter loads snapshots the old
  chapter; 3 P2 (VoiceOver forces scroll but the restore checks the stored mode; unbounded unloaded-spread waits; …).
- **R454** (round 3): P1 a completed same-chapter seek can be restored away before Readium's callback (0.3 s later);
  P1 a native drag in progress loses its cancellation at the first size report; 3 P2.
- **R455** (round 4, "reader at rest"): P1 an old callback or a slow command still allows restoring over a chosen
  passage; P1 a progression-only restore can move a resting reader to another passage after reflow; 2 P2.
  Round 5 fixed .1, .3, .4; .2 accepted by decision (approximate retention).

Every reading-position round got at least one P1 except the removal (R451) and the one-line `.never` (R452).

## 2. What's staged, exactly

`~/kudos-ios-polish` working tree on HEAD `1e5d3d44` holds both, uncommitted (38 status lines; ignore the two old
`Packages`/`Vendor` symlinks from 10-03). Patches in `~/kudos-tools/out/backups/`.

**T-451 round 5** (paged reading returns to the chapter start after a rotation round trip; seen on the iPhone after T-450)
- Files: `Features/ReaderReadium/{ReadiumBook,ReadiumNavigatorContainer,ReadiumReaderView}.swift`,
  `KudosTests/ReadiumReaderTests.swift`, untracked `KudosTests/ReadiumResizeRestoreTests.swift` and
  `ReadiumResizeRestoreFixtures.swift`. Identical copy in `~/kudos-agent-ios2`. Patch `T451r5.patch`.
- Cause (T451-result.md, "Evidence and corrected cause"): Readium's `spread .auto` reloads reflowable chapters on an
  orientation change (restoring by progression), and its live resize (`Scripts/src/utils.js` `snapCurrentPosition`)
  snaps the old pixel offset onto the new width. The Duo's cover → inner-portrait unfold changes size without
  changing orientation, so the reload path can't cover it.
- Design: `spread .never` for reflowable books; one `go(to:)` of the locator snapshotted at the burst's first real size
  change, after the 220 ms settle, paged only, snapshotted only from a reader at rest (no tracking/dragging/
  decelerating, fresh accepted location); one worker with one replaceable pending action; no acquisition while a
  command is queued or executing; interaction stamps at enqueue/dispatch/completion; 2 s age escape (`ponytail:`
  comment); exact resource URL check; a slider release keeps the issued seek; any command/touch cancels. Promise
  narrowed to "never override a position the reader chose" (DECISIONS 10-24, two T-451 entries).
- Checks: 127 tests in the reader suites green; lint nothing new; iPhone (Lane E) page 4/4 → landscape → 3/4, no
  chapter-start reset. **Needs R456** (fresh Codex job in `~/kudos-agent-ios2`, brief
  `briefs/R456-t451-r5-review-brief.md` there) before it lands. Land only the files above + TASKS.

**Duo9, round 2** (Settings/Files-style local navigation)
- New: `UIComponents/LocalNavigationHost.swift` (a `NavigationSplitView` host; `LocalNavigationState` for replacement
  sidebars and "detail needs width", registered by background `UIViewRepresentable` anchors that unregister in
  `dismantleUIView`), `UIComponents/LocalNavigationCompactContent.swift`, `Features/Library/{LibraryLocationsList,
  LibraryNavigation,QueueBrowserLocations}.swift`, `Features/Account/AccountDestinationsList.swift`,
  `Settings/SettingsCategoriesList.swift`; changed LibraryView, LibrarySectionKind/ListView, Collections,
  ReadingQueueBrowser/Organizer, AccountView, AccountInboxViews, SettingsHubView, SettingsRoute, FloatingChrome,
  FilterPanelPresentation, LibraryFilterPanel, AO3FilterPanel, `App/DemoLibrary.swift`; tests
  `KudosTests/LocalNavigationHostTests.swift` (new) and 6 changed suites. Codex rounds 1–3
  (`~/kudos-agent-ios/docs/android-port/briefs/Duo9-result.md`) plus Claude-CLI's three fixes:
  1. the render loop (stable bindings in FilterPanelPresentation; patch `duo9-filterpanel-claude-fix.patch`);
  2. the inspector/NavigationStack nesting (`filterPanelChrome` + `closeFilterInspector`; patch
     `duo9-filter-inspector-header.patch`); tap-verified on a temporary 27.0 iPad (Filter, Done keeps the section,
     reopen, facet chip, Reset) and seen on the Duo;
  3. the debug routes apply once per launch (`DebugLaunchRoute.takeRoute`).
- `~/kudos-agent-ios` (branch `claude/agent-ios-duo9`, base `663eaa90` = T-452) has the same Duo9 source/test files
  byte for byte; its base lacks T-454/T-455, which only polish has.
- Gate (16 suites, 21:35): 172 tests, 3 issues, all in
  `sectionPushAndDeepLinkRenderInTheDetailAndCompactRowsReturnOnCollapse` (LocalNavigationHostTests.swift :94
  compact destinations visible at regular width, :109 `account-root` missing after the path resets, :115 compact rows
  don't return after collapse). It runs on Codex's `NavigationTestRoot` fixture, not the app. The app does these right
  with real taps (iPad, 19:50).
- Next: `~/kudos-tools/out/duo9-r4-msg.txt` → `--resume-last` in `~/kudos-agent-ios` (fix that test without weakening
  it; tap-check the other inspector callers: root Library filter, collections, queue browser, Account works lists and
  collections, and Search/Browse, which now show the header row on iPad too).
- Seen working: Library and Account sidebars in inner landscape, the split's divider on the fold in Book pose,
  portrait detail-only, cover unchanged, Settings categories | page with ‹ Account returning, the iPad's top tab bar
  kept on Settings.

**Duo10, round 3** (the reader's measure and a fold-aligned spread): brief only,
`briefs/Duo10-round3-reader-brief.md`; not dispatched. Waits for T-451 to land (it consumes T-450/T-451 as the
baseline). Decisions it binds: one navigator/locator/speech session on pinned Readium 3.9.0 (`de07026e`); spread
gutter centred on the physical fold; Scroll/spread-off/large type wholly in the leading pane at 55–75 characters;
close/title lead, fan menu and position/TTS card trail; needs an adversarial review before landing.

## 3. What bit

**The inspector and NavigationStack nesting.** `AO3FilterPanel`/`LibraryFilterPanel` wrapped themselves in a
`NavigationStack` for their nav bar. In an `.inspector` attached inside a `NavigationSplitView` detail's
`NavigationStack`, that second stack took over: tapping Filter on a pushed Library section popped to the dashboard
and no inspector appeared. Proved by experiment on the Duo (no taps: `-KudosDebugRoute section:readingNow
-KudosDebugOpenFilters YES`): plain text in the inspector kept the section; removing the "detail needs width" request
changed nothing; a panel without its own stack kept the section but took over the page's title and toolbar. Rule now
in `UIComponents/FilterPanelPresentation.swift`: in an iOS inspector, no nested stack and no `.navigationTitle`/
`.toolbar` (they'd land on the owner page); draw a header row. Sheets keep their own stack. (Older lesson in the same
file: a compact "inspector" is the same view tree, so links inside it broke; compact must be a real `.sheet`.)

**The render loop.** Round 2's always-attached `.inspector` + `.sheet` took `Binding(get:set:)` built fresh every
render; SwiftUI never sees them equal, so the presenters re-rendered forever: the Library root spun at ~100% CPU on
skeletons and the hosted test hung 40 minutes in `layoutIfNeeded`. `sample` pointed at FilterPanelPresentation. The
first fix (the original `if/else` by size class) lost the pushed section when the size class settled during launch:
a branch switch recreates the owner's `NavigationStack` and drops its path. Final: one modifier chain for both size
classes with only stable bindings (`$isPresented` or `.constant(false)`).

**Debug-route artifacts.** A DEBUG `.task` on a tab root reruns every time the root reappears, so `acct:settings`
re-pushed Settings 1.5 s after any pop. That produced a false "you can't leave Settings" report (19:40, corrected
19:50 after real taps). Fixed with `takeRoute`. Treat any route-launched shot of a pop/back flow as suspect.

**Readium and a resize.** Facts that cost reviews: Readium publishes a location only after 0.3 s of scroll quiet;
`go(to:)` returns before the location is published; some commands never call back; ordinary locators carry only a
progression, so any restore across reflow is approximate. A locator hold/restore layer (T-449) lost to Contents,
bookmarks, the slider, Read Aloud, native swipes and links in ways each review found anew (R449, R450). What held up:
remove the layer (T-450), turn off the orientation reload (`.never`), and allow only one restore from a reader at
rest, failing safe by skipping. Test fakes on `UIScrollView`/`WKWebView` subclasses can't store properties named
`tracking`/`loading` (they clash with the Objective-C getters); use `fake*`.

**Device Hub, AXe and poses.**
- Poses only through Device Hub's canvas buttons; `~/kudos-tools/duo-pose Open|Closed|Partially Open|Rotate Right`
  presses them by AX description (Terminal has Accessibility since 10-24 11:30). System Events can't see Device Hub's
  windows; `AXUIElementCreateApplication(pid)` works. `~/kudos-tools/dh-press <label>` presses buttons in Device Hub's
  mirrored AX tree, but sidebar `List` rows aren't in that mirror.
- **Device Hub captures simulated touches:** while it runs, AXe taps/swipes do nothing on any simulator. Quitting it
  shuts down every booted simulator. So taps and a Duo pose never coexist: regular-width taps go to a temporary iPad.
- "Partially Open" isn't guaranteed to be a vertical division; read the reserved region after a rotation.
- Inner display = screen 3 (`simctl io <udid> screenshot --display=3`, 2853×2007 landscape / 2007×2853 portrait);
  cover = screen 1. Wrap screenshots in `perl -e 'alarm 40; exec @ARGV'`.
- The Simulator has no rotate command: DEBUG `-KudosDebugRotate "40 landscape 60 portrait"` rotates on any sim.

**Simulators on this Mac** (runtimes 26.5, 27.0, 27.1): `iPhone Duo` `90CEDAA8-…` (27.1); `Kudos Lane E`
`A3E046C4-…` (iPhone 18 Pro, 27.0; the gate's and "iPhone 17" in older notes); the owner's idle five: Kudos Debug,
Kudos iOS 27, Lane C, Lane D, Lane F (~27 GB; deleting them is an open owner question). iPads exist only as temporary
ones on the **27.0** runtime (27.1 has no iPad device types); I created and deleted one per check
(`com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB`).

**Headless: what can and can't be verified.**
- Can: any pose's screenshots; reaching a screen via `-KudosDebugRoute` (`library`, `section:<kind>`, `account`,
  `acct:settings[:<page>]`, `queues`, `work:<title>`, `read:<title>`), auto-open flags (`-KudosDebugOpenFilters`,
  the `shot:` sheets), `-readerMode paged`, rotation on ordinary sims; hosted tests at a set window and size class
  (`LocalNavigationHostTests` uses 951×669 with trait overrides); `sample` on a hung app; AXe taps and `describe-ui`
  on a temporary iPad or Lane E (the first `describe-ui` after boot can be empty: call it twice).
- Can't: taps, swipes, keyboard or drag on the Duo in any pose (Device Hub), so no interaction check in Book pose; the
  file importer; Read Aloud audio; anything needing AO3. These stay owner checks or iPad stand-ins.
- Harness traps: Swift Testing has no default timeout (wrap `gate.sh` in `alarm`); `xcodebuild test-without-building`
  sometimes stays running after the run ends (read `test.log`, then kill it); `screencapture` needs Screen Recording
  (Terminal has it since 21:05); `git diff` skips untracked files in patches (add `git diff --no-index /dev/null f`).

**Capacity.** Codex hit its limit three times on 10-24 (11:20, 15:10, 18:40), each mid-round; Grok is out of balance
(402); Gemini and agy's Sonnet were out. Reviews need a fresh Codex job, so a review and an implementation compete for
the same two slots.

## 4. Where Duo7's six rounds were wrong or incomplete

- **The reader blocked round 3 for the whole day.** Duo7 assumed T-450 would be the baseline; T-451 (a paged reset
  T-450 exposed) took five rounds and five reviews and still waits for R456. Plan reader layout only on a landed,
  reviewed position baseline, with a review slot reserved.
- **Round 4 had to split** (DECISIONS 10-24): 4a Work Detail landed on round 1's helper; 4b (Search, Browse, results)
  depends on round 2's host.
- **Round 2 leaked into other screens.** Duo7 named "inspector plus sidebar leaving no useful content" as the risk; the
  real one was the nested stack, and its fix changes every inspector-hosted filter panel, including Search and Browse
  on iPad, before round 4b reaches them.
- **Replacement sidebars are more machinery than Duo7 implied.** Duo7 said Settings/queues replace the parent list;
  Duo9 did it with `LocalNavigationState` registrations from pushed pages (priority/order, async unregister). Its first
  delivery showed a chosen section highlighted while the detail stayed on the dashboard, and Settings categories
  nowhere. Duo9 also collapses at every accessibility size (Duo7 asked for a measured fit).
- **Round 1's "pane-contained pages" produced one-card pages** in a one-column Book pane (T-454).
- **Duo3 findings no round owns:** #12 the root download banner overlaying the tab container (`App/ContentView.swift:60`);
  #10 subject headers and stat strips outside Home and Work Detail (Author, Series, Fandom/tag pages, collection
  detail); #6 Account's large-text fallback only partly (Duo9 collapses AX sizes). #13/#14 (bulk bar, principal-slot
  fields) sit in round 6; #15 is latent.
- **Screens and flows no round covers yet:** Author profile pages (`Features/Authors/AuthorProfileView.swift`,
  `WorksScopeAndSort.swift`), Series, Fandom and tag works pages (only if 4b claims them), Bookmarks/History/
  Subscriptions lists in Account (round 2 hosts them; their rich rows at width aren't designed), AO3 collections,
  Challenges (sign-ups, assignments), Reading Insights and Recently Deleted (route only, `readableNavigationPage` caps
  760 pt), each Settings page's own layout inside the split (14 pages; only the frame is done), onboarding/Welcome/
  What's New, sheets and form sheets at regular width on the Duo, alerts/confirmation dialogs and menus anchoring near
  the fold, the reader's own sheets (Display, Contents, Read Aloud, search) in Book pose, the composer sheet (round 5
  keeps it), the in-app AO3 browser, the keyboard in Book pose, drag between panes. Search and Browse are 4b; Inbox,
  Comments and Writing are 5.
- **The tab structure:** kept as the system `TabView(.sidebarAdaptable)`. Unexamined: the system's own tab sidebar
  expanding on top of a local split (Duo7 said local navigation must collapse then; `keepsLocalNavigationTabs` only keeps
  the root tab bar visible on pushed wide pages, `UIComponents/FloatingChrome.swift:17-21`), and the portrait floating bar over split content.
- **iPad:** the same layouts apply by measured space, but iPad coverage is spot checks on temporary iPads (T-448,
  Duo9's Library/Settings/Filter). T-452's Home and T-455's Work Detail haven't been seen on an iPad. macOS builds;
  its layouts weren't looked at after Duo9 (LocalNavigationHost is iOS-only; macOS keeps the old stack).

## 5. Riskiest parts, and what I'd do differently

Riskiest, in order:
1. **Round 3, the reader spread.** Position, Readium's CSS columns and the physical-fold gutter in one change, on top
   of a restore that every review has broken so far. Keep the single readable pane as the acceptance floor and never
   two navigators.
2. **The local navigation host.** Split + stack + inspector + sheet + replacement sidebars produced two app-hanging or
   navigation-losing bugs in one round. Every screen that moves into a host inherits the "no nested NavigationStack in
   an inspector, stable presenter bindings, no branch-switching presenters" rules.
3. **Interaction in Book pose is unverifiable here** (Device Hub vs. taps). Fold-adjacent hit targets, keyboard and
   menus need the owner or a geometry test standing in.
4. **Shared components ripple to iPad and the iPhone** (card clamp, filter chrome, region helper). Each round needs an
   ordinary iPhone and an iPad in its check matrix.
5. **Capacity:** two Codex slots, reviews in fresh jobs, frequent limits; plan rounds that can wait half a day.

What I'd do differently:
- Accept "never override a chosen position, otherwise approximate" on day one and ship `.never` + one at-rest restore,
  rather than building and reviewing a hold layer (T-449 → T-450 cost two reviews and eight P1s).
- Build the shot harness before round 1: routes that apply once, auto-open flags per presenter, the rotate hook, and a
  launch helper that waits for content. A false finding ("can't leave Settings") and an inconclusive reader check (it opened at a chapter start) came
  from the harness, not the app.
- Smaller rounds: Duo9 changed Library, queues, Account and Settings at once and needed four rounds of fixes. Land
  Settings first, then Library, then Account.
- For each presenter inside a host, a hosted test that opens it (inspector, sheet, confirmation) and asserts the path
  survives; it would have caught both Duo9 bugs before a simulator run.
- A temporary 27.0 iPad and the ordinary iPhone in every round's checks from the start, scripted (create, install,
  launch, tap, delete).
