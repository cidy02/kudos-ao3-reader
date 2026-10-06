# Brief 3bb — work-form foundations

## Inventory: iOS payload changes and data-loss risks

**Risk: an ordinary language or work-skin select without an explicit selected
attribute is read as empty by iOS, although a browser sends its first option.
iOS then sends an empty language or skin value. Its parent-language reader also
ignores selects. These paths can blank untouched metadata. Hidden co-creator
arrays, unknown controls and repeated hidden fields are not losslessly preserved
by iOS; whether an omitted association is retained by AO3 was not verified here.**

The table below comes from AO3WorkForm.parameters, AO3WorkTagSet.parameters,
parseWorkForm and its helpers. It covers the inspected iOS new/edit fixtures,
all relevant parser/encoder branches and forward-compatibility control classes.
It does not claim to enumerate every live AO3 form variant: no page was fetched.
No iOS file was changed. No row claims a live-tested server outcome.

| Control / condition | Browser sends | iOS sends | Judgment and basis |
|---|---|---|---|
| work[language_id], no explicitly selected option | First enabled option | Empty | **Risk: blanks/rejects untouched language.** Ordinary parseSelect lacks the browser fallback; parameters always emits it. |
| work[work_skin_id], no explicitly selected option | First enabled option | Empty | **Risk: clears an untouched skin.** iOS explicitly documents empty as clearing the old skin. |
| work[parent_work_relationships_attributes][0][language_id], rendered as select | Selected/default option | Empty when parent branch active | **Risk: blanks inspired-work language.** parseParentWork reads only inputValue. |
| work[author_attributes][coauthors][], if served hidden | Every hidden ID | Nothing | **Risk: no preservation of served co-creator state.** No explicit branch, and hidden arrays are skipped; server deletion behavior is unverified. |
| work[collections_to_remove][], if served | Repeated successful values | Nothing | **Risk: served association/removal instructions omitted.** No explicit branch, and hidden arrays are skipped. |
| Other unknown hidden array | All successful pairs in order | Nothing | **Risk: future association/state controls disappear.** All hidden names ending in [] are skipped. |
| Unknown visible input | Served successful value | Nothing | **Risk: untouched field omitted.** No generic visible-control carry. |
| Unknown textarea | Served text | Nothing | **Risk: untouched long text omitted.** Only named textareas are read. |
| Unknown single select | Selected/default value | Nothing | **Risk: untouched choice omitted.** Only named selects are read. |
| Unknown multiple select | All selected successful values | Nothing | **Risk: untouched selections omitted.** No generic select carry. |
| Unknown checkbox/radio | Checked successful values and any hidden twin | Only first non-array hidden twin, if any | **Risk: checked unknown flag may be reset to hidden off value.** Carry cannot see the visible choice. |
| Duplicate non-array hidden name, not overridden | Every pair | First pair only | **Risk: multiplicity/last-value semantics change.** parseCarryHiddenFields retains first, whereas a scalar browser payload's last value wins. |
| work[rating_string], empty/no explicit selection | Empty/implicit first value | Omitted unless hidden carry supplies it | Existing empty rating omission requests no update; **risk for required new-work validation or a meaningful implicit default.** tagSet emits only nonempty rating. |
| work[fandom_string] | Original comma string | Trimmed nonempty entries joined with comma-space | No effect for exercised nonempty tag entries: comma is the form's delimiter, not CSV quoting; iOS AO3TagListDiff documents this representation. |
| work[relationship_string] | Original comma string | Same list normalization | No effect for exercised delimiter/spacing cases for the same reason. |
| work[character_string] | Original comma string | Same list normalization | No effect for exercised delimiter/spacing cases for the same reason. |
| work[freeform_string] | Original comma string | Same list normalization | No effect for exercised delimiter/spacing cases for the same reason. |
| work[collection_names] | Original comma string | Joined selected offer names | No effect for unchanged selected names: the field represents comma-separated collection identifiers. Picker changes are intentional. |
| work[recipients] | Original comma string | Joined gift names | No effect for unchanged entries: iOS treats this as a comma-separated recipient list. |
| work[archive_warning_strings][] with hidden blank and checked choices | Blank plus repeated choices | Choices only; one blank if none | Blank is the form's clear/no-choice sentinel; iOS's tag encoder comments explain this. No choice-state change intended, but Rails receives a different array. **Not normalized away by tests**; a direct branch test pins exact iOS output. |
| work[category_strings][] with hidden blank and checked choices | Blank plus repeated choices | Choices only; one blank if none | Same sentinel purpose, evidenced by ReviewFindingRegressionTests.clearingEveryCategoryPostsAnEmptyValue. No extra array normalizer is used. |
| work[backdate] | Hidden 0 and checked 1 | One 0/1 | No effect with ordinary twin order: Rails takes the last scalar value. |
| work[restricted] | Hidden 0 and checked 1 | One 0/1 | No effect with ordinary twin order for the same scalar reason. |
| work[moderated_commenting_enabled] | Hidden 0 and checked 1 | One 0/1 | No effect with ordinary twin order for the same scalar reason. |
| work[anonymous], when present | Hidden 0 and checked 1 | One 0/1 | No effect with ordinary twin order; absent input means no modeled emission. |
| work[collection_inbox], when present | Hidden 0 and checked 1 | One 0/1 | No effect with ordinary twin order for the same scalar reason. |
| work[parent_work_relationships_attributes][0][translation] | Hidden 0 and checked 1 | 1 in active checked parent branch; otherwise hidden 0 if carried | No effect for ordinary twins with active parent. **Risk outside active-parent branch:** hidden carry may send 0 without visible 1. |
| work[series_attributes][id], new title and no selection | Empty select alongside title | Omitted unless hidden carry supplies it | No effect for blank select: iOS documents Work#series_attributes as adding a series; existing currentSeries is separate and not replaced. |
| work[series_attributes][title], selected membership | Empty alternative title plus ID | Title omitted unless hidden carry supplies it | No effect for empty alternative; **risk for nonempty served alternative title**, which is discarded. |
| work[series_attributes][title], no selected membership | Original title | Trimmed title, or blank for whitespace-only | Empty/whitespace-only deliberately creates no series per iOS test. **Risk for literal title whitespace**, which changes. No series-title normalizer is allowed. |
| Parent URL/title/author/language with URL and title empty | Empty controls, possibly nonempty subordinate values | Omitted unless non-array hidden carry supplies them | No effect for wholly empty parent; **risk for nonempty subordinate fields**, ignored without URL/title. |
| work[comment_permissions], no checked radio | No selected radio value | Omitted unless hidden carry supplies it | No effect for ordinary absent selection: neither browser nor iOS requests a replacement. |
| work[author_attributes][ids][], hidden blank and selected pseuds | Blank plus selected IDs | Selected IDs only | Blank is a no-ID sentinel; choices are preserved. Exact Rails array differs, so tests add no array normalizer. |
| work[author_attributes][byline], empty | Empty text | Omitted unless hidden carry supplies it | No effect for empty add-co-creator byline: no new co-creator requested. Replacement-mode server behavior has not been verified. |
| work[chapter_attributes][published_at(1i/2i/3i)], chapter absent or year empty | Successful served dates | Omitted unless non-array hidden carry supplies them | **Risk: metadata-only posted form dates can be ignored.** Android posted fixture exercises this shape and preserves dates via replay; server effect is untested. |
| utf8 | Served checkmark | Nothing | No effect on work attributes: Rails encoding sentinel outside work parameters; form already declares UTF-8. Android replays it. |
| front-notes-options-show | Checked on | Nothing | No effect on saved notes: presentation toggle; work[notes] explicitly sent. |
| end-notes-options-show | Checked on | Nothing | No effect on saved endnotes: presentation toggle; work[endnotes] explicitly sent. |
| series-options-show | Checked on | Nothing | No effect when association ID/title sent: presentation toggle. |
| parent-options-show | Checked on | Nothing | No effect when actual parent fields sent: presentation toggle. |
| chapters-options-show | Checked on | Nothing | No effect on supplied total: presentation toggle; work[wip_length] always sent. It also feeds isChaptered. |
| Chosen save_button | Served button label | 1 | No effect on draft action selection: named submit presence selects action in iOS's form workflow. |
| Chosen preview_button | Served button label | 1 | No effect on action selection for the same named-submit reason. |
| Chosen post_button | Served button label | 1 | No effect on action selection; iOS's work-post regression explicitly requires this name. |
| Chosen update_button | Served button label | 1 | No effect on action selection for the same named-submit reason. |
| Chosen edit_button / post_without_preview_button, when provided | Served button label | 1 | Same representation, but not offered by the three fixtures. **Risk using PostWithoutPreview to post a work:** iOS's regression says it is a chapter action and works require post_button. No Android dispatch exists. |
| Modeled controls missing or disabled on served page | Not successful | Several modeled fields still emitted, often empty/default | **Risk: iOS can replace values for fields it never read.** The skin clear comment proves empty is meaningful. Raw Android data retains absence/disabled state; known encoder rules follow iOS. |
| Modeled textarea whitespace | Browser textarea value | SwiftSoup text() result | No proven difference claimed. Android uses wholeText and tests exact multiline HTML; suspected SwiftSoup discrepancies require its runtime suite. |
| authenticity_token, meta/form token differ or meta has outer whitespace | Hidden token verbatim | Trimmed nonblank meta token preferred | **Risk of refusal with inconsistent/stale tokens**, without changing work data. Preference/trim is in AO3Client.parseCSRFToken. Android reproduces it and retains the raw hidden token. |
| _method, served empty | Empty pair | Omitted | No meaningful override is selected; form method is POST. Android retains the omitted served pair via replay. |
| Named chapter content blank plus separate textarea#content | Named blank and fallback under its own name | Fallback used for modeled chapter content | **Risk of replacing blank content with another control's text.** iOS uses ifEmpty; Android reproduces it and keeps both controls. |

