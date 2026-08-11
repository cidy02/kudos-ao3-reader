# Parity-fix implementation report — 2026-08-09

Acting on `parity-review-AND-validation-combined.md`, treating **Part II as authoritative**
wherever it conflicts with Part I.

**Trees**
| Platform | Worktree | Branch | Base |
|---|---|---|---|
| iOS/macOS | `.claude/worktrees/hig-review-reference` | `hig-review` | `e9ed0c6a` |
| Android | `.claude/worktrees/android-exclusion-parity` | `android/exclusion-parity` | `a5a46116` |

**Owner decisions taken before implementing**
1. Commit onto both existing branches.
2. Reading-statistics base set: iOS's is correct (count works read then un-saved).
3. Android adopts iOS's queue-only-work concept.
4. iOS gains a full `savedSearches` export + import.

---

## Verification baselines

Android **199 suites / 660 tests / 0 failures**, reproduced exactly at the base SHA.
iOS **993 tests**, per the review; re-derived after the changes below as **998 passed / 0 failed /
0 skipped** from the xcresult bundle, with `Scripts/verify.sh` **ALL GREEN** (exit 0) across all five
stages including the macOS build.

A third trap, iOS side: the suite is **Swift Testing**, so the familiar
`Executed N tests, with N failures` line reports the XCTest bucket only — it printed
`Executed 0 tests` against a 998-test run. Read `passedTests` from
`xcrun xcresulttool get test-results summary --path <bundle>` instead. (Its per-device row says
1003; the top-level total is 998.)

Two traps worth recording, one of them new:

- The known one: `verify.sh` stage 4 re-runs a subset into the same results directory, so parsing
  `test-results/testDebugUnitTest/*.xml` after a full run yields 61/210. Isolate the task.
- **New, and it cost a full 18-minute run:** the shared build directory had accumulated **814**
  duplicate result XMLs with iCloud-style ` 2.xml`/` 5.xml` suffixes. Gradle 9 then failed the
  whole task with `Cannot access output property 'xmlResultsDirectory' … Failed to create MD5 hash`,
  and a naive XML parse reported **236 suites / 793 tests** — higher than the true count, which
  reads like progress rather than corruption. `rm -rf app/build/test-results
  app/build/intermediates/unit_test_results` before trusting any count.

---

## What was changed

### §1 — P0, data loss (all fixed, each with a test that fails without it)

| Item | Commit | Note |
|---|---|---|
| 1.1 truncating manifest write | `5aaeaa49` | temp + `fd.sync()` + `renameDocument`, `.bak` fallback on import |
| 1.1b prune before commit point | `5aaeaa49` | pruning moved after the manifest write |
| 1.1c permanent wedge | `5aaeaa49` | unparseable primary *and* unparseable conflict copies are now non-fatal |
| 1.2 queue deletions dropped | `f0029482` | 4 new merge tests, all fail on the old service |
| 1.3 annotation deletions dropped | `f0029482` | ditto |
| 1.4 duplicate "Saved for Later" | `f0029482` | matched by kind, memberships remapped, system queue can't be soft-deleted |
| 1.5 membership timestamps ignored | `f0029482` | real timestamps at both call sites |
| 1.6 equal-length edits never sync | `5aaeaa49` (Android), iOS below | direct byte compare after the cheap length reject |

### §2 — P1

| Item | Commit | Note |
|---|---|---|
| 2.1 statistics base set | `07f3d5f9` | Android widened to iOS's; the ten other `observeSavedWorks` consumers untouched |
| 2.2 reveal-all inert in Hide mode | `c066196e` | fixed in `LibraryPrivacy.visibility`; the per-shelf `withReveal` mapping deleted |
| 2.3 logout race | `9df75314` | generation counter + mutex; every session-writing path guarded, not just verify |
| 2.6 uncapped background sweep | `bb165940` | now manual-only per policy; `WorkTagsRefreshWorker` fixed too |
| 2.4 / 2.5 / 2.7 | *(in flight)* | reader locator, XHTML syntax, OLED allowlists |

### §3 — implemented per the *corrected* analysis, not the review's text

