# Brief 3bt — posted work Edit tags

## iOS contract read before implementation

Read line by line, read-only, under `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`:
`Features/Writing/EditTagsView.swift`, `WritingDraftsView.swift` (`WritingTagsDestination`),
`WorkEditView.swift` (row, save gate and refresh), `Services/AO3WorkActions.swift`
(`loadEditTagsForm`, `editTags`, `submitWorkForm`, `loadWorkForm`),
`Services/AO3Client+Works.swift` (`parseEditTagsForm`), and
`Models/AO3WritingModels.swift` (`AO3EditTagsForm`, `AO3WorkTagSet.parameters`).

Only a posted work with an ID has the row; drafts edit their tags in the work form.
It reads GET `/works/{id}/edit_tags` once on opening, signed in, generation fenced.
Opening shows **Loading tags…**; failure shows UserFacingError's reason and **Try Again**.
Returning from a tag editor keeps the loaded form; retry is explicit.

Header: **AO3 Account**, **Edit tags**, `{trimmed title} · changes here do not touch the text`
(or the note alone for a blank title). Ordered sections:

- **Rating**: one selected served option; tapping it again leaves it selected.
- **Archive warnings**: served check rows, multiple selections. Footnote:
  **Choose at least one warning. Choose the first option if you don't want to name a specific warning.**
- **Categories**: served toggle rows, multiple selections.
- **Tags**: **Fandoms ∗** (required), **Relationships**, **Characters**, **Additional tags**.
  Inline chosen chips and Add push the existing WritingTagsEditor for that kind, with no
  options and immediate bound changes. Each field shows **None** or its count; the chip
  action is **Add**, with accessibility **Add {kind title}**. Chosen chips remove every
  exact occurrence and announce **Remove {name}**. Footnote:
  **As you type, AO3 suggests its canonical tags first. You can still post a tag that isn't canonical, and removing one here doesn't delete it from AO3.**

Warnings require at least one and fandoms are required by AO3; there is no local validation
or changed-value gate. **Save** disables only while saving; the fields stay editable. The editor's behavior is 3bh's
landed behavior, including whole-string Return, recent tags, autocomplete and Back.

Save requires a session, reads GET `/works/{id}/edit_tags` AGAIN, replaces that fresh
form's tags with the desired seven fields, then single-shot POST to the fresh captured
form action (normal `/works/{id}/update_tags`). Referer is `/works/{id}/edit_tags`.
Body in order: `authenticity_token` from fresh meta csrf-token (input fallback), `_method`
from fresh form if nonempty, nonempty `work[rating_string]`, repeated
`work[archive_warning_strings][]` and `work[category_strings][]` (each sends one empty
string if cleared), `work[fandom_string]`, `work[relationship_string]`,
`work[character_string]`, `work[freeform_string]` (trimmed chips joined by `, `; cleared
lists send empty strings), nonempty fresh `work[language_id]`, `update_button=1`.
Shared write request adds X-CSRF-Token, Referer, Cookie, UA and form Content-Type;
no AJAX headers, no write retry/coalescing. No text is modeled by this encoder.
Android must retain all served controls and replay the unmodeled successful controls;
an absent control must never be invented.

Verdict, in iOS code order: `workWriteError` -> rejected reason;
`workWriteNotice` -> the notice; 300…399 -> **Saved.**;
200…299 without evidence -> **AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.**;
otherwise -> **AO3 didn't accept the change.** Errors win over notices/redirects. The reference's decisive lines are:

```swift
if let error = AO3Client.workWriteError(in: body) {
    throw AO3WorkWriteError.rejected(error)
}
if let notice = AO3Client.workWriteNotice(in: body) { return notice }
if (300 ... 399).contains(status) { return "Saved." }
if (200 ... 299).contains(status) { throw AO3WorkWriteError.unconfirmed }
throw AO3WorkWriteError.rejected("AO3 didn't accept the change.")
```

Android uses the requested `writeErrorMessage`, including AO3's `div#error ul li`.
Save failure alert: **AO3 could not save the change**, reason, **OK**; fields remain.
Success calls onSaved then dismisses. No invented success banner.

