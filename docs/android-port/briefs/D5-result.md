# D5 result: doc statements the 2026-10-22 commits made wrong

**Proposed edits: iOS 2, Android 1.**

Read: all six docs in both repos, against every commit since 2026-10-22 00:00
(iOS 12 commits on `claude/polish-loop`, Android 21 on `android/redesign-parity`).
No commit today touched any of the six docs.

Two facts shaped the count:
- The Android repo's `docs/` copy is the iOS doc set with a few Android sentences added. Its Swift
  files are not the iOS branch's (T-424 and T-428 are not in that tree), so iOS-only statements
  there are not made false by Android's Kotlin commits.
- The DEBUG routes (T-427, T-428, T-432, 3gt), the large-text layouts (T-425), the skeleton rows
  (3gl), the hidden system bars (3gk), the comments notice (T-430, cde116dd) and the editor Preview
  (T-431) are not described in any of the six docs, so they make nothing false.

## iOS (`/Users/cidy02/kudos-ios-polish/docs/`)

### Edit 1 — `DATA_AND_PERSISTENCE_INVARIANTS.md`, line 33

- **Current:**
  `- Tombstones travel in the manifest, merge before conflict resolution, suppress resurrection with a newer-snapshot escape hatch; `restore()` **retracts** the tombstone rather than racing timestamps.`
- **Commit:** `7041ddfb` (T-424). File Merge now un-parks a Recently Deleted work, collection or queue
  (and retracts a work's tombstone) only when the archive's own copy is live
  (`archived.isDeleted != true`). Before, it did so unconditionally.
- **Replace with:**
  `- Tombstones travel in the manifest, merge before conflict resolution, suppress resurrection with a newer-snapshot escape hatch; `restore()` **retracts** the tombstone rather than racing timestamps. In File Merge it does so only for a live archive copy: a work, collection or queue the archive itself marks deleted stays in Recently Deleted, with its tombstone and its deadline.`

### Edit 2 — `ARCHITECTURE_MAP.md`, line 25 (row "Reader — iOS")

- **Current (the part that changes):**
  `... mid-session writes use `applyDebouncedReadiumLocator` so shelf order / folder-sync dirty don't thrash on scroll) |`
- **Commit:** `1354b4b0` (T-428). The view's position save and annotation-delete steps moved, unchanged,
  out of `ReadiumReaderView.swift` into the new `Features/ReaderReadium/ReadiumReaderPersistence.swift`
  (`writePosition`, `deleteAnnotation`; iOS only). `writePosition` is what now calls
  `applyDebouncedReadiumLocator`.
- **Replace that part with:**
  `... mid-session writes go through `ReadiumReaderPersistence.writePosition` (also holds `deleteAnnotation`), which uses `applyDebouncedReadiumLocator` so shelf order / folder-sync dirty don't thrash on scroll) |`
- Minor: the old sentence is not false, it names the wrong place to look.

### The other five iOS docs

- `AGENT_ONBOARDING.md`: nothing stale.
- `AO3_NETWORKING_POLICY.md`: nothing stale. T-429 (challenge settings read only the form the
  collection's kind names) and T-426 (maintainers parse) are not described there.
- `REGRESSION_TEST_MATRIX.md`: nothing stale. T-428's new tests
  (`ReadingAnnotationBackupTests`, `SavedWorkProgressTests`) sit in suites the "Reader progress" and
  "Reader highlights/notes/search" rows already name, and no row says they were untested.
- `KUDOSBACKUP_FORMAT.md`: nothing stale from today.

## Android (`/Users/cidy02/kudos-android-lane/docs/`)

### Edit 3 — `DATA_AND_PERSISTENCE_INVARIANTS.md`, line 33

- **Current:** the same sentence as iOS Edit 1 (identical text on that line).
- **Commit:** `dfef0970` (3gj). Android's file Merge (`BackupMergeService.kt` lines 214, 1386, 1740)
  un-parks a deleted work, collection or queue only when `archived.isDeleted != true`. The iOS
  counterpart is `7041ddfb`.
- **Replace with:** the same replacement as Edit 1.
- Note: this repo's Swift `KudosBackup.swift` does not carry the guard yet. The patch is
  `docs/android-port/briefs/3gj-ios.patch`. The sentence is the shared rule, and the Kotlin side now
  follows it, so apply this edit now.

### The other five Android docs

- `ARCHITECTURE_MAP.md`: nothing stale (no `ReadiumReaderPersistence.swift` in this tree).
- `AGENT_ONBOARDING.md`: nothing stale.
- `AO3_NETWORKING_POLICY.md`: nothing stale. Row "Challenge sign-up match joins" says "the settings
  read", which still holds after `3e23e694` (3gr): a known kind makes one read of that form. The
  sentence never described the gift-then-meme fallback.
- `REGRESSION_TEST_MATRIX.md`: nothing stale.
- `KUDOSBACKUP_FORMAT.md`: nothing stale from today.

## Seen but not today's (not counted)

- Both repos' `KUDOSBACKUP_FORMAT.md` still say version 7, "classic / non-ZIP64" and "Android (future /
  sibling)". All three were wrong before today.
- Both repos' `AGENT_ONBOARDING.md` still say "216 tests / 29 suites as of T-74". The suite is about
  2,358 tests now.
