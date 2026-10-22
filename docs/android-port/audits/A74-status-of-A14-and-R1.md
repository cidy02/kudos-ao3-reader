# A74: which of A14's and R1's open items are still open today

**Read only: change no code, commit nothing, sign in nowhere, contact no website.** Write
`docs/android-port/audits/A74-result.md` FIRST and fill it in as you go.

Two earlier audits left lists of Android work to do on 2026-10-08:

- `docs/android-port/audits/A14-result.md`, its "Triage" section at the foot: **missing
  features to brief** (eleven), **behaviour to bring in line** (seven), and **the 46 wording
  rows** (the table above the triage: rows classed "worded differently").
- `docs/android-port/audits/R1-result.md`: eleven missing features, of which two were done then
  (More on AO3, Share Profile) and one is not to be ported; "four small ones" and "four medium
  ones" remain (see its triage).

A great deal has landed on Android since (`git log --oneline 0f7a835c..HEAD` is only the last
day; `git log --since=2026-10-08 --oneline -- android | wc -l` shows the scale). Many items are
probably done. Your job is to say, for **every** item, which it is now, against this worktree's
code (HEAD `cd04b55a`) and iOS (`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`):

- **done**: Android now does what iOS does. Give the Android `path:line` that does it and the
  iOS `path:line` it matches.
- **open**: still missing or still different. Say exactly what iOS does (`path:line`) and what
  Android does instead (`path:line`, or "no code"), and what a fix would touch.
- **not applicable**: say why (an iOS-only platform feature, a decision in
  `docs/android-port/DECISIONS.md` — quote its date and title).

For the 46 wording rows: compare today's exact strings on both sides; list only the rows whose
words still differ, with both strings quoted, and count the rest as done.

Be concrete; a claim without a `path:line` on both sides does not count. Do not guess from
file names: open the code. End with a summary table (item, verdict, one line) and the counts.
