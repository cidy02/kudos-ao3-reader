# Brief 3bw — series form

## iOS inventory, read from the reference worktree

Reference is `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`: `Features/Writing/SeriesEditView.swift`, `SeriesReorderDestination.swift`, `Models/AO3WritingModels.swift`, `Services/AO3Client+Works.swift`, `AO3WorkActions.swift`, and the author series/detail views. Read 3bj **including its landing note**, 3l, 3bg including landing, 3bn (series-page result), A4-2 and its T-362 triage, and AO3 networking policy.

Entrances: an owned series page has **Edit series** and **Reorder** in its menu. Ownership uses the registered username in creator links, not the displayed pseud. The author's series list offers swipe actions **Edit** and **Reorder** only for rows whose registered creator matches the signed-in account; a co-created row on another author's profile also qualifies. The work form's Series picker can push Reorder for its selected/first current series. **New series on AO3** opens `/series/new` in Browse, offered on the signed-in author's known-empty series list. Its copy: **You have not made a series.** / `A series groups your works in reading order. Create one on AO3, then refresh this page to see it here.` / `This opens AO3 in Browse, where you can create the series.` Creating a series from a work belongs to the work save. No native standalone create screen. **Delete series on AO3** opens the series show URL in Browse, not a native delete or confirmation dialog. There is no iOS series-delete action.

Opening Edit: GET `/series/{id}/edit` once, required; GET `/series/{id}/manage` once, best effort, including failed attempts. Returning from a child does not reload. Direct Reorder: one required manage GET. Edit passes its existing manage rows to Reorder, with zero opening reads. No per-work metadata reads: already loaded posted-work blurbs join by title in order; drafts stay bare. Save form: zero preparation or verification GETs. Reorder Save: fresh manage GET, one POST, one read-back manage GET (read-back only after no refusal).

Screen: kicker **AO3 Account**, title **Edit series**, subtitle the original series title, optional `N works` and nonzero `N words`. **Series**: required **Title** (placeholder **Title**), **Creators** (placeholder **Add a co-creator byline**), **Series summary** (HTML preview, otherwise Empty/Set; pushes the writing editor), **Series notes** (Empty/Set; pushes editor). Pseuds are parsed and preserved, with no visible selection section in this view. **State**: **Series is complete**; footnote `Complete appears on the AO3 series page and its description. You can still add works to a complete series.` **Works**: **Reorder works** (count; disabled below two), **Remove works** (count; its own screen). Footnote `Reordering changes the saved position on the N works. All positions are saved together.` (one: `the work`). **Delete**: **Delete series on AO3**; footnote `Deleting the series leaves the N works posted and unlinks them.` Header **Save** disabled while saving or title trimmed with Foundation whitespaces is empty. Confirmed save stays open and displays AO3's notice (or **Saved.**); failure displays the reason, retains draft.

Reorder: kicker **AO3 Account**, title **Reorder**, original series title subtitle, **Reading order** label. Lazy rows: current proposed position, title (fallback **Untitled work**), known words/date, **Draft** if suffix ` (DRAFT)`. Drag changes local order only. **Save** writes once, disabled below two or while saving. Footnote `Each work has a numbered position. After you arrange the list, save once to update the whole order on AO3 and check that it was saved.` Success gives the verified rows back to the editor and pops; failure keeps the proposed order. Session failure: `Your AO3 session changed, so the order was not saved.`

Requests (all authenticated, shared pacing/cookies/UA, never retry a POST):

