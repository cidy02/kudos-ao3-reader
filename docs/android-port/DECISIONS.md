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
- **2026-10-03 · T-356 is not a colour bug: iOS's toolbar forces a white glyph.** The queue page's
  filled "+" is a system toolbar item with `.glassProminent`. Setting the screen colour on the
  button (`.screenTint`) and setting the foreground on the label inside it both left the glyph
  white on Neon reread's light purple (checked on the simulator both times), so the change was
  reverted. A dark glyph on iOS would need a custom-drawn button instead of a toolbar item.
  Android still draws black on a light fill, so the two differ. **Owner decision needed:** build
  the custom iOS button, or make Android's glyph white to match iOS as it renders.
- **2026-10-03 · Installed integrate `1aa3cd9a` on the owner's iPhone** (owner: "install latest
  version on paired iphone"). Signed by passing the owner-approved public team ID on the
  `xcodebuild` command line, as earlier device builds were; no tracked file changed.
- **2026-10-03 · 3m-detail (Gemini Pro) was incomplete.** It has the model, parser, repository and
  route, but `AO3CollectionDetailScreen` was never written, so it doesn't compile. The work is
  staged in `~/kudos-agent-gemini2` (the `Routes.kt` conflict with the Inbox route resolved) with
  brief 3m-detail-2 for the missing screen. Gemini ran out of quota before starting it.
- **2026-10-03 · Owner: Home and Library take their accent from the hero too, not only the wash.**
  "Home/Library are not deriving accent color from the wash". The first version coloured only the
  gradient and kept the page's controls on the app accent; that was Claude's choice and is reversed.
  - iOS: `HeroWash` now sets the screen tint (polish `ec14fd04`, integrate `58e24389`).
  - Android: `MainScaffold` gives the page tokens, subject palette and Material `primary` carrying
    the hero's tint while the wash shows.
  - On both, the toolbar or shell chrome and the tab bar sit outside and keep the app accent.
  Reverse: `HeroWash.swift`; the provider around `AppNavHost` in `MainScaffold.kt`.

- **2026-10-03 · The AO3 collection page shows every work, as iOS does; "Show mature" there only
  flips the session gate.** Codex's 3m-detail-3 left out Works and Bookmarks rows rated Mature or
  Explicit until the reader chose Show mature. iOS doesn't: `AO3CollectionDetailView.workRows`
  draws every row with `EnrichingAO3WorkRow`, and `PrivacyGate` only takes a `SavedWork`, so Hide
  mature content covers the reader's own library and never AO3's listings. As written, a collection
  of Mature works would have read "This collection has no works yet." under a count of 234. Claude
  removed the filter before landing. The menu stays (shown only while Hide mature content is on)
  and toggles the shared `PrivacyGate`.
  - Also removed: refetching the header on pull to refresh. iOS reloads the selected segment only
    and keeps the header it has, which is one AO3 request fewer per pull.
  - Not ported: leaving the page when the collection is deleted. Android has no native delete
    (every Manage row opens the web fallback), so nothing can announce it.
  Reverse: `workRows` and `load` in `account/AO3CollectionDetailScreen.kt`.
- **2026-10-03 · Cleared the three stale agent worktrees** (`~/kudos-agent-codex`, `-gemini2`,
  `-grok`), as the handoff directed, and moved them to the lane head. They held briefs 3o,
  3m-detail and 3q, already landed as `35647609`, `9a667f13` and `64e0d4cf`, plus Grok's unported
  `TASKS.md` row. Backup first: `~/kudos-tools/out/discard-<name>.patch` (tracked changes against
  each old HEAD) and `discard-<name>-untracked.tgz`.
  Reverse: check out the old commit in the worktree and `git apply` its patch.
- **2026-10-03 · Fixes from the four-theme audit; what follows iOS and what was left for the
  owner.** Twenty-one screens were checked on the emulator in Light, Sepia and OLED, and seven at
  the largest font. Bugs fixed (see the commits): dark status-bar icons on a Dark or OLED page,
  untinted icons drawn black on dark pages, two Account screens whose header sat under the status
  bar, and library works shown unblurred on the AO3 account lists. Decisions inside those fixes:
  - **The Account hub's tiles and rows are glass panels**, as iOS draws them and as `subjectPanel`
    draws every other screen. They were Material cards, stark white on Sepia. Sepia's Material
    container colours, never set, are now its own cream and tan.
  - **The tab bar's labels don't grow with the font size**, as iOS's system tab bar doesn't. At
    Android's largest size they were cut off by the bar.
  - **The account lists treat a Mature library work as iOS's `visibleEntries` does:** blurred in
    Blur mode until revealed; in Hide mode not paired, so it shows as a plain AO3 row. The menu's
    dead "Hide Mature Content" became iOS's Show mature / Hide mature.
  - **Not changed, for the owner** (`OWNER-DECISIONS-ANDROID.md`): the default accent is hard to
    read on dark chrome on both platforms.
  Reverse: each is one commit on `android/redesign-parity`, dated 2026-10-03 after 23:30.
