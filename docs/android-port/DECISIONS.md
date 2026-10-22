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
  conversion record is carried through byte for byte and is taken only with the
  original it describes. Brief 3fz adds Android's own stamp after a local conversion/rebuild;
  foreign stamps still pass through unchanged until then. An original over 128 MB is left out rather than failing the restore.
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
  moderation screen opened from a collection had no Submit or Discard. The shell now keeps the
  screens that are on screen in order of arrival: the newest holds the button row whatever an
  older one does on its way out, and when the newest leaves (a back gesture that is cancelled,
  for one) the screen underneath gets the row back. Reverse: `screens` in
  `app/PushedShellChrome.kt`.
- **2026-10-05 · The AO3 collection's moderation screen, as iOS's, with two differences kept
  for now.** Items awaiting or holding a decision, with approve, reject, unrevealed, anonymous
  and remove staged per item and sent on Submit, one request per item (see the entry above on
  that). The differences: Android asks "Submit N staged changes to AO3?" before sending, where
  iOS sends on the tap; and Android reads the list again after a refusal, where iOS does only
  after success. Both came from Claude's answer to Codex, not from the owner: owner question
  13. Never run against AO3. Reverse: `account/AO3CollectionItemsScreen.kt`,
  `account/AO3CollectionItemsState.kt`, `updateCollectionItems` in
  `network/ao3/writes/AO3WriteRepository.kt`.
- **2026-10-05 · The collection form makes iOS's two extra reads.** Codex asked whether Android
  should make them, since brief 3at said the form is read only when opened. Yes, as iOS: (1)
  Create and Save fetch AO3's form page again for a fresh token before the one POST, as every
  other write on both apps does; (2) while naming a new collection, one check per settled name
  (600 ms after typing stops, the previous one cancelled) of whether that address is taken. The
  check is an anonymous read of the collection's public page through the shared paced client,
  never made for an empty, malformed or reserved name, and a failed check never blocks Save.
  The networking policy does not forbid it: it is not a logged-in read, not in the background,
  and bounded to one per settled name. Decided by Claude under "iOS and Android behave the
  same"; the owner has not been asked. Reverse: the name check in the form's state holder
  (brief 3at).
- **2026-10-05 · Sharing a work's file is the reader's only, as on iOS.** Brief 3au asked for
  the file fallback on the work page too. Codex read iOS and stopped: iOS's work page shares
  only a link, and offers Rebuild from Original, not a viewer. iOS wins: the reader's Share
  falls back to the EPUB when a work has no link, the reader's menu gets the Original icon, and
  the work page is unchanged. Decided by Claude; the owner has not been asked.
- **2026-10-05 · The reader can hand a work's EPUB, or the file it was converted from, to
  another app.** Share in the reader's menu falls back to the EPUB when a work has no link, and
  an Original icon opens the archived original, as on iOS. Two of the app's private folders
  (`works/`, `originals/`) are now reachable through its file provider, one file at a time and
  read-only, for the app the reader picks. An address is only ever made from a work, never from
  a path: only that work's own EPUB or original, never the conversion record beside it, never
  through a link, never for a work in Recently Deleted. The database, settings and the AO3
  cookie store are outside both folders. The file's name is the work's title with path
  separators and control characters removed. Reverse: `reader/ReaderWorkActions.kt` and the
  two lines in `res/xml/file_paths.xml`.
- **2026-10-05 · The reader owns its whole window.** The shell padded the reader below the
  status bar and above the navigation bar and painted the app's colour in both strips; the
  reader's controls, which keep clear of the bars themselves, then sat a bar's height too far
  in (iOS had and fixed the same double inset). Now the reader's page colour runs under both
  bars, everything inside is inset once (the controls sit just under the status bar and no
  longer cover the first line), and the bars' icons follow the page while the reader is open
  (light icons on a Dark page in a Light app, and the reverse); the app's theme takes them back
  when the reader closes. The reader's Contents sheet also takes the reader's theme; it was on
  Material's stock lavender. Reverse: the `Surface` at the top of `reader/ReaderScreen.kt` and
  the reader's two paddings in `app/MainScaffold.kt`.
- **2026-10-05 · The reader's four themes draw iOS's exact page and text colours.** Android
  told the page view only which theme to use and let it pick the colours, so Dark was pure
  black (the same as OLED), Sepia a different cream with near-black text, and no theme's page
  matched the ground around it. iOS gives the page view the colours outright, and Android now
  gives the same ones: Light #FFFFFF with #1E1E1E text, Sepia #FBF0D9 with #5B4636, Dark
  #16161A with #CFCFD4, OLED #000000 with #CFCFD4. Readers will see Dark and Sepia change.
  Reverse: `reader/settings/ReaderColorTheme.kt` and the two colour lines in
  `reader/readium/ReadiumSettingsAdapter.kt`.
- **2026-10-05 · The AO3 collection form: new, edit and delete, as iOS's.** The "+" on AO3
  Collections and Manage › Collection Settings now open iOS's form. Create and Save send the
  served form with the reader's changes in one request; Delete Collection asks for the
  collection's name to be typed, then sends one request. Each fetches a fresh token first and is
  never retried. Android differs from iOS in three small ways, all Claude's: AO3's refusal is
  said once, "Name is available" does not stay beside it, and there are no extra top buttons.
  "Your items" is not built yet. Never run against AO3. Reverse:
  `account/AO3CollectionFormScreen.kt`, `account/AO3CollectionFormState.kt`,
  `network/ao3/account/AO3CollectionForm.kt`, `saveCollection` and `deleteCollection` in
  `network/ao3/writes/AO3WriteRepository.kt`, and `SubjectTextFieldRow` in
  `settings/SettingsChrome.kt`.
- **2026-10-05 · Known gap: Manage › Moderation opens the items screen, not iOS's Moderation
  screen.** Brief 3as built iOS's collection items screen and wired it to the Moderation row.
  On iOS that row opens a different screen (the review queue with one-tap Approve and Reject,
  membership requests, reveal and anonymity), from which the items screen is reached. The
  mistake was in Claude's brief. Until brief 3aw lands, Android's row keeps opening the items
  screen, which does the item decisions; membership requests and reveal are done on AO3's page.
- **2026-10-05 · AO3 Collections and the account lists take the reader's accent, as on iOS.**
  Both pages asked for a fixed colour by a number on the wrong scale (210, where a hue is a
  fraction from 0 to 1), which came out red whatever accent the reader had picked, and red in
  Sepia, where every other page is Sepia's brown. They now use the same accent as the Account
  page and iOS's `theme.scopePalette`. With the default dark-red accent the pages look as they
  did. Reverse: the `palette` line in `account/AO3CollectionsScreen.kt` and
  `account/AccountWorksListScreen.kt`.
- **2026-10-05 · "Your items", and two actions on a collection's row.** The "Your items" chip
  on AO3 Collections opens the items screen for the reader's own works across collections, as
  on iOS: it starts on Awaiting you, the reader can approve, reject or remove their own items,
  and the moderators' side is shown but cannot be changed. Changes are sent one request per
  item, as iOS (owner question 13 covers whether that should be one). A long press on a
  collection's row offers Edit Collection and Manage Items; iOS offers the same two from a
  context menu and a swipe, and Android uses its long-press menu for row actions. Never run
  against AO3. Reverse: `updateUserCollectionItems` in
  `network/ao3/writes/AO3WriteRepository.kt`, the account scope in
  `account/AO3CollectionItemsScreen.kt` and `account/AO3CollectionItemsState.kt`, and the row
  menu in `account/AO3CollectionsScreen.kt`.
- **2026-10-05 · The collection's Moderation screen, and the gap is closed.** Manage ›
  Moderation now opens iOS's Moderation screen: the review queue with Approve and Reject,
  "Recently decided" (which opens the items screen on Approved), membership requests with
  Accept and Decline, a maintainers summary, and Reveal now and Remove anonymity for the
  owner. Reject, Decline, Reveal and Remove anonymity ask first, in iOS's words; Approve and
  Accept do not, as on iOS. Each tap is one request to AO3. The maintainers rows open AO3's
  page until brief 3ay lands. Never run against AO3. Reverse:
  `account/AO3CollectionModerationScreen.kt`, `account/AO3CollectionModerationState.kt`,
  `network/ao3/account/AO3CollectionModeration.kt`, `decideCollectionMember` and
  `revealCollection` in `network/ao3/writes/AO3WriteRepository.kt`.
- **2026-10-05 · In the demo, the in-app browser no longer reaches the network.** The demo's
  block covered the app's own AO3 requests; a page opened in the in-app browser (More on AO3,
  a collection's Maintainers, "Open on AO3") went straight out. In the demo that browser now
  gets bundled pages or a local "not found", for every address. Outside the demo nothing
  changes. This closes a way the rule "the demo must never reach AO3" could be broken on a
  device with a connection; the emulator here has always been in airplane mode. Reverse:
  `shouldInterceptRequest` in `web/AO3WebViewFallbackScreen.kt`.
- **2026-10-05 · The drafts list has iOS's New Work button, opening AO3's page for now.** Brief
  3az asked for the drafts list only. Codex found a New Work button on iOS's screen and asked.
  Answer (Claude; the owner has not been asked): include it, as iOS has it; until Android has
  the work editor it opens AO3's new-work page in the in-app browser, as a tap on a draft opens
  that draft's edit page.
- **2026-10-05 · The drafts notice says only what is true on Android.** iOS's notice reads
  "AO3 deletes an unposted draft 30 days after you create it. Recovery copies stay on this
  device and aren't deleted with it." Android keeps no recovery copies yet, so its notice has
  the first sentence only, until it does. A deliberate, temporary difference from iOS's words
  (answer to Codex on brief 3az; Claude's, the owner has not been asked). Rule for the port:
  where iOS's words describe something Android does not have yet, those words are left out
  and listed, not reworded.
- **2026-10-05 · First run, What's New and the login screen say what iOS's say.** Welcome and
  the sync-folder setup now carry iOS's text word for word, except where iOS names an
  Apple-only thing: "iCloud Drive" became "a cloud storage app", because Android's folder
  picker shows whatever storage apps are installed and Kudos cannot promise any one of them.
  Android gains What's New (shown once after an update; the entries live in
  `support/WhatsNew.kt`; its first entry says "native Android reader" where iOS says
  "native SwiftUI reader"). The login screen has iOS's layout and words, with "Create an AO3
  account" and "Forgot your password?". How signing in works is unchanged. Reverse:
  `onboarding/`, `support/WhatsNew.kt`, `auth/AO3NativeLoginScreen.kt`,
  `auth/AO3WebLoginScreen.kt`, and the first-run block in `app/KudosApp.kt`.
- **2026-10-05 · The collection's Maintainers screen.** Manage › Maintainers, and the
  Moderation screen's two maintainers rows, now open iOS's screen: owners and moderators, an
  invitation by username, and stepping down or leaving behind a confirmation, with the rule
  that the last owner cannot step down. Each action is one request to AO3. As on iOS, pending
  invitations are not listed, and "Invite as" does not change what is sent (owner question
  15). One sentence differs from iOS on purpose: a failed token read says "open the
  collection on AO3", where iOS says "the work". Never run against AO3. Reverse:
  `account/AO3CollectionMaintainersScreen.kt`, `account/AO3CollectionMaintainersState.kt`,
  `network/ao3/account/AO3CollectionParticipants.kt`, `inviteMaintainer` and `leaveCollection`
  in `network/ao3/writes/AO3WriteRepository.kt`.
- **2026-10-05 · Writing › Drafts is a native list.** The Account page's Drafts row opened
  AO3's page in the browser. It now opens iOS's list: each draft with how many days AO3 will
  keep it and when it was created, both taken from the deletion date AO3 prints, the tally of
  drafts expiring this week, and New Work. As on iOS the list has no Post and no Delete. Two
  differences, both recorded above: the notice has only its first sentence, and a draft or New
  Work opens AO3's page in the in-app browser until Android has the editor. Reverse:
  `account/WritingDraftsScreen.kt`, `account/WritingDraftsState.kt`,
  `account/WritingDraftsRepository.kt`, `network/ao3/writing/`.
- **2026-10-05 · Android's Challenge Settings will not read every assignment page, though
  iOS's does.** Codex, reading iOS for brief 3ba, found that iOS's screen walks every page of
  three assignment lists on opening, uncapped, to show three counts. The networking policy
  lists each multi-page read the app may make (each one approved by the owner), and this walk
  is not listed. "iOS wins" does not reach past the policy, which binds both apps. Until the
  owner decides (question 16), Android's screen makes at most four reads (the challenge form,
  the collection's profile, and the first and last page of sign-ups) and shows the Assignments
  rows without counts. iOS is left as it is: changing what iOS reads is the owner's call.
- **2026-10-05 · Android's work editor is built from the bottom, and follows the editor
  design document.** `docs/WRITING_EDITOR_ARCHITECTURE.md` is the single design for both
  platforms; what iOS ships today is its native HTML mode with a formatting toolbar, a
  read-only preview, AO3's word count and the recovery store (the shared rich-text package it
  describes was never built). Posting a work cannot be taken back, so Android gets the layers
  in order, each proved by iOS's own tests before the next: AO3's work form as data (brief
  3bb), the recovery store and the word count (3bc), then the editor's screens, then Save,
  then Post. Until a layer has a screen, a draft tap and New Work keep opening AO3's page.
  The document leaves one Android choice to a measurement (its HTML-mode widget, §9.2, OD5);
  that comes with the editor screen's brief, not before.
- **2026-10-05 · The work form on Android: nothing AO3 served is lost; known fields go out
  iOS's way; the rest goes back as served.** Codex, starting brief 3bb, found that iOS's
  encoder is not a faithful copy of what a browser would send from AO3's work form: it drops
  fields it does not know and hidden arrays, collapses repeated hidden fields, tidies comma
  lists, and sends a checkbox as one value. Most of that is believed harmless; none of it has
  been run against AO3. Answer (Claude; the owner has not been asked): Android's model keeps
  every control AO3 served. For each field iOS sends, Android sends iOS's form of it, so both
  apps give AO3 the same thing and iOS's tests carry over. For every served control iOS does
  not send, Android sends it back exactly as served, as a browser would. This is deliberately
  more than iOS does. Codex is to list each thing iOS drops or changes, with whether it can
  alter a work the reader did not touch; that list goes to the owner and the iOS side.
- **2026-10-05 · Challenge Settings is a native, read-only screen.** Manage › Challenge
  Settings opened AO3's page; it now opens iOS's screen: the kind, the five dates as AO3 prints
  them, the sign-up or prompt requirements, tag sets, the sign-up count, and the rows that lead
  on. It reads at most four pages and sends nothing. Two rows show no value where iOS shows a
  count, because Android does not make iOS's walk over every assignment page (the entry above,
  and owner question 16). Five rows open AO3's page in the in-app browser until their own
  screens exist (edit settings, prompts, tag set, sign-ups, assignments). Reverse:
  `account/AO3ChallengeSettingsScreen.kt`, `account/AO3ChallengeSettingsState.kt`,
  `network/ao3/account/AO3ChallengeSettings.kt`, `getChallengeSettings` in
  `account/AO3CollectionDetailRepository.kt`.
- **2026-10-05 · The work form as data and the editor's foundations are landed; three choices
  made on landing.** (1) Android reads a text area whole (summary, notes, chapter text), where
  iOS trims its ends: an untouched Save then sends back what AO3 served, as a browser does.
  Reverse: `textarea()` in `network/ao3/writing/AO3WorkFormParser.kt`. (2) Where AO3 serves a
  list with nothing marked as chosen, Android's known fields follow iOS (nothing is sent), not
  the browser (the first choice): the two apps must send AO3 the same thing, and whether iOS
  should change is owner question 17. Not reachable on AO3's pages today. (3) The recovery
  copies are written with iOS's values and file names but are this device's only; no iOS file
  was read on Android and none needs to be. iOS evidence: `AO3Client+Works.swift`
  (`parseWorkForm`, `parseSelect`, `textareaValue`), `AO3WritingModels.swift`
  (`parameters(submit:)`), `WritingTextRecovery.swift`. Commits `0da4dfb9`, `452f1f6a`.
- **2026-10-05 · The text editor arrives before anything opens it.** Brief 3bd builds the
  writing text editor (iOS's `WritingTextEditor`, HTML mode) as a screen that edits one string
  and hands it back. Until the work form's screen and Save exist, only a demo route opens it,
  and a draft tap keeps opening AO3's page: an editor that cannot save would be worse than the
  browser. Its text widget is chosen by Codex on argument and then measured by Claude on a
  device against the design document's B1 and B6 with the 510,000-character chapter; a failed
  measurement replaces one file. Reverse: delete the screen and its demo route.
- **2026-10-05 · A challenge's tag set is a native screen that only reads (brief 3be).** iOS's
  screen has two writes (the four tag-name fields and rejecting a nomination). Android gets
  the reading screen first and the writes in a later brief, read against iOS line by line, as
  Unsubscribe was (3an). Where iOS draws a control only for a write, Android shows the value.
  If iOS turns out to read page after page there without a cap the networking policy names,
  Android reads the first page only (as owner question 16).
- **2026-10-05 · A signed-out reader can open a tag set (answer to Codex on brief 3be).** iOS's
  `TagSetView.loadTagSet()` makes one anonymous read of `/tag_sets/{id}` when nobody is signed
  in; the brief had said a signed-out screen reads nothing. iOS wins: a tag set's page is
  public, so Android makes that one read through its client for public AO3 pages and none of
  the signed-in reads (the edit form, the nominations). Answered by Claude; the owner has not
  been asked. Reverse: refuse the screen when signed out.
- **2026-10-07 · The tag set's four Tags rows open nothing until its writes are built.** Codex
  made each count row open AO3's four "tags to add" boxes read-only. AO3 serves those boxes
  empty, so a real tag set would have shown four headings over nothing. On iOS the rows open
  the Add tags editor, which is a write. Until brief 3bg lands the rows show their counts and
  are not tappable. iOS evidence: `TagSetView.swift` (the Add tags destination),
  `AO3Client+Challenges.swift:551` (the fields read are `…_tagnames_to_add`). Reverse: brief
  3bg restores the destination as an editor. Commit `4ec4d8eb`.
- **2026-10-07 · The editor's preview shows text typed outside a block tag, on both apps.**
  Found on the emulator: with `<p>one</p>` and then a loose line, Preview showed only "one".
  iOS does the same, because its preview reuses the parser for AO3's own pages
  (`AO3Client.parseRichText`), which keeps only block elements once there is one. A preview
  that hides a writer's words is a fault whoever has it, so this is fixed on both rather than
  copied: each stretch of loose text becomes a paragraph of its own before parsing, as AO3
  does when it posts. Android `wrapLoose` in `writing/WritingBufferPreview.kt` (`95e67b97`);
  iOS `wrapLooseText` in `WritingBufferPreview` (T-358), same test cases. Only the editor's
  preview changes; the parser AO3's pages use is untouched. Reverse: remove the one call.
- **2026-10-07 · On Android the preview and the recovery sheet draw long text lazily.** A
  full-length chapter drawn at once froze the preview and the sheet for seconds on the
  emulator. Both are lazy lists now (the sheet shows the copy line by line). iOS draws both
  whole and has not been measured with a full-length chapter: an item for the iOS tail.
  Reverse: `EditorPreview` and the sheet in `writing/WritingTextEditorScreen.kt`.
- **2026-10-07 · The native text field stays for now; the decision is not made.** The design
  document leaves Android's HTML-mode widget to a measurement on a Pixel 6a class phone (B1,
  B6). On the emulator the 510,000-character chapter opens, types and checkpoints, and a
  keystroke costs the same per frame as in two lines of text; the emulator's own frame times
  are far above 16 ms on any screen, so it cannot pass or fail the budget. The platform
  `EditText` is kept, the measurement is owed on a phone, and the widget is one file
  (`writing/WritingNativeTextField.kt`) if it fails.
