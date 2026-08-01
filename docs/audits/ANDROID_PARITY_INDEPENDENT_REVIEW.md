# Android parity — independent review (context-preservation log)

**Started:** 2026-08-01 00:06 local, by Claude Sonnet 5, working solo overnight on the
owner's laptop (plugged in, sleep disabled, bypass-permissions mode on). Two session
wake-timers set (05:11 and 10:16 local) in case a usage-limit gap interrupts this.

**Ask (owner, verbatim intent):** find the branches Grok used to bring Android to parity
with iOS, review the changes, confirm no silent bugs/regressions, confirm behavioral 1:1
parity across all app sections, use subagents freely, document findings in two forms —
this context log, and a final report with a technical + plain-English section per finding
— then fix what's found to the best of my ability.

This file is the working log: what was checked, in what order, and why, so a session
interrupted mid-review can pick up without re-deriving everything. The user-facing
deliverable is a separate file: `ANDROID_PARITY_REPORT.md` (written once the review
workflow returns).

---

## 1. Locating the work

`git branch -a` / `git worktree list` on the repo root found **21 `android/*` branches**,
each already checked out as its own worktree under `.claude/worktrees/android-*`, organized
in three waves plus four UI-parity passes:

- `android/wave1-w1-{account,detail,home,library,nav,settings}` (6)
- `android/wave2-w2-{bulk,collections,dlqueue,dualtitle,purge,stats}` (6)
- `android/wave3-w3-{ao3-collections,authors,fonts,series-dl}` (4)
- `android/ui-parity-ui-{account,browse-settings,library,workdetail}` (4)
- `android/sync-from-hig-review` — the integration branch all 20 of the above are merged
  into, in order (confirmed via `git log --oneline android/sync-from-hig-review`, which
  shows 20 merge commits, one per branch above, plus 4 more "Android ui: ..." commits for
  the UI-parity passes and a handful of docs commits)

**Decision:** review `android/sync-from-hig-review` as the single integration point
(current tip `5ad08eb8`) rather than the 20 branches individually — it already contains
everything, and that's what a fix would land on anyway.

One repo-hygiene issue found in passing, not touched: `git fetch --all` partially failed
on a corrupted ref name (`android/sync-from-hig-review 2`, literal trailing space+2, both
local and on `origin`). Flagged for the owner in the final report; not deleted without
confirmation since it's tangential to this task and ref deletion is a git operation I
shouldn't take unprompted.

Also found: `main` (and every android branch) contains the Android project in-repo, at
`android/` — this is a monorepo, not a separate repo. Kotlin/Jetpack Compose, package
`io.github.cidy02.kudos`, Gradle 9.4.1, Kotlin 2.3.21 (K2), Room for persistence.

Set up `.claude/worktrees/hig-review-reference` as a plain read-only checkout of
`hig-review` @ `29cd9158` (current iOS tip at the moment this review started) so review
agents have a stable iOS comparison point regardless of what happens on my own working
branch (`claude/native-api-audit-fixes`) meanwhile.

## 2. Grok's own audit trail (read before designing my own review)

