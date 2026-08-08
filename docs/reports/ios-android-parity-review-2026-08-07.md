# iOS ↔ Android parity review — 2026-08-07

**Trees reviewed:** `hig-review` @ `e9ed0c6a` (worktree `.claude/worktrees/hig-review-reference`, iOS source root `kudos-ao3-reader/`) · `android/exclusion-parity` @ `a5a46116` (worktree `.claude/worktrees/android-exclusion-parity`, Android source root `android/app/src/main/java/io/github/cidy02/kudos/`)

> Note on the Android branch name: the review prompt names the branch
> `kudos-ao3-reader-android`. The worktree at `.claude/worktrees/android-exclusion-parity`
> is checked out on `android/exclusion-parity` @ `a5a46116` — which is the exact SHA the
> prompt cites, so this is the intended tree under a different branch label.

**Method:** see *Method log* at the foot of this file. Updated as work proceeds.
**Status:** in progress

**Confirmed sizes** (`find | wc -l`, run 2026-08-07): iOS 214 Swift sources + 85 test
files; Android 281 Kotlin sources + 93 test files. Both match the prompt's figures.

---

## Progress ledger

**Resume here:** Area 4 (search + filters) — compare the filter field set and the generated
query string between `Features/Search/AO3FilterPanel.swift` and
`network/ao3/search/AO3SearchUrlBuilder.kt` + `AO3SearchFilters.kt`.
`docs/reports/filter-parity-2026-08-07.md` covers endpoints only, so defaults, ordering and
serialisation are open ground.

**Then:** areas 1, 5–13, 16, 18–20 are untouched. Read *Not covered* before planning —
it says which of them already have partial coverage from the Android branch's own
`docs/audits/` and should therefore be re-verified rather than re-derived.

**Do not redo:** area 17 (closed, see the re-check table); the date-encoding question
(closed as R-1); the suite-shape comparison in *Asymmetric test coverage*.

**Method warning for whoever resumes:** two 7-agent parallel sub-agent reviews were
dispatched for areas 2–15 and **both died on a session usage limit with zero results
returned** (1.29 M tokens, nothing recovered — the run journals contain no `result` lines).
Everything in this report was produced by direct inline reading afterwards. Do not re-try
that fan-out shape; work areas serially and commit each one.

| # | Area | iOS roots | Android roots | Status | Findings | Notes |
|---|---|---|---|---|---|---|
| 1 | Onboarding & first run | `Features/Onboarding/`, `App/MyApp.swift`, `App/ContentView.swift` | `onboarding/`, `app/` | ⬜ not started | – | |
| 2 | Auth / session / cookies | `Services/AO3AuthService.swift`, `AO3SessionVault.swift`, `AO3WebLoginCoordinator.swift`, `AO3RedirectCookieRelay.swift`, `Features/Auth/` | `auth/` | ✅ done | 0 (V-3) | Storage, cookie jar and logout all at parity; Android's plaintext store ruled out as test-only. **Not read:** `AO3SessionValidator.kt` / expiry cadence, native-vs-web login flow choice |
| 3 | Networking core (pacing, retry, coalescing, errors, URL resolution) | `Services/AO3Client.swift`, `AO3RequestCoordinator.swift`, `RequestCoalescer.swift`, `AO3URLResolver.swift` | `network/ao3/` (root files) | ✅ done | 1 (finding 6) | Every politeness constant compared and matching (V-4); UA version stale on Android. **Not read:** `AO3OverloadDetector.kt`, coalescer key/TTL detail, `AO3URLResolver` |
| 4 | Search + filters + tag autocomplete + saved searches | `Features/Search/`, `Models/SavedSearch.swift` | `search/`, `network/ao3/search/` | ⬜ not started | – | `filter-parity-2026-08-07.md` covers endpoints only |
| 5 | Browse (category → fandom → works) + fandom catalog | `Features/Browse/`, `Features/Search/FandomCatalog*.swift` | `browse/`, `network/ao3/browse/` | ⬜ not started | – | |
| 6 | Work detail + write actions (kudos/bookmark/subscribe) | `Features/WorkDetail/`, `Services/AO3WriteActions.swift` | `works/WorkDetailScreen.kt`, `network/ao3/writes/` | ⬜ not started | – | |
| 7 | Comments (threads, drafts, posting) | `Features/Comments/`, `Services/AO3Client+Comments.swift`, `AO3CommentActions.swift`, `CommentSubmission.swift` | `comments/`, `network/ao3/comments/` | ⬜ not started | – | |
| 8 | Author profile + series | `Features/Authors/`, `Services/AO3AuthorProfileService.swift`, `AO3Client+Authors.swift` | `author/`, `network/ao3/author/`, `network/ao3/series/` | ⬜ not started | – | |
| 9 | Reader(s) | `Features/ReaderReadium/`, `Features/Reader/`, `Reading/` | `reader/` (+ `readium/`, `settings/`, `speech/`) | ⬜ not started | – | iOS has two readers (Readium iOS / legacy macOS); Android one |
| 10 | Library / collections / queues / stats / recently deleted | `Features/Library/`, `Services/ReadingQueueService.swift` | `library/` | ⬜ not started | – | T-193 known divergences live here. **Partial input:** finding 3 closes the model half of the `isQueuedForLater` cluster; leads L-3/L-4 are open here |
| 11 | Home | `Features/Home/` | `home/` | ⬜ not started | – | |
| 12 | Account / inbox / dashboard / AO3 preferences | `Features/Account/`, `Services/AO3Client+Inbox.swift`, `AO3InboxActions.swift`, `AO3Client+Preferences.swift` | `account/`, `network/ao3/inbox/`, `network/ao3/preferences/` | ⬜ not started | – | |
| 13 | Import / conversion / EPUB pipeline | `Services/WorkImporter.swift`, `*WorkConverter.swift`, `Reading/` | `works/converters/`, `works/WorkImporter.kt`, `files/` | ⬜ not started | – | |
| 14 | Backup / restore / folder sync | `Services/KudosBackup*.swift`, `PersistenceSync.swift`, `FolderSyncService.swift` | `backup/` | ✅ done | 4 (1,2,4,5) + 1 minor | Manifest versions, manifest field set, date encoding (R-1), folder-sync write path (1 & 2), `SyncMerge` rules (V-1), `mergeWork` field rules (4), export round-trip (5). **Deliberately not read:** collection/queue/annotation merge bodies and ZIP container internals — the works path is the one carrying user content and it is where all four findings landed |
| 15 | Persistence + migrations (SwiftData vs Room) | `Models/Models.swift` | `data/local/` (`entity/`, `dao/`, `KudosDatabaseMigrations.kt`) | 🔄 in progress | 1 (finding 5) | `SavedWork` (64 stored) vs `WorkEntity` (46 cols) diffed mechanically → finding 5. Migration safety verified (V-2). **Not done:** the other 8 entities, type-converter round trips, DAO query semantics |
| 16 | Settings / theming | `Settings/`, `App/ThemeManager.swift` | `settings/`, `data/preferences/`, `ui/theme/` | ⬜ not started | – | |
| 17 | Update system | (none expected) | `update/`, `network/github/` | ✅ done | 0 | Confirmed Android-only; iOS has no app-update path. See the re-check table. Nothing further to compare — a feature one platform deliberately lacks is not drift |
| 18 | Support / bug report / shake | `Features/Support/` | `support/` | ⬜ not started | – | |
| 19 | Error handling & empty states | cross-cutting | cross-cutting | ⬜ not started | – | |
| 20 | Accessibility | cross-cutting | cross-cutting | ⬜ not started | – | |
| 21 | Test coverage asymmetry | `KudosTests/` (85) | `android/app/src/test` (93); no `androidTest` | 🔄 in progress | 1 minor | Suite shape done + the folder-sync asymmetry established. The per-rule sweep across all other areas is not done |

Legend: ⬜ not started · 🔄 in progress · ✅ done · ⏭️ skipped (reason in Notes)

---

## Summary

*Partial — this covers one area of twenty-one. It is written as what can honestly be said
now, not as the shape of the whole divergence.*

The one area read closely, backup and folder sync, was chosen because it is the only
subsystem whose artefact crosses between the two apps, so a divergence there means silent
data loss rather than inconsistency. Two things came out of it, and they point in opposite
directions.

The **format** layer is in good shape and better than expected. Manifest versions match
exactly, the field sets match collection for collection, unknown fields are deliberately
preserved on re-export, and the date-encoding hazard the project's own onboarding doc warns
about — the one that would corrupt merge ordering — turns out to be closed by an
unrelated mechanism (Room storing instants as epoch millis) rather than by design. That is
worth knowing precisely because it is *accidental*: lead L-2 identifies the single field
that escapes it.

