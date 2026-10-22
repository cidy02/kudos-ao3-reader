# Brief 3gi result (A71)

Implementation ready for Claude's build/test/emulator pass; not visually verified. No Gradle, builds, sign-in, AO3 requests, commits, pushes, or branch changes.

Created before implementation and updated as each item finished. Android paths are relative to this checkout. All iOS paths below are under `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only). No edits to `TASKS.md` or the two pre-existing untracked brief/audit files.

## 1. Comments — fixed

- **fixed** Reply is plain accent text and arrow in threads, retaining its 44dp action area; Inbox still calls the capsule default. `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentThreadComponents.kt:781,1033`. iOS followed: `Features/Comments/CommentThreadRow.swift:1455–1476`. Visual verification left to Claude.
- **fixed** Nested replies omit chapter badges (`replyToAuthor == null`, matching iOS's parent-author guard). `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentThreadComponents.kt:523`. iOS: `Features/Comments/CommentThreadRow.swift:827`. Test added: `CommentPostRowTest.onlyTheTopLevelCommentShowsItsChapterBadge`; its count assertion requires one badge, while removing the guard produces two.
- **fixed** Comment parsing keeps nonempty paragraphs separated by two newlines, instead of flattening the whole body. `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentParser.kt:177`. iOS: `Services/AO3Client+Comments.swift:341–348`. Test added: `AO3CommentThreadParserTest.keepsTheDemoCommentsParagraphBreaks`, reading the actual `ao3_comments_page.html` demo fixture. Restoring `normalizedText()` on the blockquote flattens the two paragraphs, contradicting its exact expected string.
- **fixed** Work creators under the title use the subject accent. `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsScreen.kt:412`. iOS: `Features/Comments/CommentsView.swift:437–453` work-header byline. Visual verification left to Claude.

## 2. Your Series — fixed

- **fixed** Account name under the title; one totals line above the cards; `SERIES` plus loaded count; series cards and series Load More/error use `cardRow()` instead of glass. Own-series ⋮ actions remain. `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:702,981,1017,1129`; `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileComponents.kt:259`. iOS followed: `Features/Authors/AuthorProfileContentSections.swift:531–552` and `Features/Authors/AuthorProfileContentSections.swift:77–100` (`AO3AuthorPaginationRows`, `.cardRow()`). Shared series-detail header also follows `Features/Authors/AO3SeriesDetailView.swift:56–57`. Owner Q24's totals retained.
- Test added: `OwnWorksScreenTest.ownSeriesShowsItsTotalsExactlyOnceAlongsideTheAccountAndSectionHeading`, opening the real own-account Series destination with bundled fixture responses. Its count assertion requires one totals node; restoring the subtitle tally produces two. Tests not run (user instruction).

## 3. What's New — fixed

- **fixed** Short notes now occupy the sheet's full available height, with partial expansion disabled. Title is centered independently of Done; notes scroll below the fixed header. Android release content and chrome retained. `android/app/src/main/java/io/github/cidy02/kudos/support/WhatsNew.kt:56,69`. iOS followed: `Features/Support/WhatsNew.swift:63–91` (`NavigationStack`, inline centered title, scrolling list, confirmation action).
- Test added: `WhatsNewLayoutTest.aShortReleaseStillFillsTheSheetWithACentredTitleAndWorkingDone` checks actual content/host height, title center and Done callback. Not run; sheet/emulator verification remains Claude's.

## 4. My copy — fixed density; progress mismatch not real

- **fixed** Removed stacked outer/group gaps, changed fact/toggle padding to iOS's 3dp and add-action padding to 6dp, set compact text leading rather than inheriting Material body leading, and restored the group-heading hairlines. `android/app/src/main/java/io/github/cidy02/kudos/works/detail/WorkDetailMyCopySheet.kt:195,347,807,834,870,902`. iOS followed: `Features/WorkDetail/WorkDetailSections.swift:238–360,610–617`, `Features/WorkDetail/WorkProvenanceSections.swift:205–214`. **not real:** iOS explicitly hides separators between individual rows (`myCopyRow`); the visible separators belong beside the group headings, so no extra row dividers were invented. Density/appearance remain for Claude's emulator pass.
- **not real** Android already uses iOS's exact known-zero/unknown rule: `publicationProgress` is legacy whole-book progress, else Readium total progression; missing progress yields `—`, known zero yields `0%`. The identical source rules do not establish a progress-formatting bug; differing saved reading state is a possible explanation for this tile. Model and fixture state were left intact. Formatting extracted at `android/app/src/main/java/io/github/cidy02/kudos/works/detail/WorkDetailMyCopySheet.kt:986` for regression coverage. iOS: `Features/WorkDetail/WorkDetailSections.swift:220`, `Models/Models.swift:550–552`.
- Test added: `MyCopySummaryTest.progressDistinguishesKnownZeroFromUnknownAsIosDoes` covers unknown, legacy zero, Readium zero and a nonzero percentage. This pins existing behavior, not a newly fixed progress bug. Not run.

## 5. Collection form — fixed

- **fixed** The collection form passes its scope palette to `SettingsPage`, which paints the existing subject wash and registers it with Android's shell. Other Settings pages keep their existing grounds. `android/app/src/main/java/io/github/cidy02/kudos/account/AO3CollectionFormScreen.kt:85`; `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsChrome.kt:90,103`. iOS followed: `Features/Account/AO3CollectionFormView.swift:92` (`subjectScreenWash`). Theme appearance remains for Claude's emulator pass.
- **fixed** Tagline uses all the width after its label, rather than the generic field's 55% width cap. It remains a trailing, single-line editable field with horizontal scrolling for genuinely long values, as iOS does; accessibility sizes retain the existing stacked form layout. `android/app/src/main/java/io/github/cidy02/kudos/account/AO3CollectionFormScreen.kt:121`; `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsChrome.kt:203`. iOS followed: `Features/Account/AO3CollectionFormView.swift:149,273–291` (single-line Tagline and expanding trailing field). Different demo text is retained.
- Test added: `CollectionTaglineLayoutTest.theDemoTaglineUsesTheSpaceAfterItsLabelWithoutClippingItsText` compares the real field's viewport with its text layout at default size. Not run.

## 6. Regression handoff — added; execution left

Six tests added, with the three required regression assertions connected to the changed parser or actual rendered destination/row:

- Paragraphs: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentParserTest.kt:34`.
- Nested badge: `android/app/src/test/java/io/github/cidy02/kudos/comments/CommentPostRowTest.kt:25`.
- Totals once: `android/app/src/test/java/io/github/cidy02/kudos/author/OwnWorksScreenTest.kt:236`.
- What's New layout/Done: `android/app/src/test/java/io/github/cidy02/kudos/support/WhatsNewLayoutTest.kt:27`.
- Known-zero/unknown formatting: `android/app/src/test/java/io/github/cidy02/kudos/works/detail/MyCopySummaryTest.kt:20`.
- Tagline viewport: `android/app/src/test/java/io/github/cidy02/kudos/settings/CollectionTaglineLayoutTest.kt:29`.

**Verified here:** `git diff --check`; source/diff inspection of callers and defaults (Inbox capsule, other Settings grounds, other field rows); static scan of changed Kotlin confirms no Android-rejected regex flags were introduced. No regex added.

**left to Claude:** compile, execute tests (including the three required tests with their production changes individually undone), and inspect `comments`, `myseries`, `whatsnew`, `mycopy`, `colsettings` in all five tile configurations. No test execution or mutation-test pass is claimed here. Check theme grounds, My copy's Activity/Origin/My tags density and heading rules, Reply styling, the collection wash, Tagline at large text, and full-height sheet behavior. The added Tagline and What's New tests pin component geometry; actual modal/form integration still needs the emulator pass. No code item intentionally left unfinished.