Found three existing docs already in `android-sync-hig-review`'s `docs/audits/`:
`IOS_ANDROID_DOMAIN_AUDIT.md`, `REMAINING_PARITY_AND_UI_GAPS.md`,
`ANDROID_HIG_REVIEW_SYNC.md`. Read the first two in full before finalizing review scope,
specifically to avoid re-reporting things Grok already knows and has documented as
deferred (that would waste the owner's time re-reading the same gap twice).

**`REMAINING_PARITY_AND_UI_GAPS.md` (2026-07-31, the more recent/authoritative one) —
explicitly deferred, NOT to be reported as new findings:**
1. Non-EPUB (PDF/HTML/txt) import — Android is EPUB-only
2. Folder / iCloud-style sync — "Android path TBD"
3. Full author profile pages / Inbox hub — Grok's doc says these are "not present as
   first-class Features on this iOS tip", which needs a sanity check: iOS's
   `AuthorProfileView.swift` and Inbox (`AccountInboxViews.swift`) do exist and have grown
   substantially this session. Told the `author` review agent to reconcile this claim
   against the *current* iOS feature set rather than trust the doc at face value — Grok's
   snapshot may predate a lot of this session's iOS work, or "first-class" may mean
   something narrower (e.g. not a top-level tab) than it first reads.
4. Reader device polish (progress pill timing) — 🟡 partial, "needs human device compare"
5. Biometric reveal for mature works — listed as missing; told the `library`/`uicomponents`
   reviewers to confirm whether mature-content *gating* exists at all without the
   biometric reveal step, since that's a privacy-relevant distinction worth being precise
   about even though the biometric piece itself is a known, accepted gap.
6. "Remote compact-card download-into-reader open path" — this is iOS's T-178/T-179
   (Account-tab cards downloading-and-opening on tap), which I built *hours ago this same
   session*. Correctly out of scope; told review agents not to flag it.

Also explicitly marked **not a parity blocker, ever**: Liquid Glass / peel dismiss / zoom
transitions (all iOS-only chrome, some of it — the zoom transition — built literally
tonight). This matches the boundary I'd already put in every review agent's prompt
independently, which is a good cross-check that the scoping is right.

**`IOS_ANDROID_DOMAIN_AUDIT.md` (older pass, useful for what it flagged as still-open
P0s that the newer doc doesn't explicitly confirm as resolved) — worth the `network-write`
and `backup` reviewers specifically re-checking against *current* code rather than trusting
either doc:**
- `AO3RedirectCookieRelay` + session restore validation — flagged P0, networking
- Backup `progressModifiedAt`/`lastModifiedAt` Room fields + last-write-wins merge +
  tombstone table — flagged P0. The newer doc claims backup "v1–v8 merge: Done", but does
  not explicitly say tombstone/LWW conflict handling was later completed — these could be
  two different senses of "done" (decodes the format vs. correctly resolves a two-device
  conflict). **This is the single highest-stakes ambiguity found before the review even
  started** — a backup restore that silently picks the wrong side of a conflict is a
  real data-loss bug, not a cosmetic gap, and I don't have a doc that confidently says
  which state it's actually in. Told the `backup` reviewer explicitly to nail this down
  from the current code, not from either doc.
- Reader TOC + chrome + settings sheet — flagged P0, matches "reader device polish"
  in the newer doc's deferred list, so likely the same known gap under two names.
- "Reading queues / annotations apply (decode only)" — same shape of concern as the
  backup LWW item: if backup import can *read* old queue/annotation data but doesn't
  *apply* it, a restore silently drops that data with no error. Told the `backup`
  reviewer to check this specifically and, if still true, report it at appropriate
  severity (this is a real, if known, data-loss-shaped gap — worth a precise severity
  call rather than either silence or alarm).

## 3. Build/test health, independent of the code review

Two independent checks, since "sound" includes "does it actually build and pass its own
tests," which a pure code-reading review can't fully answer.

- JDK: no system Java; used the JBR bundled with Android Studio
  (`/Applications/Android Studio.app/Contents/jbr/Contents/Home`, OpenJDK 21.0.10).
- Confirmed no other process is actively mutating the `android-sync-hig-review` worktree
  before trusting it as a stable read target for 20+ parallel review agents: the two
  long-lived Gradle/Kotlin daemon processes found via `ps` are both `PPID 1` (detached,
  normal daemon behavior, not evidence of a live foreground session), nothing in the
  worktree had a modification time in the last 20 minutes, and `git status`/`git log -1`
  were stable across repeated checks.
- Ran `android/Scripts/verify.sh` (Grok's own DoD gate: invariants → unit tests →
  assembleDebug → a persistence-focused test subset → whitespace) in the background —
  result pending as this log entry is written; see the final report for the outcome.

## 4. Review workflow

Launched as a background `Workflow` (run id `wf_624fcdc5-ea2`) rather than done solo,
per the owner's explicit go-ahead to use subagents. 22 area-scoped review agents, each
given: the exact Android files to read, a starting (not authoritative) hint at the iOS
counterpart, an explicit list of what does *not* count as a finding (platform-appropriate
Compose/Material differences, and the very-recent iOS-only reader chrome already listed
above), and a required structured output (technical + plain-English summary per finding,
severity, confidence).

Every candidate finding then goes through adversarial verification: three independent
agents, each arguing a different way a finding could be wrong (does it actually reproduce
when re-read from scratch; is it actually just a legitimate platform difference; is the
claimed user-facing impact real) — a finding needs 2 of 3 to survive. This exists because
a single reviewer's plausible-sounding finding is exactly the failure mode worth guarding
against on a task this size, run unsupervised overnight.

The 22 areas (each pipelined: verification of area N's findings starts as soon as area N's
review returns, without waiting for area N+1):

nav, home, library, workdetail, downloadqueue (incl. non-EPUB-import check and
series-download-via-queue), account, settings (incl. custom fonts), browse, search,
statistics, collections, readingqueues, purge, author, reader (incl. an explicit,
concrete check against iOS's `ReaderPageSkeleton` bugs fixed earlier tonight — theme-color
flash, spinner-after-skeleton, fill-height clipping — to see if Android's own
`ReaderPageSkeleton.kt` has an analogous version of any of them), auth, comments, backup
(flagged data-integrity-critical in its own prompt), network-read, network-write (flagged
silent-write-failure-critical), data/persistence, uicomponents+theme.

## 5. Third Grok doc: `ANDROID_HIG_REVIEW_SYNC.md` (read after the workflow was already
launched — used to filter/annotate results, not to change the already-running scope)

This one is dated the same day and turns out to document a pass that ports **exactly**
the iOS commits from earlier tonight this session: `f1f2844` (compact-card tap rule),
`436d65f` (one-stat-per-row cover-card stats), `5f2c3a8` (reader open skeleton),
`3d5765d` (Account-tab cards open the work), pinned against iOS tip `29cd915`. Confirms
the two codebases really are being kept in near-lockstep, and gives precise, checkable
claims for the `home`/`library`/`reader`/`uicomponents` reviewers' findings to be
weighed against:

- Claims Android's `ReaderPageSkeleton.kt` was built to avoid the *same three* bugs my
  `5f2c3a8` fixed (theme-background flash, spinner racing the first real page,
  not filling the available height). This is a claim, not a given — it's exactly what
  the `reader` area's adversarial "reproduces" lens exists to check independently rather
  than take on faith. A finding here would be genuinely new even though the *feature*
  isn't: the tricky part of my original bugs (the fill-arithmetic off-by-one, the
  double-safe-area padding) is exactly the kind of subtlety a description like "fills
  height" can miss while still being true in the broad strokes.
