# A48: iOS collection and challenge writes

## 1. The Writes

There are 26 functions that send a POST reaching `submitWrite` across the two files (excluding `leaveCollection` and `withdrawSignUp` which were covered in A41). We trace the first 16:

1. `createCollection` - `Services/AO3CollectionActions.swift:54`
2. `updateCollection` - `Services/AO3CollectionActions.swift:79`
3. `deleteCollection` - `Services/AO3CollectionActions.swift:98`
4. `revealCollection` - `Services/AO3CollectionActions.swift:130`
5. `unanonCollection` - `Services/AO3CollectionActions.swift:145`
6. `approveCollectionItem` - `Services/AO3CollectionActions.swift:160`
7. `rejectCollectionItem` - `Services/AO3CollectionActions.swift:176`
8. `updateCollectionItems` - `Services/AO3CollectionActions.swift:189`
9. `updateUserCollectionItems` - `Services/AO3CollectionActions.swift:230`
10. `acceptMember` - `Services/AO3CollectionActions.swift:277`
11. `declineMember` - `Services/AO3CollectionActions.swift:289`
12. `inviteMaintainer` - `Services/AO3CollectionActions.swift:311`
13. `joinCollection` - `Services/AO3CollectionActions.swift:335`
14. `submitWorkToCollection` - `Services/AO3CollectionActions.swift:373`
15. `saveChallengeSignUp` - `Services/AO3ChallengeActions.swift:34`
16. `withdrawSignUpAfterClose` - `Services/AO3ChallengeActions.swift:94`

The rest are:
- `reportAssignmentDefault` - `Services/AO3ChallengeActions.swift:100`
- `claimPinchHit` - `Services/AO3ChallengeActions.swift:120`
- `markAssignmentDefaulted` - `Services/AO3ChallengeActions.swift:140`
- `claimPrompt` - `Services/AO3ChallengeActions.swift:177`
- `releasePrompt` - `Services/AO3ChallengeActions.swift:197`
- `saveTagSetFields` - `Services/AO3ChallengeActions.swift:215`
- `reportRejectedTag` - `Services/AO3ChallengeActions.swift:237`
- `updateChallengeSettings` - `Services/AO3ChallengeActions.swift:261`

## 2. Callers & 3. The Screen Behind

1. `createCollection`
   - Caller: `Features/Account/AO3CollectionFormView.swift:504`. Runs: `form = savedForm; saveMessage = message; phase = .ready`
   - Type: (c) the caller changes its own state by hand
   - Screen behind: `Features/Account/AO3CollectionsList.swift:88` (`NavigationLink(value: AO3CollectionFormDestination(slug: nil))`). It shows the old collections list from an `@State` loaded once in `.task(id: WholeIndexLoadID...)`. When the pushed view goes away, none makes it read again.

2. `updateCollection`
   - Caller 1: `Features/Account/AO3CollectionFormView.swift:500`. Runs: `form = savedForm; saveMessage = message; phase = .ready`
   - Type: (c) the caller changes its own state by hand
   - Screen behind: `Features/Account/AO3CollectionDetailView.swift:355` (`manageRow("Collection Settings") { AO3CollectionFormView(...) }`). It goes on showing the old collection rules and summary from its `.task` load. None makes it read again.
   - Caller 2: `Features/Challenges/ChallengeSettingsEditView.swift:818`. Runs: `collectionForm = updated; loadedCollectionForm = updated`
   - Type: (c) the caller changes its own state by hand
   - Screen behind: `Features/Challenges/ChallengeSettingsView.swift:123`. Shows old settings; its `.task { await loadSettingsIfNeeded() }` bails because `phase != .idle`, so it doesn't reload.

3. `deleteCollection`
   - Caller: `Features/Account/AO3CollectionFormView.swift:577`. Runs: `if let onDeleted { onDeleted() } else { dismiss() }`
   - Type: (b) the caller calls a closure handed to it (`onDeleted`).
   - Screen behind: Its presenters (`AO3CollectionsList.swift:114`, `AccountView.swift:199`, `AO3CollectionDetailView.swift:355`) all pass an `onDeleted` closure that dismisses the view (e.g. `{ editingCollection = nil }`, `dismiss()`). `AO3CollectionsList` refreshes properly because the caller also posts `.ao3CollectionDeleted`.

