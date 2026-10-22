# A81 — screens never shot beside the other app

Read-only. iOS paths are under `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`. Android paths are under `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/`. A screen is a whole page or sheet. Rows, cards, menus, alerts, and confirmation dialogs are omitted. The same view is one screen, except settings pages, library sections, and home sections, which the pair lists already shoot separately. Author-profile tabs are content of `AuthorProfileView` unless a dashboard action pushes that view onto its own page. iOS demo cells are the `-KudosDebugRoute` value (plus a tap when that is the only way). Android demo cells are the `kudosDebugRoute` extra (`nav:…`), plus `--es kudosSettingsPage <id>` when that opens a settings page.

`AO3FilterPanel` is one screen (pair `searchfilters`). Fandom works, tag works, and the account lists also present it in refine mode; those openings were not shot on their own. `LibraryFilterPanel` is one screen (pair `libraryfilters`) wherever it is presented. Collection Settings and New Collection are the same form. Work edit, draft edit, and new work are the same `WorkEditView`.

| Area | iOS screen | Pair or unpaired | Android | Demo route iOS | Demo route Android |
| --- | --- | --- | --- | --- | --- |
| Shell/tabs | *(none — the five tab roots are the Home, Library, Browse, Search, and Account rows)* | | | | |
| Home | `Features/Home/HomeView.swift:12` | home | `home/HomeScreen.kt:68` | `home` | `nav:home` |
| Home | `Features/Home/HomeSectionListView.swift:7` (reading now) | hsec_reading | `home/HomeSectionListScreen.kt:119` | `homesection:readingNow` | `nav:home-section/readingNow` |
| Home | `Features/Home/HomeSectionListView.swift:7` (recently updated) | hsec_updated | `home/HomeSectionListScreen.kt:119` | `homesection:recentlyUpdated` | `nav:home-section/recentlyUpdated` |
| Library dashboard and sections | `Features/Library/LibraryView.swift:15` | library | `library/LibraryScreen.kt:162` | `library` | `nav:library` |
| Library dashboard and sections | `Features/Library/LibrarySectionListView.swift:10` (reading now) | sec_reading | `library/LibraryScreen.kt:1266` `LibrarySectionContent` | `section:readingNow` | `nav:library-section/readingNow` |
| Library dashboard and sections | `Features/Library/LibrarySectionListView.swift:10` (saved for later) | sec_later | `library/LibraryScreen.kt:1266` | `section:savedForLater` | `nav:library-section/savedForLater` |
| Library dashboard and sections | `Features/Library/LibrarySectionListView.swift:10` (finished) | sec_finished | `library/LibraryScreen.kt:1266` | `section:finished` | `nav:library-section/finished` |
| Library dashboard and sections | `Features/Library/LibrarySectionListView.swift:10` (downloaded) | sec_downloaded | `library/LibraryScreen.kt:1266` | `section:downloaded` | `nav:library-section/downloaded` |
| Library dashboard and sections | `Features/Library/LibrarySectionListView.swift:10` (history) | sec_history | `library/LibraryScreen.kt:1266` | `section:history` | `nav:library-section/history` |
| Library dashboard and sections | `Features/Library/LibrarySectionListView.swift:10` (favorites) | sec_favorites | `library/LibraryScreen.kt:1266` | `section:favorites` | `nav:library-section/favorites` |
| Library dashboard and sections | `Features/Library/LibraryFilterPanel.swift:7` | libraryfilters | `library/LibraryFilterPanel.kt:67` | `section:readingNow` and `-KudosDebugOpenFilters YES` | `nav:library-section/readingNow`, tap Filter |
| Library dashboard and sections | `Features/Library/LibraryFilterPanel.swift:231` `LibraryOptionPicker` | unpaired | `library/LibraryFilterPanel.kt:300` sheet inside `LibraryMultiSelectRow` | library filter, then a multi-select row (value “Any”) | same, on the library filter sheet |
| Reading queues | `Features/Library/ReadingQueueOrganizer.swift:31` `AllReadingQueuesGridView` | queues | `library/QueueOrganizerScreen.kt:89` (hosted by `ReadingQueueBrowserScreen.kt:19` when there is no queue id) | `queues` | `nav:reading-queues` |
| Reading queues | `Features/Library/ReadingQueueBrowser.swift:10` `ReadingQueueBrowserView` | queue | `library/QueuePageScreen.kt:90` (same host, once a queue id is set) | `queue:Neon reread` | `nav:reading-queues?queueId={q:Neon reread}` |
| Reading queues | `Features/Library/ReadingQueueSettingsView.swift:28` | unpaired | `library/QueueDetailScreen.kt:11` → `library/QueueSettingsScreen.kt:77` | `queue-details:Neon reread` | queue page, menu “Queue details”. Direct route `nav:queue-detail/<id>` (id is not the display name) |
| Reading queues | `Features/Library/NewReadingQueueSheet.swift:48` | unpaired | `library/QueueEditorSheet.kt:62` (also `home/HomeSectionsUi.kt:129` `NewQueueDialog`) | `queues`, tap “New Queue” | `nav:reading-queues`, “New Queue” |
| Reading queues | `Features/Library/NewReadingQueueSheet.swift:353` `EditReadingQueueSheet` | unpaired | `library/QueueEditorSheet.kt:62` | `queue:Neon reread`, menu “Edit Queue” (not Saved for Later) | same queue, menu “Edit Queue” |
| Reading queues | `Features/Library/AddLibraryWorksSheet.swift:13` | unpaired | `library/AddLibraryWorksSheet.kt:67` | queue page, add-works control (“Add works from your library”). Collection detail opens the same sheet | queue page, “Add works” (`QueuePageScreen.kt:330`) |
| Reading queues | `Features/Library/QueueTagSheet.swift:19` | unpaired | `library/QueueTags.kt:87` | queue details, a tag row | `nav:queue-detail/<id>`, a tag row |
| Reading queues | `Features/Library/QueueTagManagerView.swift:16` | unpaired | `library/QueueTags.kt:255` `QueueTagManager` | queue details, “Manage all tags” | queue details, “Manage all tags” |
| Reading queues | `Features/Library/QueueTagManagerView.swift:306` `QueueTagEditSheet` | unpaired | `library/QueueTags.kt:87` `QueueTagSheet` (edit of one tag; no separate editor type found) | tag manager, a tag | tag manager, a tag |
| Reading queues | `UIComponents/WorkBulkTagSheet.swift:15` | unpaired | `library/QueueTags.kt:117` | a queue or library selection, the bulk tag action | same |
| Reading queues | `Features/Library/ReadingQueues.swift:438` `AddToQueueView` | unpaired | `ui/components/WorkBulkActionBar.kt:263` `QueuePickerDialog` (a dialog, not its own route) | a work’s menu “Add to Queue” | a work’s add-to-queue action |
| Reading queues | `Features/Library/ReadingQueues.swift:257` `ReadingQueueStorageView` | unpaired | `settings/QueueStorageScreen.kt:67` | `acct:settings:readingQueues`, tap “Queue Storage” | `nav:queue_storage` |
| Local collections | `Features/Library/LibraryView.swift:115` `collectionsGridDestination` | collections | `library/CollectionsScreen.kt:55` | `collections` | `nav:collections` |
| Local collections | `Features/Library/Collections.swift:102` `CollectionDetailView` | collection | `library/CollectionDetailScreen.kt:118` | `collection:Comfort reads` | `nav:collection-detail/{c:Comfort reads}` |
| Local collections | `Features/Library/Collections.swift:279` `detailsSheet` | unpaired | `library/CollectionEditorSheet.kt:56` (edit of an existing collection; the new-collection sheet is the next row) | collection page, the details control that sets `showingDetails` (`Collections.swift:483`) | collection page, the editor sheet |
| Local collections | `Features/Library/NewCollectionSheet.swift:15` | unpaired | `library/CollectionEditorSheet.kt:56` | `library` or `collections`, “New Collection” | `nav:library` or `nav:collections`, “New Collection” |
| Local collections | `Features/Library/NewCollectionSheet.swift:174` `CollectionReorderSheet` | unpaired | `library/CollectionReorderSheet.kt:62` | collection page, reorder | collection page, reorder |
| Local collections | `Features/Library/Collections.swift:600` `AddToCollectionView` | unpaired | `library/WorkMembershipDialogs.kt:50` `AddToCollectionDialog` | a work’s “Add to Collection” | a work’s add-to-collection action |
| Recently Deleted | `Features/Library/RecentlyDeletedView.swift:27` | deleted | `library/RecentlyDeletedScreen.kt:353` | `recentlyDeleted` | `nav:recently-deleted` |
| Reading Insights | `Features/Library/ReadingInsightsView.swift:18` | insights | `library/ReadingStatisticsScreen.kt:169` | `insights` | `nav:reading-statistics` |
| Browse | `Features/Browse/NativeBrowseView.swift:24` `BrowseView` | browse | `browse/BrowseScreen.kt:56` | `browse` | `nav:browse` |
| Browse | `Features/Search/FandomListView.swift:9` | unpaired | `browse/FandomListScreen.kt:54` | `browse`, tap “TV Shows” (fixture `ao3_media.html`) | `nav:browse-fandoms/TV%20Shows/` plus the fandoms path `/media/TV Shows/fandoms` |
| Browse | `Features/Browse/NativeBrowseView.swift:93` `FandomWorksView` | unpaired | `browse/FandomWorksScreen.kt:70` | fandom list, tap “Doctor Who” | `nav:browse-works/Doctor%20Who` |
| Browse | `Features/Browse/NativeBrowseView.swift:491` `TagWorksView` | unpaired | `browse/FandomWorksScreen.kt:70` with `isTag = true` | no debug route. `AppRouter.openAO3Link` pushes it for `/tags/<name>/works` (`AppRouter.swift:232`). Callers include a reader link (`ReadiumReaderView.swift:1406`) and rich text (`AuthorProfileComponents.swift:596`) | `nav:tag-works/Star%20Wars` |
| Browse | `Features/Search/FandomListFilterSheet.swift:7` | unpaired | `browse/FandomListChrome.kt:445` `FandomListFilterSheet` | fandom list, tap Filter | fandom list, tap Filter |
| Search, filters and saved searches | `Features/Search/SearchView.swift:8` | search | `search/SearchScreen.kt:127` | `search` | `nav:search` |
| Search, filters and saved searches | `Features/Search/AO3FilterPanel.swift:31` | searchfilters | `search/SearchFilterSheet.kt:76` | `search` and `-KudosDebugOpenFilters YES` | `nav:search`, tap Filter |
| Search, filters and saved searches | `Features/Search/SaveSearchSheet.swift:14` | unpaired | `search/SaveSearchSheet.kt:50` | search filters, “Save Search…” (`AO3FilterPanel.swift:386`; the sheet is presented from the panel) | search filters, save search |
| Search, filters and saved searches | `Features/Search/SearchPaginationBar.swift:292` `PageJumpSheet` | unpaired | `ui/components/KudosPaginationBar.kt:194` `PageScrubberSheet` | the results pagination control. Hidden when the result is one page; that page count was not re-read | same |
| Search, filters and saved searches | `Features/Search/FilterLanguagePicker.swift:10` | unpaired | `search/FilterLanguagePicker.kt:51` `FilterLanguageRow` (inline in the filter sheet, not its own page) | filter panel, row “Language” | inline on the filter sheet |
| Search, filters and saved searches | `Features/Search/TagSelectField.swift:137` `TagPickerView` | unpaired | none as its own page. Include/exclude stays in `search/SearchFilterSheet.kt:76` (`SearchFilterHelpers.kt:400`) | filter panel, a tag field | inline on the filter sheet |
| Work detail and My copy | `Features/WorkDetail/WorkDetailView.swift:23` | workdetail | `works/WorkDetailScreen.kt:130` | `work:Night Market` | `nav:work-detail/local:{w:Night Market}` |
| Work detail and My copy | `Features/WorkDetail/WorkDetailView.swift:384` `myCopySheet` | mycopy | `works/detail/WorkDetailMyCopySheet.kt:93` | `mycopy:Night Market` | work detail, tap “My copy” |
| Work detail and My copy | `Features/WorkDetail/WorkDetailSections.swift:571` `DownloadedDateEditor` | unpaired | `works/detail/WorkDetailMyCopySheet.kt:528` `DownloadedDateEditorDialog` | My copy, the downloaded-date row (`WorkDetailSections.swift:444`) | My copy, the downloaded-date row |
| Work detail and My copy | `Features/WorkDetail/WorkDetailView.swift:1193` `SeriesPreservationPromptSheet` | unpaired | `works/detail/WorkDetailForms.kt:169` | **no demo data.** Demo local works have no AO3 series URL, so the prompt is not built | same limit, unless a local work is given a series URL in session |
| Work detail and My copy | `Features/WorkDetail/AO3WorkActionsModel.swift:189` `AO3BookmarkComposer` | unpaired | `works/detail/WorkDetailForms.kt:125` `WorkDetailBookmarkForm` | work detail, bookmark action (titles “Bookmark on AO3” / “Edit Bookmark on AO3”) | same |
| Reader (settings, annotations, read aloud) | `Features/ReaderReadium/ReadiumReaderView.swift:17` `BookReaderView` (body is `ReadiumReaderView` at line 28) | reader | `reader/ReaderScreen.kt:140` | `read:Night Market` | `nav:reader/{w:Night Market}` |
| Reader (settings, annotations, read aloud) | `Features/ReaderReadium/ReaderContentsSheet.swift:42` | unpaired | `reader/ReaderContentsSheet.kt:57` | reader fan “Contents”, or “Bookmarks & Highlights” (same sheet, other segment) | reader contents |
| Reader (settings, annotations, read aloud) | `Features/ReaderReadium/ReaderSearchView.swift:229` | unpaired | `reader/ReaderSearchSheet.kt:98` | reader fan “Find in Work” | reader find |
| Reader (settings, annotations, read aloud) | `Settings/SettingsView.swift:15` `ReaderOptionsForm` | unpaired | `reader/ReaderScreen.kt:1029` `ReaderDisplaySheet` | reader fan “Themes & Settings” | reader display. A long-press of the fan button also opens this sheet (`ReaderScreen.kt:693`), not speech settings |
| Reader (settings, annotations, read aloud) | `Features/ReaderReadium/ReaderNoteEditor.swift:8` | unpaired | `reader/ReaderNoteEditor.kt:59` | select text in the reader and add a note (can be created in the session; the demo seeds none) | same |
| Reader (settings, annotations, read aloud) | `Features/ReaderReadium/ReaderSpeechSettingsSheet.swift:12` | unpaired | no reader sheet. The listening page is `settings/SettingsListeningPage.kt:41`, already pair `s_listening`. Long-press on Android opens the display sheet | reader, long-press the fan button | `nav:settings` and `--es kudosSettingsPage listening` |
| Reader (settings, annotations, read aloud) | `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:16` | unpaired | `settings/PronunciationSettings.kt:60` `PronunciationSettingsSheet` | speech settings, “Pronunciations” | listening settings, pronunciations |
| Reader (settings, annotations, read aloud) | `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:338` `ReaderPronunciationEditor` | unpaired | `settings/PronunciationSettings.kt:141` `PronunciationEditor` | pronunciations, “Add Pronunciation” or a row. Also “Fix Pronunciation” on a selection | pronunciations, add or a row |
| Reader (settings, annotations, read aloud) | `Features/ReaderReadium/ReaderSpeechDeveloperSettingsView.swift:19` | unpaired | **none.** `ListeningSpeechSettings.kt:49` says the iOS developer settings are not ported | speech settings, “Developer Settings” | none |
| Reader (settings, annotations, read aloud) | `Features/Reader/CustomizeThemeView.swift:11` | unpaired | `reader/CustomizeThemeSheet.kt:66` | reader display or `acct:settings:appearance`, “Customize Theme…” | appearance settings, customize theme |
| Comments | `Features/Comments/CommentsView.swift:43` | comments | `comments/CommentsScreen.kt:103` | `comments:Sodium Lights` | `nav:comments/999000005` |
| Comments | `Features/Comments/CommentThreadScreen.swift:14` | thread | `comments/CommentThreadScreen.kt:29` | `thread:Sodium Lights` | `nav:comments/999000005`, tap “Continue thread” |
| Comments | `Features/Comments/CommentsView.swift:1264` `CommentComposerSheet` | compose | `comments/CommentComposerSheet.kt:65` | `compose:Sodium Lights` | `nav:comments/999000005?compose=true` |
| Comments | `Features/Comments/CommentMarkup.swift:373` `CommentFormattingTray` | unpaired | `comments/CommentMarkup.kt:246` | composer, “More formatting” | composer formatting tray (`CommentComposerSheet.kt:332`) |
| Comments | `Features/Comments/CommentsView.swift:326` chapter picker sheet (no separate struct) | unpaired | `comments/CommentsScreen.kt:746` `ChapterPickerSheet` | comments, “By Chapter” (`CommentsView.swift:260`) | comments, chapter picker |
| Account hub and signed out | `Features/Account/AccountView.swift:19` | account | `account/AccountScreen.kt:180` | `account` | `nav:account` |
| Account hub and signed out | `Features/Auth/AO3LoginView.swift:6` | login | native form `auth/AO3NativeLoginScreen.kt:83`. The same iOS sheet reveals a web view on fallback; that half is `auth/AO3WebLoginScreen.kt:46` | `login` | pair list says `nav:login`, which is not a route. Native form is `nav:native-login`. Web form is `nav:account-login` |
| Marked for Later, Bookmarks, History, Subscriptions | `Features/Bookmarks/AO3AccountWorksList.swift:10` (marked for later) | later | `account/AccountWorksListScreen.kt:136` | `acct:later` | `nav:account-list/MarkedForLater` |
| Marked for Later, Bookmarks, History, Subscriptions | `Features/Bookmarks/AO3AccountWorksList.swift:10` (bookmarks) | bookmarks | `account/AccountWorksListScreen.kt:136` | `acct:bookmarks` | `nav:account-list/Bookmarks` |
| Marked for Later, Bookmarks, History, Subscriptions | `Features/Bookmarks/AO3AccountWorksList.swift:10` (history) | history | `account/AccountWorksListScreen.kt:136` | `acct:history` | `nav:account-list/History` |
| Marked for Later, Bookmarks, History, Subscriptions | `Features/Bookmarks/AO3AccountWorksList.swift:10` (subscriptions) | subs | `account/AccountWorksListScreen.kt:136` | `acct:subscriptions` | `nav:account-list/Subscriptions` |
| Inbox | `Features/Account/AccountInboxScreen.swift:19` | inbox | `account/AccountInboxPane.kt:105` | `acct:inbox` | `nav:account-inbox` |
| Inbox | `Features/Account/AccountInboxFilterSheet.swift:4` | unpaired | `account/AccountInboxPane.kt:620` `AccountInboxFilterSheet` | `acct:inbox`, “Inbox Filters” | inbox, filter |
| Author pages, Works, Series, Dashboard | `Features/Authors/AuthorProfileView.swift:4` (another author) | author | `author/AuthorProfileScreen.kt:76` | `author:Avery_Archive` | `nav:author-profile/Avery_Archive` |
| Author pages, Works, Series, Dashboard | `Features/Authors/AuthorProfileView.swift:4` (own Works page) | works | `author/AuthorProfileScreen.kt:76` with the Works tab. The pair route `nav:account-list/MyWorks` is the account list, not this page | `acct:works` | `nav:author-profile/AO3_Reader` (Works is the default tab) |
| Author pages, Works, Series, Dashboard | `Features/Authors/AuthorProfileView.swift:4` (own Series page) | myseries | `author/AuthorProfileScreen.kt:76` `initialTab` Series | `acct:series` | `nav:author-series/AO3_Reader` |
| Author pages, Works, Series, Dashboard | `Features/Account/AO3DashboardView.swift:15` (presents `AuthorProfileView` with `showsDashboard`) | dashboard | `account/AO3DashboardScreen.kt:18` (presents `AuthorProfileScreen`) | `acct:dashboard` | `nav:ao3-dashboard` |
| Author pages, Works, Series, Dashboard | `Features/Authors/AuthorProfileView.swift:4` pushed on Bookmarks (`AuthorProfileView.swift:83`) | unpaired | **none** as its own destination. Dashboard “See all bookmarks” opens the paired list `account/AccountWorksListScreen.kt:136` instead (`AuthorProfileScreen.kt:871`) | `acct:dashboard`, “See all … bookmarks” | no route opens this tab. The dashboard button goes to `nav:account-list/Bookmarks` |
| Author pages, Works, Series, Dashboard | `Features/Authors/AuthorProfileView.swift:4` pushed on About | unpaired | `author/AuthorProfileScreen.kt:76` with `initialTab` About | `acct:dashboard`, menu “About” | `nav:author-about/AO3_Reader` |
| Author pages, Works, Series, Dashboard | `Features/Authors/AO3SeriesDetailView.swift:4` | unpaired | `app/SeriesWorksScreen.kt:70` | `acct:series`, tap “The Dawn Cycle” (fixture `/series/321`) | `nav:series-works/` plus `/series/321` |
| Author pages, Works, Series, Dashboard | `Features/Writing/SeriesEditView.swift:25` | unpaired | `writing/WritingSeriesScreen.kt:37` (`reorderOnly` false) | `acct:seriesedit` (opens the edit of the first series) | series page, menu “Edit series” (`SeriesWorksScreen.kt:179`) |
| Author pages, Works, Series, Dashboard | `Features/Writing/SeriesEditView.swift:277` `SeriesReorderView` | unpaired | `writing/WritingSeriesScreen.kt:37` with `reorderOnly`, or the “Reorder works” row at line 211 | series page menu “Reorder”, or the series row’s “Reorder” | series page menu “Reorder” |
| Author pages, Works, Series, Dashboard | `Features/Writing/SeriesEditView.swift:441` `SeriesRemoveWorksView` | unpaired | `writing/WritingSeriesScreen.kt:37`, “Remove works” row at line 215 | series edit, “Remove works” | series edit, “Remove works” |
| Author pages, Works, Series, Dashboard | `Features/Authors/WorksScopeAndSort.swift:171` `AO3AuthorWorksFilterPanel` | unpaired | `search/SearchFilterSheet.kt:76` in refine mode (`AuthorProfileScreen.kt:563`) | `acct:works`, tap Filter | `nav:author-profile/AO3_Reader`, tap Filter |
| AO3 collections | `Features/Account/AO3CollectionsList.swift:9` | ao3colls | `account/AO3CollectionsScreen.kt:81` | `acct:collections` | `nav:ao3-collections` |
| AO3 collections | `Features/Account/AO3CollectionDetailView.swift:23` | ao3coll | `account/AO3CollectionDetailScreen.kt:87` | `acct:ao3collection:winter_exchange` | `nav:ao3-collection-detail/winter_exchange` |
| AO3 collections | `Features/Account/AO3CollectionFormView.swift:34` | colsettings | `account/AO3CollectionFormScreen.kt:50` | `acct:ao3collection:winter_exchange` and `-KudosDebugManageRow 'Collection Settings'`. Create is the same view: `acct:collections`, “New Collection” | `nav:ao3-collection-form?slug=winter_exchange`. Create is `nav:ao3-collection-form` |
| AO3 collections | `Features/Account/AO3CollectionItemsView.swift:24` | unpaired | `account/AO3CollectionItemsScreen.kt:84` | `acct:collections`, a row’s “Manage Items”, or the “Your items” chip | `nav:ao3-collection-items/winter_exchange`, or `nav:ao3-user-collection-items` |
| AO3 collections | `Features/Account/AO3CollectionsFilterPanel.swift:16` | unpaired | `account/AO3CollectionsFilterPanel.kt:48` | `acct:collections`, tap Filter | `nav:ao3-collections`, tap Filter |
| AO3 collections | `Features/Challenges/CollectionMaintainersView.swift:8` | colmaint | `account/AO3CollectionMaintainersScreen.kt:34` | manage row “Maintainers” | collection detail, “Maintainers” |
| AO3 collections | `Features/Challenges/CollectionModerationView.swift:15` | colmod | `account/AO3CollectionModerationScreen.kt:44` | manage row “Moderation” | collection detail, “Moderation” |
| Challenges | `Features/Challenges/ChallengeSettingsView.swift:10` | chsettings | `account/AO3ChallengeSettingsScreen.kt:32` | manage row “Challenge Settings” | collection detail, “Challenge Settings” |
| Challenges | `Features/Challenges/ChallengeSettingsEditView.swift:26` | unpaired | `account/AO3ChallengeSettingsEditScreen.kt:36` (same route; `AppNavHost.kt:793` swaps it in while editing) | challenge settings, “Edit settings” | `nav:ao3-challenge-settings/winter_exchange`, “Edit settings” |
| Challenges | `Features/Challenges/ChallengeSignUpsView.swift:9` | chsignups | `account/AO3ChallengeSignUpsScreen.kt:53` | manage row “Sign-ups” | collection detail, “Sign-ups” |
| Challenges | `Features/Challenges/ChallengeSignUpsView.swift:546` `ChallengeSignUpDetailView` | unpaired | `account/AO3ChallengeSignUpsScreen.kt:229` `ChallengeSignUpDetail` | sign-ups, tap a row (the pseud) | sign-ups, tap a row |
| Challenges | `Features/Challenges/ChallengeSignUpView.swift:9` | chmysignup | `account/AO3ChallengeSignUpScreen.kt:39` | manage row “Your Sign-up”. The same view is “Create sign-up” on the sign-ups page and “New prompt” on Prompts | collection detail, “Your Sign-up”. Create is `nav:ao3-challenge-sign-up/winter_exchange` |
| Challenges | `Features/Challenges/PromptTagsEditorView.swift:4` | unpaired | `account/AO3ChallengeSignUpScreen.kt:263` `SignUpTagsEditor` | the sign-up form, row “Fandoms” (or an “Offer N” row) | sign-up form, the tags editor |
| Challenges | `Features/Challenges/ChallengeAssignmentsView.swift:15` | chassign | `account/AO3ChallengeAssignmentsScreen.kt:45` | manage row “Assignments”. “Defaults and pinch hits” is this same view | collection detail, “Assignments” |
| Challenges | `Features/Challenges/PromptMemeView.swift:16` | chprompts | `account/AO3PromptMemeScreen.kt:46` | manage row “Prompts” | collection detail, “Prompts” |
| Challenges | `Features/Challenges/TagSetView.swift:36` | unpaired | `account/AO3TagSetScreen.kt:39` | challenge settings, “Winter Exchange Tags” (the collection profile fixture links `/tag_sets/42`; the challenge-settings HTML itself has no tag-set link) | `nav:ao3-tag-set/42?title=Winter%20Exchange%20Tags&moderator=true` |
| Challenges | `Features/Challenges/TagSetView.swift:231` `tagEditorScreen` | unpaired | `account/AO3TagSetScreen.kt:241` `TagSetEditor` | tag set, “Fandoms”, “Characters”, “Relationships”, or “Additional tags” | tag set, one of those rows |
| Writing | `Features/Writing/WritingDraftsView.swift:5` | drafts | `account/WritingDraftsScreen.kt:88` | `acct:drafts` | `nav:writing-drafts` |
| Writing | `Features/Writing/WorkEditView.swift:4` | workedit and draftedit | `writing/WritingWorkFormScreen.kt:50` | `acct:workedit:1001` (posted) and `acct:workedit:1002` (draft). New work is this same view | `nav:writing-work?workId=1001` and `nav:writing-work?workId=995001`. New work is `nav:writing-work` |
| Writing | `Features/Writing/WritingPreviewView.swift:10` | unpaired | `writing/WritingAO3PreviewScreen.kt:31` | work edit, “Preview on AO3” | work edit, preview |
| Writing | `Features/Writing/WritingChaptersView.swift:11` | unpaired | `writing/WritingChaptersScreen.kt:34` | posted work edit, “Chapters” | posted work edit, “Chapters” |
| Writing | `Features/Writing/AddChapterView.swift:4` | unpaired | `writing/WritingChapterFormScreen.kt:30` | work edit, “Add chapter”. A chapter row opens the same view for that chapter | `nav:writing-chapter-new-draft-demo` or `nav:writing-chapter-draft-demo` |
| Writing | `Features/Writing/EditTagsView.swift:4` | unpaired | `writing/WritingEditTagsScreen.kt:31` | work edit, “Edit tags” | work edit, edit tags |
| Writing | `Features/Writing/WritingTagsEditor.swift:38` | unpaired | `writing/WritingTagsEditorScreen.kt:62` | the tags screen’s editor (also embedded in the work form) | `WritingTagsEditorScreen`, also embedded in the work form |
| Writing | `Features/Writing/WritingTextEditor.swift:13` | unpaired | `writing/WritingTextEditorScreen.kt:74` | a chapter or summary field that pushes the editor | `nav:writing-editor-demo` or `nav:writing-editor-fixture` |
| Writing | `Features/Writing/WritingTextEditor.swift:336` `recoverySheet` | unpaired | the editor’s recovery UI on `writing/WritingTextEditorScreen.kt:74` | **no demo data** on iOS. The sheet appears only when a recovery copy exists, and the iOS demo seeds none | the Android demo writes one copy (`app/DemoLibrary.kt:303`) for work `privacy-demo` |
| Writing | `Features/Writing/WorkAssociationPickers.swift:307` `WorkSeriesPickerView` | unpaired | `writing/WritingAssociationPickers.kt:47` `WorkAssociation.Series` | work edit, the series row | work edit, series |
| Writing | `Features/Writing/WorkAssociationPickers.swift:18` `WorkCollectionsGiftsView` | unpaired | `writing/WritingAssociationPickers.kt:47` `WorkAssociation.CollectionsGifts` | work edit, “Add to collections” or “Gift recipients” (one view) | work edit, those rows |
| Writing | `Features/Writing/WorkAssociationPickers.swift:516` `WorkCreatorsPickerView` | unpaired | `writing/WritingAssociationPickers.kt:47` | work edit, the creators row | work edit, creators |
| Writing | `Features/Writing/WorkAssociationPickers.swift:627` `WorkParentWorkPickerView` | unpaired | `writing/WritingAssociationPickers.kt:47` `WorkAssociation.Parent` | work edit, the parent-work row | work edit, parent work |
| Writing | `Features/Writing/EditMultipleWorksView.swift:4` | unpaired | `writing/WritingBulkEditScreen.kt:30` | own Works, select more than one work, then the bulk-edit action. More on AO3’s “Edit works in bulk” opens the web browser, not this page | the profile’s bulk edit (`AuthorProfileScreen` sets `WritingBulkEditState`) |
| Writing | `Features/Writing/BulkTagStatePicker.swift:14` | unpaired | `writing/WritingBulkEditScreen.kt:179` `BulkOptionsScreen` | bulk edit, a tag-state row | bulk edit, a field row |
| Writing | `Features/Writing/BulkTagStatePicker.swift:135` `BulkNameListEditor` | unpaired | `writing/WritingBulkEditScreen.kt:30` (name lists are part of this screen; a separate editor composable was not found) | bulk edit, “Add to collections” / a name list | bulk edit, that row |
| AO3 Preferences | `Features/Account/AO3PreferencesView.swift:8` | prefs | `account/AO3PreferencesScreen.kt:83` | `acct:preferences` | `nav:ao3-preferences` |
| AO3 Preferences | `Features/Account/AO3PreferencesView.swift:259` `helpSheetView` | unpaired | `account/AO3PreferencesScreen.kt:464` `PreferenceHelpSheet` | preferences, a row’s help. Some help rows instead open the web browser (`AppNavHost.kt:1385`) | preferences, help |
| Settings hub and pages | `Settings/SettingsHubView.swift:10` | settings | `settings/SettingsHubScreen.kt:40` | `acct:settings` | `nav:settings` |
| Settings hub and pages | `Settings/SettingsReadingPages.swift:9` `SettingsAppearancePage` | s_appearance | `settings/SettingsPages.kt:39` | `acct:settings:appearance` | `nav:settings` and `--es kudosSettingsPage appearance` |
| Settings hub and pages | `Settings/SettingsReadingPages.swift:72` `SettingsFontPage` | s_font | `settings/SettingsPages2.kt:457` | `acct:settings:font` | `--es kudosSettingsPage font` |
| Settings hub and pages | `Settings/SettingsReadingPages.swift:84` `SettingsReaderPage` | s_reader | `settings/SettingsPages.kt:140` | `acct:settings:reader` | `--es kudosSettingsPage reader` |
| Settings hub and pages | `Settings/SettingsReadingPages.swift:95` `SettingsListeningPage` | s_listening | `settings/SettingsListeningPage.kt:41` | `acct:settings:listening` | `--es kudosSettingsPage listening` |
| Settings hub and pages | `Settings/SettingsStoragePages.swift:8` `SettingsDownloadsPage` | s_downloads | `settings/SettingsPages.kt:189` | `acct:settings:downloads` | `--es kudosSettingsPage downloads` |
| Settings hub and pages | `Settings/SettingsStoragePages.swift:37` `SettingsPreservationPage` | s_preservation | `settings/SettingsPages2.kt:165` | `acct:settings:preservation` | `--es kudosSettingsPage preservation` |
| Settings hub and pages | `Settings/SettingsStoragePages.swift:84` `SettingsReadingQueuesPage` | s_queues | `settings/SettingsPages2.kt:409` `SettingsReadingQueuesPageWrapper` | `acct:settings:readingQueues` | `--es kudosSettingsPage reading_queues` |
| Settings hub and pages | `Settings/SettingsStoragePages.swift:63` `SettingsLibraryPage` | s_library | `settings/SettingsPages2.kt:101` | `acct:settings:library` | `--es kudosSettingsPage library` |
| Settings hub and pages | `Settings/SettingsBackupPage.swift:33` | s_backup | `backup/BackupScreen.kt:59` | `acct:settings:backup` | `nav:backup` (there is no settings-page id `backup`) |
| Settings hub and pages | `Settings/SettingsSyncFolderPage.swift:8` | s_sync | `settings/SettingsPages2.kt:636` `SettingsFolderSyncPage` | `acct:settings:syncFolder` | `--es kudosSettingsPage folder_sync` |
| Settings hub and pages | `Settings/SettingsImportPage.swift:7` | s_import | `settings/SettingsPages2.kt:133` | `acct:settings:importFiles` | `--es kudosSettingsPage import_files` |
| Settings hub and pages | `Settings/SettingsAccountPages.swift:6` `SettingsAccountPage` | s_account | `settings/SettingsPages2.kt:188` | `acct:settings:account` | `--es kudosSettingsPage account` |
| Settings hub and pages | `Settings/SettingsAccountPages.swift:22` `SettingsPrivacyPage` | s_privacy | `settings/SettingsPages2.kt:242` `SettingsPrivacySettingsPage` | `acct:settings:privacySettings` | `--es kudosSettingsPage privacy_settings` |
| Settings hub and pages | `Settings/SettingsAccountPages.swift:56` `SettingsAboutPage` | s_about | `settings/SettingsPages2.kt:303` | `acct:settings:about` | `--es kudosSettingsPage about` |
| Settings hub and pages | `Features/Account/PrivacyDataView.swift:31` | unpaired | `settings/PrivacyDataScreen.kt:47` | `acct:settings:privacy` | `--es kudosSettingsPage privacy`. Also the About page row “Privacy and local data” |
| Settings hub and pages | `Features/Account/AvailabilitySweepView.swift:9` | unpaired | `settings/AvailabilitySweepScreen.kt:54` | `acct:settings:preservation`, “Check Availability…” | `nav:availability_sweep` |
| Settings hub and pages | `Settings/PairingSheet.swift:248` | unpaired | `backup/PairingSheet.kt:277` `PairingBottomSheet` | `acct:settings:syncFolder`, “Pair a Device” | folder sync, “Pair a Device” (`PairingSheet.kt:176`) |
| Settings hub and pages | `Settings/PairingSheet.swift:417` `QRScannerSheet` | unpaired | **none.** Android draws a code and says it never scans one (`PairingSheet.kt:320`) | pairing sheet, “Scan a QR Code” | none |
| Settings hub and pages | `Settings/SettingsSyncFolderPage.swift:229` `FolderSyncDetailsView` | unpaired | **none** as its own composable. Sync counts stay on `SettingsFolderSyncPage` (`SettingsPages2.kt:636`) | sync folder, “Sync Details” | none |
| Settings hub and pages | `Settings/PairingSheet.swift:211` `RevokeDeviceSheet` | unpaired | none found as its own sheet | **no demo data.** The demo seeds no trusted device, so Revoke is not shown | same |
| Settings hub and pages | `Settings/BackupImportSheet.swift:15` | unpaired | the import step of `backup/BackupScreen.kt:59` | **no demo data.** The sheet opens only after a backup file is chosen. The fixture `android-export.kudosbackup` is not preselected | `nav:backup`, then choose a file |
| More on AO3 | `Features/Account/AccountMoreOnAO3View.swift:69` | more | `account/AccountMoreOnAO3Screen.kt:61` | `acct:more` | `nav:account-more-on-ao3` |
| More on AO3 | `Features/Browse/BrowseView.swift:8` `AO3WebBrowserView` | unpaired | `web/AO3WebViewFallbackScreen.kt:64` | `acct:more`, then any row (“Post new work”, “Import work”, “Edit works in bulk”, “Manage collection items”, “Related works”, “Drafts”, and the archive rows). **needs AO3** for `/support`, `/tos`, `/faq`, `/donate`, `/abuse_reports/new`, `/privacy`, and `/content`, which the fixture map does not serve. The web view loads the real site even when a native client would have used a fixture | `nav:web-fallback/<encoded url>` |
| Onboarding, Support, About | `Features/Onboarding/WelcomeView.swift:7` | welcome | `onboarding/WelcomeScreen.kt:50` | `-hasCompletedOnboarding NO` (not a debug route) | `nav:welcome` |
| Onboarding, Support, About | `Features/Onboarding/SyncFolderOnboardingView.swift:8` | synconb | `onboarding/SyncFolderOnboardingScreen.kt:51` | `-hasPermanentlyDismissedSyncFolderOnboarding NO` | `nav:sync-onboarding` |
| Onboarding, Support, About | `Features/Support/WhatsNew.swift:59` `WhatsNewView` | whatsnew | `support/WhatsNew.kt:54` `WhatsNewSheet` | `-lastSeenChangelogVersion 0.9` | `nav:whats-new` |
| Onboarding, Support, About | `Features/Support/BugReportView.swift:11` | bugreport | `account/BugReportScreen.kt:83` | `bugreport` | `nav:bug-report` |
| Onboarding, Support, About | `Settings/AboutView.swift:5` | unpaired | `account/AboutScreen.kt:42` | `acct:settings:about`, “About Kudos”. Report a Bug on that page is the paired `BugReportView` | `nav:about` |