The **merge** layer — the code that decides which record survives a conflict and whether a
deleted record may be revived — is a faithful port, verified function by function including
both null branches and the deliberate strict/non-strict asymmetry between "apply incoming"
and "revive over a tombstone" (V-1). That is the subsystem with the worst failure mode in
the app, and it is the most carefully ported thing found so far.

The **write** layer is where the divergence is, and it has a recognisable shape. Android's
sync path truncates the user's backup before rewriting it, where iOS writes atomically —
and this is not a case of nobody knowing better. The rule is a named binding invariant on
iOS, the Android port plan specified it, an Android contract doc already asserts it is
done, and Android implements the exact pattern correctly in its app-private file store a
few files away. It was lost only on the path where the destination is shared and
irreplaceable. Underneath it sits the same subsystem's *shared* bug — sync skipping any
file whose length happens to be unchanged — which is already documented on both platforms
and fixed on neither.

Separately, and cheaply: the one gap I spot-checked from the Android branch's own audit
corpus — the `isQueuedForLater` / queue-only concept, listed there as a highest-priority
confirmed-and-open major — is substantially implemented (finding 3). Combined with the
contract doc in finding 1 that asserts an atomicity guarantee the code does not provide,
two of the three Android-branch documents this review cross-checked misdescribe the code,
in opposite directions. Treat that corpus as leads, not coverage.

If one hypothesis is worth carrying into the remaining twenty areas, it is this: the
divergences here are not in what the two apps *know*, they are in what got *verified*.
`SyncRepository.kt` holds both defects and has no test; the iOS file it was ported from has
a 796-line suite. Where a rule is pinned on one platform and unpinned on the other is where
this review found its defect, on the first area it looked at.

---

## Findings

### 1. Android's folder sync truncates the destination before writing it — `blocker` · Backup / folder sync

- **iOS:** `kudos-ao3-reader/Services/FolderSyncService.swift:689` writes `manifest.json`
  with `options: .atomic`, and `:707-709` (`writeIfChanged`) writes every EPUB and font
  asset the same way. `Data.write(options: .atomic)` writes to an auxiliary file and
  swaps it into place, so the destination is either the old bytes or the new bytes,
  never a prefix of the new bytes. The code says so itself, at `:675-679`: *"Assets
  first, manifest last: the manifest is the commit point … An interruption leaves the
  previous manifest — and therefore the previous consistent view — in place."*
- **Android:** `backup/SyncRepository.kt:205` writes `manifest.json` with
  `context.contentResolver.openOutputStream(manifestDoc.uri, "wt")`, and `:226`
  (`writeIfChanged`) writes every EPUB and font asset the same way. The `"wt"` mode is
  *write + truncate*: the SAF provider truncates the existing document to zero length
  when the stream is opened, before a single new byte is written.
- **Divergence:** iOS never has a moment where the destination is invalid. Android has a
  window — the whole duration of the write — during which the destination is truncated or
  partially written. The *ordering* of the iOS design was ported faithfully (assets first,
  manifest last, then orphan pruning); the *atomicity* that makes that ordering mean
  anything was not.
- **Scenario:** a user with a 400 MB library syncs to a Google Drive / Dropbox / SD-card
  folder. Mid-sync the process is killed — Android's background-work killer, storage
  full, the cloud provider dropping the SAF connection, or the user force-quitting.
  On iOS the folder still holds the complete previous manifest and every previous asset,
  and the next sync retries cleanly. On Android the folder holds a zero-length or
  half-written `manifest.json`. That file is the sync folder's index of the entire
  library. On the next sync-down — and on every *other* device pointed at that folder —
  `BackupValidator` fails to parse it and the folder is unusable; the orphan-pruning passes
  at `SyncRepository.kt:176` and `:193` then have no manifest to compute "expected" from.
  The user's off-device backup is destroyed by an interrupted write.
- **Evidence:** read both write paths end to end. Grepped the Android backup package for
  any staging or rename primitive — `grep -rniE "renameTo|atomic|\.part|createNewFile"
  backup/` over `BackupExporter.kt`, `BackupPaths.kt`, `BackupRepository.kt` returns no
  staging of any kind; the only `openOutputStream` calls are the two `"wt"` ones plus
  `BackupScreen.kt:61` (a user-chosen export target, where truncation is correct because
  the user picked the file). Ruled out: (a) that SAF might make `"wt"` atomic — it does
  not, `"wt"` maps to `ParcelFileDescriptor.MODE_TRUNCATE` and the truncation is applied
  on open; (b) that a `.tmp`-and-rename existed elsewhere — no `DocumentsContract.
  renameDocument` call exists anywhere in the tree; (c) that this is deliberate — see
  History.
- **History:** not recorded as a decision anywhere — and the surrounding record makes this
  a miss rather than a trade-off, in three independent ways:
  1. **It is a named, binding invariant on the iOS side.**
     `docs/DATA_AND_PERSISTENCE_INVARIANTS.md:39` — "Writes: stage to
     `itemReplacementDirectory` (same volume) → `replaceItemAt` — the remote package must
     survive any failed write. **Never remove-then-write.**" `docs/AGENT_ONBOARDING.md:46`
     repeats it in the pitfalls table, annotated "(sync package destruction window)" — the
     pitfalls table is described in that file's own header as scar tissue from real
     debugging sessions. `AGENTS.md:153` makes the invariants doc binding for any change
     touching sync.
  2. **The Android port plan specified it and the contract doc already claims it is done.**
     `docs/android/ANDROID_PORT_PLAN.md:1005` — "Write EPUB files atomically."
     `docs/contracts/BACKUP_FORMAT.md:83` states, as settled behaviour, "EPUB files are
     written atomically when present." That sentence is true of the *restore* path (which
     lands files in app-private storage) and **false** of the sync-folder write path. A
     contract document asserting an atomicity guarantee the sync path does not provide is
     itself worth fixing, because it is what a future agent will trust instead of reading
     `SyncRepository.kt`.
  3. **Android already implements exactly this discipline elsewhere.**
     `files/WorkFileStore.kt:24-39` writes an EPUB by creating
     `Files.createTempFile(worksDirectory, ".$workId-", ".tmp")`, writing to it, then
     `Files.move(temp, destination, REPLACE_EXISTING, ATOMIC_MOVE)` with a non-atomic
     `Files.move` fallback and a `deleteIfExists(temp)` cleanup; `:80-90` does the same for
     originals. So this is not a team that does not know the pattern, and not a platform
     that cannot express it. The one path where the destination is a *user-visible,
     shared, and irreplaceable* folder is the one path that does not use it.
- **Recommendation:** Android moves. Note honestly that SAF has **no** atomic-replace
  primitive, so `.atomic` cannot be mirrored exactly — do not write a task that implies it
  can. The achievable fix is to narrow the window and keep a fallback: write to
  `manifest.json.tmp`, `flush()` + `fd.sync()`, then `DocumentsContract.renameDocument`
  over the live name, and retain the previous manifest as `manifest.json.bak` that
  sync-down falls back to when the primary fails to parse. That reduces an
  entire-write-duration hole to a rename, and makes the remaining hole recoverable.
  This is also the single highest-value place to add Android test coverage — see
  *Asymmetric test coverage*, where this exact rule turns out to be pinned on iOS and
  unpinned on Android.

### 6. Android's User-Agent reports version 0.1.0; the app is 0.2.0 — `real-bug` · Networking

`docs/AO3_NETWORKING_POLICY.md` makes "One identifiable User-Agent, with contact" the first
of its hard rules, and frames the whole policy as "Respectful access is a hard product
requirement — community trust is the whole ballgame." Android currently misidentifies its
version to AO3 on every single request.

- **iOS:** `Services/AO3AuthService.swift:202-207` builds the UA at runtime —
  `Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"`
  interpolated into `KudosReader/\(version) (+https://github.com/cidy02/kudos-ao3-reader)`.
  It cannot drift: the string is derived from the shipped bundle.
- **Android:** `network/ao3/AO3UserAgent.kt:14` — `const val APP_VERSION: String = "0.1.0"`,
  a compile-time literal, interpolated at `:19`. The actual app version is
  `android/app/build.gradle.kts:27-28` — `versionCode = 8`, `versionName = "0.2.0"`.
- **Divergence:** the two UA strings are otherwise byte-identical (I compared them
  character by character — same Safari-shaped base, same token order, same contact URL). The
  only difference is that iOS's version tracks the build and Android's is a hand-maintained
  constant that **has already fallen out of date by a minor version**.
