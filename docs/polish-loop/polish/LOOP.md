# Polish loop — one iteration

Owner, 2026-09-28: pace yourself with /loop; thorough; every screen: "Does this fit the app,
does this empower the user, is it one cohesive design philosophy consistent with the rest of
the app, and is this something Apple would be proud to ship?" Checklist + batches: PLAN.md.
Tracker: STATUS.md (update every iteration). Lane: .claude/worktrees/polish
(branch claude/polish-loop), DerivedData under ~/Library/Developer/Xcode/DerivedData/kudos-polish
(never inside ~/Documents — iCloud). Integrate: integrate/cloud-redesign.

Each iteration, in order:
1. Collect: finished auditor results (grok-delegate/grok-*.log json['text'], codex result
   <job>) → save to polish/batch-N-<who>.md. Owner messages since last iteration → add to
   STATUS.md "Owner asks" and do those FIRST.
2. Launch: keep ≤2 auditors busy (Grok task / Codex task --write, prompt-batch-N.md template)
   on the next unaudited batches. Rotate so each batch gets one external auditor; Claude
   audits one batch itself per iteration against its artboards.
3. Verify: every finding against the code AND the artboard before accepting. Reject with a
   reason in STATUS.md; never fix what you did not confirm.
4. Fix: in the lane, one commit per coherent group; shared components over per-screen hacks;
   reuse existing mechanisms (grep first). Add a test for any logic; UI-only changes go on
   the device-check list.
5. Gate: materialize dataless files (find -flags +dataless | cat) → build-for-testing +
   test-without-building (-parallel-testing-enabled NO, touched suites) → macOS build →
   Scripts/lint.sh (0 errors, ≤125 warnings) → pbxproj churn reverted.
6. Land: cherry-pick onto integrate (TASKS.md conflicts: keep both, dedupe rows), install on
   the iPhone (DEVELOPMENT_TEAM=NQH85H7343 on the command line only), record in STATUS.md
   and TASKS.md (T-row per fix group), tell the owner in 3–6 lines what changed + what to look at.
7. Screenshots: with the DEBUG demo library (-KudosDemoLibrary YES -hasCompletedOnboarding YES)
   on the Lane E simulator, screenshot each local screen touched and look at it before claiming
   it matches.
Stop when every batch has: external audit done, Claude audit done, all accepted findings fixed
or explicitly deferred with a reason; then run pass 2 (cross-screen sweep of checklist B/C/D),
then a final full-suite + device install + owner summary.
Never: contact archiveofourown.org, sign in, push, merge to main, force/reset/delete branches.
