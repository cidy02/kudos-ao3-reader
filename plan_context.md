# Plan Context — live handoff doc

**Purpose:** running record of where "continue the plan" work stands, so another
agent (or a fresh session after a rate limit) can take over without re-deriving
context. Update this **as you go**, not at the end.

Canonical plan: `/Users/cidy02/.claude/plans/agile-forging-moon.md`
Task board: `TASKS.md` (repo root). Onboarding: `docs/AGENT_ONBOARDING.md`.
Definition of done: `Scripts/verify.sh` (invariants → lint → full iOS suite →
macOS build → whitespace).

Working branch: `comment-ui-refinement` (branched from `main`; `release-hardening`
was consolidated into `main` earlier — see below). Simulator: iPhone 17,
id `77492544-056E-4D4A-ABB6-7E38CC042A4D`, bundle `com.cidy02.Kudos`.
⚠️ Multiple iPhone 17 simulator UDIDs can exist across Xcode runtime updates —
`Scripts/test.sh`'s bare device-name destination can go ambiguous; pass the
explicit `id=...` form if `xcodebuild: error: Unable to find a device...` hits.

---

## Status snapshot (2026-07-10, later)

### DONE: cherry-picked native AO3 author profiles (f86fa07) — `f98abb8`
Owner asked to bring Codex's `f86fa07` (only that commit, not
`codex/native-ao3-author-profiles`'s tip `70c4863`, a TASKS.md-only note) into
this worktree. 3 real conflicts (this branch's comment-thread rewrite landed
after f86fa07 was authored, so most of it was f86fa07's now-stale bubble/
connector geometry colliding with the superseded architecture — NOT a genuine
double-edit):
- `TASKS.md`: both branches independently claimed T-86 — kept both entries,
  renumbered the incoming one to **T-87**.
- `CommentThreadRow.swift`: kept this branch's current spine/rail card
  architecture wholesale (env-based `CommentThreadHandlers`); grafted in only
  the genuinely new content — `AO3AuthorBylineView` replacing the plain
  author `Text`, `commentIdentity`, and a new `onOpenAuthor` case on
  `CommentThreadHandlers` (`= nil` default so `.noop` and the one other
  caller keep compiling).
- `CommentsView.swift`: kept this branch's call site; wired
  `onOpenAuthor: openAuthor` into `threadHandlers(scrollProxy:)` (the
  `openAuthor()` helper + its other `AO3AuthorBylineView` use had already
  auto-merged cleanly).
- Unstaged `.idea/`/`android/` that `git add -A` swept in (untracked by
  convention, unrelated to either branch).
`Scripts/verify.sh` ALL GREEN: **315 tests / 36 suites** (298 + 17 new author
fixtures), invariants, lint (pre-existing warning thresholds only), iOS +
macOS builds, whitespace. Sim rebuilt/relaunched. **Pending owner visual pass**
of author-profile navigation (tappable bylines everywhere, Works/Series/
Bookmarks/About tabs) layered on top of the still-pending comment-thread
review below.