- Explicitly, self-documented as **not yet done** (own P0, section 7): remote/AO3 cards
  still open to Work Detail on tap, not download-then-read — the full `f1f2844` rule
  only landed for already-local cards. **Do not report this as a new finding** — it's
  Grok's own next task, already written up with a suggested TASKS.md entry.
- Explicitly deferred, P1: loading skeletons for Search/Browse/Account lists (only the
  reader got one this pass). If the `search`/`browse`/`account` reviewers notice this,
  annotate it as already-known rather than presenting it as newly discovered.
- Home shelf limit raised 4→12 "to match iOS carousel prefix scale" — matches what I
  recall of iOS's own `.prefix(12)` calls in `HomeView.swift`; a cheap corroboration for
  the `home` reviewer to confirm rather than take on faith.
- Card sizing deliberately NOT cloned 1:1 (164×228 SwiftUI tile abandoned for
  176.dp × min-220.dp content-sized MD3 cards) — a **conscious, documented, correct**
  platform difference. Not a finding no matter which reviewer notices the size differs.

**Known-gaps registry to filter the final findings against** (compiled from all three
Grok docs, before reading the workflow's results):
non-EPUB import · folder/iCloud sync · full author profile / Inbox · reader TOC/chrome
polish / TTS / annotations product · biometric mature-content reveal ·
remote-card-download-then-read · redirect-cookie relay (status unconfirmed — told
`network-write` to check current code) · backup tombstone/LWW conflict merge (status
unconfirmed — told `backup` to check current code) · reading-queue/annotation *apply* on
backup restore (status unconfirmed — same) · Search/Browse/Account list skeletons ·
advanced search filter UI · zoom/peel/Liquid Glass (never porting, by design).

A finding that only restates one of the above, without adding a new severity-relevant
fact (e.g. "and it silently drops data" where the doc only said "deferred"), gets folded
into the report's *Known, already-tracked gaps* section rather than presented as a fresh
discovery.

## 6. `verify.sh` first run: a false alarm, self-inflicted — worth recording so it isn't
mistaken for a real finding later

First `Scripts/verify.sh` run failed at step 2 (`compileDebugKotlin`) with
`IllegalStateException: Storage for [...source-to-classes.tab] is already registered`,
`BUILD FAILED in 6m 7s`. **Not a code defect.** This is Kotlin's incremental-compilation
cache getting corrupted by my own earlier `./gradlew compileDebugKotlin` invocation,
which I had force-killed after it ran past a 590s background-command cap while cold-
compiling (a first Compose/K2 build of ~194 files is genuinely slow, and I hadn't yet
found `Scripts/verify.sh` or realized the kill would leave a stale lock on disk).

Also worth a note for future me: the task-notification for this run reported
"completed (exit code 0)", which is **not trustworthy** here — my background wrapper was
two sequential statements (`sh Scripts/verify.sh > log; echo exit=$? >> log`), and the
harness's own reported exit code reflects the *last* statement (`echo`, which always
succeeds), not the actual script. The real result was in the log itself
(`android verify exit=1`). Read the log, don't trust the notification summary's exit code
for a multi-statement background command.