- Form GET `/series/{id}/edit`: captured trusted form action, method override, token, every control. Parser uses meta csrf-token then input fallback. `form.series, #work-form form, form[action*=/series]`; reads title, summary, notes, complete, selected pseud IDs (hidden fallback), literal byline. Manage GET `/series/{id}/manage`: `#sortable_series_list li`, `serial_{id}` (position-for fallback), position or index + 1, heading/link title, draft suffix.
- Save POST to captured action (normally `/series/{id}`), referer **that action**, `X-CSRF-Token` from loaded form; body in iOS order: `authenticity_token`, nonempty `_method` inserted second, `series[title]`, `series[summary]`, `series[series_notes]`, `series[complete]` `1`/`0`, repeated `series[author_attributes][ids][]` in selected order; nonempty literal `series[author_attributes][byline]`. No modeled commit button. Android replays unmodeled successful served controls and never invents an absent control.
- Reorder Save GET manage, fresh **meta csrf-token only**; reject changed membership before POST: `The series changed on AO3 since this screen opened. Reopen it and try again.` POST `/series/{id}/update_positions`, referer manage, fresh `X-CSRF-Token`, body `authenticity_token`, repeated `serial[]` serial-work IDs in proposed order. **No method override**. Read back manage: exact sorted ID order must match. A notice/redirect alone does not prove order.
- Remove (iOS inventory): fresh manage GET/token; membership and last-work checks; POST `/serial_works/{serialID}`, referer manage, `authenticity_token`, `_method=delete`; read back manage, removed ID must be absent. Confirmation `Remove “{title}” from {seriesTitle}?`, actions Cancel / Remove from series; message `The work stays posted on AO3.` Last work is disabled. No series-delete POST.

Save verdict, quoted from iOS: error first (`workWriteError`, includes validation list); `if let notice = AO3Client.workWriteNotice(in: body) { return notice }`; `if (300 ... 399).contains(status) { return "Saved." }`; plain 2xx throws unconfirmed; other status: `AO3 didn't accept the change.` Neither: `AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.` Signed out: `Log in to AO3 first.` Android uses the shared `writeErrorMessage` validation list before notices. Reorder error first, then exact read-back equality; any absent/failed/mismatched read-back is unconfirmed.

Other reference copy: missing token `Couldn't prepare the request. Try again, or open the form on AO3.`; standalone create service refusal `Creating a series from scratch still happens on AO3.`; loader **Couldn't load from AO3** / **Try Again**; draft badge **Draft**; empty work title **Untitled work**. Remove screen subtitle is `{title} · N work(s)`, with `A removed work stays posted and only leaves this series.` or `AO3 deletes a series when its last work leaves. Remove the last work by deleting the series on AO3.` Last-work refusal: `It is the series' last work on AO3, and AO3 deletes a series with its last work.` Removal failure: `{title} was not removed. {reason}`; cancellation: `Your AO3 session changed, so nothing was removed.` Save reports `UserFacingError.message(for:)`; it has no dedicated series session-change sentence. The generic cancelled request message is `The request was cancelled.`

## Android implementation

Implemented the form as transient data first, then its screen and Save, then reorder and iOS's Remove works. New `network/ao3/writing/AO3SeriesForm.kt`, `AO3SeriesFormParser.kt`, and `AO3SeriesFormRepository.kt` use the existing served-control snapshot, authenticated client and shared form encoding. New `writing/WritingSeriesState.kt` and `WritingSeriesScreen.kt` use the existing text editor, form section/footnote/toggle parts, token palettes and lazy panels. No Room, backup, dependency or durable draft-format changes.

The encoder emits iOS's modeled values in iOS order only for names AO3 actually served and enabled. Every other served successful control is replayed, preserving duplicate names, HTML text and hidden fields; unchecked/disabled controls and submit buttons without a submitter are omitted. An empty modeled byline replays its served value, following 3bb's replay boundary. Literal nonempty byline is sent, including spaces, with no invented absent field. Selected pseuds survive a save; this screen does not add a pseud picker that iOS lacks. Captured actions must pass `AO3RedirectCookieRelay.isTrustedUrl`; the parser additionally requires a POST series action and refuses an existing-series destroy form.

The repository makes exactly one authenticated GET for each explicit method. The screen owns the required edit read and the optional manage attempt, stamped **before** suspension; refusal, exception or cancellation consumes that optional attempt. A cancelled optional read under the same session retains the required form, as iOS's `try?` does. A required refusal stops before manage; signed-out or invalid-ID openings make no GET. The opening generation fences loading and writes; no anonymous fallback after an authenticated refusal.

Save uses the existing `AO3WriteRepository` and `postAuthenticatedInSession`, `writeHeaders`, shared pacing, cookies and UA. There is one non-cancellable, non-retried POST after dispatch, with no preparation or verification GET. `writeErrorMessage` reads AO3's `div#error` validation list first. Only the scoped notice or iOS's 3xx verdict confirms Save; plain 2xx is `AO3CollectionFields.UNCONFIRMED`. Busy taps cannot dispatch another POST. Every failure leaves the complete typed form and served-control snapshot in place.