- **Scenario:** an AO3 sysadmin sees traffic from `KudosReader/0.1.0`, correlates it with a
  behaviour they want to discuss or block, and reaches for the version. Every Android
  install — including the eight `versionCode`s shipped since — reports `0.1.0`. The
  identifiable-UA rule exists precisely so operators can distinguish releases; a frozen
  version silently removes that. It also means a future "0.1.0 has a bug, please upgrade"
  conversation cannot be acted on, because 0.1.0 is indistinguishable from current.
- **Evidence:** read both UA definitions. Confirmed `APP_VERSION` has exactly two references
  in the whole Android tree (`grep -rn "APP_VERSION" app/src/main/java/` → its own
  declaration and its own interpolation), so nothing else keeps it honest. Confirmed the
  invariant script does not catch it: `android/Scripts/check-invariants.sh:14-21` checks only
  that `Mozilla/5.0` appears nowhere outside `AO3UserAgent.kt` and that a `KudosReader/`
  token is present — never that the version matches `versionName`. Ruled out: (a) that
  `APP_VERSION` is generated or substituted at build time — it is a plain `const val` with a
  literal, and `build.gradle.kts` has no `buildConfigField` or token-replacement writing it;
  (b) that Android has no runtime alternative — `BuildConfig.VERSION_NAME` is available to
  any Android module and is exactly the `CFBundleShortVersionString` analogue.
- **History:** not recorded anywhere. Notable in context: the memory of this project records
  that Android has a GitHub self-update system where "every future fix/feature now needs a
  build+publish", so `versionName` moves regularly while this constant does not — the drift
  will keep widening on its own.
- **Recommendation:** Android moves, one line: `const val APP_VERSION = BuildConfig.VERSION_NAME`
  (adding `buildConfig = true` to the `buildFeatures` block if it is not already on). Worth
  pairing with one more line in `android/Scripts/check-invariants.sh` asserting that the UA's
  version token equals `versionName`, since the existing invariant already guards this file
  and clearly intends to keep it single-sourced — it just guards the wrong property.

### 5. A backup that round-trips through Android comes back to iOS with EPUB preservation state erased — `real-bug` · Persistence + backup

Android decodes nine optional iOS work fields, has no Room column for any of them, and does
not re-emit them on export. The archive is therefore lossy in one direction, and the loss is
silent because `explicitNulls = false` removes the keys rather than writing nulls.

- **iOS:** `Models/Models.swift` `SavedWork` stores all of them. On import,
  `Services/KudosBackup.swift:561-564` decodes a **missing** `epubPreservationStatusRaw` as
  `EPUBPreservationStatus.notPreserved.rawValue`, and `:565-568` decodes a missing
  `metadataSyncStatusRaw` as `MetadataSyncStatus.unknown.rawValue`. The merge at `:1973-1975`
  then applies it: `if incomingWins || work.epubPreservationStatus == .notPreserved {
  work.epubPreservationStatusRaw = archived.epubPreservationStatusRaw }`. On a fresh restore
  `incomingWins` is forced true (`:1895`, `isNewRecord ||…`), so the substituted default wins.
- **Android:** `data/local/entity/WorkEntity.kt` has 46 columns and none of these. The export
  mapper `backup/BackupMappers.kt:72-121` (`toBackupWork`) never mentions them, so each falls
  back to its `BackupWork` default — `null` — and `backup/BackupJson.kt`'s
  `explicitNulls = false` drops the key from the JSON entirely.
- **Divergence:** iOS→Android→iOS is not identity. Fields lost outright:
  `epubPreservationStatusRaw`, `metadataSyncStatusRaw`, `preservedAt`,
  `lastPreservationAttemptAt`, `assetIdentifier`, `datePublished`, `dateUpdated`,
  `ao3SeriesID`. (`bookmarks` is also absent but is the known T-193 divergence, not counted
  here.) **Two degrade rather than vanish, and it is only fair to say so:** `createdAt`
  falls back to `dateAdded` at `:1900`, and `ao3WorkID` self-heals because
  `:1966` re-derives it — `work.ao3WorkID ?? archived.ao3WorkID ?? WorkTags.ao3WorkID(from:
  archived.sourceURL)`.
- **Scenario:** an iPhone user has preserved 200 works — `epubPreservationStatus == .preserved`,
  which is the whole point of the preservation feature. They back up, restore on a new
  Android phone, use it for a month, then move back to iOS and restore Android's backup onto
  a clean install. Every work returns with `epubPreservationStatus == .notPreserved` and
  `metadataSyncStatus == .unknown`, despite the EPUBs themselves being present in the archive
  and restored correctly. AO3 publication and update dates are blank, series IDs are gone.
  Nothing warns the user, and there is no way to tell the restored state from a library that
  was never preserved. The clean-install case is the one that matters: with an existing local
  record, `newest(work.preservedAt, archived.preservedAt)` at `:1978-1982` keeps the local
  value, so the loss only bites in exactly the disaster-recovery scenario backups exist for.
- **Evidence:** derived the column/field diff mechanically rather than by eye — extracted
  stored (not computed) `var`s from `SavedWork` and `val`s from `WorkEntity` and set-differenced
  them: 64 stored iOS properties against 46 Room columns. Then read `toBackupWork`
  (`BackupMappers.kt:72-121`) in full to confirm the export omission, and the iOS decode
  defaults at `KudosBackup.swift:555-575` to confirm what a missing key becomes.
  Ruled out: (a) that `BackupValidator` carries unknown work fields through — its
  carry-through comment and `manifest.copy(...)` cover *queues, annotations and tombstones*
  only, and in any case that path runs during **import**, so it cannot survive a trip through
  a Room database that has no column; (b) that the fields are recovered by a later AO3 refresh
  — `epubPreservationStatusRaw` and `preservedAt` describe local file state, which no network
  refresh restores; (c) that iOS ignores a missing key instead of substituting — it does not,
  the `?? …notPreserved.rawValue` is explicit.
- **History:** partially acknowledged, in a way that makes the gap sharper.
  `backup/BackupManifest.kt:97` labels this exact block "Apple v5–v8 optional work fields
  (ignored for local model until ported)" — so the *decode* side is a conscious deferral. But
  `backup/BackupValidator.kt:130-131` shows the team already understands the round-trip
  hazard and solved it elsewhere: "Queues/annotations/tombstones are applied by
  BackupMergeService; carry them through here unchanged **so re-export doesn't drop
  anything**." Work fields never got that treatment. No `TASKS.md` ID covers it.
- **Recommendation:** Android moves, and it does not need 9 new columns to do it. The cheap
  fix matching the pattern the codebase already uses: add one `unmappedFieldsJson` TEXT column
  to `WorkEntity`, stash the undecoded remainder on import, and splice it back in
  `toBackupWork` — preserving every present and future iOS field for the cost of one column
  and one migration. Porting the fields properly is the better long-term answer for the two
  that drive UI (`datePublished`, `dateUpdated`) and the preservation trio, but the
  pass-through is what stops the bleeding now. Either way this wants the round-trip test that
  does not exist on either platform: export → import → export → assert the two manifests are
  equal.

### 4. Restoring an iOS backup on Android converts every queue-only work into a saved library item — `real-bug` · Backup / restore

This was lead L-3; it is now confirmed, and it turns out to defeat the exact feature
finding 3 shows Android has just implemented.

- **iOS:** `Services/KudosBackup.swift:1931` merges the flag by last-writer-wins and
  nothing else — `work.isSaved = incomingWins ? archived.isSaved : work.isSaved`. iOS
  *deliberately produces* works with `isSaved == false` and an EPUB present:
  `Services/ReadingQueueService.swift:300` and `:550` both run
  `if createdNewWork { saved.isSaved = false }` and then immediately
  `try await preserve(saved, in: context, downloadEPUB:)`, which downloads and stores the
  EPUB. That is the queue-only-with-preserved-EPUB state, and
  `Models/Models.swift:378-380` defines `isQueueOnlyWork` as
  `isQueuedForLater && !isSaved && !isFavorite`.
- **Android:** `backup/BackupMergeService.kt:193`, inside the `incomingWins` branch —
  `isSaved = restored.isSaved || existing.isSaved || (existing.hasEpub || restored.hasEpub)`.
  The presence of an EPUB on *either* side forces `isSaved` true regardless of what the
  archive says. `core/model/SavedWork.kt:81-82` defines `isQueueOnlyWork` identically to
  iOS, so forcing `isSaved` true also forces `isQueueOnlyWork` false.
- **Divergence:** iOS treats "saved to Library" and "has a local EPUB" as independent;
  Android's restore treats an EPUB as proof of saved-ness. `isSaved` can therefore only ever
  travel false→true across a restore on Android, never true→false.
