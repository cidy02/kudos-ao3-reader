# A31 Audit Result

## 1. Requests

**Moderator (logged in, maintainer/owner):**
*   **Android:**
    1.  `repository.getChallengeSettingsForm(slug)` (`AO3ChallengeAssignmentsState.kt:97`)
    2.  GET `/collections/:slug/assignments?fulfilled=true` (Page 1 only, `SignUpAssignmentList.Complete` via `AO3ChallengeSignUpsUrls.assignments`) (`AO3ChallengeAssignmentsState.kt:109`)
    3.  GET `/collections/:slug/assignments?unfulfilled=true` (Page 1 only, `SignUpAssignmentList.Open`) (`AO3ChallengeAssignmentsState.kt:109`)
    4.  GET `/collections/:slug/assignments` (Page 1 only, `SignUpAssignmentList.Defaults`) (`AO3ChallengeAssignmentsState.kt:109`)
    5.  GET `/collections/:slug/assignments?pinch_hit=true` (Page 1 only, `SignUpAssignmentList.PinchHits`) (`AO3ChallengeAssignmentsState.kt:109`)
*   **iOS:**
    1.  GET `/collections/:slug/assignments?fulfilled=true` (All pages sequentially) (`ChallengeAssignmentsView.swift:467`, `AO3Client+Challenges.swift:78`)
    2.  GET `/collections/:slug/assignments?unfulfilled=true` (All pages sequentially) (`ChallengeAssignmentsView.swift:467`, `AO3Client+Challenges.swift:78`)
    3.  GET `/collections/:slug/assignments` (All pages sequentially) (`ChallengeAssignmentsView.swift:472`, `AO3Client+Challenges.swift:78`)
    4.  GET `/collections/:slug/assignments?pinch_hit=true` (All pages sequentially) (`ChallengeAssignmentsView.swift:477`, `AO3Client+Challenges.swift:78`)
    5.  GET `/collections/:slug/gift_exchanges/edit` (`ChallengeAssignmentsView.swift:482`)

**Participant (logged in, not a maintainer):**
*   **Android:** 0 requests. The load is aborted immediately by `if (!auth.state.value.isSignedIn || !maintainer)` (`AO3ChallengeAssignmentsState.kt:89`).
*   **iOS:** 4 requests (each throwing an error locally, e.g. 403 Forbidden).
    1.  GET `/collections/:slug/assignments?fulfilled=true` (`ChallengeAssignmentsView.swift:467`) — throws error, aborting the loop so `unfulfilled` is skipped (`AO3Client+Challenges.swift:78`).
    2.  GET `/collections/:slug/assignments` (`ChallengeAssignmentsView.swift:472`) — throws.
    3.  GET `/collections/:slug/assignments?pinch_hit=true` (`ChallengeAssignmentsView.swift:477`) — throws.
    4.  GET `/collections/:slug/gift_exchanges/edit` (`ChallengeAssignmentsView.swift:482`) — throws.

**Anyone else (not logged in):**
*   **Android:** 0 requests. Aborted by `if (!auth.state.value.isSignedIn || !maintainer)` (`AO3ChallengeAssignmentsState.kt:89`).
*   **iOS:** 0 requests. Aborted by `guard auth.isLoggedIn else` (`ChallengeAssignmentsView.swift:461`).

**Writes:**
*   **Claim a pinch hit:**
    *   **Android:** `updateAssignments(slug, "cover_$assignmentID" to name, ...)` (`AO3WriteRepository.kt:351`) sending to `update_multiple` via `SignUpAssignmentList.Defaults` referer (`AO3WriteRepository.kt:357`).
    *   **iOS:** `updateAssignments(slug: slug, field: ("cover_\(assignmentID)", pinch), ...)` (`AO3ChallengeActions.swift:127`) sending to `update_multiple` via `.defaults` referer (`AO3ChallengeActions.swift:157`).
*   **Report a default:**
    *   **Android:** `updateAssignments(slug, "default_$assignmentID" to "1", ...)` (`AO3WriteRepository.kt:355`) via `SignUpAssignmentList.Open` referer (`AO3WriteRepository.kt:358`).
    *   **iOS:** `updateAssignments(slug: slug, field: ("default_\(assignmentID)", "1"), ...)` (`AO3ChallengeActions.swift:144`) via `.unfulfilled` referer (`AO3ChallengeActions.swift:157`).

## 2. Verdicts

*   **Confirmation:**
    *   **Android:** `parser.writeSuccessMessage(response.value.body) != null || response.value.statusCode in 300..399` (`AO3WriteRepository.kt:718`)
    *   **iOS:** `if AO3Client.writeSuccessMessage(in: body) != nil { return nil }` or `if (300...399).contains(status) { return nil }` (`AO3CollectionActions.swift:488, 489`)
