# D6 result: the older stale facts in KUDOSBACKUP_FORMAT.md and AGENT_ONBOARDING.md

**Proposed edits: iOS 15, Android 15 (30 in all).** Per file, in each repo: `KUDOSBACKUP_FORMAT.md` 10 edits,
`AGENT_ONBOARDING.md` 5 edits.

Read-only: nothing was run except `git grep`, `git show`, `grep`, `unzip -l/-v` and a read-only counting script.
No builds, no test runs, no network.

Read at: iOS repo `/Users/cidy02/kudos-ios-polish` HEAD `7dc23568` (`claude/polish-loop`), Android repo
`/Users/cidy02/kudos-android-lane` HEAD `022755f2` (`android/redesign-parity`). Counts are taken from HEAD
with `git grep`/`git show`, not the working trees, because both working trees have uncommitted edits.

## Facts that apply to both repos

- **The two docs are byte-identical in the two repos** (`diff` printed nothing for both files). So every
  "current" sentence below is the same text at the same line in both repos, and every replacement is the same
  in both, except Edit O1 (the counts differ) and the evidence lines, which name each repo's own files.
- **Both repos carry the same Swift backup code** at the cited lines (`KudosBackup.swift:595-596`
  `currentVersion = 8`, `MiniZip.swift:568` `ArchiveWriter`, `FolderSyncService.swift:89`), so the iOS-side
  evidence holds for both.
- **Android-side evidence is from the Android repo's Kotlin** (`android/app/src/main/java/io/github/cidy02/kudos/backup/`).
  The iOS repo also has an `android/` directory, but it is an older, smaller tree (507 files against 1,205; 889
  `@Test` against 3,308) and has no `ZipCentralDirectory.kt`. Its `BackupVersion.kt` (`CURRENT = 8`) and
  `BackupExporter.kt` (`ZipOutputStream`) agree with the Android repo, so no replacement below claims anything
  the iOS repo's `android/` tree lacks.
- **How the counts were made** (Edit O1). The method was calibrated first: at commit `fb6d6edf` (T-74, the commit
  that recorded "216 tests / 29 suites") it gives exactly **216** `@Test` functions in **29** types that contain an
  `@Test`. So the doc's old numbers were counts of `@Test` functions and of types containing `@Test`, not of
  `@Suite` attributes (only 6 existed then).
  - Swift Testing tests: `git grep -h -P "@Test\b" HEAD -- KudosTests`, dropping lines that start with `//`, `*`
    or `/*`. This counts 2,364 lines that start with `@Test` plus 4 that carry `@MainActor @Test func` on one
    line.
  - XCTest methods: `git grep -h -P "^\s*(@MainActor\s+)?(nonisolated\s+)?(final\s+)?(private\s+)?func test\w*\s*\("`
    under `KudosTests`. All are in 5 `XCTestCase` classes (`KokoroBoilerplateFilterTests`,
    `KokoroNaturalnessTests`, `KokoroQuoteDirectionTests`, `TTSSpeechUnitTests`, `TextChunkerTests`).
  - Suites: types (struct/class/enum/actor, nested ones included) whose body directly contains an `@Test`, found
    by a brace-depth scan of each file with an `@Test`. It ignores braces inside string literals, so treat it as
    approximate (±1–2). It is exact at T-74.
  - Android: `git grep -P "@Test\b" HEAD -- android/app/src/test` minus comment lines: 3,308 in 443 files
    (501 files under `src/test`). No `@Ignore`, no `androidTest` directory.
  - Six iOS tests are `@Test(… arguments:)`, so the runner's own total will be a little higher than these
    declaration counts. D5's "about 2,358 tests" was an estimate; the declared count is 2,491.

| | `@Test` | XCTest `func test` | Types with `@Test` | `XCTestCase` classes |
|---|---|---|---|---|
| iOS repo, Swift `KudosTests` | 2,368 | 123 | 263 | 5 |
| Android repo, Swift `KudosTests` | 2,294 | 122 | 252 | 5 |
| Android repo, Kotlin `android/app/src/test` | 3,308 (443 files) | n/a | n/a | n/a |

---

## iOS repo: `/Users/cidy02/kudos-ios-polish/docs/KUDOSBACKUP_FORMAT.md` (10 edits)

### F1 — lines 3–4 (what folder sync is)

- **Current:**
  ```text
  Cross-platform contract for **manual import/export**. Folder sync may still use a
  directory package on disk; that is an iOS transport detail, not the portable format.
  ```
