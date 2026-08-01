# Claude Android parity review — where it left off

**Author of this status doc:** Grok (read-only handoff investigation)  
**Date:** 2026-08-01  
**Scope:** Review only — no code was changed for this document.  
**Subject:** Claude’s independent review + fix pass over Grok’s Android parity work on `android/sync-from-hig-review`.

---

## TL;DR (plain English)

Claude spent an overnight session reviewing the whole Android integration branch (everything from the three feature waves + four UI-parity passes), found real bugs (especially privacy and delete/undo), fixed a first batch and **committed** it, then fixed a second batch (collections undo, backup safety, theme picker, crash hardening) and left that work **sitting uncommitted** on disk — with reports written saying “all 10 fixed,” while git still only has the first batch committed.

| Layer | State |
|---|---|
| **Branch** | `android/sync-from-hig-review` |
| **Worktree** | `.claude/worktrees/android-sync-hig-review` |
| **Committed tip** | `e8661a04` — privacy + soft-delete *work* revival |
| **vs origin** | **ahead 1** (that commit is **not pushed**) |
| **Working tree** | **Dirty** — ~23 modified + untracked schema/tests/reports/APK |
| **Claude’s claim in final report** | “10 bugs all fixed; verify.sh green” |
| **Git reality** | **~half landed in git** (items 1–5 family); **items 6–10 exist as uncommitted WIP** |
| **Adversarial verification of full review** | **0 / 141** lens calls (never completed) |
| **Still open after Claude** | 68 unverified leads + known deferred gaps + at least one residual data-integrity gap Claude itself re-reported |

If you pick this up next, the first mechanical step is almost certainly: **decide whether to commit/push the WIP batch** (or re-run `android/Scripts/verify.sh` and then commit), then treat the rest as a prioritized backlog — not as “parity done.”

---

## 1. Where the work lives

### Branch and worktree

| Item | Value |
|---|---|
| Integration branch | `android/sync-from-hig-review` |
| Checkout path | `/Users/cidy02/Documents/AO3_App_OpenSource/.claude/worktrees/android-sync-hig-review` |
| HEAD (committed) | `e8661a04e516ebfff37625d0f43061ecc3e47553` |
| Author trailer | `Co-Authored-By: Claude Sonnet 5` |
| Parent before Claude’s fix | `5ad08eb8` (UI-parity merges complete; review started here) |
| Remote | `origin/android/sync-from-hig-review` — local is **ahead by 1**, dirty on top |

**Not on `main`.** Main checkout is unrelated iOS inbox work. All Claude Android review state is in this worktree only.

### Claude’s own artifacts (untracked or only partially committed)

| Path | Role | Git state |
|---|---|---|
| `docs/audits/ANDROID_PARITY_INDEPENDENT_REVIEW.md` | Process / timeline log (started overnight ~00:06) | Modified (grew through session; partial content also in `e8661a04`) |
| `docs/audits/ANDROID_PARITY_REPORT.md` | User-facing findings report (tech + plain English) | **Untracked** |
| `docs/audits/raw-findings/run1-raw-findings.json` | Workflow run 1 (~51 candidates, adversarial empty) | **Untracked** |
| `docs/audits/raw-findings/run2-raw-findings.json` | Workflow run 2 (~90 candidates, adversarial empty) | **Untracked** |
| `docs/audits/raw-findings/deduplicated-findings-appendix.md` | Area status appendix | **Untracked** |
| `kudos-android-sync-debug.apk` | Local debug APK artifact | **Untracked** (should not be committed) |

Pre-existing Grok audit docs in the same folder (`REMAINING_PARITY_AND_UI_GAPS.md`, `ANDROID_HIG_REVIEW_SYNC.md`, `IOS_ANDROID_DOMAIN_AUDIT.md`) were **inputs** Claude read so it would not re-report deferred gaps as new bugs.

---

## 2. What Claude was asked to do