Reorder holds serial-work IDs from manage, including drafts, with zero per-work reads. Opening it from the editor takes the held rows; opening it directly reads manage once. Long-press drag/drop and **Move Earlier** / **Move Later** accessibility actions edit the local list. Save checks fresh membership and fresh meta token, sends the entire order once, and reads back once. Only exact verified order updates the editor's held works and returns; failures retain both the proposed order and the unchanged parent form. Remove uses the same preparation/write/read-back path, a fresh last-work guard and iOS's confirmation. No native series deletion.

The screen draws from collected `state`, including async summary preview, never from a flow-value accessor. Form, reorder and removal lists each retain their scroll state. Summary/notes use the existing editor checkpoint; Back flushes composition and its pending checkpoint before returning. Parent work/author/series state is remembered before the child branch. Each replacement registers only `ProvidePushedShellChrome`. The shell's Save is **null as a value** until form/rows arrive, and is null on Remove works; a delayed-load test covers its appearance. Returning from child editors restores the parent's chrome without reads or writes. Counts and Empty/Set are `trailing` content, so long labels keep their width. Accessibility titles/preview wrap; text and progress colors use tokens for Light, Dark, Sepia and OLED.

Entrances are wired to owned show-page menus, author series-row menus and the work form's existing Series picker. Registered creator identities come from the already-read show/list HTML, with no identity lookup GET or pseud guessing. Show uses one authenticated read when signed in, without anonymous fallback. Account → Writing → Series now opens the author list rather than treating `/users/{username}/series` as a numeric series show route. New series and Delete series keep the in-app browser boundary.

## Tests written — not executed

**37 added test methods**: 21 in `writing/WritingSeriesTest.kt`, 11 in `writing/WritingSeriesScreenTest.kt`, 3 in `network/ao3/DemoSeriesFormTest.kt`, and 2 added to the existing `AO3SeriesRepositoryParseTest` in `network/ao3/series/AO3SeriesRepositoryTest.kt`. These are source counts, not passing results.

- Parser fixture covers action, meta/input token precedence, method, pseuds/hidden fallback, literal byline, HTML, complete, all 15 controls, serial positions and draft rows. Trust, login, missing landmarks, destroy override and author-prose false-overload cases are covered.
- Untouched encoding is compared with an independent explicit browser payload; edits are checked against explicit iOS fields/order and individual deltas, including nonempty byline, duplicate replay, disabled/unchecked omission and absent-control omission.
- Counted openings, required refusal, optional failure/cancellation memory, invalid IDs and session fences; one POST per held Save/reorder; zero extra form-Save GETs; fresh meta-only reorder token, full serial order, membership refusal and exact read-back.
- Notice, redirect, validation-before-notice, plain 200/204, other-status fallback, rate limit, server/offline failure and session cancellation retain every typed field. Reorder mismatch/failed read-back retains both orders. Removal confirmation/cancellation, verification, fresh/local last-work guards and failure retention are covered.
- Compose tests use a tall window, native graphics and waits preceded by `waitForIdle`. They cover delayed toolbar registration, summary Back/notes Done checkpoints, work form → Series picker → Reorder → Back → picker → Back with the same unsaved work, actual drag, accessibility moves, 150-row laziness, busy Save, browser Delete and all four themes at 2× font scale. Short-label layout assertions use `!didOverflowHeight` and no last-line ellipsis; shared matches are counted. Coroutine experimental APIs have `@OptIn`; blocking test lambdas explicitly return Unit where needed.
- Demo/shared-client tests use terminal local interceptors or recording clients, never sockets. They check local Save/refusal/reorder persistence/reset, one POST on 429/503, real cookie/UA/token/referer/body encoding, unsafe action with zero traffic and missing-fixture local 404. Detail tests check ownership from registered creator links and one authenticated show read without fallback.