- **Evidence:** the sync payload is the `KudosLibrary/` directory, written by both apps.
  `FolderSyncService.swift:89` (`syncDirectoryName = "KudosLibrary"`; the doc comment above it: "a plain directory of
  per-record files", T-139, `b15cac6`). Android: `SyncRepository.kt:192-196` (`findFile("KudosLibrary")` /
  `createDirectory("KudosLibrary")`) and the fixture `KudosTests/Fixtures/cross-platform/android-sync-folder/KudosLibrary/`
  (`manifest.json`, `Works/`, `Fonts/`, `Originals/`). So it is not an iOS-only detail, and it is not a "package".
- **Replace with:**
  ```text
  Cross-platform contract for **manual import/export**. Folder sync (iOS and Android) uses a
  plain `KudosLibrary/` directory with the same tree; that is a transport detail, not the portable format.
  ```

### F2 — line 11 (container row)

- **Current:** `| Container | **ZIP** (classic / non-ZIP64) |`
- **Evidence:** the reader resolves ZIP64 records and the writer emits them when a value outgrows its classic field.
  `MiniZip.swift:40-56` (reader doc comment), `MiniZip.swift:561-564` (writer: "ZIP64 records are emitted exactly
  when a value outgrows its classic 16/32-bit field"), commits `682d4dfd` … `f450da0e` (branch commits labelled T-140,
  merged and renumbered **T-145** in TASKS.md line 476). Android reads a ZIP64 central directory
  (`ZipCentralDirectory.kt:4`, `parseZip64Extra`, line 100) but caps archives at 1 GiB
  (`BackupVersion.kt:37`), so it writes classic archives in practice.
- **Replace with:** `| Container | **ZIP**, classic or ZIP64 (ZIP64 records only where a value outgrows its classic field) |`

### F3 — lines 16–17 (who writes which method)

- **Current:**
  ```text
  iOS writes **store-only** entries (EPUBs are already compressed). Android and other
  clients may write deflate for `manifest.json` if useful; readers must accept both.
  ```
- **Evidence:** iOS still writes only method 0 (`MiniZip.swift:697`, `:725` `appendU16(0) // method: stored`). Android
  writes every entry deflated: `BackupExporter.kt:32` `ZipOutputStream(output)` with `ZipEntry(path)` and no
  `STORED` setting (line 96). `unzip -v KudosTests/Fixtures/cross-platform/android-export.kudosbackup` shows
  `Defl:N` on all six entries (manifest, two EPUBs, the font, both `Originals/` files).
- **Replace with:**
  ```text
  iOS writes **store-only** entries (EPUBs are already compressed). Android writes every
  entry deflated (`ZipOutputStream` default); readers must accept both.
  ```

### F4 — lines 21–25 and line 30 (layout: the missing `Originals/` folder)

- **Current (layout block and the bullet that follows the list):**
  ```text
  manifest.json
  Works/<uuid>.epub
  Fonts/<safe-filename>
  ```
  and `- Directory-only entries are optional and ignored.`
- **Evidence:** both apps write and read an `Originals/` folder: `KudosBackup.swift:490-503` (`zipData()` appends
  `Originals/<fileName>`), `:423-433` (`originalFileNames`, discovered from entry names, no manifest field);
  introduced by `c585611a` (2026-09-21, "Carry imported originals in backups"). Android: `BackupExporter.kt:74-75`,
  `BackupPaths.kt:34-43` (`ORIGINALS_DIRECTORY`, `<UPPERCASE-UUID>.<ext>`, `<UPPERCASE-UUID>.conversion.json`). The
  Android fixture archive has `Originals/10000000-…0001.html` and `.conversion.json`.
- **Replace with:** the layout block
  ```text
  manifest.json
  Works/<uuid>.epub
  Fonts/<safe-filename>
  Originals/<safe-filename>
  ```
  and, directly above `- Directory-only entries are optional and ignored.`, one added bullet:
  `- `Originals/` holds the file a converted import was made from (`<UPPERCASE-UUID>.<ext>`) and its record (`<UPPERCASE-UUID>.conversion.json`); it has no manifest field.`

### F5 — line 37 (manifest version)

