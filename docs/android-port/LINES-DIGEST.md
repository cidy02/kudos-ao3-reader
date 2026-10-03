# Android Port Lines Digest

This digest reconciles four diverged lines into the base (`android/redesign-parity`).

## kudos-ao3-reader-android
| # | Feature / fix (plain words) | Files (paths under android/) | Classification | Evidence | Port notes |
|---|---|---|---|---|---|
| 1 | Home tab Phase A port | `app/src/main/java/io/github/cidy02/kudos/home/HomeResumeCards.kt`, `HomeScreen.kt`, `HomeSectionListScreen.kt` | SUPERSEDED | Log `9118e61b`; diff `HomeResumeCards.kt` +L6, `HomeScreen.kt` +L62. | Base redesign has entirely replaced the Home UI and queue cards. Discard. |
| 2 | Legacy membership tombstones & whole-run sync single-flight | `app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt`, `BackupMappers.kt`, `BackupRepository.kt` | MISSING | Log `e2d10385`, `255d4a99`; diff `BackupMergeService.kt` +L13, +L112. | Base has its own sync hardening but lacks these specific Android/iOS interop fixes for tombstone IDs and LWW. |
| 3 | Author's notes detection in TXT/PDF and marking in HTML | `app/src/main/java/io/github/cidy02/kudos/works/converters/HTMLWorkConverter.kt`, `PDFWorkConverter.kt`, `PlainTextWorkConverter.kt` | MISSING | Log `bf9b943e`, `63e8a426`; diff `HTMLWorkConverter.kt` +L1. | Port to the base converters. |
| 4 | Offline state, help links, error message collapsing, reader reject foreign locators | `app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3Client.kt`, `AO3Error.kt`, `ReaderScreen.kt`, `SettingsScreen.kt` | MISSING | Log `fe1c805e`, `0d33b816`; diff `AO3Client.kt` +L12, `ReaderScreen.kt` +L24. | Straightforward port. |
| 5 | Library ordering, Privacy reveal-all, Backup clamp & prune fixes | `app/src/main/java/io/github/cidy02/kudos/library/LibraryScreen.kt`, `LibraryPrivacy.kt`, `BackupManifest.kt` | MISSING | Log `8c8de18f`, `c066196e`; diff `LibraryScreen.kt` +L22, `BackupManifest.kt` +L100. | Apply fixes to base. |

## android_ios-parity-port-2
| # | Feature / fix (plain words) | Files (paths under android/) | Classification | Evidence | Port notes |
|---|---|---|---|---|---|
| 1 | Work Detail hero overlay for 2x2 status grid & masonry Browse | `app/src/main/java/io/github/cidy02/kudos/ui/components/WorkStatusIconGrid.kt`, `BrowseScreen.kt`, `Skeleton.kt` | SUPERSEDED | Log `ee9dc880`, `6265aadf`; diff `WorkStatusIconGrid.kt` +L180, `BrowseScreen.kt` +L129. | Base redesign uses different UI components for status and browsing. |
| 2 | hasGivenKudos feature | `app/src/main/java/io/github/cidy02/kudos/data/local/KudosDatabaseMigrations.kt`, `app/src/main/java/io/github/cidy02/kudos/backup/BackupManifest.kt`, `WorkRepository.kt` | MISSING | Log `9bb9a1c1`; diff `KudosDatabaseMigrations.kt` +L227, `BackupManifest.kt` +L45. | Needs to be added to the unified schema migration. |
| 3 | Missing restricted works fix for signed-in users | `app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchRepository.kt`, `AO3BrowseRepository.kt` | MISSING | Log `a832848e`; diff `AO3SearchRepository.kt` +L16. | Apply the query fix to base network components. |
| 4 | MuPDF PDF-import engine port & JNI bug fixes | `app/src/main/cpp/kudos_mupdf.c`, `Scripts/build-mupdf.sh`, `app/src/main/java/io/github/cidy02/kudos/works/converters/KudosMuPDF.kt` | MISSING | Log `677df874`; diff `kudos_mupdf.c` +L211. | Entire C++ and JNI layer missing from base. |

## android_fix-savedforlater-race
| # | Feature / fix (plain words) | Files (paths under android/) | Classification | Evidence | Port notes |
|---|---|---|---|---|---|
| 1 | Duplicate "Saved for Later" queue race transaction | `app/src/main/java/io/github/cidy02/kudos/library/ReadingQueueRepository.kt` | MISSING | Log `c76c0d98`; diff `ReadingQueueRepository.kt` +L18. | Wrap queue insertions in the missing transaction. |

