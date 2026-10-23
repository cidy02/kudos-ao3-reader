# I10 result (iOS): the second half's iPhone faults (A82b, A84b)

*Done. Branch `claude/agent-ios-i9`, on top of the uncommitted I9/I9b. Nothing committed. Paths under `kudos-ao3-reader/`. I10 touched 15 files, 13 of them new to the branch (32 in all with I9 and I9b).*

**Checked against I9b first:**
- `bulktagstate` and `backupimport` were also white under Sepia in A82b. Both were fixed in I9 (`.appThemedRows()` moved onto their sections). A82b shot polish's 7dc23568, which has neither fix.
- `inboxfilter`'s blank title was fixed in I9b.

## 1. Sepia misses

- **`colsfilter`: the pinned Reset bar.** `.background(.bar)` was the system's white under Light and Sepia. It now uses the page's own ground fading upward, the gradient Challenge settings' pinned Save bar already uses (`Features/Account/AO3CollectionsFilterPanel.swift:173`).
- **`recovery`: the sheet.** The content now sits on the theme's base (Sepia, Dark, OLED); Light keeps the system's sheet (`Features/Writing/WritingTextEditor.swift:356-370`).
- **`texteditor`: the formatting bar's container.**
  - `.regularMaterial` was light grey under Sepia. Sepia, Dark and OLED now take the base with the same 9% glass fill Android's bar has; Light keeps the material (`WritingTextEditor.swift:279-286`).
- **`bulknames`.**
  - In a card list, a row without `.cardRow()` is the system's white band, and these rows had none.
  - The added names are cards now, under the card list's own "Added" header (`Features/Writing/BulkTagStatePicker.swift:170`, `:173`).
  - The name field and Add are one card, as the app's other "New … Add" rows (`:192`).
- **`pairing`: the sheet.** Both steps' Forms (the pairing form and the name-it step) get `.appThemedScroll()` and section-level rows through a `Group` (`Settings/PairingSheet.swift:304`, `:373`).
  - The "Deletion signing" card on the Sync Folder page was already themed: `SettingsPageForm` wraps its sections in a `Group` with `.appThemedRows()`.
- **`revokedevice`: the Reason card.** It is themed (`PairingSheet.swift:239`). The picker's label is hidden (`:237`): the section already asks "Why are you removing this device?", and the inline picker drew "Reason" as a row of its own inside the card.

## 2. Text cut at AX5

- **`seriesreorder`:** at accessibility sizes the position number goes above the title, and the title is unlimited (`Features/Writing/SeriesEditView.swift:403`, `:413`). This is the same reflow as I9's collection reorder.
- **`seriesremove`:** the title is unlimited at accessibility sizes (`SeriesEditView.swift:553`). Its remove button stays beside it.
- **`chapterform`:** at accessibility sizes "After chapter" goes above its field (`Features/Writing/AddChapterView.swift:180`, `AnyLayout`). Beside the field it broke onto a second line.
- **`texteditor`:**
  - The footer "Recovery copy on this device · Save from the work form" keeps its full height (`WritingTextEditor.swift:103`, `fixedSize`); the editor above gives way.
  - Done becomes the app's checkmark at accessibility sizes (`:140`, labelled "Done"). The word no longer fitted beside the four icons and the system folded it into "•••".
- **`recovery`:**
  - At accessibility sizes the sheet scrolls, the copy keeps a fixed 240 pt height, and the heading, notes and actions take their full height (`WritingTextEditor.swift:356-370`, `:389`, and the `fixedSize` on the content).
  - Below those sizes the layout is unchanged.
  - The second paragraph A82b mentions ("The text on the form has changed…") is the demo data's doing, not a fault. Both apps show it only when the form changed since the copy began; Android's demo copy matches its form.
- **`parentpicker`:**
  - "Language of the source": `WritingChoiceRow`'s value now takes two lines, and is unlimited at accessibility sizes (`Features/Writing/WritingFormFields.swift:38`). This was "Please select a la…" at every size. Every `WritingChoiceRow` (Rating, Language, bulk edit's choices) gains the same.
  - The URL field wraps (`Features/Writing/WorkAssociationPickers.swift:691`, `axis: .vertical`, 1–4 lines). A typed return is dropped, since a URL has none.
- **`availability`:** a large title can't wrap ("Check Avail…"). At accessibility sizes only, it becomes the two-line inline title (`Features/Account/AvailabilitySweepView.swift:46`). Below them the large title is as it was.
  - For this, `wrappingInlineTitle(_:isActive:)` gained `isActive` (`UIComponents/SubjectScreen.swift:148`); `false` leaves the plain title.
- **`revokedevice`:** the title uses `wrappingInlineTitle` (`PairingSheet.swift:243`). It was "Revoke Demo readi…" at every size.
- **`WritingTextEditorRow`'s second line:** unlimited at accessibility sizes (`WritingTextEditor.swift:544`).
- **Tag suggestion names:** unlimited at accessibility sizes (`Features/Writing/WritingTagsEditor.swift:338`).

## 3. Titles

- **Co-creators and Inspired by:** `.navigationTitle("")`, as `WritingTagsEditor` does (`WorkAssociationPickers.swift:565`, `:679`).
  - A title set before the wash outranks the wash's blank one, so the bar named the page above its own header block.
