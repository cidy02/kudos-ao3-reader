# A5 result: Android reader and library

Read-only. No source file was edited. Nothing was built, committed, or sent to archiveofourown.org. iOS was read at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` and not changed.

`minSdk` is 26 (`android/app/build.gradle.kts`). Room is 2.8.4 (`android/gradle/libs.versions.toml`). `MainActivity` declares `android:configChanges="orientation|screenSize|screenLayout|keyboardHidden|smallestScreenSize|density"` (`android/app/src/main/AndroidManifest.xml`), so a rotation does not recreate the activity or dispose the reader composition.

| id | severity | path:line | statement |
|---|---|---|---|
| A5-1 | P1 | `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderProgressSaver.kt:35` | Leaving or backgrounding can drop the page turn already taken out of `pending`, and a later full-row upsert can write the old locator back over one that did commit. |
| A5-2 | P1 | `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderScreen.kt:637` | The position card scrubs the whole book and saves that place. The card says the scrub is inside the chapter. |
| A5-3 | P2 | `android/app/src/main/java/io/github/cidy02/kudos/reader/EndOfWorkActions.kt:37` | A completed work is marked finished at 98.5% of the book, or at 95% of the last spine item, and an unprotected copy starts its 60-day hold then. |
| A5-4 | P1 | `android/app/src/main/java/io/github/cidy02/kudos/reader/AnnotationRepository.kt:181` | A second highlight of the same words in the same chapter overwrites the first highlight's anchor. |
| A5-5 | P2 | `android/app/src/main/java/io/github/cidy02/kudos/library/LibraryViewModel.kt:250` | A Library section bulk action still applies to rows a quick filter has hidden. |
| A5-6 | P2 | `android/app/src/main/java/io/github/cidy02/kudos/library/QueuePageScreen.kt:460` | Remove on a queue still removes works a quick filter has hidden. |

## A5-1. Leaving can drop or revert the last page turn

`android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderProgressSaver.kt:21-38`

```kotlin
fun onProgress(progress: ReaderProgress) {
    pending = progress
    job?.cancel()
    job = scope.launch {
        delay(debounceMillis)
        flushPending()
    }
}

suspend fun flush() {
    job?.cancel()
    flushPending()
}

private suspend fun flushPending() {
    val toSave = pending ?: return
    pending = null
    save(toSave)
}
```

The saver is built on `viewModelScope` and its `save` is `persistLocation` (`ReaderViewModel.kt:75-77`). Background and leave both call `flush()` and then `finishReading` (`ReaderViewModel.kt:160-176`). The screen calls those from `ON_STOP` and from `DisposableEffect` dispose (`ReaderScreen.kt:293-297`).

`persistLocation` and `finishReading` each read the whole work and upsert a whole snapshot (`ReaderRepository.kt:113-136`). `applyProgress` copies `isFinished` and the locator fields from that snapshot (`ReaderProgressMapper.kt:64-73` keeps every field the `copy` does not set). `setFinished` does the same with the locator taken from its own snapshot (`WorkRepository.kt:270-284`). `WorkDao.upsert` is `@Upsert` of `WorkEntity` (`WorkDao.kt:11-17`). The Android `@Upsert` reference says an existing row is updated from the method parameters, and a column subset is updated only when the parameter type is a different class from the entity. This parameter is the entity, so the write puts the snapshot's columns back, including a stale locator or a stale `isFinished`. The DAO comment on those lines says the same call is an in-place update.

`ReaderProgressGate.consider` moves its baseline when it accepts a report (`ReaderProgressGate.kt:77-79`), so the same locator is not offered again.

Checked against kotlinx.coroutines: `Job.cancel` makes the coroutine throw `CancellationException` at its next suspension point. The two lines that take `pending` and set it to null do not suspend. `save` does. Room's suspend DAO path suspends (`RoomDatabase.useConnection` in room-runtime 2.8.x). A cancel that arrives while that call is suspended, before the writer transaction starts, means the transaction does not start. A transaction that has already started on the writer thread is not rolled back by the coroutine cancel; it can still commit. `flush` does not join that job.

iOS keeps the latest locator across the cancel and writes it before the flush returns.

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/ReaderReadium/ReadiumProgressPersistence.swift:102-108` and `:130-134`

