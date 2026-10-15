# A53 — Claude’s 2026-10-15 Android and iOS changes

Static, read-only review of the requested changes, in the requested order. **Three fixes are worth making: qualify the failed-Replace assurance at the Android target, stamp Marked for Later when its fetch succeeds, and preserve Account’s notice typography.** Most of the changes looked right in source.

## Evidence boundary

- Android: `/Users/cidy02/kudos-android-lane`, **`03ea8d0d`**, read with `git show`, including the diffs and commit messages for `4870ad9c` (3ey), `f7ea565e` (3ez), and `e66684a8` (3fb), and their `docs/android-port/DECISIONS.md` entries at lines 1941–1958. The target also includes **3fa**, which changes the failed-Replace message again; that distinction matters below.
- iOS: `/Users/cidy02/kudos-ios-polish`, **`13132ed9`**, including T-411 through T-414 and their `TASKS.md:24–27` rows. **T-415 is not in that revision.** Its separate commit **`51c983f6`**, dated 07:44:08 EDT, and its task row were reviewed explicitly. All other iOS line numbers below refer to `13132ed9`.
- Both checked-out HEADs had advanced beyond the supplied revisions. Neither checkout was changed. Existing untracked content in those worktrees was left alone.
- Below, Android code paths are relative to `android/app/src/main/java/io/github/cidy02/kudos/`; iOS code paths are relative to `kudos-ao3-reader/`, in their respective worktrees. Test paths are repository-relative. Quoted snippets sometimes collapse whitespace.
- The networking policy and persistence invariants were read. No builds, tests, simulator actions, sign-ins, AO3 requests, commits, pushes, branch switches, or TASKS edits were performed. Confidence concerns source/control flow, not observed UI behavior.

## 1. 3ey — Save Search over Filters

**The state change looked right.** `search/SearchScreen.kt:547` still supplies `onDismiss = { showFilterSheet = false; viewModel.discardFilterEdits() }`. The Save action at `:552–553` now only sets `saveName` and `showSaveSheet = true`; it leaves Filters open. Saving or cancelling the upper sheet does not close the lower sheet (`:272–277`, `:561–570`). A reader can save the draft filter choices, return to Filters, then dismiss Filters and recover the applied search.

The discard is real: `search/SearchFilterSheet.kt:96–98` passes `onDismissRequest = onDismiss` to its `ModalBottomSheet`, and its explicit Close row at `:303` also calls `onDismiss`. `search/SearchViewModel.kt:139–142` restores `lastFilters.copy(query = _filters.value.query)` when the state is Results. Apply intentionally takes another path: `search/SearchScreen.kt:541–544` closes Filters and runs the chosen filters. **High confidence** that 3ey repairs the bypass described in its commit. The existing Results-only discard guard still excludes Loading/Error states; 3ey neither fixes nor introduces that limitation.

**Two Material sheets are present, but source alone does not establish a modal defect.** The lower sheet is `search/SearchFilterSheet.kt:96–100`; the upper is `search/SaveSearchSheet.kt:61–66`, with its own sheet state and dismiss callback. The screen’s Back handler is disabled while either is shown (`search/SearchScreen.kt:259`: `BackHandler(enabled = !showFilterSheet && !showSaveSheet)`). Thus the app does not simultaneously run its own navigation-back action. Cancel, scrim/drag dismissal of Save, and eventual dismissal of Filters have separate callbacks. With the upper modal active, the intended interaction is with Save, not the obscured Filters.

**Saving twice:** `search/SearchScreen.kt:273–277` checks the trimmed name, starts one save, then synchronously closes Save and clears the name. A repeated invocation after that clear returns without another write. Reopening Save from Filters and saving again deliberately makes another named search: `search/SavedSearchRepository.kt:38–44` constructs an entity with `id = UUID.randomUUID().toString()` and upserts it. There is no newly introduced implicit overwrite of a prior saved search. **High confidence** in that state flow; rapid physical taps were not exercised.

