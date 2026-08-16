# Security + backup-trust handoff (Claude review)

**Base commit:** `c241d2f` (`origin/hig-review`)  
**You are Claude. You run this to completion.** Review, fix, commit as you go, loop until every tree is reviewed, every FIX/BLOCK is closed, and all work lives on **one local release-candidate branch**.  
**Still forbidden:** `git push`, opening a PR, creating a **remote** branch, and any git in `/Users/cidy02/Documents/AO3_App_OpenSource`. Local branches, local merges, and local commits are required.

**There is no Phase 3** of tombstone trust. Product is Phase 1 (drop unsigned incoming) + Phase 2 (Ed25519 so *trusted* deletes can cross devices).

This file is the single brief. Start here. Do not treat `GROK-REVIEW-IOS.md` as current (several FIX items were closed later).

---

## Claude operating loop (mandatory)

You are the conductor. **Do not solo the volume.** Delegate and parallelize. Keep this file’s **Progress tracker** (below) updated and **commit the tracker** whenever status changes.

### Tools you must use

| Tool | How | Use for |
|---|---|---|
| **Your own subagents** | `spawn_subagent`: `general-purpose` (implement), `explore` (read-only map), `plan` (stack strategy). Launch independent units **near the start**, not after you have already done the work. | Parallel tree reviews, isolated fixes, RC conflict resolution in a worktree |
| **Grok plugin (`grok-cc`)** | Skill `grok-cli-runtime` / command `/grok-cc:rescue`. Companion: `node "…/grok-companion.mjs" task [--read] [--background] [--cwd <tree>] [--worktree] "<task>"`. Write by default; `--read` for review-only. | Implement or **review** (see model-split). `--cwd` to the owning worktree. |
| **Antigravity (`agy`)** | Skill `antigravity` / `/antigravity:delegate`. `agy-delegate --tier pro --yolo --digest --dir <tree-root> "…"`. Long jobs: `agy-job start --tier pro --yolo --dir <tree> --model <slug> "…"`. | Bulk review, test generation, first-pass diffs, Android gradle volume. `--dir` so it reads `AGENTS.md`. Never trust self-reported GREEN — re-run the gate. |

If Grok is missing, `/grok-cc:setup`. If `agy` is missing, `/antigravity:setup`. Do not silently skip a plugin.

### Model split — reviewer ≠ implementer

The review model **must be a different family** than who wrote the code. Same vendor reviewing itself is a fail.

| If the implementer was | Reviewer must be |
|---|---|
| Claude (you or a Claude subagent) | **Grok** (`grok-cc --read`) **or** Antigravity Gemini (`agy-delegate --tier pro --model gemini-3.1-pro-high`) |
| Grok | **You** and/or **Gemini** (`agy` pro). Not another Grok. |
| Gemini / `agy` | **You** and/or **Grok**. Not another Gemini. |
| Opus 4.6 via `agy --model claude-opus-4-6-thinking` | Treat as Claude family → review with **Grok or Gemini**, not Opus. |

Record implementer model + reviewer model in the Progress tracker for every unit.

### Loop (do not stop mid-cycle)

Repeat until the **Definition of done** at the bottom of this section is true:

1. **Update the Progress tracker** in this file (status, owner, implementer model, reviewer model, SHA). Commit: `handoff: progress — <what changed>`.
2. **Fan out reviews** in parallel: one unit per tree (or per colliding file group). Different models than the implementers (table above).
3. **Collect findings** into `/Users/cidy02/kudos-fix-tombstone/REVIEW-CLAUDE.md` (SHIP / FIX / BLOCK, `file:line`).
4. **Fix FIX/BLOCK** in the owning tree (or on the RC branch once stacked). Delegate implementation to a **different** worker than the reviewer. Commit locally after each coherent fix.
5. **Re-review** the fix with a model that is not the fixer.
6. **Stack onto the RC branch** when a unit is SHIP (see merge order). Resolve conflicts. Commit the merge. Run the iOS + Android gates on the RC. If red, go to 4.
7. **Loop.** Do not wait for the owner between cycles. Do not exit because a plugin quota-failed — switch worker and continue.

### Release-candidate branch

Create **locally** (no `git push`):

```
# from a clean throwaway clone or new worktree of hig-review
git checkout -B security-fixes/rc c241d2f
```

Suggested stack (cherry-pick or merge each tree’s branch, fix conflicts, commit, test, next):

1. `security-fixes/wp-c`
2. `security-fixes/wp-a` (includes M15)
3. `security-fixes/wp-b` (prefer A’s AppRouter/cookie code on conflict unless B’s test is stricter — keep the stricter test)
4. `security-fixes/wp-d-signing`
5. `security-fixes/tombstone-trust` (Phase 1+2 restore wins over A’s restore **except** keep M15 isolated-context discard-on-throw)
6. `security-fixes/wp-e-android`
7. `security-fixes/wp-f-android`

Work in `/Users/cidy02/kudos-fix-tombstone` **or** a dedicated `/Users/cidy02/kudos-fix-rc` worktree. Do not use `/Users/cidy02/Documents/AO3_App_OpenSource`.

On `KudosBackup.swift` conflicts: keep tombstone Phase 1/2 adopt/sign/identity-rematch **and** WP-A M15 isolated `ModelContext` / no intermediate `saveBestEffort`. If both cannot apply, BLOCK and say why — then implement the missing piece on RC.

### Progress tracker (you maintain this)

Keep the tables in **Progress for Claude** current. After every cycle append a short dated bullet under **Cycle log** (end of that section): what shipped, what is still FIX/BLOCK, RC SHA.

### Definition of done (do not stop before this)

