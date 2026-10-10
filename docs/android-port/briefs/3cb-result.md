# Brief 3cb — sign-ups list and withdrawal

**3cc follow-up (unbuilt Codex handoff, 2026-10-09).** Assignments and Defaults/pinch hits now request the native assignments screen; see [3cc-result.md](3cc-result.md) for request admission/counts, the two owner writes and pending verification. Settings still reads no assignment list for its own tally rows. The Sign-ups join still reads only Complete/Open/Defaults; its parser and shared Winter fixtures are extended, not duplicated. Historical browser-destination statements below describe the earlier landing.


## iOS first: requests, counted before implementation

Read the actual Swift in `/Users/cidy02/kudos-ios-polish/` (unchanged): `Features/Challenges/ChallengeSignUpsView.swift`, `ChallengeSignUpView.swift`, `Features/Account/AO3CollectionDetailView.swift`, `Services/AO3Client+Challenges.swift`, `AO3ChallengeActions.swift`, `AO3CollectionActions.swift`, `AO3WriteActions.swift`, and `Models/AO3ChallengeModels.swift`.

One list opening/refresh on iOS, sequentially: (1) `GET /collections/:slug/gift_exchange/edit`; only 404 or a non-gift form falls back to `GET /collections/:slug/prompt_meme/edit`. This is owner-only; a moderator's failed probe is swallowed. (2) Complete `GET /collections/:slug/assignments?fulfilled=true`, every page; (3) Open `GET /collections/:slug/assignments?unfulfilled=true`, every page; (4) Defaults `GET /collections/:slug/assignments`, every page. A failure stops that assignment walk, makes matching unknown, and still permits the sign-ups read. (5) `GET /collections/:slug/signups` (page one has no query). (6) Only if pagination reports more pages, `GET /collections/:slug/signups?page=:last` for the total. Successful two-page, single-page-assignment example: six reads. `phase == .idle` prevents another opening read; explicit refresh starts again. Load more reads just the next sign-ups page and does not repeat schedule/assignments/total; the total's last page is not inserted into the pager, so Load more can read it again. Failed pages retain existing rows. Participant detail: **zero reads**, zero writes, inline prompts from the index. The audit's total-count address and assignment-query description are superseded by this Swift: **iOS code wins**.

One own-form opening: `GET /collections/:slug/signups/new` or `/:id/edit`, once behind the existing form's attempted-load guard on Android. Only an existing parsed `signUpID` exposes Withdraw; Swift does not add a challenge-open visibility check. The service describes it as withdrawal while sign-ups are open, but AO3 decides whether the deletion is allowed. Confirmation/cancel does not read. Confirm Withdraw: one fresh `GET /collections/:slug/signups/:id/confirm_delete` for the **meta csrf token**, then exactly one `POST /collections/:slug/signups/:id`. No follow-up read, no write retry, no extra served fields.

## Android requests, counted before the implementation account

Successful two-page Winter opening, in order:

| Viewer/state | Reads | Order | Writes |
| --- | ---: | --- | ---: |
| Owner, known closed gift exchange | 6 | gift edit; Complete page 1; Open page 1; Defaults page 1; sign-ups page 1; sign-ups last page | 0 |
| Owner, known open | 3 | gift edit; sign-ups page 1; sign-ups last page | 0 |
| Owner, failed schedule probe | 3 (4 with missing/non-gift fallback) | attempted gift edit (optional meme edit); sign-ups page 1; sign-ups last page | 0 |
| Moderator | 2 | sign-ups page 1; sign-ups last page | 0 |
| Neither owner nor moderator | 0 | refused locally before constructing a request | 0 |
| Signed out | 0 | existing signed-out sentence, no request | 0 |
| Participant detail | 0 | uses the selected index row | 0 |
| Load more | 1 | next sign-ups page only | 0 |
| Withdraw Cancel | 0 | native confirmation only | 0 |
| Confirm Withdraw | 1 | fresh confirm-delete page | 1 single POST |