**Back, focus and keyboard remain a manual boundary.** `search/SaveSearchSheet.kt:101–106` uses a single-line `BasicTextField`; there is no explicit focus request or keyboard handoff in the opening callback (`search/SearchScreen.kt:548–554`). I cannot certify where focus returns, whether the first Back hides the IME or changes/dismisses the upper sheet, or the stacked-window accessibility focus behavior without running it. No unsupported claim that two Material bottom sheets necessarily break those behaviors is made here. Suggested runtime sequence: focus a filter field → Save → focus/edit name → Back → Cancel/drag/scrim → close Filters → reopen → save twice, checking that only the intended sheet closes and unapplied filters are discarded.

## 2. 3ez — Progress, identity, export and Replace

### Blank locator

**Looked right; high confidence.** `reader/ReaderProgressMapper.kt:53` defines `wroteLocator = !progress.locatorJson.isNullOrBlank()`, and `:68` now assigns `readiumLocator = if (wroteLocator) progress.locatorJson else work.readiumLocator`. Null, empty and whitespace-only callbacks preserve the saved resume anchor. The fallback spine/fraction and timestamps still update (`:65–73`); this is a guard on replacing the locator, not rejection of the whole progress report. The prior legacy-percent preservation decision also uses `wroteLocator` (`:60–63`), so the decisions now agree. The added test in `android/app/src/test/java/io/github/cidy02/kudos/reader/ReaderProgressMappingTest.kt:160–167` checks the empty-string case. It was read, not run.

### Stored AO3 identity and collisions

**The intended fix looked right; it matches the binding identity order and iOS.** `works/WorkIdentityIndex.kt:71` indexes `(work.ao3WorkID?.toLong() ?: WorkTags.ao3WorkIdFromUrl(work.sourceUrl))`; lookup at `:80–89` tries AO3 ID, then canonical URL, then record UUID. A work with a stored ID and no URL can now be found instead of duplicated. iOS uses the same precedence in `Services/WorkIdentityIndex.swift:28–32` and `:39–49`: `work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL)` and an AO3-ID hit returns before UUID lookup.

**Can two records collide? Yes; two genuinely different works require inconsistent identity data for that to be a wrong merge.** Android’s `works/WorkIdentityIndex.kt:71` uses `byAo3Id[it] = work`, so the last indexed record wins when stored IDs repeat. A concrete conditional case is local A with stored ID 5150 and URL `/works/5150`, followed by local B with stored ID 5150 but URL `/works/6161`. Incoming A finds B by 5150 before its correct URL or UUID is consulted. `backup/BackupValidator.kt:64–65` rejects duplicate record UUIDs (`if (!workIds.add(id)) throw ...`); its work-validation block at `:60–96` does not reconcile stored AO3 IDs with URLs or reject duplicate AO3 IDs.

The reader consequence is substantive **if that inconsistent input exists**: `backup/BackupMergeService.kt:152–163` chooses the matched local UUID and writes `workIdRemap[archivedId] = targetId`; Replace applies the snapshot to that match (`:220–222`), and Reconcile can apply a newer incoming snapshot (`:778–782`). Sessions and stars follow the remap (`:1936–1938`, `:1999–2008`), so they can be attached to the wrong book. iOS does not protect against this either: `Services/WorkIdentityIndex.swift:29` overwrites its ID-map entry, `:40–42` returns that hit, and `Services/KudosBackup.swift:2439–2447` applies the archived record and maps its UUID to the selected work.

**High confidence in the conditional collision mechanism; no evidence here that ordinary acquisition produces conflicting stored IDs.** `works/WorkImporter.kt:412–421` fills a missing stored ID from the source URL. Two records for the same actual AO3 ID are duplicates under the project’s identity contract; matching those is correct. I would not revert 3ez or report normal same-ID deduplication as data loss. Conflict validation is shared hardening to decide for both platforms, rather than a demonstrated new normal-flow regression.