- Every tree in §0 has a written review (SHIP or remaining FIX/BLOCK listed).
- G1–G8 are **fixed or signed off** in `REVIEW-CLAUDE.md`.
- No open BLOCK findings.
- All source work is on **one** local branch `security-fixes/rc`.
- RC iOS gate: `KudosTests/PersistenceGateSuites/KudosBackupTests` (and FolderSync if restore/sync touched) GREEN, `totalTestCount` ≠ 0.
- RC Android gate: `:app:testDebugUnitTest` GREEN, count ≠ 0.
- This `handoff.md` tracker says **RC READY**.
- Still **not** pushed.

---

## 0. Map of trees (all unmerged)

| Tree | Branch | What it is |
|---|---|---|
| `/Users/cidy02/kudos-fix-tombstone` | `security-fixes/tombstone-trust` (~20 ahead) | Backup tombstone trust Phase 1 + 2 (iOS + Android) |
| `/Users/cidy02/kudos-fix-wp-a` | `security-fixes/wp-a` | Original audit WP-A (M1*, M8/M10/M11/M14/M16/M19 remediations, M15/M20, M21 fonts, M13 file-exclude) |
| `/Users/cidy02/kudos-fix-wp-b` | `security-fixes/wp-b` | WP-B (M6–M12, second M19/M10/M14, M8 isolation tests) |
| `/Users/cidy02/kudos-fix-wp-c` | `security-fixes/wp-c` | WP-C (M4 lazy EPUB, M5 zip) |
| `/Users/cidy02/kudos-fix-wp-d-signing` | `security-fixes/wp-d-signing` | WP-D signing/entitlements + M13 file-exclude copy |
| `/Users/cidy02/kudos-fix-wp-e` | `security-fixes/wp-e-android` | M1g-Android + restore-deadline tests |
| `/Users/cidy02/kudos-fix-wp-f` | `security-fixes/wp-f-android` | M1a/M3 Android, M21/M2b fonts, revert-check evidence |

**Collision:** WP-A, WP-B, WP-C, and tombstone all edit `KudosBackup.swift` / Settings / AppRouter. You **will** reconcile these on `security-fixes/rc` (see operating loop). Until then, review each tree at its own HEAD.

**Companion docs**

- Tombstone discussion: `/Users/cidy02/kudos-fix-tombstone/backup-trust-design-discussion.md`
- Phase 2 wire: `/Users/cidy02/kudos-fix-tombstone/PHASE2-CONTRACT.md`
- iOS notes: `/Users/cidy02/kudos-fix-tombstone/IMPLEMENTATION-NOTES.md`
- Android notes: `android/PHASE1-NOTES.md`, `android/PHASE2-NOTES.md`
- WP-F mutations: `/Users/cidy02/kudos-fix-wp-f/android/WP-F-REVERT-CHECKS.md`
- Original audit: `/Users/cidy02/Documents/AO3_App_OpenSource/discussions/security-audit-cross-review.md` (read-only; do not git there)

---

## Progress for Claude (2026-08-15)

Owner: **You review, fix, and stack everything onto local `security-fixes/rc`.** Do not push. Do not stop mid-loop.

### Status key

`DONE` committed locally · `GAP` Claude should fix or sign off · `SKIP` out of scope · `STACK` only solvable at merge time

### Tombstone tree (`kudos-fix-tombstone`)

| ID | Status | What | Where |
|---|---|---|---|
| Phase 1 drop + 3 modes | **DONE** | Unsigned incoming tombstones dropped on Merge / Replace / reconcile. Folder sync = default reconcile. | `a1aa83f` `a0533c1` `ab04d64` |
| Replace extra step / snapshot-wins | **DONE** | iOS pause-sync is `setAutoSyncEnabled`. Replace ignores local suppressors; no appearance apply. | `7b77316` |
| RECONCILE vs add-only MERGE | **DONE** | File UI MERGE; folder sync RECONCILE; MERGE undeletes Recently Deleted. | `ab04d64` `bf81772` |
| R1 identity-aware Replace counts | **DONE** | iOS `BackupReplaceWorkDelta`; Android `WorkIdentitySnapshot` + preview. | `SettingsView.swift`; `BackupMergeService.preview` |
| R2+R10 Merge add-only notes | **DONE** | Existing annotation ids kept; **new ids inserted**. Collection/queue name LWW skipped on Merge. | `KudosBackup.swift`; `BackupMergeService.kt` |
| R3 folder-sync ingest test | **DONE** | `foldConflictContentsDoesNotAdoptIncomingUnsignedTombstones` | `FolderSyncTests.swift` |
| R5 Merge undelete test | **DONE** | `fileMergeUndeletesPendingDeletion` | `KudosBackupTests.swift` |
| R6 UI arming tests | **SKIP** | No SwiftUI/Compose harness. | — |
| R8 Replace snapshots links/searches | **DONE** | Hard-delete without tombstone (those models have no Recently Deleted UI). | both restore paths |
| R9 Android Replace → Recently Deleted | **DONE** | Soft-delete works, keep EPUB, no tombstone. | `BackupRepository` |
| Identity rematch on Android apply | **DONE** | `ee84fad` — same ao3/URL/UUID as iOS. GREEN **797** then **814** after P2. | `BackupMergeService.merge` |
| Phase 2 Ed25519 | **DONE** both | **No Phase 3.** Contract `PHASE2-CONTRACT.md`. iOS `e4c9278` **39/0/39**. Android `71f72fc` **814/0/0**. | `TombstoneSigning.swift` / `.kt` |

Tombstone `git log --oneline origin/hig-review..HEAD` should include through `60be1ea` plus later handoff commits. Untracked `OPUS-IMPLEMENT.md` / `OPUS-REVIEW-GROK.md` are agent prompts, not product.

### Original audit trees (`kudos-fix-wp-*`)

