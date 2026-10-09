# Brief 3by result

## iOS read first

Read the reference at `/Users/cidy02/kudos-ios-polish/`, without changing it:
`Features/Account/AccountShortcuts.swift`, `Features/Account/AccountView.swift`,
`Models/AO3WorksSort.swift`, `Features/Search/AO3FilterPanel.swift`,
`Features/Authors/WorksScopeAndSort.swift`, `Features/Authors/AuthorProfileView.swift`,
and `Services/AO3AuthorProfileService.swift`.

### Account shortcuts

| Raw value | Title | SF Symbol | iOS destination |
|---|---|---|---|
| dashboard | Dashboard | square.grid.2x2 | Account dashboard |
| markedForLater | Marked for Later | clock.badge | Marked-for-later works list |
| bookmarks | Bookmarks | bookmark | Account bookmarks list |
| collections | Collections | square.stack | My collections |
| subscriptions | Subscriptions | bell | Account subscriptions list |
| works | Works | doc.text | My works |
| series | Series | square.stack.3d.up | My series |
| drafts | Drafts | doc.badge.clock | Writing drafts |
| history | History | clock | AO3 history |
| inbox | Inbox | tray | Account inbox |
| preferences | Preferences | slider.horizontal.3 | Account preferences |
| moreOnAO3 | More on AO3 | ellipsis.circle | More on AO3 |

Defaults, in order: Dashboard, Subscriptions, Works, Bookmarks, Collections, History.
`@AppStorage("account.shortcuts")` stores comma-separated, case-sensitive enum raw
values in order, outside the backup settings. Missing or empty strings restore
defaults. Unknown names are dropped; all-unknown strings also restore defaults.
No trimming or deduplication is done by Swift's decoder.

Editor title **Shortcuts**; headers **On the grid** and **Not on the grid** (the
second is absent if there are no available rows). Every chosen row has a
`minus.circle.fill` and its shortcut's symbol, accessibility **Remove <title>**;
every available row has `plus.circle.fill`, accessibility **Add <title>**. Remove
removes all matching cases; Add appends. Changes persist immediately. iOS enables
list editing and `.onMove`, persisting the resulting order. **Reset to Default**
is disabled exactly when the decoded array equals the defaults. **Done** dismisses.
The first section's empty footer is **If you choose none, the grid is hidden. You
can still find every destination in the sections below.** Account hides the entire
Shortcuts section, including See all, for a decoded empty list.

**Code wins over the apparent intent:** the decoder never returns an empty array.
Removing the last row encodes `""`, which immediately restores defaults. The
footer and hidden-grid branch therefore cannot occur through this store. Android
must retain that behavior, rather than introduce a new empty sentinel.

Android has no native My series destination: the existing Account Series callback
hands a user index to a single-series screen. **Series is excluded** from the
offered shortcuts; no browser substitute or additional read is introduced. The
other eleven destinations already exist.

### Author works sort and completion

Current `AuthorProfileView` places the funnel in the **top-right toolbar**, only
while displaying Works, beside the profile menu. Accessibility **Sort and filter**;
help **Sort and filter the works on this page**. Its badge is the number of active
sort choices plus page-local refine facets: a non-Date Updated column, a direction
different from that column's natural direction, and a non-Any completion each add
one. The chosen column/direction/completion are shown inside the sheet, not as a
replacement toolbar label. Series, Bookmarks, About and Dashboard have no funnel.
The older audit/brief's suggestion of a scope-row control yields to this Swift.

Sheet title **Sort and filter**, **Sort by** row (chosen title plus **9 fields**),
**Direction**: **Ascending**, **Descending**; **Completion**: **Any**, **Complete**,
**In progress**. Footer: **AO3 applies this choice to all matching works, not only
the page you can see.**

| Sort title | `work_search[sort_column]` value | Natural direction |
|---|---|---|
| Creator | authors_to_sort_on | asc |
| Title | title_to_sort_on | asc |
| Date Posted | created_at | desc |
| Date Updated | revised_at | desc |
| Word Count | word_count | desc |
| Hits | hits | desc |
| Kudos | kudos_count | desc |
| Comments | comments_count | desc |
| Bookmarks | bookmarks_count | desc |

