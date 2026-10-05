# Brief 3az — Writing › Drafts

**Landing note (Claude, 2026-10-05).** Landed with one change. It applied cleanly, compiled
and passed first time; gate green (1,663 tests). It reads one page of the reader's own drafts
per opening, page turn and refresh, and sends nothing.

Changed on landing: the header was drawn too high. The list began 20dp from the top of the
window, so the kicker sat under the clock and the shell's back arrow lay over the title. It
now leaves the room the Moderation screen leaves (the status bar and the back row).

Seen on the emulator in airplane mode against the demo's two pages, in Light, Dark, Sepia and
at double text size: the list from Account › Writing › Drafts; "29 days left", "7 days left",
"1 day left" and "Last day" chips, and a draft with no deletion notice showing neither a chip
nor a Created date; the tally line on each page; page 2; a tap on a draft and the New Work
button each opening the in-app browser, which in the demo shows a bundled page. Not checked:
OLED after the header fix, the signed-out state, and the list on a day change.

Until Android has the work editor, a draft tap and New Work open AO3's pages in the in-app
browser; both addresses are in `WritingWorkDestination` in `account/WritingDraftsState.kt`.

**Deliberate temporary difference from iOS:** Android shows only `AO3 deletes an unposted draft 30 days after you create it.` It omits the recovery-copy sentence until Android actually keeps writing recovery copies. This decision and including New Work were answered by **Claude, who runs the port; the owner has not been asked**. The notice's one-line code comment marks where to add the second sentence later.

## iOS reference inventory

Read-only reference: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Writing/WritingDraftsView.swift`, `Features/Account/AccountView.swift`, `Services/AO3Client+Works.swift`, `Services/AO3WorkActions.swift`, `Services/AO3Client.swift` (`parseWorksList`), `Services/UserFacingError.swift`, `Models/AO3WritingModels.swift`, `Models/AO3Models.swift`, `UIComponents/SubjectStateBadge.swift`, `UIComponents/WorkStatLabel.swift`, and `App/DemoLibrary.swift`.

- Subject header: **AO3 Account** / **Drafts**. Before a result for the current session, no subtitle. A single page says `1 draft` / `N drafts`, optionally followed by ` · N expiring this week`. Multiple pages say `page P of T`, optionally followed by ` · N expiring this week on this page`. Only parsed deletion dates on the loaded page contribute to the expiry tally.
- Orange notice, verbatim: `AO3 deletes an unposted draft 30 days after you create it. Recovery copies stay on this device and aren't deleted with it.` The iOS notice uses orange fill at 0.1 opacity and orange border at 0.34 opacity.
- Cards: first nonblank fandom's bare display name, count of additional fandoms, expiry badge when the deletion date parsed; title (`Untitled` fallback); required-tags square with rating, categories, warnings and completion; summary; formatted word count with singular/plural; and a `Created …` date derived from the deletion date. No author row or chapter count. iOS explicitly omits the misleading draft chapter count. Created date uses `.dateTime.day().month(.abbreviated).year()`, with locale formatting.
- Badge tones: red for three days or fewer, orange for four through seven days, mint beyond seven. `DraftExpiry.chipText` says `Last day` for zero or fewer, `1 day left`, or `N days left`; `SubjectStateBadge` draws these uppercase but announces the original phrase. Whole calendar days from today's start to the deletion day, clamped to zero; Created is deletion minus **29** calendar days. The 30-day notice and 29-day derivation intentionally match iOS's distinct constants. A missing/unparsed deletion date shows neither badge nor Created date, rather than substituting another date.
- Loaded nonempty list section label: `On AO3`. Empty: `Works you save as drafts appear here.` Loading: `Loading drafts…`. Failure: `UserFacingError.message(for:)` plus `Try Again`. Signed-out `loadDrafts` throws `AO3WorkWriteError.notSignedIn`: `Log in to AO3 first.` plus the same `Try Again`; no distinct login card/button. No request while signed out.
- One bottom `SearchPaginationBar` when there is more than one page. Loading clears the previous result. Fetch task is keyed by session generation, requested page and reload counter; pull-to-refresh increments reload. App resume and calendar-day notification update `now` for chips and tally; they do **not** request the list again. A returned result is guarded against cancellation, changed session and changed requested page.
- Draft tap opens `WritingWorkDestination(workID:)`, which loads the form and opens native `WorkEditView`. This brief explicitly substitutes Android's in-app browser edit destination until its editor exists; that destination must live in one place.
- iOS also has a top-right **New Work** navigation link to `WritingWorkDestination(workID: nil)`. Claude clarified that Android must include it, opening the in-app browser until the editor exists.
- Request: `AO3AuthService.loadDrafts` requires the session, builds `AO3Client.myDraftsURL`, and makes one `authenticatedPageHTML` read of `/users/{username}/works/drafts`; page one omits the query and later pages add `?page=P`. `draftsPage` parses that one response as `parseSearchPage` and `parseDraftDeletionDates`. The latter takes only `li.work.blurb#work_ID`'s first `p.caution.notice`, with numeric `span.date`, numeric `span.year`, and the full English month from `abbr.month[title]`. The blurb's `p.datetime` is the revised date and is never used for expiry or creation.