From Claude’s process log (`ANDROID_PARITY_INDEPENDENT_REVIEW.md` opening):

> find the branches Grok used to bring Android to parity with iOS, review the changes, confirm no silent bugs/regressions, confirm behavioral 1:1 parity across all app sections, use subagents freely, document findings … then fix what's found to the best of my ability.

**Method Claude used:**

1. Treat **`android/sync-from-hig-review`** as the single integration point (21 `android/*` topic branches already merged), not re-review each wave branch.
2. Pin iOS comparison to worktree `hig-review-reference` @ `29cd9158` (important — the Android branch’s bundled `kudos-ao3-reader/` tree is **stale** for soft-delete/collection features).
3. Run a **22-area** automated review workflow (`wf_624fcdc5-ea2`).
4. Intended **adversarial** second pass: 3 independent “try to prove this wrong” lenses per finding, 2-of-3 to survive.
5. Fix verified criticals; write `ANDROID_PARITY_REPORT.md`.

---

## 3. Timeline — where Claude left off

Reconstructed from the process log + git timestamps:

| Step | What happened |
|---|---|
| ~00:06 | Overnight review starts on tip `5ad08eb8` |
| Early | Read Grok deferred-gap docs; launch 22-area workflow |
| Mid | `verify.sh` false alarm (Kotlin incremental cache after killed compile) → clean green after `./gradlew --stop` + cache wipe |
| Mid | Adversarial stage **fails twice** — **0/141** lens calls; 5 high-stakes areas return nothing (`backup`, `network-read`, `network-write`, `data`, `uicomponents`/theme) |
| Mid | Manual re-verify of criticals; almost dismisses collection soft-delete as “fabricated” because wrong iOS tree — recheck on `hig-review-reference` confirms it is real |
| **10:20** | **Commit `e8661a04`**: PrivacyGate + work soft-delete revival (+ tests + partial process log) |
| Later same session | Implements collection soft-delete (Room v3), backup LWW/tombstones, queue membership tombstone, theme wiring, TypeConverters hardening |
| | Full unit tests catch **self-inflicted** `CollectionDao` `@Insert(REPLACE)` cascade bug → fix to `@Upsert` |
| | `dexBuilder` “` 2.class` duplicate” env false alarm → `rm -rf app/build` → claims verify green |
| | Small bounded adversarial pass over new collection-lifecycle files (log says it completed; results not itemized as a separate findings list in the report) |
| **§14 last log line** | Report written; **second fix batch still “pending … commit”** |

**Claude stopped after writing the report and leaving the second fix batch uncommitted.** There is no later commit. There is no push of `e8661a04`. There is no TASKS.md claim row for this Android work (Android line is outside the usual iOS T-xx process).

---

## 4. What is DONE (landed in git)

### Commit `e8661a04` — “Android: fix privacy-reveal parity gaps and soft-delete revival bugs”

**17 files, +693 / −62.** Co-authored Claude Sonnet 5. Full message claims `android/Scripts/verify.sh` passed for this batch.

#### A. PrivacyGate (report items #1–#4)

**Technical**

- New `android/.../app/PrivacyGate.kt`: session-only `StateFlow<PrivacyRevealState>` with `reveal(workId)`, `toggleRevealAll()` (turning reveal-all off also clears per-work reveals).
- Wired via `KudosAppContainer.privacyGate` into `AppNavHost` → Home, Library, CollectionDetail, ReadingStatistics.
- Home: obscured mature cards reveal in place instead of navigating straight into details.
- Library: reveal-all no longer writes the persisted DataStore “hide mature content” key.
- Collection detail + Reading Insights: actually apply privacy filtering / redaction.

**Plain English**

Turning on “hide mature content” now means something on the screens that were broken: Home blur is not just cosmetic, Library’s eye icon is temporary (not a permanent settings flip), Collections no longer dump raw mature titles, and Reading Insights no longer lists mature fandom/title stats when privacy is on.