| WP | Status | Latest hole-close | Notes |
|---|---|---|---|
| **A** | **DONE in-tree** | `c701bdb` M13 file-vault `isExcludedFromBackup` | Also M1*, M8/M10/M11/M14/M16/M19 remediations, M15a/M20 `9070dd2` (T-196 marked done). Overlaps B on AppRouter/cookies. |
| **B** | **DONE in-tree** except one manual | `1097316` M8 store isolation + cookie leak tests **53/53** | **GAP:** hostile-EPUB JS on a **real device** (`window.location` + in-page cookie probe). Unit tests cannot execute script inside a live Readium spread. |
| **C** | **DONE in-tree** | `1ee0ade` | M4/M5. Tests were re-fixtured after an unsound first pass. |
| **D** | **DONE in-tree** for assigned halves | `1c5614d` signing; `0549539` M13 exclude | No Developer ID / notarization on this machine — **GAP:** distribution signing UTD, not a code hole. |
| **E** | **DONE in-tree** | `91195cc` | T1 now asserts ~`now+90d`. T2 merge overlay does not apply a past wipe date. |
| **F** | **DONE in-tree** | `daf3f25` | M1a/M3 mutations RED then GREEN **798/0/0**. Evidence `android/WP-F-REVERT-CHECKS.md`. M2b mapper rejects blank `recordTypeRaw`. |

### Gaps Claude should close or explicitly sign off

These are the remaining gaps. Fix in the owning tree **or on `security-fixes/rc`**. G4/G5 are STACK: resolve them when you merge, do not leave them for the owner.

| # | Gap | Own | Close how |
|---|---|---|---|
| G1 | **M8 device probe** | WP-B | Optional: run hostile EPUB on a physical device. If you cannot, **sign off** that unit isolation (non-persistent store ≠ default, cookies don’t leak, `javascript:`/`data:` cancelled) is enough to merge later. |
| G2 | **Android annotation deletes do not mint tombstones** | tombstone | There was no Android insert path. Either add sign-on-delete for annotations to match iOS, or sign off as known parity gap (deletes of highlights won’t cross devices). |
| G3 | **iOS iCloud KVS entitlement** | tombstone | Simulator: `Unable to find entitlement for KVS store`. Same-Apple-ID auto-trust of pubs needs the entitlement on a real device. Hex paste still works. Add entitlement **or** sign off as device-only follow-up. |
| G4 | **WP-A vs WP-B overlap** | STACK | Both changed `AppRouter` / session cookies / M8. On RC: keep the stricter production check **and** the stricter test. |
| G5 | **Tombstone vs WP-A `KudosBackup.swift`** | STACK | WP-A M15 isolated restore + tombstone Phase 1/2 adopt/sign. RC must have **both**. |
| G6 | **Bookmarks/saved searches Replace** | tombstone | Hard-delete, no RD UI. Confirm later Merge can re-insert (no tombstone). Sign off or add RD if you judge it a product hole. |
| G7 | **R6 Replace 1.5s UI tests** | SKIP | No harness. Do not invent one unless you already have a pattern. |
| G8 | **macOS Developer ID / notarization** | WP-D | Machine has no distribution identity. Cannot close in code. |

### What Claude should hunt (load-bearing)

**Tombstone Phase 1+2** (`git diff c241d2f...HEAD` in `kudos-fix-tombstone`):

1. Unsigned incoming never persist, never suppress (file Merge, Replace, folder-sync / default restore).
2. Trusted + valid signature **is** adopted and can suppress; untrusted valid and forged drop.
3. A `.kudosbackup` never writes the trust store.
4. Replace never mints `SyncTombstone` (signed or not) for omitted works.
5. Restore identity is ao3 → canonical URL → UUID on **both** apply and Replace counts.
6. Payload matches `PHASE2-CONTRACT.md` (hex pub 64, hex sig 128, UTC `yyyy-MM-dd'T'HH:mm:ss'Z'`).
7. Private key never in the backup / iCloud blob (pubs only).
8. Existing Phase 1 tests were not weakened.

**WP-A:** M11 reject-not-rewrite; M19 refuse non-http(s); M14 allow-list includes remember-me and validator doesn’t re-widen; M16 `SecItemUpdate` re-asserts accessibility; M8 isolated store; M15 discard-on-throw; M13 file `isExcludedFromBackup`.

**WP-B:** M6 host gate; M12 symlink test uses a *valid* EPUB target; M8 tests 11/11 isolation.

**WP-E:** hostile past `permanentDeletionScheduledAt` cannot schedule immediate wipe at **merge**, not only mapper.

**WP-F:** clamp and stricter-of still production-entry; `WP-F-REVERT-CHECKS.md` mutations quoted.

### How to run tests (if you re-run)

iOS (never `-sdk iphonesimulator` with a UDID):

```
UDID=C71780B1-35DE-4E5E-ABCD-2AB66BCB28B0
xcodebuild test -project AO3_App_OpenSource.xcodeproj -scheme AO3_App_OpenSource \
  -destination "id=$UDID" \
  -only-testing:KudosTests/PersistenceGateSuites/KudosBackupTests \
  CODE_SIGNING_ALLOWED=NO
```

`KudosTests/KudosBackupTests` matches **0** Swift Testing cases. Use the `PersistenceGateSuites` filter. `totalTestCount` 0 is a fail.

Android:

```
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
cd android && ./gradlew :app:testDebugUnitTest
```

### Review output

Maintain `/Users/cidy02/kudos-fix-tombstone/REVIEW-CLAUDE.md` across the loop (append, do not wipe):

- SHIP / FIX / BLOCK per finding (`file:line`, spec clause, patch).
- Implementer model and reviewer model per unit.
- One subsection per tree, plus an **RC** subsection once stacking starts.
- G1–G8: fixed or signed off.

### Cycle log

- 2026-08-15 — Grok wrote this brief. RC not created yet. Claude starts the loop here.

---

---

## A. Accomplishment report (2026-08-15)

### What the owner locked

A `.kudosbackup` is attacker-controlled. Adopting its `savedWork` tombstones permanently suppresses works the user never deleted and fans out through the Library Sync Folder.

Phase 1 (this session, no crypto):