- **Current:** `- JSON object; schema version in `version` (currently **7**; decoders accept 1…7).`
- **Evidence:** `KudosBackup.swift:595-596` `static let currentVersion = 8` and
  `supportedVersions: Set<Int> = [1, 2, 3, 4, 5, 6, 7, currentVersion]`. Version 8 (in-book annotations) arrived in
  `33349be7` ("Backup: manifest v8 carries in-book annotations"). Android: `BackupVersion.kt:23` `CURRENT = 8`, `:25`
  `supported = (APPLE_V1..CURRENT)`, i.e. 1…8. The Android-written fixture manifest has `"version": 8`
  (`unzip -p … android-export.kudosbackup manifest.json`).
- **Replace with:** `- JSON object; schema version in `version` (currently **8**; decoders accept 1…8).`

### F6 — line 45 (iOS / macOS row of Platform notes)

- **Current:**
  ```text
  | iOS / macOS (this app) | `MiniZipWriter` (store-only) via `KudosBackupContents.zipData()` | `MiniZip` with `.backup` size limits |
  ```
- **Evidence:** there is no `MiniZipWriter` anywhere under `kudos-ao3-reader/` (grep for the name finds nothing). The
  writer is `MiniZip.ArchiveWriter` (`MiniZip.swift:568`). Export streams to a file:
  `KudosBackupService.makeExportPlan` (`KudosBackupExport.swift:78`) then `writeArchive` (`:192`).
  `KudosBackupContents.zipData()` (`KudosBackup.swift:490`) still builds the same archive in memory
  (`MiniZip.archiveData`, `MiniZip.swift:782`). Reader: `MiniZip(data:limits: .backup)` (`KudosBackup.swift:353`).
- **Replace with:**
  ```text
  | iOS / macOS (this app) | `MiniZip.ArchiveWriter` (store-only), streamed to a file by `KudosBackupService.writeArchive`; `KudosBackupContents.zipData()` builds the same archive in memory | `MiniZip` with `.backup` size limits |
  ```

### F7 — line 46 (Android row of Platform notes)

- **Current:** `| Android (future / sibling) | `java.util.zip.ZipOutputStream` | `ZipInputStream` / `ZipFile` |`
- **Evidence:** the Android app exists and ships this format. Create: `BackupExporter.kt:32` (`ZipOutputStream`). Extract:
  `BackupImporter.kt:35` (`ZipInputStream(ByteArrayInputStream(bytes))`, after `ZipCentralDirectory.requireReadable`
  at line 24). No `ZipFile` is used in `backup/`. The fixtures in `KudosTests/Fixtures/cross-platform/` were written
  by Android, and iOS tests read them (`4a63e64b`, `b43fd9e1`).
- **Replace with:** `| Android (`android/`) | `java.util.zip.ZipOutputStream` (`BackupExporter`) | `ZipInputStream` (`BackupImporter`) |`

### F8 — lines 54–55 (legacy directory packages)

- **Current:**
  ```text
  Older exports and iOS **Library Sync Folder** packages may still be a **directory**
  named `*.kudosbackup` with the same internal tree. Importers **must** accept:
  ```
