# Decisions log (Claude, under the owner's grant of 2026-10-02)

Newest first. Each entry: decision · why · evidence · how to reverse · backup (if lossy).

- **2026-10-03 (Grok, 2x-b) · A restore adopts the archive clock for records it creates** 
  **What was decided.** A backup restore that inserts a work, a collection, or the Saved for Later queue keeps the archived timestamps. A new work takes the archive's `lastModifiedAt`. A new collection takes the archive's `lastModifiedAt`. A Saved for Later queue that did not exist before this restore takes the archive's `dateUpdated` and `lastMembershipChangedAt` (or `dateUpdated` when the membership clock is absent). Records that already lived in the library still keep the newer of the local and archived clocks. After that, membership restore still raises a queue's `lastMembershipChangedAt` to the newest membership clock. `permanentDeletionScheduledAt` is still not copied out of the archive.

**Why.** Model init and `ensureSavedForLaterQueue` stamp `Date()`. `max` against that placeholder made the restored copy look newer than the archive, so it would win every later sync on recency. Keeping the archived clock means a restore is not an edit.

**iOS evidence.** `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`: new records always adopt archive values. `KudosBackup.apply` already forces incoming fields to win on a brand-new row because the placeholder clock would otherwise block adoption. `WorkCollection.markMembershipChanged` is deliberately not stamped by a restore, for the same reason. `ReadingQueue.init` sets `lastMembershipChangedAt` from `dateUpdated`, but `ensureSavedForLaterQueue` inserts the system queue at `Date()` before the archived queue is applied, which is the path that was leaking "now".

**How to reverse.** Restore `max` against the placeholder for new works, new collections, and a Saved for Later queue created by this restore. Android already stored archive clocks for new works and collections; this decision changes the iOS restore path so both sides agree.

- **2026-10-02 · T-353 stores `downloadedAt` as a work field, not inside the EPUB or by editing Date Added.**
  Why: writing into the EPUB alters the preserved copy and `epubDigest`, and an AO3 refresh replaces the
  file. Editing Date Added would have needed a new sync rule, because both apps merge Date Added as the
  earlier of two copies. Evidence: the owner's own AO3 EPUB carries only `calibre:timestamp`
  (generation) and `dc:date` (last update). Reverse: drop the field; nothing else depends on it.
- **2026-10-02 · Library shelves follow iOS's rules, not iOS simulator counts.** The simulator's demo
  store was stale, so Finished counts 2 on a fresh seed. Evidence: `LibrarySectionKind.swift:127-129`.
  Reverse: n/a (iOS parity).
- **2026-10-02 · Android backup dates use three fractional digits** (`2023-11-14T22:13:20.000Z`), the
  iOS format, so archives round-trip byte-for-byte. Reverse: `BackupValidator.formatInstant`.
- **2026-10-03 · T-354 landed on iOS alone, before the full cross-platform suite was green.** Why: it is
  a data-loss fix (every EPUB in an Android backup was dropped on iOS restore), it's small and
  additive, and iOS's existing backup suites show only the two known pre-existing failures. Reverse:
  revert b02bf8ec.
- **2026-10-03 · The Android demo must never reach AO3 (brief 1e).** Agents ran Browse against live AO3.
  Until the demo network block lands, agents may not open Browse or Search on the emulator.
- **2026-10-03 · Tab bar visibility follows iOS's code, not brief 1d's list.** iOS hides the bar on
  every `subjectScreenWash` / `SubjectScreenChrome` / `SettingsPageForm` screen; only the selectable
  lists opt back in (`.toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)`). Checked on the
  simulator: Insights and the collections grid hide it, Recently Deleted and the queue page keep it.
  Android now hides it on Work detail, settings pages, Collections, Queue details, Insights, browse
  results and the account lists too. Reverse: `Routes.tabBarHiddenBases`.
- **2026-10-03 · The queue page's filled "+" picks its glyph colour against its own fill.** iOS's code
  says the same (`.prominentLabel()` → `label(on: screenTint)`), but the simulator draws a white glyph
  on Neon reread's light purple, probably because the toolbar sits outside the wash's `screenTint`
  environment and the label is computed against the app's red. Android follows the code's intent
  (black on a light fill). iOS follow-up queued in the Living Prompt §5. Reverse: `ToolbarAddButton`.
- **2026-10-03 · Android's Library sorts are exactly iOS's.** The sorts are Default, Date Added,
  Date Downloaded, Title, Author and Word Count. Android's "Last read", "Kudos" and "Manual" are
  gone; iOS says it doesn't offer AO3 counts because they aren't kept, and it has no last-read or
  manual sort. Default keeps each section's own order (Reading Now and History: most recently read
  first); any other sort re-sorts the section, and lights the filter button, as iOS's
  `hasActiveFilters` does. The sort wasn't persisted, so no stored value needed mapping.
  Reverse: `LibrarySort.kt`.