The selected no-effect judgments follow the purpose of the control or iOS's own
regression/comment evidence. Fixture warning/category hidden blanks occur only
when no choice is checked; checked-plus-hidden-blank cases are tested directly
against iOS's branch, not disguised as scalar Rails equivalence. Literal tag
commas remain delimiters even inside quote characters.

### Served option inventory

Read from the fixtures; these values are never hard-coded in production.

| Field | iOS reference new/edit fixtures | Android demo fixtures |
|---|---|---|
| Rating | New: blank, General Audiences. Edit: blank, Not Rated, General Audiences, Teen And Up Audiences, Mature, Explicit | All six edit choices; blank New, Teen And Up Audiences on edits |
| Warnings | New: Choose Not To Use Archive Warnings. Edit: that, Graphic Depictions Of Violence, Major Character Death, No Archive Warnings Apply, Rape/Non-Con, Underage | All six; none New, No Archive Warnings Apply on edits |
| Categories | Edit: F/F, F/M, Gen, M/M, Multi, Other; F/M and M/M selected. New: absent | All six; none New, Gen and Multi on edits |
| Language | Blank, 1=English; edit also 2=Español | Blank, 1=English, 2=Español, 3=日本語; explicit blank New, English on edits |
| Pseuds | Edit: 101=mainpseud selected, 202=altpseud. New: absent | 101=AO3_Reader selected, 202=LanternMaker |
| Series | Edit: blank, 77=Water selected, 88=Case Files. New: absent | Blank selected; 77=Lantern Voyages, 88=Mill Maps; Current Series is a separate link to 77 |
| Comment permissions | Edit: enable_all, disable_anon selected, disable_all. New: absent | Same choices; enable_all New/draft, disable_anon posted |
| Work skins | Absent in reference fixtures | Blank=Default, 55=Tidal Ink & 星, 66=Mill Ledger; 55 selected posted |
| Date parts | Absent in base reference fixtures; iOS tests inject 2025/2024, 2/3, 6/7, selecting 2024-3-7 | New/draft: 2026/2024/2019, 3/10/11, 5/7, selecting 2026-10-5; posted: 2026/2019, 10/11, 5/7, selecting 2019-11-5 |
| Collections | Text nanami_week on edit; no select | Posted text names; test-injected unknown collection select has ink_atlas/mill_exchange, selecting ink_atlas |