**Caveat still open (known/deferred):** biometric confirmation before reveal (Face ID style) was **not** ported; `PrivacyGate` comments say so explicitly.

#### B. Soft-delete revival for **works** (report item #5)

**Technical**

Four paths that can re-match a soft-deleted row now clear `isDeleted` / `deletedAt` / `permanentDeletionScheduledAt` when reviving:

- `WorkMetadataMerger`
- `WorkImporter`
- `DownloadQueue` (uses `workRepository.restoreFromRecentlyDeleted`, which also **retracts** the sync tombstone)
- `WorkDetailScreen` save/toggle path

**Plain English**

If you deleted a fic into Recently Deleted and later re-download or re-save it, Android no longer leaves it secretly marked deleted so it can vanish again at the 90-day purge.

**Important residual (Claude re-reported it under Unverified, and code still matches):**  
`WorkMetadataMerger` / importer-side revival **clear soft-delete fields but do not retract the sync tombstone** and do not always bump `lastModifiedAt`. DownloadQueue’s path *does* retract via `restoreFromRecentlyDeleted`. Claude’s own report item under “Recently Deleted / purge” still flags that a later backup merge can treat the leftover tombstone as authoritative and **drop the revived work on another device**. That is **not fixed** in either the commit or the WIP tree (merger file is not in the dirty set).

#### C. Tests committed with `e8661a04`

- `PrivacyGateTest.kt` (new)
- `WorkLifecycleTest.kt` additions for merger revival semantics

#### D. Process log started in-commit

Partial `ANDROID_PARITY_INDEPENDENT_REVIEW.md` shipped with the commit; later segments of that file remain only in the working tree.

---

## 5. What is IMPLEMENTED but NOT committed (WIP on disk)

~**816 insertions / 75 deletions** across 23 tracked paths, plus untracked schema + tests + reports.

Claude’s report presents these as “fixed.” Git does **not**. Process log §14 is the accurate handoff:

> First batch of fixes (6 root-cause bugs) already committed as `e8661a04`. This segment's additional fixes (collection soft-delete/LWW/tombstone, theme picker, TypeConverters hardening, stale-comment cleanup) **pending final `verify.sh` confirmation before their own commit**.

### Mapping to report items #6–#10

| # | Topic | Files (representative) | Completeness on disk |
|---|---|---|---|
| **6** | Collection 90-day soft-delete | `CollectionEntity`, `CollectionDao`, `WorkRepository`, `RecentlyDeletedScreen`, `CollectionDetailScreen`, `KudosApplication`, Room **v3** + `3.json` | **Looks finished end-to-end** (entity fields, migration, soft/restore/hard/sweep, UI, launch sweep) |
| **7** | Backup collection LWW + tombstones | `BackupMergeService`, `BackupMappers`/`Manifest`/`Validator`, `TombstoneIndex.collectionResolution` | **Looks finished** + unit tests in `BackupCompatibilityTest` |
| **8** | Reading-queue removeWork tombstone | `ReadingQueueRepository.removeWork` | **Looks finished** (records `READING_QUEUE_MEMBERSHIP` tombstone) |
| **9** | Theme picker actually drives theme | `KudosApp.kt` reads `SettingsRepository.settings.app.appTheme`; palette cycles via `updateAppTheme` | **Looks finished** for Light/Sepia/Dark/System; OLED chip still aliases to Dark (pre-existing model limit, documented in Settings) |
| **10** | TypeConverters crash hardening | `KudosTypeConverters.jsonToStringList` try/catch → empty list; `KudosTypeConvertersTest.kt` | **Looks finished** |

### #6 technical detail (collection soft-delete)