- **2026-10-07 · Next in Writing: the work form's screen without Save (3bf); next in
  Challenges: the tag set's two writes (3bg).** The form's screen shows a loaded work and
  changes it in memory, with the text rows opening the editor; tags and association rows wait
  for their own briefs; nothing opens it but demo routes until Save exists. The tag set's
  writes follow the pattern of Unsubscribe and the collection writes: one fresh token, one
  POST never retried, the screen changed only on AO3's confirmation, fixtures only.
- **2026-10-07 · The shell shows its top row again whenever a different screen takes it over.**
  The top row hides when a page is scrolled down, and the state is kept per route. A screen
  that replaces another inside one route (the text editor opened from the work form, the tag
  set's Add tags screen, a chooser) inherited a hidden row and had no Back, Done or Undo. The
  shell now shows the row whenever the screen holding it changes, which also means a page you
  come back to shows its row even if you had scrolled it away. iOS has no scroll-away chrome
  yet (T-349), so there is nothing there to match; when it gets one, do the same. Reverse:
  the `LaunchedEffect(pushedHolder)` line in `app/MainScaffold.kt`.
- **2026-10-07 · Choosing the blank rating does not clear a rating, on either app.** iOS's
  encoder sends no rating when none is chosen, and AO3 keeps what it had. Android's encoder
  (brief 3bb) sends the rating control back as AO3 served it, with the same result. Left as it
  is; the Save brief must not present the blank line as a way to remove a rating. iOS
  evidence: `AO3WorkTagSet.parameters()` (`if !rating.isEmpty`).
- **2026-10-07 · The tag set's writes post only to AO3.** The address Save tags posts to is
  read from AO3's page; it is kept only when it is one of AO3's own hosts, as Unsubscribe's
  captured address already was (`AO3RedirectCookieRelay.isTrustedUrl`). iOS posts to whatever
  address the form gave. Android is the stricter; nothing changes for a real AO3 page.
- **2026-10-07 · A prompt meme's close date is read once per opening, not on every further
  page (answer to Codex on brief 3bi).** iOS's `PromptMemeView` tries the schedule lookup
  again on each later page load for as long as no close date was obtained. The brief allows
  one read per "load more". Android attempts the schedule once per opening and once per pull
  to refresh; a further page is exactly one prompts read; without a close date the screen
  shows what iOS shows without one. Android is the more sparing in a failure case only.
  Answered by Claude; the owner has not been asked. For the iOS side: the repeated lookup is
  extra signed-in reads for a date that did not load. Reverse: retry the schedule in the
  page loader.
- **2026-10-07 · Owner: the prompt meme's close date is asked for once, and only when AO3
  will answer ("do it, fix iOS and skip lookup for non-maintainers").** This replaces the
  entry above it as the rule for both apps. The date is on the challenge's settings form.
  AO3 serves that form to the collection's **owners** only and refuses it to everyone else,
  moderators included (iOS `AO3CollectionDetailView.swift`, the comment on the Challenge
  Settings row), and the Prompts screen is open to any participant, so the gate is "the
  viewer is an owner": a moderator would be refused too. The rule, one pure function on each
  app: ask only for an owner, only until a date is known, once per opening and once more per
  pull to refresh. iOS: T-359, `PromptMemeView.readsSchedule`. Android: brief 3bi, applied on
  landing, where the collection page's Prompts row must also open the screen for any
  participant, as on iOS. Still open: a participant never sees "open until" on either app.
  Reverse: pass `viewerIsOwner: true` from both callers.

## 2026-10-08: the work form's Chapters list reads only, and reads once (brief 3bm)

- The Chapters row on a posted work opens iOS's list (`WritingChaptersView`): one signed-in
  read of the work's chapter index per opening and per Try Again, through the form's own
  repository. A row opens nothing until the chapter form exists on Android. Gemini Pro wrote
  the brief; its screen read twice per opening and used stock Material parts, so the screen
  and its tests were rewritten on landing and its fixture and wiring kept.
  Reverse: remove `viewingChapters` from `WritingWorkFormScreen.kt`.

## 2026-10-08: audit A4's faults fixed on both apps

- A work with several chapters: AO3 serves no chapter text box, so none is sent, shown or
  required (`AO3WorkChapterDraft.contentServed`). AO3's validation list (`#error li`) is a
  refusal. Unsubscribe on a work page and Mark for later need AO3's notice or a redirect.
  iOS: T-362. Checked against otwarchive's source; never run against AO3.
  Reverse: `needsEvidence = false` in `AO3WriteRepository.toOutcome`'s two callers.

## 2026-10-08: two backup merge rules brought to iOS's (audit A3)

- Preservation never goes down in a merge: a local "preserved" stays, whatever the archive's
  clock. File Merge of a work in Recently Deleted returns it and lets the clocks decide its
  fields; the archive row is no longer copied over it. Both are iOS's `apply`.
  Reverse: the two edits in `BackupMergeService.kt` marked "audit A3-1" and "audit A3-2".

## 2026-10-08: four reader and library faults from audit A5

- A reading position save, once begun, finishes, and leaving the reader waits for it. The
  same passage means the same stored locator (iOS), not the same words nearby. A selection
  holds only rows on screen: a row a quick filter hides is dropped from it, where iOS keeps
  it selected and skips it. Not yet changed: the position card's scrub and auto-finish at
  98.5% (brief 3br).
  Reverse: the edits marked "audit A5-1", "A5-4", "A5-5" and "A5-6".

## 2026-10-08: a section header's title may use the whole row

- `SectionRuleHeader` held its title to half the row (a weighted title beside a weighted
  spacer), so at large text sizes a short title wrapped. The title and its count now share
  the row up to See All. Five custom controls got a role and a state for screen readers
  (audit A13 and the reader's colour swatches).
  Reverse: the inner `Row` in `SectionRuleHeader`.

## 2026-10-08: Work Detail saves a series the way iOS does, and its sheets are the app's own (brief 3bn)

- Save for Later on a work in a series offers iOS's "Preserve Series?" (or preserves a small
  series by itself when the setting is on and the first page shows the whole series, at or
  under the saved threshold, which the setting now really controls). Works are downloaded one
  at a time, awaited, with the two-second pause, and can be cancelled; a restricted work is
  skipped, never requested (owner, 2026-10-07). The bookmark and Add to Queue sheets replace
  the old Material dialogs. Android now stamps the preservation status and time it used to
  carry only for iOS.
  Reverse: revert the 3bn commit; no schema or backup key changed.

## 2026-10-08: a challenge sign-up can be filled in and submitted (brief 3bl)

- "Your Sign-up" on a collection and "New prompt" on a prompt meme open the app's own form
  (iOS 1ca), no longer AO3's page. One read on opening; Submit is one fresh token read and
  one POST, never retried. Android replays every served control iOS's encoder leaves out,
  each prompt's hidden tag-set id included; iOS does not send those (audit A4).
  Fixtures only: never run against AO3.
  Reverse: point the two entry points back at the in-app browser (`onOpenSignUp`).

## 2026-10-08: action rows are drawn in the palette's accent

- `SettingsActionRow`'s text and icon use `tokens.scopePalette.accent`, not the raw accent:
  AO3 red on a dark panel was about 1.8 to 1 ("Export Backup…" in Dark). The palette's
  accent follows the reader's chosen hue and is tuned per theme, as iOS's palette does for
  its text roles. Other text in the raw accent, and iOS's tinted rows, are owner question 19.
  Reverse: `else -> tokens.accent` in `settings/SettingsChrome.kt`.

## 2026-10-08: what the Privacy page and the History list say, they do (audit A14)

- Clear reading history takes only works left in the history alone (no copy here, not saved,
  favourited, kept offline, imported or gone from AO3; and, more sparing than iOS, not in a
  queue). Clear reading positions clears positions and keeps the works. "Delete from
  History" sends iOS's request to AO3 and removes the row only when AO3 confirms; before, it
  hid the row and sent nothing. Fixtures only for the write.
  Reverse: `softDeleteHistoryOnly`, `clearReadingPositions`, `deleteReading`.

## 2026-10-08: seven backup merge rules brought to iOS's (brief 3bs, audits A3 and A12)

- Date Added and a queue's Date Created are always the earlier of two copies. Replace
  Library takes the archive's queues and memberships. File Merge returns a collection or a
  queue from Recently Deleted and retracts a returned work's deletion marker. A note a newer
  copy displaces is kept on a hidden row. A delete and its marker are one transaction,
  marker first. "Gone from AO3" is never cleared by a merge; a file's name is only filled
  when empty; two live annotations at the same place collapse to the newer (never those
  with no locator: Android only). **A signed deletion from a trusted device removes the copy
  already here** for annotations, queue memberships and saved links.
  Reverse: revert the 3bs commit; no schema, manifest key or migration changed.

## 2026-10-08: the reader finishes a work at its end, and scrubs within the chapter (brief 3br)

- A complete work is marked finished only when the bottom of its last part is on screen (or
  its last page, paged), never at a percentage; the copy's hold starts on leaving the reader.
  The position card shows the page within the chapter and its thumb seeks within it. A saved
  position that names a part the book does not have opens the book at the beginning (it used
  to stop all position tracking for that work).
  Reverse: revert the 3br commit; nothing stored changed.

## 2026-10-08: Android's writes and its comment cache after audit A17

- A plain authenticated POST is fenced by the session it was made under, like the newer
  writes. Comment, Inbox and preferences writes need AO3's own confirmation. The offline
  comment cache stays (iOS has none), as one read-only copy per viewer, used only when AO3
  cannot be reached.
  Reverse: the commits "Comment and Inbox writes need AO3's own notice" and the one after.

## 2026-10-08: comment drafts, the mature blur and the demo after audit A18

- A comment draft belongs to the account signed in when it is saved; an edit never uses the
  draft store (as iOS).
- A blurred row says "Hidden mature work. Activate to reveal." and nothing else, and any tap
  on it reveals. Search's library matches are blurred by the Library's rule. Hide mode is
  left as iOS has it (owner question 20).
- The demo skips the GitHub update check. It does not block other hosts.
  Reverse: the two commits that name audit A18.

## 2026-10-08: Reading History is grouped (brief 3bp)

- Time, State, Fandom, Flat, as iOS; the choice is kept per device under iOS's key
  (`library.history.grouping`) and is not in the backup. "Move back to In progress" writes
  the existing `keepInProgressOverride` and the work's modification time, nothing else.
- Hide mode leaves a mature work out of Search's library matches on both apps (audit A19-3;
  owner question 20 is withdrawn: iOS's own code says Hide filters before the row).
  Reverse: the commits "Reading History grouped by time, state or fandom" and "Hide mode
  leaves a mature work out of Search's library matches too".

## 2026-10-08: the work form saves (brief 3bo)

- Save on the native work form: one POST of the loaded form to its own action with the token
  it was served, never retried, never preceded by a read; done only on AO3's notice or its
  redirect; AO3's reason shown otherwise and everything typed kept. Drafts and New Work open
  the native form. After a confirmed Save the drafts list reads its current page once; an
  unsaved Back reads nothing (the more sparing choice).
  Reverse: the commit "The work form saves".

## 2026-10-08: what audit A19 found on iOS, on Android

- Every blurred surface (card row, ledger row, cover, hero, queue row) says "Hidden mature
  work. Activate to reveal." to a screen reader and nothing else, through one modifier.
  A blurred work has no long-press menu, on Home and the collection page as in the Library.
- "Check Availability" lists a mature work as "Hidden mature work" while Hide or Blur
  conceals it; a tap reveals it.
- Home's subscriptions are applied only for the session that asked for them.
  Reverse: the commit "A blurred mature work is unnamed and unopened everywhere".

## 2026-10-08: Favorites has its four scopes (brief 3bq)

- Works, Authors, Fandoms, Tags, as iOS, ranked by what was read (not by what is starred);
  mature works that are blurred or hidden are left out of the aggregates. The scope, the
  order and "Unread works" are kept per device under iOS's keys and are not in the backup.
- The demo's finished works have a read date.
  Reverse: the commit "Favorites by author, fandom and tag".

## 2026-10-08: a posted work's tags can be edited (brief 3bt)

- Edit tags reads AO3's tag form once on opening. Save reads it again for a fresh token and
  action, sends the chosen tags in one POST, never retried, and counts as done only on AO3's
  notice or redirect (iOS `editTags`). The work form underneath re-reads its own form after
  a confirmed Save and keeps unsaved text edits.
  Reverse: the commit "A posted work's tags can be edited".

## 2026-10-08: filters closed without Apply, and the page after a reply (audit A20)

- Closing the filter sheet without Apply drops its edits: on a fandom or tag page always, on
  Search while results are on screen (the typed search text stays). Before, the next page
  tap sent them. The same on iOS (T-370).
- After a reply, an edit, a delete, or a post AO3 did not confirm, comments read the page on
  screen again, not page 1, and keep the focused comment.
- A read-aloud failure logs its kind, not the exception (audit A21).
  Reverse: the commit "Filter edits closed without Apply are dropped".

## 2026-10-08: More on AO3 has iOS's rows, and they open

- The screen's sections, rows and addresses are iOS's (artboard 1aa): a page of the reader's
  own under `/users/<name>/`, or a site-wide page. A page of the reader's own does nothing
  when signed out, as on iOS. Android's earlier rows that iOS does not have (change username,
  password and email, blocked and muted users, the challenge lists) are gone from this
  screen; blocked and muted users have their own screens elsewhere.
- The author menu has "Share Profile".
  Reverse: the commit "More on AO3: iOS's rows, and they open".

## 2026-10-09: comments after audit A22

- A reload of the comments page leaves an open composer's reply or edit target alone. An
  edit AO3 did not confirm shows the failure and is not reloaded (iOS).
- The offline comment cache holds only a work's or chapter's own pages, opened by the
  reader: not one comment's thread, and not the Inbox's author lookup.
- One comments load at a time; an Inbox row loads its thread and nothing else.
  Reverse: the commit "A reply AO3 did not confirm stays a reply".

## 2026-10-09: a writer's series can be edited (brief 3bw)

- Edit series (title, creators, summary, notes, complete), Reorder and Remove from series,
  as iOS: offered only for a series whose creator links name the signed-in account. Opening
  reads the edit form once and the works list once (best effort, and a failed attempt is not
  repeated). Each write reads a fresh token where iOS does, is one POST, is never retried,
  and is done only on AO3's notice or redirect; Reorder refuses if the series changed on AO3
  since the screen opened. A work removed from a series stays posted.
  Reverse: the commit "A writer's series can be edited, reordered and trimmed".

## 2026-10-09: backup merge and Edit tags after audit A23

- Replace Library takes the archive's word for what the archive carries and wipes nothing
  else on a work that is already here (iOS runs the same `apply` in Replace): the hold date
  of a finished copy, kudos given, author identities, and optional keys an older archive
  lacks all stay.
- The seven AO3 tag lists of a work are merged in every mode.
- A deletion record for a collection membership removes the work from a collection that
  already has it, in every mode but Replace, unless the archive lists it and is newer.
- Edit tags always sends the token, the method and the submit in the body.
  Reverse: the commit "Replace keeps what the archive does not carry".

## 2026-10-09: chapters can be added, edited, posted and deleted (brief 3bu)

- The chapter form as iOS has it: a new chapter, an existing one, its preview on AO3 and
  Post from the preview, and Delete. Every write is one POST, never retried, done only on
  AO3's notice or its redirect. A chapter has no "Post?" confirmation, because iOS has none.
  After a confirmed write the work form reads its own form once for the new chapter count.
  Reverse: the commit "Chapters can be added, edited, posted and deleted".

## 2026-10-09: the Account shortcuts editor, and an author's works sorted (brief 3by)

- The Account grid shows the shortcuts the reader chose, in their order; the choice is kept
  per device under iOS's key and is not in the backup. Choosing none hides the grid.
- An author's works can be sorted and filtered by completion as on iOS: one read per Apply,
  page 1, and a dismissed sheet applies nothing.
  Reverse: the commit "The Account shortcuts can be chosen; an author's works can be sorted".

## 2026-10-09: a write that has been sent is never called "not saved" (audit A24)

- After a POST has returned, a session that moved on meanwhile is reported as "AO3 replied
  but didn't confirm the change went through", for every write in `AO3WriteRepository`. The
  check before a POST still cancels it. iOS judges the answer it has the same way.
- The collection membership pass of a restore covers only collections the archive carries
  (iOS). This narrows the entry of the same day above.
  Reverse: the commit "A write that was sent is never reported as not saved".

