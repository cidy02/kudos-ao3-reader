# Brief 3y: the reader's "Display & Themes" sheet, as iOS has it

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; don't change Room schemas or backup formats; don't edit `TASKS.md`. Your sandbox can't run
Gradle; Claude builds and tests afterwards, so make it compile by reading the real symbols you use.

In the reader, the fan menu's "Themes & Settings" pill opens a sheet. On Android it is
`ReaderDisplaySheet` in `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderScreen.kt`
(titled "Display": theme, reading mode, two-page, bold text, read aloud). On iOS it is
`ReaderOptionsForm`, titled "Display & Themes". The iOS lane is `/Users/cidy02/kudos-ios-polish`;
read these first:

- `kudos-ao3-reader/Settings/SettingsView.swift`: `ReaderOptionsForm` and the pieces it is made
  of (`ReaderThemePicker`, "Customize Theme…", `TextSizeSlider`, `ReaderLayoutSection`,
  `ReaderFontSection`);
- `kudos-ao3-reader/Features/ReaderReadium/ReaderSpeechSettingsSection.swift`: its read-aloud
  section;
- `kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift`, `readerSheet` and
  `readerSheetTitle` (about lines 1565–1640): how the sheet is presented (title, the checkmark
  Done button, the two heights, the reader theme's colours).

iOS wins: same sections in the same order, same controls, iOS's strings verbatim.

## Do this, and only this

1. Make Android's sheet match `ReaderOptionsForm`: every section and control iOS has, in iOS's
   order, with iOS's titles and labels, shown under the same conditions (for example, when
   two-page is offered).
2. **One source of truth.** Android's Settings pages (`settings/`, redesigned in brief 3i) already
   have reader controls: theme, text size, fonts, layout, read aloud. Find them and reuse those
   composables and the same settings-repository calls, so the sheet and the Settings page are the
   same controls on the same stored values. Don't write a second copy of a control that exists.
   If a control iOS's form has exists nowhere on Android, add it only if the setting behind it
   already exists; otherwise leave it out and say so.
3. A change in the sheet must reach the open reader at once, as on iOS (theme, text size, font,
   layout, and read-aloud speed while it is speaking). Read how the current sheet applies its
   changes and keep that working for every control you add.
4. Anything Android's sheet has today that iOS's form lacks: keep it working, and list it in the
   result with the iOS evidence, so Claude can decide. Don't remove a control on your own.
5. Don't touch the reader's other sheets (Contents, Find in Work), its chrome, or reading
   position code (`ReaderRepository`, `ReaderProgress*.kt`, `ReaderLocatorCodec.kt`).

## Result

Write `docs/android-port/briefs/3y-result.md`: the sheet's sections and controls before and after,
side by side with iOS's; every new or changed user-visible string; every callback before and
after; which Settings composables you reused; anything iOS has that you left out, and why; anything
Android has that iOS lacks.
