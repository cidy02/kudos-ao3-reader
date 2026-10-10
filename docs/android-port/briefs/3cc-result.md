# Brief 3cc — challenge assignments and owner writes

## iOS first: opening reads, counted before implementation

Source is the actual, unchanged `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` Swift, not the audit. `ChallengeAssignmentsView.swift:465–535` loads sequentially: Complete (`assignments?fulfilled=true`), Open (`assignments?unfulfilled=true`), Defaults (`assignments`, no query), Pinch Hits (`assignments?pinch_hit=true`), then best-effort settings (`gift_exchange/edit`, falling back to `prompt_meme/edit` only on 404/non-gift markup). Each list walks all its pages (`AO3Client+Challenges.swift:57–86`). Complete/Open share one failure group; failure there stops Open if Complete fails but Defaults and Pinch Hits still read. With four single-page lists and a gift form, **five GETs, zero POSTs**. For any logged-in viewer admitted by navigation, including a moderator, Swift attempts all five; the owner-only settings request can be refused. Signed out: **zero reads**, “Sign in to AO3 to view assignments.”. Swift's task runs per session generation; refresh and confirmed writes reload the whole sequence. It has no idle/attempt guard and no actual Load more button despite the one-page footnote. Android's binding first-page/attempt/refused-read rules supersede this crawl.

The audit's Defaults query, plural pinch_hits query, and claim referer are wrong: **iOS code wins** (`AO3ChallengeModels.swift:755–768`, `AO3ChallengeActions.swift:156–173`). Sent dates are modeled but the real parser never supplies `sentAt`; do not invent “Assigned” dates from fixtures.

## Android read budget and admission decision

Known-closed owner: four first-list pages, then one best-effort settings probe (five GETs; optional meme fallback adds one). Unknown owner from Manage: settings first to establish closure, then the four first pages only if a gift exchange is closed (five GETs on success). This reordering uses the same allowed read to avoid probing lists AO3 refuses. Open/unknown after settings failure: no assignment reads. Known-closed moderator: four list GETs, no owner settings. Unknown moderator from Manage: zero GETs, explain unavailable closure rather than probe permissions. Neither maintainer nor owner, or signed out: zero GETs. Further pages only on explicit Load more, one GET for one list. Duplicate opening never repeats even failed optional reads. Refresh/confirmed writes repeat bounded lists; a failed due read remains attempted for this screen and is not retried by refresh; a successful due read is refreshed after the four list reads, as iOS. This is the sparing resolution of the conflict with Swift's unconditional moderator/unknown-state probes.

## iOS access, entrances, layout and exact copy

`AO3CollectionDetailView.swift:362–370`: Manage → “Assignments” appears only when the dashboard exposes assignmentsURL **and** `show.isMaintainer` (owner or moderator). It passes the owner bit. The screen is Gift Exchange only: Prompt Meme has no matching. `ChallengeSettingsView.swift:115–181, 400–434, 585–592`: owners reach Settings from Manage, its gift-exchange “Assignments” and “Defaults and pinch hits” disclosures push this same screen (initially Unmatched, not Pinch hits). Settings' iOS tally values are “N matched, M unmatched” / “None sent yet” / “Couldn't load”, and defaults-plus-covered count / “Couldn't load”. Android preserves 3ba's deliberate absence of both tally values and makes only the destination native. Sign-ups-open permission is enforced by AO3, not a visibility condition in Swift; Android checks closure before reading.

`ChallengeAssignmentsView.swift:155–450`: kicker collection title (slug fallback), title “Assignments”; subtitle successful loaded “N matched”, successful “M unmatched”, optional “works due DATE”, joined by “ · ”. Segments, in order: “Matched”, “Unmatched” (initial), “Pinch hits”. Matched section “Matched” with row count: recipient → giver, recipient fallback “An anonymous sign-up”, giver pinch hitter first, original giver second, “Unclaimed” last. Secondary “Assigned DATE · due DATE”, dropping absent halves. `sentAt` is never supplied by the actual parser, so currently only “due DATE” can appear. Badge precedence (`AO3ChallengeModels.swift:390–419`): fulfilled “DELIVERED” (green); otherwise defaulted “DEFAULTED” (orange); otherwise past a resolved works-due instant “LATE” (secondary); otherwise no badge. Works due means `assignments_due_at`, not either reveal date (`worksDueAt` alias at line 271). Date display is abbreviated challenge wall-clock digits, not converted to the device zone; instant uses the served timezone, and an unrecognized Rails name suppresses Late (`AO3ChallengeInstant:113–173`).

