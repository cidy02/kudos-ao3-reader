# Audit A20: bug hunt in what is left of the iOS app

**Read-only.** Change no source file anywhere. Do not build, commit, push, switch branches,
sign in or contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A20-result.md`. No helper scripts left behind.

The code to audit is the iOS app (Swift, SwiftUI, SwiftData) at
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`, with its tests at
`/Users/cidy02/kudos-ios-polish/KudosTests/`. Three audits have covered its writes to AO3
(`audits/A4-result.md`) and its reader, Library and backup (`audits/A12-result.md`), and Search, Browse, Home, the browser, the comment drafts and the privacy blur (`audits/A19-result.md`): read
their tables and triage notes first so you do not re-file them. The same audit of Android
(`audits/A18-result.md`) is worth reading for the kinds of fault to look for: the two apps
share their design, and a fault in one is often in the other. This audit is **everything
else a reader uses**:

- `Features/WorkDetail/` in full (the sheets, import and rebuild, metadata refresh, the
  series and collection actions, the bookmark and queue forms, what a tap on each row does
  to a work that is blurred, deleted or without a file)
- `Features/Authors/`: the moderation and subscription screens and their confirmations
  (block, mute, subscribe), and what each reports when AO3 did not confirm
- `Features/Comments/`: the thread layout and its pager, collapse and "load more", the
  inbox entry with a focused comment, reply and edit targets after a page change
- `Features/Search/`: the filter panel's draft fields and what Cancel, Apply and a dismiss
  each keep; saved-search persistence and its restore; the tag pickers and their reads;
  the native fandom index
- `Settings/` forms, `Features/Onboarding/`, `Features/Support/`, the login screens in
  `Features/Auth/` beyond the coordinator's delegate
- `Features/Account/AO3CollectionsList.swift` past the start of its fetch, and the other
  account lists' loads: is a page from a session that has ended ever applied?
- **Settle A19's five unconfirmed suspicions** by reading (its section "Unconfirmed"):
  each becomes a finding with a failing case, or is closed with the reason.

A19's ten findings have since been fixed there, in commit `86389972` on
`claude/polish-loop` (`git -C /Users/cidy02/kudos-ios-polish show 86389972` shows them; the
uncommitted changes in that working copy are a separate batch of text sizes: ignore them).
Do not re-file them. **Do review those fixes**: under a heading "A19's fixes", say for each
of the ten whether the change closes the failing case A19 gave, and file anything a fix
breaks or leaves open (the browser's navigation rule and the comment-draft hand-over
especially).

Android is at `android/app/src/main/java/io/github/cidy02/kudos/` in this worktree if you
want to see how the other app does a thing; it is not the reference here.

## What counts as a finding

1. **Crashes**: a force unwrap or `try!` on data that can be absent, an index out of range, a route or
   deep link decoded without a guard, SwiftData used off its actor, a parse of AO3's HTML
   that fails on a page the fixtures do not cover, work on the main actor that can be long, a
   continuation resumed twice or never.
2. **Lost input or state**: a composer, a filter or a form that forgets what was typed on
   rotation, on leaving and returning, or on a failed request; a draft saved under the wrong
   key; a result applied to the wrong screen after navigation (a late response for work A
   shown on work B).
3. **State and concurrency**: a view that draws from a value it does not observe; a task
   that outlives its view and writes state; a `.task(id:)` keyed on the wrong thing; a
   list that is not lazy and can be long; a pager that can show two pages mixed after a fast
   double tap.
4. **A control that does not do what its words say**: a confirmation that promises one
   set of rows and takes another, a button that reports done without AO3's confirmation, a
   setting that changes nothing.
5. **Privacy**: mature-content blur that can be bypassed or that leaks a title or summary
   (in a list, a notification, a share sheet, a recents thumbnail); a private page shown
   after sign-out; anything written to logs that identifies the reader.
6. **The in-app browser**: an address outside AO3 loaded with AO3's cookies; a `javascript:`
   or `intent:` address followed; a download or a file access the reader did not ask for.
7. **Tests that prove nothing** (name the test and what would still pass if the rule broke).

Not findings: formatting, naming, "could be simpler", anything the iOS docs record as
intended (`docs/REDESIGN_DECISIONS.md`, `docs/AO3_NETWORKING_POLICY.md`, `TASKS.md`).

## The result file

Start with a table: id, severity (P1 loses data or sends something wrong to AO3; P2 wrong
behaviour a user meets; P3 the rest), file and line, one-line statement. Then one section per
finding: the exact code (quote it, with `path:line`), **a concrete failing case** (inputs or taps, then what happens and what should),
and the smallest fix you would make. If you could not confirm a suspicion by reading, put it
under "Unconfirmed" with what would confirm it; do not present it as a finding. End with what
you did not read.

Quality over count. Twenty real findings with exact lines are worth more than a hundred
guesses; a wrong file or line makes the whole report untrustworthy.