- Room DB **version 2 → 3**; `MIGRATION_2_3` adds `lastModifiedAt`, `isDeleted`, `deletedAt`, `permanentDeletionScheduledAt` on `collections`, backfills `lastModifiedAt = dateAdded`.
- `KudosAppContainer` registers `MIGRATION_2_3` alongside `MIGRATION_1_2`.
- Schema export present: `android/app/schemas/.../KudosDatabase/3.json` (**untracked** — must be included if this is committed).
- `WorkRepository`: `softDeleteCollection`, `restoreCollectionFromRecentlyDeleted`, `hardDeleteCollection`, `sweepExpiredCollectionSoftDeletes`, `observeRecentlyDeletedCollections`, `recordCollectionTombstone` (`WORK_COLLECTION`).
- `CollectionDao.upsert` changed from `@Insert(onConflict = REPLACE)` → **`@Upsert`** after tests proved REPLACE CASCADE-wiped memberships (same class of bug WorkDao already documented).
- Active queries filter `isDeleted = 0`; dedicated deleted/expired queries for Recently Deleted + sweep.
- `CollectionDetailScreen` delete dialog now soft-deletes and promises 90-day recovery (copy now true).
- `RecentlyDeletedScreen` combines works + collections; Restore / Delete Forever for both.
- `KudosApplication` launch sweep also runs `sweepExpiredCollectionSoftDeletes()`.

**Plain English:** Deleting a collection on Android finally matches iPhone’s “90 days in Recently Deleted” model instead of “gone forever,” and the empty-state text that already claimed that is no longer a lie for collections.

**Still not done for parity with full iOS preservation:** **reading queues** still have no soft-delete/delete UI lifecycle on Android (Claude noted this; only membership removal got a tombstone).

### #7 technical detail (backup collections)

- `mergeCollections` now takes `TombstoneIndex`, skips stale incoming via `SyncMerge.shouldApplyIncoming`, applies soft-delete fields from archive, and uses `collectionResolution` for new-to-device rows.
- `TombstoneIndex` indexes `WORK_COLLECTION` tombstones (constant existed earlier but was unused).

**Plain English:** Restoring a backup should no longer casually rename your collection back or resurrect a collection you deleted, if timestamps/tombstones are present.

### Self-caught regression during WIP (important process note)

While implementing #6, Claude introduced a membership-wipe bug via Room `REPLACE` semantics. **Unit tests caught it; code review would likely have missed it.** That is documented honestly in the process log §11. Regression test: `softDeletingAndRestoringACollectionPreservesItsWorkMemberships`.

### Tests in the WIP (uncommitted)

- `BackupCompatibilityTest.kt` — LWW both directions, tombstone suppress, revive-when-newer (~+98 lines)
- `WorkLifecycleTest.kt` — collection soft-delete / restore / hard-delete / membership survival
- `RoomDaoTest.kt` — schema version assertion updated for v3
- `KudosTypeConvertersTest.kt` — **new untracked file**

### Stale-comment cleanup (backup)

`BackupManifest` / `BackupValidator` comments that claimed queues/annotations were “decode only / apply deferred” were corrected in WIP — those features already applied; comments were misleading.

---

## 6. What the final report claims vs what git shows

| Claim in `ANDROID_PARITY_REPORT.md` | Reality on disk / git |
|---|---|
| “10 real bugs … **all now fixed**” | **Code for all 10 is present in the worktree**, but **only privacy + work-revival (`e8661a04`) is committed** |
| “All fixes are compiled and covered by new unit tests; `verify.sh` passes clean” | Process log says second batch needed a final verify before commit; this investigation **did not re-run** `verify.sh`. Treat green as Claude’s last self-report, not re-confirmed here |
| 68 unverified findings | Matches structure: **38 major** headings + **12 minor** + **18 note** table rows in the report body |
| Adversarial 0/141 | Matches raw JSON: run1 `confirmed:0` / 51 candidates; run2 `confirmed:0` / 90 candidates; adversarial votes never populated |
| Network write/read “confirmed clean” | Single-pass targeted agents after the 5 areas failed to return in the big workflow — **not** adversarially re-verified |

