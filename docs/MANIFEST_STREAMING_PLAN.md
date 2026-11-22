# Streaming `manifest.json` on iOS and Android — plan

Owner, 2026-11-22: "raise the limit and plan a change to stream the manifest on both platforms".
Status: **plan only** (tasks T-567 iOS, A-567 Android). **Goal (owner, 2026-11-22): once streaming is proven, no
manifest size cap on either platform**, with memory that does not grow with the manifest. A-566 measured that
Android's 8 MiB cap cannot change before this lands.

## Why

`manifest.json` is the one JSON document that carries the whole library apart from the files: works, bookmarks,
collections, queues, annotations, saved searches, reading sessions, favorites, watermarks, settings, pronunciations,
tombstones (`docs/KUDOSBACKUP_FORMAT.md`). Both apps hold the entire document in memory, several times over:

| Platform | Read today | Write today |
|---|---|---|
| iOS | `FolderSyncService.swift:742/763` and `KudosBackup.swift:233/349/357` load the file into one `Data` (`.mappedIfSafe`), then `KudosBackupContents.decodeManifest` (`KudosBackup.swift:478`) runs one `JSONDecoder` over it, which builds a tree of the whole document before the typed structs. Cap: none in Folder Sync (read straight from disk, `FolderSyncService.swift:133`); 1 GB per entry in a `.kudosbackup` (`MiniZip.Limits.backup`, `MiniZip.swift:98`). The 200 MB at `MiniZip.swift:76` is the EPUB profile, not the manifest. | `manifestData()` (`KudosBackup.swift:472`) encodes the whole manifest to one `Data`; `FolderSyncService.swift:1014` and `KudosBackupExport.swift:176` write it. |
| Android | `SyncRepository.readLimitedBytes` → `String` (UTF-16, 2× the bytes) → `parseToJsonElement` for the pass-through (`SyncManifestPassthrough.kt:66`) **and** `decodeFromString<KudosBackupManifest>` (`BackupValidator.kt:31`): two full parses. Cap: `BackupLimits.MAX_MANIFEST_BYTES` = 8 MiB (`BackupVersion.kt:39`). | `BackupJson.encodeToString(manifest)` → `toByteArray` (`BackupExporter.kt:38`, `SyncRepository.kt:437`). |

Peak memory grows with the file. Android's 8 MiB cap exists for that reason, and a large enough library would hit a
memory limit on iOS too, only later. Streaming makes peak memory depend on the largest single record, not the library.

**Measured (A-566, Android, desktop JVM, `out/a566-measure.md`):** peak heap is **15–17× the manifest size** on every
path (import, sync, sync with a pending import), almost all of it the typed object graph plus the `JsonElement` trees.
Removing duplicate copies (one parse from bytes, no `String`, no second read at commit) saved only 8–10%:
8 MiB → 119–151 MiB peak, 16 MiB → 231–287 MiB, 32 MiB → 439–558 MiB. So the limit stays 8 MiB until P2/P4 land —
the cost is per-record trees held all at once, which only streaming plus keeping just the unknown keys (P4) removes.
iOS has not been measured yet; P2 starts by measuring it the same way.

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
6. **No manifest size cap once memory is flat** (owner, 2026-11-22). Android's `MAX_MANIFEST_BYTES` check is removed
   from every reader and the exporter (`BackupValidator`, `BackupExporter`, `SyncRepository`, `PickedDocumentReader`), and
   iOS keeps having none in Folder Sync — **in the same change that proves flat memory** (below), never before. What
   stays, because it is not a manifest size cap: (a) a **per-record cap** (e.g. 1 MiB per array element) so one absurd
   record can't exhaust memory while it is the one being decoded — the owner can drop it too; (b) the ZIP **bomb
   protection** for `.kudosbackup` archives: the compression-ratio check stays, and the manifest entry is exempt from the
   per-entry size cap (iOS `MiniZip.Limits.backup` 1 GB, Android `MAX_ENTRY_BYTES` 128 MiB) since it is streamed; EPUB,
   font and original-file entries keep their caps. The EPUB profile's 200 MB per entry (`MiniZip.swift:76`) is unrelated.
7. **Streaming the parse is not enough on its own.** A-566 found the typed records cost about as much as the JSON trees,
   and import, merge and export each hold the whole library as typed objects. For an uncapped manifest the consumers must
   stream too: import writes records to the store in batches as they are decoded; merge looks records up by ID in the
   store instead of in an in-memory copy; export streams from the store (Room cursor / SwiftData fetch in batches) to the
   file; Android's pass-through keeps only each record's unknown keys, spilled to a file keyed by record ID.
8. **Memory budget (definition of done):** peak memory for import, Folder Sync and export stays under **64 MiB above
   the app's baseline at every measured manifest size**, measured with the A-566 benchmark
   (`ManifestMemoryBenchmarkTest`) on Android and an equivalent XCTest on iOS at 8, 32, 128, 256 and 512 MiB — flat across all of them is what "proven" means.

## Phases

| Phase | Platform | Change | Done when |
|---|---|---|---|
| P0 ✅ | Android | **A-566**: measured; removed duplicate copies (−8–10%); limit stays 8 MiB. | `out/a566-measure.md`; on `android/rd-a541a` `7fd493a06`. |
| P1 | both | Splitter + shared vectors (no callers yet). iOS: measure today's peak with the same generated manifests. | Both suites pass the same vectors; iOS baseline table recorded. |
| P2 | both (T-567 / A-567) | Read via the splitter, one record at a time; Android reuses one tree per record for typed + pass-through. Callers unchanged. | All backup/sync tests and golden archives pass unchanged; JSON-tree cost gone in the benchmark. |
| P3 | both | Streaming write (export + Folder Sync) from the store in batches. | Round trip iOS → Android → iOS and the reverse on a generated 128 MiB manifest. |
| P4 | Android | Pass-through keeps only unknown keys per record, spilled to a file by record ID. | Overlay no longer scales with the library in the benchmark. |
| P5 | both | Consumers stream: batched import into the store, merge by ID lookup, no whole-library arrays. | **Memory budget met at every size up to 512 MiB** on both benchmarks. |
| P6 | both | Remove Android's manifest cap (`MAX_MANIFEST_BYTES` checks), exempt the manifest from the ZIP per-entry size cap on both, add the per-record cap. iOS Folder Sync stays uncapped. | Benchmarks flat up to 512 MiB; a 512 MiB round-trip test on both gates. |

P1–P3 are independent of A-541a landing, except that Android P2 touches the pass-through read and should start
from `android/rd-a541a` once it lands. P5 is the largest phase (it changes the restore/merge services on both
platforms) and gets its own adversarial review per platform.

## Verification

- Memory tests on both platforms with generated manifests of 8 / 32 / 128 / 256 / 512 MiB (works with full tags and summaries,
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
