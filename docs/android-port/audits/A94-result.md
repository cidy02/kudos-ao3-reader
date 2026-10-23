# A94 result: adversarial review of Gemini's 3hc (read only)

*Done, 2026-10-23.*
- **Read:** `briefs/3hc.patch` (against `6c002b44`), Gemini's `3hc-result.md` with your landing note, and the brief.
- **Paths:** Android paths are under `android/app/src/main/java/io/github/cidy02/kudos/`, as applied in the lane. iOS paths are under `~/kudos-ios-polish/kudos-ao3-reader/`. Pixel values are sampled from the A88c shots.
- **Not done:** builds, Gradle, git writes, AO3.

**Verdict:** not fit to land as it is, but both fixes are small.
- **Item 4's colour goes the wrong way.** On the iPhone, a linked author in Add Works is tinted. The grey in the shot comes from the iPhone's demo data. My A88c note didn't see that, so the brief asked for the wrong thing.
- **Four of the six new tests should fail on the patched code.** They look up the wrong node, the wrong text or the wrong bounds.

The rest matches iOS. No ✅ row's screens change.

## Findings

### P2: Add Works' linked authors should keep the tint; the grey was the iPhone's demo data (item 4)

- **iOS tints a linked name here.**
  - `Features/Library/AddLibraryWorksSheet.swift:145-156` uses the `displayText:` init of `AO3AuthorBylineView`. That init passes no `tinted`, so it's the default `true` (`UIComponents/AO3AuthorNavigation.swift:69`, `:114-130`).
  - A name with a route is drawn `.foregroundStyle(tinted ? .tint : .primary)` (`:196`). Navigation is on by default (`:4`).
- **Why the iPhone's shot is grey:**
  - The iPhone demo builds its works with no author identities (`App/DemoLibrary.swift:25`, `:126`), so every name there takes the unlinked `.secondary` branch (`:219-223`).
  - Android's demo gives every sample work a registered identity (`app/DemoLibrary.kt:387`), so undertow is linked and tinted.
  - uncle_iroh_fan is added without one (`app/DemoLibrary.kt:597`), which is why it was grey on both.
  - It's a difference in the demo data, not in the code. It also colours every library byline in Android's demo the same way.
- **What `tinted = false` does** (`library/AddLibraryWorksSheet.kt:190`; `works/detail/WorkDetailIdentity.kt:230`): on a real phone, where imported works carry their AO3 identities, Android's Add Works would draw every author grey where the iPhone tints them.
  - Its meaning differs from iOS's parameter of the same name too: iOS's `tinted: false` gives `.primary`, Android's gives `secondaryInk`.
- **`includesBy = true` is right.** It's the default for this iOS init (`AO3AuthorNavigation.swift:117`).
- **Fix:**
  - Drop `tinted = false`, and drop the new parameter (no other caller wants it).
  - For iOS's caption size and regular weight, pass `compact = !isAccessibilityFontScale()`, as iOS passes `font: .caption, compact: !dynamicTypeSize.isAccessibilitySize`.
  - Record the demo difference rather than chase it in code. Android's bylines are 15.5 sp Medium today, against the iPhone's 12 pt caption.
- **No other caller changes:** `VerifiedAuthorByline` (`ui/components/SensitiveWorkRow.kt:308`, `settings/QueueStorageScreen.kt:240`) and `WorkDetailIdentityHeader` take the default `tinted = true`. With that default, the colour and the weight (`compact || !tinted`) are what they were.
- **My part:** A88c described this as a colour difference to fix ("all in the same secondary colour") and didn't check the demo's identities. The brief's item 4 came from that.

### P2: four of the six new tests should fail on the patched code (`Brief3hcContentTest.kt`)

None of these was run (Gemini ran nothing either). Each is read from the code.

1. **`collectionReorderRowsShareOneCardWithSeparators`, the ≤ 1 dp gap (`:114-121`)**
   - The row's `semantics(mergeDescendants)` comes after its `padding(vertical = 10.dp)` (`library/CollectionReorderSheet.kt:201-202`). A semantics node's bounds start at the next layout modifier inside it, so they leave out the padding.
   - Between two rows the gap is 10 + 0.5 + 10 ≈ 20.5 dp, so the assertion fails. On the old code it was 28 dp.
   - **Fix:** assert `< 22.dp`. That still fails on revert.
2. **`queueSeedRowsHaveHorizontalGapAndIndentedSeparator`, the inset (`:199-202`)**
   - `SubjectRowSeparator` applies the caller's modifier before its own `padding(start = inset)` (`ui/subject/SubjectComponents.kt:248-250`). The tag's bounds therefore start at the card's edge, x = 0, and `separatorBounds.left >= radioBounds.right` (about 37 dp) fails.
   - **Fix:** sample a pixel on each side of 43 dp, or drop that assertion. The count and the vertical order are enough.