### Export limits

**`output.size()` after `closeEntry()` is the right measure for this importer’s archive cap.** `backup/BackupExporter.kt:96–99` writes an entry and closes it before the checks at `:47`, `:55`, `:71`, and `:76`. Those checks measure ZIP bytes emitted so far, not the uncompressed library size. Crucially, `:79–80` checks again after the ZIP is closed, including the central directory. The importer’s corresponding rule is exactly `bytes.size.toLong() > BackupLimits.MAX_ARCHIVE_BYTES` (`backup/BackupImporter.kt:17–20`). **High confidence; looked right.** Checking only after entries, without the final check, would have been insufficient, but that is not this code.

The other new limits agree too: exporter manifest bytes at `backup/BackupExporter.kt:38–40` versus importer manifest validation at `backup/BackupValidator.kt:25–27`; per-font and aggregate font bytes at exporter `:65–68` versus importer `backup/BackupImporter.kt:73–89`. `backup/BackupVersion.kt:37–41` sets the caps to 1 GiB archive, 128 MiB per entry, 8 MiB manifest, 4 MiB per font and 32 MiB total fonts. The existing in-memory archive construction remains (`backup/BackupExporter.kt:31`, `:82`: `ByteArrayOutputStream()` / `output.toByteArray()`); this change does not establish a low-memory streaming guarantee.

**Yes, a library assembled from successful imports can now fail to export.** For example, separately import nine packages containing distinct 4 MiB fonts. Each package passes the importer’s per-package font limits, while font merge adds an absent font with `fontsByName[font.fileName] = font` and `filesToWrite[font.fileName] = incomingBytes` (`backup/BackupMergeService.kt:1158–1162`). Export collects every readable font (`backup/BackupRepository.kt:69–75`), and 36 MiB then exceeds the new 32 MiB check. Multiple valid book imports can likewise accumulate beyond the archive cap.

For that reader, Export now reports failure, and Replace also cannot proceed if its required safety export fails (`backup/BackupScreen.kt:147–160`: export/write safety copy before import). **That restriction is real, but the prior outcome was worse as a backup guarantee:** 3ez’s parent wrote such aggregate fonts without a total check; the unchanged importer would reject the result. Refusing to promise a restorable backup is correct. Growing beyond one transport package remains a product limitation, not evidence that the new byte measure should be removed. The added test (`android/app/src/test/java/io/github/cidy02/kudos/backup/BackupCompatibilityTest.kt:110–114`) exercises a tiny injected archive cap, not every font/manifest boundary.

### Failed Replace message

**3ez itself looked right.** At `f7ea565e`, `backup/BackupScreen.kt:178–181` says `"Part of your library may already have been replaced... import that file with Replace to go back."` only when `safetyName` exists. The name is assigned after the safety copy is written. That honestly disclosed the then-existing partial-apply behavior.

**F1 — P2: the message at the requested target promises successful rollback even when file rollback failed.** At `03ea8d0d`, 3fa supersedes that wording with `"Your library was not replaced. The safety copy is $it."` (`backup/BackupScreen.kt:175–177`). The success of file rollback is not established before this assurance: `backup/BackupFileUndo.kt:36–40` runs `Files.deleteIfExists(destination)` and `Files.move(undo, destination, StandardCopyOption.ATOMIC_MOVE)`, but catches failures with `error.addSuppressed(failure)`. `backup/BackupRepository.kt:388–395` calls rollback and rethrows the original error to the UI regardless of whether every file was restored.

A concrete failure is an earlier installed EPUB whose destination cannot be deleted during either rollback attempt after a later import error. Room rolls back its rows, but that EPUB can still contain the replacement bytes. The reader is then told the library was not replaced when the file restoration is incomplete. **High confidence in the control flow; exceptional filesystem failure not reproduced. This is a 3fa follow-up at the pinned target, not a defect in 3ez’s original caution.** Smallest message fix: remove the unconditional assurance, or qualify it when rollback reports failures; keep naming the safety copy.

