# REVIEW-CLAUDE.md — merge-gate review log

Conductor: **Claude Opus 5**. Append-only across the loop; do not wipe.
Base: `c241d2f`. RC branch: `security-fixes/rc` at `/Users/cidy02/kudos-fix-rc`.

---

## Cycle 1 — 2026-08-15

### Operational finding (blocks naive stacking) — RESOLVED

**The seven trees live in two different repositories and do not share git objects.**

| Tree | Backing repo |
|---|---|
| `kudos-fix-tombstone` | `/Users/cidy02/Documents/AO3_App_OpenSource/.git` (the forbidden main checkout) |
| `kudos-fix-wp-{a,b,c,d-signing,e,f}` | `/Users/cidy02/kudos-security-audit-1-claude/.git` |

`git -C kudos-fix-wp-a cat-file -t 3a6775d` → `fatal: Not a valid object name`, i.e. the audit repo could not see the tombstone branch at all. A single RC branch was therefore impossible by merging alone.

**Resolution (no git run in the forbidden directory):** bundled the tombstone branch *from inside its own worktree*, which §Release-candidate of the brief explicitly permits working in, then fetched that bundle into the audit repo:

```
git -C /Users/cidy02/kudos-fix-tombstone bundle create /tmp/tombstone-trust.bundle c241d2f..security-fixes/tombstone-trust
git -C /Users/cidy02/kudos-fix-wp-a fetch /tmp/tombstone-trust.bundle 'refs/heads/security-fixes/tombstone-trust:refs/heads/security-fixes/tombstone-trust'
```

All seven branches now resolve in the audit repo. RC worktree created at `/Users/cidy02/kudos-fix-rc` (`git worktree add -b security-fixes/rc … c241d2f`), provisioned with the gitignored `Vendor/MuPDF.xcframework` symlink and `android/local.properties`.

---

### RC stacking — progress

| # | Branch | Result |
|---|---|---|
| 1 | `security-fixes/wp-c` | merged clean, **but see WPC-1** |
| 2 | `security-fixes/wp-a` | merged clean, no conflicts with WP-C |
| 3 | `security-fixes/wp-b` | **10-file conflict (G4)** — aborted pending the WP-B review; analysis below |
| 4–7 | wp-d-signing, tombstone, wp-e, wp-f | not yet attempted |

RC currently at `e9f2110` (WP-C + WP-A merged, working tree clean).

---

### WPC-1 — committed development detritus, incl. a stale copy of a security-critical file

- **Severity:** FIX
- **Tree:** WP-C (found by the conductor during stacking, not by the WP-C reviewer)
- **Files:** `kudos-ao3-reader/Services/KudosBackup.swift.orig`, `fix_test.patch`, `revert_fix1.patch`, `revert_fix2.patch` — all newly created by the WP-C merge into RC.
- **Why it matters:** `.orig` is a merge-conflict leftover. Shipping a stale duplicate of `KudosBackup.swift` (the file that owns tombstone adoption and restore) into the repo is a real hazard: it is not compiled, so it silently rots, and a future reader or an automated tool can mistake it for live code. The `.patch` files are revert scripts from mutation testing.
- **Patch:** `git rm` all four on the RC branch. No production behaviour depends on them.
- **Status:** open, will be applied on RC.

---

### G4 — WP-A vs WP-B overlap (STACK). Conflict inventory captured.

Merging WP-B onto RC (which already had WP-A) conflicts in **10 files / 33 hunks**:

| File | Hunks |
|---|---|
| `KudosTests/ReaderWebIsolationTests.swift` | 6 |
| `kudos-ao3-reader/Services/ReaderWebIsolation.swift` | 6 (add/add) |
| `KudosTests/StorageTests.swift` | 5 |
| `kudos-ao3-reader/Services/Storage.swift` | 4 |
| `kudos-ao3-reader/App/AppRouter.swift` | 3 |
| `kudos-ao3-reader/Services/AO3AuthService.swift` | 3 |
| `kudos-ao3-reader/Features/Reader/ReaderController.swift` | 2 |
| `kudos-ao3-reader/Models/AO3Session.swift` | 2 |
| `kudos-ao3-reader/Services/FolderSyncService.swift` | 1 |
| `TASKS.md` | 1 |