Top-of-file comment explaining why this list has no Post/Delete actions:

> - **1x's Post and Delete swipe actions.** Both are AO3 writes — posting
>   notifies subscribers and cannot be undone — and both already live in
>   the editor (`WorkEditView`) behind its own buttons. A swipe is the
>   easiest gesture in the app to fire by accident.

## Questions raised before implementation

The brief says iOS code wins and to ask immediately and stop if a question remains.

1. **Resolved by Claude, who runs the port; the owner has not been asked:** include iOS's **New Work** top-right action. Reuse `AO3CollectionsScreen.kt`'s `ProvidePushedShellChrome` registration and shared toolbar button, with iOS's accessibility words. Until the editor exists, both New Work and draft taps open the in-app browser; keep both destinations in one place for replacement together. New Work sends nothing by itself. The demo browser must stay local; a bundled new-work page is optional if trivial, otherwise its local not-found page is acceptable and must be documented.
2. **Resolved by Claude; the owner has not been asked:** omit the recovery-copy sentence until Android has that protection. Keep the first sentence verbatim; mark the future insertion in code. For the rest of this brief, omit and document any iOS words describing a feature Android lacks, without otherwise rewording iOS.

## Work log and current handoff

Started clean on `android/agent-gemini-3az`. Before this change, Android's Account Writing › Drafts row opened `https://archiveofourown.org/users/$it/works/drafts` in the browser. Read the 3av/3aw result reports and landing notes, repository operational documents, the reference sources above, and the real Android account components, auth/client, parser, shell, routes and demo callers. No graph was present in this worktree.

Stopped before implementation for both clarifications and resumed after Claude answered them. Implementation, local demo and offline tests are written and remain uncommitted for Claude. No TASKS.md edits, commits, pushes, branch switches, sign-in, AO3 requests, Gradle/Xcode execution, helper scripts, stub files or .orig files. iOS, backup format and Room schema are untouched.

## Network scope

The policy's **What agents must NOT implement → No background or bulk scraping of logged-in pages** expressly limits authenticated reads to, among other exceptions, **the user's own account lists**. This is one such list, opened explicitly and owned by its visible composition. Only opening, an explicit page turn, refresh or Try Again reads the index; no read-ahead, per-draft enrichment or background request. Resume/day-change only recomputes local copy, matching iOS code. The existing client retains User-Agent, allow-list, pacing, slots, coalescing and transient GET retries. No writes or persistence changes are introduced.

## Implementation