## 3. 3fb — Compact, synced age and grouping

**Compact default looked right; high confidence.** `account/AccountWorksListScreen.kt:165` now calls `rememberStoredChoice("account.displayMode", AccountDisplayMode.Compact)`. `ui/components/StoredChoice.kt:19–21` reads the saved enum and uses `getOrDefault(default)` only without a valid choice; `:26–28` persists an explicit selection. Existing Ledger choices survive. History/Bookmarks receive that mode (`account/AccountWorksListScreen.kt:461`, `:474`); this does not claim every specialized account browser changes its layout.

**F2 — P2: “synced” records UI lifetime, not successful fetch time.** `account/AccountWorksListScreen.kt:444–445` says `"A new page object is a fetch that succeeded"` and uses `syncedAt = remember(current.page) { System.currentTimeMillis() }`. This is not a fetch. While that composition remains present, `remember` compares its key by equality, not object identity. `network/ao3/search/AO3SearchModels.kt:43–53` defines `AO3SearchPage` as a data class with page content and no fetch timestamp. Normal recompositions, local-library updates that retain the page, expanding cards and the minute ticker do not alone reset the stamp.

There is a concrete false-freshness path: the screen replaces the list with “No matching works” when a local filter matches nothing (`account/AccountWorksListScreen.kt:356–362`), removing the `remember` inside the later Loaded/list branch. Clear Filters (`:362`, or `:509`), and the same retained page re-enters at `:445` with the current time. A reader who has not fetched in an hour can now see “synced just now” after only changing a local filter. Those filter callbacks only assign `filters`; they do not fetch AO3.

Conversely, a same-page successful load returning equal content need not reset the time: `account/AccountViewModel.kt:250–253` retains Loaded during a same-page request, and `:272` emits `AccountListUiState.Loaded(result.value)`, whose page may compare equal. The UI therefore cannot infer every successful fetch from that key. **High confidence in both source paths; UI not exercised.** Stamp a `fetchedAt` field when the session-checked successful load is accepted and carry it with Loaded state. iOS already does that: `Features/Bookmarks/AO3AccountWorksList.swift:1258–1271` checks session/token and then sets `lastSyncedAt = Date()` on a successful Marked for Later load.

**The minute ticker itself looked right for composition lifetime.** `account/AccountWorksListScreen.kt:570–574` uses `LaunchedEffect(syncedAt) { while (true) { now = System.currentTimeMillis(); delay(60_000) } }`. It cancels when that browser leaves composition or its key changes; an ordinary recomposition does not spawn another loop. It only reads the local clock, so it adds no AO3 polling. It is not explicitly tied to Activity STARTED/STOPPED: a retained composition can continue its local clock while the app is backgrounded. This is a bounded clock update, not a networking-policy violation.

**“Everything else” looked right.** `account/AccountWorksListScreen.kt:664–665` adds the heading only for `filter == "all" && displayedWorks.isNotEmpty()`. The existing updated/non-updated split remains at `:630–659`; narrowed pills remain flat lists. iOS’s `.all` case likewise gives `.everythingElse` `showsHeader: true` even if the updated group is empty (`Features/Bookmarks/AO3MarkedForLaterWorksBrowser.swift:96–110`, `:138`). No reader metadata is hidden by this addition. **High confidence.**

## 4. iOS T-411 through T-415

### T-411 — largest text sizes

