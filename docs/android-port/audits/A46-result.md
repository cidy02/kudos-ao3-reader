11 writes traced to the end, 0 rows you think are faults.

1. `giveKudos`
   - **Write:** `network/ao3/writes/AO3WriteRepository.kt:970`
   - **Caller 1:** `reader/ReaderViewModel.kt:332`
     - **Success lines:** `_writeMessage.value = result.value.message`, `val updated = repository.markKudosGiven(workId)`, `updateReading { current -> current.copy(work = updated ?: current.work.copy(hasGivenKudos = true)) }` (`reader/ReaderViewModel.kt:333-338`)
     - **Result:** (c) it changes its own state by hand and stays.
   - **Caller 2:** `works/WorkDetailScreen.kt:1109`
     - **Success lines:** `handleWriteResult(result)`, `val updated = workRepository.upsert(local.copy(hasGivenKudos = true, lastModifiedAt = Instant.now()))`, `refreshLocal(updated.id, state.remote)` (`works/WorkDetailScreen.kt:1110-1118`)
     - **Result:** (c) it changes its own state by hand and stays.

2. `toggleSubscribe`
   - **Write:** `network/ao3/writes/AO3WriteRepository.kt:1033`
   - **Caller:** `works/WorkDetailScreen.kt:1122` (via `runAo3Write` at `works/WorkDetailScreen.kt:561`)
     - **Success lines:** `state.copy(ao3Message = result.value.message, isSubscribed = subscribedAfter)` (`works/WorkDetailScreen.kt:536-549`)
     - **Result:** (c) it changes its own state by hand and stays.

3. `unsubscribe`
   - **Write:** `network/ao3/writes/AO3WriteRepository.kt:1076`
   - **Caller:** `account/SubscriptionUnsubscribeState.kt:28`
     - **Success lines:** `is AO3Result.Success -> onSuccess()` (`account/SubscriptionUnsubscribeState.kt:43`)
     - **Lambda passed:** `account/AccountWorksListScreen.kt:1023` passes `{ onUnsubscribeWork(work) }`. The composable receives this from `account/AccountWorksListScreen.kt:310` which passes `{ viewModel.removeSubscription(it.remote.id, loaded?.page?.currentPage ?: 1) }`.
     - **Result:** (b) it calls a lambda handed to it (`onSuccess`), which ultimately changes its own state by hand and stays (c).

4. `deleteReading`
   - **Write:** `network/ao3/writes/AO3WriteRepository.kt:1092`
   - **Caller:** `account/SubscriptionUnsubscribeState.kt:32`
     - **Success lines:** `is AO3Result.Success -> onSuccess()` (`account/SubscriptionUnsubscribeState.kt:43`)
     - **Lambda passed:** `account/AccountWorksListScreen.kt:835` passes `{ deletedIds = deletedIds + pending.remote.id }`.
     - **Result:** (b) it calls a lambda handed to it (`onSuccess`), which ultimately changes its own state by hand and stays (c).

5. `markForLater`
   - **Write:** `network/ao3/writes/AO3WriteRepository.kt:1154`
   - **Caller:** `works/WorkDetailScreen.kt:1123` (via `runAo3Write` at `works/WorkDetailScreen.kt:561`)
     - **Success lines:** `state.copy(ao3Message = result.value.message, ...)` (`works/WorkDetailScreen.kt:546-549`)
     - **Result:** (c) it changes its own state by hand and stays.

6. `createBookmark`
   - **Write:** `network/ao3/writes/AO3WriteRepository.kt:1179`
   - **Caller:** `works/WorkDetailScreen.kt:852`
     - **Success lines:** `bookmarkDialog = false`, `bookmarkIsEdit = true`, `handleWriteResult(result)`, `when (val refreshed = writeRepository.fetchWorkActionStates(workId)) { is AO3Result.Success -> { advisoryBookmark = refreshed.value.second; state = state.copy(isSubscribed = refreshed.value.first.isSubscribed) } }` (`works/WorkDetailScreen.kt:854-862`)
     - **Result:** (c) it changes its own state by hand and stays (partially reading from AO3 via `fetchWorkActionStates` without passing bypassCache).

7. `submitComment`
   - **Write:** `network/ao3/comments/AO3CommentRepository.kt:88`
   - **Caller:** `comments/CommentsViewModel.kt:670`
     - **Success lines:** `_message.value = result.value.message`, `if (replyTo != null || edit != null) reloadPageOnScreen() else load()` (`comments/CommentsViewModel.kt:681-701`)
     - **Result:** (a) the screen reads its own page again from AO3 (`repository.loadThread(target, page, focusedId)`, bypassCache is not passed).

8. `editComment`
   - **Write:** `network/ao3/comments/AO3CommentRepository.kt:178`
   - **Caller:** `comments/CommentsViewModel.kt:668`
     - **Success lines:** identical to `submitComment` (`comments/CommentsViewModel.kt:681-701`)
     - **Result:** (a) the screen reads its own page again from AO3 (no bypassCache).