4. `revealCollection`
   - Caller: `Features/Challenges/CollectionModerationView.swift:891`. Runs: `await load()`
   - Type: (a) the caller reloads its own data from AO3.

5. `unanonCollection`
   - Caller: `Features/Challenges/CollectionModerationView.swift:904`. Runs: `await load()`
   - Type: (a) the caller reloads its own data from AO3.

6. `approveCollectionItem`
   - Caller: `Features/Challenges/CollectionModerationView.swift:821`. Runs: `await removeDecided(item)`
   - Type: (c) the caller changes its own state by hand.

7. `rejectCollectionItem`
   - Caller: `Features/Challenges/CollectionModerationView.swift:834`. Runs: `await removeDecided(item)`
   - Type: (c) the caller changes its own state by hand.

8. `updateCollectionItems`
   - Caller: `Features/Account/AO3CollectionItemsView.swift:528`. Runs: `await load(page: currentPage, replacing: false)`
   - Type: (a) the caller reloads its own data from AO3.

9. `updateUserCollectionItems`
   - Caller: `Features/Account/AO3CollectionItemsView.swift:530`. Runs: `await load(page: currentPage, replacing: false)`
   - Type: (a) the caller reloads its own data from AO3.

10. `acceptMember`
    - Caller: `Features/Challenges/CollectionModerationView.swift:847`. Runs: `withAnimation { membershipRequests.removeAll { $0.id == participant.id } }`
    - Type: (c) the caller changes its own state by hand.

11. `declineMember`
    - Caller: `Features/Challenges/CollectionModerationView.swift:869`. Runs: `withAnimation { membershipRequests.removeAll { $0.id == participant.id } }`
    - Type: (c) the caller changes its own state by hand.

12. `inviteMaintainer`
    - Caller: `Features/Challenges/CollectionMaintainersView.swift:478`. Runs: `await loadMaintainers()`
    - Type: (a) the caller reloads its own data from AO3.

13. `joinCollection`
    - (No callers in `Features/`)

14. `submitWorkToCollection`
    - (No callers in `Features/`)

15. `saveChallengeSignUp`
    - Caller: `Features/Challenges/ChallengeSignUpView.swift:671`. Runs: `form = result`, then posts `.ao3CollectionChanged`.
    - Type: (c) the caller changes its own state by hand.

16. `withdrawSignUpAfterClose`
    - (No callers in `Features/`)

## 4. The Cache

No writes in `AO3CollectionActions.swift` or `AO3ChallengeActions.swift` trigger any invalidations of `AO3AuthorPageCache`. (Invalidations like `AO3AuthorPageCache.shared.removePages` or `AO3AuthorProfileFetcher.invalidate` are absent in these files).

- `createCollection`, `updateCollection`, `deleteCollection` change the author's collections list on their profile `/users/NAME/collections`. No removal follows.
- `approveCollectionItem`, `rejectCollectionItem`, `updateCollectionItems` change a work's collections, which are shown on the author's dashboard/works list. No removal follows.
- `acceptMember`, `declineMember`, `inviteMaintainer` change the author's memberships page. No removal follows.
- `saveChallengeSignUp` changes the author's signups page. No removal follows.

## Table

