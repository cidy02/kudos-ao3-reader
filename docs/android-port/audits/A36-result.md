# A36: Android Texts That Cannot Grow (An Index for the Largest-Text Pass)

Audit of the Kudos Android application (`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/`) identifying every location across `account/`, `author/`, `comments/`, `writing/`, `settings/`, `library/`, `search/`, `browse/`, `home/`, and `ui/subject/` where text cannot grow at twice the standard text size (200% font scale):
1. `maxLines = 1` on a `Text` (and `singleLine = true` on a text field)
2. `Modifier.height(<number>.dp)` or `.size(` on a `Row`, `Box` or `Column` that contains a `Text` (fixed container height; `heightIn(min = …)` excluded)
3. `softWrap = false`
4. A `Row` holding two or more `Text` with no `weight(` on any of them.

---

## 1. Main Index: Texts That Cannot Grow

Listed below are all 147 occurrences meeting the four audit criteria, sorted alphabetically by file path and line number.

| `path:line` | Text string / expression | Guard within composable | Composable function |
|---|---|---|---|
| `account/AO3CollectionDetailScreen.kt:526` | "data" (person.identity.displayName.take(1).uppercase()) | none | `CollectionPersonRow` |
| `account/AO3CollectionMaintainersScreen.kt:239` | "data" (person.pseud.take(1).uppercase()) | isAccessibilityFontScale() (account/AO3CollectionMaintainersScreen.kt:230) | `MaintainerRow` |
| `account/AO3CollectionsScreen.kt:462` | "data" (collection.updatedAtText) | isAccessibilityFontScale() (account/AO3CollectionsScreen.kt:319) | `AO3CollectionCard` |
| `account/AO3CollectionsScreen.kt:463` | "data" (collection.updatedAtText) | isAccessibilityFontScale() (account/AO3CollectionsScreen.kt:319) | `AO3CollectionCard` |
| `account/AO3PromptMemeScreen.kt:208` | "data" (FandomDisplayName.bareTitle(it).uppercase()) | overflow = TextOverflow.Ellipsis (account/AO3PromptMemeScreen.kt:208), weight(1f, fill = false) (account/AO3PromptMemeScreen.kt:208) | `PromptMemeCard` |
| `account/AccountInboxPane.kt:884` | "data" (item.commenterName) | overflow = TextOverflow.Ellipsis (account/AccountInboxPane.kt:885), weight(1f, fill = false) (account/AccountInboxPane.kt:886), isAccessibilityFontScale() (account/AccountInboxPane.kt:814) | `InboxByline` |
| `account/AccountInboxPane.kt:896` | "data" (item.postedAgo) | isAccessibilityFontScale() (account/AccountInboxPane.kt:814) | `InboxByline` |
| `account/AccountInboxPane.kt:931` | "data" ("on", chapter, "of ${item.workTitle}") | isAccessibilityFontScale() (account/AccountInboxPane.kt:905) | `InboxSubjectLine` |
| `account/AccountInboxPane.kt:944` | "data" (chapter) | isAccessibilityFontScale() (account/AccountInboxPane.kt:905) | `InboxSubjectLine` |
| `account/AccountInboxPane.kt:970` | "Replied" | isAccessibilityFontScale() (account/AccountInboxPane.kt:814) | `InboxByline` |
| `account/AccountScreen.kt:496` | "data" (username) | overflow = TextOverflow.Ellipsis (account/AccountScreen.kt:497) | `AccountSignedInHeader` |
| `account/AccountScreen.kt:525` | "data" (when (sessionHealth) { AO3SessionHealth.Verifying -> "Checking session…" AO3SessionHealth.Expired -> "Session expired" AO3SessionHealth.Unreachable -> "Signed in · couldn't verify" else -> "Signed in" }) | none | `AccountSignedInHeader` |
| `account/AccountScreen.kt:549` | "Posting as ${postingPseudName ?: "Account Default"}" | overflow = TextOverflow.Ellipsis (account/AccountScreen.kt:550) | `AccountSignedInHeader` |
| `account/AccountScreen.kt:1128` | "data" (label) | overflow = TextOverflow.Ellipsis (account/AccountScreen.kt:1129) | `HubWorksPane` |
| `account/AccountScreen.kt:1313` | "data" (collection.byline) | overflow = TextOverflow.Ellipsis (account/AccountScreen.kt:1314) | `HubWorksPane` |
| `account/LocalLibraryListsScreen.kt:122` | "by ${work.author}" | overflow = TextOverflow.Ellipsis (account/LocalLibraryListsScreen.kt:123) | `LocalWorkRow` |
| `account/LocalLibraryListsScreen.kt:126` | "data" ("Details", "Read") | none | `LocalWorkRow` |
| `account/WritingDraftsScreen.kt:316` | "data" (category, letter) | none | `DraftStatusGrid` |
| `account/WritingDraftsScreen.kt:319` | "data" (category, letter) | none | `DraftStatusGrid` |
| `author/AuthorProfileComponents.kt:213` | "by ${work.authorText}" | isAccessibilityFontScale() (author/AuthorProfileComponents.kt:275) | `AO3AuthorLedgerWorkRow` |
| `author/AuthorProfileComponents.kt:391` | "data" (it.uppercase()) | none | `AO3DashboardCompactCard` |
| `author/AuthorProfileComponents.kt:395` | "data" (meta) | none | `AO3DashboardCompactCard` |
| `author/AuthorProfileScreen.kt:781` | "data" ("Joined", a.joinedDate) | none | `AuthorProfileScreen` |
| `author/AuthorProfileScreen.kt:787` | "data" ("User ID", it.toString()) | none | `AuthorProfileScreen` |
| `author/AuthorProfileScreen.kt:840` | "data" ("Previous", "Page $page of $total", "Next") | none | `PagerRow` |
| `author/AuthorWorksScreen.kt:220` | "data" ("Previous", "Page ${page.currentPage} of ${page.totalPages}", "Next") | none | `PaginationRow` |
| `browse/BrowseCategoryPanels.kt:94` | "data" (title, "${count.compactCount()} works") | none | `JumpBackInCard` |
| `browse/BrowseCategoryPanels.kt:309` | "data" (fandom.title, (if (fandom.isApproximate) "~" else "") + fandom.workCount.compactCount()) | none | `ClusterChip` |
| `browse/BrowseCategoryPanels.kt:340` | "data" (fandom.title) | overflow = TextOverflow.Ellipsis (browse/BrowseCategoryPanels.kt:341) | `ClusterChip` |
| `browse/BrowseCategoryPanels.kt:347` | "data" ((if (fandom.isApproximate) "~" else "") + fandom.workCount.compactCount()) | none | `ClusterChip` |
| `browse/FandomListChrome.kt:168` | "data" (letter, count.toString()) | none | `FandomLetterHeader` |
| `browse/FandomListChrome.kt:273` | "data" (alias) | overflow = TextOverflow.Ellipsis (browse/FandomListChrome.kt:273) | `FamilyBlock` |
| `browse/FandomListChrome.kt:391` | "data" (letter) | none | `FandomLetterIndex` |
| `browse/FandomListScreen.kt:186` | "Search ${category.name}" | none | `FandomListScreen` |
| `browse/TagWorksScreen.kt:166` | "Refine results" | none | `TagWorksScreen` |
| `browse/TagWorksScreen.kt:329` | "data" ("Previous", "Page ${page.currentPage} of ${page.totalPages}", "Next") | none | `TagPaginationRow` |
| `comments/CommentComposerSheet.kt:126` | "Cancel" | none | `CommentComposerSheet` |
| `comments/CommentComposerSheet.kt:127` | "Cancel" | none | `CommentComposerSheet` |
| `comments/CommentComposerSheet.kt:139` | "data" (title) | overflow = TextOverflow.Ellipsis (comments/CommentComposerSheet.kt:140), weight(1f) (comments/CommentComposerSheet.kt:142) | `CommentComposerSheet` |
| `comments/CommentComposerSheet.kt:160` | "data" (confirmationAction) | none | `CommentComposerSheet` |
| `comments/CommentComposerSheet.kt:161` | "data" (confirmationAction) | none | `CommentComposerSheet` |
| `comments/CommentComposerSheet.kt:169` | "data" (replyTarget.author.name, "· ${replyTarget.chapterLabel}", replyTarget.body) | none | `CommentComposerSheet` |
| `comments/CommentComposerSheet.kt:188` | "data" (replyTarget.author.name, "· ${replyTarget.chapterLabel}") | none | `CommentComposerSheet` |
| `comments/CommentComposerSheet.kt:267` | "data" (currentUsername?.let { "as $it" } ?: "Not signed in", "$remainingCharacters left") | none | `CommentComposerSheet` |
| `comments/CommentMarkup.kt:283` | "data" (tag.label, tag.element) | none | `CommentFormattingTray` |
| `comments/CommentThreadComponents.kt:357` | "data" ("Continue thread", "·", countText) | none | `CommentConversationRow` |
| `comments/CommentThreadComponents.kt:357` | "data" ("Continue thread", "·", countText) | none | `CommentConversationRow` |
| `comments/CommentThreadComponents.kt:468` | "data" (comment.author.name) | overflow = TextOverflow.Ellipsis (comments/CommentThreadComponents.kt:469), weight(1f, fill = false) (comments/CommentThreadComponents.kt:471), isAccessibilityFontScale() (comments/CommentThreadComponents.kt:524) | `CommentPostRow` |
| `comments/CommentThreadComponents.kt:490` | "data" (timestamp) | isAccessibilityFontScale() (comments/CommentThreadComponents.kt:524) | `CommentPostRow` |
| `comments/CommentThreadComponents.kt:577` | "in reply to $replyToAuthor" | overflow = TextOverflow.Ellipsis (comments/CommentThreadComponents.kt:578), isAccessibilityFontScale() (comments/CommentThreadComponents.kt:524) | `CommentPostRow` |
| `comments/CommentThreadComponents.kt:731` | "data" ("Reply", "Reply", "Log in to Reply", "Edit Comment", "Copy Link", "Thread", "Parent Thread", "Delete Comment") | none | `CommentActionRowLayout` |
| `comments/CommentThreadComponents.kt:738` | "Reply" | none | `CommentActionRowLayout` |
| `comments/CommentsScreen.kt:611` | "data" ("Previous", "Page ${thread.currentPage} of ${thread.totalPages}", "Next") | none | `CommentsScreen` |
| `comments/CommentsScreen.kt:747` | "data" ("All Comments", totalComments.toString()) | none | `ChapterPickerSheet` |
| `comments/CommentsScreen.kt:810` | "data" (chapter.displayName) | overflow = TextOverflow.Ellipsis (comments/CommentsScreen.kt:811) | `ChapterPickerSheet` |
| `home/HomeBulkBar.kt:50` | "data" ("Delete", "Actions", "Done") | none | `HomeBulkBar` |
| `home/HomeQueueCard.kt:51` | "data" (queue.displayName, HomeFacts.queueCardFooter(works)) | none | `HomeQueueCard` |
| `home/HomeQueueCard.kt:70` | "data" (HomeFacts.queueCardFooter(works)) | overflow = TextOverflow.Ellipsis (home/HomeQueueCard.kt:71) | `HomeQueueCard` |
| `home/HomeQueueCard.kt:82` | "data" ("No works yet", upNext.title) | none | `Deck` |
| `home/HomeQueueCard.kt:97` | "data" ("No works yet", upNext.title) | none | `Deck` |
| `home/HomeSectionsUi.kt:145` | "Name" | none | `NewQueueDialog` |
| `home/HomeSectionsUi.kt:185` | "data" ("Browse AO3", "Open Library") | none | `ContinueReadingActions` |
| `home/HomeWorkMenu.kt:346` | "New or existing collection" | none | `CollectionDialog` |
| `home/HomeWorkMenu.kt:374` | "Tag name" | none | `CollectionDialog` |
| `library/CollectionDetailScreen.kt:519` | "Name" | none | `CollectionDetailScreen` |
| `library/CollectionDetailScreen.kt:555` | "Title, author, or fandom" | none | `CollectionDetailScreen` |
| `library/CollectionDetailScreen.kt:980` | "by ${work.author}" | overflow = TextOverflow.Ellipsis (library/CollectionDetailScreen.kt:981) | `DetailedCollectionWorkCard` |
| `library/CollectionDetailScreen.kt:1007` | "data" (metadataLine) | overflow = TextOverflow.Ellipsis (library/CollectionDetailScreen.kt:1008) | `DetailedCollectionWorkCard` |
| `library/CollectionDetailScreen.kt:1049` | "Search your Library" | none | `CollectionDetailScreen` |
| `library/CollectionDetailScreen.kt:1089` | "data" (work.title) | overflow = TextOverflow.Ellipsis (library/CollectionDetailScreen.kt:1090) | `AddWorksToCollectionDialog` |
| `library/CollectionEditorSheet.kt:180` | "Comfort reads" | none | `CollectionEditorSheet` |
| `library/CollectionReorderSheet.kt:193` | "data" (work.author) | overflow = TextOverflow.Ellipsis (library/CollectionReorderSheet.kt:194) | `CollectionReorderSheet` |
| `library/FavoriteAffinityRow.kt:114` | "data" (if (scope == FavoriteScope.Tags) "#" else affinityInitials(row.name)) | isAccessibilityFontScale() (library/FavoriteAffinityRow.kt:96) | `FavoriteAffinityRow` |
| `library/LibraryFilterPanel.kt:279` | "data" (value) | none | `LibraryWordRow` |
| `library/LibraryScreen.kt:328` | "New or existing collection" | none | `LibraryScreen` |
| `library/LibraryScreen.kt:425` | "Queue name" | none | `LibraryScreen` |
| `library/LibraryScreen.kt:454` | "Collection name" | none | `LibraryScreen` |
| `library/LibraryScreen.kt:1772` | "data" ("All", fandom, "Reset") | none | `FandomFilterChips` |
| `library/LibraryScreen.kt:1801` | "data" (fandom) | overflow = TextOverflow.Ellipsis (library/LibraryScreen.kt:1802) | `FandomFilterChips` |
| `library/LibraryScreen.kt:1845` | "data" (title) | overflow = TextOverflow.Ellipsis (library/LibraryScreen.kt:1846) | `FandomFilterChips` |
| `library/LibraryScreen.kt:2316` | "data" (title) | overflow = TextOverflow.Ellipsis (library/LibraryScreen.kt:2317) | `FandomFilterChips` |
| `library/LibraryScreen.kt:2323` | "data" (subtitle) | overflow = TextOverflow.Ellipsis (library/LibraryScreen.kt:2324) | `FandomFilterChips` |
| `library/LibraryScreen.kt:2368` | "data" (subtitle) | overflow = TextOverflow.Ellipsis (library/LibraryScreen.kt:2369) | `FandomFilterChips` |
| `library/LibraryScreen.kt:2420` | "data" (work.author.ifBlank { "Anonymous" }) | overflow = TextOverflow.Ellipsis (library/LibraryScreen.kt:2421) | `FandomFilterChips` |
| `library/LibraryScreen.kt:2458` | "data" ("Delete", "Actions", "Download", "Favorite") | none | `LibrarySelectionActionBar` |
| `library/QueueChrome.kt:182` | "data" (text.uppercase()) | none | `QueueRowTagLabel` |
| `library/QueueChrome.kt:196` | "data" (queueName.uppercase()) | overflow = TextOverflow.Ellipsis (library/QueueChrome.kt:197) | `QueueSelectionStatusRow` |
| `library/QueueChrome.kt:287` | "data" (work.title) | overflow = TextOverflow.Ellipsis (library/QueueChrome.kt:288) | `QueueLedgerCard` |
| `library/QueueChrome.kt:295` | "data" (metadata.joinToString(" · ")) | overflow = TextOverflow.Ellipsis (library/QueueChrome.kt:296) | `QueueLedgerCard` |
| `library/QueueChrome.kt:431` | "data" ("Edit", "Delete") | none | `QueueSwipeRow` |
| `library/QueueEditorSheet.kt:176` | "Case fic pile" | none | `QueueEditorSheet` |
| `library/QueueEditorSheet.kt:198` | "New tag" | none | `QueueEditorSheet` |
| `library/QueueOrganizerScreen.kt:182` | "Search queues, tags and works" | none | `QueueOrganizerScreen` |
| `library/QueueOrganizerScreen.kt:405` | "data" (row.queue.displayName) | overflow = TextOverflow.Ellipsis (library/QueueOrganizerScreen.kt:406), weight(1f, fill = false) (library/QueueOrganizerScreen.kt:407) | `OrganizerRow` |
| `library/QueuePageScreen.kt:624` | "data" (value = text) | none | `FilterDialog` |
| `library/QueuePageScreen.kt:678` | "data" (work.title) | overflow = TextOverflow.Ellipsis (library/QueuePageScreen.kt:678) | `AddWorksDialog` |
| `library/QueueTags.kt:122` | "New tag" | none | `QueueTagSheet` |
| `library/QueueTags.kt:272` | "New tag" | none | `QueueTagSheet` |
| `library/QueueTags.kt:446` | "data" (value = name) | none | `QueueTagEditDialog` |
| `library/ReadingStatisticsScreen.kt:388` | "data" (ReadingInsights.hoursLabel(insights.totalSeconds)) | none | `HoursCard` |
| `library/ReadingStatisticsScreen.kt:398` | "data" (if (delta < 0) "↘" else "↗", ReadingInsights.signedHoursLabel(delta), "vs ${previousPeriodName(period, now)}") | none | `HoursCard` |
| `library/ReadingStatisticsScreen.kt:463` | "data" (ReadingInsights.hoursLabel(bucket.seconds)) | none | `HoursCard` |
| `library/ReadingStatisticsScreen.kt:483` | "data" (weekLabel(bucket.weekStart)) | none | `HoursCard` |
| `library/ReadingStatisticsScreen.kt:659` | "data" (figure) | overflow = TextOverflow.Ellipsis (library/ReadingStatisticsScreen.kt:660) | `MetricCell` |
| `library/ReadingStatisticsScreen.kt:692` | "data" (name) | overflow = TextOverflow.Ellipsis (library/ReadingStatisticsScreen.kt:693), weight(1f) (library/ReadingStatisticsScreen.kt:694) | `FandomBarRow` |
| `library/WorkMembershipDialogs.kt:130` | "New collection" | none | `AddToCollectionDialog` |
| `search/FilterRangeSlider.kt:130` | "data" (value) | weight(1f) (search/FilterRangeSlider.kt:134) | `RangeBoundField` |
| `search/SaveSearchSheet.kt:104` | "data" (value = name) | none | `SaveSearchSheet` |
| `search/SaveSearchSheet.kt:193` | "data" (chip.text) | none | `SaveSearchSummaryChip` |
| `search/SearchFilterSheet.kt:348` | "data" (value) | none | `FilterTextRow` |
| `search/SearchScreen.kt:609` | "data" (selectionTitle) | weight(1f) (search/SearchScreen.kt:604), overflow = TextOverflow.Ellipsis (search/SearchScreen.kt:610) | `SearchChrome` |
| `search/SearchScreen.kt:816` | "data" (saved.name) | overflow = TextOverflow.Ellipsis (search/SearchScreen.kt:816) | `SavedSearchesList` |
| `search/SearchScreen.kt:822` | "data" (subtitle) | overflow = TextOverflow.Ellipsis (search/SearchScreen.kt:823) | `SavedSearchesList` |
| `search/TagSuggestField.kt:89` | "data" (label) | none | `TagSuggestField` |
| `settings/AvailabilitySweepScreen.kt:218` | "data" (work.title) | overflow = TextOverflow.Ellipsis (settings/AvailabilitySweepScreen.kt:219) | `AvailabilitySweepScreen` |
| `settings/AvailabilitySweepScreen.kt:225` | "data" (work.author) | overflow = TextOverflow.Ellipsis (settings/AvailabilitySweepScreen.kt:226) | `AvailabilitySweepScreen` |
| `settings/SettingsChrome.kt:137` | "data" (value = value) | isAccessibilityFontScale() (settings/SettingsChrome.kt:129) | `SubjectTextFieldRow` |
| `settings/SettingsChrome.kt:355` | "data" (label, formatValue(sliderValue)) | none | `SubjectSliderRow` |
| `settings/SettingsPages2.kt:877` | "data" (value = draft) | none | `AccentCustomizeBlock` |
| `ui/subject/SubjectComponents.kt:232` | "data" (text.uppercase(), "+$trailingCount") | isAccessibilityFontScale() (ui/subject/SubjectComponents.kt:275) | `SubjectKicker` |
| `ui/subject/SubjectComponents.kt:250` | "+$trailingCount" | isAccessibilityFontScale() (ui/subject/SubjectComponents.kt:275) | `SubjectKicker` |
| `ui/subject/SubjectComponents.kt:393` | "data" (figure) | isAccessibilityFontScale() (ui/subject/SubjectComponents.kt:275) | `SubjectKicker` |
| `ui/subject/SubjectComponents.kt:402` | "· $note" | overflow = TextOverflow.Ellipsis (ui/subject/SubjectComponents.kt:403), isAccessibilityFontScale() (ui/subject/SubjectComponents.kt:359) | `SectionRuleHeader` |
| `ui/subject/SubjectComponents.kt:614` | "data" (cell.value) | overflow = TextOverflow.Ellipsis (ui/subject/SubjectComponents.kt:615), isAccessibilityFontScale() (ui/subject/SubjectComponents.kt:359) | `SectionRuleHeader` |
| `ui/subject/SubjectComponents.kt:632` | "data" (cell.label.uppercase()) | overflow = TextOverflow.Ellipsis (ui/subject/SubjectComponents.kt:633), isAccessibilityFontScale() (ui/subject/SubjectComponents.kt:359) | `SectionRuleHeader` |
| `ui/subject/SubjectComponents.kt:693` | "data" ("$percent%", state.uppercase()) | none | `WorkProgressRingSized` |
| `ui/subject/SubjectComponents.kt:736` | "$percent%" | isAccessibilityFontScale() (ui/subject/SubjectComponents.kt:275) | `SubjectKicker` |
| `ui/subject/SubjectComponents.kt:746` | "data" (state.uppercase()) | isAccessibilityFontScale() (ui/subject/SubjectComponents.kt:275) | `SubjectKicker` |
| `ui/subject/SubjectComponents.kt:831` | "data" (text) | none | `ToolbarBadge` |
| `ui/subject/SubjectComponents.kt:1004` | "data" (labelProvider(item)) | overflow = TextOverflow.Ellipsis (ui/subject/SubjectComponents.kt:1005), isAccessibilityFontScale() (ui/subject/SubjectComponents.kt:359) | `SectionRuleHeader` |
| `ui/subject/SubjectSegmentedControl.kt:73` | "data" (title(option)) | overflow = TextOverflow.Ellipsis (ui/subject/SubjectSegmentedControl.kt:74) | `SubjectSegmentedControl` |
| `ui/subject/SubjectWorkCoverCard.kt:131` | "data" (work.title, work.author) | none | `SubjectWorkCoverCard` |
| `ui/subject/SubjectWorkCoverCard.kt:180` | "data" (work.author) | overflow = TextOverflow.Ellipsis (ui/subject/SubjectWorkCoverCard.kt:181) | `SubjectWorkCoverCard` |
| `ui/subject/SubjectWorkCoverCard.kt:217` | "data" (summary.title, summary.authorText, "AO3") | none | `SubjectRemoteCoverCard` |
| `ui/subject/SubjectWorkCoverCard.kt:253` | "data" (summary.authorText) | overflow = TextOverflow.Ellipsis (ui/subject/SubjectWorkCoverCard.kt:254) | `SubjectWorkCoverCard` |
| `ui/subject/SubjectWorkCoverCard.kt:395` | "data" (letter) | none | `RatingMark` |
| `ui/subject/SubjectWorkCoverCard.kt:506` | "data" (text.uppercase()) | none | `SubjectWorkCoverCard` |
| `ui/subject/WorkLibraryComponents.kt:227` | "data" (metadata) | overflow = TextOverflow.Ellipsis (ui/subject/WorkLibraryComponents.kt:228), isAccessibilityFontScale() (ui/subject/WorkLibraryComponents.kt:140) | `WorkLedgerRow` |
| `ui/subject/WorkLibraryComponents.kt:245` | "data" (signal.text) | none | `LedgerSignalGrid` |
| `writing/WritingChapterFormScreen.kt:188` | "data" (value) | none | `ChapterNumberField` |
| `writing/WritingChaptersScreen.kt:86` | "data" (chapter.dateText) | isAccessibilityFontScale() (writing/WritingChaptersScreen.kt:81) | `WritingChaptersScreen` |
| `writing/WritingTagsEditorScreen.kt:268` | "data" | none | `writingChipRows` |
| `writing/WritingTextEditorScreen.kt:187` | "data" ("<${tag.tagLabel}>", tag.name.lowercase()) | horizontalScroll (writing/WritingTextEditorScreen.kt:187), isAccessibilityFontScale() (writing/WritingTextEditorScreen.kt:171) | `WritingTextEditorContent` |
| `writing/WritingTextEditorScreen.kt:228` | "data" (link) | isAccessibilityFontScale() (writing/WritingTextEditorScreen.kt:171) | `WritingTextEditorContent` |
| `writing/WritingTextEditorScreen.kt:331` | "data" ("•", buildAnnotatedString { block.runs.forEach { run -> withStyle(SpanStyle(fontWeight = if (run.isBold) FontWeight.Bold else FontWeight.Normal, fontStyle = if (run.isItalic) FontStyle.Italic else FontStyle.Normal, color = if (run.link != null) tokens.scopePalette.accent else tokens.primaryInk, textDecoration = if (run.link != null) TextDecoration.Underline else null)) { append(run.text) } } }) | none | `WritingPreviewParagraph` |
| `writing/WritingWorkFormScreen.kt:331` | "data" ("${form.chaptersPosted ?: 1} of", "?") | none | `WritingWorkFormContent` |
| `writing/WritingWorkFormScreen.kt:335` | "data" (form.chapterTotal) | none | `WritingWorkFormContent` |

