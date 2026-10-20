# Brief T-419 (iOS): accent-coloured text and icons read on Dark and OLED (owner Q19, 2026-10-20)

**Write code in the iOS worktree you are given; do not commit, push, switch branches, sign in,
run xcodebuild or contact archiveofourown.org.** Claude builds and runs the suite. Do not edit
`TASKS.md`. Leave a result file `docs/android-port/briefs/T-419-result.md` beside this brief in
the **Android lane** path you are given (or in the iOS worktree root if you cannot write there),
written as you go.

The owner answered on 2026-10-20 (question 19): on Dark and OLED, text and icons drawn in the
accent colour are lightened until they read at 4.5:1 against the page; filled controls keep the
exact accent (T-348 stands for fills: `SubjectPalette.controlColor`). Light and Sepia unchanged.
AO3 red (#990000) was about 1.8:1 on Dark's page.

**Android already does this** (lane commit `c17d376d`): `KudosTokens.accentInk`
(`android/app/src/main/java/io/github/cidy02/kudos/ui/subject/KudosTokens.kt`) is
`accent.readableOn(theme.cardBackdrop)` on Dark and OLED, where `readableOn`
(`ui/subject/SubjectColor.kt`) mixes the colour toward white in 5% steps (at most 20) until the
WCAG contrast ratio is ≥ 4.5. Use **the same rule and the same page colour** on iOS so both apps
draw the same ink.

iOS today: the app-wide tint is `ThemeManager.effectiveTint` (`App/ThemeManager.swift:59`),
applied with `.tint(...)` at the root; about 38 views draw text or glyphs with
`.foregroundStyle(.tint)` (e.g. `Settings/AboutView.swift:16`, `Settings/SettingsView.swift:176`,
`Features/Comments/CommentThreadRow.swift:861`, `Features/Library/WorkRow.swift:237`,
`Features/Search/AO3WorkRow.swift:146`, `UIComponents/SubjectForm.swift:249`), and plain/borderless
buttons draw their labels in the tint. Filled controls (`.borderedProminent`, `Toggle`, sliders,
progress fills, selection fills) also take the tint.

Do:
1. A shared `readable(on:minimum:)` colour helper (WCAG relative luminance, the same 5% steps)
   and `ThemeManager.accentInk` (the lifted tint on Dark/OLED, the tint itself otherwise).
2. Make text, glyphs and text-button labels use the ink and every fill keep the exact tint.
   Choose the smaller correct change: either replace `.foregroundStyle(.tint)` with the ink (a
   `ShapeStyle` or environment value so views need no new parameters) and give text-only
   buttons the ink, or set the root tint to the ink and put the exact accent back on the fill
   controls. Say which and why in the result file, and list every call site changed.
3. Leave `SubjectPalette.accent` (already a readable tone per theme) as it is.
4. Tests in `KudosTests/`: AO3 red on Dark and OLED reaches ≥ 4.5:1, a colour that already reads
   is returned unchanged, Light and Sepia return the tint itself, and the ink for #990000 on Dark
   equals Android's (compute Android's value with the same arithmetic and assert the hex).
