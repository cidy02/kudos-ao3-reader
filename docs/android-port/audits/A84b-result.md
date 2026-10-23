# A84b result: the second 35 A82 screens, compared in code

*Read only. iOS `kudos-ios-polish` working tree (7dc23568 plus the uncommitted A85 work); Android `kudos-android-lane` working tree (933b9bed plus Codex 3gw, uncommitted). Nothing built or run.*

## Counts

- **Screens:**
  - **18 same:** colitems, colsfilter, chsignupdetail, prompttags, tagset, tagseteditor, writingpreview, chapters, edittags, texteditor, recovery, seriespicker, collectionsgifts, bulkedit, privacydata, availability, pairing, revokedevice.
  - **17 with differences:** inboxfilter, authorabout, seriesdetail, seriesedit, seriesreorder, seriesremove, authorworksfilter, chsettingsedit, chapterform, tagseditor, creatorspicker, parentpicker, bulktagstate, bulknames, prefhelp, backupimport, aboutkudos.
- **P1:** 0. **P2:** 1. **P3:** 24 (2 of them suspected).
- **By app:**
  - **iOS:** 9 P3, mostly text cut at the largest sizes and titles. The inboxfilter title is already fixed on `claude/agent-ios-i9` (I9b).
  - **Android:** the P2 and 7 P3.
  - **Both apps,** differing from each other: 8 P3.
- **Not reported, by the brief:** Android's chrome (the Material bar, sheets vs dialogs, switches, menus and their order), fonts, demo data, the accent of a sheet, and pairing's QR-generate-only role (DECISIONS).

## Every P2

1. **`seriesdetail` (Android): the series card never shows "Restricted", and names one fandom.**
   - Android: `app/SeriesWorksScreen.kt:236-251` builds the card without `isRestricted` and with the first work's first fandom only.
   - iOS: `Features/Authors/AO3SeriesDetailView.swift:55-58` shows the summary's own flag and fandoms.

## The P3s at a glance

- **iOS cuts text at the largest sizes:**
  - series reorder and remove rows (`SeriesEditView.swift:401-403`, `:540`);
  - the work and chapter form's second line, e.g. "Empty. This opens the editor…" (`WritingTextEditor.swift:514-517`);
  - tag suggestion names (`WritingTagsEditor.swift:283-286`).
  - Android lifts each limit at accessibility font scales.
- **iOS titles:**
  - Inbox Filters shows none, because its title is set after the wash (fixed in I9b).
  - Co-creators and Inspired by show their name twice, because their titles are set before the wash and also appear in the header block (`WorkAssociationPickers.swift:508`, `:596`).
- **Wording:**
  - author About's empty state and Try Again vs Retry;
  - the bulk picker's "Unchanged";
  - "Restore from Backup" for an empty library;
  - the series list's Works figure;
  - the About version line.
- **Behaviour:**
  - iOS's Refine tag picker searches AO3 while Android's offers only the page's tags;
  - iOS opens "Delete series on AO3" in Safari while Android uses the in-app browser;
  - Android locks the challenge settings form after a 403;
  - iOS help text is selectable.
- The rest are below, screen by screen.

## Per-screen notes

Paths: iOS under `kudos-ios-polish/kudos-ao3-reader/`, Android under `kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/`. Both are working trees (Android with 3gw uncommitted).

### `inboxfilter`
- **P3 (iOS): the sheet shows no "Inbox Filters" title.**
  - iOS `Features/Account/AccountInboxFilterSheet.swift:61` sets the title after `.subjectScreenWash` (`:60`), whose `hidesNavigationBarChrome()` empties it, and the innermost title wins.
  - Android shows it (`account/AccountInboxPane.kt:650`).
  - Already fixed on `claude/agent-ios-i9` (I9b), not landed.
- Otherwise same: the fields and options from AO3's form, a check on the selected one, and a tap that applies, ends selection, reloads page 1 and closes (iOS `AO3InboxModel.swift:374-389`; Android `AccountInboxViewModel.kt:253-273`, `AccountInboxPane.kt:173-176`). No empty state on either when the form hasn't loaded.

