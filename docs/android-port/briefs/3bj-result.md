# Brief 3bj — work association pickers

## Reads, counted first

- Form load: the existing one authenticated form GET; **zero extra reads** on Android. iOS also reads the signed-in account's `/users/<username>/collections` (page one, no `page` query) during form load. Android deliberately defers that one best-effort authenticated GET until the shared collections/gifts picker first opens, once per form **attempt**, including failure or cancellation. No later pages, collection detail reads, anonymous fallback or automatic retry.
- Collections search: **one anonymous GET per settled nonblank term**, `/autocomplete/open_collection_names?term=<Foundation-trimmed, encoded term>`, through the existing autocomplete repository. iOS waits **300 ms** after a keystroke; a changed query cancels its wait/request, clears results immediately, and ignores cancelled answers. Leaving cancels. No search on opening, empty terms or reads ahead. iOS silently drops failures; the field and local collection toggles remain usable. Transport pacing/retry stays in the existing client.
- Series, gifts, co-creators and Inspired by: **zero picker GETs**. iOS has no gift/byline/source/series name autocomplete. The combined gifts entry opens the same collection screen and therefore shares its first-opening account read.
- **Zero writes**. iOS's separate Reorder the series destination is excluded here: display its value without a navigation control; no series-order read or save. No removal from current series (`DELETE /serial_works/:id`).

## iOS inventory (read before Android changes)

Read-only reference: `/Users/cidy02/kudos-ios-polish/`, `Features/Writing/WorkAssociationPickers.swift`, `WorkEditView.swift`, `Models/AO3WritingModels.swift`, `Services/AO3Client+Works.swift`, `AO3WorkActions.swift`, `AO3Client.swift`, `Services/AO3TagAutocomplete.swift`; tests `AO3WorkFormParsingTests.swift` and `WritingSeriesCollectionsTests.swift`. The picker file's old introductory comment says nothing is fetched; its actual search task and form loader win over that comment.

All four screens have kicker **Edit work**, Back only, immediate binding edits retained on Back, no Done/Save action. No picker implements drag or reordering of selected values. No invented maximum length/count or server validation is present.

### Series

Header **Series**. Subtitle precedence: `Saving adds <workTitle> to <selected title>`; `Saving creates <trimmed new title> with <workTitle> in it`; `<workTitle> is part of one series` / `<workTitle> is part of N series`; `Choose a series to add <workTitle> to`.

Sections in order:

- **Your series** (count of offered series). Empty row **You have no series yet**. Each served series title; current membership has **This work is in it**, checkmark and disabled selection. Others single-select; tap the picked row clears it. Optional detail `<N> work(s) · this work is <ordinal>` drops unknown parts; position only for a selected row. Current parser supplies neither count nor position, so do not invent them.
- Footnote: **Each save adds this work to one series. Saving doesn't remove it from another series. To do that, use Remove works on the series' Edit screen.**
- When selected, else first current series: **Position in <title>**, row **Reorder the series**, optional `<N> work(s)` value. iOS pushes `SeriesReorderDestination`, saving every work's order independently. Android shows this value without a control because that write is outside this brief. Footnote: **Changing the reading order updates every work in the series. Save the new order on its own screen.**
- **New series**: field **Create a series from this work**, placeholder **Title**. Footnote: **AO3 creates the series with this work first. Add the series summary and notes afterwards.**

AO3 accepts one series per work-form save, adding only. Selecting clears `newSeriesTitle`; typing a nonblank Foundation-trimmed title clears selections; whitespace alone does not clear a selection. Current memberships cannot be removed. Form row **Series**: current titles joined `, `; **None**, **Adding <pending>**, current titles alone, or `<current> + <pending>`.

Fields changed: `series[].isSelected`, `newSeriesTitle` only. Encoder emits first selected `work[series_attributes][id]`, else trimmed nonblank `work[series_attributes][title]`, else both empty; currentSeries never posts. Existing 3bb lossless remainder still carries the other served alternative when iOS's modeled branch omits it.

### Add to collections and Gift recipients (one screen)

Header **Collections and gifts**, subtitle literal work title. Sections:

- **Your collections** (count of all offers). **Search** field, placeholder **Search all collections by name**. The query filters held title/name case-insensitively and asks for other open collection names. Empty: **AO3 offers this work no collections** only when both list and raw query are empty, else **No collection matches “<query>”**. Held rows toggle selection, including closed collections (iOS does not disable them). Search hits show plus, join held offers **unticked**, and disappear from results. Exclude names already held case-insensitively. Display title, fallback name. States word for word: **Moderated (a maintainer approves the work)**; **Closed to new works**; **Open**; unknown autocomplete state **Open to new works (it may be moderated or unrevealed)**. Append ** · Unrevealed until reveal** and ** · Anonymous** as applicable; closed wins over other states.
- Footnote: **A work submitted to a moderated collection waits for a maintainer's approval. A work in an unrevealed collection stays hidden until the reveal. AO3 shows either state on the work.**
- **Gift recipients** (count). Field **Add**, placeholder **Username or pseud**, **Add** button (disabled for blank trimmed input); Return also adds. Whole trimmed text is one name, including commas; case-insensitive duplicate is a no-op retaining input. Accepted name appends and clears field. Each literal name has **Remove <name>** action, removing exact matching names. No gift suggestions and no reordering.
- Footnote: **When you post, AO3 emails each gift recipient. You can't take back the gift, so check each name before you save.**
- If parent URL nonempty: **Also on this work**, disabled **Inspired by** row, **1 work** (generic iOS view also supports **N works**; form passes zero or one).

Account collection states merge in page order; selected membership matches slug only, case-insensitively, never title. Missing held selected names append with default Open access. Empty/failure retains the original offers. Autocomplete's `id` is slug, `name` is `Title (slug)`; remove that exact trailing suffix for display. Search-hit access is unknown, without detail probes.

Fields changed: `collections` offers/selection and `gifts`; original `collectionNames` remains the served fallback. Encoder's missing offer-aware rule will be added there: when offers exist post selected slugs in list order, even when all unticked; only empty offers fall back to `collectionNames`. `work[collection_names]` and `work[recipients]` always emit trimmed comma-space lists or empty. Form values **Add to collections** / **Gift recipients** are **None** or selected/gift counts.

### Co-creators

Header **Co-creators**, subtitle literal work title. **Your pseuds** (available count); each served pseud title and toggle. Empty row **AO3 listed no pseuds for this work**. Last selected pseud cannot be unticked; additions append unique IDs, deselection removes matching IDs only when selected count > 1. **Invite a co-creator**, field **Byline**, placeholder **username (pseud)**. No suggestions/validation/trim. Footnote: **AO3 invites a co-creator, and the work stays unchanged until they accept. Enter their byline exactly as it appears on AO3, as username or username (pseud).**

Fields changed: `creators.selectedPseudIDs`, `creators.coauthorByline`. Encoder repeats `work[author_attributes][ids][]` in selected order; nonempty literal byline emits `work[author_attributes][byline]`. Empty byline follows existing hidden/remainder fallback (does not invent an invitation cancellation). Form **Co-creators**: **None**, pseud count, or **N + 1 invited** for any nonempty byline.

### Inspired by

Header **Inspired by**, subtitle **No source work** when URL empty, otherwise literal URL. **Source work**: **URL**, placeholder **https://archiveofourown.org/works/…** (URL keyboard); **Title**, placeholder **Optional**; **Author**, placeholder **Optional**. Footnote: **For a work on AO3, enter its web address. For a work from elsewhere, enter its title and author, which will appear instead of a link.** **Translation**: toggle **This work is a translation**, choice **Language of the source** using the work's `languageOptions`, always visible even with translation off. No validation, URL resolution, source fetch or deletion control; fields can be cleared individually.

Fields changed: all five `parentWork` fields only. When URL or title is nonempty, encoder emits literal url/title/author/language_id under `work[parent_work_relationships_attributes][0]`; translation `1` only if enabled. Hidden translation `0` and conditional omitted controls retain 3bb's existing carry contract. Author alone does not activate the modeled group. Form **Inspired by** remains **None** for empty URL even with a source title; otherwise **1**. iOS wins over any implication that this should count title-only sources.

## Android implementation