- Drop **all** incoming unsigned tombstones on file Merge, file Replace, and folder-sync ingest.
- Owner accepted **short inconsistency**: deletes do not cross devices until Phase 2.
- **Three modes.** Do not collapse file Merge and folder sync.

| Mode | Who uses it | Meaning |
|---|---|---|
| **reconcile** | Folder sync / default `restore` / default `importPackage` | LWW on overlap. Add missing. Do not delete omitted local works. Drop incoming tombstones. Local tombstones still suppress. |
| **merge** | File-import **Merge** | Add-only. Undelete Recently Deleted if the file has that work. Do not overwrite active overlap (title/progress/tags/notes/EPUB). Drop incoming tombstones. |
| **replaceLibrary** | File-import **Replace Library** after extra step | This device’s works / progress / collections / queues / annotations / **saved links (bookmarks)** / **saved searches** become the snapshot. Fonts, appearance, AO3 login stay. Omissions go to **Recently Deleted** on **both** platforms (no `SyncTombstone`). Drop incoming tombstones. This device only. |

Replace extra step: counts, amber if much smaller, checkbox + 1.5s delay, pause-sync default, pre-replace safety `.kudosbackup`. Empty library: one Restore. No Replace-via-sync.

### Who did what

| Who | What happened |
|---|---|
| **Opus 4.6** | Started iOS `restore` + Settings Merge/Replace fork. Quota-failed mid-implementation (`ReplaceLibraryConfirmationView` / `makePreReplaceBackup` referenced but missing). Could not finish tests or review Grok. |
| **Grok 4.6 + subagents** | Finished iOS UI + `.reconcile` split + tests + mutations. Implemented all Android Phase 1. Reviewed Opus iOS. Fixed the review BLOCK/FIX items that were in scope. Wrote this report. |
| **Gemini 3.1 Pro** | Design discussion + an implementation review that forced the Android `RECONCILE` vs add-only `MERGE` split. |

### Commits (`origin/hig-review`..`HEAD`, local only)

| Commit | What |
|---|---|
| `a1aa83f` | Android: drop unsigned incoming tombstones; Replace UX; `exportedAt` clamp; canonical `sourceURL` |
| `a0533c1` | iOS: drop incoming tombstones; `BackupImportMode`; Merge vs Replace Library UI |
| `ab04d64` | Android: `RECONCILE` (folder-sync LWW) vs add-only file `MERGE` + tests. GREEN **787 / 0 / 0** |
| `bf81772` | Android: file Merge undeletes Recently Deleted |
| `14267e5` | iOS: merge/reconcile production-entry tests + Mutation A/B evidence |
| `7b77316` | iOS review fixes: pause-sync compile break, Replace snapshot-wins, ignore local suppressors, do not apply appearance |
| `759cf47` | Locked three-mode spec + iOS review writeup |
| `ab6f7c5` | Notes for the post-review iOS Replace fixes |

### iOS — shipped

**Production**

- `kudos-ao3-reader/Services/KudosBackup.swift`
  - `BackupImportMode`: `reconcile` \| `merge` \| `replaceLibrary`
  - `restore(..., mode: .reconcile)` default
  - Incoming unsigned tombstones are **not** inserted and are **not** used to build `TombstoneIndex` (local rows only)
  - `.merge`: skip `apply` / EPUB / tag union on **active** overlap; undelete `isPendingDeletion` then apply
  - `.replaceLibrary`: snapshot-wins on overlap (`isNewRecord = true`); ignore local work-tombstone suppressors; soft-delete omissions **without** `SyncTombstone`; do **not** `settings.apply`
- `kudos-ao3-reader/Settings/SettingsView.swift`
  - Empty library → one Restore (`.merge` into empty)
  - Non-empty → Merge vs Replace sheet
  - `ReplaceLibraryConfirmationView` + `makePreReplaceBackup()` (Documents)
  - Pause-sync calls `setAutoSyncEnabled` (the original `setAutoSync` API **does not exist** — that was a compile BLOCK, now fixed)
  - Replace does not `applyRestoredTheme`
- `FolderSyncService.swift` (unchanged callers): all four `restore` sites omit `mode` → default `.reconcile`

**Tests** (`KudosTests/KudosBackupTests.swift`, production `KudosBackupService.restore`):

- `incomingUnsignedTombstonesAreNotAdoptedOnMerge`
- `replaceDoesNotLeaveStandingTombstonesThatBlockLaterMerge`
- `fileMergeDoesNotOverwriteActiveOverlapTitleProgressOrUserTags`
- `defaultReconcileAppliesLastWriterWinsOnOverlap`
- `defaultReconcileDropsIncomingUnsignedTombstonesAndStillInsertsPresentWork`

**GREEN last** after `7b77316` (`/tmp/tomb-ios-rerun.xcresult`):

```
result: Passed
passedTests: 30
failedTests: 0
totalTestCount: 30
```

Filter that actually runs the suite (the short name matches **0** Swift Testing cases):

```
-only-testing:KudosTests/PersistenceGateSuites/KudosBackupTests
```

Never pass `-sdk iphonesimulator` together with a UDID destination. Simulator: `C71780B1-35DE-4E5E-ABCD-2AB66BCB28B0`.

**Mutation A** (temporarily re-adopt incoming tombstones) — RED, then reverted:

- `incomingUnsignedTombstonesAreNotAdoptedOnMerge` — `"Incoming unsigned tombstone was persisted"` — **0.223s**
- `replaceDoesNotLeaveStandingTombstonesThatBlockLaterMerge` — `SyncTombstone` fetch not empty — **0.023s**
- `defaultReconcileDropsIncomingUnsignedTombstonesAndStillInsertsPresentWork` — **0.127s**

**Mutation B** (drop on `.merge`, still adopt on default `.reconcile`) — RED, then reverted:

- Merge test stayed GREEN — **0.011s**
- Reconcile drop test RED — **0.210s**

### Android — shipped

**Production**