3. **`addLibraryWorksPrefixesBy…`, the click (`:220`, `:258`)**
   - The fixture's identity is `{"display":…,"username":…,"pseud":…}`. `AO3AuthorIdentities.byline` matches only `displayName` with `kind` registered or orphaned (`network/ao3/author/AO3AuthorIdentities.kt:46-48`).
   - So undertow isn't linked, there's no "Author: undertow" node, and the click fails.
   - It also means the colour assertions pass whether or not `tinted = false` is there.
   - **Fix:** use the demo's form (`"displayName"`, `"kind":"registered"`), and with the P2 above, assert the linked name is `scopePalette.accent`.
4. **`chapterPickerUsesOpenBookIcon…`, the text lookups (`:269-290`)**
   - `AO3ChapterRef(1L, 1, "1. Arrival").displayName` is "Chapter 1 · 1. Arrival" (`network/ao3/chapters/AO3ChapterIndex.kt:18-22`). `onNodeWithText("1. Arrival")` matches the whole text, so it finds nothing.
   - **Fix:** titles that repeat the generic name (`AO3ChapterRef(1L, 1, "Chapter 1")`, shown as "Chapter 1"), or look up the full display names.

The other two (the collection editor and the series Draft) should pass, and each fails with its change reverted.

### P3: the collection's details sheet (`collectiondetails`) is a form on the iPhone, so its cards are cream in Sepia, not glass (item 2)

- **New collection is right:** `newcollection` and the reorder sheet are `.subjectPanel()` glass on iOS (`Features/Library/NewCollectionSheet.swift:106-125`; `UIComponents/SubjectForm.swift:29-41`, `:65-104`).
  - Sampled iPhone Behaviour cards: (230,230,235) on (242,242,247) in Light, (224,211,183) on (236,222,193) in Sepia.
  - Android's are (230,230,234) and (224,211,183), the same.
- **Details differ:** the details sheet is a `Form` section with `.appThemedRows()` (`Features/Library/Collections.swift:186-220`; `UIComponents/AppThemeSurface.swift:26-35`). Its cells take `appElevatedBackground`.

  | Theme | iPhone colour and Behaviour cards | Android Behaviour card | Android new colour card (`library/CollectionEditorSheet.kt:271`) |
  |---|---|---|---|
  | Sepia | cream #FBF0D9 on #ECDEC1 | (224,211,183): darker than the sheet, the wrong way | glass, so the same |
  | Dark | (34,34,40) | — | — |
  | OLED | (28,28,30) | — | — |
  | Light | darker than the glass sheet | glass is right | glass is right |

- **Fix:** it's A93's reader-sheet case (`cardSurface` in Sepia, Dark and OLED; glass in Light). `cardSurface` is exactly the iPhone's #222228 and #1C1C1E in Dark and OLED. Fold the editing branch's two cards (`:271`, `:305`) into 3hd's mechanism.
- **Pre-existing:** the Behaviour card was already this way. 3hc adds a second card that copies it.

### P3: the reorder rows became one non-lazy item, and a dragged row has no ground (item 1)

- **The structure:** `library/CollectionReorderSheet.kt:167-168` puts every row in one `item { Column(...subjectPanel()) }`.
  - **Every row composes and lays out at once.** For a big collection that's every row on open. iOS's `List` + `ForEach` + `.onMove` stays lazy (`NewCollectionSheet.swift:246-255`).
  - **The rows have no fill of their own.** While a row is dragged (`graphicsLayer` translation), its text slides over the rows under it with nothing behind it.
- **Spacing:** removing the list's `spacedBy(8.dp)` moved things.
  - The header to "Reading order" loses 8 dp.
  - The label to the card goes from 12 dp to 8 dp.
  - The card to the footnote goes from 16 dp to 8 dp.
- **Simpler and closer to iOS:** do what the series reorder already does (`writing/WritingSeriesScreen.kt:126-129`, `:170`).
  - Keep `itemsIndexed`, and give each row `.writingSuggestionPanel(index == 0, index == ordered.lastIndex)`, with a `SubjectRowSeparator` under every row but the last.
  - That's iOS's `subjectPanelSegmentRow`. It keeps the list lazy, and each row carries its own segment while dragged.
  - Put the list's spacing back on the items that lost it.

### P3 (small): what's left in the chapter picker and the seed rows

