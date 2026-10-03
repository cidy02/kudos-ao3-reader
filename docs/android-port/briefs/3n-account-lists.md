# Brief 3n: the AO3 account lists and Inbox, redesigned as iOS draws them

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. If you can run Gradle,
build and test until green: `cd android && ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline`.
Otherwise write code that compiles by careful reading: declare every value before use, and check every
symbol you call exists with that exact signature. Use **emulator-5554 only**. It is in airplane mode on
purpose; keep it that way. The debug demo (`--ez kudosDemoLibrary true --es kudosTheme dark`) serves AO3
from fixtures.

## Read first
- `docs/android-port/specs/account.md`: the porting spec, with iOS file:line references.
- `docs/android-port/LIVING-PROMPT.md` §1 and §6. **iOS wins**, and behaviour must be identical across
  platforms. Reuse the iOS strings verbatim.
- iOS: kudos-ao3-reader/Features/Bookmarks/ (AO3MarkedForLaterWorksBrowser, AO3BookmarksWorksBrowser, AO3HistoryWorksBrowser, AO3SubscriptionsWorksBrowser, AO3NamedSubscriptionsList, AO3AccountWorksList) and Features/Account/AccountInboxScreen.swift, AccountInboxFilterSheet.swift.
- Patterns in the lane: `ui/subject/*`, `app/PushedShellChrome.kt` (floating back plus actions), and the
  already-redesigned Home, Library, queues, Browse and Account screens.

## Build
Rebuild the Android screens for the account lists (`account/` list screens, the AccountList route) and Inbox to match the iOS screens the spec describes, section by
section: structure, components, data sources, interactions (menus, filter panel, toolbars), strings and
owner decisions. **Keep every action Android has today working**: restyle, don't drop features. Where
the spec lists an iOS behaviour Android lacks, add it if it's self-contained, or list it in the result
if it needs data or network work.

Don't touch `backup/`, `data/local` entities or migrations, or areas another agent is working in:
`settings/`, `reader/`, `comments/`, `library/`, `author/`, `account/AccountScreen.kt`, `account/AO3Collection*` (Gemini Pro is there), `app/Routes.kt` and `app/MainScaffold.kt`.
If emulator screenshots are possible, save Dark ones to `docs/android-port/shots/3n/`. Write
`docs/android-port/briefs/3n-result.md` (under 400 words).

## AO3 is off limits
These lists come from AO3. The debug demo serves AO3 from fixtures (brief 1e), and the emulator is in
airplane mode. **Never** contact archiveofourown.org. **Never** mark, unmark, bookmark, delete or write anything except against the fixture or a local stub. If the demo has no fixture for the
screen you need, add one under the demo fixtures (follow how brief 1e's fixtures are wired) rather
than reaching the network. Use `--ez kudosDemoSignedIn true` to see the signed-in states.

## Before you finish
List every user-visible string and every `on…` callback in the reader files you rewrote, before and after
(`git show HEAD:<file>`). Each one must still exist, or be listed in your result as deliberately moved
(with where) or dropped because iOS drops it (with the iOS file:line). A rewrite that silently drops a
feature will be rejected.

## Chrome and headers
Use the floating pushed chrome (`ProvidePushedShellChrome(hasSubjectHeader = true, trailingContent = …)`,
as `works/WorkDetailScreen.kt` and `author/AuthorProfileScreen.kt` do): no title bar. Put the status-bar
inset plus 56dp above each `SubjectHeaderBlock`. Open the list directly with
the Account hub's rows (or `--es kudosDebugRoute nav:account`) (plus `--ez kudosDemoSignedIn true`). Delete any helper
scripts or `.orig` files before finishing.

## Rows
iOS uses `SensitiveWorkRow` (the full work card) for works in these lists. Android already has it
(`ui/components/SensitiveWorkRow.kt`, landed in 3u). Use it, with the privacy blur.
