# Streaming `manifest.json` on iOS and Android — plan

Owner, 2026-11-22: "raise the limit and plan a change to stream the manifest on both platforms".
Status: **plan only** (tasks T-567 iOS, A-567 Android). The limit raise is A-566 (Android, by measurement).

## Why

`manifest.json` is the one JSON document that carries the whole library apart from the files: works, bookmarks,
collections, queues, annotations, saved searches, reading sessions, favorites, watermarks, settings, pronunciations,
tombstones (`docs/KUDOSBACKUP_FORMAT.md`). Both apps hold the entire document in memory, several times over:

| Platform | Read today | Write today |
|---|---|---|
| iOS | `FolderSyncService.swift:742/763` and `KudosBackup.swift:233/349/357` load the file into one `Data` (`.mappedIfSafe`), then `KudosBackupContents.decodeManifest` (`KudosBackup.swift:478`) runs one `JSONDecoder` over it, which builds a tree of the whole document before the typed structs. Cap: ZIP entry 200 MB (`MiniZip.swift:76`). | `manifestData()` (`KudosBackup.swift:472`) encodes the whole manifest to one `Data`; `FolderSyncService.swift:1014` and `KudosBackupExport.swift:176` write it. |
| Android | `SyncRepository.readLimitedBytes` → `String` (UTF-16, 2× the bytes) → `parseToJsonElement` for the pass-through (`SyncManifestPassthrough.kt:66`) **and** `decodeFromString<KudosBackupManifest>` (`BackupValidator.kt:31`): two full parses. Cap: `BackupLimits.MAX_MANIFEST_BYTES` = 8 MiB (`BackupVersion.kt:39`). | `BackupJson.encodeToString(manifest)` → `toByteArray` (`BackupExporter.kt:38`, `SyncRepository.kt:437`). |

Peak memory grows with the file. Android's 8 MiB cap exists for that reason, and a large enough library would hit a
memory limit on iOS too, only later. Streaming makes peak memory depend on the largest single record, not the library.

## Decisions

1. **The on-disk format does not change.** Still one `manifest.json`, same keys, same JSON. No v9, no shards. Every
   older build, the golden archives (`CrossPlatformBackupTests`, `CrossPlatformFolderSyncTests`) and the
   `manifest.json`-is-the-commit-point rule of Folder Sync stay valid. (Sharding into `works.jsonl` etc. was
   considered and rejected for now: it needs both apps and every older reader to change together.)
2. **One splitter algorithm, written twice, tested by shared vectors.** A small byte-level scanner walks the top-level
   object and yields `(key, kind, byteRange)` for each top-level value and, for top-level arrays, one byte range per
   element. It tracks only strings, escapes and nesting depth; it does not interpret values. iOS (Swift) and Android
   (Kotlin) each implement it (~150 lines); both run the same conformance vectors in
   `KudosTests/Fixtures/cross-platform/manifest-splitter/` (escaped quotes and backslashes, `\u` escapes, emoji,
   nested arrays in records, empty arrays, `null` values, whitespace, truncated input).
3. **Decode one element at a time** with the existing decoders: iOS `JSONDecoder` per element range of the mapped
   `Data`; Android `parseToJsonElement` + `decodeFromJsonElement` per element (one tree, reused for both the typed
   record and the pass-through, instead of two parses).
4. **Semantics the decoder already has must survive exactly**: missing key vs JSON `null` vs `[]` (T-563
   `omittedKeys`), `LossyArray` for `writingRecovery` / `documents` (one bad entry doesn't sink the rest), unknown
   keys ignored by iOS and carried by Android (A-541a), version check, `supportedVersions`.
5. **Write streams too**: open the temp file, write `{`, then each key with its value; arrays are written element by
   element (`JSONEncoder` per element on iOS, `encodeToStream` per element on Android), then the same atomic
   rename/commit as today. Output may differ in whitespace or key order from today's bytes; content must be equal.
   (Android compares a digest of bytes it uploaded to detect its own manifest, so the first write after the change
   reads as "changed" once — harmless, note it in the PR.)
6. **Limits change meaning** once memory no longer scales with the file: a per-record cap (e.g. 1 MiB per element,
   catches a single absurd record) plus a total file cap equal on both platforms (iOS's 200 MB), and the Android
   8 MiB → A-566 value goes away.

## Phases

| Phase | Platform | Change | Done when |
|---|---|---|---|
| P0 | Android | **A-566**: raise `MAX_MANIFEST_BYTES` by measurement (peak ≤ 128 MiB), remove avoidable copies. | Measured table in `out/a566-measure.md`; gate green. |
| P1 | both | Splitter + shared vectors (no callers yet). | Both suites pass the same vectors. |
| P2 | iOS (T-567) | `decodeManifest` reads via the splitter, returns the same `KudosBackupManifest`. No caller changes. | All backup/sync tests and golden archives pass unchanged; a memory test shows peak ≈ typed size, not ≈ 3–5× file size. |
| P2 | Android (A-567) | Sync and import read via the splitter; one tree per element for typed + pass-through. | Same as iOS; A-541a pass-through tests unchanged. |
| P3 | both | Streaming write (export + Folder Sync). | Round trip iOS → Android → iOS and the reverse on a 100 MB generated manifest, on both gates. |
| P4 | Android | Pass-through keeps only the **unknown** keys of each record (not the whole raw record), so the overlay stops being a second copy of the library. | Overlay size measured before/after. |
| P5 | both, only if measurements still demand it | Consumers (restore, merge) take sequences or batch by ID instead of whole arrays. | Only after P2–P4 numbers. |

P1–P3 are independent of A-541a landing, except that Android P2 touches the pass-through read and should start
from `android/rd-a541a` once it lands.

## Verification

- Memory tests on both platforms with generated manifests of 8 / 32 / 100 MB (works with full tags and summaries,
  many reading sessions, unknown iOS keys): record peak memory before and after each phase.
- Golden archives and cross-platform fixtures pass byte-for-content (decoded equality).
- Folder Sync crash points (asset upload, manifest temp write, rename) behave as today.
- Each new test is shown red on the old code, per the review rules.

## Risks

- **Splitter bugs** (an escape or Unicode edge case splits a record wrongly): mitigated by the shared vectors and by
  validating every element through the real decoder; any splitter error fails the whole read, as a bad manifest
  does today — never a partial import.
- **Behaviour drift in decode semantics** (missing vs `null`, lossy arrays): covered by keeping the existing tests
  and adding vectors for each.
- **Write path ordering**: the temp-file + rename commit point must stay the last step; no partial `manifest.json`
  may ever be visible in the sync folder.
