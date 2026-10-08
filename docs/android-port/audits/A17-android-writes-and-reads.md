# Audit A17: Android, every write to AO3 and every read that repeats

**Read-only.** Work only in this worktree. Change no source file. Do not build, commit, push,
switch branches, sign in or contact archiveofourown.org. Write exactly one file:
`docs/android-port/audits/A17-result.md`. No helper scripts left behind.

The code to audit is the Android app under
`android/app/src/main/java/io/github/cidy02/kudos/` (Kotlin). iOS is the reference for
behaviour, at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only). The rule book
is `docs/AO3_NETWORKING_POLICY.md` (its "must not implement" list is binding). What is
recorded as decided or left out is in `docs/android-port/DECISIONS.md` and
`docs/android-port/briefs/*-result.md` with their landing notes.

You are hunting for **bugs**, not style. The same audit of iOS (`audits/A4-result.md`, read
it with its triage first) found six, and the second pass over the string checks
(`audits/A14-result.md`) found three on Android that show what to look for here:

- a confirmation that says "Delete from History" and then only hides the row on the device:
  AO3 is never told (`account/AccountWorksListScreen.kt`, near the delete confirm);
- a button "Clear {n} Work(s)" whose message says saved and downloaded works are not
  affected, and whose action soft-deletes every finished work (`settings/PrivacyDataScreen.kt`,
  `WorkRepository.softDeleteAllFinished`);
- a row "Clear reading positions" whose click does nothing.

## What to read

1. **Every write to AO3**: `network/ao3/writes/AO3WriteRepository.kt` and its parser and
   URLs, `network/ao3/comments/` (post, edit, delete, the unconfirmed-post handling),
   `account/` view models that call them (inbox actions, collections: form, items,
   moderation, maintainers, Your items; the tag set's two writes; prompt meme Claim and
   Release; the challenge sign-up), `network/ao3/account/`, preferences
   (`account/AO3Preferences*`), login and logout (`auth/`), kudos, bookmark, subscribe,
   mark for later, history. Find the rest with `postAuthenticated`, `postForm`, `"_method"`.
   For each: is the token fresh and from the page iOS takes it from; can the request be sent
   twice (a double tap, a recomposition, a `LaunchedEffect` restarting, a refresh in
   flight, a retry policy that covers POSTs); is a refusal told apart from success, and an
   unconfirmed reply from both; does the screen change before AO3 confirms; is typed input
   kept on every failure; does a control that says it writes to AO3 really do so.
2. **Every read made more than once or in a loop**: pagers that walk pages by themselves,
   enrichment reads per row or per work, reads repeated on recomposition or on returning to
   a screen, reads made for a viewer AO3 will refuse, reads with no cap the policy names.
   `network/ao3/` repositories, `account/`, `author/`, `search/`, `browse/`, `home/`,
   `works/` (the availability sweep, metadata refresh, series), `update/`.
3. **Local actions that destroy or hide data**: every "Clear", "Delete", "Remove", "Reset"
   and "Free" in `settings/`, `library/`, `works/`, `account/`: does it do what its words
   say, exactly that set of rows, with the confirmation iOS has, soft where iOS is soft.
4. **The session**: a result applied after sign-out or after another account signed in; a
   private page cached and shown to the next account; cookies or tokens written to a log, a
   backup or a crash report.

## What counts as a finding

P1: sends something wrong to AO3, loses or hides a reader's data, or leaks a session. P2:
wrong behaviour a reader meets (a control that lies, a write reported as done that was not,
a read the policy forbids). P3: the rest. Not findings: formatting, naming, "could be
simpler", anything recorded as decided or as left out (cite the line if you rely on that).

## The result file

Start with a table: id, severity, `path:line`, one-line statement. Then one section per
finding: the exact code (quote it, with `path:line`), the iOS code it is checked against
(`path:line`), **a concrete failing case** (taps or inputs, then what happens and what
should), the policy line it breaks if any, and the smallest fix you would make. If you could
not confirm a suspicion by reading, put it under "Unconfirmed" with what would confirm it.
End with what you did not read.

Quality over count. A wrong file or line makes the whole report untrustworthy. Check any
claim about a language or library rule (Kotlin coroutines, Compose, OkHttp, Room) before
resting a finding on it.