Labels/values/order/selections are HTML data, not application allow-lists.
Parent language follows iOS's input-only rule, while served select options also
remain in parentLanguageOptions/raw data.

### Source inventory

Also read AO3Client.swift.parseCSRFToken and WorkEditView submit selection: meta token is trimmed/preferred; Save is Update for posted works and SaveDraft for drafts; work Post uses Post.

Read-only reference root: `/Users/cidy02/kudos-ios-polish/`.

- `kudos-ao3-reader/Models/AO3WritingModels.swift`: field constants,
  `AO3WorkForm`, nested value types, `AO3WorkTagSet.parameters`,
  `AO3TagListDiff.split/joined`, and `AO3WorkForm.parameters(submit:)`.
- `kudos-ao3-reader/Services/AO3Client+Works.swift`: URLs, `workFormHTML`,
  `parseWorkForm`, and the form/control helpers.
- `kudos-ao3-reader/Services/AO3WorkActions.swift`: form loads, `saveWork`,
  `previewWork`, `loadWorkForm(at:)`, `submitWorkForm` and preview construction.

The parser reads the following controls. Options are served data; their concrete
values are not hard-coded in the reference parser. All encoding rules in this table
apply to every submit action; only the chosen submit pair differs. “Always” means
the encoder emits a pair even if that control was absent in the served form.