Signed-out Account is the same `AccountView` the `account` pair shoots signed in. It is not a second screen. Dashboard “See all works” and “See all series” push the same pages as `works` and `myseries`.

## Counts

Screens below. A row with two pair names (`workedit` and `draftedit`) counts as one paired screen. Shell/tabs has no screen of its own.

| Area | Paired | Unpaired | Screens |
| --- | --- | --- | --- |
| Shell/tabs | 0 | 0 | 0 |
| Home | 3 | 0 | 3 |
| Library dashboard and sections | 8 | 1 | 9 |
| Reading queues | 2 | 10 | 12 |
| Local collections | 2 | 4 | 6 |
| Recently Deleted | 1 | 0 | 1 |
| Reading Insights | 1 | 0 | 1 |
| Browse | 1 | 4 | 5 |
| Search, filters and saved searches | 2 | 4 | 6 |
| Work detail and My copy | 2 | 3 | 5 |
| Reader (settings, annotations, read aloud) | 1 | 9 | 10 |
| Comments | 3 | 2 | 5 |
| Account hub and signed out | 2 | 0 | 2 |
| Marked for Later, Bookmarks, History, Subscriptions | 4 | 0 | 4 |
| Inbox | 1 | 1 | 2 |
| Author pages, Works, Series, Dashboard | 4 | 7 | 11 |
| AO3 collections | 5 | 2 | 7 |
| Challenges | 5 | 5 | 10 |
| Writing | 2 | 14 | 16 |
| AO3 Preferences | 1 | 1 | 2 |
| Settings hub and pages | 15 | 7 | 22 |
| More on AO3 | 1 | 1 | 2 |
| Onboarding, Support, About | 4 | 1 | 5 |
| **Total** | **70** | **76** | **146** |