### IN PROGRESS: final sanity review of comment-ui-refinement
Picked up from an agent that hit its usage limit mid-review. 16 branch commits
+ a large uncommitted final-polish diff got committed since (`ba10450`,
`e849e85` — real-page tombstone handling, avatar trademark guard, highlight/
sort/CTA/padding fixes from an owner live-testing pass). Full suite green
(298 tests, pre-cherry-pick) including a real-page sanity probe
(`ZZZRealPageSanityProbe.swift`, since deleted per its own throwaway
convention) against 4 captured live AO3 pages at
`/private/tmp/claude-501/.../39f686ea.../scratchpad/ao3_real/` (118 comments,
9 levels deep, 68 pages, 4 deleted-comment tombstones — all pages that
prompted this probe are LOCAL scratch files, not committed).
An adversarial-review workflow (6 dimensions: truncation-probe geometry
feedback loops, reply-expansion state/List-recycling, focus-scroll race,
session-identity cache keys, parser edge cases on real markup, geometry/theme
drift) was launched **twice** and **both times all 6 finder agents hit the
session usage limit** before producing findings — no confirmed/refuted
results exist yet. One concrete gap already found+fixed manually (not via the
workflow): the probe's own invariants didn't account for deleted-comment
tombstones; fixed by asserting on tombstone shape explicitly rather than
loosening the check.
**Next: re-run the 6-dimension adversarial review** (script cached at
`wf_4d797c52-100` — `Workflow({scriptPath, resumeFromRunId: 'wf_4d797c52-100'})`
replays anything already computed) once the usage window resets, THEN address
any confirmed findings, THEN this cherry-picked author-profiles work should
get its own pass too (it wasn't in scope for the original 6 dimensions).

### DONE: T-84 comment-UI restoration (merge clobber) — `20d6f74`
Owner caught that "comment ui fixes in the other branches aren't in this one."
Root cause: merge `b684e54` resolved `CommentThreadRow.swift` to the OLDER
T-85 nesting version, discarding the same-day owner-corrected T-84 rounds
(3d573c8/96b1827/08446cc — connector geometry, avatar-in-bubble). Every branch
was ancestry-contained but content was lost (rev-list can't catch this; tree
diffs + chronology did). Restored bbf3116's file + grafted T-85's
`AO3CommentTimestamp.displayText` rendering into T-84's placement; geometry
test now pins T-84's occlusion invariant. Consciously dropped (documented in
COMMENTS_HANDOFF.md, recoverable from d0a51ea): T-85's branched ancestor
connector drawing. verify.sh ALL GREEN 282/33. **Merge-clobber audit of the
whole stack:** only 3 merges exist; signature audit confirmed all other
features' content intact (initialChapterPosition/loadInitial/ao3StoryChapter/
parseFandomIndex/AO3SessionHealth/verifySession/CollectionWorkPicker/
readingState). CommentThreadRow was the only casualty.

### Branch-consolidation readiness (owner asked)
All branches (local + origin) are fully contained in `merge-test`; `main` is a
strict ancestor (fast-forward possible); android branch excluded per owner.
Remaining gates before consolidating: owner visual pass of the restored
comment thread UI, T-82 live-session write checklist, BUG-5 device retest,
drag-reorder still pinned/broken (rides as known-open).

### DONE: BUG-5 second root cause — fandom-index parse balloon — `9ab14c2`
Fixed, verified (282/33 green), empirically re-measured (peak 1.33GB → 427MB,
parser byte-identical on real pages), committed, BUG-5 entry updated.
**Owner must rebuild/reinstall on the iPhone to pick it up.** Details below
kept for the record:

### (diagnosis record) BUG-5 second root cause — fandom-index parse balloon
Owner re-reported Browse CPU/memory balloon → jetsam on iPhone 17 Pro, AFTER
`685c8a3` (view-side stats-storm fix). **Reproduced empirically in the sim**
(merge-test build, fandom disk cache wiped, tapped Browse via computer-use,
1 Hz `ps` sampler): RSS 330MB → **1.25–1.33GB in ~10s**, CPU pegged ~100%;
sim survives (footprint peak 982MB then settles ~105MB), a phone jetsams.
`sample` hot stacks (`/tmp/kudos_sample2.txt`): the cost is INSIDE
`AO3Client.fandoms(atPath:)` — SwiftSoup full-DOM parse of each multi-MB
`/media/<cat>/fandoms` page, then `li.select("a.tag")` PER `<li>` (14k+ per big
category), each triggering vendored SwiftSoup's
`rebuildQueryIndexes…`/`traverseElementsDepthFirst` over the giant tree —
quadratic CPU + massive transient allocation churn, ×3 concurrent categories.
**Fix (uncommitted, verify.sh running `/tmp/verify_bug5b.log`):**
1. `AO3Client.parseFandomIndex(_:)` — linear string-scan extractor (no DOM),
   CSS-faithful class matching via `classList(in:)`; `fandoms(atPath:)` now uses
   it. +3 fixture tests in `AO3ClientTests`.
