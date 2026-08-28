# Validation of the iOS ↔ Android parity review — 2026-08-08

**Verdict:** trustworthy with the corrections below

Validated against the trees the review names, at the SHAs it names (both confirmed:
`hig-review-reference` @ `e9ed0c6a`, `android-exclusion-parity` @ `a5a46116`; 214 Swift + 85
test files, 281 Kotlin + 93 test files — all four counts reproduce).

Fifteen findings and three verified-agreement sections were sampled. Eleven hold as written.
Five carry errors, one of which (**finding 4**) would ship a fix that does not fix the
scenario the finding leads with. The document also contradicts itself in four places about
whether the test suites were run, and its coverage claim ("all 21 areas closed") is
overstated by at least five subsystems, one of them privacy-relevant.

The five items the validation prompt asked me to attack hardest: findings **1**, **5** and
**21** and **V-9** survive intact and are precisely cited. Finding **25**'s central claim
("disjoint sets") is false as stated, though the divergence it reports is real.

---

## Findings sampled

| # | Kind | Verdict | One-line reason |
|---|---|---|---|
| 1 | blocker | **CONFIRMED** (2 evidence errors) | `"wt"` truncating write and iOS `.atomic` both verified; the ordering claim and one scenario clause are wrong — see E5 |
| 3 | real-bug (docs) | **CONFIRMED** | Two of four clusters re-verified independently; both stale — see below |
| 4 | real-bug | **OVERSTATED** | Divergence real and broader than reported, but the cited mechanism, scenario and fix are wrong — see E1 |
| 5 | real-bug | **CONFIRMED** | `toBackupWork` omits all nine; `explicitNulls = false`; iOS decode defaults exact at `:561-568` |
| 6 | real-bug | **CONFIRMED** | `APP_VERSION = "0.1.0"` vs `versionName = "0.2.0"`, exact lines |
| 8 | real-bug | **CONFIRMED** | Zero `lastScrollFraction` reads in `Features/ReaderReadium/`; only consumer is the macOS reader |
| 12 | real-bug | **CONFIRMED** | `onOpenSeries` has exactly two hits; `AppNavHost.kt:674-683` omits it. Reachable — the row is `Modifier.clickable` |
| 16 | real-bug | **CONFIRMED** | All six `error.toString()` sites and all four `displayMessage()` definitions at the exact cited lines |
| 18 | minor | **CONFIRMED** | `|| existing?.hasEpub == true` at `:64`; `currentEpubIds` filesystem filter at `BackupRepository.kt:112-118` |
| 19 | minor · iOS-side | **OVERSTATED** | The load-bearing grep claim is false — see E3; also mislabelled in the Summary — see E7 |
| 20 | real-bug | **CONFIRMED** | `ReaderColorTheme` has three cases; `ReaderSettingsMapper.kt:50` collapses Oled→Dark |
| 21 | real-bug | **CONFIRMED** | `appThemes`/`readerThemes` allowlists omit `"oled"`; `BackupSettings.kt:72` emits it; `fromStorage` falls back to `Light` |
| 23 | gap | **CONFIRMED** | Both placeholders are unconditional `when` bodies; the Inbox one really is dead (`KudosAppContainer.kt:162` non-null `by lazy`) |
| 24 | minor · iOS-side | **CONFIRMED** | Independent extraction reproduces 28 titles, 11 Title Case / 17 sentence case exactly |
| 25 | real-bug | **OVERSTATED** | Three shelves do diverge; "disjoint sets" is false — see E2 |
| 28 | gap | **OVERSTATED** | Conclusion holds; ruled-out (a) is false — Android does reference the concept — see E4 |
| V-7 | agreement | **CONFIRMED** | 21/21 declared on both; `toBackupSettingsPayload` really does stop at `accentColorHex` |
| V-9 | agreement | **CONFIRMED** | All nine statistics plus `completionRate` verified formula-for-formula; `hasStarted` re-listing matches term for term |
| V-12 | agreement | **CONFIRMED** | Home predicates, sorts, `recency` helper and the 12-cap identical clause for clause |