| Number | Write | Caller | Screen behind and what it goes on showing | Type |
|--------|-------|--------|-------------------------------------------|------|
| 1 | `Services/AO3CollectionActions.swift:54` | `Features/Account/AO3CollectionFormView.swift:504` | `Features/Account/AO3CollectionsList.swift:88` (old collections list) | (c) |
| 2 | `Services/AO3CollectionActions.swift:79` | `Features/Account/AO3CollectionFormView.swift:500` | `Features/Account/AO3CollectionDetailView.swift:355` (old collection rules) | (c) |
| 2 | `Services/AO3CollectionActions.swift:79` | `Features/Challenges/ChallengeSettingsEditView.swift:818` | `Features/Challenges/ChallengeSettingsView.swift:123` (old challenge settings) | (c) |
| 3 | `Services/AO3CollectionActions.swift:98` | `Features/Account/AO3CollectionFormView.swift:577` | N/A (all presenters pass a closure that dismisses) | (b) |
| 4 | `Services/AO3CollectionActions.swift:130` | `Features/Challenges/CollectionModerationView.swift:891` | N/A | (a) |
| 5 | `Services/AO3CollectionActions.swift:145` | `Features/Challenges/CollectionModerationView.swift:904` | N/A | (a) |
| 6 | `Services/AO3CollectionActions.swift:160` | `Features/Challenges/CollectionModerationView.swift:821` | N/A (changes own state) | (c) |
| 7 | `Services/AO3CollectionActions.swift:176` | `Features/Challenges/CollectionModerationView.swift:834` | N/A (changes own state) | (c) |
| 8 | `Services/AO3CollectionActions.swift:189` | `Features/Account/AO3CollectionItemsView.swift:528` | N/A | (a) |
| 9 | `Services/AO3CollectionActions.swift:230` | `Features/Account/AO3CollectionItemsView.swift:530` | N/A | (a) |
| 10 | `Services/AO3CollectionActions.swift:277` | `Features/Challenges/CollectionModerationView.swift:847` | N/A (changes own state) | (c) |
| 11 | `Services/AO3CollectionActions.swift:289` | `Features/Challenges/CollectionModerationView.swift:869` | N/A (changes own state) | (c) |
| 12 | `Services/AO3CollectionActions.swift:311` | `Features/Challenges/CollectionMaintainersView.swift:478` | N/A | (a) |
| 13 | `Services/AO3CollectionActions.swift:335` | (No caller) | (No caller) | - |
| 14 | `Services/AO3CollectionActions.swift:373` | (No caller) | (No caller) | - |
| 15 | `Services/AO3ChallengeActions.swift:34` | `Features/Challenges/ChallengeSignUpView.swift:671` | N/A (changes own state and posts `.ao3CollectionChanged`) | (c) |
| 16 | `Services/AO3ChallengeActions.swift:94` | (No caller) | (No caller) | - |

## Triage (Claude, 2026-10-10)

Gemini found 26 collection and challenge writes and traced 16. Checked in the Swift:

- **Rows 1 and 2 are real, P2/P3, fixed as iOS T-381** (polish `46c98c03`, integrate
  `ff70edc5`): after a collection was created or saved, the collections list and the
  collection's page kept showing what it was; after a challenge's settings were saved, the
  settings page behind kept the old dates and switches. The form and the editor now post
  `.ao3CollectionChanged`, and the three screens read again.
- Row 3 (delete) already posts `.ao3CollectionDeleted`. Rows 4 to 12 and 15 read as the index
  says. Rows 13, 14 and 16 have no caller: dead code, left.

**Not traced: the other ten writes** (prompt claims, tag sets, assignments and the rest of
`AO3ChallengeActions.swift`). Gemini's quota ran out at about 06:50 on 2026-10-10 and comes back
at about 00:05 on 2026-10-15, so this is Claude's to do by hand or to send then.

### The ten Gemini did not reach, traced by hand (Claude, 07:06)

In `Services/AO3ChallengeActions.swift`: `claimPinchHit` and `markAssignmentDefaulted`
(`ChallengeAssignmentsView.swift:659`, `:664`) are followed by `await load()`; `claimPrompt` and
`releasePrompt` (`PromptMemeView.swift:574`, `:587`) by `await loadPrompts(page: currentPage)`;
`saveTagSetFields` and `reportRejectedTag` (`TagSetView.swift:720`, `:732`) change the tag set's
own screen by hand. None leaves a screen behind showing what the write changed.
`withdrawSignUpAfterClose` and `reportAssignmentDefault` have no caller. `updateChallengeSettings`
is T-381.

The reader's own actions in `Services/AO3WriteActions.swift` (kudos, subscribe, mark for later,
a bookmark, and the removals from the account's lists) each change the screen that made them:
`AO3WorkActionsModel.swift` for the first four, `AO3AccountWorksList.swift` and
`AO3NamedSubscriptionsList.swift` for the removals. Not checked: whether a bookmark saved from
a work opened out of the Bookmarks list is shown in that list's row on the way back (P3 if not;
the same question on Android).

**So every iOS write has now been traced, by Gemini or by hand; the faults of this kind were
the ones fixed as T-377 to T-381.**