**Looked right in source.** `Features/Reader/TextSizeSlider.swift:12–25` gives both decorative A labels `.fixedSize()` instead of 18-point frames, leaving the Slider flexible; its “Text size” label and points value remain at `:20–21`. `Features/Reader/CustomizeThemeView.swift:159–160` top-aligns the swatch row; `:207–212` keeps names on one line with `.minimumScaleFactor(0.5)`; `:230–237` gives icons `frame(minWidth: 22)` rather than a fixed width. The reader gets natural label widths and less icon/title overlap. Shrinking swatch names is an explicit fit compromise; their full VoiceOver labels and selection traits survive (`:218–219`). **Moderate confidence for largest-size fit; high confidence that the intended constraints changed.** Both views are iOS-only (`:1` in each); this does not establish a macOS layout change. No AX5 screenshot was inspected in this audit.

### T-412 — Save sheet attached to Filters

**Looked right; no broken alternative caller found.** `Features/Search/SearchView.swift:283–300` now attaches `.sheet(isPresented: $showingSaveDialog, ...)` to `filterPanel`. `UIComponents/FilterPanelPresentation.swift:37–50` uses that same panel closure inside a real iPhone sheet and inside an iPad/macOS inspector. It does not omit the new presenter on those platforms. The sole caller of `presentSaveDialog` in SearchView is `onSave: presentSaveDialog` on the panel (`Features/Search/SearchView.swift:685–690`); the function itself only seeds the name and sets the binding (`:841–843`). There is no other off-panel caller stranded by moving the presenter.

`Features/Search/SaveSearchSheet.swift:91–98` dismisses its own sheet on Cancel or after Save. It does not dismiss the inspector/filter panel. Search’s panel-close restoration still listens to `router.panel == .searchFilters` (`Features/Search/SearchView.swift:263–275`), so closing the upper save sheet does not itself discard the draft. **High confidence in caller coverage and state ownership; iPad and Mac presentation remains a runtime check.** Source supports “the inspector still hosts a presenter,” not an unobserved claim that all SwiftUI window configurations were tested.

### T-413 — collection item rows stack

**Looked right.** `Features/Account/AO3CollectionItemsView.swift:578–582` switches between `VStackLayout(alignment: .leading, spacing: 6)` at accessibility sizes and the former horizontal layout otherwise. Header, approval, flag and footer rows use that helper (`:611`, `:683`, `:706`, `:748`, `:788`). The collection kicker gets three lines at accessibility sizes (`:618`), and Remove can wrap instead of claiming its uncompressed horizontal width (`:800–804`). The reader keeps the role, status, switches, creator, action and date; they move vertically rather than disappear.

Bindings are unchanged: approval uses the existing `set` closure (`:685–688`), flags use `Toggle(label, isOn: Binding(...))` (`:751–752`), and Remove still only changes staging (`:797–798`). Read-only approval still combines its accessibility children (`:711`); the layout helper does not reorder the declared children. Existing spacers (`:620`, `:808`) become vertical space, not missing fields. **High confidence in preserved data/actions; moderate confidence in AX5 geometry, unobserved here.**

### T-414 — footers become rows

**Search and BulkNameListEditor looked right.** Search keeps `.onDelete(perform: deleteSavedSearches)` on the saved-search `ForEach`, before the separate explanatory Text (`Features/Search/SearchView.swift:427–453`). Deleting a saved search still indexes only `savedSearches`, records its tombstone and deletes that record (`:873–879`); the help row cannot become an extra deletable search. Deleting the last one selects `searchPrompt` (`:422–423`), which keeps the equivalent guidance (`:464–465`). The help row is declared after the search buttons, so no source-level VoiceOver ordering inversion is introduced.

Bulk’s help Text remains after its TextField and Add button (`Features/Writing/BulkTagStatePicker.swift:157–174`), with `.font(.footnote)` and `.foregroundStyle(.secondary)`. Its added-name buttons remain above those controls (`:145–153`). Search applies the same typography to its help row (`Features/Search/SearchView.swift:451–453`). `.bareListRow()` hides separators and uses `listRowBackground(Color.clear)` without hiding accessibility elements (`UIComponents/AppThemeSurface.swift:368–376`). **High confidence in deletion scope and source order; actual VoiceOver traversal/focus after deletion was not exercised.** These static texts become list rows, so the runtime row/section announcements can differ from footers even though their content order is preserved.

