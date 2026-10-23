# I11 result (iOS): a failed save says so, instead of closing as if it worked

*Done. Branch `claude/agent-ios-i11` from `7a905485`. Nothing committed. Eight Swift files changed. Paths under `kudos-ao3-reader/`.*

## How each write can fail

- **Reading queues and collections:** SwiftData `ModelContext.save()`, through `saveBestEffort`. It throws on a store or disk error (a full disk, an I/O or store failure), so it can fail, if rarely.
  - `saveBestEffort` logs the error and returns whether the change is now persisted (`Utilities/ModelContext+SaveBestEffort.swift:36-47`). Every one of these sheets threw that answer away.
  - A failed SwiftData save leaves its changes pending in the context, so iOS had two more problems. A retried Create would insert a second queue or collection. And a later autosave could quietly persist an edit the reader had been told nothing about.
- **Pronunciations:** `KokoroPronunciationStore.setOverride` encodes and writes a JSON file and throws on failure (`Features/ReaderReadium/KokoroPronunciationStore.swift:98-106`). Both callers used `try?`.

## The rule on failure (all five sheets)

- The sheet stays open, keeps what was typed, and shows the app's alert pattern (as Recently Deleted's failed restore, `Features/Library/RecentlyDeletedView.swift:244-253`). The words are Android's: **"Could not save"**, with "… wasn't saved. Try again."; for a pronunciation, Android's own "Could not save correction. Try again."
- For SwiftData, the context is rolled back on failure, so the half-made object or the edit is gone. Create or Save can then be tried again without making a duplicate, and Cancel leaves nothing unsaved behind. `KudosBackup`'s restore already uses `rollback()` on the caller's context for the same reason.
- Success behaves exactly as before.

## 1. New Reading Queue and Edit Queue

- **The sheet:** `NewReadingQueueSheet.onCreate` now returns `Bool` (`Features/Library/NewReadingQueueSheet.swift:57`). Create/Save shows the alert when it returns false (`:146`, alert `:172`).
  - Return in the name field creates too, so it reports the same way (`:239-240`). An empty name still does nothing there, as before; the hosts' empty-name guard would otherwise read as "Could not save".
- **New queue, from all three hosts:** each used to close the sheet and clear the name before creating. Now each creates first, asks `context.saveBestEffort` whether it stuck, and on false rolls back and returns false. It clears and closes only on success.
  - Home: `Features/Home/HomeView.swift:637`.
  - The queue organizer: `Features/Library/ReadingQueueOrganizer.swift:603`.
  - The queue browser, which still selects the new queue after a success: `Features/Library/ReadingQueueBrowser.swift:901`.
- **Edit Queue:** `EditReadingQueueSheet` does the same after `updateQueue`, and only starts the offline downloads once the change is saved (`NewReadingQueueSheet.swift:397`).
- **Why the service's signature is unchanged:**
  - `createQueue` and `updateQueue` already end in `saveBestEffort` (`Services/ReadingQueueService.swift:194`, `:236`).
  - Asking `saveBestEffort` once more at the caller reports exactly what the service's own save did. When that save worked there is nothing left to save and it returns true; when the store refused, the changes are still pending, so it retries once and returns false if the store still refuses.
  - Changing the return types would have touched 22 `createQueue` call sites in the tests and four other callers (e.g. Add to Queue's inline "New queue"), all of which keep today's behaviour as it is.

## 2. New Collection and a collection's details

- **New Collection:** `create()` closes only when the save succeeds. Otherwise it rolls back (dropping the inserted collection) and shows the alert (`Features/Library/NewCollectionSheet.swift:168`, alert `:99`).
- **Details (colour, description, the two behaviour switches):**
  - The sheet still writes through on every change, as it always has. Each write's result is now kept in `detailsSaveFailed` (`Features/Library/Collections.swift:118`; writes at `:198`, `:208`, `:231`, `:251`, `:268`; helper `:311`).
  - **Done** (`closeDetails`, `:316`) closes when everything is saved. After a failed write it tries once more, and if that also fails it keeps the sheet open with "Could not save" / "Your changes to this collection weren't saved. Try again."
  - The alert's choices are **Try Again** and **Discard Changes** (destructive: rolls back and closes). The sheet has no Cancel, so this is the way out.
  - While a write is unsaved, the sheet can't be swiped away (`:304`, `interactiveDismissDisabled`).
  - Keep downloads still queues its downloads when switched on, as before.

## 3. The pronunciation editor

- `ReaderPronunciationEditor.onSave` now returns `Bool` (`Features/ReaderReadium/ReaderPronunciationSettingsView.swift:361`). Save closes on true and shows "Could not save correction. Try again." on false (alert `:438`).
- **In Settings:** `save(word:ipa:)` returns whether `setOverride` succeeded (`:226`, `do`/`catch` in place of `try?`).
  - **A rename now saves the new word before removing the old one** (`:182`). It used to remove first, so a failed save lost the old correction as well as the new one.
- **In the reader (Fix Pronunciation):** the closure returns whether `setOverride` succeeded (`Features/ReaderReadium/ReadiumReaderView.swift:280`).
- Forgetting the word from "Words I guessed at" stays best-effort (`try?`). It is a cleanup, and the correction itself is saved by then.

## Tests

No service signature changed, so no service test is required by the brief. These three pin what the sheets now rely on:

1. **`KudosTests/ReadingQueueTests.swift`: a failed queue create can be undone.**
   - Use an in-memory `ModelContainer` with `ModelConfiguration(schema:isStoredInMemoryOnly: true, allowsSave: false)` (SwiftData's own way to make `save()` throw; the suite has no failing-store fake yet).
   - Call `ReadingQueueService.createQueue(named: "X", in: context)` and expect `context.saveBestEffort(reason: "t")` to be false. Then `context.rollback()`, and expect no `ReadingQueue` named "X" in a fetch.
   - What it pins: the guard the hosts use (`HomeView.swift:637` and the others). Without the rollback, a second create would find two "X" queues pending.
2. **`KudosTests/CollectionMembershipDeletionTests.swift` (or a new `CollectionSaveFailureTests`): the same for a `WorkCollection`** inserted the way `NewCollectionSheet.create()` does.
3. **`KudosTests/KokoroPronunciationStoreTests.swift`: `setOverride` throws when the store can't write.** Use `KokoroPronunciationStore(url:)` with a path under a plain file, e.g. a temp file plus "/sub/p.json". The editor's false/alert path depends on that throw; with a `try?` back in place, the call would succeed silently.

## Build and lint

- **iOS:** arm64 simulator SDK, `…/kudos-agent-ios-ios`, BUILD SUCCEEDED. **macOS:** `…/kudos-agent-ios-mac`, BUILD SUCCEEDED. Both rebuilt after the last edit.
- **Compiler warnings:** none new. The one warning in a touched file predates this change: `ReaderPronunciationSettingsView.swift:457`, an unnecessary `try`, shifted from `:439`. The first build caught the name field's unused `onCreate` result, which is now handled (above).
- **SwiftLint:** the same rules as HEAD on all eight files.
  - `ReadingQueueBrowser.swift`'s `file_length` (785 → 790) and `ReadingQueueOrganizer.swift`'s `type_body_length` (473 → 477) were already over and grew by the new lines.
  - `Collections.swift` was kept under its 700-line limit by writing the details helpers compactly.
- **Not run:** tests, the simulator.
