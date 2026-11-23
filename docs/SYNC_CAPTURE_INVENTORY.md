# Sync capture inventory: every place that writes synced data (T-569 D6, part 1)

Status: inventory, documentation only. No app code changed. Input to G-capture (`docs/DATA_ARCHITECTURE_PLAN.md` v3.2 § B "Change capture", "Save boundary"), and the companion of the D4 matrix (`docs/SYNC_OPERATION_MATRIX.md`, branch `claude/rd-t569d4`) whose entity / value-group vocabulary this uses.

Code read at: iOS `claude/kudos-iphone-redesign-74f213` (`985027170`; the writer code is identical to the `22aeca1a1` tree the D4 matrix cites). Android `rd-a541a` (`7fd493a06`, `/Users/cidy02/kudos-android-a541a/android`). Every `file:line` cites those trees. Nothing here was run: this is a static read, so frequency and "reachable from" statements are code-reading claims, and § 7 lists what was not verified.

Cite shorthand. iOS paths are under `kudos-ao3-reader/`. Android paths are under `android/app/src/main/java/io/github/cidy02/kudos/`.

## 0. How to read the rows

**Columns.** `file:line` is the write itself (the assignment, insert, delete or DAO call), not the function header. *Entity . groups* uses D4 names (SavedWork value groups: Identity, Lifecycle, Text metadata, Counters, Flags, Monotonic, Reading status, Progress, Tag lists, User tags, Preservation, Cover pin, Insights provenance, Chapter word counts, Asset facts, Authors, Download date, Derived/device, Record clock). *Owner . commit* is the context or transaction that holds the write and how it reaches disk. *Origin . freq* is where the write comes from and how often. *Capture* is the strategy recommended for that row; *blocker* is what stops it from being safe today.

**iOS context owners.**
- **MC** = the one shared main-actor `ModelContext` that `.modelContainer(Self.sharedModelContainer)` injects (`App/MyApp.swift:25,50`). Autosave is ON. Every view's `@Environment(\.modelContext)`, every `@Query`-bound edit, every `static func ...(in context:)` service and the sync observer write here, so one dirty change from any writer is committed by the next unrelated `save()`.
- **BG** = a second context, `ModelContext(container)` (`Services/FolderSyncBackgroundTask.swift:65`), used by the BGAppRefresh task.
- **ACT** = `@ModelActor` private contexts (`Services/PersistenceSync.swift:769,804`), `modelContainer`-scoped, off the main actor.
- **RESTORE** = `KudosBackupService.restore` runs on the caller's MC but flushes it first (`Services/KudosBackup.swift:3205-3207`), turns autosave off for the call (`:3212-3214`) and commits once at `:4715`, with `rollback()` on throw (`:3232`).

**iOS commit paths.**
- **SBE** = `saveBestEffort(reason:)` (`Utilities/ModelContext+SaveBestEffort.swift:48`): returns true WITHOUT saving when `autosaveEnabled == false`, logs a failure, never throws.
- **COMMIT** = `commitNow` (`:59`): saves even with autosave off (used by Sort New Undo, `Services/QueueSortNew.swift:654,738`).
- **SAVE?** = `try? context.save()`: failure swallowed. **SAVE!** = `try context.save()`: throws to the caller.
- **AUTO** = no explicit save at all: the change waits for SwiftData autosave or for another writer's `save()`.
- **rollback** = the writer calls `context.rollback()` on the shared MC on failure (also discards other writers' unsaved edits): `Features/Library/Collections.swift:294`, `Features/Home/HomeView.swift:1196`, `Features/Library/NewCollectionSheet.swift:175`, `Features/Library/ReadingQueueOrganizer.swift:636`, `Features/Library/ReadingQueueBrowser.swift:1686`, `Features/Library/NewReadingQueueSheet.swift:904`, `Features/Library/ReadingInsightsSheets.swift:484`, `UIComponents/RemoteWorkSelection.swift:411`, `Services/QueueSortNew.swift:655,739`.

**Origins.** `U` user command (tap, swipe, sheet); `R` reader checkpoint; `IM` import/download; `RS` restore or folder-sync apply; `MG` migration/backfill; `SW` sweep/background task; `AO` AO3 refresh (a network read that rewrites local fields); `LCH` launch task.
**Frequency.** `1` per command; `PT` per page turn / scroll settle but throttled; `O` per reader open/close; `L` per launch; `B` bulk (N rows in one pass); `K` per keystroke.

**Capture codes (iOS).** `CMD` = command-owned save on an isolated, autosave-disabled context plus outbox rows in the same save (plan § B). `CMD-after-draft` = same, but the writer must first stop editing live `@Query` objects (use a draft or a command). `SNAP` = leave to snapshot reconciliation (derived, device-local, or no recoverable intent). `NONE` = must not be captured (derived / device-local / transport state).
**Capture codes (Android).** `TRG` = SQLite trigger on the table. `DAO` = an explicit DAO operation that writes the outbox row in the same `withTransaction`. `TRG+DAO` = trigger for the row diff, DAO op for intent / origin. `SNAP` / `NONE` as above.

**Hazard tags used in the blocker column.**
- `H-shared` writer shares the dirty MC with unrelated writers (the outbox row and the change could be committed by different saves, or one writer's `rollback()` discards another's change).
- `H-auto` change relies on autosave or on a later unrelated save.
- `H-swallow` `try?` save: a failed save leaves dirty state that a later save commits without the command that made it.
- `H-nostamp` the write changes synced data but does not call `markModified` / bump the record clock, so the folder-sync change token (`App/FolderSyncObserver.swift:118-134`, `lastModifiedAt`/`dateAdded`/`dateUpdated` newest per entity, whole-second floor) and any `lastModifiedAt`-keyed diff will not see it.
- `H-cascade` SwiftData relationship delete rule or SQLite FK `ON DELETE CASCADE` removes related rows with no command intent.
- `H-relationship` a to-many relationship (`SavedWork.collections`, `SavedWork.tags`, `ReadingQueue.tags`) changes with no row of its own to carry a stamp or tombstone.
- `H-bulk` one pass touches every row or a bounded batch; per-row outbox rows would be a bulk write.
- `H-order` the file write and the database write are not atomic with each other.
- `H-replace` (Android) `OnConflictStrategy.REPLACE` = delete-then-insert; SQLite does not fire `DELETE` triggers for a REPLACE conflict unless `recursive_triggers` is on, and FK children of the deleted row cascade.
- `H-wholerow` (Android) read-modify-write of the whole row through `workDao.upsert(work.copy(...))`: a stale read writes back untouched columns; a trigger cannot tell which value group the command meant.

