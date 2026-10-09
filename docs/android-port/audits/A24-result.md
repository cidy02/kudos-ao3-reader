# Audit A24 result

Read-only. No source edit, build, emulator, commit, or request to archiveofourown.org.
iOS reference is `kudos-ios-polish/kudos-ao3-reader`. A22 and A23 are not re-filed.
Line numbers are the files as they are on `android/agent-grok-a1` at this read.

| id | severity | where | statement |
|---|---|---|---|
| A24-1 | P2 | `AO3WriteRepository.kt:112`, `WritingSeriesState.kt:116` | After a series reorder or remove POST has already been sent, a session change is reported as "not saved" / "nothing was removed" instead of iOS's unconfirmed verdict. |
| A24-2 | P3 | `WritingSeriesScreen.kt:106` | Remove works says "1 works". iOS says "1 work". |
| A24-3 | P3 | `SeriesWorksScreen.kt:166` | The series page offers Reorder when fewer than two works are loaded. iOS hides it. |

## A24-1 A finished series reorder or remove is described as if it never went out

`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:109-126`

```kotlin
val response = withContext(NonCancellable) {
    client.postAuthenticatedInSession(action, fields, writeHeaders(token, url), expectedGeneration)
}
requireCollectionSession(expectedGeneration)
when (response) {
    is AO3Result.Failure -> return response
    is AO3Result.Success -> parser.writeErrorMessage(response.value.body)?.let {
        return AO3Result.Failure(AO3Error.Validation(it))
    }
}
val fresh = try {
    when (val result = client.getAuthenticated(url)) {
        is AO3Result.Failure -> null
        is AO3Result.Success -> try { seriesParser.parseManage(result.value.body, url) } catch (_: Exception) { null }
    }
} catch (cancelled: CancellationException) { throw cancelled }
catch (_: Exception) { null }
requireCollectionSession(expectedGeneration)
```

`requireCollectionSession` (`AO3WriteRepository.kt:479-480`) throws `CancellationException` when `client.sessionGeneration()` is no longer `expectedGeneration`. The POST itself is inside `NonCancellable`, so it is not cancelled.

`android/app/src/main/java/io/github/cidy02/kudos/writing/WritingSeriesState.kt:116-118` and `:136-137`

```kotlin
} catch (_: CancellationException) {
    if (active) mutable.value = state.value.copy(error = if (order) "Your AO3 session changed, so the order was not saved."
        else WORK_FORM_SESSION_CHANGED)
```

```kotlin
} catch (_: CancellationException) {
    if (active) mutable.value = state.value.copy(error = "Your AO3 session changed, so nothing was removed.")
```

iOS checks the generation before the POST and again before reading the manage page, and a mismatch on the read-back is unconfirmed, not a cancellation. `Services/AO3WorkActions.swift:296-302` and `:356-363`:

```swift
let (_, body) = try await submitWrite(request, using: client)
if let error = AO3Client.workWriteError(in: body) {
    throw AO3WorkWriteError.rejected(error)
}
guard let rows = await readBackManagePage(manageURL, expectedGeneration: expectedGeneration, using: client),
      rows.sorted(by: { $0.position < $1.position }).map(\.serialWorkID) == orderedSerialWorkIDs
else { throw AO3WorkWriteError.unconfirmed }
```

```swift
guard let html = try? await workFormHTML(at: url, using: client),
      sessionGeneration == expectedGeneration
else { return nil }
```

`requireSessionGeneration` (`Services/AO3AuthService.swift:765-768`) throws `CancellationError`, and the reorder screen uses that only for a real cancellation (`Features/Writing/SeriesEditView.swift:414-417`). Unconfirmed is a different error (`Models/AO3WritingModels.swift:1070-1072`): "AO3 replied but didn't confirm the change went through. Check on AO3 before trying again." Remove is the same split (`AO3WorkActions.swift:344-350`, `SeriesEditView.swift:557-560`).

Failing case. Reorder two works and tap Save. The POST to `/series/{id}/update_positions` finishes; AO3 has the new order. Verify Session (or any other generation bump) lands before line 112, or the read-back GET is cancelled. Android shows "Your AO3 session changed, so the order was not saved." Remove shows "Your AO3 session changed, so nothing was removed." The writer can reopen the form under the new generation and send a second order, or delete the series believing the work is still in it. iOS shows the unconfirmed sentence and tells them to check AO3 before trying again.