## Local demo routes and taps

Use the existing isolated demo launch extras `kudosDemoLibrary=true`, `kudosDemoSignedIn=true`, in airplane mode; they provision local fixtures/session, not a live sign-in. No demo launch was performed here. Supported series is **321, The Dawn Cycle**, already listed by the demo author. Added original filler fixtures `ao3_demo_series_edit.html`, `ao3_demo_series_manage.html`, `ao3_demo_dawn_series.html`; only series 321's registered creator link in `ao3_author_series.html` changes to `AO3_Reader`, keeping displayed pseud **Avery Writes**. Rows are First Light, A Lamp at the Crossing, The Last Window (DRAFT), serial IDs 3211–3213.

1. Account → Writing → Series, or debug `kudosDebugRoute=nav:author-series/AO3_Reader`. On The Dawn Cycle, **Actions for The Dawn Cycle → Edit**. Alternatively open its title and use **Edit series**. Direct show debug route: `nav:series-works/https%3A%2F%2Farchiveofourown.org%2Fseries%2F321`.
2. Change Title, Creators, summary/notes or complete, then **Save**. The local notice is **Series was successfully updated.** Reopening Edit reads the stored local form.
3. Set Title to **Refuse this series**, change another field, then **Save**. AO3-shaped `div#error > ul` reports **Title is too long (maximum is 255 characters)**; all edits remain on screen and the previous saved fixture remains unchanged.
4. **Reorder works**, long-press/drop a numbered row (or use its accessibility move action), then **Save**. The local POST changes manage order; the read-back confirms it and returns to Edit. The draft participates. Author-row **Reorder** and show-menu **Reorder** open the same native destination directly.
5. **Remove works → Remove → Remove from series** verifies local removal; **Cancel** sends nothing. Once only one remains, there is no Remove control. **Delete series on AO3** opens Browse. New series is a browser link only when the own list is known empty; this populated fixture does not invent an empty-list route.

GET `/series/321/edit`, GET `/series/321/manage`, POST `/series/321`, POST `/series/321/update_positions` and POST `/serial_works/3211`–`3213` are local. Missing assets fail terminally; no socket fallback. Mutation lasts for the interceptor/process lifetime and resets on relaunch. Show/list blurbs retain their original display fixture; edit/manage are the mutable answers. Existing work-form fixtures still offer series 77/88; the supported mutation demo deliberately stays with 321 reached from Account/list/show.

## Decided without asking

- Place transient series models/parser/repository beside the existing work form, screen/state beside writing screens, fixtures in existing debug assets and tests in their existing package families. Reuse shared components/transport; no helper script, stub, `.orig`, new dependency or persistence layer.
- Reuse series 321 and original filler, with its registered creator corrected for local demo ownership rather than add another demo account/series. Keep its pseud display unchanged. Mutate only edit/manage answers; reset through the established interceptor lifetime.
- Preserve iOS's native **Remove works** rather than expose an inert row. Keep standalone New/Delete series in Browse, with no native create/delete POST.
- Use a compact existing card-header action menu for author rows instead of iOS swipe gestures or adding a vertical action row; exact **Edit** / **Reorder** labels and creator gating remain.
- Preserve selected pseuds silently; Creators edits only the literal co-creator byline, as iOS's view does. Save availability follows Foundation whitespaces (not newlines), without trimming the submitted title.
- Interpret “one-read repository” as one GET per explicit load method. **iOS wins over a one-GET total editor interpretation:** it requires edit plus one optional manage attempt. No metadata, identity or automatic retry reads are added.
- For Save's Android session fence use the existing work-form sentence **Your AO3 session changed. Reopen this form before saving.** iOS Save uses generic localized error mapping rather than a dedicated series cancellation sentence. Reorder/removal keep iOS's explicit sentences. Android's existing form loading row says **Loading…** / **Saving…**, whereas iOS shows progress without text.

## Open questions