| Item | Commit | Note |
|---|---|---|
| Finding 4 / §6 queue-only | `5036b363` | owner decision; `isSaved \|\| hasEpub` coercion removed in both mapper and merge |
| Finding 9 letter-spacing | `4d76b848` | the review had it inverted; fixed Android's own sliders — **and word spacing, which neither report named** |
| Finding 25 collections order | *(with 2.2 branch)* | iOS orders by `dateAdded` desc; Android was alphabetical |
| V-13 saved searches | iOS, below | implemented as a real export+import, not "preserved" |

### §4 — P2 wiring

| Finding | Commit | Note |
|---|---|---|
| 6 UA version | `bb165940` | `BuildConfig.VERSION_NAME`; the invariant now asserts the **value**, not just where it lives |
| 12 series row | `cfb24195` | not a dead ripple — it was not clickable and no series route existed |
| 15 commenter profile | `cfb24195` | reuses the byline route |
| 16 error messages | `cfb24195`, `fe1c805e` | five copies collapsed to one, plus a regression test banning `^[A-Z][A-Za-z]*\(` |
| 17 offline state | `cfb24195` | classified from the transport throwable, no ConnectivityManager polling |
| 22 helpUrl | `cfb24195` | the parser never selected the anchor — parser work, not "one small composable" |
| 23 Writing tabs | *(in flight)* | Series native like iOS, Drafts to the web like iOS |

### §5 — P3

| Area | Commit | Note |
|---|---|---|
| 17 release notes | `4a19bc13` | data was already fetched; only presentation was missing |
| 18 bug-report payloads | `4a19bc13` (Android), `f85359d7` (iOS) | Android gains the git SHA, iOS gains the device model |
| iOS cleartext URLs | `f85359d7` | three real sites; the validation named two that are not URL checks |

### §6 — lead L-2

`BackupValidator.formatInstant` now truncates to milliseconds (`861eba9e`). Made unconditionally, as
the prompt suggests: the defect is unconfirmed on device, but if it is live it aborts the **entire**
import of any Android-written archive on iOS, and the fix is one call.

### iOS

- §1.6 content compare in `FolderSyncService.writeIfChanged`.
- **savedSearches export + import** — new `KudosBackupSavedSearch`, manifest member, `CodingKeys`,
  `decodeIfPresent` for backward compat, export builder and restore path. No version bump (Android's
  `BackupVersion.isSupported` accepts 1…8).
- **Cleartext AO3 URLs rejected** at `BrowserThemeStyle.isAO3URL`, `AO3URLResolver.resolve` and
  `AO3AuthorRoute.isAO3URL`. `allowExternalHost` still permits http for genuinely off-site links, but
  an AO3 host now requires https on that path too.
- **Bug report** carries the `utsname` machine identifier, so an iPhone SE is distinguishable from an
  iPad Pro.

A defect neither report found, surfaced while wiring the saved-search round trip: iOS encoded
`warnings`/`categories` as AO3 **numeric ids** (`"23"`) while Android encodes camelCase names
(`"mm"`, `"noWarnings"`). A round trip would have silently dropped every warning and category
filter. Both are now accepted on decode, case names on encode.

## Verification results

| | Baseline | After |
|---|---|---|
| **Android** | 199 suites / 660 tests / 0 failures | **212 suites / 721 tests / 0 failures** |
| **iOS** | 993 tests | **998 passed / 0 failed / 0 skipped** |

Android counts are from an isolated `:app:testDebugUnitTest --rerun-tasks` — **32 of 32 actionable
tasks executed**, nothing cache-served — and reproduced twice. `android/Scripts/verify.sh` is
**ALL GREEN** across all five stages. `Scripts/verify.sh` on iOS is **ALL GREEN** across all five,
including the macOS build.

**One thing I will not paper over.** During the first full `verify.sh` run after the last commits,
stage 2 reported **1 failure out of 721**. Two subsequent full runs — another `verify.sh` and a
second `--rerun-tasks` isolation — are both clean at 721/0. I could not identify the test: the next
stage had already deleted the results XML, and it has not recurred in three later runs. The most
likely cause is residual state from a `testDebugUnitTest` I killed at a 10-minute timeout minutes
earlier (the same run that exposed the duplicate-`.class` corruption). **It should be treated as an
unexplained one-off, not as green**, and watched on the next few CI runs — new Robolectric tests that
register a `ContentProvider` (the fake SAF provider) are exactly the kind of thing that can leak
across a shared JVM.

---