### `authorabout`
- **P3: the empty and error wording differ.**
  - About missing with no error: iOS "Profile details unavailable" / "Kudos could not read this AO3 profile page." (`Features/Authors/AuthorProfileView.swift:531-538`). Android "No about" / "Profile details unavailable." (`author/AuthorProfileScreen.kt:1072`).
  - Failed load: iOS "Couldn't load about" with **Try Again** (`AuthorProfileContentSections.swift:33-39`). Android "Couldn't load about" with **Retry** (`AuthorProfileScreen.kt:894-901`).
- **P3: the Account section when it has nothing to show.** iOS always builds the "Account" section, even with no pseud, join date or user ID (`AuthorProfileView.swift:521-529`); Android leaves it out when empty (`AuthorProfileScreen.kt:1105-1117`). Suspected only: whether SwiftUI draws an empty section's header.
- Same otherwise:
  - Sections Bio, Pseuds, Account, in that order.
  - "This user has not added a bio."; the bio as rich text with links.
  - Pseud rows with a check on the current one.
  - Selected Pseud, Joined, and User ID with grouping.
  - Loading placeholder rows (iOS `:482-483`, Android `:889-891`).

### `seriesdetail`
- **P2 (Android): the series card never shows "Restricted", and names one fandom.**
  - Android builds the card from the series page's header but passes no `isRestricted`, and takes only the first work's first fandom (`app/SeriesWorksScreen.kt:236-251`, `:243`). `AO3SeriesRow`'s amber "Restricted" badge (`author/AuthorProfileComponents.kt:305-307`) therefore never appears here.
  - iOS draws the summary it was opened with (`Features/Authors/AO3SeriesDetailView.swift:55-58`, `shownSeries`). From an author's Series tab that summary carries the restricted flag and the series' own fandoms.
  - Small, but it is information one app shows and the other drops.
  - The reverse gap is on iOS's side and recorded in its code: from a subscription, its card has title and byline only (`Services/AO3Client+NamedSubscriptions.swift:47-58`). Android's card is complete from anywhere.
- **P3: the Works heading's figure differs.** iOS shows the count of works loaded (`AO3SeriesDetailView.swift:68-72`); Android shows "Page X of Y" (`SeriesWorksScreen.kt:257-261`).
- **P3, suspected: works you have saved.** iOS merges the AO3 list with your library and shows a saved work as its local row, with your progress and download state (`AO3SeriesDetailView.swift:189-212`, `CanonicalWorkMerge.remoteLed`; Hide applied to the local side, `:226-233`). Android shows every work as an AO3 row (`SeriesWorksScreen.kt:262-276`). Not checked whether Android's `SensitiveWorkRow` marks a saved work.
- Same otherwise:
  - "Couldn't load series" with Try Again.
  - "No visible works" / "No works in this series are visible to you on AO3."
  - "Showing cached AO3 data"; load more with an inline error.
  - Pull to refresh past the cache; reload after an edit.
  - Edit series and Reorder only for a creator, Reorder only with more than one work.
  - Open on AO3, Share Series, Select, Expand All.

### `seriesedit`
- **P3: "Delete series on AO3" leaves the app on iOS.**
  - iOS calls the environment's `openURL(series.url)` (`Features/Writing/SeriesEditView.swift:224-229`); nothing above it reroutes `openURL`, so the series opens in Safari.
  - Android opens it in the in-app AO3 browser (`writing/WritingSeriesScreen.kt:227`, `onOpenAo3(AO3SeriesFormUrls.show(id))`).
  - Both go to the series page, not a delete page.
- **P3: saving shows differently.** Android adds a spinner row, "Saving…" (`WritingSeriesScreen.kt:236`, `:262-265`). iOS only disables the form and the Save button (`SeriesEditView.swift:89`, `:143-146`).
- Same otherwise:
  - Header "AO3 Account" / "Edit series" / "title · N works · W words".
  - Series rows: Title (required), Creators byline, Series summary (with a preview), Series notes.
  - State: "Series is complete", with the same footnote.
  - Works: Reorder works (count; inactive under two) and Remove works (count), with the same footnote.
  - Delete, with the same footnote; AO3's answer below, scrolled into view.
  - Save disabled for a blank title.
  - Load failure "Couldn't load from AO3" with Try Again (iOS `WritingDraftsView.swift:550-557`, Android `WritingSeriesScreen.kt:251-257`).