2. `FandomCatalog.loadMissing/refresh` persist PER landed category (was once
   after the whole group — a mid-load jetsam lost everything → refetch kill loop).
Baseline for post-fix A/B (SwiftSoup run's real-page counts): Movies 14,496 /
Books 14,212 / TV 11,558 / VG 8,342 / Anime&Manga 5,079 / Theater 1,796
(cache `fandom-catalog.json` 3.3MB; 4 categories failed that run → refetch).
Next: verify green → rebuild sim → cold-open Browse again → compare memory
curve + per-category counts (parser equivalence on real pages) → commit →
TASKS.md/BUG-5 update → owner rebuilds on device.

## Status snapshot (2026-07-09)

### Landed: Comments QoL — reader chapter-aware Comments button — `073a7f7`
On `feature/ao3-comments`. Owner-specified (`Comments_QoL_Reader_Chapter_Aware_Button.md`).
Tapping Comments from a reader opens By-Chapter on the AO3 chapter you're reading.
Reusable `[ReaderSection].ao3StoryChapter(forSpineIndex:)` (Preface/Summary→1,
chapter→own number, Afterword/post-story→last, empty/OOB→1) — reuses the T-76
normalization, no naive `spineIndex+1`. Both readers wired (Readium direct;
macOS via `AO3WorkActionsMenu`/`Model`). `CommentsModel.loadInitial` resolves +
clamps against `/navigate`, one GET + index, falls back to All when no index;
`isApplyingInitialContext` suppresses onChange double-loads. +7 tests (spec
matrix). verify.sh ALL GREEN, **272 / 33**. Mapping + manual checklist in
`docs/ai/COMMENTS_HANDOFF.md`. **Still merge-gated with T-82** (owner live pass).
Doc frames the full-feature **adversarial review as the next step** — not run yet.

### Landed: Phase 4 — Native AO3 Comments — `87ef7d0` / T-82 (⛔ merge-gated)
Owner-specified feature (mockups as direction, not pixel spec) built on
`feature/ao3-comments` off `release-hardening`. Full working notes, live-
verified endpoint table, respect rules, double-post design, scope-outs, and
the owner's manual test checklist live in `docs/ai/COMMENTS_HANDOFF.md` —
read that first when resuming. verify.sh ALL GREEN (265 tests / 33 suites).
**Do NOT merge** until the owner's live-session pass (post/reply/edit/delete +
double-post sims). Candidate follow-ups listed in the handoff doc.

## Earlier snapshot (2026-07-08, updated same day)

### Landed: Phase 3 item 9 (ReadingState enum) — `a4c844e` / T-81
Picked up Fable's complete-but-uncommitted ReadingState work (cut off by a
usage limit). Reviewed the full diff: `SavedWork.ReadingState`
(`.unread/.inProgress/.finished/.freedHistory`, exactly one true per work,
`.finished` wins even after the EPUB is freed) + `var readingState` +
`isInProgress` reimplemented via it (provably identical). Consumers updated
behavior-preservingly: `LibrarySectionKind` readingNow/finished shelves
(`== .inProgress`/`== .finished` ⟺ old `isInProgress`/`isFinished`);
`ReadingStatistics.hasStarted` now defers to `hasStartedReading` (a documented
strict-superset bug fix — old private re-listing missed the Readium locator,
undercounting iOS-only reads); History `@Query` predicate UNCHANGED (only its
comment), so the flagged History-vs-Finished product decision is sidestepped,
not made. Tests: +4 total (3 in `SavedWorkProgressTests`, 1 in
`ReadingStatisticsTests`; 244 → 248).
First `Scripts/verify.sh` run: ALL GREEN (`/tmp/verify_rs.log`, 18:03).

**Adversarial review (workflow `wf_1b4eef1d-e56`) triaged** — its verify agents
died on the same usage limit, so findings were re-verified inline by Fable:
- CONFIRMED + FIXED: `MediaBrowserView.hasBeenRead` re-rolled "started" from
  `isFinished || lastSpineIndex > 0` (missed Readium locator → iOS-only reads
  never surfaced recent fandoms). Now `isFinished || hasStartedReading`.