- **Scenario:** on iPhone, add a work to a reading queue without saving it. iOS creates it
  with `isSaved = false` and preserves the EPUB, so it stays out of the Library shelves and
  out of Reading Now / Recently Updated / Recently Opened — that is the whole point of the
  queue-only concept. Back up, restore on Android. `restored.isSaved` is false and
  `existing` is absent, but `restoredHasEpub` is true because the archive carried the EPUB,
  so `:193` evaluates to true. The work lands as a full Library item, is counted in the
  saved totals, and appears in the Home sections `home/HomeSectionKind.kt:50,59,64`
  explicitly filters queue-only works out of. A second, subtler case: un-save a work on
  iOS that has a downloaded EPUB, sync, and the un-save never reaches Android.
- **Evidence:** read `mergeWork` in full, both branches (`BackupMergeService.kt:176-284`).
  Ruled out: (a) that the `else` branch compensates — it does not touch `isSaved` at all
  (`:205-229`), which correctly mirrors iOS's `: work.isSaved`, so the divergence is
  confined to the `incomingWins` branch; (b) that the neighbouring rules diverge too, which
  would suggest a generally sloppy port — they do not: `isQueuedForLater` is OR'd on both
  (iOS `:1971`, Android `:194`), `dateAdded` is `min` on both (iOS `:1901`, Android `:195`),
  `lastModifiedAt` is `max` on both (iOS `:1996`, Android `:196`). `isSaved` is the one
  field that departs, which is why it reads as an oversight rather than a design;
  (c) that Android's `hasEpub` derivation is itself wrong — it is not,
  `BackupMergeService.kt:63-67` grounds it in real file presence
  (`incomingEpub != null || id in currentEpubIds || existing?.hasEpub == true`).
- **History:** not recorded. The `isSaved` semantics *cluster* is documented on the Android
  branch (`docs/audits/ANDROID_PARITY_REPORT.md:231,247,292`), but every instance there is
  in the import/library-query paths — `WorkImporter.saveMetadataOnly`,
  `WorkMetadataMerger.merge`, `WorkRepository.observeSavedWorks`. No document mentions
  `BackupMergeService`, and greps for `isSaved` across `docs/` return no hit in a backup
  context. This is a new instance of a known root divergence, in a file nobody has looked at.
- **Recommendation:** Android moves, and the fix is to delete the clause:
  `isSaved = restored.isSaved` in the `incomingWins` branch, matching iOS exactly. The
  `hasEpub` guard is protecting the wrong invariant — Android already preserves the EPUB
  itself via `hasEpub = existing.hasEpub || restored.hasEpub` on the next line, and
  `SavedWork.kt:69-75` already folds `isQueuedForLater` into deletion protection, so
  nothing needs `isSaved` forced true to keep the file safe. Worth pairing with the
  round-trip test neither platform has: save → un-save → export → restore → assert
  `isSaved` is still false.

### 3. The Android branch's own audit corpus is stale: the `isQueuedForLater` / queue-only gap it reports as open is implemented — `real-bug` (in the documentation) · Cross-cutting

This is a finding about the *record*, not the code, and it is reported because acting on
that record would waste a work cycle re-building something that exists.

- **Claimed, in three places on the Android branch:**
  `docs/audits/ANDROID_PARITY_REPORT.md:231` — "On Android there is no
  `isQueuedForLater`/queue-only concept at all in `SavedWork` (`core/model/SavedWork.kt`)
  or `LibraryQuery`." `docs/audits/ANDROID_PARITY_FINDINGS_VERIFIED.md:59` lists it as
  **CONFIRMED**, and `:23` names it among the "Highest-priority CONFIRMED majors (still
  open)". `docs/audits/PARITY_SWEEP2_A_home-library-queues-stats.md:6,24` then excludes
  the whole cluster from re-review on the grounds that it is already covered as a known
  open gap.
- **Actually, at `a5a46116`:** it is implemented, and implemented as a deliberate mirror of
  iOS.
  - `core/model/SavedWork.kt:21` — `val isQueuedForLater: Boolean = false`, with the
    comment at `:17-20` explicitly citing iOS's `SavedWork.isQueuedForLater` and noting it
    is "Kept distinct from `isSaved`".
  - `core/model/SavedWork.kt:80-82` — `val isQueueOnlyWork get() = isQueuedForLater &&
    !isSaved && !isFavorite`, documented as "iOS `SavedWork.isQueueOnlyWork`". That is
    character-for-character the iOS predicate the audit quotes from `Models.swift:376-378`.
  - `data/local/entity/WorkEntity.kt:59` — the backing Room column exists.
  - `home/HomeSectionKind.kt:50`, `:59`, `:64` — queue-only works are filtered out of
    exactly three sections, which are the same three (Reading Now / Recently Updated /
    Recently Opened) the audit says iOS excludes them from at `HomeSections.swift:57,66,71`.
  - `library/LibraryQuery.kt:14` carries a comment stating a queue-only work is
    "intentionally not on the main saved" shelf, and
    `core/model/SavedWork.kt:69-75` folds `isQueuedForLater` into the deletion-protection
    predicate with the note "queue-add now preserves the EPUB".
- **Divergence:** between the Android branch's documentation and the Android branch's code.
- **Scenario:** a planner reads `ANDROID_PARITY_FINDINGS_VERIFIED.md`, sees a
  highest-priority confirmed-open major, and schedules "add `isQueuedForLater` to Android".
  The work is already done. Worse, `PARITY_SWEEP2_A:6` uses the same belief to *exclude*
  the area from a later sweep, so the cluster is simultaneously "known open" and "not
  re-checked" — the state in which a stale claim survives indefinitely.
- **Evidence:** greps run against `a5a46116` — `grep -n "isQueuedForLater|isQueueOnly"
  core/model/SavedWork.kt data/local/entity/WorkEntity.kt` and
  `grep -rn "isQueueOnly" --include="*.kt" .`, which returns hits in `SavedWork.kt`,
  `settings/QueueStorageScreen.kt` (`:119`, `:244`, `:281`, `:316`),
  `home/HomeSectionKind.kt` and `library/LibraryQuery.kt`. I did **not** verify the
  *whole* cluster: specifically, whether `WorkImporter.saveMetadataOnly` still hard-codes
  `markSaved = true` (the audit's other half) is **unchecked** — see lead L-3. So the
  correct statement is "the model/query half of this cluster is closed", not "the cluster
  is closed".
- **History:** the audit documents carry no revision date tying them to a SHA, which is why
  the staleness is invisible from inside them. Note the same pattern as finding 1's
  `BACKUP_FORMAT.md:83`: an Android-branch document asserting something the code
  contradicts. In finding 1 the doc over-claims completion; here it under-claims it. Both
  directions cost real work.
- **Recommendation:** neither platform's code moves. The Android audit documents should
  gain a "verified at `<sha>`" line and have this cluster's status corrected. More
  generally: the review prompt's first rule — "review the trees, not the reports" — is
  earning its place. Two of the three documents this review cross-checked turned out to
  misdescribe the code.

---

## Bugs present on both platforms

### 2. Sync skips any changed file whose byte length is unchanged — `real-bug` · `DEFERRED` · Backup / folder sync · **both platforms**

> **This is not a new discovery, and this review adds nothing to it.** It is already
> written up — correctly, in more detail than I would have given it, and on both halves —
> on the Android branch at `docs/iOS_Issues_Found_While_Porting.md:69-96`, under the
> heading "Sync skips unchanged files by size alone, so a same-size edit never syncs".
> That entry cites the same iOS lines (`:707-710`, and `:687` for the unconditional
> manifest write), makes the same "the index stays correct while the asset is stale —
> arguably worse than both being stale" argument, proposes the same fix ("A content hash,
> or size plus modification time, would close it"), **and already records that Android
> ported it deliberately**: *"ported faithfully (`backup/SyncRepository.kt`
> `writeIfChanged`), because iOS is the specification for this sweep and diverging
> unilaterally would make the two platforms disagree about what 'unchanged' means. Fix
> both together."*
>
> It is retained here, tagged `DEFERRED`, for exactly one reason: it is the clearest
> instance in the codebase of the category this report is asked to surface, it remains
> unfixed at both review SHAs, and it has no `TASKS.md` ID, so nothing schedules it. The
> only thing I verified independently is that it is still true at `e9ed0c6a` / `a5a46116`.

- **iOS:** `kudos-ao3-reader/Services/FolderSyncService.swift:707-709` —
  `writeIfChanged` returns early when `existingSize == data.count`, comparing **only**
  the file's byte length against the new payload's byte length. No hash, no mtime.