### `seriesreorder`
- **P3 (iOS): long titles are cut at the largest text.** iOS rows are `.lineLimit(2)` at every size (`SeriesEditView.swift:401-403`). Android lifts the limit at accessibility font scales (`WritingSeriesScreen.kt:170-171`).
- Same otherwise:
  - "Reorder" / series title; "Reading order".
  - Numbered rows showing the position Save will write, "Untitled work" for an empty title, words and date when known, and Draft.
  - The same footnote. Save needs two works, saves once and goes back.
  - "Your AO3 session changed, so the order was not saved." (iOS `:437`, Android `WritingSeriesState.kt:121-122`).
  - Screen-reader label "N. title, Draft, metadata".
  - Loader title "Reorder series" on both (iOS `SeriesReorderDestination.swift:31`, Android `WritingSeriesScreen.kt:131`).
  - The Draft chip vs Android's "Draft" line is styling.

### `seriesremove`
- **P3 (iOS): long titles are cut at the largest text,** as in Reorder (`SeriesEditView.swift:540`; Android `WritingSeriesScreen.kt:170-171`).
- Same otherwise:
  - "Remove works" / "title · N works".
  - The remove button only while more than one work remains, with the same screen-reader label.
  - Confirm "Remove “title” from series?" / "The work stays posted on AO3." / Remove from series.
  - The two footnotes (one work vs several).
  - Errors: session changed / unconfirmed / "title was not removed. …" (iOS `:571-579`, Android `WritingSeriesState.kt:152-170`).

### `authorworksfilter`
- **P3: the tag pickers look in different places.**
  - In Refine, Android passes no AO3 autocomplete and offers only tags found on the works already on the page (`author/AuthorProfileScreen.kt:575-579`; `search/SearchFilterSheet.kt:253-273`, `if (refine) null else autocompleteRepository`).
  - iOS's `TagSelectField` has no Refine branch, so its picker searches AO3 ("Type above to search AO3 …", `Features/Search/AO3FilterPanel.swift:510-526`, `TagSelectField.swift`).
  - So iOS can pick a tag none of the loaded works carry (matching nothing), and Android can't.
- **P3: the match line with nothing loaded.** iOS hides "N of the M works on this page match" when the page has no works (`AO3FilterPanel.swift:155-156`). Android always passes it (`AuthorProfileScreen.kt:568-574`), so an empty page reads "0 of the 0 works on this page match".
- Same otherwise:
  - Title "Sort and filter"; Reset (inactive with nothing to clear) and Apply (commits the sort draft only if it changed).
  - Sort by with the column and "9 fields"; Direction; Completion chips with "AO3 applies this choice to all matching works, not only the page you can see."
  - Rating, then Match and Include Not Rated.
  - Warnings and Categories as include/exclude/clear rows.
  - Chapters, with no page-level Completion under a works sort; Language.
  - Tags (Fandoms, Characters, Relationships, Additional Tags) with the tap-once/twice/three-times note.
  - Word count with the open-bound note.
  - No Crossovers, dates, title/creator, hits/kudos/comments/bookmarks or Save in Refine.
  - Order matches. Android also wraps Sort by and Direction at large font scales (`AuthorWorksSortFields.kt:41-72`); iOS has no AX branch here.

### `colitems`
- **Same.** Read end to end on both (iOS `Features/Account/AO3CollectionItemsView.swift`, Android `account/AO3CollectionItemsScreen.kt` with `AO3CollectionItemsState.kt`):
  - **Header:** "AO3 Account › Collections" / "Collection items" / "scope · N need a decision" or "· N items", with "· page X of Y".
  - **Tabs:** the four pills (Awaiting collection, Awaiting you, Rejected, Approved) and Reset; the default tab is per scope.
  - **Staging:** "N staged", Discard, and Submit labelled "Submit N staged changes".
  - **Each card:**
    - the collection as eyebrow, the role, and the unsent-changes dot;
    - the title, struck through when removed, with the removal notice;
    - creator and moderator approval as a three-way chip (Awaiting / Approved / Rejected), read-only when AO3 disables it;
    - Unrevealed and Anonymous switches, or "On"/"Off";
    - the byline, "Remove from collection"/"Keep", and the date.
  - **States:** "Nothing in this tab."; "Couldn't load collection items" with Try Again; "Log in to AO3 to manage collection items."; pagination; pull to refresh on the current page.
  - **Largest text:** the same stacking (iOS `:577-583`, Android `:263-302`).