- CONFIRMED + FIXED: `WorkDetailView` keep-status text checked `!hasEPUB`
  before `isFinished`, labeling unfinished freed works "Finished." Now switches
  on `work.readingState` (finished wins; `.freedHistory` gets honest copy).
- REFUTED (left as-is): `ReadingStatistics.inProgressWorks` counts freed-but-
  unfinished works as in progress — intentional stats semantics (reading
  behavior, not shelf placement), not accidental drift.
- REFUTED by workflow: PersistenceSync keep-in-sync comment — already in sync.
Second full `Scripts/verify.sh` (post-review-fixes): ALL GREEN, 248/31.
Committed `a4c844e`, TASKS.md row T-81. **Pending owner sim verification**
(Library shelves, Work Detail keep-status line, Browse recent fandoms).

### Latest: Phase 5 item 16 (session health) landed — `a80e517` / T-80
Found a complete, coherent uncommitted session-health implementation on the
branch (AO3SessionHealth enum + verifySession() + Account UI row/button).
Verified it, added 4 regression tests (`ConfigurableAO3SessionValidator`
mock), fixed a test-authoring trap (the suite's `testSession` is computed —
mints a fresh `savedAt` per access; capture once per test), full verify.sh
ALL GREEN (244 tests / 31 suites). **Pending owner sim verification** like
everything else on this branch. Phase 5 items 15 (author profiles) and 17
(account reconciliation) remain unbuilt.

## Earlier snapshot (2026-07-08)

### Done + committed this session (pending the owner's manual sim verification)
Plan Branches A/B/C (BGTask, PreservedWork, CanonicalIdentity) and Branch D
(UI fix pass, 8 items) are landed per TASKS.md T-77. On top of that, this
session fixed a run of owner-reported UI bugs, each verified via full
`Scripts/verify.sh` and committed:
- `6d492ae` detailed-card outline position + blurred-row expand button + tap-to-reveal
- `4d8e904` carry dashboard selection into "see all" expanded lists
- `3db9862` hide "Tap to reveal" while in select mode
- `f65b052` D6 phantom empty-search back step
- `d204a6d` cache drill-down results so search Back never re-fetches (occasional blank page)

### PINNED / on hold (do NOT work these without owner say-so)
- **Branch E — Drag-to-Reorder**: owner reports it still doesn't work in
  carousels or compact/detailed views. Owner explicitly said "revisit later."
  Leave alone until asked.
- All the commits above are **pending the owner's own sim verification** — do
  not treat as closed.

### Owner's latest directive (this turn)
"Continue work on the plan. Use multiple agents if needed but document their
run state. Don't run verify agents before the code they verify is done. Keep
this plan_context.md updated so another agent can take over on a rate limit."

---

## The remaining plan = "After A/B/C: the rest of the backlog" (phases 2–8)

The plan doc's phases 2–8 were written 2026-07-07, BEFORE the big D3 selection /
`WorkBulkActionBar` work landed, so several assumptions are now stale. Ground
truth already established this turn:

- **Phase 2 item 12 (bulk add/remove/mark actions): largely DONE.**
  `WorkBulkActionBar` (`UIComponents/WorkBulkActionBar.swift`) already offers
  Save, Favorite, Save/Remove for Later, Add to Queue, Add to Collection, Mark
  Finished/Still Reading over a multi-selection, wired app-wide.
- **Phase 2 item 11 (add works from INSIDE a collection): STILL A GAP.**
  `CollectionDetailView` (`Features/Library/Collections.swift:114-121`) only
  shows "Add works to this collection from a work's page" — no in-collection
  "Add Works" entry point. `AddToCollectionView` already supports
  `init(works: [SavedWork])` (batch), so the picker plumbing exists.

A read-only reconnaissance workflow is being run to reconcile phases 3–8 the
same way before committing to a sequence. See "Agent/workflow run log" below.

---

## Agent / workflow run log

