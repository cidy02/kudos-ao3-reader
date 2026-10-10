# A35: iOS Texts That Cannot Grow (An Index for the Largest-Text Pass)

Audit of `kudos-ao3-reader/Features/` and `kudos-ao3-reader/UIComponents/` identifying every view where text cannot grow at the largest Dynamic Type accessibility sizes:
1. `.lineLimit(1)` (and `lineLimit(1...1)`)
2. `.frame(height: <number>)` and `.frame(minHeight:maxHeight:)` with a fixed maximum, on a view that contains a `Text`
3. `.fixedSize()` on a `Text` inside an `HStack`
4. `.minimumScaleFactor(` (already guarded: listed separately in Table 2)

---

## 1. Main Index: Texts That Cannot Grow

Listed below are all occurrences of `.lineLimit(1)`, fixed-height `.frame(...)` on views containing `Text`, and `.fixedSize()` on `Text` inside an `HStack`. Sorted alphabetically by file path.

| `path:line` | Text string / expression | Guard within view | Screen (enclosing struct) |
|---|---|---|---|
| `kudos-ao3-reader/Features/Account/AO3CollectionDetailView.swift:266` | "ANON" | none | `AO3CollectionDetailView` |
| `kudos-ao3-reader/Features/Account/AO3CollectionDetailView.swift:634` | "data" (person.identity.displayName.prefix(1)) | none | `AO3CollectionMaintainerAvatar` |
| `kudos-ao3-reader/Features/Account/AO3CollectionItemsView.swift:613` | "data" (item.role) | @ScaledMetric (AO3CollectionItemsView.swift:570) | `AO3CollectionItemCard` |
| `kudos-ao3-reader/Features/Account/AO3CollectionItemsView.swift:614` | "data" (item.role) | `@ScaledMetric` (AO3CollectionItemsView.swift:570) | `AO3CollectionItemCard` |
| `kudos-ao3-reader/Features/Account/AO3CollectionItemsView.swift:713` | "data" (item.title) | none | `AO3CollectionItemCard` |
| `kudos-ao3-reader/Features/Account/AO3CollectionItemsView.swift:791` | "Keep" / "Remove from collection" | none | `AO3CollectionItemCard` |
| `kudos-ao3-reader/Features/Account/AccountComponents.swift:93` | "data" (title) | minimumScaleFactor (AccountComponents.swift:94) | `AccountStatsTile` |
| `kudos-ao3-reader/Features/Account/AccountComponents.swift:137` | "data" (person.displayName) | none | `AO3PersonPickerItemRow` |
| `kudos-ao3-reader/Features/Account/AccountComponents.swift:186` | "data" (label) | minimumScaleFactor (AccountComponents.swift:187) | `AO3CollectionRoleOptionRow` |
| `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:355` | "data" (item.commenterName) | none | `AccountInboxItemRow` |
| `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:368` | "data" (item.subjectTitle) | .truncationMode (AccountInboxViews.swift:369) | `AccountInboxItemRow` |
| `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:388` | "data" (chapter) | none | `AccountInboxItemRow` |
| `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:389` | "data" (chapter) | none | `AccountInboxItemRow` |
| `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:489` | "Replied" | none | `InboxRepliedBadge` |
| `kudos-ao3-reader/Features/Account/AvailabilitySweepView.swift:90` | "data" (run.displayTimestamp) | none | `AvailabilitySweepView` |
| `kudos-ao3-reader/Features/Account/AvailabilitySweepView.swift:94` | "data" (summary) | none | `AvailabilitySweepView` |
| `kudos-ao3-reader/Features/Authors/AuthorDashboardSections.swift:280` | "data" (row.title) | none | `AuthorDashboardSections` |
| `kudos-ao3-reader/Features/Authors/AuthorDashboardSections.swift:291` | "data" (row.subtitle) | none | `AuthorDashboardSections` |
| `kudos-ao3-reader/Features/Authors/AuthorProfileComponents.swift:209` | "data" (series.title) | @ScaledMetric (AuthorProfileComponents.swift:178) | `AO3AuthorSeriesRow` |
| `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:412` | "data" (work.title) | none | `AuthorProfileView` |
| `kudos-ao3-reader/Features/Challenges/ChallengeAssignmentsView.swift:317` | "data" ("Delivered" / "Late" / "Defaulted") | none | `ChallengeAssignmentsView` |
| `kudos-ao3-reader/Features/Challenges/ChallengeAssignmentsView.swift:356` | "Claim" | @ScaledMetric (ChallengeAssignmentsView.swift:233) | `ChallengeAssignmentsView` |
| `kudos-ao3-reader/Features/Challenges/ChallengeAssignmentsView.swift:357` | "Claim" | `@ScaledMetric` (ChallengeAssignmentsView.swift:233) | `ChallengeAssignmentsView` |
| `kudos-ao3-reader/Features/Challenges/ChallengeAssignmentsView.swift:622` | "OPEN" / "CLAIMED" | @ScaledMetric (ChallengeAssignmentsView.swift:233) | `ChallengeAssignmentsView` |
| `kudos-ao3-reader/Features/Challenges/ChallengeAssignmentsView.swift:623` | "OPEN" / "CLAIMED" | `@ScaledMetric` (ChallengeAssignmentsView.swift:233) | `ChallengeAssignmentsView` |
| `kudos-ao3-reader/Features/Challenges/ChallengeSignUpsView.swift:264` | "MATCHED" / "UNMATCHED" | none | `ChallengeSignUpsView` |
| `kudos-ao3-reader/Features/Challenges/CollectionMaintainersView.swift:244` | "data" (roleText.uppercased()) | @ScaledMetric (CollectionMaintainersView.swift:207) | `CollectionMaintainersView` |
| `kudos-ao3-reader/Features/Challenges/CollectionMaintainersView.swift:245` | "data" (roleText.uppercased()) | `@ScaledMetric` (CollectionMaintainersView.swift:207) | `CollectionMaintainersView` |
| `kudos-ao3-reader/Features/Challenges/CollectionMaintainersView.swift:284` | "data" (initial) | none | `CollectionMaintainersView` |
| `kudos-ao3-reader/Features/Challenges/CollectionModerationView.swift:303` | "data" (item.itemType.uppercased()) | none | `CollectionModerationView` |
| `kudos-ao3-reader/Features/Challenges/CollectionModerationView.swift:418` | "data" (title) | @ScaledMetric (CollectionModerationView.swift:273) | `CollectionModerationView` |
| `kudos-ao3-reader/Features/Challenges/CollectionModerationView.swift:419` | "data" (title) | `@ScaledMetric` (CollectionModerationView.swift:273) | `CollectionModerationView` |
| `kudos-ao3-reader/Features/Challenges/PromptMemeView.swift:299` | "data" (item.workTitle) | none | `PromptMemeView` |
| `kudos-ao3-reader/Features/Challenges/PromptMemeView.swift:397` | "data" (title) | @ScaledMetric (PromptMemeView.swift:275) | `PromptMemeView` |
| `kudos-ao3-reader/Features/Challenges/PromptMemeView.swift:398` | "data" (title) | `@ScaledMetric` (PromptMemeView.swift:275) | `PromptMemeView` |
| `kudos-ao3-reader/Features/Challenges/PromptMemeView.swift:402` | "data" (title) | none | `PromptMemeView` |
| `kudos-ao3-reader/Features/Challenges/TagSetView.swift:349` | "Save tags" | none | `TagSetView` |
| `kudos-ao3-reader/Features/Challenges/TagSetView.swift:520` | "Reject" | @ScaledMetric (TagSetView.swift:299) | `TagSetView` |
| `kudos-ao3-reader/Features/Challenges/TagSetView.swift:521` | "Reject" | `@ScaledMetric` (TagSetView.swift:299) | `TagSetView` |
| `kudos-ao3-reader/Features/Challenges/TagSetView.swift:538` | "data" (text) | @ScaledMetric (TagSetView.swift:299) | `TagSetView` |
| `kudos-ao3-reader/Features/Comments/CommentMarkup.swift:293` | "B", "I", "U", "S" | none | `CommentFormatBar` |
| `kudos-ao3-reader/Features/Comments/CommentMarkup.swift:315` | "B", "I", "U", "S" | none | `CommentFormatBarButtonFace` |
| `kudos-ao3-reader/Features/Comments/CommentMarkup.swift:510` | "data" (tag.name) | minimumScaleFactor (CommentMarkup.swift:511) | `CommentFormatTileFace` |
| `kudos-ao3-reader/Features/Comments/CommentMarkup.swift:515` | "data" (tag.syntaxGuide) | minimumScaleFactor (CommentMarkup.swift:516) | `CommentFormatTileFace` |
| `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:312` | "data" (role.rawValue) | none | `CommentParticipantBadge` |
| `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:349` | "Reply" | none | `CommentReplyButton` |
| `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1217` | "data" (kicker) | .truncationMode (CommentThreadRow.swift:1218) | `CommentPostRow` |
| `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1223` | "data" (attribution) | .truncationMode (CommentThreadRow.swift:1224) | `CommentPostRow` |
| `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1275` | "data" (collapse.label) | none | `CommentPostRow` |
| `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1276` | "data" (collapse.label) | none | `CommentPostRow` |
| `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1365` | "data" (timestamp) | none | `CommentPostRow` |
| `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1366` | "data" (timestamp) | none | `CommentPostRow` |
| `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1382` | "data" (chapter) | none | `CommentPostRow` |
| `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1383` | "data" (chapter) | none | `CommentPostRow` |
| `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1425` | "Reply" | none | `CommentPostRow` |
| `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1426` | "Reply" | none | `CommentPostRow` |
| `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1786` | "data" (text) | minimumScaleFactor (CommentThreadRow.swift:1785) | `CommentPostActionPill` |
| `kudos-ao3-reader/Features/Comments/CommentsView.swift:837` | "data" (title) | minimumScaleFactor (CommentsView.swift:838) | `CommentsView` |
| `kudos-ao3-reader/Features/Comments/CommentsView.swift:935` | "data" (author) | none | `CommentsView` |
| `kudos-ao3-reader/Features/Comments/CommentsView.swift:1390` | "data" (title) | none | `CommentsView` |
| `kudos-ao3-reader/Features/Home/HomeCards.swift:59` | "data" (work.title) | none | `HomeWorkCard` |
| `kudos-ao3-reader/Features/Home/HomeCards.swift:147` | "data" (work.title) | none | `HomeResumeCard` |
| `kudos-ao3-reader/Features/Home/HomeCards.swift:211` | "data" (work.title) | none | `HomeContinueReadingCard` |
| `kudos-ao3-reader/Features/Home/HomeCards.swift:433` | "data" (label) | minimumScaleFactor (HomeCards.swift:437) | `HomeStatsTile` |
| `kudos-ao3-reader/Features/Library/CollectionLedgerRow.swift:66` | "data" (work.title, work.author) | none | `CollectionLedgerRow` |
| `kudos-ao3-reader/Features/Library/CollectionLedgerRow.swift:83` | "data" (collection.name) | none | `CollectionLedgerRow` |
| `kudos-ao3-reader/Features/Library/CollectionLedgerRow.swift:88` | "data" ("\(workCount) works") | none | `CollectionLedgerRow` |
| `kudos-ao3-reader/Features/Library/CollectionLedgerRow.swift:142` | "data" (work.author) | none | `MiniatureWorkCover` |
| `kudos-ao3-reader/Features/Library/CollectionLedgerRow.swift:147` | "data" (work.title, work.author) | none | `MiniatureWorkCover` |
| `kudos-ao3-reader/Features/Library/Collections.swift:47` | "data" (work.title, work.author) | none | `CollectionCard` |
| `kudos-ao3-reader/Features/Library/Collections.swift:56` | "data" ("\(workCount) works") | none | `CollectionCard` |
| `kudos-ao3-reader/Features/Library/FavoriteAffinityRow.swift:265` | "data" (usesHashTile ? "#" : Self.initials(row.name)) | none | `FavoriteAffinityRow` |
| `kudos-ao3-reader/Features/Library/LibraryFilterEmptyState.swift:75` | "data" (workCountText(drop.remainingCount)) | `@ScaledMetric` (LibraryFilterEmptyState.swift:34) | `LibraryFilterCollisionCard` |
| `kudos-ao3-reader/Features/Library/ReadingInsightsView.swift:169` | "data" (stat.value) | minimumScaleFactor (ReadingInsightsView.swift:170) | `ReadingInsightsView` |
| `kudos-ao3-reader/Features/Library/ReadingInsightsView.swift:235` | "data" (stat.value) | minimumScaleFactor (ReadingInsightsView.swift:236) | `ReadingInsightsView` |
| `kudos-ao3-reader/Features/Library/ReadingInsightsView.swift:256` | "data" (stat.value) | minimumScaleFactor (ReadingInsightsView.swift:257) | `ReadingInsightsView` |
| `kudos-ao3-reader/Features/Library/ReadingInsightsView.swift:296` | "data" (fandom.name) | .truncationMode (ReadingInsightsView.swift:297) | `ReadingInsightsView` |
| `kudos-ao3-reader/Features/Library/ReadingInsightsView.swift:370` | "data" (stat.value) | minimumScaleFactor (ReadingInsightsView.swift:371) | `ReadingInsightsView` |
| `kudos-ao3-reader/Features/Library/ReadingQueueOrganizer.swift:712` | "data" (queue.displayName) | none | `ReadingQueueOrganizer` |
| `kudos-ao3-reader/Features/Library/ReadingQueuePageParts.swift:232` | "data" (queueName.uppercased()) | @ScaledMetric (ReadingQueuePageParts.swift:221) | `ReadingQueueSectionKicker` |
| `kudos-ao3-reader/Features/Library/ReadingQueues.swift:56` | "data" ("\(workCount) works") | none | `ReadingQueueCard` |
| `kudos-ao3-reader/Features/Library/ReadingQueues.swift:82` | "data" (work.title) | none | `ReadingQueueCard` |
| `kudos-ao3-reader/Features/Library/ReadingQueues.swift:85` | "data" (work.title) | none | `ReadingQueueCard` |
| `kudos-ao3-reader/Features/Reader/CustomizeThemeView.swift:183` | "Aa" | none | `ThemePreviewPaletteOption` |
| `kudos-ao3-reader/Features/Reader/ReaderView.swift:334` | "data" (positionLabel) | none | `ReaderView` |
| `kudos-ao3-reader/Features/ReaderReadium/ReaderChromeTopBar.swift:62` | "data" (title) | .truncationMode (ReaderChromeTopBar.swift:63) | `ReaderChromeTopBar` |
| `kudos-ao3-reader/Features/ReaderReadium/ReaderChromeTopBar.swift:69` | "data" (title, author) | `.truncationMode(.tail)` (ReaderChromeTopBar.swift:63) | `ReaderChromeTopBar` |
| `kudos-ao3-reader/Features/ReaderReadium/ReaderChromeTopBar.swift:94` | "data" (author) | .truncationMode (ReaderChromeTopBar.swift:95) | `ReaderChromeTopBar` |
| `kudos-ao3-reader/Features/ReaderReadium/ReaderFanMenu.swift:141` | "data" (pill.title) | none | `ReaderFanMenu` |
| `kudos-ao3-reader/Features/ReaderReadium/ReaderPositionCard.swift:126` | "data" (workLine) | minimumScaleFactor (ReaderPositionCard.swift:131) | `ReaderPositionCard` |
| `kudos-ao3-reader/Features/ReaderReadium/ReaderSearchView.swift:403` | "data" (snippet) | none | `ReaderSearchView` |
| `kudos-ao3-reader/Features/Search/AO3WorkRow.swift:385` | "data" (updated) | none | `AO3WorkRow` |
| `kudos-ao3-reader/Features/Search/AO3WorkRow.swift:419` | "data" (bookmark.date) | `@ScaledMetric` (AO3WorkRow.swift:293) | `AO3WorkRow` |
| `kudos-ao3-reader/Features/Search/FandomFamilyRows.swift:153` | "data" (count.compactCount) | none | `FandomFamilyBlock` |
| `kudos-ao3-reader/Features/Search/FandomListView.swift:310` | "data" (letter) | none | `FandomIndexScrubber` |
| `kudos-ao3-reader/Features/Search/FandomListView.swift:926` | "data" (count.formatted()) | none | `FandomListRow` |
| `kudos-ao3-reader/Features/Search/FandomListView.swift:927` | "data" (count.formatted()) | none | `FandomListRow` |
| `kudos-ao3-reader/Features/Search/FandomListView.swift:942` | "data" (count.compactCount) | none | `FandomListRow` |
| `kudos-ao3-reader/Features/Search/FilterRangeSlider.swift:78` | "From" / "To" | none | `FilterRangeSlider` |
| `kudos-ao3-reader/Features/Search/MediaBrowserView.swift:516` | "data" (text) | none | `JumpBackInEntry` |
| `kudos-ao3-reader/Features/Search/SaveSearchSheet.swift:156` | "data" (search.name) | none | `SaveSearchSheet` |
| `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift:163` | "data" ("Page \(currentPage)", "/ \(totalPages)") | @ScaledMetric (SearchPaginationBar.swift:126) | `SearchPaginationBar` |
| `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift:418` | "data" ("Page \(currentPage)") | minimumScaleFactor (SearchPaginationBar.swift:419) | `SearchPaginationBar` |
| `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift:461` | "data" ("Page \(currentPage)") | minimumScaleFactor (SearchPaginationBar.swift:462) | `SearchPaginationBar` |
| `kudos-ao3-reader/Features/Search/SearchView.swift:422` | "data" (tag.name) | none | `SearchView` |
| `kudos-ao3-reader/Features/Search/TagSelectField.swift:389` | "data" (tag.name) | none | `TagSelectField` |
| `kudos-ao3-reader/Features/WorkDetail/WorkDetailComponents.swift:58` | "data" (value) | minimumScaleFactor (WorkDetailComponents.swift:59) | `WorkDetailStatPill` |
| `kudos-ao3-reader/Features/WorkDetail/WorkDetailFactsSections.swift:237` | "data" (value) | minimumScaleFactor (WorkDetailFactsSections.swift:238) | `WorkDetailFactsSections` |
| `kudos-ao3-reader/Features/WorkDetail/WorkDetailFactsSections.swift:275` | "data" (value) | minimumScaleFactor (WorkDetailFactsSections.swift:276) | `WorkDetailFactsSections` |
| `kudos-ao3-reader/Features/WorkDetail/WorkDetailOverviewSections.swift:183` | "data" (other.title) | none | `WorkDetailOverviewSections` |
| `kudos-ao3-reader/Features/WorkDetail/WorkDetailSections.swift:316` | "data" (collection.title) | none | `WorkDetailSections` |
| `kudos-ao3-reader/Features/Writing/WritingDraftsView.swift:277` | "data" (DraftExpiry.chipText(daysLeft: daysLeft)) | none | `DraftCard` |
| `kudos-ao3-reader/Features/Writing/WritingFormFields.swift:34` | "data" (title) | none | `WritingFormFields` |
| `kudos-ao3-reader/UIComponents/DownloadDateImportConfirmation.swift:64` | "data" (work.title) | none | `DownloadDateImportConfirmation` |
| `kudos-ao3-reader/UIComponents/StackedWorkCover.swift:40` | "data" (work.title, work.author) | none | `StackedWorkCover` |
| `kudos-ao3-reader/UIComponents/StackedWorkCover.swift:76` | "data" (work.author) | none | `StackedWorkCover` |
| `kudos-ao3-reader/UIComponents/SubjectForm.swift:350` | "data" (label) | none | `SubjectFormOptionRow` |
| `kudos-ao3-reader/UIComponents/SubjectForm.swift:402` | "data" (title) | minimumScaleFactor (SubjectForm.swift:403) | `SubjectFormCheckRow` |
| `kudos-ao3-reader/UIComponents/SubjectScreen.swift:445` | "data" (kicker) | none | `SubjectScreenHeader` |
| `kudos-ao3-reader/UIComponents/SubjectScreen.swift:586` | "data" (title) | none | `SubjectChip` |
| `kudos-ao3-reader/UIComponents/SubjectScreen.swift:591` | "data" (count.formatted()) | none | `SubjectChip` |
| `kudos-ao3-reader/UIComponents/SubjectSurface.swift:454` | "data" (text.uppercased()) | none | `SubjectKicker` |
| `kudos-ao3-reader/UIComponents/SubjectSurface.swift:525` | "data" (subtitle) | `ViewThatFits` (SubjectSurface.swift:523) | `SubjectHeaderBlock` |
| `kudos-ao3-reader/UIComponents/SubjectSurface.swift:621` | "data" (title) | none | `SubjectCardHeader` |
| `kudos-ao3-reader/UIComponents/SubjectSurface.swift:738` | "data" (text.uppercased(), count) | none | `SubjectSectionKicker` |
| `kudos-ao3-reader/UIComponents/SubjectSurface.swift:847` | "data" (primary) | minimumScaleFactor (SubjectSurface.swift:848) | `SubjectMetricPill` |
| `kudos-ao3-reader/UIComponents/SubjectSurface.swift:862` | "data" (secondary) | minimumScaleFactor (SubjectSurface.swift:863) | `SubjectMetricPill` |
| `kudos-ao3-reader/UIComponents/SubjectSurface.swift:931` | "data" ("\(percent)%") | minimumScaleFactor (SubjectSurface.swift:932) | `SubjectProgressRing` |
| `kudos-ao3-reader/UIComponents/SubjectSurface.swift:939` | "data" (state.uppercased()) | minimumScaleFactor (SubjectSurface.swift:940) | `SubjectProgressRing` |
| `kudos-ao3-reader/UIComponents/SubjectSurface.swift:945` | "data" ("\(percent)%", state.uppercased()) | `minimumScaleFactor(0.6)` (SubjectSurface.swift:932, 940) | `SubjectProgressRing` |
| `kudos-ao3-reader/UIComponents/SubjectSurface.swift:1058` | "data" (label) | none | `SubjectSegmentControl` |
| `kudos-ao3-reader/UIComponents/WorkStatLabel.swift:50` | "data" (text) | none | `WorkStatLabel` |
| `kudos-ao3-reader/UIComponents/WorkStatLabel.swift:51` | "data" (text) | none | `WorkStatLabel` |
| `kudos-ao3-reader/UIComponents/WorkStatLabel.swift:227` | "data" (item.text) | none | `WorkListStatsRow` |
| `kudos-ao3-reader/UIComponents/WorkStatLabel.swift:228` | "data" (item.text) | none | `WorkListStatsRow` |

