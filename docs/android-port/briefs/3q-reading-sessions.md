# Brief 3q: the Android reader records reading sessions, as iOS does

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind. **Don't change the Room schema or the backup format**: the `reading_sessions` table and its
backup mapping already exist and already round-trip with iOS. Your sandbox can't run Gradle; Claude
builds and tests afterwards, so make it compile by reading the real symbols you use.

**The gap.** Android stores reading sessions (`data/local/entity/ReadingLogEntities.kt`,
`data/local/dao/ReadingLogDao.kt`) and restores them from backups, but nothing ever writes a new
one: the only caller of `upsertSession` is backup restore. So Reading Insights' time figures
(`library/ReadingStatistics.kt`) never grow from reading on Android.

**Do this:**

1. Read iOS `kudos-ao3-reader/Services/ReadingLogService.swift` end to end (the iOS lane is
   `/Users/cidy02/kudos-ios-polish`): `startSession`, `endSession`, and everything they call. Find
   every call site in the iOS reader and app lifecycle. In your result, state the rules exactly:
   when a session starts, when it ends, the minimum length that is kept, how an interrupted or
   backgrounded session is closed, what is stored (ids, dates, durations, progress), and how
   privacy or incognito settings affect it.
2. Port those rules to Android: a small `ReadingLogService` (or the name Android's conventions
   suggest) over `ReadingLogDao`, and calls from the Android reader (`reader/`) at the same
   moments: open, close, background, foreground. Match iOS's stored values field for field, since
   the rows go into backups that iOS reads.
3. Unit-test the rules with a fake clock, mirroring iOS's tests for `ReadingLogService` if there
   are any (`KudosTests/`): start then end, too-short sessions dropped, a session left open and
   closed on the next start, and whatever else iOS covers.
4. Don't change what the reader looks like or how it navigates.

Write `docs/android-port/briefs/3q-result.md`: the rules from step 1, each Android call site with
its iOS counterpart, anything iOS does that you didn't port and why.