- Android also blocks a tab change while submitting (`:205`), which is harmless.

### `colsfilter`
- **Same.** iOS `Features/Account/AO3CollectionsFilterPanel.swift`; Android `account/AO3CollectionsFilterPanel.kt`.
  - "Sort and filter" with Cancel and Apply; Apply is inactive until the draft changes.
  - Sort by: "Order by"; Direction hidden for "as returned"; the Recently updated note.
  - Show only: Open to new works, Has works, Moderated, Unrevealed, with the "more than one" note.
  - The no-role note; Reset, inactive at the defaults.
  - Dismissing cancels on both.

### `chsettingsedit`
- **P3: field errors sit in different places.**
  - iOS lists the schedule's and limits' field errors above each group's panel (`Features/Challenges/ChallengeSettingsEditView.swift:204-206`, `:216-218`).
  - Android puts each under its own row (`account/AO3ChallengeSettingsEditScreen.kt:156`, `:180`).
- **P3: a failed save locks Android.** After a 403 or a lost session, Android disables the whole form (`AO3ChallengeSettingsEditState.kt:96-97`, `terminal`). iOS shows the error and leaves the form live.
- Same otherwise:
  - **Header:** "Gift exchange/Prompt meme · moderator" / "Challenge settings" / "title · N sign-ups".
  - **Basics:** Name, Tagline, Introduction as a word count, FAQ, each opening the collection form, and "Collection settings · Couldn't load". "Sign-up instructions" with the same placeholder.
  - **Schedule:**
    - Sign-ups open and close, "Assignments sent" (Manual), Works due, Works revealed, Creators revealed. A date AO3 leaves off is skipped; "Not set" offers Set.
    - Time zone or "Unavailable", with both footnotes.
  - **Sign-up limits and restrictions:**
    - Requests (and Offers for a gift exchange) as 0–20 "to" 0–20.
    - The three request restrictions, with the "Prompts have been added…" lock note.
  - **Tag set(s):** rows opening the tag set.
  - **Matching:**
    - "Match on"; Requests that must match (All, 1–5) and each tag type (All, 0–5).
    - "Count optional tags for"; Request fandoms 0–10 each; Allow any fandom with its caption; the matching footnote.
  - **Anonymity and moderation:** four switches saved through the collection form, plus "Prompts posted anonymously" for a prompt meme.
  - **At AO3:** Run matching and Delete challenge, "Opens AO3".
  - **Saving:** "Save changes", owner only, validated first. "Reveal now?" before turning off Unrevealed or Anonymous. The notice joins both saves.
  - **States:** "Loading challenge settings…" and "Couldn't load challenge settings" with Try Again.

### `chsignupdetail`
- **Same.** iOS `Features/Challenges/ChallengeSignUpsView.swift:546-635`; Android `account/AO3ChallengeSignUpsScreen.kt:232-262`.
  - The header: collection, pseud, "N requests · N offers".
  - A section per "Request n" and "Offer n".
  - Two-line rows for Fandoms, Relationships, Characters, Additional tags and Optional tags, with "Any" appended for an any-choice and empty types left out.
  - The prompt text in serif. Read-only, no extra request.

### `prompttags`
- **Same.** iOS `Features/Challenges/PromptTagsEditorView.swift`; Android `account/AO3ChallengeSignUpScreen.kt:267-293`.
  - "Request/Offer n" / "Tags" / "Comma-separated tag names".
  - Fandoms, Relationships, Characters, Additional tags in that order, with the same placeholders.
  - Done splits on commas and trims; leaving without Done keeps nothing.
  - Android's field wraps onto more lines (`multiline = true`), which is styling.

