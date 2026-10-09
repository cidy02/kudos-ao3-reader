# Brief 3bu — chapter form

## iOS contract, read before writing Android

Read-only reference: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`:
`Features/Writing/{AddChapterView,WritingChaptersView,WritingDraftsView,WritingTextEditor,WritingPreviewView,WorkEditView}.swift`,
`Models/AO3WritingModels.swift`, `Services/{AO3Client+Works,AO3WorkActions}.swift`.

Entry: WorkEditView shows Chapters and Add chapter only for a posted work. Chapters
reads `/works/<id>/navigate` once. A row pushes WritingChapterDestination with
workID, workTitle, chapterID and the index's chapterCount. Add chapter passes only
workID/workTitle (no count). The destination reads exactly one authenticated GET:
`/works/<id>/chapters/new` for new, `/works/<id>/chapters/<chapter>/edit` for existing.
No co-creator, chapter-total or other read on opening. Loader title is Edit chapter,
including for new. Failure: “Couldn't load from AO3”, reason, “Try Again”.

AddChapterView header: “AO3 Account”, “Add chapter” / “Edit chapter”. Subtitle is
`<workTitle> · chapter <positive position>`, otherwise work title + chapter title
(or “chapter”). Sections/rows:

* Chapter: Title; Chapter number (`N of` + expected total) when position was served,
  otherwise Expected chapter total (Unknown); Position (“After chapter” + N−1)
  when served. Typing a nonnegative after-number stores N+1; other text passes
  through. Changing expected total changes chapter[wip_length], not work[wip_length].
* Text: Chapter text; Summary; Beginning notes; End notes. Each pushes the existing
  one-field editor, account = signed-in username, target =
  `work:<id>:chapter:<chapterID or new>`, fields = content / summary / notes /
  endnotes. Content's rule title is Chapter N. Content alone gets Preview on AO3
  and Delete chapter in More. Delete appears only with an existing chapter and
  chapterCount > 1. iOS parses selected creator IDs but **shows no co-creator UI**.
* Publication: Set a different publication date (Custom publication date for
  accessibility); Publication date when year nonempty; Post without preview only
  for new/draft (off initially); This is the last chapter (off initially).
  Date on fills today's unpadded year/month/day; off empties all three. DatePicker
  here has no allowedRange restriction. Last chapter does not change position or
  expected total; it schedules a second write with total = positive position.
  Invalid position: “Enter this chapter’s position to mark it as the last chapter.”
* Post: posted = Save chapter changes; new/draft = Post chapter now and Save as
  draft. After a confirmed chapter but failed total: Retry updating the work total
  and “The chapter was saved. Only the work total will be retried.” Edits disabled.

Footnotes, verbatim:
“When you turn on Last chapter, Kudos sets the work's total to this chapter's position. AO3 marks the work complete when its posted and total chapters match.”
“Posting a chapter notifies your subscribers. Save it as a draft if you want to work on it over several sittings without sending a notification.”

All chapter form writes POST the captured action (new `/works/<id>/chapters`,
existing `/works/<id>/chapters/<chapter>`), referer = action, X-CSRF-Token = loaded
CSRF token, body authenticity_token = same token (trimmed nonblank page meta first,
form token fallback), non-AJAX, through submitWrite, never retried. Exact modeled
fields/order: authenticity_token; nonempty _method; chapter[title]; chapter[position]
only if includePosition and nonempty; chapter[wip_length] only if nonempty;
chapter[summary]; chapter[notes]; chapter[endnotes]; chapter[content]; nonempty-year
branch chapter[published_at(1i)], (2i), (3i); repeated
chapter[author_attributes][ids][]; selected submit name = 1. Save as draft uses
save_button. Posted update uses update_button. Direct Post uses
post_without_preview_button. Default Post first sends preview_button.
Preview page requires #previewpane; no pane: AO3 refusal or
“AO3 didn't return a preview. Try opening the work on AO3.” Preview header Preview, AO3 notice,
lazy heading/label/paragraph blocks with images dropped; buttons Post chapter
(or Update) and Edit. Post sends post_button via the same form save path; Edit
returns locally. A NEW preview saves a draft: adopt preview work/chapter identity,
new token if supplied, action `/works/<id>/chapters/<chapter>`, _method patch,
isDraft true. Missing/mismatched identity is unconfirmed; never invent an ID.

Last chapter: after confirmed chapter write only, updateWorkTotals loads the work
edit form, sets chapterTotal = position, posted = nil (no posted-count override),
saves all work parameters with update_button if posted, save_button if draft.
iOS loadWorkForm also best-effort reads the signed-in user's collections page 1.
Sequential, not parallel. Failure prefixes “The chapter was saved, but the work total was not updated. ”
to the ordinary reason. Retry sends ONLY the total operation; chapter isn't repeated.
Error title “AO3 could not save the chapter”, OK; preview title “AO3 could not post this”.
Session fence: “Your AO3 session changed. Reopen this form before saving.”

Delete: editor alert `Delete “Chapter N: Title”?` (trimmed title; number/title
fallbacks in chapterName), message “This will delete all comments on the chapter as well and cannot be undone.”,
Delete on AO3 / Cancel. Confirmation closes/checkpoints editor, then one GET
`/works/<id>/chapters/<chapter>/confirm_delete`; parse action/token/_method;
POST action, referer action, body authenticity_token + _method (served nonempty
or delete), **no submit button**, no extra fields. Expected generation checked
before and after GET and at write dispatch. Cancellation: “Your AO3 session changed, so nothing was deleted.”
Other failure: “The chapter was not deleted. ” + reason. AO3 refuses an only chapter
or only posted chapter through its error flash; index doesn't carry posted status.

Verdicts (submitWorkForm): AO3's first nonempty #main flash.error / #error li,
outside writer content, wins; notice = #main > .flash.notice; redirect 300–399
also confirms (“Saved.”). A 2xx without notice: “AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.”; other status: “AO3 didn't accept the change.”
Preview evidence is its pane and (for new) same-work draft identity. Writer's own
error/notice/successfully text proves nothing. These paths do not clear recovery.

After confirmed Save/Post/Update/Delete: onSaved and dismiss. The Chapters list
increments reload (one index GET) and notifies work form. Work form refreshes work
edit (one GET + one best-effort collections GET in iOS), taking only chapterTotal,
chaptersPosted, isChaptered and fresh chapter-1 fields; it preserves an unsaved
publication date if different from initially loaded date. Other unsaved work edits
stay. Failure blocks work Save with “Reload chapter totals before saving this work. ”
+ reason and Reload chapter totals. A total failure still calls onSaved (chapter
was saved), refreshing list/work while keeping chapter screen open for total retry.
A new preview also calls onSaved (new draft exists), without dismissing. Existing
preview, failed/unconfirmed chapter, or failed delete does not refresh parents.

## Reference disagreements and sparing decisions

* The brief requires iOS's chapter post confirmation words. **AddChapterView has
  no post confirmation alert and passes no confirmation to WritingPreviewView.**
  WorkEditView's work confirmation is not chapter copy. iOS wins: use its chapter
  footnote and default preview-first path; no invented alert/extra request.
* The brief says no notice/no error never confirms; iOS explicitly accepts a raw
  3xx as confirmation. iOS wins for 3xx; flashless 2xx remains unconfirmed.
* The brief names writeErrorMessage. Current iOS uses scoped workWriteError for
  work/chapter/delete to exclude writer markup; Android must preserve that scope
  while using the shared validation-list reader, with refusal before notice.
* Android's parent work repository does not eagerly fetch collections. Keep that
  sparer policy: total/parent refresh reads the work form once, no unused picker GET.
  No collections are sent that the loaded work form's encoder would not send.

## Work log

Clean start on android/agent-codex-3bu. Prior briefs including 3bm landing note and
A4 triage read; reusable served-controls snapshot, authenticated client/write path,
form state/chrome, text recovery and demo terminal interceptor inspected. No
Gradle/Xcode, branch operation, TASKS edit, sign-in or network contact authorized.

## Decided without asking

Use writing package and network/ao3/writing alongside work form; original local
995006/995001 fixtures in debug assets, test fixture reads reuse existing loader.
No dependencies, persistent fields, backup or Room changes. Details added as built.

## Open questions

The absent iOS chapter confirmation is an owner/iOS follow-up, not invented Android
copy. Current iOS behavior wins. Android's sparer collections-read policy retained.

## Verification

All four phases are written. Compilation, test execution and all visual claims remain
for Claude; this sandbox did not run Gradle or Xcode. Static evidence and the exact
handoff checks are recorded below. No passing-test or visual-correctness claim is made.

### Phase 1 written

AO3ChapterForm/Field/Urls and AO3ChapterFormEncoder retain every served control using
AO3WorkFormParser.servedControls. Modeled order/branches match iOS; enabled served
name filtering prevents sending absent controls. Omitted modeled branches replay
successful served values, as 3bb requires. Coauthor hidden arrays remain replay data;
no co-creator row is invented. AO3ChapterFormParser reads form/action/token/text/date/
creator IDs/draft submits from one page and checks trusted action/path/method.
AO3WorkFormRepository.loadChapterForm makes one authenticated read, checks requested
work/chapter identity and session, no enrichment. Eight original new/draft/posted/
one-shot fixtures plus two delete fixtures cover 995006 and 995001. AO3ChapterFormTest
and WritingChapterReadTest authored; not run. Preview identity adopts patch/action
and preview-served submit controls while preserving original text and recovery fields.

### Phase 2 written

Re-read landed 3bt/3bo and current work screen/state/parser/encoder/repository/demo;
resumed on android/agent-codex-3bu2 with only the result file from the earlier run.
WritingChapterFormState owns one attempted opening and all in-memory text/title/
position/total/date choices. WritingChapterFormScreen uses collected state, one lazy
item per panel segment, shared form parts and statusBars + 76dp. Chapters rows now
open existing forms with chapter count; Add chapter opens new with no count. Both
are posted-work-only like iOS. Text editors reuse exact account/target/field and
checkpoint-on-departure. No hidden co-creator editor added. The existing date sheet
has an opt-in unbounded chapter mode (years 1…9999, future dates allowed), leaving
work-date bounds as before. Back discards only the chapter's in-memory form;
recovery copies remain. Phase-2 state tests authored, not run.

### Phase 3 written

Extended the landed submitWork with shared postWriting/workVerdict; Save work and
Edit tags preserve their existing behavior. Chapter Save/Update/direct Post/Preview
use the existing generation-fenced authenticated client once, loaded action/token,
no preparation read. Work-total update reads the work form once and sends its current
full encoder payload with only chapterTotal replaced, filtered to served enabled
names. No optional collections fetch. Refusal uses work-scoped evidence through the
shared writeErrorMessage list reader, before notice/redirect. Preview requires AO3's
pane; a new draft's same-work ID is mandatory before adoption. Draft identity/token/
preview-served submit are retained for subsequent writes; no second create.

Confirmed chapter, total and preview state are distinct. Total failure retains all
text and locks edits, shows the exact prefix and total-only retry. New preview, every
confirmed save/delete and total-only retry notify owners; failed/unconfirmed chapter
and existing preview do not. Chapters keeps its loaded list mounted logically while
a child is pushed; one confirmed change triggers one index GET. Work parent refresh
copies totals/chapter-1 only, including its raw chapter replay controls to prevent
stale text/date replay, preserving unsaved publication date as iOS does. Required
refresh failures remember attempts and block Save until Reload chapter totals.
Operation scopes belong to the owner, so a sent write's confirmation still refreshes
parents after Back. No optimistic success or invented success banner.

WritingChapterSaveTest authored for exact fields/headers/submit, one POST and ordered
two-request totals, refusal/notice/redirect/unconfirmed, retained failures, duplicate
busy taps, preview identity, and session/transport failures. Not run.

### Phase 4 written

The content editor gets callbacks only (no form/client/auth dependency): More adds
Preview on AO3 and, with known count >1 and ID, Delete chapter. Its exact iOS alert
names the chapter and warns about comments/irreversibility. Cancel sends nothing;
Delete on AO3 first closes/checkpoints the editor into the form, then confirms the
state's delete operation. Only then is confirm_delete read once and its checked
same-chapter action/token/method POSTed once, without commit/submit/total. Failures
retain every field and exact iOS prefixes; session cancellation has iOS's separate
“nothing was deleted” message. Only AO3 confirmation closes/notifies parents.
WritingChapterDeleteTest authored for gate, ordered requests, refusal/unconfirmed,
retention, only/new/unknown count suppression, duplicate tap and session fence.

## Demo routes and taps (authored, not exercised)

Use existing local extras kudosDemoLibrary=true and kudosDemoSignedIn=true, airplane
mode. These are fixture flags, never an AO3 sign-in. All chapter/read/write answers
terminate in DemoNetworkInterceptor → DemoWorkSaves → DemoWritingChapters. New
handler has no HTTP client/proceed/socket; fresh process resets its answers.

* nav:writing-work-posted-demo (995006): Text → Chapters → either row → existing
  chapter. Save chapter changes confirms locally; index and work totals re-read
  locally. Chapter text → More → Delete chapter → named alert → Cancel sends
  nothing; Delete on AO3 reads local confirm_delete and posts one deletion, then
  the local index loses that row. The last chapter/last posted chapter is refused.
* Same route → Add chapter: edit Title/Chapter text etc. Save as draft creates a
  local draft. Default Post chapter now first previews (creates/adopts a draft),
  Post chapter updates that same draft, Edit returns locally. With Post without
  preview on, Post chapter now sends one direct post. Reopen Chapters to see it.
* nav:writing-chapter-new-draft-demo (995001 new) and
  nav:writing-chapter-draft-demo (995001 existing 12311): same fields/actions,
  original filler. These entrances are debug-only and guarded by demo isolation;
  the production draft work form still has no Chapters/Add row, like iOS.
* Title Refuse this chapter → Save as draft / direct Post / Preview returns a
  local 422 #error ul with “Title is too long (maximum is 255 characters)” and
  “Content can't be blank”. iOS displays the first reason; all typed fields stay.
  Correcting and explicitly tapping again makes a new attempt, never an auto retry.
* This is the last chapter on → Save/Update/direct Post: chapter POST, work edit
  GET, work total POST, sequentially. Normal titles succeed. Title Fail total once
  makes the first total POST fail with “Expected chapter total could not be updated.”
  after the chapter was saved. The exact prefixed message appears; OK → Retry
  updating the work total sends only work edit GET + work POST and succeeds.
  Chapter is never repeated. The handler retains each success for later reads.

Decided without asking: 995006 index IDs 12301/12302 and 995001 draft 12311; new IDs
advance locally. Original content fixtures, deterministic title triggers, process-local
state; two debug draft entrances because iOS deliberately hides chapter entry on a
draft work. No production route/visibility exception. Work refresh's chapter-control
snapshot is updated along with its interpreted fields to satisfy Android's replay
boundary (iOS has no raw replay snapshot). Last total POST is served-name-filtered;
work Save's previously landed encoder is otherwise untouched.

## Offline tests authored (not passing-test claims)

AO3ChapterFormTest, WritingChapterReadTest, WritingChapterFormStateTest,
WritingChapterSaveTest, WritingChapterDeleteTest, WritingChapterRefreshTest,
WritingChapterFormScreenTest, AO3ChapterDispatchTest, DemoWritingChaptersTest.
Existing inert Add chapter assertions now expect its action. Browser oracle is
3bb's independent DOM reader with only the fixture form ID changed; replay values,
multiplicity/order stay exact. Modeled untouched pairs allow only submit label → 1;
no array, Unicode or whitespace normalization. Encoder branch oracle is literal iOS
field order/conditions. Tests cover both works, every fixture, absent/disabled fields,
all text recovery keys, one attempted read, explicit retry, exact request headers/
fields/encoded bytes, 429/503 no write retry, shared pacing/session fence, every
verdict, retention, ordered totals/partial retry, preview adoption, confirmation-only
Delete and required parent refresh. Compose uses tall native-graphics windows and
patient waits with waitForIdle before off-screen state waits; lazy theme checks use
height overflow/last-line ellipsis, never hasVisualOverflow on a short label.


## Read and write counts after the opening

Counts below exclude the initial chapter GET and, where applicable, the initial
index/work GET. They describe a visible owning work form and Chapters list. iOS's
best-effort collections attempt is counted even if it fails. Android retains 3bb's
requested-form-only read policy. Returning to an already loaded chapter/editor is
local; explicitly reopening a destination or retrying a failed load is a new read.

| Outcome | Chapter/total POSTs | iOS following reads | Android following reads |
| --- | --- | --- | --- |
| Existing Save draft / Post / Update confirmed, Last off | 1 | index 1 + parent work 1 + collections attempt 1 = 3 | index 1 + parent work 1 = 2 |
| Existing confirmed, Last on, total succeeds or fails | 2 when total preparation succeeds | total work 1 + collections attempt 1 + index 1 + parent work 1 + collections attempt 1 = 5 | total work 1 + index 1 + parent work 1 = 3 |
| Total-only retry succeeds or fails, chapter already saved | 1 when total preparation succeeds | same 5 reads; chapter POST is never repeated | same 3 reads; chapter POST is never repeated |
| Delete confirmed | 1 | confirm_delete 1 + index 1 + parent work 1 + collections attempt 1 = 4 | confirm_delete 1 + index 1 + parent work 1 = 3 |
| Chapter refused/unconfirmed/transport failure | 1 attempt | 0 parent/index reads; no total request | 0 parent/index reads; no total request |
| Delete refused/unconfirmed | 1 | confirm_delete 1 only | confirm_delete 1 only |
| Existing Preview succeeds | 1 | 0 parent/index reads | 0 parent/index reads |
| New Preview via Add succeeds | 1 (creates draft) | parent work 1 + collections attempt 1 = 2 | parent work 1 |
| New Save/direct Post via Add succeeds, Last off | 1 | parent work 1 + collections attempt 1 = 2 | parent work 1 |

Add owns no mounted index, so its success does not fetch an unseen index; opening
Chapters afterwards fetches it once. Its Last-on path adds the work-total preparation
read(s) and one work POST to the Add counts. A failed total preparation GET sends no
work POST, still reports partial success and refreshes its owners. A missing/invalid
Delete confirmation form sends no delete POST. A refused opening makes only its opening GET and sends no write.
A new Preview with no usable identity does not clear the new form or refresh owners.

## Remaining copy and replay details

The empty Chapter text hint is “Empty. This opens the editor with plain text, AO3’s
HTML tags, or a paste from elsewhere.” Other text rows show Empty / Set. Chapter
loader and form use no toolbar Save; editors restore their own More/Done/local
Preview toolbar, and the server preview has Edit plus Post chapter / Update.
Chapter form errors use “AO3 could not save the chapter”; server preview uses
“AO3 could not post this”; both have OK. iOS's opening destination exposes
“Couldn't load from AO3” and Try Again. No recovery file is deleted by an AO3 write.

Shared iOS/UserFacingError sentences retained through workFormFailure:

* “Log in to AO3 first.” before an unauthorized chapter operation; “Your AO3 session expired. Please log in again.” for a login-required opening.
* “AO3 refused the request (HTTP 403). Wait a while before trying again.”
* “That work or page couldn't be found (it may be restricted).”
* “AO3's page format wasn't what the app expected.”
* “AO3 had a server problem (HTTP <status>). Try again shortly.”
* “AO3 is rate-limiting requests. Wait a moment and try again.”
* “You're offline. Connect to the internet and try again.”
* “AO3 took too long to answer. Try again.”
* “Couldn't make a secure connection to AO3.”
* “Couldn't reach AO3. Check your connection and try again.”
* “AO3 returned an unexpected response (HTTP <status>).”

The write-specific no-token sentence in iOS is “Couldn't prepare the request. Try
again, or open the form on AO3.” The chapter opening parser in iOS throws AO3Error.parse for a missing token.
Android likewise rejects it as a parse failure with the work-form error mapping; it sends nothing.
An AO3 validation reason is shown verbatim. Session changes use the chapter Save
and Delete sentences inventoried above and suppress any stale success.

Replay is deliberately the 3bb boundary: names absent or disabled on the captured
form are never sent; chosen modeled pairs override all served instances of that
name; remaining successful controls replay with multiplicity, order and exact text.
When iOS omits an empty total/position/date/creator branch, served values replay;
clearing the UI does not invent an AO3 clearing parameter. Preview captures newly
served patch/post controls before using them. Demo replies preserve unknown replay
controls, and its draft entrance uses known initial chapter count 1, suppressing
Delete rather than inventing a count. The posted index provides the live count.

## Final verification and Claude handoff

Authored **52 offline test cases in 9 new suites**, plus the two existing screen
assertion updates. Tests use recording clients or terminal interceptors; no test
needs a socket or AO3 credentials. New fixtures: **10** original local HTML files.
A local Python HTML structural check verified each fixture's one POST form,
CSRF/token controls, chapter action and position-present/absent expectation. This
is a structural check, not execution of the Kotlin parser tests. `git diff --check`
passed. Source/call-site review checked real constructors, field names, Compose
APIs, session/write fences and existing editor callbacks. Experimental coroutine
test APIs have explicit opt-ins. Nothing was compiled or visually exercised.

Claude still needs to build Android debug and run the nine new suites above, then
regress AO3WorkFormTest, AO3WorkFormRepositoryTest, AO3WorkSaveDispatchTest,
WritingWorkSaveTest, WritingWorkFormStateTest, WritingWorkFormScreenTest,
WritingWorkFormRoutesTest, WritingChaptersTest, WritingTextEditorScreenTest,
WritingTagsEditorScreenTest, WritingEditTagsScreenTest, WritingEditTagsTest,
DemoWorkFormTest and DemoNetworkBlockTest. Run the lane's required checks afterwards.
Request order/counts, retention,
preview adoption, parent refresh after Back, demo isolation, Kotlin/Compose
compilation and all assertions require that run; none are claimed passing here.

Manual offline demo checks still owed: all routes/taps above, keyboard and text
checkpoint return, preview adoption/Post/Edit, named Delete/Cancel, partial total
failure/retry, parent reload failure/retry, and Light/Dark/Sepia/OLED at regular and
accessibility font scales. Inspect headers below statusBars + 76dp, restored shell
chrome, long labels/trailing values, publication date sheets and lazy bottom actions.
The visual approval gate is still outstanding.

No Gradle, Xcode, sign-in, AO3 contact, commit, push, branch switch, TASKS edit,
iOS edit, backup change, Room schema change, helper script or .orig file was made.
Changes are left uncommitted on android/agent-codex-3bu2 for Claude's build/test/commit.


### Work-total body inventory

The second POST uses the fresh work form's captured action (normally
`/works/<workID>`), method POST, referer = that action, fresh token in both
`authenticity_token` and X-CSRF-Token, `_method` when served/nonempty,
`update_button=1` for posted or `save_button=1` for draft. It sends no
`work[chaptersPosted]` override because AddChapterView passes posted:nil.
Every other modeled value comes from that fresh form, using its existing full
encoder (3bb and 3bt), then served-name filtering and browser replay:

* work[title]; nonempty work[rating_string]; repeated work[archive_warning_strings][]
  and work[category_strings][] (a single empty string when none selected).
* work[fandom_string], work[relationship_string], work[character_string],
  work[freeform_string] with the shared iOS tag-list join; work[language_id].
* work[summary], work[notes], work[endnotes]; work[collection_names] and
  work[recipients] with the shared list join.
* Selected work[series_attributes][id], else trimmed nonempty
  work[series_attributes][title], else both empty.
* If parent URL/title is nonempty: work[parent_work_relationships_attributes][0][url],
  [title], [author], [language_id]; [translation]=1 when enabled.
* work[wip_length] = the saved chapter position; work[backdate], work[restricted],
  work[moderated_commenting_enabled] as 1/0; nonempty work[comment_permissions];
  optional work[anonymous] and work[collection_inbox] as 1/0; work[work_skin_id].
* If chapter 1 exists: work[chapter_attributes][title], [summary], [content] only
  when served; [published_at(1i)], (2i), (3i) only when year nonempty.
* Repeated work[author_attributes][ids][]; nonempty work[author_attributes][byline].
* Existing encoder's conditional hidden carry and all remaining browser-successful
  served controls, with duplicates preserved. No field absent from the fresh form
  is sent by this total operation.

The parent's unsaved work form is never the source of that second POST. A total
retry re-reads its work form/token, so only the confirmed chapter operation is
remembered; the second operation is rebuilt from the current server form.

## Landing note (Claude, 2026-10-09)

Landed on `android/redesign-parity`. Gate: 2,309 tests.

Changed on landing:

- **Merged by hand over the series form** (3bw landed while this was being written): two
  conflicts, a list of routes in `Routes.kt` and, in `WritingWorkFormScreen.kt`, the place
  where both added a screen that takes the form's place (the series reorder, the chapter
  form). Both are kept. `AO3WriteRepository.kt`, `DemoNetwork.kt` and the rest merged by
  themselves.
- Two test faults: a missing import (`getOrNull`), and section titles looked for in mixed
  case where the shared section header draws capitals.

Where this followed iOS against the brief (kept): a chapter has **no "Post?" confirmation**
on iOS, so none here (posting goes through the preview, with iOS's footnote); a raw redirect
counts as AO3's confirmation, a 2xx with no notice does not.

**Nothing has been seen on the emulator** (it would not stay up on 10-09). Owed: Add chapter
from a draft and from a posted work; editing a chapter from the Chapters list; Save, with a
refusal; the preview and Post from it; Delete chapter with its confirmation; the work
form's chapter count after each; four themes and large text. Nothing here has run against
AO3.

## Seen on the emulator (Claude, 2026-10-09)

`nav:writing-chapter-new-draft-demo`: the form with its sections and switches; Post chapter
now opens the Preview with "Draft saved." and Post chapter / Edit; Save as draft closes the
form. Not seen: Delete, the posted work's chapter list, Sepia and large text.