| Form name | Kind / served options | `AO3WorkForm` destination | iOS encoding, including empty values |
|---|---|---|---|
| `authenticity_token` | Hidden; page token parser also consulted | `csrfToken` | Always the modeled token |
| `_method` | Hidden | `httpMethodOverride` | Sent only when nonempty |
| `work[title]` | Text | `title` | Always verbatim, including empty |
| `work[rating_string]` | Single select, all served options | `rating`, `ratingOptions` | Omitted if empty; otherwise selected value |
| `work[archive_warning_strings][]` | Multiple checkboxes, served values/labels | `warnings`, `warningOptions` | Repeated selections, or one empty pair if none; no additional hidden blank with selections |
| `work[category_strings][]` | Multiple checkboxes, served values/labels | `categories`, `categoryOptions` | Same empty/selection rule as warnings |
| `work[fandom_string]` | Comma-separated text | `fandoms` | Always trimmed nonempty entries joined with `, `, including empty result |
| `work[relationship_string]` | Comma-separated text | `relationships` | Same list rule |
| `work[character_string]` | Comma-separated text | `characters` | Same list rule |
| `work[freeform_string]` | Comma-separated text | `additionalTags` | Same list rule |
| `work[language_id]` | Single select, all served options | `languageID`, `languageOptions` | Always selected value, including empty |
| `work[summary]` | Long text | `summary` | Always parsed textarea text, including empty |
| `work[notes]` | Long text | `notes` | Always parsed textarea text, including empty |
| `work[endnotes]` | Long text | `endnotes` | Always parsed textarea text, including empty |
| `work[collection_names]` | Comma-separated text | `collectionNames`, synthesized selected `collections` | Always joined selected offer names when offers exist, otherwise joined `collectionNames`; empty result sent |
| `work[recipients]` | Comma-separated text | `gifts[].name` | Always joined names, including empty |
| `work[series_attributes][id]` | Single select; positive integer options retained as memberships | `series[].seriesID/title/isSelected` | First selected membership's ID; if none and new title blank, empty pair; omitted if new title nonblank |
| `work[series_attributes][title]` | Text | `newSeriesTitle` | Trimmed nonblank title only if no selected series; empty pair if neither; omitted when a series is selected |
| `work[parent_work_relationships_attributes][0][url]` | Text; input-name `[url]` fallback | `parentWork.url` | Sent with other parent text fields only if URL or title nonempty |
| `work[parent_work_relationships_attributes][0][title]` | Text; input-name `parent_work` fallback | `parentWork.title` | Same parent branch; empty included within that branch |
| `work[parent_work_relationships_attributes][0][author]` | Text | `parentWork.author` | Same parent branch |
| `work[parent_work_relationships_attributes][0][language_id]` | Read by `inputValue`, not select parsing | `parentWork.languageID` | Same parent branch |
| `work[parent_work_relationships_attributes][0][translation]` | Checkbox | `parentWork.isTranslation` | `1` only when checked and parent branch active; a captured non-array hidden twin can otherwise survive the carry pass |
| `work[chapter_attributes][title]` | Text | `chapter.title` | Always when `chapter` exists, including empty |
| `work[chapter_attributes][summary]` | Long text | `chapter.summary` | Always when `chapter` exists, including empty |
| `work[chapter_attributes][content]` | Long text; `textarea#content` fallback | `chapter.content` | Always when `chapter` exists, including empty; empty content control still creates a chapter model |
| `work[chapter_attributes][published_at(1i)]` | Year select or input | `chapter.publishedYear` | All three date parts sent if year nonempty; otherwise all omitted |
| `work[chapter_attributes][published_at(2i)]` | Month select or input | `chapter.publishedMonth` | Verbatim parsed part, including empty when year present |
| `work[chapter_attributes][published_at(3i)]` | Day select or input | `chapter.publishedDay` | Same date rule; select values remain unpadded |
| `work[author_attributes][ids][]` | Multiple pseud select, or hidden IDs | `creators.selectedPseudIDs`, `availablePseuds` | Repeated IDs; none emitted if empty. Parser falls back to nonempty hidden IDs only when no option explicitly selected |
| `work[author_attributes][byline]` | Text | `creators.coauthorByline` | Nonempty only, subject to hidden-field carry if an empty modeled value has a hidden twin |
| `work[wip_length]` | Text | `chapterTotal` | Always, including empty |
| `chapters-options-show` / `#chapters-options-show` | Checkbox / presentation control | `isChaptered` | No explicit encoded pair; a non-array hidden twin could be carried |
| `work[backdate]` | Checkbox | `backdate` | Always one `1` or `0` |
| `work[restricted]` | Checkbox | `restricted` | Always one `1` or `0` |
| `work[moderated_commenting_enabled]` | Checkbox | `moderatedCommenting` | Always one `1` or `0` |
| `work[comment_permissions]` | Single radio choice; served values/labels | `commentPermissions`, `commentPermissionOptions` | Nonempty selected value only, subject to hidden-field carry |
| `work[anonymous]` | Optional checkbox | `anonymous` | One `1`/`0` when any matching input exists; omitted otherwise |
| `work[collection_inbox]` | Optional checkbox | `collectionInbox` | Same optional-checkbox rule |
| `work[work_skin_id]` | Single select; all served options | `workSkinID`, `workSkinOptions` | Always selected value, including empty to clear a skin |
| Other non-array hidden names | Hidden | `hiddenFields` | First instance per name carried if no explicit pair already overrides it |

