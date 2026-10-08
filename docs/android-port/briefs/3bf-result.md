# Brief 3bf — work form screen, in memory only

## iOS contract, read before implementation

Reference: read-only `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Writing/WorkEditView.swift`, `WritingFormFields.swift`, `WritingTextEditor.swift`, `WritingDraftsView.swift`, `Services/AO3WorkActions.swift`, `Models/AO3WritingModels.swift`, and `Models/AO3Models.swift`.

### Header and ordered sections

Kicker: **AO3 Account**. New: **New work**; draft: **Draft**; posted: **Edit work**. Subtitle begins with the live title, or **Untitled**. Every unposted form (including new, because `isDraft == !isPosted`) appends ** · never posted**. Posted forms append ** · 1 chapter** or ** · N chapters** only when `chaptersPosted` is present. No saved-time or posted-date guess.

New and draft header footnote, word for word: “This draft isn't public yet. Options that apply only after posting will appear once you post it.”

Sections in order: **Required before posting** (new/draft) or **Required** (posted), **Tags**, **Association**, **Text**, **When posted** (new/draft) or **Publication** (posted), then **Post** (unposted) or **Delete** (posted with an ID).

### Every row

| Section | Label | Value and required mark | iOS destination/control |
|---|---|---|---|
| Required | Title | Literal title; placeholder Title; required ∗ | Inline trailing text field |
| Required | Rating | Matching served option title; unmatched empty “Select…”; unmatched nonempty raw value; no required star in code | Menu/inline single Picker, served `ratingOptions` |
| Required | Archive warnings | None or number selected; required ∗ | `WritingTagsEditor`, served `warningOptions` |
| Required | Fandoms | None or count; required ∗ | `WritingTagsEditor(kind: .fandom)` |
| Required | Language | Matching served title, same fallback as Rating; no star | Menu/inline single Picker, served `languageOptions` |
| Tags | Categories | None or count | `WritingTagsEditor`, served `categoryOptions` |
| Tags | Relationships | None or count | `WritingTagsEditor(kind: .relationship)` |
| Tags | Characters | None or count | `WritingTagsEditor(kind: .character)` |
| Tags | Additional tags | None or count | `WritingTagsEditor(kind: .freeform)` |
| Association | Series | Current names joined “, ”; None if neither current nor pending; “Adding NAME” if only pending; “CURRENT + NAME” if both | `WorkSeriesPickerView(series:newSeriesTitle:workTitle:currentSeries:)` |
| Association | Add to collections | None or selected-membership count | `WorkCollectionsGiftsView(collections:gifts:workTitle:parentWorkCount:)` |
| Association | Gift recipients | None or count | Same collections/gifts screen |
| Association | Co-creators | None if zero pseuds and no byline; pseud count otherwise; “N + 1 invited” for nonempty byline | `WorkCreatorsPickerView(creators:workTitle:)` |
| Association | Inspired by | None if parent URL empty, otherwise 1 (title alone does not count) | `WorkParentWorkPickerView(parentWork:languageOptions:)` |
| Text | Summary | Empty/Set; nonempty markup-stripped words appear under label instead of Set (two lines normally) | `WritingTextEditor` |
| Text | Beginning notes | Empty or Set | `WritingTextEditor` |
| Text | End notes | Empty or Set | `WritingTextEditor` |
| Text, unposted only | Work text | Empty or Set; no required star | `WritingTextEditor`; creates chapter model if absent when text returns |
| Text, posted with ID | Chapters | Posted count or empty | `WritingChaptersView`; marks publication refresh after a write |
| Text, posted with ID | Add chapter | Empty | `WritingChapterDestination`; marks publication refresh |
| Text, posted with ID | Edit tags | Empty | `WritingTagsDestination`; marks tag refresh |
| Text | Work skin | Matching title; blank option is named Default if blank label, or prepended if absent; otherwise normal choice fallback | Menu/inline single Picker, `workSkinOptions` |
| Publication, posted only | Chapters posted | “N of” (N defaults to 1), trailing editable total, placeholder ? | Changes `chapterTotal` only |
| Publication, posted only | Work is complete | On iff total equals posted count (default 1) | On sets total to posted count; off sets empty; does not change `isChaptered` |
| Publication | Set a different publication date | `backdate` | Turning on fills today only when an existing chapter's year is empty |
| Publication, backdate and chapter present | Publication date | Gregorian chapter year/month/day, invalid/absent falls back to today | DatePicker, 1950-01-01 through today; writes unpadded year/month/day |
| Publication | Only show to registered users | `restricted` | Toggle |
| Publication | Enable comment moderation | `moderatedCommenting` | Toggle |
| Publication | Who can comment | Matching served option title, normal choice fallback | Menu/inline single Picker, `commentPermissionOptions` |
| Post, unposted | Post work; Preview on AO3; Delete draft (ID only) | No values | Confirmation; server preview; delete confirmation |
| Delete, posted with ID | Delete work on AO3 | No value, destructive | Delete confirmation |

