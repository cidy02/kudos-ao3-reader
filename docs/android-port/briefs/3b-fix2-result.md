# 3b-fix2 result

1. **Toolbar circles:** Introduced `ToolbarCircleButton` (44dp glass circle with 17sp glyph, `SubjectMetrics.toolbarCircle`) and `ToolbarAddButton` (accent-tinted "+" icon) in `ui/subject/SubjectComponents.kt`. Refactored `LibraryShellChrome.kt`, `HomeShellChrome.kt`, and `MainScaffold.kt` to share these composables directly. Library's top-right "+", filter, and "…" buttons are now identical in size (44dp) and "+" tint (accent) to Home's.

2. **Fandom kicker peeling:** Ported iOS `FandomDisplayName` to Kotlin in `browse/FandomDisplayName.kt` along with `FandomDisplayExceptions.kt` (`keepWhole` set) and `FandomUmbrellas.kt` (`rpfKeepAttached` and `fandomKeepAttached` sets). Connected `HomeFacts.bareFandomTitle` and `HomeFacts.primaryFandom` to `FandomDisplayName.bareTitle`, peeling tag suffixes like " - All Media Types" into "Star Wars" while keeping umbrella tags and exception titles intact. Updated `WorkLedgerRow` in `ui/subject/WorkLibraryComponents.kt` to display peeled kickers via `HomeFacts.primaryFandom`. Cover cards and queue chrome automatically inherit peeled kickers.

Added unit tests in `browse/FandomDisplayNameTest.kt` verifying all iOS test cases, plus updated `HomeFactsTest.kt`.
