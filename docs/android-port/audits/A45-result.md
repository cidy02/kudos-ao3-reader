12 writes traced to the end.
1 fault found.

1. **`reorderSeries`** (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:79`)
   - Caller: `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingSeriesState.kt:118`
   - Success lines:
     ```kotlin
                         is AO3Result.Success -> if (current()) {
                             seriesChanged()
                             val fresh = keepingMetadata(rows, result.value)
                             mutable.value = state.value.copy(rows = fresh, form = state.value.form?.copy(works = fresh), orderSaved = true)
                         }
     ```
   - (b) it calls a lambda handed to it (`onBack`).
   - Callers of `WritingSeriesScreen`:
     - `android/app/src/main/java/io/github/cidy02/kudos/app/SeriesWorksScreen.kt:117` passes `onChanged = { load(1, bypassCache = true) }`.
     - `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:269` passes `onChanged = { loadHeader(bypassCache = true) { loadTab(tab, 1, bypassCache = true) } }`.
     - `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt:133` passes `onBack = { reorder = null }` and nothing that reloads.
   - For `WritingWorkFormScreen`, the screen the reader is returned to is `WritingWorkFormScreen` (specifically the `WritingAssociationPicker`). What on it the write changed: the series order. Where that data lives: `remember { mutableStateOf<Pair<Long, String>?>(null) }` inside `WritingWorkFormScreen` (`android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt:128`). This is a fault.

2. **`saveSeries`** (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:50`)
   - Caller: `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingSeriesState.kt:126`
   - Success lines:
     ```kotlin
                     is AO3Result.Success -> if (current()) { seriesChanged(); mutable.value = state.value.copy(notice = result.value) }
     ```
   - (d) it only shows a message.
   - The screen returned to when dismissing is `SeriesWorksScreen` (from `android/app/src/main/java/io/github/cidy02/kudos/app/SeriesWorksScreen.kt:117`) or `AuthorProfileScreen` (from `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:269`). Both pass an `onChanged` that reads again when the reader comes back. (Not a fault).

3. **`removeWorkFromSeries`** (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:83`)
   - Caller: `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingSeriesState.kt:145`
   - Success lines:
     ```kotlin
                     is AO3Result.Success -> if (current()) { seriesChanged(); mutable.value = state.value.copy(form = state.value.form?.let {
                         val retained = it.works.filter { w -> w.serialWorkID != row.serialWorkID }
                         it.copy(works = retained)
                     }, rows = state.value.rows?.filter { it.serialWorkID != row.serialWorkID }) }
     ```
   - (c) it changes its own state by hand and stays.

4. **`bulkEditWorks`** (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:162`)
   - Caller: `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingBulkEditState.kt:45`
   - Success lines:
     ```kotlin
                     is AO3Result.Success -> if (active) mutable.value = state.value.copy(saved = true)
     ```
   - (b) it calls a lambda handed to it (`onSaved`).
   - Callers of `WritingBulkEditScreen`:
     - `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:251` passes `onSaved = { bulkModel = null; loadHeader(bypassCache = true) { loadTab(tab, 1, bypassCache = true) } }`. It reads again when the reader comes back. (Not a fault).

5. **`deleteWorks`** (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:193`)
   - Caller: `android/app/src/main/java/io/github/cidy02/kudos/author/OwnWorksControls.kt:48`
   - Success lines:
     ```kotlin
                     is AO3Result.Success -> state.value.copy(confirmed = state.value.confirmed + 1)
     ```
   - (c) it changes its own state by hand and stays. `AuthorProfileScreen` (`android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:242`) observes this state and reads again when the reader comes back. (Not a fault).

6. **`saveWork`** (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:220`)
   - Caller: `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormState.kt:71` (inside `perform` at line 108)
   - Success lines:
     ```kotlin
                 is AO3Result.Success -> if (active) mutable.value = confirmed(old, result.value)
     ```
     (which applies `old.copy(saved = true, preview = null)`)
   - (b) it calls a lambda handed to it (`onSaved`).
   - Callers of `WritingWorkFormScreen`:
     - `android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt:652` passes `onSaved` which updates `writingWorkSaved` in `savedStateHandle` (so `WritingDrafts` reads again when the reader comes back) and navigates back.
     - `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingOwnWorkScreen.kt:23` passes `onSaved = { onChanged(); onBack() }`. Reads again when the reader comes back. (Not a fault).