**Bottom line:** Trust the process log’s commit split more than the report’s “all fixed” summary when deciding what is safely on the branch history.

---

## 7. What is LEFT TO DO

Grouped by urgency for a next agent/human.

### A. Immediate hygiene (before any more feature work)

1. **Commit or discard the WIP batch** for items #6–#10 + docs + schema `3.json` + tests.  
   - Include untracked: `3.json`, `KudosTypeConvertersTest.kt`, `ANDROID_PARITY_REPORT.md`, `raw-findings/**`.  
   - **Do not** commit `kudos-android-sync-debug.apk`.
2. **Re-run `android/Scripts/verify.sh`** on a clean `app/build` if anything about the last green run is doubted (this worktree has a history of duplicate-class / Kotlin-cache false failures).
3. **Push** `e8661a04` and the WIP commit if accepted (`origin` is still at pre-Claude tip).
4. Optional: clean corrupted git ref name `android/sync-from-hig-review 2` (literal trailing space) — Claude flagged, did not touch.

### B. Residual data-integrity gap inside “already fixed” #5

- **Importer/merger revival without tombstone retract + lastModifiedAt bump** (report section “Recently Deleted / purge”, major on `WorkMetadataMerger`).  
  - **Technical:** revived works can still lose to an old tombstone on backup merge.  
  - **Plain English:** re-adding a deleted fic can look fine on this phone and then disappear after restore on another.  
  - DownloadQueue path is the good example; other paths need the same retract/timestamp discipline.

### C. Unverified findings backlog (68 leads)

These are **not** confirmed bugs. Claude’s recommendation: verify in **batches of 5–8 areas**, not another 22-way fan-out.

**Priority callout from Claude’s recommendations:**

1. **`AppNavHost` shared selection state / back stack shows the wrong work** after nested detail navigation (major, high user confusion).

**Other high-signal majors still open as leads** (sample; full text is in `ANDROID_PARITY_REPORT.md`):

| Area | Lead (short) |
|---|---|
| Account | Inbox is a stub; Dashboard is a link dump; Privacy & Local Data navigates to generic Settings |
| Auth | Login WebView host suffix check missing leading `.`; session restore IOException can crash launch; login can stall if username scrape fails |
| Author | No real profile (bio / subscribe / series / bookmarks tabs) — also in known deferred list |
| Browse | Fandoms alpha not popularity-sorted; no filter/sort on fandom works; full DOM parse of huge fandom indexes (iOS already fixed jetsam risk) |
| Comments | No work header context; thinner feature set vs iOS |
| Search | No local-first library search; Clear filters leaves stale results; tags are local-only suggestions |
| Settings / Reader | Custom font import selects but Readium never applies font |
| Work Detail | No AO3 metadata refresh on open; update-check failure path doesn’t stamp last-check (retry storm) |
| Library / stats | Several polish/behavior diffs; stats `hasStarted` may omit `readiumLocator` |
| Queues | No rename/delete/soft-delete of queues themselves |

Also: **one major in the unverified list duplicates fixed #9 (theme)** — ignore as already addressed in WIP.

### D. Known deferred gaps (explicitly not “new Claude findings”)

From Claude’s report + Grok’s `REMAINING_PARITY_AND_UI_GAPS.md` — still product backlog, not regressions of Claude’s pass:

- Non-EPUB import (Android EPUB-only)
- Folder / cloud sync path for Android
- Full author profile + real Inbox hub
- Reader TOC/chrome/TTS / deep font polish
- Biometric mature reveal (gating fixed; biometrics not)
- Remote card “download then open reader” (local cards done; remote still Work Detail)
- Search/Browse/Account loading skeletons
- iOS-only chrome (Liquid Glass / peel / zoom) — never a parity target

### E. Methodology debt

