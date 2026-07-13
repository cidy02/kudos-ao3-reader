# RELEASE_READINESS_FABLE5.md — Fable 5 Release-Readiness Audit

Sequential ten-area audit ledger. Audit only — no production code is modified by
this audit. Continue from this file; do not restart completed areas.

## 1. Release candidate

| Field | Value |
|---|---|
| Branch | `inbox-refinement` |
| Product baseline SHA | `c1bf21176763df481ddf48488b99e2d8dfc62bae` |
| Product baseline subject | `Refine native Inbox comments and actions` |
| Recorded | 2026-07-12 |

Areas 1–7 were originally inspected while the Inbox refinement was an
uncommitted diff on `58e307e`. That exact diff is now frozen in `c1bf211`; Area
1's canonical verification was re-run against the clean product commit before
Area 8 began. The earlier area narratives retain their historical SHA wording
so their evidence trail is not rewritten after the fact.

## 2. Working-tree cleanliness

**PRODUCT TREE CLEAN at `c1bf211`.** T-91's Inbox implementation, fixtures,
tests, networking-policy update, regression matrix, and task handoff are all in
the product commit. `Scripts/verify.sh` was re-run after the commit: 371/371
tests passed, macOS built, and invariants/lint gate/whitespace passed.

The working directory still contains this audit ledger plus unrelated untracked
`.idea/` and `android/` directories. The latter is the separate Android product
line and is deliberately excluded; neither directory nor the ledger changes the
audited iOS/macOS product artifact.

## 3. Intended platforms and build configurations

- **Platforms:** iOS / iPadOS (Readium reader), macOS (legacy WKWebView reader).
  Single target `AO3_App_OpenSource`, product `Kudos`, bundle `com.cidy02.Kudos`,
  scheme `AO3_App_OpenSource`. GPL-3.0.
- **Configurations:** Debug and Release. Simulator/CI builds use
  `CODE_SIGNING_ALLOWED=NO`; device builds require a team in Xcode Accounts.
- **Toolchain:** Xcode-beta (`xcode-select -p`); `Scripts/build-macos.sh` pins a
  stable build for macOS. Canonical test destination:
  `platform=iOS Simulator,name=iPhone 17,OS=26.5`.
- **Known history:** Release builds once crashed the beta Swift compiler in
  vendored SwiftSoup (T-66) — Release must be re-verified, never assumed.
- **Known signing drift (pre-existing):** AGENTS.md says keep `DEVELOPMENT_TEAM`
  scrubbed to `""`; onboarding notes commit `bcfe335` follow-ups carry
  `NQH85H7343` — human decision pending (checked in Area 1).

## 4. Compact invariant summary (reuse in later areas; sources in docs/)

**Data (DATA_AND_PERSISTENCE_INVARIANTS.md):** Never lose EPUBs, progress
(`readiumLocator`/`lastSpineIndex`/`lastScrollFraction`), flags, tags, queues,
collections, bookmarks. No network outcome deletes local data (404 → mark
`ao3Unavailable`, keep all). Deletion is user-initiated → Recently Deleted 90
days (`PreservedWorkService.softDelete`); only sweep/explicit hard-deletes.
Identity: AO3 id → canonical URL → UUID, only via `WorkIdentityIndex`;
re-acquiring revives, never duplicates. Backups: manifest v7, decode v1–v7,
fractional-second encode / whole-second decode fallback; derived
`searchText`/index never in backups; `reindex` never `markModified`. Merges
timestamp-gated (`SyncMerge.shouldApplyIncoming`); tombstones suppress
resurrection, `restore()` retracts. Folder sync: stage-to-temp + `replaceItemAt`
(never remove-then-write), NSFileCoordinator, never skip while unresolved
NSFileVersion conflicts exist, all gated by `PersistenceOperationGate`. New
`@Model` fields additive-with-defaults only; never name a property `isDeleted`.

**AO3 networking (AO3_NETWORKING_POLICY.md):** One contact UA
(`AO3RequestDefaults.userAgent`, single-sourced). `AO3Client.pace()` ≥0.6s
between request starts (all four touchpoints). 3-slot `AO3RequestCoordinator`
for fan-out. `RequestCoalescer` dedups anonymous GETs by URL, authenticated by
URL+Cookie. 429 honors Retry-After; writes surface it, never auto-retry.
`withRetry` max 2, transient-only (5xx/429/transport); 403/404/parse never
retried. Writes single-shot, never coalesced. Refresh throttles: tags 24h,
update checks WIP-only 6h, folder-sync 60s. Batches sequential. Parse failures
degrade to `AO3Error.parse`/empty and never mutate local records. Forbidden: raw
URLSession to AO3, retry loops on writes, background polling beyond the BGTask,
bulk scraping of logged-in pages, weakening pacing/UA.

**Engineering (AGENT_ONBOARDING.md pitfalls):** `@MainActor` around SwiftData;
actors are reentrant (pacing ≠ actor). Guard `modelContext != nil` in
fire-and-forget tasks. One `.fileImporter` per view node. No `isDeleted` model
property. pbxproj: synchronized groups — no edits to add files; revert cosmetic
churn. Parallel testing disabled (`PersistenceOperationGate` contention).
Sepia needs `.appThemedScroll()/.appThemedRows()`. Definition of done =
`Scripts/verify.sh` all green.

**Never-live-verified (standing release gates, pre-existing):** AO3 write
actions (`AO3WriteActions` — kudos/comments/bookmarks POSTs); real-device BGTask
scheduling; signed-device Keychain persistence.

## 5. Ten-area ledger

| # | Area | Status | Notes |
|---|---|---|---|
| 1 | Baseline, build, and release configuration | COMPLETE | Original P1 unfrozen-RC process finding resolved by `c1bf211`; 1×P2 (team-ID leak), 1×P3 (target drift) remain. Canonical recheck: verify.sh ALL GREEN (371/371). Earlier iOS+macOS Release builds + unsigned archive SUCCEEDED against the same now-frozen Inbox diff. |
| 2 | Persistence, migration, backup, sync safety | COMPLETE | 1×P1 (user-tag clobber on stale-archive restore), 1×P3 (ungated EPUB blob overwrite), test-gap notes. Direct inspection + 1 bounded subagent (validated); no destructive error paths found anywhere. |
| 3 | AO3 networking and parser safety | COMPLETE | Original Area-3 result retained. T-91 addendum adds parser/form findings RF6/RF7/RF9; avatar requests are now paced through `AO3Client`. Area 5's A5-F1 still governs anonymous/auth isolation. |
| 4 | Concurrency and lifecycle correctness | COMPLETE | Original Area-4 result retained. T-91 addendum adds 3×P1: ambiguous Inbox reply verification checks synthetic page 1 (RF1), unresolved guards are lost across target/screen transitions (RF2), and a post-write reload can cross an account switch (RF3). |
| 5 | Authentication, security, privacy | COMPLETE | Original 4×P1/3×P2/1×P3 retained. T-91 addendum adds RF3 (cross-account post-write overwrite, P1) and RF5 (same-username session/cache reuse, P2). Existing A5 blockers still apply. |
| 6 | Core functional regression matrix | COMPLETE | Original 4×P2/1×P3 retained. T-91 addendum adds Inbox identity hydration, parser-empty, filter, pagination, response, accessibility, and chapter-retry findings RF4–RF11. |
| 7 | Reader and EPUB behavior | COMPLETE | 2×P1 (iOS auto-finishes/frees EPUB at 99%; macOS loses every intra-chapter position), 6×P2 (macOS WKWebView retention, active-content boundary, cross-spine state desync, encoded-href blank chapters, stale extraction overlay; iOS nested-TOC loss), 2×P3 (duplicate-basename TOC collision; malformed-spine compact-index drift). Two new release blockers. |
| 8 | Performance and scalability | COMPLETE | 3×P2 (root whole-store observation/recomputation; package backup/restore peak memory scales with all EPUB bytes; unbounded Comments page cache), no P0/P1. Inbox visible-page hydration is bounded/sequential/cached but can take ~12s for 20 uncached works by policy. Manual device thermal/battery and large-store Instruments gates remain. |
| 9 | Accessibility, UI integrity, platform behavior | NOT STARTED | |
| 10 | Documentation, packaging, final assessment | NOT STARTED | |

---

## Area 1 — Baseline, Build, and Release Configuration

Status: **COMPLETE** (2026-07-12). Audited by Claude (Fable 5). All evidence
gathered on the audit machine (Xcode-beta toolchain, iPhone 17 / iOS 26.5 sim).

### Verification commands and outcomes

| # | Command | Outcome |
|---|---|---|
| 1 | `Scripts/verify.sh` | **ALL GREEN**, exit 0 — invariants → lint → full iOS Debug test suite → macOS Debug build → `git diff --check` |
| 2 | iOS test suite (within #1), xcresult `Test-…2026.07.12_14-36-20` | **363/363 passed, 0 failed, 0 skipped** |
| 3 | `xcodebuild -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' CODE_SIGNING_ALLOWED=NO build` | **BUILD SUCCEEDED** — historical T-66 SwiftSoup Release-compiler crash does NOT reproduce (SwiftSoup 2.13.5) |
| 4 | `xcodebuild -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build` | **BUILD SUCCEEDED**; 3 unique warnings, all benign (AppIntents metadata note; asset-catalog note re macOS 26.5.1 vs SDK 26.5 — see A1-F3; dead ternary `ReaderView.swift:384` — compile-time-false branch on macOS, no runtime effect) |
| 5 | `xcodebuild -configuration Release -destination 'generic/platform=iOS' -archivePath … CODE_SIGNING_ALLOWED=NO archive` | **ARCHIVE SUCCEEDED** — unsigned arm64 `Kudos.app` in archive; only warning = AppIntents metadata note |
| 6 | Dependency resolution | `Package.resolved` tracked; 9 pins (readium swift-toolkit 3.9.0, swiftsoup 2.13.5, zip 2.1.2, zipfoundation 3.0.1, cryptoswift 1.10.0, differencekit 1.3.0, fuzi 4.0.0, gcdwebserver 4.0.1, sqlite.swift 0.16.0). Clean local clone resolved the full graph and `xcodebuild -list` auto-generated the `AO3_App_OpenSource` scheme (no shared scheme is tracked, but xcodebuild autocreates — clean-checkout CLI builds work; hypothesis "missing shared scheme breaks clean checkout" tested and **refuted**) |
| 7 | Built-product inspection | iOS Debug + Release + archived `Info.plist` all carry the Run-Script-injected `BGTaskSchedulerPermittedIdentifiers=[com.cidy02.Kudos.folderSyncRefresh]` and `UIBackgroundModes=[fetch]`; macOS correctly omits them. All 5 Readium/SPM resource bundles present in the Release app (~50 MB). Version metadata consistent: `MARKETING_VERSION=1.0`, `CURRENT_PROJECT_VERSION=1`, both configs |
| 8 | Production-hygiene greps | **Zero** `#if DEBUG` in `kudos-ao3-reader/` sources; zero launch-argument gates (`ProcessInfo.arguments`); zero test credentials/fixtures/debug menus in production code; zero `try!`/`as!`; one `fatalError` (`MyApp.swift:19`, ModelContainer creation — standard SwiftData pattern); one `precondition` (`AO3RequestCoordinator.swift:29`, compile-time-constant arg, cannot fire) |
| 9 | Entitlements | No `.entitlements` file (by design — no-entitlement folder sync); `NSFaceIDUsageDescription` present for the privacy gate |

### Findings

**A1-F1 — P1 Must Fix (process) — Unfrozen release candidate: audit baseline
includes another agent's uncommitted work.**
File: working tree (T-91 "AO3 Inbox v2", Codex, in progress). Feature: release
process, all platforms. Repro: `git status` on `inbox-refinement` shows 7
modified + 4 untracked paths. Expected: a release candidate is a frozen, clean
commit. Actual: every build/test result above includes the uncommitted T-91
diff; HEAD alone was not built. Impact: release artifact is not reproducible
from any commit; a later `git checkout` of HEAD yields a different app than
audited. Evidence: §2 above. Smallest correction: land or shelve T-91, freeze a
clean commit, re-run `Scripts/verify.sh` + one Release build against it.
Regression test: n/a (process). Blocks release: **YES** (trivially resolvable).

**Resolution (2026-07-12):** T-91 landed as `c1bf211`; the product tree is now
reproducible from that commit and `Scripts/verify.sh` passed 371/371 on the
frozen SHA. A1-F1 is closed and no longer blocks release.

**A1-F2 — P2 Should Fix — `DEVELOPMENT_TEAM = NQH85H7343` committed in a public
repo, contradicting stated policy.**
File: `AO3_App_OpenSource.xcodeproj/project.pbxproj:456` (app Debug) and `:509`
(app Release); test-target configs are correctly scrubbed (`:560`, `:581`).
Feature: repo hygiene/privacy, signing. Expected: AGENTS.md — "scrubbed to `""`
— keep it empty when you commit." Actual: personal team ID present (known drift
since `bcfe335`; AGENT_ONBOARDING.md marks the policy decision "human decision
pending"). Impact: personal identifier published in a public GPL repo (already
in git history, so removal now is hygiene not secrecy). Smallest correction:
scrub both values to `""` or record an explicit owner decision to keep them and
update AGENTS.md. Regression test: add a `check-invariants.sh` rule failing on
a non-empty `DEVELOPMENT_TEAM`. Blocks release: no.

**A1-F3 — P3 Follow-up — Deployment-target drift.**
File: `project.pbxproj:372/436` (project-level `IPHONEOS_DEPLOYMENT_TARGET =
27.0`) vs `:483/536` (app target `26.5`, which wins); `:374/438`
(`MACOSX_DEPLOYMENT_TARGET = 26.5.1`, above the SDK's known `26.5` — produces
the asset-catalog warning in every macOS build). Feature: build config, both
platforms. Impact: none today (target-level overrides project-level); risk is a
silent min-iOS jump to 27.0 if the target-level setting is ever removed, plus a
permanent noise warning that trains readers to ignore warnings. Smallest
correction: set project-level iOS to 26.5 and macOS to 26.5. Regression test:
n/a. Blocks release: no.

### Observations (not findings)

- CI (`.github/workflows/ci.yml`) is lint-only; the build job is deliberately
  omitted until GitHub runners ship the iOS 26 / Xcode 27 SDK (documented in
  the workflow). Accepted limitation.