Unmatched section “Unmatched sign-ups” counts Defaults. Consecutive recipients are grouped in twos for layout only. Titles “Two sign-ups lost their giver” / “One sign-up lost its giver”. Prose, verbatim templates: “The givers for NAME and NAME defaulted, and no pinch hitter has covered them yet. Only AO3 can match participants, so cover this with a pinch hit or assign someone on AO3.” / “The giver for NAME defaulted, and no pinch hitter has covered it yet. Only AO3 can match participants, so cover this with a pinch hit or assign someone on AO3.” Each “Open on AO3” goes to the Pinch Hits filtered page in the browser; it is not a write.

Pinch hits section “Pinch hits” counts Defaults + the separately fetched Pinch Hits, open first in AO3 order (`AO3ChallengeScreenModels.swift:75–100`). Labels “Pinch hit #N”; “OPEN” accent chip or “CLAIMED” secondary chip. Open detail “Requested by NAME”, **no due suffix**. Claimed “Claimed by HITTER for NAME · due DATE”, dropping unknown due; empty recipient is lowercase “an anonymous sign-up”. No fandom or posted date is invented. An open row shows “Claim” only for logged-in **owners**, not moderators. All Claim buttons disable when an item is in flight.

Footnote, verbatim: “You can view assignments and pinch hits here one page at a time. You can report a default or claim a pinch hit here, but asking for a pinch hitter and running the match open on AO3.” Swift actually walks all pages; Android's explicit one-list “Load more (Complete)” / “Load more (Open)” / “Load more (Defaults)” / “Load more (PinchHits)” resolves that discrepancy with the mandated first-page budget. These parenthetical list identifiers distinguish the two independent pagers inside Matched and Pinch hits; they are Android copy, not a Swift control.

`ChallengeAssignmentsView.swift:682–780`: bottom bar only when signed in, loaded, and owner. “Report a default” disabled when no sent, undelivered, non-defaulted candidate exists or any write is busy. “Claim a pinch hit” disabled when Defaults is empty or any write is busy. Picker titles “Report a default” / “Claim a pinch hit”; candidates original/pinch giver → recipient with the same fallbacks; “Cancel”. Native confirmation titles “Report this default?” / “Claim this pinch hit?”. Default message “This marks GIVER's assignment for RECIPIENT as defaulted on AO3 and adds it to the pinch hits waiting for cover.” Claim message “You'll be the pinch hitter for RECIPIENT's gift, due DATE.”, or “You'll be the pinch hitter for RECIPIENT's gift.” when unknown. Confirm “Report default” (destructive) / “Claim”; dismiss “Cancel”. No byline field: Claim sends the signed-in viewer's own username.

`ChallengeAssignmentsView.swift:539–609`: loading “Loading assignments…”. Whole failure “Couldn't load assignments”, reason, “Try Again”. Per-list failures “Couldn't load matched assignments” / “Couldn't load defaults” / “Couldn't load pinch hits”, reason, “Try Again”; Pinch hits fails if its own or Defaults read fails. Empty “No matched assignments yet.” / “No defaulted assignments are waiting for a pinch hitter.” / “No pinch hits open right now.”. Action error card has warning, red text, x dismiss. Swift prefixes thrown reasons with “Couldn't record the default: ” / “Couldn't claim that pinch hit: ” (`perform:650–678`). Android follows the owner's later binding rule: **repository verdict alone**, especially UNCONFIRMED. Swift's CancellationError return can leave busy set; Android always clears busy in finally while active. Reload in Swift clears pickers/targets; Android preserves them on refresh as A22 requires.

## Two writes: exact Swift contract

