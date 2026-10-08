# A4 result: iOS writes and repeating reads

Read-only. The iOS tree was not edited, built, or checked out. Nothing was sent to archiveofourown.org. Server behavior below is from `otwarchive` master on GitHub (`works_controller.rb`, `work.rb`, `chapter.rb`, `_standard_form.html.erb`, `series_controller.rb`, `series/edit.html.erb`, `bookmarks_controller.rb`, `bookmark.rb`, `bookmarks/new.html.erb`, `bookmarks/edit.html.erb`, `config.yml`).

Paths are relative to `kudos-ao3-reader/`.

| id | severity | path:line | statement |
|---|---|---|---|
| A4-1 | P1 | `Models/AO3WritingModels.swift:604` | Saving a work with more than one chapter posts chapter 1's content as empty. AO3 rejects the save, so the text is not wiped, and the edit the user made is not stored. On an unposted multi-chapter draft the Work text row is that empty string, so typing there replaces chapter 1. |
| A4-2 | P1 | `Models/AO3WritingModels.swift:738` | Edit Series shows a co-creator byline field and a successful save never posts it. |
| A4-3 | P1 | `Services/AO3WriteActions.swift:384` | A bookmark validation failure is a 200 with `error_messages_for`. That list is not what `writeErrorMessage` matches, so the app says "Bookmarked." and closes the composer. |
| A4-4 | P2 | `Services/AO3Client+Challenges.swift:78` | Opening gift-exchange settings walks every page of the assignment lists, uncapped, to show three numbers. The same walker runs when Assignments or Sign-ups opens. |
| A4-5 | P2 | `Services/AO3ChallengeActions.swift:298` | "successfully" anywhere in a 200 body is treated as saved before the parsed `#error` list is read. Collection save and preferences save do the same. |
| A4-6 | P2 | `Services/AO3WriteActions.swift:110` | Unsubscribe from the work page, and Mark for later, treat any HTTP 200–399 as success. The newer history and subscription-index writes do not. |

## A4-1. Multi-chapter work save posts an empty chapter 1

`Services/AO3Client+Works.swift:810-831`

```swift
private static func parseNestedChapter(in form: Element) -> AO3WorkChapterDraft? {
    let content = textareaValue(form, name: AO3WorkFormField.chapterContent)
        .ifEmpty(textareaValue(form, id: "content"))
    let title = inputValue(form, name: AO3WorkFormField.chapterTitle) ?? ""
    let summary = textareaValue(form, name: AO3WorkFormField.chapterSummary)
    let hasChapterField =
        firstElement(form, tag: "textarea", name: AO3WorkFormField.chapterContent) != nil
            || ((try? form.select("textarea#content").first()) ?? nil) != nil
    if !hasChapterField, content.isEmpty, title.isEmpty, summary.isEmpty { return nil }
    return AO3WorkChapterDraft(
        title: title,
        summary: summary,
        content: content,
        ...
    )
}
```

`Models/AO3WritingModels.swift:601-604`

```swift
if let chapter {
    pairs.append((AO3WorkFormField.chapterTitle, chapter.title))
    pairs.append((AO3WorkFormField.chapterSummary, chapter.summary))
    pairs.append((AO3WorkFormField.chapterContent, chapter.content))
```

`Features/Writing/WorkEditView.swift:410-430` shows "Work text" only when `form.kind == .new || form.isDraft`. A posted work has no row for this field. `Services/AO3WorkActions.swift:197-202` loads that same form and `saveWork`s it to change `work[wip_length]`. `Features/Writing/AddChapterView.swift:384-388` calls `updateWorkTotals` after a chapter save when the new chapter is marked last.

AO3's edit action sets `@chapters` when `number_of_chapters > 1` (`chapters.count`, drafts included). `_standard_form.html.erb` always emits `work[chapter_attributes][title]` inside `fields_for`, and emits the content textarea only `unless @chapters`. A chapter titled "Prologue" therefore parses as a draft whose `content` is `""`, and `parameters` posts `work[chapter_attributes][content]` as empty. `work_params` permits `:content`. `update` assigns those attributes onto the first chapter and saves the chapter before the work. `Chapter` requires content and a minimum of 10 characters (`CONTENT_MIN` in `config.yml`), so this save returns the edit form and does not persist. `Work#save_chapters` (`save(validate: false)` in an `after_save`) does not run unless `@work.save` runs, and the controller only reaches that when `@chapter.save` succeeded.