*   **Refusal:**
    *   **Android:** `val error = parser.writeErrorMessage(response.value.body)` ... `error != null -> AO3Result.Failure(AO3Error.Validation(error))` (`AO3WriteRepository.kt:714-716`)
    *   **iOS:** `if let error = AO3Client.writeErrorMessage(in: body) { return .rejected(error) }` (`AO3CollectionActions.swift:486`)
*   **Not Confirmed:**
    *   **Android:** `response.value.statusCode in 200..299 -> AO3Result.Failure(AO3Error.Validation(AO3CollectionFields.UNCONFIRMED))` (`AO3WriteRepository.kt:719`). Message: `"AO3 replied but didn't confirm the change went through. Check on AO3 before trying again."` (`AO3CollectionForm.kt:47`).
    *   **iOS:** `guard (200...299).contains(status) else { ... } return .unconfirmed` (`AO3CollectionActions.swift:490`). Message: `"AO3 replied but didn't confirm the change went through. Check on AO3 before trying again."` (`AO3CollectionActions.swift:420`).
*   **Fallbacks:** Both Android (`AO3WriteRepository.kt:351,355`) and iOS (`AO3ChallengeActions.swift:127,144`) use the exact words: `"AO3 couldn't claim that pinch hit."` and `"AO3 couldn't record the default."`

## 3. Words on screen

The following strings are in `account/AO3ChallengeAssignmentsScreen.kt` (or state) but absent from `ChallengeAssignmentsView.swift` (searched for substrings):
*   Android: `"AO3 shows assignments to collection owners and moderators after sign-ups close."` (`account/AO3ChallengeAssignmentsState.kt:91`). I searched iOS for "shows assignments" and "owners and moderators" — absent.
*   Android: `"AO3 shows assignments to maintainers after sign-ups close. Kudos can't confirm that sign-ups are closed."` (`account/AO3ChallengeAssignmentsState.kt:101`). I searched iOS for "can't confirm" — absent.
*   Android: `"Refresh assignments"` (`account/AO3ChallengeAssignmentsScreen.kt:39`). I searched iOS for "Refresh assignments" — absent.
*   Android: `"Dismiss error"` (`account/AO3ChallengeAssignmentsScreen.kt:47`). I searched iOS for "Dismiss error" — absent (iOS uses an unlabeled `xmark` image instead, line 125).
*   Android: `"Load more (${list.name})"` (`account/AO3ChallengeAssignmentsScreen.kt:75`). I searched iOS for "Load more" — absent (iOS pages automatically).

## 4. Second taps

*   **Android:** `state.value.busy` (`account/AO3ChallengeAssignmentsState.kt:127`) blocks execution in `perform()`, and visually disables the confirmation alert button via `enabled = !disabled` where `disabled = ... || state.busy` (`account/AO3ChallengeAssignmentsScreen.kt:30`).
*   **iOS:** The write triggers are disabled via `.disabled(itemInFlight != nil)` (`ChallengeAssignmentsView.swift:233, 245`). The confirmation sheet itself invokes `Task { await perform(write) }` without a programmatic guard inside `perform()` (`ChallengeAssignmentsView.swift:204`), relying on standard SwiftUI behavior where an alert is immediately dismissed upon its button being tapped.

## 5. The demo

`DemoChallengeAssignments` (`network/ao3/DemoNetwork.kt:1373`) intercepts `/collections/winter_exchange/assignments` and `/collections/winter_exchange/assignments/update_multiple` locally.

The assignments `GET` address was already answered by the demo for the **Sign-ups screen** (1by) to read page 1 counts. The patch extended the interception (`DemoNetwork.kt:236`) to recognize `page=2` and `pinch_hit=true` for this Assignments screen.

## Table

| # | Severity | Kotlin | Swift | Note |
|---|---|---|---|---|
| 1 | P1 | `AO3ChallengeAssignmentsState.kt:111` | `AO3Client+Challenges.swift:78` | Android fetches only page 1, while iOS fetches all pages sequentially. |
| 2 | P1 | `AO3ChallengeAssignmentsState.kt:97` | `ChallengeAssignmentsView.swift:482` | Android requests `gift_exchanges/edit` first; iOS requests it last. |
| 3 | P2 | `AO3ChallengeAssignmentsState.kt:89` | `ChallengeAssignmentsView.swift:467` | Android explicitly guards network requests behind `!maintainer`; iOS makes them and relies on catching the 403. |
| 4 | P3 | `AO3ChallengeAssignmentsScreen.kt:39` | `ChallengeAssignmentsView.swift:125` | Android uses string `"Refresh assignments"` and `"Dismiss error"`; iOS lacks them (e.g., uses unlabelled `xmark`). |
| 5 | P3 | `AO3ChallengeAssignmentsScreen.kt:75` | `ChallengeAssignmentsView.swift:467` | Android has `"Load more"` button string because it paginates manually, unlike iOS. |