- Full adversarial verification of the 68 leads: **never done**.
- Late five areas (backup, network-*, data, theme): single pass only.
- Small post-fix adversarial on collection lifecycle: log claims completion; **no separate surviving-findings list** in the report beyond the Fixed section — treat as “Claude believed the new code was OK,” not as independent human sign-off.
- Citations in unverified section may point at stale line numbers or the wrong iOS tree; re-check against `hig-review-reference` @ `29cd9158` (or current iOS tip if newer).

---

## 8. What Grok’s earlier work Claude was reviewing

For context only (not re-audited here in full):

- **Waves 1–3** feature ports (account, library, detail, download queue, collections, stats, purge, series download, fonts, authors, AO3 collections, …)
- **UI parity passes** (Account hub, Work Detail tabs, Library chips/menus, Browse/Settings)
- Integration merges into `android/sync-from-hig-review`, tip at review start `5ad08eb8`
- Claude’s overall take in the report: **Grok’s work is solid overall**; write-path networking is faithful (and in redirect-cookie handling **more defensive than iOS**); main new bugs were privacy + delete/undo/data integrity, not a total rewrite need

---

## 9. Recommended next steps (ordered)

1. **Snapshot / commit WIP** on `android/sync-from-hig-review` (or explicitly stash) so collection soft-delete + backup LWW work cannot be lost — this is the largest unfinished handoff risk.
2. **`android/Scripts/verify.sh`** on a clean build directory; fix anything that fails.
3. **Push** branch to origin (currently ahead 1 + dirty).
4. **Fix residual revival/tombstone gap** on non-DownloadQueue paths (`WorkMetadataMerger` / importer) so #5 is complete under backup.
5. **Verify then fix** the AppNavHost wrong-work-on-back major if you want the next user-visible reliability win.
6. Triage the remaining ~37 open major leads in small batches; fold true bugs into tasks; demote false positives.
7. Keep known deferred list out of “must fix now” unless product prioritizes Inbox / author profile / cloud sync.

---

## 10. File index for the next agent

```
.claude/worktrees/android-sync-hig-review/
  HEAD e8661a04  (committed privacy + work revival)
  dirty tree     (collection soft-delete + backup + theme + converters + tests + docs)

  docs/audits/ANDROID_PARITY_INDEPENDENT_REVIEW.md   # process log — §14 is handoff
  docs/audits/ANDROID_PARITY_REPORT.md               # full findings (untracked)
  docs/audits/raw-findings/                          # raw workflow JSON (untracked)
  docs/audits/CLAUDE_PARITY_REVIEW_STATUS.md         # THIS file

  android/app/schemas/.../3.json                     # Room v3 schema (untracked)
  android/app/src/main/.../PrivacyGate.kt            # committed
  android/app/src/main/.../WorkRepository.kt         # dirty — collection lifecycle
  android/app/src/main/.../BackupMergeService.kt     # dirty — LWW collections
  android/app/src/main/.../KudosApp.kt               # dirty — theme from DataStore
```

---

## 11. Confidence notes for this status document

| Assertion | Confidence | Basis |
|---|---|---|
| Branch / HEAD / dirty inventory | **High** | `git status`, `git log`, `git show`, `git diff --stat` on the worktree |
| What `e8661a04` contains | **High** | Full commit message + file list + PrivacyGate source read |
| WIP implements #6–#10 | **High** | Diff samples of entity/migration/repo/UI/backup/theme/converters + tests present |
| “verify.sh green for WIP” | **Medium** | Claude’s log only; not re-run in this investigation |
| Completeness of small adversarial pass on new collection code | **Low–medium** | Log claims done; report does not itemize surviving findings |
| 68 / 38 / 12 / 18 counts | **High** | Report structure + regex counts on headings/table rows |
| Residual tombstone gap on merger revival | **High** | Report text + current `WorkMetadataMerger.kt` still only clears soft-delete flags |

---

*End of status. No application code was modified to produce this document.*