- `account/WritingDraftsScreen.kt`: subject wash/header using `tokens.scopePalette`; iOS's tally, expiry-only notice, loading/error/empty copy and section order; draft-only cards with fandom count, title, required-tags tray, summary, words and localized Created date. No author, chapter count, tag link, long-press menu, Post or Delete. New texts have explicit line heights. At `isAccessibilityFontScale()`, title/summary/fandoms can wrap fully, the status tray and metadata reflow below, and shared pagination stacks. No shared-component line heights were changed. Notice/chip urgency colours come from theme-aware `SubjectPalette.fromHue`, preserving red/orange/mint thresholds; the required-tags tray reuses the account cards' `statusChips`/`WorkStatIcons`/AO3 status colour helpers.
- New Work registers the shared `ToolbarAddButton` through `ProvidePushedShellChrome`, as Collections does, with accessibility name **New Work**. Both its `/works/new` address and a draft's `/works/{ID}/edit` address live in **`account/WritingDraftsState.kt` → `WritingWorkDestination.url`**. `AppNavHost` hands these to the existing in-app browser. Replace this single destination helper/caller together when the native editor arrives. The list does not fetch either form or send a write when a card or New Work is tapped.
- `account/WritingDraftsRepository.kt`: calls the existing `AO3AuthenticatedClient.getAuthenticated` (the container's `DefaultAO3AuthenticatedClient`) once per list load. Signed-out loads return before the client. Parsing uses an injectable `parseDispatcher`, Default in the app and **Unconfined in Compose tests**, per the 3aw landing note. Cancellation and session generation guard both the response and parsed data; a served login form expires the session without an anonymous retry.
- `network/ao3/writing/AO3Drafts.kt`: draft index URLs reuse `AO3AuthorUrls.userDraftsUrl`; work parsing reuses `AO3AccountParser`/`AO3SearchParser`. The draft parser adds iOS's all-blurbs-unparseable failure check, without changing other lists' parsers. Expiry parsing uses only the notice's English month/day/year. `DraftExpiry` uses `LocalDate` calendar arithmetic, accepts a passed clock, derives Created with the 29-day offset, and supplies the exact tally/chip words and urgency thresholds.
- `WritingDraftsState` is owned by the current page/session composition. An opening or page change performs one load; refresh/retry perform one additional current-page load. Concurrent duplicate loads on that composition are ignored. Loading clears stale rows/tally. Disposal cancels opening/refresh/retry work. Resume and date/time/time-zone broadcasts update only the local calendar day; they never load AO3. Production day reads use the current device zone; tests inject a clock.
- Account's actual Writing row now calls `onOpenDrafts`, routed to **`Routes.WritingDrafts` = `writing-drafts`**. Subject header/tab-bar rules match other pushed lists. The existing More on AO3 browser destinations and signed-out Account preview are unchanged. The old `AO3AuthorUrls` and destination-test comments claiming Drafts had no native list were corrected.

**Where the brief/older outline differ from iOS, iOS code wins:** retain New Work (Claude's clarification); Created uses deletion minus **29**, while the notice still says **30**; zero days reads **Last day**; paged tallies omit a fabricated total-draft count and explicitly scope expiry to the loaded page; app resume/day-change recompute without fetching; chapter count and Post/Delete are absent. The only iOS wording omitted for an unavailable Android feature is the recovery-copy sentence, by Claude's explicit answer. Editor navigation is the browser fallback explicitly requested by the brief and clarified for New Work.

## Local demo

Open **Account → Writing → Drafts**, or the existing `nav:` debug-route mechanism consumed by `KudosApp.kt` → `MainScaffold`:

```sh
adb shell am force-stop io.github.cidy02.kudos
adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --ez kudosDemoSignedIn true --es kudosDebugRoute nav:writing-drafts
```

These commands are handoff instructions and were **not run here**.

Page 1: **Lanterns Above the Mill** (995001, 29 days, mint), **Seven Quiet Windows** (995002, 7 days, orange, two fandoms), **A Map Without a Date** (995003, missing notice: no chip or Created date, `1 word`). Tally: `page 1 of 2 · 1 expiring this week on this page`.

Page 2: **One More Ferry** (995004, `1 day left`, red), **Last Light in the Orchard** (995005, `Last day`, red). Tally: `page 2 of 2 · 2 expiring this week on this page`.

All five are original filler in the two new `ao3_demo_drafts_1.html` / `ao3_demo_drafts_2.html` assets. Their deletion notices have demo-only day offsets. `demoDraftsPage` rebases those notices to today's device-local date when the local interceptor/browser answers a drafts request, so opening on any date still demonstrates 29/7/1/0. While the already-loaded screen remains open, day changes count down those loaded dates without any request. Tests pin the demo clock in leap-year and year-boundary cases. No production response or persistence data is rebased.

Drafts routes are anchored and precede the generic user Works fixture route; neither page replaces the Works, dashboard or other screens' fixtures. Missing assets return a terminal local failure. New Work and draft edit browser pages were **already bundled** (`ao3_work_new_draft.html` and `ao3_work_edit.html`), so no extra form fixture or browser change was needed. `AO3WebViewFallbackScreen`'s existing demo isolation serves these or a local not-found page and does not contact AO3.

## Offline tests written, not run

| Suite | Cases | Covers |
|---|---:|---|
| `WritingDraftsTest` | 13 | Both fixture pages and fields; missing/unreadable deletion notices; malformed-neighbour/all-malformed parsing; 29/8/7/4/3/1/0/past thresholds; calendar midnight in a local zone with a passed clock; 29-day Created derivation; each tally case; URLs and pushed-route rules; one authenticated index read per opening/page/refresh; no signed-out reads; busy duplicate prevention, error/retry, cancellation/logout and served login page |
| `WritingDraftsScreenTest` | 14 | The real `AccountDraftsRow` component opening the screen; draft edit address; shared toolbar's New Work name/address and no extra reads; absence of Post/Delete/recovery promise; page turn; date-change and resume updating copy with no read; loading, empty, failure, signed-out/retry; actual pull-to-refresh; Light/Dark/Sepia/OLED and double-font-scale field availability |
| `DemoDraftsTest` | 3 | Real interceptor's two pages rebased against pinned clocks; route isolation from Works; bundled new/edit browser pages; local browser drafts answer; missing assets never fall through |

Repository/screen tests use an in-memory GET client behind the real authenticated wrapper and a POST client that throws if called. Demo interceptor tests install a downstream interceptor that throws before any socket request. The Account interaction test mounts the **same extracted row used by AccountScreen**, then the real drafts screen; it is not a full production NavHost test. Actual `AppNavHost` wiring was read and still needs the demo navigation pass.

## Verification and Claude handoff

Performed here: source/caller/symbol review against the named Swift/Kotlin components; Python standard-library HTML inspection verified five unique draft ids on two pages, four notices with offsets 29/7/1/0 and one missing notice; `git diff --check` passes. No Gradle, Xcode, emulator, tests, sign-in or AO3 traffic. **Compilation, passing tests and visual correctness are not claimed.**

Claude must build Android debug and run `:app:testDebugUnitTest`, including all three new suites, account destination/navigation/shell tests and existing demo/networking regressions. The request-count, cancellation/session isolation, clock/day change, parser/empty/error, interaction and theme assertions above require that run. Then exercise the local demo's Account row and `nav:writing-drafts`, page turns and refresh, both browser destinations and Back, missing-date card, app resume and midnight/day-change, and compare screenshots in Light/Dark/Sepia/OLED and accessibility text sizes. Check the largest text for clipping, the required-tags tray and localized Created dates; screenshot review remains manual.

Everything stays in this worktree, uncommitted and unpushed for Claude's build/test/review/commit pass. No open product question remains from this brief; the native editor and recovery feature are later briefs. This handoff does not authorize live AO3 verification.