## §7 — tests where the defects live

`backup/SyncRepository.kt` had **no test at all**. It now has seven, running the real repository
against a fake SAF `DocumentsProvider` under Robolectric
(`KudosTests`-equivalent: `SyncRepositoryTest.kt` + `FakeTempDocumentsProvider.kt`), covering the
atomic manifest write and its `.bak`, recovery from a corrupt manifest, recovery from a zero-length
manifest without pruning `Works/`, an unparseable conflict copy surviving on disk, prune ordering,
and equal-length content changes. That last one is what exposed finding 13 above.

`BackupCompatibilityTest.kt` gained branches rather than a new file, as asked: queue-deletion
propagation, annotation-deletion propagation, system-queue-by-kind with membership remapping,
membership timestamps in the conflict clock, and queue-only preservation on restore.

Every fix in §1 and §2 has a test that **fails when that fix alone is reverted**, verified by
actually reverting each one. Where a signature change made a clean revert impossible, the behaviour
was reverted instead and the failure recorded.

---

## What the reports got wrong that neither validation caught

1. **`AvailabilitySweep.kt` does not exist.** The file is `works/WorkAvailabilitySweep.kt`, and the
   worker is `works/AvailabilitySweepWorker.kt`. Every §2.6 line citation is against a filename that
   is not in the tree.

2. **"No spacing" is wrong, and the real story is better and worse.** §2.6 says the Android sweep
   fires "with no spacing". Android already paces *every* AO3 request globally:
   `AO3RequestCoordinator.awaitSpacingTurn()` enforces `minDelayBetweenRequestsMillis = 600`
   (`AO3NetworkConfig.kt:6`, explicitly "Apple paces at 0.6s … Keep parity"), and `AO3Client.kt:149`
   and `:199` route through it. So the sweep was paced at 0.6s, not unpaced. The genuine defects —
   no cap, no recheck-interval skip, no oldest-first, not cancellable, and running unattended on a
   timer — all stand, and the sweep-specific 1500 ms spacing was still missing.

3. **The policy prohibition is stronger than §2.6's remedy.** `docs/AO3_NETWORKING_POLICY.md:41`
   says plainly: *"No background polling beyond the existing BGTask folder-sync refresh; no periodic
   full-library metadata sweeps."* §2.6 asks only for `Constraints` and pacing. Adding constraints
   to a job the policy forbids outright would have left the violation in place, so the periodic
   availability sweep is now unscheduled entirely (manual-only, matching iOS) rather than merely
   constrained.

4. **`WorkTagsRefreshWorker` has the same defect and is named nowhere in either report.** It walked
   every saved work with one AO3 request each, **daily** — a higher-frequency full-library sweep
   than the 7-day one the reports focused on — and returned `Result.retry()` on any single failure,
   so one 404 re-ran the entire library walk with WorkManager backoff.

5. **§1.1's suggested fix has a SAF trap the report does not mention.** `DocumentFile.createFile`
   appends its own extension when the display name's extension does not match the MIME type, so a
   temp created as `manifest.json.tmp` can land as `manifest.json.tmp.json` — which the existing
   conflict-copy glob (`startsWith("manifest") && endsWith(".json")`) would then fold in as a
   *conflict manifest*, and a half-written one would throw. `renameDocument` does not mangle names,
   only `createDocument` does. The implementation therefore never looks the temp up by name and
   excludes staging names from the glob.

6. **§1.6's "cheap content hash" is the wrong primitive.** Deciding whether the bytes differ
   requires reading the remote file either way; once it is in memory a direct comparison is exact,
   cheaper than hashing, and less code. Both platforms now keep the length check as the cheap reject
   and compare bytes only when the length cannot already prove a difference.

7. **§3's finding-5 pass-through is not a pass-through.** Android's `BackupWork` carries
   `epubPreservationStatusRaw` / `preservedAt` / `lastPreservationAttemptAt`, but Android's
   *domain* `SavedWork` has no preservation fields at all — so there is nowhere to hold the values
   between import and re-export. Making them survive needs three new Room columns and a schema
   migration, not a mapper line. See Deferred.

---

