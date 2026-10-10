# Brief 3cd — own works and Edit multiple works

## iOS contract (read from Swift, not the audits)

Reference read-only: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`.
`AuthorProfileView.swift:528–536` compares the signed-in account username with the
route username case-insensitively. It never infers ownership from a displayed pseud.
Own Works gets Select Works; Select All/Deselect All selects loaded rows only;
Done exits. The own bar replaces the reading bar: Edit N (Edit when empty),
Collections, Visibility, Delete, all disabled for zero selected or during Delete.
Collections/Visibility open the same form scrolled to their named sections.
`AuthorProfileContentSections.swift:338–421` gives nonselecting own rows trailing
swipe actions, full swipe disabled: Delete, Chapter (completion != true), Tags,
Edit. Edit opens the work form; Tags opens Edit tags; Chapter opens Add chapter;
Delete asks `Delete “TITLE”?`, `Delete on AO3`/`Cancel` and
`This permanently removes the work and its chapters, kudos, comments and bookmarks from AO3 for everyone.`
The id comes from the row: no ownership probe or detail read for navigation.

`WritingBulkEditDestination` remembers its loaded form across reappearance.
Opening bulk edit: authenticated GET `/works/FIRST/edit` for CSRF, then one
nonmutating POST `/users/USERNAME/works/edit_multiple`, referer that same URL,
body `authenticity_token=TOKEN`, repeated `work_ids[]=ID` in selection order.
No `_method` on this rendering POST (Swift sends none). No opening/selecting/
cancelling selection writes. Explicitly opening the form DOES send its rendering
POST: iOS wins over the brief's literal “nothing sent on opening”. Failed loads
retry only through Try Again. Loading: `Loading N works…`.

Header `AO3 Account`, `Edit 1 work` / `Edit N works`, subtitle served titles joined
`, `. Introduction: `Your changes apply to every selected work. Use the separate Add and Remove groups for tags. Anything you leave alone stays unchanged.`
Ordered sections and rows from `EditMultipleWorksView.swift`:

- Tags to add / Tags to remove: Fandoms, Relationships, Characters, Additional tags.
- Change on all: Rating, Archive warnings, Categories, Language. Footnote:
  `Changing the rating or language replaces that value on every selected work. Warnings and categories are added or removed instead.`
- Collections and gifts: Add to collections (Collection name), Remove from collections
  (disabled None if no served options), Gift recipients (disabled Per work).
- Comments and visibility: Only show to registered users, Enable comment moderation,
  Who can comment.
- Creators: Add co-creators (Pseud), Remove me as a co-creator. Footnote:
  `AO3 sends each co-creator an invitation. Their work doesn't change until they accept it.`

Rating/language/comment choices are parsed from the served form. Blank options are
replaced with one `Leave as is`. iOS has literal On=1/Off=0 for the two permission
choices; Android follows those literal Swift choices; this is an iOS-wins exception to
the brief's otherwise served-only option rule.
Warning/category three-state choices come from AO3; label `Leave as is` or `+N, -N`.
Picker states Add / Remove / Unchanged; footer:
`Tap an option once to add it to every selected work, twice to remove it, or three times to leave it unchanged.`
Collection-name footer:
`Enter the collection name exactly as it appears on AO3. If AO3 doesn't recognize it, you will see that when you save.`
Save, Cancel; failure `AO3 could not save the change`, reason, OK. No save confirmation.