Default: Date Updated / Descending / Any. Switching columns adopts the new
column's natural direction; selecting the same column retains the direction.
`work_search[sort_column]` is omitted for Date Updated;
`work_search[sort_direction]` is omitted for the selected column's natural
direction (otherwise `asc` or `desc`); `work_search[complete]` is omitted for Any,
otherwise `T` for Complete or `F` for In progress. Page one omits `page`; later
pages send `page=P`. No Search-tab parameters or refine facets are added.
GET `/users/<username>[/pseuds/<pseud>]/works` (or `/works/collected`); the Gifts
route does not accept these query items. No stats/header/enrichment request is
caused by sorting.

`WorksSortPresentation` seeds a draft on each showing. **Apply** commits only a
changed draft, then closes; `applyWorksSort` resets the Works list to page one.
Unchanged Apply costs zero reads, despite the brief's literal “one read per Apply.”
A dismiss discards the sort/completion draft. **Reset filters** resets only the
live, page-local refine facets, is disabled when those facets are at defaults,
and neither resets nor commits the sort draft. The full iOS form's remaining
controls are Rating, Match (when rated), Include Not Rated, Warnings, Categories,
Chapters, Language, Tags (Fandoms, Characters, Relationships, Additional Tags),
and Word count, with the existing shared form's words. These facets update the
visible loaded page live, including through a dismiss; they never read AO3.
There is no duplicate page-local Completion control in the works sheet.

Sort and facets live in the profile model, survive tab/scope/page changes, and
reset for a new author/pseud or session; they are not device preferences.

## Network scope

`docs/AO3_NETWORKING_POLICY.md`'s **Author profiles** rule allows explicitly
opened profiles and on-demand selected lists/later pages. **No background or
bulk scraping of logged-in pages** permits pages opened through explicit profile
navigation. A changed Apply is one foreground Works-page read, page one; a page
turn reads only that page. No dashboard reload, stats probe, anonymous retry on
an authenticated refusal, read-ahead, or bulk fetch. Shared clients retain their
existing pacing, allow-list and transient transport retry policy.

## Decided without asking

- Keep iOS's actual empty-string/default behavior; test the unreachable footer
  condition rather than inventing storage semantics.
- Exclude Series until Android has the native account series list.
- Reuse the existing SearchFilterSheet in Refine mode for the live facets,
  adding its works-index draft rather than making a second filter form.
- Use the current author-list generation guard pattern for superseded loads;
  this profile screen itself currently lacks that guard.
- Use explicit accessible Move up/Move down icon actions for reorder on Android,
  preserving the ordered result without adding a drag library.
- Enrich the existing `ao3_author_works.html` and its three sample rows rather
  than add unrelated author files. Keep its existing three-page pagination
  (the same sample rows on each page). `data-demo-posted` is a demo-only date key.
- Put models/editor in `account/`, works-index fields in `author/`, and extend
  the existing SettingsRepository and SearchFilterSheet. Tests stay alongside
  the relevant account, author, preferences and demo suites.
- Strip images from profile test responses so the hero's independent Coil
  loader has no URL to request.

## Open questions

- iOS's choose-none footer conflicts with its decoder; retained the decoder
  and no new empty encoding. A future iOS fix should be ported together.
- Gifts excludes work-search parameters; retain iOS's request omission rather
  than sending parameters AO3 does not accept.

## Work log

Started clean on `android/agent-gemini-3by`. Read repository instructions,
onboarding, architecture, regression matrix, persistence/network policy, R1's
two sections, 3az and 3bq including landing notes. No TASKS edits or task claim:
this brief explicitly forbids them. Implementation written for Claude's build/test pass. No Gradle,
Xcode, commits, pushes, branch changes, sign-in or AO3 contact.

## Implementation

- `AccountShortcuts.kt`: eleven supported destinations, Material icons, existing
  list count keys and the Swift-compatible codec. Collections has no cached
  count in Android's count store; none is invented. No native My series choice.
- `SettingsRepository.accountShortcuts` is a collected Flow; its updater edits
  only `account.shortcuts`. No KudosSettings, backup encoding/version, Room or
  schema changes. `replaceAll` retains it, following Favorites' landing.
- `AccountScreen` draws the ordered grid from collected preferences and count
  labels from collected account state. See all pushes **`account-shortcuts`**
  through AppNavHost. All eleven choices use existing native destinations.
- `AccountShortcutsEditor` uses lazy `writingSuggestionPanel` rows, subject
  header/section headers, scope palette, tokens and explicit line heights.
  Add/remove/reset/reorder persist immediately; Done only pops. Accessible
  **Move <title> up/down** icon actions disable at the boundaries, sit beside
  normal rows, and below labels at accessibility sizes. The header inset is
  `statusBars + 76dp`. Only ProvidePushedShellChrome registers shell chrome.
  Account grid labels now wrap fully at accessibility scale.