`parseSelect` records the last explicitly selected value; it does not use the
browser's implicit first-option selection. `controlValue` for dates does use the
first selected option or first option, falling back to option text for a blank
value. Textareas are read with SwiftSoup `text()`. Exact whitespace fidelity needs
fixtures/tests; it has not been asserted from this inspection.

Non-control metadata: action becomes `actionURL`; the numeric action path becomes
`workID`; heading/action and the presence of `save_button` / `update_button`
determine `kind`, `isDraft`, `isPosted`. Posted means Update present and Save Draft
absent. Edit-chapter links determine `chaptersPosted`, with `wip_length == 1` as a
fallback. Current-series links and removal links become `currentSeries`; these are
read-only and not posted. `#parent-options` link titles become
`existingParentTitles`, excluding Remove; those labels are not posted.

### Submit names and values

| Purpose | iOS action | Encoded submit pair |
|---|---|---|
| Save new work as draft | `.saveDraft` | `save_button=1` |
| Save changes to a draft | `.saveDraft` | `save_button=1` |
| Update posted work | `.update` | `update_button=1` |
| Post | `.post` | `post_button=1` |
| Post without preview | `.postWithoutPreview` | `post_without_preview_button=1` |
| Preview | `.preview` | `preview_button=1` |
| Edit submit action also defined by iOS | `.edit` | `edit_button=1` |

`parameters` does not validate that the requested submit exists on the page.
`saveWork` locally checks required fields only for Post/Post Without Preview.
Draft save does not have that local gate. `previewWork` uses the same encoder with
Preview. No Android write function is needed to implement an encoder.

### Served controls without a modeled value

This is the behavioral classification from the inspected parser. Local HTML
inventory checked both iOS work fixtures and all three Android demo forms.
The reference edit fixture also serves the five presentation toggles and submits;
its new fixture adds only submits. Android's richer fixtures include utf8,
work[chapter_attributes][id] and coauthor hidden arrays. No live page was fetched.