- `WritingAssociationPickers.kt`: all five form rows push four in-route screens. Uses the form's panels, rows, toggles and choice sheet, the tag editor's field and lazy panel edges, `tokens.scopePalette`; Back comes from `ProvidePushedShellChrome` alone. Status bars + 76 dp precede each header. New literal Text calls specify line height. Accessibility controls stack; long series/collections/pseud/gift lists use lazy items. Collection input is sticky, results are drawn from collected search state and brought into view above the IME padding. No Material chips/cards/text-field decoration. iOS uses rows rather than chips for these values, so no invented drag/chip controls.
- `WritingWorkFormState.kt`: edits the actual form for selections, gifts, pseuds, byline and all source fields. The optional account read stamps its attempt before suspension, keeps it on failure/cancellation, and rejects closed/signed-out/stale-session results. A response arriving after edits preserves both selected and unticked held offers; it enriches offered names without overwriting the writer's choices. Back hides the keyboard; edits survive reopening.
- `AO3WorkForm.kt` / parser / encoder: in-memory collection offers/access, initial selected offers from served names, iOS `postedCollectionNames` fallback, slug-only account merge. The encoder owns offer-aware collection posting, and Foundation whitespace trimming for collection/gift joins and new-series titles. `servedControls`, original fallback names and every unrelated field remain unchanged. No write dispatcher or persistence type.
- `AO3WorkFormRepository.kt`: optional authenticated page-one collections method uses the existing `AO3AccountUrls`, `AO3AccountParser`, authenticated client, parse dispatcher and generation fence. Login/overload handling is reused; no anonymous fallback or pagination. The original form-load methods do not call it.
- `AO3TagAutocompleteRepository.kt`: collection suggestions use the same client/address builder as tags, with iOS's strict required String `id`/`name` decoder, slug trimming and display-suffix removal. Does not infer moderation/access from extra JSON, fetch collection profiles or alter the tag/search minimum gates.
- `WritingCollectionsSearchState.kt`: separate 300 ms query task, immediate clear, cancellation and silent failures. No cache or implicit retry (iOS's collection task has neither). All screen results come from `val searchState by search.state.collectAsState()`; form rows come from the parent form's collected state.
- `SettingsChrome.kt`: optional `keyboardType` on the existing field, default unchanged; only the source URL requests the URI keyboard. Existing callers were inspected. `WritingTagsEditorScreen.kt` only exposes its lazy panel-edge modifier for reuse.
- Waiting rows **Chapters**, **Add chapter**, **Edit tags** retain no action. The existing waiting-row regression removes just the five implemented association labels. No production navigation was changed: draft taps and New Work still open the browser pending the Save brief.

## Local demo

Reach from `nav:writing-work-new-demo`, `nav:writing-work-draft-demo`, `nav:writing-work-posted-demo` under the existing isolated signed-in demo launch. This task did not execute a sign-in or launch. Open Series, Add to collections, Gift recipients, Co-creators or Inspired by. Collections and gifts share the first-opening read; reopening either does not request that page again.

The existing `/users/AO3_Reader/collections` → `ao3_collections_index.html` answer is reused by the account collections screen, browser and work picker. It offers **Winter Exchange 2026** (moderated/anonymous), **Summer Prompt Meme** (open), **Rare Pairs Week** (closed/moderated/unrevealed); the posted form's held `lantern_exchange` and `star_atlas` remain appended. No separate answer or fixture is introduced.

The existing shared `DemoNetworkInterceptor` adds `/autocomplete/open_collection_names`: **demo** returns three unknown-access, unticked offers (`demo_lanterns`, `demo_atlas`, `demo_exchange`); **none** returns `[]`; **fail** is a terminal local 403. Other terms are empty. No gift/byline/series/source suggestion addresses exist on iOS, so no fictional demo answers for them. No POST answers were added.

## Offline tests written — 18 cases, not run

- `WritingAssociationStateTest` (10): all three forms × all six encoder actions for series select/clear/create/whitespace/selection exclusivity/current membership; collection add-unticked/select/untick-all/fallback; gift whole-name trimming/blank/case duplicate/removal/clear; pseud add/remove/last-pseud protection and literal/blank byline; every source field/translation/language/clear and existing remainder behavior. `assertDelta` checks the full ordered payload outside the explicitly changed field group and exact unchanged served snapshots. Also tests first-opening-only collection reads after success/empty/403/exception/cancellation, no read on form load, held edits during response, slug-only merge, exact access copy, virtual-clock debounce/supersession/one-letter/blank/close, in-flight cancellation, continued use after failure, session fencing, signed-out no-read, anonymous strict autocomplete decoding and no metadata probes. Form/suggestion clients throw on POST.
- `WritingAssociationScreenTest` (6): each form's actual five rows/fields/taps/IME/suggestions/Back/encoder, shared screen and once-only page read; failed account/search reads with continued editing; all four themes at 2× font scale with non-vacuous text-layout height and ellipsis assertions; lazy 150-offer list and asynchronously drawn suggestions beside a pinned field. Native graphics, tall `w411dp-h2400dp`, 15-second waits. No short-label `hasVisualOverflow` assertion or ambiguous shared count lookup.
- `DemoAssociationPickersTest` (2): real local interceptor for shared account/browser offers across all three forms; collection autocomplete several/empty/403/blank answers. A downstream interceptor throws before any socket and the POST client throws.
- Existing `AO3WorkFormTest.theCollectionsPickerDecidesWhatIsPosted` now edits offer selection, matching iOS's test rather than merely replacing the original string list. The existing empty-branch case explicitly exercises the empty-offer fallback. Existing form-screen waiting-row test still covers all three waiting rows.

## Verification and handoff

Performed only static review: real iOS code and tests, Android call sites/types/authenticated client and shared parser, fixture inventory, cached Compose icon/API inspection (`jar`/`javap`), lexical delimiter checks on the new Kotlin files, and `git diff --check` (clean). **No Gradle, Xcode, Kotlin test run or emulator pass. Compilation, passing tests, keyboard behavior and visual correctness are not claimed.** All 18 cases and updated regressions require Claude's run.

Claude: build Android debug and run `:app:testDebugUnitTest`, including `WritingAssociation*`, `DemoAssociationPickersTest`, existing `AO3WorkForm*`, `WritingWorkForm*`, `WritingTagsEditor*`, account-collections, autocomplete, demo-network and field-component regressions. Manually inspect the three local-only routes in Light/Dark/Sepia/OLED, large text, long values/lists and a real keyboard; verify the top row after a scrolled form pushes/back, selected vs unticked offers, silent failures, and first-opening request counts. No live AO3 verification is authorized. Optional series count/position metadata is absent from iOS's work-form parser and Android does not guess it; the displayed reorder value is therefore empty for these forms.

Changes are uncommitted/unpushed in this worktree on `android/agent-codex-3bj`. No branch switch, `TASKS.md` edit, iOS edit, backup-format/Room-schema change, sign-in, AO3 contact, helper script, stub or `.orig` file. iOS's actual code wins on the shared collections/gifts destination, no gift/byline suggestions, no association drag/reorder controls, title-only source row reading None, and silent collection failures. The explicitly requested Android lazy-read timing and omission of separate write controls are the brief's deliberate platform differences.

## Decided without asking

- Four pushed screens in `writing/WritingAssociationPickers.kt`, form mutations in the existing form state, collection offers in the existing in-memory form model. No persistence model.
- Reuse the existing account collections demo address/fixture and shared autocomplete interceptor; `demo`, `none`, `fail` terms. No new fixture account or helper script.
- Silent collection/search failures match iOS. No invented retry or failure copy. Back hides the keyboard and retains edits.
- Kept the existing three debug-only entrances and local fixture names; did not expose a production editor or alter fixture membership to create a prettier demo. Added state/screen/demo test files beside the corresponding existing suites.

## Open questions

- Series reordering requires a separate AO3 write not included here: show its value without a control, pending that later brief. No extra reads to support it.
- The 3bb conditional remainder contract can preserve an old byline/source/series alternative on a clear; retain that landed contract and test it explicitly rather than sending more than the reference modeled encoder. Save integration must account for it.

**Landing note (Claude, 2026-10-08).** Landed with one test updated. Gate green (1,970 tests).
Still reached only through the work form's three debug routes.

**The reads were counted first.** Loading the form makes its one GET and no other. The
account's own collections (first page) are read when the Collections and gifts picker is
first opened, once per form, where iOS reads them on every form load. Searching collections
is one anonymous read per settled term after 300 ms. Series, co-creators and Inspired by read
nothing. Nothing is sent.

**Changed on landing.** An older test of the tags editor still asserted that the five
association rows open nothing; it now names the three rows that still wait (Chapters, Add
chapter, Edit tags).

Read against iOS: the four screens' sections, words and footnotes; the encoder now posts the
picker's selected collection names (iOS's `postedCollectionNames`) and trims a new series
title as Foundation does.

Seen on the emulator in airplane mode (Dark), each opened from the scrolled form of the
posted work with its Back button: Series ("Your series 2", "This work is in it", the two
notes, Reorder the series shown without a control, New series); Collections and gifts (five
collections with their access lines after the one read, Search, the note, one gift recipient
with Remove); Co-creators (two pseuds, Invite a co-creator); Inspired by (the source's URL
and author, the translation switch, the source's language). Not seen: changing anything in a
picker, the collections search, Light, Sepia, OLED, large text (all in tests).

For the Save brief, from Codex's open questions: clearing a co-creator's byline, a source or
a new series title does not yet clear it on AO3, because the encoder sends back as served a
field iOS leaves out (the same contract as the blank rating). Reordering a series and removing
the work from one are separate writes, not built.