All single/multiple tag choices are the labels/values/order AO3 served. No rating, warning, category, language, comment-permission or skin catalog lives in the app. Skin's Default sentinel is the iOS exception.

Text recovery arguments, quoted from iOS: `account: auth.username ?? ""`; `target: "work:\(workID)"` or **"work:new"**; fields **"summary"**, **"notes"**, **"endnotes"**, **"content"**, respectively. Each binds directly to the form's field, including checkpoint and Done/leave. Do not use `chapter:*` or a demo-only account for this screen.

### Footnotes, top button, alerts and leaving

Other footnotes word for word:

- “Tags can also be edited separately from the work text.”
- Posted Publication: “AO3 marks a work in progress when its total chapters are higher than the number posted. Complete sets both numbers to the same value.”
- Existing unposted Post: “AO3 deletes an unposted draft 30 days after it is created.”

Top button: **Save**, update for posted, saveDraft otherwise, disabled during saves/posts or either required refresh. Normal navigation Back is provided by the app.

Alerts: **AO3 could not save the change**, message from `UserFacingError`, **OK**; **Post this work?**, **Post work** if nothing missing, otherwise **Fill in what is missing**, plus **Cancel**. Valid post message: “Posting notifies your subscribers and can't be undone. You can edit a posted work, but you can't return it to a draft.” Missing message: “One thing is missing” / “Two things are missing” / “N things are missing”, then “. Add LIST. AO3 requires it” / “both” / “all of them”, then “. Posting also notifies your subscribers and can't be undone. You can edit a posted work, but you can't return it to a draft.” LIST maps Title→a title, Rating→a rating, Archive Warning→an archive warning, Fandoms→a fandom, Language→a language, Work Text→the work text and uses localized list joining. Delete dialog: **Delete this draft?** with **Delete**, or **Delete this work?** with **Delete on AO3**; **Cancel**; message is AO3's parsed `cautionText`, not invented app text.

Refresh failure alert message prefixes: “Reload chapter totals before saving this work. ” / “Reload tags before saving this work. ” + error. Session-write rejection: “Your AO3 session changed. Reopen this form before saving.”

`WorkEditView` has no unsaved-changes flag, exit interception, Save/Discard prompt or automatic save. Back discards the in-memory form. Text-editor leaving first checkpoints into its binding and retains local recovery; the form does not clear recovery. Android follows that behavior.

Loader: header New work or Edit work, no subtitle; spinner without invented loading sentence. Failure title **Couldn't load from AO3**, button **Try Again**. Initial signed-out: **Log in to AO3 first.** Expired session: **Your AO3 session expired. Please log in again.** iOS AO3Error has no dedicated overloaded case: a 503 is **AO3 had a server problem (HTTP 503). Try again shortly.** Android's existing typed Overloaded uses that iOS server wording for 5xx, its rate-limit wording for 429, and the parse wording for an overloaded HTML page returned with 200 (iOS has no dedicated overload parser state). Its heading is the same failure title. Other iOS words: forbidden **AO3 refused the request (HTTP 403). Wait a while before trying again.**; not found **That work or page couldn't be found (it may be restricted).**; parse **AO3's page format wasn't what the app expected.**; rate limited **AO3 is rate-limiting requests. Wait a moment and try again.**

### AO3 operations for the Save brief (reference only)