```swift
func locatorForFlush() -> String? {
    guard let latest = latestLocatorString else { return nil }
    guard latest != lastPersistedString else { return nil }
    return latest
}

func cancelTrailingWrite() {
    trailingTask?.cancel()
    trailingTask = nil
}
```

`cancelTrailingWrite` drops the sleep task. It leaves `latestLocatorString` in place. `flushProgress` calls it and then writes `locatorForFlush()` with `modelContext.save()` before returning (`ReadiumReaderView.swift:902-925`). Backgrounding calls that flush before the `scenePhase` callback returns (`ReadiumReaderView.swift:404-406`).

**Failing case.** The reader has a stored position. The user turns a page. `onProgress` accepts it, so `pending` holds the new locator and the 1500 ms job is running. The delay ends, `flushPending` sets `pending` to null, and `persistLocation` is suspended before its writer transaction starts. The user presses Back, or switches apps, in that window. `flush` cancels the job and sees `pending == null`, so it writes nothing. The gate baseline is already the dropped locator. Reopen uses the locator from before the page turn.

The same leave also calls `finishReading` without waiting for a save that had already reached the writer thread. `finishReading` upserts the row it read, locator included. If that read happened before the in-flight save committed and the upsert happens after, the shelf stamp puts the old locator back.

A second overlap, independent of leave: the debounced `persistLocation` has read a not-finished row and has not upserted, and `maybeAutoFinish` (`ReaderViewModel.kt:145-151`) has `setFinished` read that same row. Whichever upsert commits last keeps its snapshot. One outcome stores the new locator with `isFinished` still false. The other stores `isFinished` true with the locator from before that save.

`ReaderProgressSaverTest.flushPersistsPendingImmediately` (`android/app/src/test/java/io/github/cidy02/kudos/reader/ReaderProgressSaverTest.kt:32-39`) calls `flush` during the delay, before `save` starts. It still passes when a cancel inside `save` drops the value.

**Smallest fix.** Keep the value until `save` returns. `flush` should await the in-flight save, then write a newer `pending` if one arrived, and the write should run in `NonCancellable`. Put `persistLocation`, `finishReading`, and `setFinished` behind one mutex for that work, or update only the columns each call owns.

## A5-2. The chapter scrub jumps through the book and saves that place

`android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderScreen.kt:356-363` and `:633-648`

```kotlin
val currentProgress = state.liveProgress?.totalProgression?.toFloat()
    ?: ReaderProgressDisplay.percent(
        state.liveProgress,
        publication.readingOrder.size
    )?.div(100f) ?: 0f

val page = state.liveProgress?.spineIndex?.plus(1) ?: 1
val pageCount = publication.readingOrder.size.coerceAtLeast(1)
```

```kotlin
onSeek = { progression ->
    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
    val spineCount = publication.readingOrder.size
    if (spineCount > 0) {
        val targetIndex = (progression * spineCount).toInt()
            .coerceIn(0, spineCount - 1)
        val fraction = (progression * spineCount) - targetIndex
        val target = ReaderRestoreTarget.Fallback(
            targetIndex,
            fraction.toDouble()
        )
        val loc = ReadiumProgressAdapter.initialLocator(target, publication)
        if (loc != null) {
            navigatorController.go(loc, animated = false)
        }
    }
},
```

`initialLocator` for a fallback builds a locator at that spine item and that resource progression (`ReadiumProgressAdapter.kt:51-55`). `go` moves the navigator. The navigator's locator callback calls `onProgress` (`ReaderScreen.kt:418-421`), which is the save path in A5-1. The slider label is "Seek within chapter" and the time suffix is "left in chapter" (`ReaderPositionCard.kt:216` and `:230`). `minutesRemaining` is the whole work's remaining words divided by 200 (`ReaderProgressDisplay.kt:43-49`).