9. `deleteComment`
   - **Write:** `network/ao3/comments/AO3CommentRepository.kt:209`
   - **Caller:** `comments/CommentsViewModel.kt:631`
     - **Success lines:** `_message.value = "Comment deleted."`, `reloadPageOnScreen()` (`comments/CommentsViewModel.kt:635-636`)
     - **Result:** (a) the screen reads its own page again from AO3 (no bypassCache).

10. `save` (Preferences)
    - **Write:** `network/ao3/preferences/AO3PreferencesRepository.kt:31`
    - **Caller:** `account/AO3PreferencesScreen.kt:125`
      - **Success lines:** `status = "Saved successfully."`, `hasEdits = false`, `val reloadResult = repository.load(username)` (`account/AO3PreferencesScreen.kt:133-136`)
      - **Result:** (a) the screen reads its own page again from AO3 (no bypassCache).

11. `performBulkAction` (Inbox)
    - **Write:** `network/ao3/inbox/AO3InboxRepository.kt:55`
    - **Caller:** `account/AccountInboxViewModel.kt:287`
      - **Success lines:** `mutableState.update { it.copy(...) }`, `reloadAfterWrite(state.currentPage)` (`account/AccountInboxViewModel.kt:296-305`)
      - **Result:** (a) the screen reads its own page again from AO3 (`repository.load(page = page, ...)` inside `reloadAfterWrite`, no bypassCache).

### Summary Table

| Number | Write | Caller | Screen Behind / State | Class |
|---|---|---|---|---|
| 1 | `network/ao3/writes/AO3WriteRepository.kt:970` | `reader/ReaderViewModel.kt:332` | State in `_state` (`reader/ReaderViewModel.kt`) | (c) it changes its own state by hand and stays |
| 2 | `network/ao3/writes/AO3WriteRepository.kt:970` | `works/WorkDetailScreen.kt:1109` | State in `state` hoisted in `works/WorkDetailScreen.kt` | (c) it changes its own state by hand and stays |
| 3 | `network/ao3/writes/AO3WriteRepository.kt:1033` | `works/WorkDetailScreen.kt:1122` | State in `state` hoisted in `works/WorkDetailScreen.kt` | (c) it changes its own state by hand and stays |
| 4 | `network/ao3/writes/AO3WriteRepository.kt:1154` | `works/WorkDetailScreen.kt:1123` | State in `state` hoisted in `works/WorkDetailScreen.kt` | (c) it changes its own state by hand and stays |
| 5 | `network/ao3/writes/AO3WriteRepository.kt:1179` | `works/WorkDetailScreen.kt:852` | State in `state` hoisted in `works/WorkDetailScreen.kt` | (c) it changes its own state by hand and stays |
| 6 | `network/ao3/writes/AO3WriteRepository.kt:1076` | `account/SubscriptionUnsubscribeState.kt:28` | State in `mutableState` (`account/AccountViewModel.kt`) | (b) calls lambda -> (c) changes own state |
| 7 | `network/ao3/writes/AO3WriteRepository.kt:1092` | `account/SubscriptionUnsubscribeState.kt:32` | State in `deletedIds` (`account/AccountWorksListScreen.kt`) | (b) calls lambda -> (c) changes own state |
| 8 | `network/ao3/comments/AO3CommentRepository.kt:88` | `comments/CommentsViewModel.kt:670` | State in `_state` (`comments/CommentsViewModel.kt`) | (a) reads its own page again from AO3 |
| 9 | `network/ao3/comments/AO3CommentRepository.kt:178` | `comments/CommentsViewModel.kt:668` | State in `_state` (`comments/CommentsViewModel.kt`) | (a) reads its own page again from AO3 |
| 10 | `network/ao3/comments/AO3CommentRepository.kt:209` | `comments/CommentsViewModel.kt:631` | State in `_state` (`comments/CommentsViewModel.kt`) | (a) reads its own page again from AO3 |
| 11 | `network/ao3/preferences/AO3PreferencesRepository.kt:31` | `account/AO3PreferencesScreen.kt:125` | State in `snapshot` (`account/AO3PreferencesScreen.kt`) | (a) reads its own page again from AO3 |
| 12 | `network/ao3/inbox/AO3InboxRepository.kt:55` | `account/AccountInboxViewModel.kt:287` | State in `mutableState` (`account/AccountInboxViewModel.kt`) | (a) reads its own page again from AO3 |

## Triage (Claude, 2026-10-10)

Eleven writes traced, none called a fault, and none is: the reader's own actions (kudos,
subscribe, mark for later, a bookmark) change the screen that made them and stay on it; the
subscriptions and history lists remove the row by hand; comments, preferences and the Inbox
read their own page again. Where another screen is behind (Work Detail behind the reader), it
is a route with plain `remember` state, which starts again on return (tested on the emulator,
see A44's triage).

**With A44 and A45, all 46 Android writes have been traced: the faults of this kind were the
four found and fixed tonight** (the bulk edit, the series form, Edit and Tags from a row, the
list of collections).