- `android/app/src/main/java/io/github/cidy02/kudos/backup/KudosBackup.kt` — `RECONCILE` \| `MERGE` \| `REPLACE_LIBRARY`
- `BackupMergeService.kt` — drop incoming tombstones; MERGE keep-overlap + undelete `isDeleted`; RECONCILE LWW; REPLACE snapshot without minting tombstones; REPLACE keeps `current.settings`
- `BackupRepository.kt` — `importPackage` / `importV2ZipBytes` default **RECONCILE**
- `BackupScreen.kt` — empty → Restore; else Merge vs Replace extra step; file UI passes `MERGE` / `REPLACE_LIBRARY` explicitly
- `BackupMappers.kt`, `WorkTags.kt` — `lastModifiedAt` clamp + canonical `sourceURL`

**Tests:** `BackupTrustPhase1Test`, `BackupCompatibilityTest` (incl. `BackupTombstoneTrustPhase1MergeTest` cases), `WorkIdentityIndexTest`. Production entries: `BackupMergeService.merge`, `BackupRepository.importPackage`, `SyncRepository.runSync`.

**GREEN last** (`:app:testDebugUnitTest` after `ab04d64`): **787 / 0 / 0**. Undelete follow-up (`bf81772`) focused `BackupTrustPhase1Test`: **10 / 0 / 0**.

**Mutation A** (re-upsert incoming tombstones) — RED, reverted:

- `mergeDoesNotAdoptOrSuppressWithIncomingTombstones` — `"incoming unsigned tombstones must not be adopted"` — **0.04s**
- `importPackageDoesNotAdoptIncomingTombstones` also RED

**Mutation B** (drop on merge, still adopt on folder-sync `importPackage`) — RED, reverted:

- `folderSyncIngestDoesNotAdoptIncomingTombstones` — `"folder-sync must not insert the remote unsigned tombstone"` — **3.212s**
- `importPackageDoesNotAdoptIncomingTombstones` — **0.035s**

Known gaps are enumerated with owners in **§C**. The Phase 1 review in §B should confirm them, not silently implement them, unless a finding is **BLOCK**.

---

## B. Review brief — current Phase 1 (do this first)

**Assignee:** Opus **5** if available, otherwise Opus **4.6**. Codex Sol 5.6 may run the same brief as an independent second review.

You are reviewing, not implementing. **Read-only unless you find a BLOCK** (does not compile, incoming unsigned tombstones are adopted, Replace plants `SyncTombstone`, or folder sync uses add-only Merge). Do not restyle. Do not start Phase 2. Do not start §C implement items during this pass. Do not push. Do not run git in `/Users/cidy02/Documents/AO3_App_OpenSource`.

### B.1 Read first, in this order

1. This file — locked spec is §1–§5 below; do not re-litigate owner decisions.
2. `git log --oneline origin/hig-review..HEAD` and `git diff origin/hig-review...HEAD` (this worktree only).
3. iOS: `kudos-ao3-reader/Services/KudosBackup.swift` (`BackupImportMode`, `restore`), `kudos-ao3-reader/Settings/SettingsView.swift` (`ReplaceLibraryConfirmationView`, `makePreReplaceBackup`, `restorePendingBackup`), `kudos-ao3-reader/Services/FolderSyncService.swift` (the four `restore` call sites).
4. iOS tests: `KudosTests/KudosBackupTests.swift` (the five named tests above).
5. Android: `android/app/src/main/java/io/github/cidy02/kudos/backup/{KudosBackup,BackupMergeService,BackupRepository,BackupScreen}.kt` and `android/app/src/test/java/io/github/cidy02/kudos/backup/{BackupTrustPhase1Test,BackupCompatibilityTest}.kt`.
6. `IMPLEMENTATION-NOTES.md`, `android/PHASE1-NOTES.md`. Treat `GROK-REVIEW-IOS.md` as historical — verify whether its FIX list is still true at `HEAD`.

### B.2 What “good” is

Judge against the **locked product in §2**, not taste, not Phase 2, not “first-empty-restore TOFU.”

Must be true:

1. Incoming unsigned tombstones are never written to the local tombstone store on Merge, Replace, or folder-sync ingest.
2. Incoming unsigned tombstones are never used to suppress a work that is present in the same snapshot.
3. Local pre-existing tombstones still suppress on Merge and reconcile (user deleted it *here*). Replace **ignores** local suppressors so the snapshot can load.
4. File Merge does not overwrite an **active** overlapping work’s title, progress, tags, or EPUB. Recently Deleted / `isDeleted` is undeleted then applied.
5. Folder sync / default import is **reconcile** (LWW), never add-only Merge.
6. Replace does not mint `SyncTombstone` (or Room tombstone rows) for omitted works. A later Merge of a pre-Replace work must still insert it.
7. Replace extra step exists (counts, amber, checkbox + delay, pause-sync default, safety backup). Empty library is Restore-only.
8. Existing assertions were not weakened.
9. Tests hit production entry points (`KudosBackupService.restore`, `BackupRepository.importPackage` / `BackupMergeService.merge`, and on Android `SyncRepository.runSync`).

### B.3 Hunt these specifically

