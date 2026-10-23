# Brief 3hb (Android): what the re-review of the re-shot screens found (A88c), part one

**Write code in this worktree only (`/Users/cidy02/kudos-agent-codex`, branch `android/agent-codex-3hb`, from
the lane's landing of 3ha). Do not commit, push, switch branches, sign in, contact archiveofourown.org, or
run Gradle (Claude builds and tests).** Do not edit `TASKS.md`. Write `docs/android-port/briefs/3hb-result.md`
first; per item `path:line`, what changed, and per test what it does with its change reverted. iOS is the
reference (`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`). Reviews:
`/Users/cidy02/kudos-agent-ios/docs/android-port/briefs/A88c-cli-result.md` (Claude-CLI, with causes) and
`/Users/cidy02/kudos-agent-flash/docs/android-port/audits/A88c-gemini-result.md` (Gemini). Tiles:
`/Users/cidy02/kudos-tools/pairs/tiles-a88c/<name>.png`; raw shots `/Users/cidy02/kudos-tools/pairs/shots/`
(`a_` Android, `i_` iPhone; `_dark _light _sepia _oled _big`). Avoid dialog windows in Robolectric tests
(test the content composable). Another agent (brief 3hc) is editing collection reorder, the collection and
queue forms, Add Works' bylines, the comments chapter picker, the Draft badge and the remote work row's date
at the same time: don't touch those.

1. **The wash restarts at a pinned field** (`tagseditor`, `collectionsgifts`; every Android column). Under the
   subtitle there's a hard edge, then a second band of wash from the field down (Claude measured it: the
   Light page's wash fades to (237,230,235) at y=640 and restarts at (227,201,205) at y=680). Both
   `stickyHeader`s paint their own `.subjectWash(palette, SubjectMetrics.defaultWashHeight)` as an opaque
   ground (`writing/WritingTagsEditorScreen.kt:126-130`, `writing/WritingAssociationPickers.kt:131-133`),
   there since `531a11a9`. The iPhone's wash fades once with no seam. Keep scrolled chips/rows from showing
   under the pinned field, but give the field an opaque ground only while it's pinned (or paint the page's
   ground as it is at that offset). One shape for both.
2. **`collectionsgifts`**: a gift recipient's remove is a red ✕; the iPhone's is a red ⊖ (read iOS's icon).
3. **Cards in sheets are darker than the sheet** (Sepia: `readerdisplay`, `readernote`; Light and Sepia:
   `pronunciations`, `backupimport`). The iPhone's are lighter: white on #F2F2F7 in Light, cream #FBF0D9 on
   tan in Sepia; Android's are #E6E6EA on #F2F2F7 and #E0D3B7 on #ECDEC1. Android's own `readerspeech` sheet
   already gets it right (white cards in Light, cream in Sepia): find what it uses and use the same in these
   four. (`panelFill` is not it; only collection screens use that.)
4. **`queuetags`**: with the field empty, Add is drawn in full accent, where the iPhone's is pale. The button
   is disabled, but `Text("Add", color = palette.accent)` overrides the disabled colour
   (`library/QueueTags.kt:458`, `:225-226`).
5. **`texteditor`'s bar title** is cut in every column ("Chapter …", "Cha…" at 2.0×). iOS sets
   `.navigationTitle(title)` (`Features/Writing/WritingTextEditor.swift:117`), but on an iPhone the bar's
   buttons leave it no room, so no title is drawn (all five iPhone columns). Draw the editor's title only
   when it fits whole, otherwise none; TalkBack should still get it (pane title). Other screens'
   `customTitle`s (selection counts, `home/HomeSectionListScreen.kt:260`, `author/AuthorProfileScreen.kt:461`)
   must keep their behaviour.
6. **`customizetheme`**: the section headers are uppercase ("TEXT", "ACCESSIBILITY & LAYOUT") where the
   iPhone's are "Text" and "Accessibility & Layout" (Android's other reader sheets use title case too); the
   Font row has no chevron after "System"; and at 2.0× the preview's text grows with the font scale ("A Study
   in / Starlight" on two lines) though the reader's text doesn't. The iPhone's preview stays at the reader's
   size at AX5. Match.
7. **`pagejump`**: the current Nearby tile is the red accent (Dark, Light, OLED); the iPhone's is the page's
   tan in every theme (Sepia matches). Read iOS's page-jump tile fill. Also the works pages' pager next arrow
   (`fandomworks`, `tagworks`) is the red accent where the iPhone's is the page's brown: check the pager
   against iOS and match.
8. **Reader sheets in Sepia**: the Contents sheet's Done ✓, and the Display sheet's check and "Customize
   Theme…", are dark grey where the iPhone's are the Sepia accent (`readercontents`, `readerdisplay`). The
   Contents rows have no dividers where the iPhone's do.
9. **`readerfind` and `readernote`** open at full height with the field focused and the keyboard up; the
   iPhone opens at its half-height detent and waits for a tap. Read iOS (`Features/ReaderReadium/`) and
   match the opening focus and height.

Not to change (decided): Android's extra rows below the iPhone's fold on the reader sheets; Cancel/Done text
against capsules; the voice-engine notes.

Tests for every behaviour change, each failing with its change reverted.
