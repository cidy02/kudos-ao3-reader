16 writes traced to the end.
2 rows are faults.

1. `network/ao3/writes/AO3WriteRepository.kt:432` `claimPinchHit`
   - Caller: `account/AO3ChallengeAssignmentsState.kt:169`
   - On success: `confirmed = true; mutable.value = state.value.copy(pending = null)` followed by `if (confirmed && active && generation == auth.generation.value) load(refresh = true)`
   - Composable: `AO3ChallengeAssignmentsScreen`
   - (a) reads its own page again: `val answer = repository.getChallengeAssignments(slug, list, page)` (does not pass `bypassCache = true`).

2. `network/ao3/writes/AO3WriteRepository.kt:438` `markAssignmentDefaulted`
   - Caller: `account/AO3ChallengeAssignmentsState.kt:171`
   - On success: `confirmed = true; mutable.value = state.value.copy(pending = null)` followed by `if (confirmed && active && generation == auth.generation.value) load(refresh = true)`
   - Composable: `AO3ChallengeAssignmentsScreen`
   - (a) reads its own page again: `val answer = repository.getChallengeAssignments(slug, list, page)` (does not pass `bypassCache = true`).

3. `network/ao3/writes/AO3WriteRepository.kt:467` `withdrawSignUp`
   - Caller: `account/AO3ChallengeSignUpState.kt:111`
   - On success: `is AO3Result.Success -> state.value.copy(withdrawn = true, notice = "Sign-up withdrawn.")`
   - Composable: `AO3ChallengeSignUpScreen`
   - (b) calls a lambda handed to it (`onWithdrawn`): `LaunchedEffect(model, state.withdrawn) { if (state.withdrawn) onWithdrawn("Sign-up withdrawn.") }`.
     - Called from `app/AppNavHost.kt:847`: `onWithdrawn = { notice -> navController.popBackStack(); android.widget.Toast.makeText(context, notice, android.widget.Toast.LENGTH_LONG).show() }`
   - Screen behind: `AO3ChallengeSignUpsScreen` goes on showing the withdrawn sign-up row and count. State lives in `val model = remember(slug, repository, generation, authState.isSignedIn, viewerIsOwner, viewerIsMaintainer) { AO3ChallengeSignUpsState(slug, viewerIsOwner, admitted, repository) }` inside a `sharedComposable` route of `app/AppNavHost.kt:812` (read again when the reader comes back: no).

4. `network/ao3/writes/AO3WriteRepository.kt:489` `saveChallengeSettings`
   - Caller: `account/AO3ChallengeSettingsEditState.kt:92` and `109`
   - On success: `is AO3ChallengeSettingsSaveOutcome.Saved -> { mutable.value = state.value.copy(data = state.value.data?.copy(form = outcome.form), notice = outcome.message) }`
   - Composable: `AO3ChallengeSettingsEditScreen`
   - (c) changes its own state by hand and stays: `state.notice?.let { item { ChallengeEditMessage(it, error = false) } }`.

5. `network/ao3/writes/AO3WriteRepository.kt:538` `saveChallengeSignUp`
   - Caller: `account/AO3ChallengeSignUpState.kt:83`
   - On success: `is AO3SignUpSaveOutcome.Saved -> state.value.copy(saving = false, form = outcome.form, notice = "Sign-up submitted successfully!")`
   - Composable: `AO3ChallengeSignUpScreen`
   - (c) changes its own state by hand and stays: `state.notice?.let { message -> item { SignUpMessage(message, false) } }`.

6. `network/ao3/writes/AO3WriteRepository.kt:585` `claimPrompt`
   - Caller: `account/AO3PromptMemeState.kt:63`
   - On success: `is AO3Result.Success -> loadPage(state.value.data?.currentPage ?: 1, readSchedule = false)`
   - Composable: `AO3PromptMemeScreen`
   - (a) reads its own page again: `val result = repository.getPromptMemePrompts(slug, page)` (does not pass `bypassCache = true`).

7. `network/ao3/writes/AO3WriteRepository.kt:590` `releasePrompt`
   - Caller: `account/AO3PromptMemeState.kt:62`
   - On success: `is AO3Result.Success -> loadPage(state.value.data?.currentPage ?: 1, readSchedule = false)`
   - Composable: `AO3PromptMemeScreen`
   - (a) reads its own page again: `val result = repository.getPromptMemePrompts(slug, page)` (does not pass `bypassCache = true`).

8. `network/ao3/writes/AO3WriteRepository.kt:617` `saveTagSetFields`
   - Caller: `account/AO3TagSetState.kt:54`
   - On success: `is AO3Result.Success -> state.value.copy(saving = false, saveNotice = "Tags saved.")`
   - Composable: `AO3TagSetScreen`
   - (c) changes its own state by hand and stays: `state.saveNotice?.let { message -> item { TagSetFeedback(message, error = false) } }`.