A single-page sign-ups list saves the last-page read. The settings reader retains iOS's gift-to-meme fallback; a known prompt meme does not probe assignments. Assignment failure stops that three-list sequence: a Complete failure makes four opening reads (settings, attempted Complete, first/last sign-ups); an Open failure makes five. A failed last-page total remains absent and does not lose page-one rows. Recomposition/duplicate load does not repeat a completed **or failed** opening. An explicit refresh starts the same bounded sequence; it sends nothing. Permission/session refusals on the required index make the pager terminal instead of exposing a read AO3 has just refused. Load more does not reattempt optional reads. Transport-level transient GET retries remain owned by the existing client/policy (at most two); there is no new retry loop, and 403/404/parse failures and every POST are never automatically retried.

## iOS access, taps, content and exact words

Collection Manage shows Sign-ups only with a sign-ups link **and** `show.isMaintainer` (owner or moderator). Challenge Settings belongs to owners; its gift exchange Sign-ups row opens the same list. Your Sign-up is independent of maintainer status and requires login plus a sign-ups link. List rows push a read of that participant; bottom links “Your sign-up” (own ID by case-insensitive login or trailing `(login)`) and “Create sign-up” open the existing form. Matching has no chip without a successful nonempty assignment array. The join prefers request sign-up ID, then case-insensitive recipient byline; a giver and no default mean MATCHED, otherwise UNMATCHED.

Header kicker is collection title (slug fallback), title “Sign-ups”; subtitle is total “1 sign-up” / “N sign-ups”, then “closed”, “open”, or “open until <formatted date>”, joined by “ · ”. Segments: “All”, “Matched”, “Unmatched”. Section “Sign-ups” counts filtered loaded rows. Row: pseud, “MATCHED” / “UNMATCHED” when known, “N request(s) · M offer(s)”, distinct request fandoms including “Any Fandom”, one summary line except accessibility text. Detail header: pseud and the same request/offer count; “Request N” then “Offer N”, nonempty “Fandoms”, “Relationships”, “Characters”, “Additional tags”, “Optional tags”; an any flag adds “Any” to its type, tags comma-separated, prompt prose in serif. No edit/delete actions on participant detail.

Exact list messages: “Loading sign-ups…”; “Couldn't load sign-ups”; “Try Again”; retained-page failure “Couldn't load sign-ups: <reason>”; matching failure “Kudos can't tell which sign-ups are matched. AO3 shows assignments to maintainers after sign-ups close. <reason>”; empty assignments “No assignments have been sent yet, so no sign-up is matched or unmatched.”; “No sign-ups yet” / “Sign-ups will appear here as people join the challenge.”; “No matched sign-ups” / “No unmatched sign-ups”; `No sign-ups in this page match the "<filter>" filter.`; unknown filtered empty “Match state unavailable” / “No sign-up can be shown as matched or unmatched without assignments.”; footnote “AO3 shows 20 sign-ups per page, so these filters apply only to the pages you have loaded. Each tag summary shows one line from that person's sign-up requests.”; pagination “Load page N of M”. Swift has no separate signed-out list card: authenticated-request construction fails and feeds the failure card. Swift's `AO3AuthenticatedRequestError.notAuthenticated` says “Log in to AO3 before using this feature.” Android shows that same sentence before any read.

Withdraw section “Withdraw”; row “Withdraw sign-up” with xmark-circle and spinner while withdrawing; confirmation “Withdraw this sign-up?”; “Withdrawing removes your requests and offers from <title>.”; destructive “Withdraw Sign-up”; “Cancel”. Success sets “Sign-up withdrawn.” and dismisses. Refusal updates general errors while retaining the form. Exact errors: “Log in to AO3 first.”; token preparation via shared `AO3WriteError` uses “Couldn't prepare the request. Try again, or open the work on AO3.”; fallback “AO3 couldn't withdraw that sign-up.”; unconfirmed alone “AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.”

## Write contract, quoted from Swift

```swift
body: Self.formEncoded([("_method", "delete"), ("authenticity_token", token)]),
csrf: token, referer: referer, ajax: false
```