| # | Question | Likely files |
|---|---|---|
| 1 | Any remaining `contents.manifest.tombstones` insert / Room upsert on restore? | `KudosBackup.swift` `restore`, `BackupMergeService.merge` |
| 2 | Does folder sync pass `.merge` / `MERGE` anywhere? | `FolderSyncService.swift`, Android `SyncRepository` |
| 3 | Does default `restore` / `importPackage` still LWW-update overlap? | call sites + tests that omit `mode` |
| 4 | Does file Merge still skip apply on active overlap **and** undelete pending-delete? | both platforms |
| 5 | Does Replace plant suppressors or leave `isPendingDeletion` in a way that blocks later Merge? | replace path + `replaceDoesNotLeaveStandingTombstonesThatBlockLaterMerge` |
| 6 | Does Replace still compile? Pause-sync must call `setAutoSyncEnabled`, not `setAutoSync`. | `SettingsView.swift` |
| 7 | Does Replace apply appearance / fonts-as-selection / login? Spec: they stay. | `settings.apply`, `applyRestoredTheme`, Android `current.settings` |
| 8 | Are confirmation counts identity-aware or UUID-only? | `ReplaceLibraryConfirmationView`, Android preview |
| 9 | Does Merge overwrite annotation **notes** on existing IDs? | `restoreAnnotations`, `mergeAnnotations` |
| 10 | Were existing restore/LWW/tag-union tests weakened to make Phase 1 green? | `git diff` on `KudosBackupTests.swift`, `BackupCompatibilityTest.kt` |
| 11 | iOS filter trap: `KudosTests/KudosBackupTests` runs 0 tests. Do not accept a 0-count xcresult. | harness |
| 12 | Identity order still `ao3WorkID` → canonical URL → `recordID`? | `WorkRestoreIndex` / `WorkIdentityIndex` / Android equivalent |

### B.4 How to report

Write `/Users/cidy02/kudos-fix-tombstone/REVIEW-OPUS5-OR-CODEX.md` (or append a “Round 4 review” section to `backup-trust-design-discussion.md` if you prefer one file). Sign the review with which model actually ran (Opus 5, Opus 4.6, or Codex Sol 5.6).

Use **SHIP / FIX / BLOCK** only:

- **BLOCK** — does not build; incoming unsigned tombstones adopted or used to suppress; Replace plants standing work tombstones; folder sync is add-only Merge; tests are 0-count or existing assertions were gutted.
- **FIX** — spec hole that should be patched before merge, but the tombstone-drop invariant holds.
- **SHIP** — matches the locked spec.

Each finding: `file:line`, which §2/§3 clause it violates, concrete patch (do not apply it unless BLOCK). List what is correct. Say whether you agree with §A “Known gaps.”

If you re-run tests (optional; evidence already exists):

**iOS**

```
UDID=C71780B1-35DE-4E5E-ABCD-2AB66BCB28B0
xcodebuild test \
  -project AO3_App_OpenSource.xcodeproj \
  -scheme AO3_App_OpenSource \
  -destination "id=$UDID" \
  -only-testing:KudosTests/PersistenceGateSuites/KudosBackupTests \
  CODE_SIGNING_ALLOWED=NO \
  -resultBundlePath /tmp/tomb-ios-review.xcresult \
  -parallel-testing-enabled NO \
  -derivedDataPath /tmp/kudos-tombstone-dd
```

Quote `result / passedTests / failedTests / totalTestCount`. `totalTestCount` 0 is a fail.

**Android**

```
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
cd android && ./gradlew :app:testDebugUnitTest
```

Do not invent Java. Do not weaken tests to get green.

### B.5 Out of scope for you (this review pass)

- Phase 2 Ed25519 / QR / iCloud pubs (see §C R-P2-*)
- Implementing §C items (review first; implement only after this pass, and only your platform)
- Push, PR, remote branch
- Rewriting working restore “for clarity”
- Reopening “trust tombstones on first empty restore”
- Running git in `/Users/cidy02/Documents/AO3_App_OpenSource`

---

## C. Remaining work — implement vs review

**Opus = Opus 5 if available, otherwise Opus 4.6.** Same person/role either way.

Do these in order. Do not start Phase 2 until the owner says so. Local commits only. No push.

### C.0 Next action (now)

| ID | Work | Implement | Review |
|---|---|---|---|
| **R0** | Independent review of Phase 1 as shipped + close-out. Follow §B and §Progress. | — (read-only) | **Claude** before merge. Optional: Opus 5/4.6 or Codex Sol 5.6. |

Grok already reviewed the iOS core (`GROK-REVIEW-IOS.md`; several items fixed in `7b77316`). Owner assigned Claude as the merge-gate review.

### C.1 Phase 1 close-out

**Live status is the table in §Progress.** Spec text below is what “done” means. Reviewer is **Claude** before merge (owner). Implementer for this close-out is **Grok** (Opus quota).

| ID | Work |
|---|---|
| **R1** | Identity-aware Replace confirmation counts (`ao3WorkID` → canonical `sourceURL` → `recordID`). |
| **R2** | File Merge add-only on collection name / queue name / membership note / existing annotation ids. Reconcile stays LWW. |
| **R3** | Production-entry folder-sync ingest test (`foldConflictContents` or `syncDown`). |
| **R4** | Fix stale Android `PHASE1-NOTES.md` Gaps (Merge **does** undelete). |
| **R5** | iOS production-entry Merge undelete test. |
| **R6** | Replace extra-step UI tests — **SKIP** this merge (no harness). |
| **R7** | GREEN last after close-out. Filter `KudosTests/PersistenceGateSuites/KudosBackupTests`. |
| **R8** | Replace snapshots saved links and saved searches (no tombstone). |
| **R9** | Android Replace soft-deletes omitted **works** (Recently Deleted), no DAO-hard-delete, no tombstone. |
| **R10** | File Merge inserts **new** annotation ids; does not overwrite existing ids. Folded into R2. |

### C.2 Product decisions — locked 2026-08-15

| ID | Owner said | Meaning |
|---|---|---|
| **R8** | **Replace** | Saved links and saved searches are part of the Replace snapshot, not merge-add leftovers. |
| **R9** | **Bring Android to parity with iOS** | Android Replace uses Recently Deleted, not a hard DAO delete. |
| **R10** | **Add new IDs** | File Merge inserts highlights/notes the file has that this phone does not; it never overwrites an existing highlight/note. |

These are no longer questions. Implement as C.1 rows. Do not re-ask.

### C.3 Phase 2 (specified in §2 — owner must say go)