iOS treats the thumb as pages inside the current resource and seeks inside that resource.

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift:233-235`

```swift
/// A compact reading position for the progress pill: overall percent, chapter
/// place, and **swipe-scale** page within the chapter (never ~1KB positions
/// as "Page X of Y" — that was the "2 of 13 vs 6 of 103" bug).
```

The thumb is `(page - 1) / (pageCount - 1)` for that resource (`ReadiumReaderView.swift:1773-1777`). Releasing it calls `goToProgressionInCurrentResource` (`ReadiumReaderView.swift:1840-1847`), which copies the current locator and sets `locations.progression` (`ReadiumBook.swift:404-412`). The card's minutes come from remaining Readium positions (`ReaderTimeEstimate.swift:6-14`), and the chapter line is `remainingInChapter` (`ReadiumReaderView.swift:1764-1765`).

**Failing case.** A 20-chapter work, reader in the last chapter at resource progression 0.8, with `totalProgression` 0.99. The card shows "Page 20 of 20", the thumb sits at 99%, and TalkBack says "Seek within chapter: Page 20 of 20". The minutes line is the whole work's remainder labeled "left in chapter". Drag the thumb to 0.95. `0.95 * 20` is 19.0, so `targetIndex` is 19 and `fraction` is 0. `go` opens the start of the last chapter. That locator is what the next accepted `onProgress` stores. Reopen is the start of the last chapter. iOS would move within the pages of the chapter the reader was already in.

**Smallest fix.** Drive the thumb from the current resource's page and progression, and seek by copying the current locator with that resource progression, as `goToProgressionInCurrentResource` does. Pass minutes left in the chapter. Keep the spine index out of the "Page X of Y" line.

## A5-3. Auto-finish treats 98.5% as the end

`android/app/src/main/java/io/github/cidy02/kudos/reader/EndOfWorkActions.kt:17-42`

```kotlin
/** Total-progression threshold treated as "at end" (iOS trailing-edge). */
const val END_PROGRESSION_THRESHOLD = 0.985

fun isAtEndOfPublication(progress: ReaderProgress?, spineCount: Int): Boolean {
    if (progress == null) return false
    progress.totalProgression?.let { total ->
        return total >= END_PROGRESSION_THRESHOLD
    }
    if (spineCount <= 0) return false
    val lastSpine = spineCount - 1
    return progress.spineIndex >= lastSpine && progress.scrollFraction >= 0.95
}
```

`maybeAutoFinish` calls `markFinished` when the work `isComplete`, is not finished, and this function returns true (`ReaderViewModel.kt:145-151`). `markFinished` calls `setFinished`, which sets `isFinished` and, for an unprotected work that has an EPUB, sets `freedAt` to now (`WorkRepository.kt:274-280`). Opening the work later calls `releaseHeldCopy` (`ReaderRepository.kt:53`), which clears `freedAt`.

iOS finishes only on the trailing edge of the last reading-order resource, and it does not start the hold until the reader leaves.

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderCompletion.swift:21-33`

```swift
static func isAtEnd(viewport: NavigatorViewport?, readingOrder: [ReadiumShared.Link]) -> Bool {
    guard let viewport, let lastLink = readingOrder.last else { return false }
    let lastHref = lastLink.url().normalized.string
    guard let visibleLast = viewport.resources.last(where: {
        $0.href.normalized.string == lastHref
    }) else { return false }
    return visibleLast.progression.upperBound == 1.0
}
```

The comments at lines 6-19 say a progression threshold was the "99% ≈ done" defect, and `totalProgression` is the leading edge and is not consulted. The rising edge calls `onReachedPublicationEnd` (`ReadiumBook.swift:1010-1019`). That handler sets `isFinished` for a complete, unfinished work and does not call `markFinished` (`ReadiumReaderView.swift:1373-1395`). The hold is `freeEPUBIfFinished` from `onDisappear` (`ReadiumReaderView.swift:428`, `WorkLifecycle.swift:113-116`). Explicit `markFinished` does hold immediately (`WorkLifecycle.swift:16-20`); the automatic path does not.