### `tagset`
- **Same.** iOS `Features/Challenges/TagSetView.swift:36-227`, `:350-640`; Android `account/AO3TagSetScreen.kt:39-213`.
  - The header: "Tag set · moderator/owner", "Tag set", "title · N tags".
  - Ownership: Title, and "Visible to everyone" read-only.
  - Tags with a count: four rows opening Add tags.
  - Nominations: open (read-only) and the four "… per person" limits.
  - Review: Awaiting review / Approved / Rejected counts. The queue is grouped by fandom ("No fandom listed" last), each row with a type label and Reject or a state badge; "Couldn't reject “tag”: …"; "No nominations yet" / "Nothing has been nominated to this tag set."
  - The review footnote; At AO3: Associate nominations, and Delete tag set in red ("Opens AO3").
  - Loading and failure with Try Again.
  - Android also stacks a nomination row at large font scales (`:226-229`); iOS rows wrap the name (`fixedSize`) but keep the badge beside it.

### `tagseteditor`
- **Same.** iOS `TagSetView.swift:237-355`; Android `AO3TagSetScreen.kt:241-270`.
  - "Tag set" / "Add tags" / title.
  - Four comma-list fields with the same labels and placeholders, filled from the edit page.
  - The same footnote; error or "Tags saved."; "Save tags" with a spinner.

### `writingpreview`
- **Same.** iOS `Features/Writing/WritingPreviewView.swift`; Android `writing/WritingAO3PreviewScreen.kt`.
  - "AO3 Account" / "Preview" / subtitle, with AO3's notice.
  - AO3's preview blocks (headings, labels, text), laid out lazily.
  - Post: "Post work"/"Post chapter"/"Update" in the success green, and Edit.
  - "Post this work?" with the same missing-fields message before a first post (iOS `WorkEditView.swift:269-271`, Android `WritingWorkFormState.kt:475-485`).
  - "AO3 could not post this" on failure; back is blocked while posting.

### `chapters`
- **Same.** iOS `Features/Writing/WritingChaptersView.swift`; Android `writing/WritingChaptersScreen.kt`.
  - "AO3 Account" / "Chapters" / "title · N chapters".
  - One row per chapter from AO3's index, with its date, opening the chapter form.
  - "Loading chapters…"; the failure message with Try Again; rows kept when a later read fails; reload after a save.
  - At the largest text Android moves the date under the title (`:69-75`); iOS's `SubjectFormRow` stacks at accessibility sizes itself (`UIComponents/SubjectForm.swift:264-285`).

### `chapterform`
- **P3 (iOS): a text row's second line is cut at the largest text.**
  - iOS's `WritingTextEditorRow` caps its detail line at two lines at every size (`Features/Writing/WritingTextEditor.swift:514-517`). That line is the empty-Chapter-text hint "Empty. This opens the editor with plain text, AO3’s HTML tags, or a paste from elsewhere." here, and a summary preview elsewhere.
  - Android lifts the limit at accessibility font scales (`writing/WritingChapterFormScreen.kt:107-110`).
  - The same row is on `seriesedit` (summary) and the work form.
- **P3: the header while loading.** Android titles a still-loading form "Edit chapter" even for a new chapter (`:72`, `form?.chapterID == null && form != null`). iOS builds Add chapter with its form in hand and loads only existing chapters behind "Edit chapter" (`WritingDraftsView.swift:506`). Only a flash on Android.
- Same otherwise:
  - Chapter: Title; "Chapter number N of ?" or "Expected chapter total"; Position "After chapter n".
  - Text: Chapter text, Summary, Beginning notes, End notes, as Empty/Set rows that open the editor, with Preview and Delete (more than one chapter) in the editor's menu.
  - Publication: "Set a different publication date" and the date; "Post without preview" (posting only); "This is the last chapter"; the same footnote.
  - Post: "Post chapter now" or "Save chapter changes"; "Save as draft" when posting; "Retry updating the work total" after a half-save; the same footnote.
  - "AO3 could not save the chapter"; "Couldn't load from AO3" with Try Again.