`saveSeries` has the same fence after its POST (`AO3WriteRepository.kt:53-57`) and the same catch turns it into "Your AO3 session changed. Reopen this form before saving." iOS `saveSeries` (`AO3WorkActions.swift:231-238`) judges the body and does not throw `CancellationError` for a generation change. `briefs/3bw-result.md` records that Save uses the work-form sentence for its session fence, so the sentence itself is not the finding. Discarding a finished POST's verdict is.

Smallest fix. Once `postAuthenticatedInSession` has returned, do not throw `CancellationException`. If the generation no longer matches, or the read-back is cancelled, return `AO3Result.Failure(AO3Error.Validation(AO3CollectionFields.UNCONFIRMED))`. Keep the pre-POST `requireCollectionSession` throws so a change before the POST still uses iOS's cancellation sentences.

## A24-2 Remove works says "1 works"

`android/app/src/main/java/io/github/cidy02/kudos/writing/WritingSeriesScreen.kt:105-107`

```kotlin
SubjectHeaderBlock(kicker = "AO3 Account", title = if (ordering) "Reorder" else if (removing) "Remove works" else "Edit series",
    subtitle = if (ordering) title else if (removing) "$title · ${rows?.size ?: 0} works" else subtitle,
    palette = palette, gutter = SubjectMetrics.accountGutter)
```

iOS `Features/Writing/SeriesEditView.swift:463-466`:

```swift
SubjectHeaderBlock(
    kicker: "AO3 Account", title: "Remove works",
    subtitle: "\(seriesTitle) · \(rows.count) work\(rows.count == 1 ? "" : "s")",
    palette: palette, gutter: gutter
)
```

The same Android file already pluralizes the footnote (`worksPhrase`, `WritingSeriesScreen.kt:236`: one work is "the work"). The series-page entrance pluralizes its own subtitle (`SeriesWorksScreen.kt:118`). `briefs/3bw-result.md` inventories the remove subtitle as `{title} · N work(s)` and does not record dropping the plural.

Failing case. Open Remove works on a series of one work (the row is still there; the Remove button is hidden and the last-work footnote shows). The header reads "Dawn Cycle · 1 works". It should read "Dawn Cycle · 1 work".

Smallest fix. When `rows?.size == 1`, use "work". Otherwise "works".

## A24-3 The series page offers Reorder for a one-work series

`android/app/src/main/java/io/github/cidy02/kudos/app/SeriesWorksScreen.kt:164-166`

```kotlin
if (canEdit && formRepository != null && writes != null) {
    DropdownMenuItem(text = { Text("Edit series", color = tokens.primaryInk, lineHeight = 21.sp) }, onClick = { showMenu = false; editing = false })
    DropdownMenuItem(text = { Text("Reorder", color = tokens.primaryInk, lineHeight = 21.sp) }, onClick = { showMenu = false; editing = true })
}
```

iOS `Features/Authors/AO3SeriesDetailView.swift:100-104` offers Reorder only when the loaded works number more than one:

```swift
if canEditSeries, works.count > 1 {
    Button { isReorderingSeries = true } label: {
        Label("Reorder", systemImage: "arrow.up.arrow.down")
    }
}
```

Edit series stays available for the owner either way (`AO3SeriesDetailView.swift:109-112`). The author-list menus on both platforms offer Reorder with no count (`AuthorProfileScreen.kt:458-461`). That part matches iOS and is not this finding. The reorder screen itself refuses a list shorter than two (`WritingSeriesState.kt:97`, `WritingSeriesScreen.kt:202`).

Failing case. Open a series you own whose loaded page has one work. The menu contains Reorder. Tapping it opens the reorder screen, and Save does nothing useful. iOS does not show the row.

Smallest fix. Show that menu item only when `(page?.works?.size ?: 0) > 1`.

## Fixes of 2026-10-09

Each of these closes the case its comment names. None of them is re-filed. What each still does is below.

**A22-1, comments reload.** `CommentsViewModel.load` (`CommentsViewModel.kt:146-150`) clears the reply, edit, and composer parent only when the composer is not presented. An unconfirmed edit does not call `load`. The stated case, a reply or edit whose text was then posted as a new comment, is closed. The composer sheet stays up during `Loading` (`CommentsScreen.kt` presents it from `composerPresented`).

**A22-2, focused thread cache.** `AO3CommentRepository` reads and writes the cache only when `useCache && focusedCommentId == null` (`AO3CommentRepository.kt:58` and `:73`). The inbox author lookup calls `loadThread` with `useCache = false`. Closed.

