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

### WP-B, WP-D, tombstone — reviews in flight (Claude Opus 5, via Workflow `wv60qb8dd`)
### WP-C, WP-E — reviews in flight (Grok, xhigh)
### WP-F — review in flight (Gemini 3.1 Pro)

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
