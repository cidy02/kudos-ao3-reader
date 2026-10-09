# Audit A25: iOS test rules with no Android test, for parsing, backup and sync

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A25-result.md`. No helper scripts or scratch files left behind.

iOS tests are at `/Users/cidy02/kudos-ios-polish/KudosTests/` (read-only). Android tests are in
this worktree under `android/app/src/test/java/io/github/cidy02/kudos/`, and the code they test
under `android/app/src/main/java/io/github/cidy02/kudos/`.

`docs/android-port/audits/A16-result.md` lists every iOS test suite and how many of its tests
have an Android test **of the same name**. A name is a weak signal: Android often tests the
same rule under another name, and sometimes not at all. This audit settles that for the two
groups where a missing rule costs most: **"AO3 parsing"** and whichever groups hold the
**backup, restore, sync and tombstone** suites (every suite whose file name contains
`Backup`, `Sync`, `Tombstone`, `Restore`, `Merge` or `Persistence`).

For each suite in those groups, in A16's order:

1. Open the Swift file. For **each test function**, write one line: its name, and **the rule
   it pins**, in plain words (what input, what must come out). Group tests that pin the same
   rule.
2. Find where Android has that code (name the Kotlin file) and where its tests are. For each
   rule say one of:
   - **covered**: an Android test pins the same rule. Name the test and its `path:line`.
   - **weaker**: an Android test touches it but would still pass if the rule broke. Say what
     input it lacks.
   - **uncovered**: Android has the code and no test of the rule. Name the function.
   - **no code**: Android does not have the feature the rule belongs to. Name the feature.
3. For every **uncovered** and **weaker** rule, quote the Swift test's essential lines (the
   input and the expectation), so that the Android test can be written from them.

Finish with a table: suite, tests, covered, weaker, uncovered, no code; then the list of
uncovered rules ordered by what a failure would cost (a wrong merge or a lost record first,
then a parse that silently drops data, then the rest).

**Do not report a rule as uncovered without having searched the Android tests for the
function under test and for the fixture or input the Swift test uses.** Say how you searched.
Exact files and lines only.