**A22-3, one load, inbox thread first.** `load` sets `_focusedCommentId` before the first suspend, cancels the previous job, and `ensureActive` drops a stale answer (`CommentsViewModel.kt:142-157`). The screen's focus effect loads again only when the focused id differs (`CommentsScreen.kt:131-136`), and the chapter effect bails when a focus is set (`:139-143`). The race the comment names is closed.

**A22-4, subscriptions after Verify Session.** `loadSubscriptions` (`HomeViewModel.kt:201-207`) sees a generation mismatch while still signed in and asks again with the new state, and that call is awaited before the outer `finally` clears the loading flag. The empty shelf from a dropped answer is closed. A generation that moves again during the inner request asks one more time. It is not a loop unless something in the load itself bumps the generation. That was not shown.

**A22-5, cached replies.** `CommentCache.readOnly` (`CommentCache.kt:56-62`) nulls `editPath` and `deletePath`, sets `canReply` false, and walks `replies`. Closed for those write affordances.

**A23-1, Edit tags token.** `AO3WorkFormEncoder.encode` (`AO3WorkFormEncoder.kt:8-14`) always sends `authenticity_token`, `_method`, and the submit name for an Edit tags form. The seven tag fields still require a served name. The meta-only body token is no longer dropped. Closed.

**A23-2, Replace Library.** `applyReplaceWork` (`BackupMergeService.kt:1230-1260`) keeps `freedAt` and `authorIdentitiesJSON` from the device, ORs `hasGivenKudos`, and takes `keepInProgressOverride` and `hiddenFromHistoryAt` from the archive only when that key is present. The three fields A23 named survive. The function still starts from `restored.copy`, so a field it does not name comes from the archive. `epubDigest` is one of those. See Unconfirmed.

**A23-3, collection membership tombstone.** Affirmed memberships are stored before the local-clock return (`BackupMergeService.kt:1324-1331` and `:1390`). The second pass (`:1448-1460`) then removes a work that is not affirmed when the tombstone is not strictly older than `lastMembershipChangedAt ?: lastModifiedAt`. Replace skips the pass. The test case A23 named, a collection that is in the file, is closed. Equal timestamps suppress on both platforms (`SyncMerge.tombstoneResolution` at `:2539-2542`; iOS `suppressesCollectionMembership` uses `>=`, `KudosBackup.swift:4253`). The pass also walks local collections the file never mentioned, because `affirmedMemberships[id]` is then empty. iOS's sweep sits inside `for archived in contents.manifest.collections` (`KudosBackup.swift:2551` and `:2706-2735`), so a collection absent from the file is left alone. `DECISIONS.md` (2026-10-09, backup merge) records the broader rule: a membership deletion removes the work from a collection that already has it, unless the archive lists it and is newer. Not filed.

**A23-4, tag lists.** Both arms of `mergeWork` (`BackupMergeService.kt:815-823` and `:842-851`) and `applyReplaceWork` (`:1253-1259`) union the seven lists through `mergeStringLists`. The replacement A23 named is closed. `mergeStringLists` (`:2302-2304`) dedupes with `normalizedNames`, which is case-sensitive (`BackupMappers.kt:838-844`). iOS `TagMerge.merged` (`Services/TagMerge.swift:8-16`) dedupes case-insensitively and keeps the first casing. A list that already differed only by case keeps both spellings. The losing arm used this helper before this fix, and the decision says the lists are merged. Not filed.

**A23-5, two chip removes.** The click reads `model.state.value.form` at tap time (`WritingEditTagsScreen.kt:171-172`). `writingTags` updates the state before it returns, so a second click on the same composition sees the list after the first removal. Closed. The `.value` read is inside the click, not the composition that draws the chips.

**More on AO3.** `AccountMoreOnAO3Screen.kt:124-179` matches `AccountMoreOnAO3View.swift` titles, order, suffixes, and the two footnotes, and `AO3ArchivePage` / `AO3MoreOnAO3Route` (`AccountMoreOnAO3View.swift:5-12` and `:57-61`). User rows are `/users/{name}/{suffix}` (`:174-179`); a signed-out user row returns null and does not open, as `AccountExternalNavCard.userURL` returns nil (`AccountExternalNavCard.swift:121-125`). iOS percent-encodes with `urlPathAllowed` and Android with `URLEncoder` (`+` rewritten to `%20`). AO3 usernames cannot contain `/`. Closed.

