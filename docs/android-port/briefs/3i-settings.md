# Brief 3i: Settings, redesigned as iOS draws it (artboards 1ab, 1ac, 1aa, 1z, 1bb)

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. If you can run Gradle,
build and test until green: `cd android && ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline`.
Otherwise write code that compiles by careful reading: declare every value before use, and check every
symbol you call exists with that exact signature. Use **emulator-5554 only**. It is in airplane mode on
purpose; keep it that way. The debug demo (`--ez kudosDemoLibrary true --es kudosTheme dark`) serves AO3
from fixtures.

## Read first
- `docs/android-port/specs/settings.md`: the porting spec, with iOS file:line references.
- `docs/android-port/LIVING-PROMPT.md` §1 and §6. **iOS wins**, and behaviour must be identical across
  platforms. Reuse the iOS strings verbatim.
- iOS: kudos-ao3-reader/Settings/* (hub and pages), Features/Account/PrivacyDataView.swift, AccountMoreOnAO3View.swift, AO3PreferencesView.swift.
- Patterns in the lane: `ui/subject/*`, `app/PushedShellChrome.kt` (floating back plus actions), and the
  already-redesigned Home, Library, queues, Browse and Account screens.

## Build
Rebuild the Android screens under `settings/ and account/AO3PreferencesScreen.kt` to match the iOS screens the spec describes, section by
section: structure, components, data sources, interactions (menus, filter panel, toolbars), strings and
owner decisions. **Keep every action Android has today working**: restyle, don't drop features. Where
the spec lists an iOS behaviour Android lacks, add it if it's self-contained, or list it in the result
if it needs data or network work.

Don't touch `backup/`, `data/local` entities or migrations, or areas another agent is working in:
Work detail (`works/`), Account (`account/AccountScreen.kt`), and Search or Settings (whichever isn't
yours). If emulator screenshots are possible, save Dark ones to `docs/android-port/shots/3i/`. Write
`docs/android-port/briefs/3i-result.md` (under 400 words).