`AO3WorkActions.swift:bulkEditWorks` and `AO3BulkEditChanges`:
Tags are merged sequentially per work, stops at first refusal. For each work iOS
GETs `/works/ID/edit_tags` to merge, then `editTags` GETs it AGAIN for fresh
CSRF/action and sends one POST (normally `/works/ID/update_tags`, referer edit_tags).
That is two reads per tag write, not the brief's one: Swift wins. Current tag lists
are removed by case-insensitive comparison then additions append uniquely; rating
is chosen bulk rating or current. Tag parameters use the landed Edit tags encoder:
authenticity_token, served nonempty _method, nonempty work[rating_string], warnings
and categories arrays (empty sentinel if cleared), fandom/relationship/character/
freeform strings joined comma-space (empty when cleared), nonempty fresh language,
update_button=1, plus the existing successful served-control replay. No work text.
After tags, uniform changes (if any) GET `/works/FIRST/edit` for a new CSRF then
POST `/users/USERNAME/works/update_multiple`, referer same URL. Body in order:
`authenticity_token=TOKEN`, `_method=patch`, repeated `work_ids[]=ID`, nonempty
`work[rating_string]`, nonempty `work[language_id]`, nonempty joined
`work[collections_to_add]`, repeated `work[collections_to_remove][]=NAME`, nonempty
`work[restricted]`, `work[moderated_commenting_enabled]`, `work[comment_permissions]`,
`work[work_skin_id]`, `work[pseuds_to_add]`; `remove_me=1` only when selected.
No tag fields in the uniform POST; untouched fields omitted. Nothing changed sends
nothing. No gifts field and no skin row. A partial tag run is not rolled back.

Bulk Delete asks `Delete “TITLE”?` for one, `Delete N works?` for several;
`Delete on AO3` / `Cancel`. Single message as above; plural:
`This permanently removes LIST and their chapters, kudos, comments and bookmarks from AO3 for everyone.`
LIST is the locale's list formatter of every title in curly quotes. Snapshot holds
count/titles/ids and session. Then GET `/users/USERNAME/works/show_multiple` for CSRF,
POST `/users/USERNAME/works/delete_multiple`, referer show_multiple; body
`authenticity_token=TOKEN`, ordered `work_ids[]=ID`, `commit=Yes, Delete Works`.
No `_method` here because Swift sends none. It clears selection ONLY on confirmation,
then `model.refresh` reads dashboard first and, only when that succeeds, page one
of the selected list (retaining scope/sort). Its force load resets pagination. Bulk edit only dismisses;
Swift has no selection clear or list refresh on bulk edit success: iOS wins over
that part of the brief. Single Delete refreshes the profile without touching Library.

All POSTs use shared explicit Cookie/contact UA, form Content-Type
`application/x-www-form-urlencoded; charset=UTF-8`, X-CSRF-Token, Referer, ajax=false
(no X-Requested-With/Accept override). Token preparation reads require meta CSRF; only the rendered form parser has
an input fallback, as Swift does. No retry/coalescing of any POST, including form
rendering. GET pacing/retry remains owned by the existing client.

Swift verdict, `submitWorkForm`, verbatim:
```swift
if let error = AO3Client.workWriteError(in: body) {
    throw AO3WorkWriteError.rejected(error)
}
if let notice = AO3Client.workWriteNotice(in: body) { return notice }
if (300 ... 399).contains(status) { return "Saved." }
if (200 ... 299).contains(status) { throw AO3WorkWriteError.unconfirmed }
throw AO3WorkWriteError.rejected("AO3 didn't accept the change.")
```
Only a direct nonempty #main > .flash.notice confirms; errors are the first
nonempty #main .flash.error / #main #error li outside workskin/userstuff/previewpane.
A direct previewpane suppresses authored refusal extraction. Unconfirmed:
`AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.`
No read-back or mutation after refusal/unconfirmed. Session changed after a POST
uses the repository's unconfirmed verdict, except AO3's login response retains its
session-expired verdict, following 3bx's landing. Busy flags clear in finally.
Swift uses no library-copy deletion, backup or model operation in these flows.

## Policy permissions

Author profiles / explicit profile navigation allow the selected own list and its
post-confirmation refresh. User-opened forms allow edit/edit_tags/show_multiple
reads, never background crawling, ownership probes or read-ahead. Writes allows
the explicit rendering/save/delete POSTs through AO3WriteRepository and the existing
authenticated client, with fresh CSRF, session dispatch fence and no retry. Requests
are strictly sequential; no new HTTP client, identity or pacing implementation.

## Decided without asking

- Reuse RemoteWorkSelectionState in AuthorProfileScreen; the old AuthorWorksScreen
  is a search-by-creator surface and its displayed creator cannot prove ownership.
- Use an in-route pushed bulk screen, like the existing series form. No new bulk route.
- Put bulk models/parser in network/ao3/writing and form/state in writing; tests
  alongside writing/author/demo tests. Reuse writing form rows, panels and tag editor.