8. **The two Account → Writing tabs are not equivalent, so "remove them" would have been wrong.**
   Finding 23 calls both dead. On iOS, **Series is native** — `AccountView.swift:383` routes it
   through the author profile's series tab — while **Drafts is deliberately web-only**
   (`AccountMoreOnAO3View.swift:11-13`, `pathSuffix: "works/drafts"`). Deleting either would have
   widened the gap the finding was filed to close.

9. **Word spacing has the same defect as letter spacing and is named nowhere.** Finding 9 is about
   the letter-spacing slider; the word-spacing slider allowed `0..1.0` against a validator ceiling
   of `0.6` — a wider overshoot than the one that was filed.

10. **Five error-message helpers, not four.** Finding 16 counts four `displayMessage()` copies;
    `browse/BrowseUi.kt` has a fifth under a different name (`browseMessage()`), with six call sites.

11. **Finding 12's citation points at the wrong screen.** `AppNavHost.kt:674-683` is the *author
    profile* call site. The work detail's series row had no `onOpenSeries` parameter and was not
    clickable at all — and no series route existed to wire it to, so "the URL builder, repository and
    parser all exist" understated the work.

12. **`ReaderColorTheme` could not express OLED at all.** Finding 20 reads as a one-line mapper bug
    (`Oled → Dark`). The mapper had nothing else to map *to*: Android's reader had no OLED theme,
    while iOS's `ReaderTheme` has had `oled` since `ReaderStyle.swift:28`. The reader-side gap was
    the actual divergence.

13. **Finding 2's real consequence on Android is data loss, not a missed sync — and it is not in
    `writeIfChanged` at all.** This only surfaced once `SyncRepository` had tests.
    `BackupMergeService` queued the incoming EPUB for writing whenever the archive carried one,
    **completely ungated by the LWW result computed two lines above it**. Because sync-down runs
    before sync-up, the stale remote copy was restored over a newer local file and then exported back
    out. So a locally changed EPUB was *destroyed*, not merely "never syncs" as the finding says.
    Fixing `writeIfChanged` alone — which is all §1.6 asks for — would not have fixed the user-visible
    behaviour. The font merge already compared content and preserved rather than clobbered; works now
    match. Commit `a03226b1`.

14. **`HTMLWorkSanitizer.swift` is in `Services/`, not `Reading/`** (E2 and §2.5 both cite
    `Reading/HTMLWorkSanitizer.swift`). `EPUBBuilder.swift` *is* under `Reading/`, so the two live in
    different directories despite being cited as neighbours.

15. **The build directory corrupts itself under iCloud, twice, in different ways.** Beyond the 814
    duplicate result XMLs, a later run accumulated **299** duplicate `.class` files
    (`BackupUserTagMergeTest 3.class`) in `intermediates/`, which made
    `compileDebugUnitTestKotlin` fail with the same unreadable-output MD5 error — presenting as a
    *hang* of the whole test task, not a clear error. Worth a `.nosync` on `app/build` or moving the
    checkout out of `~/Documents`.

---

## Deferred, with reasons

- **Finding 5 (preservation-state pass-through).** Deferred. Cost is a Room schema migration; the
  residual loss the validation actually confirmed is the original `preservedAt` timestamp being
  replaced with restore time (iOS re-derives status and `hasEPUB` via
  `ReadingQueueService.swift:201-206`). A migration on the works table is a data-loss-shaped risk,
  and this is the lowest-value item in the list. To do it: add the three nullable columns to
  `WorkEntity`, carry them in `EntityMappers`, map them in `BackupMappers` both ways, and add the
  migration beside the existing ones in `KudosDatabaseMigrations.kt`.

- **Finding 10, PDF/TXT half.** The HTML path is done and is the reliable one (AO3 downloads are
  HTML, so a `div.notes` *is* a note). PDF and TXT carry no markup to key off, and iOS handles them
  with `Services/AuthorNoteDetector.swift` — a ~200-line engine of scoped indicators with
  edge-weighted prefix/phrase matching. Approximating that with a quick heuristic would produce
  false positives, and formatting narration as apparatus is worse than missing a note. Left as its
  own change.

- **E7's dropped collection `description`.** Not in the task list, and confirmed real: Android's
  `CollectionEntity` has `description`, it is rendered and written to the backup
  (`BackupMappers.kt:238-239`), and iOS's `ArchivedCollection` has no such key — so an
  Android→iOS restore drops it. Filed here rather than fixed; it belongs with the iOS manifest work.