| Unmodeled control category | iOS result on encoding |
|---|---|
| `utf8` hidden control | Not read into carry fields; not sent |
| Hidden name ending in `[]`, except explicitly encoded warning/category/pseud names | Not carried; not sent by generic carry pass |
| Unknown non-array hidden control | First served value carried, unless a modeled pair overrides that name |
| Repeated non-array hidden name | Only first captured value can survive |
| Unknown text, textarea, select, radio or checkbox | Not modeled or carried; not sent, except a same-name non-array hidden twin can survive |
| Unchosen submit buttons | Not sent; chosen action always sends `1` |
| `work[collections_to_add]`, `work[pseuds_to_add]`, `remove_me` | Constants exist but no explicit work-form parse/encode branch; non-array hidden version can survive, visible version cannot |
| `work[collections_to_remove][]`, `work[author_attributes][coauthors][]` | Constants exist but no explicit work-form parse/encode branch; hidden array versions are also skipped |

There is no generic rule that sends every unmodeled control empty. Empty values
come from explicit model branches or from a captured hidden value. No conclusion
about whether an omitted control clears an AO3 association is claimed without
server/fixture evidence.

### Pages and request sequence

`loadNewWorkForm` reads `/works/new`; `loadWorkForm(workID:)` reads
`/works/{ID}/edit`. Both delegate to `loadWorkForm(at:)`, which also attempts an
authenticated read of the signed-in user's collection-list page 1 and applies
parsed offers to the form. This is a separate page, not options read from the work
form. The enrichment uses `try?`; failure leaves the initially parsed offers.

`workFormHTML` delegates to the existing authenticated page client.
`workFormElement` prefers `form#work-form` / `form.work.post` and then falls back
to the first `form[action*=/works]`.

**`saveWork` makes no fresh GET before its single POST.** It uses the supplied
form's token/action/parameters through `submitWorkForm`, which builds a write
request and calls `submitWrite` once. Likewise Preview uses the supplied token
and form. The broad comment saying methods fetch CSRF once is not evidence of a
fresh save-time read: the actual `saveWork` body wins. This differs from the
collection save's fresh-token refetch described in 3at.

## Encoding decision — answered by Claude, not the owner

The model must preserve every served control, its name, every value, multiplicity
and order, including controls it does not understand. For fields iOS emits, the
encoder must use iOS's representation and empty-value rules. Remaining controls
must be replayed with browser successful-control semantics and exact values and
multiplicity; names emitted by the iOS branch must be excluded from replay, with
an explicit test proving those name sets are disjoint.

Untouched round-trip tests split into two assertions: iOS-emitted fields compare
to browser controls in meaning using **only** these normalizations: checkbox
hidden twins compare by the value Rails takes; comma lists compare after trimming
around commas; submit buttons compare by name presence. Remaining controls compare
exactly without normalization. The result must list these rules and begin with a
per-control table of everything iOS drops/changes, browser and iOS payloads, and
the evidence-based judgment of no effect or risk. Android deliberately exceeds
iOS's preservation behavior; nothing on iOS is to be changed.

## Read-scope decision — answered by Claude, not the owner

Resolved by Claude, who runs the port; the owner has not been asked: read only
the requested form page. No further open question remains.

## Work log and handoff

Initial status clean; current branch `android/agent-gemini-3bb`. Read AGENTS.md,
TASKS.md, README.md, onboarding, architecture/test guidance, writing architecture
including the requested sections, AO3 networking policy, and 3az/3at including
their landing notes. Applied Ponytail's reuse-first guidance. No task claim was
written: this brief expressly forbids TASKS.md edits.

3az leaves both New Work and draft taps using `WritingWorkDestination.url` and the
in-app browser; that routing must remain unchanged. 3at's landing note confirms
the existing collection form/client approach and warns that its earlier unanswered
questions were later resolved by Claude, not the owner. Claude has now explicitly
answered both questions from this brief, as recorded above.

## Android implementation

New production code is under android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writing/:

- AO3WorkForm.kt: iOS-named editable fields plus servedControls, an ordered
  immutable list. Every control keeps tag, all attributes, raw text, current
  browser values, effective disabled state, and every option's text/value/
  attributes/disabled state. Unknown, unnamed, unchecked and disabled controls
  remain in the snapshot. No persistence/backup serialization was added.
- AO3WorkFormParser.kt: iOS form-kind/group/tag/pseud/date/current-series/parent
  parsing, with options kept as served. Modeled selects follow iOS's explicit
  selection rule; the raw snapshot separately records browser defaults.
  Textareas use wholeText. Preferred form selectors and fallback follow iOS,
  with additional trusted HTTPS action, POST method, title-control and token
  validation. Typed LoginRequired, Overloaded and InvalidForm exceptions.
  Existing username parser, overload detector and trusted-URL policy reused.