## 2026-10-09: what a sent write says, continued (audit A26)

- A verdict from `AO3WriteRepository` is shown as it is by the chapter form and the work
  form; "Your AO3 session changed. Reopen this form before saving." is kept for a failure
  before a POST. A preview AO3 returned is adopted even if the session has since moved on.
- AO3's login page in answer to a work, chapter or Edit tags POST is "Your AO3 session
  expired. Please log in again.", not "didn't confirm".
- An unconfirmed chapter delete or series removal is not prefixed "was not deleted" or "was
  not removed" (iOS says both sentences; Android leaves out the one that may be untrue).
- The collection form ends a write caught by a session change: "didn't confirm" after the
  POST, "Not saved"/"Not deleted" before it.
- The Inbox's "Chapter Comments" opens the chapter's first page with the inbox comment's
  thread first when it is not on that page (iOS). Three reads: the thread, the chapter index,
  the chapter's page. A comments screen opened on a chapter is labelled with that chapter.
- A chapter POST always carries its token and method in the body.
- A series Save scrolls AO3's answer into view.
  Reverse: the commit "A sent chapter or work write keeps AO3's verdict; Chapter Comments
  shows the inbox thread".

## 2026-10-09: no Account shortcuts is a choice (audit A27-11)

- An explicit empty choice is stored as `none` and stays empty; a value never written, an
  empty one, or one with no known name is still the six defaults. iOS stores the same word
  since T-371. Android had copied iOS's fault (removing the last shortcut brought all six
  back) with two tests that pinned it.
- Not changed, **owner question 21**: a deletion does not reach a copy the other device made
  on its own, on either app, and Replace Library treats a later deletion in two different
  ways. Android's restore has the same rules as iOS's here (`BackupMergeService`).
  Reverse: the commit "Choosing no Account shortcuts stays empty".

## 2026-10-09: the work form posts, previews on AO3 and deletes (brief 3bx)

- Post is one POST of the form as it stands (`post_button`), after iOS's confirmation; missing
  required fields are named and nothing is sent. Preview on AO3 is one POST
  (`preview_button`); a new work's preview adopts the draft AO3 created, so a later Save or
  Post updates it. Delete reads AO3's confirmation page, shows its caution verbatim, and on
  confirmation reads that page again for a fresh token and sends one POST.
- A deleted work's copy in the reader's library is not touched (iOS).
- Android does not read the work's own page for a delete (iOS does, twice, for counts it
  never shows).
- A preview that names its work is kept even if the session has moved on since; AO3's login
  page in answer to a POST is "session expired".
  Reverse: the commit "The work form posts, previews on AO3 and deletes".

## 2026-10-09: the Privacy screen as iOS has it (brief 3bz)

- Settings' Privacy page has iOS's opening card and four sections: what is stored on this
  device (measured on opening and after each Clear, off the main thread), Clear, the AO3
  session with Remove AO3 session, and the Read Aloud downloads note, in iOS's words.
- Sizes are allocated bytes where the file system gives them, as iOS; a reading copy is
  counted by its length and subtracted from the works folder, as iOS.
- Removing the session is the existing local logout: no request to AO3.
- Kept from Android: the "confirm before delete" preference still governs the four Clear
  confirmations (iOS always asks); Clear reading history leaves a queued work alone.
  Reverse: the commit "The Privacy screen as iOS has it".

## 2026-10-09: fifteen small differences from iOS (brief 3ca, from reading R5)

- An empty tag page says whether filters emptied it; a missing author is "Author unavailable"
  with no retry; a later page that fails keeps the pages already shown; the Account identity
  waits for a restoring session; a preference kept after a refused save; signed-out named
  subscriptions show the ordinary failure card; the comment format sheet offers all six
  heading levels and re-levels a heading in place; a page-local bookmark filter that empties
  the page says so. Each is iOS's behaviour, with a test per row.
- An author page and a search make one read in the session they have. The anonymous second
  read after a failed signed-in read is gone.
  Reverse: the commit "Fifteen small differences from iOS".

## 2026-10-09: Chapter Comments from the Inbox, second version (audit A28)

- One operation: the comment's thread, then its chapter's first page with the thread first
  when it is not on that page. The chapter is the one the thread's own page names; no chapter
  index is read (two reads). A thread naming no chapter is shown by itself. This replaces the
  three-read version recorded earlier the same day.
- Try Again on a failed comments load repeats the request that failed.
- A page load puts the work's draft only into a field nobody has opened.
  Reverse: the commit "Chapter Comments is one operation; a page load never fills an open reply".

## 2026-10-09: a challenge's sign-ups list, and withdrawing a sign-up (brief 3cb)

- A challenge's owner or moderator has a native Sign-ups list (All, Matched, Unmatched; a
  participant's sign-up read from the row already loaded; "Load page N of M"). Anyone else is
  refused before a request is made.
- Reads for one opening: an owner of a closed gift exchange six (the schedule, the first page
  of each of the three assignment lists, the first and last sign-ups pages); an owner of an
  open one three; a moderator two, with no match state. iOS walks every assignment page and
  makes the owner's reads for a moderator too: Android does neither (owner question 16, and
  "a read AO3 will refuse is not made").
- An existing sign-up has Withdraw, with iOS's confirmation: one fresh read of AO3's
  confirmation page, one POST, never retried.
- Left out: withdrawing after sign-ups close (it records a default on the assignment), and
  everything else about assignments.
  Reverse: the commit "A challenge's sign-ups list, and withdrawing a sign-up".

## 2026-10-09: a required field is spoken as "…, required"

- A form label drawn with the required marker ("Title ∗", "Archive warnings ∗", "Fandoms ∗")
  is spoken as "Title, required", as iOS's row does; the marker itself was being read aloud.
  Beside a text field the field says "…, required" and the label says the name alone. The
  rule is in the two shared form rows (`SubjectFormRow`, `SubjectTextFieldRow`), keyed on the
  marker, so nothing else changes.
  Reverse: the commit "A required field is spoken as required".

## 2026-10-09: the chapter index is read in the reader's session (audit A28-4)

- A work's chapter index (`/works/:id/navigate`, for the comments screen's chapter scope and
  the reader's comments button) is read through the session when the reader is signed in,
  as iOS reads it, and without one otherwise. One read; a refusal is not asked again without
  the session.
- Its cache is per work and per session: what one account was shown is not served to the
  next account or to a signed-out reader.
  Reverse: the commit "The chapter index is read in the reader's session".

## 2026-10-09: a comment's first line at large text, and a name's room

- At large text (font scale above 1.3) a comment's name has its own line and the date, the
  chapter and Hide wrap under it. In one line as tall as the avatar the name was squeezed to
  a letter or out, and the rest was cut in half. iOS had the same line run off the screen
  (T-373).
- At every size the name takes the room that is left on its line; it used to share that room
  half and half with an empty gap, so "Calytrix" was drawn "Calyt…" beside empty space.
- The line is never shorter than its text (a minimum height, where it was a fixed one).
  Reverse: the commit "A comment's name is shown whole, and its first line fits at large text".

## 2026-10-09: the composer's header at large text

- At large text the composer's title gives way (one line, cut short if it must be) and
  Cancel and Post never wrap. "Post" was drawn "Pos" over "t". Seen broken on the emulator;
  the fix was not seen (the emulator had stopped responding).
  Reverse: the commit "The comment composer's action is not broken across lines at large text".

## 2026-10-09: audit A30's Android findings (Codex's review of what landed that day)

- **A draft read late never lands in another composer (A30-1).** Every opening, closing and
  change of what the composer is for moves one count, and a draft lookup that returns after
  the count moved is dropped. "Write a comment" read the work's draft before its sheet
  appeared; Reply or Edit tapped meanwhile got that text, and it would have been sent as the
  reply. The test fails without the guard.
- **A choice made while Chapter Comments loads replaces it (A30-5)**, also when it equals what
  is shown: "All comments" did nothing and the chapter then took the screen.
- **The chapter and its number come from the thread, root first (A30-6, A30-7)**, as iOS's
  `chapterRef(in:)`; the Inbox's own number is only the fallback, and the chapter index, when
  it is read, replaces the placeholder for the same chapter with its title and number.
- **One row per comment, the root included (A30-10).** When the chapter's page holds the
  thread's root without the reply that was asked for, the page's copy gives way to the thread.
  The demo's single-comment page no longer renames its first comment to an id the page
  already holds.
- **The comments screen's chapter list belongs to whoever it was read for (A30-11)**: read as
  a guest while the session was restoring, it is read again once the reader is signed in.
- **A required label says so unless its own field does (A30-12).** `SubjectFormRow` takes
  `labelSpokenByControl`; only the settings text field row sets it. Edit tags' "Fandoms" row
  (a count beside the label) had lost its "required".
- **The Privacy demo's fandom list is dated 1970 (A30-9)**, so it is measured and never
  served: dated today, Browse showed one fandom as all of TV Shows for a week on a launch
  without the demo. A debug install that already ran that demo keeps the bad entry until it
  is a week old or Privacy's "Clear fandom catalog" is used.
  Reverse: the commit "Audit A30's Android findings".

## 2026-10-09: a challenge's assignments, claim a pinch hit, report a default (brief 3cc)

- The assignments screen for a gift exchange's owner and moderators: Matched, Unmatched and
  Pinch hits, from the first page of each of AO3's four lists (iOS reads every page; Android
  reads more of one list on a tap: owner question 16). The owner can report a default and
  claim a pinch hit: one fresh token, one POST, never retried, fixtures only.
- **Nobody is asked for what AO3 will refuse.** A participant and a signed-out reader make no
  request (iOS makes four that fail). Known-open sign-ups: none. A refusal of one list stops
  the others.
- **A moderator's lists are asked for without knowing that sign-ups are closed**, because
  only the owner is served the page that says so. AO3 answers.
- A due date in a time zone the app cannot name never shows a "Late" badge.
  Reverse: the commit "A challenge's assignments, with claim a pinch hit and report a default".

## 2026-10-09: the comment the Inbox named goes first by itself (audits A30-10, A32)

- When the chapter's page holds the thread's root without the comment that was asked for,
  that comment is put first by itself and the page's root keeps every reply it has. The
  first fix (the same day) replaced the page's root with the thread's, which could drop
  replies only the page held.
  Reverse: the commit of the same name.

## 2026-10-09: Merge takes a highlight brought back after its deletion (audit A30-4)

- File Merge is add-only for a highlight this device already has, with one exception: when
  the copy here is older than a trusted deletion (so the sweep is about to remove it) and
  the archive holds the same highlight made again after that deletion, the archive's copy is
  taken. Skipped, the old copy was swept and the newer one never installed: neither was left.
  Reconcile and Replace already took it. A note the old copy held is parked, as elsewhere.
  Found on iOS by Codex's review A30 and fixed there the same day (T-376); Android had the
  same path. A30's other restore finding (Replace and a newer local mark on the same
  passage) does not apply here: Android removes the marks the snapshot does not list before
  it compares passages.
  Reverse: the commit "Merge takes a highlight brought back after its deletion".

## 2026-10-09: the writer's own works, and Edit multiple works (brief 3cd)

- On the signed-in writer's own Works list: Select Works with a bar (Edit, Collections,
  Visibility, Delete) and, on a row, Edit, Tags, Chapter and Delete. Ownership is the
  account's own name against the page's, never a displayed pseud.
- Edit multiple works is AO3's own form: opening it sends AO3's rendering POST (it changes
  nothing), as iOS; tags are changed work by work, then everything else in one POST. A tag
  run that fails stops there and is not rolled back, as iOS.
- Delete asks first, naming the count and the titles; one POST, never retried.
  Fixtures only.
  Reverse: the commit "The writer's own works, and Edit multiple works".

## 2026-10-09: a page AO3 could not serve again is shown from memory, and says so (brief 3ce)

- The Inbox, the Account tab's own profile, an author's profile and a series page keep the
  pages they read, **in memory only** (never on disk, never in a backup, gone on relaunch),
  128 pages at most. For five minutes an opening makes no request, as on iOS; for a day the
  copy can stand in when AO3 cannot be reached, with the line "Showing cached AO3 data".
- **Only when AO3 could not be reached** (no connection, a timeout, "AO3 is busy", a 5xx).
  Never after AO3's own refusal: what someone was allowed to see before is not shown in its
  place.
- **A copy belongs to the session that read it.** It is keyed by the account's name and the
  session, and every step of the session (sign-in, sign-out, a restore, an expiry) clears
  the whole cache.
- A write removes the pages it changes; the writer's own bulk edit and delete (brief 3cd)
  read the list again from AO3.
  Reverse: the commit "A page AO3 could not serve again is shown from memory".
- **2026-10-10 · After a saved Edit multiple works, the writer's list is read again.** The
  rows kept the rating and tags from before the Save until the reader pulled the list, and the
  kept page would have shown them for five minutes more. Android now reads the header and the
  list again from AO3 after the Save, as it does after a row's edit and after a delete. iOS
  does not (its form closes and nothing reads the list): to be fixed there the same way.
  Reverse: `onSaved` in `author/AuthorProfileScreen.kt`.
- **2026-10-10 · A challenge's settings can be edited (brief 3cf).** The owner's Edit settings
  opens iOS's form: Basics, Schedule, Sign-up limits, Tag sets, Matching, Anonymity and
  moderation, with one Save changes at the bottom. Save is one request for the challenge and,
  only if one of the four collection switches changed, a second for the collection; turning
  off Unrevealed or Anonymous asks "Reveal now?" first. As with the work form, Android sends
  back every control AO3 served, changed only where the reader changed it; iOS re-encodes
  what it models (the difference is listed in `briefs/3cf-result.md`, question 1). The
  sign-up total is shown only when the first page is the whole list (owner question 16).
  Never run against AO3. Reverse: `account/AO3ChallengeSettingsEdit*.kt`,
  `network/ao3/account/AO3ChallengeSettingsForm.kt`, `saveChallengeSettings` in
  `network/ao3/writes/AO3WriteRepository.kt`.
- **2026-10-10 · A panel in a dialog gets a solid ground.** Three pickers (the challenge
  form's date picker and number chooser, the assignments screen's two pickers) drew a 9% glass
  panel with nothing under it but the dimmed screen. `Modifier.dialogGround` puts the page's
  own colour under such a panel. Use it for any panel shown in a `Dialog`.
- **2026-10-10 · A Library section's order is described in iOS's words.** The order was
  already the same on both apps; Android's sentence under the header said otherwise for four
  sections ("most recently finished first" over a list sorted by last read). Now: Reading Now,
  Finished and History "most recently read first"; Saved for Later "most recently read or
  added first"; Downloaded and Favorites "newest first" (`library/LibraryScreen.kt`). No test:
  it is a table of words.
- **2026-10-10 · A comment composer belongs to what it was opened for, and to the reader who
  opened it (brief 3cg; audit A32 items 1, 4, 5).** Its draft slot and its send are fixed when it
  opens, as iOS's `composerContext`; the reader is the published name **and** the session's
  count, as iOS's `AuthContext`. Three differences from iOS, each the more sparing: a composer
  still reading its draft does not open once the reader has chosen another chapter; after a
  change of reader the screen asks again for what the route named, not the work's first page;
  and a comment AO3 confirmed is cleared from its draft slot even if the reader changed while
  AO3 answered. A saved edit no longer clears the new comment waiting as a draft. Reverse:
  `Composer`, `Viewer` and `syncViewer` in `comments/CommentsViewModel.kt`. Details and the
  mutation table: `briefs/3cg-result.md`.
- **2026-10-10 · A confirmed series save drops the kept series page.** The page cache (3ce)
  answered the series page from before the save for five minutes, and the screen that opened
  the form showed its old state. The form's state now removes `/series/<id>` from the cache
  when AO3 confirms a save, an order or a removal, and its opener reads again past the cache.
  The rule for every new write: **if a screen can show a page the cache keeps, the write drops
  that page.** Reverse: `seriesChanged` in `writing/WritingSeriesState.kt`.
- **2026-10-10 · A text field never takes a late echo of its own text for a change from
  outside.** The comment composer lost and reordered characters typed fast, because the draft
  comes back through a flow a frame late and was put over what had been typed since. The rule
  for any field whose text also lives in a flow: the field's own state is the truth while it
  is open; a value from the flow is applied only if the field did not send it
  (`DraftEchoes`, `comments/CommentComposerSheet.kt`).
- **2026-10-10 · A list behind a form reads again after the form wrote to AO3 (both apps).**
  After the work form or the tags editor, opened from a row of the writer's own list, saved,
  posted or deleted, the list came back as it stood: the old title, or a work that no longer
  exists. Android: `writing/WritingOwnWorkScreen.kt` now calls `onChanged` for Edit and Tags as
  it did for the chapter form. iOS: T-379, with the collection page and the kept pages too. The
  rule for every new form: **a confirmed write tells the screen that opened the form**, and a
  kept page that shows what was written is dropped.
- **2026-10-10 · One segmented control, and it keeps its labels whole at large text.** There
  were two copies (`SubjectSegmentedControl` in its own file and in `SubjectComponents.kt`);
  the second now calls the first. At an accessibility text size more than three segments sit
  two to a row and a label may take a second line; a figure's value may take a second line
  too. At the normal size nothing changes except that the profile's tabs take the first copy's
  track and border. Seen on the emulator at both sizes.
- **2026-10-10 · The list of collections reads again after a collection is created, saved,
  deleted or left.** It keeps its rows in a view model, so coming back to it showed a deleted
  collection until pulled. The form and the maintainers screen raise a count on the list's
  back-stack entry (`collectionsChanged` in `app/AppNavHost.kt`), as the work form already
  does for the drafts list; the list reads once for each change.

- **2026-10-11 · Android keeps which AO3 account wrote a work.** The column for it
  (`authorIdentitiesJSON`) was added long ago and nothing filled it: no import wrote it and no
  backup carries it (it is device-only on iOS too). So Favorites › Authors never knew an
  author's account: no way to open their page from a row, and nothing to check for new work.
  Now a blurb's and a work page's author links are read into it (`AO3AuthorIdentities`, the
  shape iOS stores), with no new request: only pages the app was reading anyway. A work
  already in the library learns its author the next time its page or blurb is read. A byline
  that changes without naming an account (the work went Anonymous) drops the old account
  rather than keeping it under the new name. Reverse: the three lines in
  `works/WorkMetadataMerger.kt`.