**Fix applied:** `./gradlew --stop` (stopped the one stale daemon) + deleted
`app/build/kotlin/compileDebugKotlin` (a build-output cache directory, not source) +
re-ran `Scripts/verify.sh` from clean. Re-run in progress; result in the next entry.

## 7. `verify.sh` re-run: clean, ALL GREEN

Confirmed by reading the log directly, not the background-command notification (see the
exit-code trap note above — this wrapper is also two statements, same trap). Full
`android/Scripts/verify.sh` — invariants, unit tests, `assembleDebug`, persistence subset,
whitespace — passed clean.

## 8. Adversarial verification never ran — twice

The 22-area review workflow (`wf_624fcdc5-ea2`) finished both its review fan-out passes
(51 candidates, then a fuller 90-candidate re-run), but its adversarial verification stage
— 3 independent "try to refute this" agents per candidate finding, 2-of-3 needed to
survive — got 0/141 successful lens calls across both runs. Every one errored out on
session-limit exhaustion. I'd already caught and fixed a bug in my own workflow script
where this failure mode was silently indistinguishable from "3 real REJECTED votes" (see
below) — with that fixed, both runs correctly came back as 0 confirmed / all unverified,
rather than the misleading "0 confirmed, all REJECTED" the bug would have produced. I did
not attempt a third full re-run — same session-limit ceiling would almost certainly hit
again — and pivoted to manual, personal verification instead, prioritized by severity.

**5 of the 22 areas returned zero candidate findings in either run**, not because they're
clean but because their review agent calls themselves never completed:
`backup`, `network-read`, `network-write`, `data`/persistence, `uicomponents`+theme. This
is a real gap, not a null result — two of the five (`backup`, `network-write`) were the
areas flagged pre-review as highest-stakes (data-integrity, silent-write-failure). Ran 3
more targeted `Agent` calls (not another full `Workflow`, to stay under the ceiling that
broke the first two attempts) to cover these 5 areas directly: one on backup/sync data
integrity, one on the write-action network layer, one combined on read-path resilience +
Room persistence + theme. Results pending; will be folded into the report.

