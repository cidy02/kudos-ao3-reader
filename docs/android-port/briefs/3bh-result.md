# Brief 3bh — work form tags editor

## iOS contract read from code

Read-only reference: `WritingTagsEditor.swift`, `WritingTagConvenience.swift`, `GlassFieldBar.swift`, `WritingFormFields.swift`, `WorkEditView.swift`, `AO3TagAutocomplete.swift`, `AO3Client.autocompleteTags/autocompleteURL`, `KudosBackupSettings.capture`, and `AuthorProfileView.swift` in `/Users/cidy02/kudos-ios-polish/`.

Header kicker **Edit tags**; titles **Fandoms**, **Relationships**, **Characters**, **Additional tags**. Empty subtitle: **AO3 offers its canonical tags as you type**. Nonempty: **N chosen · drag to reorder · AO3 offers its canonical tags as you type**. No work title in this header.

Field placeholder **Add a tag**, magnifying glass, trailing **Clear** when nonempty; plain field, Search Return key, no autocapitalization/autocorrection. Return calls `add(term)`. A comma has no special handler; pasting several comma-separated names changes only the field. Return or tapping the typed-term row then appends the entire trimmed string as ONE chip. The eventual comma-list encoder joins chips with `, `; it does not split a chip first. Exact repeats and blanks are no-ops and KEEP the field text. Case variants are distinct chosen chips. Outer Foundation whitespaces/newlines are trimmed; interior spacing, punctuation and Unicode are kept.

Chosen chips keep append order; removal removes every exact occurrence. Drag lands before its target, except a forward drop on the last chip lands after it. Accessibility actions **Move Earlier**, **Move Later** swap neighbors; hint **Drag to reorder.**; removal **Remove NAME**. No sorting.

Suggestions label **Suggestions** appears with its panel iff there is a free typed term, a suggestion or an error. Typed row first, then AO3 order, then failure. Names, optional real work count, badge, trailing plus. Badge **Canonical** (accessibility **canonical tag**) on autocomplete names; **Posts as typed** (accessibility **posts as typed**) on a typed row. Typed row omitted when its trimmed name matches a suggestion or chosen name case-insensitively. Suggested chosen names are excluded case-insensitively. No claim that an absent name is non-canonical. No loading sentence, no spinner, no special empty-results sentence: an empty response leaves the typed row. Failure: **Suggestions unavailable. You can still add a tag by name.** Typing and adding remain possible.

Footnote, word for word: **AO3 suggests only its canonical tags and doesn't provide work counts here. You can still post a tag exactly as you type it, which is how new tags are created.** No decorative count, zero or dash. The long comment explicitly rejects “most-used first”, “Not canonical”, tag-page/count enrichment and `/tags/search`: autocomplete order is substring/word-match then taggings, not a popularity ranking. AO3's endpoint cap is 15; iOS does not truncate the response again. The actual suggest path maps names to canonical=true/count=nil; its separate optional-key parser is NOT called by this screen.

**Recently used**: JSON `{byKind: {kind: [names]}}` under device UserDefaults key `writing.recentTags.v1`, 20 per kind, newest successful add first, case-insensitive removal of older spellings, no `.tag` kind. Re-read before recording to retain another editor's edits; selected spellings hidden case-insensitively. `KudosBackupSettings.capture` is an explicit field allowlist that excludes this key; folder sync uses that manifest/settings contract. Neither list is in library backup/sync.

**From your other works**: environment sources from author profile's already-loaded Works blurbs (`WritingOtherWorkTags.sources(model.works)`), empty elsewhere; excludes the edited ID, blanks, chosen names and duplicate case-folded names. First-seen work/tag order, no cap. Only in memory, no persistence and no request from the editor. Android's form has no corresponding author-profile input; omit this section for all four kinds rather than loading works here.