- **2026-10-11 · Favorites › Authors: each author's newest work, and "With new work" (as
  iOS).** `library/AuthorNewestWorkStore.kt` is iOS's store: one page per author with a
  single registered account, newest posted first, asked for only while the reader has that
  list open, one author after another through the paced client, stopped when the reader
  leaves, and kept in memory for half an hour per session. The filter cannot be chosen until
  every author has answered. **How the policy's sentence was read:** it says the round "stops
  at the first unresolved response". iOS's code, later than that sentence, goes on past a
  byline that has no page (a 404 is an answer: nothing to show) and stops at anything that
  would meet the next author too (offline, overloaded, unreadable). Android does what iOS's
  code does. The stricter reading would switch the filter off for the whole session whenever
  one favorite author was renamed or deleted. The choice is kept on the device
  (`library.favorites.authorQuickFilter`, iOS's key), outside backups. Reverse: the store's
  line in `app/KudosAppContainer.kt` and the two arguments in `app/AppNavHost.kt`.
- **2026-10-11 · An author is opened by the account behind the byline, not by the byline's
  words.** A work's page passed the words it shows, so "Second Pseud (SecondAccount)" was
  asked for as an account of that name and AO3 answered 404: any author posting under a
  pseud could not be opened from their work. AO3 prints a byline as "pseud (account)" unless
  the pseud is the account's own name, and an account name has no space or bracket, so the
  closing "(name)" can only be AO3's: `AO3AuthorRoute.fromByline` reads it, and the one route
  every way in passes through (`app/AppNavHost.kt`) uses it, opening the account with that
  pseud chosen. **Unlike iOS, Android still lets a name with no recorded account be tapped**
  (iOS opens only a link AO3 gave it); for a file imported from elsewhere that is still a
  guess, as it was before. Reverse: the two lines in the author route.
- **2026-10-11 · Favorites › Authors reads a saved AO3 work's one author from its byline when
  no account was recorded.** Accounts are kept only from today (the entry above), so in a
  library that already exists no author had one: the Authors list would have had no one to
  check, and "With new work" would have answered "No new work" about authors it never asked
  about. For a work from AO3 with one author the byline is "account" or "pseud (account)",
  so it is read from there, with no request (`accountFromAO3Byline`, `ReadingAffinities.kt`).
  Left unknown: a file from elsewhere, several authors, Anonymous, an orphaned work, and any
  work whose accounts are recorded. **This differs from iOS**, which never reads an account
  from words (it fetches each work's page to learn it), and **it widens who Android's
  newest-work round asks about** to the authors iOS's round already covers. Reverse: the
  `?: accountFromAO3Byline(work)` in `ReadingAffinities.authors`.
- **2026-10-11 · The writer's own Works page shows "12 works · 248,400 words · 3,812 kudos"
  (brief 3ch, audit A34-1).** One more read on the signed-in account's own page, after the
  header and the list: `/users/<name>/stats`, which AO3 serves to its owner only. The guard is
  in the repository (`loadOwnStats` answers null, with no request, for another author, a
  pseud, or a signed-out reader), so no screen can ask for someone else's. Silent on failure;
  read again by pull to refresh and after a confirmed write to the writer's own works (that
  last one is Android's own; iOS keeps the totals until the page is reopened). The policy's
  "Author profiles" row now says so. Reverse: the `LaunchedEffect` that calls `loadOwnStats`
  in `author/AuthorProfileScreen.kt`.
- **2026-10-11 · The Inbox's cards have Reply, Copy Link and Open Comment (audit W3, as iOS).**
  Reply opens the comment's thread and then the reply composer for that comment: the route
  that already carried "compose" now means "answer this comment" when a comment is named
  too (`CommentsViewModel.replyWhenLoaded`). The composer opens only once that comment is on
  the page; a page without it opens nothing (never a new comment on the work in its place),
  and a change of reader forgets the request. A comment whose work the Inbox does not name
  opens on AO3. Copy Link shows no alert: Android says what was copied itself. Reverse: the
  `onReply` argument in `app/AppNavHost.kt`.
- **2026-10-11 · A kept copy of a comments page says that it is one, and how old (audit W3).**
  Android showed the copy kept for offline reading as if AO3 had just served it. The copy is
  stamped when it is read (`AO3CommentThread.fetchedAt`, on the kept copy only) and the screen
  shows iOS's sentence above it. The rule from 3ce holds for comments too: **what is shown
  from memory says so.** Reverse: the `fetchedAt` block in `comments/CommentsScreen.kt`.
- **2026-10-11 · A page of the Inbox that fails does not take the shown page away (as iOS).**
  The failure is a card under the rows, naming the page, with Try Again. A session that ended
  is not a failed page: everything is cleared, as before.
- **2026-10-11 · The comments screen can be pulled to refresh (as iOS).** Android had none: new
  comments showed only after leaving the screen and coming back. The page on screen is read
  again and stays there until the answer is in (`CommentsViewModel.refresh`); a refresh
  without a connection shows the kept copy and says so. Reverse: the `KudosRefreshBox` in
  `comments/CommentsScreen.kt`.
- **2026-10-11 · A fandom's works (Browse › a fandom) can be pulled to refresh.** Checked every
  iOS screen with `.refreshable` against Android: all have a refresh box except comments
  (added the same day), this list, and Privacy & Data (iOS re-measures the storage figures on
  a pull; left, the figures are measured on opening). The page on screen is read again with
  the filters it was asked for, and stays until the answer is in. The tag-works and
  author-works screens have none either, and nothing opens them.
- **2026-10-11 · Subscribe and Unsubscribe on an author's page are native writes (brief 3ci).**
  The button opened the form's submit address in the web view, which does nothing there. It
  is now one write of AO3's own form with a fresh token, in the session the form was read in;
  an unsubscribe is confirmed first, in iOS's words; the result is shown and the header read
  again. Mute and Block are unchanged (AO3's confirm page in the web view) until their own
  step. Reverse: `onSubscription` in `author/AuthorProfileScreen.kt` back to `onOpenWeb`.
- **2026-10-11 · "Add Works" is one picker for a collection and a reading queue, and it never
  names a work Hide Mature is keeping back.** Both of Android's pickers offered every
  candidate by title (the collection's with its author too), so a Mature or Explicit work the
  Library hides or obscures was named there, and the collection's search answered for it. The
  queue's was also a bare list of titles: no search, no authors, one work per tap. Both now
  use `library/AddLibraryWorksSheet.kt` (iOS `AddLibraryWorksSheet`): iOS's words, Global
  Search's matching, several works chosen and added in the order shown, and only works that
  are `Visible` (a "Show mature" button reveals the rest, behind the same lock as elsewhere).
  A queue no longer offers a work that exists only as another queue's entry (iOS
  `appendCandidates`). **A judgment:** iOS leaves out only Hide mode's works and names the
  ones Blur mode blurs; that is treated as an iOS fault (T-392), not a pattern to copy.
  Reverse: `AddLibraryWorks.eligible` back to `!= Hidden`.
  Not changed, and noted: a collection's picker offers only kept works (`observeSavedWorks`),
  where iOS offers every Library work that is not queue-only; adding to a queue that keeps
  works offline still asks for a missing copy, as it did.
- **2026-10-11 · A collection's tile and its page say nothing about an obscured work (audit
  A38 opened).** The tile's small covers showed an obscured work's title and author; the
  page's "Hidden mature work" card still showed its fandom, author, word count and chapters.
  The tile leaves the work off (`LibraryPrivacy.nameableWorks`; its count still counts it)
  and the card shows only its two lines. The other places to check are listed in
  `briefs/A38-privacy-names.md`, none confirmed yet. Reverse: the two callers back to
  `collectionMembers.map { it.item.work }`, and the two `obscured` checks out of
  `DetailedCollectionWorkCard`.
- **2026-10-11 · Home's queue card does not name a work the privacy setting keeps back (A38,
  lead 1).** The card's face showed the queue's next work, fandom and title, with no privacy
  check at all: in Hide mode too, on the app's first screen, beside a Continue Reading card
  that said "Hidden mature work" for the same work. `HomeFacts.queueFace` now decides the
  face: a hidden work is passed over (as on the queue's page), an obscured one is the next
  work still but shown as "Hidden mature work" with no fandom and a colour that is not its
  own. The face is a required argument of `HomeQueueCard`, so a new caller cannot skip it.
  The count and the progress strip are for the whole queue, as before. Reverse:
  `queueFace(works)` in `HomeScreen.kt` back to `QueueFace(HomeFacts.upNext(works))`.
- **2026-10-11 · A collection's Reorder is off while Hide mode is hiding one of its works
  (A38).** The Reorder screen lists every work by title and author, so in Hide mode it put
  hidden works back on screen. The menu item reads "Show Mature to Reorder" and is off, as on
  a queue's page (and on the iPhone since T-394). Blur mode is unchanged and is owner
  question 23, with what a search or a filter list may say about a blurred work. Reverse:
  `hidesMature` out of `canReorder` in `CollectionDetailScreen.kt`.
- **2026-10-11 · The queue organizer's search does not answer for a work Hide mode hides
  (A38).** "Search queues, tags and works" matched a queue by any member work's title or
  author, so a hidden work's title found the queue it is in. `matchesSearch` takes a
  required `mayAnswer`; the organizer now has the privacy setting and the reveal state (it
  had neither). Blur mode is unchanged (owner question 23, which also gained Recently
  Deleted). Reverse: `{ true }` at the call in `QueueOrganizerScreen.kt`.
- **2026-10-11 · The Library's Select mode does not name an obscured work (A38).** Its rows
  listed every work by title and author, obscured ones included, while the shelf behind
  said "Hidden mature work". The row now says that and nothing else, and can still be
  selected (iOS does the same: "still blurred, so still unnamed", its audit A19-8).
  `LibraryPrivacy.shownTitle` holds the rule. Reverse: `work.title` and the author line back
  in `SelectableWorkRow`.
- **2026-10-11 · The two unreachable local lists are removed (A38).**
  `account/LocalLibraryListsScreen.kt` and its routes `local-history` and `local-favorites`
  were left in place on 2026-10-04 when the Account menu stopped linking to them. They list
  works by title with no privacy check at all, and the Library's own History and Favorites
  lists have replaced them. Removed rather than gated: nothing opens them. Reverse: revert
  the commit that names this.
- **2026-10-11 · Browse does not mark a fandom because of a work Hide mode hides (A38).**
  Browse reads the Library to star a fandom, count its downloads, say "read before" and fill
  Jump Back In. It read every work. Both screens now read `LibraryPrivacy.withoutHidden`,
  and are given the privacy setting and the reveal state (they had neither); until the
  setting has been read they assume the stricter one (`UNREAD_SETTING`). Obscure mode keeps
  its works in these marks (owner question 23). The iPhone's is T-397. Reverse: `library`
  back to the unfiltered list in `BrowseScreen.kt` and `FandomListScreen.kt`.
- **2026-10-11 · A test that hung once is made to wait on its fake (not a product fault).**
  `AO3CollectionsViewModelTest.aCollectionChangedElsewhereMakesTheListReadAgain` waited on
  the screen's state for a read that is asked for off the test's clock; a list that comes
  back the same emits nothing, so one full run in about a dozen today sat for its whole
  minute and failed the gate. It polls the fake's own record now. The gate that failed was
  not committed on; two clean full runs followed.
- **2026-10-11 · A result you already have is not marked, and no tag is suggested, because of
  a work Hide mode hides (A38).** The tag, fandom and author works screens badge an AO3
  result you have a copy of and suggest your Library's tags in their filter. They read every
  saved work. They now read `rememberShownWorks` (one helper, which Browse's two screens use
  as well); Search's and the Account lists' tag suggestions follow the same rule. iOS leaves
  a hidden work out of the pairing on its account lists. Obscure mode is unchanged (owner
  question 23). Reverse: `savedWorks` back to the unfiltered flow in the three screens.
- **2026-10-11 · Mute and Block on an author's page are native (3ci, second step).** The two
  buttons opened AO3's confirm page in the web view. They now read that page once on the tap
  and show it as a dialog in AO3's own words (heading, notice, both button labels); Yes sends
  the page's own form once, with the token it carried. iOS does the same. The read on the
  tap is one authenticated read of a page the reader asked for; the networking policy's
  "Author profiles" row says so. Reverse: `onModeration` in `author/AuthorProfileScreen.kt`
  back to `{ onOpenWeb(it.url) }`.
- **2026-10-11 · A collection whose works are all hidden says so, and its tile says "1 work"
  (found comparing empty states).** With Hide Mature in Hide mode a collection page whose
  every work is hidden showed a bare "Works 0". It now says "Mature works are hidden / Hide
  Mature is hiding every work in this collection." with "Show mature", as iOS since T-394.
  The tile's spoken label said "1 works". Of iOS's 55 empty states with a fixed title, the
  others are on Android in the same words, belong to Read Aloud, or are the reader's error
  (Android's has more: Back, Retry, Remove offline copy). One real gap is a brief: 3cj, AO3
  Preferences help. Reverse: the first `if` of the works list in `CollectionDetailScreen.kt`.
- **2026-10-11 · AO3 Preferences help is read and shown in a sheet (brief 3cj), and two
  faults beside it.** A "?" opened AO3's help page in the web view; it now reads that one
  page on the tap and shows its topics as cards, as iOS does. Sections and fields carry the
  "?" AO3 gives them (Android read only a link beside a checkbox, so the section headings
  had none). Section titles no longer carry the "?" glyph, and a select or a text field is
  called what AO3 calls it instead of its raw field name. One deviation from iOS: a section
  takes help only from its own heading or legend, not from a field inside it. Reverse: the
  `PreferenceHelpButton` calls back to `onOpenHelp(help.url)`.
- **2026-10-11 · Menus compared (iOS 61 menu and toolbar labels with a fixed title): one
  gap, brief 3ck.** Outside Read Aloud's pronunciation screen, the labels Android lacks are
  "Move to Queue" and "Download missing copies", and behind them: a selection on a queue's
  or a collection's page can only be removed on Android, and several works cannot be tagged
  at once anywhere. Written up as `briefs/3ck-selection-actions.md` (P2), not built in the
  tick that found it.
- **2026-10-11 · Several works can be tagged at once (3ck, part 1).** The Library's Actions
  has Tag, opening iOS's bulk tag sheet: each of your tags is on every selected work, on
  some, or on none; a tap puts it on the rest, or takes it off them all when it was on all.
  The sheet is the queues' tag sheet made common (`SharedTagSheet`), not a second one. The
  queue's and the collection's Select mode still offer only Remove: parts 2 and 3. Reverse:
  the "Tag" item out of `LibrarySelectionActionBar`.
- **2026-10-11 · A selection on a queue's page or a collection's page can do what iOS's can
  (3ck, parts 2 and 3).** `library/ScopedSelectionBar.kt`: a queue's page has Download, Move
  to, Tag, Remove and More; a collection's has Remove from Collection, Actions and Done.
  Move to adds each work to the other queue and then takes it out of this one (a work
  already there simply leaves; iOS, whose picker cannot report a choice, compares counts).
  The bar is an opaque surface: over glass its labels sat on the rows behind. Reverse: the
  two `ScopedSelectionBar` calls out of `QueuePageScreen.kt` and `CollectionDetailScreen.kt`.
- **2026-10-11 · Settings compared (iOS `Settings/` and `App/`: 133 labels with a fixed
  title; 26 not on Android by their words): nothing to change.** The earlier comparisons
  had read only `Features/` and `UIComponents/`; re-run over the other folders they add one
  item, below. What the 26 are: backup, import, font and sync-folder failures that Android
  reports in its own words on the page instead of in an alert (ten); the "Sync Details"
  screen, which iOS's own comment calls development diagnostics (Android shows the last
  sync, the last error and merged conflicts on the page) (eleven); "Scan a QR Code" (Android
  is QR-generate-only by an earlier decision); the segmented control's "When locked" name
  and "Require Face ID" for "Require biometric"; and **"Add Saved Works to Saved for
  Later"**, an iOS tool for works saved before that queue existed, which fetches a copy of
  each. Not ported: Android has no such legacy, and a bulk fetch should be asked for. If the
  owner wants it, it is a brief of its own.
- **2026-10-11 · Three spoken hints from audit W3 (rows 17 to 19) are click labels on
  Android.** The page button says "double-tap to open the page picker", "Show n more
  replies" says "expand nested replies", and the deep-thread row says "open the rest of this
  thread" (not "on the AO3 website": Android opens it in the app). Rows 20 and 21 need
  nothing. W3 is closed. Reverse: the three `onClick(label = …)` / `onClickLabel`.
- **2026-10-11 · Largest text on the screens audit A35 had left: one iOS fix (T-398), one
  Android brief (3cl).** On iOS a category's fandom list was unreadable at the
  accessibility sizes and Browse's fandom chips did not grow: fixed in T-398. Android at
  2.0× was looked at for the same screens and reads well. Putting the two fandom lists side
  by side showed Android's is not the redesign's (a titled bar, plain rows, a switch for a
  chip, and a fandom's "(TV)" qualifier not drawn): `briefs/3cl-fandom-list.md`.
- **2026-10-11 · A category's fandom list is the redesign's (brief 3cl).** A fandom's
  qualifier ("(TV)") and its other names are drawn under its title; the titled bar is gone
  (floating chrome, the header block is the title); rows are cards; "Group variants" is a
  chip in the rail; the search field is the app's glass field, kept at the top; "Open on
  AO3" is only on the error page, as on iOS; works counts use the app's face with tabular
  figures. Reverse: the commit that names 3cl.
- **2026-10-11 · Six pages beside the iPhone's (3cm).** Inbox: a name is no longer held to
  half its row, "User" is no longer a chip (iOS: only Author, Me and Guest say something),
  and a commenter with no icon is their first letter (guests keep the silhouette), in
  threads too. AO3 Preferences: sections fold (for the visit only) and the Account rows have
  icons. Queues: the glass search field. Collections: the header lines up with its tiles.
  Left: AO3 collections' card tint and glyph. Reverse: the commit that names 3cm.
- **2026-10-11 · An AO3 collection's card is its own (3cm, second commit).** Hue from the
  title (iOS), a box glyph, a maintainer's name opens their profile (a page the reader opens
  by a tap, as a work's byline does), and the "by" line only when it adds someone to the
  kicker. Reverse: the commit that names it.
- **2026-10-11 · AO3 results are drawn as the iPhone's ledger card (3cn, step 1).** iOS
  has two forms of its result card; Android had only the older. `SensitiveWorkRow` gains
  `ledger`: fandom as a kicker, the tray of four symbols, figures in words, the date. Used
  where iOS always uses it and Android had the screen ready: Search results, a fandom's
  works, a tag's works. The owner's line (layout, content and order follow iOS; chrome is
  Android's) covers it: the ripple, the checkbox and the overflow menu stay Material. The
  date stays as AO3 prints it. Reverse: pass `ledger = false` at the three call sites.
- **2026-10-11 · Marked for Later, Subscriptions and an AO3 collection's works draw the
  ledger card (3cn, step 2)**, as iOS always does there; a work also in the Library draws
  the same body (iOS draws its library row). The footer under a subscribed work wraps at
  the large text sizes. Reverse: `ledger = true` at three call sites.
- **2026-10-11 · A bookmark is one card (3co, step 1).** A work not in the Library draws
  iOS's bookmark card (Rec and Private by the kicker, the note and tags inside, the day it
  was bookmarked, no kudos or hits); a saved work draws its own row with the same pieces
  under it. **A blurred work's bookmark note and tags are not drawn until it is revealed**
  (they were; iOS never drew them). Reverse: the commit that names 3co step 1, but not the
  blur rule.
- **2026-10-11 · History is grouped by time, with its visit line and Delete inside the
  card (3co, step 2).** Groups follow AO3's own order (iOS's rule, ported with its tests).
  Delete stays a button (iOS: a swipe) and is offered only where AO3 gave a link, and not
  on a blurred row. A dialog nothing could open ("Clear your entire history?") is removed:
  its confirm did not write to AO3. Reverse: the commit that names 3co step 2.
- **2026-10-11 · History, Bookmarks and the account's works lists choose a Layout (3co,
  step 3).** Detailed or Ledger, in the More menu as Home's section pages do it, kept as
  iOS's `account.displayMode` in its own small preferences file (no backup or settings
  change). Android opens on Ledger: iOS opens on Compact, which Android has not built and
  does not offer. Whether to open on Compact once it exists is the owner's. Reverse: the
  commit that names 3co step 3.
