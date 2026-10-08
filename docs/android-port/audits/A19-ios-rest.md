# Audit A19: bug hunt in the rest of the iOS app

**Read-only.** Change no source file anywhere. Do not build, commit, push, switch branches,
sign in or contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A19-result.md`. No helper scripts left behind.

The code to audit is the iOS app (Swift, SwiftUI, SwiftData) at
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`, with its tests at
`/Users/cidy02/kudos-ios-polish/KudosTests/`. Two audits have covered its writes to AO3
(`audits/A4-result.md`) and its reader, Library and backup (`audits/A12-result.md`): read
their tables and triage notes first so you do not re-file them. The same audit of Android
(`audits/A18-result.md`) is worth reading for the kinds of fault to look for: the two apps
share their design, and a fault in one is often in the other. This audit is **everything
else a reader uses**:

- `Features/Search/` (the query, filters and their panel, saved searches, results,
  pagination, the tag pickers and their reads)
- `Features/Browse/` (the native browse pages, the in-app browser and its bookmarks)
- `Features/Authors/` (profile, works, series, bookmarks, the subscription and moderation
  actions and their confirmations)
- `Features/Comments/` (the thread model, the composer and its drafts, the verification of an
  unconfirmed post, the cache and its keys)
- `Features/Home/`, `Features/WorkDetail/` (the sheets, import, rebuild, metadata refresh)
- `Features/Account/` (the hub, the inbox, the lists, Privacy and its clearing actions,
  the availability sweep), `Features/Bookmarks/`
- `Settings/`, `Features/Onboarding/`, `Features/Support/`, `Features/Auth/`
- `App/` (navigation and routes, deep links and "Open with", the theme manager, the demo
  mode's boundary: nothing in demo mode may reach the network, and no debug launch argument
  may change a release build)

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