Line drift across the sample is small — most citations are exact, the rest within ±2. One
exceeds tolerance: finding 5 cites `KudosBackup.swift:1966` for the `ao3WorkID` re-derivation;
it is at **`:1960`**.

---

## Errors found

### E1 — Finding 4 cites the wrong mechanism, and its recommended fix does not fix its own scenario

**Claimed** (finding 4, scenario): *"Back up, restore on Android. `restored.isSaved` is false
and `existing` is absent, but `restoredHasEpub` is true because the archive carried the EPUB,
so `:193` evaluates to true."*

**The code shows** this is impossible. `backup/BackupMergeService.kt:179-182` declares
`mergeWork(existing: SavedWork, restored: SavedWork, archived: BackupWork)` — `existing` is
non-null by signature, and `:193` dereferences it (`existing.hasEpub`). The `existing == null`
case never reaches `:193`: `backup/BackupMergeService.kt:68-70` short-circuits to `restored`
directly.

The clean-restore scenario the finding leads with is caused by a line the review never
mentions — **`backup/BackupMappers.kt:143`**:

```kotlin
// Prefer archive flag; default to saved when Apple marks hasEPUB so the
// work appears in the offline Library after import.
isSaved = isSaved || hasEpub,
```

inside `BackupWork.toSavedWork`, which builds `restored` *before* `mergeWork` runs. Three
consequences:

1. **The divergence is broader than reported.** It applies on both the fresh-install path and
   the merge path, because `restored` is already forced saved.
2. **The recommended fix is incomplete.** The review says *"the fix is to delete the clause:
   `isSaved = restored.isSaved` in the `incomingWins` branch, matching iOS exactly."* Applying
   only that leaves `BackupMappers.kt:143` in place, so restoring an iOS queue-only work onto a
   clean Android install still produces a full Library item — the exact outcome the finding's
   title promises to fix.
3. **"History: not recorded" is false.** `backup/BackupMappers.kt:141-142` is a comment
   recording the decision and its rationale. This is a deliberate design choice with a stated
   reason, not an oversight — which changes the recommendation from "delete the clause" to
   "decide whether the offline-Library rationale outranks iOS's queue-only semantics", i.e.
   the same product decision the review reserves for Saved for Later in finding 25.

The finding's ruled-out (a) — *"that the `else` branch compensates"* — checks the wrong
sibling. The path that needed checking was `existing == null`.

### E2 — Finding 25's "disjoint sets" is false

**Claimed:** *"the History divergence is not a near-miss — the two platforms show **disjoint
sets of works** under the same name."*

**The code shows** substantial overlap, and it is the *typical* case:

- iOS `Features/Library/LibrarySectionKind.swift:107-109` — `!hasEPUB && !isQueuedForLater`
- Android `library/LibraryQuery.kt:139-143` — `lastReadDate != null`