The underlying iOS work form then reads `/works/{id}/edit` and replaces ONLY rating,
warnings, categories, fandoms, relationships, characters, additionalTags. Save is blocked
until this succeeds. Failure: **Reload tags before saving this work. ** plus the reason;
**Reload tags** is an explicit retry. iOS's loadWorkForm also makes an optional first-page
account collections read; Android's landed repository keeps that separate. This port needs
only tags and makes no collection read. Counts per successful opening/save: one opening GET,
one preparation GET, one POST, one work-form refresh GET (iOS additionally tries collections).
No refresh after refusal or unconfirmed. Autocomplete reads remain user-term-driven as 3bh.

## iOS wins over the brief

Save itself re-reads the tag form; it does not use the opening token/action. The row's
value is empty, with disclosure. Required fields do not disable Save. Bare 3xx confirms.

## Decided without asking

- Reuse AO3WorkForm, its parser, WritingWorkFormState and the landed WritingTagsEditor.
  Add a tags-only encoder branch and screen; no second editor or persistence model.
- Keep original demo work 995006; add one complete original tags-only HTML fixture beside
  its work form, plus local save handling in the existing DemoWorkSaves.
- Tests live beside work-form state/screen and demo tests; reuse existing recording clients
  and the independent browser-control oracle.
- Expose only 3bh's existing chip size/row helper within the module; use its lazy measured
  rows here. Reserve trailing-glyph width only for opted-in multiline SubjectChips.
- Keep fields editable during Save as iOS does; retain in-flight edits on every failed
  result. Let the owning work-form scope finish a dispatched Save after Back.
- Use **Refuse this tag** as the original local Additional-tags refusal trigger;
  no stored test account, limits or new fixture route.
- Do not repeat iOS's optional collection enrichment while refreshing tags: the existing
  Android loader doesn't do it, and none of the copied fields needs it.

## Work log

Clean start on `android/agent-codex-3bt`. Read requested briefs (including 3bh landing),
A4 triage, networking policy, project operational docs and actual reference symbols.
No task claim/commit/build because this brief overrides those operations. Implementation and offline tests are written for Claude’s build/test handoff.

## Open questions

None requiring input. The optional collections read is deliberately omitted as above.

## Implementation

`WritingEditTagsScreen.kt` draws the collected form state. Rating and warnings are
served check rows; categories use the existing toggle rows. The four tag fields show
counts as trailing content, removable wrapping chips and an Add chip. Chip flow rows
reuse 3bh's measured layout (now internal), each lazy, with `writingSuggestionPanel`
end caps and the existing form headings/footnotes/loading/failure style. Add opens the
existing `WritingTagsEditorScreen`; Back keeps its immediate bound changes and makes
no request. Light/Dark/Sepia/OLED all use the existing scope palette. There is no stock
Material Button or default-coloured progress ring. A multiline SubjectChip now reserves
width for its trailing remove glyph; default single-line chips retain their behavior.

`WritingWorkFormState` owns a separate tags opening through its existing read/save/edit
machinery, with an `editTagsOnly` mode. Its factory and the write method reject New/draft
forms before a tag GET. Opening attempts are remembered, including failures; only Try
Again requests another opening read. The screen registers only `ProvidePushedShellChrome`
for shell chrome, including after returning from a scrolled picker. The route's existing
session pin is taken on opening this editor so a session transition preserves the draft
and fences Save to its original generation.

`AO3WorkFormRepository.loadEditTagsForm` uses the existing authenticated GET and parser,
and verifies kind and work ID. The parser's title-input guard now recognizes a tags-only
page by its edit-tags address and served fandom box; action host/path/method validation
remain. No title, chapter or text field is fabricated for this page.

`AO3WriteRepository.editWorkTags` performs the single fresh preparation GET, parses its
meta/input token, method, action and language, then replaces only the desired seven tag
fields. The extracted `submitWork` preserves work-form Save's dispatch/verdict behavior;
tags use `writeErrorMessage` for validation/refusal and the existing work notice/3xx/
unconfirmed rules. Both reads and POST keep the original generation fence. Only this
tag encoder branch filters iOS modeled pairs to enabled served names; every other
served successful control replays from the captured snapshot, with its order, duplicates,
checkbox/radio/select/textarea behavior. No second HTTP path, retry loop or CSRF read.