Headers: explicit authenticated Cookie and shared identifiable User-Agent; Content-Type `application/x-www-form-urlencoded; charset=UTF-8`; `X-CSRF-Token: <fresh token>`; Referer confirm-delete URL. No AJAX `X-Requested-With` or special Accept. Session stamp is internal and stripped before transport. Error selector: `#error li, .errorlist li, .error p, .flash.error, .flash.comment_error, .flash.caution`; notice selector `.flash.comment_notice, .flash.notice`. Verdict order from `collectionWriteVerdict`:

```swift
if let error = AO3Client.writeErrorMessage(in: body) { return .rejected(error) }
if AO3Client.writeSuccessMessage(in: body) != nil { return nil }
if (300...399).contains(status) { return nil }
guard (200...299).contains(status) else { return .rejected(fallback) }
return .unconfirmed
```

## Networking and sparing decisions

Policy: explicit collection navigation allows foreground authenticated list/form reads; the brief explicitly permits only the first page of each assignment list (no multi-page crawl). User-initiated Load more permits one sign-ups page; total permits only its last page, as iOS. Writes use the existing authenticated client, pacing, contact UA, redirect/cookie fencing and single-shot POST. No live AO3 traffic is used in this work.

Android must skip the moderator's refused owner-edit read. Known-open owner schedule must skip refused assignment reads. If closed state is not known (including moderator entry), the sparing choice is no assignment probes and unknown matching, rather than testing AO3's permission with a refused read. See Open questions. This is a deliberate request reduction required by the brief's standing rule; Swift's unconditional probes cannot satisfy that rule. A failed optional read counts as attempted and does not erase the rest of the screen.

## Decided without asking

- Reuse the existing client, repository, verdict, form parts and token palette; no schema/backup/shared UI changes.
- Add list parser/state/screen beside their challenge neighbours; participant detail stays inside the list route and uses only ProvidePushedShellChrome (including its own Back callback), with no second scaffold or shared-shell edits.
- Original Winter demo filler shares one answer per address, including Settings' existing sign-ups count. Mutable withdrawal is process-local and resets on relaunch.
- Tests use memory clients or a demo interceptor followed by a throwing socket guard; no helper scripts or stubs.

## Open questions

- Owner question 16: iOS walks every assignment page; Android reads page one only when known closed. Later-page sign-ups may therefore be unmatched with respect to this limited join. Whether to permit a broader read remains for the owner.
- A moderator cannot read the switch that closes sign-ups. Until an authoritative already-read closed signal is available, no assignment probes are made for that viewer; the list/detail still work and matching is unknown. This avoids reads AO3 refuses while sign-ups are open.

## Left out

After-close `withdrawSignUpAfterClose` calls `reportAssignmentDefault`: fresh first assignments-page token, POST `/:assignmentID/default` with `_method=patch` and authenticity token, fallback “AO3 couldn't record the default.” This brief implements neither. Assignment management, pinch-hit/default actions and navigation remain browser destinations. Prompt tags editor is unchanged; participant detail is read-only.

## Work log and verification

