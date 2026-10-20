# Brief 3fs: the reader's selection menu and Customize Theme, as the iPhone's (owner Q29/Q30, 2026-10-20)

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests and lands it. Do not edit `TASKS.md`. Leave a short
result file, `docs/android-port/briefs/3fs-result.md`: what you changed (`path:line`), each iOS
rule you ported with its iOS `path:line`, the tests you added, and anything you could not do.
Write it as you go, so a time limit leaves what is done.

Hard rules (`docs/android-port/LIVING-PROMPT.md` §1): Room migrations additive only (none
should be needed here); backup manifest stays v8 with additive keys; iOS is the source of truth;
no feature, control, figure or line of text Android has today may be lost (owner, 2026-10-20:
"the goal is visual and UX parity with no lost features or information"). Android's own
navigation and chrome (Material 3 top bar and icon buttons) stay as they are (owner, 2026-10-04).
Regex: Android's ICU engine rejects some flags the JVM accepts (`RegexPortabilityTest`).

The owner answered on 2026-10-20: make Android's reader do what the iPhone's does.

## 1. Highlight and Add Note (Q30)

iOS: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift`
`createAnnotationFromSelection(withNote:)`, `applyHighlightColor`, `existingHighlight(matching:)`
(locator-string equality via `ReadingAnnotationMatching.isSamePassage`), and the floating colour
bar (`colorBarAnnotationID`); `ReadingAnnotationColor.lastUsed`; `ReaderNoteEditor.swift`.

- **Highlight** marks the selection at once in the last colour used. No dialog. If a live
  highlight covers exactly that passage: the same colour removes it; another colour recolours
  it in place. After a new mark, the colour bar appears so the reader can refine with one tap
  (one tap applies and dismisses; picking a colour updates "last used").
- **Add Note** creates the mark (or takes the existing one) and opens the full note editor
  (`reader/ReaderNoteEditor.kt`, "Add Note" / "Edit Note"), which already keeps a typed note on
  Back and swipe (3dz). Never lose a typed note.
- Android today: the system menu items are in `reader/readium/ReaderSelectionContainer.kt:96`
  and `:101`; both open a dialog in `reader/ReaderScreen.kt` near `:1206`–`:1267` ("Add note" /
  "Highlight" / "Save note"). Replace the dialog path with iOS's. If the dialog holds anything
  the editor or colour bar does not (a colour choice before saving, for instance), keep it
  reachable through the colour bar or the editor.
- Where "last used colour" lives on iOS, find its Android equivalent; if Android has none,
  store it as a device preference (not in the backup, as iOS: check whether iOS backs it up and
  follow that).
- Tests: a JVM test of the toggle/recolour/new-mark rule (port iOS's tests for it if
  `KudosTests/` has them: search `ReadingAnnotationMatching`, `lastUsed`), and that Add Note
  routes to the editor for both a new and an existing mark.

## 2. "Customize Theme…" opens the reading-text sheet (Q29)

iOS: `Features/Reader/CustomizeThemeView.swift` (opened from `Settings/SettingsReadingPages.swift:62`
and `Settings/SettingsView.swift:71`, and from the reader). It is one sheet: a sample page, the
four themes, Font, Bold Text, a Customize switch, spacing, margins, Justify Text, Reset Theme.
Read the file for its exact order, labels and what each control writes.

- Android has two rows named "Customize Theme…": `settings/SettingsPages.kt:110` (Appearance:
  today it unfolds the accent colour's presets, the same as "Accent Color" above it) and
  `reader/ReaderScreen.kt:1022` (the reader's sheet: unfolds Bold Text and more). Make both open
  one shared Compose sheet with iOS's controls in iOS's order, bound to the preferences Android
  already has (spread over Appearance, Reader and Font today). Bold Text must be reachable from
  Settings too, as on iOS.
- Keep every control that exists today: the accent presets stay under "Accent Color" (or
  wherever iOS keeps them); the reader sheet's existing controls stay where they are as well
  as in the new sheet, unless iOS's reader sheet has removed them in favour of this one (follow
  iOS, and say which in the result file).
- Draw it with the shared parts in `ui/subject/` (`SubjectFormRow`, `SubjectToggle`,
  `SubjectSegmentedControl`, `subjectPanel`, `SectionRuleHeader`), as Settings' other pages do.
- Tests: a Compose or JVM test that both entries open the same sheet and that Reset Theme
  restores iOS's defaults (quote them).

## 3. Out of scope

"Fix Pronunciation" in the selection menu is brief 3ft (it needs a pronunciation store Android
does not have). Leave a clearly named hook for it in the selection menu code if that is
natural, but add no menu item.