---

## 2. Separately Listed: `.minimumScaleFactor` (Already Guarded)

Listed below are all occurrences of `.minimumScaleFactor(...)` in `Features/` and `UIComponents/`. These views already define a text downscaling tolerance when space is constrained.

| `path:line` | Text string / expression | Guard within view | Screen (enclosing struct) |
|---|---|---|---|
| `kudos-ao3-reader/Features/Account/AccountComponents.swift:94` | "data" (title) | `minimumScaleFactor(0.5)` | `AccountStatsTile` |
| `kudos-ao3-reader/Features/Account/AccountComponents.swift:187` | "data" (label) | `minimumScaleFactor(0.8)` | `AO3CollectionRoleOptionRow` |
| `kudos-ao3-reader/Features/Account/AccountComponents.swift:310` | "data" (title) | `minimumScaleFactor(0.7)` | `AccountProfileHeader` |
| `kudos-ao3-reader/Features/Account/AccountComponents.swift:473` | "data" (title) | `minimumScaleFactor(title.contains(where: \.isWhitespace) ? 0.8 : 0.5)` | `AccountOptionCard` |
| `kudos-ao3-reader/Features/Authors/AuthorProfileComponents.swift:37` | "data" (pseud) | `minimumScaleFactor(0.75)` | `AuthorProfileHeader` |
| `kudos-ao3-reader/Features/Comments/CommentMarkup.swift:511` | "data" (tag.name) | `minimumScaleFactor(0.75)` | `CommentFormatTileFace` |
| `kudos-ao3-reader/Features/Comments/CommentMarkup.swift:516` | "data" (tag.syntaxGuide) | `minimumScaleFactor(0.75)` | `CommentFormatTileFace` |
| `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1785` | "data" (text) | `minimumScaleFactor(0.6)` | `CommentPostActionPill` |
| `kudos-ao3-reader/Features/Comments/CommentsView.swift:838` | "data" (title) | `minimumScaleFactor(0.8)` | `CommentsHeader` |
| `kudos-ao3-reader/Features/Home/HomeCards.swift:437` | "data" (label) | `minimumScaleFactor(0.8)` | `HomeStatsTile` |
| `kudos-ao3-reader/Features/Library/ReadingInsightsView.swift:170` | "data" (stat.value) | `minimumScaleFactor(0.6)` | `ReadingInsightsView` |
| `kudos-ao3-reader/Features/Library/ReadingInsightsView.swift:236` | "data" (stat.value) | `minimumScaleFactor(0.7)` | `ReadingInsightsView` |
| `kudos-ao3-reader/Features/Library/ReadingInsightsView.swift:257` | "data" (stat.value) | `minimumScaleFactor(0.7)` | `ReadingInsightsView` |
| `kudos-ao3-reader/Features/Library/ReadingInsightsView.swift:371` | "data" (stat.value) | `minimumScaleFactor(0.6)` | `ReadingInsightsView` |
| `kudos-ao3-reader/Features/ReaderReadium/ReaderPositionCard.swift:131` | "data" (workLine) | `minimumScaleFactor(0.75)` | `ReaderPositionCard` |
| `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift:419` | "data" ("Page \(currentPage)") | `minimumScaleFactor(0.6)` | `SearchPaginationBar` |
| `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift:462` | "data" ("Page \(currentPage)") | `minimumScaleFactor(0.7)` | `SearchPaginationBar` |
| `kudos-ao3-reader/Features/Search/SearchResultsHero.swift:197` | "data" (querySummary) | `minimumScaleFactor(0.85)` | `SearchResultsHero` |
| `kudos-ao3-reader/Features/WorkDetail/WorkDetailComponents.swift:52` | "data" (title) | `minimumScaleFactor(0.85)` | `WorkDetailActionButton` |
| `kudos-ao3-reader/Features/WorkDetail/WorkDetailComponents.swift:59` | "data" (value) | `minimumScaleFactor(0.85)` | `WorkDetailStatPill` |
| `kudos-ao3-reader/Features/WorkDetail/WorkDetailFactsSections.swift:238` | "data" (value) | `minimumScaleFactor(0.75)` | `WorkDetailFactsSections` |
| `kudos-ao3-reader/Features/WorkDetail/WorkDetailFactsSections.swift:276` | "data" (value) | `minimumScaleFactor(0.75)` | `WorkDetailFactsSections` |
| `kudos-ao3-reader/Features/WorkDetail/WorkDetailIdentityBlock.swift:263` | "data" (work.title) | `minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)` | `WorkDetailIdentityBlock` |
| `kudos-ao3-reader/UIComponents/StackedWorkCover.swift:68` | "data" (work.title) | `minimumScaleFactor(0.85)` | `StackedWorkCover` |
| `kudos-ao3-reader/UIComponents/SubjectForm.swift:403` | "data" (title) | `minimumScaleFactor(0.7)` | `SubjectFormCheckRow` |
| `kudos-ao3-reader/UIComponents/SubjectSurface.swift:516` | "data" (title) | `minimumScaleFactor(isOneWord ? 0.5 : 0.7)` | `SubjectHeaderBlock` |
| `kudos-ao3-reader/UIComponents/SubjectSurface.swift:848` | "data" (primary) | `minimumScaleFactor(0.7)` | `SubjectMetricPill` |
| `kudos-ao3-reader/UIComponents/SubjectSurface.swift:863` | "data" (secondary) | `minimumScaleFactor(0.7)` | `SubjectMetricPill` |
| `kudos-ao3-reader/UIComponents/SubjectSurface.swift:932` | "data" ("\(percent)%") | `minimumScaleFactor(0.6)` | `SubjectProgressRing` |
| `kudos-ao3-reader/UIComponents/SubjectSurface.swift:940` | "data" (state.uppercased()) | `minimumScaleFactor(0.6)` | `SubjectProgressRing` |

