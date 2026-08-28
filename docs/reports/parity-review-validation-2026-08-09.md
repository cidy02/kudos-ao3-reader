# Validation of the iOS ↔ Android parity review — 2026-08-09

**Verdict:** trustworthy with the corrections below — **except its "Verified agreement" section
and its coverage claim, neither of which should be relied on as closure.**

The 28 findings are largely sound: the blocker holds, the framing holds, the citation discipline
is genuinely good, and both verify suites reproduce exactly. The risk sits where a reader would
least expect it — in the parts that *close* areas:

- **Of the 16 V-sections, six do not hold and one (V-13) is outright false.**
- **Two "deliberately not read" exclusions hide four unfiled cross-platform defects**, three of
  them in a single excluded function group.
- **Two areas closed at "0 findings" (17 and 18) each contain real divergences** — including one
  whose stated justification is contradicted by the code it cites.
- **The review's own self-declared "highest-value follow-up" is misdescribed** — there is a real
  privacy defect there, but not the one it names.

**Second-pass note.** The artefact at HEAD (`eafc948d`, 2,897 lines) is *post-correction*: a
2026-08-08 validation applied E1–E3, E5, E7 and filled the re-check table. This report validates
the current text and independently re-tests that pass's conclusions — **including two I found it
got wrong** (E20, E21).

Validated against the trees at the SHAs named: `hig-review-reference` @ `e9ed0c6a`,
`android-exclusion-parity` @ `a5a46116`. All four file counts reproduce exactly (214 Swift + 85
test; 281 Kotlin + 93 test).

**Sampled:** **25 of 28 findings** (all but 4, 18, 28), **all 16** V-sections, R-1, L-2, all four
challenged exclusions, a direct sweep of areas 17 and 18, the ledger, the known-divergence
boundary, and both suites. **All 21 ledger areas were independently checked.**

---

## Findings sampled

| # | Verdict | One-line reason |
|---|---|---|
| 1 `blocker` | **CONFIRMED** | Truncating `"wt"` write + iOS `.atomic` both exact; two errata, one of which *worsens* it — E9 |
| 2 | CONFIRMED | iOS `FolderSyncService.swift:707-708` has the identical byte-length skip; genuinely both-platforms |
| 3 | **OVERSTATED** | Substance holds — all clusters stale — but only **three** are enumerated, not four — E17 |
| 5 | **OVERSTATED** | Mechanism exact, but iOS self-heals the preservation trio on restore — E10 |
| 6 | CONFIRMED | `AO3UserAgent.kt:14` `"0.1.0"` vs `build.gradle.kts:28` `"0.2.0"`; the invariants guard checks placement, not value |
| 7 | CONFIRMED | Ten-parameter set difference and `sort_direction` reachability check out |
| 8 | CONFIRMED | Zero `lastScrollFraction` reads under `Features/ReaderReadium/`; macOS consumer is `#if os(macOS)`-guarded; not a re-report of the two-reader split |
| 9 | **OVERSTATED** | iOS does **not** validate letter-spacing on restore; the divergence inverts — E13 |
| 10 | **OVERSTATED** | Layer 2 falsified: iOS ships `.author-note` CSS *inside* the EPUB — E12 |
| 11 | **OVERSTATED** | Gap real, but the Library scenario is unreachable and the clickable count is wrong |
| 12 | CONFIRMED | Dead clickable real, unreachable by any other path |
| 13 | CONFIRMED | Genuine drift, `drift` severity honest |
| 14 | CONFIRMED | Direction correct; if anything undercounts Android |
| 15 | CONFIRMED | Parsed and stored, no UI consumer, no reachable route |
| 16 | CONFIRMED | All ten citations exact; one of the six sites (`SettingsScreen.kt:283`) is dead code — 5 live + 1 defensive |
| 17 | CONFIRMED | No connectivity classification anywhere on Android |
| 19 | **OVERSTATED** | "No feature writes them" false — `PersistenceSync.swift` writes `syncStatus` at 5 sites — E14 |
| 20 | CONFIRMED | `ReaderColorTheme.kt:9` has three cases; `ReaderSettingsMapper.kt:50` collapses Oled→Dark. Not double-counting 21 — different code, no backup involved |
| 21 | **CONFIRMED** | Allowlist omits `"oled"`, exporter emits it, silent substitution to light |
| 22 | **OVERSTATED** | `helpUrl` is never *populated*; the "one small composable" fix does not exist — E11 |
| 23 | CONFIRMED | Placeholders unconditional; Inbox sibling dead; `userSeriesUrl` correction accurate |
| 24 | **OVERSTATED** | Missed every indirected title; recount ≈20/22, not 11/17 — E15 |
| 25 | **OVERSTATED** | History overlap now correct, but Collections is counted as a match and diverges — E4 |
| 26 | CONFIRMED | Both directions real; its own "presentation only" ruling-out too generous |
| 27 | CONFIRMED | All three OPF defects hold; `EpubBuilder.kt` genuinely the only writer |
| **V-1** | **OVERSTATED** | Android passes `emptyList()` for membership timestamps at both call sites — E5 |
| V-2 | CONFIRMED | No destructive fallback in any form; all six migrations registered |
| **V-3** | **OVERSTATED** | Denies a privacy divergence that exists: logout race — E6 |
| V-4 | **OVERSTATED** | Constants match, but an uncapped Android-only AO3 sweep bypasses them — E18 |
| V-5 | CONFIRMED | `splitRequiredTag` and every selector identical |
| **V-6** | **OVERSTATED** | Categorical premise false: `?: raw` defeats the guard — E3 |
| V-7 | CONFIRMED | 21/21 declared, qualification present, no third unpopulated field |
| **V-8** | **OVERSTATED** | Misses a live XHTML well-formedness defect in the same function — E2 |
| V-9 | **OVERSTATED** | Formulas identical; **base sets are not** — E1 |
| V-10 | CONFIRMED | No concept present on one side only |
| **V-11** | **OVERSTATED** | 12 columns unaccounted; drops an Android-only column entirely — E7 |
| V-12 | CONFIRMED | Home predicates, sorts, cap identical |
| **V-13** | **WRONG** | iOS has no `savedSearches` in its manifest at all — E0 |
| V-14 | CONFIRMED | All four sub-areas hold |
| V-15 | CONFIRMED | Five of six sub-claims spot-checked, all hold |
| **V-16** | **OVERSTATED** | iOS bio is structured rich text, Android a flat string — counted as a match — E8 |