| # | Kind | Purpose | State | Output ref |
|---|------|---------|-------|-----------|
| R1 | Workflow (read-only recon, 5 parallel agents) | Reconcile backlog phases 2–6 vs current code | DONE — runId `wf_b406a42c-01f`. 2/5 returned clean; A/C/E hit StructuredOutput retry-cap flakiness (env, not prompt) | synthesis below |
| I1 | Solo implementation | Phase 2 item 11 — in-collection "Add Works" (`Collections.swift`) | DONE — committed `e54402e`, verify.sh ALL GREEN (240 tests), sim relaunched. TASKS.md T-78. **Pending owner sim verification.** | `AddWorksToCollectionView` + `CollectionWorkPicker` helper + entry points in `CollectionDetailView` + `KudosTests/CollectionWorkPickerTests.swift` |

Recon areas (one agent each): A=Phase2 in-collection "Add Works"; B=Phase3 ReadingState enum;
C=Phase4 comments read/reply; D=Phase5 author profiles/session health/account reconcile;
E=Phase6 update-detection wiring into filters/badges. Read-only — no verify pass needed.

(Update this table whenever a workflow/agent starts, finishes, or is superseded.)

---

## Reconciled backlog map (from R1 + direct recon)

- **Phase 2 item 11 — in-collection "Add Works": GAP, chosen as next chunk.**
  `CollectionDetailView` (`Features/Library/Collections.swift`) has no in-page
  entry to add existing library works; empty state just says "add from a work's
  page." `AddToCollectionView` already has batch `init(works:)` + membership
  toggle logic to mirror. Small, self-contained, additive, low-risk, does NOT
  touch pending-verification surfaces. **← implementing now.**
- **Phase 3 item 9 — ReadingState enum: not-built, S/low-risk, no deps, no
  collision.** Pure computed convenience over existing SavedWork booleans
  (`isFinished`/`isSaved`/`hasEPUB`/`isInProgress` etc.) — no schema change, no
  migration, backup format unaffected. Value only realized once consumers
  (History filter `AccountView.swift:227`, `LibrarySectionKind`,
  `ReadingStatistics`'s duplicated `hasStarted`) adopt it. Good SECOND chunk.
  Must stay orthogonal to the AO3 `Completion` (WIP-vs-complete) filter.
- **Phase 5 items 15-17 — not-built, larger.** Session-health (16) is smallest:
  `AO3AuthService` already has `LiveAO3SessionValidator.validate()` + status enum,
  but validation runs only once at launch — no on-demand re-verify / health badge.
  Author profiles (15) need parser changes (author username/href is currently
  discarded at `AO3Client.swift:618-630`) + a new scraper + view. Reconciliation
  (17) can build on existing `CanonicalWorkMerge` + `RemoteWorkBulkActions`.
- **Phase 4 (comments read/reply) & Phase 6 (update badges/filters): recon agents
  hit env flakiness — re-run or scope inline when those phases are reached.**
  Plan's prior notes: Phase 4 large/isolated (own planning pass); Phase 6 mostly
  wiring existing `hasUpdate`/`knownChapterCount`/`WorkUpdateChecker` signals into
  filter facets + card badges.

## Next action

Phase 2 closed (T-78); Phase 3 item 9 closed (T-81, `a4c844e`); Phase 5
item 16 closed (T-80, `a80e517`).
**Next chunk = wire `ReadingState` into the user-facing filters** — the value
the enum was built for (backlog items 10 + 19, the small end of Phase 6):
- Library filter panel: add a Reading State facet (`LibraryFilters` +
  wherever its facets render) filtering on `work.readingState`.
- Local reading-history filter (`LocalReadingHistoryView`,
  `AccountView.swift`): finished-vs-unfinished-history split.
- Keep orthogonal to the AO3 `Completion` (WIP-vs-complete) facet.
After that: Phase 6 items 18/20 (update badges into cards/filters — re-recon
first, agents were flaky) or Phase 5 item 15/17 (author profiles / account
reconcile, larger). Phase 4 (comments) needs its own planning pass.
Verify + sim + commit + TASKS.md row as usual.
