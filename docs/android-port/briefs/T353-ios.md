# Brief T-353 (iOS): record when a work was downloaded, and let the reader set it

Owner feature (2026-10-02). Read `docs/android-port/LIVING-PROMPT.md` §5b ("T-353") in full; it is the
spec, including the owner's words and the design decisions. This brief is the **iOS** half. Android
follows with identical rules later.

Work in the iOS lane: `/Users/cidy02/Documents/AO3_App_OpenSource/.claude/worktrees/handoff-documentation-2151af/.claude/worktrees/polish`
(`claude/polish-loop`). **Do not commit**, push, switch branches, stash or reset. Leave changes uncommitted;
Claude builds, runs the gate (iOS and macOS builds, `Scripts/lint.sh` with no new warnings, tests),
checks the simulator, and commits. Your sandbox may not run Xcode; if not, write carefully and say so.
Read `AGENTS.md`, `docs/DATA_AND_PERSISTENCE_INVARIANTS.md` and `docs/AO3_NETWORKING_POLICY.md` first.

## Build
1. **Model:** `SavedWork.downloadedAt: Date?` (SwiftData, additive, nil for existing works). Never set
   automatically after capture.
2. **Capture:**
   - an AO3 download (`WorkDownload` / `DownloadQueue`, whichever finishes a download): `downloadedAt = now`;
   - an import (`Services/WorkImporter.swift`, `Services/UserDocumentImport.swift`,
     `Settings/SettingsImportPage.swift`): the rule below.
3. **The rule** (one pure, tested function, for example `DownloadDateDetector.detect(fileCreated:fileModified:epubGeneratedAt:now:)`):
   - Take the earliest of the file's creation and modification dates. Read them from the picked URL
     before any copy; with `fileImporter`, read the resource values on the security-scoped URL.
   - Discard a candidate within 5 minutes of `now` (a fresh copy) or earlier than the EPUB's
     `calibre:timestamp` (impossible).
   - Fall back to `calibre:timestamp` (parse it from the OPF `<meta name="calibre:timestamp">`), then
     `now`.
   - Return the date **and its source** (`.file`, `.ao3Generated`, `.importTime`).
4. **Import UI:** where imports are confirmed (SettingsImportPage and the share/open-in path), show the
   detected date and its source ("Downloaded Oct 2, 2026 · from the file" / "AO3 generated this copy
   Mar 3, 2026" / "Couldn't tell. Using today") with a date picker to change it. For a batch: a choice
   between "Use each file's download date" (default) and "Use today". Use friendly copy, matching T-342's
   tone.
5. **Work detail:** an editable "Downloaded" date row in the My copy / facts area (a date picker sheet).
   Editing it stamps `lastModifiedAt` like other edits.
6. **Sort:** add a Library sort "Date downloaded" (`downloadedAt ?? dateAdded`, newest first) wherever
   Library sorts are offered (`LibraryFilters` / sort menus), beside "Date added".
7. **Backup and sync:** `downloadedAt` as an additive optional key on `KudosBackupWork` (manifest stays v8),
   encoded only when non-nil, merged like other per-work fields (incoming wins on recency; a nil incoming
   never clears a local value). Add it to `KudosBackupExport` and the restore apply.
8. **Tests:** the rule (all branches, including a copy within 5 minutes, a pre-generation date, and no
   calibre timestamp), the backup round trip with and without the key, and the sort order.

Write `docs/android-port/briefs/T353-ios-result.md` (in `~/kudos-android-agent-codex`): the files changed,
the rule's location, and anything you were unsure of.