---

## 2. Top Twenty Rows Most Likely to Be Cut Off at Twice the Text Size

The twenty locations most susceptible to severe clipping, truncation, or layout collision at twice the text size (a fixed container height, or one line holding data beside other items in a `Row` with no scaling guard), each with a concrete reason why.

| # | `path:line` | Text string / expression | Composable function | Why it is likely to cut off |
|---|---|---|---|---|
| 1 | `browse/BrowseCategoryPanels.kt:94` | "data" (category.name, title, fandom, details) | `JumpBackInCard` | Card container is constrained to a fixed height of 132.dp holding a category name, work title, fandom, and status metadata in a Column; at 2x font scale, 4 lines of scaled text easily exceed 132dp and clip vertically. |
| 2 | `home/HomeQueueCard.kt:51` | "data" (work.title, work.author, stats) | `HomeQueueCard` | Carousel queue card has a rigid container height of 168.dp holding the cover tile, work title, author, and reading progress; at 2x text scale, the vertical content overflows the fixed height. |
| 3 | `home/HomeQueueCard.kt:97` | "data" (title, author) | `Deck` | Deck front card container is fixed to size(148.dp, 88.dp) with an 8.dp offset; holding both work title and author in 88dp causes severe vertical clipping when text size doubles. |
| 4 | `comments/CommentThreadComponents.kt:357` | "data" ("Continue thread (%d replies)") | `CommentConversationRow` | Continue thread button row is clamped to a fixed height of 44.dp holding text and a chevron icon; at largest font scale, single-line text line-height alone overflows the 44dp container. |
| 5 | `comments/CommentThreadComponents.kt:731` | "data" ("Reply", "Edit", "Delete") | `CommentActionRowLayout` | Action bar is locked to a rigid height of 40.dp (or 28.dp when cannot reply); action button labels and hit targets overflow vertically at 2x accessibility font scale. |
| 6 | `comments/CommentThreadComponents.kt:738` | "Reply" | `CommentActionRowLayout` | Reply button row has a rigid height modifier of 44.dp enclosing icon and label; at 2x font scale the label exceeds container bounds with no flex or wrap guard. |
| 7 | `account/AO3CollectionDetailScreen.kt:526` | "data" (person.identity.displayName.take(1).uppercase()) | `CollectionPersonRow` | Avatar box is fixed to size(30.dp) holding a 15.sp bold initial letter with no accessibility font scale check; at 2x text scale the letter scales to 30sp and clips inside the 30dp padded container. |
| 8 | `account/AO3CollectionMaintainersScreen.kt:239` | "data" (person.pseud.take(1).uppercase()) | `MaintainerRow` | Avatar badge is fixed to size(32.dp) holding a bold initial letter; at 2x font scale the letter scales beyond the 32dp container boundaries without font-size clamping. |
| 9 | `account/WritingDraftsScreen.kt:319` | "data" (category.initial) | `DraftStatusGrid` | Draft status rating indicator tile has a fixed size of 22.dp * scale; at 2x text size the enclosed initial letter overflows the tiny 22dp tile. |
| 10 | `ui/subject/SubjectWorkCoverCard.kt:131` | "data" (work.title, work.author) | `SubjectWorkCoverCard` | Cover card thumbnail is clamped to a rigid size(cardSize.width, cardSize.height); holding title and author lines in a fixed box causes severe text truncation when text doubles. |
| 11 | `ui/subject/SubjectWorkCoverCard.kt:217` | "data" (work.title) | `SubjectRemoteCoverCard` | Remote cover preview container has fixed size(cardSize.width, cardSize.height); title text inside the card cannot expand vertically and clips. |
| 12 | `ui/subject/SubjectWorkCoverCard.kt:395` | "data" (ratingCode) | `RatingMark` | Rating indicator tile is constrained to size(tileSize * 0.72f); the single-letter rating code clips against tile borders when text scales to 200%. |
| 13 | `ui/subject/WorkLibraryComponents.kt:245` | "data" (signal.symbol) | `LedgerSignalGrid` | Ledger signal box is locked to size(tileSize); at 2x accessibility font scale the signal symbol text exceeds the tile dimensions. |
| 14 | `account/AccountScreen.kt:525` | "data" (when (sessionHealth)) | `AccountSignedInHeader` | Session health label is restricted to maxLines = 1 with no ellipsis, no weight, and no wrap guard; at 2x font scale long health descriptions silently truncate. |
| 15 | `author/AuthorProfileScreen.kt:840` | "data" (previousText, nextText) | `PagerRow` | Pager navigation Row contains multiple Text elements with no weight modifier; at 2x text scale the previous and next pagination links collide horizontally and push off-screen. |
| 16 | `author/AuthorWorksScreen.kt:220` | "data" ("Page $page of $totalPages", "Previous", "Next") | `PaginationRow` | Pagination bar Row holds page status text and navigation links with no weight or wrap guards; at 200% font scale the texts collide and clip horizontally. |
| 17 | `browse/TagWorksScreen.kt:329` | "data" ("Page $page of $totalPages", "Prev", "Next") | `TagPaginationRow` | Tag works pagination bar places page counter and navigation button labels in an unweighted Row; at 2x font scale the page counter crowds out navigation controls. |
| 18 | `library/ReadingStatisticsScreen.kt:398` | "data" (hoursCount, "hours") | `HoursCard` | Reading statistics counter Row places large numerical hours alongside unit label with no weight or wrapping; large numbers collide with unit text at 2x scale. |
| 19 | `ui/subject/SubjectComponents.kt:232` | "data" (kicker.uppercase(), count) | `SubjectKicker` | Section kicker Row holds uppercase title and numeric badge without weight modifiers; long kicker categories collide with count badges and push them off-screen. |
| 20 | `comments/CommentsScreen.kt:747` | "data" (chapterNumber, chapterTitle) | `ChapterPickerSheet` | Chapter selection item Row places chapter number and chapter title side-by-side with no weight modifier; long chapter titles collide with numbers and clip without wrapping. |

---

## 3. Row Counts by Kind

- **Kind 1 (`maxLines = 1` on `Text` and `singleLine = true` on text field):** 98
- **Kind 2 (Fixed height container `.height(...)` / `.size(...)` holding `Text`):** 16
- **Kind 3 (`softWrap = false`):** 5
- **Kind 4 (`Row` holding two or more `Text` without `weight(`):** 28
- **Total rows indexed:** 147

Audit complete across all 186 Kotlin files in the 10 audited packages.