## android_tasklist-15-reports
| # | Feature / fix (plain words) | Files (paths under android/) | Classification | Evidence | Port notes |
|---|---|---|---|---|---|
| 1 | Work card stat row parity (published/updated dates) | `app/src/main/java/io/github/cidy02/kudos/data/local/KudosDatabaseMigrations.kt`, `app/src/main/java/io/github/cidy02/kudos/ui/components/WorkStats.kt` | MISSING | Log `a2fc89d5`; diff `KudosDatabaseMigrations.kt` +L205, `WorkStats.kt` +L344. | Base has stat rows but misses these dates. Add columns to schema. |
| 2 | Restore real WebView scrollbar & detailed card stats | `app/src/main/java/io/github/cidy02/kudos/ui/components/WorkStats.kt`, `ReaderScreen.kt` | CONFLICT | Log `fe799218`; diff `WorkStats.kt` +L344. Base has heavily modified cards and reader. | Apply scrollbar fix; adapt stats to redesign's card UI. |
| 3 | Scoped bulk removal & availability sweep UI | `app/src/main/java/io/github/cidy02/kudos/ui/components/ScopedRemovalBulkActionBar.kt`, `app/src/main/java/io/github/cidy02/kudos/settings/AvailabilitySweepScreen.kt` | MISSING | Log `3c0c1cc7`; diff `ScopedRemovalBulkActionBar.kt` +L290. | Port as new features, adapting to new material components. |

## 1. Room schema and migrations
The base (`android/redesign-parity`) is at schema 9, defining `MIGRATION_7_8` (epub preservation columns) and `MIGRATION_8_9` (tombstone signatures). 
`android_ios-parity-port-2` adds `hasGivenKudos INTEGER NOT NULL DEFAULT 0` (diff `KudosDatabaseMigrations.kt` +L227).
`android_tasklist-15-reports` adds `datePublished TEXT NOT NULL DEFAULT ''` and `dateUpdated TEXT NOT NULL DEFAULT ''` (diff `KudosDatabaseMigrations.kt` +L205).

**Proposal**: Since released apps are on v7, and base is at v9 (unreleased/internal to the lane), the simplest chain that preserves all state is:
1. Keep the base `MIGRATION_7_8` (`epubPreservationStatusRaw`, `preservedAt`, `lastPreservationAttemptAt`).
2. Keep the base `MIGRATION_8_9` (`signerPublicKey`, `signature`).
3. Add a new `MIGRATION_9_10` to apply the columns from the diverged lines:
   - `hasGivenKudos INTEGER NOT NULL DEFAULT 0`
   - `datePublished TEXT NOT NULL DEFAULT ''`
   - `dateUpdated TEXT NOT NULL DEFAULT ''`

Update all `app/schemas/*.json` accordingly up to version 10.

## 2. Backup manifest
Fields read/written by diverged lines not present in base:
- `hasGivenKudos: Boolean` (`BackupManifest.kt` +L45 from `android_ios-parity-port-2`).
- `datePublished: String`, `dateUpdated: String` (from `android_tasklist-15-reports`).
- Note: `epubPreservationStatusRaw`, `preservedAt`, `lastPreservationAttemptAt` were added in the 0.2.1-alpha shared base (in `kudos-ao3-reader-android` and `android_fix-savedforlater-race`) but the base branch *already has* these.

## 3. Overlaps
- `kudos-ao3-reader-android` and `android_fix-savedforlater-race` share the identical 43 commits from the `0.2.1-alpha` base. This includes AuthorNoteDetector, EPUB preservation on backup, BackupMergeService tombstone logic, Library screen UI passes, etc. These should be ported **once**.
- `Relicense to AGPL-3.0` is duplicated across `kudos-ao3-reader-android`, `android_ios-parity-port-2`, and `android_fix-savedforlater-race`. The base branch already has or should have the updated LICENSE.
- All lines modify `BackupMergeService.kt` heavily, primarily because they all carry the 0.2.1-alpha sync logic that needs to be cleanly grafted onto the base branch's own sync hardening.

### Recommended Port Order & Estimates
1. **Migrations & Backup (100 lines)**: Add `MIGRATION_9_10` and `BackupManifest.kt` fields (`hasGivenKudos`, dates) so all subsequent data layers build.
2. **Overlap Base (0.2.1-alpha) (1,500 lines)**: The 43 commits shared by lines 1 and 3 (sync logic, `AuthorNoteDetector`, error collapsing). Ignore UI passes superseded by the redesign.
3. **Queue Race Fix (20 lines)**: `android_fix-savedforlater-race` top commit.
4. **MuPDF & Native Engine (500 lines)**: C++ files and build scripts from `android_ios-parity-port-2`.
5. **Missing Network/API Fixes (150 lines)**: `hasGivenKudos` and restricted-works fixes from `android_ios-parity-port-2`.
6. **Tasklist 15 Reports (800 lines)**: Scoped bulk removal, availability sweep UI, and scrollbar from `android_tasklist-15-reports`.
