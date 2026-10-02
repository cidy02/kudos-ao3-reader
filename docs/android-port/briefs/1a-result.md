# Brief 1a result

Package `io.github.cidy02.kudos.ui.subject`. Additive. Material schemes in `KudosTheme` are unchanged and existing screens are not restyled. `:app:assembleDebug :app:testDebugUnitTest --offline` passed. Uncommitted.

## Files

Added, main: `SubjectColor.kt`, `KudosTokens.kt`, `SubjectPalette.kt`, `DebugRoutes.kt`, `SubjectComponents.kt`.

Added, debug: `DesignCatalogScreen.kt` (`DebugDestination` plus the catalog). Release stub `src/release/.../DebugDestination.kt` always returns false.

Added, test: `SubjectPaletteTest.kt` (plain JUnit, no Robolectric).

Edited: `Theme.kt` (provides `LocalKudosTokens` and `LocalSubjectPalette`; System resolves to Light or Dark), `MainActivity.kt` (`kudosDebugRoute` only when `BuildConfig.DEBUG`, including `onNewIntent`), `KudosApp.kt` (debug early return so onboarding cannot hide the catalog).

`adb shell am start -n io.github.cidy02.kudos/.MainActivity --es kudosDebugRoute designCatalog`

## iOS → Kotlin

`ReaderTheme` → `ReaderTheme`. `ThemeManager.accentColor` / `effectiveTint` → `KudosTokens.accent` (Sepia uses `appTint` / `SepiaTint` `#9A6732`). `scopePalette` → `ReaderTheme.scopePalette`, `KudosTokens.scopePalette`, `LocalSubjectPalette`. `label(on:)` → `SubjectPalette.label`. `controlColor` (unchanged colour, T-348) → `SubjectPalette.controlColor`. `init(hue:theme:)` → `fromHue`. `init(color:theme:)` → `fromColor`. Wash stops → `WashStop`; `wash` is a vertical brush. `cardBackdrop` → `KudosTokens.background` / `ReaderTheme.cardBackdrop`. `cardSurface` → `cardFill` / `cardSurface`. Panel `glassFill(0.09)` → `panelFill` plus `glassFill(opacity)`. Primary / secondary / tertiary → `primaryInk` / `secondaryInk` / `tertiaryInk`. Separator → `separator`. `glassStroke` → `KudosTokens.glassStroke` / `ReaderTheme.glassStroke`. `subjectScreenWash` → `Modifier.subjectScreenWash` (default 380.dp). `SubjectKicker`, `SubjectHeaderBlock`, `SectionRuleHeader`, `SubjectRowSeparator` keep their names. `subjectPanel` (radius 14) → `Modifier.subjectPanel`. `SubjectChip` / `.Style` → `SubjectChip` / `SubjectChipStyle` (Neutral, Tinted, Dashed, Pill). `SubjectStatStrip` / `.Cell` → `SubjectStatStrip` / `SubjectStatCell`. `WorkProgressRing` keeps the name (`state` is the label). The 22pt square inside `AccountShortcutGridTile` (there is no `AccountIconSquare` type) → `AccentIconSquare`. `GlassCircleButton` uses `onClick`. `FilterButton` uses `onClick`, `badgeCount`, `onClearFilters`. `SubjectMetrics` adds `panelRadius` 14 and `defaultWashHeight` 380. `compactCount`, `hueComponent`, `relativeLuminance` keep their names; Swift `opacity` is `withOpacity`; `hsb()` is 0…1 like SwiftUI. New pieces read `KudosTokens.accent`, not Material `primary` (dark primary is paper).

## Not ported

`SubjectFormRow`, `SubjectFilterRail`, `WorkLedgerRow`, `WorkReadingOrDownloadRing` and download dimming, carousel tints, `SubjectFieldLabel`, `SemanticThemeColors`. The iOS hairline leader was already gone; the spacer remains. The stat-strip Dynamic Type cap is not applied (`sp` scales freely). No text auto-shrink. Filter menu contents are not ported. The catalog does not write theme settings.

## Guessed or diverged

Light page is UIKit `systemGroupedBackground`, taken as `#F2F2F7`. Dark page is the source override `#0B0B0D`; OLED is black; Sepia page `0.925/0.871/0.757` and card `0.984/0.941/0.851` are the source floats. Light/dark secondary and tertiary ink and non-Sepia separators are resolved UIKit values: secondary base alpha 0.6, tertiary 0.3 (light base `rgb(60,60,67)`, dark `rgb(235,235,245)`); light separator that base at 0.29; dark/OLED separator `rgb(84,84,88)` at 0.6. Sepia separator is the source colour at 0.18. Sepia ink matches light. Primary ink is black on light/Sepia and white on dark/OLED.

Compose stores sRGB in 8 bits, so `withOpacity` lands within 1/255 of the Swift float (`0.16 * 0.55` stores as 22/255). Tests allow that delta. `compactCount` is one-decimal K/M/B, not Foundation `compactName`. Corners are `RoundedCornerShape` (no squircle); capsules use percent 50. `subjectPanel` stroke is a centered border. The dashed chip stroke is inset by half its width. Stat dividers are a 0.5.dp `drawBehind` on each cell after the first (`VerticalDivider` plus intrinsic height crashes in a vertical scroll). Selected pill fill and accented glass use the hue-derived `accent`, matching the Swift bodies. `tint`, `tokens.accent`, and the active filter use the exact picked colour. Sepia `scopePalette` ignores the user accent; `fromColor` on Sepia does not. The filter glyph is `Icons.Filled.FilterList`; active is accent plus a `99+` badge. The glass glyph is 17.sp in a fixed 34.dp circle, and the square glyph is 12.sp in 22.dp, so a large font can overflow.