- **Android:** `backup/SyncRepository.kt:217-221` — `writeIfChanged` returns early when
  `file.length() == data.size.toLong()`. The same rule, ported faithfully, including the
  name of the function.
- **Divergence:** none between the platforms — that is the point. This is one wrong
  assumption implemented identically twice, so no amount of iOS↔Android comparison
  surfaces it; only asking what the rule *is* does.
- **Scenario:** a user has work X synced. AO3's copy is edited by its author — a typo
  fixed, a word swapped for another of the same length, a punctuation change — and Kudos
  re-downloads the EPUB. EPUB is a ZIP: a same-length content change very often yields a
  same-length archive (the compressed streams differ, the central directory and entry
  sizes do not move). `writeIfChanged` compares 41,932 bytes to 41,932 bytes, returns
  early, and the sync folder keeps the **old** EPUB forever. Every other device syncing
  from that folder receives the stale text. The manifest is rewritten (it goes through
  the unconditional path, not `writeIfChanged`), so the sync *reports success* and the
  user has no signal at all that one work's content never propagated. The same applies to
  a custom font replaced by a different font of identical file size.
- **Evidence:** read both implementations in full. Confirmed that the manifest write does
  **not** go through `writeIfChanged` on either platform (iOS `FolderSyncService.swift:687-690`;
  Android `SyncRepository.kt:201-206`), so nothing downstream compensates — the manifest
  changing does not cause the asset to be re-copied. Ruled out: (a) that EPUBs are
  content-addressed by name, so a changed file would land under a new name — they are not,
  the name is `<work-uuid>.epub` on both sides (iOS `:680`, Android `:169`) and is stable
  across re-downloads; (b) a checksum anywhere in either path —
  `grep -niE "sha|md5|checksum|digest"` over both files returns zero hits.
  **Not** ruled out by grep alone, and worth stating precisely: iOS *does* read
  modification dates in this file — `coordinatedContentModificationDate` at
  `FolderSyncService.swift:741-748`, called from `:273`, `:338` and `:380`. Reading those
  three call sites shows they all operate on `manifestURL` (and a legacy URL), to decide
  sync *direction* and staleness of the folder as a whole. None of them is on the
  per-asset path, and `writeIfChanged` at `:707-709` consults nothing but size. Android
  has no modification-date read at all in `SyncRepository.kt` (same grep, zero hits).
- **Why it is written this way:** deliberately, and for a good reason — the iOS comment at
  `:677-679` explains that leaving unchanged files untouched (same inode) is what lets
  iCloud Drive upload only the delta. Hashing every EPUB on every sync would be the
  obvious fix and would cost a full read of the library each time. So this is a real
  trade-off that was made consciously on iOS; what is missing is that the *cheap* half of
  the trade-off was taken without the correctness half.
- **History:** `docs/iOS_Issues_Found_While_Porting.md:68-90` (Android branch) records the
  iOS side; nothing records the Android side, and nothing in `TASKS.md` assigns it an ID or
  a decision. It has therefore been known and unowned for as long as that document has
  existed.
- **Recommendation:** both platforms move, and the fix should stay cheap: compare
  `(size, mtime)` rather than size alone. That keeps the same-inode / delta-upload property
  the iOS comment is protecting, costs one stat per file instead of a full read, and closes
  the case above because a re-download updates mtime even when it does not change length.
  A content hash is the belt-and-braces option and is not worth a full library read on
  every sync. iOS already has the helper it needs —
  `FolderSyncService.swift:741-748`'s `coordinatedContentModificationDate` — currently used
  only against the manifest; Android would use `DocumentFile.lastModified()`, which it does
  not currently call anywhere in `SyncRepository.kt`.

---

## Asymmetric test coverage

Partially assessed. The shape of the two suites, established by direct enumeration:

| | iOS | Android |
|---|---|---|
| Test files | 85 under `KudosTests/` | 93 under `android/app/src/test/` |
| Test targets / source sets | one target, `KudosTests` (only `name = KudosTests;` appears in `AO3_App_OpenSource.xcodeproj/project.pbxproj`) | one source set, `src/test` (JVM) |
| UI / instrumented tests | **none** — no UI-test target, and `grep -rl XCUIApplication KudosTests` → zero hits | **none** — `android/app/src/androidTest/` does not exist |
| UI-test dependency declared | n/a | yes — `androidTestImplementation(libs.androidx.compose.ui.test.junit4)` at `android/app/build.gradle.kts:110`, plus the Compose BOM at `:77` |
| Android-framework simulation in unit tests | n/a | Robolectric (`android/app/build.gradle.kts:117`), used by ≥10 unit tests incl. `ReaderViewModelPreferencesTest.kt`, `CommentsViewModelDraftTest.kt`, `RoutesNavigationTest.kt`, `ThemeTest.kt` |

Two observations follow, and they point in opposite directions:

1. **Neither app has a single UI-level test.** This is a *shared* gap, not an asymmetry —
   every screen on both platforms is verified only by the human screenshot gate that
   `AGENTS.md` mandates. It is recorded here rather than in Findings because it is a
   property of the project's testing strategy, not a divergence between the two apps.
2. **Android declares an instrumented-test dependency it never uses.**
   `androidTestImplementation(libs.androidx.compose.ui.test.junit4)` is resolved on every
   build for a source set that does not exist. That is dead build configuration —
   `minor`, and worth deleting or filling.

### One per-rule asymmetry, established

The full per-rule comparison is **not done** — it is the substance of this section and
belongs to area 21, which was never dispatched. But the backup/sync area produced one
instance directly, and it is the one that matters most, because it sits under finding 1:

| | iOS | Android |
|---|---|---|
| Folder-sync tests | `KudosTests/FolderSyncTests.swift`, **796 lines**, plus `FolderSyncBackgroundTaskTests.swift` | **none** — `android/app/src/test/…/backup/` contains only `BackupCompatibilityTest.kt` and `DatabaseChangeTrackerTest.kt` |

`SyncRepository.kt` — the file holding both findings above — has no test of any kind.
That is precisely the prediction the review prompt makes about asymmetric coverage: *where
one platform pins a rule and the other does not is where the divergence appears next*.
Here it already has. The write-atomicity rule is pinned on iOS by a 796-line suite and is
unpinned on Android, and Android is the platform that lost it.

---

## Already-known divergences, re-checked

The calibration list from the review prompt. Status filled in as each area is reached.

| Known divergence | Recorded in | Re-checked? | Status |
|---|---|---|---|
| "Show zero counts" (Settings → Library) is iOS-only; Android always shows zeros | `TASKS.md` T-193 | ⬜ | |
| Android's `SavedWork` has no `bookmarks` column | `TASKS.md` T-193 | ⬜ | |
| Compose `FlowRow` applies `SpaceBetween` to a wrapped last row; iOS leaves it ragged | `TASKS.md` T-193 | ⬜ | |
| iOS ships two readers (Readium iOS / legacy macOS); Android has one | prompt | ⬜ | |
| Android has a GitHub-backed self-update system; iOS has none | prompt | ✅ | **Still true.** `grep -rniE "appUpdate\|checkForUpdate\|releases/latest\|api\.github\.com\|installUpdate\|AppUpdateRepository" kudos-ao3-reader --include="*.swift"` returns exactly two hits, both `WorkUpdateChecker` — which checks *AO3 works* for new chapters (`Services/WorkUpdateChecker.swift:17`, called from `Features/Home/HomeView.swift:134`), not the app. iOS has no app-update path of any kind. Android's lives in `update/` + `network/github/`. |

---

## Open leads

*Nothing is ever deleted from this section — leads are promoted to Findings or moved
to Ruled out with a reason.*

**L-1 — the Android branch's in-tree copy of the iOS app is 122 files behind.**
Suspicion: Android work is being ported against a stale iOS reference, so "parity"
decisions recorded on the Android branch may be parity with an iOS that no longer
exists. Where seen: `find .claude/worktrees/android-exclusion-parity/kudos-ao3-reader
-name '*.swift' | wc -l` → **92**, versus **214** in `hig-review-reference`. The check
that settles it: diff the file lists, then confirm whether any Android-side doc or
task cites iOS behaviour that `hig-review` has since changed. This is a process
finding, not a user-visible one — it is recorded here because it predicts *where*
user-visible drift will be found.

**L-3 — RESOLVED → promoted to finding 4.** The `isSaved` merge-rule divergence is
confirmed: iOS assigns the flag outright (`KudosBackup.swift:1931`), Android ORs it with
EPUB presence (`BackupMergeService.kt:193`), so an iOS queue-only work becomes a saved
Library item on restore. See finding 4 for the full write-up and the ruled-out alternatives.