| ID | Work | Implement | Review |
|---|---|---|---|
| **R-P2-1** | Ed25519 keypair on device. Private key never leaves the device. Sign each tombstone at delete time. Payload UTF-8 fields joined by `\n`: `recordType`, `ao3WorkID`, `canonicalSourceURL`, `recordID`, `deletedAt` (`2026-08-15T16:00:00Z`), `signerPublicKey`. | **Opus** iOS (`CryptoKit.Curve25519.Signing`). **Grok** Android (Tink or API 33 Ed25519). | Cross. Optional Codex Sol 5.6 pass on the crypto boundary. |
| **R-P2-2** | `canonicalSourceURL` must match `WorkTags.canonicalAO3WorkURL` on both platforms. Sign **sink identity**, not a bare workId. | Both (shared contract). | Cross |
| **R-P2-3** | iCloud publishes **public** keys only; same Apple ID auto-trusts those pubs. A file never adds a trusted key. | **Opus** | **Grok** |
| **R-P2-4** | Android: QR once to trust the other platform’s pub. | **Grok** (QR + trust store). **Opus** (iOS show-pub / scan if needed for parity). | Cross |
| **R-P2-5** | Merge applies an incoming tombstone only if the signer is already trusted. Incoming unsigned still drop. | **Opus** iOS, **Grok** Android | Cross |
| **R-P2-6** | First Phase 2 launch: one-time local re-sign of tombstones already in *this* store (`tombstoneMigrationComplete`). | **Opus** iOS, **Grok** Android | Cross |
| **R-P2-7** | 24h clock clamp stays a pre-filter, not authorization. Do not treat clamp as “signed.” | Both (already present as clamp — do not regress). | Cross |
| **R-P2-8** | Identity-aware `retractWorkTombstone` (ao3 / canonical URL / recordID), not UUID-only. | **Opus** iOS, **Grok** Android | Cross |
| **R-P2-9** | Same drop-or-verify rule for collection / queue / annotation tombstone *types* when they arrive. Do not invent a new product; apply the signed-tombstone rule. | Both | Cross |
| **R-P2-10** | Deletes cross devices again (the Phase 1 short inconsistency ends). Production-entry tests + Mutation A/B: unsigned incoming still drop; trusted signed incoming suppress; forged signature does not. | Both | Cross + optional Codex |

Do **not** mint signed tombstones from Replace for omitted works (owner + Grok/Opus rejected a signed fleet wipe).

### C.4 Explicitly not remaining work

- Push / PR / remote branch — **owner only**.
- GPG / OpenPGP — rejected.
- Wiping or rewriting the Library Sync Folder from Replace — rejected.
- Re-implementing working `restore` / `merge` “for clarity.”
- Trust-on-first-empty-restore / file TOFU — rejected.

### C.5 How a later implement pass should run

1. R0 review is done (or owner waives it).
2. Implementer reads §2 + the row in this table. Does **not** rewrite unrelated restore.
3. Tests at the production entry point. Do not weaken existing assertions.
4. Local commit. No push.
5. The other agent reviews that commit against §2. SHIP / FIX / BLOCK.
6. Only then start the next ID.

---

## 1. The vulnerability

A `.kudosbackup` is attacker-controlled (AirDrop, email, “curated backup”). Importing one that contains a `savedWork` tombstone for a work the user never deleted:

- Permanently suppresses that work from later backups (`suppressesResurrection` / `worksSuppressed`).
- Propagates through the Library Sync Folder to every peer.
- Never expires.

**Pre-Phase-1 code (true at `c241d2f`):**

- iOS `KudosBackup.swift` `restore` inserted every incoming manifest tombstone not already keyed `recordTypeRaw|recordID`, then used that expanded set to skip works.
- Android `BackupMergeService.kt` unconditionally upserted incoming tombstones, then suppressed.
- Match order: `ao3WorkID` → canonical `sourceURL` → `recordID`. A fresh/forged `lastModifiedAt` wins.

---

## 2. Locked product (owner + three-model discussion)

### Phase 1 (this session — no cryptography)

**Incoming unsigned tombstones are dropped** on file import Merge, file import Replace, and folder sync ingest (`reconcile`).

Owner chose **short inconsistency**: your own deletions will **not** cross devices until Phase 2. That is acceptable.

**Three restore modes — do not collapse Merge and folder sync.** See the table in §A.

**Why three modes:** “Merge” as the owner’s file-import verb is add-only. Folder sync must keep LWW so progress and metadata still cross devices. Using file Merge for folder sync would freeze overlap on every peer. Using folder LWW for file Merge would let a hostile file overwrite local notes/progress.

**Replace extra step (required):**

1. Show the delta: works in library, works in file, will add, will remove, in both.
2. If removals ≫ additions, amber: “This backup is much smaller than your library.”
3. Red **Replace Library** stays disabled until the user checks: **“Remove N works that are not in this backup.”**
4. Button enables after the check **and** ~1–2 seconds.
5. If Library Sync is on: “Sync will put removed works back. Pause sync for this device?” Default **Pause**. Do **not** offer to wipe the sync folder.
6. Before execute: write a timestamped `.kudosbackup` of the current library (Documents). Confirmation names that file.

**Empty library / first run:** skip Merge vs Replace. One **Restore from Backup** button (functionally Merge into empty).

**Folder sync** stays implicit **reconcile** forever. No Replace-via-sync.

**Replace snapshot includes** works, progress, collections, queues, in-book annotations, **saved links (browse bookmarks)**, and **saved searches**. Fonts, appearance, AO3 login, and (later) trusted keys stay.

**Replace omissions** go to **Recently Deleted** on iOS **and** Android. Soft-delete only. **No** `SyncTombstone` / Room tombstone. A later Merge of the user’s real backup must still be able to bring those works back (undelete).

**Replace does not persist the file’s unsigned tombstones.** Absence in the snapshot is enough for *this* load. Do **not** mint new standing tombstones for works Replace removed (that would be a signed fleet wipe in Phase 2).

**Replace is this device only.** Other phones are untouched.

