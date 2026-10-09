# Audit A29: the rules A25 found no Android test for, checked against Android's code

**Read-only.** Work only in this worktree. Change no source file. Do not build, commit, push,
switch branches, sign in or contact archiveofourown.org. Write exactly one file:
`docs/android-port/audits/A29-result.md`. No helper scripts left behind.

`docs/android-port/audits/A25-result.md` (yours) lists, for iOS's parsing, backup and sync
tests, each rule and whether an Android test pins it: 127 are marked `[uncovered: …]` and 9
`[weaker: …]`. A missing test is not a bug. **A missing rule is.** This audit finds the
missing rules.

iOS is at `/Users/cidy02/kudos-ios-polish/` (read-only): tests in `KudosTests/`, code in
`kudos-ao3-reader/`. Android is this worktree: `android/app/src/main/java/io/github/cidy02/kudos/`.

## What to do

For **every** rule A25 marks `[uncovered]` or `[weaker]`, in A25's order:

1. Read the iOS test (the whole test function, not only the line A25 quotes) and state the
   rule in one sentence: given what input, what must come out.
2. Find the Android code that would have to implement it (A25 names a function for most; check
   it, and look further if it is wrong). Read that code.
3. Give one verdict, with the Android `path:line` you read:
   - **implemented**: Android's code does the same thing for that input. Quote the line that
     does it.
   - **differs**: Android does something else for that input. Quote both sides and give the
     concrete input and the two outputs.
   - **absent**: Android has no such code (the feature is not there, or the case is not
     handled and would throw, drop the row or fall through). Say which, and what a reader
     would see.
   - **not applicable**: the rule is about an iOS-only thing (SwiftData, the Files app, a
     SwiftUI view). Say why in a few words.
4. Do not trust a function's name or its comment: read its body. If you did not read the
   code, write **not read** and why; never guess a verdict.

## The result file

Start with three counts (implemented, differs, absent, not applicable, not read) and then a
table of **only** the `differs` and `absent` rows: the iOS test's name and file, the rule in
one sentence, the Android `path:line`, the concrete input and the two outputs, and a severity
(P1 loses data or sends something wrong to AO3; P2 wrong behaviour a reader meets; P3 the
rest). Then one line per remaining rule in A25's order: test name, verdict, Android
`path:line`. Quality over count: a wrong file or line, or a verdict given without reading the
code, makes the report useless.