- `AuthorProfileScreen` offers the funnel in the top-right toolbar on Works
  only, with the existing toolbar badge. The existing Refine form gains the
  works-index sort draft. Dismiss discards sort/completion; changed Apply reads
  page one once; unchanged Apply costs zero reads. Live facets use the existing
  local `matchesSummary` predicate, including after dismiss. Tag suggestions
  come only from loaded rows; no autocomplete repository is supplied.
- `AuthorWorksSortFields` supplies Sort by/menu, 9 fields, ordinary segmented
  direction, wrapping chips at accessibility scale, completion and the exact
  footer. Sort values stack at accessibility scale. SearchFilterSheet now uses
  lazy groups. No shared `ui/subject/` or `settings/` UI components were edited.
  Swift's refine group count ignores Include Not Rated: changing that alone
  still leaves Reset disabled, as on iOS. Reset clears only facets.
- Loads capture route, scope, sort, page and collected session generation.
  The author-list generation pattern plus cancellation fences superseded tab,
  page, scope and Apply requests; old results cannot change rows/errors/loading.
  Header loads have a separate fence. Scope changes no longer cause both a
  handler load and a header-plus-tab effect. Re-tapping a tab/scope costs zero.
  New author/pseud/session resets choices; tabs/pages/scopes preserve them.
  Page-one reload clears returned works, never choices or live facets.
- `AO3AuthorRepository.loadWorks` makes one authenticated request when signed
  in or one public request when signed out. Authenticated refusal returns
  without an anonymous second read. Parse cancellation propagates. An injectable
  parse dispatcher defaults to Default; UI tests use Unconfined, as earlier
  landings require. The existing URL model already matched Swift's parameters;
  its new select(column) method supplies the natural-direction rule.
- Demo's OkHttp interceptor and browser share `demoAuthorWorksPage` over the
  same fixture/address. Only author Works/Collected/Gifts index paths qualify;
  Gifts keeps its unfiltered answer because the builder omits work-search
  parameters there. Drafts, series, bookmarks and forms keep their handlers.
  Missing assets remain terminal local failures.

## Demo routes, taps and rows

Launch the existing local demo with **kudosDemoLibrary=true** and
**kudosDemoSignedIn=true**; no real sign-in is needed. These are handoff
instructions and were not run here.

1. **Account → Shortcuts → See all**, or **`nav:account-shortcuts`**. Remove
   Dashboard, add Inbox/Drafts/Marked for Later, move chosen rows up/down, Done,
   and check the grid order. Reopen and Reset to Default. Remove down to one
   row, then remove it: the six defaults return, as Swift's decoder requires.
   No reachable choose-none demo/footer exists; the empty component branch is
   tested with explicitly empty input.
2. Open the profile from Account's avatar, or **`nav:author-profile/Avery_Archive`**.
   On Works, tap top-right **Sort and filter**, Title, Apply: the first row changes
   from Two Voices at Dawn to A Name Withheld. Reopen, change Direction or
   Completion, Apply. Move to page 2, change a sort, Apply: return to page 1.
   Change a draft and dismiss: applied order/page/request count stay put.

| Demo row | Complete | Posted key | Updated | Words | Hits | Kudos | Comments | Bookmarks |
|---|---|---|---|---:|---:|---:|---:|---:|
| 1001 Two Voices at Dawn | yes, 3/3 | 2026-01-01 | 09 Jul 2026 | 12,345 | 900 | 80 | 8 | 30 |
| 1002 A Name Withheld | no, 1/? | 2026-03-01 | 08 Jul 2026 | 2,000 | 300 | 120 | 2 | 10 |
| 1003 An Orphaned Work | yes, 2/2 | 2026-02-01 | 07 Jul 2026 | 30,000 | 1,200 | 40 | 16 | 20 |

Default Updated descending: **1001,1002,1003**. Creator ascending:
**1002,1001,1003** (Anonymous, Avery Writes + Second Pseud, orphan_account).
Title ascending / Posted descending: **1002,1003,1001**. Words/Hits/Comments
descending: **1003,1001,1002**. Kudos descending: **1002,1001,1003**. Bookmarks
descending: **1001,1003,1002**. Opposite directions reverse each order.
Complete selects **1001/1003**, In progress selects **1002**, by `.iswip .text`,
which these rows actually contain. Python source inspection confirmed unique ids
and every used date/count/chapter field. Kotlin demo tests pin all 54 combinations
and compare each interceptor answer with the browser answer.