- **2026-10-03 · The Account header's menu is iOS's three items, and Log Out asks first.** Android's
  "…" menu also held Settings, Privacy & Local Data, Backup, Local Reading History, Favorites, Local
  Collections and About Kudos, and it showed on the signed-out card too. iOS's menu
  (`AccountComponents.accountMenu`) is Verify Session, Open on AO3 and Log Out, and its signed-out
  card has no menu. Android now matches. Nothing became unreachable that iOS offers: Settings is
  the gear; Privacy, Backup and About are inside Settings; History, Favorites and Collections are
  in the Library. Log Out shows iOS's confirmation ("Log out of AO3?") in this menu and in
  Settings > AO3 Account; before, one tap logged out.
  - Left in place but no longer reachable: `account/LocalLibraryListsScreen.kt` (routes
    `local-history` and `local-favorites`), an old Material list.
  Reverse: `AccountOverflowDropdownMenu` and its callers in `account/AccountScreen.kt`.
- **2026-10-04 · Large text follows iOS's Dynamic Type rules; Android's font scale above 1.3 counts
  as iOS's accessibility sizes.** Android read the font scale nowhere, and iOS branches on
  `dynamicTypeSize.isAccessibilitySize` (AX1 and up, about 1.65×; its largest ordinary size is
  about 1.35×). Android's steps are 0.85, 1.0, 1.15, 1.3, 1.5, 1.8 and 2.0, so 1.5 and above take
  iOS's large-text layouts: headers wrap, form rows stack, ledger rows become one column. Sizes
  iOS marks `@ScaledMetric` (cover cards, rings, status tiles) are multiplied by the font scale.
  The tab bar's labels don't scale, as iOS's don't. Brief 4a did the shared components; each
  screen still needs its own pass.
  Reverse: `isAccessibilityFontScale()` in `ui/subject/SubjectComponents.kt` is the one switch.
- **2026-10-04 · A tapped tag searches AO3 inside the app, as on iOS.** iOS's
  `AppRouter.searchAO3(field, value)` switches to Search and searches that tag in its own field
  (fandom, character, relationship, additional tag, warning). Android's Work detail opened
  `archiveofourown.org/tags/…/works` in the phone's browser instead, and its work rows only
  offered a plain additional-tag search from inside Search. Both now do what iOS does (brief 3z).
  This also removes a way for the demo to leave the app for the live site.
  Reverse: `LocalTagSearch` in `app/MainScaffold.kt`; `WorkDetailSections.kt`.
- **2026-10-04 · Android's sync folder uses iOS's EPUB names, and prunes as iOS does.** Android
  named a work's EPUB in the folder with a lowercase UUID; iOS uses capitals, and each app looked
  for, and pruned by, its own exact name. A folder shared across the two had each deleting the
  other's EPUBs. Android also pruned the EPUB of any work it held no file for, and pruned even
  when it could not read the folder's manifest; iOS does neither (`FolderSyncService`). Android now
  writes iOS's name, finds either case, renames an older lowercase file when it rewrites it,
  keeps every work and font the manifest lists, and prunes nothing when the manifest was
  unreadable. The manifest's own format is unchanged; only file names in `Works/`.
  - **Consequence to know:** an Android device still on an older build does not find the new
    names. Nothing is lost from a library (each device re-uploads what it holds), but the folder
    churns until both devices update. iOS should also compare names without regard to case
    (`5a-result.md`); not changed.
  Reverse: `runSyncLocked`, `importManifest` and `removeOrphans` in `backup/SyncRepository.kt`.
- **2026-10-04 · A restore replaces a local EPUB only when iOS would.** Android wrote an archive's
  or the sync folder's EPUB over a local one whenever the archive's record was newer, without
  looking at the bytes or at preservation. Now, as iOS (`KudosBackupService.mayReplaceEPUB`,
  `ReadingQueueService.replaceEPUB`): a preserved work that still has its file is never replaced;
  bytes that are not a readable EPUB are skipped and the local copy kept; a work whose file is
  gone is always filled in; File Merge of a work in Recently Deleted replaces its file only when
  the archive is newer. Replace Library and new records are unchanged. Kept stricter than iOS: on
  equal clocks Android keeps the local file. Details: `briefs/5a-result.md`, part 2.
  Reverse: the block above `mayReplaceEpub` in `backup/BackupMergeService.kt`.
- **2026-10-04 · A sync-down reads only the EPUBs that changed, a batch at a time.** Android read
  every EPUB in the sync folder into one map on every sync: a large library would run the app out
  of memory. Now, as iOS's `readChangedRemoteAssets`: an EPUB is read only when its size differs
  from the local file, or the sizes are equal and the manifest's digest differs; at most 32 MB is
  held at once, and the manifest is merged again with each batch. Android's manifest now carries
  the digest of the bytes it uploads, not the one an earlier manifest gave it. Same as iOS and a
  known limit: with no digest in the manifest, an equal size counts as unchanged. And as iOS's
  `viewIsCurrent`: if the manifest's date moved between this run's read and its write, nothing is
  pruned.
  Reverse: `importManifest`, `isUnchangedLocally` and `manifestStampAtRead` in
  `backup/SyncRepository.kt`.