**File Merge and in-book notes:** add-only by annotation id. Existing ids stay local. New ids in the file are inserted even if the work already exists. Folder-sync reconcile stays LWW on annotations.

### Phase 2 (specified, not this session)

- Ed25519, platform-native (`CryptoKit.Curve25519.Signing` / Tink or API 33 Ed25519). No GPG.
- Sign each tombstone at delete time. Payload, UTF-8 fields joined by `\n`: `recordType`, `ao3WorkID`, `canonicalSourceURL`, `recordID`, `deletedAt` (`2026-08-15T16:00:00Z`), `signerPublicKey`.
- `canonicalSourceURL` must match `WorkTags.canonicalAO3WorkURL` on both platforms.
- Private key never leaves the creating device. iCloud publishes **public** keys; same Apple ID auto-trusts those pubs. Android: QR once.
- A file never adds a trusted key. Merge applies a tombstone only if the signer is already trusted.
- First Phase 2 launch: one-time local re-sign of tombstones already in *this* store (`tombstoneMigrationComplete`). Incoming unsigned still drop.
- 24h clock clamp stays as a pre-filter, not authorization.

---

## 3. Implementation notes (Phase 1)

### iOS — `KudosBackup.restore`

1. **Do not insert incoming tombstones** into `SyncTombstone` (file restore and any folder-sync caller of `restore`).
2. **Do not** use incoming tombstones to populate `TombstoneIndex` for this batch. Local tombstones still apply on Merge/reconcile. **Replace ignores local work suppressors** so the snapshot can load. Still do not insert the file’s tombstones.
3. Modes:
   - **reconcile (default):** LWW `apply` on overlap. Incoming tombstones dropped. Folder sync omits `mode`.
   - **merge:** active identity hit → skip `apply`. `isPendingDeletion` → undelete then apply. Insert + apply new works. Still create collections/queues so added works are not orphaned. Do not remove local works. Annotations: skip LWW on an existing id; **insert new ids** (R10).
   - **replaceLibrary:** snapshot-wins on overlap (treat as `isNewRecord` / incomingWins). Soft-delete omitted works / collections / queues / annotations / **bookmarks** / **saved searches** into Recently Deleted **without** `SyncTombstone`. Do not apply incoming appearance settings.
4. Settings UI: empty → Restore. Non-empty → Merge vs Replace extra step. Pause-sync must call `setAutoSyncEnabled`.

### Android — `BackupMergeService` / `BackupRepository.importPackage`

Same three modes (`RECONCILE` / `MERGE` / `REPLACE_LIBRARY`).

- Default of `merge()` / `importPackage` / `importV2ZipBytes` is **RECONCILE**.
- File-import UI (`BackupScreen`) passes **MERGE** or **REPLACE_LIBRARY** explicitly.
- MERGE overlap: keep `existing` unless `isDeleted`, then undelete + apply. Do not overwrite EPUB or union tags on an **active** existing work. Annotations: keep existing ids; **insert new ids** (R10).
- RECONCILE: LWW + tag union.
- REPLACE_LIBRARY: snapshot this device including bookmarks and saved searches (R8). Soft-delete omitted works into Recently Deleted (`isDeleted` + recovery window) **without** minting tombstones (R9 — parity with iOS; no DAO-hard-delete of active works). Keep `current.settings`.
- Ledger: clamp `lastModifiedAt` with `min(value, exportedAt)` and reject `> now+24h`. Canonicalize `sourceURL` like `WorkTags.canonicalAO3WorkURL`.

### Invariants to test

**File Merge**

> After `restore(A, mode: .merge)` on a library that already contains work J, a `savedWork` tombstone in A must **not** be in the local tombstone store, and a later `restore(B, mode: .merge)` that contains work K must still insert K. Active overlap is not overwritten. A new annotation id in A on work J is inserted; an existing annotation id on J is left local.

**Replace**

> After `restore(A, mode: .replaceLibrary)`, local works absent from A are in Recently Deleted (not hard-gone, not tombstoned), A’s works are present, A’s bookmarks and saved searches are the snapshot, and **no new** work tombstones exist for A’s unsigned tombstones. A later `restore(B, mode: .merge)` of a pre-Replace work **must insert / undelete that work**.

**Folder sync / reconcile**

> Default restore / `importPackage` / folder-sync ingest of a remote manifest that contains a new `savedWork` tombstone for identity I must not insert that tombstone and must not skip a work I present in the same snapshot. Overlap still LWW-updates.

### What legitimate input is now rejected (Phase 1)

- Incoming deletion claims from a file or sync folder. **Your deletes on phone A will not appear on phone B** until Phase 2.
- Replace of an unsigned file cannot plant suppressors that block a later Merge of the user’s real backup.
- File Merge of an unsigned file cannot overwrite local active overlap (including an existing highlight/note id). New highlight/note ids from the file are still added.

---

## 4. Explicitly out of scope (this session)

- Ed25519, QR, iCloud pub publishing (Phase 2).
- Collection/queue/annotation tombstone *types* as a separate product (same drop rule if they arrive — do not adopt *any* incoming tombstone in Phase 1).
- Identity-aware `retractWorkTombstone`.
- Clearing or rewriting the sync folder from Replace.
- GPG / OpenPGP.

---

## 5. Definition of done

Per platform:

1. Production-entry-point test (real `restore` / `importPackage` / folder-sync ingest — not a helper).
2. Mutation A: unconditional tombstone adopt → RED, quoted assertion, duration > 0.
3. Mutation B: weaker substitute (drop on file Merge but still adopt on folder sync / reconcile) → RED.
4. GREEN last; counts from the result bundle / Gradle. `totalTestCount` 0 is a fail.
5. iOS: **never** `-sdk iphonesimulator` with a UDID destination.
6. Do not weaken existing assertions.
7. Local commits only. No push.

iOS and Android Phase 1 meet this definition at the current branch tip for the tombstone-drop + three-mode core. Remaining work and owners are §C. The next task is R0 (§B).