### `edittags`
- **Same.** iOS `Features/Writing/EditTagsView.swift`; Android `writing/WritingEditTagsScreen.kt`.
  - "AO3 Account" / "Edit tags" / "title · changes here do not touch the text".
  - Rating as single-check rows.
  - Archive warnings as check rows, with "Choose at least one warning…".
  - Categories as switches.
  - Tags: Fandoms (required), Relationships, Characters, Additional tags in that order. Each shows a count or "None", its chips (tap to remove) and Add.
  - The canonical-tags footnote; Save; "AO3 could not save the change".

### `tagseditor`
- **P3 (iOS): long suggestion names are cut at two lines at every size** (`Features/Writing/WritingTagsEditor.swift:283-286`, `.lineLimit(2)`). Android does not limit them (`writing/WritingTagsEditorScreen.kt:214`).
- Same otherwise:
  - "Edit tags" / kind / "N chosen · drag to reorder · AO3 offers its canonical tags as you type".
  - The "Add a tag" field with Clear; chosen chips with drag, Move Earlier/Later and Remove.
  - "Recently used", then "From your other works".
  - Suggestions: the typed term as "Posts as typed" first, then AO3's with Canonical or Posts as typed. "Suggestions unavailable. You can still add a tag by name."
  - The same footnote.

### `texteditor`
- **Same.** iOS `Features/Writing/WritingTextEditor.swift:13-330`; Android `writing/WritingTextEditorScreen.kt:74-235`.
  - The rule with the chapter name and a word count from the last checkpoint.
  - Preview/Edit (rendered off the main thread; "Couldn't render this HTML" on iOS), Undo, Redo.
  - More: "Paste as plain text", plus "Preview on AO3" and "Delete chapter" for a chapter. Delete asks "Delete “name”?" / "This will delete all comments on the chapter as well and cannot be undone." / Delete on AO3.
  - "Recovery copy on this device · Save from the work form".
  - The tag bar of AO3's tags with their names, and its note; "Insert link" with the safe-link check.
  - Checkpoints when the app leaves the foreground and on low memory.
  - At the largest text Android puts the word count on its own line (`:132-137`). iOS caps the header at 22 pt so the count stays beside it (`UIComponents/…SectionRuleHeader`, `labelSize = min(labelSize, 22)`).

### `recovery`
- **Same.** iOS `WritingTextEditor.swift:299-337` (with the uncommitted Copy text); Android `WritingTextEditorScreen.kt:206-232`.
  - "Recover unfinished text?", with a choice of copy when there is more than one.
  - "A recovery copy was saved on this device <date>." and the form-changed warning.
  - The copy drawn a line at a time.
  - Copy text, Restore local copy, Keep form text, Delete this local copy, in that order. The sheet can't be swiped away.
  - Android's Copy text also falls back to a .txt share past the clipboard's limit (A85). iOS has no such limit.

### `seriespicker`
- **Same.** iOS `Features/Writing/WorkAssociationPickers.swift:265-495`; Android `writing/WritingAssociationPickers.kt:61-99`.
  - "Edit work" / "Series" / the same four subtitles ("Saving adds…", "Saving creates…", "… is part of one series", "Choose a series…").
  - Your series as single-pick rows; the current series is checked, disabled and marked "This work is in it". "You have no series yet".
  - The add-only footnote; "Position in <series>" with Reorder the series and its footnote.
  - New series, where typing un-picks and picking clears the title, with its footnote.
  - iOS's row detail ("N works · this work is 3rd") and the Reorder row's work count read `workCount`/`position`, which its parser never fills (`Services/AO3Client+Works.swift:761-770`), so neither app shows them.

### `collectionsgifts`
- **Same.** iOS `WorkAssociationPickers.swift:5-262`; Android `WritingAssociationPickers.kt:100-163`.
  - "Your collections" with a count; search across AO3's collections, offering only new ones.
  - Held rows toggle, found rows add; the two empty texts; the same access wording (Moderated, Closed, Open, "may be moderated or unrevealed", Unrevealed, Anonymous) and footnote.
  - Gift recipients: add with a case-insensitive duplicate check, remove, the same footnote.
  - "Also on this work · Inspired by".