A finished work whose EPUB was freed — precisely the population iOS's own comment
(`LibrarySectionKind.swift:103-106`, "Works whose EPUB was freed after finishing") says the
shelf exists for — almost always has a `lastReadDate`, so it appears on **both**. Neither set
contains the other; they intersect. The finding's own prose two paragraphs later describes
this correctly ("a finished work whose file you freed appears in iOS's History and appears in
Android's **only if** it was ever opened"), so the headline word contradicts the body.

Severity is unaffected — the shelves genuinely mean different things — but "disjoint" is the
sentence a planner will quote, and it is wrong.

### E3 — Finding 19's load-bearing grep claim is false

**Claimed:** *"Grepping the whole iOS tree for these names returns hits in `Models/Models.swift`
only — no feature writes them, no view reads them."*

**The code shows** three hits outside `Models.swift`, in the backup transport:

- `Services/KudosBackup.swift:616` — `let syncStatusRaw: String?` on the archived collection payload
- `Services/KudosBackup.swift:629` — `syncStatusRaw = collection.syncStatusRaw` (export)
- `Services/KudosBackup.swift:1282` — `collection.syncStatusRaw = archived.syncStatusRaw ?? collection.syncStatusRaw` (restore)

So `WorkCollection.syncStatusRaw` is serialised into every archive and restored from it. That
falsifies the grep as stated, and it invalidates the finding's closing safety note — *"Deleting
on either side is safe only after confirming no archive in the wild carries a value — which,
per the evidence above, none can"* — since deleting the property is a **manifest schema
change**, not an inert removal. (The `lastSyncAttemptAt` / `lastSyncError` half of the claim is
correct: those two really are `Models.swift`-only.)

### E4 — Finding 28's ruled-out (a) is false

**Claimed:** *"Ruled out: (a) that Android implements the behaviour without the setting — no
code references the concept, and `SeriesPreservation.kt` (Android's series-preservation file)
contains neither name."*

**The code shows** Android references the concept in that exact file:

- `library/SeriesPreservation.kt:29` — `SeriesPreservationPrompt(..., val threshold: Int, ...)`
- `library/SeriesPreservation.kt:36-37` — `canAutoPreserve get() = ... && knownCount <= threshold`
- `library/SeriesPreservation.kt:56-57` — `autoPreserveLabel get() = "Always auto-preserve series under $threshold works"`
- `works/WorkDetailScreen.kt:815` and `:817` — construct the prompt with `threshold = 5` **hard-coded**

The narrow claim ("contains neither name") is technically true and the finding's conclusion
survives — `canAutoPreserve` and `autoPreserveLabel` have no consumers (`.message` at
`WorkDetailScreen.kt:736` is the only property read), so the feature is not wired. But "no code
references the concept" is wrong, and the hard-coded `threshold = 5` is the same value the
round trip resets to, which is worth knowing: the recommendation's second half ("it needs a
settings control and a hook in the save-for-later path") is cheaper than described, because the
threshold is already threaded into a real prompt type at two construction sites.

### E5 — Finding 1: the ordering claim is backwards, and one scenario clause is wrong

The core of finding 1 is **correct and precisely cited** (`FolderSyncService.swift:689`,
`:707-709`; `SyncRepository.kt:205`, `:226`; comment at `:673-678`, cited as `:675-679`). Two
supporting claims are not.

1. **Claimed:** *"The *ordering* of the iOS design was ported faithfully (assets first,
   manifest last, then orphan pruning)."*
   **The code shows** Android prunes *before* the manifest write: works pruning at
   `SyncRepository.kt:176-179`, fonts at `:193-196`, manifest at `:200-205`. iOS prunes *after*
   the commit point (`FolderSyncService.swift:697` and `:701`, following the manifest write at
   `:685-690`), and says so in the comment the finding quotes. Android therefore also loses the
   after-the-commit-point discipline — a second, independent divergence in the same 40 lines,
   which strengthens the finding rather than weakening it.
2. **Claimed:** *"the orphan-pruning passes at `SyncRepository.kt:176` and `:193` then have no
   manifest to compute 'expected' from."*
   **The code shows** `expectedWorks` / `expectedFonts` are built from the in-memory
   `snapshot.works` / `snapshot.fonts` (`SyncRepository.kt:161-170`, `:186-188`), never from the
   manifest file. The pruning passes are unaffected by a corrupt manifest.

### E6 — Four places in the document state the suites were never run

The *Verification runs* section (added last) reports both suites green. Four earlier passages
were never updated and now flatly contradict it:

- `:22-24` — *"(2) run `Scripts/verify.sh` and `android/Scripts/verify.sh`, neither of which this review ran"*
- `:131-132` — *"**Not established:** no test suite was run on either platform and nothing here is runtime-verified."*
- `:2593-2595` — *"**Not run:** neither `Scripts/verify.sh` nor `android/Scripts/verify.sh`. No build, no test suite, no simulator or emulator. Every claim here is static reading of source."*
- `:132-134` — *"Two questions specifically cannot be closed by reading — lead L-2 … "*, written before L-2 was probed.

Related: the ledger's **Resume here** block is stale in the opposite direction. `:20` says
*"nothing is outstanding — all 21 areas are closed"*, and `:27-28` — nine lines later — says
*"areas 1, 5, 7, 8, 19 are untouched; 6, 9, 12, 13, 16, 18, 20, 21 are partial."* A cold reader
resuming from this document is told both things on the same screen.

### E7 — The Summary mislabels finding 19

`:122-123` — *"Two findings are iOS-side outright (19, 24)."* Finding 19 is titled *"**Both
platforms** carry dead persistence schema, in opposite directions"* (`:1607`) and is filed under
the *Bugs present on both platforms* heading. Only finding 24 is iOS-side outright. (The
validation prompt inherited this error, describing 19 and 24 as "both `minor` findings that are
iOS-side".)

### E8 — Area 17 is declared closed against a table that is 20% filled

`:60` — area 17 *"✅ done … See the re-check table"*, and `:34` — *"**Do not redo:** area 17
(closed…)"*. The *Already-known divergences, re-checked* table (`:1739-1745`) has **four of its
five rows marked ⬜ with an empty Status column**. The table's own header promises *"Status
filled in as each area is reached."* Only the Android self-update row was checked.

This matters for the audit the validation prompt asked for: I confirmed independently that none
of the 28 findings restates one of the five known divergences — but the review cannot claim to
have confirmed that, because it never re-checked four of the five.

### Finding 3 — independently verified, holds

Two of the four spot-checked clusters were re-verified against the trees:

- **Queue-only cluster.** `docs/audits/ANDROID_PARITY_REPORT.md:231` asserts *"On Android there
  is no `isQueuedForLater`/queue-only concept at all in `SavedWork` … or `LibraryQuery`."* It is
  present at `core/model/SavedWork.kt:21` and `:82`, `data/local/entity/WorkEntity.kt:59`,
  `home/HomeSectionKind.kt:50,59,64`, and `library/LibraryQuery.kt:22`. **Stale.**
  `ANDROID_PARITY_FINDINGS_VERIFIED.md:23` still lists it among *"Highest-priority CONFIRMED
  majors (still open)"*.
- **Reading-statistics cluster.** `ANDROID_PARITY_REPORT.md:306` asserts `hasStarted` *"omits
  `readiumLocator`"*; `library/ReadingStatistics.kt:87` contains
  `!work.readiumLocator.isNullOrBlank()`. The `formatCompactNumber` rounding fix is in place at
  `library/ReadingStatisticsScreen.kt:490-500`, with a comment naming the audit's own 999,950
  worked example. **Stale, in all its claims.**

The finding's framing — that the corpus is systematically behind the code, not merely drifting
— is supported.

---

## Coverage gaps

Subsystems that no finding, no V-section and no ledger row addresses. Confirmed by grepping the
review text for each identifier.

1. **Mature-content privacy gate — the most material of these, and privacy-relevant.**
   iOS `Features/Privacy/MatureContent.swift` (`PrivacyGate`, `LAContext.evaluatePolicy`,
   `isHidden`, `hasVisibleMatureWorks`) is consumed in **11 files** including
   `Features/Library/LibraryView.swift:19,89,482,508`, `Features/Library/Collections.swift`,
   `Features/Account/AccountView.swift`, `Features/Bookmarks/AO3AccountWorksList.swift`,
   `Features/Authors/AO3SeriesDetailView.swift`. Android's `app/PrivacyGate.kt` is consumed in
   **three**, all under `home/` (`HomeViewModel.kt`, `HomeScreen.kt`, `HomeSectionListScreen.kt`).
   `library/LibraryPrivacy.kt` never consults reveal state at all, where iOS's `isHidden`
   includes `&& !isRevealed(work)`.
   The string `PrivacyGate` appears **zero** times in the review; `MatureContent` appears once,
   as a settings-payload field name in V-7. Area 16 checked that the three privacy *settings*
   round-trip; nothing checked the behaviour they drive. This looks like an unfiled divergence,
   not just a gap.

2. **Background scheduling / workers.** iOS `Services/FolderSyncBackgroundTask.swift` (83 lines)
   against Android `backup/FolderSyncWorker.kt` (23 lines), `works/AvailabilitySweepWorker.kt`,
   `works/WorkTagsRefreshWorker.kt`, `works/KudosWorkerFactory.kt`, `KudosApplication.kt`.
   Area 14's iOS roots stop at `FolderSyncService.swift`. `FolderSyncWorker` appears zero times
   in the review. Sync cadence and constraints are user-visible (does an Android device sync
   without the app open?) and untested on both sides.

3. **Download queue.** iOS `Services/DownloadQueue.swift` (146 lines) against Android
   `works/DownloadQueue.kt` (284 lines) — a 2× size difference. Area 13 excludes it as
   *"scheduling rather than conversion"*, and no other area picks it up. `DownloadQueue` appears
   once in the whole review, in passing inside finding 12's evidence.

4. **In-app WebView fallback and its URL trust boundary.** Android `web/AO3WebUrlPolicy.kt`,
   `web/AO3WebViewFallbackScreen.kt`, `web/BrowserThemeStyle.kt`. Zero mentions. Notable because
   `docs/audits/ANDROID_PARITY_FINDINGS_VERIFIED.md:23` lists *"WebView login host `endsWith`
   trust boundary"* among its highest-priority confirmed-open majors, and area 2's ledger row
   explicitly leaves *"native-vs-web login flow choice"* unread. A security-relevant claim in the
   corpus the review declares untrustworthy was neither confirmed nor refuted.

5. **AO3 work-page metadata parser.** Android `network/ao3/work/` (7 files, incl.
   `AO3WorkMetadataParser.kt`, `AO3SparseWorkEnricher.kt`, `AO3EpubDownloader.kt`,
   `AO3DownloadUrlBuilder.kt`) and `network/ao3/chapters/` (`AO3ChapterIndex.kt`,
   `AO3ChapterIndexRepository.kt`). V-5 verified the *search blurb* parser; area 6 covered the
   work-detail UI and write endpoints. The parser that produces every saved work's metadata was
   not compared. Zero mentions of `AO3WorkMetadataParser` or `AO3ChapterIndex`.

---

## Exclusions judged unreasonable

- **Area 14 — "collection/queue/annotation merge bodies".** This is ~234 lines in the *same
  file* that produced findings 4 and 18: `mergeCollections` (`BackupMergeService.kt:376-451`),
  `mergeQueues` (`:485-582`), `mergeAnnotations` (`:583-642`). The stated reason — *"the works
  path is the one carrying user content"* — is contradicted by the review's own finding 26,
  which opens *"Annotations travel between devices — they are manifest **v8** content and
  round-trip through backup and folder sync."* Both findings in the read half of this file were
  merge-rule bugs; the unread half is the highest-prior-probability place left in the codebase.
  **Unreasonable.**

- **Area 13 — "the download queue, which is scheduling rather than conversion".** The download
  queue determines request volume and concurrency against AO3. V-4 declares
  `docs/AO3_NETWORKING_POLICY.md` binding and verifies the *client's* pacing constants — but a
  queue that fans out N downloads is exactly what those constants exist to bound, and it is
  twice the size on Android. **Unreasonable as scoped**; it belongs to area 3, not 13.

- **Area 9 — TTS.** iOS ships 1,287 lines across four files
  (`Features/ReaderReadium/ReaderSpeechController.swift` 810,
  `ReaderSpeechSettingsSection.swift` 220, `ReaderSpeechPreferences.swift` 189,
  `ReaderSpeechSkip.swift` 68). Android ships `reader/speech/ReaderSpeechController.kt`, 229
  lines. Both persist voice/rate/pitch (iOS `UserDefaults` at
  `ReaderSpeechPreferences.swift:31-48`; Android `reader/settings/ReaderPreferences.kt:40-43`
  with controls at `reader/ReaderScreen.kt:1170-1183`), so it is not a total gap — but a 5.6×
  line ratio in an area declared closed is not "no cross-device contract", it is unmeasured.
  **Unreasonable.**

- **Area 16's ledger claim over-reaches.** *"every stored setting checked for an Android control
  → 28"*. What was actually checked is the **21 backup-payload fields**. iOS's speech voice /
  rate / pitch are stored settings outside that payload and were not in scope. The finding is
  fine; the ledger sentence is broader than the work.

- **Judged reasonable:** area 15's DAO query semantics, area 10's collection CRUD and queue
  drag-reorder (genuinely local UI with no wire format), area 1's onboarding copy, area 19's
  skeleton states, area 8's orphaned-author rendering.

- **Admissions confirmed accurate, not narrower than the true gap:** the EPUB builder's
  generated documents really were compared only at the level of which Dublin Core elements are
  emitted; TTS really was not compared; the Settings screens' per-row wording really was not
  diffed.

---

## Verification re-run

**Android — the reported figures reproduce exactly.** Parsing
`android/app/build/test-results/testDebugUnitTest/*.xml` grouped by run generation:

| Run generation | Suites | Tests | Failures | Skipped |
|---|---|---|---|---|
| 08-07 22:11 | 25 | 61 | 0 | 0 |
| 08-08 17:44 | 61 | 210 | 0 | 0 |
| **08-08 17:46** | **199** | **660** | **0** | **0** |

The 17:46 generation is the review's `--rerun-tasks` run and matches its reported **199 suites /
660 tests / 0 failures / 0 skipped** to the digit. The 17:44 generation of 61 suites is
`verify.sh` stage 4 (the persistence/reader/network subset), consistent with the review's account
of the cache-served first pass.

**One caveat for anyone repeating this.** That directory is *not* wiped between runs: it now
holds three generations plus 61 macOS-style `… 2.xml` duplicates, so a naïve `*.xml` aggregate
today yields 285 files / 931 tests. The review's stated method ("Counts parsed from
`app/build/test-results/testDebugUnitTest/*.xml`") produced the right answer for its run and
will not for the next one.

**iOS — not re-run.** Skipped per the validation prompt's cost guidance; it needs the
`Vendor/MuPDF.xcframework` symlink and a full simulator test pass. The 993 tests / 91 suites
figure is unverified here.

**Lead L-2 — the characterisation is honest.** The mechanism checks out end to end:
`backup/BackupValidator.kt:161` is `fun formatInstant(instant: Instant): String = instant.toString()`;
`backup/BackupRepository.kt:31` is `private val clock: () -> Instant = { Instant.now() }`;
`Services/KudosBackup.swift:228` declares `let exportedAt: Date` **non-optional**, and the custom
decoding strategy at `:193-206` throws `DecodingError` when neither formatter matches — so a
6-digit fraction does abort the whole manifest decode, not just one field. "The assumption of
safety is disproven; the defect itself is unconfirmed" is exactly right: the JBR probe is a
desktop JVM and the review says so, the desugaring argument is stated as removing a defence
rather than proving a hazard, and the one remaining device step is named. Not overstated.

---

## What I could not check

- **The iOS suite** (993 tests / 91 suites) — not re-run; see above.
- **The other two of finding 3's four clusters** — the `WorkImporter.saveMetadataOnly` /
  `ReadingQueueRepository.removeWork` pair (L-4) and the MuPDF entry in
  `docs/iOS_Issues_Found_While_Porting.md:45-60`. The prompt asked for two; I did the queue-only
  and reading-statistics clusters.
- **13 of the 28 findings** — 2, 7, 9, 10, 11, 13, 14, 15, 17, 22, 26, 27, and the
  *Asymmetric test coverage* line counts. Sampling stopped at the prompt's quota plus the five
  named priorities.
- **13 of the 16 V-sections** — V-1 through V-6, V-8, V-10, V-11, V-13, V-14, V-15, V-16.
- **Anything runtime.** No emulator, no simulator, no screen reader. The rendered-height half of
  finding 11 and the TalkBack half of V-16 remain open exactly as the review states.
- **Whether the privacy-gate divergence in Coverage gap 1 is a defect or a deliberate scope
  decision.** I established that Android's `PrivacyGate` reaches only `home/` and that
  `library/LibraryPrivacy.kt` ignores reveal state; I did not trace whether some other Android
  surface compensates, and I did not search `TASKS.md` or the Android branch's `docs/` for a
  recorded decision. It is reported as a coverage gap with a strong lead, not as a finding.