## 9. A citation that looked fabricated, and was actually my own tooling error — worth
recording precisely because of how it happened

Manually re-checking each of the 8 deduped `critical`-severity raw findings against real
code before writing them into the report. Two are the same underlying bug (`home`/`nav`
areas both caught the same Home-carousel reveal gap) — already fixed this session, see the
commit. Confirmed the other 5 fixed-this-session criticals are real.

The 8th — "collections have no 90-day soft-delete/undo unlike iOS" — I initially logged as
**fabricated**: I checked its citations (`PreservedWorkService.softDelete(collection, in:
context)` at `Collections.swift:254`, `isPendingDeletion` at `PreservedWorkService.swift:
44-46`) against `android-sync-hig-review`'s own bundled `kudos-ao3-reader/` tree and found
neither the symbols nor a matching line. **That tree is stale** — `android-sync-hig-review`
branched from iOS before this backup/soft-delete work landed and never merged it forward,
since Android branches don't track every iOS commit. The correct comparison point, per §1
of this log, is the separate `hig-review-reference` worktree pinned at iOS tip `29cd9158`
— set up for exactly this reason. Rechecked there: `PreservedWorkService.swift` and its
`softDelete(_ collection: WorkCollection, in: context)` overload (setting
`isPendingDeletion`/`deletedAt`/`permanentDeletionScheduledAt`, same shape as the
already-ported `SavedWork` soft-delete) are real and exactly where cited.
`Collections.swift`'s delete confirmation dialog genuinely calls it and genuinely says
"The collection moves to Recently Deleted for 90 days." **The finding was correct; my
first verification pass used the wrong tree.** Same mistake almost repeated on the
`readingqueues` area's citations of `ReadingQueueService.swift` before catching it the
same way.

Net effect: this is a real, critical, verified parity gap. Implementing it properly now
(soft-delete for `CollectionEntity`, mirroring the existing `SavedWork` pattern already in
`WorkRepository`/`WorkMetadataMerger`) rather than leaving the copy-only mitigation I
applied before catching my own error — see the commit for the real fix. The copy fixes
(`RecentlyDeletedScreen.kt`, `CollectionDetailScreen.kt`) stay, now describing accurate
behavior instead of compensating for a missing feature.

**Lesson for the final report, still valid despite this one resolving as "my error, not
the finding's":** every one of the ~75 remaining deduped raw findings is a single,
unverified LLM pass, generated by an agent that in at least one case (`readingqueues`,
`collections`) was reading iOS ground truth I didn't have loaded correctly myself on first
check. The specific failure mode to flag in the report isn't "findings are fabricated" —
it's "trust the citations enough to re-check them against the right tree, not enough to
skip re-checking." I'm re-verifying `hig-review-reference` (not the bundled copy) for
every finding I write into the report at more than raw-listing detail.

## 10. The 3 targeted-area agents returned: one clean bill of health, two more real bugs

All 3 finished. `network-write`: no critical/major issues — Android's write-action network
layer (kudos/comments/subscribe/bookmark) correctly inspects HTTP status, login-redirects,
and AO3's overload page before declaring success on every action checked; its redirect-
cookie-relay handling is actually more defensive than iOS's (iOS has none). `backup`: real
major findings — `mergeCollections` had no last-write-wins gating (unconditionally
overwrote local renames) and neither collection deletion nor reading-queue-membership
removal recorded a sync tombstone, so a stale backup restore could silently resurrect
either. `network-read`/`data`/`uicomponents`+theme (combined 3rd agent): confirmed the
Settings theme picker is genuinely disconnected from the app's actual rendered theme
(critical — a real, working control exists, but it's a separate undocumented palette icon
that doesn't persist), plus one major defensive gap (`KudosTypeConverters.jsonToStringList`
throws uncaught on malformed JSON instead of degrading).

