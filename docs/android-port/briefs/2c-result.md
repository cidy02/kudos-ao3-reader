# Brief 2c result

- **Downloaded rule:** `WorkDownloadSemantics` is the pure iOS rule; `SavedWork.isDownloaded` exposes it. `WorkDao.getKeptOfflineWorkIds` plus `WorkRepository.decorate` derive queue/collection keep state (queue `nil` keeps, collection `nil` does not). Library shelves, filters, cards, Home, Browse indicators, Work Detail, and selection state now use it, so reading-only copies are not called downloaded.
- **Download actions:** `WorkDownloadSemantics.action` provides Download, Remove Download, and Kept Offline by _name_. `LibraryScreen`/`LibraryViewModel` and Work Detail use those actions. Remove Download only clears `isSaved`; a missing AO3 EPUB is queued through the existing serial `DownloadQueue`; active keep-offline containers disable removal.
- **Finished-copy lifecycle:** `WorkRepository` now stamps `freedAt`, restores, frees now, releases while reading, re-holds on reader close, and sweeps after `FREED_COPY_WINDOW` (60 days). Saving, favoriting, and adding to a keeping queue/collection clear the hold. `KudosApplication` runs this sweep beside the existing 90-day sweeps. No migration was added.
- **Recently Deleted:** `RecentlyDeletedScreen` retains the existing **Deleted** section and adds **Finished, not kept**, the iOS explanatory text, 60-day expiry, Restore, and Remove Copy actions.
- **Keep works you read / space:** `AppSettings` and `SettingsRepository` add the device-local, default-off `keepsWorksYouRead` key. `ReaderRepository.open` keeps the work when enabled. Settings uses the iOS toggle copy and adds Free up space for every finished, unprotected local copy.
- **Tests:** focused tests cover the pure rule/actions, reading-copy filtering, queue/collection defaults, hold/restore/free/sweep, Remove Download retaining the file, reader open/close behavior, and DataStore persistence.

Left out: nothing from the brief; backup, theme/subject, schema, and networking behavior were intentionally untouched.

Unsure: Android has no persisted `ao3WorkID`; repository decoration uses the shared canonical AO3 URL matcher, so an imported file whose source URL is AO3 cannot be distinguished from an AO3 work as precisely as iOS can.

Verification: core Kotlin compiled with Android Studio's `kotlinc`; the two pure JUnit tests and `git diff --check` passed. The requested Gradle command could not start because this sandbox forbids Gradle's file-lock socket (`SocketException: Operation not permitted`), including with a temporary `GRADLE_USER_HOME`.

## Follow-up

- `statisticsCountWorksThatWereReadThenUnsaved`: kept the expectation. The fixture lacked an AO3 URL, so T-344 correctly classified it as an imported, protected download; it now models an AO3 history work. iOS basis: `Models/Models.swift:469-480`.
- `snapshotIncludesSavedWorksUserTagsAndCollections`: kept the expectation for the same reason and corrected the shared fixture rather than excluding real imports from Android's Library. iOS basis: `Models/Models.swift:469-480`.
- `closingReholdsAFinishedUnkeptReadingCopy`: fixed `ReaderRepository.close` to pass its injected clock into `WorkRepository.holdFinishedCopy`; the hold and `lastModifiedAt` now use the deterministic reader timestamp.
