# A41 Audit Result

## 1. The writes
- `saveWork`: `Services/AO3WorkActions.swift:126`
- `editTags`: `Services/AO3WorkActions.swift:145`
- `createChapter`: `Services/AO3WorkActions.swift:166`
- `updateChapter`: `Services/AO3WorkActions.swift:180`
- `updateWorkTotals`: `Services/AO3WorkActions.swift:195`
- `saveChapterUpdatingTotal`: `Services/AO3WorkActions.swift:206`
- `saveSeries`: `Services/AO3WorkActions.swift:229`
- `createSeries`: `Services/AO3WorkActions.swift:264`
- `reorderSeries`: `Services/AO3WorkActions.swift:290`
- `removeWorkFromSeries`: `Services/AO3WorkActions.swift:334`
- `bulkEditWorks`: `Services/AO3WorkActions.swift:405`
- `deleteWork`: `Services/AO3WorkActions.swift:439`
- `deleteWorks`: `Services/AO3WorkActions.swift:454`
- `deleteDraft`: `Services/AO3WorkActions.swift:473`
- `deleteChapter`: `Services/AO3WorkActions.swift:485`
- `submitWorkForm`: `Services/AO3WorkActions.swift:570`
- `submitDelete`: `Services/AO3WorkActions.swift:600`

- `giveKudos`: `Services/AO3WriteActions.swift:27`
- `postComment`: `Services/AO3WriteActions.swift:55`
- `toggleSubscribe`: `Services/AO3WriteActions.swift:99`
- `unsubscribe`: `Services/AO3WriteActions.swift:151`
- `markForLater`: `Services/AO3WriteActions.swift:180`
- `unmarkForLater`: `Services/AO3WriteActions.swift:212`
- `deleteReading`: `Services/AO3WriteActions.swift:243`
- `clearReadingHistory`: `Services/AO3WriteActions.swift:280`
- `saveBookmark`: `Services/AO3WriteActions.swift:358`
- `writeRequest`: `Services/AO3WriteActions.swift:443`

- `createCollection`: `Services/AO3CollectionActions.swift:54`
- `updateCollection`: `Services/AO3CollectionActions.swift:79`
- `deleteCollection`: `Services/AO3CollectionActions.swift:98`
- `revealCollection`: `Services/AO3CollectionActions.swift:130`
- `unanonCollection`: `Services/AO3CollectionActions.swift:145`
- `approveCollectionItem`: `Services/AO3CollectionActions.swift:160`
- `rejectCollectionItem`: `Services/AO3CollectionActions.swift:176`
- `updateCollectionItems`: `Services/AO3CollectionActions.swift:189`
- `updateUserCollectionItems`: `Services/AO3CollectionActions.swift:230`
- `acceptMember`: `Services/AO3CollectionActions.swift:277`
- `declineMember`: `Services/AO3CollectionActions.swift:289`
- `inviteMaintainer`: `Services/AO3CollectionActions.swift:311`
- `joinCollection`: `Services/AO3CollectionActions.swift:335`
- `leaveCollection`: `Services/AO3CollectionActions.swift:354`
- `submitWorkToCollection`: `Services/AO3CollectionActions.swift:373`
- `updateParticipantRole`: `Services/AO3CollectionActions.swift:402`
- `submitCollectionForm`: `Services/AO3CollectionActions.swift:426`

- `saveChallengeSignUp`: `Services/AO3ChallengeActions.swift:34`
- `withdrawSignUp`: `Services/AO3ChallengeActions.swift:74`
- `withdrawSignUpAfterClose`: `Services/AO3ChallengeActions.swift:94`
- `reportAssignmentDefault`: `Services/AO3ChallengeActions.swift:100`
- `claimPinchHit`: `Services/AO3ChallengeActions.swift:120`
- `markAssignmentDefaulted`: `Services/AO3ChallengeActions.swift:140`
- `updateAssignments`: `Services/AO3ChallengeActions.swift:156`
- `claimPrompt`: `Services/AO3ChallengeActions.swift:177`
- `releasePrompt`: `Services/AO3ChallengeActions.swift:197`
- `saveTagSetFields`: `Services/AO3ChallengeActions.swift:215`
- `reportRejectedTag`: `Services/AO3ChallengeActions.swift:237`
- `updateChallengeSettings`: `Services/AO3ChallengeActions.swift:261`