- **2026-10-11 · Layout choices open and are kept as on iOS (3co, step 4).** The author's
  profile opens on the ledger; the author's, a collection's and the account lists' choices
  are kept between launches in `layout-choices` under iOS's names. A collection's Detailed
  and Ledger were swapped and are put right, so a collection opens on the full card. The
  detailed card carries the symbols tray. Reverse: the commit that names 3co step 4.
- **2026-10-11 · One ledger row for saved works (3co, step 5).** A collection's Ledger draws
  the shared `WorkLedgerRow` (ring, kicker, tray) and its own copy is gone; that row's tray
  is the tray of four symbols, not four letters. Reverse: the commit that names 3co step 5.
- **2026-10-11 · The overflow button is "More" on every list (3co's last small item).** iOS's
  shared list menu says "More"; a work's page and the reader say "More actions". Android
  said "More actions" on five lists, "Menu" on an author's profile and "More options" on
  the Library. Seven screens changed; a work's page keeps "More actions".
- **2026-10-11 · Compact is the account lists' third Layout (3co, step 6).** Covers under
  each heading in History and on the works lists; Bookmarks keeps its cards (iOS does). A
  work not in the Library gets a cover drawn from AO3's blurb through a display-only
  `SavedWork`. Android still opens on Ledger; opening on Compact, as iOS does, is the
  owner's to say. Reverse: remove `Compact` from `AccountDisplayMode`.
- **2026-10-11 · Clear History is native on Android (3co, step 7).** iOS's write, field for
  field: AO3's confirm page for the token, one POST to `readings/clear`, never retried,
  "cleared" only on AO3's own evidence, the list emptied on the device without a second
  read. Fixtures and the demo only; owed a second review. The networking policy gains its
  "Reading history writes" row. Reverse: the commit that names 3co step 7.
- **2026-10-11 · The detailed card's tray is an AO3 work's only, and its rating chip is a
  letter (3cp).** iOS draws the tray on `AO3WorkRow`'s card and not on a saved work's; 3co
  step 4 had given it to both. The rating chip says "G", "T", "M", "E" or "NR", as iOS's
  does, so the four chips fit one line; the full rating is spoken. Reverse: the commit that
  names 3cp.
- **2026-10-11 · A work's page names the action and counts Saved for Later (3cp, second
  commit).** The button for a finished work says "Mark as Still Reading", as iOS; "My copy"
  counts Saved for Later as a queue, as iOS. Reverse: the commit that names them.
- **2026-10-11 · A saved work's detailed card follows iOS `WorkRow`, an AO3 work's follows
  `AO3WorkRow` (3cp, third commit).** Saved: every fandom on the line, the unfold only for
  a long summary or tags, no warnings group when unfolded. AO3: one fandom and a count,
  the unfold for those and warnings too, the symbols tray. Android had one rule for both.
  Reverse: the commit that names it.
- **2026-10-11 · The finished toggle has one wording (3cp, fourth commit).** "Mark as
  Finished" / "Mark as Still Reading", from `finishedActionLabel`, as iOS's
  `WorkActionLabels.finished`. Six wordings across nine places are gone.
- **2026-10-12 · The tab bar and chrome buttons take the colour of the screen on top
  (owner, 2026-10-11; iOS T-399).** Android's shell draws its own chrome and tab bar under
  the page's wash palette (`LocalShellWashes.page`), where it had kept the app accent "as
  on iOS". A page with no wash keeps the app accent. The page's content is untouched.
  Reverse: the provider around `MainScaffold`'s outer box.
- **2026-10-12 · The symbols tray says what it does not know as iOS does (3cp, fifth
  commit).** No rating: no tile. No category: the two figures. Unknown completion: "?".
  And the Account hub's Collections and Series have their own glyphs. Reverse: the commit
  that names them.
- **2026-10-12 · The writer's own pages (3cq).** A writer's kudos, comments and hits are one
  strip inside the ledger card and are left off its line (iOS `showsPerformance`); the
  dashboard knows it is the reader's own; "+" starts a work from the writer's Works and
  Dashboard; the dashboard's fandoms carry their counts and its sections their "See all"
  links. Reverse: the commit that names 3cq.
- **2026-10-12 · The Series row and the form's choices (3cr).** An author page opens on the
  tab it was asked for (the account's Series row opened Works). A form row that opens a
  choice draws its value in the accent with "⌄" (`showsChoice`), Android's mark for iOS's
  picker; a required mark is in the accent. Reverse: the commit that names 3cr.
- **2026-10-12 · The series card (3cs).** Whether a series is complete follows iOS's rule
  ("Series Complete: No" was read as complete). The card says Complete and Restricted in
  pills, prints the whole word count and the bookmarks, and the figure reader never takes
  a label. Reverse: the commit that names 3cs.
- **2026-10-12 · Restarts of the activity (3ct).** The activity handles `uiMode`,
  `fontScale`, `keyboard` and `navigation` itself, so the phone switching to dark, a
  text-size change or a keyboard being connected no longer restarts it (what was being
  typed was lost, and the reader crashed). Where it does restart (a language change, the
  return after the process was killed), Readium's reader fragment is not rebuilt from
  saved state: `ReaderFragmentRestore`. A launching file is offered for import on a fresh
  start only. Reverse: the commit that names 3ct.
- **2026-10-12 · Recovery through a kill (3cu).** A form's long text comes back through
  the app being killed in the background (seen); its short fields do not, on either app,
  by the editor's design. Left as designed and put to the owner (question 26). The drafts
  note says recovery copies stay on the device, as iOS. Reverse: the commit that names 3cu.
- **2026-10-12 · Back from a kill (3cv).** The app draws no page until the saved AO3
  session has been read back (bounded at two seconds), so a page that returns with the app
  never asks AO3 as a signed-out reader. The works that open pages were given, and the
  page of the search on screen, are saved state; the search is read once more on return,
  as every restored page reads its own address. Reverse: `869eb8c0` and the commit that
  names 3cv.
- **2026-10-12 · A work reached by its id (3cw).** The work page's own heading, byline and
  summary are read when a page has only the work's id, and the reader is no longer told
  what the parser lacks. Reverse: the commit that names 3cw.
- **2026-10-12 · Edit tags' chips (3cx).** A tag chip is drawn at its own size inside its
  48 dp touch target, with "Add" after the last chip, as iOS; the layout's allowance for
  the chip's mark grows with the text size. Reverse: the commit that names 3cx.
- **2026-10-12 · The tag editor's pills (3cy).** A chosen tag's pill is drawn at its own
  height inside its 48 dp touch and drag target, as 3cx did for Edit tags' chips.
  Reverse: the commit that names 3cy.
- **2026-10-12 · The chapter form's Post rows (3cz).** The chapter form draws its Post
  rows as the work form does (a mark, green for the step that sends), and its publication
  date as a choice. iOS's demo answers the chapter and series pages from copies of
  Android's demo pages (T-400). Reverse: the commit that names 3cz; iOS T-400.
- **2026-10-12 · A series's page (3da).** The page opens with the series's own card, read
  from the series's page (creator, description, figures, complete, bookmarks, updated),
  under the page's title. The standard AO3 work card closes with the work's date, as the
  ledger card and iOS's standard card do. Reverse: the commit that names 3da.
- **2026-10-12 · The series form's title (3db).** Marked required ("Title ∗"), as iOS and
  as the work form. Reverse: the commit that names 3db.
- **2026-10-12 · Challenge pages (3dc).** Each challenge page's main action is one filled
  button (`ChallengePrimaryAction`); Sign-ups and Assignments filter with the segmented
  control; Edit collection labels its sections as the other AO3 forms do. Reverse: the
  commit that names 3dc.
- **2026-10-12 · Edit collection's Save (3dd).** A filled button, as iOS and as the
  challenge pages' actions. Reverse: the commit that names 3dd.
- **2026-10-12 · Comments (3de).** The header's creators are separated by commas; "Latest"
  is the newest comment and says how long ago; a guest has a "Guest" pill in the thread;
  the chapter pill drops AO3's "on"; the composer's count has its thousands separator.
  Reverse: the commit that names 3de.
- **2026-10-12 · The order of comments (3df).** Comments open newest first, from the
  work's last page (one read of page 1 for the count, one of the last page), as iOS.
  Pages read for a comments screen are kept in memory by that screen for five minutes
  each, one reader's, and a write empties them (`docs/AO3_NETWORKING_POLICY.md`,
  "Comments"). Reverse: the commit that names 3df.
- **2026-10-12 · A work page's byline (3dg).** A name that opens its author is drawn in the
  page's accent, as iOS. Reverse: the commit that names 3dg.
- **2026-10-12 · Settings' pages and the top row (3dh).** Where one route holds several
  pages (Settings), each page is named to the shell so its "top row scrolled away" is its
  own (`PushedShellChrome.scrollKey`): a page opened from a scrolled one has its back
  button. The list calls the privacy mode "Blur". Reverse: the commit that names 3dh.
- **2026-10-12 · Sizes, Listening's speeds, Insights' figures (3di).** A size is written one
  way ("8 KB", `LocalStorageFootprint.formatted`); Listening's three speeds sit side by
  side; Insights' big figures are in the page's face. "Words per hour" counts a work's
  whole length for every sitting on both apps: recorded, not changed (owner question 27).
  Reverse: the commit that names 3di.
- **2026-10-12 · Another author's page (3dj).** A tapped name opens the account its link
  names, never an account of the name's words. Addresses read from a page are decoded
  before they are kept. A bookmark's badges are drawn whether or not the work names a
  fandom. AO3's formatted words are drawn with `AO3RichText`, which keeps plain formatting
  and http/https links only. Reverse: the commit that names 3dj.
- **2026-10-12 · The reader's bar buttons are the app's own (3dk, iOS T-403; owner).** The
  reader's back button and fan menu button sit where every other page's bar buttons sit,
  with the same mark at the same size and strength. On Android they keep a round backing,
  because they float over the page's text. Reverse: the commits that name 3dk and T-403.
- **2026-10-12 · The reader's sheets share one header and one kind of control (3dl).** Each
  has a title and a Done tick in the palette's accent; a choice between views is the app's
  segmented control, not Material's tabs. In that control a one-word label is never broken
  across lines. Reverse: the commit that names 3dl.
- **2026-10-14 · Read Aloud uses the device's own voice until the Kokoro pack is installed
  (3dm).** As iOS's Automatic engine. Only an on-device voice is used, never one that needs the
  network, so the work's text stays on the phone; with none the reader offers the pack as
  before. The pack's download moved from the refusal banner to a row in the reader's Display &
  Themes: the same user-started download from the reader, no new network use. Reverse: the
  commit that names 3dm.
- **2026-10-14 · Queues, Collections, More on AO3 (3dn).** More on AO3's rows carry iOS's
  glyphs as Material outlined icons; a mosaic tile's title may shrink to 85% as iOS's; every
  size in the app is written by `LocalStorageFootprint.formatted`. Reverse: the commit that
  names 3dn.
- **2026-10-14 · Author links and My copy (3do).** On a work's page an author's name is a link
  only when AO3 linked it to an account, as iOS; otherwise it is plain text. My copy shows
  Preservation for a kept work and iOS's origin sentences. Reverse: the commit that names 3do.
- **2026-10-14 · Library dashboard (3dp).** An empty section's line starts with the section's
  glyph, as iOS. Reverse: the commit that names 3dp.
- **2026-10-14 · Browse sees the Library; counts as iOS writes them (3dq, iOS T-405).** Browse
  reads the Library as state, so its downloaded counts, read marks and Jump Back In follow it.
  Its panels drop the Mac-only "Recently read" block and carry iOS's figure glyphs. Every
  compact count is written as Foundation's compact notation. On iOS, Search's empty prompt
  takes the theme's backdrop. Reverse: the commits that name 3dq and T-405.
- **2026-10-14 · Two stand-ins replaced (3dr).** The Settings hub names the chosen font; the
  author hero knows your own page. Reverse: the commit that names 3dr.
- **2026-10-14 · Dead account-list code removed (3ds).** Five unused functions in
  `AccountScreen.kt`, whose cards had do-nothing menu actions. Reverse: the commit that names
  3ds.
- **2026-10-14 · One avatar view (3dt).** Account and author pages share `AO3AuthorAvatar`,
  whose fallback is iOS's person glyph, not the Kudos mark or a blank square. Reverse: the
  commit that names 3dt.
- **2026-10-14 · Collection item cards in their collection's colour (3du; iOS T-406).** As
  iOS's `subjectCard`. On iOS the demo answers "Your items". Reverse: the commits that name
  3du and T-406.
- **2026-10-14 · A fandom's works page takes the results' own head (3dv).** As iOS's Browse
  and as Search: spec 1k's page head with its sort, not the older card under a second
  header. Reverse: the commit that names 3dv.
- **2026-10-14 · Settings declares its own header (3dw).** Fixes 3dh's regression, where
  Settings first opened under a plain top bar. Reverse: the commit that names 3dw.
- **2026-10-14 · The filter panel's menus look like choices (3dx).** As iOS's pickers, with
  `showsChoice`; Save Search has iOS's bookmark glyph. Reverse: the commit that names 3dx.