9. `network/ao3/writes/AO3WriteRepository.kt:641` `reportRejectedTag`
   - Caller: `account/AO3TagSetState.kt:72`
   - On success: `is AO3Result.Success -> state.value.copy(nominationInFlight = null, data = state.value.data?.let { current -> val index = current.reviewQueue.indexOfFirst { it.id == nomination.id }; current.copy(reviewQueue = current.reviewQueue.mapIndexed { rowIndex, row -> if (rowIndex == index) row.copy(state = AO3TagNominationState.Rejected) else row }) })`
   - Composable: `AO3TagSetScreen`
   - (c) changes its own state by hand and stays.

10. `network/ao3/writes/AO3WriteRepository.kt:663` `decideCollectionMember`
    - Caller: `account/AO3CollectionModerationState.kt:159`
    - On success: `ModerationAction.Accept, ModerationAction.Decline -> mutable.value = state.value.copy(data = data.copy(requests = data.requests.filterNot { it.id == decision.id }))`
    - Composable: `AO3CollectionModerationScreen`
    - (c) changes its own state by hand and stays.

11. `network/ao3/writes/AO3WriteRepository.kt:689` `revealCollection`
    - Caller: `account/AO3CollectionModerationState.kt:161`
    - On success: `ModerationAction.Reveal, ModerationAction.Unanon -> load()`
    - Composable: `AO3CollectionModerationScreen`
    - (a) reads its own page again: `val result = repository.getModeration(slug)` (does not pass `bypassCache = true`).

12. `network/ao3/writes/AO3WriteRepository.kt:713` `inviteMaintainer`
    - Caller: `account/AO3CollectionMaintainersState.kt:81`
    - On success: `is AO3Result.Success -> { mutable.value = state.value.copy(inviting = false, username = "", notice = "Invitation sent to $username."); load() }`
    - Composable: `AO3CollectionMaintainersScreen`
    - (a) reads its own page again: `val result = repository.getCollectionParticipants(slug)` (does not pass `bypassCache = true`).

13. `network/ao3/writes/AO3WriteRepository.kt:737` `leaveCollection`
    - Caller: `account/AO3CollectionMaintainersState.kt:118`
    - On success: `is AO3Result.Success -> state.value.copy(left = true)`
    - Composable: `AO3CollectionMaintainersScreen`
    - (b) calls a lambda handed to it (`onLeft`): `LaunchedEffect(model, state.left) { if (state.left && authState.isSignedIn) onLeft() }`.
      - Called from `app/AppNavHost.kt:719` (inside `Routes.AO3CollectionMaintainers`): `onLeft = { navController.collectionsChanged(); navController.popBackStack() }`
    - Screen behind: `AO3CollectionDetailScreen` goes on showing dashboard links for maintainers ("Maintainers", "Collection Settings"). State lives in `var show by remember(slug) { mutableStateOf<AO3CollectionShow?>(null) }` inside `account/AO3CollectionDetailScreen.kt:39` (read again when the reader comes back: no).

14. `network/ao3/writes/AO3WriteRepository.kt:759` `saveCollection`
    - Caller: `account/AO3CollectionFormState.kt:122`
    - On success: `is AO3CollectionSaveOutcome.Saved -> state.value.copy(form = outcome.form, notice = outcome.message, saving = false, changes = state.value.changes + 1)`
    - Composable: `AO3CollectionFormScreen`
    - (c) changes its own state by hand and stays: `state.notice?.let { notice -> item { SettingsFootnote(notice) } }`.

15. `network/ao3/writes/AO3WriteRepository.kt:858` `updateCollectionItems`
    - Caller: `account/AO3CollectionModerationState.kt:156` and `account/AO3CollectionItemsState.kt:106`
    - On success (`AO3CollectionModerationState`): `val queue = data.queue.copy(items = data.queue.items.filterNot { it.id == decision.id }); mutable.value = state.value.copy(data = data.copy(queue = queue))`
    - On success (`AO3CollectionItemsState`): `mutableState.value = state.copy(phase = AO3CollectionItemsUiState.Phase.Loaded, staging = if (result is AO3Result.Success) state.staging.clear(drafts.map { it.itemId }) else state.staging, submitError = (result as? AO3Result.Failure)?.error?.displayMessage())` and calls `load(...)`
    - Composable: `AO3CollectionModerationScreen` and `AO3CollectionItemsScreen`
    - (c) changes its own state by hand and stays.