After confirmation, the parent marks `tagsNeedRefresh`, performs one work-form GET and
copies only the seven fields through `withTagsFrom`. Its original served controls, text,
title, associations and publication edits remain. Fields remain editable while saving and a refusal retains edits made while waiting.
Save stays blocked after refresh failure;
Reload tags is explicit and an attempted failure does not turn into a reappearance retry.
The parent owns the Save coroutine: like iOS's Task, a dispatched save survives Back from
the tags page and still refreshes its owner on confirmation. Closing the whole work route
cancels preparation/late publication through the existing scope/session rules. There is
no change to reader-stored work records, backup, Room or text recovery.

Existing failure copy is reused from `workFormFailure`: expired session **Your AO3 session
expired. Please log in again.**; forbidden **AO3 refused the request (HTTP 403). Wait a while
before trying again.**; not found **That work or page couldn't be found (it may be restricted).**;
parse **AO3's page format wasn't what the app expected.**; rate limit **AO3 is rate-limiting
requests. Wait a moment and try again.**; server **AO3 had a server problem (HTTP N). Try
again shortly.**; unexpected HTTP **AO3 returned an unexpected response (HTTP N).**;
offline **You're offline. Connect to the internet and try again.**; timeout **AO3 took too
long to answer. Try again.**; TLS **Couldn't make a secure connection to AO3.**;
other transport **Couldn't reach AO3. Check your connection and try again.**; validation
shows AO3's exact reason. The existing Android generation fence says **Your AO3 session
changed. Reopen this form before saving.** No typed form is replaced after any failure.

## Local demo route and taps (not executed here)

Use the existing local-only demo extras `kudosDemoLibrary=true`, `kudosDemoSignedIn=true`
in airplane mode, with `nav:writing-work-posted-demo`. These are fixture session flags,
not an AO3 sign-in. The screen's Edit tags row is in Text, after Add chapter. Opening
loads `ao3_demo_work_edit_tags.html` for posted work 995006. No new navigation route.

- Success: Edit tags → a rating/warning/category choice, or Add Fandoms/Relationships/
  Characters/Additional tags → type a name → Return → Back → Save. The local notice
  confirms, the tags screen closes, and the owning work form re-reads its local edit
  answer and gets the new tags. Unsaved title/text edits underneath stay.
- Refusal: Add Additional tags → type **Refuse this tag** → Return → Back → Save.
  Local 422 uses `div#error` / `ul` / `li`, reason **Additional tags: Refuse this tag
  could not be saved.** The alert has iOS's title and OK; the chip and every other
  edit remain. Remove that chip and explicitly Save to make a new attempt.
- Clearing every warning returns **Please select at least one warning**; clearing
  fandoms returns **Fandom can't be blank**. These are local validation answers,
  not client limits or invented Save gates.
- Back without Save makes no POST and leaves the underlying form's tags alone.
  Reopening makes a new opening GET. Force-stop/relaunch resets interceptor edits.

`DemoWorkSaves` terminates both tags GET/POST locally, updates its own tag-form and work-form
HTML only after acceptance, and retains them unchanged after refusal. Existing browser
fixture lookup also knows the tags address; dynamic save answers belong to the native
interceptor. The posted title/content filler is original, as in the earlier work form.

## Tests written, not run