## 2. The callers
- `saveWork`: `Features/Writing/WorkEditView.swift:571`
  - (d) the caller only dismisses or shows a message.
- `deleteWork`: `Features/Writing/WorkEditView.swift:538`, `Features/Authors/AuthorProfileView.swift:611`
  - `WorkEditView.swift`: (d) the caller only dismisses or shows a message.
  - `AuthorProfileView.swift`: (a) the caller reloads its own data from AO3 (calls `await model.refresh(auth: auth)`).
- `deleteDraft`: `Features/Writing/WorkEditView.swift:544`
  - (d) the caller only dismisses or shows a message.
- `deleteWorks`: `Features/Authors/OwnWorksBulkBar.swift:73`
  - (b) the caller calls a closure handed to it (`onDeleted`). `AuthorProfileView.swift:106` passes one and it calls `await model.refresh(auth: auth)`.
- `bulkEditWorks`: `Features/Writing/EditMultipleWorksView.swift:371`
  - (b) the caller calls a closure handed to it (`onSaved`).
- `createChapter`, `updateChapter`, `deleteChapter`: `Features/Writing/AddChapterView.swift:383`, `445`
  - (b) the caller calls a closure handed to it (`onSaved`). `WritingChaptersView.swift:69` passes one and it does `reload += 1`. `AuthorProfileView.swift:580` passes one and does `await model.refresh(auth: auth)`. `WorkEditView.swift:451` passes one and does `needsPublicationRefresh = true`.
- `withdrawSignUp`: `Features/Challenges/ChallengeSignUpView.swift:688`
  - (d) the caller only dismisses or shows a message.
- `leaveCollection`: `Features/Challenges/CollectionMaintainersView.swift:504`
  - (d) the caller only dismisses or shows a message.
- `deleteCollection`: `Features/Account/AO3CollectionFormView.swift:573`
  - (d) the caller only dismisses or shows a message.

## 3. The screen behind
- **`saveWork`, `deleteWork`, `deleteDraft`**:
  - Pushed by: `Features/Authors/AuthorProfileView.swift:86` / `575` and `Features/Writing/WritingDraftsView.swift:91` via `WritingWorkDestination`.
  - What it shows: `AuthorProfileView.swift:505` shows `row.title` from `model.works`.
  - Does it read again?: None. (Searched `Features/Authors/AuthorProfileView.swift` and `Features/Writing/WritingDraftsView.swift` for `onChange`, `onAppear`, or `task(id:)` changes triggered by the dismiss, and found none).
- **`withdrawSignUp`**:
  - Pushed by: `Features/Account/AO3CollectionDetailView.swift:384` (`ChallengeSignUpView`).
  - What it shows: `Features/Account/AO3CollectionDetailView.swift:377` shows `show.collection.viewerIsSignedUp`.
  - Does it read again?: None. (Searched `Features/Account/AO3CollectionDetailView.swift` for `onChange`, `onAppear`, or `task(id:)` changes triggered by the dismiss, and found none).
- **`leaveCollection`**:
  - Pushed by: `Features/Account/AO3CollectionDetailView.swift:337` (`CollectionMaintainersView`).
  - What it shows: `Features/Account/AO3CollectionDetailView.swift:336` shows "Moderation" section.
  - Does it read again?: None. (Searched `Features/Account/AO3CollectionDetailView.swift` for `onChange`, `onAppear`, or `task(id:)` changes triggered by the dismiss, and found none).
- **`deleteCollection`**:
  - Pushed by: `Features/Account/AO3CollectionsList.swift:114`.
  - What it shows: The list of collections.
  - Does it read again?: Yes, `Features/Account/AO3CollectionsList.swift:151` has `.onReceive(NotificationCenter.default.publisher(for: .ao3CollectionDeleted)) { ... refreshAfterDelete(slug: slug) }`.