- **2026-10-04 · A saved search a paired device deleted is removed here too.** Android adopted
  the other device's signed tombstone and refused to add the search back, but kept its own copy
  and published it again, so the deletion never settled. iOS removes the existing copy
  (`applyTombstonesToExisting`, `TombstoneSweepsExistingRecordsTests`); Android now does the same:
  only for a tombstone from a trusted device, not for a search newer than the tombstone, and
  never in Replace Library. Nothing changes for a device that has paired with no one.
  Reverse: the sweep in `mergeSavedSearches` (`backup/BackupMergeService.kt`) and the deletion
  beside the saved-search upsert in `BackupRepository.applyMergeResult`.
- **2026-10-04 · A later deletion of the same record replaces the tombstone row it shares an id
  with.** Android never overwrote a tombstone row it already held, to stop a trusted key from
  swapping a local deletion for another record's. That also dropped the same record's later
  deletion, and kept the earlier date: a snapshot dated between the two would bring the record
  back (iOS `NewestTombstoneWinsTests`). The row is now replaced only when the incoming tombstone
  is trusted, is for the same record, and is later. It can only widen what the row suppresses.
  Reverse: `sameRecordDeletedLater` in `backup/BackupMergeService.kt`.
- **2026-10-04 · The Mac's reading percent merges with the reading progress, as on iOS.**
  Android took `legacyReaderProgress` from whichever side had the newer metadata, and never
  cleared it when a snapshot with no such key had read further. iOS decides it inside the progress
  merge (`SyncMerge.applyProgress`): taken only when the incoming progress wins; a key that is
  absent is not a clear, unless the incoming locator moved by at least the reader's own delta.
  Android now does the same. Reverse: `applyProgressLww` and `keylessLocatorMoved` in
  `backup/BackupMergeService.kt`.
- **2026-10-04 · A font over the limits is skipped; it no longer fails the sync.** Android threw
  when a font in the sync folder was over 4 MB, or when the folder's fonts added up to more than
  32 MB, and the sync failed every time after. iOS skips such a font, does not count fonts the
  device already holds, and prunes nothing while a font is still outstanding
  (`readChangedRemoteAssets`). Android now does the same. A file that is not a font at all still
  fails the sync, as on iOS. Reverse: the font loop in `importManifest`
  (`backup/SyncRepository.kt`).
- **2026-10-04 · A converted import's original file travels with Android's backups and sync
  folder.** Android dropped iOS's `Originals/` on restore and exported none, so a library that
  passed through Android lost the file a work was converted from (often the last copy). Android
  now reads, restores, exports and syncs them by iOS's rules (`briefs/5b-result.md`). The
  conversion record is carried through byte for byte, not ported, and is taken only with the
  original it describes. An original over 128 MB is left out rather than failing the restore.
  No format change: this is iOS's existing layout.
  Reverse: `originalFilesByName` in `backup/KudosBackup.kt` and its users.
- **2026-10-04 · "Check Availability…" opens a screen that states the cost first; it no longer
  starts at a tap.** Android's Preservation page ran the check the moment the row was tapped. A
  check is one AO3 request for each work, and iOS deliberately makes it a screen that says so
  before any request is sent (`AvailabilitySweepView`, `SettingsPreservationPage`). Android now
  has that screen: the cost, "Check Now", progress, the result, and the list of works no longer
  on AO3 (which was a separate row). Reverse: `settings/AvailabilitySweepScreen.kt` and
  `SettingsPreservationPage`.
- **2026-10-04 · A sync always writes its manifest; without a full view of the folder it only
  never deletes.** Codex's audit (brief 5c) proposed that Android stop and write nothing when the
  folder's manifest is missing or damaged, when a listed file is not in the folder, or when a
  font is over a limit. A folder in any of those states could then never sync again, and an
  interrupted first sync is enough to leave one (files uploaded, no manifest yet). Decided
  instead: the run writes its manifest, and prunes only when it read the live manifest, took
  every file that is in the folder, and left no conflict copy unfolded. A manifest recovered
  from `.bak` never allows a prune. A file the manifest lists that is not in the folder is
  nothing to fetch, as on iOS. This replaces the rule of earlier today that a font over a limit
  only stops the prune: that still holds, and the font now also stays in the manifest Android
  writes. Reverse: `folderViewIsCurrent` and `pendingFonts` in `runSyncLocked`
  (`backup/SyncRepository.kt`).
- **2026-10-04 · A manifest Android cannot read is never written over, unless it is plainly
  damaged.** Three cases. Cut short or empty (not JSON at all): damage from a write that died;
  the run repairs it and prunes nothing. Whole JSON that does not decode (a version number this
  build does not know, or more than its limits allow): another app version's index; the sync
  stops with a message and the file is left as it is. There and not readable at all (the
  provider is offline, the file is over 8 MB): the sync stops. Reverse: `readLiveManifest` and
  `isWholeJsonObject` in `backup/SyncRepository.kt`.
- **2026-10-04 · A manifest another device wrote during the sync stops the run.** Earlier today
  the run went on and only skipped the prune. It then wrote a manifest that did not list what
  the other device had just added, and the folder's only index lost those records. The run now
  stops ("Sync folder changed during sync. Try syncing again.") and the next one reads the new
  manifest first. The comparison is of the manifest's bytes, not its date: a provider's dates can
  be missing or coarse. Supersedes `de066460`. Reverse: the `contentEquals` check before the
  commit point in `runSyncLocked`.