Given items #6 (collections had no soft-delete at all, re-verified as REAL after my own
false "fabricated" call in §9), backup's collection-LWW/tombstone gaps, and the theme
picker all landed in the same working session, fixed all of them together:

- `PrivacyGate` wiring for Home/Library/Collections/ReadingStatistics (4 bugs, §earlier
  session before this summary segment).
- Soft-delete revival fixed on 4 call sites (WorkImporter/DownloadQueue/WorkMetadataMerger/
  WorkDetailScreen) — same, earlier in session.
- **New this segment:** full collection soft-delete lifecycle — `CollectionEntity`/
  `WorkCollection` gained `lastModifiedAt`/`isDeleted`/`deletedAt`/
  `permanentDeletionScheduledAt` (Room migration v2→v3, `MIGRATION_2_3`), `WorkRepository`
  gained `softDeleteCollection`/`restoreCollectionFromRecentlyDeleted`/
  `hardDeleteCollection`/`sweepExpiredCollectionSoftDeletes` mirroring the existing
  `SavedWork` pattern exactly, `RecentlyDeletedScreen`/`ViewModel` now show and act on
  deleted collections (combined Flow, not just works), `CollectionDetailScreen`'s delete
  dialog and `RecentlyDeletedScreen`'s empty-state copy now describe the real (now-true)
  90-day-recoverable behavior. `BackupMergeService.mergeCollections` rewritten to gate by
  `SyncMerge.shouldApplyIncoming` + a new `TombstoneIndex.collectionResolution`, matching
  `mergeQueues`'s existing shape; `WORK_COLLECTION` tombstones are now actually recorded
  (the constant existed, unused, before this). `ReadingQueueRepository.removeWork` now
  records a `READING_QUEUE_MEMBERSHIP` tombstone. `KudosApp.kt` now derives its theme from
  `SettingsRepository` instead of unpersisted local state, and the palette-icon quick-toggle
  writes back to the same source instead of diverging from it. `KudosTypeConverters`
  degrades to `emptyList()` on malformed JSON instead of throwing.
- Stale "apply deferred" comments in `BackupManifest.kt`/`BackupValidator.kt` corrected —
  queues/annotations have been actually applied for a while; the comments just never caught
  up, which is exactly the kind of misleading trail that nearly cost extra review time on
  this task too.
- New tests: `WorkLifecycleRepositoryTest` (+2 collection lifecycle tests), 4 new
  `BackupCollectionMergeTest` cases (LWW both directions, tombstone suppress + revive-when-
  newer), `KudosTypeConvertersTest` (new file, 3 tests).

Self-caught mistake worth recording: my first attempt at these new tests declared a second
`class BackupCollectionMergeTest { ... }` — one already existed in the same file (a
name-collision test, unrelated to LWW). Same class of error as the `WorkMetadataMergerTest`
duplicate earlier this session; same fix, folded the new cases into the existing class.
Kotlin's compiler caught it immediately (`Redeclaration`) rather than silently shadowing.

Full `compileDebugKotlin`/`compileDebugUnitTestKotlin` passes clean. Full `verify.sh`
in flight as this entry is written; result and final commit go in the next entry.

## 11. `verify.sh` full unit-test run caught a real bug my own code review missed

Running `testDebugUnitTest` for real (not just `compileDebugUnitTestKotlin`) surfaced 4
genuine failures — not flaky, not environmental: `RoomDaoTest.databaseCreatesAtSchemaVersionTwo`
(expected, needed updating for the v3 schema bump — fixed, renamed to
`databaseCreatesAtCurrentSchemaVersion`), and three tests all failing the same way —
`expected:<[Weekend]> but was:<[]>` — a collection's work membership vanishing.