- **Evidence:** the live sync folder is no longer a `*.kudosbackup` package. `FolderSyncService.swift:89`
  (`KudosLibrary` directory) and `:98-104` (`legacySyncFileName = "KudosLibrary.kudosbackup"`, "The pre-2026 payload …
  Strictly read-only now"). The directory-package import path still exists (`KudosBackup.swift:224`, `:233`), so
  the two numbered rules below the sentence stay true.
- **Replace with:**
  ```text
  Older exports, and the pre-2026 iOS **Library Sync Folder** package (`KudosLibrary.kudosbackup`,
  now read-only), may still be a **directory** named `*.kudosbackup` with the same internal tree. Importers **must** accept:
  ```

### F9 — line 64 (first Non-goals bullet: ZIP64 and the size limit)

- **Current:** `- ZIP64 (archives stay under classic size limits; iOS backup limit is ~3.5 GiB uncompressed total).`
- **Evidence:** ZIP64 is supported (F2). The iOS backup limits are `Limits.backup`: 250,000 entries, 1,000,000,000
  bytes per entry, 64,000,000,000 bytes total, ratio 1100 (`MiniZip.swift:99-104`; raised in `682d4dfd`, T-145 row).
  Android: `BackupLimits` `MAX_ARCHIVE_BYTES` 1 GiB, `MAX_ENTRY_BYTES` 128 MiB (`BackupVersion.kt:37-38`).
  A non-goal that is a shipped feature is wrong, so the bullet moves out of Non-goals and its numbers are corrected.
- **Replace with:** delete the bullet from Non-goals, and add this row to the Container table, after the
  "Path encoding" row:
  ```text
  | Size limits | iOS reads up to 250,000 entries, 1 GB per entry, 64 GB total; Android reads up to 1 GiB per archive and 128 MiB per entry |
  ```

### F10 — line 65 (second Non-goals bullet)

- **Current:** `- Partial / streaming sync redesign (full package remains the portable unit).`
- **Evidence:** sync is already incremental and streaming export exists: the sync folder writes per-record files with
  `manifest.json` last (`FolderSyncService.swift:84-89`, T-139), and the export streams to a file (T-145,
  `KudosBackupExport.swift:192`). What is still not streamed is restore: the archive is mapped into memory and
  opened as `MiniZip(data:)` (`KudosBackup.swift:352-353`); T-145 records "streaming restore is a documented deferral".
- **Replace with:** `- Streaming restore (export streams to a file; restore still opens the whole archive in memory; the full archive remains the portable unit).`

---

## iOS repo: `/Users/cidy02/kudos-ios-polish/docs/AGENT_ONBOARDING.md` (5 edits)

### O1 — line 58 (the test count)

- **Current:**
  `2. New behavior has tests (see REGRESSION_TEST_MATRIX for suite placement). Suite count only goes up (216 tests / 29 suites as of T-74).`
- **Evidence:** the counts in the table above, at HEAD `7dc23568`, by the method calibrated on T-74 (216 / 29
  reproduced exactly). Recorded runs in `TASKS.md` lines 92–94 give 2,314 tests, from an older point on this branch.
- **Replace with:**
  `2. New behavior has tests (see REGRESSION_TEST_MATRIX for suite placement). Suite count only goes up (2,368 `@Test` functions in 263 suites, plus 123 XCTest methods in 5 classes, as of 2026-10-22; counted by `git grep`, not by a test run).`

### O2 — line 12 (the model list)

- **Current:**
  `- **Models**: all `@Model` classes in `Models/Models.swift` (`SavedWork`, `WorkCollection`, `ReadingQueue`, `ReadingQueueMembership`, `Tag`, `Bookmark`, `CustomFont`, `SavedSearch`, `SyncTombstone`). Remote value types in `Models/AO3Models.swift`.`
- **Evidence:** `grep -rn -A3 "^@Model" kudos-ao3-reader` finds 13 `@Model` classes: in `Models.swift` `SyncTombstone` (:72),
  `SavedWork` (:134), `Tag` (:678), `Bookmark` (:695), `CustomFont` (:715), `WorkCollection` (:741), `ReadingQueue`
  (:874), `ReadingQueueMembership` (:986), `ReadingAnnotation` (:1068); in their own files `FandomReadWatermark`,
  `ReadingFavorite`, `ReadingSession`, `SavedSearch` (all under `Models/`). So `SavedSearch` is listed but not in
  `Models.swift`, and four classes are missing from the list.
- **Replace with:**
  `- **Models**: the `@Model` classes in `Models/` — `Models.swift` holds `SavedWork`, `WorkCollection`, `ReadingQueue`, `ReadingQueueMembership`, `Tag`, `Bookmark`, `CustomFont`, `ReadingAnnotation`, `SyncTombstone`; `SavedSearch`, `ReadingSession`, `ReadingFavorite` and `FandomReadWatermark` each have their own file. Remote value types in `Models/AO3Models.swift`.`

### O3 — lines 24–26 (three rows that duplicate and contradict lines 22, 23 and 27)

The table has two "Test destination", two "Parallel tests" and two "Signing" rows. `git blame`: lines 22–23 are
from `5bd9304c` (2026-08-14), line 27 from `a339a4ac` (2026-08-12), lines 24–26 are the older `bf08c45f`
(2026-07-07) text that was never removed.

- **Current (delete these three rows in full):**
  ```text
  | Signing | Simulator/tests: `CODE_SIGNING_ALLOWED=NO`. Device builds need a team in Xcode's Accounts pane. ⚠️ Policy drift: AGENTS.md says keep `DEVELOPMENT_TEAM` scrubbed to `""`, but commit `bcfe335`'s follow-ups carry `NQH85H7343` — human decision pending; don't "fix" either way without asking. |
  | Test destination | `platform=iOS Simulator,name=iPhone 17,OS=26.5` (canonical, used in TASKS.md verification notes). |
  | Parallel tests | **Disabled** (`Scripts/test.sh` passes `-parallel-testing-enabled NO`): `PersistenceOperationGate` is a process-wide static lock; parallel suites contend it and flake. Persistence-touching suites are `@Suite(.serialized)`. |
  ```
- **Evidence:** the tests run only on a UDID, never on a named device: `Scripts/test.sh` exits 64 without
  `KUDOS_CASEFOLD_SIMULATOR_UDID` and hands off to `Scripts/test-casefold-fonts.sh`, whose destinations are
  `-destination "id=$SIMULATOR_UDID"` (lines 79, 141). `-parallel-testing-enabled NO` is at
  `test-casefold-fonts.sh:143`, not in `test.sh`. Line 22 and line 23 already say this correctly. Line 27 is the
  fuller Signing row.
- **Replace with:** nothing (delete the three rows). Lines 22, 23 and 27 stay.

### O4 — line 27 (the end of the Signing row: "human decision pending")

- **Current (the part that changes, at the end of the row):**
  `⚠️ Policy drift: AGENTS.md says keep `DEVELOPMENT_TEAM` scrubbed to `""`, but commit `bcfe335`'s follow-ups carry `NQH85H7343` — human decision pending; don't "fix" either way without asking. |`
- **Evidence:** the decision was made. `Scripts/check-invariants.sh:141-143` ("NQH85H7343 is the owner's real Apple
  Developer team ID … the owner has explicitly decided it is fine to keep tracked in project.pbxproj … Do not "fix"
  this by scrubbing it", dated 2026-08-16) and `:149` (`PUBLIC_PLACEHOLDER_TEAM="NQH85H7343"`, the only team value
  the gate accepts). At HEAD `project.pbxproj` has `DEVELOPMENT_TEAM = "";` at both places (lines 686, 709), and
  `AGENTS.md` line 130 still says scrubbed to `""`. So "pending" is out of date, but the two files still disagree.
  **Owner call:** keep the last sentence so nobody picks a side.
- **Replace that part with:**
  `⚠️ AGENTS.md says keep `DEVELOPMENT_TEAM` scrubbed to `""`, and `project.pbxproj` has `""`; `Scripts/check-invariants.sh` also accepts `NQH85H7343`, which it records as owner-approved to stay public (2026-08-16), and rejects any other team. Don't "fix" either way without asking. |`

### O5 — line 33 (the branch chain)

- **Current:**
  `- `merge-test` = integration branch (linear chain of every feature since T-65). Features stack on the latest tip: `merge-test` ← `indexing-implementation` ← `release-hardening` (current tip).`
- **Evidence:** `git for-each-ref` lists no `merge-test`, `indexing-implementation`, `release-hardening` or `hig-review`
  ref, local or `origin/*`, in either repo. The refs that exist are `main`, `integrate/cloud-redesign`,
  `claude/polish-loop` and `android/redesign-parity`. `claude/polish-loop` (this branch) is not a descendant of
  `integrate/cloud-redesign`, so the current chain is not a simple line. `AGENTS.md` ("check `TASKS.md`'s newest rows
  for the tip") already tells agents where the tip is. `AGENTS.md` itself still names `merge-test` as the
  integration branch. **Owner call:** whether `merge-test` is still the name; this edit drops only the dead chain.
- **Replace with:**
  `- `merge-test` = integration branch (linear chain of every feature since T-65). Features stack on the tip that `TASKS.md`'s newest rows name.`

---

## Android repo: `/Users/cidy02/kudos-android-lane/docs/KUDOSBACKUP_FORMAT.md` (10 edits)

Edits F1–F10: **the current text and the replacement are the same as the iOS repo's F1–F10** (same lines, same
text; the file is byte-identical). Evidence for the Android repo's own tree:

- F1: `SyncRepository.kt:192-196`; Swift `FolderSyncService.swift:89`.
- F2: Swift `MiniZip.swift:561-568`, `:40-56`; Kotlin `ZipCentralDirectory.kt:4-11`, `:100`
  (last touched `b4969b07`, 2026-10-21, "3fw"); `BackupVersion.kt:37`.
- F3: `BackupExporter.kt:32`, `:96`; fixture `Defl:N` on all entries.
- F4: `BackupExporter.kt:74-75`; `BackupPaths.kt:34-43`; Swift `KudosBackup.swift:423-433`, `:500-503`.
- F5: `BackupVersion.kt:23-25` (`CURRENT = 8`, supported 1…8); Swift `KudosBackup.swift:595-596`; fixture
  `"version": 8`. `BackupExporter.kt:22` writes `BackupVersion.CURRENT`, and `:26` stamps `schemaVersion = BackupVersion.CURRENT`.
- F6: Swift `MiniZip.swift:568`, `:782`; `KudosBackup.swift:490`; `KudosBackupExport.swift:78`, `:192`.
- F7: `BackupExporter.kt:32`; `BackupImporter.kt:24`, `:35`.
- F8: Swift `FolderSyncService.swift:89`, `:98-104`.
- F9: Swift `MiniZip.swift:99-104`; Kotlin `BackupVersion.kt:36-42`.
- F10: Swift `FolderSyncService.swift:84-89`; `KudosBackup.swift:352-353`.

For F7, this repo's Android tree can say more than the doc line needs. It could also name `BackupMergeService`. The
replacement above stays the same, since that is all the table row records.

## Android repo: `/Users/cidy02/kudos-android-lane/docs/AGENT_ONBOARDING.md` (5 edits)

### O1 — line 58 (the test count; this one differs from iOS)

- **Current:** the same sentence as iOS O1.
- **Evidence:** counts in the table above, at HEAD `022755f2`. This repo's Swift `KudosTests`: 2,294 `@Test` in 252
  types, 122 XCTest methods in 5 classes. Its Kotlin `android/app/src/test`: 3,308 `@Test` in 443 files (the working tree
  has 3,313: four test files have uncommitted edits).
- **Replace with:**
  `2. New behavior has tests (see REGRESSION_TEST_MATRIX for suite placement). Suite count only goes up (Swift: 2,294 `@Test` functions in 252 suites, plus 122 XCTest methods in 5 classes; Android: 3,308 `@Test` functions in `android/app/src/test`; as of 2026-10-22, counted by `git grep`, not by a test run).`

### O2 — line 12 (the model list)

- **Current and replacement:** the same as iOS O2. Evidence: the same 13 `@Model` classes at the same lines in this
  repo's `kudos-ao3-reader/Models/` (`grep` output identical).

### O3 — lines 24–26 (the three duplicate rows)

- **Current and replacement:** the same as iOS O3 (delete the three rows). Evidence: same scripts. `Scripts/test.sh`
  requires the UDID, and `Scripts/test-casefold-fonts.sh:79`, `:141`, `:143` hold the destination and the parallel flag.

### O4 — line 27 (the Signing row's "human decision pending")

- **Current and replacement:** the same as iOS O4. Evidence: this repo's `Scripts/check-invariants.sh` has the same
  guard text, and `project.pbxproj` has `DEVELOPMENT_TEAM = "";` at lines 686 and 709.

### O5 — line 33 (the branch chain)

- **Current and replacement:** the same as iOS O5. Evidence: the same four refs exist here, and none of
  `merge-test`, `indexing-implementation`, `release-hardening`, `hig-review`.

---

## Seen and left alone (no edit proposed)

- `AGENT_ONBOARDING.md` line 3, "Facts below are **confirmed against the codebase as of 2026-07-07**": after the five
  edits it is still not true of every line, because I did not re-check each one. Changing the date would claim
  more than this pass verified. I checked the symbols named in the pitfalls and the high-level section: they exist
  (`PersistenceOperationGate`, `PersistenceMigrationService` in `PersistenceSync.swift`, `WorkTags.refreshFromAO3`,
  `WorkSearchIndex.rebuildIfNeeded` / `reindex`, `applyDebouncedReadiumLocator` and `markModified` in `Models.swift`,
  `AO3RequestDefaults` in `AO3AuthService.swift:245`, `pace()` with `minRequestInterval = 0.6` in `AO3Client.swift:209-211`),
  and `AppTab` has the five cases home, library, browse, account, search, so "4 tabs + global Search" holds.
- `AGENT_ONBOARDING.md` line 21 (Xcode-beta is the active toolchain): a property of one machine. On this machine
  `xcode-select -p` prints `/Applications/Xcode.app/Contents/Developer`. Not code, so not changed.
- `AGENT_ONBOARDING.md` line 7, "(README.md:139)": line 139 of `README.md` is now unrelated text. The disclaimer is at
  lines 38 and 159. It is a stale line reference only; the claim is still true. Not counted as an edit. If you want it
  fixed: `(README.md:38)`.
- `KUDOSBACKUP_FORMAT.md` line 39 names `KudosBackupService.restore`: it exists (`KudosBackup.swift:2104`).
- The comment above `KudosBackupManifest.currentVersion` (`KudosBackup.swift:591-594`) still describes only v7. That
  is code, outside this brief.