- Keep demo changes in DemoWorkSaves; own rows are local clones of existing metadata,
  with three original titles and ids, no new fixture address or external data.

## Open questions

- Preserve Swift's two tag preparation reads, and preserve selection after confirmed
  bulk edit; only confirmed Delete clears it. These conflict with the brief's shorthand.
- iOS's literal On/Off choices override the brief's served-only shorthand. All
  other choice groups are taken from AO3's form.

## Work log

Read instructions, operational docs, audits, 3bt/3bo/3bx/3by including landing notes,
and actual Swift/Kotlin symbols. Clean start on android/agent-codex-3cd. No TASKS
edit, build, branch switch, commit, push, sign-in or AO3 contact. Implementation in progress.

## Implementation and decisions after the symbol check

The implementation is written for Claude's build/test review; nothing is compiled
or visually verified here. `AO3BulkEdit.kt` models only the served option groups and
in-memory diffs. `AO3WriteRepository` owns rendering, fresh-token uniform Save and
bulk Delete. Tag Save follows the actual two-read Swift sequence and uses the existing
Edit tags writer for its body, headers, dispatch fence and verdict. Empty uniform
fields are omitted, never sent as clearing values. Required token GETs use the meta
token only: `AO3Client.parseCSRFToken` and `fetchCSRFPage` are meta-only in current Swift;
the bulk form parser itself allows the Swift input fallback. No preparation reads
are reused across writes, and no POST is retried.

`WritingBulkEditState` remembers every opening attempt, keeps typed changes when
load is requested again, keeps its generation and repository verdict, and clears
loading/saving in finally while active. A late session transition cannot send the
old form under the new account. `WritingBulkEditScreen` uses collected state, lazy
rows, writing panels/sections/footnotes and scope tokens. Separate add/remove tags
push the existing tag editor; warnings/categories push the three-state list;
collection names have their own lazy local editor; choices come from AO3. Back from
a picker restores form chrome through ProvidePushedShellChrome only. Focus scrolls
to the exact section; Save and Cancel are Material icon buttons. Save's trailing
content is null until the form exists. Short values are trailing content; long
values have a bounded wrapping width. New text has explicit line heights.

**Correction to the initial reading above:** current iOS has a literal two-option
On/Off list for restriction and moderation, not a served list. The implementation
now follows that Swift list (`1`/`0`) with Leave as is, despite the brief's absolute
“no list written into the app”; this is the explicit iOS-wins exception. Other
options remain parsed. No Work Skin row or gift field is invented.

`AuthorProfileScreen` reuses RemoteWorkSelectionState, not a second selector. Own
selection replaces the reading bar with Edit N / Collections / Visibility / Delete.
Other profiles keep the reading actions. Selected rows keep the existing work card's
metadata. Own rows get an accessible menu and trailing-drag reveal with the same
four Swift actions; no swipe sends anything. Complete rows omit Chapter; unknown
completion offers it. Native work/Tags/Chapter screens use the known id without a
detail probe. Own Works uses an AO3 Account subject header and scope palette.
Account → Works uses this same profile list through the existing AccountList route.
AppNavHost also supplies its dependencies to AuthorProfile/AuthorSeries. No new
routes: no neighbour list registration is needed. The Account route pins its first
writer's username so a session expiry cannot dispose a dispatched write's screen.

**Additional sparing decision:** own controls apply to Works and In collections,
but not Gifts. Swift gates only on the own profile + Works tab; a Gifts scope can
contain someone else's work. The explicit requirement to avoid editing another
writer's rows wins this edge case. No pseud/byline matching or ownership GET is used.

OwnWorksDeleteState snapshots named works/session when asking. Cancel sends nothing;
confirmed Delete exits selection, reads the dashboard header, and only on header
success reads page one of the selected list, retaining scope/sort;
refusal/unconfirmed retain selection and show the exact verdict. The model that owns
an open confirmation or dispatched Delete survives session changes until its error
is acknowledged; fresh idle operations get the current generation. Nothing calls a
library repository or a Room mutation. Work/Tags success reached directly from a row
just closes, as their Swift destinations do; Chapter success refreshes the profile.
Bulk Edit likewise only closes, retaining selection and costing no follow-up read.