**Resolution rule (from the brief): keep the stricter production check AND the stricter test.**

Two determinations already made by direct comparison:

1. **`AppRouter.open(_:)` — WP-A is strictly stronger. Keep WP-A.**
   WP-A has *both* the scheme gate and a host gate: non-AO3 `http(s)` is handed to the system browser and only `https` AO3 hosts reach the in-app sheet. WP-B's side has the scheme gate but **no host gate at all** — that whole `if !AO3AuthorRoute.isAO3URL(url) { …open externally…; return }` block is absent on the WP-B side. Taking WP-B here would regress M19 by letting an arbitrary `https://evil.example` load in the in-app browser that carries AO3 session state.
   WP-B's *comment* is better (it explains that `javascript:` is a WebKit no-op today but `data:` genuinely commits and renders). Keep WP-A's code, fold in WP-B's rationale as a comment.

2. **`openAO3Link` host predicate — the two are functionally identical; free choice.**
   `AO3AuthorRoute.isAO3URL` (WP-A) and `AO3RequestDefaults.isTrustedURL` (WP-B) both do https-only + apex-or-subdomain against `archiveofourown.org`. Verified verbatim on both branches; the only delta is `url.host` vs the newer `url.host()`. No security difference. Prefer one and drop the duplicate predicate later (a single host-trust helper for the app would be an improvement, but that is cleanup, not a merge blocker).

Remaining 8 files still need the same stricter-of adjudication — deferred until the WP-B review (which was explicitly tasked to identify where WP-B is stricter, with `file:line`) returns.

---

## Tree reviews

### WP-A — reviewed by **Gemini 3.1 Pro (High)** (implementers: Claude Opus 5 / Opus 4.8, + Grok on M13)

Full report: `/Users/cidy02/kudos-fix-wp-a/REVIEW-GEMINI-WPA.md`. **Verdict: 6 SHIP, 2 FIX, 0 BLOCK.**