Root cause: `CollectionDao.upsert` was still `@Insert(onConflict = REPLACE)`. Room
implements `REPLACE` as an actual `DELETE` of the conflicting row followed by an `INSERT`
of the new one — not an in-place `UPDATE`. `CollectionWorkCrossRef` has
`ForeignKey(parentColumns=["id"], childColumns=["collectionId"], onDelete=CASCADE)` against
`CollectionEntity`, so every `DELETE` of a collection row cascade-deleted its cross-refs
too. My new `touchCollection()` (called after every `addToCollection`/`removeFromCollection`)
and `softDeleteCollection`/`restoreCollectionFromRecentlyDeleted` all call
`collectionDao.upsert(...)`, so every one of those operations was silently emptying the
collection it touched. This is the *exact* bug `WorkDao.upsert` already has a comment
documenting and was already fixed for, for the identical reason — I didn't check whether
`CollectionDao` had the same latent issue before adding code that would trigger it far more
often than the original, rarer `deleteCollection` ever did.

Fixed: `CollectionDao.upsert` → `@Upsert` (in-place `UPDATE` on conflict, no cascade).
Added a dedicated regression test
(`softDeletingAndRestoringACollectionPreservesItsWorkMemberships`) verifying membership
survives a full soft-delete → restore cycle. Re-ran the full suite: **all tests pass.**

This is worth being honest about in the final report: this bug would **not** have been
caught by a plausible-sounding code review pass — the Kotlin type-checks, the annotation
compiles, and `@Insert(REPLACE)` "looks" idempotent unless you specifically know Room's
`REPLACE` semantics and think to check whether the entity has any cascading foreign keys
pointed at it. It was only caught because the actual test suite ran against a real in-memory
database and asserted on real query results — a concrete argument for why `verify.sh`'s full
test run (not just a compile check) stayed in the loop every time, even under time pressure.

## 12. Second full `verify.sh` run: a build-tooling false alarm, not a code defect (same
pattern as before, so resolved immediately rather than re-diagnosed from scratch)

Re-running the complete `verify.sh` gate (not just tests) hit `dexBuilderDebug FAILED` —
`Type ... LibraryContent$lambda$2$0$0$$inlined$items$default$4 is defined multiple times`,
comparing a `... 2.class` file against its non-suffixed twin. This is the exact
"` 2`"-suffixed duplicate-file pattern already diagnosed earlier in this session (found
then in `app/build/kotlin`, git refs, and a stray worktree ref) and attributed to a
pre-existing environmental quirk of this specific worktree, not anything caused by this
session's edits. Confirmed 335 such duplicate files under `app/build` this time too. Fixed
identically: `rm -rf app/build`, fresh `verify.sh` run — passed clean, `android verify: ALL
GREEN`, invariants + full test suite + `assembleDebug` + persistence subset + whitespace.

## 13. Adversarial review of the new collection-lifecycle code, this time actually
completing (small, bounded scope — 3 lenses, not 22 areas)

With ultracode explicitly on for this session going forward, and given this session's new
code (collection soft-delete, LWW-gated backup merge, tombstone recording) is exactly the
kind of data-integrity-critical, only-self-reviewed code the original review's adversarial
pass existed to catch, ran one more small, tightly-scoped `Workflow` — 3 independent review
lenses (Room/Kotlin framework correctness, iOS parity, edge-case interactions) over just the
~15 touched files, each candidate finding then adversarially verified by 3 independent
refutation votes. Kept deliberately small (unlike the original 22-area fan-out that hit
session limits twice) specifically so it could complete. Result folded into the final report
once back.

## 14. Status at last update

`ANDROID_PARITY_REPORT.md` written in full — methodology, all 10 fixed findings (7
critical, 3 major) each with technical + plain-English sections, the "reviewed and
confirmed clean" areas, the 68 deduplicated unverified findings organized by area (38
major given full treatment, 12 minor + 18 note in compact tables), the known-gaps registry
cross-referenced against Grok's own docs, and closing recommendations. Raw findings (both
workflow runs' JSON + the deduplicated appendix) copied into `docs/audits/raw-findings/`.
First batch of fixes (6 root-cause bugs) already committed as `e8661a04`. This segment's
additional fixes (collection soft-delete/LWW/tombstone, theme picker, TypeConverters
hardening, stale-comment cleanup) pending final `verify.sh` confirmation before their own
commit.