Line drift is small — most citations exact, the rest within ±2.

---

## Errors found

### Group A — false claims of agreement

#### E0 — V-13 is false, and the Summary quotes it as proof the port was done right

**Claimed:** saved searches "round-trip losslessly through Android, *including filters Android
cannot itself use*", with a worked example at `:2135-2136`.

**The code shows the round trip cannot happen in either direction.** The iOS `.kudosbackup`
manifest has no `savedSearches` member: `Services/KudosBackup.swift:227-242` lists works,
bookmarks, fonts, collections, readingQueues, readingQueueMemberships, annotations, settings,
tombstones — nothing else. `CodingKeys` (`:269-281`) has no such case; `init(from:)` (`:284-309`)
never decodes one. Grepping the iOS tree for `SavedSearch` returns only schema registrations
(`App/MyApp.swift:20`, `App/ContentView.swift:510`), the UI, and the model. **No export path, no
import path.**

The Android-internal mechanism is real (`BackupMappers.kt:271,280`; `BackupManifest.kt:129-135`).
But iOS writes no saved searches for Android to preserve and silently drops the array Android
writes. The true state is a **one-sided gap** — the opposite of the agreement recorded.

Most serious error in the document: Summary `:92` cites it as a headline example of "where
someone sat down and ported a rule, they ported it correctly."

#### E1 — V-9: identical formulas, different input sets

- iOS `Features/Library/LibraryView.swift:70-72` — `statisticsWorks` filters only
  `!isQueueOnlyWork` + privacy, over `@Query` at `:20-21` (`!$0.isPendingDeletion`). Unprotected
  works **are** included.
- Android `library/ReadingStatisticsScreen.kt:69` consumes `observeSavedWorks()` →
  `works/WorkRepository.kt:44` — `.filter { it.isProtected && !it.isQueueOnlyWork }`. Unprotected
  works are **excluded**.

`isProtected` is equivalent on both sides (`Models.swift:386-388`, `core/model/SavedWork.kt:74`).
The state is reachable: reading then un-saving leaves the record alive
(`Services/WorkLifecycle.swift:39-42`; `Models.swift:157-161` documents this "history entry"
state), and Android's mirror path (`WorkRepository.kt:161-164`) keeps the row but drops it from
the stats flow.

10 read, 5 finished, 4 of those un-saved → iOS `completionRate` 5/10 = 50%, Android 1/6 = 17%.
**All nine statistics affected.** Exactly the "one wrong denominator" case. The comparison read
the two computation files and never the call sites.

#### E2 — V-8 declares HTML sanitisation "clean" over a live defect in the same function

The allowlist comparison is right (SwiftSoup `Whitelist.relaxed()` is tag-, attribute- and
protocol-identical to Jsoup `Safelist.relaxed()`). But iOS also forces XML output:
`Reading/HTMLWorkSanitizer.swift:99-105`, commented "void elements come out as `<br />`, so the
chapter file stays well-formed for strict EPUB parsers."

Android's `works/converters/HTMLWorkConverter.kt:34` uses plain `Jsoup.clean(...)` — default HTML
syntax, unclosed `<br>`, `<hr>`, `<col>`. `EpubBuilder.kt:103-105` then wraps that in XHTML with
the OPF declaring `media-type="application/xhtml+xml"` (`:70`). **Any imported HTML work
containing a `<br>` — near-universal in fanfic — produces a non-well-formed XHTML chapter, on
Android only.**

#### E3 — V-6's categorical premise is false; Android does apply a foreign locator

`reader/readium/ReadiumNavigatorController.kt:72-78`:

```kotlin
val decoded = ReaderLocatorCodec.decodeCompatibleLocator(raw) ?: raw
Locator.fromJSON(JSONObject(decoded))
```

The `?: raw` overrides exactly the guard V-6 rests on. An iOS bare locator is the same Readium
schema, so `fromJSON` succeeds and Android navigates to it. Reachable: restore an iOS backup on
Android (`BackupManifest.kt:169` / `BackupMappers.kt:420,444`) → open work → TOC sheet → tap a
bookmark (`reader/ReaderScreen.kt:638-641`). The *reading-position* half is real and correct.
V-6 also misses the asymmetry it was positioned to find: iOS discards a foreign-locator
annotation outright (`ReadiumReaderView.swift:670,:801`).

#### E5 — V-1: Android neuters the queue rule it is credited with matching

