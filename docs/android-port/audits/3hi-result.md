# A102 / 3hi: Reading Insights' cards and figures (Codex, finished by Claude-Code)

Codex hit its usage limit at 06:48, after the code and tests were written but before it wrote this report or
committed. Claude-Code reviewed the diff, ran the tests, and wrote this.

## Changes
- `ui/subject/SubjectComponents.kt`: `Modifier.subjectCard(palette, cornerRadius = SubjectMetrics.rowRadius)`. It is
  iOS's `SubjectCardBackground` (`UIComponents/SubjectSurface.swift` ~400–418): the theme's card surface, the
  palette's `rowWash` over it, and a 0.5 dp `rowBorder`.
- `library/ReadingStatisticsScreen.kt`: the six Insights blocks (hours, fandom hours, pace, no-sessions note, library,
  most-read fandoms) draw `subjectCard(palette)` with the page palette, as iOS's six `.subjectCard(palette:)`
  (`ReadingInsightsView.swift:186, 280, 341, 421, 448, 484`). "words read" uses the shared `compactCount()`
  (iOS `.compactName`: 202,600 → "203K"). `formatCompactNumber` is deleted; its tests moved to the shared function.
- iOS's other `.subjectCard` sites:
  - Converted: `account/AO3CollectionDetailScreen.kt`'s person row (iOS `AO3CollectionDetailView.swift:579`) and
    `account/AO3ChallengeAssignmentsScreen.kt`'s unmatched-pair card (iOS `ChallengeAssignmentsView.swift:420`).
  - Already tinted on Android in the A102 pairs: AO3CollectionsList (`ao3colls`), AO3CollectionItems (`colitems`),
    Bookmarks, Marked for Later, FavoriteAffinityRow (`sec_favorites`) and Recently Deleted.

## Verified (Claude-Code, 2026-10-25 08:05)
- `Parity3hiInsightsTest` (2), `ReadingStatisticsTest`, `CompactCountTest` and the Assignments and Collection Detail
  tests: 43 run, none failed.
- **Revert check:** with the library card back on `subjectPanel()`, the card test fails in Dark. It expected the
  tinted (67,24,29), close to the iPhone's measured (60–69,24–27,28–31), and got glass (34,33,35).
- The full Android gate and the re-shoot follow.