- AO3WorkFormEncoder.kt: iosParameters uses iOS's field order, representation,
  empty rules and conditional branches. Modeled conditional hidden fallback
  (especially translation=0) follows iOS's first-hidden rule. carriedParameters
  replays successful raw controls whose names that branch did not emit.
  No duplicate name occurs across the two branches. Unknown duplicate hidden
  fields, hidden arrays and visible controls stay exact, without a map or
  deduplication. Final order is modeled pairs followed by the remainder in its
  original relative order. Editing modeled fields never changes the snapshot.
- AO3WorkFormRepository.kt: loadNewWorkForm/loadWorkForm make one requested
  authenticated GET, with injectable parseDispatcher (Default normally,
  Unconfined in tests). Signed-out calls never reach the client. Cancellation
  and generation changes discard HTML/parsed forms. Served login form expires
  that generation with no anonymous retry. Errors use existing AO3Result.
  No app container, screen or route calls this repository.

Replay excludes unchecked checkbox/radio values, disabled controls/options
(including fieldsets except first legend), unnamed controls, reset/plain buttons
and unchosen submits, exactly as browser successful controls. Those controls
remain modeled in the snapshot. External form-ID-associated controls are kept
in document order. No upload or image-submit interaction is introduced.

The replay boundary is the names the iOS branch actually emits, per Claude's
rule 3. A conditionally omitted name (e.g. empty modeled rating, unused series
alternative, date without nested chapter) retains its **served** payload.
This deliberate preservation difference is tested. A later editor must account
for that contract before treating such a modeled clear as a server operation.
No mutation function exists in this brief.

Where the original brief and iOS differed, the modeled representation follows
iOS (conditional fields, comma lists, scalar booleans and named submits).
Claude's explicit clarification adds preservation of the remainder; his separate
read-scope answer defers collection enrichment. Neither decision is represented
as owner approval.

Collection/gift names are ordered strings, without synthesized picker offers,
access flags or enrichment-only data. Every served option stays in raw data.

## iOS reads deferred to a later brief

Claude answered explicitly; the owner has not been asked. Defer the authenticated
account collection-list page-1 GET, parseCollectionOffers and applyingCollectionStates
from iOS loadWorkForm(at:) to **the association-pickers brief (Add to collections)**.
It feeds that picker's offers/access states. This foundation reads only the
requested form page and adds no enrichment-only model. No numbered picker brief
was provided or invented.

## Local fixtures and demo answers

- Expanded existing ao3_work_new_draft.html: original-filler demo account's
  new form, blank required fields and same draft-csrf token. Existing /works/new
  answer reuses that same asset.
- ao3_demo_work_draft_edit.html: drafts-fixture work 995001, Lanterns Above
  the Mill, original text, own action/token/chapter ID.
- ao3_demo_work_posted_edit.html: work 995006, two posted chapters out of five;
  series Lantern Voyages; collections lantern_exchange and star_atlas;
  co-creator IDs 303/404; gift PaperNavigator; inspired-work URL/title/author;
  2019-11-5 backdate; skin 55; comment moderation on; all tag kinds, with comma
  delimiters, ampersands, quotes and Japanese characters. Metadata-only form has
  no chapter text; dates and chapter ID are preserved through replay.
- DemoNetwork.kt: only exact 995001/edit and 995006/edit read answers added
  before the legacy generic edit answer. Browser and interceptor share the
  same address table. Generic edit/work-detail assets stay in place. No POST
  answer added.
- Static HTML count: new 66 controls/46 distinct names; draft edit 66/48; posted
  edit 64/45. Each has one form. Counts include nonsuccessful controls.

No editor destination was added. Account → Writing → Drafts → first draft still
opens the browser, now with its own local 995001 form. New Work uses the expanded
local answer. Posted form is available through demo browser /works/995006/edit
or the fixture test. No emulator pass was run. The data repository has test callers
only. Use the existing network-blocking demo mode; no live sign-in is needed.

## Offline tests written — 43 cases, not run

AO3WorkFormTest: 32; AO3WorkFormRepositoryTest: 8; DemoWorkFormTest: 3.

Two round-trip cases cover all three fixtures and all six iOS enum actions.
For a submit absent from the fixture, the test adds only that submitter to its
HTML, then parses/encodes the entire resulting form unchanged. Even Edit and
PostWithoutPreview are tested as pure encodings, without claiming valid work
operations. The browser oracle reads the DOM independently of production code.

