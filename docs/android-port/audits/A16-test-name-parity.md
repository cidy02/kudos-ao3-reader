# Audit A16: iOS tests with no Android test of the same name

**Read-only.** Work only in this worktree. Change no source file. Do not build, commit, push,
switch branches, sign in or contact archiveofourown.org. Write exactly one file:
`docs/android-port/audits/A16-result.md`. **Leave no helper files behind**: work in memory or
under `/tmp`, and delete anything you create except the result.

This is a mechanical check, and its value is exactness. Report only what you found by
searching; never infer, never invent a line number.

## The check

The Android port's convention is that a rule ported from iOS brings its test **with the same
name** (iOS `@Test func theSameWordsFurtherDown…()` in `KudosTests/*.swift` becomes Android
`fun theSameWordsFurtherDown…()` under `android/app/src/test/`).

1. List every iOS test function: in `KudosTests/*.swift`, each `@Test func name(` (the
   attribute may be on the previous line, and may carry arguments) and each `func testName(`
   in an `XCTestCase`. Record the suite (the enclosing `struct` or `class`), the file and the
   line.
2. For each, search `android/app/src/test/` for a Kotlin test function with **exactly** that
   name (`fun name(`), then for one whose name differs only by a leading `test` or by
   backticks. Record the Android `path:line` if found.
3. Group the iOS suites by what they test, from the suite's name and its file's header
   comment: AO3 parsing; AO3 writes; reading progress and the reader; annotations; backup,
   restore and sync; library, queues and collections; search and filters; comments; writing;
   challenges; settings and privacy; speech; everything else.

## The result file

1. Counts: iOS suites, iOS test functions, with an Android test of the same name, without.
2. Per group, a table of the **suites** (not every function): suite, file, iOS tests in it,
   how many have an Android namesake, and the names of up to eight that do not (the ones
   whose names state a rule about data, a request to AO3, or a merge, first).
3. The ten suites with the most tests and **no** Android namesake at all, with their file
   and header comment quoted, so a reader can tell whether Android has the feature.
4. What you did not read.

Do not judge whether Android tests the rule under another name: that is a later pass.
