# A38: the challenge settings edit form (brief 3cf), as landed, read against iOS

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A38-result.md`. No helper scripts left behind.

This worktree holds the landed code. Commit `4f2bc028` added the form: see it with
`git show 4f2bc028 --stat` and `git show 4f2bc028 -- android/app/src/main`. Codex wrote it and
its own account is `docs/android-port/briefs/3cf-result.md` (with Claude's landing note at the
foot, which says what was **not** read line by line: `network/ao3/account/AO3ChallengeSettingsForm.kt`,
`account/AO3ChallengeSettingsEditState.kt`, `account/AO3ChallengeSettingsEditScreen.kt`).
iOS, the reference, is at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only):
`Features/Challenges/ChallengeSettingsEditView.swift`, `ChallengeSettingsEditSections.swift`,
`Models/AO3ChallengeModels.swift`, `Models/AO3ChallengeScreenModels.swift`,
`Services/AO3Client+Challenges.swift`, `Services/AO3ChallengeActions.swift`.

Claude will review those three files; what helps is an **index of where to look**. So: every
row must quote the Kotlin (`path:line`) and the Swift (`path:line`) it compares. A row without
both quotes is worth nothing: leave it out. Never write "absent" or "missing" without naming
the files you searched and the words you searched for.

Check, in this order, and stop where you run out of time (say where):

1. **Requests.** For one opening: each request Android makes, in order, beside each request
   iOS makes, for a gift exchange and for a prompt meme. Then each write (the challenge Save;
   the collection Save that may follow): the address, and every field name and value, beside
   iOS's. Any request Android makes that iOS does not, and the reverse.
2. **What a row edits.** For every row of the form in iOS's order: the Swift property it
   changes and the form field that property is sent as, beside the Kotlin control name the
   same row changes. A row whose Kotlin control name differs from the Swift field name is the
   most valuable thing you can find. A row one side has and the other lacks.
3. **Validation before sending.** Each check `validated()` makes on iOS (deadline order,
   limits) beside Android's, with each message word for word.
4. **Verdicts.** What Android takes as saved, refused and "not confirmed" for each write
   beside iOS's code; each message, word for word.
5. **Words on screen.** Every string in `AO3ChallengeSettingsEditScreen.kt` beside iOS's
   string for the same place; list only the ones that differ, with both quotes.
6. **Second taps, stale answers, the reveal question.** What stops a second Save while one is
   out; what stops an answer that arrives after a session change being shown; exactly when
   "Reveal now?" is asked on each platform (quote both conditions).

End with a table: number, severity as you see it (P1 a wrong or doubled write, or a field
sent under the wrong name; P2 a wrong read, verdict or word; P3 the rest), the two
`path:line`, one line.