## Demo routes, production taps and exact cases

Launch locally with `kudosDemoLibrary=true`, `kudosDemoSignedIn=true` (the existing
local AO3_Reader session, no real sign-in). Use **`nav:author-profile/AO3_Reader`** or
**`nav:account-list/MyWorks`**. Production entrance: Account → Works (shortcut or
Writing row). Row Actions → Edit/Tags/Chapter; a trailing swipe reveals that menu.
Existing `nav:writing-work-posted-demo` still opens work 995006 directly.
Select Works → choose rows or Select All → Edit N / Collections / Visibility;
Collections and Visibility open their respective group in the same form. Done
exits selection. Cancel closes the form without another request.

| Own demo row | ID | Completion / available case |
|---|---:|---|
| The Cartographer’s "Second" Tide & 星 | 995006 | 2/5, in progress: Edit, Tags, Chapter, Delete; existing full chapter demo |
| The Locked Lantern | 995008 | 2/2 complete: Edit, Tags, Delete; bulk edit refusal below |
| The Keeper’s Copy | 995009 | 2/2 complete: Edit, Tags, Delete; bulk Delete refusal below |

All three rows have author links under `/users/AO3_Reader/pseuds/Writer`; the drawn
pseud Writer deliberately differs from the account name. The rule selecting the
rows is the exact own username route (including own pseud and collected works
paths), not those displayed links. Each is a posted-form clone of 995006 with its
own work id/action/token/title; the clones set wip_length=2, and the list derives
2/2 vs 2/5 from those form values. The Chapter predicate (`isComplete != true`)
therefore offers Chapter only on 995006, whose existing chapter fixture is real.
Other authors retain their original three rows and sort fixtures.

- Select all three, Edit 3 → Rating Explicit / Language Español → Save: confirmed
  for all; each edit/tags form retains those changed values. Selection remains as
  Swift does. Reopen a row or reload the list to see the new rating.
- Select **The Locked Lantern** (alone or with others), Edit → Add co-creators
  `Refuse this edit` → Save: `The Locked Lantern could not be updated.` The chosen
  title is bound to id 995008; the exact byline trigger and selection membership
  are both checked before demo state changes. A refusal leaves all selected works
  unchanged. Other edits, including rating/language on all three, succeed.
- Select 995006 and 995008, Delete: confirmation names both titles; Delete on AO3
  succeeds, and the fresh own list shows only The Keeper’s Copy. Local Library stays.
- Select any set containing **The Keeper’s Copy**, Delete: confirmation names that
  set, then `The Keeper’s Copy could not be deleted.` Selection and list remain.
- The existing tag trigger `Refuse this tag` remains supported by each tags form.

All answers live in DemoWorkSaves, extending its existing edited/tag/posted/deleted
state. The application's authenticated clients and read-only browser use the same
mutable answer object; activation resets it. No duplicate handler for an address.
Tests can inject their own instance to avoid sharing writes across cases. Unknown
AO3 routes remain terminal local 404s. No socket, real account or external write.

## Offline tests written (not run)

- **WritingBulkEditTest**: literal ordered rendering/uniform/delete fields for one
  and several; exact CSRF/referer headers; DefaultAO3AuthenticatedClient cookie and
  non-AJAX headers; two-read tag sequence and fresh second token; complete tag body
  against an independent literal oracle; merge/dedupe/removal ordering; first
  refusal stops later works and uniform Save; served options/title extraction;
  notice/redirect/refusal-before-notice/unconfirmed 200 and 204/other status;
  failed preparation, signed out, changed session before/during preparation/after
  POST, AO3 login response, thrown transport; every active busy flag cleared;
  missing meta token (input alone rejected); remembered failed rendering; retry
  only when explicit; unchanged Save/Cancel sends nothing; duplicate busy tap.
- **OwnWorksScreenTest**: real profile, injected local clients and stripped images;
  own row/bar absent for another profile and signed-out reader; no requests on
  selecting/cancelling; single/plural confirmation naming; Delete refusal retains
  selection, confirmation exits and reads header + list; Edit/Tags use known id
  with no detail read, Back restores shell chrome; complete Chapter omitted;
  username vs displayed pseud; wrapping bar in four themes at double text size.
