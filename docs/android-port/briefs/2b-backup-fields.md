# Brief 2b-i: back up and restore the schema-11 fields exactly as iOS does

Edit-only. **Do not commit**, push, switch branches, stash or reset. No network. You cannot run
Gradle: write code that compiles by careful reading, and check every symbol you use exists with
that signature. Claude builds, runs the tests and sends compile errors back.

Code: `android/app/src/main/java/io/github/cidy02/kudos/backup/`. The fields already exist on
`SavedWork`, `WorkCollection` and `ReadingQueue` (core/model) and in Room (schema 11).
iOS reference: `kudos-ao3-reader/Services/KudosBackup.swift` (`KudosBackupWork`,
`KudosBackupCollection` ~line 1373, `KudosBackupReadingQueue` ~1428, the collection merge
~2570, the queue merge ~2812) and `SyncMerge.chosenColor` in
`kudos-ao3-reader/Services/PersistenceSync.swift:577`.
JSON config: `BackupJson.kt` (`encodeDefaults = true`, `explicitNulls = false`, so Kotlin nulls
are omitted on export).

## 1. Works (`BackupWork` in BackupManifest.kt, mappers in BackupMappers.kt, `mergeWork` in BackupMergeService.kt)

Add to `BackupWork`, all with default `null`:
- `keepInProgressOverride: Boolean?`
- `bookmarks: Int?`
- `epubDigest: String?`
- `legacyReaderProgress: JsonElement?`
- `hiddenFromHistoryAt: JsonElement?`

`datePublished`, `dateUpdated`, `ao3SeriesID` and `assetIdentifier` already exist on `BackupWork`;
map them too.

`legacyReaderProgress` and `hiddenFromHistoryAt` are **tri-state**, as on iOS (`Double??` and
`Date??`, KudosBackup.swift:923-933 and 1149-1152). A missing key means "leave the local value";
an explicit JSON `null` means "no value"; a value means set it. So:
- **Export (`toBackupWork`) always writes them**: `JsonPrimitive(value)`, or
  `JsonPrimitive(BackupValidator.formatInstant(date))` for the date, or `JsonNull` when the
  value is null. `JsonNull` is a non-null Kotlin value, so `explicitNulls = false` does not drop it.
- **Import (`toSavedWork`)**: a missing key or `JsonNull` → `null`; a number → Double; a string
  → `BackupValidator.parseNullableInstant(…, "work.hiddenFromHistoryAt", exportedAt)`.

