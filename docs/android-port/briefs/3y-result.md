# 3y result

Done by Claude: Codex's weekly limit ran out before it could start.

## The sheet, before and after

| | Before (titled "Display") | After (iOS `ReaderOptionsForm`, titled "Display & Themes") |
|---|---|---|
| Header | title only | title and a Done check button |
| 1 | Text size slider with a percent label | **Appearance**: Theme (Light, Sepia, Dark, OLED, segmented) and "Customize Theme…" |
| 2 | Theme chips (Light, Sepia, Dark, Oled) | **Text Size**: small A, slider, large A |
| 3 | Reading mode chips (Scroll, Paged, Two-page) | **Reading**: Layout (Scrolled, Paged, segmented), "Two-page spread" on wide screens, "Keep screen awake", and iOS's footnote |
| 4 | Font chips | **Read Aloud**: Voice chips, Speed, Pitch |
| 5 | Bold text, Letter spacing, Word spacing | **Font**: one row per font, a check on the chosen one |
| 6 | Read aloud: voices, Speed, Pitch | |

The sheet now takes the reader's theme (its background and its controls), as iOS's does; before,
it was drawn in the app's theme even when the reader's differed.

## Strings

New or changed: "Display & Themes" (was "Display"), "Done", "Appearance", "OLED" (was "Oled"),
"Customize Theme…", "Text Size" (was "Text size · N%"), "Reading" (was "Reading mode"), "Layout",
"Scrolled" (was "Scroll"), "Two-page spread" (was "Two-page"), "Keep screen awake", "Choose
whether you turn pages or scroll while reading.", "On a wide screen, Paged mode can show two
pages side by side.", "Read Aloud" (was "Read aloud"), "Voice", "Bold Text" (was "Bold text"),
"Selected". Unchanged: "Theme", "Light", "Sepia", "Dark", "Paged", "Font", the font names,
"Letter spacing", "Word spacing", "Speed", "Pitch".

## Callbacks

All thirteen of the old sheet's callbacks are kept and call the same view-model functions
(`setFontSizePercent`, `setColorTheme`, `setScrollMode`, `setTwoPage`, `setBold`,
`setLetterSpacing`, `setWordSpacing`, `setSpeechRate`, `setSpeechPitch`,
`setSpeechVoiceIdentifier`, `setFontFamily`). New: `onDone` (closes the sheet) and
`onKeepScreenAwakeChange`, which calls the new `ReaderViewModel.setKeepScreenAwake`, writing the
same `keepScreenAwake` setting Settings > Reader writes.

## Reused from Settings

`SettingsGroupLabel`, `SettingsPanel`, `SettingsSection`, `SettingsActionRow`, `SubjectSliderRow`
and `TextSizeSlider` (now `internal`, with a range, a unit and a live callback, so Settings sets
points and the reader sets percent with the same control), plus the subject components
(`SubjectSegmentedControl`, `SubjectFormRow`, `SubjectToggle`, `SubjectRowSeparator`).

## Different from iOS, and why

- **"Customize Theme…" opens in place**, showing Bold Text, Letter spacing and Word spacing (the
  three controls the old sheet had loose). iOS opens a separate "Customize Theme" sheet that also
  has line height, justification and a Customize switch; the reader's view model has no setters
  for those, and Settings > Appearance and Settings > Reader hold them.
- **Two-page spread** is hidden on a phone, as on iOS, unless it is already on (so it can be
  turned off). The old sheet offered it on every screen.
- **Font** lists the built-in fonts, as the old sheet did. iOS also lists imported fonts and has
  "Add Font…"; on Android both are in Settings > Font, whose file picker this sheet does not host.
- **Read Aloud** keeps Android's controls. iOS's engine and Kokoro pickers, "Read author's notes"
  and Pronunciations have no Android counterpart yet.
- Sliders other than text size apply when the finger lifts (the Settings pages' slider row);
  text size still applies while dragging.

## Checked on the emulator

Opened from the reader's fan menu: the five sections in order; choosing Sepia re-themed the page
and the sheet at once; Paged and Scrolled; the font list with its check; Done closed it. Gate
green.
