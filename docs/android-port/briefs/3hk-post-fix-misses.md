# 3hk: gaps found while judging the post-fix re-shoot (A102)

Claude-Code, 2026-10-25, on `android/agent-codex-3he` after 3hj. Judging the post-fix Android shots
(`~/kudos-tools/pairs/tiles-post/`) beside the iPhone's turned up differences that both A102 judges had passed
over. They were there before 3he (the pre-fix shots in `shots-final-2026-10-25/` show them too). Each is checked
against the iOS code named.

| # | Screen | Android before | iOS | Fix |
|---|---|---|---|---|
| 1 | addtoqueue | Queue row icons in the accent | `ReadingQueues.swift:481-482`: the row's `Label` is `.primary`, icon included | `WorkDetailForms.kt`: `statusInk = primaryInk` |
| 2 | bulktag | A "+" before the field; "YOUR TAGS" | `WorkBulkTagSheet.swift:31-52`: a plain `List` row; `Section("Your tags")` | `QueueTags.kt`: no "+" and `SettingsGroupLabel` for the work sheet; the queue sheet keeps both, as iOS's `QueueTagSheet` |
| 3 | author | The hero sits on the wash | `AuthorProfileView.swift:231`: `AO3AuthorHero(...).cardRow()`, 16 pt inside | `AuthorProfileScreen.kt`: `Modifier.cardRow().padding(16.dp)` |
| 4 | addtocollection (Dark, OLED) | Checkbox and Done cream | The accent's readable ink | Root cause: Material `primary` was `PaperWarm` in the Dark and OLED schemes, so any bare Material control (69 `AlertDialog` sites in 47 files, 5 of them themed) drew cream. `Theme.kt`: `primary` is the accent's readable ink, as `SubjectPaletteTheme` already makes it. Subscribe (3he) and the date picker (3hf) were two earlier cases. |
| 5 | chmysignup | "Prompt" as the row's sentence-case label | `ChallengeSignUpView.swift:328`: `SubjectFieldLabel(text: "Prompt", style: .formGroup)` in the card | `AO3ChallengeSignUpScreen.kt`: the field label, then the field with `fieldOnly` (as Sign-up instructions already does) |
| 6 | chsettingsedit | Each Basics and Schedule row its own card | `ChallengeSettingsEditView.swift:170-346`: one panel for Basics, one for Schedule down to Time zone | `ChallengeEditPanel(first, last)` joins a run of items into one card, with separators |
| 7 | seriespicker, collectionsgifts (2.0×) | The selection mark stays 18 dp | An SF Symbol grows with Dynamic Type | `WritingAssociationPickers.kt`: sized `18.sp.toDp()`, as `SubjectFormRow`'s icons are |
| 8 | myseries | "SERIES 2" 16 dp inside the cards' edge | `AuthorProfileContentSections.swift:560`: a `List` section header, at the cards' edge | `SectionRuleHeader(gutter = 0.dp)` on the author's Series tab; the parameter mirrors `SubjectHeaderBlock`'s |
| 9 | colsfilter | The sheet opens at half height, Reset under the last note | Full height, Reset at the foot; the 2026-10-15 decision keeps the account lists' sheets full height | `AO3CollectionsFilterPanel.kt`: the content fills the height, a spacer puts Reset at the foot |
| 10 | later, history, subs | Section headers 16 dp inside the cards' edge | At the cards' edge (`AO3MarkedForLaterWorksBrowser.swift:333` and the other account lists) | `AccountWorksListScreen.kt`'s four `SectionRuleHeader`s take `gutter = 0.dp`, as #8 |
| 11 | bulktagstate | Glass rows darker than the ground (Light 230 on 242, Sepia 224 on 236) | iOS's plain list: elevated cards (white, Sepia 251,240,217) on the grouped ground | `BulkOptionsScreen`'s tag-state page: Settings' ground and `cardSurface` rows (`writingSuggestionPanel(fill:)`, `BulkRow(card:)`) |

## Tests
- `app/Parity3hkThemeTest`: Material `primary` in Dark and OLED is the accent's readable ink (fails with `PaperWarm`).
- `library/TagSheetParityTest.workTagsHaveLeadingThreeStateMarks…`: "Your tags", not "YOUR TAGS" (fails with
  `SubjectFieldLabel`).
- The rest are visual and are checked in the re-shoot: Dark for every screen (to find what #4 changed), all five
  columns for the screens above.

## Reversal
Revert the 3hk commit.