**L-5 — Android may not downgrade a stale `hasEpub` when the file is gone.** Suspicion:
iOS actively clears the flag — `KudosBackup.swift:1229`, `work.hasEPUB = false` in the
`else if !FileManager.default.fileExists(...)` branch, which also demotes
`epubPreservationStatus` to `.missingFile`. Android's equivalent
(`BackupMergeService.kt:64-67`) computes
`existingHasEpub = id in currentEpubIds || existing?.hasEpub == true` — the trailing OR
means a DB flag that is already true survives even when the work has no file on disk and
none in the archive. A user whose EPUB was removed out from under the app (storage
cleaner, restored-from-a-thinner-backup) would keep seeing the work as downloaded on
Android and would see it correctly marked missing on iOS. The check that settles it: read
what populates `currentEpubIds` in `BackupMergeService`, then test a restore where the DB
says `hasEpub = true`, no file exists locally, and the archive carries no EPUB for that id.
Low severity — cosmetic until the user taps Read — but it is the same class as finding 4:
a flag Android can raise and never lower.

**L-4 — the other half of the `isQueuedForLater` cluster is unverified.** Finding 3
establishes that the model/query half is implemented. `docs/audits/ANDROID_PARITY_REPORT.md:292`
also claims `WorkImporter.saveMetadataOnly` hard-codes `markSaved = true`
(`WorkImporter.kt:25-36`, specifically `:32`) so every queue-add still becomes a full
library item, and that `ReadingQueueRepository.removeWork` never cleans up a queue-only
work the way iOS's `removeFromQueueAndDeleteIfQueueOnly` does. I did not open either file.
The check that settles it: read `works/WorkImporter.kt:25-36` and
`library/ReadingQueueRepository.kt:75-79,132-135` against
`Services/ReadingQueueService.swift:242,270-300,550,575-600`. Until that is done, finding 3
should be read as narrowly as it is written.

**L-2 — `exportedAt` is the one manifest date that bypasses Room, and its precision is
unverified.** Suspicion: R-1 below proves the date round trip is safe *because* every
`Instant` is milli-precision after a Room round trip. `exportedAt` is the exception — it
comes straight from an injected clock, `backup/BackupRepository.kt:31`
(`private val clock: () -> Instant = { Instant.now() }`), and `backup/SyncRepository.kt:31`
does the same. iOS decodes it as a real `Date` (`KudosBackup.swift:228`) through the strict
two-formatter strategy. If `Instant.now()` on the target Android runtime returns
microsecond-precision nanos — as `Clock.systemUTC()` does on OpenJDK 9+, though Android's
libcore has historically been millisecond-backed — then `formatInstant` emits six fractional
digits, iOS's fractional formatter rejects it, the whole-second fallback rejects it, and
`KudosBackup.swift:200-205` throws. That aborts the **entire** import of an Android-written
archive on iOS. Where seen: `BackupValidator.kt:161` (`instant.toString()`) reached from a
non-Room source. The check that settles it: on a device/emulator at the project's `minSdk`,
evaluate `Instant.now().nano % 1_000_000` — non-zero means the hazard is live. The fix is
one call either way and is worth making unconditionally: `.truncatedTo(ChronoUnit.MILLIS)`
in `formatInstant`, which also makes Android's output identical in shape to iOS's for every
field. **I could not settle this from source alone and am not claiming it as a defect.**

---

## Verified agreement

A verified "these genuinely agree" is a result, not an absence of one. This section records
only comparisons where the rule was non-trivial and I read both implementations in full.

### V-1 — the sync merge/conflict rules are semantically identical, including the parts most likely to rot

`SyncMerge` is the decision core of backup restore on both platforms: it decides which
record survives a conflict, whether a deleted record may be revived, and how a reading
queue's effective modification time is computed. iOS `Services/PersistenceSync.swift:379-431`
against Android `backup/BackupMergeService.kt:718-753`, function by function:

| Rule | iOS | Android | |
|---|---|---|---|
| `shouldApplyIncoming` — incoming missing | `guard let incomingModifiedAt else { return false }` (`:396`) | `if (incomingModifiedAt == null) return false` (`:720`) | ✅ |
| — local missing | `guard let localModifiedAt else { return true }` (`:397`) | `if (localModifiedAt == null) return true` (`:721`) | ✅ |
| — both present | `incomingModifiedAt >= localModifiedAt` (`:398`) | `!incomingModifiedAt.isBefore(localModifiedAt)` (`:722`) | ✅ same relation, **ties go to incoming** on both |
| `effectiveQueueModifiedAt` | max of the non-nil of (`dateUpdated`, `lastMembershipChangedAt`) plus every membership's `lastModifiedAt` (`:405-412`) | `(listOfNotNull(queueUpdatedAt, lastMembershipChangedAt) + membershipModifiedAts).maxOrNull()` (`:726-733`) | ✅ |
| `tombstoneResolution` — no tombstone | `.noTombstone` (`:428`) | `NO_TOMBSTONE` (`:739`) | ✅ |
| — tombstone but no incoming timestamp | `.preserveAmbiguous` (`:429`) | `PRESERVE_AMBIGUOUS` (`:740`) | ✅ |
| — both present | `incomingModifiedAt > tombstoneDeletedAt` → revive, else suppress (`:430`) | `incomingModifiedAt.isAfter(tombstoneDeletedAt)` → `REVIVE_NEWER`, else `SUPPRESS_STALE` (`:741-745`) | ✅ **strict** `>` on both, so **ties suppress** |

The detail worth dwelling on is the last two rows against the third. `shouldApplyIncoming`
uses a **non-strict** comparison (a tie applies the incoming record) while
`tombstoneResolution` uses a **strict** one (a tie suppresses, i.e. a deletion wins a tie
against a same-instant edit). That asymmetry is deliberate and easy to lose in a port —
it is the difference between "a tie is harmless" and "a tie must not resurrect something
the user deleted". Android preserves it exactly. Both enum shapes match too, four cases
each with the same names.

**One thing was not ported: the reason.** iOS carries a comment at `PersistenceSync.swift:401-405`
explaining that `effectiveQueueModifiedAt` *deliberately* takes no
restore/import wall-clock parameter, because doing so "previously let a content-stale backup
revive an explicitly-deleted queue just because the file itself happened to be newer than
the tombstone" — i.e. it records a fixed bug. Android's equivalent (`:726-733`) has the
correct signature but no such note; its KDoc is only "Apple `SyncMerge` helpers used by
backup restore." Nothing is wrong today. The risk is that a future change to the Android
side that adds an export-time parameter looks like a reasonable improvement and silently
reintroduces a bug iOS already paid for. Recorded as `minor`, with the fix being one
comment, not one line of code.

---

### V-4 — every AO3 politeness constant matches, and Android enforces the no-retry-on-writes rule more strongly than iOS

`docs/AO3_NETWORKING_POLICY.md` is binding on both platforms and specifies exact numbers.
They agree, and one of them says so in a comment.

| Rule (policy doc) | iOS | Android | |
|---|---|---|---|
| Pacing ≥ 0.6 s between request **starts** | `AO3Client.swift:180` — `minRequestInterval: TimeInterval = 0.6` | `AO3NetworkConfig.kt:6` — `minDelayBetweenRequestsMillis = 600`, with the comment "Apple paces at 0.6s between starts (AO3RequestDefaults). Keep parity." | ✅ |
| Concurrency cap of 3 | `AO3RequestCoordinator.swift:28` — `init(limit: Int = 3)`, with `:16` noting it "matches the polite '2–3 concurrent metadata requests'" | `AO3NetworkConfig.kt:4` — `maxConcurrentRequests: Int = 3` | ✅ |
| Max 2 retries | `AO3Client.swift:298` — `withRetry<T>(maxRetries: Int = 2, …)` | `AO3NetworkConfig.kt:7` — `maxRetries: Int = 2` | ✅ |
| Backoff 0.5 s → 1 s → 2 s | `AO3Client.swift:330` — `0.5 * pow(2, Double(attempt - 1))` | `AO3RetryPolicy.kt:36` — `500L * (1L shl (retryNumber - 1).coerceAtLeast(0))` | ✅ identical curve |
| `Retry-After` honoured, floored by backoff | `:332-333` — `max(retryAfter ?? 0, backoff)` | `:38-39` — `maxOf(error.retryAfterMillis ?: 0L, backoff)` | ✅ |
| Retry only transient (5xx / 429 / transport) | `:331-340` — `rateLimited`, `server`, transient `URLError`; everything else returns `nil` | `:22-33` — `Network`, `Overloaded`, `RateLimited`, `Server` true; `BadRequest`, `AuthenticationRequired`, `Forbidden`, `NotFound`, `Http`, `Parse`, `Validation` false | ✅ |
| Identifiable UA, single-sourced | `AO3AuthService.swift:202-207` | `AO3UserAgent.kt:16-20` | ⚠️ same string, stale version — **finding 6** |

