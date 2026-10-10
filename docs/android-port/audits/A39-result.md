1. **Reads through the cache.**
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/series/AO3SeriesRepository.kt:67`: reads `/series/...` (`bypassCache` parameter is passed).
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/inbox/AO3InboxRepository.kt:46`: reads `/users/.../inbox` (`bypassCache` parameter is passed).
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/author/AO3AuthorRepository.kt:72`: reads `/users/...` dashboard, about, works, series, and bookmarks (`bypassCache` parameter is passed).

2. **Removals.**
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/inbox/AO3InboxRepository.kt:93`: `pageCache.removePages(java.net.URI(it).path, viewer)` triggered by `performBulkAction`.
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/inbox/AO3InboxRepository.kt:95`: `pageCache.remove(AO3PageCache.Key(form.actionUrl, viewer, AO3PageCache.Kind.Inbox))` triggered by `performBulkAction`.
- `android/app/src/main/java/io/github/cidy02/kudos/auth/AO3AuthRepository.kt:347`: `io.github.cidy02.kudos.network.ao3.AO3PageCache.shared.clear()` triggered by `advanceSessionGenerationLocked` (login/logout/token expiry).

3. **Writes beside those reads.**
- **`AccountInboxViewModel.kt`** (reads `load`):
  - `repository.performBulkAction` succeeds: (a) it re-reads with `bypassCache = true` via `reloadAfterWrite(state.currentPage)` (`android/app/src/main/java/io/github/cidy02/kudos/account/AccountInboxViewModel.kt:305`).
- **`AuthorProfileScreen.kt`** (reads `loadWorks`, `loadDashboard`, etc.):
  - `WritingBulkEditScreen` succeeds: (a) it re-reads with `bypassCache = true` via `onSaved = { bulkModel = null; loadHeader(bypassCache = true) { loadTab(tab, 1, bypassCache = true) } }` (`android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:252`).
  - `WritingOwnWorkScreen` succeeds: (a) it re-reads with `bypassCache = true` via `onChanged = { loadHeader(bypassCache = true) { loadTab(tab, 1, bypassCache = true) } }` (`android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:260`).
  - `deletes?.confirm()` (`writes.deleteWorks`, `writes.deleteWork`) succeeds: (a) it re-reads with `bypassCache = true` via `if (deleteState.confirmed > 0) { selection.exit(); heldDelete = null; loadHeader(bypassCache = true) { loadTab(tab, 1, bypassCache = true) } }` (`android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:243`).
  - `WritingSeriesScreen` succeeds: (e) it does not re-read and changes nothing via `onBack = { editingSeries = null }` (`android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:270`).
- **`SeriesWorksScreen.kt`** (reads `detailPage`):
  - `WritingSeriesScreen` succeeds: (e) it does not re-read and changes nothing via `onBack = { editing = null }` (`android/app/src/main/java/io/github/cidy02/kudos/app/SeriesWorksScreen.kt:118`).

4. **Screens that do not write but show a page another screen changes.**
- A series edited in the series form (from `WritingSeriesScreen` inside `AuthorProfileScreen.kt`), then opened in the series page (`SeriesWorksScreen.kt`). The write does not remove the series page from the cache, so the series page reads the stale address from the cache (`detailPage`).
- An Inbox item marked read in `AccountInboxViewModel.kt`, then the Inbox opened again from Account. The write (`performBulkAction`) removes the page from the cache first, so the screen fetches fresh.

| Number | Write | Read that follows or other screen | Result |
|---|---|---|---|
| 1 | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountInboxViewModel.kt:287` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountInboxViewModel.kt:305` | (a) it re-reads with `bypassCache = true` |
| 2 | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:251` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:252` | (a) it re-reads with `bypassCache = true` |
| 3 | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:258` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:260` | (a) it re-reads with `bypassCache = true` |
| 4 | `android/app/src/main/java/io/github/cidy02/kudos/author/OwnWorksControls.kt:47` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:243` | (a) it re-reads with `bypassCache = true` |
| 5 | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:269` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:270` | (e) it does not re-read and changes nothing |
| 6 | `android/app/src/main/java/io/github/cidy02/kudos/app/SeriesWorksScreen.kt:117` | `android/app/src/main/java/io/github/cidy02/kudos/app/SeriesWorksScreen.kt:118` | (e) it does not re-read and changes nothing |
| 7 | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:269` | `android/app/src/main/java/io/github/cidy02/kudos/app/SeriesWorksScreen.kt:99` | (c) it re-reads without either |

## Triage (Claude, 2026-10-10)

Rows 1 to 4 read as Gemini says (each re-reads past the cache). **Rows 5, 6 and 7 are one real
fault, P2, fixed:** a saved series edit (title, summary, order, a work removed) returned to a
series page or an author's series list that still showed the page from before the save, and a
series page opened afterwards from anywhere else was answered from the cache for five minutes.
`WritingSeriesState` now drops the kept `/series/<id>` pages when AO3 confirms a save and says
it changed; `SeriesWorksScreen` and `AuthorProfileScreen` then read again past the cache. Test
`WritingSeriesTest.aConfirmedSaveDropsTheKeptSeriesPageAndARefusedOneDoesNot` fails without it.

Not covered by this index, and still to check by hand: a work edited in the work form and the
series page that lists it; subscribe and unsubscribe on an author page (iOS drops the author's
dashboards after it: `invalidateAuthorDashboards`; Android has `removeAuthorDashboards`, callers
not checked here); a comment posted and the work's comment count.

**iOS, to check:** `SeriesEditDestination` is opened from `AO3SeriesDetailView.swift:127` and
`AuthorProfileContentSections.swift:553` with no "saved" callback, and `SeriesEditView.save`
(`:251`) drops nothing from `AO3AuthorPageCache`. Probably the same fault.