**Show in Library.** The button is shown when at least one file was imported (`KudosApp.kt:93` and `:230-236`) and increments `showLibraryRequest`. `MainScaffold.kt:126-127` calls `navigateShellRoot(Routes.Library)`, which pops to the start destination and opens Library (`MainScaffold.kt:608-615`). It does not open the work. iOS switches `router.selection` to `.library` when `notice.workID != nil` (`ContentView.swift:137-146`). A failure-only notice hides the button. Closed.

**Nearby tiles.** `nearbyPageWindow` (`KudosPaginationBar.kt:266-272`) is the same window as `SearchPaginationBar.nearbyPageWindow` (`SearchPaginationBar.swift:266-272`). A tile assigns `draft` (`KudosPaginationBar.kt:204`) and Go is what calls `onSelect` (`:247-249`). Closed.

**Share Profile.** The row shares `AO3AuthorUrls.userDashboardUrl(route.username, route.pseud)` (`AuthorProfileScreen.kt:206-214`), which is `/users/{name}` or `/users/{name}/pseuds/{pseud}` (`AO3AuthorUrls.kt:25-34`). iOS shares `route.dashboardURL` (`AuthorProfileView.swift` ShareLink; `AO3AuthorModels.swift:111-113`). Closed. Open on AO3 on this screen still uses `userProfileUrl` (`AuthorProfileScreen.kt:203`). That line is older than this menu item and is not part of the share fix.

## Series form, checked and not filed

Save, reorder, and remove addresses match iOS. Save POSTs the captured action, referer that action, header token from the loaded form. The modeled body order is `authenticity_token`, a nonempty `_method`, title, summary, notes, complete `1`/`0`, repeated pseud ids, and a nonempty byline (`AO3SeriesForm.kt:44-52`, `AO3WorkActions.swift` `saveSeries` via `submitWorkForm`). Reorder POSTs `/series/{id}/update_positions` with `authenticity_token` and `serial[]`, no `_method`, referer the manage page, meta csrf-token only (`AO3WriteRepository.kt:94-107`). Remove POSTs `/serial_works/{id}` with `authenticity_token` and `_method=delete`. Both refuse a changed membership and a last-work removal, then require the manage page to show the new order or the missing id (`:99-129`). iOS does the same (`AO3WorkActions.swift:272-350`).

Ownership is the registered username from a trusted `/users/{name}/…` link (`AO3AuthorModels.kt:177-181`), compared ignore-case, on the series page (`SeriesWorksScreen.kt:112`) and the author list (`AuthorProfileScreen.kt:449-450`). A pseud that merely equals the account name does not match. That is iOS `AO3SeriesSummary.isCreator` (`AO3AuthorModels.swift:480-496`).

The work-form hand merge still returns in order: Edit tags (`WritingWorkFormScreen.kt:94-112`), series reorder (`:117-121`), text editor, tag editor, association picker, chapters, tag choices. Rating, language, skin, comments, and the date are sheets on the form (`:327-338`), composed only when those earlier returns are not taken. Reorder from the association picker returns to the picker, because `association` is remembered above the return. Edit tags cannot be set while reorder is showing. No shared state that leaks across those screens was shown.

Recorded, and not filed: an empty byline is replayed as served (`briefs/3bw-result.md`); modeled fields, including the body token, are sent only when AO3 served that name (`AO3SeriesForm.kt:36-37`, same result file); the series form does not reload on a session change; a failed manage GET leaves the editor with no work rows; drag has no edge auto-scroll; Save's enabled state uses Foundation whitespaces; New series and Delete series stay in the browser; there is no native series-delete POST. The collection sweep's extra scope is the decision cited under A23-3.

## Unconfirmed

**A top-level comment draft can land in an open reply.** `load`'s success path writes a stored top-level draft when `_draft` is empty and `_editTarget` is null (`CommentsViewModel.kt:170-172`). It does not look at `_replyTarget` or `_composerPresented`. `startReply` clears `_draft` and then loads the reply draft (`:326-338`). If a `load` finishes in that window, the reply field receives the top-level draft. Confirm by showing a load that can complete while a reply composer is open and the field is still empty. The sheet is modal, and reply rows are not drawn during `Loading`, so the window may be unreachable.