- **2026-10-04 · The manifest is written in place, and the one it replaces is copied to `.bak`
  first.** Android renamed the live manifest to `.bak` and then renamed a temp into place, so
  for a moment the folder held files and no manifest. A released iOS build reads that as a first
  write, publishes its own library, and prunes every file that library does not list. A manifest
  cut short instead cannot be read by either app, and neither prunes by what it could not read.
  A folder with no manifest yet still gets a temp renamed into place. Seen on the emulator with
  Android's own storage provider: names exact, no "(1)" copies, `.bak` holds the manifest that
  was replaced. Reverse: `writeManifest` in `backup/SyncRepository.kt`.
- **2026-10-04 · An old lowercase EPUB is still replaced by one under iOS's name.** The audit
  proposed keeping the lowercase name and having iOS read either case. iOS now does read either
  case (T-357), but a released iOS build reads only the name in capitals and prunes the other,
  so Android goes on replacing the file. It is deleted and written again (a rename that changes
  only case is refused on a phone's storage). Originals and conversion records keep whatever
  name they have: iOS finds them by listing the folder, in either case. Reverse: `recase` in
  `writeIfChanged`.
- **2026-10-04 · An incoming EPUB with an equal clock replaces the local one, as on iOS.** This
  morning's rule (`932d1e93`) asked for a strictly newer clock. With batches, the first merge
  moved every clock up to the folder's, and each later batch's EPUB was then refused. iOS's rule
  is newer or equal. Android bumps the clock on every local EPUB write, so a local re-download
  is still not undone. Reverse: `incomingIsNewer` in `BackupMergeService.kt`.
- **2026-10-04 · A later tombstone replaces a held one only when AO3 id and URL also match.**
  Narrower than iOS, which replaces on type and record id alone (`NewestTombstoneWinsTests`).
  Codex's reason: the row id is not signed, so a trusted key could swap a held deletion for one
  that suppresses less. Kept as the safer side; a legitimate change of URL spelling is then not
  taken. **Differs from iOS; listed for the owner.** Reverse: `sameRecordDeletedLater`.
- **2026-10-04 · Font names are compared in composed form; letter case is not folded when a
  font is looked up.** A provider can list `Café.ttf` in decomposed form, and an exact compare
  then missed it. Case is not folded for the lookup because two fonts can differ only by it, and
  folding wrote one font's bytes over the other's file. The prune does fold case: it keeps more.
  Reverse: `fontNamed` in `backup/SyncRepository.kt`.
- **2026-10-04 · Top-level manifest keys Android does not know are written back as found.** iOS's
  pronunciation corrections, and whatever a later version adds. Android has no table for them
  and dropped them from the folder's index. No format change (they are iOS's keys) and no Room
  change. Backups exported from Android still hold none. Reverse: `knownManifestKeys` and
  `unknown` in `runSyncLocked`.
- **2026-10-04 · A file that cannot be written fails the import.** A restore ignored failed
  EPUB, font and original writes and reported success; the sync then uploaded the old bytes as
  the newest copy. Reverse: `orThrow` in `backup/BackupRepository.kt`.
- **2026-10-04 · A deleted record keeps the countdown it already has** (iOS
  `archivedDeletionState`). Reverse: `keptDeletionSchedule` in `backup/BackupMappers.kt`.
- **2026-10-04 · The incoming-EPUB check reads the package the container names** (iOS
  `inspectPackage`), through the ZIP's central directory. Reverse: `isReadablePackage` in
  `works/EpubImportMetadata.kt`.
- **2026-10-04 · Android's Sync Folder page says devices must be paired, and shows why a sync
  failed.** iOS's text ("devices on the same Apple account are trusted automatically") is not
  true on Android. **Android's wording now differs from iOS's on purpose.** Reverse: the two
  footnotes and `lastSyncError` in `SettingsFolderSyncPage` (`settings/SettingsPages2.kt`).
- **2026-10-04 · iOS folder sync changed (T-357, on `claude/polish-loop` and
  `integrate/cloud-redesign`, not pushed).** An upload reads first (`syncUp` is `syncNow`);
  files and no manifest is not a first write; a manifest with no readable date allows no prune;
  EPUBs are read in either letter case and the prune folds case; a manifest cut short is
  repaired, from Android's `manifest.json.bak` when there is one. Codex drafted the lowercase
  read and the read-before-upload; its refusal to write a folder with no manifest was reworked
  for the same reason as on Android. **This changes the reference app's behaviour and needs the
  owner's eye.** Reverse: revert `91f3930f` (polish) and `ef120853` (integrate).
- **2026-10-04 · Room 14: a work remembers it is owed an EPUB** (`remoteEpubPending`, iOS
  `remoteEPUBPending`). Local only, never in a manifest. Migration `MIGRATION_13_14`, tested from
  the exported schema 13 and on the emulator's real database. A work promised an EPUB that has
  not arrived is exported as having one, so an iPhone goes on looking for it.
  Reverse: needs a migration back; leave the column and stop reading it.