- **`prefhelp`:** the title card is gone (`Features/Account/AO3PreferencesView.swift:314`).
  - The sheet's title is already the same words (`helpSheetTitle` returns `content.title`), and the card added only a "?" mark.
  - The topics and the footer now start at the top.
  - The type's `// swiftlint:disable:this type_body_length` became superfluous (it is now under the limit) and is removed (`:8`).

## 4. `aboutkudos`

- The License now reads bold "GNU Affero General Public License v3.0 (AGPL-3.0)" (`Settings/AboutView.swift:32`, `Text` interpolation with `.bold()`).
- A `"…" + "**…**"` concatenation is a `String`, not a Markdown `LocalizedStringKey`, so it drew the asterisks.

## 5. `seriesremove` opening with "0 works"

**Not an app fault: the A82b shots of `seriesremove` (and `seriesedit`) were taken on a build that did not yet have the demo's manage page.**
- Their status bars read **8:16–8:17 PM** (`seriesedit` 8:14–8:15). The app in the simulator was built at **8:51 PM**: `…/Bundle/Application/940B7E2B…/Kudos.app`, read on disk and nothing launched. That build is the first with the `^/series/\d+/manage → ao3_demo_series_manage` route, committed in 7dc23568 at 9:01 PM.
- `seriesreorder`, shot at **8:58 PM** after that install, lists all three works from the same page.
- The current code reads the works:
  - `loadSeriesForm` fetches `/series/<id>/edit`, then `/series/<id>/manage` (`Services/AO3WorkActions.swift:36-47`).
  - The demo route is present (`App/DemoLibrary.swift:736`), and the fixture is in both checkouts' `KudosTests/Fixtures`.
  - `parseSeriesManagePage` reads the fixture as three rows (3211 First Light, 3212 A Lamp at the Crossing, 3213 The Last Window (DRAFT)). Checked with a throwaway script compiled against the SwiftSoup checkout; not a project test.
- Nothing changed. **Re-shoot `seriesedit` and `seriesremove`:** they should show "3 works", and the editor's Reorder works and Remove works should show 3.
- Both apps keep the editor when the optional manage read fails (iOS `try?`, Android `WritingSeriesState.kt:77-86`), which is why a missing page read as "0 works" rather than an error.

## 6. The two select-mode counts

- **Confirmed and fixed.**
  - `RecentlyDeletedView` and the queues grid set `navigationTitle(isSelecting ? "N selected" : "")` after `.subjectScreenWash`, whose `hidesNavigationBarChrome()` sets `""`. The inner title wins, so the count never showed.
  - Neither header block shows it either: Recently Deleted's says "N items", and the grid's has no count.
- Each title is now set before its wash (`Features/Library/RecentlyDeletedView.swift:73`, `Features/Library/ReadingQueueOrganizer.swift:311`). The bar reads "N selected" while selecting and stays blank otherwise.

## Left for the owner: `colitems`' Unrevealed and Anonymous

**Neither app has a rule of its own: both draw a switch only where AO3's page leaves the field enabled.**
- iOS: `item.unrevealedIsEditable`/`anonymousIsEditable`, else "On"/"Off" (`Features/Account/AO3CollectionItemsView.swift`, `flagRow`). Android: `item.unrevealedEditable`, else "On"/"Off" (`account/AO3CollectionItemsScreen.kt`, `ItemFlagRow`).
- The difference in A82b comes from the demo. iOS opened the account-wide items page ("Your works in AO3 collections"), the creator's view. Android opened one collection's items page ("Winter Exchange") as its maintainer.
- On AO3, as I recall otwarchive's collection items form (not re-read; no AO3 access here): only a **collection maintainer** may set Unrevealed and Anonymous, and a work's creator sees them disabled. A creator's own control is approving or declining the item.
- So iOS's read-only text is right for the page it showed, and Android's switches are right for the page it showed.
- Re-shooting both on the same page would settle it visually: either both apps on `acct:collections` → a collection's Manage Items, or both on "Your items".

## Tests to add (Claude runs them)

These changes are layout and modifier placement; no rule changed, and the project has no view-inspection tests. Two that would hold behaviour:
- **`WorkParentWorkPickerView` URL newline stripping:** drive the binding with "https://a\nb" and expect "https://ab". It would need the binding pulled into a static helper first (not done here, to keep the diff small).
- **The demo manage page:** add to `KudosTests/AO3WorkFormParsingTests.swift`, which already tests `parseSeriesManagePage` but not the demo fixture, a test that parses `ao3_demo_series_manage.html` and expects three rows, the third a draft. It passes today; it would fail if the demo page or the parser broke, which is what an "0 works" shot would otherwise be the first to show.

## Build and lint

- **iOS:** arm64 simulator SDK, `-derivedDataPath …/kudos-agent-ios-ios`, BUILD SUCCEEDED (built twice; the second after the last edit).
- **macOS:** `…/kudos-agent-ios-mac`, BUILD SUCCEEDED.
- **Compiler warnings:** none new. The warnings in touched files predate this change and show only because those files recompiled: `AO3PreferencesView.swift:210` (HEAD's `return HStack` in a `@ViewBuilder`) and `AddChapterView.swift:387`, `:395`, `:450` (unused `withSlot` results in untouched code).
- **SwiftLint:** the same as HEAD's copies on all 15 files. The only change was the superfluous `type_body_length` disable in `AO3PreferencesView`, which now lints 0 → 0.
- **Not run:** tests, any simulator. The simulator was read only on disk, for the installed build's time and strings.