### `creatorspicker`
- **P3 (iOS): the title shows twice.**
  - iOS sets `.navigationTitle("Co-creators")` before `.subjectScreenWash` (`WorkAssociationPickers.swift:508-509`). The innermost title wins, so the bar names the page above its own "Co-creators" header block.
  - `WritingTagsEditor.swift:56-60` blanks its title for exactly this reason. Android shows the header only.
- Same otherwise:
  - "Your pseuds" switches (never the last one off) or "AO3 listed no pseuds for this work".
  - "Invite a co-creator": a Byline field with the same footnote.

### `parentpicker`
- **P3 (iOS): the title shows twice,** as in `creatorspicker` (`.navigationTitle("Inspired by")` before the wash, `WorkAssociationPickers.swift:596-597`).
- Same otherwise:
  - The subtitle is the URL or "No source work".
  - Source work: URL, Title and Author, with the same footnote.
  - Translation: "This work is a translation" and "Language of the source".

### `bulkedit`
- **Same.** iOS `Features/Writing/EditMultipleWorksView.swift`; Android `writing/WritingBulkEditScreen.kt`.
  - "AO3 Account" / "Edit N works" / the titles, and the "apply to every selected work" note.
  - Tags to add and Tags to remove: Fandoms, Relationships, Characters, Additional tags.
  - Change on all: Rating and Language as "Leave as is" choices; Archive warnings and Categories as "Leave as is" or "+a, -r". The same footnote.
  - Collections and gifts: Add to collections; Remove from collections ("None" and inactive with nothing to remove); Gift recipients "Per work", inactive.
  - Comments and visibility: three "Leave as is" choices.
  - Creators: "Add co-creators" (Pseud), "Remove me as a co-creator", the invitation footnote.
  - Save, Cancel and "AO3 could not save the change". Opening at a focused group scrolls there.

### `bulktagstate`
- **P3: wording for an option left alone.** Android shows "Unchanged" beside it (`writing/WritingBulkEditScreen.kt:198`). iOS shows nothing there (`Features/Writing/BulkTagStatePicker.swift:96-101`) but speaks "Unchanged", and marks Add and Remove with a plus or minus icon and strikes through a removed one (`:37-45`).
- Same otherwise: the options AO3 serves; tap to cycle Add → Remove → unchanged; "Tap an option once to add it to every selected work, twice to remove it, or three times to leave it unchanged."

### `bulknames`
- **P3: the names already added have no heading on Android.** iOS lists them under an "Added" section with a minus icon each (`BulkTagStatePicker.swift:155-166`). Android lists them as rows with "Remove" beside each (`WritingBulkEditScreen.kt:192-201`).
- Same otherwise:
  - Tap a name to remove it.
  - The "Collection name" field and Add, with exact-name de-duplication.
  - "Enter the collection name exactly as it appears on AO3. If AO3 doesn't recognize it, you will see that when you save."

### `prefhelp`
- **P3: help text can be selected only on iOS.** iOS enables selection on each topic's body and the footer (`Features/Account/AO3PreferencesView.swift:337-355`); Android's text isn't selectable (`account/AO3PreferencesScreen.kt:520-532`).
- Same otherwise:
  - Every "?" opens the help sheet on both. A82's note that some Android help rows open the browser is out of date: all four kinds now call `openHelp` (`:281`, `:310`, `:351`, `:391`).
  - "Loading help…"; "Couldn't load help" with Try Again and Open on AO3.
  - The title, one card per topic (heading and body), then AO3's footer.

