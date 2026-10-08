# Brief W1: Android's wording brought to iOS's, one mechanical batch

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never
sign in and never contact archiveofourown.org; no helper scripts or scratch files left behind
(work in memory or under `/tmp`); don't edit `TASKS.md`. You cannot run Gradle: Claude builds
and tests afterwards, so change only string literals and make no other edit.

## The job

`docs/android-port/audits/A14-result.md`, section "4. W — same thing, different words", is a
table: an iOS string with its `path:line`, the Android string with its `path:line`. For each
row, change the Android string to iOS's wording, **exactly** (capitals, punctuation, the
ellipsis character, curly or straight apostrophes as iOS has them).

Open each Android file and find the string at or near the line given (the lines may have
moved a little: search for the string). Change only that literal.

**Skip a row, and list it, when:**

- iOS's words name something Android does not have or names differently: the Files app,
  iCloud, Face ID, "shake your device", the App Store, a Mac, a swipe that Android does not
  use, "tap and hold" where Android says "long-press";
- the file says, in a comment at that string, that the wording is deliberate, or
  `docs/android-port/DECISIONS.md` records the rewording (search it for a few words of the
  string): cite the line;
- the Android string is built from a pattern or shared by other screens where the new words
  would be wrong (say which);
- you cannot find the Android string.

If a test under `android/app/src/test/` contains the old Android string as an expectation,
change it there too, to the same new words, and list the test.

## The result file

Write `docs/android-port/briefs/W1-result.md`: a table of every row with "changed" (Android
`path:line`, old, new) or "skipped" (the reason), then the tests you touched. Nothing else.