- **2026-10-04 · The sync fetches an EPUB only for a work whose manifest entry says it has
  one** (iOS `readChangedRemoteAssets`). Android fetched every listed work's file. Reverse: the
  `hasEPUB` guard in `importManifest` (`backup/SyncRepository.kt`).
- **2026-10-04 · A manifest this device wrote itself is not merged again.** iOS skips it by its
  date; Android by a digest of its bytes (`syncLastManifestDigest` in DataStore), stored only
  when nothing is outstanding and cleared when the folder is changed. Without it a removed
  download came back at the next sync, and every sync merged the whole library for nothing.
  Reverse: `ownManifest` in `runSyncLocked`.
- **2026-10-04 · The kept flag follows the newer snapshot, as on iOS; the queued flag stays
  ORed.** iOS sets the queued flag from queue membership after every restore. Not ported:
  older Android data holds queued works with the flag and no membership, and they would drop
  out of both the library and the queues. Reverse: `isSaved` in `mergeWork`.
- **2026-10-04 · Keeping a work through the importer advances its clock.** Reverse:
  `stampedIfFlagsChanged` in `works/WorkImporter.kt`.
- **2026-10-04 · Replace Library keeps omitted collections and queues for 90 days, with their
  memberships, and marks omitted highlights pending deletion** (iOS). It deleted them outright.
  Reverse: `removeRecordsAbsentFromReplaceSnapshot` in `backup/BackupRepository.kt`.
- **2026-10-04 · The last sync error is stored and shown** (iOS `lastError`): on the Sync
  Folder page, and as "Error" on the Settings row, which now reads Off, Error, On or Paused as
  iOS's does. Not in backups. Reverse: `syncLastError` in `SettingsRepository`.
- **2026-10-04 · A queue membership this device holds is not removed when a paired device has
  deleted it. Held for the owner.** Codex's brief 5e patch removed it, to let the queued flag
  follow membership. iOS does not: a membership deletion only stops the membership being added
  back. Closing that gap is a change to how deletions travel on both apps (saved links and
  highlights are the same), so it is owner question 7, and the queued-flag part of 5e waits with
  it. The patch is kept as `bcb5ce5a` on `android/agent-codex-5e`.
- **2026-10-04 · A late conversion record is taken only beside the same original.** iOS takes
  an absent record on its own; that can attach one device's record to another device's
  different file. Android compares the folder's original with the local one (size, then
  SHA-256) first. **Stricter than iOS on purpose.** Reverse: `restoreOriginals` in
  `backup/BackupRepository.kt`.
- **2026-10-04 · Only the last batch of a sync marks queued works preserved.** Reverse:
  `normalizeQueuePreservation` in `BackupMergeService.merge`.
- **2026-10-04 · The Backup page is iOS's, with three guards added and none removed** (brief
  6b): Replace has a review step of its own, the acknowledgement is asked even when nothing
  would be removed, and the copy saved before a Replace can no longer overwrite an earlier one.
  Not taken from iOS: the "second attempt" override that lets a Replace go ahead without a
  saved copy. Android keeps refusing. Reverse: `backup/BackupScreen.kt`.
- **2026-10-04 · The Sync Folder page uses the Backup page's pairing section.** It had a
  hand-drawn copy that opened an old Material dialog. Reverse: `SettingsFolderSyncPage`.
- **2026-10-04 · Kept on Android's Backup page though iOS's has neither:** the two technical
  notes under the footer, and the pairing section (iOS shows pairing only on its Sync Folder
  page). Nothing was removed without the owner; it is owner question 9.
- **2026-10-04 · The Subscriptions page looks up every work on the loaded page, as iOS does.**
  Android looked up only the rows that scrolled into view, and its own comment called an eager
  page-wide lookup wrong. iOS walks the loaded page (`enrichLoadedSubscriptionPage`) because the
  new-chapter badges, Mark All as Seen and the Refine filter need every row's chapter count, and
  its networking policy names the walk as an allowed exception: anonymous, one work at a time,
  through the paced client, bounded by the page, stopped when the screen is left. Up to 20
  requests for a page the reader opened, where there used to be as many as rows seen.
  Reverse: the `LaunchedEffect` walk in `account/AccountWorksListScreen.kt`.
- **2026-10-04 · A sort or filter on AO3 Collections reads the account's other collections
  pages, as iOS does.** One page at a time through the paced client, never more than 25,
  started only by the reader applying a filter or pulling to refresh, stopped when the screen is
  left. Named in iOS's networking policy as an allowed exception. Reverse: `loadWholeIndex` in
  `AO3CollectionsViewModel` (`account/AccountViewModel.kt`).
