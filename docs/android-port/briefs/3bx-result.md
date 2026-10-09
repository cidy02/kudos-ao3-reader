# Brief 3bx — work Post, Preview on AO3 and Delete

## iOS contract read before implementation

Read-only reference root: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`.
Read line by line: `Features/Writing/WorkEditView.swift:129–146,195–253,524–601,665–796`,
`Features/Writing/WritingPreviewView.swift:1–140`,
`Services/AO3WorkActions.swift:84–98,120–142,419–423,452–455,478–490,550–621`,
`Models/AO3WritingModels.swift:495–518,970–1012,1032–1077`,
`Services/AO3Client+Works.swift:541–687,879–912`.
The R2 audit is a location guide only. Also read 3bo/3bt/3bu including landing notes,
3bb's replay boundary, writing architecture §0/§8.7 and networking policy.

### Post

New and draft forms have **Post** with **Post work**, **Preview on AO3**, and (only
with an existing work ID) **Delete draft**. The latter has the footnote **AO3 deletes
an unposted draft 30 days after it is created.** Posted forms instead have **Delete** /
**Delete work on AO3**; no Post or Preview row. The toolbar remains **Save**.

Post work opens **Post this work?**. Complete fields: **Post work**, **Cancel**;
message **Posting notifies your subscribers and can't be undone. You can edit a
posted work, but you can't return it to a draft.** Missing fields: **Fill in what is
missing**, **Cancel**, no write. Names in order: Title, Rating, Archive Warning,
Fandoms, Language, Work Text. Title/rating/language trim Foundation whitespace;
warnings/fandoms check array emptiness; Work Text is checked only for new/draft,
with a chapter whose contentServed is true and whose trimmed content is empty.
Phrases: a title, a rating, an archive warning, a fandom, a language, the work text.
Message: **One thing is missing. Add {list}. AO3 requires it. Posting also {consequence}**;
**Two things are missing. Add {list}. AO3 requires both. Posting also {consequence}**;
**{N} things are missing. Add {list}. AO3 requires all of them. Posting also {consequence}**.
`ListFormatter.localizedString(byJoining:)` joins the phrases.

Swift: `static let postSubmit = AO3WorkSubmitAction.post`. Direct Post does NOT
preview or Save first, including a never-saved new work. It sends one POST to the
form action (`/works` new; `/works/{id}` existing), `post_button=1`. Repository also
rejects missing fields with **AO3 still needs {names joined with " and "}.**
`perform` checks busy twice, fences the opening session, disables the list/Save,
sets isPosting, and closes form plus preview only on confirmation. Failure clears
busy and retains form/recovery; alert **AO3 could not save the change**, reason, **OK**.
No subscriber count is guessed. No write, retry or preparation read on opening.

### Shared work body and headers, in order

All addresses here use the configured AO3 base URL. The existing client owns
contact User-Agent, explicit Cookie, pacing and session stamp; Content-Type is
**application/x-www-form-urlencoded; charset=UTF-8**, **X-CSRF-Token** = first body
authenticity_token, **Referer** = action. Non-AJAX: no X-Requested-With or special
Accept. Both platforms single-source the literal UA:
`Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 KudosReader/{version} (+https://github.com/cidy02/kudos-ao3-reader)`.
iOS version is CFBundleShortVersionString (fallback 1.0); Android is BuildConfig.VERSION_NAME.
Cookie comes from the current session's scoped cookie header, never a form value. Authenticated GETs use the existing Cookie/contact UA; no write headers.

`AO3WorkForm.parameters` supplies the same pairs for Post and Preview as Save,
changing only the selected submit. Values come from the current collected form,
including editor departure checkpoints (§8.7), never reserialized on submit:

| Order | Field | Value / empty branch |
|---|---|---|
| 1 | authenticity_token | Loaded form token; preview meta token after adoption |
| 2 | _method | Nonempty loaded override only; adopted new draft uses patch |
| 3 | work[title] | Exact current title, including empty |
| 4 | work[rating_string] | Current rating only when nonempty; otherwise served replay |
| 5–6 | work[archive_warning_strings][], work[category_strings][] | Ordered arrays; one empty pair for an empty array |
| 7–10 | work[fandom_string], work[relationship_string], work[character_string], work[freeform_string] | Trimmed nonempty names joined by comma-space; empty string for none |
| 11–14 | work[language_id], work[summary], work[notes], work[endnotes] | Exact strings, including empty |
| 15–16 | work[collection_names], work[recipients] | Selected collections/gifts joined comma-space; empty for none |
| 17 | work[series_attributes][id] / [title] | First selected ID, else trimmed new title; else both empty, ID then title |
| 18 | work[parent_work_relationships_attributes][0][url], [title], [author], [language_id], [translation] | URL/title branch sends first four exact strings including empty; translation=1 only when true; omitted names replay served values |
| 19–22 | work[wip_length], work[backdate], work[restricted], work[moderated_commenting_enabled] | Total exact, switches 1/0 |
| 23 | work[comment_permissions] | Only nonempty, else served replay |
| 24–25 | work[anonymous], work[collection_inbox] | Present optional booleans 1/0; nil omitted/replayed |
| 26 | work[work_skin_id] | Exact, including empty |
| 27 | work[chapter_attributes][title], [summary], [content] | When chapter present: title/summary exact; content only if contentServed |
| 28 | work[chapter_attributes][published_at(1i)], (2i), (3i) | When year nonempty: year/month/day exact, empty month/day allowed; otherwise served replay |
| 29 | work[author_attributes][ids][] | One per selected pseud, ordered; empty array adds none |
| 30 | work[author_attributes][byline] | Nonempty only, else served replay |
| 31 | conditional hidden fields | First captured conditional hidden value for names not already sent |
| 32 | post_button / preview_button / save_button / update_button | Selected submit = 1 only |
| 33 | replay boundary | Unoverridden successful served controls, in browser order, preserving duplicates/empty values; no invented unknown field |

Verdict, quoted Swift, in order: `if let error = AO3Client.workWriteError(in: body)`
throws rejected; `if let notice = AO3Client.workWriteNotice(in: body)` confirms;
`if (300 ... 399).contains(status)` returns **Saved.**;
`if (200 ... 299).contains(status)` throws unconfirmed; otherwise **AO3 didn't accept
the change.** Refusal selector **#main .flash.error, #main #error li**, first nonempty,
excluding ancestors **#workskin**, **.userstuff**, **#previewpane**; direct
**#main > #previewpane** suppresses refusal. Notice: nonempty **#main > .flash.notice**.
Unconfirmed: **AO3 replied but didn't confirm the change went through. Check on AO3
before trying again.** Signed out before dispatch: **Log in to AO3 first.** Session
change before dispatch: **Your AO3 session changed. Reopen this form before saving.**
The owner's continuation rule supersedes the old post-return cancellation behavior:
a moved session after POST returns is **UNCONFIRMED**, including an authentication
response that expires that session. The repository verdict is displayed unchanged.
Typed transport/HTTP words reuse 3bo's
`workFormFailure` (403/404/429/5xx/other HTTP/offline/timeout/TLS/transport/expired
session). No authored success word is evidence. No automatic retries, including 429.

### Preview on AO3

Form row starts isSaving and disables the form; no pushed screen until the answer.
One POST of all current work pairs with **preview_button=1**; same action/referer/token
as Save, zero preparation reads. `postPreview` tries workWriteError first, then
`guard (200 ... 399).contains(status)` else previewUnavailable. `parsePreviewHTML`
requires **#previewpane**; absent pane tries refusal again, then **AO3 didn't return
a preview. Try opening the work on AO3.** It finds the first form with
**[name=edit_button]**, derives work/chapter IDs from its action, takes CSRF only from
page meta and notice from workWriteNotice. It removes **form, .landmark, img** from
the pane; selects **h2.title, h3.title, .module > h3.heading, .userstuff** in order;
title is heading, heading is label, userstuff yields one rich paragraph per lazy row.
Images never load. A bare notice/2xx without a pane is insufficient.

`form = try form.adopting(page)` updates token when supplied; existing work keeps its
identity. New work MUST have preview.workID or throws unconfirmed with form unchanged.
It adopts action `/works/{id}`, _method patch, kind draft, isDraft true/isPosted false;
all typed fields retained. Later Save uses save_button at that ID, Post post_button
at that ID. No second creation. Recovery copies are not deleted or migrated.

Pushed header **AO3 Account**, **Preview**, current form subtitle; optional AO3 notice;
lazy blocks; **Post** panel with **Post work** (or **Update** if posted) and **Edit**.
Edit returns locally. Post work asks **Post this work?**, same message, **Post work** /
**Cancel** (Swift preview does not replace that button for missing fields; repository
validation refuses without sending). Posted Update has no alert. While posting the
row shows progress, list disabled; failure alert **AO3 could not post this**, reason,
**OK**, preview and exact form retained. Success closes both. No retry.

### Delete

Row starts isCheckingDelete (action rows disabled, no spinner in iOS). iOS
`loadDeleteImplications` requires sign-in, GET **/works/{id}/confirm_delete**, then
GET **/works/{id}** for missing stats. Confirm parser: first **form.destroy,
form[method=post]**, else first form; action resolved against AO3; token from meta,
else authenticity_token input (visible input preferred to hidden/submit, as Swift's
inputValue); _method input else delete. Heading **h2.heading, h2**;
caution **p.caution, p.notice, .caution.notice**, trimmed; draft when heading/caution
contains draft. Title between first/last ASCII quote, else heading. Counts from
**dl.stats dd.{chapters,kudos,comments,bookmarks,words}, dd.{name}**, digits only;
chapters before slash, falling back to all digits if that prefix is not numeric;
caution fallback `(\d[\d,]*)\s+{chapter,kudo,comment,bookmark,word}`.
Second page fills nil counts only. WorkEditView displays **imp.cautionText** verbatim,
not a synthesized count sentence.

Confirmation: draft **Delete this draft?**, **Delete**, **Cancel**; posted **Delete this
work?**, **Delete on AO3**, **Cancel**. Message = AO3's cautionText. Confirmation invokes
`deleteDraft` → `deleteWork` or `deleteWork` directly; Swift repeats loadDeleteImplications
(confirm GET, stats GET), then **one POST** to the freshly captured action. Body only
**authenticity_token=TOKEN**, **_method=served nonempty override or delete**; no commit,
work fields or submit. Same headers/referer as work writes. Same work verdict. Session
mismatch at Swift delete entry throws **Log in to AO3 first.** Android retains 3bo's
stronger opening-session fence before dispatch. After a returned POST, the owner's
continuation rule requires UNCONFIRMED instead of cancellation or “not deleted”.
No mutation on failure;
form alert **AO3 could not save the change**, reason, **OK**. Successful delete dismisses;
no recovery cleanup and no reader-library deletion. Evidence: WorkEditView success
only `dismiss()`; AO3WorkActions.deleteWork only `loadDeleteImplications` and
`submitDelete`; neither receives ModelContext/SavedWork/lifecycle/recovery services.
No local library call exists in this path.

Failure words shared with Save (all show an OK alert; no automatic action retry):

| Failure | Message |
|---|---|
| Expired authentication (source error mapping; after a sent POST that expires the generation, Android shows UNCONFIRMED alone) | Your AO3 session expired. Please log in again. |
| 403 | AO3 refused the request (HTTP 403). Wait a while before trying again. |
| 404 | That work or page couldn't be found (it may be restricted). |
| 429 | AO3 is rate-limiting requests. Wait a moment and try again. |
| 5xx | AO3 had a server problem (HTTP {status}). Try again shortly. |
| Other HTTP | AO3 returned an unexpected response (HTTP {status}). |
| Parse | AO3's page format wasn't what the app expected. |
| Offline | You're offline. Connect to the internet and try again. |
| Timeout | AO3 took too long to answer. Try again. |
| TLS | Couldn't make a secure connection to AO3. |
| Other transport | Couldn't reach AO3. Check your connection and try again. |
| Source token-preparation enum | Couldn't prepare the request. Try again, or open the form on AO3. (No fresh token lookup is added to Post/Preview.) |

After confirmed Save/Post/Delete return, iOS Drafts task reads the current page once
on reappearance: GET `/users/{URL-encoded username}/works/drafts` on page one,
`/users/{URL-encoded username}/works/drafts?page={N}` on later pages; no POST or body,
same authenticated Cookie/UA. Reuse Android's landed onSaved revision for exactly that read. Debug
routes without a list close with zero list reads. Failure/preview/Edit do not reload.

## Reference disagreements and sparing boundary

- iOS wins over the audit's preview-first suggestion: work Post is directly one POST,
  even for new. Chapter's preview-first path is not copied.
- iOS Delete makes four GETs across row + confirmed action, not the brief/audit's one.
  For posted works Android follows that order. The owner's binding rule forbids reads
  AO3 will refuse: an unposted draft's public `/works/{id}` is not read. Draft Delete
  uses two confirm GETs (before alert and after confirmation) and one POST. All allowed
  reads remain user-initiated, sequential, session-fenced. No speculative lookup.
- Swift shows AO3's caution verbatim. Parsed fallback stats do not invent a replacement
  sentence. Demo caution itself includes comments/kudos/bookmarks, so counts are visible.

## Decided without asking

Reuse existing work encoder/replay/verdict/single-shot client, chapter preview model,
paragraph renderer and lazy preview screen; no second HTTP or rich-text renderer.
Place new work action parser/model beside network/ao3/writing, tests beside writing
and demo suites. Reuse 995001 (draft), 995006 (posted), 995007 (new preview draft).
Refusals are deterministic local title triggers, documented below. No Room/backup change.
The continuation uses inline post-return generation checks, ready for Claude to fold
into main's movedOnAfterWrite, and small chapter-state compatibility edits because
its preview and POST path are reused here. No separate helper or HTTP path is added.

## Open questions

Draft work-page stats reads conflict with the owner's refused-read rule. Sparing choice:
skip them for drafts; never attempt an expected refusal. Posted reads follow Swift.
No broader entry-route or profile reload mechanism is introduced: landed Drafts revision
is reused; demo routes have no underlying list. Manual review remains for Claude.

Swift parseRichText treats nested div and blockquote containers as one paragraph
block. Sparing choice: retain that source shape in the shared Android renderer;
the long-preview test uses separate p elements. No second sanitizer, container
flattening or renderer is introduced. A very large single container/paragraph
layout remains a manual stress case for Claude.

## Work log and verification

Initial clean tree on android/agent-codex-3bx. No builds, branch switches, TASKS changes,
commits, pushes, live sign-in or AO3 contact. Implementation below is written;
compilation, tests and visual verification remain pending.

### Implementation completed in this worktree

`AO3WriteRepository` adds direct `postWork`, `previewWork`, `loadDeleteImplications`
and `deleteWork`. Post selects post_button through existing submitWork/workVerdict.
Work and chapter preview now share parseWritingPreview and AO3ChapterFormParser's
pane parser; work mode accepts only a trusted `/works/{positive id}` action.
New `network/ao3/writing/AO3WorkActions.kt` holds the preview alias, work adoption,
delete implications and pure delete parser. No new network transport or persisted field.
Required-field whitespace now uses the existing Foundation-compatible trimWritingTag.

WritingWorkFormState shares its guarded perform across Save/Post/Preview/check Delete/
Delete. Preparation and writes both freeze the exact snapshot; every failure restores
it, preview adoption is atomic, and duplicate calls during either GET or POST are inert.
Session checks surround confirm parsing/stats reads and the existing dispatch fence.
Save/Edit tags keep their prior editable-in-flight distinction. The form wrapper pins
its opening model before every asynchronous action, including failed Preview/Delete.

WritingWorkFormScreen draws the new Post/Delete groups as lazy panel segments, using
its sections/footnotes/alert. Posted forms have only Delete; new forms no Delete; a
preview-created draft gains Delete draft on Edit. WritingAO3PreviewScreen extracts
and reuses 3bu's screen and WritingPreviewParagraph, with work confirmation as an
optional parameter. Headings/labels retain Swift's semibold weight, and the posted
Delete row has no icon, as Swift's deletePanel draws it. Chapter's default tag/actions/
confirmation behavior remains. Its existing panel segment
is now named WritingPanelRow and reused by all three screens; no second panel helper.
ProvidePushedShellChrome owns preview chrome; statusBars + 76dp precedes its header.
All added text has line height; no fixed row height or label/value split. Destructive
colour is MaterialTheme.colorScheme.error, exactly SettingsActionRow's destructive
token; success uses the existing SuccessGreen colour token. No ui/subject or settings
component, typography, backup format or Room schema changed.

All success paths reuse state.saved → onSaved, already wired by AppNavHost to one
current-page Drafts revision/read. Preview/Edit/failure does not advance it. There is
no local deletion, optimistic list update, metadata verification or recovery cleanup.

### Policy authorization, one action at a time

| Operation | Rule allowing it | Logical requests after opening |
|---|---|---|
| Post work (new/draft) | Explicit writer action; Writes single-shot + write-session fence | 0 GET, 1 POST; no Save/Preview first |
| Preview (new/draft) | Explicit writer action; same Writes rule (creates a draft), never read-only | 0 GET, 1 POST; parse answer/adopt ID locally |
| Preview Post | Explicit confirmed writer action; same single-shot/fence | 0 GET, 1 POST to adopted action |
| Delete row, draft | User-opened work navigation permitted by no-background/private-scraping rule; refused-read rule skips public draft page | 1 confirm GET, 0 POST |
| Delete row, posted | Same explicit navigation rule | confirm GET then work stats GET, 0 POST |
| Confirm Delete, draft | Explicit destructive confirmation; fresh token through own confirm page, single-shot/fenced write | 1 confirm GET, 1 POST |
| Confirm Delete, posted | Same rule; source iOS sequence wins | confirm GET then stats GET, 1 POST |
| Confirmed close to Drafts | User's own foreground current account page, landed Save return path | 1 current-page GET |
| Failed/cancelled action or Preview Edit | No authorization for verification/polling | 0 follow-up requests |

Every read uses getAuthenticated, existing host allow-list, pacing and ordinary shared
GET policy. No repository retry loop is added. Every POST uses postWriting →
postAuthenticatedInSession once, never retries/coalesces, including preview, 429 and
5xx. The shared client retains its existing GET retry policy; source iOS's authenticated
GET likewise has transient retry policy. The brief's “never a retry” is applied to
writes and automatic action retries, not by silently changing the shared GET client.

### Local demo routes and taps (written, not run)

Launch existing local extras kudosDemoLibrary=true and kudosDemoSignedIn=true in airplane
mode. This is fixture session state, never real sign-in. Force-stop/relaunch resets the
process-local interceptor state. No new asset or script was introduced.

- **Draft that posts:** Account → Writing → Drafts (`nav:writing-drafts`) →
  **Lanterns Above the Mill**, work **995001**, or `nav:writing-work-draft-demo`.
  Scroll to Post → Post work → Post this work? → Post work. Its fixture has a nonblank
  title/rating/language/content, one warning and two fandoms: missingRequiredFields
  selects zero missing fields. POST returns Work was successfully posted. Current
  Drafts page then omits 995001. Reopening its edit page offers posted Update/Delete.
- **Refused Post:** same row, change Title to **Refuse this post**, Post work, confirm.
  All other served required fields remain filled. Local title rule runs only on
  post_button; returns **This draft could not be posted.** Exact title stays in form;
  the stored AO3 demo draft stays unchanged. It also works on the preview's Post.
- **New preview creates draft:** Drafts top New Work or `nav:writing-work-new-demo`.
  Type a title (blank fields also preview; Swift imposes no preview gate), Preview on
  AO3. Answer contains #previewpane + edit_button form action **/works/995007**, meta
  token and **Draft was successfully created.** Edit returns as Draft with Delete draft.
  Save posts **/works/995007**, never /works again. The current Drafts page includes
  995007 with the saved title. To Post this new draft instead, fill Title, Rating,
  Archive warnings, Fandoms, Language and Work text before preview/Post.
- **Posted work deletes:** `nav:writing-work-posted-demo`, work **995006**,
  **The Cartographer’s "Second" Tide & 星**. Delete work on AO3 reads local confirm
  and the existing local work page. AO3 caution names the work and **7 comments,
  23 kudos, 4 bookmarks**, then Delete this work? → Delete on AO3. One local delete
  POST, **Your work was deleted.**, closes. A later edit/confirmation/page request is
  locally 404. The existing saved library copy is not touched by the form.
- **Refused Delete:** same posted route after reset, Title **Refuse this delete**,
  Save, reopen; Delete work on AO3 → Delete on AO3. The rule uses the last locally
  saved title (the delete body correctly contains no title), returning **This work
  could not be deleted.** Form stays and the remote demo copy stays. Draft 995001
  may likewise be saved with this title and refused; draft Delete skips public GET.

One shared mutable answer owner remains DemoWorkSaves in DemoNetwork.kt. It handles
Post/Preview/Delete and subsequent edit/current Drafts/confirm responses; every write
terminates in the existing demo interceptor. New preview stores the draft; an existing
preview only renders its buffer without saving those edits. Posting removes save/post
controls and adds update; deleting suppresses all subsequent work/chapter/tag addresses.
No background operation, fixture web sign-in or socket is needed.

### Offline tests authored; all need Claude's run

- **WritingWorkActionsTest:** ordered literal iOS field oracle (reuse 3bo's independently
  specified fields, selected submit parameterized), new/draft/posted Post and Preview,
  zero preparation reads, ID/token adoption and next Save's update address, new preview
  followed by Post, missing required fields, Foundation whitespace, no ID unconfirmed,
  Swift Delete ordering and exact two fields, caution counts and nil-only stats filling,
  refusal-before-notice,
  raw redirect confirmation, unconfirmed 200/204, authored false flashes, signed out,
  every HTTP/transport group, before/during action session changes, duplicate in-flight
  GET/POST taps, retained typed fields and four recovery copies on failure and success,
  unsafe captured action and served-empty method fallback.
- **WritingWorkActionsScreenTest:** native/tall-window Compose, missing-field words,
  Post confirmation/refusal/title retention, posted-only Delete and AO3 caution counts,
  close only after confirmed Delete, preview pushed chrome/Edit/Save address, preview
  Post confirmation/error title, unconfirmed Preview/Delete retention, 1,000 paragraph
  preview laziness, real wrapper session retention/disabled second tap, Light/Dark/
  Sepia/Oled and large text with didOverflowHeight/last-line ellipsis checks.
- **WritingWorkDeleteLibraryTest:** real in-memory Room row and actual app works/{id}.epub
  bytes remain after confirmed remote Delete. No schema change; no main-thread @After.
- **DemoWorkActionsTest:** terminal local interceptor, real row postability, Post/refusal,
  preview-created 995007 then same-draft Save, posted Delete/refusal/counts, unchanged
  stored draft on existing Preview, token refusal and fresh-interceptor reset.
- **AO3WorkSaveDispatchTest:** added real shared-client Post/Preview/Delete cases: exact
  encoded bytes, contact User-Agent/Cookie/Content-Type/CSRF/Referer, no AJAX headers,
  one dispatched POST on success/429/503. Existing pacing-generation test retained.
- **Existing WritingWorkFormScreenTest:** inventory now expects the new controls per
  state, with no writes while opening. Existing Save/tag/chapter suites protect reuse.
  Recording helper now records interleaved requests and per-address GET answers.

### Static review, limits and handoff

`git diff --check` passes. The final static inventory contains 22 task files, all
under Android or this result document; new files are nonempty and have no trailing
whitespace or forbidden names. A source scan checks all 14 authenticated POST calls:
none has an immediate post-return cancellation fence. This is source inspection,
not compilation or test execution. Read real Swift encoder/header/parser/error code, Kotlin
client/encoder/parser/recovery/shell/row/Room/domain/EpubBuilder/test symbols and callers.
No Gradle, Xcode, Kotlin compiler, emulator, screenshot or test executable was run.
All compilation, coroutine timing, request counts, verdicts, Room/EPUB and Compose
assertions above are **authored claims requiring a test run**, not passing results.

Claude: compile debug and run :app:testDebugUnitTest with WritingWorkActionsTest,
WritingWorkActionsScreenTest, WritingWorkDeleteLibraryTest, DemoWorkActionsTest,
AO3WorkSaveDispatchTest, plus existing Work Save/forms/replay/tags/chapter/preview/
Drafts/shell/routes/demo isolation/session suites; then full Android gate. Review demo
screenshots in all four themes, accessibility text, Post/Preview/Edit/Delete, failure,
Back, new-draft adoption, current-page Drafts return and preserved library/recovery.
Human screenshot gate remains; no visual correctness or live AO3 success is claimed.

Work is left uncommitted/unpushed on android/agent-codex-3bx. TASKS.md, reference iOS,
backup and Room schema untouched. No helper script, stub or .orig file left behind.


### Continuation: owner's post-return session rules (2026-10-09)

Continued the existing uncommitted implementation on android/agent-codex-3bx; no
restart, rebase, branch switch or commit. The owner's three continuation rules take
precedence over the older base's handling of moved sessions after writes:

- AO3WriteRepository keeps requireCollectionSession only before dispatch/preparation.
  Every postAuthenticatedInSession response boundary now compares generation and
  returns Validation(AO3CollectionFields.UNCONFIRMED) when it moved, including the
  shared postWriting path, collection-item loop and account index write. Series
  verification after a dispatched write uses the same verdict. These are deliberately
  small inline checks: **Claude should fold them into main's movedOnAfterWrite helper**
  when merging; no competing helper was introduced.
- Work state displays returned Success/Failure without a later generation override
  or cancellation check. CancellationException from preparation/dispatch can still
  produce WORK_FORM_SESSION_CHANGED before anything is sent. Every active exit has
  finally cleanup of saving. Off-main preview parsing completes under NonCancellable
  before publishing its verdict; its own post-parse generation check is unconfirmed.
- The reused chapter state receives the same limited compatibility fix: returned
  verdicts survive unchanged, busy clears in finally for Save/Preview/Delete, and
  UNCONFIRMED gets neither “The chapter was not deleted.” nor a total-update prefix.
  Other chapter refusal copy and request sequencing remain the existing 3bu behavior.
- Work Save/action, Edit tags and real-wrapper session tests now distinguish zero-POST stale
  preparation from one-POST unconfirmed completion. Additional held Delete POST
  cases (notice and refusal responses) assert unconfirmed alone, exact typed form
  retained, one POST, no close/refresh and cleared busy. Thrown failure/cancellation
  cleanup and chapter delete/session regression cases are authored as well. A real
  shared-client terminal-interceptor regression covers Save/Post/Preview/Delete on
  a moved 200 response and a returned 401 expiring the session: one POST, unconfirmed.

These continuation claims also require Claude's test run. Add WritingChapterSaveTest
and WritingChapterDeleteTest to the focused run. The repository's shared boundaries
also require the existing series/collection/account write suites from main; Claude's
manual merge must retain main's corresponding state-verdict/cleanup fixes. No shared
UI component, backup format, Room schema, TASKS.md or iOS reference was changed.

---

## Landing note (Claude, 2026-10-09)

Landed on `android/redesign-parity` after a hand merge. Gate: 2,365 tests. **Not seen on the
emulator** (four agents were running): owed are Post with its confirmation in each wording,
Preview on AO3 with a long work, Delete draft and Delete work with AO3's caution, in Light and
Sepia and at the largest text.

Changed on landing:

- **Seven files conflicted** with the fixes of audits A24 and A26 landed after this work's
  base. In `AO3WriteRepository` the thirteen inline "session moved" checks became the lane's
  `movedOnAfterWrite`; the shared `parseWritingPreview` took the lane's rule for a preview
  (below). The chapter and work form states were taken as written here: they are the same
  changes the lane had made, with a `finally` that clears the busy flag.
- **A preview from a session that has since moved on is kept when it names its work**
  (audit A26-1: previewing a new work makes AO3 create the draft, and a form that forgets it
  creates a second one). This result file says such an answer is UNCONFIRMED: that was the
  instruction given on resume, and it was too broad. A pane with no work behind it, from a
  session that moved on, is still UNCONFIRMED.
- **AO3's login page in answer to a POST is "Your AO3 session expired. Please log in again."**
  (its own refusal, and what ended the session), not UNCONFIRMED: decision of the same day.
  Two tests here expected UNCONFIRMED and were corrected.
- **The work's own page is not read for a delete.** iOS reads it after the confirmation page,
  before the alert and again on the confirmed delete, for counts neither app shows (the alert
  is AO3's caution, verbatim). Removed: `withStats`, the `isDraft` argument, one test; a
  posted work's delete is two reads and one POST where iOS makes four reads. **An iOS task:**
  drop the same read there.
- Two tests waited on the test clock for work done on another thread (the confirmation page's
  parse, the preview's rows) and failed: they wait in real time now.

Left as written: an unconfirmed total after a saved chapter shows the unconfirmed sentence
without "The chapter was saved, but the work total was not updated."