The three compared functions are byte-equivalent. But Android passes `membershipModifiedAts =
emptyList()` at **both** call sites (`BackupMergeService.kt:507`, `:524`) while iOS feeds real
membership timestamps on both (`KudosBackup.swift:660-665`, `PersistenceSync.swift:416-422`). The
data is in scope on Android (`:487`, `:489`) — a dropped input, not a model limitation. **For a
queue whose memberships changed but whose `dateUpdated` did not, the platforms pick different
conflict winners from the same file.**

The cited iOS range also stops one line short of `SyncMerge.applyProgress`
(`PersistenceSync.swift:434-455`), a fourth rule in the same enum, where Android diverges on
locator (`BackupMergeService.kt:287` `?:` fallback vs iOS's unconditional overwrite at `:452`).

#### E6 — V-3 denies a privacy divergence that exists

Android has no session-generation guard. `AO3AuthRepository.verifySession()` (`:95-126`) awaits a
network validate and on return calls `applyValidSession` (`:112`), re-running `sessionStore.save()`
+ `cookieStore.install()`. `logout()` (`:170-174`) runs in a separate coroutine
(`AccountViewModel.kt:86` vs `:90`, no mutex), both controls on the same screen
(`AccountScreen.kt:200-201`). **Tap *Verify Session*, then *Log out* while it is in flight: the
session file is rewritten and AO3 cookies re-installed after logout.** iOS blocks exactly this
(`AO3AuthService.swift:505` advance; guards at `:396,:419,:451,:458,:472,:545,:580`).

Two smaller errors: the row "What is in plaintext | Android: nothing" is false
(`AO3PostingPseudStore.kt:24`, `CommentDraftStore.kt:20-22`); and the deletion-failure gap is
deflated to "a one-line honesty gap" when iOS's `markRemovalPending()`
(`AO3AuthService.swift:531`) makes a later launch *refuse to restore* — Android ignores
`File.delete()`'s boolean (`AO3SessionStore.kt:76-77`) and reloads unconditionally (`:45`).

#### E7 — V-11's arithmetic does not close, and the diff is one-directional

After applying the section's three escape hatches, **12 columns remain unaccounted**:
`syncStatusRaw`/`lastSyncAttemptAt`/`lastSyncError` on `WorkCollection` (`Models.swift:591-593`),
`ReadingQueue` (`:632-634`) and `ReadingQueueMembership` (`:691-693`) — 9 columns, unmentioned,
and **not** dead schema (see E14) — plus `WorkCollection.createdAt` (`:585-587`) with no Android
counterpart.

And the diff only looks one way: Android `CollectionEntity.kt:17-18` adds `description` and
`sortOrder`; `description` is rendered (`library/CollectionsScreen.kt:243-245`) and written to the
backup (`BackupMappers.kt:238-239`), while iOS's `ArchivedCollection`
(`KudosBackup.swift:608-617`) has no such key — **an Android→iOS restore drops it.**

#### E8 — V-16 counts a lossy field as a match

Field *counts* match, but iOS's `bio` is `AO3RichText` (`Models/AO3AuthorModels.swift:365-390`)
whose runs carry `isBold`, `isItalic`, `link: URL?`, rendered structurally
(`Features/Authors/AuthorProfileComponents.swift:284`). Android flattens via `normalizedText()`
(`network/ao3/author/AO3AuthorParser.kt:82-83`) into one plain `Text`
(`author/AuthorProfileScreen.kt:422-425`). **A bio with links, bold, or a list renders as an
unformatted, unclickable blob on Android.** Also `AO3AuthorIdentity.kind` (`:139-144`) has no
Android counterpart, contradicting "nothing is present on one side only".

#### E18 — V-4's "every politeness constant matches" is bypassed by uncapped Android background work

V-4 verifies the *client's* constants and declares the networking policy honoured. But
`works/AvailabilitySweep.kt:14-34` walks **every** saved work, one AO3 request each, with **no
spacing, no cap, and no recheck-interval skip** (it only *writes* `lastAvailabilityCheck` at
`:24,:31`; the sole skip is `work.ao3Unavailable` at `:18`). iOS's counterpart
`Services/WorkAvailabilitySweep.swift:31-44` is manual-only (sole trigger
`Features/Account/AvailabilitySweepView.swift:198`) and enforces all four: 7-day recheck skip,
1500 ms serial spacing, 150-work cap, oldest-first, cancellable.

Worse, `KudosApplication.kt:63-82` schedules the sweep as a 7-day `PeriodicWorkRequest` **and**
`WorkTagsRefreshWorker` daily, both with **no `Constraints` at all** — contrast
`backup/SyncRepository.kt:66-68`, which does set `setRequiresBatteryNotLow`. `WorkTagsRefreshWorker.kt:30`
returns `Result.retry()` on any failure, so WorkManager backs off and re-runs. iOS has exactly one
BGTask (`FolderSyncBackgroundTask.swift:25`), gated on `isConnected && autoSyncEnabled` (`:40`).

**An unattended, unspaced, uncapped library-wide sweep against AO3 exists on Android only** — a
live politeness divergence in the area V-4 closes. `Availability` appears **zero** times in the
report.

### Group B — finding-level errors

#### E4 — Finding 25 counts a fourth diverging shelf as a match

Collections diverges in **order**, on a finding titled "select or **order** different works":
iOS `LibraryView.swift:24-27` (`sort: \WorkCollection.dateAdded, order: .reverse`) vs Android
`library/LibraryQuery.kt:55-57` (`compareBy(String.CASE_INSENSITIVE_ORDER) { it.name }`). So it is
four diverging, three matching. The History row also gives only a predicate under a
"predicate / sort" header, and ruled-out (a) dismisses `LibraryQuery.kt:22` while the load-bearing
filter is upstream at `WorkRepository.kt:44` — the same gate as E1. The corrected "not disjoint"
text is right and survives attack.

#### E9 — Finding 1: a wording erratum, and a scenario branch wrong in the *safe* direction

The blocker is **confirmed**; severity should not be lowered. Every load-bearing citation verified
(iOS `:689`, `:707-709`; Android `:205`, `:226`; no `renameDocument` anywhere;
`WorkFileStore.kt:24-39` is the temp+`ATOMIC_MOVE` pattern; all five history citations land).

1. **The CORRECTION's wording is backwards.** "iOS writes the manifest **first** (`:687`)" — iOS
   writes every EPUB and font at `:679-685` *before* the manifest at `:687-690`, which is what the
   finding's own first bullet quotes ("Assets first, manifest last", `:673`). The intended reading
   is manifest-before-*prune*, and that half is true (iOS prunes `:697`/`:701`; Android `:176`/`:193`
   before its manifest at `:201-205`). But "Nor was the ordering ported" over-reaches — Android
   *does* write assets before the manifest; only the prune position diverges.
2. **The zero-length branch is wrong — and the truth is worse.** `SyncRepository.kt:110` guards
   `if (bytes.isNotEmpty())`, so a zero-length manifest is silently *skipped*, never validated.
   Only a non-empty truncated manifest throws (`BackupValidator.kt:32-37`) — and because import
   (`:91-148`) precedes export (`:150-207`), that throw hits the catch at `:212-214` and the
   corrupt manifest is **never repaired**: every later sync returns `SyncResult.Error`, wedging the
   folder permanently. The zero-length case still destroys data by an unnamed route — a second
   device skips import, then prunes `Works/` at `:176-180` to its own snapshot, deleting works only
   the first device held.

#### E10 — Finding 5's headline consequence is largely self-healed

Mechanism exact (`BackupMappers.kt:72-121` emits 38 fields, none of the nine;
`BackupJson.kt:7` `explicitNulls = false`; the `:1966`→`:1960` drift fix was applied). But
`KudosBackup.swift:1501` calls `normalizeAllQueuedWorks(in:)` right after membership restore, and
`ReadingQueueService.swift:201-206` re-derives `epubPreservationStatus = .preserved` and
`preservedAt` for any queued work with an EPUB on disk. Queues and memberships round-trip intact;
EPUBs restore with `hasEPUB = true` (`:1205-1220`).

So `:1363` ("Every work returns with `.notPreserved`"), `:1365` ("series IDs are gone" — Android
*does* export `seriesURL`, `BackupMappers.kt:96`, and `:186-188` re-derives) and `:1366-1367` are
false **for the finding's own scenario**. Residual real loss: the original `preservedAt` timestamp
is replaced with restore time.

#### E11 — Finding 22's recommended fix does not exist

`helpUrl` is never *populated*: `network/ao3/preferences/AO3PreferencesParser.kt:103-107`
constructs `AO3PreferenceToggle(name=, label=, checked=)` with no `helpUrl`, so
`AO3PreferencesModels.kt:7` (`val helpUrl: String? = null`) is always null. The parser never
selects an `<a href="/help/…">`. The review read its own one-line grep as "parsed but unused" when
it is "never populated" — **the parser work is the bulk of the fix, not "one small composable"**
(`:672-674`). The gap itself is real.

#### E12 — Finding 10's second layer is falsified by the iOS EPUB builder

iOS ships the `.author-note` CSS **inside the EPUB**: `Reading/EPUBBuilder.swift:75` writes
`OEBPS/style.css`, `:85-95` the rules, `:118` into the archive, `:192` the manifest item, `:247`
the `<link rel="stylesheet">` in every chapter. Android imports EPUBs byte-for-byte
(`works/WorkImporter.kt:150`; stored as-is at `files/WorkFileStore.kt:61`) and renders with
Readium, which loads the publication's own CSS. So "Android injects no CSS … nothing styles it" is
wrong for the cross-platform case, and ruled-out (c) describes a path that does not exist.
Residual real gap: Android's own PDF/TXT/HTML imports do not detect notes.

#### E13 — Finding 9 inverts which platform is stricter

`ReaderStyle.swift:250` (`letterSpacingRange = 0.0...0.12`) has exactly **one** consumer —
`CustomizeThemeView.swift:85`, the slider. It is a slider bound, not a validator. iOS's restore is
unvalidated: `KudosBackup.swift:848` decodes a raw `Double` (`?? 0`), `:938` writes it straight to
`UserDefaults`. iOS says so itself at `ReaderStyle.swift:312-315`. So "iOS's range does not include
it" is wrong — iOS stores −0.02 too. For values outside Android's validator range **iOS is the
laxer side**: `BackupValidator.kt:174-175` substitutes the default while iOS keeps the raw number.
The comparison (iOS slider constants vs Android's backup validator) also hides a larger reachable
bug: Android's own slider allows 0.5f (`settings/SettingsScreen.kt:552-553`), which
`BackupValidator.kt:174` silently discards on restore.

#### E14 — Finding 19's central assertion is false, and its ruled-out names the file that falsifies it

"No feature writes them" and ruled-out (a) are false. `Services/PersistenceSync.swift` writes
`syncStatus` — whose setter is `syncStatusRaw = newValue.rawValue` — at `:195`, `:211`, `:234`,
`:247`, `:296`. Live: `PersistenceMigrationService.run` calls it (`:143`, `:145`) and `runIfNeeded`
fires at launch (`App/ContentView.swift:97`). **Every record flips `localOnly` → `pending` on first
launch**, so `KudosBackup.swift:629` exports a non-default value. The fields are
write-only-never-read, not unwritten. Undercount: `Models.swift:787` gives `ReadingAnnotation` a
fifth `syncStatusRaw` — 13 properties across 5 types, not 12 across 4. `minor` is honest either way.

#### E15 — Finding 24 missed every indirected empty-state title

The 11/17 split is right **for literal titles** (I reproduced it). But the report claims it
"extracted every `ContentUnavailableView` title across the iOS tree" and dropped the six
variable-titled sites: `Features/Bookmarks/AO3AccountWorksList.swift:330-331`
(`kind.signedOutTitle`, four more Title Case at `:50-57`) and `:217-218` (`kind.emptyTitle`, five
sentence case at `:30-38`); `Features/ReaderReadium/ReaderContentsSheet.swift:80,87`;
`Features/Library/LibrarySectionListView.swift:208-209,215-216` (`kind.title` →
`LibrarySectionKind.swift:31-37`). Recount ≈ **20 Title Case / 22 sentence case** — a near-tie, not
a 17-of-28 majority — and ~20 strings to change, not "Eleven". Headline survives, worse than filed.
(Only 10 of its 11 Title Case strings are named; "Couldn't Open Reader",
`Features/Library/WorkCardActions.swift:114`, is counted but never listed.)

#### E17 — Finding 3 claims four spot-checked clusters and enumerates three

`:1558-1561` concludes "Four clusters spot-checked, four stale". The finding enumerates the
queue-only cluster (`:1494-1509`) and the reading-statistics cluster (`:1516-1533`), then jumps to
"A fourth stale entry, in a different document" — MuPDF (`:1545`). **There is no third.** Separately
`:1540-1544` concedes it did **not** verify whether `saveMetadataOnly` still hard-codes
`markSaved = true` — then counts that cluster as whole 16 lines later.

**The substance holds and is now stronger.** I closed both gaps independently. *MuPDF:*
`docs/iOS_Issues_Found_While_Porting.md:45-60` claims MuPDF "is built and verified but never wired
in" and assigns iOS a live medium-severity defect — `Services/PDFWorkConverter.swift:64` and `:125`
call `KudosMuPDF`, and the xcframework is linked at `project.pbxproj:14,30,54`. **Stale.**
*`saveMetadataOnly`/`removeWork`:* `works/WorkImporter.kt:38-42` now takes
`isQueuedForLater: Boolean = false` alongside an overridable `markSaved`;
`ReadingQueueRepository.kt:114-128` does record a tombstone; `renameQueue`/`deleteQueue` exist at
`:233`/`:246` against the audit's "no rename/delete/reorder". **Stale in both halves.** The claim
should read "three clusters, three stale" — the count is padded, not the substance.

### Group C — process and self-correction errors

#### E16 — The corrections table drops E4 while claiming every error was fixed

The *Validation pass* section states "**Every reported error was independently re-verified** … All
were confirmed, and **all are now fixed in place**." Its table lists E1, E2, E3, **E5**, E6, E7, E8
— jumping E3→E5. **E4 is absent and was never applied.** (E6 and E8 *were* fixed despite not being
named in the commit message; only E4 is outstanding.)

E4 was correct, and the false sentence still stands at `:313`: "no code references the concept,
and `SeriesPreservation.kt` … contains neither name." Android references the concept in that exact
file: `library/SeriesPreservation.kt:36-37` (`canAutoPreserve … knownCount <= threshold`) and `:56`
(`autoPreserveLabel`), constructed with a hard-coded `threshold = 5` at
`works/WorkDetailScreen.kt:815` and `:817`. The narrow sub-claim ("contains neither *name*") is
true; the general one is not.

#### E19 — The re-check table's first row is wrong, not "inconclusive"

`:1799` claims `grep -rniE "zeroCount|showZero|hideZero"` "returns nothing on either platform, so
the setting is not findable under that name on iOS either", and marks the row ⚠️ inconclusive.

**The iOS setting is right there:** `Settings/SettingsView.swift:36`
(`@AppStorage("showsZeroStats")`), `:275` (`Toggle("Show zero counts", isOn: $showsZeroStats)`),
`:282-283` its help text, consumed at `UIComponents/WorkStatLabel.swift:111` and `:130`. All three
grep patterns miss because none is a substring of `showsZeroStats`, and the exact toggle title
T-193 spells out verbatim was never grepped. Android side: `grep -rni "zero" --include="*.kt"`
returns two unrelated hits. **The known divergence is straightforwardly still true.** The row's
candour ("Do not treat this row as verified") is honest labelling of a check that was skipped.

Same table, `:1801`: "Both `FlowRow` call sites now use `Arrangement.spacedBy`" — there are
**eleven** FlowRow sites (`WorkStats.kt:73,:440`; `KudosUi.kt:205`; `SettingsScreen.kt:1261,:1316`;
`SearchResultsHero.kt:151`; `WorkDetailScreen.kt:1581,:2003,:2039`; `BrowseScreen.kt:308,:371`),
all correct — the conclusion is stronger than stated but the evidence is false. The
"`SpaceBetween` uses that remain" three-item list is written as exhaustive and is roughly a sixth
of the ~20 that exist.

---

## Coverage gaps

**"All 21 areas closed" is overstated**, and the review's own gap list is both wrong in its
headline item and shorter than the truth.

### The self-declared "Highest-value follow-up" is misdescribed — but there *is* a defect there

Report `:2794-2798` claims Android's `PrivacyGate` "reaches **3**, all under `home/`, and
`library/LibraryPrivacy.kt` never consults reveal state".

**The reach count is false.** Apples-to-apples on the literal identifier: iOS 12 files, Android 11
(9 excluding definitions, four under `library/`). Reveal state *is* applied there, deliberately:
`library/LibraryModels.kt:34-39` is a shared `withReveal()` whose own doc reads "shared by every
screen's ViewModel (Library, Home) … **so the rule can't drift between them**", called on all
eight Library shelves (`LibraryViewModel.kt:69-76`) and all four Home sections
(`HomeViewModel.kt:180-183`).

**But a real divergence sits one layer down, and it is not the one described.** In **Hide** mode
Android drops items *before* reveal is ever consulted: `library/LibraryQuery.kt:25`
(`LibraryPrivacyVisibility.Hidden -> null`) and `library/LibraryModels.kt:36` (`withReveal`
early-returns for anything not `Obscured`), so `LibraryViewModel.kt:67-75` can never bring them
back. Same shape at `home/HomeSectionListScreen.kt:88-89`. iOS's
`Features/Privacy/MatureContent.swift:63-65` includes `&& !isRevealed(work)`, so reveal-all
restores Hide-mode works — used across nine files.

Reachable: Hide mode is user-selectable (`settings/SettingsScreen.kt:816-826`), and the eye button
still shows (`LibraryModels.kt:113-114`, counted over all saved works at `LibraryQuery.kt:33`).
**Pick Hide, tap the eye: the shelves stay empty and the icon flips to "Hide mature works".** A
dead control. Only `library/ReadingStatisticsScreen.kt:79-82` gets it right
(`Hidden -> reveal.isRevealed(work.id)`) — proving the rule is known and inconsistently applied.

So: file it, but as *"Android's reveal-all is inert in Hide mode"*, not as *"Android's privacy gate
barely reaches the Library"*.

### Subsystems no finding, V-section or ledger row addresses

| Gap | Status |
|---|---|
| **Background workers / availability sweep** | **Real, and hides an unfiled defect** — see E18. `Availability` appears zero times in the report. |
| **Download queue** | Real and unaddressed (one incidental mention at `:1039`). iOS `Services/DownloadQueue.swift` 146 lines vs Android `works/DownloadQueue.kt` 284. Contains a reachable behavioural divergence: Android has a `force` flag (`:84,:104-108,:185`) with a soft-delete revive (`:231-248`); iOS handles Recently-Deleted inline (`DownloadQueue.swift:83-93`) with no force path. |
| **Work-page metadata + chapter parsers** | Real and unaddressed. V-5 verified only the *search-blurb* `required-tags` trap; `network/ao3/work/` is a separate 453-line surface with an iOS counterpart, never compared. |
| **WebView URL trust boundary** | Real gap, **but the review's framing points at the wrong platform** — see below. |
| **Collections end-to-end** | Falls through the seam between two exclusions — see below. |

**WebView — the security framing is inverted.** Android `web/AO3WebUrlPolicy.kt:26-33` classifies
via `network/ao3/browse/AO3BrowseUrls.kt:31-38`, which parses with `toHttpUrl()`, requires
`scheme == "https"`, and anchors the suffix on `".${WORKS_HOST}"` — a correct host check, **not**
the naive `endsWith` the Android audit corpus lists as a top open major (so that corpus entry is
stale too, supporting finding 3). iOS `Features/Browse/WebBrowser.swift:33-36` `isAO3URL` checks
host and dot-anchored suffix with **no scheme check**, so `http://archiveofourown.org` passes;
`Services/AO3URLResolver.swift:42` and `Models/AO3Session.swift:70,82` share that shape. File it as
**"iOS accepts cleartext AO3 URLs where Android does not."**

---

### Areas 17 and 18 were closed at "0 findings" and both contain divergences

I swept both directly, because they are the thinnest rows in the ledger.

**Area 17 — "nothing further to compare" is wrong.** iOS genuinely has no app-update path
(confirmed: the only `checkForUpdates` in the iOS tree is
`Services/WorkUpdateChecker.swift:17`, which checks *AO3 works* for new chapters). But the update
system carries a user-visible surface that **does** have an iOS counterpart, and it diverges:
Android fetches and deserializes `body`, `htmlUrl`, `publishedAt` and `name`
(`network/github/GitHubReleaseModels.kt:12-22`) and `AndroidReleaseMatcher.Match` carries the whole
release object (`update/AndroidReleaseMatcher.kt:26-30`) — **none of which is referenced anywhere
outside the model file.** The update UI (`settings/SettingsScreen.kt:991-1070`) renders version
strings only. So an Android user is auto-downloaded into a new build
(`AppUpdateRepository.kt:44-56`, `autoDownload = true`) **with zero explanation of what changed**,
while an iOS user gets `Features/Support/WhatsNew.swift` on launch (`App/ContentView.swift:205-213`).

**Area 18 — the stated justification is contradicted by the code.** The ledger accepts `WhatsNew`
as iOS-only because "Android surfaces GitHub release notes." **Android does not.** The release
`body` is parsed (`GitHubReleaseModels.kt:20`) and never read by any composable; there is no
changelog screen anywhere in the Android tree. The conclusion may still stand on the `TASKS.md`
design decision, but the evidence cited for it is false — and as written it hides the real gap:
*no* Android surface tells the user what changed.

**Area 18 — the bug-report payloads were never compared, and diverge both ways.** Android sends
device identity: `"Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}); ${Build.MANUFACTURER} ${Build.MODEL}"`
(`account/BugReportScreen.kt:43`). iOS sends **no device at all** —
`"\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"`
(`Features/Support/BugReportView.swift:166-173`), so an iOS bug report cannot distinguish an
iPhone SE from an iPad Pro, which is exactly what a triager needs. Conversely iOS appends the git
commit SHA to its version field (`Settings/AboutView.swift:155-164`) where Android sends only
`VERSION_NAME (VERSION_CODE)` (`BugReportScreen.kt:42`). Neither collects logs. Low severity,
cheap to fix, and genuinely missed.

**What area 18 got right:** L-6's screenshot conclusion survives — iOS captures at shake time
(`Features/Support/ScreenshotCapture.swift:8-23`) and offers `ShareLink`, but submission on both
platforms is a prefilled GitHub issue URL that cannot carry an image, so neither actually attaches
one. And shake-to-report exists on **both** (`Features/Support/ShakeDetector.swift:101-136`;
Android approximates the missing OS gesture with an accelerometer listener at
`support/ShakeDetector.kt:27-104`) — different mechanics, correct per-platform idiom, same
behaviour.

---

## Exclusions judged unreasonable

### Area 14 — unreasonable, and it hid three real defects

Measured: `mergeCollections` (`BackupMergeService.kt:376-450`, 75 lines), `mergeQueues`
(`:485-581`, 97), `mergeAnnotations` (`:583-641`, 59) = **231 excluded lines against ~115 read**
(`mergeWork` `:179-238` + `applyProgressLww` `:239-293`). **The exclusion skips twice the code that
produced findings 4 and 18.** Reading it yields three unfiled cross-platform divergences:

1. **Queue tombstones do not propagate.** `BackupMergeService.kt:500` —
   `if (archived.isDeleted == true) return@forEach` — drops an incoming deleted queue before any
   LWW/tombstone logic, while iOS `KudosBackup.swift:1414-1421` explicitly applies
   `queue.isPendingDeletion = incomingWins ? (archived.isDeleted ?? false) : …`. **An iOS queue
   deletion never reaches Android.**
2. **Annotation tombstones likewise.** `BackupMergeService.kt:601`
   (`if (archived.isPendingDeletion) return@forEach`) vs iOS `KudosBackup.swift:1637` and `:1661`,
   which both assign `isPendingDeletion = archived.isPendingDeletion`.
3. **Duplicate system queue.** iOS matches Saved-for-Later by **kind**
   (`KudosBackup.swift:1345,1349-1350,1401-1403`); Android's `mergeQueues` matches only by
   canonical UUID (`:501-508`) with no kind special-case, and each platform mints its own UUID
   (`ReadingQueueRepository.kt:177-186`). **Restoring an iOS archive on Android inserts a second
   "Saved for Later" queue.** `ReadingQueueDao.kt:36-40` resolves with
   `ORDER BY sortOrder ASC, name ASC LIMIT 1`, so the list silently splits — and
   `ReadingQueueRepository.kt:237,:248` forbid renaming or deleting system queues, so the user
   cannot clean it up.

The stated reason ("the works path is the one carrying user content") is contradicted by the
review's own finding 26 and by `BackupManifest.kt:23,164-179`: annotations carry `locatorString`,
`selectedText` and `note` — highlights and notes are user content by any definition. ZIP container
internals remain unmeasured as well.

### Area 10 — unreasonable; "no cross-platform contract" is simply false

`BackupManifest.kt:114-127` (`BackupCollection`) carries exactly the CRUD-authored fields — `name`,
`description`, `sortOrder`, `isDeleted`, `deletedAt`, `permanentDeletionScheduledAt`,
`lastModifiedAt` — and `BackupMergeService.kt:425-443` merges every one. `BackupManifest.kt:152-160`
carries `sortOrderInQueue`, which is precisely what drag-reorder writes, and
`BackupMergeService.kt:574` sorts merged memberships by it. iOS matches at `KudosBackup.swift:1294`
and `:1339-1423`.

Note also that `docs/contracts/BACKUP_FORMAT.md:20,112` claims collections are "Not included / Not
exported in current v1" — itself stale and contradicted by the manifest model. If the review leaned
on that doc, it leaned on a document its own finding 3 warns about.

**Combined with area 14, collections and queues were never read end to end** — CRUD excluded by
area 10, merge excluded by area 14 — which is exactly where defects 1–3 above were sitting.

### Area 9 — TTS unreasonable; TOC/in-reader search fair

iOS 1,287 lines across four files vs Android 229 in one (5.6×), both persisting voice/rate/pitch,
**with no reason given for the TTS half at all** — the ledger's stated reason covers only
TOC/in-reader search. Unmeasured, not closed.

### Area 13 — **reasonable. I am correcting the prior validation, which called it unreasonable.**

The challenge premise (that a download queue fans out N requests and bypasses V-4's constants) is
refuted by both trees: iOS `Services/DownloadQueue.swift:73-110` is a single
`while let index = items.firstIndex(where: .queued)` loop with one awaited download per iteration,
documented at `:6-7` as "reusing the already-serialized AO3Client"; Android
`works/DownloadQueue.kt:162-179` `pump()` takes `pumpMutex.tryLock()` and returns if held, one
`process(index)` per iteration. **No TaskGroup, no async fan-out, no unbounded launch on either
side.** It does not belong to area 3. (It remains a *coverage* gap for the `force`-semantics
divergence noted above — but the exclusion's reasoning was sound.)

### Area 16's ledger phrase over-reaches

"Every stored setting checked for an Android control" — what was checked is the 21 backup-payload
fields. iOS's speech settings sit outside it.

**Judged reasonable:** area 15's DAO semantics, area 1's onboarding copy, area 19's skeleton
states, area 8's orphaned-author rendering, area 9's TOC/in-reader search.

**The review's own admissions are accurate, not narrower than the true gap** — the EPUB builder
really was compared only at the level of which Dublin Core elements are emitted, TTS really was not
compared, and Settings row wording really was not diffed.

---

## Self-corrections — audited, and honest

All five named corrections survive contact with the code:

| Correction | Verdict |
|---|---|
| Finding 23's `AO3AuthorUrls.userSeriesUrl` retraction | **CONFIRMED** — retracted claim genuinely gone; replacement true in code; the withdrawn "no series URL" assertion is not repeated anywhere else |
| V-7 qualified by finding 28 | **CONFIRMED** — qualification physically present and accurate |
| *Asymmetric test coverage* walking back "absent tests predict defects" | **CONFIRMED** — every load-bearing number exact (see below); contradicted claims elsewhere *were* updated; two supporting citations in its own table are wrong |
| V-12's near-miss admission on Subscribe | **CONFIRMED** — accurate, code exactly as described |
| Leads L-3, L-4, L-5, L-6 marked RESOLVED | **CONFIRMED** — all four survive the code; none is a word-swap |

I verified the walk-back's arithmetic myself: `BackupCompatibilityTest.kt` is exactly **1,327 lines
/ 41 `@Test`**; `KudosTests/FolderSyncTests.swift` is exactly **796 lines**; and
`grep -rl SyncRepository` across the Android test tree returns **nothing**.

---

## Known-divergence boundary — clean

None of the 28 findings restates any of the five already-known divergences. The riskiest case is
fenced explicitly: finding 5 notes "(`bookmarks` is also absent but is the known T-193 divergence,
not counted here.)" Findings 8/9/20/21/26 all compare against the shipping Readium reader rather
than reporting "iOS has two readers" as drift. The re-check table is now filled — but see **E19**,
where one row is wrong and another's evidence is false.

---

## Verification re-run

**Android — reproduces exactly.** `android/Scripts/verify.sh` with the Android Studio JBR:
**ALL GREEN, exit 0**, all five stages. I then isolated the full unit-test task with
`--rerun-tasks` (32 actionable tasks, **32 executed** — nothing cache-served) and parsed the XML:

| Suites | Tests | Failures | Skipped |
|---|---|---|---|
| **199** | **660** | **0** | **0** |

Matches the review's figure to the digit.

**A methodology trap worth recording.** `verify.sh` stage 4 runs a persistence/reader/network
*subset* into the same results directory, overwriting stage 2's output. Parsing
`test-results/testDebugUnitTest/*.xml` after a full `verify.sh` yields **61 suites / 210 tests** —
I reproduced exactly that before isolating the task. The review's stated method gave the right
answer for its run and will mislead the next reader.

**iOS — not re-run.** Needs the `Vendor/MuPDF.xcframework` symlink and a full simulator pass. The
993 tests / 91 suites figure is unverified here.

**Lead L-2 — honest, not overstated.** "The assumption of safety is disproven; the defect itself is
unconfirmed" is exactly what the evidence supports: the probe is labelled as a desktop JVM, the
desugaring argument is stated as *removing a defence* rather than proving a hazard, and the one
remaining device step is named. R-1 is consistent with it — R-1 covers Room-sourced dates
(millisecond converters at `data/local/converters/KudosTypeConverters.kt:13-21`) and explicitly
hands the `Instant.now()` clock path to L-2.

---

## What I could not check

- **The iOS suite** (993 / 91) — not re-run.
- **3 of 28 findings** — 4, 18 and 28. All three carry the prior pass's analysis (E1 for 4, E4 for
  28) and their source leads L-3/L-5 were re-verified as part of the corrections audit, but I did
  not independently re-derive them. Finding 28's E4 half I did check (E16).
- **Anything runtime.** No emulator, no simulator, no screen reader. The rendered-height half of
  finding 11 and the TalkBack half of V-16 remain open exactly as the review states.
- **Whether E7's dropped `description` column is live.** Android writes it to the backup and iOS
  has no key for it; I did not exhaustively prove no Android path assigns a non-null value.
- **Severities for the newly-found defects** (E18, and area 14's three). I report mechanism and
  reachability; ranking them against the existing 28 is the owner's call. The area-14 duplicate
  system queue and the queue/annotation tombstone drops look like the most consequential — they are
  silent, cross-platform, and unrecoverable by the user.