16. `network/ao3/writes/AO3WriteRepository.kt:895` `updateUserCollectionItems`
    - Caller: `account/AO3CollectionItemsState.kt:107`
    - On success: `mutableState.value = state.copy(..., staging = if (result is AO3Result.Success) state.staging.clear(drafts.map { it.itemId }) else state.staging)` and calls `load(previous.tab, previous.page?.currentPage ?: 1)`
    - Composable: `AO3CollectionItemsScreen`
    - (a) reads its own page again: `val answer = repository.getUserCollectionItems(username, tab, page)` (does not pass `bypassCache = true`).

| Number | Write | Caller | Screen Behind | Type |
|---|---|---|---|---|
| 3 | `network/ao3/writes/AO3WriteRepository.kt:467` | `account/AO3ChallengeSignUpState.kt:111` | `AO3ChallengeSignUpsScreen` showing the withdrawn sign-up row and count; state lives in `remember(...) { AO3ChallengeSignUpsState(...) }` (`app/AppNavHost.kt:812`). | (b) calls `onWithdrawn` which only goes back. |
| 13 | `network/ao3/writes/AO3WriteRepository.kt:737` | `account/AO3CollectionMaintainersState.kt:118` | `AO3CollectionDetailScreen` showing dashboard links for maintainers; state lives in `var show by remember(slug) { mutableStateOf<AO3CollectionShow?>(null) }` (`account/AO3CollectionDetailScreen.kt:39`). | (b) calls `onLeft` which only goes back. |
| 1 | `network/ao3/writes/AO3WriteRepository.kt:432` | `account/AO3ChallengeAssignmentsState.kt:169` | N/A | (a) reads its own page again. |
| 2 | `network/ao3/writes/AO3WriteRepository.kt:438` | `account/AO3ChallengeAssignmentsState.kt:171` | N/A | (a) reads its own page again. |
| 4 | `network/ao3/writes/AO3WriteRepository.kt:489` | `account/AO3ChallengeSettingsEditState.kt:92` | N/A | (c) changes its own state by hand and stays. |
| 5 | `network/ao3/writes/AO3WriteRepository.kt:538` | `account/AO3ChallengeSignUpState.kt:83` | N/A | (c) changes its own state by hand and stays. |
| 6 | `network/ao3/writes/AO3WriteRepository.kt:585` | `account/AO3PromptMemeState.kt:63` | N/A | (a) reads its own page again. |
| 7 | `network/ao3/writes/AO3WriteRepository.kt:590` | `account/AO3PromptMemeState.kt:62` | N/A | (a) reads its own page again. |
| 8 | `network/ao3/writes/AO3WriteRepository.kt:617` | `account/AO3TagSetState.kt:54` | N/A | (c) changes its own state by hand and stays. |
| 9 | `network/ao3/writes/AO3WriteRepository.kt:641` | `account/AO3TagSetState.kt:72` | N/A | (c) changes its own state by hand and stays. |
| 10 | `network/ao3/writes/AO3WriteRepository.kt:663` | `account/AO3CollectionModerationState.kt:159` | N/A | (c) changes its own state by hand and stays. |
| 11 | `network/ao3/writes/AO3WriteRepository.kt:689` | `account/AO3CollectionModerationState.kt:161` | N/A | (a) reads its own page again. |
| 12 | `network/ao3/writes/AO3WriteRepository.kt:713` | `account/AO3CollectionMaintainersState.kt:81` | N/A | (a) reads its own page again. |
| 14 | `network/ao3/writes/AO3WriteRepository.kt:759` | `account/AO3CollectionFormState.kt:122` | N/A | (c) changes its own state by hand and stays. |
| 15 | `network/ao3/writes/AO3WriteRepository.kt:858` | `account/AO3CollectionModerationState.kt:156` | N/A | (c) changes its own state by hand and stays. |
| 16 | `network/ao3/writes/AO3WriteRepository.kt:895` | `account/AO3CollectionItemsState.kt:107` | N/A | (a) reads its own page again. |

## Triage (Claude, 2026-10-10)

All sixteen writes were traced. **The two rows called faults (3 and 13) are not.** Both come back
to a screen that is a route of `app/AppNavHost.kt` with its state in plain `remember`, and such a
screen starts again when the reader returns to it. This was the assumption behind several
"sound" verdicts, so it was **tested on the emulator** rather than taken from the code: on a
collection's page, People was chosen, Maintainers opened, and Back pressed; the page came back on
Works, with its works read again. (The brief said such a screen is not a fault; the index
listed them anyway.)

Rows 1, 2, 4 to 12 and 14 to 16 read as the index says. Row 14 (`saveCollection`) stays on the
form, and the list of collections behind it is now told (`0af8f6bf`).

**A lead from the test itself, P3, not changed:** a collection's page forgets its segment and
its place, and reads its page again, every time the reader comes back from one of its Manage
screens. iOS keeps both. Each return costs a read AO3 did not need to serve; worth a look
with the other screens that keep their state in `remember` inside a route.