---

## 3. Top Twenty Rows Most Likely to Be Cut Off at Largest Size

The twenty rows most susceptible to clipping or truncation at the largest accessibility text size (a fixed container height, or one line holding data beside other things in an `HStack`, with no scaling guard), each with a concrete reason why.

| # | `path:line` | Text string / expression | Screen | Why it is likely to cut off |
|---|---|---|---|---|
| 1 | `kudos-ao3-reader/Features/ReaderReadium/ReaderChromeTopBar.swift:69` | "data" (title, author) | `ReaderChromeTopBar` | Fixed container height of 44pt holds both the work title and author line in a capsule; at accessibility text sizes, two lines of text cannot fit within 44pt without severe vertical truncation/clipping. |
| 2 | `kudos-ao3-reader/Features/Challenges/PromptMemeView.swift:402` | "data" (title) | `PromptMemeView` | Capsule button has a fixed height of 34pt and holds a single-line fixed-size title beside an icon or ProgressView with zero guards; accessibility type scales far beyond 34pt. |
| 3 | `kudos-ao3-reader/Features/Challenges/TagSetView.swift:349` | "Save tags" | `TagSetView` | Action button row has a hard-coded `.frame(height: 44)` enclosing bold text beside a ProgressView; at AX sizes the text height alone exceeds 44pt. |
| 4 | `kudos-ao3-reader/Features/Reader/ReaderView.swift:334` | "data" (positionLabel) | `ReaderView` | Floating position pill has a fixed height of 44pt holding reader position data (e.g. 'Page 14 of 50'); at largest Dynamic Type sizes, the monospaced text clips vertically. |
| 5 | `kudos-ao3-reader/Features/Library/CollectionLedgerRow.swift:147` | "data" (work.title, work.author) | `MiniatureWorkCover` | Cover preview card is held to a rigid `.frame(width: 61, height: 54)` while holding both work title and author text; at accessibility text sizes, the strings violently overflow the tile. |
| 6 | `kudos-ao3-reader/Features/ReaderReadium/ReaderFanMenu.swift:141` | "data" (pill.title) | `ReaderFanMenu` | Menu navigation action buttons have a rigid fixed height (`Self.roundActionHeight`) and width in an `HStack` beside icons with no text wrapping or scale fallback. |
| 7 | `kudos-ao3-reader/Features/Account/AO3CollectionItemsView.swift:613` | "data" (item.role) | `AO3CollectionItemCard` | Held to `.lineLimit(1)` and `.fixedSize()` inside an `HStack` beside a flexible collection title kicker; long role names push into the kicker or clip without wrapping. |
| 8 | `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:355` | "data" (item.commenterName) | `AccountInboxItemRow` | Byline row holds commenter name to `.lineLimit(1)` beside an unread indicator with no truncation mode or scale guard; long pseuds are silently cut off. |
| 9 | `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:388` | "data" (chapter) | `AccountInboxItemRow` | Chapter indicator text is held to `.lineLimit(1)` and `.fixedSize()` in an `HStack` beside static 'on' text and subject title; cannot wrap or compress. |
| 10 | `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1275` | "data" (collapse.label) | `CommentPostRow` | Collapse button is held to `.lineLimit(1)` and `.fixedSize()` in a crowded byline `HStack` beside author identity, timestamp, and chapter badge with no scaling guard. |
| 11 | `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1365` | "data" (timestamp) | `CommentPostRow` | Relative timestamp text is held to `.lineLimit(1)` and `.fixedSize(horizontal: true, vertical: false)` inside a crowded byline `HStack` with no wrap or scale guard. |
| 12 | `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1382` | "data" (chapter) | `CommentPostRow` | Chapter capsule badge is held to `.lineLimit(1)` and `.fixedSize()` inside the byline `HStack`; at AX sizes it refuses to shrink and causes clipping of surrounding text. |
| 13 | `kudos-ao3-reader/Features/Challenges/CollectionMaintainersView.swift:244` | "data" (roleText.uppercased()) | `CollectionMaintainersView` | Role badge is constrained to `.lineLimit(1)` and `.fixedSize()` trailing an expanding pseud and subtitle in an `HStack`; long role titles cannot wrap. |
| 14 | `kudos-ao3-reader/Features/Challenges/ChallengeAssignmentsView.swift:622` | "OPEN" / "CLAIMED" | `ChallengeAssignmentsView` | Status indicator is constrained to `.lineLimit(1)` and `.fixedSize()` directly beside a 'Pinch hit #X' title in an `HStack` with no scale factor. |
| 15 | `kudos-ao3-reader/Features/Search/AO3WorkRow.swift:385` | "data" (updated) | `AO3WorkRow` | Updated date is held to `.fixedSize(horizontal: true, vertical: false)` beside metadata summary text in an `HStack`; at large sizes it crowds out adjacent metadata. |
| 16 | `kudos-ao3-reader/Features/Search/AO3WorkRow.swift:419` | "data" (bookmark.date) | `AO3WorkRow` | Bookmark date is held to `.fixedSize(horizontal: true, vertical: false)` in an `HStack` trailing metadata text; at AX sizes the date consumes horizontal space without wrapping. |
| 17 | `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift:163` | "data" ("Page \(currentPage)", "/ \(totalPages)") | `SearchPaginationBar` | Pagination label is constrained to `.lineLimit(1)` inside a 44pt height container; large page numbers (e.g. Page 1,234 / 5,678) clip horizontally when fonts scale up. |
| 18 | `kudos-ao3-reader/UIComponents/SubjectSurface.swift:738` | "data" (text.uppercased(), count) | `SubjectSectionKicker` | Section kicker row places section title, numeric count, and optional note all inside an `HStack` with `.lineLimit(1)`; at AX sizes the items collide and truncate. |
| 19 | `kudos-ao3-reader/UIComponents/WorkStatLabel.swift:50` | "data" (text) | `WorkStatLabel` | Metadata stat chip applies `.lineLimit(1)` and `.fixedSize()` to an icon+text `HStack`; at largest accessibility sizes the text cannot wrap or scale down. |
| 20 | `kudos-ao3-reader/UIComponents/SubjectScreen.swift:591` | "data" (count.formatted()) | `SubjectChip` | Facet/filter chip count is locked to `.lineLimit(1)` directly beside the chip title inside an `HStack`; at AX sizes the count easily truncates. |

---

## 4. Row Counts by Kind

- **Kind 1 (`.lineLimit(1)` and `.lineLimit(1...1)`):** 91
- **Kind 2 (Fixed height frame on view containing `Text`):** 19
- **Kind 3 (`.fixedSize()` on `Text` inside an `HStack`):** 25
- **Kind 4 (`.minimumScaleFactor(`, guarded separately):** 30
- **Total rows indexed:** 165 (135 in Main Index + 30 Guarded)

Audit complete across all 268 Swift files in `kudos-ao3-reader/Features/` and `kudos-ao3-reader/UIComponents/`.
