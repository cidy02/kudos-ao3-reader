# 3he: Android fixes from the parity verification, batches 1 and 2 (A102)

The owner asked for Android parity to be verified before any iPhone Duo work. Two judges (Claude-Code and
Claude-CLI) compared fresh pairs from both phones, in five columns: Dark, Light, Sepia, OLED, and Sepia at
the largest text. The iPhone is the reference: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` at `HEAD`.
Its working tree has uncommitted Duo work, so read with `git show HEAD:<path>` where it matters. Each item below
was measured on the shots and traced in code. Fix the cause, not the screen.

**Where:** `/Users/cidy02/kudos-agent-codex`, branch `android/agent-codex-3he` (already created from the lane's
`53649f26`). Touch only what the items need.

**Rules:**
- Do not run Gradle; your sandbox blocks it, and Claude-Code runs the gate.
- Do not sign in or contact archiveofourown.org.
- Do not change the schema, migrations, backup keys or `project.pbxproj`.
- Do not revert anyone's work.
- Commit on your branch with explicit paths (never `git add -A` or `.`). End each commit message with
  `Co-Authored-By: Codex <noreply@openai.com>`.
- One commit per item is ideal.

The rule behind items 1 to 5 is the iOS colour contract:
- Scope surfaces (pickers and forms opened over a page) use the app accent, brown in Sepia (iOS T-446).
- A coloured sheet (one with its own subject colour) gives all its controls that colour (owner, 2026-10-22).
- Fills, meaning switches, filled buttons and selected pills, use the exact colour, never the lightened text
  accent (owner question Q19, T-348).
- Only iOS's coloured editor sheets draw a wash (`NewReadingQueueSheet.swift:139`, `NewCollectionSheet.swift:79` and
  `:288`).

## 1. Sheets that Android washes but iOS keeps flat
Each of these draws a `subjectScreenWash` inside its sheet. On the iPhone, each sheet is one flat theme ground. In
Dark, Android's top band reads (62,7,8) against the iPhone's (22,22,27).
- **Work Details' forms:** `works/detail/WorkDetailForms.kt:87` puts `.subjectScreenWash(tokens.scopePalette)` on the
  `LazyColumn` of the shared form sheet. That covers Add to Queue and the Bookmark form, and any other form using it.
  Check each against its iOS sheet, and keep a wash only where the iOS sheet has `subjectScreenWash`:
  - `AddToQueueView` (`Features/Library/ReadingQueues.swift`);
  - the bookmark form;
  - `SeriesPreservationPromptSheet`;
  - the download-date editor;
  - the My Copy sheet.
- **The queue page's bulk Tag sheet** ("Your changes apply to all N selected works"): purple wash, purple Done and
  "+". Make it flat, with its controls in the app accent (red, brown in Sepia). The iPhone's amber is its own bug.
- **The collection's details sheet** (colour, description, behaviour). iOS `Features/Library/Collections.swift:282`
  `detailsSheet` is a plain `Form` with `.appThemedScroll()`: flat. Its Done and switches are the collection's colour,
  inherited from the page's `.screenTint(palette)` at `:572`. Keep the coloured controls and drop the wash.

## 2. Author page: Subscribe in Dark and OLED
`author/AuthorProfileComponents.kt:176` is a bare Material `Button`. In Dark and OLED, Material `primary` is
`PaperWarm` (`ui/theme/Theme.kt:55,68`), so it draws a cream fill (244,232,215) with red text. The iPhone draws the
exact accent (153,0,0) with white text, and so does Android in Light. Give it the page's exact fill with
`SubjectPalette.label(fill)` as content. Use the same colour the page's selected "All" fandom pill already uses,
which measures exact. `library/LibraryFilterPanel.kt:117` shows the pattern.

## 3. Writing forms' switches (and every `SubjectToggle`)
`writing/WritingWorkFormScreen.kt:486` `WorkFormToggle` passes `scopePalette.accent`, the text accent. Chapter form's
"Set a different publication date" measures:

| Theme | Android now | iPhone |
|---|---|---|
| Dark, OLED | (219,114,114) | (153,0,0) |
| Light | (133,37,37) | (153,0,0) |
| Sepia | (122,86,49) | (154,103,50) |

Use the exact tint, the one the author works filter sheet's switch uses (it measures exact). Then grep every
`SubjectToggle(` call and every other switch, and make each fill exactly. A77's W09 named
`library/QueueEditorSheet.kt:203` and `library/CollectionEditorSheet.kt:250`; check whether they are already exact.

## 4. A coloured sheet's Cancel
In the collection's Reorder works sheet, Done is the collection's green. Cancel is Material primary: red in Light,
cream in Dark. On the iPhone, both are the sheet's green (`.screenTint(palette)`). Make every header action in a
coloured sheet take the sheet's palette: reorder works, new and edit collection, new and edit queue, and any other
sheet that sets its own palette. A77 C38 found the same at `library/QueueEditorSheet.kt:110`.

## 5. Choice values on the AO3 collection's manage pages
On Maintainers, "Invite as · Moderator ⌄" is red. The iPhone's is the page's teal. `SubjectFormRow` colours a choice
with `LocalSubjectPalette.current.accent` (`ui/subject/SubjectForm.kt:153`). `account/AO3CollectionMaintainersScreen.kt:64`
provides `LocalKudosTokens` and Material colours from the teal palette, but not `LocalSubjectPalette`. Provide it.
Then check every manage and challenge page that builds its own palette for the same gap: moderation, collection
settings, sign-ups, sign-up, assignments, prompts, challenge settings and tag set.

## 6. AO3 Account header inset (author About and Bookmarks)
`author/AuthorProfileScreen.kt` around line 722: the `usesAccountHeader` branch calls
`SubjectHeaderBlock(..., palette = palette)` without `gutter = 0.dp`, so the block's own gutter stacks on the list's
padding. The error branch, around line 703, passes `gutter = 0.dp`. The kicker, title and subtitle then sit about
24 dp further in than "Bio" and the cards. The iPhone aligns them all to one margin.

## 7. Serif where iOS sets editors in serif
iOS uses `design: .serif` in four places:

| iOS | What | Android |
|---|---|---|
| `Features/Challenges/ChallengeSignUpView.swift:350,357` | The sign-up prompt editor and its placeholder | `account/AO3ChallengeSignUpScreen.kt`, sans |
| `Features/Challenges/ChallengeSettingsEditView.swift:273,280` | The sign-up instructions editor | `AO3ChallengeSettingsEditScreen` |
| `Features/Writing/WritingTextEditor.swift:629` | The text editor | `writing/WritingTextEditorScreen.kt` |
| `Features/Comments/CommentMarkup.swift:324–330, 534–561` | The formatting tray's B/I/U/S/Aa letters | the comments formatting tray |

Android already uses `FontFamily.Serif` for the sign-ups list, the work summary, queue settings and Customize
Theme. Match iOS's sizes where iOS sets one.

## 8. Collections filter: "Order by" shows no ⌄
On the AO3 Collections filter sheet, the value "AO3 order" has no choice mark. The iPhone shows ⌃⌄. Draw it as a
choice (`showsChoice = true`), as brief 3cr did for the other choices.

## Tests
Add a focused test per item where the existing test style allows it. Precedents are `FandomListA88Test`,
`PairingSheetA88Test` and `A88dSmallFixesTest`. Assert the colour or font each item names. Each test should fail with
the fix reverted, so say how you checked that by reading. Follow the repo's Compose test lessons:
- reset sticky global state;
- read palettes through `LocalKudosTokens` inside content;
- call `waitForIdle` before reading composition-set values.

Where a test is impractical, say so. Don't fake one.

## Report
Write `docs/android-port/audits/3he-result.md`:
- per item: what you changed (`path:line`), the iOS reference, the test, and anything you left out and why;
- every other call site you changed under the "check every" sentences;
- anything you think the brief got wrong.