Failing case, posted work. A work has 5 chapters. Chapter 1 is titled "Prologue" and has real text. Open Edit Work, change the summary, tap Save. The POST includes an empty `work[chapter_attributes][content]`. AO3 rejects the chapter. The summary, tags, and chapter total are not saved. Chapter 1's text stays, because the chapter save failed validation. The Work text row is hidden, so there is nothing on screen that shows the empty body being sent. The same POST is what "this chapter is the last" uses after the new chapter has already been saved: the chapter stays, the expected total does not (`AddChapterView` then shows "The chapter was saved, but the work total was not updated.").

Failing case, unposted draft with 2 chapters. Edit Work shows Work text bound to that empty `content`. Leave it blank and Save: same rejection, draft text unchanged. Type 10 or more characters into that empty row and Save: chapter validation passes, and that text replaces chapter 1.

A one-chapter edit still has the content textarea, so the parsed body is the real text and this does not apply. A multi-chapter work whose chapter 1 title, summary, and content are all empty also skips the draft (`parseNestedChapter` returns nil) and does not post content.

Smallest fix: remember whether the content textarea was in the form, and do not append `work[chapter_attributes][content]` unless it was. Keep posting the title, which the page did contain.

## A4-2. Series save drops the co-creator byline

`Features/Writing/SeriesEditView.swift:153-154`

```swift
SubjectFormRow(label: "Creators", arrangement: .control) {
    TextField("Add a co-creator byline", text: $form.creators.coauthorByline)
```

`Models/AO3WritingModels.swift:727-741`

```swift
func parameters() -> [(String, String)] {
    var pairs: [(String, String)] = [
        (AO3WorkFormField.authenticityToken, csrfToken),
        (AO3WorkFormField.seriesFormTitle, title),
        (AO3WorkFormField.seriesSummary, summary),
        (AO3WorkFormField.seriesNotes, notes),
        (AO3WorkFormField.seriesComplete, isComplete ? "1" : "0")
    ]
    ...
    for id in creators.selectedPseudIDs {
        pairs.append((AO3WorkFormField.seriesAuthorIDs, id))
    }
    return pairs
}
```

`parseSeriesForm` stores creators with prefix `"series"` (`Services/AO3Client+Works.swift:395`), and `parseCreators` reads `series[author_attributes][byline]` into `coauthorByline` (`AO3Client+Works.swift:844-848`). The work form posts the same kind of field when it is non-empty (`AO3WritingModels.swift:614-616`). The series encoder never does.

AO3's series edit page renders `pseuds/_byline` inside `form_for(@series)`, so the control is `series[author_attributes][byline]`. `series_params` permits `author_attributes: [:byline, ids: [], coauthors: []]`. `update` saves when the model is valid and sets `flash[:notice]` to "Series was successfully updated."

Failing case. Open Edit Series, type `friend (friend)` in "Add a co-creator byline", tap Save. The POST has title, summary, notes, complete, and pseud ids, and no byline. AO3 flashes success. `SeriesEditView.save` (`Features/Writing/SeriesEditView.swift:245-246`) shows that message. The co-creator is not invited. Reopening the form loads the byline AO3 stored, which is still empty.

Smallest fix: append `series[author_attributes][byline]` from `creators.coauthorByline` the way the work form appends `work[author_attributes][byline]`.

## A4-3. Bookmark refusal reported as success, composer closed

`Services/AO3WriteActions.swift:383-386`

```swift
let (status, responseBody) = try await submitWrite(request)
if (200 ... 399).contains(status), AO3Client.writeErrorMessage(in: responseBody) == nil {
    return existing == nil ? "Bookmarked." : "Bookmark updated."
}
```

`writeErrorMessage` (`Services/AO3Client.swift:1047-1050`) matches `.errorlist li, .error p, .flash.error, .flash.comment_error, .flash.caution`. The work-write classifier documents `error_messages_for` as an `#error` list and matches `#main #error li` instead (`Services/AO3Client+Works.swift:644-665`), because the shared selector does not.