- **Chapter picker, the unselected total** (`comments/CommentsScreen.kt:850`):
  - The iPhone draws it at the tint's second level, a paler purple: sampled (138,121,170) in Light, (163,144,170) in Sepia, (94,74,130) in Dark.
  - Android uses grey `secondaryInk`. `palette.accent` at about 0.6 alpha would match.
  - The test asserts the grey (`:299`).
- **Chapter picker, two small differences:**
  - Android puts the ✓ before the total (`:844-850`); iOS puts the total, then the ✓ (`Features/Comments/CommentsView.swift:1012-1027`).
  - Android keeps SemiBold on the chosen row (`:840`, `:906`); iOS sets no weight.
  - Both were there before 3hc.
- **Seed rows** (`library/QueueEditorSheet.kt:311`):
  - iOS's inset of 43 is 13 + its 19 pt ring + 11, which lines the hairline up under the label (`Features/Library/NewReadingQueueSheet.swift:308-314`).
  - Material's `RadioButton` is 24 dp, so Android's label starts at 48 dp, and the line starts 5 dp to its left. Use 48 dp.

## Your specific questions

- **Item 4:** "by" matches iOS. The colour doesn't: see the first P2. No other caller changes.
- **Items 1 and 2, glass:**
  - Right for the reorder card and New collection: iOS draws both with `subjectPanel`, and the sampled values match.
  - Wrong for the details sheet in Sepia (and, by the same mechanism, Dark and OLED): it's a form there. See the first P3.
- **Item 5:** yes, iOS colours every row's label and icon.
  - Sampled ink (72,37,133) in Light on All Comments, Chapter 1 and Chapter 3 alike, the same as the ✓.
  - The code reads as if only the chosen row is tinted. But each row is a `Button` in a `List`, and `.foregroundStyle(.primary)` there is the first level of the button's tint, not the label colour.
  - `palette.accent` matches iOS's tint: `screenTint(palette)` is `accentTint(palette.tint)`, and for a title-hued page `tint` is `accent` (`UIComponents/SubjectSurface.swift:76`).
  - The open book matches iOS's "book" in the picker and on the page's chip (`CommentsView.swift:632`, `:1062`).
- **Item 6:** right.
  - iOS draws `SubjectChip(text: "Draft", style: .neutral, palette: theme.scopePalette)` on exactly these two rows (`Features/Writing/SeriesEditView.swift:419-421`, `:559`; palettes `:325`, `:488`). Android's `palette` there is `tokens.scopePalette` (`writing/WritingSeriesScreen.kt:57`).
  - The one change (`:161`) sits in the reorder and remove branch only.
  - The other `SubjectStateBadge` callers match iOS's uppercase badge (works, author series, drafts expiry: `WritingDraftsView.swift:283-286`).
  - TalkBack reads "Draft" twice, once in the row's own description and once from the chip's. That was so with the old badge too. `clearAndSetSemantics {}` on the chip would make it once, as iOS does (`SeriesEditView.swift:425-427`).
- **Tests that pass with their change reverted:**
  - Add Works' colour and weight assertions, as written (its fixture isn't linked).
  - The chapter picker's grey total (a guard, and the old value).
  - Otherwise each test fails on revert. The four in the second P2 also fail without reverting anything.

## Checked and fine

- **No ✅ row's screens change.** The touched screens are in Local collections, Reading queues, Comments and Writing, all 🟦. The shared byline is unchanged at its default. `ChapterPickerSheet`'s only caller is Comments.
- **Extractions keep behaviour:**
  - **`AddLibraryWorksContent`:** query, selection, Clear Search, the mature reveal and the author tap all route to the same state.
  - **`CollectionEditorContent`:** each setter still saves in edit mode, as before. The footnote and Description keep their places in both modes.
  - **`QueueSeedPanel`:** same rows, enabled rule and subtitles.
- **The reorder's behaviour:**
  - `key(work.id)` keeps each row's state across moves, and the bounds clean-up is unchanged.
  - TalkBack's Move up and Move down use the current index.
  - The separators sit outside the keys.
- **New collection's card:** Name, Description and swatches in one `subjectPanel`, as iOS's `collectionPanel` (`NewCollectionSheet.swift:106-125`).
  - Its fields stay outlined under small uppercase labels, which the brief allowed. The first swatch sits at 14 dp and the fields at 12 dp, a 2 dp step.
- **Seed rows:** 13 × 11 padding, an 11 dp gap and 2 dp between title and subtitle, as iOS (`NewReadingQueueSheet.swift:279-294`).
- **Gemini's iOS quotes:** all are real code. The three misattributed paths are as your landing note says.

**P1 0 / P2 2 / P3 3**
