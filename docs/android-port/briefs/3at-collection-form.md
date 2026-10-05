# Brief 3at: the AO3 collection form (new and edit), and the two dead controls it revives

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result, and if a question remains, ask it at once and stop rather than guess. Write
`docs/android-port/briefs/3at-result.md` as you go.

Read `briefs/3as-result.md` with its landing note first: it is the pattern for an AO3 screen
that reads a form and writes it back (the repository read, `AO3WriteRepository`, the demo's
local answers, the tests), and for what was corrected on landing.

## What is missing

On the AO3 Collections list (`account/AO3CollectionsScreen.kt`) the "+" button and the "Your
items" chip do nothing. On a collection the reader maintains, Manage › Collection Settings
leads nowhere useful. iOS has the form: `AO3CollectionFormView.swift` (find it and the client
and write calls it uses, new and edit), and a screen behind "Your items" (find what iOS's chip
opens: `AO3Client+Collections.swift`, `updateUserCollectionItems`).

Start the result with what iOS has: every field of the form in iOS's order with its label,
footnote, kind, limits and default; which fields exist only when editing; the validation iOS
does before sending and its messages; the buttons and their words; what success and failure
look like; and the same for the "Your items" screen. Then build both on Android.

## Rules for the network

- Reads: AO3's own new-collection or edit-collection page, fetched when the form is opened, to
  take the form's fields, current values, token and action from what AO3 served. Nothing in the
  background.
- The write: one POST per confirmed Save, carrying the served form with the reader's changes,
  through Android's existing authenticated write path, exactly as iOS builds it (field names,
  method override, how unchanged and disabled fields are treated). Never retried. Success is
  recognised as iOS recognises it (read `collectionWriteVerdict`). Validation errors AO3
  returns are shown beside the form with the reader's entries kept.
- "Your items": as iOS, including whether it sends one request per item (iOS's
  `updateUserCollectionItems`; say what it does and match it).
- Read `docs/AO3_NETWORKING_POLICY.md` and say which rules cover the reads and the writes. If
  any forbids one, stop and say so at the top of the result.

## How it must be drawn

The form is a settings-style page: `SettingsPage`, `SettingsSection`, `SubjectFormRow`,
`SubjectToggle`, `SettingsActionRow`, `SettingsFootnote`, `SubjectSliderRow` (read
`settings/SettingsChrome.kt` and `settings/SettingsListeningPage.kt`). The settings chrome has
no text field row: look at how the New Collection sheet and the reader's note editor take text
on these tokens, and add one small text field row beside the chrome's other rows for this form
to use, with a label, a placeholder, a multi-line variant and an error line. Layout, content
and words are iOS's. The top buttons are the shared `ToolbarCircleButton`. Tokens only: no
stock Material chips, cards or default Material colours. Light, Dark, Sepia and OLED; every
text with a line height; rows that reflow at `isAccessibilityFontScale()`.

## Demo and tests

- The demo answers the form reads and the POSTs locally (`network/ao3/DemoNetwork.kt`, fixtures
  under `app/src/debug/assets/fixtures/`, original filler only): a new collection that
  succeeds, one whose name AO3 refuses with a validation message, and editing Winter Exchange
  2026. Say how to reach each on the emulator.
- Tests, none reaching the network: the form parser on the fixtures; the POST body built from
  the served form with changes; exactly one POST per confirmed Save and none on Cancel; AO3's
  validation message shown with entries kept; a session that changes while the request is out
  does not touch the screen.