AO3 `BookmarksController#create` renders `:new` when save fails, and `#update` renders `:edit`. Both templates call `error_messages_for :bookmark`. `Bookmark` rejects `bookmarker_notes` longer than `NOTES_MAX` (5000 in `config.yml`). That response is HTTP 200, with no success flash.

`Features/WorkDetail/AO3WorkActionsModel.swift:132-133` then does `showingBookmark = false` and sets the banner to the returned string.

Failing case. Open the bookmark composer, paste notes longer than 5,000 characters, tap save. AO3 re-renders the form with the length error and does not store the bookmark. `writeErrorMessage` does not see `#error li`. The method returns "Bookmarked." The sheet closes, so the notes are gone from the screen, and the banner says the bookmark was saved.

The subscribe branch is the same test (`AO3WriteActions.swift:129-130`): a 200 with no `writeErrorMessage` hit returns "Subscribed." `AO3WorkActionsModel.subscribe` (`Features/WorkDetail/AO3WorkActionsModel.swift:80`) then runs `onSubscribed`, which Work Detail sets to `downloadIfSubscribedWithoutEPUB` (`Features/WorkDetail/WorkDetailView.swift:457`). A refused subscribe that comes back as a bare 200 starts an EPUB download.

Smallest fix: classify the bookmark (and this subscribe branch) the way `workWriteError` / `readingsWriteResult` do. Success is a success flash or a 3xx. An `#error` list is a refusal. Anything else 2xx is unconfirmed. Close the composer and start the download only on success.

## A4-4. Uncapped assignment crawl to paint three numbers

`Services/AO3Client+Challenges.swift:71-84`

```swift
static func allChallengeAssignments(...) async throws -> [AO3ChallengeAssignment] {
    var assignments: [AO3ChallengeAssignment] = []
    for list in lists {
        var page = 1
        while true {
            try Task.checkCancellation()
            let result = try await fetchPage(list, page)
            assignments.append(contentsOf: result.assignments)
            guard page < result.totalPages else { break }
            page += 1
        }
    }
    return assignments
}
```

`Features/Challenges/ChallengeSettingsView.swift:545-553` calls it twice during `loadSettings`, once for `AO3ChallengeAssignmentList.sent` and once for `[.defaults]`, after the settings form loads. Prompt memes return before that (`539-542`). The rows are reduced to `matchedCount`, `unmatchedCount`, and `defaultsCount` (`550-557`). The row text is "N matched, N unmatched" (`594-598`) plus the defaults figure at line 430. `.task` starts `loadSettingsIfNeeded` (line 87). Pull to refresh calls `loadSettings` again (line 88) and walks the lists again. There is no page cap.

The same function is how Assignments fills its three lists (`Features/Challenges/ChallengeAssignmentsView.swift:505`) and how Sign-ups loads assignments to join (`Features/Challenges/ChallengeSignUpsView.swift:510`). Those screens are showing the rows, and they are still an uncapped walk of maintainer pages on open.

Policy, `AO3_NETWORKING_POLICY.md` line 47: no crawling of logged-in pages beyond the listed exceptions. Collections' whole-index crawl is capped at 25 and is user-initiated (line 25). This one is not on that list. The settings screen is the case called out in the brief: three numbers, every page, no "load all".

Failing case. As the owner, open Challenge Settings on a gift exchange with 40 pages of sent assignments. Before the three numbers appear, the app requests every page of sent assignments and every page of defaults. Pull to refresh does it again. A participant never gets this screen (`AO3CollectionDetailView.swift:391-392` gates it on the owner), so it is not a refused viewer. It is still the crawl the policy forbids.

Smallest fix: count matched and unmatched from the first page and the last page, the way `signUpTotal` does (`AO3Client+Challenges.swift:47-52`). Do not walk every page to add covered pinch hits into the third number. On Assignments and Sign-ups, page the list the user is looking at instead of calling `allChallengeAssignments` on appear.

## A4-5. The word "successfully" beats the parsed error list

`Services/AO3ChallengeActions.swift:283-313`

