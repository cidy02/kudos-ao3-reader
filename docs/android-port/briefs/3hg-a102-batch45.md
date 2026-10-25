# 3hg: Android fixes from the parity verification, batches 4–5 (A102)

Same setup as 3he and 3hf. Their briefs are in this worktree's `docs/android-port/briefs/`, and the Readium notes
are at the worktree root.
- **Where:** `/Users/cidy02/kudos-agent-codex`, branch `android/agent-codex-3he`, which now holds 3he `ef99bb6b` and
  3hf `2ce2498a`.
- **Rules:** no Gradle, no sign-in or AO3 traffic, no schema or backup changes, never revert anyone's work.
- **Committing:** if the git index can't be written, leave the edits uncommitted and say so.
- **Report:** write `docs/android-port/audits/3hg-result.md` in 3hf's shape.

## 1. The queue page's Compact grid drops its second column (a real bug)
In Compact mode, In Line (`library/QueuePageScreen.kt:396–418`) draws `inLine.chunked(2)` as `Row`s of two
`QueueWorkItem`s. A swipeable item wraps its card in `SwipeActionRow`, which applies `fillMaxWidth()`
(`ui/subject/WorkLibraryComponents.kt:271`). So the first card in each row takes the whole width and its partner gets
none.

On the emulator, "IN LINE 4" shows only Sodium Lights and Winter Garden. The iPhone shows all four in two columns:
Sodium Lights and a blurred card, then Frozen and Hades.

Make both cards in a row share the width: each takes half, with the 8 dp gap. In a final row with one card, the card
keeps a half-width slot. Keep the swipe actions and the obscured (no-swipe) path working. Check whether any other
hand-built two-column grid puts a `SwipeActionRow` inside a `Row`.

**Test:** compose a queue page (or the In Line block) with four works in Compact mode, and assert that both cards of
the first row are displayed with a non-zero width side by side.

## 2. The queue tag manager's dialogs take the queue's colour
iOS `QueueTagEditSheet` (`Features/Library/QueueTagManagerView.swift:314`) is the queue's colour: its own wash at
`:411` and `.screenTint(palette)` at `:451`. Android's Edit tag `AlertDialog` (`library/QueueTags.kt`, around
`:625–691`) and the tag manager's other dialogs (around `:390`, `:430`, `:573`) take Material primary, the app accent.
On the purple Neon reread queue, Cancel is (152,0,0) in Light and brown in Sepia; the iPhone's is purple.

The dialog form itself is decided. Give these dialogs the queue's `palette` (`SubjectPaletteTheme(palette)`), so
their buttons, radio and check marks, and field cursor take it.

## 3. Add Note's Done is in the accent
`reader/ReaderNoteEditor.kt:100` draws Done as a `ToolbarCircleButton` with no tint, so its ✓ is primary ink. The
reader's other sheets (Contents, Find, Display) and the iPhone draw it in the accent. Tint it as those siblings do.

## 4. Preference help's ground in Light
iPhone, measured in Light: the help sheet's ground is (242,242,247), with white cards (255). In Dark, Sepia and OLED,
Android already matches: (11,11,13) with (34,34,40) cards, (236,222,193) with (251,240,217), and (0,0,0) with
(28,28,30). Android's Light sheet is all white, so its white cards vanish. The cause is
`account/AO3PreferencesScreen.kt:482` `presentSheet(LocalKudosTokens.current.sheetGround)`.

Use the page's own ground (`tokens.background`) there. Leave the text editor's recovery sheet
(`writing/WritingTextEditorScreen.kt:270`) on `sheetGround`: the iPhone's recovery sheet is white in Light.

## 5. Series picker: the selected mark
In Edit Work › Series (`writing/WritingAssociationPickers.kt`, the series list), the iPhone marks the work's series
with a filled check circle (`checkmark.circle.fill`, accent) and the others with an empty circle. Android draws a bare
✓ for the selected one. Use the filled check circle in the accent, with the same empty circle for the rest. Keep
Android's extra "This work is in it" line.

## 6. The formatting tray's remaining glyphs
3he set B/I/U/S/Aa as serif letters. Three more differ from the iPhone tray (`Features/Comments/CommentMarkup.swift`):

| Tag | iPhone | Android |
|---|---|---|
| Superscript | A² | X² |
| Subscript | A₂ | X₂ |
| Heading | H | T |

Match the iPhone's glyphs: serif letters where iOS draws letters, at iOS's sizes. Leave Quote, Bullets, Numbers,
Code, Divider, Link and Spoiler as icons. Extend 3he's `formattingLettersUseIosSerifSizes` test to cover them.

## Tests and report
Follow 3he and 3hf. Add one focused test each for items 1–3, each failing with its fix reverted. Say how you checked
that by reading.
