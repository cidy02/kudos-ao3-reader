# Audit A86 (read-only): adversarial review of the 3gw landing on Android

**Read only. Do not edit any file except the result file named below. Do not run git or shell commands
that change anything, do not build, do not sign in, do not contact archiveofourown.org.**

Write your result to `/Users/cidy02/kudos-agent-flash/docs/android-port/audits/A86-result.md`
(create it first, then fill it as you go).

## What to review

The Android lane is `/Users/cidy02/kudos-android-lane` (project in `android/`). Its newest commit (`8ffb409d`) lands ten screen fixes written by another AI
(Codex) and a navigation fix written by Claude. Read the whole diff, saved for you at
`/Users/cidy02/kudos-agent-flash/docs/android-port/audits/A86-diff.patch`, then the full files it
touches (the lane's working files are that commit).
iOS is the reference app: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (each item names its
iOS file in `docs/android-port/briefs/3gw-result.md`).

Look for real faults only, each with `file:line`, a severity (P1 data loss or crash, P2 wrong
behaviour a user meets, P3 minor) and a concrete failing case (what the user does, what happens,
what should happen):
1. Behaviour lost: anything the old code did that the new code no longer does and iOS does do
   (for example an action that is no longer reachable, a state no longer shown, a TalkBack label
   dropped). Android extras that `docs/android-port/DECISIONS.md` records as Android's must stay.
2. Wrong behaviour in the new code: the page-jump sheet's draft and Go (compare iOS
   `Features/Search/SearchPaginationBar.swift` `PageJumpSheet`), the reader contents swipe
   actions (iOS `Features/ReaderReadium/ReaderContentsSheet.swift`), the pronunciation More menu,
   the tag picker's empty query, the collection editor's order and title, the theme swatches.
3. `app/MainScaffold.kt`: debug-shot navigation now keeps the start destination under the shot
   (`popUpTo(navController.graph.findStartDestination().id)`). Could this break normal
   navigation, or only DEBUG shots? Check it is guarded to debug shots.
4. Tests: does each changed or new test fail if its change is reverted? Name tests that would
   still pass with the change undone.

For every finding quote the lines on both sides (Android and, where it applies, iOS). If you are
not sure a finding is real, put it under "Unconfirmed" with what would confirm it. End with a
one-line count: P1 / P2 / P3 / unconfirmed.