1. Opening requires a session; GET `/works/new` or `/works/ID/edit`, then iOS optionally GETs that account's collections page 1 and merges collection offers. The loaded form survives returns from pushed screens in the same generation. Android here deliberately uses only 3bb's one form GET, with no collections enrichment.
2. Save captures/fences session generation; `saveWork` requires login; `form.parameters(.update / .saveDraft)` is posted once to the served action, with CSRF and referer equal to action. Success closes form and preview. No auto retry/coalescing. Post uses that same path with **post_button**, never the chapter's post_without_preview_button; validates required fields and asks first.
3. Delete tap: GET `/works/ID/confirm_delete`, then GET `/works/ID` for missing stats, then show parsed caution. Confirm calls deleteDraft/deleteWork, which loads those implications again, and posts the served deletion form once with its method override and token. Success dismisses; local reader data is not deleted by this view.
4. Preview on AO3: generation check; POST `parameters(.preview)` to action. AO3 can create a draft from a new form; parse preview, adopt returned work ID/action/token/override before pushing `WritingPreviewView`. Its Post/Update uses the same perform path; prevents creating a duplicate new work. It renders returned HTML without remote image loads.
5. After a pushed chapter screen writes: GET edit form (and optional collection enrichment); replace total, posted count, chaptered flag and chapter 1. Preserve a locally changed publication date by comparing against the last loaded chapter; otherwise take the fresh date. Other unsaved fields stay. Save blocked until refresh succeeds; **Reload chapter totals** retries.
6. After Edit tags writes: same edit-form read; replace only rating, warnings, categories, fandoms, relationships, characters, additional tags. Other edits stay. Save blocked until successful; **Reload tags** retries. Tag picker autocomplete and association reads belong to their later briefs.

## iOS wins over the brief

There is no chapter-title/chapter-summary row in this work screen, and no anonymous or collection-inbox switch even when their model fields exist. Those fields remain untouched. New forms also get the draft footnote, Required before posting and When posted. The posted demo is metadata-only (`chapter == null`), so its served date survives untouched in raw replay but no date row appears. These are code-derived decisions, not omissions to fill with invented UI.

## Decided without asking

- Reuse the three existing 3bb fixtures; no new HTML, seeded recovery copy or test data catalog.
- Put screen/state/tests in `writing/`, named `WritingWorkForm*` to avoid package collisions.
- Three separate debug-only routes, each with no query parameters; require existing local demo mode before instantiating the form repository, so accidental non-demo debug navigation cannot contact AO3.
- Pending rows show their iOS values with no click action or disclosure. Omit Save, the entire Post/Delete groups and their draft-expiry footnote. The separate-tags footnote stays: it belongs to the retained Tags group and describes a later editor, not a removed server write control.
- No unsaved-change dialog; reuse editor checkpoints/recovery without clearing or changing stored reader data.
- A token-colored lazy Gregorian component picker uses iOS's date range; no fixed-height calendar at accessibility sizes. Date choices follow `AO3PublicationDate`, rather than the fixture's abbreviated date-select options, as iOS does.
- Tests reuse `workFixture`; changed-text literals include whitespace, Unicode and HTML. The empty-year case removes only existing date controls from a test-only DOM, rather than adding a new stored fixture. Compose tests use a tall native-graphics window and an in-memory client whose POST throws.

## Work log

Clean initial tree on `android/agent-codex-3bf`. Read the specified briefs including landing notes, architecture §§0/8.7, project docs, real Swift/Kotlin symbols. User's brief overrides TASKS claims, commit/push/branch/build instructions. No Gradle, Xcode, sign-in or AO3 traffic.

## Implementation and local demo routes

`WritingWorkFormState.kt` owns a generation-scoped form and edits only modeled fields using immutable copies. Its load guard retains the form across returns and ignores repeated loads; only an explicit failure retry reads again. Closing/session change rejects late edits. Existing 3bb repository/parser/encoder are unchanged. `WritingWorkFormScreen.kt` uses the account subject header, rule headers, SettingsPanel, SubjectFormRow, separators, plain collection-form title field and SubjectToggle. Fixed-size section panels sit in a lazy page; every potentially long choice list is lazy. Summary stripping reuses `core.strippingHtml` off-main; chapter content is never rendered on the form. Editors use the existing 3bd screen and deliver checkpoints and Done to the same state method. There is no Save/POST path, association read, autosave request, preview request or local reader-data mutation.

The closed warning/category picker is a pushed chooser with iOS's **Choose**, **None chosen** / **N chosen**, served rows and trailing checkmarks; Back retains changes. Single-choice menus use a token-colored modal lazy list. For publication dates, a token-colored native Compose sheet exposes Gregorian Year/Month/Day selectors, each lazy; it writes immediately like iOS's binding, uses iOS's 1950-through-today bounds, and has no Save. Calendar component choices are generated from that iOS range, not AO3's abbreviated fixture selects: iOS itself uses DatePicker rather than those served options. This platform presentation was decided without asking to prevent a fixed-height month calendar from clipping at accessibility size.

Every new Text/TextStyle has a line height. No shared component's typography was changed. Accessibility controls stack, labels/values wrap, and the form and pushed chooser reserve **statusBars + 76dp**. Palette: `tokens.scopePalette` throughout; no Material card/chip/text-field decoration. Only the text editor supplies its existing icon toolbar; the form and closed-list chooser have no new top action.