- The active toolchain is **Xcode-beta**; all Release evidence above is from
  the beta toolchain (`Scripts/build-macos.sh` pins stable for macOS Debug).
  For an App Store–style distribution a stable-toolchain rebuild would be
  required; for GPL personal/sideload distribution this is acceptable — record
  as a release-note.
- `ReaderView.swift:384` "will never be executed" — macOS-only dead ternary
  branch (`compact` is compile-time false there); zero runtime impact.
- Standing never-live-verified gates (pre-existing, tracked for Area 10):
  AO3 write actions; real-device BGTask scheduling; signed-device Keychain.

### Manual checks remaining (Area-1 scope)

- Signed device archive/install (needs a signing team + physical device) — NOT RUN.
- Launch of the Release artifact on a physical device — NOT RUN (simulator
  Debug launches are routine; Release-artifact launch is covered indirectly by
  the successful archive only).

---

## Area 2 — Persistence, Migration, Backup, and Sync Safety

Status: **COMPLETE** (2026-07-12). Baseline SHA re-verified unchanged
(`58e307e`; same T-91 dirty set plus this ledger file).

### Method

Direct inspection of `Models.swift`, `WorkImporter.swift`, `WorkLifecycle.swift`,
`PreservedWorkService.swift`, `WorkIdentityIndex.swift`, `Storage.swift`,
`WorkSearchIndex.swift`, `FolderSyncService.swift`, `WorkTags.refreshFromAO3`,
`ReadingQueueService.replaceEPUB`. One bounded subagent audited
`KudosBackup.swift` + `PersistenceSync.swift` against the written invariants
(10 structured questions); its two findings and load-bearing claims were
hand-verified against the tree before acceptance. Existing automated evidence
reused from Area 1's green run (363/363, incl. `KudosBackupTests`,
`PersistenceSyncTests`, `FolderSyncTests`, `PreservedWorkTests`, `EPUBTests`,
`WorkSearchIndexTests`, `ReadingQueueTests`); no destructive tests were run
against the owner's real library.

### Invariants verified (evidence: file:line, current tree)

- EPUB-loss safety: `copyImportedEPUB`/`replaceEPUB` validate the new file
  first, then staged `replaceItemAt` (never remove-then-write); failure leaves
  the prior EPUB intact (`WorkImporter.swift:518-548`,
  `ReadingQueueService.swift:662-679`). Folder-sync writes stage to
  `itemReplacementDirectory` + `replaceItemAt` under `NSFileCoordinator`
  (`FolderSyncService.swift:417-457`).
- 404 → `ao3Unavailable = true`, keep all local data; other errors keep state
  and retry later; `modelContext != nil` guarded (`WorkTags.swift:67-77`).
- Soft-delete → 90-day window with tombstone; `restore()` retracts the
  tombstone (no timestamp race); sweep gate-checked and fully synchronous on
  MainActor (`PreservedWorkService.swift:31-38, 70-77, 100-109, 143-176`).
- `hardDelete` tombstones the work AND its queue memberships before cascade
  (`WorkLifecycle.swift:64-76`); only PreservedWorkService calls it.
- Re-acquire revives: both import funnels restore Recently-Deleted matches
  before merging, fill-only (`WorkImporter.swift:42-72, 249-271`); TOCTOU
  re-check after the awaited download (`WorkImporter.swift:37-42`).
- Identity via 3-tier matcher (`WorkIdentityIndex.swift:38-51`).
- Backup: manifest v7, `supportedVersions = 1…7`, uniform `decodeIfPresent`
  defaults; fractional-second encode + fractional→whole-second decode fallback
  intact both directions (`KudosBackup.swift:130-160, 175, 235-251`).
- All five invariant booleans `incomingWins`-gated (`KudosBackup.swift:
  1605-1615`); latch-OR only on `workTagsFetched`/`ao3Unavailable`/
  `isQueuedForLater` (commented, outside the invariant list); work-tag arrays
  merge additively via `TagMerge` (never remove).
- Tombstone suppression with newer-snapshot revival; membership tombstones
  incl. `.workCollectionMembership` composite ID (`KudosBackup.swift:1436-1538`,
  `PersistenceSync.swift:360, 413-420`). Existing local records match via
  `WorkRestoreIndex` before tombstone consult → a re-created record cannot be
  permanently suppressed.
- Suppressed works' EPUB blobs are never written (suppression `continue`s
  before the blob write, `KudosBackup.swift:1016-1019` vs `1048`).
- Derived index excluded from export; restored works reindexed inline
  (`KudosBackup.swift:393-446 CodingKeys, :1035`); `reindex` never calls
  `markModified` (`WorkSearchIndex.swift:83-86`); launch rebuild yields and
  re-checks model liveness (`WorkSearchIndex.swift:100-119`).
- Migration stages gate-protected, yield every 50, `modelContext != nil`
  guards, stage-aware errors; `reconcileAssets` flips flags only, deletes
  nothing (`PersistenceSync.swift:137-167, 285-307`).
- No `context.delete`/`removeItem`/soft/hard delete reachable from any catch
  block in the audited files (grep + the repo-wide `check-invariants.sh` rule,
  green in Area 1).
- Interrupted restore: additive-only; blob writes `.atomic`; settings applied
  only after a successful `context.save()`; a mid-restore throw leaves a
  committed partial *merge* (non-destructive) — orphan EPUB files for
  never-persisted inserts match the documented accepted risk.
- All `@Model` fields defaulted (additive migration); no `isDeleted` property.
- `Storage.safeEPUBAssetIdentifier` rejects separators/non-`.epub` names
  (path-traversal defense) (`Storage.swift:14-25`).

### Findings

**A2-F1 — P1 Must Fix — User-tag associations replaced ungated on restore;
a stale archive silently strips locally-added tags.**
File: `kudos-ao3-reader/Services/KudosBackup.swift:1039`. Feature:
backup/import restore AND automatic folder-sync merges (both platforms;
`FolderSyncService` sync-down/conflict-fold call this restore on
launch/foreground triggers). Repro: device A tags work W ("fluff"),
`markModified(t=200)`; device A then syncs down device B's package containing
W with `lastModifiedAt=100` and no user tags → `work.tags =
archived.userTags.compactMap {…}` runs unconditionally (no `incomingWins`
gate, no union) → the local tag association is removed. Expected: tags are on
the invariants' "Never lose" list and merges are timestamp-gated. Actual:
wholesale replacement regardless of which side is newer. Impact: silent loss
of user-authored organization data via the normal, automatic sync path — no
error shown, nothing recoverable. Evidence: hand-verified in tree
(`:1005-1046`); the only tag-restore test (`KudosBackupTests.swift:120-196`)
restores into a tagless local so the clobber is invisible. Smallest safe
correction: union archive tags into `work.tags` (append missing) and permit
removals only when `incomingWins` (or never, absent a membership-style
tombstone). Regression test: newer local work with tag + stale archive without
it → association survives; archive-only tags still get added. Blocks release:
**YES** (data-loss class on the "Never lose" list).

**A2-F2 — P3 Follow-up — Unconditional EPUB blob overwrite on restore.**
File: `KudosBackup.swift:1048-1050`. Restoring any package containing a blob
for a matched work replaces the local file regardless of timestamps or
`epubPreservationStatus`. Write pattern is atomic (no corruption), and this is
adjacent to the documented full-package accepted risk — but for a work that is
`ao3Unavailable` + `.preserved`, regressing to an older blob is unrecoverable.
Smallest correction: skip the overwrite when the local work is strictly newer
and a preserved file exists. Regression test: preserved work, newer local,
older archive blob → file bytes unchanged. Blocks release: no.

### Observations (not findings)

- `WorkImporter` carries two bespoke identity matchers
  (`existingWork(forSource:)`, title/author/file-size heuristic) predating the
  "only via `WorkIdentityIndex`" doc invariant. Same canonicalization helpers,
  same tiers, different priority order; no reachable divergence found — doc/
  code drift to reconcile, not a defect.
- Test-coverage gaps recorded from the subagent's Q10 (validated): fractional-
  second *encode* direction untested (decode fallback would mask a
  regression); no suppressed-work-blob-absence assertion; v3–v6 manifests not
  round-tripped; migration failure path (`.failedRecoverable`) untested;
  mid-restore-failure state untested; "Restored Queue" membership-without-
  metadata path untested. All P3 test-debt, listed for Area 10.

### Manual checks remaining (Area-2 scope)

- Cross-device backup restore and real iCloud Drive folder-sync propagation on
  hardware (already standing gates in REGRESSION_TEST_MATRIX.md).
- Real reinstall/upgrade walkthrough (schema verified additive; device walk
  still manual).

---

## Area 3 — AO3 Networking and Parser Safety

Status: **COMPLETE** (2026-07-12). Baseline SHA re-verified (`58e307e`).
Audited artifact includes T-91's uncommitted networking code
(`AO3InboxActions.swift`, `AO3Client+Inbox.swift` diff). No subagent used.
No live AO3 traffic was generated beyond what existing tests already avoid
(fixtures only).

### Entry-point enumeration (all verified through direct read)

| Entry point | Pipeline | Verdict |
|---|---|---|
| `AO3Client.getHTML`/`fetchData` (anonymous GET) | paced (`pace()` slot-claim, ≥0.6s starts) + coalesced by URL + `withRetry` (max 2, transient-only) + typed status checks | conforms (`AO3Client.swift:45-116`) |
| `authenticatedHTML`/`authenticatedPageHTML` | paced + coalesced by **URL+Cookie** (account-switch-safe) + retry + login-redirect → `.authenticationRequired`; `httpShouldHandleCookies=false` isolates the auth cookie set from the shared jar | conforms (`:356-382`) |
| `submitWrite` (all writes) | paced, **never retried, never coalesced**, 429 surfaced typed, login-redirect detected | conforms (`:395-411`); all **12** call sites (`AO3WriteActions`×6, `AO3CommentActions`×3, `AO3AuthorProfileService`×1, `AO3PreferencesActions`×1, uncommitted `AO3InboxActions`×1) are single-shot — zero loops/`withRetry` wrappers in any write file (grep-verified) |
| `downloadEPUB` | paced + retry + status-checked; temp-dir staging | conforms (`:575-590`) |
| `imageData(at:)` | paced/coalesced image pipeline; used by comment avatars (`CommentThreadRow.swift:847`) | conforms — but see A3-F1 for the two surfaces that don't use it |
| Batch: `DownloadQueue` | strictly sequential, skip/revive existing before download, cancel clears queued (in-flight finishes), failures logged not destructive | conforms (`DownloadQueue.swift:73-110`) |
| Batch: `WorkMetadataRefresh` | 3-slot `AO3RequestCoordinator`, `Task.isCancelled` checked before each fetch, both cancellation shapes break the loop, save-only-after-successful-parse | conforms (`WorkMetadataRefresh.swift:36-80`) |
| Poll: `WorkUpdateChecker` | WIP-only, 6h throttle stamped on failure too, serial | conforms (`WorkUpdateChecker.swift:12-52`) |
| WKWebView (browse fallback, login) | user-driven navigation — browser-equivalent by definition | out of pipeline by design |

Policy primitives re-verified: `RequestCoalescer` (in-flight dedup, cleared on
completion — de-duplicator not cache); `AO3RequestCoordinator` (fair FIFO
suspension semaphore, cancellation-aware waiters, slot handed directly to next
waiter). `Retry-After` parsed (seconds + HTTP-date) and honored via
`retryDelay`. Retry policy: 5xx/429/transient transport only; 403/404/other-4xx/
parse never retried; `CancellationError` propagates immediately. No raw
`URLSession(configuration:)` outside `AO3Client`/`AO3AuthService` (grep across
tree incl. uncommitted files; other hits are comments only).

Parser safety: parsers are pure (`static func parse…`), throw `AO3Error.parse`
or skip malformed blurbs individually (`parseWorksList:1002-1018`); Area 2
verified no caller mutates local data on parse failure. `parseFandomIndex` is
the deliberate linear scan (BUG-5 fix) — no DOM balloon. T-91's new inbox
form parsers **fail closed**: partial/malformed mass-edit or filter forms
return nil so the UI stays read-only rather than fabricating a write
(`AO3Client+Inbox.swift` diff, `parseInboxBulkForm` guards).

Error distinguishability: `AO3Error.rateLimited(retryAfter:)/.forbidden/
.notFound/.server/.http/.network/.parse/.authenticationRequired` + preserved
`URLError` (offline vs timeout vs cancel) — callers differentiate (e.g.
`CommentsModel.message(for:)`, `isOfflineError`).

Logging: networking/auth files log status descriptions and URLs only — no
cookie values, tokens, response bodies, or user content (keyword grep +
spot-read). Note for Area 5: authenticated-GET URLs (which contain the user's
AO3 username in the path) are logged at `.debug` with `privacy: .public` —
debug-level OSLog is not persisted by default; assess there.

### Findings