- **2026-10-14 · A queue's description is written as it is typed (3dy).** It was lost when
  the page was left without the field losing focus. The New Queue sheet loses its
  Description field (iOS's has none; the details page edits it) and picks tags from one
  row with a "+ New tag" chip. Reverse: the commit that names 3dy.
- **2026-10-14 · Only Cancel throws a typed note away (3dz, both apps).** The note editor
  keeps a changed note when it is swiped away or closed with Back; dismissing keeps the
  colour as iOS's swipe did. Android's Add note pop-up ignores a tap beside it while a note
  is typed. Reverse: the commits that name 3dz and T-407.
- **2026-10-14 · Read Aloud says what iOS's says (3ea).** Paragraphs kept apart; AO3's
  labels and closing plug dropped; a link said as its site (iOS's `KokoroBoilerplateFilter`).
  Reverse: `speakableParagraphs` in `reader/ReaderContentText.kt`.
- **2026-10-14 · Links in a work open in the app; a tag's works page is the works page
  (3eb, 3ec).** An AO3 author, work or tag tapped in a work's text opens its page in the
  app, as iOS; the tag opens `FandomWorksScreen(isTag = true)` and `TagWorksScreen` is
  removed. Reverse: the commits that name 3eb and 3ec.
- **2026-10-14 · Read Aloud's "Read author's notes" (3ee).** iOS's switch and rule, in
  Settings › Listening only (the reader's sheet waits on question 12). Reverses part of 3ak's
  "left out". Reverse: the commit that names 3ee.
- **2026-10-14 · Codex's A49 findings F5, F6, F7, F8, F12, F13 fixed (3ef).** Each read against
  the code first; all six real. Reverse: the commit that names 3ef.
- **2026-10-14 · Codex's A49 findings F1 to F4 fixed (3eg).** Read Aloud: the speech engine
  query in the manifest; speech handed over under Stop's lock; one engine per reading;
  the device's voice when the pack will not open. Reverse: the commit that names 3eg.
- **2026-10-14 · A49 F9 and F11 fixed; F10 kept as iOS (3eh).** A name two accounts share is
  not a link; Contents' percentages off the main thread; the compact "50k+ words" stays, as
  iOS's spec 1ay. Reverse: the commit that names 3eh.
- **2026-10-15 · A50 F1, F8, F9, F10, F11 fixed (3ei).** OkHttp no longer resends requests
  itself (a POST could reach AO3 twice); comment edits go to the comment; comment writes stay
  in their session; collection switches save onto the current form; the comment field is
  read-only while sending. Reverse: the commit that names 3ei.
- **2026-10-15 · The Authors round reads in the foreground only, from printed accounts only
  (3ej, A50 F4 to F6).** It stops in the background; a bare byline name is no longer read as
  an account (narrows 3b: iOS never does); a stale cached page is not an answer. Reverse: the
  commit that names 3ej.
- **2026-10-15 · A50 F2 and F3 fixed; F7 left open (3ek).** The subscribe button waits for the
  page to reload; a cleared history stays cleared on every page. Reverse: the commit that
  names 3ek.
- **2026-10-15 · Edit multiple works reads each work's tags once (3em, A37 F5).** The changes
  are merged into the form that is sent. Reverse: the commit that names 3em.
- **2026-10-15 · A lost answer after a collection write says it may have landed (3en, A37
  F10).** Not "try again". Goes further than iOS's generic failure, against a repeat write.
  Reverse: the commit that names 3en.
- **2026-10-15 · A comments page without AO3's list is an error (3el, A50 F7, Codex).** As
  iOS: a work's or chapter's page needs `#comments_placeholder > ol.thread`; a page without
  it shows the error and Retry, not "No Comments Yet". Reverse: the commit that names 3el.
- **2026-10-15 · The page cache after writes, as iOS (3eo, A37 F1, F2, F4).** A removal stops
  only reads of the pages it removed; an own-work write forgets the writer's pages; a series
  write forgets the series and its creator's lists. Reverse: the commit that names 3eo.
- **2026-10-15 · A37 F8, F9, F11, F12 fixed (3ep).** Assignments write only from cleanly read
  lists and ask for the due date again on Refresh; a series keeps its page when the next fails;
  the own author page's menus take the app's colours. Reverse: the commit that names 3ep.
- **2026-10-15 · An author's Works can be narrowed to one fandom, as iOS (3eq).** The Fandom
  chip row on the plain Works list. Reverse: the commit that names 3eq.
- **2026-10-15 · Challenges compared with iOS (3er).** The same; Challenge Settings' footnote
  has iOS's whole sentence again. Reverse: the commit that names 3er.
- **2026-10-15 · Tag set and prompt meme compared with iOS (3es).** The same; a prompt's tags
  are a caption line, not a chip. Reverse: the commit that names 3es.
- **2026-10-15 · Queue rows show a chevron (3eu).** As iOS's list rows and Android's other
  opening rows. A37 F3 left open (shared with iOS). Reverse: the commit that names 3eu.
- **2026-10-15 · A51 fixed: writes are one-shot to OkHttp; comment delete at the comment;
  and four screen-state fixes (3ev).** F3 not a fault (disclosed); F4 and F6 left. Reverse:
  the commit that names 3ev.
- **2026-10-15 · "No new work" names only the authors Kudos could check (3ew, T-410; A51 F6).**
  Both apps. Reverse: the commits that name 3ew and T-410.
- **2026-10-15 · The shared GET coalescer stops a read nobody waits for, and a reload after a
  write never joins a read begun before it (3ex; A51 F4, A37 F3).** Codex wrote it, Claude
  reviewed and gated it. The last waiter to leave cancels the shared request before it is
  sent or retried; a cache-bypassing read (the reload after a write) runs on its own. Left,
  narrower: an ordinary read opened while a pre-write GET of the same page is in flight still
  joins it (rare; a later reload corrects it). iOS: its `RequestCoalescer` already counts
  waiters (F4 was Android catching up); a reload joining an earlier GET is a documented
  limit there (`AO3Client.swift`, "Not atomic with the fetch that follows it"); not changed.
  Reverse: the commit that names 3ex.
- **2026-10-15 · Save Search opens over the filter sheet, on both apps (3ey, T-412).** iPhone:
  the save sheet was attached under the filter sheet and never opened. Android: it opened by
  closing the filter sheet, which skipped dropping unapplied edits (A20-3), so the next page
  tap ran them as a new search. Now both open Save over the filters and return to them.
  Reverse: the commits that name 3ey and T-412.
- **2026-10-15 · A52's four small ones fixed (3ez):** a blank reading locator never overwrites
  the saved place; a work's stored AO3 ID identifies it in a restore (as iOS); an export
  refuses what its own import would refuse; a Replace that fails part-way says so and names the
  safety copy. Two kept by design and recorded in A52's triage: every deletion keeps its
  suppressors (5c F6), and content clocks are clamped to the archive's export date. A failed
  Replace's rollback and naming what an export left out are brief 3fa. Reverse: the commit
  that names 3ez.
- **2026-10-15 · The account lists open on Compact, and Marked for Later says when it synced
  (3fb), as iOS.** Android kept Ledger as the first layout from before Compact was built
  (3co step 6); iOS opens on Compact. Marked for Later's subtitle gains iOS's "· synced just
  now / N min ago" (stamped when a page arrives, read again each minute, not stored), and its
  All list is headed "Everything else" even when nothing is updated. A choice already made is
  kept. Reverse: the commit that names 3fb.
- **2026-10-15 · A failed Replace leaves the library as it was; an export names the books it
  left out (3fa, A52 #1 and #8; Codex, reviewed and gated by Claude).** Replace runs in one
  Room transaction; before a file is overwritten it is moved aside under a fixed sibling name
  (`.kudos-replace-undo`; Android refuses hard links, seen on the emulator) and moved back on
  failure; launch and every Replace first repair asides a crash left. Merge and Reconcile keep
  their partial apply (sync relies on its pending-file flags). The export says "N books were
  left out because their files are missing: …". No schema or archive change. Reverse: the
  commit that names 3fa.
- **2026-10-15 · A collection's challenge pages take its colour; A53's two Android fixes (3fc).**
  Sign-ups, Assignments, a sign-up and Prompt Meme drew in the theme's scope colour; iOS draws
  them in the collection's (`CoverArt.workHue` of its title, else its slug), as Android's
  Moderation and Challenge already did. `KudosTokens.scopePaletteOverride` lets a screen hand its
  colour to everything under it. A53 F1: a Replace that could not put every file back says so
  (`BackupError.ReplaceNotUndone`) instead of "not replaced". A53 F2: Marked for Later's "synced"
  is stamped when AO3's answer is accepted (`Loaded.fetchedAt`), not when drawn. Reverse: the
  commit that names 3fc.
- **2026-10-15 · Search's and Browse's filter sheets open at half height (3fe), as iOS** (spec
  1ao, `detents: [.medium, .large]`); drag for the rest. Android opened them full height, kept
  from the first filter sheet (epic 4, July). The author's and the account lists' sheets keep
  full height, as iOS's. Reverse: `opensHalfHeight = false` at the two call sites.
- **2026-10-15 · A54's six parsing faults fixed (3fd; Codex, reviewed and gated by Claude).**
  Sign-ups join every page of Complete, Open and Defaults before showing who is matched (a
  recipient matched on page 2 showed UNMATCHED); like iOS, uncapped, sequential and paced, only
  when an owner or maintainer opens the screen, any failure leaving the match unknown (written
  into the networking policy). A collection's absent totals stay unknown, not 0, and the strip
  leaves them out as iOS's `statCells`. Subscription bylines keep their accounts; an empty
  preview is an error; a deleted work keeps its last visit; AO3 Preferences lists the account
  links AO3 serves (opened only in the in-app view's AO3 allow-list). Reverse: the commit
  that names 3fd.
- **2026-10-15 · A private bookmark stays private; a single-pseud comment carries its pseud
  (3ff; A55 #1, #3).** The bookmark form's private and rec flags are read from the checkbox,
  not the hidden "0" AO3 writes before it (a private bookmark read as public, and an edit saved
  it public). The posting pseud is read from a hidden input first, as iOS's
  `parseDefaultPseudID`. Tests port iOS's on its own fixture. Reverse: the commit that names 3ff.
- **2026-10-15 · A55's write and request faults fixed (3fg; Codex, reviewed and gated by
  Claude).** Marked for Later's Unmark really unmarks on AO3 (a fenced token read, one
  `mark_as_read` PATCH-override POST, the row removed only on AO3's notice; it was only hidden on
  screen while the page said it was removed on AO3). A comment cannot go twice: admission is
  synchronous, and a lost answer is verified (never reposted on its own) across reopening, as
  iOS's `CommentSubmissionTests`. An unnamed session's drafts move to the verified account; a
  post clears only its own chapter's drafts. Challenge schedules are not re-sent without a
  timezone; a saved search keeps an unknown language's ID; closing filters during the first
  load drops unapplied edits; the URL resolver (no live caller) takes iOS's trust rules. One
  of Codex's tests set its fake AO3's answer too early (the form read got the maintenance page
  and nothing posted); Claude moved the switch to the POST. Reverse: the commit that names 3fg.
- **2026-10-15 · Delete Forever spares what was restored meanwhile; the launch sweeps wait for
  the persistence gate (3fh; A56 #1, #2).** Hard deletes take `onlyIfStillDeleted`; Recently
  Deleted, the expiry sweeps and `hardDeleteAllPending` pass `true`, so a stale confirmation or
  expiry snapshot can no longer erase a live work with its EPUB, place and marks (iOS
  `deletePermanentlyLeavesALiveWorkCollectionAndQueueAlone`). The launch sweeps run under the
  persistence gate, after any restore or sync holding it. Reverse: the commit that names 3fh.
- **2026-10-15 · A56's Library, queue and reading-record faults fixed (3fi, 3fi-2; Codex,
  reviewed and gated by Claude).** Remove from Queue keeps the work (Remove from Later and
  Remove from All Queues may still send a queue-only work to Recently Deleted, as iOS). Opening,
  queueing or re-importing a work in Recently Deleted revives it instead of making a second
  copy (a source-less EPUB matched by title, author and size, as iOS); `/downloads/<id>` and
  `/works/<id>` match both ways. Deleting a queue tombstones its memberships and normalizes its
  works; a collection's membership clock (already stored) is stamped on add and remove, not on
  rename; adding to a collection stamps the work too. Deleting a last copy AO3 no longer has
  says so. Collection pickers offer reading and history works; colliding tag renames merge
  everywhere; only History and Favorites default to ledger rows. 3fi first broke ten tests: its
  normalization read "no file probe given" as "file missing" and cleared `hasEpub`; 3fi-2 reads
  it as unknown. No schema or backup-format change. Reverse: the commit that names 3fi.
- **2026-10-15 · A permanent delete removes an imported original; a restore cannot switch off
  the delete confirmation (3fj; A57).** `hardDelete` (when it removes the work) now also deletes
  the work's preserved original and conversion record, as iOS
  (`permanentDeletionRemovesThePreservedOriginal`); they were left behind, unreachable. The
  settings restore treats `confirmBeforeDelete` as tighten-only, like the privacy gates (iOS
  `aRestoreCannotRelaxPrivacyGates`). A57's other faults are brief 3fk; the document
  converter's gaps (imported HTML, text and PDF become one chapter without metadata) are a
  feature, recorded. Reverse: the commit that names 3fj.
- **2026-10-15 · The client requests only HTTPS AO3 hosts; unreadable results are errors; only
  identity cookies are kept; a rotated session cookie replaces the old one (3fk part 1; A57;
  Codex, reviewed and gated by Claude).** `OkHttpAO3Client` refuses any other host before
  coalescing, pacing or a call (injectable for tests on local servers); the session cookie
  was already AO3-only. A works list or account bookmarks page whose blurbs exist but none
  parse fails closed, as iOS; the account parser keeps raising its own error. Only
  `_otwarchive_session` and `user_credentials` are kept, as iOS. Found by Codex's new test: the
  session merge keyed cookies by their domain as written, so a web-login cookie
  (`.archiveofourown.org`) and AO3's rotation (`archiveofourown.org`) were kept side by side and
  the stale one sent first; the key now drops the leading dot. **SameSite is not stored:**
  WebView treats a cookie without it as Lax, iOS's value; the session format is unchanged.
  Reverse: the commit that names 3fk.
- **2026-10-15 · Sign-out clears the WebView's cookies; hostile EPUBs are refused at import;
  blank usernames build no address; availability as iOS (3fk-2; A57 items 4 to 8; Codex,
  reviewed and gated by Claude).** Sign-out clears every WebView cookie (`removeAllCookies`;
  the in-app view only loads AO3), where expiring root cookies missed path- and
  subdomain-scoped ones. The EPUB preflight rejects unsafe or duplicate entry names, oversize
  and implausible-ratio entries and an aggregate over budget, at iOS's `MiniZip.Limits.epub`
  numbers. A one-work refresh's 404 marks the last copy and keeps a recovered work ID; an
  inconclusive sweep check counts as checked. A work page's published, updated and status
  fields are read; gift recipients are not (Android shows none). Four of Codex's tests compared
  a microsecond `dateAdded` with Room's milliseconds; fixed. Reverse: the commit that names 3fk-2.
- **2026-10-15 · A58's reader, Browse and work-detail faults fixed (3fl; Codex, reviewed and
  gated by Claude).** Browse's "All N tags" opens the family's union (each sibling's filter ID
  read once, paced and cached, as iOS's `fandomFilterID`, then one `filter_ids:(A OR B)`
  search; an unresolved sibling is an error, not a partial list). "Last Copy" only with a local
  EPUB; fresh remote figures win on Work Detail; a nested TOC keeps its outer title and the
  chapter total; blank or tiny page samples publish nothing; a non-AO3 import without a status
  shows Unknown; Comments fall back to chapter 1 as iOS's `ao3StoryChapter` (one older Android
  test asserting the opposite was corrected); removing a source-less work closes its page; the
  comment budget counts code points; queue and collection labels name their memberships; a
  malformed chapter falls back to 1; series creators match as iOS; detail dates as iOS. Two
  ledger rows took `Boolean` where completion is now `Boolean?` (fixed). A58's colour, skeleton,
  italic, speech-chunking and media-control items are left. Reverse: the commit that names 3fl.
- **2026-10-15 · A59's account-session faults, first four (Claude; Codex at its usage limit).**
  A comment that succeeds after the account changed touches nothing, the sending account's
  draft included, as iOS's `staleSuccessfulSubmitCannotClearOrCloseTheNewAccountsComposer`
  (the draft stays until that account reopens the work; AO3 has the comment). The Inbox's lit
  pill and filter mark read the form of the page on screen, not the filter asked for, so a
  failed request leaves the pill of the rows shown. Subscription watermarks skip a row with no
  chapter count instead of recording zero. History's Clear confirmation and "cleared" state are
  keyed to the session. A59 #1, #3, #4 and the remaining missing rows go to brief 3fm.
  Reverse: the commit that names A59.
- **2026-10-15 · Comments opened from the Inbox belong to that session; a signed-in comment read
  is never retried publicly (A59 #1; Claude).** The Inbox's (and the account hub's) links to
  Comments carry the session generation they were opened under; when it has ended the screen
  closes and reads nothing, as iOS's `belongsToCurrentSession` dismisses. Other ways into
  Comments (reader, work page) are not fenced, as iOS. Signed in, a comments page is read as the
  account or not at all: a failed read shows the failure (or this account's kept copy when AO3
  could not be reached) instead of asking again publicly, as iOS's
  `missingApplicableAuthCookieNeverFallsBackToAnonymousReads`. Signed out, reads stay public.
  Two older tests modelled a signed-out reader with the fake's default signed-in name; they now
  have none. Reverse: the commit that names A59 #1.
- **2026-10-15 · Account-list counts belong to a session; a Bookmarks page is a floor (A59 #4;
  Claude).** Counts are kept under the name and session generation, as iOS's
  `sessionScopedCacheScope`, so signing out and in again (even under the same name) starts with
  no counts. One page of Bookmarks records "at least N", as iOS's `mayOmitRows`, because the
  page keeps only work bookmarks; it no longer replaces an exact figure. The list screen's
  second, duplicate recording of the same count was removed (the repository records it).
  Seeding counts from the dashboard nav (iOS `record(dashboardActions:)`) goes to brief 3fm.
  Reverse: the commit that names A59 #4.
- **2026-10-15 · The comment tray writes tags as the chapter editor does (A59 #3; Claude).** As
  iOS, where both surfaces go through `AO3Markup.splice`, the comment tray now uses Android's
  existing `WritingMarkup.insertion`: the divider is `<hr>` after the selected words on its own
  line (it was `<hr />` before them), a list makes one `<li>` per non-empty line (one `<li>`
  wrapped everything), the spoiler's caret goes in an empty summary (it wrote "Spoiler"), and a
  link puts the caret inside the empty href with the words as its text. The tray prints
  "h1–h6" under Heading and "a href" under Link, as iOS. Headings keep their own level rule.
  Reverse: the commit that names A59 #3.
- **2026-10-15 · A59's last account-safety rows (Claude).** An Inbox action is sent only in the
  session it was tapped in (the client's fenced `postAuthenticatedInSession`, with the
  generation captured at the tap), as iOS's `queuedATapCannotSubmitTheEquivalentBRow`; Android
  already captured it at the first suspension, so this makes it explicit rather than closing a
  seen leak. "Write a comment" opened while signed out does nothing, as iOS's
  `consumeInitialComposeIfNeeded`. A subscription row's enrichment that answers after the
  session changed is not recorded (iOS `enrichmentFromAnOldGenerationIsNotRecorded`).
  `aClearedAccountKeepsNoRowsOrUnsubscribePath` was the History flags, fixed earlier.
  Reverse: the commit that names these rows.
- **2026-10-15 · Marked for Later: an emptied page loads the nearest page with rows; the
  download line names its size (3fm item 1, part; Claude).** As iOS's `reloadIfPageEmptied`
  and `AO3AccountWorksPaging.pageAfterEmptying`, unmarking the last row of a page loads the
  same page while later ones exist, else the page before; with one page the empty state stays.
  As iOS's `AO3MarkedForLaterDownloadLine`, a row says "Downloaded · 1.4 MB" only when its
  EPUB's size can be read (sized with the Storage screen's formatter), and nothing otherwise.
  Not seen running: the demo has no downloaded work in Marked for Later. The "updated" run as
  covers stays with 3fm. Reverse: the commit that names this.
- **2026-10-15 · Subscriptions name the new chapters (3fm item 2; Claude).** A row says
  "Chapters 13-14 new" (or "Chapter 13 new") from its watermark and the posted count, as
  iOS's `AO3SubscriptionsChapterRange`, where it said "2 chapters new". No watermark, no count
  or no growth: no line. Enriched work-page summaries already reach the rows, so an index row
  becomes updated once enrichment brings its count, as iOS. Seen in the demo: "Chapters 4-5
  new", "Chapters 6-8 new". Reverse: the commit that names this.
- **2026-10-15 · The account hub's counts are seeded from the dashboard nav (3fm item 3;
  Claude).** As iOS's `record(dashboardActions:)`, the Works, Series, Bookmarks and
  Collections sizes AO3 prints in the nav of the dashboard page the hub already reads ("Works
  (535)") are kept for the session, with no request of their own; only exact
  `/users/<name>/<list>` links count, so a pseud's numbers never land there. The hub's
  Collections and Series rows now show a count, as iOS's. Not seen running: the demo's
  dashboard, like iOS's fixture, prints no counts. Reverse: the commit that names this.
- **2026-10-15 · The dashboard's groups as iOS reads them; the account hub makes no request for
  a count (3fm item 4; Claude).** A missing Recent works, series or bookmarks group is AO3's
  empty state ("No recent … visible on AO3."); one blurb that will not parse makes that group
  "Couldn't read recent …. Open the full list to try again." instead of a silently shorter
  list, and its siblings stand. "See all" stays under each section, as iOS. **The hub no longer
  reads Subscriptions page 1 in the background** to show a count (added 10-03 in 3h-fix): iOS's
  counts cache never makes a request of its own, and the binding networking policy keeps
  reads to what the reader opened. The count still appears once Home (or the list) has read
  that page; seen in the demo ("6+"). Reverse: the commit that names this.
- **2026-10-15 · Signed out, comment rows offer no Reply; More on AO3's links as iOS builds
  them (3fm items 6 to 8, part; Claude).** AO3 shows guests a reply link where a work allows
  guest comments, but the app posts only signed in: as iOS's `showsLeadingReply`, a signed-out
  row has no Reply and keeps no reply band (its menu still says "Log in to Reply"). Seen in the
  demo: no Reply signed out, six signed in. More on AO3's site paths get exactly one slash and
  the account's root has none after it, as iOS's `siteWideURL`/`userURL` (the rows in use
  already had them). A test pins the comment tray to the chapter editor's markup for every tag
  but Link. Left to 3fm: the tray as a four-column grid, series creators' pseud links, bookmark
  collections, tag autocomplete's canonical mark and count. Reverse: the commit that names this.
- **2026-10-16 · Teen's mark is mustard on light themes; Other is black (A58 #13; Claude).** As
  iOS's `teenYellow`, the Teen rating's yellow (about 1.3:1 on a light card, where the "T"
  vanished) becomes a dark mustard (`#8C6600`, about 4.5:1) on Light and Sepia, on the status
  chips and the cover card's tiles; Dark and OLED keep the yellow. The Other category is black,
  AO3's own coding and iOS's `categoryColor`. Seen on the emulator (Light, the dashboard's
  Teen tile drew `#8C6600`). Reverse: the commit that names this.
- **2026-10-16 · Fandom aliases in italic where the script has one (A58 #20; Claude).** As
  iOS's `FandomScript.hasItalicForm`, Browse's fandom rows set an alias in italic when it is
  Latin or Cyrillic, and leave CJK, kana, Hangul, Thai, Hebrew, Arabic and mixed-script names
  upright (a skewed CJK glyph blurs at caption size; half a slanted string reads as a fault).
  Not looked at on screen. Reverse: the commit that names this.
- **2026-10-16 · Brief 3fm landed (Codex, reviewed and gated by Claude), and a composer crash
  fixed.** Marked for Later draws its updated run (and the Updated pill) as covers, the rest as
  the ledger, as iOS. The formatting tray is iOS's grid: four columns, two above font scale 1.3,
  one from 1.8 (Android's stand-ins for the accessibility sizes). The writing tag picker shows
  AO3's canonical mark ("Posts as typed" otherwise) and the work count it already sent; Claude
  made the parser read each field leniently, so one odd row (a numeric id) costs only itself.
  Series creators keep their pseud routes and link to the author's page, only for AO3's own
  `/users/` links (anonymous and orphan_account have none); a bookmark's collections are kept,
  not drawn, as iOS. **Separately, a crash:** `CommentSubmissionKey.normalize` used a regex
  flag Android's engine rejects, so opening the composer with a saved draft crashed the app
  (the JVM tests accept the flag); it now splits on `Char.isWhitespace`, and a source check
  keeps such patterns out. Codex's second review found two session gaps (an Inbox delete
  confirmation outliving its session; a comment success crossing a session while its draft is
  cleared), fixed next. Reverse: the commits that name 3fm and the composer crash.
- **2026-10-16 · Codex's two review findings fixed (Claude).** The Inbox's Delete confirmation
  belongs to the session that showed it: it closes when the Inbox resets for a new session, and
  a Confirm from an ended session sends nothing (the view model refuses an action whose
  confirmation was opened in another session; the dispatch fence then holds the rest). A
  comment success that waits on storage to clear its draft rechecks the session afterwards, so
  an ended session publishes no "Posted." and reloads nothing of the next reader's. Each test
  fails with its guard removed. Reverse: the commit that names the review.
- **2026-10-16 · A write's POST is never sent twice on a 307/308; author-page writes need
  AO3's notice (Codex's 3fn review, F1 and F2; Claude).** The redirect relay followed a 307/308
  with the method and body kept, so a write answered that way was sent a second time, outside
  the single-shot fence (the shared transport since before these features). It now returns
  the 307/308 for anything but GET/HEAD, and the write is reported as "AO3 asked for this to be
  sent again, and it wasn't. Check on AO3 before trying again." AO3 answers its writes with a
  302 (followed as a GET), so ordinary writes are unchanged. Author Subscribe, Unsubscribe,
  Mute and Block no longer count a bare redirect as success; History, the subscriptions
  list's Unsubscribe and Unmark keep iOS's notice-or-redirect rule (`readingsWriteResult`),
  which the policy names. iOS follows a 307 itself (`AO3RedirectCookieRelay.swift`); that is
  noted for the iOS lane, not changed tonight. Reverse: the commit that names F1 and F2.
- **2026-10-16 · Brief 3fn landed: A58's deferred reader items (Codex, reviewed and gated by
  Claude).** Read Aloud gives the system media controls a duration and elapsed time from iOS's
  speech estimate (68.75 s per position at 1x, scaled by rate; seen on the emulator: PLAYING at
  68,750 ms). The sentence chunker with iOS's abbreviation protection exists beside the
  paragraph chunker, which the engine still uses. Converted author notes carry
  `epub:type="note"` (new conversions only; the EPUB declares the namespace). The reader's
  loading skeleton fills its area with bounded prose-shaped paragraphs. **The app's Dark base
  is now iOS's #16161A** (it was #191817; the reader already used #16161A), so dark unwashed
  screens are a shade cooler; the washed-card backdrop stays #0B0B0D, as iOS. Not looked at on
  screen: the skeleton and the Dark surfaces. Codex's three write reviews found F1/F2 (landed
  separately). Reverse: the commit that names 3fn.
- **2026-10-16 · iOS keeps its author-write verdict; Android is stricter (recorded, not
  changed).** iOS T-417 (`c3eb0bc8`/`04543763`) ports the 307/308 fix. iOS's author Subscribe,
  Mute and Block still count any 200–399 without an error flash as done
  (`AO3AuthorProfileService.swift:970`); Android now needs AO3's notice (`42155cc1`). The
  binding policy doesn't require the notice for these writes, and iOS's demo answers them
  with plain fixture pages, so tightening iOS would also need demo answers. Left as a known
  difference; revisit if a real AO3 answer is ever seen without the notice.
- **2026-10-16 · A60: code the JVM passes and a device fails (Codex audit; fixed by Claude).**
  No other crash: every literal regex compiled under ICU (Codex checked 112 sites, 71 demo
  routes and the dynamic ones against ICU 78). Two wrong results: Android's `\w` and `\d` are
  Unicode, the JDK's ASCII, so a collection name like "aéb" passed the client's check on a
  device, and a release tagged with Arabic-Indic digits would rank as an update. Both
  patterns now spell out ASCII (`[A-Za-z0-9_]`, `[0-9]`). The JVM tests cannot show the
  difference, so no test was added for it. Reverse: the commit that names A60.
- **2026-10-16 · A web login that is left, or cannot be saved, leaves no half-signed-in state
  (A61 #1, #3; Claude).** Leaving the login screen while AO3's cookies are being read put the
  app back to signed out, where it stayed on "Signing in". Once the session's save starts it
  finishes (iOS's cancel lands before the save too). A secure store that cannot save (a
  keystore fault) is now the "AO3 logged in, but the session could not be saved securely"
  message, with the web view's login cookies cleared; it was an exception out of the login
  screen that could crash the app. A61 (Codex) settled 181 unsure rows: 80 kept, 19 fixed
  since, 25 not applicable, 57 missing in 31 items. Reverse: the commit that names A61 #1.
- **2026-10-16 · Brief 3fo, first part (Codex to its usage limit; reviewed, corrected and gated
  by Claude).** A61 #4 (a collection's staged items survive leaving and returning; a cancelled
  load restarts without dropping drafts), #6 (PDF imports drop running headers, page numbers
  and the echoed title, and rejoin split words), #7 (a PDF import is refused when MuPDF cannot
  read it, instead of scraping every parenthesised string), #8, #10 (restored works are
  reindexed after their tags are attached), #13 to #20, #23, #24. Claude's corrections:
  #10's test assumed a merge takes the backup's tags for an existing work (it keeps the
  local ones, as iOS); rewritten. #15 sent a tag link with a query or sub-listing to the
  phone's browser, which an earlier fix had stopped for AO3 links (the demo would reach AO3);
  every AO3 page without a native screen now opens in the app's own web view, which the demo
  answers locally. #24's sweep swallowed cancellation and returned as if done; it propagates
  now. Deferred by Codex: #9 (Readium gives no visible-spread range), #21 (Read Aloud has no
  position seek). Left for its next run: #25 to #31. Reverse: the commit that names 3fo.
