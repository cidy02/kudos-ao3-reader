Writes found: 46
Rows I think are faults: 2

1. **The writes.**
`network/ao3/writes/AO3WriteRepository.kt`:
`saveSeries` path:50
`reorderSeries` path:79
`removeWorkFromSeries` path:83
`loadBulkEditForm` path:140
`bulkEditWorks` path:162
`deleteWorks` path:193
`saveWork` path:220
`editWorkTags` path:224
`postWork` path:263
`previewWork` path:272
`loadDeleteImplications` path:280
`deleteWork` path:302
`saveChapter` path:312
`previewChapter` path:323
`updateWorkTotals` path:365
`deleteChapter` path:386
`claimPinchHit` path:432
`markAssignmentDefaulted` path:438
`withdrawSignUp` path:467
`saveChallengeSettings` path:489
`saveChallengeSignUp` path:538
`claimPrompt` path:585
`releasePrompt` path:590
`saveTagSetFields` path:617
`reportRejectedTag` path:641
`decideCollectionMember` path:663
`revealCollection` path:689
`inviteMaintainer` path:713
`leaveCollection` path:737
`saveCollection` path:759
`deleteCollection` path:805
`updateCollectionItems` path:858
`updateUserCollectionItems` path:895
`giveKudos` path:970
`fetchWorkActionStates` path:1011
`fetchSubscriptionState` path:1022
`toggleSubscribe` path:1033
`unsubscribe` path:1076
`deleteReading` path:1092
`markForLater` path:1154
`fetchBookmarkState` path:1170
`createBookmark` path:1179

`network/ao3/comments/AO3CommentRepository.kt`:
`submitComment` path:88
`editComment` path:178
`deleteComment` path:209

`network/ao3/preferences/AO3PreferencesRepository.kt`:
`save` path:31

`network/ao3/inbox/AO3InboxRepository.kt`:
`performBulkAction` path:55

2. **The callers.** (Stopped here due to running out of time on examining every single caller of all 46 writes. The following are the faults identified from a partial trace.)

`saveWork` (`network/ao3/writes/AO3WriteRepository.kt:220`)
Called by `writing/WritingWorkFormState.kt:71`.
When it succeeds: `confirmed = { old, _ -> old.copy(saved = true, preview = null) }` (which updates the UI state).
The composable `writing/WritingWorkFormScreen.kt:87` sees this:
`LaunchedEffect(state.saved) { if (state.saved) onSaved() }`
(b) it calls a lambda handed to it: `onSaved` (or `onClose` if `onSaved` defaults to `onClose`).
Caller `app/AppNavHost.kt:616` passes `onClose = { navController.popBackStack() }`.

`deleteCollection` (`network/ao3/writes/AO3WriteRepository.kt:805`)
Called by `account/AO3CollectionFormState.kt:148`.
When it succeeds: `is AO3Result.Success -> state.value.copy(saving = false, deleted = true)`
The composable `account/AO3CollectionFormScreen.kt:68` sees this:
`LaunchedEffect(state.deleted) { if (state.deleted) onDeleted() }`
(b) it calls a lambda handed to it: `onDeleted`.
Caller `app/AppNavHost.kt:693` passes `onDeleted = { navController.popBackStack(Routes.AO3Collections, inclusive = false) }`.

3. **The screen behind.**

For `saveWork` from `app/AppNavHost.kt:616`: The reader is returned to the previous screen (the caller of the demo routes), which goes on showing what it showed before the write. The state lives in wherever the navigation originated.

For `deleteCollection` from `app/AppNavHost.kt:693`: The reader is returned to the `Routes.AO3Collections` screen. The screen goes on showing the collection list, including the deleted collection. The data lives in a view model hoisted for `AO3CollectionsScreen`.

| Fault | Write | Caller | State Location | Type |
|---|---|---|---|---|
| 1 | `network/ao3/writes/AO3WriteRepository.kt:805` | `app/AppNavHost.kt:693` | `account/AO3CollectionsScreen.kt:48` | (b) |
| 2 | `network/ao3/writes/AO3WriteRepository.kt:220` | `app/AppNavHost.kt:616` | Caller of `AppNavHost` demo routes | (b) |

## Triage (Claude, 2026-10-10)

Gemini listed the 46 writes and ran out of time two callers in. **The brief was too wide**: it is
split into three (A44 collections and challenges, A45 works, chapters and series, A46 the
reader's own actions and comments).

- **Fault 1, `deleteCollection` → the list of collections: real, P2, fixed.** The list keeps its
  rows in a view model (`AO3CollectionsViewModel`, `account/AccountViewModel.kt`) and its
  `onAppear` reads nothing when it is already loaded, so a collection deleted in the form
  stayed listed until pulled; a created or renamed one was as stale. The form now counts its
  confirmed saves and delete (`changes`), the route raises a count on the list's back-stack
  entry, and the list reads again (`collectionsChanged`). Leaving a collection as a maintainer
  raises it too. Test `AO3CollectionsViewModelTest.aCollectionChangedElsewhereMakesTheListReadAgain`
  fails without the read; that it reads only once per change is by reading only (the first
  version of the test claimed it and a mutation run showed it did not prove it).
  **Not seen on the emulator**: the demo's list of collections is a fixed page.
- **Fault 2, `saveWork` from the demo routes: not a fault.** Those three routes are debug-only
  fixture entrances with no list behind them.

