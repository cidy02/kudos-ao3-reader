# Brief 3k: comments, redesigned as iOS draws them

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. If you can run Gradle,
build and test until green: `cd android && ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline`.
Otherwise write code that compiles by careful reading: declare every value before use, and check every
symbol you call exists with that exact signature. Use **emulator-5554 only**. It is in airplane mode on
purpose; keep it that way. The debug demo (`--ez kudosDemoLibrary true --es kudosTheme dark`) serves AO3
from fixtures.

## Read first
- `docs/android-port/specs/comments.md`: the porting spec, with iOS file:line references.
- `docs/android-port/LIVING-PROMPT.md` §1 and §6. **iOS wins**, and behaviour must be identical across
  platforms. Reuse the iOS strings verbatim.
- iOS: kudos-ao3-reader/Features/Comments/ (CommentsView.swift, CommentThreadScreen.swift, CommentThreadRow.swift, CommentMarkup.swift, CommentsModel.swift, CommentsErrorMessages.swift).
- Patterns in the lane: `ui/subject/*`, `app/PushedShellChrome.kt` (floating back plus actions), and the
  already-redesigned Home, Library, queues, Browse and Account screens.

## Build
Rebuild the Android screens under `comments/` to match the iOS screens the spec describes, section by
section: structure, components, data sources, interactions (menus, filter panel, toolbars), strings and
owner decisions. **Keep every action Android has today working**: restyle, don't drop features. Where
the spec lists an iOS behaviour Android lacks, add it if it's self-contained, or list it in the result
if it needs data or network work.

Don't touch `backup/`, `data/local` entities or migrations, or areas another agent is working in:
Settings (`settings/`), `reader/`, `app/Routes.kt` and `app/MainScaffold.kt`.
If emulator screenshots are possible, save Dark ones to `docs/android-port/shots/3k/`. Write
`docs/android-port/briefs/3k-result.md` (under 400 words).

## AO3 is off limits
Comments come from AO3. The debug demo serves AO3 from fixtures (brief 1e), and the emulator is in
airplane mode. **Never** contact archiveofourown.org. **Never** post, reply, edit or delete a
comment except against the fixture or a local stub. If the demo has no comment fixture for the
screen you need, add one under the demo fixtures (follow how brief 1e's fixtures are wired) rather
than reaching the network. Posting stays behind the signed-in state, as on iOS.

## Before you finish
List every user-visible string and every `on…` callback in the reader files you rewrote, before and after
(`git show HEAD:<file>`). Each one must still exist, or be listed in your result as deliberately moved
(with where) or dropped because iOS drops it (with the iOS file:line). A rewrite that silently drops a
feature will be rejected.