`EndOfWorkActionsTest.endDetectedByTotalProgression` asserts that spine 3 of 10, scroll 0.5, `totalProgression` 0.99 is the end (`EndOfWorkActionsTest.kt:23-30`). `endDetectedByLastSpineScroll` asserts scroll 0.97 on the last spine (`:44-50`). Both lock in this rule.

**Failing case.** A completed, unprotected fic. The navigator reports `totalProgression` 0.99 while the reader is on spine item 4 of 10, halfway through that item (the test's inputs). Android sets finished and sets `freedAt`, so the copy enters Recently Deleted's 60-day hold. iOS leaves it unfinished until the last resource's trailing edge is exactly 1.0, and it starts the hold only when the reader leaves. Marking the work still reading, or opening it again, clears the hold. If the reader does neither, `sweepHeldCopies` deletes the file after 60 days (`WorkRepository.kt:310-321`).

**Smallest fix.** Finish only when the visible viewport's last reading-order resource has its trailing edge at 1.0. Delete the 0.985 and 0.95 shortcuts, and change those two tests. Start the hold from reader close, which already calls `holdFinishedCopy` (`ReaderRepository.kt:151`).

## A5-4. A repeated phrase overwrites the earlier highlight

`android/app/src/main/java/io/github/cidy02/kudos/reader/AnnotationRepository.kt:136-144` and `:165-181`

```kotlin
val existing = findSamePassage(workId, selectedText, progression, spineIndex)
val annotation = if (existing != null) {
    existing.copy(
        colorRaw = color,
        note = note.ifBlank { existing.note },
        kindRaw = kind,
        locatorString = locatorString.ifBlank { existing.locatorString },
        lastModifiedAt = Instant.now()
    )
} else {
```

```kotlin
return observeForWork(workId).first()
    .filter {
        it.kindRaw.equals("highlight", ignoreCase = true) ||
            it.kindRaw.equals("note", ignoreCase = true)
    }
    .filter { it.spineIndex == spineIndex }
    .filter { it.selectedText.trim().equals(needle, ignoreCase = true) }
    .minByOrNull { kotlin.math.abs(it.progression - progression) }
    ?.takeIf { kotlin.math.abs(it.progression - progression) < 0.05 }
```

`addHighlight` calls this without `annotationEditMutex` (`ReaderViewModel.kt:241-252`). Recolor and note edits use the mutex (`:268-286`).

iOS reuses a highlight only when the stored locator string is the same, and only for kind highlight.

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/ReaderReadium/ReadingAnnotationMatching.swift:13-20`

```swift
static func isSamePassage(
    existingLocator: String,
    selectionLocator: String
) -> Bool {
    !existingLocator.isEmpty
        && !selectionLocator.isEmpty
        && existingLocator == selectionLocator
}
```

`existingHighlight` filters `kind == .highlight` and uses that function (`ReadiumReaderView.swift:676-689`). The comment on lines 9-12 says text and position fallbacks were removed because repeated short phrases matched the wrong mark.

**Failing case.** In one chapter, highlight "Harry" at progression 0.10 and attach a note. Highlight another "Harry" at progression 0.12 with a different color and no note. The distance is 0.02, which is under 0.05, and the trimmed text matches. Android updates the first row's locator and color and keeps the old note on the new anchor. The first passage no longer has a mark. iOS inserts a second highlight because the locator strings differ.

**Smallest fix.** Match only equal stored locator strings, and only highlights, as `isSamePassage` does. Run `addHighlight` under the same mutex as the other annotation writes.

## A5-5. Library section bulk actions include hidden rows

`android/app/src/main/java/io/github/cidy02/kudos/library/LibraryViewModel.kt:249-256`

```kotlin
fun bulkSoftDelete() {
    val ids = selectedWorkIds.value
    if (ids.isEmpty()) return
    viewModelScope.launch {
        for (id in ids) {
            workRepository.softDelete(id)
        }
```

`bulkSetFavorite`, `bulkSetSaved`, `bulkSetFinished`, `bulkRemoveFromSaveForLater`, `bulkAddToSaveForLater`, `bulkAddToQueue`, and `bulkAddToCollection` all take `selectedWorkIds.value` the same way (`LibraryViewModel.kt:204-304`). `selectedCount` is that set's size (`LibraryModels.kt:103-104`). The delete dialog uses it (`LibraryScreen.kt:342-350`).

On a section list the quick-filter chips stay clickable during selection (`LibraryScreen.kt:1333-1356`). Reading Now's WIP chip sets `LibraryCompletionFilter.InProgress`. Favorites' chips only change the local `favoriteQuickFilter` (`LibraryScreen.kt:1238-1243`). Either way the rows on screen are `filterLibrarySectionItems` (`LibrarySectionQuickFilter.kt:46-52`), which drops complete works for WIP, and drops non-rereads or online works on Favorites. Select All replaces the set with the ids on screen (`LibraryScreen.kt:1249-1264`). A later chip change does not remove ids that left the list. The confirm count and the bulk call still use the full set.

iOS applies the bar to the rows still on screen, and the Favorites chips stay available in that list.

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Library/LibrarySectionListView.swift:145-147`

```swift
private var selectedWorks: [SavedWork] {
    visibleItems.filter { selection.contains($0.id) }
}
```

The All / Rereads / Offline / WIP rail is `favoriteQuickFilter` (`LibrarySectionListView.swift:453-460`). The bulk bar is given `selectedWorks` (`:191` and `:195`).

Home already intersects. The dashboard uses `selectable.filter { it.id in selection }` (`HomeScreen.kt:120-121`). A home section uses `visibleItems.filter` (`HomeSectionListScreen.kt:194-196`). Collection detail's `selectedWorks` on iOS is the unfiltered `works` (`Collections.swift:147-155` and `:534-536`), so Android's `bulkRemove(selectedIds)` matching that is the same rule.

**Failing case.** Library → Reading Now, with a complete-on-AO3 in-progress work and a WIP. Select both. Tap the WIP chip. The complete work leaves the list and stays in `selectedWorkIds`. Delete says "Delete 2 works?" and moves both to Recently Deleted. iOS deletes the WIP only. The same steps on Favorites with the Offline chip, after selecting an offline work and an online one, unsave or delete both. Soft delete is the 90-day Recently Deleted path, so the works can be restored.

**Smallest fix.** Intersect `selectedWorkIds` with the ids currently shown before the confirm count and before every bulk call, the way `selectedWorks` does.

## A5-6. Queue remove includes hidden rows

`android/app/src/main/java/io/github/cidy02/kudos/library/QueuePageScreen.kt:452-467`

```kotlin
if (showRemove) {
    val count = selected.size
    AlertDialog(
        ...
        confirmButton = {
            TextButton(onClick = {
                val ids = selected
                showRemove = false
                scope.launch {
                    ids.forEach { repository.removeWork(queueId, it) }
```

While selecting, `QueueHeaderDetails` stays up and its quick filter still assigns `quick` (`QueuePageScreen.kt:300-310`). `shown` is the filtered list (`:193-200`). WIP keeps `!work.isComplete` (`ReadingQueueFacts.kt:28-32`). Select All replaces `selected` with `shown` (`QueuePageScreen.kt:261-266`). Changing the chip afterward leaves the hidden ids selected. The dialog count is `selected.size`.

iOS hides that rail during selection and still intersects.

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift:154-159`

```swift
/// Selection acts on what is on screen: Select hides the filter rail, so a
/// filtered-out or hidden work must never be removed, moved, tagged or
/// downloaded unseen (L3 B2 #1).
private var selectedWorks: [SavedWork] {
    displayedWorks.filter { selection.contains($0.id) }
}
```

During selection the header replaces the filter rail with the status row (`ReadingQueueBrowser.swift:557-566`).

**Failing case.** A queue with a complete work and a WIP. Select both. Tap WIP. The complete work leaves the list and stays in `selected`. Remove says "Remove 2 works from this queue?" and removes both. The works stay in the library. iOS removes the WIP only.

**Smallest fix.** Remove, and the dialog count, should use `selected` intersected with `shown`. Hiding the quick filter during selection matches the iOS rail.

## Unconfirmed

These are not findings. Each one needs the check named here.

- `pauseReadingSession` and `close` return as soon as they launch `viewModelScope` work (`ReaderViewModel.kt:179-184`). `ON_STOP` and dispose therefore return before Room has committed. Whether a process kill in that gap loses the flush depends on the navigation dispose-versus-`ViewModel.onCleared` order and on the writer thread. A5-1 does not depend on that kill. `ReaderViewModel` does not override `onCleared`.
- `ReadiumProgressAdapter.toReaderProgress` takes the spine index from `link.url().toString() == locator.href.toString()` and coerces a miss to 0 (`ReadiumProgressAdapter.kt:19-23`). A real AO3 EPUB whose href does not string-match would store `lastSpineIndex` 0 and file new highlights on spine 0. Restore of an Android envelope still uses the envelope (`ReaderProgressMapper.kt:22-24`). Confirm with one downloaded EPUB's reading-order URL against `Locator.href`.
- The content tap listener returns true (`ReadiumNavigatorHost.kt:148-153`). The comment says Readium has already handled pagination. Confirm against Readium 3.3.0 `InputListener` order before calling a swallowed page turn.
- `ReaderProgressGate` discards the first report that carries `totalProgression` even when spine or scroll already left the landing (`ReaderProgressGate.kt:65-70`). Confirm from a navigator trace that those two reports are both the open page.
- `ReadiumNavigatorHost` remembers the fragment factory on publication, initial locator, and font declarations. `setFontFamily` was not shown to change `fontDeclarations`, so a font change recreating the navigator and saving a zero locator is not established.
- `ReaderScreen.kt:713` and `:726` store a Find in Work bookmark at spine 0 when `hrefKey` misses the section. Tapping Bookmark twice on one result is a recorded gap (`docs/android-port/DECISIONS.md`, the 2026-10-05 note that points at `briefs/3ai-result.md`) and is not filed here.
- The Library dashboard still assigns `onShowFilters` while selection is on (`LibraryScreen.kt:249`), and the selection list is `state.items` (`:734-741`). Fandom chips are hidden in selection (`:718-720`). Whether the filter control can still be opened, and then hide a selected row, was not confirmed.
- Reading Insights week buckets, words per hour, and finish rate were not compared line by line with `Services/ReadingInsights.swift`. `ReadingStatistics.wordsRead` summing finished works' word counts matches `Features/Library/ReadingStatistics.swift:47-48`.

## Checked and not filed

- The open landing is discarded on purpose (`ReaderProgressGate.kt:13-15` and `:45-50`). A foreign locator is rejected on purpose (`ReadiumNavigatorController.kt:82-88`). Spine fallback restores scroll 0 (`ReaderProgressMapper.kt:25-29`), matching `ReadiumBook.open`.
- Highlights and notes are deleted and tombstoned with a hard-deleted work (`WorkRepository.kt:414-425`).
- The Display sheet's pitch slider is session-only, and Kokoro's `setPitch` is a no-op. Pitch was left out in `DECISIONS.md` (2026-10-05) and `briefs/3ak-result.md`.
- `HomeFacts.upNext` calls `first()` after an empty check. `CollectionDetailScreen`'s `collection!!` is inside `collection != null`. `QueueEditorSheet`'s `existing!!` is inside the editing branch. `ReaderSearchGrouping.first()` is on a `groupBy` bucket. `java.nio.file.Files` in `ReaderRepository.open` is API 26.
- Reading-log pause, resume, and the 15-second minimum match `Services/ReadingLogService.swift` closely enough that no session-count bug was confirmed. `ReadingLogServiceTest` asserts background time is excluded and a short visit is dropped.
- Recently Deleted's bulk restore and delete use `allEntries.filter { it.id in selection }` (`RecentlyDeletedScreen.kt:652`). That screen has no row filter that hides entries. iOS intersects the same way (`RecentlyDeletedView.swift:169` and `:359-366`).

## Not read

- Most of `reader/speech/` beyond `KokoroTTSController.setPitch`, `setRate`, and the speak call. Pronunciations and the Kokoro rows were out of scope.
- `reader/settings/` past `ReaderPreferences`, `ReaderSpeechPreferences.applyTo`, and a mapper grep. `ReaderSearch.kt`, `ReaderContentsSheet` past its call site, `ReaderChrome`, `ReaderLinkHandler`, the highlight decoration listener, the settings adapter, and the publication opener.
- `works/` detail, rebuild-from-original, and the finished / favourite / delete actions outside `WorkRepository.setFinished`, `holdFinishedCopy`, `releaseHeldCopy`, `softDelete`, and `hardDelete`.
- `HomeViewModel`, and the hero's click through to which work id. `HomeResumeHero.kt` was read for the Resume label only. `AppNavHost`'s reader route was not read.
- `LibraryFilter` past the completion enum and `LibraryQuery.matchesFilters`. Queue membership editing past `QueuePageScreen` and a `ReadingQueueRepository` grep. Statistics past `ReadingStatistics.kt` and the `wordsRead` comparison.
- `DECISIONS.md` outside the 2026-10-05 reader notes (about lines 480-599) and a slider grep. Brief results other than `3ak-result.md` (pitch) and the `3ai-result.md` bookmark gap cited from that decision.
- iOS `Services/ReaderProgressBridge.swift`, `Services/ReadingInsights.swift` past a grep, and `Services/ReadingProgress*.swift` (the progress type that is present is `ReadiumProgressPersistence.swift`).
- Tests other than `ReaderProgressSaverTest`, `ReadingLogServiceTest`, `EndOfWorkActionsTest`, `ReadiumProgressAdapterTest`, the start of `ReaderFanMenuTest`, and greps of `LibrarySelectionTest`, `LibrarySectionQuickFilterTest`, `ReaderProgressMappingTest`, `ReaderProgressDisplayTest`, and `AnnotationTombstoneTest`.

## Triage (Claude, 2026-10-08)

Each finding read against the Kotlin and the Swift it cites. All six are real.

- **A5-1 real, fixed; P2 as it stands** (the window is the few milliseconds of a save, 1.5 s
  after a page turn, and what is lost is one page turn). `ReaderProgressSaver` now finishes a
  save it has begun and a flush waits for it (`NonCancellable` under a mutex); Mark as
  Finished writes the position first. Tests `aFlushDuringASaveWaitsForItAndLosesNothing`,
  `aFlushWritesWhatArrivedDuringASave`. **Still open** (its first unconfirmed suspicion):
  `close()` and `pauseReadingSession()` launch on the view model's scope and return; if the
  view model is cleared before they finish, the session's end and the shelf date are lost.
  Needs a look at the order of dispose and `onCleared` on a device.
- **A5-2 real, not fixed: brief `3br`.** The position card's thumb is the whole book's
  progress, its label and its minutes say "chapter", and a drag goes to a chapter's start.
- **A5-3 real, not fixed: brief `3br`.** Finished at 98.5% of the book: on a long work that
  is a chapter early, and the copy's 60-day hold starts then. iOS finishes at the last
  resource's trailing edge and starts the hold on leaving.
- **A5-4 real, fixed.** The same passage is the same stored locator, as iOS. Test
  `theSameWordsFurtherDownAreASecondHighlightNotTheFirstMoved`. New highlights now go
  through the annotation mutex.
- **A5-5 and A5-6 real, fixed.** A row a quick filter hides leaves the selection, in the
  Library's section lists and on a queue page (`LibrarySelection.visible`). iOS keeps a
  hidden id selected and skips it; here it is dropped, so switching the filter back does
  not reselect it. Test `aRowAFilterHidesLeavesTheSelection`; the two screens' effects are
  not covered by a screen test.
- Unconfirmed suspicions: the spine index coerced to 0 on an href mismatch
  (`ReadiumProgressAdapter.kt:19-23`) and the Library dashboard's filter during selection
  (`LibraryScreen.kt:249`) are worth a look; the rest wait.
