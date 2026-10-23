# Brief 3hc2 (Android): finish 3hc after A94

**Work in `/Users/cidy02/kudos-agent-codex2`, branch `android/agent-codex-3hc2`, from the lane's
`6c002b44`, with 3hc applied uncommitted as the lane had it.** Gemini's 3hc is recorded on
`android/agent-gemini-3hc`. Item 7 (card dates) is withdrawn under owner Q28, and its code and test are
already gone.

Rules:
- Do not commit, push, switch branches, sign in or contact archiveofourown.org.
- You **may** run only these test classes, in this worktree:
  `./gradlew :app:testDebugUnitTest --tests 'io.github.cidy02.kudos.app.Brief3hcContentTest' --tests 'io.github.cidy02.kudos.library.ActionParityFormsTest' --tests 'io.github.cidy02.kudos.account.Brief3caScreenTest'`,
  plus any class you add. Don't run the full suite or lint; Claude does.
- Do not edit `TASKS.md`.
- Write `docs/android-port/briefs/3hc2-result.md` first. Per item: `path:line` and what changed. Per test:
  what it does with its change reverted, which you may now run.

Reading:
- The review: `docs/android-port/briefs/A94-result.md` (Claude-CLI; copied here).
- iOS is the reference: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`.

**What failed in Claude's gate with 3hc applied** (all fine without it):
- `Brief3hcContentTest`: `collectionReorderRowsShareOneCardWithSeparators`,
  `addLibraryWorksPrefixesByAndUsesSecondaryInkForVerifiedAndUnverifiedAuthors`,
  `queueSeedRowsHaveHorizontalGapAndIndentedSeparator`,
  `collectionEditorGroupsNameDescriptionAndSwatchesInOneCardAndWrapsColourOnDetails`,
  `chapterPickerUsesOpenBookIconAndPaletteAccentOnAllRowLabels`. A94 explains four of them (the gap is
  measured after the row's padding; the separator's tag sits before its own padding; the fixture's
  identity needs `displayName` and kind `registered`; the chapter row's text is "Chapter 1 · 1. Arrival").
- `ActionParityFormsTest.queuePickerTogglesAllMembersAndCreatesWithoutClosing`: "Failed to perform text
  input … (SetText is defined) … the unmerged tree contains '1' node". 3hc's `QueueEditorSheet` change
  merged the name field into another node's semantics. Fix the code, not the test.
- `Brief3caScreenTest.row47NonemptyAccountPageFilteredToZeroHasClearWhichOnlyChangesLocalFilters`: times
  out with 3hc and passes without. Find out whether 3hc's byline change causes it.

**A94's P2s:**
1. **Add Works' bylines:** keep "by", but iOS tints a linked author (`AddLibraryWorksSheet.swift:145-156`
   uses the `displayText:` init, which leaves `tinted = true`; `UIComponents/AO3AuthorNavigation.swift:69`,
   `:196`). The iPhone's grey was demo data, since iOS's demo works carry no identities. Drop the `tinted`
   parameter (no other caller wants it), keep `includesBy = true`, and pass
   `compact = !isAccessibilityFontScale()` for iOS's caption size. Assert the tint on a linked author.
2. **The tests above:** they must pass on the finished code and fail with their change reverted.

**A94's P3s:**
3. **Collection reorder:** use the series reorder's pattern instead of one non-lazy item. That's
   `itemsIndexed` with `writingSuggestionPanel(first, last)` and separators
   (`writing/WritingSeriesScreen.kt:126-129`, `:170`), iOS's `subjectPanelSegmentRow`. Rows then compose
   lazily, a dragged row keeps its ground, and the spacing between header, label, card and footnote comes
   back.
4. **Collection details** is a Form with `appThemedRows` on iOS (`Features/Library/Collections.swift:186-220`):
   cream in Sepia, #222228 in Dark, #1C1C1E in OLED, glass in Light. The new colour card and the old
   Behaviour card are darker than the sheet in Sepia. Match, using the speech sheet's form-ground
   mechanism (`LocalSettingsFormGround`), which 3hd is applying to the reader's sheets in Sepia.
5. **New queue's seed separator** starts 5 dp before the label: inset 48 dp, not 43.
6. **The chapter picker's unselected total** is a paler tint of the accent on the iPhone (sampled), grey
   on Android. Match.