## 4. The cache
- `removeSeries`: `Services/AO3WorkActions.swift:253`. Triggered by `saveSeries`, `reorderSeries`, `removeWorkFromSeries`.
- `invalidate`: `Services/AO3AuthorProfileService.swift:881`. Triggered by `.parse` error.
- `invalidateAuthorDashboards`: `Services/AO3AuthorProfileService.swift:426`, `478`. Triggered by `submitAuthorSubscription` and `submitAuthorModeration`.
- `invalidateInbox`: `Features/Account/AO3InboxModel.swift:469`. Triggered by `updateInboxMessage`.

**Writes from Step 1 that change author page, series page, or Inbox:**
- `saveWork`, `deleteWork`, `deleteWorks`, `deleteDraft`, `createChapter`, `updateChapter`, `deleteChapter`, `bulkEditWorks`, `editTags`: Change author page works list. **No removal follows** (Searched `Services/AO3WorkActions.swift` for `removeValue`, `removePages`, `removeAuthorDashboards`, `removeSeries`, and `invalidate`).
- `saveSeries`, `reorderSeries`, `removeWorkFromSeries`: Change series page. **`removeSeries` follows.**

## 5. Summary Table

| Number | The write | The caller | The screen behind and what it goes on showing | Type |
|---|---|---|---|---|
| 1 | `saveWork` (`AO3WorkActions.swift:126`) | `WorkEditView.swift:571` | `AuthorProfileView.swift:575`: `row.title` | (d) |
| 2 | `deleteWork` (`AO3WorkActions.swift:439`) | `WorkEditView.swift:538` | `AuthorProfileView.swift:575`: `row.title` | (d) |
| 3 | `deleteDraft` (`AO3WorkActions.swift:473`) | `WorkEditView.swift:544` | `WritingDraftsView.swift:91`: `work.title` | (d) |
| 4 | `withdrawSignUp` (`AO3ChallengeActions.swift:74`) | `ChallengeSignUpView.swift:688` | `AO3CollectionDetailView.swift:384`: `show.collection.viewerIsSignedUp` | (d) |
| 5 | `leaveCollection` (`AO3CollectionActions.swift:354`) | `CollectionMaintainersView.swift:504` | `AO3CollectionDetailView.swift:337`: maintainers list | (d) |

## Triage (Claude, 2026-10-10)

Every row was checked in the Swift before anything was changed. All five are real, one fault
class, and are fixed on iOS as **T-379** (polish `7ea2c933`, integrate `8bda0989`):

| Row | Verdict | Fix |
| --- | --- | --- |
| 1, 2 (`saveWork`, `deleteWork` from `WorkEditView`) | **Real, P2.** The form closed and the writer's works list was neither told nor re-read: the old title, or a work that had just been deleted, stayed listed until pulled. | `WorkEditView.onChanged`; the profile refreshes. The tags editor opened from the profile had a callback and was handed none; now it is. |
| 3 (`deleteDraft`) | **Real, P2.** The drafts list kept the deleted draft. | The drafts list reloads. |
| 4 (`withdrawSignUp`), and a submitted sign-up, which the index did not list | **Real, P3.** The collection page went on saying the reader was, or was not, signed up. | `.ao3CollectionChanged`; the page reads every segment again. |
| 5 (`leaveCollection`) | **Real, P3.** The page went on offering Manage. | The same notification. |
| Section 4: no removal follows an own-content write | **Real.** The kept pages answered for five minutes. | `AO3AuthorPageCache.removeAuthorPages` after every own-content write that is sent. |

**The same on Android?** Checked by reading:

- The work form and the tags editor opened from a row of the writer's list: **yes, the same
  fault** (`writing/WritingOwnWorkScreen.kt`: only the chapter form called `onChanged`).
  Gemini's A39 row 3 had called this path sound; it was sound for the chapter form only.
  Fixed, with a test that fails without it
  (`OwnWorksScreenTest.aWorkSavedFromItsRowReadsTheListAgainFromAO3`). The tags path has the
  same one-line change and no test of its own.
- The drafts list: sound (`AppNavHost.kt`, `writingWorkSaved`).
- The collection page: sound. Its state is plain `remember`, so it is read again whenever the
  reader comes back to it.

Not checked on either app: the collection form's own save and what the collection page shows
of it; a maintainer invited or removed; moderation approvals and the page's counts.