### `privacydata`
- **Same.** iOS `Features/Account/PrivacyDataView.swift`; Android `settings/PrivacyDataScreen.kt`.
  - "AO3 Account › Settings" / "Privacy" / "Your reading data stays on this device"; the mint promise panel with the same words.
  - Stored on this device:
    - size rows (Works you're reading, Original files kept and Imported fonts only when above zero), shown as "—" until measured;
    - Reading positions, Local collections, Saved searches, "Search history · Not recorded";
    - the same footnote.
  - Clear: Free up space, Clear reading positions, Clear reading history and Clear browse cache (becoming "Browse cache cleared"). Each is inactive with nothing to clear and asks first, with the same titles, messages and counted buttons (90 days on both).
  - AO3 session: "Signed in" plus "Remove AO3 session" with the log-out confirmation, or "AO3 account · Not signed in"; the footnote with any sign-out notice.
  - Read Aloud downloads with the same text. Pull to re-measure.

### `availability`
- **Same.** iOS `Features/Account/AvailabilitySweepView.swift`; Android `settings/AvailabilitySweepScreen.kt`.
  - "Before you start": the count, the two-second note, the imported-works line and the 500-limit line.
  - Progress "Checked N of M".
  - "Finished"/"Stopped": "N works are no longer on AO3" with its note, or "Everything checked is still on AO3", and the same detail line.
  - "No longer on AO3 (N)": one-line title and author, or "Hidden mature work" (tap to reveal) under Hide/Blur.
  - Check Now / Checking… and Stop; "You checked every AO3 work in your Library within the past week."

### `pairing`
- **Same, apart from what DECISIONS keeps.** iOS `Settings/PairingSheet.swift:48-460`; Android `backup/PairingSheet.kt:48-400`.
  - Kept by decision: Android has no "Scan a QR Code", its intro and section footnote say so, and it has no automatic Apple-account trust (`DECISIONS.md:1635-1636`, `:2366`).
  - The card: "This device" with the selectable key; "N deletions skipped from an unpaired device", which opens the sheet and clears the count; "No other devices paired yet."
  - Device rows: name or "Unnamed device", an 8-character key, Rename, and Undo Trust within 24 hours, then Revoke. "Undid trust for that device." / "Revoked that device."
  - The sheet: Show/Hide My QR Code (kudos-pub-v1), Copy My Key, "Advanced: paste a key manually" with "I got this key from my other device" and Trust. "Not a recognizable Kudos device key."; "That key can't be trusted (it may be revoked)."; the name-it step with "e.g. Sam's iPhone" and Done.

### `revokedevice`
- **Same** (A82 listed no Android sheet; it is `backup/PairingSheet.kt:398-460`, `RevokeDeviceDialog`).
  - "Revoke <name or this device>" and "Why are you removing this device?".
  - Stolen or compromised (the default) / Retired or sold; Cancel and a red Revoke.
  - Revoking removes the key only on both (iOS `PairingSheet.swift:137-143`; Android `:176-186`).

### `backupimport`
- **P3: different action for an empty library.**
  - With nothing Replace could remove, iOS shows the ordinary Merge button and its footnote and leaves out Replace (`Settings/BackupImportSheet.swift:54-60`).
  - Android shows "Restore from Backup" over "This library is empty. Restore N work(s) from the selected backup." (`backup/BackupScreen.kt:536-541`). Same action, different words.
- **P3 (Android extra): a second Merge note.**
  - Android adds "Merge adds works that are not already here. It does not delete local works or apply unsigned deletion claims from the file." under Merge's footnote (`BackupScreen.kt:547-550`).
  - iOS has only the first. Owner question 9 covers the Backup page's own notes, not this sheet.
- Same otherwise:
  - "Import Backup", Cancel.
  - "This backup": Library records, Saved links, Reading queues, Collections, Custom fonts.
  - Merge with "Merge keeps everything… It removes nothing."
  - "Replace Library…" with the same footnote, opening the Replace review.

### `aboutkudos`
- **P3: the version line.** iOS appends the build's branch when it isn't `main` ("1.0 (1) · abc1234 · claude/polish-loop", `Settings/AboutView.swift:107-120`). Android shows the version and commit only (`account/AboutScreen.kt:52-57`, `bugReportVersionString`).
- Same otherwise:
  - The icon, "Kudos", the version, and the one-line description (Apple/Android devices).
  - License (AGPL-3.0, in bold).
  - Open-Source Components: three credits, each the platform's own library (SwiftSoup/Jsoup, Readium Swift/Kotlin) with license, line and link.
  - Help & Feedback: Report a Bug, View on GitHub.
  - The Disclaimer, word for word.
