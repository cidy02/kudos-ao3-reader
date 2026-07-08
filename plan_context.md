# Plan Context — live handoff doc

**Purpose:** running record of where "continue the plan" work stands, so another
agent (or a fresh session after a rate limit) can take over without re-deriving
context. Update this **as you go**, not at the end.

Canonical plan: `/Users/cidy02/.claude/plans/agile-forging-moon.md`
Task board: `TASKS.md` (repo root). Onboarding: `docs/AGENT_ONBOARDING.md`.
Definition of done: `Scripts/verify.sh` (invariants → lint → full iOS suite →
macOS build → whitespace).

Working branch: `release-hardening`. Simulator: iPhone 17,
id `77492544-056E-4D4A-ABB6-7E38CC042A4D`, bundle `com.cidy02.Kudos`.

---

## Status snapshot (2026-07-08, updated same day)

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

Phase 2 closed (T-78); Phase 5 item 16 closed (T-80, `a80e517`).
**Next chunk = Phase 3 item 9: `ReadingState` enum.**
Per R1 area B: a pure computed convenience on `SavedWork` (`.unread/.inProgress/
.finished/.freedHistory`) folding the existing booleans (`isFinished`/`hasEPUB`/
`isInProgress`/queue/history predicates) in ONE place — no stored @Attribute, no
schema change, backup format untouched. Keep existing `isInProgress`/
`hasStartedReading` working. Then (optionally, incrementally) refactor the three
drifting consumers to read `work.readingState`: `LibrarySectionKind.works(from:)`,
`ReadingStatistics` (deleting its duplicated `hasStarted`), and
`LocalReadingHistoryView`'s @Query (`AccountView.swift:227`). MUST stay orthogonal
to the AO3 `Completion` (WIP-vs-complete) filter — different concept. S / low-risk.
Verify + sim + commit + TASKS.md row as usual.
