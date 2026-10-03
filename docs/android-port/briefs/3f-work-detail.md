# Brief 3f: Work detail, redesigned as iOS draws it (artboard 1a)

Edit-only. **Do not commit**, push, switch branches, stash or reset. No network. You cannot run
Gradle: write code that compiles by careful reading. **Declare every value before use, and check
every symbol you call exists with that exact signature, including properties on domain classes**
(your last two briefs failed to compile on exactly that). Claude builds and checks on the emulator.

## Read first
- `docs/android-port/specs/work-detail.md`: the porting spec, with iOS file:line references.
- `docs/android-port/LIVING-PROMPT.md` §1: iOS code wins, and behaviour must be identical across
  platforms.
- iOS: `kudos-ao3-reader/Features/WorkDetail/*` (WorkDetailView, IdentityBlock, Overview, Facts sections,
  Figures, Provenance, ResumeCard, AO3WorkActionsMenu, the "My copy" area).
- Patterns already in the lane: `ui/subject/*` (header block, panels, chips, stat strip, rings, status
  tray in `SubjectWorkCoverCard.kt`, `ToolbarCircleButton`/`ToolbarAddButton`, `SubjectToggle`),
  `app/PushedShellChrome.kt` (floating back plus actions row), and `core/model/WorkDownloadSemantics.kt`
  (Download / Remove Download / "Kept by", whose behaviour is already ported).

## Build
Rebuild `works/WorkDetailScreen.kt` (split it into files under `works/detail/` if that helps) to match
the iOS Work detail section by section: the identity block (kicker, title, author, the tag rows),
the read action ("Read" / "Continue reading" with the play glyph), the resume card, the figures
strip (words, chapters, kudos, comments, bookmarks, hits), facts and provenance, the "My copy" section
(downloaded / kept by / held copy states and actions, with iOS's exact strings: "Not downloaded",
"Removed to save space. Kudos gets it again when you read it", and so on), and the AO3 actions menu
in the floating "…". **Keep every action Android has today working** (kudos, bookmark, comments,
subscribe, add to queue or collection, download, series preservation prompt, and the rest).
Restyle; don't drop features.

Don't touch `backup/`, `data/local`, migrations, repositories' data rules, `browse/` (another agent is
there) or `library/`. Write `docs/android-port/briefs/3f-result.md` (under 400 words).