- No blocking product questions. Optional manage failure keeps an editable form with no works rows; there is no best-effort retry or fallback work read. Ownership absent from AO3's served creator links offers no native editing action. These are the sparing choices.
- Drag/drop currently targets visible rows; there is no edge auto-scroll during a held drag. Scroll between drags or use Move Earlier/Later for distant positions. Claude should check pointer behavior on device before landing; no extra request is needed for either interaction.

## Landing overlap and verification handoff

This work stays on `android/agent-gemini-3bw`, intentionally uncommitted. The brief overrides the general TASKS/commit/build workflow. No branch switch, commit, push, TASKS edit, sign-in, AO3 contact, iOS edit, schema or backup-format change. The lane's newer Edit tags work was **not merged here**.

Claude must reconcile these three overlapping files while preserving the lane's Edit tags implementation and shared private `submitWork`:

| File | 3bw change to retain |
|---|---|
| `WritingWorkFormScreen.kt` | Optional series repository/writer passed to content, remembered standalone reorder destination before child branches, callback from the Series picker, return to the held work/picker. Existing work Save/tag behavior is unchanged here. |
| `AO3WriteRepository.kt` | New `saveSeries`, `reorderSeries`, `removeWorkFromSeries` and private `changeSeriesWorks` before existing work writes. This diff does not refactor `saveWork` or implement `editWorkTags`/`submitWork`. |
| `DemoNetwork.kt` | Series 321 routes, interceptor-owned `DemoSeriesWrites` and its terminal local answers before other handlers. Existing `DemoWorkSaves` is unchanged here. Keep the lane's Edit tags routes/handler. |

Static checks: reread real Swift/Kotlin symbols and call sites, fixed the missing reorder callback signature, checked editor Back checkpoint and shell registration paths, reviewed test return/wait/opt-in patterns; `git diff --check` passed. **No Gradle, Xcode, Kotlin compilation, unit/Compose tests, emulator launch or visual inspection was run.** All compile, runtime, timing, read-count, one-POST and layout claims above describe implementation/test assertions and need execution.

Claude's remaining gate: from `android/`, build `./gradlew :app:assembleDebug`, run `./gradlew :app:testDebugUnitTest` (including the 37 added methods plus existing author/profile/routes, work-form/association, shared write and demo suites). Confirm the lane reconciliation compiles. Manually exercise demo Save success/refusal, both kinds of reorder entrance, pointer drag, summary/notes and work-picker Back, session failure, native removal/last-work guard and browser links. Capture Light/Dark/Sepia/OLED at accessibility scale with keyboard visible and shell restored; visual correctness remains unclaimed. Keep this verification fixture-only and offline.

## Landing note (Claude, 2026-10-09)

Landed on `android/redesign-parity`. Codex wrote most of this on 10-08, stopped on its usage
limit, and finished it on 10-09 from where it had stopped. Gate: 2,253 tests.

Changed on landing:

- **Merged by hand over Edit tags** (3bt landed between this brief's base and its end): one
  conflict, in `WritingWorkFormScreen.kt`, where both added a screen that takes the form's
  place (the tags screen, the series reorder). Both are kept. `AO3WriteRepository.kt` and
  `DemoNetwork.kt` merged by themselves.
- Two test faults: the key for a row's custom accessibility actions is
  `SemanticsActions.CustomActions`, not `SemanticsProperties`; and one test compared a whole
  parsed form where only the summary could be equal.

**Nothing has been seen on the emulator**: it would not stay up on 10-09 (the Mac was out
of memory with five agents running). Owed: Edit series from an owned series page and from
the author's own series list; Save, with a refusal; Reorder by drag and by Move Earlier /
Later, with Save; Remove from series and its confirmation; a series the reader does not own
offering none of it; four themes and large text. The open question about dragging past the
edge of the screen needs a device. Nothing here has run against AO3.

## Seen on the emulator (Claude, 2026-10-09)

`nav:series-works/…321` → More actions → Edit series: the form opens with its four sections;
Reorder works: a long-press drag moved the third work to the top, Save returned to the form
and the order was kept on reopening; the complete switch and Save give "Series was
successfully updated." (below the fold until the landing of audit A26 made Save scroll to it).
Not seen: Remove works, a refusal, Sepia and large text.