- **2026-10-16 · Transport failures read as sentences; Unknown has its own mark (A61 #26, #28;
  Claude).** As iOS's `UserFacingError`, a timeout says "AO3 took too long to answer. Try
  again." and any other non-offline transport failure "Couldn't reach AO3. Check your
  connection and try again.", where the exception's own text ("timeout", "unexpected end of
  stream…") reached the reader. A work of unknown status shows a question-mark icon, not
  WIP's clock. A61 #30 is not real: the work page already says "Remove from Later"; the label
  cited is the bulk bar's, which says "Remove from Saved for Later" as iOS's card menus do.
  Reverse: the commit that names A61 #26.
- **2026-10-16 · A61 #29 and #31 left (recorded).** #29 (iOS's compact P/S/N/M/A section
  pills in the reader) is reader chrome, which waits on owner question 12. #31 (an offline
  symbol beside connection errors) would add a symbol Android's error card has never drawn;
  design, not a fault. #25 (tag picker "From your other works") and #27 (Add Chapter's empty
  hint) go to Codex's next run.
- **2026-10-16 · A61 #27 is not real.** Android's Add Chapter already shows "Empty. This opens
  the editor with plain text, AO3's HTML tags, or a paste from elsewhere." under an empty
  Chapter text row, as iOS's `emptyHint`; A61 looked at the work form, where iOS shows none.
- **2026-10-16 · A61 #25 was in 3fo's first part.** Codex wrote "From your other works" in the
  writing tag picker before its limit (`860c39f7`; iOS's `WritingOtherWorkTags`: the author
  page's already-loaded works, the current work and chosen names left out, no request),
  though its result file stopped at #24. A61 is closed but for the deferred #2/#5, #9,
  #11/#12, #21, #22 and the left #29, #31.
- **2026-10-16 · A62's first four: a file, a bookmark, an order and a note no longer lost
  (Claude).** A62 (Codex; every reader action in iOS's Library, Work Detail and Reader against
  Android's) found 33 differences. Fixed: **F01** Work Detail's Android-only "Delete EPUB" is
  offered only for a work AO3 can give back (iOS offers no download action for an import,
  whose file may be the only copy). **F02** the bookmark button matches the page's exact
  Readium position, as iOS; within 2% of the work it could remove a bookmark pages away
  (seen: add, then remove, on the emulator). **F26** a collection's Reorder opens in its
  reading order, so Done no longer saves newest-added order over it (seen). **F03** Back from
  a newly typed note keeps it, as iOS's note editor does; Cancel still discards. Reverse: the
  commit that names A62 F01.
- **2026-10-16 · Brief 3fp, first part: A62 F04 to F10 (Codex, reviewed and gated by Claude).**
  F04: Library bulk Delete, a collection's bulk Remove, Queue Storage's Remove and the
  queue-only Remove swipe always ask, as iOS, whatever the delete-confirmation setting (that
  setting covers single-work deletes). F05: Rebuild from Original asks first and shows a
  failure (one shared dialog). Brief 3fz adds converter stamps: older Android copies rebuild
  at once; current Android, unmarked/legacy, and foreign-platform stamps ask first (3gc).
  Missing/unreadable stamps also ask: there is no Android version to judge. Each app uses
  only its own explicitly tagged converter scale (owner decision, 2026-10-20).
  F06: Read on a work with no file fetches a reading copy and opens it, without keeping it as
  a download; a fresh copy resets Finished and the fallback position, as iOS's
  `restoreReadableEPUB`. F07: Continue Reading from a work page opened over its reader goes
  back to that reader (seen on the emulator: one reader, Back to Library). F08: Chapter
  comments and Write a comment open their own destinations. F09: Contents' chapter Bookmark
  and Add Note work. F10: a queue's and a collection's filters are the Library's full panel.
  Reverse: the commit that names 3fp.
- **2026-10-16 · Brief 3fp, second part: A62 F11 to F33 but F21/F22 (Codex to its usage
  limit; reviewed, corrected and gated by Claude).** Queue and collection pages get the
  Library's per-work menus and swipes, with scoped Remove (F11, F12); pull-to-refresh
  refreshes the listed works' metadata, one paced request at a time, as iOS's
  `WorkMetadataRefresh` (F13); New Collection on the Library dashboard is the full editor
  (F14); the queue and collection pickers toggle membership for a whole selection and create
  in place (F15, F16); Remove from Saved for Later for a selection (F17); Layout and Expand All
  (F18); My copy's tag names filter the Library and a failed preservation can be retried
  (F19); other local works in the series on Work Detail (F20); Highlight applies at once in
  the last colour and a repeat removes it, and deleting a mark is immediate, as iOS (F23,
  F24); wording (F25); Edit tag's Remove (F27); Collection Details saves as it changes (F28);
  the voice-pack download asks and can be cancelled or retried (F29); Select All in the queue
  organiser (F30); bylines open authors (F31); every tag shows (F32); long-press clears
  filters (F33). Claude's corrections: Home's section list was never handed the importer
  (Codex could not compile); the refresh change stopped saving a work ID recovered from the
  source URL when AO3 could not be reached (an existing test caught it); the bulk collection
  picker called `onAdded` on opening, so a caller that reloads on it would reopen it without
  end; Codex's new picker test never settled under Robolectric (the dialog runs and toggles on
  the emulator), so its membership rule is tested on its own. Reverse: the commit that names
  3fp part 2.
- **2026-10-16 · A63 (Codex: every action on Home, Search, Browse, Account, Bookmarks,
  Comments and author pages; 31 differences) and Claude's four (F07, F16, F25, F31).** F16:
  Delete From Inbox always asks, as iOS (a deleted notification has no undo). F07: Reply,
  Edit and Delete inside an open comment thread now show their composer and confirmation
  (they set state the thread view never drew; seen on the emulator). F25: Thread and Parent
  Thread inside an open thread scroll to a comment it already shows, as iOS's
  `focus(_:proxy:)`, instead of narrowing it; one above the thread still opens there. F31:
  AO3's own "N more comments in this thread" opens that page in the app's web view (iOS opens
  the website; the in-app view keeps the demo off AO3). The rest go to brief 3fq. Reverse:
  the commit that names A63 F07.
- **2026-10-16 · Brief 3fq: A63's main differences (Codex, reviewed, corrected and gated by
  Claude).** F01: Home's bulk Delete always asks. F30, F08, F20: an AO3 result that is also in
  the Library uses the local work (its blur, its reader, its menu) on author, series, Search
  and Account lists. F17: Download for a selection of AO3 works fetches the EPUBs (one paced,
  user-started request each; it stops at an outage). F12: a failed Search bulk action says
  so and keeps the selection. F10, F11: AO3 result menus offer Read, Comments, Download,
  Later, Queue, Finished, Collection and Work Details, as iOS (seen on the emulator); Copy
  Link works where it remains. F05, F02, F03, F04: the shared queue, collection and tag
  pickers everywhere. F09 (no extra ask for a saved search), F28 (Open on AO3 keeps the
  pseud), F29 (More on AO3's full page), F06 (Show/Hide mature), F32 (the fandom index adjusts
  by TalkBack). Claude's corrections: one new test called a suspend function outside a
  coroutine and used a non-UUID id; the author list's tests tapped a Select button the card
  now replaces; and the bulk-collection-picker test hung under Robolectric and ran the test
  JVM out of memory (the dialog runs on a device), so it was removed with a note. Left for
  3fq part 2: F13, F14, F18, F19, F21 to F24, F26, F27. Reverse: the commit that names 3fq.
