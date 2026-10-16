# Brief 3fm: A59's remaining rows (Marked for Later, Subscriptions, Dashboard, comments polish)

Rules (binding): work only in this worktree (`~/kudos-agent-codex`, branch
`android/agent-codex-3fm`, at the lane's HEAD named in the dispatch); don't commit, push, or
switch branches; never sign in and never contact archiveofourown.org; no stub files; no helper
scripts or `.orig` files left behind; **don't edit `TASKS.md`**. No Room schema or
backup-format change (stop and say so if one seems needed). Your sandbox can't run Gradle:
Claude builds, tests and commits, so make what you write compile (`SavedWork` needs an
`author`; give test works a fixed millisecond `dateAdded`, since Room keeps milliseconds).
**Write your result file early and keep it current**, so a usage limit cannot leave it empty:
`docs/android-port/briefs/3fm-result.md`. Binding: `docs/AO3_NETWORKING_POLICY.md`.

Your A59 (`docs/android-port/audits/A59-result.md`; read Claude's triage at its top). Claude has
fixed the six priority items, the account-safety rows and most of this brief's first list
(DECISIONS.md, 2026-10-15 entries, says which). **What is left**, in this order; for each,
confirm it against the code at HEAD first, then fix it as iOS does
(`/Users/cidy02/kudos-ios-polish/`, read-only) with a test porting the iOS assertion, or say
why it isn't real. Stop where you run out of time and say where.

1. `AO3MarkedForLaterScreenTests.allSplitsUpdatedAheadOfEverythingElse` and
   `narrowedPillsAreOneList`: the grouping is right at HEAD, but iOS draws the "Updated since
   you looked" run (and the Updated pill) as **covers** and the rest (and Downloaded) as the
   **ledger** (`AO3MarkedForLaterWorksBrowser.swift`); Android draws every run as the ledger.
2. `CommentPolishTests.theTrayIsFourColumnsUntilAccessibilitySizes`: the formatting tray as
   iOS's grid (`CommentFormattingLayout`: four columns, gap 7, tiles at least 58 tall with
   inner padding; two columns at the first two accessibility sizes, one from the third), where
   Android's `CommentFormattingTray` is a `FlowRow` of chips. Font scale stands in for
   Dynamic Type; say which scales you map to which.
3. `AO3TagAutocompleteTests.canonicalAndCountAreParsedWhenPresent`: keep AO3's `canonical` and
   `work_count` and show them in the writing tag picker as iOS's `WritingTagsEditor` does
   (the canonical badge or "posts as typed", and the count).
4. `AO3AuthorProfileTests.parsesSeriesAndBookmarkMetadata`: series creators as identities with
   their pseud routes (anonymous with none), and a bookmark's collections, as iOS parses and
   shows them (`AuthorProfileComponents.swift`).

Then, if time is left, a **second review** of what Claude landed alone today (read-only for
these; findings into your result file with `path:line`): `127654f3`, `cf6d1bcd`, `8667d16a`,
`15897e0a`, `3138771b`, `24e02912`, `c1e910e1`, `7db6b987`, `8afbc2b4`, `73039199`.