**The comments model is keyed only by work id.** `CommentsScreen.kt:121-124`. The focus effect does not reload when `focusedCommentId` is null (`:131-136`). Opening that work's ordinary comments after an inbox thread on the same model would keep the thread. Confirm whether the comments destination's `ViewModelStore` entry survives that navigation.

**Reorder and remove treat a broad error parse as a refusal and skip the read-back.** They call `writeErrorMessage` (`AO3WriteRepository.kt:115`), which matches `.error p`, `.flash.error`, and `.flash.caution` anywhere (`AO3WriteFormParser.kt:155-159`). iOS calls `workWriteError` (`AO3WorkActions.swift:297`, `AO3Client+Works.swift:658-669`), which stays inside `#main`, ignores `#previewpane`, and ignores writer HTML. Confirm with a positions or serial-work response whose body contains one of the broad selectors, while the manage page already shows the new order or the missing row.

**Replace still copies `epubDigest`.** `applyReplaceWork` does not keep the local digest, and iOS `apply` never restores it (`KudosBackup.swift:4523-4533`) because a copied digest can make the next sync skip the download. Android's sync-down compares the remote manifest's digest to a hash of the local file (`SyncRepository.kt:649-654`), and sync-up republishes a hash of the bytes on disk (`:282-286`). That is not the permanent skip. Confirm on the manual `.kudosbackup` export: it passes the stored digest through (`BackupMappers.kt:179`) and was not checked for a later import that treats that digest as a skip key.

**A series edit page whose token lives only in the meta tag.** `parameters()` drops `authenticity_token` unless a served control has that name (`AO3SeriesForm.kt:36-37`). The header still carries the token. `briefs/3bw-result.md` records the served-name filter, which is why this is not a finding. The demo fixture includes the hidden input, so the tests do not catch a meta-only page. Confirm against a real series edit document that has `meta[name=csrf-token]` and no `input[name=authenticity_token]`.

## Not read

- `KudosAppContainer.kt` and the rest of `AO3AuthorParser.kt` beyond the series-blurb creator links.
- The bodies of `WritingSeriesTest`, `WritingSeriesScreenTest`, and `DemoSeriesFormTest`. One assertion that Save's session sentence is `WORK_FORM_SESSION_CHANGED` was grepped, not the surrounding test.
- The comments route in the navigation graph, so the work-id view-model lifetime above is unconfirmed.
- Whether `accountListRepository.load` itself changes `sessionGeneration`.
- `DemoNetwork.kt` outside `DemoSeriesWrites` (`:1101-1173`).
- `WritingWorkFormScreen.kt` below the choice and date sheets.
- Whether `SeriesWorksScreen`'s `page.works` is only the current page or an accumulation. The reorder blurb list is whatever that property holds (`SeriesWorksScreen.kt:117`). iOS passes the works the series screen has already loaded.
- No test was run, and nothing was opened on an emulator.

## Triage (Claude, 2026-10-09)

Three findings, all real, all fixed (gate 2,324, plus one new test). Its review of the day's
fixes found each closes its case.

- **A24-1 real, and wider than the series form.** Every write in `AO3WriteRepository`
  checked the session again after its POST had returned and, if the session had moved on,
  threw the cancellation that screens word as "not saved" or "nothing was removed". The
  request had gone out. All fourteen such checks (series, works, chapters, tags, sign-ups,
  prompt claims, tag sets, collections and their items) now return "AO3 replied but didn't
  confirm the change went through. Check on AO3 before trying again." The check **before**
  a POST still stops it outright. One test pinned the old words for a series save and was
  corrected.
- **A24-2 real, fixed**: "1 work".
- **A24-3 real, fixed**: the series page offers Reorder only with more than one work loaded.

From its notes:

- **The series form dropped its token from the body** when AO3 gave it only in the meta tag
  (the fault A23-1 found in Edit tags). Fixed; test
  `theTokenAndMethodGoInTheBodyEvenWhenOnlyTheMetaTagCarriesTheToken`.
- **The collection membership pass** (A23-3) ran over every local collection; iOS runs it
  only for a collection the archive carries. Narrowed to match.
- Not changed: tag lists are merged case-sensitively here and case-insensitively on iOS (two
  spellings that differ only by case are both kept); `epubDigest` still comes from the
  archive on Replace; `writeErrorMessage` looks for an error anywhere on the page where iOS
  looks inside `#main`.
- Unconfirmed, not looked at: a top-level draft landing in an open reply if a load finishes
  in that instant; a comments view model kept from an Inbox thread when the same work's
  comments are opened next.