Export the rest in `toBackupWork`:
- `keepInProgressOverride` as is.
- `datePublished` and `dateUpdated` as is (iOS writes the string, even an empty one).
- `bookmarks` as `bookmarks ?: 0` (iOS's field is a non-optional Int).
- `ao3SeriesID` as is.
- `epubDigest` and `assetIdentifier` as `ifBlank { null }`.

Do **not** export `freedAt` or `authorIdentitiesJSON`: iOS keeps them on the device.

Import the rest in `toSavedWork`:
- `keepInProgressOverride ?: false`
- `datePublished.orEmpty()` and `dateUpdated.orEmpty()`
- `bookmarks`, `ao3SeriesID`
- `epubDigest.orEmpty()` and `assetIdentifier.orEmpty()`

`mergeWork` (BackupMergeService.kt ~line 394). In the `incomingWins` branch (`restored.copy(...)`),
add:
- `freedAt = existing.freedAt`
- `authorIdentitiesJSON = existing.authorIdentitiesJSON`
- `keepInProgressOverride = archived.keepInProgressOverride ?: existing.keepInProgressOverride`
- `hiddenFromHistoryAt = if (archived.hiddenFromHistoryAt != null) restored.hiddenFromHistoryAt else existing.hiddenFromHistoryAt`
- `legacyReaderProgress =` the same pattern
- `datePublished = restored.datePublished.ifBlank { existing.datePublished }`, and the same for `dateUpdated`, `epubDigest` and `assetIdentifier`
- `bookmarks = archived.bookmarks ?: existing.bookmarks`
- `ao3SeriesID = archived.ao3SeriesID ?: existing.ao3SeriesID`

In the local-wins branch (`existing.copy(...)`), only fill blanks:
- `datePublished = existing.datePublished.ifBlank { restored.datePublished }`, and the same for `dateUpdated`, `epubDigest` and `assetIdentifier`
- `bookmarks = existing.bookmarks ?: archived.bookmarks`
- `ao3SeriesID = existing.ao3SeriesID ?: archived.ao3SeriesID`
- every other new field keeps its local value

## 2. Colour rule

Add `SyncMerge.chosenColor` (`object SyncMerge` is in BackupMergeService.kt) as a straight port:

```kotlin
fun chosenColor(local: Pair<Double?, String?>, incoming: Pair<Double?, String?>, incomingWins: Boolean): Pair<Double?, String?> {
    val incomingHue = incoming.first ?: return local
    if (!incomingWins && local.first != null) return local
    if (incoming.second == null && local.second != null && local.first != null &&
        kotlin.math.abs(local.first!! - incomingHue) < 0.01) return local
    return incomingHue to incoming.second
}
```

## 3. Collections (`BackupCollection`, mappers, `mergeCollections` ~line 786)

Add to `BackupCollection`, defaults `null`:
- `hue: Double?`
- `colorHex: String?`
- `keepsWorksOffline: Boolean?`
- `showsOnHome: Boolean?`
- `workOrderRaw: String?`

Export all five as is. Import as `hue`, `colorHex`, `keepsWorksOffline`, `showsOnHome ?: false`
and `workOrderRaw.orEmpty()`.

Write one private helper, `fillCollectionFields(existing: WorkCollection, archived: BackupCollection, incomingWins: Boolean): WorkCollection`,
ported from iOS KudosBackup.swift ~2576-2600:
- `(hue, colorHex) = chosenColor(...)`
- `keepsWorksOffline = archived.keepsWorksOffline` if it is non-null and
  `(incomingWins || existing.keepsWorksOffline == null)`
- `showsOnHome = archived.showsOnHome` if it is non-null and
  `(incomingWins || !existing.showsOnHome)` (assign, don't OR)
- `workOrderRaw = archived.workOrderRaw` if it is non-null and non-empty and
  `(incomingWins || existing.workOrderRaw.isEmpty())`

Apply it in all three existing-collection paths:
- the `MERGE` branch, with `incomingWins = false`;
- the reconcile branch when `!shouldApplyIncoming`, with `incomingWins = false`. Today that path
  does `return@forEach`. Instead store the filled copy (count it as updated only if it
  changed), then continue;
- the reconcile branch when the archive wins, with `incomingWins = true`, applied to the
  existing collection's values. Do not take a null from `archived` directly.

New collections (`existing == null`) take the archive's values through `toWorkCollection`.

## 4. Queues (`BackupReadingQueue`, mappers, `mergeQueues` ~line 987)

Add to `BackupReadingQueue`, defaults `null`:
- `hue: Double?`
- `colorHex: String?`
- `isPinned: Boolean?`
- `keepsWorksOffline: Boolean?`
- `notes: String?`

Queue tags (`tagNames`) are **not** part of this brief.

Export all five as is. Import as `hue`, `colorHex`, `isPinned ?: false`, `keepsWorksOffline` and
`notes`.

Write a helper, `fillQueueFields(existing: ReadingQueue, archived: BackupReadingQueue, incomingWins: Boolean): ReadingQueue`,
from iOS ~2817-2845:
- colour through `chosenColor`
- `isPinned = archived.isPinned` if it is non-null and `(incomingWins || !existing.isPinned)`
- `keepsWorksOffline` filled if the archive's value is non-null and
  `(incomingWins || existing.keepsWorksOffline == null)`
- `notes = archived.notes` if it is non-null and `(incomingWins || existing.notes == null)`

Apply it in:
- the `MERGE` branch ("Keep local queue name / fields"), with `incomingWins = false`;
- the reconcile branch where the archive does not win, with `false`;
- the reconcile branch where it wins. There the code builds `restored.copy(...)`, whose
  colour fields come straight from the archive and would clear local values. After building
  it, overwrite `hue`, `colorHex`, `isPinned`, `keepsWorksOffline` and `notes` with
  `fillQueueFields(existing, archived, incomingWins = true)`'s values.

## 5. Tests

Create `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupPhase2FieldsTest.kt`. Copy the
setup style from `BackupCompatibilityTest.kt` (`sampleSavedWork`, `samplePackage`,
`sampleManifest`, `sampleBackupWork`, `BackupMergeService.merge(current = BackupLibrarySnapshot(...), backup = ..., now = ...)`).
Cover:
1. A work with every new field round-trips: export through `toBackupWork`, encode with
   `BackupJson`, decode, `toSavedWork`.
2. The tri-state fields:
   - the archive omits `hiddenFromHistoryAt` → the local value is kept even when the archive wins;
   - the archive has an explicit `null` and wins → it clears;
   - the archive has a date and loses → the local value is kept.
3. `freedAt` and `authorIdentitiesJSON` survive a winning archive.
4. `chosenColor`:
   - an incoming nil never clears;
   - incoming wins → takes the incoming value;
   - local wins with a local hue → keeps the local value;
   - local hue nil → fills in;
   - a local hex with the same hue (within 0.01) and an incoming nil hex keeps the local hex.
   Port the iOS cases from `KudosTests` if you find any (`grep -rn chosenColor KudosTests`).
5. A collection: an older archive without `hue` doesn't clear the local colour, and
   `showsOnHome = false` in a losing archive doesn't take a collection off Home.
6. A queue: a losing archive with `isPinned = false` doesn't unpin; a winning one does.
7. Decode a literal JSON work object shaped like an iOS export, with `"legacyReaderProgress": null`,
   `"hiddenFromHistoryAt": "2026-09-01T10:00:00Z"`, `"bookmarks": 12` and `"keepInProgressOverride": true`.

Do not change existing tests. When done, write `docs/android-port/briefs/2b-result.md` (under 300 words):
the files changed and anything you were unsure of.