Two asymmetries that are *not* defects and are worth recording so nobody "fixes" them:

1. **Android enforces the write rule structurally; iOS enforces it by construction.** The
   policy says writes are "single-shot: never retried, never coalesced". Android's
   `AO3RetryPolicy.shouldRetry` opens with `if (method != AO3HttpMethod.GET) return false`
   (`:19`) — no non-GET can be retried, whatever the error. iOS achieves the same by having
   `submitWrite` simply not call `withRetry`. Android's is the more robust expression of the
   rule, because a future caller cannot accidentally opt a POST into retries. If anything,
   iOS could adopt it.
2. **Android has an `Overloaded` error class iOS does not** (`AO3OverloadDetector.kt`,
   handled at `AO3RetryPolicy.kt:24` and `:39`). It is treated exactly like `RateLimited` —
   retried, `Retry-After` honoured. That is an addition in the politeness direction, so it
   does not violate the policy's "no removal/weakening" clause. I did **not** read
   `AO3OverloadDetector.kt` to see what it detects; noted rather than assessed.

### V-3 — session storage, cookie handling and logout are at parity; no privacy divergence

The review prompt calls out weaker credential storage on one platform as a blocker-severity
privacy finding. I went looking for it and it is not there.

| | iOS | Android |
|---|---|---|
| Session store | Keychain, one item — `Services/AO3SessionVault.swift:96` `KeychainAO3SessionVault`, written with `SecItemAdd`/`SecItemUpdate` (`:127`, `:130`) | `auth/AO3SessionStore.kt:26` `EncryptedFileAO3SessionStore`, AES-256-GCM via `MasterKey.Builder(...).setKeyScheme(AES256_GCM)` (`:35-37`), i.e. hardware-backed Android Keystore |
| Device-only / no cloud escape | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (`:125`) — never syncs to iCloud Keychain, never restored to another device | file lives under `context.noBackupFilesDir` (`:116`), so it is excluded from Android auto-backup and device transfer |
| What is in plaintext | a bare "removal pending" flag and a username *hint* in `UserDefaults` (`:49`, `:68`), documented at `:40` and `:67` as "Non-secret — a bare flag, never session data" | nothing; the legacy plaintext store is discussed below |
| WebView cookie jar | `WKWebsiteDataStore.default().httpCookieStore` (`AO3SessionVault.swift:312`, `:317`, `:342`) | `android.webkit.CookieManager` (`auth/AO3CookieStore.kt:15`) |
| Logout clears the web cookie jar | yes | yes — `clear()` (`:41-51`) re-sets every AO3 cookie expired, for both `BASE_URL` and `WORKS_HOST`, then `flush()` |

Both scope the cookie wipe to AO3's hosts rather than nuking the whole jar, which is the
correct choice on both platforms.

**Ruled out — Android's plaintext session store is not reachable in production.**
`auth/AO3SessionStore.kt:111` defines `FileAO3SessionStore`, which writes the session as
unencrypted JSON. Its own KDoc at `:107-110` says it is "retained only for unit tests that
don't need Android Keystore". I did not take that on trust: `grep -rn` for its constructor
across the whole Android source root returns exactly one production wiring site,
`app/KudosAppContainer.kt:103`, and it passes `EncryptedFileAO3SessionStore`. Further, the
encrypted store actively migrates and deletes any legacy plain file (`:100`). Not a finding.

