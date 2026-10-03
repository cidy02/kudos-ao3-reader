# Brief T-353 (Android): record when a work was downloaded, and sort the Library by it

The iOS half landed on integrate (`7c11edd9`, `80baffc5`; iOS lane `8932a86e`). Android must
behave **identically**, and a backup from either app must carry the date intact to the other (owner
rule: "iOS and Android must speak the same language"). Read `docs/android-port/LIVING-PROMPT.md` §5b
(the spec, with the owner's words) and the iOS diff:
`git -C /Users/cidy02/Documents/AO3_App_OpenSource/.claude/worktrees/handoff-documentation-2151af/.claude/worktrees/polish show 8932a86e`.

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. Leave changes
uncommitted; Claude builds, runs the gate and commits. If your sandbox can't run Gradle, write
carefully: declare every value before use, and check every symbol and signature you call exists.

## Build (mirror the iOS diff)
1. **Model:** `downloadedAt: Instant?` on the work.
   - Room: an additive nullable column on works, schema **12 → 13**, with a migration in the same
     style as 11→12, the exported schema JSON, and the `RoomDaoTest`/version bumps the earlier
     migrations needed.
   - Domain: `SavedWork.downloadedAt`.
   - Nil for existing works. Never set automatically after capture.
2. **Capture:**
   - An AO3 download finishing sets `downloadedAt = now` (via the repository's injected clock).
   - Imports use the rule below. Re-importing a work that already has one keeps it (iOS: `if
     existing.downloadedAt == nil`).
3. **The rule:** a pure `DownloadDateDetector.detect(fileCreated, fileModified, epubGeneratedAt,
   now)` returning the date and its source (`File`, `Ao3Generated`, `ImportTime`), ported line for
   line from `kudos-ao3-reader/Services/DownloadDateDetector.swift`:
   - Take the earliest file date.
   - Discard it if it's within 5 minutes of now, or earlier than `epubGeneratedAt`.
   - Then fall back to `epubGeneratedAt`, then to now.
   - Android's SAF gives `DocumentsContract.Document.COLUMN_LAST_MODIFIED` and usually no
     creation date; pass null for what you can't read.
   - Parse `<meta name="calibre:timestamp" content="2026-03-03T14:53:11.321543+00:00">` from the
     OPF (microseconds and an offset: test that exact string).
   - Port `KudosTests/DownloadDateDetectorTests.swift` to a JUnit test with the same cases.
4. **Import confirmation:** before an import commits, show the detected date and its source, using
   iOS's strings verbatim from `UIComponents/DownloadDateImportConfirmation.swift`:
   - "Downloaded <date> · from the file";
   - "AO3 generated this copy <date>";
   - "Couldn't tell. Using today".

   Add a date picker (no future dates), and for a batch, "Use each file's download date"
   (default) or "Use today". Use a Material3 `DatePickerDialog`/sheet in the subject style.
5. **Work detail → My copy → Activity:** a "Downloaded" row after "Added", showing the date or "Not
   recorded". It opens a date editor; Save sets the date and stamps `lastModifiedAt` as other
   edits do.
6. **Sort:** add "Date Downloaded" to Library's sorts (`downloadedAt ?? dateAdded`, newest first),
   next to the date-added sort. Test it like iOS's `LibraryFiltersTests` case.
7. **Backup** (`backup/`):
   - Add `downloadedAt` as an additive optional key on the work record. Use the same date format
     as every other backup date (`.000Z`; see `BackupValidator.formatInstant`). Encode it only when
     non-null; the manifest stays v8.
   - Merge it as iOS's restore does (`KudosBackup.swift`, the `archived.downloadedAt` block): a
     missing or null incoming value never clears a local one, and otherwise incoming wins when the
     archive's record wins on recency or the local value is null.
   - Add round-trip tests with and without the key.

Don't touch `settings/`, `reader/`, `search/` or `comments/` (other agents are in them), or
`app/MainScaffold.kt`. Write `docs/android-port/briefs/T353-android-result.md`: files changed,
migration number, and anything you weren't sure of.