7. **`editWorkTags`** (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:224`)
   - Caller: `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormState.kt:71`
   - Success lines: same as `saveWork`.
   - (b) it calls a lambda handed to it (`onSave` / `onSaved`).
   - Callers for `editTagsOnly`:
     - `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingOwnWorkScreen.kt:25` passes `onSave = { scope.launch { model.save(); if (model.state.value.saved) { onChanged(); onBack() } } }`. Reads again when the reader comes back.
     - `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt:335` passes `onSave` which calls `tagsModel.save()` and then `model.tagsSaved()`. Reads again when the reader comes back. (Not a fault).

8. **`postWork`** (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:263`)
   - Caller: `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormState.kt:75`
   - Success lines: same as `saveWork`.
   - (b) it calls a lambda handed to it (`onSaved`).
   - Callers of `WritingWorkFormScreen` are identical to `saveWork`. (Not a fault).

9. **`deleteWork`** (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:302`)
   - Callers:
     - `android/app/src/main/java/io/github/cidy02/kudos/author/OwnWorksControls.kt:48`: Success sets `confirmed = state.value.confirmed + 1`. (c) it changes its own state by hand and stays. `AuthorProfileScreen` observes it and reads again. (Not a fault).
     - `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormState.kt:92`: Success sets `saved = true`. (b) it calls a lambda handed to it (`onSaved`). Callers are identical to `saveWork`. (Not a fault).

10. **`saveChapter`** (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:312`)
    - Caller: `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingChapterFormState.kt:110`
    - Success lines:
      ```kotlin
                      is AO3Result.Success -> {
                          if (!active) return
                          mutable.value = state.value.copy(chapterSaved = true)
                      }
      ```
      (and `savedRevision = state.value.savedRevision + 1` in finally block).
    - (b) it calls a lambda handed to it (`onSaved` and `onBack`).
    - Callers of `WritingChapterFormScreen`:
      - `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingChaptersScreen.kt:57` passes `onSaved = { attempt++; onSaved() }`. Reads again.
      - `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingOwnWorkScreen.kt:34` passes `onSaved = onChanged`. Reads again.
      - `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt:138` passes `onSaved = { model.chapterSaved(); scope.launch { model.refreshPublication() } }`. Reads again. (Not a fault).

11. **`updateWorkTotals`** (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:365`)
    - Caller: `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingChapterFormState.kt:119`
    - Success lines:
      ```kotlin
                      is AO3Result.Success -> Unit
      ```
      (and sets `finished = true` on line 124).
    - (b) it calls a lambda handed to it (`onBack`).
    - Callers of `WritingChapterFormScreen` are identical to `saveChapter`. (Not a fault).

12. **`deleteChapter`** (`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:386`)
    - Caller: `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingChapterFormState.kt:171`
    - Success lines:
      ```kotlin
                  is AO3Result.Success -> {
                      if (active) mutable.value = old.copy(finished = true, savedRevision = old.savedRevision + 1)
                  }
      ```
    - (b) it calls a lambda handed to it (`onSaved` and `onBack`).
    - Callers of `WritingChapterFormScreen` are identical to `saveChapter`. (Not a fault).

---
| # | Write | Caller | Screen Behind & State Location | Type |
|---|---|---|---|---|
| 1 | `reorderSeries` (`network/ao3/writes/AO3WriteRepository.kt:79`) | `writing/WritingSeriesState.kt:118` | `WritingWorkFormScreen` goes on showing the series order before the write. State lives in hoisted `var reorder` at `writing/WritingWorkFormScreen.kt:128`. | (b) |

## Triage (Claude, 2026-10-10)

All twelve writes were traced. **The one row called a fault is not one.** The work form opens the
series reorder screen from its Series picker and takes no "changed" callback, but the work form
shows nothing of a series' order: the picker has one row, "Reorder the series"
(`writing/WritingAssociationPickers.kt:112`), and the work form's model holds no position. The
reorder itself drops the kept series pages (`WritingSeriesState.seriesChanged`), so the screens
that do show the order read it again.

The other eleven read as the index says, after today's fixes (`7c3ad663` for Edit and Tags
from a row; `8be57ce5` for the series form). **Works, chapters and series: no fault left that
this index can see.**