`WritingEditTagsTest`: tags-only fixture parsing; independent browser payload comparison
(per-name values/order, with the explicit iOS submit-label → `1` rule); independent literal
iOS encoder comparison for all seven changed kinds, all clears and whole comma-containing
chips; raw disabled/unchecked controls retained, absent/disabled modeled fields omitted,
unknown duplicates, checkbox twins, multiselect, textarea and form-associated replay;
one opening GET/no opening POST, cached return; fresh Save action/method/meta token/input
precedence/language and Referer/Cookie; notice/3xx/refusal/refusal-over-notice/unconfirmed/
fallback exact words; retained entire form after every verdict, read/transport/HTTP/
rate-limit/session failure; explicit opening retry; a second tap during preparation or
POST sends nothing; closed-model late reply ignored; in-flight edits survive refusal while the submitted snapshot stays exact; one confirmed refresh copies only
all seven tag fields while unsaved title/summary stay; failed refresh blocks parent Save
and remembers its attempt; explicit retry; signed out, New/draft, unsafe action and changed
session do not dispatch a POST (New/draft and signed out make no tag read).

`WritingEditTagsScreenTest`: actual posted-row and all four Add taps using the landed
editor, Return and Back, retained edits and restored shell chrome; actual rating/warning/
category/chip removal payload; refusal alert and retained input; flashless unconfirmed
copy; held Save disabled and screen retained until confirmation; post-confirmation owning
form reload; Back during dispatched Save still refreshes the owner; refused opening with
explicit Try Again/no Save; no draft row; four themes at 2× font scale, long warning labels
and a >150-character chip, no height overflow/ellipsized last line. Tests use tall
`w411dp-h2400dp`, patient 15-second waits and `@GraphicsMode(NATIVE)`.

Extended `DemoWorkFormTest`: real terminal demo interceptor, parser/encoder Save, success,
clears, changed tags returned by both edit endpoints, unchanged title/summary/notes/text,
422 refused reason with no server state mutation, bad token, restart reset and initial
browser/native fixture parity. A downstream interceptor throws before any socket.
Existing waiting-row test now covers only Add chapter; its Edit tags entry is implemented.
All clients in these tests are in-memory or terminate in local interceptors.

## Verification and handoff

Source/caller/signature review, `git diff --check`, changed/new-line whitespace,
conflict-marker, filename/scope scans (18 files) and standard-library HTML fixture
structure checks and a Kotlin delimiter/comment/string scan performed (no type check). There are 18 new writing test methods and one added demo
method, a source count rather than passing tests. No Gradle, Xcode, Kotlin compilation,
unit/Compose tests, emulator, screenshots, sign-in or AO3 contact. **Compilation, passing
tests, request/coroutine behavior and visual correctness need Claude's test run.**

Claude: build Android debug; run `WritingEditTagsTest`, `WritingEditTagsScreenTest`,
`DemoWorkFormTest` plus the existing `AO3WorkForm*`, `WritingWorkForm*`, work Save,
tag editor, demo block/browser and authenticated-write/session-dispatch suites, then
`:app:testDebugUnitTest`. Check the local demo in all four
themes, normal/large text, long-chip removal, every picker, keyboard, scrolled Back/chrome,
Save success/refusal, failed refresh/Reload tags and Back during Save. Human screenshot
review remains. No live AO3 test is authorized by this brief.

Changes are left uncommitted/unpushed on `android/agent-codex-3bt`, entirely in this
worktree. TASKS.md, iOS reference, backup format, Room schema and branch are untouched.
No helper scripts, stub or `.orig` files are left. Next step: Claude builds/tests/reviews
and commits. No owner answer is needed to continue that handoff.

## Landing note (Claude, 2026-10-08)

Landed on `android/redesign-parity`; the patch applied cleanly. Gate: 2,207 tests.

Changed on landing: a theme's name in a test (`Oled`, not `OLED`), and an older test that
pinned "the Edit tags row opens nothing" (`WritingTagsEditorScreenTest`), which is no longer
true.

Seen on the emulator (demo, posted work 995006): the row opens the screen; header, the
title in the subtitle, Rating and Archive warnings with their ticks, Save in the top row; a
changed rating and Save closes the screen back to the work form with no alert.

Not seen: the new rating on the work form's own row after the re-read (it was off screen),
the refusal ("Refuse this tag"), the four tag fields and their chips, Light, Sepia, OLED and
large text. The rating list shows AO3's empty first option ("Please select a rating") as a
row, because the choices are the served ones: check what iOS draws there.
Nothing here has run against AO3.