- **2026-10-16 · Brief 3fq part 2: A63's smaller items (Codex, to its weekly limit; reviewed,
  test-corrected and gated by Claude).** F14: an EPUB downloaded in the in-app AO3 web view is
  imported into the Library (only HTTPS AO3 `/downloads/…epub` links; the paced downloader).
  F13: the web view has an address/search field, Reload, Add Bookmark and Done (seen on the
  emulator). F18: author Works, Series and Bookmarks and a series' works append with Load More
  (seen: page 2 of 3 joins page 1). F21: the page picker takes an exact page number (the
  Inbox's own pager is left; it is Claude's file). F19: dashboard fandom chips open their
  works and the list folds at five. F26: Expand/Collapse All on author pages. F27: the
  dashboard's About. F22: the tag picker offers "Popular in <fandom>" from one read of that
  fandom's first works page when it opens, as iOS's `popularTags`. F24: Collection Items'
  Submit no longer asks twice. F23: Preferences' result is a transient message with Try
  Again. Claude's test corrections: two new tests looked for what the screen does not draw
  (the fixture's works have nothing to fold; the label is drawn in capitals), and one
  raced the database close. **Codex is at its weekly limit until 2026-10-22 03:09.**
  Reverse: the commit that names 3fq part 2.
- **2026-10-16 · The Inbox uses the shared pager (A63 F21, Inbox part; Claude).** First,
  Previous, the page label with its picker and exact page field, Next, Last, as iOS's Inbox
  uses the shared `SearchPaginationBar`; it had Previous and Next only (seen on the emulator).
  Large text keeps its own stacked pager. A63 is done but for F15 (withdrawn in the audit).
- **2026-10-16 · Settings, Onboarding, Privacy and Support compared again (iOS 102 labels; 16
  not on Android by their words; Claude): three changes.** (1) **Sync Folder** takes iOS's
  rows: Folder, Auto Sync, Sync Now, Change Folder, Disconnect when a folder is chosen, Choose
  Sync Folder when not. `sync.isEnabled` is iOS's Auto Sync (the hub already showed "Paused");
  Android's old "Enable folder sync" switch forgot the folder when turned off, and the footnote
  spoke of an Auto Sync switch Android did not have. Choosing a folder syncs at once, and
  Disconnect forgets when it last synced, as on iOS (all seen on the emulator; the hub reads
  "Paused" with Auto Sync off). **Bug fixed with it:** Backup › Replace's "Pause Library Sync" left the background
  worker scheduled, and the worker did not look at the setting, so it could sync the works
  Replace removed back in. The worker and the app's own runs now go through
  `SyncRepository.runAutoSync`, which does nothing while Auto Sync is off. Sync Details stays
  out (2026-10-11). (2) **Bug report**: a shake grabs the screen first (PixelCopy, so images
  come out) and the report offers Include a screenshot, its preview and Save or Share
  Screenshot (the share sheet, from a cache folder of its own), and notes it in the issue
  body, as iOS (seen on the emulator: a shake opens the report with the screen under it, and the
  share sheet takes the image). The body is built line by line now: a description of several lines used to
  keep the template's indent and show on GitHub as code. (3) **Replace** that cannot save its
  undo copy says "Could not save an undo copy … Your library was not replaced. Free some space
  and try again." Android never offers iOS's second-attempt "I understand the risks": no copy,
  no Replace (the more sparing). Platform wording, left: Face ID, Apple devices, Scan a QR
  Code (generate-only, earlier decision), "Import files" (an iOS spoken label for Android's
  "Import Files"); "Add Saved Works to Saved for Later" stays out (2026-10-11). Reverse: the
  commit that names this entry.
- **2026-10-16 · No daily background walk of the library on AO3 (Claude).** Android ran
  `WorkTagsRefreshWorker` every day: up to 150 saved works read from AO3, chosen by a "needs
  refresh" test that was only "24 hours since the last attempt" (so every work, in turn), and
  on success it stamped the attempt and kept nothing it had read. The policy allows no
  background polling but folder sync and no periodic full-library metadata sweep; iOS refreshes
  tags only while the Library is open (`LibraryView.backfillFilterMetadata`), for works that
  lack data. A WorkManager process also does not see the demo's network fence (A18), so the
  worker was a way for the demo to reach AO3. The August decision (`bb165940`) that kept it
  read the policy's throttle row as allowing a background job; it did not know the worker
  saved nothing. Now: the worker, its factory entry and the wrong `SavedWork.needsAO3Refresh`
  are gone, and each launch cancels a scheduled run left by an older build. iOS's predicate
  stays in `BackupMergeService`. **Not ported yet: iOS's foreground Library backfill** (EPUB
  tags first, then AO3 once per work that lacks tags, sequential, cancellable, every attempt
  stamped, behind the demo fence); it is a new AO3 read path, so it gets a brief of its own.
  Reverse: restore `WorkTagsRefreshWorker.kt` and its scheduling from `2f00aa6a`.
- **2026-10-16 · Brief 3fr: iOS's Library tag backfill, in the foreground (Claude, the agents
  being away).** While the main Library is open (not a section's page), `WorkRepository.
  backfillFilterMetadata` walks every work that is not queue-only: an untagged work with an
  EPUB gets its tags from the EPUB (local), then one AO3 read when `SavedWork.needsAO3Refresh`
  (now iOS's rule, shared with the backup merge) says AO3 would add something. One work at a
  time through the paced client; leaving the Library cancels it. The attempt is stamped before
  the read (24-hour cooldown); a cancelled read puts the old stamp back; a page without tags
  keeps the work's; a 404 marks it gone. The page's data goes through `WorkMetadataMerger`
  (tags merged, flat tags rebuilt, language, words, chapters, stats, verified authors,
  `workTagsFetched`), and a freeform that is also a fandom, character, warning or category is
  dropped, as iOS. Android's EPUB reader also knows the AO3 preface, but only the flat tags and
  an empty rating are taken, as iOS. **In the demo nothing is read from AO3** (after the launch
  decision): its local answers would mark the demo's works deleted. Expect one read per work the
  first time an existing library opens the Library, as on iOS. Reverse: the `LaunchedEffect`
  in `LibraryScreen.kt`.
- **2026-10-16 · No AO3 read at app start (Claude).** Every process start read up to five works
  from AO3 that had never been checked (`KudosApplication`, "opportunistic tag refresh"),
  including a start made only by the folder-sync worker in the background. iOS reads nothing
  at launch but the session check; the Library's foreground backfill (3fr) now reads what a
  work lacks, 404s included. Removed. Reverse: the block in `KudosApplication.onCreate` before
  this commit.
- **2026-10-16 · 3fr's walk reads each work when its turn comes (Claude, own review).** It took
  the whole library once at the start and wrote that copy back as it reached each work, so a
  favourite, a Finished mark or a tag set in the Library while the walk ran (one paced AO3 read
  per work, so minutes on a large library) was undone. Each work is now read at its turn and
  again just before each write; a test favourites one work while the walk reads another.
- **2026-10-16 · A work is read again after an AO3 read, before it is written (Claude).** Home's
  WIP update check, Settings' availability sweep and pull-to-refresh (`refreshMetadata`) wrote
  back the copy of a work they had before the request. Home's check runs on while the reader
  reads, so a work opened from Home could have its place put back to where it was when the
  check began; the sweep (up to 150 works, 1.5 s apart) and a refresh could undo a favourite,
  a Finished mark or a page read meanwhile, and a work deleted during a refresh came back.
  iOS edits the live record and has none of this. Each now reads the work after the request
  (as `WorkMetadataRefresh` already did); a test for each writes a reading place during the
  request. The same in `WorkImporter`: Download and Save looked the work up before reading AO3,
  and an EPUB download (seconds) wrote back the copy it started with, so a place read or a
  Finished mark set while an update came down was lost; the work is now looked up after AO3
  answers and read again after the file is written. Work Detail's Kudos, too, wrote the
  screen's copy (loaded before a visit to the reader) after AO3 answered; it reads the stored
  work first now. Checked and fine: the reader (every write reads first), the repository's
  setters (by id) and the queue code (reads inside its transactions).
- **2026-10-20 · The owner answered four questions (§11: 19, 24/25, 27, 29/30), all "match iPhone"
  or the recommended fix.** Asked in chat at 12:50. (Q29/Q30) Android's reader follows iOS:
  Highlight marks the selection at once in the last colour used (the same colour again on the
  same passage takes it off, another colour recolours it: iOS `createAnnotationFromSelection`,
  `ReadiumReaderView.swift`), Add Note marks it and opens the full note editor, and
  "Customize Theme…" opens iOS's one reading-text sheet (`Features/Reader/CustomizeThemeView.swift`);
  Android's chrome stays Material (owner, 2026-10-04). Brief 3fs. (Q24/Q25) Own Works and Series
  as the iPhone's list with fandom chips, the unfold control at a card's foot, History,
  Bookmarks and the works lists opening on Compact; Android's own-works totals line stays (the
  owner's rule: no information lost). Brief 3fu. (Q19) On Dark and OLED, accent-coloured
  text and icons are lightened to 4.5:1 against the page on both apps; fills keep the exact
  accent (T-348 stands for controls). (Q27) Reading Insights' words per hour counts what was
  read in each sitting on both apps. Reverse: each brief's commit.
- **2026-10-20 · Screens without a mockup get a best-effort redesign (owner, 2026-10-20).**
  Each is written up in `REDESIGNED-WITHOUT-MOCKUP.md`: what it was, what it is, the iOS screen
  it matches and what was kept. Where iOS already restyled the screen Android follows iOS.
- **2026-10-20 · Read Aloud's pronunciation corrections are a gap, not a decision.** iOS keeps a
  word → respelling list (`KokoroPronunciationStore`, Settings and "Fix Pronunciation" in the
  selection menu, backed up as the manifest's `pronunciations`); Android carried the key through
  backups and sync untouched but had no store, no editor and no menu item. Brief 3ft ports it,
  reading and writing the same key.
- **2026-10-20 · iOS's built-in reading fonts read as Android's generic families (Claude).**
  New York, Georgia, Palatino and Times read as `serif`, Helvetica Neue and Avenir as
  `sans-serif`, Menlo as `monospace`. Android has none of iOS's faces, and Readium refuses a font
  family declared without a file: once 3fs declared every built-in the reader crashed on opening
  (seen on the emulator), and before it, picking any built-in font crashed it too (the JVM tests
  never ran Readium). Only imported fonts (with a file) are declared. Reverse:
  `ReaderSettingsMapper.BUILT_IN_GENERIC_FAMILY`.
- **2026-10-20 · Lane note: `720cf773` carried 3fv and 3fu ungated (Claude).** `git apply --3way`
  stages what it applies, and a docs commit made with `git add <docs> && git commit` swept the
  staged code in with it. That commit is local history now (not rewritten, per §1); `the next
  commit` makes the gate green on top of it. From now on docs are committed with a pathspec
  commit (`git commit -m … -- <paths>`), which takes only those paths.
- **2026-10-20 · Busy flags after a session change (Claude, review of 3fv).** 3fv cleared a write's
  busy flag only when the AO3 session was unchanged. Assignments and a sign-up's Save and Withdraw
  must clear it whatever happened (their tests, and the code before 3fv): otherwise a sign-out
  mid-write left the button busy for good. Maintainers, Moderation, Tag Set and the Prompt Meme
  keep Codex's guard: their contract is that a session change never touches the old screen.
- **2026-10-20 · Converter records are judged by the app that wrote them (Claude; Android 3gc,
  iOS T-421).** Each app numbers its converter on its own scale (iOS 9, Android 1), and both
  carry the same `Originals/<id>.conversion.json` through backups and sync. Android writes the
  additive key `converterPlatform: "android"`; iOS writes none. Android calls a record stale only
  when it is Android's and older; iOS only when it has no platform (or "ios") and is older. A
  foreign record is never stale, so neither app nags about the other's imports (My copy still
  rebuilds them, after asking). Reverse: `WorkConversionRecord.isStale` on both apps.
- **2026-10-20 · Pronunciation corrections: kept, edited, backed up and synced as iOS; heard only
  once Android's voice pack honours them (Claude, 3ft).** Android now has iOS's store (the same
  JSON), the list and editor in Settings › Listening, Fix Pronunciation in the selection menu, and
  the backup key `pronunciations` merged on restore as iOS (archive wins conflicts, local-only kept,
  a device's own manifest never overwrites newer local edits). The bundled Kokoro pack
  (`kokoro-int8-en-v0_19`, sherpa-onnx 1.13.6) ignores a lexicon, so a correction does not yet
  change Android's speech; the page says so. A later pack that reads the lexicon picks them up
  with no data change. Reverse: drop the Listening row; the key would pass through as before.
- **2026-10-21 · A ticked challenge-settings box is posted as a browser posts it (Claude; closes
  A65 #102).** A browser sends AO3's hidden "0" and then the box's "1"; iOS sends the box once.
  Rails keeps the last value, so AO3 ends with the same setting either way. Android keeps the
  browser's exact body, which its tests pin ("untouched bodies equal a browser's, field for
  field"), and owner question 17 covers the general choice. 3fx's change to drop the "0" was
  taken back; its tests now assert the value Rails keeps.

- **2026-10-20 · Privacy & Local Data's four Clears always ask first (brief 3ga).**
  The owner's iOS parity goal reverses the 2026-10-09 (3bz) decision that kept the
  Android preference governing these actions. Free up space, Clear reading positions,
  Clear reading history and Clear browse cache now always show their confirmation,
  matching iOS `Features/Account/PrivacyDataView.swift:120–177`. “Confirm before deleting”
  continues to govern swipes only, as its footnote says. No clear action or stored
  preference is removed.
- **2026-10-21 · A collection's membership clock stays on the device (Claude; corrects A68).**
  Neither app writes `collections[].lastMembershipChangedAt` to a backup: iOS's own comment calls
  it "when this device's reader last chose the contents of this collection", the clock a device
  uses to weigh a deletion from elsewhere against its own edits. Gemini's A68 said both apps
  read and write it; they do not, by design (queues' clock is in both manifests). Codex's 3ge
  found the absence; it is not a gap.
- **2026-10-21 · A70's screen differences that are not Android's to change (Claude).** Checked
  against both apps' code: History's group order is the same rule on both (AO3's order kept, a
  heading wherever the bucket changes; iOS `AO3HistoryVisitGrouping`), so a different order is
  different data. The Settings hub's Appearance value shows the stored theme; the screenshots set
  the theme for the session only. The iPhone's AO3-logo avatar is an image the simulator fetched
  online (iOS's fallback is the same person glyph as Android's; the emulator is offline). Where
  Android keeps information at the largest text that the iPhone cuts or hides (a collection's
  maintainer line, the dashboard card's symbol grid, the collection preview's rows, the reading
  ring's label, chips the iPhone clips), Android keeps it: the owner's rule is no lost
  information, and the iPhone's cuts are listed for the iOS tail.
- **2026-10-21 · A queue a restore creates keeps the archive's membership clock (Claude; 3ge, iOS
  T-423).** The cross-platform readers found iOS setting a newly restored queue's
  `lastMembershipChangedAt` to the later of the archived clock and the queue's `dateUpdated` (the
  initializer's placeholder), so a restored queue looked as if its contents changed at its last
  edit. Android restores the clock as written. iOS now does too; a queue already on the device
  still keeps the newer of the two clocks, on both apps. Reverse: the one `hadExistingQueue` branch
  in `KudosBackupService`'s queue loop.
- **2026-10-21 · A71's differences that are not Android's to change (Claude, with Codex 3gh/3gi).**
  The harness's own: the reader in Light (the DEBUG theme extra now saves the theme), Library
  sections showing Home's tab (the debug route opens them from Home), Comments titled "A Test
  Work" (the route carries no work), the queue's Details page (now the queue page). Demo data:
  fixture counts and dates, "Finished" order, which works are AO3-linked (Android's demo links
  four; the iPhone's none). Kept on Android as information iOS lacks: verified author links in
  the accent, affinity tags and the unfold control on tagged cards, a History row's favourite
  star, Challenges' refresh. At the largest text the iPhone hides Welcome's and sync setup's rows
  under a pinned bar and keeps segmented controls small; Android scrolls and scales (iOS tail).
  What's New's version differs per app.
- **2026-10-21 · A73: a deletion record wins a tie, and a lone figure spans its row (Claude).**
  A soft-deleted collection whose snapshot clock equals its tombstone's is suppressed on a device
  that never had it, on both apps: the record already describes that copy. At accessibility sizes
  an odd figure strip's last cell spans its row, as iOS's does.
- **2026-10-21 · Owner: three UI changes approved (owner, 23:40).** Android's reader hides the
  system bars while reading and Android opts in to predictive back (Android's own chrome); the
  iPhone's layouts at the largest text sizes are fixed where they cover or cut off content; and
  Android shows placeholder rows while AO3 lists load, as iOS already does. Not approved, so not
  built: hiding Write a comment while scrolling, a wallpaper (Material You) accent.
- **2026-10-22 · A73 fixes (Codex 3gj): a file Merge no longer undoes a deletion the archive
  itself records.** A work, collection or queue the archive marks deleted stays in Recently
  Deleted with this device's deadline; a live archive copy still undoes Replace's parking (iOS
  T-424 is the same fix). A deleted AO3 comment with surviving replies stays as a placeholder so
  its replies keep their parent (iOS `parseComment`). A selected ledger row's border and checkbox
  sit outside the blur. Reverse: `archived.isDeleted != true` in `backup/BackupMergeService.kt`;
  the `h4.heading.byline` check in `AO3CommentParser.parseOneComment`; `WorkLedgerRow`.
- **2026-10-22 · Android's reader hides the system bars while reading; predictive back is on
  (owner, 2026-10-21; Codex 3gk).** Bars follow the reader's chrome, as iOS's status bar does;
  a swipe from the edge shows them for a moment without moving the page; any sheet over the
  reader, a screen above it, or leaving it brings them back. Codex also added a "Discard
  changes?" question to the writing forms because the brief assumed one existed; iOS does not
  ask, so it was not landed (owner question 32). Reverse: `reader/ReaderSystemBars.kt` and
  `enableOnBackInvokedCallback` in the manifest.
- **2026-10-22 · Placeholder rows while AO3 lists load (owner, 2026-10-21; Codex 3gl).** Ten
  AO3 lists draw the shape of what is coming (work rows, category panels, inbox and comment
  rows, the author header) in place of a spinner, as iOS's `SkeletonLoading` does; thirteen
  keep their spinner where iOS has one or no loading state. A refresh keeps the rows already
  shown. The Inbox toolbar keeps its height while empty, so the header no longer rides up under
  the back button during the first load. Debug only: `--ei kudosDemoDelayMs 4000` makes demo
  pages answer late, to see loading states. Reverse: `ui/subject/SubjectSkeletons.kt`.