```swift
if let error = AO3Client.writeErrorMessage(in: body) {
    ...
    return .invalid(invalid)
}
if let notice = AO3Client.writeSuccessMessage(in: body)
    ?? (body.localizedCaseInsensitiveContains("successfully")
        ? "Challenge was successfully updated." : nil) {
    ...
    return .saved(message: notice, form: parsed)
}
...
if (200...299).contains(status),
   let parsed = try? AO3Client.parseChallengeSettingsForm(...),
   !parsed.generalErrors.isEmpty || !parsed.fieldErrors.isEmpty {
    return .invalid(parsed)
}
```

`parseChallengeFormErrors` (`AO3Client+Challenges.swift:896-903`) collects `#error ul li, .error ul li, #errorExplanation li`. `writeErrorMessage` does not match those. The substring check returns `.saved` before that parsed-error check runs.

`Features/Challenges/ChallengeSettingsEditView.swift:775-778` on `.saved` sets the notice and then calls `saveCollectionSwitches()`.

The same substring sits in front of the parsed-error check in `submitCollectionForm` (`Services/AO3CollectionActions.swift:443-449`, "successfully created" / "successfully updated") and in `savePreferences` (`Services/AO3PreferencesActions.swift:55-57`, "successfully updated"). The work and readings writers already refuse this: a re-rendered form contains the writer's own text (`AO3WorkActions.swift:571-574`, `AO3WriteActions.swift:319-320`).

Failing case. Gift-exchange sign-up instructions contain "Entries that are successfully matched will be emailed." Set sign-ups to close before they open and tap Save. AO3 re-renders the edit form (HTTP 200) with the date error in the `#error` list and no `.flash.error`. `writeErrorMessage` returns nil. The body still contains "successfully". `updateChallengeSettings` returns `.saved` with the message "Challenge was successfully updated." The dates are not saved. The screen shows the notice. If a collection switch was also changed on that tap, `saveCollectionSwitches` still POSTs it.

Smallest fix: delete the substring fallbacks. Keep error flash, then success flash, then 3xx, then the parsed `#error` list, then unconfirmed.

## A4-6. Work-page unsubscribe and Mark for later treat any 2xx as success

`Services/AO3WriteActions.swift:105-113`

```swift
let (status, responseBody) = try await submitWrite(request)
if (200 ... 399).contains(status) { return "Unsubscribed." }
throw AO3WriteError.rejected(
    AO3Client.writeErrorMessage(in: responseBody) ?? "Couldn't unsubscribe."
)
```

`Services/AO3WriteActions.swift:189-193`

```swift
let (status, responseBody) = try await submitWrite(request)
if (200 ... 399).contains(status) { return "Marked for later." }
throw AO3WriteError.rejected(
    AO3Client.writeErrorMessage(in: responseBody) ?? "Couldn't mark for later."
)
```

Neither branch looks for an error flash before returning success. `mark_for_later` and the work-page unsubscribe redirect on success. `submitWrite` follows the redirect, so a real success is a final 200 that carries the notice. A final 200 with no notice is the case `unmarkForLater` and `unsubscribe(path:)` already call unconfirmed (`AO3WriteActions.swift:206-208` and `170-173`, via `readingsWriteResult`). These two older branches still treat that 200 as the action having happened. The subscribe half of `toggleSubscribe` at least requires `writeErrorMessage` to be nil (`129-130`); the unsubscribe half does not.

Failing case. Tap Mark for later. AO3 answers 200 with a maintenance or interstitial page and no flash. The banner says "Marked for later." The work was not added. Tap Unsubscribe on a work and get the same kind of 200: the banner says "Unsubscribed." and `writeErrorMessage` is never consulted, so a `.flash.error` on that 200 is also reported as success. The menu label is not flipped locally; the banner is the lie. `giveKudos` (`41-44`) is not this bug: the comment at `416-418` says `kudos.js` has no flash and uses 422 for "already left", and the 200 branch matches that endpoint.

Smallest fix: return `readingsWriteResult` from both branches, as `unmarkForLater` and the subscriptions-index `unsubscribe` already do.

## Unconfirmed

