# Brief 3j: the reader chrome, redesigned as iOS draws it

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. If you can run Gradle,
build and test until green: `cd android && ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline`.
Otherwise write code that compiles by careful reading: declare every value before use, and check every
symbol you call exists with that exact signature. Use **emulator-5554 only**. It is in airplane mode on
purpose; keep it that way. The debug demo (`--ez kudosDemoLibrary true --es kudosTheme dark`) serves AO3
from fixtures.

## Read first
- `docs/android-port/specs/reader.md`: the porting spec, with iOS file:line references.
- `docs/android-port/LIVING-PROMPT.md` §1 and §6. **iOS wins**, and behaviour must be identical across
  platforms. Reuse the iOS strings verbatim.
- iOS: kudos-ao3-reader/Features/ReaderReadium/ (ReadiumReaderView.swift, ReaderChromeTopBar.swift, ReaderPositionCard.swift, ReaderFanMenu.swift, ReaderContentsSheet.swift and the sheets the spec lists).
- Patterns in the lane: `ui/subject/*`, `app/PushedShellChrome.kt` (floating back plus actions), and the
  already-redesigned Home, Library, queues, Browse and Account screens.

## Build
Rebuild the Android screens under `reader/` to match the iOS screens the spec describes, section by
section: structure, components, data sources, interactions (menus, filter panel, toolbars), strings and
owner decisions. **Keep every action Android has today working**: restyle, don't drop features. Where
the spec lists an iOS behaviour Android lacks, add it if it's self-contained, or list it in the result
if it needs data or network work.

Don't touch `backup/`, `data/local` entities or migrations, or areas another agent is working in:
Search (`search/`), Settings (`settings/`), `app/Routes.kt` and `app/MainScaffold.kt`.
If emulator screenshots are possible, save Dark ones to `docs/android-port/shots/3j/`. Write
`docs/android-port/briefs/3j-result.md` (under 400 words).

## Reading position is off limits
Brief 3r fixed reading-position loss: opening and closing a work without moving must keep its stored
fraction, and the reader writes progress only when iOS does. **Don't change** how the reader picks its
start position or when it saves progress (`ReaderRepository`, `ReaderProgress*.kt`, `ReaderRestoreTarget.kt`,
`ReaderLocatorCodec.kt` and their tests); this brief is the chrome only. `ReaderRepositoryTest`,
`ReaderProgress*Test` and the other reader tests must pass unchanged.

## Before you finish
List every user-visible string and every `on…` callback in the reader files you rewrote, before and after
(`git show HEAD:<file>`). Each one must still exist, or be listed in your result as deliberately moved
(with where) or dropped because iOS drops it (with the iOS file:line). A rewrite that silently drops a
feature will be rejected.
