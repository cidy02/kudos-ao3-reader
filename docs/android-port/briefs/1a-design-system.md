# Brief 1a: the redesign's design system, in Compose

You are porting the iOS app's redesign foundation to the Android app (Kotlin + Jetpack Compose).
Work only in this worktree. **Do not commit.** Do not push, do not touch git branches, do not use
the network. Leave your changes uncommitted; Claude reviews, builds and commits them.

## Read first
- `docs/android-port/LIVING-PROMPT.md` §0, §1 and §4 (Phase 1).
- iOS (the reference, SwiftUI):
  - `kudos-ao3-reader/App/ThemeManager.swift`: the themes (Light, Dark, OLED, Sepia, System) and the accent.
  - `kudos-ao3-reader/UIComponents/SubjectSurface.swift`: `SubjectPalette` (from a hue, from a picked colour), washes, `subjectPanel`, `SubjectChip`, `SectionRuleHeader`, rings.
  - `kudos-ao3-reader/UIComponents/SubjectScreen.swift`: `SubjectHeaderBlock`, the screen wash.
  - `kudos-ao3-reader/UIComponents/AppThemeSurface.swift`, `SemanticThemeColors.swift`, `CarouselCardStyle.swift`.
  - `kudos-ao3-reader/UIComponents/SubjectForm.swift`: form rows and panels.
  - `kudos-ao3-reader/Features/Account/AccountComponents.swift`: `AccountIconSquare`, the 22pt accent square.
- Design spec: `docs/design/Final_Redesign_Spec.dc.html`. Artboards 1b (Home) and 1m (Account hub) show most of these pieces with exact sizes. Artboards are dark-only; derive other themes from the iOS theme code, never from literal rgba values in the spec.
- Android today: `android/app/src/main/java/io/github/cidy02/kudos/ui/theme/{Theme,Color,Type}.kt` (Material 3 schemes per `KudosThemeMode`).

## Build
A new package, `io.github.cidy02.kudos.ui.subject`, holding the shared pieces every redesigned screen will use. Port behaviour and numbers from the iOS code: sizes, radii, opacities, font sizes and weights, and the colour maths. Name things after their iOS counterparts so later ports can map one to one.

1. **Theme tokens.** Add a `KudosTokens` CompositionLocal, provided by the existing `KudosTheme`, that carries:
   - the iOS `AppTheme` semantic colours: background, panel and card fills, primary, secondary and tertiary ink, separators and `glassStroke(alpha)`;
   - the accent, which is the user's picked accent used exactly (T-348). Sepia does whatever iOS does; read `ThemeManager`.
   Keep the Material schemes working: the existing screens must look no worse.
2. **`SubjectPalette`.** Port it, including `fromHue(hue, theme)` (the hue-derived palette: accent, `cardWash`, `rowWash`, `panelWash`, borders, chip fill and stroke) and `fromColor(color, theme)` (the picked-colour path, where backgrounds use the colour at alpha). Add the theme's scope palette and a `LocalSubjectPalette`.
3. **Composables and modifiers**, each matching iOS:
   - `Modifier.subjectScreenWash(palette)`
   - `SubjectHeaderBlock` (kicker, short rule, title, optional subtitle)
   - `SectionRuleHeader` (title, optional count, collapse chevron)
   - `Modifier.subjectPanel(cornerRadius)`
   - `SubjectRowSeparator`
   - `SubjectChip` (tinted, neutral, pill and dashed variants)
   - `SubjectStatStrip`
   - `WorkProgressRing` (progress and label)
   - `AccentIconSquare` (iOS `AccountIconSquare`)
   - `GlassCircleButton` (the 34pt glass chrome circle)
   - `FilterButton` with a count badge
4. **A debug-only catalog screen** (`DesignCatalogScreen`) that shows every piece above, with a theme switcher (Light, Dark, OLED, Sepia), and three palettes: the default accent, a hue palette and a picked-colour palette. Make it reachable from a debug build only, through a route Claude can open with `adb shell am start -n io.github.cidy02.kudos/.MainActivity --es kudosDebugRoute designCatalog`. Add that intent-extra handling in `MainActivity`/navigation, guarded by `BuildConfig.DEBUG`.
5. **Unit tests** for the `SubjectPalette` maths: hue → colours, picked colour → alpha backgrounds, and an exact accent on controls. Use plain JUnit under `app/src/test`.

## Rules
- Additive only. Do not restyle existing screens yet, and do not touch persistence, backup, network or reader code.
- Use only libraries already in `android/gradle/libs.versions.toml`.
- Use sp for text so it scales with the font size, as iOS Dynamic Type does.
- At the end, write `docs/android-port/briefs/1a-result.md`: the files you added, each iOS symbol → Kotlin symbol, anything you could not port, and anything you guessed. Keep it under 600 words.