**SHIP:** M11 (`Storage.swift:142-156`, rejects rather than rewrites, UUID fallback) · M16 (`AO3SessionVault.swift:157-162`, `SecItemUpdate` re-asserts `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) · M8 (`ReaderWebIsolation.swift:61`, `nonPersistent()` store) · M15/M20 (`KudosBackup.swift:1351-1362` + `ModelContext+SaveBestEffort.swift:24` — `autosaveEnabled = false`, `rollback()` on catch, and `saveBestEffort` no-ops while autosave is disabled so no partial state commits) · M13 (`AO3SessionVault.swift:227-231`, `isExcludedFromBackup`) · the `openAO3Link` host-check fix the conductor landed earlier this session (`AppRouter.swift:228`) — independently confirmed correct.

Both FIX findings are the exact class the reviewer was asked to hunt — **the fix is right but the test cannot catch a revert**:

- **WPA-1 (FIX) — M19 test has a revert loophole.** `KudosTests/AppRouterM19Tests.swift`, `unguardedURLSinkIsClosed` asserts only `router.pendingURL == nil` and `!router.isPresentingWebBrowser`. If the fix regressed to handing `javascript:`/`data:` to `UIApplication.shared.open`, **both assertions would still hold** and the test would pass. Patch: inject the system-open handler (or a test seam) and assert it is *not* invoked for hostile schemes.
- **WPA-2 (FIX) — M14 validator paths are untested.** No test covers `LiveAO3SessionValidator.responseCookies` or `merging`; the suite exercises `MockAO3SessionValidator` instead. A revert that re-widened the persisted blob to every AO3-domain cookie would go completely unnoticed. Patch: a direct unit test on `responseCookies`/`merging` asserting off-domain and non-allow-listed cookies are dropped.

Conductor's note: WPA-1/WPA-2 are test-coverage holes, not live vulnerabilities — the production code is correct today on both. They are genuine FIX (the brief's definition of done requires a test that goes RED when the fix is removed), but neither is a BLOCK for stacking.

### WP-C — reviewed by **Grok (xhigh)** (implementers: Claude Opus 5 + Gemini 3.1 Pro)

Full report: `/Users/cidy02/kudos-fix-wp-c/REVIEW-GROK-WPC.md` (340 lines). **Verdict: 0 BLOCK, 5 FIX, 5 SHIP.** Reviewer's headline: *"Do not merge as 'done' until the FIX items below are closed — T-195 overclaims directory laziness, the ZIP laziness test still does not prove unread-until-access, and `1ee0ade` shipped leftover artifacts."*

**SHIP:** M5 zero-compressed-DEFLATE guard placement + the 500 MB → 2 MB fixture change (a *strengthening*, not a weakening) · ZIP EPUB decode genuinely lazy and restore uses the accessor · Settings pre-confirm ordering · M17 residual honestly recorded as accepted-risk rather than claimed fixed · existing restore/round-trip tests adapted, not gutted.

**FIX-1** — the ZIP laziness test does not prove unread-until-access, so it is not yet a regression test for M4.
**FIX-2** — **directory import still materialises every EPUB (and the whole tree) after confirm.** M4 is only actually fixed on the `.kudosbackup` ZIP path; the directory path is still a live user-facing Settings route. **T-195's "DONE" claim is an overclaim.**
**FIX-3** — ZIP `init(zipData:)` still eagerly extracts every font (same decompression-bomb class as M4, smaller typical N).
**FIX-4** — leftover artifacts committed in `1ee0ade`; reviewer independently flags these must go *before* stacking onto `security-fixes/rc`. **This is the same issue as WPC-1 above, found independently.**
**FIX-5** — the split read introduces a confirm-time TOCTOU (new with this WP, lower severity than FIX-2).

### WP-E — reviewed by **Grok (xhigh)**

Full report: `/Users/cidy02/kudos-fix-wp-e/REVIEW-GROK-WPE.md` (257 lines). **Verdict: SHIP, 0 BLOCK, 2 FIX (both test-coverage/bookkeeping, not production holes).**

Confirms the load-bearing question from the brief: the M1g guard **is** at the merge entry point for the paths that bypass the mapper (SHIP-3), the shared helper never copies the archive wipe instant (SHIP-1), T1 does assert ≈`now + RECOVERY_WINDOW` (SHIP-5), T2 hits `BackupMergeService.merge` and proves overlay neutralisation for collections and queues (SHIP-6), and no existing assertions were weakened (SHIP-8).

**FIX-1** — T2 never overlays a *work*, so the P0 vector is untested at the merge entry (collections and queues are covered; production is currently safe, hence FIX not BLOCK).
**FIX-2** — `TASKS.md` cites a SHA that is not on this branch.

### WP-F — reviewed by **Gemini 3.1 Pro (High)** (implementers: Grok 4.5 + Claude Opus 5/4.8)

Full report: `/Users/cidy02/kudos-fix-wp-f/REVIEW-GEMINI-WPF.md`. **Verdict: 1 FIX, 2 SHIP, 0 BLOCK.**

**SHIP** — M3 privacy stricter-of is correctly implemented *at the real persistence boundary* (`SettingsRepository.replaceAll:205-215`, used by `BackupRepository.applyMergeResult`), and its mutations are strong. M21/M2b: font extension allow-list, per-entry cap enforced during read, aggregate `MAX_TOTAL_FONT_BYTES` bound, and blank/unknown `recordTypeRaw` strictly rejected rather than defaulting to `savedWork`.

**FIX (WPF-1) — the M1a timestamp clamp does not do what WP-F claims, and its own mutation evidence is unsound.**
- `BackupValidator.kt:154-155` *clamps* a `> now + 24h` value to `now + 24h` instead of **rejecting** it.
- The `min(value, exportedAt)` clamp is **absent entirely** from both `parseInstant` and `BackupMergeService.parseOptionalInstant`.
- Reviewer's judgement on the evidence: the M1a mutations quoted in `android/WP-F-REVERT-CHECKS.md` are **"too weak to be meaningful — they test that the timestamp is clamped to `now + 24h`, asserting the *broken* implementation instead of enforcing the spec."** This is exactly the failure mode the review was asked to hunt: mutation evidence that certifies the bug rather than the fix.

---

### G9 (NEW, STACK) — two Android `exportedAt` clamp implementations will collide on RC

Conductor-level finding; no single-tree reviewer could see it.

WP-F's Android clamp is **missing** the `exportedAt` component (WPF-1 above). But the **tombstone tree** independently added one: commit `a1aa83f` is described as *"Android: drop unsigned incoming tombstones; Replace UX; `exportedAt` clamp; canonical `sourceURL`"*. Both trees therefore modify Android backup date handling, and they merge at RC steps 5 and 7.

This corroborates, from a second direction, the gap recorded in the pre-existing tombstone design notes ("Android has no `exportedAt` clamp; iOS clamps via `min(archived.lastModifiedAt, contents.manifest.exportedAt)` at `KudosBackup.swift:1334`").

**Action at merge:** verify the tombstone tree's clamp actually lands and supersedes WP-F's weaker one, and that the combined result **rejects** `> now + 24h` rather than clamping it. If the tombstone version also only clamps, WPF-1 must be fixed on RC. Do not assume the later merge silently fixes it — diff the final `parseInstant`/`parseOptionalInstant` on RC and re-run the Android gate.

### tombstone — reviewed by **Claude Opus 5** (R0 merge gate; implementers Grok + Opus 4.6 + Gemini design)

Full report: `/Users/cidy02/kudos-fix-tombstone/REVIEW-CLAUDE-TOMBSTONE.md`. **Verdict: FIX — 9 findings, 15 items confirmed correct, 0 BLOCK.** Two of these defeat the Phase 2 model and are the most serious findings of the entire cycle.

- **TOMB-1 (FIX, both platforms) — `lastModifiedAt` is authorization-bearing but is NOT in the signed payload.**
  `PHASE2-CONTRACT.md` signs six fields; `lastModifiedAt` is not one of them. Yet `lastModifiedAt` is the **only** field that decides suppression (`KudosBackup.swift:2079-2080` `tombstone.lastModifiedAt >= archivedModifiedAt`; `BackupMergeService.kt:1247`). Both platforms copy the incoming value verbatim into the adopted row, and R-P2-7's 24h clamp is applied only to the archived *work's* timestamp, never the tombstone's (iOS has no clamp on this path at all). An attacker holding one of the user's own `.kudosbackup` files takes a stale but **validly signed** tombstone, leaves all six signed fields byte-identical so Ed25519 still verifies and the signer is still trusted, and rewrites `lastModifiedAt` to 2099 — suppressing that work forever against every future snapshot. **This re-creates the exact "never expires" property that handoff §1 exists to kill, now with a valid signature.** Patch is small and lossless (`lastModifiedAt == createdAt` at every minting site already): pin to `archived.createdAt` on iOS (`KudosBackup.swift:2140`) and `.copy(lastModifiedAt = it.createdAt)` on Android (`BackupMergeService.kt:57`).
- **TOMB-2 (FIX, Android only) — a trusted signature can DELETE a local tombstone.** The adopt loop keys the working map by the row's own `id` (`BackupMergeService.kt:62`), which is **not** a signed field. That map is seeded from local Room rows and written back via `syncTombstoneDao().upsert()` against `@PrimaryKey val id`. An attacker copies a validly-signed tombstone's six signed fields verbatim, sets `id = T2.id` where T2 is the local tombstone suppressing a work the user deliberately deleted (both values readable from the same file) — T2 is destroyed and the work it suppressed is resurrected permanently. Violates locked spec §2 / B.2 clause 3. iOS is **not** vulnerable (dedupes on `recordTypeRaw|recordID`, insert-if-absent, `id` not `.unique`). Patch: skip if the key already exists.
- **TOMB-3 (FIX, iOS) — Replace leaves collections and queues permanently un-undeletable.** Locked spec §2 promises a later Merge can bring back what Replace removed. Works do undelete (`:1279-1281`), but collections and queues pin `incomingWins = false` on `.merge` (`:1420`, `:1554`) so `isPendingDeletion` stays true forever (`:1442`, `:1579`) — they silently accumulate restored works as members and are hard-deleted by the 90-day sweep. Android does **not** have this hole, so it is an iOS-only divergence from the owner's R9 parity ruling.
- **TOMB-4 (FIX) — the "a backup never writes the trust store" test survives a revert.** Every trust-store *read* in restore is defaults-injected; the one *write* (`TombstoneSigning.swift:97`) uses default `.standard`. Reintroducing TOFU the natural way would write to `UserDefaults.standard` while the test asserts against the injected suite — both assertions still pass, regression ships silently. (Also leaks the host device pub into real user defaults on every test run.)
- **TOMB-5 (FIX) — `TombstoneSigningTest.signThenVerifyRoundTrip` is 1-in-16 flaky.** The forgery appends a literal `"0"` to a truncated signature; with a fresh random keypair per run the last hex char is `'0'` ~6% of the time, reproducing the *valid* signature and failing the assertion. Would turn the Android gate red on a correct tree — directly threatens "GREEN last" (DoD #4). Both sibling forgery tests already do this correctly.
- **TOMB-6 (FIX) = G3** — no iCloud KVS entitlement anywhere in the project, yet shipped Settings copy (`SettingsView.swift:1244`) promises the feature works. Reviewer's position: this is **more than a device-only follow-up** because the UI makes a promise the build cannot keep.
- **TOMB-7 (FIX, Android)** — Replace lets an adopted tombstone suppress a work in the same snapshot; iOS Replace does not (`BackupMergeService.kt:66`).
- **TOMB-8 (FIX) = G2** — Android annotation deletes mint no tombstone, so deleted highlights are **resurrected by the next folder sync**. Reviewer argues this is a real data-integrity bug, not merely a parity gap to sign off.
- **TOMB-9 (FIX)** — two added Swift lines exceed the 120-char lint ceiling; CI runs `swiftlint --strict`, so this alone fails the gate.

### WP-B — reviewed by **Claude Opus 5** (implementer: Grok 4.6)

Full report: `/Users/cidy02/kudos-fix-wp-b/REVIEW-CLAUDE-WPB.md`. **Verdict: FIX — 6 findings, 2 merge instructions, 19 items confirmed correct, 0 BLOCK.** This is the G4 input I was waiting for.

- **WPB-1 (FIX) — decisive for G4:** WP-B's two new `openAO3Link` tests (`KudosTests/AppRouterTests.swift:158`, `:168`) **assert the looser behaviour** and will go **RED** as soon as WP-A's stricter `AppRouter.open` wins the merge. Confirms my independent determination that WP-A is stricter here; the tests must be updated, not the production code.
- **WPB-2 (FIX)** — the M9 relay test (`LiveAO3SessionValidatorRelayTests.swift:33-36`) has **no positive control**: it passes vacuously if the redirect never reaches the attacker at all.
- **WPB-3 (FIX)** — the Readium navigation guard is installed *opportunistically*, so a freshly **preloaded spread runs unguarded** (`ReadiumBook.swift:512`, `:648`; `ReadiumNavigatorContainer.swift:136`). This re-scopes G1.
- **WPB-4 (FIX) — second RC merge trap:** `coordinatedReadData` is edited incompatibly by WP-A and WP-B, and **the plausible merge resolution silently drops M12 on the font path** (`FolderSyncService.swift:562-571` vs WP-A's `:581-597`).
- **WPB-5 (FIX)** — the M9 test seam is un-gated production API, against WP-A's own `#if DEBUG` precedent in the same work.
- **WPB-6 (FIX)** — WP-A's stricter M14 filtering of `install()`/`merging()` is untested in **both** trees; deleting it leaves the suite green. (Converges with Gemini's WPA-2 from a different direction.)
- **Merge instruction (SHIP):** `ReaderController.swift` needs a **hybrid, not a pick** — each tree is stricter in a different place (`:191-205`).
- **G1:** sign off, re-scoped to the preloaded-spread case (WPB-3).

