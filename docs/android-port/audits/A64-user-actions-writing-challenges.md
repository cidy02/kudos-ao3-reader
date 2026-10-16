# A64: every action a writer can take, iOS against Android (Writing, Challenges)

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file: `docs/android-port/audits/A64-result.md`.
**Write the priority list first and keep it current.** Do not edit `TASKS.md`.

A52 to A61 compared iOS's **tests**; A62 and A63 compared the reading and account screens'
actions. This audit compares the actions a writer or a collection maintainer can reach. Owner direction (binding): "Layout, content, order of information
and behaviour stay in step with iOS. Navigation and chrome controls are Android's own." So a
missing action, or one that does something different, is a finding; a different-looking
control for the same action is not.

iOS (read-only): `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/` `Writing/` and `Challenges/` only. Android:
this worktree at the lane HEAD named in the dispatch. Read DECISIONS.md's entries from
2026-10-10 on first: some differences are recorded decisions, not findings.

For each iOS screen in those folders, list every user action it offers: buttons, menu and
context-menu items, swipe actions, long presses, toolbar items, sheet actions, empty-state
actions, keyboard shortcuts that have a touch equivalent. For each, find Android's (quote both
sides, `path:line`) and mark it **same**, **different** (say what a reader would notice),
**missing**, or **Android only**. Note the confirmation, the undo and the message after it,
where iOS has one.

## Report

The priority list first: the **missing** and **different** actions worth fixing, one line
each, most harmful first (anything that loses a reader's place, text or work; anything that
acts on the wrong work or without the confirmation iOS asks for; anything sent to AO3 that the
writer did not write; then missing features; then wording). Then one table per screen. Say plainly where Android is right.

Work screen by screen and write each screen's table as you finish it, so a time limit leaves
what is done. Quote `path:line` on both sides or mark the row **unsure**.