## Offline checks written, not run

| Suite | Added tests | Coverage |
|---|---:|---|
| SettingsRepositoryTest | 1 | Literal iOS key/default order; all choices round-trip; raw encoding; mixed/all unknown, missing, empty, case, whitespace, duplicates; last removal/default fallback; unchanged backup payload and preference survives replaceAll |
| AccountShortcutsScreenTest | 5 | Real grid See all/editor transition; add/remove/reorder/reset/Done and collected redraw; external preference update; conditional footer/unreachable store empty; hidden empty grid/absent available section; four themes at double text size |
| AuthorWorksSortTest | 2 | Nine literal Swift query values × two directions × three completions; omitted defaults, page, encoded username/pseud, Collected/Gifts rules; direction selection; one read per load; refusal has no anonymous retry; signed-out public read |
| AuthorProfileSortScreenTest | 5 | Real toolbar/sheet; changed Apply reads page one once and does not reload header; dismiss/unchanged Apply read nothing; reseeding; next-page choice; direction/completion; local Reset leaves draft; late answer dropped; scope single-load and works-only funnel; four-theme wrapping |
| DemoAuthorWorksSortTest | 2 | All 54 orders/completion answers via real local interceptor and browser; pseud/scope/page routing; drafts/series isolation; terminal missing assets before sockets |

The Account test composes the actual shared grid and editor, not the full NavHost.
Author tests compose the actual profile with an in-memory client and real parser.
All clients are injected; demo tests have a throwing downstream interceptor.
Images are stripped only from profile test responses. No test signs in or needs
AO3. Layout assertions check `!didOverflowHeight` and an unellipsized last line.
Compose tests have tall windows, native graphics and idle-before-request waits;
no blocking coroutine cleanup runs in an After method.

## Verification and Claude handoff

Performed: real Swift/Kotlin symbol/caller review, local fixture metadata
inspection, and **git diff --check: passed**. Branch remains
`android/agent-gemini-3by`, everything uncommitted in this worktree. No TASKS
edits, helper scripts, stub files, .orig files, external writes, AO3 contact,
sign-in, branch switch, commit or push. iOS, backup format and Room are untouched.

**Needs a run:** Claude must build Android debug and run `:app:testDebugUnitTest`
with the five suites above, plus existing settings/backup, author URL/parser,
account navigation/shell, Search/Refine and demo isolation regressions.
Compilation, passing tests, request/cancellation timing and Compose behavior
are not claimed. Then run both demo routes through the actual shell/Back/Done,
tap each destination, exercise add/remove/reorder/reset, sorts/completion,
page-one reset, dismiss and tab/scope changes. Inspect Light/Dark/Sepia/OLED at
ordinary/accessibility sizes: header inset, top chrome, long labels, sheet menu,
scrolling, chips and footer need screenshots. No visual correctness claim is
made. This handoff does not authorize live AO3 verification.

## Landing note (Claude, 2026-10-09)

Landed on `android/redesign-parity`. Gate: 2,324 tests.

Changed on landing:

- **Merged by hand** over the series form, the chapter form and "Share Profile", which all
  landed while this was being written: four conflicts (two route lists in `Routes.kt`, the
  author profile's parameters, its call in `AppNavHost.kt`). Both sides kept each time.
- Three test faults: the theme was called without a mode; "See all" was looked for as a
  word, where the header draws an arrow named "See all Shortcuts"; and "Complete" matched
  the status chips of the works under the sheet as well as the sheet's option.

**Nothing has been seen on the emulator** (it would not stay up on 10-09). Owed: the
Shortcuts editor (add, remove, reorder, Reset to Default, the empty grid), the Account grid
following it, and an author's works under each sort and completion choice, with a dismiss
that applies nothing; four themes and large text.

## Seen on the emulator (Claude, 2026-10-09)

Account → See all Shortcuts: removing Dashboard, adding Inbox and moving Works up, then Done,
gave the grid Works, Subscriptions, Bookmarks, Collections, History, Inbox. An author's works:
Sort and filter → Sort by → Title → Apply changed the first row from Two Voices at Dawn to A
Name Withheld. Not seen: choosing none, Sepia and large text.