Of the 76 unpaired screens, these cannot be opened from the demo as it stands: series preservation (**no demo data**), the iOS recovery sheet (**no demo data**; Android’s demo does seed a copy), revoke-device (**no demo data**), and backup import (**no demo data** until a file is chosen). The AO3 web browser is **needs AO3** for the archive paths the fixture does not serve. Page jump stays hidden on a one-page result. Tag works has an Android debug route and no iOS debug route.

## Could not place

- `Settings/LegalNoticesView.swift:8` is never presented. It is not a screen.
- `App/DemoLibrary.swift:418` `CommentsDemoView` is the debug overlay for `-KudosDebugRoute comments` with no work title. The real comments screen is `CommentsView`.
- `AccountView` builds an `AO3FilterPanel` sheet for the hub’s works tab (`AccountView.swift:869`, `isWorksVisible`). `selectedTab` is only ever set to `.overview` (`AccountView.swift:426`), so that sheet cannot be opened. It is not counted.
- The login pair’s Android value `nav:login` matches neither `account-login` nor `native-login`. Both composables exist. The iOS sheet is one screen that starts as the native form and can show the web view.
- `author/AuthorWorksScreen.kt:55` is registered as `author-works/{name}` (`AppNavHost.kt:1117`). Nothing in the app calls `Routes.authorWorks`. There is no iOS page for it. The iOS works page is `AuthorProfileView`.
- `writing/WritingOwnWorkScreen.kt:14` is not its own page. It hands “edit”, “tags”, and “chapter” to `WritingWorkFormScreen`, `WritingEditTagsScreen`, and `WritingChapterFormScreen`.
- `library/QueuePageScreen.kt:90` is the selected queue inside `ReadingQueueBrowserScreen`, which is the paired `queue` screen, not an extra iOS page. `ReadingQueueDetailView` (`ReadingQueues.swift:189`) only wraps `ReadingQueueBrowserView`.
- `Features/Reader/ReaderView.swift:13` is the non-Readium body of `BookReaderView`, not a second destination. `MediaBrowserView` is the body of Browse. `WritingWorkDestination`, `WritingChapterDestination`, `SeriesEditDestination`, `SeriesReorderDestination`, `HomeWorkDestination`, and `LocalWorkDestinationView` load another view and are not screens.
- `AO3NamedSubscriptionsList` is embedded in the subscriptions browser. Saved-search rows are not a screen; the Search screen is paired and the demo list is empty.
- Skipped as confirmation UI: `UIComponents/DownloadDateImportConfirmation.swift:15` (it is a multi-field sheet if that call is reconsidered) and `Settings/SettingsView.swift:327` `ReplaceLibraryConfirmationView`.
- `Features/ReaderReadium/ReaderSpeechAuditionHarness.swift:32` was not found on a navigation path. It is left out of the table.
