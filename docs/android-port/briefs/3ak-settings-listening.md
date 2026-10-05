# Brief 3ak: Settings › Listening, as iOS's

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result. Write `docs/android-port/briefs/3ak-result.md` as you go.

## The screen

Android's Settings › Listening (`SettingsListeningPage` in `settings/SettingsPages2.kt`) is a
placeholder that says the page does not change anything yet. iOS's has the read-aloud controls
(`ReaderSpeechSettingsSection.swift`, and whatever settings page hosts it: find it from
`Settings/SettingsRoute.swift`). Android already reads aloud (`reader/speech/`, and the reader's
"Read aloud" action); find where its voice, speed and other options are stored and changed
today (the reader's own sheet, a preferences class) and make this page the same controls over
the same stored values. One store, two places to change it: never a second copy of a setting.

Start the result with a table: every control on iOS's page, in iOS's order, with its label,
its footnote, its values and default; beside each, whether Android's engine and store support
it today. Build what is supported, in iOS's order and iOS's words. For what is not, do not
build a control that does nothing: list it under "missing, needs engine work" with what it
would take.

## How it must be drawn

- The settings chrome only: `SettingsPage`, `SettingsSection`, `SubjectFormRow`,
  `SubjectToggle`, `SettingsActionRow`, `SettingsFootnote` (read `settings/SettingsChrome.kt`
  and a finished page such as `SettingsFolderSyncPage` first). No Material buttons or outlined
  fields where a settings row belongs; every text with a line height; a row opens from anywhere
  on it, not only from its value.
- A choice among a few values is a row with the value at its end that opens a menu, as the
  other pages do; a continuous value (speed, pitch) is a slider row. If the chrome has no slider
  row, look at how `search/FilterRangeSlider.kt` draws one on the same tokens and add a small
  single-value one beside the chrome's other rows.
- Owner's rule since 2026-10-04: layout, content and behaviour follow iOS; navigation and chrome
  controls are Android's own (Material), never an imitation of an iOS-only look. Nothing on this
  page should need that, but do not add glass or capsule controls.
- Light, Dark, Sepia and OLED come from the tokens: no literal colours.

## Behaviour

- A change takes effect for the next thing read aloud, and at once if something is being read
  now, exactly as the reader's own control does today. Say what you found.
- A "preview" or "test voice" control on iOS: build it only if Android can speak a sample
  through the existing engine without opening the reader; otherwise list it as missing.
- Voices that must be downloaded: show what exists today (name, whether it is on the device),
  and do not start a download from this page unless iOS's page does and Android has the code
  for it already. No new network request of any kind.

## Tests

One test per stored value this page can change: changing it here is what the reader's speech
code then reads. And one that the page lists exactly the voices the engine reports.
