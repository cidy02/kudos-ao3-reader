# ADVERSARIAL_REVIEW_TEMPLATE.md — how to review changes in this repo

Every merge-bound branch gets an adversarial review (AGENTS.md rule). This is the
methodology that caught the real bugs of the 2026-07 cycle (ghost rendering, revive-on-
reacquire, macOS blur leak, EXDEV staging, dismissal-ordering, silent batch failures).
Any model can run it — the structure does most of the work.

## Principles

1. **Review the tree, not the report.** Run `git diff`/`git status` and read files.
   Implementation summaries are claims, not evidence.
2. **One reviewer per concern, plus one cross-cutting critic.** Per-concern reviewers
   verify a specific claim; the critic hunts damage BETWEEN concerns (same file edited
   twice, scope creep, stage-on-stage reverts) that per-concern reviewers can't see.
3. **Try to refute, not confirm.** Enumerate alternative causes/failure modes and rule
   them out in code. A diagnosis is CONFIRMED only when alternatives are excluded.
4. **Findings need a failure scenario.** No file+line+concrete-user-impact → not a
   finding. Style nitpicks are noise here.
5. **Check both platform branches** (`#if os(iOS)` / macOS `#else`) — the macOS blur
   leak hid in an `#else` the iOS-focused fix never touched.
6. **Grep every call site of anything shared you changed** (components, services,
   initializers). Compile success ≠ behavior preserved.

## Per-concern reviewer prompt skeleton

```
Adversarially verify against the ACTUAL working tree (run git diff / read files —
trust no summary): "<the claim, stated precisely>".
Hunt specifically for:
- <the 3–6 most plausible ways this exact change breaks, written by someone who
  knows the pitfalls in docs/AGENT_ONBOARDING.md>
- every call site of <shared things touched> (grep them yourself)
- the invariants in docs/DATA_AND_PERSISTENCE_INVARIANTS.md / AO3_NETWORKING_POLICY.md
  that this area touches
Report ONLY real behavioral defects: file, line, one-sentence summary, concrete
failure scenario (inputs/state → wrong outcome), severity (blocker / real-bug / minor).
```

## Cross-cutting critic prompt skeleton

```
You are the regression critic for a multi-part change to one working tree. Run git
status + git diff yourself. Ignore per-part correctness (others cover it); hunt ONLY:
files edited by two parts with conflicting assumptions; edits outside the declared
scopes (<list the parts' file scopes>); stray debug leftovers; lint regressions
(run Scripts/lint.sh); lost accessibility labels on touched controls; TASKS.md/docs
statements the diff just made false.
```

## Verdict discipline

- `CONFIRMED` = alternatives ruled out in code. `PLAUSIBLE` = consistent but unproven
  (say what would prove it). `REFUTED` = state the actual cause.
- Mark anything you could not empirically check (e.g. runtime presentation order) as
  an explicit caveat — don't silently promote it to fact.
- Fixes applied in response to findings get re-verified (at minimum `Scripts/verify.sh`).