- **2026-10-03 · Repaired the lane branch after iCloud broke a ref update (no work lost).** The 08:56
  commit (3v, `2595f7c8`) wrote `refs/heads/android/redesign-parity.lock` and a `HEAD.lock`, but the
  rename into place failed, most likely because the repo's `.git` lives in iCloud `~/Documents`.
  Git then read a stale `packed-refs` value (`ff2b6cb6`), so the branch looked rewound and the
  index looked like the whole night was staged. Repair:
  - confirmed no git process held the locks (two unrelated 2-day-old `git diff HEAD` processes
    were running);
  - backed up the lock and `packed-refs` to the scratchpad;
  - removed the two stale locks;
  - `git update-ref`'d the branch back to `2595f7c8`, guarded on `ff2b6cb6`.

  The reflog had recorded every commit, so nothing was rewritten. Prevention: after every commit,
  check the branch resolves to the new commit and that no `.lock` is left behind. Keep a
  `git bundle` of the lane's commits outside iCloud in `~/kudos-backups/` (§9).
  Reverse: n/a (repair).
- **2026-10-03 · Owner override: Last Read and Kudos sorts are back on Android and added to iOS.**
  The owner: "restore last read and kudos sorting to android, and port it to iOS. they seem like
  useful features". This reverses the earlier entry that removed them; Manual stays removed. Both
  apps now offer: Default, Date Added, Date Downloaded, Last Read, Title, Author, Word Count, Kudos.
  - Last Read: most recently read first, never-read works last.
  - Kudos: highest first; iOS keeps `SavedWork.kudos`, so its old comment saying kudos counts
    "aren't kept" was out of date.
- **2026-10-03 · Freed about 6 GB of regenerable build caches to slow iCloud eviction.** With the disk at
  97% (14 GB free), macOS offloaded the repo's iCloud files faster: evicted loose objects went from
  970 to 2,428 in an hour, and active source files were evicted too. Deleted only caches that
  nothing was using and that rebuild on demand: Xcode DerivedData `kudos-probe`, `kudos-t283` and
  `kudos-t284`, and the idle Grok worktree's `android/app/build`. Kept `kudos-polish`,
  `kudos-polish-mac`, `kudos-device` (iPhone builds) and the Gradle caches. Free space is now
  23 GB. Not lossy: everything deleted is build output. Reverse: rebuild.
- **2026-10-03 · Account's theme-palette button is gone (Android-only).** iOS changes theme only in
  Settings > Appearance. The quick-cycle button was an Android-only testing aid in the shell. The
  gear is now an accent-tinted glass circle, as on iOS. Reverse: `MainScaffold.kt` (Account
  chrome).
- **2026-10-03 · Shut down the five idle iOS simulators.** The machine was at load 550 with swap
  at 32.6 of 33.8 GB and 80 MB of RAM free. All five simulators (Kudos Debug and Lanes C, D, E
  and F, booted 5–8 days earlier, none running a build) were killing and respawning their daemons,
  and adb hung. `simctl shutdown` keeps every simulator's data, and load fell to about 6.
  Reverse: `xcrun simctl boot <udid>`.
- **2026-10-03 · Prepared for the owner's Mac wipe.** The owner: "prepare this mac to be wiped.
  move everything related to this project to iCloud Drive … create a resume prompt … push to
  github also, so we don't loose progress".
  - Committed the outstanding work:
    - the Inbox route on the lane (`a3f099a2`);
    - the three agents' unreviewed work, as WIP commits on their own branches;
    - the iOS polish loop's uncommitted docs on integrate (`1aa3cd9a`).
  - Pushed the smallest set of branch tips that contains every local commit: 34 tips, which
    with origin's existing branches leave 0 commits uncovered, checked with `git rev-list`.
    Agent branches already contained in another pushed branch weren't pushed by name. Before
    pushing, scanned every added line for signing identities, non-placeholder team IDs and API
    keys.
  - **Did not push the separate security-fixes repo.** Its local-only history must stay private,
    and this GitHub repo is public. It went to iCloud Drive as a private git bundle instead, with
    its worktrees' uncommitted files.
  - The handoff folder is iCloud Drive › `Kudos Handoff 2026-10-03`. It holds the resume prompt
    and the gitignored `*prompt*.md` files, the Living Prompt among them.
  Reverse: n/a (nothing deleted).
- **2026-10-03 · Work moved off iCloud, by copying.** The owner: "do the part of the handoff to move
  stuff out of icloud that needs to be moved. copy, don't move". With every branch on GitHub, the
  copy is a clone: `~/AO3_App_OpenSource`, with worktrees `~/kudos-android-lane` (this lane),
  `~/kudos-ios-integrate`, `~/kudos-ios-polish` and `~/kudos-agent-{codex,gemini,gemini2,grok}`.
  - The old worktree folders (`~/kudos-android-redesign`, `~/kudos-android-agent-*`) belong to the
    iCloud repo and were left exactly where they are, so the new ones have new names.
  - Local-only files were copied in: `local.properties`, the sherpa-onnx AAR, the gitignored
    prompts, `.claude-overnight/`, FluidAudio and MuPDF.
  - The iCloud workarounds (post-commit ref check, rsync snapshot) are dropped from the loop.
  - The old iCloud copy is a frozen fallback. The two copies share nothing but GitHub.
  Reverse: keep working in the old folders; delete the new ones.
