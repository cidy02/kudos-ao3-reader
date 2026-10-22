# A78: re-check W2's word differences against today's code

**Read only: change no code, commit nothing, sign in nowhere, contact no website, run no Gradle.**
Write `docs/android-port/audits/A78-result.md` FIRST and fill it in as you go.

`docs/android-port/audits/W2-result.md` (2026-10-09, another model) compares every reader-visible
and reader-audible string on eleven screen pairs ported on 10-08 and 10-09 (the work form, Edit
Tags, the chapters list and chapter form, the series form, the challenge sign-up, Account
shortcuts, author works sort fields, Library history grouping, favourite affinities, More on AO3,
and the rest it lists). A first check found it unreliable row by row (six invented differences,
one real), and much has changed since.

For **every** row W2 calls different, decide against this worktree's Android code (HEAD
`a5a2c7f4`, `android/app/src/main/java/io/github/cidy02/kudos/`) and iOS
(`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`):

- **same now**: quote the string once, with Android `path:line` and iOS `path:line`.
- **still differs**: quote both strings exactly, with both `path:line`, and say whether it is
  visible text or spoken only (accessibility label, hint, action name).
- **not applicable**: a platform matter (say which), or a decision in
  `docs/android-port/DECISIONS.md` (quote its date and title).
- **W2 was wrong**: the string it quoted does not exist on that side; say what is there.

Then, for each of the eleven pairs, list any visible or spoken string on iOS that W2 missed and
Android lacks or words differently today (same evidence standard). Open the code; a verdict
without a `path:line` on both sides does not count. End with the list of **still differs**
items, the ones a reader sees first, and the counts.