### WP-D — reviewed by **Claude Opus 5** (implementer: Grok 4.6)

Full report: `/Users/cidy02/kudos-fix-wp-d-signing/REVIEW-CLAUDE-WPD.md`. **Verdict: FIX — 8 findings + 2 SHIP, 10 items confirmed correct, 0 BLOCK.** For a 2-commit tree this is the heaviest result of the cycle: **the macOS signing guard is largely non-functional, and one change actively weakens iOS.**

- **WPD-3 (FIX) — actively harmful:** the entitlement pin is **unqualified on a five-platform target** (`project.pbxproj:605-606`), which **weakens iOS Release from Keychain to the plaintext file vault** (`AO3SessionVault.swift:271-281`). A signing-hardening change that downgrades session storage on the main platform.
- **WPD-5 (FIX) — third RC merge trap:** taking WP-D's `AO3SessionVault.swift` on conflict **silently reverts WP-A's M14 and M16**. RC stack order puts WP-A at #2 and WP-D at #4, so the naive resolution loses two confirmed fixes.
- **WPD-1/2/4/6/7 (FIX) — the guard does not guard:** the check never reads the file that now *is* the entire Release entitlement set, so `get-task-allow` written into `Kudos.entitlements` **passes with exit 0** (`:36-47`); the product assertion is **never invoked anywhere** and no script in the repo builds Release (`ci.yml:38`, `verify.sh:26-35`, `build-macos.sh:27-30`); hardened runtime can be disabled and ad-hoc signing re-added while still passing (**mutation-proven**); `set -e` aborts the product half at `:64` before the `get-task-allow`/sandbox/hardened-runtime assertions run; and it writes working data to a fixed, predictable `/tmp` path.
- **WPD-8 (FIX)** — the newly-pinned `Kudos.entitlements` **under-declares** what shipped macOS folder-sync code needs (`FolderSyncService.swift:490, 507, 688, 719, 738`) — a functional break, not just a security one.
- **SHIP:** M13 is byte-identical to WP-A's `c701bdb` (neither stricter; the test is a genuine revert-catcher) → resolves that half of the G4/WP-D overlap. **G8 signed off** as a genuine environmental limit.