**One real asymmetry, reported as a note rather than a finding.** iOS's `logout()`
(`Services/AO3AuthService.swift:504-533`) does five things Android's
(`auth/AO3AuthRepository.kt:170-174` → `clearSession()` at `:184-188`) does not: it advances
a session generation to invalidate in-flight requests (`:505`), cancels the in-progress
login (`:506`), deletes the username hint (`:515`), clears the logged-out identity's
unresolved comment-submission guards (`:522-524`, annotated T91-RF2 — "must not survive the
account they were made under"), and refuses to report success if the durable delete threw
(`:526-533`, annotated A5-F4). Android's is four lines and reports no error.

I am not filing this as a finding for two reasons, and both are worth stating so a later
session does not re-open it. First, the leak iOS's comment-store clearing prevents does not
exist on Android: `network/ao3/comments/CommentDraftStore.kt:20-22` keys every draft by
`"draft:$workId:$chapterId:$parentId:${username ?: "guest"}"`, so account A's text can never
surface for account B — the same partitioning iOS achieves with `entriesByIdentity`
(`Services/CommentSubmission.swift:119-151`). The residual behaviour difference is only that
a draft survives on Android if the *same* user logs back in, which is arguably the better
product behaviour. Second, the *idempotency* half — Android lacking iOS's unresolved-submission
guard — is already documented on the Android branch
(`docs/audits/PARITY_SWEEP2_D_workdetail-reader-comments-infra.md:7`, "incomplete idempotency
guard", listed as already covered). What is genuinely unrecorded is the missing
delete-failure reporting, which is a one-line honesty gap rather than a user-visible defect.

### V-2 — Android's Room migration story is safe, and no destructive fallback exists

The review prompt flags `fallbackToDestructiveMigration` as a data-loss blocker if reachable
in a release build. It is not present:
`grep -rn "fallbackToDestructiveMigration|allowMainThreadQueries"` across the whole Android
source root returns **zero hits**. `data/local/KudosDatabase.kt:44-45` declares
`version = 7, exportSchema = true`, and `data/local/KudosDatabaseMigrations.kt` provides an
explicit, hand-written `Migration` object for every step — `MIGRATION_1_2` (`:20`),
`2_3` (`:159`), `3_4` (`:173`), `4_5` (`:181`), `5_6` (`:192`), `6_7` (`:199`). Six
migrations covering versions 1→7 with no gaps, so an existing user's database is carried
forward rather than recreated.

The comparison to iOS is not symmetric and should not be forced: SwiftData performs
lightweight migration implicitly from the model definitions, so there is no iOS artefact to
diff against these. The correct parity statement is that both platforms preserve an
upgrading user's data, by different mechanisms — which is a platform-idiom difference, not
drift. Note also `data/local/converters/KudosTypeConverters.kt:31-38`, which degrades a
corrupt JSON list column to `emptyList()` rather than throwing, with a comment explaining
that one bad row must not take down every query touching the column. That is defensive
behaviour iOS has no equivalent of, and it is a point in Android's favour rather than a gap.

---

## Ruled out

**R-1 — backup date encoding is *not* incompatible between the two apps.** This was the
most promising lead in the whole backup area and it does not survive contact with the code,
so it is worth recording in full to stop the next session chasing it.

The suspicion: `docs/AGENT_ONBOARDING.md:43` warns that plain `.iso8601` truncates to whole
seconds and makes merge decisions unorderable, and that iOS therefore uses "a fractional-seconds
encoder with whole-second decode fallback. Don't change either direction." iOS does exactly
that — `KudosBackup.swift:169-179` builds two `ISO8601DateFormatter`s (one with
`.withFractionalSeconds`, one without); `:181-189` always *writes* the fractional one;
`:191-206` *reads* fractional first and falls back to whole-second, throwing
`DecodingError` if neither matches. Android, meanwhile, writes dates via
`BackupValidator.formatInstant`, which is a bare `instant.toString()`
(`backup/BackupValidator.kt:161`). `Instant.toString()` emits `DateTimeFormatter.ISO_INSTANT`,
whose fractional part is *variable width* — 0, 3, 6 or 9 digits depending on the value's
nanos. `ISO8601DateFormatter` accepts **exactly** 3 fractional digits or none. So a 6- or
9-digit fraction from Android would fail both iOS formatters and abort the entire import.

Why it does not happen: every `Instant` that reaches the manifest comes back out of Room,
and Room stores them through `data/local/converters/KudosTypeConverters.kt:13-21`, which is
`instantToEpochMillis` / `epochMillisToInstant` — `toEpochMilli()` / `Instant.ofEpochMilli()`.
Millisecond precision in, millisecond precision out. A milli-precision `Instant` renders as
either 0 fractional digits (nanos == 0) or exactly 3. iOS's whole-second fallback covers the
first, its fractional formatter covers the second. The round trip is sound in both
directions, and Android's parser (`BackupValidator.kt:145-155`) accepts iOS's always-fractional
form via `Instant.parse`, with an `OffsetDateTime.parse` second chance for offset-bearing
timestamps. **Verified compatible.** One residual is carved out as lead L-2 below.

---

## Not covered

This is the honest majority of the review. **17 of 21 areas were not read at all.**

**Read closely (the only code this report's claims rest on):**
`Services/FolderSyncService.swift` (the sync write/commit path, ~lines 560–760),
`Services/KudosBackup.swift` (manifest struct, version constants, the encoder/decoder
date strategy), `Services/KudosBackupExport.swift` (skimmed);
`backup/SyncRepository.kt` in full, `backup/BackupManifest.kt` in full,
`backup/BackupVersion.kt`, `backup/BackupJson.kt`, `backup/BackupValidator.kt` (the
instant helpers and the manifest validation pass), `backup/BackupMappers.kt` (date call
sites only), `files/WorkFileStore.kt` (the atomic-write helpers),
`data/local/converters/KudosTypeConverters.kt`, and the `SyncMerge` object plus
`TombstoneResolution` at `backup/BackupMergeService.kt:718-753` against
`Services/PersistenceSync.swift:379-431`.

**Skimmed, conclusions not load-bearing:** the package/folder inventory of both trees
(used only to build the area map); `Features/Support/WhatsNew.swift` (line count only).

**Not reached at all:** areas 1–13, 15, 16, 18, 19, 20 — onboarding, auth/session,
networking core, search/filters, browse, work detail + writes, comments, authors/series,
the readers, library/queues/statistics, home, account/inbox, import/conversion,
persistence schema + migrations, settings/theming, support, error handling/empty states,
accessibility. Within area 14 itself, `BackupMergeService.kt` (866 lines) and
`PersistenceSync.swift` were **not** read, so nothing in this report says anything about
merge/conflict semantics.

**Where a follow-up should start, and a warning about it.** The Android branch carries its
own audit corpus that this review did not verify:
`docs/audits/PARITY_SWEEP2_A…D`, `ANDROID_PARITY_FINDINGS_VERIFIED.md`,
`ANDROID_PARITY_INDEPENDENT_REVIEW.md`, `IOS_ANDROID_DOMAIN_AUDIT.md`,
`REMAINING_PARITY_AND_UI_GAPS.md`, and `docs/Android_Parity_Review_2026-08-04.md`
(461 lines). Those cover much of areas 1–13 already. **They are claims, not evidence** —
the review prompt's first rule — and at least one of their sibling documents is now
provably wrong about the code (`docs/contracts/BACKUP_FORMAT.md:83` asserts atomic EPUB
writes that finding 1 shows the sync path does not perform). So the efficient next pass is
to treat them as a *lead list to re-verify against the trees*, not as coverage already
banked. That is also why they were not folded into this report wholesale — and finding 3
is that warning cashed in: the one cluster I spot-checked from those documents turned out
to be substantially implemented while still listed there as a "highest-priority CONFIRMED
major (still open)".

**Not run:** neither `Scripts/verify.sh` (iOS) nor `android/Scripts/verify.sh`. No build,
no test suite, no simulator or emulator run. Every claim here is static reading of source.
Lead L-2 in particular **cannot** be closed without running code.

---

## Method log

Chronological record of what was actually done, so a cold reader can judge the
evidence rather than trust the conclusions.

### 2026-08-07 — scoping pass (no source files read yet)

- Confirmed both worktrees exist at the SHAs the prompt names (`git worktree list`):
  `hig-review-reference` @ `e9ed0c6a`, `android-exclusion-parity` @ `a5a46116`.
- Read `AGENTS.md`, `docs/AGENT_ONBOARDING.md`, `docs/ADVERSARIAL_REVIEW_TEMPLATE.md`
  in the `hig-review` tree.
- `TASKS.md` in `hig-review` is 530 lines / 450 KB (very long rows). Indexed rather
  than read linearly: `grep -oniE '(android|parity|deferred|not ported|port to)…'`
  shows Android/parity material concentrated in rows 24, 26, 30, 61, 64, 75, 78, 82,
  87, 93, 116, 241, 262, 382. Full-text search against `TASKS.md` is the required
  check before any finding is reported.
- Enumerated both source trees to build the area map above (`ls` per package).
- **Noted for the record:** the Android worktree carries its own, divergent `docs/`
  tree (`docs/audits/`, `docs/contracts/`, `docs/Android_Parity_Review_2026-08-04.md`,
  `docs/iOS_Issues_Found_While_Porting.md`) that the `hig-review` tree does not have,
  and `hig-review`'s `docs/reports/` does not exist on the Android branch. It also
  contains a **stale copy of the iOS app**: 92 Swift files under `kudos-ao3-reader/`
  versus 214 in `hig-review`. Anyone comparing "iOS" from inside the Android worktree
  is comparing against a much older iOS. Recorded as Open lead L-1.
- No source file has been read yet; no suite has been run. Nothing below is claimed
  as verified until it carries file:line evidence on both platforms.

### 2026-08-07/08 — attempted parallel review of areas 2–15, abandoned

Two `Workflow` runs were dispatched, seven area reviewers each (areas 2–8, then 9–15),
every finding pipelined into an adversarial refutation stage. **Both runs failed
completely.** All 14 reviewers terminated on a session usage limit; the run journals
(`…/workflows/wf_63152fd2-03e/journal.jsonl` and `wf_26c5bb5e-db9/journal.jsonl`) contain
zero `{"type":"result"}` lines, so nothing was recoverable — 1.29 M sub-agent tokens spent
for no output. Recorded because it is a real cost already paid and the next session should
not repeat the shape. Everything in this report was produced afterwards by direct inline
reading.

### 2026-08-07/08 — cross-check of the Android branch's audit corpus

Spot-checked one cluster (`isQueuedForLater` / queue-only) that
`docs/audits/ANDROID_PARITY_FINDINGS_VERIFIED.md:23,59` lists as a highest-priority
CONFIRMED-and-open major, and that `PARITY_SWEEP2_A:6,24` therefore excludes from
re-review. Found it substantially implemented at `a5a46116` → **finding 3**. Opened
L-3 (an `isSaved` merge-rule divergence noticed while reading the work-merge bodies) and
L-4 (the unchecked half of the same cluster). No other audit document was verified.

### 2026-08-07/08 — area 14 (backup / folder sync), partial

- Compared manifest versioning: iOS `KudosBackup.swift:224-225` (`currentVersion = 8`,
  `supportedVersions = [1…8]`) against Android `backup/BackupVersion.kt:22-25`
  (`CURRENT = 8`, `supported = 1..8`). They agree, and Android's file documents the Apple
  version history deliberately. No finding.
- Compared the manifest field set: iOS `KudosBackupManifest` (`KudosBackup.swift:220-250`)
  against Android `KudosBackupManifest` (`backup/BackupManifest.kt:9-27`). Same ten
  collections. Android's `BackupJson` (`backup/BackupJson.kt`) sets `ignoreUnknownKeys`
  and `explicitNulls = false`, and `BackupValidator` carries queues/annotations/tombstones
  through unchanged "so re-export doesn't drop anything" — i.e. the unknown-field
  preservation question the review prompt raises is handled deliberately. No finding.
- Chased the date-encoding hazard to a conclusion → **ruled out**, recorded as R-1, with
  the one residual carved out as lead L-2.
- Read both folder-sync write paths end to end → **findings 1 and 2**.
- Cross-referenced against the Android branch's own docs, which changed two conclusions:
  `docs/iOS_Issues_Found_While_Porting.md:69-96` already documents finding 2 on both
  platforms (so this review claims no credit for it — see the note under that finding),
  and `docs/contracts/BACKUP_FORMAT.md:83` + `docs/android/ANDROID_PORT_PLAN.md:1005`
  turned finding 1 from "an oversight" into "a specified requirement, asserted as complete
  in a contract doc, while the same codebase implements the pattern correctly elsewhere at
  `files/WorkFileStore.kt:24-39`".
- Compared the `SyncMerge` decision core in full, both null branches and both comparison
  strictnesses → **V-1**, verified identical. This is the result I expected least: the
  subsystem with the worst failure mode has the most faithful port.
- Corrections applied to this file after re-checking my own citations: three line numbers
  (iOS EPUB naming `:680` not `:681`; Android `:169` not `:170`; Android orphan pruning
  `:176`/`:193` not `:181-186`/`:193-197`), and one over-claimed grep — iOS *does* read
  modification dates in `FolderSyncService.swift` (`:741-748`, called from `:273`, `:338`,
  `:380`), just never on the per-asset skip path. The corrected form is what appears under
  finding 2's evidence.