**A3-F1 — P2 Should Fix — Author-profile and inbox avatars bypass the paced
AO3 pipeline (and the app's User-Agent identity).**
Files: `kudos-ao3-reader/Features/Authors/AuthorProfileComponents.swift:137`,
`kudos-ao3-reader/Features/Account/AccountInboxViews.swift:190`. Feature:
author profiles, Account›Inbox (iOS+macOS). Repro: open an author profile or
scroll the inbox — each visible row's `AsyncImage(url:)` fires an immediate
GET for its AO3-hosted icon via `URLSession.shared`: unpaced, uncoalesced, and
with the default CFNetwork User-Agent instead of `AO3RequestDefaults.userAgent`
(forking the app's single-UA identity). Expected: the codebase's own precedent
— comment avatars were explicitly migrated to `AO3Client.imageData(at:)`
(paced pipeline, `CommentThreadRow.swift:847`, and the doc comment at
`AO3Client.swift:76-78` states this policy). Actual: two surfaces render the
same class of icons outside the pipeline. Impact: bursts of unpaced,
wrongly-identified requests to AO3-hosted assets; policy/consistency violation
rather than user-visible breakage (a browser rendering the same page also
fetches its icons, and many icons resolve to CDN hosts — hence P2 not P1).
Smallest correction: load both through `AO3Client.shared.imageData(at:)` as
`CommentAvatar` does. Regression test: add a `check-invariants.sh` rule
rejecting `AsyncImage(` in `kudos-ao3-reader/` (mechanical, matches the
existing single-UA rule). Blocks release: no.

### Observations (not findings)

- `WorkUpdateChecker` saves the context per work in its loop (`try? context.
  save()` twice per iteration) — correctness fine; batching noted for Area 8.
- Standing gate unchanged: all write actions (incl. T-91's inbox bulk actions)
  remain never-live-verified against AO3 — construction/fixture-tested only.

### Manual checks remaining (Area-3 scope)

- Live 429 handling can't be ethically provoked — Retry-After honored by code
  + `AO3ClientPolicyTests`; live behavior remains a trust-the-tests item.
- Live-HTML parser drift (fixtures are point-in-time snapshots).

---

## Area 4 — Concurrency and Lifecycle Correctness

Status: **COMPLETE** (2026-07-12). Baseline SHA re-verified (`58e307e`).
Risk-prioritized direct inspection (not an exhaustive enumeration of every
view-local `Task {}`); no subagent.

### Verified (evidence: file:line)

- **Isolation model:** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` +
  `SWIFT_APPROACHABLE_CONCURRENCY = YES` on every configuration
  (`project.pbxproj:493-494, 546-547, 568-569, 589-590`) — unannotated
  SwiftData access is compile-time main-actor-bound; both platforms build
  green (Area 1). `AO3Client` is the deliberate actor exception; commit
  `e918382`'s `nonisolated` demotions are exclusively immutable `Sendable`
  value types (diff-verified) — no mutable state was demoted.
- **Continuations (all sites):** `AO3RequestCoordinator.acquire` — fair FIFO,
  cancellation-aware, take-and-remove on both resume paths, actor-serialized
  (`AO3RequestCoordinator.swift:59-89`). `AO3WebLoginCoordinator.
  hiddenContinuation` — every resume site takes-and-nils on MainActor
  (`:162-164, 277-280, 290-292`); timeout (`startTimeout`→`failHidden`) and
  `cancel()` (also invoked via `onCancel`) cover never-resume; `login()`
  pre-cancels prior attempts. JS-evaluation and `WKHTTPCookieStore`
  continuations wrap single-fire callbacks (`AO3WebLoginCoordinator.swift:
  374-396`, `AO3SessionVault.swift:289-304`). No double/never-resume path found.
- **Detached tasks (all 10 sites):** every one captures only Sendable value
  snapshots (e.g. `LibraryWorkSnapshot`/`CategoryStatsInput` in
  `MediaBrowserView.swift:262-276`; URL/Data values in `WorkImporter.swift:30,
  245`, `WorkTags.swift:90`, `FolderSyncService.swift:219-299`,
  `ReaderView.swift:553`, `FandomCatalog.swift:166,177`); results re-applied on
  MainActor, several behind `Task.isCancelled` checks. No `@Model` crosses an
  actor boundary.
- **Task lifetime/cancellation:** large-list `.refreshable` tasks stored and
  cancelled on tab change via `cancelRefreshOnTabChange` (4 documented
  surfaces: Home/Library section lists, queues, collections). Screen loads use
  `.task(id:)` keyed on context (`AccountView.activationKey`,
  `AccountWorksInlineSection.loadTaskID`, reader `bookLoadToken`) so repeated
  appearances don't duplicate work. Comments stores + cancels its three
  long-lived tasks in `.onDisappear` (`CommentsView.swift:115-119` region).
  Single-flight guards on user-triggered loads (`AccountWorksInlineSection.
  launch()`, `AO3InboxModel`, `AO3WorkActionsModel.isWorking`). Write tasks
  intentionally survive dismissal (never cancel an in-flight POST) and are
  single-flighted (`AO3WorkActionsModel.swift:45-80`).
- **Cancellation not converted to error/retry:** both cancellation shapes
  (`CancellationError`, `URLError(.cancelled)`) break loops silently
  (`WorkMetadataRefresh.swift:36-67`, `CommentsModel.fetchPage`,
  `AccountWorksInlineSection.load`); coordinator wakes cancelled waiters
  without consuming slots.
- **Operation races:** `PersistenceOperationGate` (MainActor under default
  isolation, `PersistenceSync.swift`) serializes migration / backup import /
  folder sync / sweep; sweep additionally re-checked in Area 2 (fully
  synchronous on MainActor). `importEPUB` TOCTOU re-check closes the
  concurrent-acquisition race. Reindex/migration guard `modelContext != nil`
  around every yield.
- **Actor reentrancy:** `pace()` is explicitly designed for reentrancy
  (slot-claiming, not actor serialization) — the historical pitfall is
  structurally addressed.
- **Main-thread pressure:** EPUB unzip/parse, backup blob reads, catalog
  stats, and fandom-index parsing all run detached/off-main (measured
  behaviorally in Area 8).
- **Cross-platform:** BGTask registration iOS-only; security-scoped bookmark
  options split per platform (`FolderSyncService.swift:361-395`); macOS build
  green. macOS legacy reader internals (`ReaderController.swift`) remain the
  least-audited region (standing ARCHITECTURE_MAP "unknown") — residual risk,
  not a finding.

### Findings

None. No reachable race, leak, deadlock, hang, double-resume, or
invalid-actor SwiftData access was found in the inspected high-risk paths.

### Tooling notes / manual checks remaining

- Thread Sanitizer: **NOT RUN** — justified: default-MainActor isolation +
  approachable-concurrency Sendable checking give compile-time coverage for
  the dominant main-actor code; the test suite (serialized) is green. A TSan
  pass remains worthwhile before a store-grade release; record in Area 10.
- Instruments leak pass (repeated reader / comments / profile open-close):
  manual device gate — code-level lifecycle (saves on `onDisappear`,
  `.task(id:)` teardown) verified only.
- macOS `ReaderController` deep audit: deferred residual (Area 7 exercises its
  behavior surface).

---

## Area 5 — Authentication, Security, and Privacy

Status: **COMPLETE** (2026-07-12). Baseline SHA re-verified (`58e307e`);
recorded T-91 dirty set unchanged. Audit only: no production files changed and
no live AO3 traffic generated. Direct inspection covered authentication,
cookies, Keychain/file vaults, CSRF/write construction, logging, privacy claims,
biometric gating, repository hygiene, and trust configuration. One bounded
subagent inspected only archive/import/output and external-URL boundaries; all
accepted results below were re-read against the live files.

Two local, synthetic probes supplied behavioral evidence without real
credentials or external traffic: `URLSessionConfiguration.default` reported
`httpShouldSetCookies=true` and the same object as
`HTTPCookieStorage.shared`; a localhost capture then observed a synthetic
shared cookie automatically attached. Separately,
`URL.appendingPathComponent("../../escape").standardizedFileURL` resolved
outside its base, confirming the MiniZip path is exploitable rather than a
string-only concern.

### Controls verified (evidence: file:line, current tree)

- **Password/credential lifetime:** the password exists only in SwiftUI state
  and the coordinator's short-lived tuples; every success/failure/cancel path
  clears coordinator copies (`AO3LoginView.swift:12-13, 80-90, 201-211`;
  `AO3WebLoginCoordinator.swift:85-96, 154-170, 253-292`). JavaScript insertion
  uses JSON encoding, not string interpolation (`:316-336, 402-406`). No
  password, cookie, token, response body, or private HTML is intentionally
  persisted in backups or diagnostics.
- **Secure store:** signed builds use one device-only Keychain item with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; a container file is used
  only for `errSecMissingEntitlement`, with iOS file protection and atomic
  writes (`AO3SessionVault.swift:66-125, 128-180, 188-237`). Backup/folder-sync
  schemas contain no AO3 session or password (`KudosBackup.swift:38-108,
  926-965`; UI claim at `SettingsView.swift:881-884`). Signed-device behavior
  remains a manual gate.
- **Cookie and request scoping:** stored cookies validate expiry, path, secure
  scheme, and exact AO3-domain suffix; authenticated requests reject non-HTTPS
  and non-AO3 hosts and explicitly disable ambient cookie handling
  (`AO3Session.swift:44-83, 99-112`; `AO3AuthService.swift:209-214, 468-485`;
  `AO3Client.swift:356-381, 395-405`). Login success is accepted only on a
  trusted AO3 URL with logged-in markup, never from cookie presence alone
  (`AO3WebLoginCoordinator.swift:181-214, 253-265`). See A5-F1 for the separate
  anonymous-session violation.
- **CSRF/write boundary:** every write begins from an authenticated AO3 page or
  parsed AO3 form, sends the current authenticity token, and reaches the one
  trusted-host-enforcing `writeRequest`; bodies/tokens are never logged
  (`AO3WriteActions.swift:183-210`; all 12 `submitWrite` call sites enumerated
  in Area 3). There is no custom TLS challenge delegate, trust bypass,
  arbitrary-load exception, debug authentication bypass, or disabled
  certificate validation (repo-wide grep + direct WebKit/URLSession read).
- **Logout's normal path:** local session, username hint, WebKit AO3 cookies,
  and shared HTTP AO3 cookies are all targeted (`AO3AuthService.swift:400-416`;
  `AO3SessionVault.swift:268-279`). A successful-delete mock test covers that
  path (`AO3AuthTests.swift:300-321`); see A5-F4 for its untested failure path.
- **Input-path protections that do exist:** stored EPUB asset identifiers are
  basename-only `.epub` values (`Storage.swift:10-24`); user imports require a
  file URL, `.epub`, readable container/OPF/spine, and staged replacement
  (`WorkImporter.swift:239-247, 518-543`); backup font names reject separators
  (`KudosBackup.swift:75-83, 162-167`). No tracked private key/API-token pattern
  or embedded test credential was found.
- **Privacy claims:** no analytics/tracking SDK or background telemetry exists;
  network code is AO3-facing and user-invoked website/support links are visible.
  Mature reveal state is in-memory only (`MatureContent.swift:31-59`). Runtime
  claims accurately exclude sessions/passwords from backups, subject to the
  log and biometric findings below.

### Findings

**A5-F1 — P1 Must Fix — The nominally anonymous AO3 client automatically
inherits the signed-in cookie jar, defeating account isolation.**
Files: `kudos-ao3-reader/Services/AO3Client.swift:23-30, 91-115` and
`kudos-ao3-reader/Services/AO3SessionVault.swift:255-265`. Affected feature:
all native public/search/tag/metadata/autocomplete reads on iOS and macOS, and
account switches. Repro: sign in; `AO3CookieBridge.install` writes AO3 session
cookies to `HTTPCookieStorage.shared`; `AO3Client`'s
`URLSessionConfiguration.default` has that same store with automatic cookie
handling enabled, so its supposedly anonymous `session.data(from:)` attaches
the account cookies. Concurrent identical reads are then coalesced by URL only,
so a read begun under account A can satisfy the same URL requested after a
logout/account-B transition. Expected: anonymous reads carry no session and
only explicit authenticated requests are scoped/coalesced by cookie. Actual:
the shared jar silently authenticates the URL-only pipeline. Impact: account
state and personalized/restricted AO3 responses can cross anonymous or changed
account contexts; this directly invalidates Area 3's anonymous/auth separation
verdict and the `authCoalescer` comment's account-switch guarantee. Supporting
evidence: live code plus the local synthetic URLSession capture described
above. Smallest safe correction: give `AO3Client` a cookie-less session
(`httpCookieStorage=nil`, accept policy never/automatic handling off) and stop
installing into the shared HTTP jar unless a proven isolated consumer needs it;
keep WebKit cookies and explicit authenticated headers unchanged. Regression
test: a synthetic cookie in the shared store must not appear on an anonymous
request, while `authenticatedRequest` still carries it; a URL-only in-flight
read must never bridge two auth scopes. Blocks release: **YES**.

**A5-F2 — P1 Must Fix — MiniZip trusts archive-controlled paths and sizes,
allowing sandbox path traversal plus malformed-archive crashes/exhaustion.**
Files: `kudos-ao3-reader/Reading/MiniZip.swift:21-51, 65-107`, reached by
`EPUB.swift:220-224, 235-258`, `WorkImporter.swift:239-247`, and the macOS
reader at `ReaderView.swift:548-555`. Affected feature: selected user EPUBs on
both platforms (bounds/allocation crash); extraction and arbitrary writes in
the macOS legacy reader. Repro: import an otherwise valid EPUB whose central
directory also contains `../../../Application Support/<known file>`; package
inspection reads only the expected container/OPF and accepts it, then macOS
open appends the raw name and writes outside `Caches/Reader/<UUID>`. Separately,
a 46-byte central record can declare a 65,535-byte name beyond the buffer and
trap in `subdata`, or a tiny compressed entry can declare a multi-gigabyte
`uncompressedSize`, which is allocated without a quota. Expected: malformed or
oversized archives fail with a typed error and every output stays below a fresh
reader root. Actual: entry names, record ranges, output sizes, compression
ratios, and cumulative extraction are trusted. Impact: a chosen EPUB can crash
the app, exhaust memory/disk, or overwrite known files inside the app sandbox,
including library/session-support data. Supporting evidence: direct read and
the standardized-path probe above; existing `EPUBTests` cover only a normal
fixture and non-ZIP bytes (`EPUBTests.swift:23-34, 121-145`). Smallest safe
correction: add checked arithmetic, complete record/method validation, strict
per-entry/cumulative size and ratio limits, and standardized-root containment;
extract into a fresh staging directory before use. Regression tests: valid
EPUB plus traversal entry must throw without changing an outside sentinel;
truncated-name and oversized-output records must fail before subdata/allocation.
Blocks release: **YES** (macOS arbitrary-write path; the crash boundary should
land in the same hardening change).

**A5-F3 — P1 Must Fix — Backup restore accepts arbitrary bytes as an EPUB and
atomically overwrites a valid local asset.**
Files: `kudos-ao3-reader/Services/KudosBackup.swift:53-83, 1048-1050`.
Affected feature: manual backup restore and automatic folder-sync restore on
iOS/macOS. Repro: create a structurally valid package/manifest matching an
existing work UUID but put junk or truncated bytes at
`Works/<UUID>.epub`; restore writes those bytes over `work.fileURL`, marks
`hasEPUB=true`, and reports success. Expected: invalid incoming assets are
rejected before any restore mutation and the valid local EPUB remains intact.
Actual: only package shape/version/name are checked; EPUB contents are not.
Impact: destructive loss of a potentially non-redownloadable user-imported or
unavailable work via an imported or synced package. Evidence: current tests
actually use plain strings such as `"restored-epub"` as assets and expect them
to replace the file (`KudosBackupTests.swift:134-135, 188-189`), proving the
validation gap. This is distinct from A2-F2's stale-but-valid blob overwrite;
that path remains P3, while corrupt/untrusted input is release-blocking.
Smallest safe correction: preflight every incoming EPUB with the hardened
validator and stage all valid assets before mutating models or files; reject or
skip a corrupt asset without touching an existing file. Regression test:
invalid incoming bytes matched to a work with a valid EPUB must leave the
original bytes/state unchanged; update positive backup tests to use a real
minimal EPUB. Blocks release: **YES**.

**A5-F4 — P1 Must Fix — Keychain deletion failures are suppressed while the UI
claims the AO3 session was removed.**
Files: `kudos-ao3-reader/Services/AO3AuthService.swift:400-416, 653-658` and
`kudos-ao3-reader/Services/AO3SessionVault.swift:112-117, 239-248`; user-facing
entry at `PrivacyDataView.swift:36-52`. Affected feature: Log Out / Remove AO3
Session on both platforms. Repro: make `SecItemDelete` return a non-not-found,
non-missing-entitlement error (for example a locked/unavailable macOS
Keychain). `CascadingAO3SessionVault.delete` throws before attempting its file
store; `logout` logs the error, clears current cookies, nevertheless sets
`"Logged out of AO3."`; the retained Keychain item can be loaded and restore
the session next launch. Expiry cleanup silently uses `try?` and has the same
durability problem. Expected: removal clears every durable store or visibly
remains pending/failed and can never restore the stale session. Actual: success
is unconditional despite a known failed delete. Impact: the explicit privacy
control can leave reusable credentials behind and sign the user back in after
relaunch. Supporting evidence: complete call path above; the only logout test
uses an infallible memory vault (`AO3AuthTests.swift:300-321, 500-527`).
Smallest safe correction: always attempt both vault deletions, persist a
non-secret removal-pending marker before clearing UI state, and refuse restore
while it remains; surface a retryable error and clear the marker only after all
stores are purged. Regression tests: a throwing delete must not produce the
success notice or permit later restore, and the file-vault delete must still be
attempted when Keychain deletion throws. Blocks release: **YES**.

**A5-F5 — P2 Should Fix — Production logs explicitly publish reading/search
identifiers and local paths.**
Files: `AO3Client.swift:109, 361, 398, 575-577`,
`WorkMetadataRefresh.swift:62-65`, `DownloadQueue.swift:95-106`,
`WorkImporter.swift:55-60, 101-106, 541-546`, and reader error logs. Affected
feature: local diagnostics on both platforms. Repro: search a sensitive term,
open an authenticated account list, download/refresh a work, or trigger a file
error; full URLs (including query text/usernames), exact AO3 work IDs, and
localized file errors are interpolated as `privacy: .public` (numeric work IDs
are also public by OSLog convention). Expected: diagnostics exclude or redact
user content, account paths, reading identity, and filesystem paths. Actual:
those values are readable in applicable unified-log/diagnostic captures;
`.debug` URLs are not normally persisted, but info/notice work IDs are, so the
risk is not debug-only. Impact: a Console/sysdiagnose shared for support can
reveal account names, searches, exact works, or machine paths; no cookies,
CSRF values, passwords, or HTML bodies were found. Smallest safe correction:
log operation/category/status only, or mark sensitive interpolation private
and sanitize `localizedDescription` before public logging. Regression test:
add an invariant rejecting public full URLs/work IDs and public raw filesystem
errors in production logging. Blocks release: no.

**A5-F6 — P2 Should Fix — The enabled Face ID reveal control fails open when
device-owner authentication is unavailable.**
Files: `kudos-ao3-reader/Features/Privacy/MatureContent.swift:85-100`, setting
at `SettingsView.swift:345-367`, public claim at `README.md:23`. Affected
feature: Mature/Explicit privacy reveal on iOS/macOS. Repro: enable "Require
Face ID to reveal" on a device/simulator with no evaluable owner-auth policy
(or restore that backed-up setting onto one), then reveal a work; the failed
`canEvaluatePolicy` guard calls `onSuccess()` immediately. Expected: an enabled
authentication requirement either remains closed or cannot be enabled when
the platform has no credential. Actual: one tap reveals with no challenge.
Impact: the promised local privacy gate is bypassed precisely when the system
cannot authenticate. Supporting evidence: direct branch at `:91-94`; no
authenticator abstraction or tests exist. Smallest safe correction: fail
closed and explain why reveal is unavailable, while disabling/explaining the
setting when device-owner authentication cannot be configured. Regression
test: inject an authenticator and assert unavailable/failed/cancelled outcomes
never invoke reveal; only success does. Blocks release: no.

**A5-F7 — P2 Should Fix — A lookalike AO3 hostname is trusted for native tag
routing and rendered under Kudos chrome.**
Files: `kudos-ao3-reader/App/AppRouter.swift:126-141` and
`Features/Browse/NativeBrowseView.swift:680-684`; reader call sites at
`ReaderView.swift:517-520` and `ReaderReadium/ReadiumReaderView.swift:871-875`.
Affected feature: HTTP(S) links embedded in imported EPUBs/author content on
iOS/macOS. Repro: activate
`https://archiveofourown.org.evil.test/tags/Foo/works`; the router's
`host.contains("archiveofourown.org")` check creates a native tag request, which
fetches and parses the attacker's URL. Expected: only HTTPS exact AO3 or its
true subdomains receive native trust; every lookalike remains visibly external.
Actual: attacker HTML is shown as a native works screen without the external
host chrome. Impact: origin-confusion/phishing surface (this route is
anonymous; no off-domain cookie disclosure was found). Supporting evidence:
strict reusable checks already exist at `AO3AuthService.swift:209-214` and
`AO3AuthorModels.swift:110-115`, making this `contains` call the outlier.
Smallest safe correction: reuse a single exact/dot-suffix HTTPS AO3-origin
predicate before creating any native route. Regression test:
`archiveofourown.org.evil.test`, `notarchiveofourown.org`, and HTTP must fall
back to the visible browser; real HTTPS AO3 must still route natively. Blocks
release: no.

**A5-F8 — P3 Follow-up — A tracked handoff publishes a personal absolute path
and simulator identifier.**
File: `plan_context.md:7, 12-17`. Affected surface: public repository hygiene.
Repro: clone/read the tracked file; it names `/Users/cidy02/...` and a specific
simulator UDID while pointing collaborators to an unavailable local plan.
Expected: tracked operational docs are portable and machine-neutral. Actual:
machine-specific identifiers are committed. Impact: minor workstation
fingerprinting and stale/non-reproducible guidance; no credential or secret was
found. Smallest safe correction: remove/generalize the path and UDID, and keep
local live-handoff state ignored or in portable repo docs. Regression test:
extend repository hygiene checks to reject `/Users/<name>/`, simulator UDIDs,
and equivalent home-directory paths in tracked files. Blocks release: no.

### Observations (not findings)

- Area 1's two Debug `DEVELOPMENT_TEAM` values remain the already-recorded
  A1-F2; this area does not duplicate them. Secret-pattern and machine-path
  scans otherwise found no tracked keys, tokens, credential files, or personal
  paths beyond A5-F8. The recorded untracked `.idea/`, `android/`, and dirty
  T-91/ledger files remain the A1-F1 frozen-candidate problem for Area 10.
- `AO3CookieBridge.clearAO3Cookies` removes only AO3-domain cookies from both
  WebKit and the shared HTTP store; unrelated website state is preserved. The
  hidden login coordinator checks trust before inspecting/injecting and clears
  credential tuples on every terminal path.
- File-vault fallback is intentionally restricted to missing-entitlement
  development builds; iOS uses atomic writes plus protection until first user
  authentication. Production must still prove that signed builds never fall
  back (manual gate).
- Backup package child lookup is UUID-exact for EPUBs and basename-checked for
  fonts, so no package-filename traversal was found. A5-F3 concerns the
  unchecked contents of an otherwise safely named child.

### Manual checks remaining (Area-5 scope)

- Signed physical-device Keychain persistence across relaunch/update, plus
  successful and forced-failure Remove AO3 Session verification: **NOT RUN**.
- Real authenticated hidden login, visible fallback/challenge, logout,
  expiration, and rapid account A→B transition: **NOT RUN** (no audit
  credentials/live-write authorization used).
- Face ID/Touch ID/passcode success, cancel, lockout, and unavailable-policy
  matrix on hardware: **NOT RUN**.
- Post-fix malicious EPUB fixtures on macOS, structured MiniZip fuzzing, and
  confirmation of Readium iOS archive containment/resource limits: **NOT RUN**.

---

## Area 6 — Core Functional Regression Matrix

Status: **COMPLETE** (2026-07-12). Baseline SHA re-verified (`58e307e`);
recorded T-91 dirty set unchanged. Audit only: no production files changed, no
live AO3 traffic or writes generated, and no unchanged full suite repeated.
Area 1's 363/363 green result applies to this exact working artifact. Targeted
verification below means a direct execution-path trace against the current tree
and its existing tests. One bounded subagent inspected journeys 13–18; every
accepted finding was re-read against the live files.

Detailed reader internals remain reserved for Area 7. Persistence, networking,
and security findings are referenced rather than duplicated.

### Regression matrix

| # | Journey / primary implementation entry | Automated coverage | Missing coverage + targeted verification result | Required manual/live check | Release risk |
|---|---|---|---|---|---|
| 1 | **First launch/disclaimer** — `ContentView` onboarding presentation; `WelcomeView`; `SyncFolderOnboardingView` | No UI/onboarding automation. | State trace confirmed `hasCompletedOnboarding` gates the disclaimer and sync-folder step; no new defect found. Relaunch/version-transition behavior is unpinned. | Fresh install, complete both steps, relaunch, and repeat on iOS/macOS. | **Low**, manual gate. |
| 2 | **Signed-out Home, Library, Browse/Search, empty states** — `HomeView`, `LibraryView`, `NativeBrowseView`, `SearchView` | Auth-state tests plus parser/filter/search unit coverage; no end-to-end tab UI test. | Trace confirmed Subscriptions suppresses its request when signed out, Library stays local, and Browse/Search retain public/local paths; no new defect found. Empty/loading/error rendering is not snapshot/UI tested. | Signed-out cold launch through every tab with both empty and populated local data. | **Low–moderate**, UI/manual. |
| 3 | **Login/logout/session restoration** — `AO3LoginView`, `AO3AuthService`, `AO3SessionVault` | `AO3AuthTests` covers logged-in/out parsing, restore/verification, unreachable AO3, and successful logout. | Normal state transitions traced; failure-path gaps remain. **A5-F1** (ambient anonymous cookies) and **A5-F4** (failed durable delete still reports logout) already block release. | Signed-device login, challenge/fallback, relaunch restore, offline restore, logout, and forced-delete failure. | **High — blocked by A5-F1/A5-F4.** |
| 4 | **Home and Library loading** — SwiftData queries in `HomeView`/`LibraryView`; subscription/marked-for-later loaders | `LibrarySectionKindTests`, `CanonicalWorkMergeTests`, filter/identity tests. | Trace found existing content retained on ordinary subscription failure and local Library independent of network; no new defect. Full loading/refresh/empty UI and rapid tab-change behavior lack UI automation. | Populated/empty, pull-to-refresh, offline refresh, sign-in transition, and large-library pass. | **Moderate**, manual state coverage. |
| 5 | **Privacy Blur/Hide** — `PrivacyGate`, `SensitiveWorkRow`, `SensitiveWorkCoverCard`, `MatureRevealToggle` | Predicate behavior receives indirect section tests; no rendered privacy-mode or authenticator tests. | Call paths consistently wrap protected work surfaces; no new functional defect. **A5-F6** is the existing biometric fail-open. | Blur and Hide on every Home/Library/Account/search-adjacent surface; reveal success/cancel/failure/unavailable on hardware. | **Moderate; A5-F6 should fix.** |
| 6 | **Privacy controls only when relevant** — `PrivacyGate.hasVisibleMatureWorks` / `shouldShowMatureRevealControl` and per-screen visible-entry scopes | No direct unit/UI coverage. | All call sites traced. Account now scopes relevance to the current visible list rather than the whole Library; no new defect. | Mixed ratings, filters that remove the last adult work, page/tab changes, Blur/Hide/off. | **Low**, manual regression risk. |
| 7 | **Library filters, clear, selection, reorder** — `LibraryFilters`, `LibraryFilterPanel`, `LibraryView`, `ReadingQueues` | `LibraryFiltersTests` covers predicates/sorts/clear inputs; `LibrarySectionKindTests`; `ReadingQueueTests` covers service ordering only. | Filter logic traced with no new defect. Selection presentation is untested. Current `TASKS.md` still records owner-confirmed broken Reading Queue drag reorder; **A6-F1**. | Filter/clear/select across list modes; drag first/middle/last works and relaunch in detailed/compact on both platforms. | **Moderate — A6-F1.** |
| 8 | **Multi-select download/save/queue/collection** — `WorkBulkActionBar`; `RemoteWorkBulkActions`; selection surfaces in Home/Library/Browse/Search/Author | Series batch behavior has partial-failure tests; no direct shared bulk-helper or selection UI tests. | Remote resolution is sequential and reports ordinary partial failures, but cancellation can be ignored (**A6-F4**). Local Save for Later starts one untracked preservation task per work and has no aggregate outcome (**A6-F2**). | Inject one failure, cancellation, unavailable work, and dismissal in every selection surface; verify result counts and destination-sheet behavior. | **Moderate — A6-F2/A6-F4.** |
| 9 | **Work download and EPUB import** — `AO3Client.downloadEPUB`, `WorkImporter.importEPUB/importUserEPUB`, Settings file importer | `EPUBTests`, `PreservedWorkTests`, identity/search-index tests cover normal and some invalid inputs. | Normal staging/identity/index paths traced. No new functional finding; **A5-F2** unsafe MiniZip and **A5-F3** unchecked backup EPUB replacement already block the relevant import/restore boundary. | File importer/iCloud materialization, duplicate import, unavailable AO3 download, cancellation, and post-fix hostile EPUBs. | **High — blocked by A5-F2/A5-F3.** |
| 10 | **Work Detail consistency from all entries** — `WorkDetailView.Source`, `LocalWorkDestinationView`, card navigation across Home/Library/Browse/Search/Account/Author/Series | Underlying identity, action, preservation, and parser tests; no Work Detail UI/navigation test. | Route inventory found saved and remote cards converge on the canonical detail view (with intentional local reader-first destinations); no divergent implementation or new defect found. | Open the same local/remote work from every entry and compare actions, metadata, privacy, back navigation, and reader transition. | **Low–moderate**, manual parity gate. |
| 11 | **Collections and Reading Queue** — `Collections`, `ReadingQueues`, `ReadingQueueService` | `CollectionWorkPickerTests`, `ReadingQueueTests`, `PreservedWorkTests`, backup/folder-sync tests. | Create/add/remove/delete service paths traced without a new defect. Reorder remains broken at the UI boundary (**A6-F1**); collection ordering is intentionally unsupported. | Create/rename/delete collection/queue; add/remove/revive; reorder and relaunch; protect queue-only EPUBs. | **Moderate — A6-F1.** |
| 12 | **Local search/index/reindex** — `SearchView`, `WorkSearchIndex`, launch/import/restore reindex call sites | `WorkSearchIndexTests` covers normalization, diacritics, fields, AND matching, reindex, launch-once, and backup exclude/restore. | Index lifecycle and navigation paths traced; no new defect. Search-result UI, interrupted reindex, and very large libraries lack integration coverage. | Import/edit/delete/restore then search before/after relaunch; clear/back navigation; large-index timing. | **Low–moderate**, strong logic coverage. |
| 13 | **Account lists and Preferences** — `AccountView`; `AccountWorksInlineSection`; `AO3AccountWorksList`; `AO3PreferencesView`; `AO3PreferencesActions` | `AO3AccountListCountsTests` covers scoped counts/cache; `AO3PreferencesParseTests` covers form/help parsing and generated parameters. | Root/list UI, pagination races, refresh failure, and save responses lack integration tests. Trace found full-list loads can finish out of order and replace retained rows with an error (**A6-F3**). | Every signed-in list, filters/pagination/offline refresh, preference edit/save/reload, and current T-91 Inbox actions. | **Moderate — A6-F3; T-91 still unfrozen.** |
| 14 | **Author profiles/name routing** — `AO3AuthorRoute`, `AppRouter`, `AO3AuthorNavigationModifier`, `AuthorProfileView`, `AO3AuthorProfileModel` | Extensive identity/parser/state/router tests cover users, pseuds, coauthors, anonymous/orphan names, cancellation, pagination, and auth-scoped cache. | No end-to-end navigation-stack or live subscribe/mute/block coverage. No new defect. Retain **A5-F7** lookalike-host routing and **A3-F1** avatar-pipeline findings. | Coauthor/pseud routes from each feature; lazy tabs; signed-in subscribe/mute/block/undo. | **Moderate**, prior findings + live writes. |
| 15 | **Comments load/thread/sort/chapter/post/reply/edit/delete** — `CommentsView`, `CommentsModel`, `AO3Client+Comments`, `AO3CommentActions`, `CommentSubmissionGuard` | `AO3CommentsParseTests` covers threading/tombstones/actions/pagination/order/chapters/timestamps/verification; `CommentSubmissionTests` covers duplicate/ambiguous guard and drafts; reader-section mapping tests. | No mocked end-to-end model/write lifecycle or edit/delete response tests. Trace confirmed the already-recorded newest-first new-page miss (**A6-F5**); no additional defect. | Signed-in multi-page post/reply/edit/delete; ambiguous timeout + reverify; chapter switching; large/deleted threads. | **Moderate–high manual gate; A6-F5 is low.** |
| 16 | **Deleted/restricted/unavailable works** — `WorkTags.refreshFromAO3`, `WorkMetadataRefresh`, `SavedWork.ao3Unavailable`, `PreservedWorkService`, queue preservation | `PreservedWorkTests` covers warning/revival; `ReadingQueueTests` covers unavailable/mixed-failure series; policy tests pin 404 no-retry. | No direct 404→unavailable/preserve-EPUB test or 403/restricted/offline state test. No new defect; **A5-F1** affects restricted/account response isolation. | Retained EPUB after deletion, signed-out/in restricted work, 403/404/offline refresh, delete warning. | **Moderate; A5-F1 blocks release.** |
| 17 | **Offline launch and Library** — `MyApp` model container; `ContentView` launch restoration/migration/index; `AO3AuthService.restoreSession`; local `LibraryView` | Offline-auth preservation, persistence sync, EPUB, section, progress, and reader-preparation tests. | Static trace found no new defect. No full cold-launch offline UI or signed-device Keychain test. Prior **A5-F1/A5-F4** and **A5-F3** govern session/restore integrity. | Airplane-mode cold launch with restored session and saved EPUBs; filter/open/read/relaunch on signed hardware. | **High until prior release blockers/device gate close.** |
| 18 | **Cancellation and partial failure** — `WorkMetadataRefresh`; `RemoteWorkBulkActions`; `ReadingQueueService`; author/account load models | Coordinator waiter cancellation, superseded author loads, and series partial-result accounting are tested. | No shared bulk-helper, metadata-refresh cancellation, or local bulk-preservation tests. Trace found all-local remote batches can mutate after cancellation (**A6-F4**) and local Save for Later is untracked (**A6-F2**). | Cancel/dismiss every batch and refresh mid-flight; inject one failure among successes; verify no post-dismiss UI/mutation and accurate summaries. | **Moderate — A6-F2/A6-F4.** |

### Findings

**A6-F1 — P2 Should Fix — Reading Queue drag-to-reorder remains
owner-confirmed broken despite its visible Reorder affordance.**
Files: `kudos-ao3-reader/Features/Library/ReadingQueues.swift:290-430` and
`kudos-ao3-reader/Services/ReadingQueueService.swift` (`reorder`); tracking
evidence at `TASKS.md:113`. Affected feature: detailed and compact Reading
Queue lists on iOS/iPadOS/macOS. Repro status: the current task registry records
that Branch E's drag reorder was reported still broken by the owner and pinned
untouched; current automation proves only service-level order mutation, not the
`List.onMove` or grid drag/drop bridge. Expected: entering Reorder and dragging
a handle moves the work and persists its membership order. Actual: the owner
reports that the advertised gesture does not reorder. Impact: a visible library
organizing control is nonfunctional, but no data is destroyed. Smallest safe
correction: reproduce detailed and compact independently, repair the failing
gesture/index bridge without changing the membership model, and retain the
service implementation. Regression coverage: extract/test the drop-delegate
transition plus UI automation for `List.onMove`; manually verify first/middle/
last moves survive relaunch in both layouts/platforms. Blocks release: no.

**A6-F2 — P2 Should Fix — Local bulk “Save for Later” fans out one untracked
preservation job per selected work and provides no aggregate failure result.**
Files: `kudos-ao3-reader/UIComponents/WorkBulkActionBar.swift:152-169` and
`kudos-ao3-reader/Services/ReadingQueueService.swift:228-260, 287-347`.
Affected feature: local-work multi-select actions exposed from Home/Library
surfaces on their supported platforms. Repro: select many local AO3 works that
do not yet have EPUBs and choose Save for Later. The bar loops over the models
and creates an independent `Task` for every item; each task immediately adds
membership and may download/backfill metadata, while `addAndPreserve` suppresses
the thrown preservation error. Expected: one tracked, cancellable/sequential
batch (or the shared download queue) with honest completed/failed/cancelled
accounting. Actual: all jobs outlive the initiating control, can overlap after
pacing, and a partial failure has no batch result. Impact: unexpected continued
work/request fanout and no reliable user-level outcome for a core batch action;
queue membership itself is intentionally retained. Smallest safe correction:
route the loop through one owned sequential task/shared queue and return a
summary while preserving failed membership state. Regression test: injected
preserver proves max concurrency one, cancellation stops later items, and mixed
results are counted. Blocks release: no.

**A6-F3 — P2 Should Fix — Full Account lists have racing pagination and hide
retained rows after a refresh failure.**
File: `kudos-ao3-reader/Features/Bookmarks/AO3AccountWorksList.swift:223-249,
305-370`. Affected feature: refined/full Account lists on iOS/iPadOS/macOS.
Repro: rapidly select two different pages whose requests complete out of order;
each callback creates an independent untracked `Task`, and each `load` writes
`works/currentPage` unconditionally, so the older completion can win. Or load a
page, go offline, and pull to refresh: the existing `works` remain in memory,
but `.failed` replaces them with a full-screen error. Expected: last navigation
intent wins and failed refresh leaves the successful page visible with an
inline error. Actual: stale page content can overwrite the requested page, and
a transient refresh failure hides all retained rows. Impact: inconsistent
navigation/temporary loss of access, not durable loss. Smallest safe correction:
own one load task and cancel/token-gate superseded results; when rows exist,
retain loaded presentation and expose a non-destructive refresh error.
Regression tests: delayed injected loaders prove last-request-wins, and a
loaded-page→offline-refresh case proves rows remain visible. Blocks release: no.

**A6-F4 — P2 Should Fix — Cancelling a remote-work batch does not stop local
fast-path mutations or destination presentation.**
Files: `kudos-ao3-reader/Services/RemoteWorkBulkActions.swift:13-59` and
`kudos-ao3-reader/Services/ReadingQueueService.swift:581-608`; view-owned task
cancellation is used by Browse/Search/Author selection surfaces. Repro: select
summaries whose local twins already exist, start Save/Add to Collection/Add to
Queue, then leave the view. `batchTask.cancel()` sets cancellation, but neither
helper checks it at entry/loop boundaries/before `perform`; `resolveLocalWork`
can return synchronously for every item, so no suspension throws and the final
mutation or sheet presentation still occurs. The preserved-work Save for Later
fast path has the same gap. Expected: dismissal cancellation prevents all later
items and final presentation. Actual: an all-local or partly-local cancelled
batch can finish after the user leaves. Impact: unintended saved/queue/
collection changes and post-dismiss state. Smallest safe correction: call
`Task.checkCancellation()` before every item and immediately before the final
callback (and in the Save for Later loop), retaining already-completed-item
accounting. Regression test: pre- and mid-cancelled all-local batches never
invoke the callback or mutate later items. Blocks release: no.

**A6-F5 — P3 Follow-up — A successful newest-first comment post can miss a
newly-created last page until manual refresh.**
Files: `kudos-ao3-reader/Features/Comments/CommentsModel.swift:142-157,
280-290, 401-410`; existing tracker: `TASKS.md:195` (`BUG-6`). Affected
feature: top-level comment posting while displaying newest first on a work whose
comment count crosses AO3's page boundary. Repro: with cached page 1 reporting N
pages, post the comment that creates page N+1. `finishIfSucceeded` calls
`load(forceRefresh: true)`, but `load` still accepts `knownTotalPages` from the
cached page-1 entry and refreshes page N rather than refetching page 1/N+1. The
post succeeds but is absent until a later manual refresh discovers the new
count. Expected: successful forced refresh displays the just-posted comment.
Actual: every page-boundary top-level post can look lost. Impact: confusing
state, but no duplicate or data loss; the submission guard remains intact.
Smallest safe correction: when `forceRefresh` and newest-first are both true,
bypass cached page-count sizing and fetch page 1 before the new last page.
Regression test: seed a stale N-page cache, return N+1 on forced page 1, and
assert page N+1 is loaded. Blocks release: no.

### Observations (not findings)

- No crash, destructive library action, inaccessible primary tab, or broken
  Work Detail route was found in the targeted traces. The release remains
  blocked by Area 5's four P1 findings and unfrozen-candidate A1-F1, not by a new
  Area 6 issue.
- The current uncommitted T-91 Inbox refinement has parser/fixture coverage and
  passed Area 1's exact-artifact suite, but its live AO3 action semantics and UI
  remain part of the Account manual gate; this audit did not treat unfinished
  branch state as a separate functional defect.
- Remote batch ordinary-failure behavior is deliberately sequential and honest;
  A6-F4 is specifically the no-suspension cancellation fast path. Similarly,
  A6-F2 concerns the older local-model bulk bar, not the remote helper.

### Manual checks remaining (Area-6 scope)

- Fresh-install onboarding plus the complete signed-out/populated/empty tab
  matrix on iOS and macOS: **NOT RUN**.
- Signed-device login/restore/logout; Account lists/preferences/T-91 Inbox;
  restricted/deleted works; offline cold launch and local-library use:
  **NOT RUN**.
- Privacy Blur/Hide/relevance and biometric outcomes across every work surface:
  **NOT RUN**.
- Reading Queue reorder in detailed/compact; all local/remote multi-select
  actions with injected failure/cancellation; same-work Work Detail parity from
  every entry: **NOT RUN**.
- Live signed-in comment post/reply/edit/delete on a multi-page work, ambiguous
  verification, and page-boundary newest-first refresh: **NOT RUN**.

---

## Area 7 — Reader and EPUB Behavior

Status: **COMPLETE** (2026-07-12). Baseline SHA re-verified (`58e307e`);
recorded T-91 dirty set unchanged. Audit only: no production files changed and
no EPUB was downloaded from AO3. The iOS/Readium implementation, shared section
normalization/progress model, legacy EPUB parsing, and macOS WKWebView reader
were inspected separately. One bounded subagent covered only the macOS legacy
reader; all accepted findings were re-read against the live files.

Targeted verification ran only the five relevant iOS suites on the canonical
iPhone 17 / iOS 26.5 simulator: **58/58 tests passed** (`EPUBTests` 11,
`ReaderSectionTests` 23, `ReaderThemeTests` 6, `ReadiumReaderTests` 4,
`SavedWorkProgressTests` 14; xcresult `Test-AO3_App_OpenSource-
2026.07.12_18-31-46--0400.xcresult`). This includes the bundled local
`sample.epub` and the 104-spine synthetic AO3 section shape; it does not create
an `EPUBNavigatorViewController` or exercise a macOS `WKWebView`. The test host
restored the simulator's existing session and logged its normal four-work update
check during launch, so the run was not fully network-isolated; no reader test
requested an AO3 download or write and no live result is used as reader evidence.

Two local probes supported macOS findings without changing the tree: Foundation
resolved `Chapter%201.xhtml` through `appendingPathComponent` as the literal path
`Chapter%201.xhtml` / URL `Chapter%25201.xhtml`; and the matching SwiftUI
`@State`→owned callback→captured view ownership pattern retained its controller
after scope exit. The resolved Readium 3.9.0 source was also inspected: its
viewport tests and implementation establish continuous `totalProgression` and
an exact **1.0 only at the end of the final resource**, making A7-F1 a concrete
early-finish path rather than a rounding hypothesis.

### Acceptance matrix

| Requirement | Automated / code-verifiable result | Missing human or fixture check | Risk |
|---|---|---|---|
| Imported and AO3-downloaded EPUBs open | Bundled EPUB import, inspection, extraction, NCX, and dedup tests pass; both acquisition paths converge on `SavedWork.fileURL`. iOS opens through Readium, macOS through `EPUBDocument`. | No navigator-open integration test and no current real AO3 EPUB read-through. Encoded filenames and other valid structures fail on macOS (**A7-F6**). | **Moderate.** |
| Preface, Summary, numbered chapters, Afterword order | The exact 104-spine synthetic AO3 shape passes, including synthesized Summary and 101 story chapters. | Real AO3/Calibre file on both platforms. | **Low**, strong pure coverage. |
| Index contains intended sections | Shared `ReaderSectionBuilder` and both index views include all four kinds and omit `.other` by design. | Nested Readium TOCs lose child entries (**A7-F8**); path collisions affect both readers (**A7-F9**). | **Moderate.** |
| Pill uses P / S / chapter progress / A | Exact labels `P`, `S`, `1/101`, `101/101`, and `A` pass. Both readers consume the same sections. | Visual truncation/localization on phone, iPad, and macOS. | **Low.** |
| Front/back matter excluded from chapter total | AO3 total parsing and section-count fallback both pass at 101, not 104. | WIP/unknown total against a live AO3 export. | **Low.** |
| Progress across relaunch, navigation, modes, upgrades | iOS persists a full Readium locator on every location change and flushes on dismissal; serialization/model progress tests pass. macOS stores only a spine and never reads/writes `lastScrollFraction` or a page (**A7-F2**). | iOS force-quit/upgrade restore and cross-device locator; complete macOS resume after fix. | **High — A7-F2 blocks release.** |
| Returning to a previous chapter restores its prior position | Readium owns one publication-wide navigator on iOS. macOS only lands on the previous chapter's last edge and has no per-chapter position memory (**A7-F2**). | Navigate away/back repeatedly in both modes. | **High on macOS.** |
| Scrolled and paged consistency | iOS maps both to Readium preferences. macOS's layout scripts implement both, but changing modes resets position (**A7-F2**). | Page-turn feel, two-page spread, long chapter, rapid mode switches. | **High on macOS.** |
| Swipe-down dismissal preserves progress / avoids gesture conflict | iOS vertical-dominance/top-of-scroll gates and a pre-dismiss locator flush are code-verified; horizontal page gestures remain separate. | Gesture comfort, Reduce Motion, scroll top, iPad split view, rapid double-dismiss. | **Manual feel gate.** |
| Page turns do not crash, trap input, or show blank content | iOS delegates to Readium; macOS uses bounded JS page indices/native horizontal scrolling. No force-unwrap/trap path found. | Very long/image-heavy chapters and rapid page turns. macOS encoded hrefs can show blank content (**A7-F6**). | **Moderate.** |
| Light, Dark, Sepia, OLED themes | Theme token/style mapping suites pass; both readers apply the same `ReaderTheme` values. | Rendered page/chrome screenshots in all four themes. | **Low–moderate**, visual gate. |
| OLED pitch black; Dark remains lighter | Tests pin OLED `#000000` and Dark `#16161A`, including app surfaces; Readium receives explicit colors. | Device screenshot/pixel verification. | **Low.** |
| Font, spacing, orientation, split view, Dynamic Type | Readium preference conversion, fallback stacks, and imported `@font-face` declarations pass; macOS CSS uses the same stored options. | Position/layout after resize, rotation, split view, Dynamic Type/accessibility sizes, custom font changes. macOS mode/resize position is broken by A7-F2. | **Moderate.** |
| TOC navigation and internal links | Normal flat NCX and AO3 section navigation pass. Readium itself handles resource links, but Kudos drops nested TOC children (**A7-F8**). macOS cross-file links desynchronize host state (**A7-F5**) and encoded hrefs fail (**A7-F6**). | EPUB3 nested nav, footnotes/backlinks, duplicate basenames, fragment links. | **Moderate.** |
| Reader comments use correct chapter/work | Shared section→AO3 chapter mapping passes for Preface/Summary/all chapters/Afterword and clamps against the live index. | Real comments sheet from each section. macOS cross-file links can leave the scope stale (**A7-F5**). | **Moderate.** |
| Long/malformed/missing-landmark/images/notes/unusual EPUBs fail safely | Typed basic legacy errors and empty-TOC fallback exist. Normal local fixture passes. | No large/image/note/EPUB3/hostile fixture. Retain **A5-F2**; macOS active content, encoded paths, stale cache, and malformed spine mapping are **A7-F4/F6/F7/F10**. | **High until hardening lands.** |
| Repeated open/close releases publication/web view/tasks | Readium navigator delegate and internal delegates are weak; no app-side iOS retain cycle was found. | Instruments on both platforms. macOS callback ownership retains its controller/WKWebView (**A7-F3**). | **Moderate.** |

### Findings

**A7-F1 — P1 Must Fix — iOS marks complete works finished at 99% and then
deletes an unprotected EPUB while content remains unread.**
Files: `kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift:640-645,
859-869` and `kudos-ao3-reader/Services/WorkLifecycle.swift:28-34, 45-55`.
Affected feature: iOS/iPadOS Readium reader for complete, ordinary AO3 works
that are not saved, favorited, or queued. Repro: read a sufficiently long
complete work until a location reports `totalProgression == 0.99`, close the
reader, then reopen offline. Expected: only reaching the actual end marks the
work finished and makes the intentional post-finish storage policy eligible.
Actual: `locationDidChange` uses `progress >= 0.99`; `.onDisappear` immediately
calls `freeEPUBIfFinished`, which removes the file and cache. Readium 3.9.0's
own viewport implementation linearly interpolates progression and its tests pin
the exact final-resource end at **1.0**, so values from 0.99 through less than
1.0 represent real remaining content, not an end sentinel. Impact: the final 1%
of a long work can be made unavailable offline and the work is incorrectly
moved to Finished; redownload is required and may later be impossible. Smallest
safe correction: gate auto-finish on a true end signal (at minimum exact 1.0;
prefer the navigator's last-resource/end state) and keep deletion after that
verified transition. Regression test: locators at 0.99 and 0.999 must not finish
or free; only the actual end may, with protected works still retained. Blocks
release: **YES**.

**A7-F2 — P1 Must Fix — The macOS reader never records or restores any
intra-chapter position.**
Files: `kudos-ao3-reader/Features/Reader/ReaderView.swift:244-250, 545-587`,
`ReaderController.swift:124-157`, and `ReaderStyle.swift:442-553`. Affected
feature: macOS legacy reader in scrolled and paged modes. Repro: open a long
chapter, scroll halfway or move to a later page, close/reopen; also switch modes
mid-chapter or leave and return to a prior chapter. Expected: restore the prior
semantic location. Actual: `ReaderView` reads/writes only `lastSpineIndex`;
`lastScrollFraction` is unused repo-wide by the reader, `page/pageTotal` exist
only in controller memory, every `load` resets page to 1, and the layout script
resets page state on mode changes. There is no dismissal progress flush or
explicit normal-close save. Impact: core reading progress is lost on every
macOS close/relaunch, mode change, and chapter revisit. Smallest safe correction:
have the JS bridge report a normalized location for both modes, persist it with
the spine, restore it after layout, and flush/explicitly save on disappearance.
Regression test: a synthetic multi-page chapter reopens near its midpoint and
retains the same semantic location across scrolled↔paged and resize transitions.
Blocks release: **YES**.

**A7-F3 — P2 Should Fix — macOS reader callbacks retain their controller and
WKWebView after dismissal.**
Files: `kudos-ao3-reader/Features/Reader/ReaderView.swift:39, 244-250,
496-525`, `ReaderController.swift:21-29`, and the wrapper at
`Features/Browse/WebBrowser.swift:405-421`. Affected feature: repeated macOS
reader open/close. Repro: open and close works repeatedly and inspect
`ReaderController`/`WKWebView` allocations. Expected: dismissal releases the
controller, web view, callbacks, and handlers. Actual: the controller strongly
owns four escaping callbacks that capture the `ReaderView`'s `@State` storage,
which owns that controller; no callback is cleared and the generic wrapper has
no `dismantleNSView`. The script proxy is weak, but it does not break this
separate cycle. A matching local SwiftUI ownership probe remained `retained`
after scope exit. Impact: a WKWebView and publication resources can accumulate
per opening. Smallest safe correction: add idempotent teardown that clears
callbacks, stops loading, removes handlers/delegates, and invoke it on disappear
or `dismantleNSView`. Regression test: wire/teardown under a weak reference and
assert deallocation; confirm flat allocations with Instruments. Blocks release:
no.

**A7-F4 — P2 Should Fix — A macOS imported EPUB can execute publisher script
through the privileged reader bridge and load unrestricted remote subresources.**
Files: `kudos-ao3-reader/Features/Reader/ReaderController.swift:51-57,
124-157, 168-194` and `ReaderStyle.swift:442-550`; documented current boundary
at `docs/EPUBParsing.md:77-85`. Affected feature: user-imported EPUBs in the
macOS legacy reader. Repro: import XHTML containing script that posts
`{event:"bottom"}` to `window.webkit.messageHandlers.reader` and includes a
remote HTTPS beacon. Expected: untrusted publication content cannot invoke host
actions or contact arbitrary hosts without a user gesture. Actual: the default
WK configuration enables publisher JavaScript, exposes the same `reader`
handler used by app-injected code, uses the persistent website-data store, and
has no content rule for remote subresources; the navigation delegate only
cancels HTTP(S) navigation actions. Impact: content can spoof page/bottom/key
events, trigger reader state transitions, track the open, and persist web data.
Smallest safe correction: disable publisher script while running app layout code
in an isolated content world, use a nonpersistent store, and block non-file
subresources while preserving explicit tapped-link routing. Regression test: a
hostile fixture's script/beacon cannot run, while local images, layout code, and
internal anchors remain functional. Blocks release: no, but fix with EPUB
hardening.

**A7-F5 — P2 Should Fix — Cross-spine links on macOS render a new chapter while
the pill, TOC, progress, controls, and comments remain on the old one.**
Files: `kudos-ao3-reader/Features/Reader/ReaderController.swift:168-194` and
`ReaderView.swift:251-305, 391-405, 577-585`. Affected feature: macOS notes and
internal links that target another XHTML spine resource. Repro: activate
`chapter2.xhtml#note` from chapter 1. Expected: render the target and update all
host state to its spine index. Actual: every `file:` navigation is allowed in
the WKWebView, but `didFinish` never resolves the new URL back to `currentIndex`;
the old index drives every named surface and future previous/next navigation.
Impact: incorrect chapter-scoped comments and saved progress plus broken
navigation labels/sequence. Smallest safe correction: intercept cross-file
links, resolve them against the normalized spine, update `currentIndex`, then
navigate; allow same-document fragments in place. Regression test: chapter 1
link→chapter 2 note updates both rendered content and every host state to spine
2. Blocks release: no.

**A7-F6 — P2 Should Fix — Percent-encoded OPF resource hrefs become literal
filenames on macOS, producing blank valid chapters.**
Files: `kudos-ao3-reader/Reading/EPUB.swift:121-127, 156-189` and
`Features/Reader/ReaderView.swift:577-583`. Affected feature: macOS EPUBs with
legal URL-encoded resource names. Repro: archive `Text/Chapter 1.xhtml` and
reference it as `Text/Chapter%201.xhtml` in the OPF. Expected: URL semantics
decode once and load the extracted space-named file. Actual:
`appendingPathComponent` treats `%20` literally; the local probe produced path
`Chapter%201.xhtml` and URL `Chapter%25201.xhtml`. The spine remains nonempty,
so parsing succeeds and the reader tries the nonexistent URL. Impact: valid
chapters/TOCs can render blank or fail to navigate. Smallest safe correction:
resolve hrefs as relative URLs, decode/normalize exactly once, and validate
standardized containment below the extraction root. Regression test: an EPUB
with encoded spaces in OPF/nav hrefs parses, opens, and maps its TOC. Blocks
release: no.

**A7-F7 — P2 Should Fix — macOS extraction overlays a persistent per-work cache,
so a replaced or corrupt EPUB can render stale files from its predecessor.**
Files: `kudos-ao3-reader/Reading/EPUB.swift:219-224`, `MiniZip.swift:65-76`, and
`Features/Reader/ReaderView.swift:545-555`. Affected feature: macOS reopen after
an EPUB replacement, repair, sync, or backup restore. Repro: open version A,
replace the same work's EPUB with structurally accepted version B that omits or
cannot decode a referenced payload, then reopen. Expected: fresh extraction
fails visibly on the missing resource. Actual: extraction never clears or stages
the fixed reader directory; present entries overwrite, while absent/undecodable
entries remain from A and can satisfy B's references. Impact: wrong-version
content and masked corruption. Smallest safe correction: extract/validate into a
fresh sibling and atomically replace the cache; invalidate cache whenever the
stored EPUB changes. Regression test: reuse one logical work directory across A
and B and prove an omitted A-only resource cannot appear under B. Blocks release:
no. Area 5's required fresh-staging MiniZip hardening can close both issues.

**A7-F8 — P2 Should Fix — The iOS chapter sheet drops every nested TOC child.**
File: `kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift:219-224,
257-274, 834-849`. Affected feature: iOS/iPadOS EPUBs with a hierarchical EPUB2
NCX or EPUB3 nav. Repro: a top-level Part link with child Chapter links. Readium
models hierarchy in `Link.children` and its own sample outline explicitly
flattens recursively; Kudos iterates only the top-level array when constructing
`ReaderSection`s. Expected: all navigable chapter descendants appear in reading
order. Actual: children are never visited, their spine items become `.other`,
and the chapter sheet hides them. Page turning still reaches content. Impact:
most index navigation is missing for a valid common TOC shape. Smallest safe
correction: recursively flatten TOC links in document order before spine
matching, retaining titles and deduplicating resolved spine targets. Regression
test: nested Part→Chapter links all produce navigable section rows in order.
Blocks release: no.

**A7-F9 — P3 Follow-up — Path-insensitive basename matching collapses distinct
TOC resources in both readers.**
Files: `kudos-ao3-reader/Reading/ReaderSection.swift:135-143` and
`Reading/EPUB.swift:147-154, 193-204`. Affected feature: a valid EPUB containing,
for example, `part1/chapter.xhtml` and `part2/chapter.xhtml`. Repro: give both
resources separate spine/TOC entries. Expected: each maps to its own spine item.
Actual: both helpers discard directories and use only lowercased basename; the
second link resolves/collides with the first, leaving one wrong/hidden section.
Impact: incorrect index, pill/comments mapping, and TOC navigation for an
unusual valid structure. Smallest safe correction: compare normalized,
fragment-stripped full publication-relative paths; use basename fallback only
when it is unique. Regression test: duplicate basenames in distinct directories
remain independently mapped on both pipelines. Blocks release: no.

**A7-F10 — P3 Follow-up — Dropping an unresolved legacy spine item leaves later
TOC indices out of range.**
File: `kudos-ao3-reader/Reading/EPUB.swift:121-127, 147-154, 193-204`.
Affected feature: macOS malformed EPUBs with a missing manifest id between
readable spine items. Repro: raw spine `[valid1, missingID, valid2]` with TOC
entries for both valid resources. Expected: safely drop the invalid item and map
valid2 to compacted index 1, or reject the malformed package. Actual:
`spineURLs.compactMap` creates two items but `keyToIndex` enumerates the original
three idrefs and maps valid2 to index 2; selecting it produces an out-of-range
`currentIndex` that `loadCurrentChapter` silently ignores. Impact: dead/wrong
TOC navigation rather than a clear failure. Smallest safe correction: build one
normalized compact spine and derive URLs and TOC indices from that same array.
Regression test: a missing middle idref either throws or leaves the later
chapter navigable at compact index 1. Blocks release: no.

### Verified controls / observations

- Normal EPUB2/NCX parsing, two-chapter extraction, import/dedup, AO3 section
  normalization, comments mapping, theme tokens, and Readium typography/font
  mapping are green in the focused run.
- iOS progress persistence is materially stronger than macOS: a full locator is
  saved on every change and before both custom dismiss paths; Readium's delegate
  and internal view-model delegates are weak. Exact force-quit restoration,
  navigator recreation, and Instruments lifetime remain manual.
- HTTP(S) main-frame links are handed out of both readers rather than replacing
  book content. Readium handles same-publication links internally; A7-F5 is the
  legacy cross-file state bridge.
- `ReadiumMetadataMapper` and the documentation claiming iOS import metadata is
  Readium-backed do not match the current tree: both AO3 and user import paths
  still call legacy `EPUBDocument` inspection/metadata code. This is recorded for
  Area 10 documentation/cleanup rather than counted as a separate reader defect;
  A5-F2 already covers the security consequence.
- A7-F7's stale-cache behavior is distinct functional evidence, but its smallest
  correction is intentionally shared with A5-F2's staged-extraction fix.

### Manual checks remaining (Area-7 scope)

- Real AO3 single-/multi-chapter EPUB with Preface/Summary/Afterword in both
  readers; index, pills, comments scope, footnotes/backlinks: **NOT RUN**.
- iPhone/iPad Readium scroll/paged modes, page turns, swipe-down/edge-back,
  orientation/split view, Dynamic Type, custom fonts, and all four themes:
  **NOT RUN**.
- macOS exact resume after close/relaunch, mode/resize transitions, two-page
  spread, key/swipe navigation, encoded/nested/duplicate-path fixtures, and
  hostile/malformed EPUBs: **NOT RUN**.
- Very long/image-heavy chapters and repeated open/close/foreground cycles under
  Instruments on both platforms: **NOT RUN**.

---

## Area 8 — Performance and Scalability

Status: **COMPLETE** (2026-07-12). Product baseline frozen at `c1bf211`.
Audit-only inspection and bounded synthetic probes; no live AO3 load test and no
production source changes. The exact baseline passed `Scripts/verify.sh` after
the Inbox commit: **371/371 tests**, macOS Debug build, invariants, lint gate,
and whitespace all green.

### Evidence and scenario coverage

| Scenario | Evidence | Assessment / remaining gate |
|---|---|---|
| Empty/small normal library | Existing simulator test launch and complete suite remained responsive; app launch logs show WebKit prewarm processes at roughly 1.2s on this machine, but the system declined CA first-frame metrics, so this is not treated as a launch benchmark. | No release finding. Cold/warm first-frame timing remains a device gate. |
| ~1,000 to several-thousand local works, queues, memberships, and tombstones | Root inspection found seven unbounded `@Query` arrays mounted for the entire app and recomputed into a max-date token on the main actor on every dependency invalidation (**A8-F1**). Home/Library also intentionally materialize the local library and perform repeated per-section filters/sorts; this compounds A8-F1 but is not counted separately without a representative large SwiftData fixture. | Large-store Time Profiler/SwiftUI update pass required. |
| Local search and index rebuild | `WorkSearchIndex` stores normalized derived text, bounds summary contribution to 600 characters, fetches only stale index versions, and yields every 200 records. Query matching remains a linear in-memory substring scan of the loaded candidate array. | Sensible current control; quantify several-thousand-work typing latency manually. |
| Backup, restore, and folder sync with many/large EPUBs | Direct code trace plus a 64×4 MiB synthetic package probe. Loading and consuming the 256 MiB payload produced **280,641,536 bytes max RSS** versus **12,304,384 bytes** before payload pages were consumed; the app retains all EPUB `Data` objects in one package value (**A8-F2**). | Material peak-memory risk; device jetsam/large-file gate remains. |
| Extensive comments / repeated comment browsing | Thread flattening is iterative; casual expansion renders 20 replies per chunk. The session page/chapter cache has no cap or eviction and expired pages remain retained (**A8-F3**). | Large-thread UI is bounded; long browsing-session memory is not. |
| Repeated reader open/close and long reading | Area 7 already establishes the macOS controller/WKWebView retention cycle (A7-F3); it is referenced, not duplicated. iOS app-side delegates inspected weak. | Instruments allocation graph on both platforms remains mandatory. |
| Inbox refinement network/perceived latency | One Inbox page GET plus at most one work-metadata GET per distinct unresolved work on the currently visible page. The loop is sequential, cancellable, auth-scoped, deduplicated, stops on systemic failure, and caches 128 work contexts. Global pacing makes 20 uncached work contexts take a theoretical minimum of roughly **12 seconds** after the page request. | Deliberate owner-approved correctness/UX tradeoff, recorded as an observation rather than a new defect. Verify progressive updates and battery impact on device. |
| Network request counts outside Inbox | Request coordinator/coalescer/pacing controls from Area 3 remain intact; no synthetic/live AO3 stress was performed. Fandom index uses its linear parser specifically to avoid the prior >1 GB DOM balloon. | No new finding. |

### Findings

**A8-F1 — P2 Should Fix — The app root permanently observes and recomputes
across seven complete SwiftData tables, even when folder auto-sync is off.**
File: `kudos-ao3-reader/App/ContentView.swift:13-19, 215-229`. Affected feature:
launch, every tab, large libraries/queues, iOS and macOS. Repro: populate a store
with several thousand works and queue memberships, disable Auto Sync, launch or
mutate any observed record, and profile SwiftData fetches/main-actor view updates.
Expected: disabled sync has near-zero ongoing observation cost; enabled sync uses
bounded change tracking. Actual: seven unfiltered root `@Query` values materialize
all works, bookmarks, fonts, collections, queues, memberships, and tombstones;
`folderSyncChangeToken` maps each full array to dates and scans each temporary
date array for its maximum. The `scheduleFolderSyncUp` guard happens only after
this observation/recomputation. Impact: launch/store memory and main-actor work
scale with the entire database on every screen, with queue memberships likely
the largest multiplier. Smallest safe correction: persist a monotonic sync
change revision or observe bounded aggregate/change records only, and do not
mount full sync queries while auto-sync is disabled. Regression test: seed a
large in-memory store, prove a root render/change does not fetch/materialize all
records, and assert disabled sync schedules no work. Blocks release: no.

**A8-F2 — P2 Should Fix — Backup, restore, and folder sync retain every EPUB
payload in one in-memory package graph, so peak memory scales with total library
bytes rather than one file.**
Files: `kudos-ao3-reader/Services/KudosBackup.swift:38-108, 926-965,
970-1050` and `FolderSyncService.swift:398-430`. Affected feature: export,
import/restore, and sync for large preserved libraries on both platforms. Repro:
construct a package containing 64 4-MiB EPUBs (256 MiB total), load its immediate
`FileWrapper`, retain each `regularFileContents`, and consume/write the payloads.
The bounded macOS probe reported 280,641,536-byte maximum RSS; the no-touch load
was 12,304,384 bytes. Expected: streaming or file-by-file staging keeps peak
memory near one EPUB plus manifest overhead. Actual: `KudosBackupContents` owns
`[UUID: Data]` for all works (and all font data), export first builds the complete
dictionary, import constructs it from the complete `FileWrapper`, and restore
only then iterates and writes each retained blob. Impact: a backup comparable to
device memory can be killed by memory pressure mid-export/restore/sync; larger
libraries fail deterministically despite ample disk. Smallest safe correction:
make the package representation URL/FileWrapper-backed and stream/stage one asset
at a time, retaining only the manifest and current asset; preserve the existing
atomic destination swap. Regression test: export and restore a synthetic package
larger than a fixed memory budget while asserting bounded resident growth and
byte-identical EPUBs. Blocks release: no, but should be fixed before claiming
large-library backup reliability.

**A8-F3 — P2 Should Fix — The session Comments cache never evicts pages or
chapter indexes; TTL expiry stops reuse but does not release memory.**
File: `kudos-ao3-reader/Features/Comments/CommentsModel.swift:664-704`.
Affected feature: long sessions browsing many works/chapters/comment pages, iOS
and macOS. Repro: visit distinct comment pages for many works for longer than the
five-minute TTL and inspect `CommentsPageCache`; each `store` only assigns into
`pages`, each chapter index remains indefinitely, and an expired `page(for:)`
returns nil without removing its retained `AO3CommentsPage`. Expected: TTL expiry
or an LRU cap bounds session memory. Actual: memory grows with every distinct
work/chapter/page/auth key until process exit, retaining full parsed thread trees
and strings. Impact: extensive browsing can accumulate stale comment graphs and
increase pressure alongside reader/WebKit resources. Smallest safe correction:
remove expired entries on lookup/store and enforce a modest LRU/count or cost
cap for both dictionaries. Regression test: insert more than the cap, advance a
test clock beyond TTL, and assert old page/chapter values are released while the
recent auth-scoped page remains. Blocks release: no.

### Verified controls and observations

- T-91 Inbox metadata enrichment is limited to distinct IDs actually rendered
  on the current page; it cancels on navigation/page changes, stops after a
  systemic failure, skips complete local/profile seeds, and caps its context
  cache at 128. The request volume is therefore bounded and policy-conformant,
  though the progressive last-card latency is visible by design.
- Comment reply projection uses an iterative stack (avoids deep-recursion and
  O(depth²) concatenation) and renders casual expansion in 20-item chunks.
- Fandom parsing remains the purpose-built linear scan added after the older DOM
  parse exceeded 1 GB; no regression to whole-document SwiftSoup parsing found.
- Search index rebuild yields every 200 stale records and saves once. No repeated
  network work is coupled to local search/indexing.
- Area 7's macOS retained WKWebView/controller remains the dominant known
  repeated-reader-cycle issue and is not double-counted here.

### Manual checks remaining (Area-8 scope)

- Cold/warm launch and first usable Home/Library on a physical lower-memory iPhone
  with empty, ~1,000-work, and several-thousand-work stores: **NOT RUN**.
- Time Profiler / SwiftUI body updates while scrolling, filtering, searching,
  editing queues, and mutating sync-observed records in a large store: **NOT RUN**.
- Allocations/leaks over repeated reader, comments, Inbox, Browse, and Account
  open/close cycles; verify task/WKWebView counts return to baseline: **NOT RUN**.
- Export/restore/sync of a real multi-gigabyte package on device under memory
  pressure, including cancellation and low-disk behavior: **NOT RUN**.
- Battery/thermal pass for prolonged reading, large-library scrolling, Inbox
  hydration, and background folder sync: **NOT RUN** and remains a human device
  release gate.

---

## T-91 Inbox Refinement — Cross-Cutting Release-Review Addendum

Status: **COMPLETE** (2026-07-12). Reviewed after the feature was frozen at
`c1bf211`, before starting Area 9. This addendum supplements Areas 3–6 and
pre-identifies accessibility work for Area 9; it does not reopen or renumber the
ten sequential prompts. No production source was modified during this review.

### Scope and evidence

- Inspected all 22 paths changed by `c1bf211`, including Inbox parsing/forms,
  state and pagination, native writes, visible-page metadata hydration, Account
  navigation, focused Comments loading, comment-submission safety, shared role/
  Reply/overflow components, author-page cache invalidation, and the new tests.
- Traced authenticated requests, cache keys, cancellation boundaries, account
  changes, single-write behavior, redirect/error parsing, and every async yield
  between a successful write and its forced reload.
- Cross-checked the parser and response assumptions against the current primary
  AO3 source:
  [`inbox/show.html.erb`](https://github.com/otwcode/otwarchive/blob/master/app/views/inbox/show.html.erb),
  [`inbox/_inbox_comment_contents.html.erb`](https://github.com/otwcode/otwarchive/blob/master/app/views/inbox/_inbox_comment_contents.html.erb),
  [`inbox/_reply_button.html.erb`](https://github.com/otwcode/otwarchive/blob/master/app/views/inbox/_reply_button.html.erb),
  and [`inbox_controller.rb`](https://github.com/otwcode/otwarchive/blob/master/app/controllers/inbox_controller.rb).
- Reproduced RF2 against the committed `CommentSubmissionGuard` in a standalone
  compile probe: the same unresolved key was rejected while `.ambiguous`, then
  accepted after visiting a different reply target; a fresh guard created by
  rebuilding the pushed Comments screen also accepted it.
- The frozen product baseline remains build/test green: `Scripts/verify.sh`
  passed **371/371 tests**, macOS Debug build, invariants, lint gate, and
  whitespace. Those tests do not exercise the state/lifecycle failures below.

### Findings

**T91-RF1 — P1 Must Fix — An ambiguous reply opened from Inbox verifies against
synthetic work-comment page 1, recreating the real duplicate-post path on any
parent thread stored later in pagination.**
Files: `Features/Comments/CommentsModel.swift:214-217, 602-611` and
`Services/AO3CommentActions.swift:117-150`. Repro: open an Inbox reply whose
parent thread lives on work-comments page 2+, submit a reply, and make the POST
time out after reaching AO3. Expected: verification checks the exact parent
thread and keeps reposting blocked unless absence is proven. Actual: focused
standalone threads always assign `currentPageNumber = 1`; the composer passes
that as `knownPage`, and `verifyCommentPosted` fetches work-level page 1. It does
not find the parent/new reply, returns `.absent`, and unlocks another POST.
Impact: a user following the recovery UI can create a real duplicate AO3 reply.
Smallest safe correction: verify replies through the standalone
`/comments/<parentCommentID>` thread (already parsed/fetched elsewhere), not a
work pagination guess; match the direct reply there. Regression: an Inbox reply
whose work parent is modeled as page 5 must remain blocked when page 1 lacks it,
and standalone-parent verification must find the posted body. Blocks release:
**YES**.

**T91-RF2 — P1 Must Fix — The unresolved duplicate-post guard is neither
multi-context nor screen-durable; changing targets or leaving the pushed thread
silently unlocks the original ambiguous submission.**
Files: `Features/Comments/CommentsModel.swift:507-544`,
`Features/Comments/CommentsView.swift:625-633, 932-974`, and
`Services/CommentSubmission.swift:60-65, 78-94, 141-144`. Two independent
repros survive: (1) ambiguous reply A → Cancel → open reply B → Cancel → reopen
A; `startComposer` calls `reset()` for B, which changes `.ambiguous` to `.idle`
without resolving/removing A, and `begin(A)` now returns true; (2) ambiguous A →
Cancel → Back to Inbox → reopen A; the pushed `CommentsView` and its model-local
guard were destroyed, while the saved draft survives in `UserDefaults`, so a
fresh guard accepts the same key. Expected: the same unresolved key remains
blocked throughout navigation until read-only verification resolves it. Impact:
real duplicate comments despite the documented invariant. Smallest safe
correction: make unresolved submissions an auth-scoped set/store above an
individual `CommentsModel` (persist enough state across view recreation), and
never let switching to another context collapse or overwrite an unresolved key.
Regression: both target-hop and pop/reopen flows must reject A while still
allowing a genuinely different resolved submission. Blocks release: **YES**.

**T91-RF3 — P1 Must Fix — A successful Inbox write can race an account switch
and let the old account's forced reload overwrite the new account's model.**
File: `Features/Account/AO3InboxModel.swift:241-283, 315-354`. Repro: account A
starts Mark Read/Delete; after `submitWrite` returns and the scope guard at
268–270 passes, switch to account B while cache invalidation or the forced
`load` is suspended. Expected: every post-write continuation remains bound to A
and becomes inert as soon as scope changes. Actual: the write task is deliberately
separate from `activeTask`; the one scope guard occurs before multiple awaits,
and `reset()` cannot cancel that write task. If the old reload already built A's
URL/request, it can complete after B's reset/load and assign A's private Inbox
HTML into a model whose `authenticationScope` is B. Impact: cross-account
private-content exposure and wrong action forms on a shared device. Smallest
safe correction: carry an immutable expected scope/session generation into
`load`, re-check after every await and immediately before every mutation, and
prevent post-write reload from running after a mismatch. Regression: suspend A's
reload, activate B, then resume A; B's rows/forms must remain unchanged. Blocks
release: **YES**.

**T91-RF4 — P2 Should Fix — A metadata-complete older `SavedWork` with no
verified creator identities suppresses the exact hydration required for Author
badges.**
Files: `Models/AO3CommentModels.swift:88-103, 144-150`,
`Models/Models.swift:301-306`, and `Features/Account/AO3InboxModel.swift:105-120`.
Repro: use a pre-identity saved AO3 work with title/fandom/rating/chapters and
plain author text populated but `authorIdentitiesJSON == ""`; receive a comment
from its creator under an alternate pseud. Expected: the visible-page metadata
pass fetches canonical account identities and marks the commenter Author. Actual:
`needsSummaryEnrichment` treats plain author names as a complete creator, so the
Inbox skips the request; identity resolution cannot match the alternate pseud
and displays User indefinitely. The `SavedWork` model itself correctly recognizes
missing identities as enrichment-needed, demonstrating the contract mismatch.
Smallest correction: distinguish display-author completeness from canonical
identity completeness and attempt the bounded metadata load when an AO3-backed
context lacks identities (with an explicit completed-anonymous state to avoid
per-refresh retries). Regression: complete legacy metadata + empty identity JSON
must still hydrate once and resolve an alternate-pseud creator as Author. Blocks
release: no.

**T91-RF5 — P2 Should Fix — Logging out and back into the same AO3 username can
reuse stale Inbox rows and a CSRF form from the previous session.**
Files: `Services/AO3AuthorProfileService.swift:10-22`,
`Services/AO3Client+Authors.swift:563-620`,
`Features/Account/AO3InboxModel.swift:153-166`, and
`Features/Account/AccountView.swift:364-417`. Repro: load Inbox, log out, then
create/restore a new AO3 session for the same username and return to Inbox within
the cache window. Expected: a session boundary invalidates private HTML/forms
even when the username matches. Actual: auth scope is only
`signed-in:<username>`; signed-out activation returns before resetting Inbox,
and same-name activation sees the old scope plus a non-idle phase and performs no
load. Even if forced, the shared cache uses the same key. Impact: stale read/
delete state and session-bound CSRF fields; writes can fail until a manual fresh
reload. Smallest correction: include a non-secret session generation in private
cache/model scope and explicitly reset/invalidate Inbox on logout/session
replacement. Regression: logout→same-user login must cold-load new HTML and form
tokens. Blocks release: no.

**T91-RF6 — P2 Should Fix — Valid AO3 Inbox entries without a normal byline are
silently dropped, and an all-unavailable page is reported as “No comments yet.”**
Files: `Services/AO3Client+Inbox.swift:30-49, 81-84` and
`Features/Account/AccountInboxViews.swift:401-427`. AO3's current upstream
template deliberately renders an admin-hidden comment as a `<li
id="feedback_comment_…">` containing only an unavailable message, followed by
its actions/checkbox—no `h4.heading.byline`. Expected: retain a visible
unavailable tombstone or fail the page honestly. Actual: `parseInboxItem` throws,
the page `compactMap` discards it, and the recognized-page guard only checked
whether raw `<li>` elements existed. If every row has this shape, parsing returns
`.loaded` with `items.isEmpty` and the UI fabricates a genuinely empty Inbox.
Impact: users cannot see or manage real notifications and receive false state.
Smallest correction: parse unavailable rows as explicit tombstones using the
feedback and InboxComment ids, and fail rather than fabricate empty if raw rows
exist but none can be represented. Regression: the upstream hidden-row shape
must remain visible/selectable (or produce a parser error), never “No comments.”
Blocks release: no.

**T91-RF7 — P2 Should Fix — Native filter parsing claims fail-closed behavior
but accepts any nonempty partial set of groups/options and invents a selection
when AO3 checked none.**
Files: `Services/AO3Client+Inbox.swift:236-285` and
`Models/AO3InboxModels.swift:149-197`. Repro: remove the date radio group, one
read option, or every `checked` attribute from the fixture. Expected: native
filters disable because the form contract is incomplete. Actual: group/option
construction uses `compactMap`, the only final guard is `!fields.isEmpty`, and
`selectedValue` falls back to the first option. The UI remains enabled and emits
a query assembled from a partial/unselected form. Impact: silent filter/sort
changes after AO3 markup drift, contrary to the documented safety boundary.
Smallest correction: validate the current stable names and complete allowed
value sets (`filters[read]`, `filters[replied_to]`, `filters[date]`) with exactly
one checked value per group; otherwise return nil. Regression: every missing/
duplicate/unchecked variant disables native filters. Blocks release: no.

**T91-RF8 — P2 Should Fix — A failed pagination request hides retained Inbox
content and Retry targets the previous page instead of the page that failed.**
Files: `Features/Account/AO3InboxModel.swift:169-182, 315-354` and
`Features/Account/AccountInboxViews.swift:401-427, 500-509`. Repro: from page 1,
tap page 2 and make that request fail. Expected: page 1 remains visible with a
page-2 error/retry, or Retry repeats page 2. Actual: `currentPage` changes only
after a successful parse, failure changes the global phase to `.failed` (hiding
the retained items/pagination), and `retry()` reloads `currentPage`—still 1.
Impact: normal offline/server failures eject the user from the feed and make the
requested page impossible to retry directly. Smallest correction: track the
requested page independently and use a non-destructive pagination error state.
Regression: failed page 2 preserves page 1 and retries 2. Blocks release: no.

**T91-RF9 — P2 Should Fix — AO3's normal stale-selection failure response is
classified as a successful Inbox write.**
Files: `Services/AO3InboxActions.swift:32-42` and
`Services/AO3Client.swift:483-489`; upstream behavior in
`InboxController#update`. Repro: load a notification, remove it in another
session so the submitted InboxComment id is stale, then perform a native action
(or include it in a multi-selection). AO3 rescues `InboxComment.find`, sets a
`flash[:caution]` “must select item” response, and redirects with HTTP 200; no
selected item is updated. Expected: surface the server failure. Actual:
`writeErrorMessage` recognizes error lists/`.flash.error` but not AO3's
`.caution`/`.notice.caution`; the 200 response is accepted as success. Impact:
valid selected rows in the same batch can remain unchanged with no explanation.
Smallest correction: recognize AO3 caution flashes for write failures or require
the expected success notice/state before claiming success. Regression: a 200
Inbox page containing `div.caution` must throw, while the real success notice
passes. Blocks release: no.

**T91-RF10 — P2 Should Fix (accessibility) — Inbox cards expose several
redundant VoiceOver “open thread” controls, while select/filter state is conveyed
only by hidden checkmarks.**
File: `Features/Account/AccountInboxViews.swift:122-207, 211-240, 530-559`.
Repro: navigate a populated Inbox with VoiceOver, then enter Select and open
Filters. Expected: one primary card action plus distinct Reply/Chapter/More
actions; selected/not-selected and current filter values are announced. Actual:
the same row has an accessible full-card background Button plus separate avatar,
byline, excerpt, and subject Buttons that all open the same thread. In select
mode the only selected-state icon is `accessibilityHidden(true)` and the Button
has no selected trait/value; filter checkmarks are likewise hidden without an
equivalent selected announcement. Impact: excessive swipes and no reliable
state feedback for assistive-technology users, violating the project's
accessibility-non-optional standard. Smallest correction: consolidate the card's
primary accessibility element/custom actions and add `.isSelected`/explicit
values to selection and filter rows. Regression/manual gate: Accessibility
Inspector hierarchy plus VoiceOver page/select/filter walkthrough. Blocks
release: no, but must be included in Area 9.

**T91-RF11 — P3 Follow-up — Chapter-focus retry consumes its only fallback
position before success and ignores an already-resolved selected chapter.**
File: `Features/Comments/CommentsModel.swift:155-199, 238-245`. Repro: use an
Inbox Chapter destination whose standalone thread lacks a chapter link, let the
first attempt resolve `requestedChapterPosition` through `/navigate`, then fail
the chapter-page fetch and retry. Expected: retry reuses the resolved chapter or
the original position. Actual: `pendingInitialChapterPosition` is set to nil at
the start of the first attempt; retry has neither that local value nor a fallback
to `selectedChapter`, so it can degrade into `AO3Error.parse` even after the
network recovers. Smallest correction: consume initial context only after
success and seed the retry with `selectedChapter`. Regression: failed chapter
page followed by a successful retry retains the exact chapter and focused root.
Blocks release: no.

### Lower-severity observations (not additional findings)

- The filter sheet applies one radio choice and dismisses immediately, so changing
  Read + Replied + Sort requires opening it three times; the visible Done button
  never commits a local set. Functional, but Area 9 should judge the interaction.
- The bulk Delete confirmation is attached to the trailing Done control rather
  than the Delete button; on popover-style platforms its visual anchor can point
  to the wrong action. Include in the iPad/macOS manual pass.
- An internally-launched first-page Inbox request can finish after the user leaves
  the Inbox tab. It is one bounded request (not polling/prefetch) and does not
  independently meet the material-finding threshold, but a view-owned task would
  make the documented lifecycle clearer.
- A fresh visual screenshot was not obtained in this addendum: the available
  booted simulator session was signed out and on Home. The owner's earlier Inbox
  visual acceptance covers the tested configuration only; Light/Dark/Sepia/OLED,
  accessibility sizes, iPad, and macOS remain Area-9 gates.

### Verified strengths

- Inbox page and metadata requests remain paced; metadata hydration is sequential,
  distinct-work-only, current-page-only, cancellation-aware, auth-checked after
  response, stopped on systemic failure, and capped at 128 stored contexts.
- Inbox writes use the exact parsed checkbox/action values and one `submitWrite`
  call—no retry/coalescing loop. All current filter/page cache variants are
  invalidated after a confirmed same-scope success.
- Work/non-work routing, Parent Thread-or-self resolution, exact chapter insertion,
  Reply capability gating, Guest/User/Author/Me precedence, Anonymous Creator
  provenance, paced avatars, the dedicated Reply capsule, trailing green Replied
  marker, and nonredundant overflow actions are structurally correct in the normal
  fixture/live-markup path.
- The current upstream Inbox form still uses PUT-via-POST, the three stable action
  names, the three documented filter groups, and distinct feedback-comment versus
  InboxComment ids; the normal fixture matches those contracts.

### Test and release gates

The added tests cover parser happy paths, recognized-empty versus wholly
unrecognized markup, form-body construction, cache invalidation breadth, role
resolution, standalone-thread projection, and pure metadata merging. There is
**no instantiated `AO3InboxModel` test** and no injected page/write loader, so
activation, same-user relogin, page/filter failure, account-switch races,
post-write response handling, metadata cancellation/failure, and selection
lifecycle are review-only today. Before release:

1. Fix and regression-test RF1–RF3; all three are release blockers.
2. Add an injected Inbox page/write seam and model-state suite covering RF4–RF9.
3. Run owner live Mark Read/Unread/Delete against AO3, including a stale row from
   another browser/session; agents must not manufacture a live write.
4. Complete Area 9's VoiceOver, Dynamic Type, theme, iPhone/iPad, and macOS pass,
   explicitly including RF10 and the two UI observations above.
5. Retain the standing release blockers from Areas 2, 5, and 7; this addendum does
   not supersede A5-F1/F4 or the reader/persistence blockers.

Release conclusion for T-91 at this point: **NOT READY — 3 P1 blockers, 7 P2
findings, 1 P3 follow-up.**