- **2026-10-04 · Not ported to the account lists, for lack of anything behind them:** iOS's
  display mode picker (Android has no account-wide display setting) and Clear History (Android
  has no call for AO3's clear-history form). Both are listed in `briefs/3w-result.md`.
- **2026-10-04 · The search filter sheet is iOS's panel, and sends what iOS sends.** Rows,
  pickers and sliders in iOS's order; ten sorts with an order; Chapters, After and Before,
  Title and Creator, and ranges for hits, kudos, comments and bookmarks are new on Android.
  The AO3 search link gains the parameters iOS already sends for them (`title`, `creators`,
  `single_chapter`, `hits`, `kudos_count`, `comments_count`, `bookmarks_count`, `date_from`,
  `date_to`, `sort_direction`). No new kind of AO3 request: tag lookups use the lookup Android
  already had, after a 300 ms pause and two letters, as on iOS. Reverse:
  `search/SearchFilterSheet.kt`, `network/ao3/search/AO3SearchUrlBuilder.kt`.
- **2026-10-04 · A saved search made on Android carries all 37 of iOS's filter keys.** Android
  refused to save a search that used a choice its saved form could not hold; the owner's
  standing rule is that the two apps behave the same, so the form was widened and the refusal
  removed. No key, name or version of the backup changed; the filters object inside a saved
  search holds more of the keys iOS defines. A value Android cannot show (a sort from a later
  version, say) is kept and written back unless that one control is changed. A date is a
  calendar day here and a moment on iOS: Android writes the start of the picked day in iOS's
  text form and keeps iOS's exact moment when the date is not touched. iOS fails its whole
  manifest on a value it does not know, so the check is against a saved search iOS wrote:
  `CrossPlatformRestoreTest.androidWritesASavedSearchsFiltersTheWayIosDoes`. Reverse:
  `search/SearchFiltersCodec.kt`.
- **2026-10-04 · The Library filter panel's Done is the accent-filled circle.** iOS draws its
  confirm that way on both filter panels; Android's search sheet had it and the Library panel
  did not. The tag pickers' Done stays plain, as on iOS. Reverse: `library/LibraryFilterPanel.kt`.
- **2026-10-04 · The owner asked for the Material design documents to be found and read.** They
  are `docs/contracts/KUDOS_ANDROID_INTERFACE_GUIDELINES.md` and
  `ANDROID_MATERIAL_HIG_TRANSLATION.md` (with `CROSS_PLATFORM_UI_BRIDGE.md`), all from
  2026-06-27. They say Android keeps iOS's behaviour and order of information but draws it with
  Material 3's own parts. The lane's mission, written in October, says match the iOS redesign
  screen for screen, and the lane has been replacing Material parts with the redesign's. Nothing
  was changed on the strength of the reading; the lane goes on under its mission until the
  owner says otherwise. It is owner question 11.
- **2026-10-04 · Owner: Android is the same product as iOS, not a copy of it; its tab bar and
  chrome buttons are Android's own.** In the owner's words: "while i want the Kudos app to feel
  like one cohesive product across platforms, i also don't want android to look like an attempt
  to clone iOS. let's give Android native feeling tab bar and chrome buttons". This answers
  question 11 with a mix. The redesign's layout, content, order of information and behaviour
  stay in step with iOS; navigation and chrome controls are Material 3's. The owner named the
  tab bar and the chrome buttons only, so panels, headers, sheets and the reader are unchanged.
- **2026-10-05 · What "native" was taken to mean** (landed; each choice is Claude's and can be
  reversed on its own):
  - *Tab bar:* Material 3's short navigation bar across the bottom edge, in place of the
    floating glass capsule and Search circle. Five destinations, Search the fifth. It stays put
    when a list scrolls (iOS's shrinks). **Search now keeps the bar**: it hid it before, which
    made the Search item a button dressed as a tab. A page opened from a tab keeps that tab
    marked. Labels stop growing at 1.3 times the text size, since five do not fit beyond that.
  - *Chrome buttons:* Material's plain icon button (48dp to touch, a ripple, no circle) in
    place of the glass circle. An accented button (the "+", Account's gear, a filter that is
    on) is Material's tonal icon button: an accent-tinted container under a glyph that reads on
    it. The queue page's prominent "+" is Material's filled icon button. The overflow is
    Android's vertical dots. The filter count is Material's badge.
  - *A list under the buttons:* plain icons cannot be read over text, so while a list runs
    under them the top of the screen is painted again in the page's own wash, fading out at its
    lower edge. It is Material's top bar that turns solid on scroll, in the page's colour.
  - *The accent on Dark:* the selected tab and accented buttons draw a glyph made to sit on the
    accent (`accentOnFill`) over an accent-tinted container, not the bare accent. That settles
    the tab bar and toolbar part of owner question 2 on Android; action rows in Settings and a
    sheet's selected tab are as they were.
  - *Not done:* the reader's controls are still glass (owner question 12). The functions keep
    their names (`ToolbarCircleButton`) until the owner has seen the look.
  Reverse: `ShellNavigationBar` and `TopChromeFade` in `app/MainScaffold.kt`;
  `ToolbarCircleButton`, `ToolbarAddButton`, `FilterButton` and `ShellWashes` in
  `ui/subject/SubjectComponents.kt`; the tab bar rule in `search/SearchScreen.kt`.
- **2026-10-04 · Owner: push as you go.** Asked whether to push after each landing, the owner
  said "you shoudl push as you go". Working branches only, plain pushes; never `main`, never
  forced, never the security-fixes branches.
- **2026-10-05 · Replace Library removes only what it saw when it started.** It swept whatever
  the database held when it finished, so a saved link or search made while it ran was deleted
  outright, and a work, collection, queue or note made meanwhile went to Recently Deleted. Now
  the merge names the rows it dropped and only those are touched. Reverse:
  `removeRecordsAbsentFromReplaceSnapshot` in `backup/BackupRepository.kt`.
- **2026-10-05 · A field Android does not know inside a record survives an Android sync.** A
  later iOS version can add a field to a work or a collection; an older Android build rewrote
  the folder's manifest without it, and iOS then took Android's newer copy of the record with
  the field at its default. Android now carries such keys over from the manifest it replaces.
  No format change. A backup file made on Android cannot do this: it has nothing to carry
  from. Reverse: `carryUnknownRecordKeys` in `backup/SyncRepository.kt`.
- **2026-10-05 · Restoring the same backup twice does not copy an identical font again.**
  Android only; iOS still adds a copy each time. Reverse: `mergeFonts` in
  `backup/BackupMergeService.kt`.
- **2026-10-05 · The reader's Find in Work is iOS's, and the brief was wrong about two things.**
  iOS has no "this chapter / whole work" choice (the brief asked for one): "This Chapter" is the
  first group of results. And iOS searches on one letter. Codex followed iOS. Left as gaps, in
  `briefs/3ai-result.md`: tapping Bookmark twice on one result stores two bookmarks (iOS returns
  the first); a result's context is what Android's search engine returns, not a whole sentence.
  Reverse: `reader/ReaderSearchSheet.kt`, `reader/ReaderSearch.kt`.
- **2026-10-05 · An import does not write over what the reader did while it ran.** Before
  writing, inside the same database write, it reads the library again; a row that changed since
  the import began is merged again with the backup's record (the newer wins, a reading position
  saved meanwhile never moves back), and a row deleted meanwhile stays deleted. iOS cannot meet
  this: its restore runs in one go. Android says one new thing when a backup's value was held
  back: "N item(s) you changed during the import kept your version; import again to take the
  backup's". Reverse: `refreshForApply` in `backup/BackupMergeService.kt` and
  `applyMergeResult` in `backup/BackupRepository.kt`.
- **2026-10-05 · Settings › Listening is iOS's page, as far as Android's speech engine goes.**
  Audition Voice (sample text, speed, three speed shortcuts, Play Sample), the voice pack's
  state, and Read Aloud (voice, speed, reset). Left out, because Android's engine has nothing
  behind them: the engine choice, the model and compute choices, Read author's notes,
  Pronunciations, Developer Settings and Pitch (`briefs/3ak-result.md` lists what each would
  take). Two changes of behaviour come with it: **read-aloud speed stops at 1.5x, as on iOS**
  (Android's went to 2.0x), and **the chosen voice and speed are now kept between sessions**
  (they were forgotten when the reader closed). They are kept on the device, outside backups,
  as on iOS. Reverse: `settings/SettingsListeningPage.kt`,
  `reader/settings/ReaderSpeechPreferences.kt`, and the speech keys in
  `data/preferences/SettingsRepository.kt`.
- **2026-10-05 · The page's own colour stays under the status bar on a scrolled page.** With
  the top buttons scrolled away, text ran under the clock. The wash-coloured ground that sits
  behind the buttons now shrinks to the status bar's height instead of going away. Reverse:
  the `fadeHeight` lines in `app/MainScaffold.kt`.
- **2026-10-05 · Which files an import writes is decided when it writes them.** A work marked
  to keep, a download removed, or a work deleted while an import ran still got the file the
  import had planned. Each EPUB, original and font is now checked against the work's row at the
  moment of writing, by the merge's own rule. Reverse: `applyMergeResultLocked` in
  `backup/BackupRepository.kt`.
- **2026-10-05 · Subscriptions lists series and authors, as iOS does.** The two tabs were fixed
  empty states that told a reader with subscriptions they had none. They now ask AO3 for the
  reader's own `type=series` and `type=users` pages: one request when a tab is opened, on a
  page change and on pull-to-refresh, through the paced client, never in the background. The
  networking policy allows a signed-in read of the reader's own account lists. No Unsubscribe
  on these rows yet (brief 3an). Reverse: `account/NamedSubscriptionsLoader.kt` and
  `parseNamedSubscriptions` in `network/ao3/account/AO3AccountParser.kt`.
- **2026-10-05 · Found, not yet fixed: Unsubscribe on the Subscriptions page does not
  unsubscribe.** It hides the work's row on the device, in memory, and sends AO3 nothing; the
  subscription is still there on AO3 and the row is back at the next visit. iOS posts AO3's own
  form. Brief 3an.
- **2026-10-05 · Unsubscribe on the Subscriptions page unsubscribes on AO3.** For works, series
  and authors: the reader taps Unsubscribe and confirms; Kudos fetches the subscriptions page
  for a fresh token and posts AO3's own form for that row, once, through the paced client; the
  row leaves the list only when AO3's answer confirms it, and a refusal says "Couldn't
  unsubscribe" and leaves the row. It is iOS's flow line for line, and the networking policy
  allows a write the reader starts and confirms. The row hidden only on the device is gone.
  It has not been run against AO3 (neither have iOS's write actions): a release check on a real
  phone. Reverse: `unsubscribe` in `network/ao3/writes/AO3WriteRepository.kt` and
  `account/SubscriptionUnsubscribeState.kt`.
- **2026-10-05 · A signed-in page read that finishes after the account changed is dropped.**
  It was returned to its caller, which could show one account's page under another. Reverse:
  `getAuthenticated` in `network/ao3/writes/AO3AuthenticatedClient.kt`.
- **2026-10-05 · The reader's menu holds what iOS's holds.** Contents, Bookmarks & Highlights,
  Find in Work, Comments (an AO3 work only), Themes & Settings; then Share, Give kudos (an AO3
  work only), Read aloud, Lock rotation, Add bookmark. **Mark finished left the menu**: iOS
  has it on the work's page, and so does Android. Kept though iOS has them elsewhere:
  Highlight selection and Add note to selection, because Android's text selection menu cannot
  make them yet. Left out for lack of anything behind them: Original, Rebuild from Original
  (iOS shows it only when the conversion is out of date, which Android cannot tell), and
  sharing a work that has no link. How the menu is drawn is unchanged (owner question 12).
  Reverse: `reader/ReaderFanMenu.kt`.
- **2026-10-05 · Highlight and Add Note join the system's text selection menu by wrapping it,
  not through the reader toolkit's own hook.** Readium 3.3.0's `selectionActionModeCallback`
  replaces the menu, so setting it would lose Copy and every other system action. Codex asked;
  the answer was a small container view that wraps the callback the WebView starts, passes
  everything through, and adds the two items. The two pills stay in the reader's menu until
  the real menu has been seen on a device. (Brief 3ap, in progress.)
- **2026-10-05 · At the largest text size Android reflows three screens that iOS does not.**
  iOS keeps the Inbox byline on one line and the local collection covers as a scaled mosaic;
  on Android at font scale 2.0 they cut or crowd their text, so Android stacks and wraps there
  (brief 3aq, in progress). Nothing changes at ordinary sizes.
- **2026-10-05 · A highlight made on Android is stored in the form its page can draw.** It was
  stored with a bare Readium locator; the page draws, and goes to, only a locator in this
  reader's envelope (the rule that keeps an iPhone's locators from being followed into the
  wrong place). So a highlight or a note made from selected text was saved and never shown,
  since those two pieces of code were written. `ReaderViewModel.addHighlight` now stores the
  envelope, as bookmarks always did. Highlights already stored bare stay undrawn: nothing tells
  them from an iPhone's. Reverse: `ReaderLocatorCodec.forStorage`.
- **2026-10-05 · The selection menu's two actions are added whenever the system's menu holds
  anything.** Not "when it holds Copy": the WebView's Copy cannot be found by Android's Copy
  id, which the first version looked for, and so added nothing on a device. A book's page has
  no field for a caret, and with nothing selected either action does nothing. The two pills
  are still in the reader's menu; they go next. Reverse: `addActions` in
  `reader/readium/ReaderSelectionContainer.kt`.
- **2026-10-05 · The collection moderation screen sends one request per staged item, as iOS
  does.** The brief said one for all (an old survey note); iOS's code is deliberate about it:
  each item is its own write, one after another, never in parallel, each through the paced
  client, and the first refusal stops the rest. AO3's own page sends every item in one request,
  which would be lighter on AO3; neither app does that. Noted for the owner, nothing changed
  because of it. (Brief 3as, in progress.)
- **2026-10-05 · A tap on a highlight opens its editor, and the two selection pills are gone
  from the reader's menu.** As on iOS: the editor shows the passage, a note to add or edit, the
  colour (saved at once) and Delete Highlight. Highlight and Add Note are made from the text
  selection menu, so the reader's menu holds iOS's five pills. An underline is now drawn as an
  underline (it was drawn as yellow). Reverse: `reader/ReaderNoteEditor.kt`,
  `reader/readium/ReaderHighlightDecorationListener.kt`, and the pill builder in
  `reader/ReaderFanMenu.kt`.
- **2026-10-05 · A pushed screen that is leaving no longer wipes the next screen's top
  buttons.** When one pushed screen opens another, the old one leaves the composition after the
  new one has registered its buttons with the shell, and its farewell reset cleared them. Most
  screens recovered by registering again; one whose arguments never change did not, and the
  moderation screen opened from a collection had no Submit or Discard. The shell now remembers
  which screen the buttons belong to. Reverse: `owner` in `app/PushedShellChrome.kt`.
- **2026-10-05 · The AO3 collection's moderation screen, as iOS's, with two differences kept
  for now.** Items awaiting or holding a decision, with approve, reject, unrevealed, anonymous
  and remove staged per item and sent on Submit, one request per item (see the entry above on
  that). The differences: Android asks "Submit N staged changes to AO3?" before sending, where
  iOS sends on the tap; and Android reads the list again after a refusal, where iOS does only
  after success. Both came from Claude's answer to Codex, not from the owner: owner question
  13. Never run against AO3. Reverse: `account/AO3CollectionItemsScreen.kt`,
  `account/AO3CollectionItemsState.kt`, `updateCollectionItems` in
  `network/ao3/writes/AO3WriteRepository.kt`.