- Sign-up save does not post `form.hiddenFields` (`AO3Client+Challenges.swift:451-462`). Prompt ids are posted when `id > 0` (`757`). A hidden `tag_set_attributes[id]` on an existing prompt is not. The signup fixture that was grepped has no such input. Confirm with an edit-sign-up page from otwarchive's signup form. If that hidden id is present, editing tags can create a second tag set or fail the nested update.
- `collectionFormParameters` (`AO3Client+Collections.swift:714-759`) posts preference and profile ids and does not append the rest of `hiddenFields`. Confirm against a collection edit page whether any other hidden nested id is required. Reveal and un-anon POST this encoder.
- Unchecking "This is a translation" omits the field instead of posting `0` (`AO3WritingModels.swift:578-580`). Existing parents are delete links, not form fields. Confirm the parent setter only if an unchecked translation on a still-filled URL must clear the flag.
- `Work#challenge_assignment_ids=` replaces the set only when the key is present (`work.rb`). The app drops `challenge_assignment_ids[]` and `challenge_claim_ids[]` because `parseCarryHiddenFields` skips names ending in `[]` (`AO3Client+Works.swift:860`) and `parameters` never adds them. That is not a wipe. It does mean the app cannot tick an open assignment. Not filed as a bug.
- `AO3CollectionItemsView.submit` (`513-524`) does not reject a second entry when `phase` is already `.submitting`. The button disables on that flag, and the flag is set inside `Task { await submit() }`. A second tap queued before the first task reaches its await can POST the same drafts again. The updates look idempotent. Confirm with a double tap if that second POST is worth fixing; the work editor already guards this beat (`WorkEditView.perform`, `557-564`).
- `WritingRecoveryWriter` (`33-35`) says a failed last checkpoint is not retried. The editor does surface it (`WritingTextEditor.swift:421-425`) and copies the checkpoint into the form binding before the disk write (`397-400`). Not filed. A crash in the window after a failed last write and before the next successful one would lose that checkpoint. That is the comment, and the comment matches the code.

`PromptMemeView` was only grepped. The old "value not arrived, so look it up again" loop was not found. `WritingBufferPreview` was not opened.

## Not read

Not opened, or only named by a grep: `WritingBufferPreview`, most of `PromptMemeView`, `EditTagsView`, `EditMultipleWorksView`'s save body, `WritingChaptersView`, `WritingPreviewView`, `WritingNativeTextView.restore`, the preferences field encoder, inbox and comment UI, author-profile paging, the subscriptions enricher, `AO3CollectionsList`'s 25-page cap (the policy describes it; the cap was not re-read), bulk-edit parameter building past its comment, and tests. `seriesWorks` (`AO3Client.swift:1292-1300`) is an uncapped series-page walk used by an explicit Download series and by series preservation, which the policy's batch row already allows. It is not filed. Collection item submit, collection delete, challenge withdraw, and reveal were read far enough to see confirmation dialogs and a generation check on the items POST. No wrong-collection apply was found in that path.

## Triage (Claude, 2026-10-08)

Each finding was read against the Swift code and against otwarchive's source
(`works/_standard_form.html.erb`, `works_controller.rb`, `validation_helper.rb`,
`bookmarks_controller.rb`). Five are real; one is an open owner question.

- **A4-1 real.** Fixed on iOS (T-362, `9c753a11`) and on Android, which had copied it: the
  chapter text is sent, shown and required only when AO3 served its box (`contentServed`).
- **A4-2 real, iOS only** (Android has no series form yet; its brief must send the byline). Fixed in T-362.
- **A4-3 real on both.** `writeErrorMessage` now reads `#error li` on both apps.
- **A4-4 known:** owner question 16 (iOS walks every page of a challenge's lists). Not changed.
- **A4-5 real, closed by A4-3's fix:** the validation list is checked before the word
  "successfully" in all three places. The substring fallbacks remain (P3).
- **A4-6 real on both.** Unsubscribe on a work page and Mark for later need AO3's notice or a
  redirect; a flashless 200 is "didn't confirm". Subscribe and Bookmark still accept one (P3).
- Unconfirmed suspicions: not yet looked at. The sign-up form's hidden fields matter for brief 3bl.
