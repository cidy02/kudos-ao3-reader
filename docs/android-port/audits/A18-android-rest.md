# Audit A18: bug hunt in the rest of the Android app

**Read-only.** Work only in this worktree. Change no source file. Do not build, commit, push,
switch branches, sign in or contact archiveofourown.org. Write exactly one file:
`docs/android-port/audits/A18-result.md`. No helper scripts left behind.

Four audits have covered the reader and the Library (`audits/A5-result.md`), backup and sync
(`A3-result.md`), the writes to AO3 (`A17-result.md`) and the newest screens
(`A1-result.md`). Read their tables and triage notes first so you do not re-file them. This
audit is **everything else a reader uses**, under
`android/app/src/main/java/io/github/cidy02/kudos/`:

- `search/` (the query, filters and their panel, saved searches, results, pagination)
- `browse/` (fandom and category pages, tag pages, the fandom index and its cache)
- `author/` (profile, works, series, bookmarks tabs and their paging)
- `comments/` (the thread model and geometry, the composer and its draft, the screen's state)
- `home/` (the dashboard, section lists, the resume hero, menus)
- `works/` (Work Detail and its sheets, import of files, rebuild from original, metadata
  refresh, the availability sweep, the download-date confirmation)
- `settings/`, `onboarding/`, `support/`, `update/`, `auth/` (what is stored, what is reset,
  what is shown to whom)
- `app/` (navigation, routes and their arguments, the shell's top row and tab bar, the demo
  mode's boundary: nothing in a release build may be reachable only through a debug extra,
  and nothing in demo mode may reach the network)
- `web/` (the in-app browser: which addresses it may load, what it does with cookies)

iOS is the reference for behaviour, at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`
(change nothing there).

## What counts as a finding

1. **Crashes**: a `!!`, an unchecked index or cast, `first()` or `single()` on what can be
   empty, a route argument decoded without a guard, a parse of AO3's HTML that throws on a
   page the fixtures do not cover, an API above `minSdk` 26, work on the main thread that can
   be long.
2. **Lost input or state**: a composer, a filter or a form that forgets what was typed on
   rotation, on leaving and returning, or on a failed request; a draft saved under the wrong
   key; a result applied to the wrong screen after navigation (a late response for work A
   shown on work B).
3. **State and concurrency**: a composable that draws from a value it does not observe; a
   coroutine that outlives its screen and writes state; a flow collected twice; an effect
   keyed on the wrong thing; a list that is not lazy and can be long; a pager that can show
   two pages mixed after a fast double tap.
4. **Wrong behaviour against iOS** that a reader would meet: a rule, a default, an order or
   an edge case that differs and is not recorded in `docs/android-port/DECISIONS.md` or a
   brief's result.
5. **Privacy**: mature-content blur that can be bypassed or that leaks a title or summary
   (in a list, a notification, a share sheet, a recents thumbnail); a private page shown
   after sign-out; anything written to logs that identifies the reader.
6. **The in-app browser**: an address outside AO3 loaded with AO3's cookies; a `javascript:`
   or `intent:` address followed; a download or a file access the reader did not ask for.
7. **Tests that prove nothing** (name the test and what would still pass if the rule broke).

Not findings: formatting, naming, "could be simpler", anything recorded as a decision or as
left out, the wording differences already listed in `audits/A14-result.md`.

## The result file

Start with a table: id, severity (P1 loses data or sends something wrong to AO3; P2 wrong
behaviour a user meets; P3 the rest), file and line, one-line statement. Then one section per
finding: the exact code (quote it, with `path:line`), the iOS code it is checked against
(`path:line`), **a concrete failing case** (inputs or taps, then what happens and what should),
and the smallest fix you would make. If you could not confirm a suspicion by reading, put it
under "Unconfirmed" with what would confirm it; do not present it as a finding. End with what
you did not read.

Quality over count. Twenty real findings with exact lines are worth more than a hundred
guesses; a wrong file or line makes the whole report untrustworthy.