Routes (single argument each, no `&`):

- `nav:writing-work-new-demo`
- `nav:writing-work-draft-demo` — 995001
- `nav:writing-work-posted-demo` — 995006

Example commands for Claude's local demo pass; not executed here:

```sh
adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --ez kudosDemoSignedIn true --es kudosDebugRoute nav:writing-work-new-demo
adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --ez kudosDemoSignedIn true --es kudosDebugRoute nav:writing-work-draft-demo
adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --ez kudosDemoSignedIn true --es kudosDebugRoute nav:writing-work-posted-demo
```

Each registration is under BuildConfig.DEBUG and checks existing `DemoNetwork.isActive` before constructing the repository. Without local demo isolation the route immediately closes. Signed-out local demo shows the failure page with zero reads. Production draft taps and New Work still use `WritingWorkDestination.url()` and the browser; neither that type nor `WritingDraftsScreen.kt` changed.

### Served demo picker inventory

These are read from the existing HTML, never app constants:

| Picker | Choices, in served order | New / draft / posted value |
|---|---|---|
| Rating | blank: Please select a rating; Not Rated; General Audiences; Teen And Up Audiences; Mature; Explicit | blank / Teen And Up Audiences / same |
| Archive warnings | Choose Not To Use Archive Warnings; Graphic Depictions Of Violence; Major Character Death; No Archive Warnings Apply; Rape/Non-Con; Underage | none / No Archive Warnings Apply / same |
| Categories | F/F; F/M; Gen; M/M; Multi; Other | none / Gen, Multi / same |
| Language | blank: Please select a language; 1: English; 2: Español; 3: 日本語 | blank / 1 / 1 |
| Who can comment | enable_all: Registered users and guests; disable_anon: Only registered users; disable_all: No one | enable_all / enable_all / disable_anon |
| Work skin | blank: Default; 55: Tidal Ink & 星; 66: Mill Ledger | blank / blank / 55 |