Implemented the inline sign-ups parser/join, generation-scoped pager, lazy list and participant read, native entry callbacks and route/chrome registration (`Routes.titleFor` is the real Kotlin name corresponding to the brief's `Routes.title`). Added the existing-form Withdraw section, native confirmation, single-shot repository method, success dismissal/notice, refusal/unconfirmed presentation and busy cleanup in `finally`. All new screen Text calls have explicit line heights. Subject tokens drive panels, chips, progress tracks, text and the destructive color; no shared UI/Settings component was edited.

### Local demo routes, taps and row evidence

Use the existing fixture demo with `kudosDemoLibrary=true`, `kudosDemoSignedIn=true`, and an optional `kudosDebugRoute` below. All demo requests terminate locally.

- `nav:ao3-challenge-sign-ups/winter_exchange?title=Winter%20Exchange%202026&owner=true&maintainer=true`: owner list, “6 sign-ups · closed”. Page one: **demo (4)** is MATCHED by Complete's recipient byline (that assignment deliberately omits a sign-up ID); **Harbor (demo) (5)** is UNMATCHED because Defaults' `undefault_82` makes it defaulted despite its old giver; **mapfold (6)** is MATCHED by Open's sign-up ID with a pinch-hit giver; **The Keeper of Every Lamp Along the Snowbound Harbor (7)** is UNMATCHED because it has no joined assignment. Load page 2 of 2 adds **emberpost (8)** MATCHED by Open's ID and **ashletter (9)** UNMATCHED without an assignment. Three matched and three unmatched across both pages. These are the exact selector/control/byline cases tested, not decorative badges in HTML.
- Change `owner=false&maintainer=true` for a moderator: all these rows have UNKNOWN matching (no chips), with the matching-unavailable note; Matched/Unmatched show the exact unavailable card. Change both flags to false for the locally refused non-maintainer state. Omit the signed-in demo extra for the signed-out state.
- Tap any participant row for its inline read: one request and one offer, chosen fandoms/relationship/additional tags, “Any” Character, separate Optional tags and original prompt prose. No read and no editing controls. Back restores the list's own shell row.
- From the owner list, tap **Your sign-up**, then **Withdraw sign-up** → Cancel: no token read, no write. Confirm **Withdraw Sign-up** on **demo / ID 4** for success, dismissal and “Sign-up withdrawn.” Refresh the retained list: row 4 is gone, total is five, and Your sign-up now resolves to **Harbor (demo) / ID 5** by its `(demo)` suffix. Confirming its withdrawal gives “Sign-ups are closed. You cannot delete your sign-up.” and retains that form and every typed field. Relaunch resets both rows and the six-row total.
- Direct cases: `nav:ao3-challenge-sign-up/winter_exchange?title=Winter%20Exchange%202026&id=4` (success) and the same route with `id=5` (refusal). ID 5's edit is a real populated fixture, not a stub. The confirm-delete fixtures contain fresh meta tokens different from their stale hidden inputs, plus an extra commit control which the native write deliberately does not send.
- Both production entrances: Account → Collections → Winter Exchange 2026 → Manage → **Sign-ups**; and Manage → **Challenge Settings** → **Sign-ups**. Both ask for the native list. Assignments, Defaults and pinch hits, Run matching and the other existing AO3 escape hatches keep their previous destinations.

The synthetic list schedule is closed so the assignment joins can be demonstrated. The local ID-4 confirmation deliberately simulates AO3's successful verdict independently of that schedule; ID 5 simulates the closed-signups refusal. This fixture success is not a claim that live AO3 permits deletion after close. The real write always lets AO3 decide, exactly like the Swift form (which shows Withdraw on any persisted ID). After-close defaulting is not implemented.

### Tests written — not run

25 new test methods in five suites:

- `AO3ChallengeSignUpsTest`: both page fixtures and all three assignment fixtures; chosen/any/optional tags and prose; malformed/recognized-empty parsing; ID/byline/default/pinch joins and own-ID lookup; exact owner/moderator/non-maintainer/signed-out request counts; known-open admission; optional failures retained and remembered; Load more counts; refresh/page failure retention; filters; duplicate/in-flight loads; generation change and departure. Memory-only client with the existing injectable parser dispatcher.
- `AO3ChallengeWithdrawTest`: iOS field order/body, token/referer/AJAX omissions; confirmed notice/redirect, error-before-notice/refusal, unconfirmed 2xx, fallback, failed/meta-less token, signed out, stale/pre-POST and post-POST generations; busy cleanup; duplicate taps, edits/save/refresh blocked while busy, departure; unfinished draft/target/control preservation on refresh; real OkHttp encoding/contact UA/cookie/header construction and one POST even on 429/503, with an interceptor that answers before a socket.
- `AO3ChallengeSignUpsScreenTest`: actual lazy rows/filters/page two; participant read and shell Back with zero extra reads; unknown matching on optional failure; signed out; loading/moderator; long pseud and action height/last-line checks across Light, Dark, Sepia and Oled at enlarged text; actual Manage entrance and route encoding/title/header/tab-bar registry checks.
- `AO3ChallengeWithdrawScreenTest`: actual native Cancel/confirm controls, exact message and success callback; AO3's refusal once with typed prompt retained; Sepia accessibility height/last-line check; Oled unconfirmed alone and no dismissal. Both Compose suites use tall windows, patient waits, NATIVE graphics and idle synchronization before waiting on request/callback counts; neither closes a database/client in After.
- `DemoChallengeSignUpsTest`: shared native/browser fixture addresses, Settings' six-row count, exact fixture join outcomes, ID-5 parsed form, success/removal/refusal/state retention/relaunch reset, missing assets/pages and wrong/extra write fields with a downstream throwing socket guard.

Updated existing `AO3ChallengeSettingsScreenTest` to expect its native Sign-ups destination; `AO3ChallengeSignUpScreenTest` to expect Withdraw only on the existing form (and no confirm-page read on opening); `DemoChallengeSettingsTest` for the shared six-row count.

### Checks performed and remaining handoff

Actually performed: read real Swift/Kotlin symbols and callers, including the shared token/flash parser, authenticated dispatch/session fence, theme/form row parts and `ProvidePushedShellChrome`; checked fixture HTML IDs (4/5/6/7 and 8/9), inline prompt containers, assignment ID/byline/default join evidence, closed switch and distinct fresh/stale tokens with Python's standard-library HTML parser; checked referenced fixture files exist, no new main-source type collisions, changed-file scope and `git diff --check`. These are static checks, not a Kotlin parser/test execution.

Claude must build Android debug and run the five new suites, the three amended suites, existing sign-up Save/session-dispatch, collection/navigation and demo block suites, then the full Android gate. The assertions about parser outputs, request counts, state verdicts, encoding, coroutine/session timing, route behavior, drawing and interaction **all need a test run**. The header/action/dialog/progress/list/detail spacing, all four themes, long labels and large fonts need emulator screenshots and human review; no visual correctness is claimed. Live AO3 compatibility remains unverified and is not part of this offline handoff.

No Gradle, Xcode, compiler, emulator, test suite, sign-in or live AO3 request was run. Branch remains `android/agent-codex-3cb`. No commits, pushes, branch switches, TASKS.md edits, schema/backup changes, iOS edits, helper scripts, stubs or `.orig` files. Work remains uncommitted here for Claude's build, tests and commit.

---

## Landing note (Claude, 2026-10-09)

Landed on `android/redesign-parity`; the patch applied cleanly. Gate: 2,418 tests.

Changed on landing:

- **The demo's own sign-up was listed under a name that is not the demo account's** ("demo"
  and "Harbor (demo)"; the demo signs in as AO3_Reader), so "Your sign-up" could never find
  it, in the demo or in the test that checks it. The three demo pages and the tests name
  AO3_Reader now.
- A test's token held a character no header can carry (OkHttp refuses it, and AO3's token is
  base64); one test called `KudosTheme {}` without a mode.

Read and left as written: the withdraw is one fresh read of the confirmation page and one
POST, the session checked only before it, the token and `_method` in the body, the busy flag
cleared on every path. A moderator's list makes two reads and shows no match state, because
the read that would say sign-ups are closed is the owner's (iOS tries it and swallows the
refusal); an owner's list reads the first page of each assignment list only (owner question
16).

## Seen on the emulator (Claude, 2026-10-09, afternoon)

Account → Collections → Winter Exchange 2026 → Manage → Sign-ups: "6 sign-ups · closed", four
rows with MATCHED and UNMATCHED chips, the Unmatched filter (2 rows), a participant's read
(Request 1, Offer 1, Back), "Load page 2 of 2" (6 rows), Your sign-up → Withdraw sign-up →
"Withdraw this sign-up?" → Cancel sends nothing; Withdraw Sign-up closes the form and the
list reads "5 sign-ups"; Your sign-up then opens the second one, whose withdrawal AO3's demo
answer refuses: "Sign-ups are closed. You cannot delete your sign-up." at the top of the
form, which scrolls to it. Not seen: a moderator's list, Sepia and large text. A debug route
with neither owner nor moderator shows the refusal as "AO3 refused the request (HTTP 403)",
though no request is made: no production path reaches it.