The normalizer contains exactly three rules:

1. Scalar checkbox/hidden twin compares by the last successful scalar (Rails
   value). Arrays do not get this rule.
2. Six comma-list fields compare after trimming around commas. Order/spelling
   remain exact; no missing-segment, deduplication, sorting or CSV normalization.
3. Submit compares by chosen name presence. Missing is distinct from present.

No general whitespace, HTML, date, select-default, absent/empty, case-fold,
array-sentinel or series-title normalization. Modeled comparison checks every
emitted field with fixture/action/name in failure messages. Replay comparison
checks remaining names/values/multiplicity exactly, whole-remainder order, and
disjoint branch names. Known conditional omission and array-hidden sentinel cases
have direct iOS-branch assertions rather than hidden normalization.

Other cases cover each changed field kind; unknown controls/options; duplicate
hidden fields/arrays; disabled/legend and external ownership semantics; typed
login/overload/invalid refusals; token/method; Unicode/HTML and body fields through
existing OkHttp FormBody; one authenticated GET with cookies; signed-out/no-read;
cancellation/logout; deterministic generation change at parse dispatch; typed
responses without repository retry. Demo tests use the real local interceptor
with a downstream interceptor that throws before a socket. Both repository
suites use a POST client that throws.

Relevant iOS tests keep their names: parsesWorkEditFormGroups,
clearedWorkSkinIsStillPosted, postingAWorkSendsTheWorkFormsOwnPostButton,
missingRequiredFieldsNamesWhatPostNeeds, publicationDateKeepsAO3sUnpaddedFormat,
backdateOnPostsTheChosenDate, backdateOffLeavesTheDateFieldsUntouched,
pickingASeriesPostsOnlyThatSeries, aWhitespaceOnlySeriesTitleIsNotPosted,
missingFormThrowsParse, namedParamKeysMatchOtwarchive;
theWorkFormReadsItsCurrentSeriesAndPostsNoneOfIt,
theCollectionsPickerDecidesWhatIsPosted, postedFieldKeepsDisplayedChipOrder,
clearingEveryCategoryPostsAnEmptyValue, categoriesStillPostOneValueEachWhenSet.

Original assertions are retained for data-layer symbols; picker-interaction
assertions use direct model copies, date reconstruction uses LocalDate.
Reference edit fixture remains unchanged for original assertions.
Chapter-only, tag-diff, bulk, delete, preview-response, UI post-confirmation,
collection-offer enrichment and picker-autocomplete tests are outside this
foundation and are not claimed as ported. No out-of-scope feature was added.

## Verification and Claude handoff

Performed: Kotlin client/auth/error/demo symbol/caller review, iOS source/test
review, Python standard-library fixture inventory, git diff --check (clean).
No Gradle, Xcode, emulator or Kotlin test execution.
**Compilation and passing tests are not claimed.**

Claude must compile Android debug and run :app:testDebugUnitTest, including all
three new suites, DemoDraftsTest/DemoNetworkBlockTest, networking/auth regressions
and WritingDrafts destination tests. All 43 behavioral cases require that run,
especially exact round trips, session fencing, typed refusal, no-write/no-socket
guards and iOS reference assertions. Inspect the three local browser answers if
doing a demo pass; this brief adds no UI to approve. Association pickers own the
deferred collection read. No live AO3 verification is authorized.

Final static checks also found no undefined AO3WorkFormField references, no new
production write-dispatch sites, and no app caller of the repository. Browser
semantics tests cover multiple checked radios resolving to the last checked
control while raw checked attributes remain intact, and an unselected size>1
listbox contributing no successful value. These are written assertions and
still require the Kotlin test run.

Changes stay in this worktree, uncommitted/unpushed on android/agent-gemini-3bb.
No sign-in, AO3 contact, branch switch, TASKS.md edit, iOS edit, backup-format or
Room-schema change. No helper scripts, stubs or .orig files remain.
AO3WriteRepository is unchanged. No save/post/preview/delete dispatch function,
screen, route or draft-tap change was added.

**Open questions: none.** Both clarification decisions came from Claude, who
runs the port; the owner has not been asked. The risk table is for the owner/iOS
side; no iOS changes were made here.