New subtitle: **Untitled · never posted**. Draft: **Lanterns Above the Mill · never posted**. Posted: **The Cartographer’s "Second" Tide & 星 · 2 chapters**. Draft and posted tag counts are warnings 1, fandoms 2, categories 2, relationships 2, characters 2, additional tags 3. Posted Series **Lantern Voyages**, collections **2**, gifts **1**, co-creators **1** (raw hidden coauthors do not affect iOS's displayed count), Inspired by **1**, Chapters **2**, total **5**, complete off, backdate on, registered-only off, moderation on, no date row because chapter is absent. New/draft have no posted chapter totals or completion row; new text rows Empty, draft text rows Set except Summary's stripped preview. No chapter title is drawn for First Lantern; it remains in the payload unchanged.

## Offline tests written, not run

`WritingWorkFormStateTest`: one read per opening/repeated-load and return guards, new openings, signed-out no reads including retry, title and every single choice, rating clearing, warnings/categories tap order/removal/clear sentinel, invalid option refusal, visibility/moderation/backdate switches, complete/total binding, every available editor field checkpoint/Done/leave including empty and exact HTML, recovery target/field/account names, Gregorian date parts/range and blank-year backdate default, metadata-only date preservation, late callback/session cancellation, failure words/explicit retry. Every delta compares the full **ordered** untouched payload outside the exact named fields for **all six submit actions**, checks the changed values verbatim, and retains the original `servedControls` snapshot (including unknown fields, hidden coauthors, chapter IDs and dates).

`WritingWorkFormScreenTest`: the actual content/state used by the screen for all three forms, sections/labels/values/flags, omitted controls, all pending rows without click actions, title + single choice + switch interaction payload, served multiple-choice push/Back preserving title and payload, date-sheet interaction, posted total/complete interaction, real 3bd editor Done/Back raw text handback retaining title, leaving without prompt, Light/Dark/Sepia/OLED at double font scale with text-layout overflow assertions. Public wrapper tests cover held loading, busy failure/retry, signed-out no reads and removal of private form on logout. Tall `w411dp-h2400dp`, 15-second waits, `@GraphicsMode(NATIVE)`, and setup's repository `parseDispatcher = Dispatchers.Unconfined`. All clients are in-memory; POST increments a counter then throws. Existing editor tests own timer scheduling/recovery IO; this suite adds the form binding and return path.

`WritingWorkFormRoutesTest`: three query-free demo routes' pushed header/tab-bar/title policy and exact unchanged draft/new browser destination URLs. Existing `WritingDraftsScreenTest` still tests actual draft tap/New Work, and `DemoWorkFormTest` still tests the real local interceptor with a socket-blocking downstream interceptor.

## Verification and handoff

Performed here: source/caller review against the real Swift and Kotlin APIs, inspection of the cached Material3 API signatures, `git diff --check` and whitespace checks including new files (clean), duplicate top-level type scan of `writing/` (none), write-dispatch scan (none added), and changed-file checks for TASKS/drafts (unchanged). There are **29 written test methods**: 10 state, 17 screen, 2 route. No passing-test count is claimed.

Written behavior is not an executed result. No Gradle, Xcode, Kotlin compilation, emulator or screenshot pass was run. Claude must build Android debug and run `:app:testDebugUnitTest`, particularly these three suites, the existing 3bb form/repository and demo-network tests, 3bd editor/checkpoint/recovery tests, drafts destination tests and shell navigation tests. Compile, payload parity, request counts, editor timing/return behavior, tests and visual correctness all need that run/pass before claiming done. No live AO3 work is authorized.

Manual pass still owed: three local demo routes, theme and accessibility screenshots (including title and selected values), every picker/toggle/date change, opening and leaving each text field, checkpoint before Done, recovery after app kill, Back discarding only in-memory changes while retaining recovery, no second GET on return, pending rows opening nothing, both existing drafts browser destinations. Review publication date sheet layout and closed-list chooser at largest font scale on a real small phone. Do not approve UI without seeing it.

## Open questions

None. iOS-vs-brief decisions and platform picker/fixture/naming decisions are listed above. No TASKS.md edit, commit, push, branch switch, sign-in, AO3 contact, iOS edit, Room schema or backup-format change. No stub, helper script or `.orig` file was created. Work remains uncommitted in this worktree for Claude.

**Landing note (Claude, 2026-10-07).** Landed with a fix in the shell, one in the editor and
two test corrections. Gate green (1,886 tests). Nothing in the app opens this screen: three
debug routes only. A draft tap and New Work still open the browser.

**Read against iOS:** the sections and their order, the three headers and subtitles, which
rows carry the required mark, the footnotes kept and left out, and the recovery key the text
rows pass to the editor (`work:<id>` or `work:new`; `summary`, `notes`, `endnotes`,
`content`): the same as `WorkEditView.swift`, so a copy written on one screen is found by the
other. One GET per opening, nothing sent.

**Found on the emulator and fixed.**

1. **The editor opened from the form had no top buttons: no Back, no Undo, no Done.** The
   shell hides its top row when a page is scrolled down, per route. The Text rows are below
   the fold, so the writer has always scrolled before opening the editor, and the editor,
   which takes the form's place inside the same route, inherited a hidden row with nothing to
   scroll to bring it back. The tag set's Add tags screen (3bg) and this form's choosers had
   the same fault. Fixed where every screen passes: `PushedShellChrome` now says which screen
   holds the row (`holder`), and the shell shows the row again whenever that changes
   (`ShellChromeState.reveal`, `MainScaffold`). Two tests. Seen on the emulator: scrolled
   form (row hidden), End notes opened (Back, Preview, Undo, Redo, More, Done all there),
   Done (the form has Back again), the warnings chooser (Back there).
2. **The keyboard stayed up over the form after Done.** The editor now puts it away on Done
   and on Back. **Not seen on the emulator** (the Mac ran out of memory before the check).

**Test corrections.** The large-text check used `hasVisualOverflow`, which reports a width
overflow for a short label narrower than its row. And one test expected Android to send no
rating after the writer picks the blank line; the encoder (3bb, by decision) then sends the
rating control back as AO3 served it. iOS sends nothing. AO3 keeps the rating it had either
way, so on neither app does choosing the blank line clear a rating: the Save brief should
know this.

Seen on the emulator in airplane mode: the posted work (Dark; all sections, the title with
quotes and non-Latin letters, Series, collections, gifts, co-creators, Inspired by, chapters
"2 of 5", the switches, "Who can comment"), the draft (Light; header and footnote), the new
work (Dark; "Untitled · never posted", "Please select a rating", every count "None"); Rating
changed to Mature; Archive warnings' chooser, a second warning ticked, the row's count going
to 2; Beginning notes opening the editor with the note's text, typing, and the recovery sheet
offering that text on the next opening. Not seen: the date picker, the single-choice menus
other than Rating, Work text, Sepia, OLED, large text (all in tests).

Left for polish (P3): the title field shows the start of a long title cut at the row's edge;
Rating and Language open a menu but carry no mark that they do.