`AO3ChallengeActions.swift:120–173`: Claim trims byline and rejects blank with “Name a pinch hitter.”; field `cover_ID=USERNAME`. Default field `default_ID=1`. Both use one fresh authenticated **first Defaults page** for Claim (bare `/collections/SLUG/assignments`), or **first Open page** for Default (`?unfulfilled=true`), then one POST to `/collections/SLUG/assignments/update_multiple`. Page one has no page query. `fetchCSRFPage` (`AO3WriteActions.swift:404–413`) reads **meta[name=csrf-token]**, ignoring a stale hidden input, and throws shared `AO3WriteError.noCSRFToken` (“Couldn't prepare the request. Try again, or open the work on AO3.”), despite the unused challenge-specific no-token error mentioning a challenge.

```swift
let list: AO3ChallengeAssignmentList = field.0.hasPrefix("cover_") ? .defaults : .unfulfilled
let referer = AO3ChallengeURL.assignments(slug: slug, list: list, page: 1)
let (_, token) = try await fetchCSRFPage(at: referer, using: client)
if let expectedGeneration { try requireSessionGeneration(expectedGeneration) }
let params: [(String, String)] = [("_method", "put"), ("authenticity_token", token), field]
let request = try writeRequest(
    to: AO3ChallengeURL.assignmentUpdateMultiple(slug: slug),
    body: Self.formEncoded(params), csrf: token, referer: referer, ajax: false
)
let (status, body) = try await submitWrite(request, using: client)
try throwIfChallengeWriteFailed(status: status, body: body, fallback: fallback)
```

`writeRequest` (`AO3WriteActions.swift:446–459`): explicit Cookie and shared contact User-Agent; Content-Type `application/x-www-form-urlencoded; charset=UTF-8`; X-CSRF-Token fresh meta token; Referer exact first-list URL above. **No** X-Requested-With, special Accept, commit, other assignments, approval/undefault fields, or any served hidden fields. Token and `_method=put` are always in the body. Signed out “Log in to AO3 first.”. The internal session stamp is stripped before sending. Auth/session checks run before token read and after it, and the existing shared client fences immediately before dispatch. Once sent, Android does only `movedOnAfterWrite(expectedGeneration, response)?.let { return it }` and verdict parsing, no throwing session check.

`AO3CollectionActions.swift:483–494`, invoked by `throwIfChallengeWriteFailed` (`AO3ChallengeActions.swift:319–329`):

```swift
if let error = AO3Client.writeErrorMessage(in: body) { return .rejected(error) }
if AO3Client.writeSuccessMessage(in: body) != nil { return nil }
if (300...399).contains(status) { return nil }
guard (200...299).contains(status) else {
    return .rejected(fallback)
}
return .unconfirmed
```

Error selectors `#error li, .errorlist li, .error p, .flash.error, .flash.comment_error, .flash.caution`; notice `.flash.comment_notice, .flash.notice`. Errors win over notices/redirects. Fallback “AO3 couldn't claim that pinch hit.” / “AO3 couldn't record the default.”. Unconfirmed 2xx alone: “AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.”. No optimistic list changes; refusal preserves rows and displays AO3's exact reason. Confirmation reloads Complete, Open, Defaults, Pinch Hits first pages, then successful prior due read for owners (five GETs); moderators have no writes. If due read already failed, the reload is four GETs. Session movement after sending produces unconfirmed alone and no reload; before POST stops dispatch. HTTP permission/session refusal stops further controls, including retrying a refused token page.

## Networking policy mapping

`docs/AO3_NETWORKING_POLICY.md`: each list, settings and fresh token GET is foreground authenticated navigation of an explicitly opened challenge owned/moderated by this viewer, not background/bulk scraping. Moderators skip the owner-only settings endpoint; lists require known closed gift-exchange admission. Explicit Load more is one page, not an automatic walk (owner question 16 / this brief). Every read uses the existing repository/client's auth headers, generation fencing, shared coordinator/pacing, identifiable UA, allow-list and GET retry policy; no raw transport or new loop. Each confirmed action permits one fresh token GET and one single-shot `AO3WriteRepository` POST, through the existing authenticated client/pacing/dispatch fence, never retried/coalesced. No request is made by dialog opening/Cancel, recomposition, or mere segment selection; refresh sends zero writes. No AO3 service was contacted in this work.

## Decided without asking

Reuse and extend `AO3ChallengeSignUpsParser.parseAssignments` and `AO3SignUpAssignment`, alongside their neighbours; no second parser, Room/schema/backup changes or shared component changes. Carry already-known closed state from Settings through the new route. Manage has no authoritative closed field: owners resolve it with the existing settings read, moderators are refused locally until closure is known. Original Winter demo rows/pages are shared with Sign-ups, with process-local mutable assignment state reset on relaunch.

## Open questions

Owner question 16 remains unanswered: opening reads first pages only. Moderator Manage admission lacks a closed signal; choose no read. Swift walks all pages despite its footnote; Android adds explicit per-list Load more. A failed due-date attempt remains remembered even on refresh, as the standing owner rule requires; successful due reads repeat only on explicit refresh or confirmed-write reload.

## Work log

Reference read complete; implementation and offline test evidence follow below. No builds/tests/live requests claimed.

## Implementation and demo walkthrough

Implemented `account/AO3ChallengeAssignmentsState.kt` and `AO3ChallengeAssignmentsScreen.kt`, sharing the existing authenticated collection repository and `AO3WriteRepository`. Rows are drawn from the collected `state`; no flow-value reader is called by composition. The new route is in `Routes.titleFor` (the actual Kotlin name), `hasSubjectHeader`, `tabBarHiddenBases`, and `AppNavHost`. All three entrance callbacks are wired. Shell refresh is a Material icon button handed over **as null** until loaded/applicable. Header reserves statusBars + 76dp. Long lists and candidate lists are lazy; row panels use `writingSuggestionPanel`, failure/loading follow the challenge form's token parts, chips use SubjectChip, every new Text has explicit line height, large fonts wrap rows and stack bottom actions. Claim's bottom action uses the scope accent and labelOnAccent; delivered/defaulted chips derive green/orange SubjectPalettes rather than fixed/default Material colours. No shared UI or settings component was edited.

Winter uses the existing closed settings page (works due March 1, 2026, timezone UTC) and the existing three shared assignment fixtures, extended in place. New Pinch Hits and page-two fixtures live beside them. The matcher rule remains the original three-list join, not all four enum entries; both Sign-ups state and its tests explicitly keep Complete/Open/Defaults so the new fourth list neither adds a request nor overrides a join. The demo's mutable `DemoChallengeAssignments` handler answers those same addresses for both native readers. Read-only browser fixtures use the same source assets/URLs for their initial answers, as the existing demo convention does; they do not render mutable native state after writes.

Use fixture demo extras `kudosDemoLibrary=true`, `kudosDemoSignedIn=true`, optionally `kudosDebugRoute`. Demo account is **AO3_Reader**; no real login is needed/permitted for verification.

- `nav:ao3-challenge-assignments/winter_exchange?title=Winter%20Exchange%202026&owner=true&maintainer=true&closed=true`: owner. Opening is five GETs, no automatic page two, no POST. Header initially loaded “5 matched · 3 unmatched · works due DATE”; Unmatched initially shows one two-name card (Harbor (AO3_Reader), Lantern Watch) and one singular card (The Keeper of Every Letter Along the Snowbound Harbor). Both browser buttons point to `assignments?pinch_hit=true`.
- Matched: **81 cloudscribe → AO3_Reader** is DELIVERED, Complete's assignment-link ID/byline (no sign-up ID). **83 Replacement → mapfold** is a claimed pinch hitter on Open. **84 riverpost → emberpost** is open and LATE with this past UTC deadline. **86 cinderquill → Winter Letter Keeper** is also LATE, the default-refusal case. **87 frostink → Snowbound Atlas** is DEFAULTED because of its `undefault_87` control even though it is served on Open; badge precedence is proved by the parser/control, not decorative HTML. With no due form/unknown zone the undelivered non-defaulted rows have **no badge**, covered by state/parser tests and moderator demo. No row fabricates an Assigned date.
- Pinch hits: **#1 / 82**, open, Harbor (AO3_Reader); **#2 / 85**, open, Lantern Watch; **#3 / 88**, open, the long recipient; **#4 / 83**, CLAIMED by Replacement for mapfold, with due suffix. Open details omit due. Header/numbering is computed from Defaults first then Pinch Hits, not inserted fixture labels.
- Claim success: tap **#1 Claim**, or bottom **Claim a pinch hit** → **FormerGiver → Harbor (AO3_Reader)** → **Claim** in “Claim this pinch hit?”. Sends `cover_82=AO3_Reader`, fresh Defaults meta token. Notice “Assignments updated.” confirms; reread moves 82 out of Defaults and into Open and Pinch Hits with AO3_Reader. No optimistic patch. Claim refusal: choose **northpost → Lantern Watch** / **#2 Claim**, confirm; “This pinch hit is no longer available.”; lists unchanged. Long-row 88 can also be claimed successfully.
- Default success: bottom **Report a default** → **riverpost → emberpost** → **Report default** in “Report this default?”. Sends `default_84=1`, fresh Open meta token. Notice confirms; reread moves 84 from Open to Defaults as uncovered. That new default can then be claimed. Refusal: **cinderquill → Winter Letter Keeper**; “This assignment cannot be defaulted.”; rows unchanged. Default picker excludes delivered 81 and defaulted 87, includes covered-but-undelivered 83 as Swift does; demo 83 refuses generically rather than pretending every row is writable.
- Each visible **Load more (LIST)** reads only page two of that list. Complete adds **91 aurorapost → Midwinter Star** (DELIVERED); Open adds **92 winterink → River Almanac**; Defaults adds **93 lostquill → Ember Atlas** (another open pinch hit); Pinch Hits adds **94 AO3_Reader → Snow Lantern** (CLAIMED by the actual viewer). After Defaults page two, the number of later claimed rows changes because opens always come first. Later-page rows are valid populated original filler; their writes are locally refused unless in the explicitly modeled success set, so no POST can escape to AO3.
- Known-closed moderator: change `owner=false&maintainer=true&closed=true`; exactly four GETs; no works-due read/date/Late badges; three segments but no Claim buttons or bottom owner bar. Neither: both role flags false, zero reads. Unknown moderator: omit closed or use `closed=unknown`, zero reads and closure-unavailable sentence. Signed out: omit the signed-in demo extra, zero reads and exact Swift sign-in sentence.
- Production taps for **every row/action above**, avoiding the shell's `&` truncation: Account → Collections → Winter Exchange 2026 → Manage → **Assignments** (owner settings admission read first), or Manage → **Challenge Settings** → **Assignments**, or **Defaults and pinch hits** (passes the already-read closed switch). Then use the segments/pickers/Claim described above. The two Settings rows keep absent tally values under 3ba/question 16. Manage's moderator entry opens the native unavailable-closure state; that limitation is intentional and recorded under Open questions.
- Device-shell warning from the brief: an unquoted/poorly relayed `nav:` route with `&` may lose owner/maintainer/closed. Prefer production taps for owner actions. The full routes above describe the arguments; they are not claims that a device shell will preserve them.

Relaunch creates a new interceptor/handler and resets assignment mutations. Demo token meta values differ from stale hidden values. POST bodies are validated for exact field list, token/header/referer, absence of AJAX headers/extra commit fields and AO3_Reader byline. Refusal cases do not mutate state; repeated successful mutation IDs are refused. Missing assets and unknown pages return local 404; writes outside the fixture's modeled rows are local refusals.

## Left out, with iOS's behavior

- Participant own default: `reportAssignmentDefault` (`AO3ChallengeActions.swift:100–113`) fetches Complete first page (`?fulfilled=true`, no page=1), POSTs `assignments/ID/default` with `_method=patch` and authenticity_token, fallback “AO3 couldn't record the default.”. `withdrawSignUpAfterClose:94–96` delegates to it. Neither is added here; existing open-sign-up Withdraw remains untouched.
- **Run matching**: iOS Settings (`ChallengeSettingsView.swift:452–456`) uses its external/browser escape to `/collections/SLUG/potential_matches`; Android's existing escape remains. No matching/generate write added.
- **Send assignments**: no native control or write in the actual iOS Assignments screen. Settings Edit only displays AO3's “Assignments sent” timestamp; its comment says AO3 stamps it when an owner sends by hand. No endpoint invented on Android.
- Requesting volunteers/assigning someone from an unmatched card: iOS “Open on AO3” goes to the Pinch Hits list. It remains the browser escape on Android. No native “request a pinch hit” invented. Other existing AO3 escape hatches remain as served by their reference screens.

## Tests written, not run

**26 new test methods** across `AO3ChallengeAssignmentsTest`, `AO3ChallengeAssignmentWritesTest`, `AO3ChallengeAssignmentsScreenTest`, `DemoChallengeAssignmentsTest`. They cover all eight fixtures, malformed/recognized empty pages, assignment IDs/recipient/giver/pinch/default/fulfilled evidence, badge precedence and served timezone; owner/moderator/neither/signed-out/unknown/open read counts; duplicate/in-flight/retired reads; independent failures and remembered optional attempt; explicit one-page pagination; preserved confirmation target on refresh; nothing posted on reads/refresh/Cancel; both writes' fields, token URL, header/body encoding, exact reason/unconfirmed/fallback/notice/redirect verdicts; failed/missing token and blank byline; signed out, stale/pre-POST and post-POST session movement/session-expiry verdict; busy cleared and other controls blocked; one POST even on 429/503; confirmed reload and no refusal reload; real shell-registry/Manage callback; actual segments, candidate pickers/confirmations, busy controls, loading/signed-out/moderator/failure states; enlarged text across Light/Dark/Sepia/Oled with last-line/height assertions, tall native-graphics Compose window and patient idle-synchronized waits. No client/database is closed in After. Socket guards stop every wire/demo test before transport.

Amended `AO3ChallengeSettingsScreenTest` asserts both native entrance callbacks while preserving the external Run matching destination and no extra reads on row taps. Amended `AO3ChallengeSignUpsTest` and `DemoChallengeSignUpsTest` keep the original three-list join/read budget after enum extension. All behavioral assertions, coroutine timing, parser outputs, request counts, UI text layout, navigation and demo mutations **need Claude's test run**. The source inspection is not a compile/test claim.

## Static verification and Claude handoff

Actually performed: read real reference Swift and Kotlin callers/symbols (shared meta/flash parser, dispatch/session fence, theme/form parts, route arguments and shell chrome); inspect all eight assignment assets with Python's standard-library HTML parser for fresh meta tokens, assignment/sign-up controls/IDs and page-two links; scan unique new declarations (state, screen, page DTO, demo handler); resolve explicit project import packages/symbol text in source; scan changed/new files for conflict markers and new files for trailing whitespace; `git diff --check`. The import scan is **textual**, not a Kotlin resolver. Counts from the source scan (including the final due-refresh regression): 8 parser/read/state tests, 6 write tests, 9 Compose screen tests, 3 demo tests. Thirty changed/new files including this report and two brief follow-up pointers. TASKS.md and shared `ui/subject/` / `settings/` have no diff.

Claude must build Android debug, run these four suites plus amended Challenge Settings/Sign-ups/demo Sign-ups suites, existing collection/navigation/Save/withdraw/auth-dispatch tests, then the full Android gate. Parser outputs, request counts, encoding/header behavior, coroutine/session timing, busy flags, demo mutations, route/entrance callbacks and UI assertions are **written claims needing that test run**. Emulator/human review still needs all three production entrances, all three segments, two pickers/confirmations/refusals/success reloads, explicit pagination, long labels and large text under Light/Dark/Sepia/Oled. No screen or screenshot was viewed; no visual correctness is claimed. Live AO3 compatibility remains unverified and is not an authorized step here.

Remaining sparing decisions: Manage's unknown-closure moderator entry cannot display lists without an authoritative closed signal; this is locally refused before a request. First-page counts are loaded-page counts, not global totals. A failed best-effort due read stays attempted; only a successful due read repeats on explicit refresh or confirmed write. iOS's actual code, not R3's mistaken query/referer descriptions, governs the two writes.

No Gradle, Xcode, compiler, test suite, emulator, sign-in or live AO3 request was run. Work stays uncommitted on `android/agent-codex-3cc` in this worktree for Claude's builds/tests/commit. No commit/push/branch switch/TASKS.md edit, iOS edit, schema/backup change, helper script, stub file or .orig file was made/left behind.

## Landing note (Claude, 2026-10-09)

Landed with four changes. Gate: 2,454 tests. **Not yet seen on the emulator** (the Mac was
out of memory that evening): the matrix row stays in progress until it is.

- **A moderator is no longer turned away.** Only the owner is served the settings form, so
  for a moderator arriving from Manage the screen could never learn that sign-ups were
  closed, and said "Kudos can't confirm that sign-ups are closed" for good. The lists are
  now asked for, as on iOS; AO3 decides.
- **AO3's first refusal stops the other lists.** They are served to the same people, so a
  403 or a sign-in page on one is the answer for all four: one refused read, where the patch
  made up to three (iOS makes four). A failure that is not a refusal (no connection, AO3
  busy) still leaves the other lists to be read. New test.
- **The owner's failed settings read can be tried again** when it was not a refusal. It was
  terminal: one lost connection and the screen said "can't confirm" until reopened.
- **"Load more (PinchHits)" became words** ("Load more pinch hits", and so on). These four
  labels exist only on Android: iOS walks every page at once, Android reads a list a page
  at a time on a tap (owner question 16).

Read against iOS with Gemini's index `audits/A31-result.md` (requests, both writes field for
field, the verdict rule): no difference found beyond the page walk and the participant's
reads (iOS asks and is refused four times; Android does not ask). Both writes go through
`movedOnAfterWrite` after the POST and clear their busy flag in `finally`.

Not reviewed line by line: the screen's layout code and the parser's new list. A Codex
review of the landed code is owed (after A32).

### Seen on the emulator (Claude, 2026-10-10)

As the owner, in Light, OLED and in Sepia at twice the text size (the two actions stack, the
text wraps, nothing is cut): nothing wrong found. Still not seen: the screen as a moderator,
and "Load more".