Limits: upstream OTW defaults are **150 characters per tag** and **75 user-defined tags across fandoms, relationships, characters and additional tags combined**, rather than 75 for each list. `Tag` validates name length after squishing whitespace; `Work` validates `user_defined_tags_count` (admin exception). Sources read on GitHub only: [configuration](https://raw.githubusercontent.com/otwcode/otwarchive/master/config/config.yml), [Tag validation](https://raw.githubusercontent.com/otwcode/otwarchive/master/app/models/tag.rb), [Work validation](https://raw.githubusercontent.com/otwcode/otwarchive/master/app/models/work.rb), [Taggable count](https://raw.githubusercontent.com/otwcode/otwarchive/master/app/models/concerns/taggable.rb). These are upstream defaults, not a probe of deployment settings.

This iOS editor has NO name-length guard, chosen-list size guard, limit validation message or count/max counter. The 15 suggestions and 20 recent tags are its only caps. Later Save goes through `AO3WorkActions.submitWorkForm`: the first parsed server refusal outside writer content (`AO3Client.workWriteError`, `#main .flash.error` / `#main #error li`) becomes `AO3WorkWriteError.rejected`, then `UserFacingError` appears under **AO3 could not save the change** with **OK**. The picker itself reports neither server limit. Android follows that code: names beyond 150 and lists beyond 75 stay editable; this brief adds no Save/write path.

Leaving: there is NO Done toolbar button in this iOS screen. Navigation Back retains binding changes immediately, discards unsubmitted field text and cancels the task. No save, discard prompt or AO3 write. The separate **Edit tags** work-form row still waits for its own brief.

Every editor request: GET `https://archiveofourown.org/autocomplete/fandom?term=...`, `/relationship?term=...`, `/character?term=...`, `/freeform?term=...`; percent-encoded trimmed original term. No read on opening/blank field. SwiftUI `.task(id: term)` cancels on text change or leaving. `AO3TagAutocomplete.suggest` waits **300 ms** then enters the existing coordinator/client. Cache keyed by trimmed lowercase term, successful answers (including empty) retained for this opening; revisiting a cached term does not fetch. Failed answers are not cached by iOS. Prior suggestions stand while a new term waits; blank clears them. Never tag search, landing pages, popular-tags seeds, author pages, pagination or read-ahead. No POST.

## iOS wins over the brief

Comma and paste do not automatically add/split names; Return adds their whole trimmed value. No Done action or tag-length/list-size limit UI exists in the reference. Tests will pin these actual behaviors, including the encoder's comma string after the same taps.

## Decided without asking

- Keep new state/screen/tests in `writing/`, named `WritingTagsEditor*`; reuse the existing form fixture/test helpers.
- Store recent-tag JSON in the existing settings DataStore, outside `KudosSettings`, backup and Room.
- Omit “From your other works”: no already-loaded source reaches Android's work-form routes.
- Share one local autocomplete answer in `DemoNetworkInterceptor` with search filters; use `demo` for several names, `none` for empty, `fail` for a terminal failure, for all four addresses. No new fixture files.
- Retain the three existing demo routes; use their existing demo isolation before constructing dependencies.

## Work log

Initial clean worktree on `android/agent-codex-3bh`. Read the two requested results and landing notes, real Swift/Kotlin symbols, operational docs. Brief overrides task claims, commits, pushes, branch changes and build commands. No TASKS edit, sign-in, AO3 contact or iOS edit.

## Implementation

`WritingWorkFormScreen` pushes `WritingTagsEditorScreen` from the four count rows, leaving warnings/categories and every waiting association/chapter/Edit-tags row as before. `WritingWorkFormState.writingTags` immutably replaces only the selected list. Updates happen immediately; Back keeps them and drops the unsent field. The public screen's dependency parameters default to absent for isolated existing tests; the actual three fixture routes inject the container's existing `tagAutocompleteRepository` and `settingsRepository` under the pre-existing `DemoNetwork.isActive` guard. Production draft/New Work routing remains the browser, as required by the earlier briefs.

`WritingTagsEditorState` owns a cancellable job per raw field change, a 300 ms wait, and successful/empty-answer cache keyed by trimmed lowercase term. The existing autocomplete repository is the only URL builder/parser; its default two-character search gate stays, while writing opts into a nonblank one-character minimum. Cancellation is rethrown, late replies ignored. Stale suggestion lists remain during the wait; blank clears; failure leaves a typed row plus iOS's exact failure sentence. Chosen exclusions apply when a response/cache is installed, like iOS. No additional work-count, popular-tags, author, tag-page or tag-search read. No POST capability is held by the editor.

Trimming uses the exact Foundation whitespace/newline set, including U+0085 and U+200B, while keeping Kotlin-only U+001C…U+001F separators. The four tag fields use this in the encoder too; collection/gift list encoding is unchanged. A Python ctypes query of this Mac's CoreFoundation predefined character set confirmed every BMP member/range against the Kotlin implementation; no Swift compiler/Xcode was run. Chips still keep whole comma-containing entries; the encoder produces the same comma string as iOS.

`SettingsRepository.recentWritingTags/recordWritingTag` uses atomic DataStore edits of `{byKind: ...}` at `writing.recentTags.v1`, global to the device like iOS, newest first, cap 20, case-insensitive recent dedupe. Its existing backup restore allowlist leaves the local key intact. No `KudosSettings`, backup DTO, manifest or Room change. Nothing touches reader work records or text recovery.

UI reuses `SubjectHeaderBlock`, `SubjectChip`, `SubjectFieldLabel`, panel tokens and separators, and the collection form's `SubjectTextFieldRow`. Three opt-in component additions leave default behavior intact: the field can supply Search Return/icons and omit a second visible label, chips can wrap instead of one-line ellipsis, labels can supply a line height. Root palette is `tokens.scopePalette`; statusBars + 76dp precede the header. The input is pinned within a lazy list; IME padding reduces the viewport and typing scrolls Suggestions into it with the measured pinned-field height reserved above the label. Chosen/recent chips are measured into flow rows, each lazy; suggestion rows share one rounded token panel using per-row end caps. Every new Text/TextStyle has a line height. Long tag labels wrap at accessibility sizes. Drag begins on a chip, never its independent Material removal icon button; accessibility neighbor moves use the exact iOS labels. The shell supplies its existing Back Material icon button; no invented Done action.

## Local demo

Existing routes: `nav:writing-work-new-demo`, `nav:writing-work-draft-demo`, `nav:writing-work-posted-demo`. Open any four tag rows. Type **demo** → three canonical names per kind, **none** → typed row only, **fail** → typed row and failure copy. `DemoNetworkInterceptor` has one shared JSON answer for each autocomplete address, available to the search filters too; all other terms return empty. Failure is a terminal local 403, so it needs no retry/socket. No extra fixture files or seeded recent history.

## Tests written, not run

- `WritingTagsEditorStateTest` (6 tests): all four kinds × all three forms, Return, comma and paste without implicit splitting, suggestion add, exact/case-variant duplicates, blank no-op retaining text, Foundation trimming, removal, drag/neighbor order, clear, a 160-character name and 80 added names without invented limits. Every change checks all six submit actions with `assertDelta`: the chosen field is exact and all other ordered pairs/served controls remain untouched. Virtual-clock tests prove no opening read, no replaced-term read inside 300 ms, one settled read, success/empty cache reuse, single-letter query, blank/close cancellation, in-flight cancellation, stale-list behavior and continued typing after failure. POST-throwing clients.
- `WritingTagsEditorScreenTest` (13 native-graphics tests, tall `w411dp-h2400dp`, 15-second waits): all four rows for each form, actual field/IME/suggestion/removal/Back payload, captions/badges, empty/failure state, accessibility reorder, pointer drag onto last chip, cancellation on removal, recent-section filtering/add/reopen, a lazy 150-chip list with Suggestions below the pinned field, waiting rows inert, and Light/Dark/Sepia/OLED at 2× font scale. Text assertions use `!didOverflowHeight` and a non-ellipsized last line. Shared badges are counted; typed names are matched within their row.
- `DemoTagAutocompleteTest` (2 tests): all four addresses, several/empty/failure, same answer for search/writing, preserved search gate, single-letter writing, encoded Unicode, no count enrichment. A terminal interceptor throws before any socket.
- `SettingsRepositoryTest` (2 added tests): cap/order/case dedupe, re-read across two repository instances, ignored any-tag/blank values, malformed JSON repair, existing snapshot/backup-restore contract exclusion.
- Updated 3bf's waiting-row test to remove only the four rows now implemented; all remaining waiting rows retain its no-action assertions.

## Verification and handoff to Claude

Performed: real source/caller/signature review; cached Compose 1.11.3 and serialization bytecode API inspection with `javap` (no build); CoreFoundation trim-set comparison; local fixture inspection; `git diff --check` and changed-file scope/Kotlin delimiter scans. No Gradle, Xcode, emulator or Kotlin tests run. **Compilation, passing tests and visual correctness are not claimed.**

Claude must build Android debug and run `:app:testDebugUnitTest`, including the new state/screen/demo suites and existing `WritingWorkForm*`, `SettingsRepository*`, `AO3WorkForm*`, search-filter and demo-network regressions. Every behavioral assertion above needs that run. Manual local-only demo pass: all three routes, each kind; all themes, large text, real keyboard (field and suggestions above it), long-list scrolling/drag, Back from a scrolled form revealing chrome, and recent tags after reopening/relaunch. No live AO3 test is authorized.

Changes remain uncommitted/unpushed in this worktree on `android/agent-codex-3bh`. TASKS.md, iOS, branch, backup format and Room schema are untouched. No sign-in or archiveofourown.org contact, helper script, stub or .orig file. GitHub upstream source reads above were solely documentation research; no app network call was executed.

Open questions: none.

**Landing note (Claude, 2026-10-08).** Landed with one fix to the screen and one to a test.
Gate green (1,936 tests). Still reached only through the work form's three debug routes: a
draft tap and New Work open the browser.

**Found by the brief's own tests and fixed.** Five screen tests timed out waiting for
suggestions. The request was made and answered, but the list was not drawn: the screen read
the names with `model.suggestions()`, which reads the flow's value without subscribing, and
the only subscribed read sat behind a short-circuit that a typed term always took. So names
that arrived after the last keystroke waited for the next key. The screen now reads them from
its collected state. Seen on the emulator: type "demo", touch nothing, and the suggestions
appear.

One test needed `@OptIn(ExperimentalTestApi::class)` to compile (custom accessibility
actions).

**Read against iOS and checked:**
- The reads: none on opening; one per settled term after iOS's 300 ms; a term replaced inside
  the wait is never asked; through the existing `AO3TagAutocompleteRepository` (the search
  filters keep their two-letter minimum, the editor asks from one letter as iOS). Nothing sent.
- Recent tags: iOS keeps them in UserDefaults under `writing.recentTags.v1`, capped at 20 a
  kind, newest first, an older spelling replaced; its backup does not carry them
  (`WritingTagConvenience.swift`). Android keeps the same JSON under the same key in the
  settings DataStore, outside the settings that are backed up. No backup or Room change.
- The encoder trims the four tag lists with Foundation's whitespace set where it used
  Kotlin's; they differ only in a few control and zero-width characters.
- Return adds the whole typed text; a comma or a paste does not split it (iOS wins over the
  brief). There is no Done: Back keeps the changes.

Left out and listed by Codex: "From your other works" (Android has no loaded list of the
writer's other works to draw on yet).

Seen on the emulator in airplane mode (Dark): Fandoms opened from the draft's form with its
header line, the field, two chosen chips with their remove buttons and the footnote; "demo"
typed, then "demo · Posts as typed" and two canonical suggestions above the keyboard; Back to
the form. Not seen: choosing a suggestion, removing and reordering chips, the failure
sentence, the recent list, the other three kinds, Light, Sepia, OLED, large text (all in
tests; my script tapped a name the fandom list does not have).

Left for polish (P3): the pinned field sits on a band whose colour does not match the wash
above it, and the header's last line touches the band.