**F3 — P3: Account’s moved notice loses its footer typography.** Unlike the other two conversions, `Features/Account/AccountView.swift:570–572` now has only `Text(notice).pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)`. `UIComponents/SubjectScreen.swift:228–231` shows that `pageBodyRow` changes insets, separator and background, not font or foreground style. The surrounding list (`Features/Account/AccountView.swift:286–297`) supplies no notice-specific typography. Moved out of the footer, a logout/session-expiry notice therefore inherits ordinary row typography instead of the footer’s treatment, giving it more visual weight and potentially more height at large text sizes. The same file’s other notice rendering explicitly uses `.font(.footnote).foregroundStyle(.secondary)` (`:325–329`).

**High confidence in the lost styling; visual extent not measured.** Restore those two modifiers on the moved notice, as Search and Bulk do. This is a small consistency/density regression, not evidence of a changed sign-in state or a VoiceOver ordering bug. Account still declares the notice immediately after the profile card (`:560–573`), and its row background is correctly clear.

### T-415 — Browse ground in Light and Dark

**The code change looked right, with a correction to the “unchanged Dark” explanation.** At **`51c983f6`**, `Features/Search/MediaBrowserView.swift:83–109` applies `.appThemedScroll()` outside the phase switch, covering loading, error and loaded content. `UIComponents/AppThemeSurface.swift:16–22` only returns content unchanged when `appBaseBackground` is nil; otherwise it hides the scroll background and paints the theme’s base.

`Features/Reader/ReaderStyle.swift:124–129` explicitly returns `nil` for Light, warm paper for Sepia, `backgroundColor` for Dark and black for OLED. Thus **Light is a no-op; Dark is not a no-op**. Dark uses the app/reader’s chosen ground (`backgroundHex` is `#16161A`, `:52–58`) rather than being guaranteed to retain whatever system ground happened to show before. That agrees with the shared theme contract in `:113–120` and does not show a reader-facing regression. T-415’s task-row wording that Light and Dark “keep the system grounds” is inaccurate for Dark. **High confidence in the token behavior; no Light/Dark visual comparison performed here.**

## Completion and fixes first

All four requested sections were reviewed; no time cutoff. Runtime modal/keyboard behavior, iPad/Mac presentation, AX5 geometry, VoiceOver traversal and appearance comparisons remain unverified under this audit’s static scope. No new AO3 request path or source/data mutation was introduced by this review. Only this report was written.

- **F1 — P2:** Qualify Android’s failed-Replace assurance when file rollback fails; keep the safety-copy name (3fa wording at the pinned target).
- **F2 — P2:** Store Marked for Later’s successful fetch time with Loaded state; local filters must not make old data say “synced just now.”
- **F3 — P3:** Restore `.font(.footnote).foregroundStyle(.secondary)` on Account’s moved notice.

## Triage (Claude, 2026-10-15 11:30)

All three checked against the code; all real.

- **F1, real:** fixed (3fc). `BackupFileUndo.isUndone`; a Replace whose files could not all
  be put back throws `BackupError.ReplaceNotUndone`, and the screen then says "Not every file
  could be put back" and names the safety copy, instead of "not replaced". Test:
  `BackupFileUndoTest`.
- **F2, real:** fixed (3fc). `AccountListUiState.Loaded.fetchedAt`, stamped when AO3's answer
  is accepted after the session check (iOS `lastSyncedAt`); kept through `copy`; no stamp, no
  "synced" clause. Test: `SubscriptionsWorksRemovalTest` asserts the stamp.
- **F3, real:** fixed in iOS T-416 (the notice's footnote, secondary style).
- **T-415's note:** right, Dark takes the app's own ground (#16161A, as the other tabs), not
  the system's; the TASKS row is corrected in T-416.