---

## Cycle 1 totals

**6 trees reviewed by 3 model families. 0 BLOCK. ~30 FIX findings.** Nothing prevents stacking, but four findings must be fixed *on RC* rather than merged past, and three are RC merge traps where the obvious conflict resolution silently reverts a confirmed fix.

**Highest severity, in order:**
1. **TOMB-1** — signed tombstones carry an unsigned field that alone decides suppression (both platforms). Defeats Phase 2.
2. **TOMB-2** — a trusted signature can erase a local tombstone on Android and resurrect a deliberately deleted work.
3. **WPD-3** — WP-D's entitlement pin downgrades iOS session storage from Keychain to the plaintext file vault.
4. **WPC-FIX-2** — M4 is unfixed on the directory-import path; T-195's "DONE" is an overclaim.
5. **WPF-1** — the M1a clamp clamps instead of rejecting, `exportedAt` is absent, and its own mutation evidence certifies the bug.

**Three RC merge traps to honour when stacking:** WPD-5 (`AO3SessionVault.swift` — must not take WP-D's), WPB-4 (`coordinatedReadData` — must not drop M12 on the font path), WPB-1 (WP-B's `openAO3Link` tests must be updated to WP-A's stricter behaviour, not the reverse). Plus WPB's instruction that `ReaderController.swift` needs a **hybrid**, not a pick.

### G1–G9 status after cycle 1

| # | Status |
|---|---|
| G1 M8 device probe | **signed off**, re-scoped to the preloaded-spread case → now tracked as WPB-3 |
| G2 Android annotation tombstones | **escalated** — reviewer says deleted highlights are resurrected by folder sync (TOMB-8), not a benign parity gap |
| G3 iOS iCloud KVS entitlement | **escalated** — shipped UI promises a feature the build cannot deliver (TOMB-6) |
| G4 WP-A vs WP-B overlap | 2 of 10 files adjudicated + WPB-1/WPB-4 + ReaderController hybrid instruction now in hand; remainder mechanical |
| G5 tombstone vs WP-A `KudosBackup.swift` | not yet reached (merge step 5) |
| G6 bookmarks/saved-searches Replace | superseded in part by TOMB-3 (collections/queues have the same undelete hole) |
| G7 Replace 1.5s UI tests | SKIP per brief |
| G8 macOS Developer ID / notarization | **signed off** — genuine environmental limit |
| G9 Android `exportedAt` clamp collision | open; now compounded by WPF-1 and TOMB-1 (all three touch Android tombstone/date handling) |

**Paused here at the owner's request.** All six reviews complete and recorded; no agents running. Nothing pushed.

---

### G1–G8 status

| # | Status |
|---|---|
| G1 M8 device probe | pending WP-B review's assessment |
| G2 Android annotation tombstones | pending tombstone review's assessment |
| G3 iOS iCloud KVS entitlement | pending tombstone review's assessment |
| G4 WP-A vs WP-B overlap | **in progress** — 2 of 10 files adjudicated (above) |
| G5 tombstone vs WP-A `KudosBackup.swift` | not yet reached (merge step 5) |
| G6 bookmarks/saved-searches Replace | pending tombstone review |
| G7 Replace 1.5s UI tests | SKIP per brief (no harness) |
| G8 macOS Developer ID / notarization | pending WP-D review; expected environmental, not a code hole |

---

## Cycle 2 — RC stacking, gates, and the first fix round (2026-08-16)

### RC assembled

All 7 trees stacked on `security-fixes/rc` in the brief's order. Conflict resolutions and the two traps (F4, WPD-5) are documented in the merge commits and in `handoff.md`'s cycle log. Highlights:

- **G4** (10 files / 33 hunks) resolved per WP-B review Part 3's per-item stricter-of table.
- **G5** caught a real drop: `makeTombstone` had **no** `exportedAt` clamp while HEAD did, so taking the tombstone side wholesale would have silently removed it. Kept both.
- **G9** hybridised: tombstone's mode/trust plumbing + WP-F's M21 font validation and M2b DAO type filter.
- **WPC-1 / WP-C FIX-4** applied — removed `KudosBackup.swift.orig` and three mutation revert patches.

### Gate failures — all three were merge artifacts, none were work-package defects

Every one had the same shape: a declaration taken from one tree and its usage from the other.

1. `KudosBackup.swift` — WP-A's M15 wrapper/inner split vs the tombstone tree's `mode:` parameter. 13 `cannot find 'mode' in scope`. Threaded through. **This is exactly the G5 collision the brief said could only be resolved at stack time.**
2. `SettingsView.swift` — tombstone's three-mode import bodies with WP-A's two-field (`SecurityScopedURL` + manifest) state shape. Unified onto the tombstone model.
3. `SettingsView.swift` — a leftover `_ = scopedURL` keep-alive with nothing left to keep alive.

### ⚠️ Vacuous-gate trap found and fixed in the brief itself

`-only-testing:KudosTests/FolderSyncTests` matches **0 cases and still exits 0**. `FolderSyncTests` is nested under `PersistenceGateSuites` exactly like `KudosBackupTests`, so the only valid path is `KudosTests/PersistenceGateSuites/FolderSyncTests` (27 cases). The brief documented this trap for `KudosBackupTests` but then used the bare form for FolderSync.

**This mattered concretely**: FolderSync holds `coordinatedReadData`, i.e. the F4 symlink guard hand-merged in this cycle. Following the brief literally produces a green iOS gate that never exercises it. `handoff.md` corrected in `136dcae`. **Always confirm which suites ran, not merely that the run was green.**

### Fix round 1 — tombstone batch (implementer Grok 4.6, reviewer Claude — split respected)

Six commits (`02fa547`…`7433016`) plus `FIXES-GROK-TOMBSTONE.md`. **All six independently verified against the code by the conductor, not accepted on the report:**

| Finding | Verified |
|---|---|
| TOMB-1 iOS | `makeTombstone`: `lastModifiedAt = archived.createdAt` (signed field); RC's `exportedAt` clamp still applied after adopt |
| TOMB-1 Android | `.let { it.copy(lastModifiedAt = it.createdAt) }` before verify/trust |
| TOMB-2 Android | `if (tombstonesById.containsKey(incomingKey)) return@forEach` — a trusted signature can no longer destroy a local tombstone row |
| TOMB-3 iOS | collections **and** queues undelete on `.merge` (`:1618`, `:1747`), mirroring works |
| TOMB-4 iOS | `TombstoneTrustStore.add(pub, defaults: defaults)` — the write is injectable |
| TOMB-5 | flip branches on `if last == '0'`, matching the correct sibling |

**Grok's evidence independently validated a conductor decision.** Its iOS TOMB-1 mutation went RED showing `lastModifiedAt → 2026-08-16`, which it correctly identified as the snapshot's `exportedAt` — proving the G5 clamp I preserved *was* engaging and still left TOMB-1 open. Keeping the clamp was right; it was necessary but not sufficient. It also hit the same 0-count filter trap on a single-test filter and reported it unprompted.

### Gates after fix round 1

- **Android: 848 tests / 0 failures / 0 errors / 0 skipped** — tallied by the conductor directly from the JUnit XML, not from Gradle's summary or Grok's report. Matches the claimed figure exactly.
- **iOS:** re-running at time of writing (42/42 backup + 27/27 folder sync before this round).

### STACK hazard from Grok's "not closed" list — CHECKED, clean

Grok flagged that RC must keep WP-F's rejection of a blank `recordTypeRaw` and must not revert to the tombstone tree's `ifBlank { "savedWork" }`. Verified directly: `BackupMappers.toSyncTombstone` **throws** `IllegalArgumentException` on blank or unknown types (`:543`). The default would have been the dangerous outcome — any garbage type string in an untrusted archive becoming a *work* tombstone, and work tombstones are precisely what suppress a later restore. The remaining `ifBlank` calls are unrelated (`kindRaw` for queues/bookmarks).

### Still open after cycle 2

| Finding | Owner |
|---|---|
| TOMB-6 / G3 — no iCloud KVS entitlement; shipped Settings copy promises the feature | open |
| TOMB-7 — Android Replace lets an adopted tombstone suppress in-snapshot; iOS does not | open |
| TOMB-8 / G2 — Android annotation deletes mint no tombstone; folder sync resurrects deleted highlights | open |
| WPD-1..8 — incl. **WPD-3, the iOS Keychain→plaintext-vault downgrade** | next |
| WPC FIX-1/2/3/5, WPF-1, WPA-1/2, WPB-1..6 | queued |
| RC pre-confirm laziness regression (tombstone `read` vs `preConfirmManifest`) | queued |