- **WritingBulkEditScreenTest**: delayed form gains Save in shell; refusal and
  unconfirmed preserve typed form; confirmed Save dismisses; Collections focus,
  served scalar/three-state picker, Cancel request counts; long rows in four
  themes at double text size. The host's selection remains when Save dismisses.
- **DemoBulkWorksTest**: all three actual posted own rows; uniform changes retained
  in each work/tag form; title-bound edit and Delete refusals; confirmed Delete
  removes only named rows; new instance resets; injected demo interceptor and
  browser share changed answers; a throwing downstream interceptor catches escape.
- **WritingWorkDeleteLibraryTest**: additional bulk test seeds three Room records
  and EPUB files, confirms remote Delete, then compares all records and bytes.
  No screen/coroutine outlives this test; resources close in its own test body.

Existing AO3AuthenticatedPostTest / AO3NetworkingCoreTest cover the shared transport's
contact UA, form encoding/media type, pacing and single-shot POST. No new transport
was written. New Compose suites use tall windows, native graphics, patient waits,
idle before request-count waits, Unit coroutine test bodies and full-height/
unellipsized-last-line checks. No main-thread-blocking @After cleanup.

## Verification and Claude handoff

Performed: source-level Swift/Kotlin symbol and caller checks, fixture/predicate
inspection, `git diff --check` (passes). No compilation, test execution, emulator
or screenshot claim. No Gradle/Xcode, AO3 contact, real sign-in, helper/stub/.orig
files, task edit, branch switch, commit or push. iOS, backup format, Room schema and
3cc-specific assignments files are untouched; shared DemoNetwork/WriteRepository/
AppNavHost edits are limited to this brief.

Claude must build Android and run the five suites above plus existing writing,
Edit tags/work/chapter/series, author sort/profile, account navigation/shell, demo
isolation and 3cc assignments regressions. Request counts, timing/session fences,
Compose behavior, Kotlin/API compatibility and passing tests all need that run.
Then inspect the two nav routes through actual Account taps, Back, Done, trailing
swipe/menu, zero/one/several selections, both focus destinations, tag add/remove,
all choices and fields, save/refusal/unconfirmed and Delete/cancel/refusal/success.
See Light/Dark/Sepia/OLED at ordinary and accessibility sizes: header inset, shell
restoration, long titles/labels/values, lazy scrolling, confirmation title lists and
form footer wrapping need screenshots. No live AO3 verification is authorized.

Final source review: verified `AO3AuthorProfileService.refresh` / `loadSelectedTab`:
post-confirmation refresh is dashboard, then selected list **page one**, with no
list request after a refused header. Android now follows that order and page reset.
The Edit entrance also passes the existing series repository so the work form
retains its native reorder/edit series destinations. Demo own lists have one
page of the three actual rows; original other-author pagination is unchanged.
Single row Delete: after the app's named confirmation, one GET
`/works/ID/confirm_delete`, parsed meta token (form input fallback), one POST to
its captured `/works/ID` action; body only authenticity_token and the nonempty
served _method (delete fallback), referer that action. No public-work stats read.
It uses the same refusal/notice/redirect/unconfirmed verdict and ordered profile
refresh as above. The form's existing Save/Post/Preview/Delete fields and screens
remain the landed 3bo/3bx implementation; this brief adds their own-row entrance.

The served bulk form's work-id order is adopted for Save, as Swift's initializer
does. The parser verifies the same selected set/count while accepting AO3's
reordering; it never adopts an unselected work. Added offline checks pin this and
the Delete confirmation's immutable id snapshot/duplicate busy tap. Basic delimiter
scanning of all 14 changed/new Kotlin files and local fixture/predicate assertions
also passed; neither is a Kotlin compiler or an Android test run.

Own Select Works is the separate toolbar control; other-profile/Gifts reading
selection remains in Menu, following Swift's placement. The real auth generation
is collected as a StateFlow immediately, avoiding a fabricated initial zero that
could cause an unnecessary first header read before the actual generation arrives.
