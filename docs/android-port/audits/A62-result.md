# Priority list

Source-traced findings at Android `24cf81c7`. Ordered by loss of work/place/text, missing confirmation, missing behavior, then wording. IDs are stable across the tables below.

1. **F01 — Different / Android only: “Delete EPUB” immediately deletes even a source-less import's readable file.** No confirmation or Recently Deleted; iOS's Remove Download keeps the file. I `Features/WorkDetail/WorkDetailOverviewSections.swift:125` “WorkDownload”; A `works/WorkDetailScreen.kt:1439` “Delete EPUB” → `works/WorkRepository.kt:384` “deleteWorkEpub”.
2. **F02 — Different: Add/Remove bookmark can delete a bookmark on another page.** iOS matches the exact Readium position; Android removes the nearest mark in the same spine within 2% of the entire work. I `Features/ReaderReadium/ReadiumReaderView.swift:1567` “locations.position == position”; A `reader/AnnotationRepository.kt:95` “tolerance: Double = 0.02”, `reader/ReaderFanMenu.kt:161` same display predicate.
3. **F26 — Different: opening Collection Reorder then Done overwrites the existing reading order with newest-added order.** I `Features/Library/Collections.swift:151` passes “collection.inReadingOrder”; A `library/CollectionDetailScreen.kt:602` passes raw “works”, loaded by `works/WorkRepository.kt:739` → `data/local/dao/CollectionDao.kt:122` “ORDER BY works.dateAdded DESC”; `library/CollectionReorderSheet.kt:71` initializes from that raw list.
4. **F03 — Different: Back from a newly typed selection note discards its text.** iOS creates the mark then opens the autosaving editor; Android's initial Add note dialog dismisses without saving. I `Features/ReaderReadium/ReadiumReaderView.swift:652` “editingNote = annotation”, `Features/ReaderReadium/ReaderNoteEditor.swift:100` “keepDraft()”; A `reader/ReaderScreen.kt:780` “annotateDialog = null”, `:1176` “onDismissRequest = onDismiss”. Existing-note editing correctly keeps drafts.
5. **F04 — Different: disabling delete confirmation also bypasses confirmations iOS always asks for.** Library bulk Delete, collection bulk Remove, Queue Storage Remove, and a queue-only Library swipe can run without the corresponding iOS confirmation. I `UIComponents/WorkBulkActionBar.swift:128`, `UIComponents/ScopedRemovalBulkActionBar.swift:130`, `Features/Library/ReadingQueues.swift:347` “confirmationDialog”; A `library/LibraryScreen.kt:381`, `library/CollectionDetailScreen.kt:510`, `settings/QueueStorageScreen.kt:170` “confirmBeforeDelete”.
6. **F05 — Different: Rebuild from Original skips the up-to-date-work confirmation and silently ignores failures.** I `Features/Library/WorkCardActions.swift:468` “Rebuild this work?”, `Features/WorkDetail/WorkProvenanceSections.swift:137` same, `:150` “Couldn't Rebuild”; A `works/WorkDetailScreen.kt:1045`, `:1098`, `library/LibraryScreen.kt:581` discard `rebuildFromOriginal`'s result.
7. **F06 — Different: Read without a local EPUB queues a kept download and requires another tap to open.** I `Features/WorkDetail/WorkDetailView.swift:1051` restores a reading copy then “readerWork = work”; A `works/WorkDetailScreen.kt:1181` calls “download()”, completion at `:395` only refreshes details. Read and Download have different keep semantics on iOS.
8. **F07 — Different: Reader → title/Work Detail → Continue Reading pushes a second reader.** I `Features/WorkDetail/WorkDetailView.swift:1045` “if openedFromReader” dismisses; A `app/AppNavHost.kt:1112` retains the first reader and `:1054` unconditionally navigates to another. Back now returns through duplicate reader/detail entries.
9. **F08 — Different: “Chapter comments” and “Write a comment” just open All comments.** I `Features/WorkDetail/WorkDetailSections.swift:169` “focusesChapter: true”, `:179` “composes: true”; A `works/WorkDetailScreen.kt:1626` passes the same “onComments” to all three rows.
10. **F09 — Missing: Contents → chapter Bookmark and Add Note are unwired.** I `Features/ReaderReadium/ReaderContentsSheet.swift:151` “Bookmark”, `:158` “Add Note”; A `reader/ReaderContentsSheet.kt:65` nullable callbacks, neither supplied by `reader/ReaderScreen.kt:843`.
11. **F10 — Missing: queue and collection filters omit iOS's full sort/facet controls.** I `Features/Library/ReadingQueueBrowser.swift:339`, `Features/Library/Collections.swift:395` mount “LibraryFilterPanel”; A `library/QueuePageScreen.kt:654` only title/author, rating, Complete; `library/CollectionDetailScreen.kt:559` only title/author/fandom.
12. **F11 — Missing: queue cards have no per-work menu/swipes.** I `Features/Library/ReadingQueueBrowser.swift:645`, `:727` “localWorkContextMenu” plus list swipes; A `library/QueuePageScreen.kt:365`, `:390`, `:628` only activate the work. Read, Comments, Download, Favorite, Later, Queue, Finished, Collection, Work Details, scoped Remove and Delete are lost from the queue page.
13. **F12 — Missing: collection work menus offer only Open Work, Read and Remove.** I `Features/Privacy/MatureContent.swift:231` “localWorkContextMenu”; A `library/CollectionDetailScreen.kt:912` three-item menu. Missing Comments, Select-this-work, Download, Favorite, Later, Queue, Finished, Collection, Rebuild and Delete.
14. **F13 — Different: Library/section pull-to-refresh refreshes queues, not the works' metadata.** I `Features/Library/LibraryView.swift:896`, `Features/Library/LibrarySectionListView.swift:902` “WorkMetadataRefresh.refresh”; A `library/LibraryScreen.kt:601` → `library/LibraryViewModel.kt:510` only queue previews/deleted queue count. Work Detail refresh also does nothing for a remote-only work (`works/WorkDetailScreen.kt:1108` requires local).
15. **F14 — Missing: Library dashboard's New Collection is a name-only alert.** I `Features/Library/NewCollectionSheet.swift:99` name, description, colour, Keep downloads, Show on Home; A `library/LibraryScreen.kt:460` only “Collection name”. Android's full editor exists on the separate Collections screen, but this entry does not use it.
16. **F15 — Missing: Library and bulk Add to Queue pickers cannot toggle membership, create a queue in place, or add a series.** I `Features/Library/ReadingQueues.swift:467` “New queue”, `:477` “toggle(queue)”, `:503` “Also add works from this AO3 series”; A `library/WorkMembershipDialogs.kt:47`, `ui/components/WorkBulkActionBar.kt:265`, `library/LibraryScreen.kt:305` only pick an existing queue and add. Work Detail has creation/series controls; its additive-only membership is explicitly retained by brief 3bn's data-safety constraint, as recorded below.
17. **F16 — Missing: bulk Add to Collection cannot remove existing memberships or show their check state.** I `Features/Library/Collections.swift:638` “toggle(collection)”; A `library/LibraryScreen.kt:332` and `ui/components/WorkBulkActionBar.kt:303` only add and close. Single-work pickers correctly toggle.
18. **F17 — Missing: scoped selection cannot remove from Saved for Later.** I `UIComponents/ScopedRemovalBulkActionBar.swift:207` toggles by all selected memberships; A `library/ScopedSelectionBar.kt:163` always “Save for Later”, always adds.
19. **F18 — Missing: Library section Layout and Expand All/Collapse All; queue Detailed layout/expansion; collection Expand All/Collapse All.** I `Features/Library/LibrarySectionListView.swift:228`, `Features/Library/ReadingQueueBrowser.swift:792`, `Features/Library/Collections.swift:462`; A `library/LibraryScreen.kt:1390` omits layout, `library/QueuePageScreen.kt:604` only Compact/List, `library/CollectionDetailScreen.kt:433` only Detailed/Ledger. Android chrome may differ; losing a content view/action is not chrome.
20. **F19 — Missing: My copy's tag-name tap cannot filter Library, and failed queue preservation has no Retry action.** I `Features/WorkDetail/WorkDetailSections.swift:542` “filterLibrary(.userTag…)”, `:248` “Retry Queue Preservation”; A `works/detail/WorkDetailMyCopySheet.kt:765` name is plain Text, `:318` status section has only three toggles.
21. **F20 — Missing: Work Detail cannot open another already-local work in the series directly.** I `Features/WorkDetail/WorkDetailOverviewSections.swift:156` “ForEach(seriesWorks)” links/reveal; A `works/WorkDetailScreen.kt:1648` passes series title/position/URL only to “WorkDetailSeriesSection”.
22. **F31 — Missing: linked author bylines on detailed Library/collection rows and Add Works candidates cannot open the author.** I `Features/Library/WorkRow.swift:220` “AO3AuthorBylineView”, `Features/Library/AddLibraryWorksSheet.swift:136` same (dismisses picker then opens profile); A `ui/components/SensitiveWorkRow.kt:298` and `library/AddLibraryWorksSheet.kt:146` render plain “Text”. Work Detail/Favorites author links do work.
23. **F32 — Missing: expanded work-card tag groups stop at 16 clickable tags.** I `Features/Library/WorkRow.swift:322` renders every tag button; A `ui/components/SensitiveWorkRow.kt:399` “maxItems = 16” → `ui/components/KudosUi.kt:218` inert “+$hiddenCount”. Remaining tag-search actions require opening Work Detail instead.
24. **F30 — Missing: queue organizer Select All / Deselect All.** I `Features/Library/ReadingQueueOrganizer.swift:361` “SelectAllButton”; A `library/QueueOrganizerScreen.kt:358` selecting toolbar has only Pin, Tag, Delete, Done. Large queue selections require one tap per queue.
25. **F21 — Missing: reader theme customization lacks Customize on/off, line spacing, margins, justification, Reset Theme and preview; reader font list lacks custom fonts/Add/Delete.** I `Features/Reader/CustomizeThemeView.swift:78`, `:81`, `:88`, `:90`, `:101`; `Settings/SettingsView.swift:157`, `:183`, `:185`; A `reader/ReaderScreen.kt:1004` only Bold/Letter/Word spacing and `:1142` built-ins only. These are content/actions, beyond the recorded choice of Android chrome.
26. **F29 — Different: reader voice-pack download has no second confirmation, in-sheet cancellation or explicit Retry.** I `Features/ReaderReadium/ReaderSpeechSettingsSection.swift:253` “Download”/“Cancel”, `:292` “Retry Download”, `:403` running “Cancel”; A `reader/ReaderScreen.kt:1135` directly invokes download, `:1133` only shows progress. Download remains user-started; this is action parity, not an allegation of unsolicited network use.
27. **F22 — Different: Read Aloud Previous/Next moves paragraphs rather than chapters; hiding chrome also hides the only mini-player.** I `Features/ReaderReadium/ReaderSpeechController.swift:878`, `:902` “Previous chapter”/“Next chapter”; `Features/ReaderReadium/ReadiumReaderView.swift:1069` “standaloneMiniPlayer”; A `reader/ReaderPositionCard.kt:397` “Previous paragraph”, `reader/speech/ReaderSpeechController.kt:162` advances one queue item; `reader/ReaderScreen.kt:665` mini-player exists only while chrome is visible. Hold-seek is separately recorded deferred (A61 #21).
28. **F23 — Different: Highlight always starts yellow and repeats recolour instead of removing the same mark.** I `Features/ReaderReadium/ReadiumReaderView.swift:625` deletes same-colour repeat, `:634` “lastUsed”; A `reader/ReaderScreen.kt:1172` “YELLOW”, `reader/AnnotationRepository.kt:135` existing mark always copied/recoloured. Initial Highlight also adds a confirm dialog instead of applying immediately.
29. **F24 — Different: deleting a bookmark/highlight adds a confirmation on Android; iOS deletes immediately.** I `Features/ReaderReadium/ReaderContentsSheet.swift:190`, `Features/ReaderReadium/ReaderNoteEditor.swift:56` immediate delete; A `reader/ReaderScreen.kt:315` “Delete annotation?” / Cancel, controlled by delete preference. No undo on either.
30. **F25 — Different wording: a History/Favorites Later swipe says “Unsave” instead of naming Saved for Later.** I `Features/Library/LibraryWorkSwipeActions.swift:62` “SaveForLaterButton”; A `library/LibraryScreen.kt:1095` “Unsave”. In the same app Remove Download is a separate operation, so the abbreviated label is ambiguous.
31. **F27 — Missing: Edit tag lacks its own Remove row.** I `Features/Library/QueueTagManagerView.swift:383` “Remove”; A `library/QueueTags.kt:511` editor has Name/Merge only. Returning to the manager offers the same removal, so this is lower priority.
32. **F28 — Different: Collection Details stages edits until Save and discards them on Back, while iOS writes them immediately and keeps them on dismissal.** I `Features/Library/Collections.swift:225` setter writes description; A `library/CollectionEditorSheet.kt:186` changes draft, `:103` saves, `:78` dismisses without applying. An explicit Save/Cancel explains the difference but behavior is out of step.
33. **F33 — Missing: Filter long-press → Clear All Filters on Library dashboard, section lists and queue page.** I `UIComponents/WorkCardListControls.swift:97` context menu; A dashboard `library/LibraryShellChrome.kt:130` is a click-only button; section `library/LibraryScreen.kt:1378` omits “onClearFilters”; queue `library/QueuePageScreen.kt:576` likewise. Collection page correctly passes the callback (`library/CollectionDetailScreen.kt:375`). Reset in the filter sheet is an available fallback.

## Scope and evidence

Read-only source audit on `android/agent-codex-a62`, HEAD `24cf81c7`. iOS references are relative to `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`; Android references are relative to `android/app/src/main/java/io/github/cidy02/kudos/`. Only this result file is written. No build, commit, push, branch switch, sign-in, or AO3 request. Recorded decisions from 2026-10-10 onward were applied before classifying differences.

## Reading the tables

I = iOS, relative to `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (HEAD `c3eb0bc87958d4b825fa33cb4fd1a31f1250864f`). A = Android, relative to `android/app/src/main/java/io/github/cidy02/kudos/`. Quoted text is a label or handler excerpt, not a claim of runtime observation. A **missing** row cites the actual counterpart/complete menu where the omission can be checked. Shared menus are inventoried once and explicitly referenced by each screen that uses them.

**same** means the reachable action and its ordinary effect match in source. It does not certify device gestures, appearance or races under process death. Unless a row says otherwise, neither side asks for confirmation, offers undo, or shows a success message. For soft deletion, recovery is Restore in Recently Deleted for 90 days, not an immediate Undo button. Cancel on a live membership picker closes it; it does not undo toggles already applied.

## Library dashboard — LibraryView

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Open Reading Now, Saved for Later, Finished, Downloaded, History, Favorites via See All | “LibrarySectionListView” `Features/Library/LibraryView.swift:249`; See All pushes `:522` | “onOpenSection” for each of those six `library/LibraryScreen.kt:819`, `:833`, `:847`, `:873`, `:887`, `:901` | **same** — corresponding Library list. |
| Open Collections / a collection | “NavigationLink(value: collection)” `Features/Library/LibraryView.swift:440` | “onOpenCollections”, “onOpenCollection” `library/LibraryScreen.kt:860` | **same**. |
| Expand/collapse a dashboard group | “WorkCarouselSection” `Features/Library/LibraryView.swift:515` | “onToggleCollapsed” `library/LibraryScreen.kt:818` | **same** local display change; repeated for all dashboard groups. |
| New Collection | “New Collection” `Features/Library/LibraryView.swift:714` → full `Features/Library/NewCollectionSheet.swift:99` | “Collection name” `library/LibraryScreen.kt:468` | **different F14** — description, colour and both behavior toggles unavailable here. Create/Cancel work; full Android editor elsewhere does not fix this entry. |
| Filter / clear active filters | “FilterButton…onClearFilters” `Features/Library/LibraryView.swift:718` | “onShowFilters” `library/LibraryShellChrome.kt:131`; “Reset filters” `library/LibraryFilterPanel.kt:102` | **same** filter panel; direct clear placement differs as chrome. Full panel table below. |
| All / choose or deselect fandom / Reset quick rail | “All”, fandom toggle, “Reset” `Features/Library/LibraryView.swift:599`, `:603`, `:616` | “onSelectAll”, “onSelectFandom”, “onReset” `library/LibraryScreen.kt:793`–`:795` | **same** quick fandom filter across dashboard groups. |
| Show/Hide mature | “MatureRevealToggle” `Features/Library/LibraryView.swift:725` | “Show mature works” `library/LibraryShellChrome.kt:146` | **same** uses privacy gate, not direct opening of an obscured work. |
| Select / select one work / Select All / Deselect All / Done | “Select” `Features/Library/LibraryView.swift:731`, “SelectAllButton” `:673` | “Select” `library/LibraryShellChrome.kt:161`, “onSelectAll” `library/LibraryScreen.kt:274`; selection bar `:2527` | **same** available over visible works; bulk table below. |
| Layout: carousels / list | “Picker(\"Layout\")” `Features/Library/LibraryView.swift:738` | “Show Detailed List” / “Show Carousels” `library/LibraryShellChrome.kt:172` | **same** two dashboard presentations; Android wording/control is its chrome. |
| Reading Insights | “Reading Insights” `Features/Library/LibraryView.swift:746` | “Reading Insights” `library/LibraryShellChrome.kt:206` | **same**. |
| Recently Deleted | “RecentlyDeletedDestination()” `Features/Library/LibraryView.swift:483` | “Recently Deleted” `library/LibraryScreen.kt:1625`, `library/LibraryShellChrome.kt:215` | **same**; Android also offers a menu entry. |
| Tap work / reveal obscured work / long press work | “LocalWorkDestination.reader(work)” `Features/Library/LibraryView.swift:857`, “localWorkContextMenu” `:855` | “onOpen” / “onLongClick” `library/LibraryScreen.kt:2001`, `:2028` | **same** ordinary downloaded-work open/reveal. Shared local-menu table applies, with compact-menu exception below. |
| Delete collection from card long press | “Delete” / “Cancel” `Features/Library/Collections.swift:791` | “Delete Collection” `library/LibraryScreen.kt:2303`, confirmation `:403` | **same** confirmation; moves collection only to recovery, works stay. |
| Pull to refresh (normal and selecting) | “refreshLibraryDashboard” / “refreshSelectableWorks” `Features/Library/LibraryView.swift:895` | “viewModel.refresh()” `library/LibraryScreen.kt:601` → `library/LibraryViewModel.kt:510` | **different F13** — Android only reloads queue summaries, never refreshed works' AO3 facts. |
| Reading Queues shortcut | iOS dashboard toolbar has only privacy/select/layout/insights `Features/Library/LibraryView.swift:723` | “Reading Queues” `library/LibraryShellChrome.kt:197` | **Android only**, useful extra route to existing organizer. |

## Shared local-work context menu and work swipes

Used by iOS Library cards, every Library section, collection work rows and queue work cards. Android's full menu below is `LibraryWorkMenu`, used by Library list rows/cards; its separate compact carousel menu is less capable. Queue/collection omissions are listed on their own screens.

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Read | “Read” `Features/Library/WorkCardActions.swift:349` | “if (work.hasEpub)…Read” `library/LibraryScreen.kt:1170` | **different F06** — Android omits Read for freed/no-file works; iOS can prepare the file via the reader route. Ordinary local EPUB opens correctly. |
| Comments | “Comments” `Features/Library/WorkCardActions.swift:357` | “Comments” `library/LibraryScreen.kt:1176` | **same** AO3-backed works only, opens discussion. |
| Select this work | “Select” `Features/Library/WorkCardActions.swift:362` | “Select” `library/LibraryScreen.kt:1180` | **same** when parent has selection. |
| Download / Remove Download / Kept Offline by… | “WorkDownloadButton” `Features/Library/WorkCardActions.swift:372` | “WorkDownloadSemantics.action” `library/LibraryScreen.kt:1183` | **same** keep toggle, protected membership informational/disabled, imported work has no Download action. No file deletion on Remove Download. |
| Favorite / Unfavorite | “WorkActionLabels.favorite” `Features/Library/WorkCardActions.swift:378` | “Unfavorite…Favorite” `library/LibraryScreen.kt:1202` | **same**, reversible by toggling again. |
| Save for Later / remove from Later | “WorkActionLabels.savedForLater” `Features/Library/WorkCardActions.swift:386` | “Remove from Saved for Later” `library/LibraryScreen.kt:1205` | **same** single-work menu action. Series prompt behavior is inventoried under Work Detail. |
| Add to Queue | “Add to Queue” `Features/Library/WorkCardActions.swift:394` | “Add to Queue” `library/LibraryScreen.kt:1208` | **different F15** picker capabilities below. |
| Mark as Finished / Still Reading | “WorkActionLabels.finished” `Features/Library/WorkCardActions.swift:401` | “finishedActionLabel” `library/LibraryScreen.kt:1211` | **same** lifecycle toggle; finished un-kept copy held, not instantly removed. |
| Add to Collection | “Add to Collection” `Features/Library/WorkCardActions.swift:409` | “Add to Collection” `library/LibraryScreen.kt:1214` | **same** single-work membership picker; see picker table. |
| Rebuild from Original | “Rebuild from Original” `Features/Library/WorkCardActions.swift:419` | same `library/LibraryScreen.kt:1218` | **different F05** skips redundant-rebuild confirmation, ignores failure. Also **missing** from the separate compact carousel menu (`library/LibraryScreen.kt:2034`–`:2147`, ends in “Remove”). |
| Work Details | “Work Details” `Features/Library/WorkCardActions.swift:424` | same `library/LibraryScreen.kt:1222` | **same**. |
| Delete | “Delete” `Features/Library/WorkCardActions.swift:443`; confirmation `:460` | “Delete” `library/LibraryScreen.kt:1225`; dialog `:417` | **same** setting-controlled confirmation, 90-day recovery and unavailable-AO3 warning via shared deletion message. Compact Android menu says “Remove” (`:2139`) for the same soft delete: wording difference. |
| Leading swipe Download / Favorite (non-Favorites sections) | “WorkDownloadButton”, “favorite” `Features/Library/LibraryWorkSwipeActions.swift:64`, `:75` | “Download”, “Favorite” `library/LibraryScreen.kt:1101`, `:1115` | **same**; iOS prohibits full-swipe activation, Android uses explicit revealed actions. |
| History/Favorites leading Later swipe | “SaveForLaterButton” `Features/Library/LibraryWorkSwipeActions.swift:62` | “Unsave” / “Save for Later” `library/LibraryScreen.kt:1095` | **different F25** label only. |
| Favorites trailing Unfavorite | “favorite(isFavorite: true)” `Features/Library/LibraryWorkSwipeActions.swift:92` | “Unfavorite” `library/LibraryScreen.kt:1136` | **same**; removes star, not work. |
| History trailing Remove | “Remove” `Features/Library/LibraryWorkSwipeActions.swift:107`; prompt `:141` | “Remove this work?” `library/LibraryScreen.kt:391`, handler `:398` | **same** always asks; explains reading again brings it back. No work/file deletion. Android message omits work title. |
| Queue-only trailing Remove from every queue | “will leave every queue” `Features/Library/LibraryWorkSwipeActions.swift:148` | “onRemoveFromAllQueues(work.id)” `library/LibraryScreen.kt:1147` → direct callback `:568` | **different** — Android has no confirmation at this entry (part of F04); iOS always sets the pending removal and asks; Android dispatches removal directly. |
| Ordinary trailing Delete | “pendingDelete = work” `Features/Library/LibraryWorkSwipeActions.swift:112` | “actions.onRemove(work.id)” `library/LibraryScreen.kt:1152` | **same** shared soft-delete confirmation path. |

## Detailed work row content (Library and collection rows)

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Expand / Show Less one row | “WorkRowExpandButton” `Features/Library/WorkRow.swift:309`, toggle `:342` | “Show more” / “Show less” `ui/components/SensitiveWorkRow.kt:283` | **same** individual expansion; Expand All is separately F18. |
| Tap verified author name | “AO3AuthorBylineView” `Features/Library/WorkRow.swift:220` | plain “Text…by $author” `ui/components/SensitiveWorkRow.kt:298` | **missing F31**, whole-row tap opens work instead. iOS intentionally disables author navigation while selecting/obscured (`Features/Privacy/MatureContent.swift:239`), so no missing action claimed in those states. |
| Tap expanded relationship/character/freeform tag | “router.searchAO3(field, tag)” `Features/Library/WorkRow.swift:323` | “tagSearch(field, tag)” `ui/components/SensitiveWorkRow.kt:400` | **same** for visible tags; **missing F32** tags after the first 16 in each group. iOS renders all; Android's +N chip has no callback (`ui/components/KudosUi.kt:218`). |
| Filter toolbar long-press / Clear All Filters | “Clear All Filters” `UIComponents/WorkCardListControls.swift:100` | shared component has “Clear All Filters” `ui/subject/SubjectComponents.kt:995` but callers omit callback | **missing F33** dashboard/sections/queue; **same** collection page passes `onClearFilters` (`library/CollectionDetailScreen.kt:375`). Panel Reset remains available everywhere. |

## Shared Library section controls

This table applies independently to Reading Now, Saved for Later, Finished, Downloaded, History and Favorites → Works. Each screen's unique controls follow in a separate table.

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Filter / reset | “FilterButton” `Features/Library/LibrarySectionListView.swift:211` | “onShowFilters” `library/LibraryScreen.kt:1381` | **same** full Library filter panel. |
| Show/Hide mature | “MatureRevealToggle” `Features/Library/LibrarySectionListView.swift:219` | “Show mature works” `library/LibraryScreen.kt:1393` | **same**. |
| Select; row toggle; Select/Deselect All; Done | “Select” / “SelectAllButton” `Features/Library/LibrarySectionListView.swift:225`, `:187` | “Select” / “Select All” `library/LibraryScreen.kt:1398`, `:1371`; bar `:1569` | **same**, intersected with visible rows; bulk actions below. |
| Layout Compact/Ledger/Detailed, as allowed by screen | “DisplayModeMenuPicker…allowedDisplayModes” `Features/Library/LibrarySectionListView.swift:228` | menu contains privacy and Select only `library/LibraryScreen.kt:1390` | **missing F18**. Android has fixed defaults (History/Favorites ledger; other lists detailed). |
| Expand All / Collapse All in Detailed | “ExpandAllMenuItem” `Features/Library/LibrarySectionListView.swift:231` | no item in menu `library/LibraryScreen.kt:1390` | **missing F18**; individual work expansion survives in detailed rows. |
| Pull to refresh | “refreshSection()” `Features/Library/LibrarySectionListView.swift:287` | “KudosRefreshBox(onRefresh = onRefresh)” `library/LibraryScreen.kt:1416` → `library/LibraryViewModel.kt:510` | **different F13**, same absent work refresh as dashboard. |
| Tap/reveal work, long press, swipe | “SensitiveWorkRow” / “localWorkContextMenu” `Features/Library/LibrarySectionListView.swift:816` | “LibrarySubjectLedgerRow” `library/LibraryScreen.kt:1536` | **same** shared local actions except listed menu/layout differences. |

## Reading Now section

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| All / WIP quick pills, including counts | “pill(\"All…\")”, WIP `Features/Library/LibraryCompletionPills.swift:13` | “All”, “Wip” `library/LibrarySectionQuickFilter.kt:18`, count `:30` | **same** completion filter; full panel may select Complete. |
| Shared section controls and local actions | “LibraryCompletionPills” `Features/Library/LibrarySectionListView.swift:369` | “librarySectionQuickFilterLabel” `library/LibraryScreen.kt:1462` | **same** actions as shared tables, with F06/F13/F18. |

## Saved for Later section

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Open work / remove Later / download / favorite / finished / queues / collection / delete | “LibrarySectionListView” shared rows `Features/Library/LibrarySectionListView.swift:816` | shared “LibraryWorkMenu” `library/LibraryScreen.kt:1158` | **same** ordinary membership/local actions, subject to F06/F15/F18. This is the local queue, not AO3 Marked for Later. |
| Filters, select, refresh, layout, expansion | shared section toolbar `Features/Library/LibrarySectionListView.swift:178` | shared section toolbar `library/LibraryScreen.kt:1366` | **different/missing F13/F18** as above. |

## Finished section

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Mark as Still Reading, reopen, local menu and swipes | “WorkActionLabels.finished” `Features/Library/WorkCardActions.swift:401` | “finishedActionLabel(work.isFinished)” `library/LibraryScreen.kt:1211` | **same** ordinary toggle; reopening without a copy has F06. |
| Filters, select, refresh, layout, expansion | “DisplayModeMenuPicker” `Features/Library/LibrarySectionListView.swift:228` | menu `library/LibraryScreen.kt:1390` | **different/missing F13/F18**; other shared controls match. |

## Downloaded section

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Remove Download / other local menu and swipes | “WorkDownloadButton” `Features/Library/LibraryWorkSwipeActions.swift:64` | “Remove Download” `library/LibraryScreen.kt:1109` | **same**, un-keeps; file remains, protected/imported controls follow download semantics. |
| Filters, select, refresh, layout, expansion | toolbar `Features/Library/LibrarySectionListView.swift:178` | toolbar `library/LibraryScreen.kt:1366` | **different/missing F13/F18**; other shared controls match. |

## Reading History section

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Group By state / time | “LibraryHistoryGrouping.allCases” `Features/Library/LibrarySectionListView.swift:640` | “History grouping” `library/LibraryScreen.kt:1612` | **same** local grouping choice. |
| Move abandoned work back to In Progress | “MoveBackToInProgressButton” `Features/Library/LibrarySectionListView.swift:889` | “MoveBackToInProgressButton” `library/LibraryScreen.kt:1577`, callback `:600` | **same**. |
| Remove from History | “Reading it again brings it back” `Features/Library/LibraryWorkSwipeActions.swift:147` | same `library/LibraryScreen.kt:392` | **same** confirmation, reversible by reading again; file stays. |
| Shared filters/select/menus/swipes | “localWorkContextMenu” `Features/Library/LibrarySectionListView.swift:816` | “LibraryWorkMenu” `library/LibraryScreen.kt:1158` | **same** except F06/F13/F18/F25. |

## Favorites — Works

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Switch Works/Authors/Fandoms/Tags | “FavoriteScope.allCases” `Features/Library/LibrarySectionListView.swift:423` | “FavoriteScope.entries” `library/FavoriteAffinityRow.kt:205` | **same** four scopes. |
| All / Rereads / Downloaded / WIP | “FavoriteQuickFilter.allCases” `Features/Library/LibrarySectionListView.swift:459` | “librarySectionQuickFilters” `library/LibrarySectionQuickFilter.kt:13` | **same** local filters. |
| Unfavorite swipe or context menu | “favorite(isFavorite: true)” `Features/Library/LibraryWorkSwipeActions.swift:92` | “Unfavorite” `library/LibraryScreen.kt:1136` | **same** no confirmation, toggle restores star. |
| Shared filters/select/menus/refresh/layout | toolbar `Features/Library/LibrarySectionListView.swift:178` | toolbar `library/LibraryScreen.kt:1366` | **same** available controls, F06/F13/F18/F25 exceptions. |

## Favorites — Authors

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Scope switch and affinity ordering | “ReadingAffinities.Order.allCases” `Features/Library/LibrarySectionListView.swift:429` | “FavoriteSegments” `library/FavoriteAffinityRow.kt:207` | **same**. |
| All / With new work | “FavoriteAuthorFilterRail” `Features/Library/LibrarySectionListView.swift:435` | “FavoriteAuthorQuickFilter” `library/FavoriteAffinityRow.kt:102` (host), rail below `:218` | **same** availability waits for settled author answers; recorded decisions apply to account identity and foreground fetching. |
| Check-again path after incomplete round | “isUnavailable” `Features/Library/LibrarySectionListView.swift:441`; disabled chip/hint `Features/Library/FavoriteAuthorFilterRail.swift:68` | “Switch away and back to retry” `library/FavoriteAffinityRow.kt:243` | **same** disabled status chip explains switching away/back to retry; no dedicated retry button on either app. |
| Open author via chevron/accessibility action | “Open author page” `Features/Library/FavoriteAffinityRow.swift:138` | “Open author page” `library/FavoriteAffinityRow.kt:159` | **same** printed account only. |
| Open newest work | “newestWorkBlock” `Features/Library/FavoriteAffinityRow.swift:84` (background link `:218`) | “Open this work” `library/FavoriteAffinityRow.kt:177` | **same**. |

## Favorites — Fandoms

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Scope and affinity order | “Order.allCases” `Features/Library/LibrarySectionListView.swift:429` | “FavoriteSegments” `library/FavoriteAffinityRow.kt:207` | **same**. |
| Tap fandom to filter Library | “router.filterLibrary” `Features/Library/FavoriteAffinityRow.swift:62` | “libraryDestination…clickable” `library/FavoriteAffinityRow.kt:132`, routing `library/LibraryScreen.kt:591` | **same**; star here is not a toggle on either side. |

## Favorites — Tags

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Scope, affinity order; All / Unread works | “Unread works” `Features/Library/LibrarySectionListView.swift:449` | “onUnread” `library/FavoriteAffinityRow.kt:202`, control `:211` | **same**. |
| Tap additional tag to filter Library | “.additional” `Features/Library/FavoriteAffinityRow.swift:54` | “onFilterLibraryTag” `library/LibraryScreen.kt:596` | **same**, read-only affinity star. |

## Library Filters panel

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Sort by | “Picker(\"Sort by\")” `Features/Library/LibraryFilterPanel.swift:58` | “LibraryChoiceRow(\"Sort by\")” `library/LibraryFilterPanel.kt:122` | **same** available order choices. |
| Rating | “Rating” `Features/Library/LibraryFilterPanel.swift:61` | “Rating” `library/LibraryFilterPanel.kt:124` | **same**. |
| Select/deselect warnings | “toggle(warning…)” `Features/Library/LibraryFilterPanel.swift:69` | “warnings.toggled” `library/LibraryFilterPanel.kt:132` | **same** multiselect. |
| Select/deselect categories | “toggle(category…)” `Features/Library/LibraryFilterPanel.swift:79` | “categories.toggled” `library/LibraryFilterPanel.kt:140` | **same**. |
| Completion / Language | “Completion”, “Language” `Features/Library/LibraryFilterPanel.swift:87`, `:91` | same `library/LibraryFilterPanel.kt:146`, `:155` | **same**, language from library. |
| Word count From / To | “From”, “To” `Features/Library/LibraryFilterPanel.swift:99`, `:103` | same `library/LibraryFilterPanel.kt:163`, `:165` | **same** numeric input. |
| Your Tags / Fandoms / Characters / Relationships / Additional / Exclude | six fields `Features/Library/LibraryFilterPanel.swift:115`–`:127` | six fields `library/LibraryFilterPanel.kt:172`–`:193` | **same** multiselect option sheets, one row per field. |
| Reset filters / Done / dismiss | “Reset filters”, “Done” `Features/Library/LibraryFilterPanel.swift:36`, `:44` | same `library/LibraryFilterPanel.kt:102`, `:115` | **same** live binding, not staged Apply; dismiss keeps selections. |
| Favorites/status/download/collections/text query controls | iOS panel ends at Tags `Features/Library/LibraryFilterPanel.swift:132` | “Status”, “Download”, “Collections”, “Search library” `library/LibraryFilterPanel.kt:197`, `:211`, `:218`, `:223` | **Android only** extra local narrowing controls. |

## Library filter option picker (each of the six tag fields)

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Search options | “Filter \\(title)” `Features/Library/LibraryFilterPanel.swift:291` | “Filter $title” `library/LibraryFilterPanel.kt:329` | **same** normalized matching. |
| Toggle each result | “selection.remove…selection.insert” `Features/Library/LibraryFilterPanel.swift:263` | “selection.toggled” `library/LibraryFilterPanel.kt:339` | **same** immediate multiselect. |
| Done / Back/dismiss | “Done” `Features/Library/LibraryFilterPanel.swift:300` | “Done”, dismiss `library/LibraryFilterPanel.kt:327`, `:316` | **same** keeps choices; neither provides Cancel/undo. Empty/no-match messages have no action besides editing query/dismissing. |

## Filter collision / empty-result card

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Drop one revealing filter | “Without…” `Features/Library/LibraryFilterEmptyState.swift:66` | “Without…” `library/LibraryFilterEmptyState.kt:98` | **same**, applies displayed remaining filters/count. |
| Clear all filters | “Clear all filters” `Features/Library/LibraryFilterEmptyState.swift:97` | same `library/LibraryFilterEmptyState.kt:111` | **same**. |
| Edit filters | “Edit” `Features/Library/LibraryFilterEmptyState.swift:110` | same `library/LibraryFilterEmptyState.kt:114` | **same** opens panel. |

## Library work selection / bulk actions

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Download / Remove Download | “WorkDownload.bulkAction” `UIComponents/WorkBulkActionBar.swift:55` | “Download”, “Remove Download” `library/LibraryScreen.kt:2513`, `:2522` | **same** operations, Android offers separate explicit choices rather than one state-dependent item. |
| Favorite / Unfavorite | “allFavorited…Favorite” `UIComponents/WorkBulkActionBar.swift:68` | “Favorite”, “Unfavorite” `library/LibraryScreen.kt:2514`, `:2521` | **same** set-on/set-off capabilities. |
| Save for Later / remove from Later | “allSavedForLater” `UIComponents/WorkBulkActionBar.swift:74` | “Save for Later”, “Remove from Saved for Later” `library/LibraryScreen.kt:2515`, `:2523` | **same**, unlike scoped selection. |
| Add to Queue / Add to Collection | labels `UIComponents/WorkBulkActionBar.swift:81`, `:86` | labels `library/LibraryScreen.kt:2516`, `:2517` | **different F15/F16** destination picker capability. |
| Tag | “Tag” `UIComponents/WorkBulkActionBar.swift:94` | “Tag” `library/LibraryScreen.kt:2518` | **same** shared tag sheet, below. |
| Mark as Finished / Still Reading | “finished(isFinished: allFinished)” `UIComponents/WorkBulkActionBar.swift:99` | two explicit items `library/LibraryScreen.kt:2519`, `:2524` | **same** batch state effects. |
| Delete selected | “Delete N works?” / “Delete” / “Cancel” `UIComponents/WorkBulkActionBar.swift:128` | same dialog `library/LibraryScreen.kt:376` | **different F04** mandatory on iOS, bypassable by delete setting on Android. Both soft delete/recover 90 days; last-copy warning is present. |
| Exit selection | “Done” `UIComponents/WorkBulkActionBar.swift:118` | “Done” `library/LibraryScreen.kt:2528` | **same**, no additional action/undo. |

## Collections index / collection tiles

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Open collection | “NavigationLink(value: collection)” `Features/Library/LibraryView.swift:548` | “onOpenCollection” `library/CollectionsScreen.kt:185` | **same**. |
| New Collection, including empty state | “New Collection” `Features/Library/LibraryView.swift:714` | “CollectionEditorSheet” `library/CollectionsScreen.kt:107` | **same** full editor on Android's Collections index (dashboard entry is F14). |
| Delete tile / Cancel | “collectionCardMenu” `Features/Library/Collections.swift:811`, prompt `:786` | “Delete Collection” `library/CollectionsScreen.kt:214`, prompt `:120` | **same** moves collection to recovery; works stay. |

## New Collection sheet

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Name / description | “Comfort reads”, “Optional” `Features/Library/NewCollectionSheet.swift:102`, `:107` | same `library/CollectionEditorSheet.kt:179`, `:188` | **same** in full editor. |
| Pick named colour / custom colour | “SubjectHueSwatchRow” `Features/Library/NewCollectionSheet.swift:111` | same `library/CollectionEditorSheet.kt:193` | **same** named swatches and custom colour entry. |
| Keep downloads / Show on Home | “Toggle” for both `Features/Library/NewCollectionSheet.swift:123`, `:127` | both “SubjectToggle” `library/CollectionEditorSheet.kt:227`, `:247` | **same** draft values apply on create. |
| Create / Cancel / dismiss | “Create”, “Cancel” `Features/Library/NewCollectionSheet.swift:84`, `:81` | “Create”/“Save” and “Cancel” `library/CollectionEditorSheet.kt:102`, `:94` | **same**, blank trimmed name disabled; discard drafts on cancel. Dashboard has F14. |

## Collection page

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Tap work or obscured work | “SensitiveWorkRow…openMode: .reader” `Features/Library/Collections.swift:326` | “onOpenReader…else onOpenWork” `library/CollectionDetailScreen.kt:758` | **same** for downloaded work/reveal; **different F06** no-file work goes to details rather than preparing reader. |
| Work context menu | “localWorkContextMenu” `Features/Privacy/MatureContent.swift:231` | “Open Work”, “Read”, “Remove from Collection” `library/CollectionDetailScreen.kt:912` | **missing F12** remaining shared local-menu actions; ordinary three supplied actions are correct. |
| Swipe Remove from collection | “Remove” `Features/Library/Collections.swift:344`, message `:540` | “Remove” `library/CollectionDetailScreen.kt:902`, prompt `:491` | **same** setting-controlled named confirmation, work stays in Library. |
| Add Works (toolbar and empty state) | “Add Works” `Features/Library/Collections.swift:311`, `:427` | “Add Works” `library/CollectionDetailScreen.kt:367`, `:686` | **same**, shared searchable multi-picker, keeps missing copies if collection keeps downloads. |
| Filter, clear, no-match Clear Filters | “LibraryFilterPanel” `Features/Library/Collections.swift:396`; clear `:383` | “Filter Collection”, “Title, author, or fandom” `library/CollectionDetailScreen.kt:562`, `:567`; clear `:734` | **different F10** only text filter; sort, rating, warnings, categories, completion, language, words and six tag scopes missing. |
| Show/Hide mature / all-hidden Show mature | “MatureRevealToggle” `Features/Library/Collections.swift:375`, `:438` | “Show mature” `library/CollectionDetailScreen.kt:388`, `:724` | **same** gated reveal. |
| Select / Select All / Done / scoped action bar | “SelectAllButton”, “ScopedRemovalBulkActionBar” `Features/Library/Collections.swift:402`, `:406` | “Select All”, “ScopedSelectionBar” `library/CollectionDetailScreen.kt:352`, `:779` | **same** selection; see scoped table for F04/F15/F16/F17. |
| Reorder; disabled while filtered/hidden | “Clear Filters to Reorder” / “Show Mature to Reorder” `Features/Library/Collections.swift:454` | same `library/CollectionDetailScreen.kt:421` | **same** entry and guards. |
| Detailed / Ledger | “DisplayModeMenuPicker” `Features/Library/Collections.swift:462` | “Display · Detailed” / “Display · Ledger” `library/CollectionDetailScreen.kt:435` | **same** two layouts. |
| Expand All / Collapse All | “ExpandAllMenuItem” `Features/Library/Collections.swift:464` | layout followed by Rename `library/CollectionDetailScreen.kt:433`, `:449` | **missing F18**. |
| Rename name / Save / Cancel | “Rename Collection” `Features/Library/Collections.swift:520` | same `library/CollectionDetailScreen.kt:526`, `:542`, `:553` | **same**, nonempty trimmed name; no membership change. |
| Details | “Details” `Features/Library/Collections.swift:483` | “Details” `library/CollectionDetailScreen.kt:458` | **different** editor persistence, next table. |
| Delete Collection / Cancel | “Delete Collection” `Features/Library/Collections.swift:491`, helper `:534` | same `library/CollectionDetailScreen.kt:466`, prompt `:481` | **same** single-collection confirmation follows delete preference, explains 90 days/works stay. |
| Pull to refresh | “refresh(visibleWorks…)” `Features/Library/Collections.swift:362` | “works.forEach…ref.refresh(it)” `library/CollectionDetailScreen.kt:641` | **different** Android refreshes every member, including members hidden by current filter/privacy; iOS only visible members. Queue page has same wider refresh (`library/QueuePageScreen.kt:290` vs iOS `Features/Library/ReadingQueueBrowser.swift:469`). Worth narrowing with F13 rather than adding requests unrelated to shown works. |

## Collection Details editor

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Description / colour | “TextField”, “SubjectHueSwatchRow” `Features/Library/Collections.swift:221`, `:233` | “description”, “SubjectHueSwatchRow” `library/CollectionEditorSheet.kt:184`, `:193` | **different** iOS writes through bindings immediately; Android stages until Save. Explicit Save/Cancel makes this visible. |
| Keep downloads / Show on Home | “Toggle” `Features/Library/Collections.swift:241`, `:257` | “SubjectToggle” `library/CollectionEditorSheet.kt:227`, `:247` | **same** resulting behavior after Save; both can fetch missing copies when keep enabled. |
| Done / close | “Done” `Features/Library/Collections.swift:291` | “Save”, “Cancel” `library/CollectionEditorSheet.kt:102`, `:94` | **different** iOS dismissal retains edits; Android Back/Cancel discards staged edits. No undo on iOS; Android Cancel is an explicit discard. |
| Rename field in Details | iOS Details has description/colour/behavior `Features/Library/Collections.swift:218` | “name” `library/CollectionEditorSheet.kt:175` | **Android only**; iOS Rename is separate. |

## Collection Reorder sheet

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Move work | “ordered.move(fromOffsets…)” `Features/Library/NewCollectionSheet.swift:243` | “moveWork(index, index - 1)” and +1 `library/CollectionReorderSheet.kt:200`, `:209` | **same** order can be changed; arrow steps are Android's alternative to drag. |
| Done | “collection.setReadingOrder(ordered)” `Features/Library/NewCollectionSheet.swift:284` | “setCollectionReadingOrder” `library/CollectionReorderSheet.kt:113` | **different** Android initializes “ordered = works” (`:71`) instead of the page's existing saved reading order (`library/CollectionDetailScreen.kt:193`, `:602`). Reopen Reorder and tap Done can overwrite a custom order without moving anything. **F26**, added to priority list. |
| Cancel / Back | “Cancel” `Features/Library/NewCollectionSheet.swift:281` | “Cancel”, “onDismissRequest” `library/CollectionReorderSheet.kt:101`, `:85` | **same**, no writes until Done. |

## Add Works to collection / queue sheet

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Search candidates | “Search your library” `Features/Library/AddLibraryWorksSheet.swift:104` | “Search your library” `library/AddLibraryWorksSheet.kt:112` | **same** normalized library search, excludes already-member and queue-only candidates. |
| Select/deselect several works | selection row `Features/Library/AddLibraryWorksSheet.swift:155` | selected-ID toggle `library/AddLibraryWorksSheet.kt:134` | **same**, ordered add rather than tap-order reorder. |
| Add N works | “confirmationTitle(count…)” `Features/Library/AddLibraryWorksSheet.swift:116` | “confirmationTitle” `library/AddLibraryWorksSheet.kt:158` | **same** commits chosen set, closes; destination handles offline copies. |
| Cancel / dismiss | “Cancel” `Features/Library/AddLibraryWorksSheet.swift:113` | “Cancel” `library/AddLibraryWorksSheet.kt:156` | **same** discards selection. |
| Clear Search when no match | “Clear Search” `Features/Library/AddLibraryWorksSheet.swift:96` | “Clear Search” `library/AddLibraryWorksSheet.kt:120` | **same**. |
| Show mature | “MatureRevealToggle” `Features/Library/AddLibraryWorksSheet.swift:75` | “Show mature” `library/AddLibraryWorksSheet.kt:93` | **same** explicit reveal; Android intentionally does not name blurred candidates (2026-10-11 recorded decision, iOS fault T-392). |

## Add Works candidate byline

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Open candidate's verified author | “dismiss(); router.openAuthorProfile(route)” `Features/Library/AddLibraryWorksSheet.swift:141` | plain “Text(work.author)” `library/AddLibraryWorksSheet.kt:146` | **missing F31**, Android tap belongs to work selection; no author route in picker. |

## Reading Queues organizer / browser entry

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Open queue / switch back to all queues | “AllReadingQueuesDestination” `Features/Library/ReadingQueueOrganizer.swift:542` | “onOpenQueue” `library/QueueOrganizerScreen.kt:255`; browser `library/ReadingQueueBrowserScreen.kt:55` | **same** Android Back replaces iPad/Mac sidebar switching; iPhone's removed bottom switcher is not missing. |
| Search queues/tags/works, clear text | “Search queues, tags and works” `Features/Library/ReadingQueueOrganizer.swift:156` | same `library/QueueOrganizerScreen.kt:198` | **same**, hidden-work matching constrained by privacy. |
| All / tag filter chips / clear search+filters empty state | chip `Features/Library/ReadingQueueOrganizer.swift:194`; “Clear Search and Filters” `:298` | tag rail `library/QueueOrganizerScreen.kt:206`; same clear `:244` | **same**. |
| New Queue | “New Queue” `Features/Library/ReadingQueueOrganizer.swift:378` | same `library/QueueOrganizerScreen.kt:366` | **same** full New Queue editor. |
| Select queue / Done | “Select”, “SelectAllButton” `Features/Library/ReadingQueueOrganizer.swift:386`, `:361` | “Select” `library/QueueOrganizerScreen.kt:378`; select-all toolbar `:156` | **same** ordinary row selection/Done; **missing F30** Select All/Deselect All. Android toolbar `library/QueueOrganizerScreen.kt:358` offers only Pin, Tag, Delete, Done; no select-all callback is supplied. |
| Bulk Pin / Unpin | “pins ? Pin : Unpin” `Features/Library/ReadingQueueOrganizer.swift:411` | “pinLabel” `library/QueueOrganizerScreen.kt:162`, action `:171` | **same** targets whole selection. |
| Bulk Tag | “Tag” `Features/Library/ReadingQueueOrganizer.swift:418` | “Tag” `library/QueueOrganizerScreen.kt:360` | **same** tri-state queue tag sheet. |
| Bulk/single Delete custom queues | “deletable(queues)” `Features/Library/ReadingQueueOrganizer.swift:423`; “Delete”/“Cancel” `:346` | “deletable(chosen)” `library/QueueOrganizerScreen.kt:179`, dialog `:317` | **same** confirmation, preserves queue/members for recovery; built-in Saved for Later excluded. |
| Row Edit / Pin-Unpin / Delete | “queueSwipes” `Features/Library/ReadingQueueOrganizer.swift:453`, “QueueCardMenu” `:268` | “OrganizerRow” callbacks `library/QueueOrganizerScreen.kt:257`, `:258`, `:264` | **same** custom edit/delete and pin actions. |
| Reorder custom queues, guard while filtering | “Clear Filters to Reorder” `Features/Library/ReadingQueueOrganizer.swift:392`, “onMove” `:288` | same label `library/QueueOrganizerScreen.kt:380`; step `:286` | **same** effective order action, Android arrow steps. Exit reorder is Back on Android, Done on iOS (`:372`), an Android chrome difference. |

## New Queue / Edit Queue sheet

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Name | “Case fic pile” `Features/Library/NewReadingQueueSheet.swift:218` | “Case fic pile” `library/QueueEditorSheet.kt:174` | **same** trimmed nonempty validation. |
| Swatch/custom colour | “SubjectHueSwatchRow” `Features/Library/NewReadingQueueSheet.swift:104` | same `library/QueueEditorSheet.kt:178` | **same**. |
| Toggle known tags / New tag / Add / Cancel | “New tag”, “Add”, “Cancel” `Features/Library/NewReadingQueueSheet.swift:162`; tag row `:178` | “+ New tag” `library/QueueEditorSheet.kt:294`, dialog `:239` | **same** staged draft tags. |
| Keep works offline | “Keep works offline” `Features/Library/NewReadingQueueSheet.swift:238` | same `library/QueueEditorSheet.kt:199` | **same**. |
| Start Empty / Saved for Later (new queue only) | start buttons `Features/Library/NewReadingQueueSheet.swift:261` | “Empty”, “Saved for Later” `library/QueueEditorSheet.kt:215`, `:222` | **same** optional seed and availability; editing omits seed choice. |
| Create / Save / Cancel | “isEditing ? Save : Create”, “Cancel” `Features/Library/NewReadingQueueSheet.swift:143`, `:140` | same `library/QueueEditorSheet.kt:118`, `:110` | **same** draft committed once, cancelled sheet leaves queue unchanged. New Queue description intentionally edited on Details, per 2026-10-14 decision. |

## Queue page — custom queue / Saved for Later browser

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Tap Up Next / In Line; reveal obscured | “LocalWorkDestination.reader” `Features/Library/ReadingQueueBrowser.swift:723`; sensitive row `:629` | “activate(work)” `library/QueuePageScreen.kt:218` | **same** with a local EPUB; no-file open goes to details (F06). |
| Per-work long press/context actions | “localWorkContextMenu” `Features/Library/ReadingQueueBrowser.swift:645`, `:727` | “clickable(onClick = onClick)” `library/QueuePageScreen.kt:639`; covers `:390` | **missing F11** full shared menu, including Remove from Queue. Must enter Select to remove even one on Android. |
| List row swipes | “ledgerRow” `Features/Library/ReadingQueueBrowser.swift:527` → shared list actions | “QueueLedgerCard” `library/QueuePageScreen.kt:628` with only click/step | **missing F11** local work swipe actions. |
| All / Unread / Offline / WIP quick filters | “QueueHeaderDetails…quickFilter” `Features/Library/ReadingQueueBrowser.swift:573` | “QueueHeaderDetails…onQuickFilter” `library/QueuePageScreen.kt:315` | **same** state filters; see actual enum labels in `ReadingQueuePageParts.swift` and `ReadingQueueFacts.kt`. |
| Add tag to queue | “onAddTag” `Features/Library/ReadingQueueBrowser.swift:579` | “onAddTag” `library/QueuePageScreen.kt:322` | **same** queue tag sheet. |
| Add Works toolbar / empty-state button | “Add Works” `Features/Library/ReadingQueueBrowser.swift:457`, `:829` | toolbar “Add Works” `library/QueuePageScreen.kt:573`; empty state “action = null” `:330` | **different** toolbar works; empty-state Add Works action itself **missing**. F11 includes this discoverability gap. |
| Filter / clear; Reset / dismiss | “LibraryFilterPanel” `Features/Library/ReadingQueueBrowser.swift:340` | “FilterDialog” `library/QueuePageScreen.kt:654` | **missing F10** most facets and sort. Android Done applies staged title/rating/Complete, Cancel discards; iOS filters apply live. |
| All-hidden no-match recovery | “No matching works” / “Clear Filters” `Features/Library/ReadingQueueBrowser.swift:478` | same `library/QueuePageScreen.kt:333` | **same** shared limitation: Clear Filters cannot reveal privacy-hidden members; More → Show mature remains available on both. Not an Android regression. |
| Show/Hide mature | “MatureRevealToggle” `Features/Library/ReadingQueueBrowser.swift:774` | “Show mature” `library/QueuePageScreen.kt:586` | **same** gate. |
| Select / Select All / Done / scoped bar | “ScopedRemovalBulkActionBar” `Features/Library/ReadingQueueBrowser.swift:838` | “ScopedSelectionBar” `library/QueuePageScreen.kt:425` | **same** entry/set handling; scoped differences below. |
| Reorder + Move Up/Down/Top/Bottom | “Move Up…Move to Bottom” `Features/Library/ReadingQueueBrowser.swift:716` | “onStep(delta)” `library/QueuePageScreen.kt:351` | **same** effective manual ordering through repeated steps; direct Top/Bottom shortcuts **missing** on Android. Reorder correctly gated when narrowed/hidden. |
| Layout Compact / Ledger / Detailed + Expand All | “DisplayModeMenuPicker”, “ExpandAllMenuItem” `Features/Library/ReadingQueueBrowser.swift:792`, `:794` | “Display · Compact” / “Display · List” `library/QueuePageScreen.kt:604` | **missing F18** Detailed/expansion; two other presentations remain. |
| Queue Details / Edit Queue / Delete Queue | labels `Features/Library/ReadingQueueBrowser.swift:855`, `:861`, `:866` | same `library/QueuePageScreen.kt:607`–`:610` | **same** custom-only edit/delete; Delete/Cancel confirmation explains 90 days/works stay, both. |
| Pull to refresh | “refreshable” `Features/Library/ReadingQueueBrowser.swift:469` | “refresh.refresh(work)” `library/QueuePageScreen.kt:290` | **different** refresh scope is all members on Android, visible members on iOS (F13). |

## Queue Details screen

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Edit description, including leave without focus change | “set…queue.notes = newValue” `Features/Library/ReadingQueueSettingsView.swift:78` | “onValueChange” `library/QueueSettingsScreen.kt:185` | **same** write as typed; 2026-10-14 fix is present. |
| Remove tag chip / Add tag | “Remove…”, “Add tag” `Features/Library/ReadingQueueSettingsView.swift:98`, `:107` | chip `library/QueueSettingsScreen.kt:230`, “Add tag” `:239` | **same**, removes queue relationship only; add opens shared tag sheet. |
| Change named Colour / From queue name | “From queue name” `Features/Library/ReadingQueueSettingsView.swift:202` | same `library/QueueSettingsScreen.kt:270` | **same**, immediate writes. |
| Keep works offline on/off | “Keep works offline” `Features/Library/ReadingQueueSettingsView.swift:217` | same `library/QueueSettingsScreen.kt:283` → `library/ReadingQueueRepository.kt:350` | **same**, enabling preserves missing works. |
| Manage all tags | “Manage all tags” `Features/Library/ReadingQueueSettingsView.swift:243` | same `library/QueueSettingsScreen.kt:309` | **same** manager screen. |
| Done/Back | ordinary navigation `Features/Library/ReadingQueueSettingsView.swift:117` | “Done” `library/QueueSettingsScreen.kt:136` | **same** leave with live changes retained; Done is extra Android chrome. |

## Shared queue-tag / bulk-work-tag sheet

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| New tag text / Add | “New tag” / “Add” `Features/Library/QueueTagSheet.swift:132`, `:135`; work version `UIComponents/WorkBulkTagSheet.swift:32` | “New tag” / “Add” `library/QueueTags.kt:194`, `:210` | **same**, adds to selected queues/works immediately. |
| Toggle each tag: all / some / none | queue coverage rows `Features/Library/QueueTagSheet.swift:152`; work “some” `UIComponents/WorkBulkTagSheet.swift:82` | “TagCoverage.All/Some/None” `library/QueueTags.kt:60`, row `:220` | **same**, partial coverage adds to remaining items; all removes from all. |
| Done / dismiss | “Done” `Features/Library/QueueTagSheet.swift:97`, `UIComponents/WorkBulkTagSheet.swift:65` | “Done” `library/QueueTags.kt:178` | **same**, no rollback; toggles are reversible. |

## Queue tag manager

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Add new tag / Add | “New tag”, “Add” `Features/Library/QueueTagManagerView.swift:232`, `:238` | “New tag”, “Add” `library/QueueTags.kt:341`, `:357` | **same**, queue vocabulary. |
| Rename / Merge into… | both set “editing = tag” `Features/Library/QueueTagManagerView.swift:181`, `:186` | same editor destinations `library/QueueTags.kt:455`, `:456` | **same** opens Edit tag. |
| Show only this tag | “onShowOnlyTag(tag)” `Features/Library/QueueTagManagerView.swift:193` | “TagAction.Show” `library/QueueTags.kt:457` | **same**, closes manager/details and filters queue. |
| Copy tag to another queue | “copy(tag, to: destination)” `Features/Library/QueueTagManagerView.swift:199` | “Copy tag to another queue” picker `library/QueueTags.kt:376` | **same** destination queue tag, not copied works; no-other-queues disabled/empty choice. |
| Remove from N works / Cancel | “Remove from…works” `Features/Library/QueueTagManagerView.swift:210`, prompt `:106` | same `library/QueueTags.kt:460`, prompt `:401` | **same** explicit confirmation; scope limited to this queue's works/tag, no undo. |

## Edit tag sheet

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Name / Save / Cancel | “Name”, “Save”, “Cancel” `Features/Library/QueueTagManagerView.swift:360`, `:409`, `:406` | same `library/QueueTags.kt:516`, `:560`, `:562` | **same** global rename for fresh name. Collision behavior is **different, recorded**: Android merges on rename into existing exact-name tag (`:519`); iOS disables conflicting Save (`:410`). 2026-10-15 3fi explicitly records colliding renames merging everywhere. |
| Merge target / Merge / Cancel | “Merge…” prompt `Features/Library/QueueTagManagerView.swift:428` | same `library/QueueTags.kt:567` | **same** queue-scoped merge after confirmation; Android confirmation shortens scope explanation to “You can't undo this in Kudos.” |
| Remove from this queue / N works from inside editor | “Remove tag from…” `Features/Library/QueueTagManagerView.swift:383`, confirm `:413` | editor ends after Name and Merge `library/QueueTags.kt:511`–`:563` | **missing** inside editor; same operation is reachable by returning to manager's Remove menu. Lower priority discoverability gap, **F27**. |

## Scoped work selection (queue / collection)

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Download missing copies | “bulkDownload” `UIComponents/ScopedRemovalBulkActionBar.swift:257` | “downloadMissing” `library/ScopedSelectionBar.kt:111` | **same** missing-copy operation, sequential downloads through shared queue on Android. |
| Download / Remove Download keep state | “WorkDownload.bulkAction” `UIComponents/ScopedRemovalBulkActionBar.swift:193` | “allDownloaded…Remove Download” `library/ScopedSelectionBar.kt:156` | **same** ordinary set/unset, protected works handled by semantics. |
| Favorite / Unfavorite | “allFavorited” `UIComponents/ScopedRemovalBulkActionBar.swift:204` | “allFavorited” `library/ScopedSelectionBar.kt:159` | **same** effect; iOS calls on-state “Favorited”. |
| Save for Later / remove Later | “allSavedForLater” `UIComponents/ScopedRemovalBulkActionBar.swift:210` | “Save for Later” `library/ScopedSelectionBar.kt:163` | **missing F17** remove counterpart. |
| Add to Queue / Collection | labels `UIComponents/ScopedRemovalBulkActionBar.swift:217`, `:222` | same `library/ScopedSelectionBar.kt:166`, `:168` | **different F15/F16** reduced bulk destination dialogs. |
| Move to Queue | “startMove” `UIComponents/ScopedRemovalBulkActionBar.swift:235` | “movingToQueue” `library/ScopedSelectionBar.kt:218` | **same** add destination then leave source; Cancel leaves source alone. Android intentionally handles already-member destination explicitly (2026-10-11 3ck decision). |
| Tag | “showingTagSheet = true” `UIComponents/ScopedRemovalBulkActionBar.swift:76` | “tagging = true” `library/ScopedSelectionBar.kt:171` | **same** tri-state tags. |
| Finished / Still Reading | “finishedAction” `UIComponents/ScopedRemovalBulkActionBar.swift:226` | “finishedActionLabel(allFinished)” `library/ScopedSelectionBar.kt:174` | **same**. |
| Remove from current queue / collection | “Remove N works?” `UIComponents/ScopedRemovalBulkActionBar.swift:130` | same `library/ScopedSelectionBar.kt:192` | **same** queue confirmation always asks and preserves works. Collection overrides with its own preference-controlled prompt (`library/CollectionDetailScreen.kt:505`): **different F04**. |
| Done | “Done” `UIComponents/ScopedRemovalBulkActionBar.swift:108` | “Done” `library/ScopedSelectionBar.kt:184`; queue toolbar `library/QueuePageScreen.kt:570` | **same**, exits selection. |

## Add to Queue membership picker

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Create queue by name + Add | “New queue”, “Add” `Features/Library/ReadingQueues.swift:467`, `:469` | Work Detail “New queue”, “Add” `works/detail/WorkDetailForms.kt:214`, `:215` | **same** Work Detail creation; **missing F15** Library/general bulk pickers (`library/WorkMembershipDialogs.kt:53`, `ui/components/WorkBulkActionBar.kt:265`) have no creation field. |
| Tap existing queue / checked member | “toggle(queue)” `Features/Library/ReadingQueues.swift:477`, removes member `:666` | Work Detail “selected queues stay selected” `works/WorkDetailScreen.kt:922`; other pickers “onAdd(queue.id)” `library/WorkMembershipDialogs.kt:67` | **different** Work Detail is deliberately additive per brief `3bn-work-detail-series-and-bookmark.md:75` (“nothing here may remove…a queue membership”). Recorded scope restriction, not a new fix request. **missing F15** removal/check-state in other pickers; returning from Add never removes on Android. |
| Select multiple queues without closing | iOS form stays open after `toggle` `Features/Library/ReadingQueues.swift:477` | Work Detail “selectedQueueIds + queue.id” `works/WorkDetailScreen.kt:490`; Library closes `library/LibraryScreen.kt:493` | **different F15** Library/bulk close after one destination, must reopen for another. Work Detail stays open correctly. |
| Also add works from series | “Also add works from this AO3 series” `Features/Library/ReadingQueues.swift:503` | same `works/detail/WorkDetailForms.kt:230` | **same** Work Detail only; **missing F15** Library's single-work picker has no series controls. Bulk iOS picker offers series only for one work, so no claim that multi-work series is missing. |
| Add Series to Selected Queues / cancel running addition | “Add Series…” / “Cancel Series Addition” `Features/Library/ReadingQueues.swift:522`, `:533` | same `works/detail/WorkDetailForms.kt:243`, `:245` | **same** explicit action after preview, progress/result messages, cancellable. Restricted-work skip is owner-directed (3bn), not a finding. |
| Done / close | “Done” `Features/Library/ReadingQueues.swift:560` | Work Detail “Done” `works/detail/WorkDetailForms.kt:212`; generic “Close” `library/WorkMembershipDialogs.kt:77` | **same** dismisses; live adds stay. Generic Library additionally offers “Manage queues” (`:80`): **Android only** useful alternate route. |

## Add to Collection membership picker

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| New collection name / Add | “New collection”, “Add” `Features/Library/Collections.swift:624`, `:626` | “New collection”, “Add” `library/WorkMembershipDialogs.kt:129`, `:148`; Work Detail `works/WorkDetailScreen.kt:711`, `:741` | **same** creates/attaches single work; bulk also can create/attach. |
| Toggle each collection / checked membership | “toggle(collection)” / “In this collection” `Features/Library/Collections.swift:640`, `:651` | “toggleable…memberIds” `library/WorkMembershipDialogs.kt:170`; Work Detail toggle `works/WorkDetailScreen.kt:764` | **same** single-work picker, including removal without deleting work. |
| Toggle selected batch membership | same `Features/Library/Collections.swift:640` over `works` | “add(col.name)” `ui/components/WorkBulkActionBar.kt:337`; `library/LibraryScreen.kt:352` | **missing F16** removal/check state; Android bulk picker is only additive. |
| Done / dismiss | “Done” `Features/Library/Collections.swift:671` | “Done” `library/WorkMembershipDialogs.kt:203`, Work Detail `works/WorkDetailScreen.kt:824` | **same** single picker retains live changes; bulk closes after add instead of allowing repeated toggles. |

## Queue Storage (iOS screen lives in Library/ReadingQueues.swift)

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Keep Download for un-kept preserved work | “Keep Download” `Features/Library/ReadingQueues.swift:312`, `:322` | “Keep Download” `settings/QueueStorageScreen.kt:263` | **same**, protects copy after queues are removed. |
| Remove from Reading Queues | “Remove from Reading Queues” `Features/Library/ReadingQueues.swift:328` | same `settings/QueueStorageScreen.kt:272` | **same** effect; last queue-only entry may soft-delete, saved/favorited entry retained. |
| Confirm removal / Cancel | “Remove from reading queues?” `Features/Library/ReadingQueues.swift:347`, “Cancel” `:361` | confirmation `settings/QueueStorageScreen.kt:156`, “confirmBeforeDelete” `:170` | **different F04** Android may skip mandatory iOS confirmation. Both distinguish “Remove Queues & Delete” from simple queue removal. No immediate undo; recovery for soft-deleted work. |

## Recently Deleted — deleted works, collections, queues; finished un-kept copies

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Restore single item via swipe/menu | “onRestore” `Features/Library/RecentlyDeletedView.swift:632`, `:638` | “viewModel.restore(entry)” `library/RecentlyDeletedScreen.kt:568`, `:610` | **same** restores deletion or keeps held finished copy; no confirmation; failure says “Couldn't Restore”. |
| Delete Permanently / Remove Copy single | “entry.deleteLabel” `Features/Library/RecentlyDeletedView.swift:97` | “entry.deleteLabel” `library/RecentlyDeletedScreen.kt:736` | **same** always asks; real title and file/place/highlight/bookmark counts composed at `:427`, then permanent delete; held-copy removal leaves history. No undo. |
| Select / row toggle / Select-Deselect All | “Select”, “SelectAllButton” `Features/Library/RecentlyDeletedView.swift:159`, `:146` | “Select”, “Select All” `library/RecentlyDeletedScreen.kt:406`, `:391` | **same**, both sections selectable. |
| Restore selected | “Self.restore(chosen…)” `Features/Library/RecentlyDeletedView.swift:171` | “bulkRestore(chosen)” `library/RecentlyDeletedScreen.kt:669` | **same**, reports failed restores, exits select. |
| Delete selected permanently / Cancel | “Delete Permanently” `Features/Library/RecentlyDeletedView.swift:128` | same `library/RecentlyDeletedScreen.kt:803` | **same** always confirmed, count captured with selection, no undo; warns progress/notes/downloads lost, AO3 unaffected. |
| Done | “Done” `Features/Library/RecentlyDeletedView.swift:191` | same `library/RecentlyDeletedScreen.kt:710` | **same** exits select. |
| Delete All Permanently / Cancel | “Delete All Permanently” `Features/Library/RecentlyDeletedView.swift:109` | same `library/RecentlyDeletedScreen.kt:773` | **same** always-confirmed count/title and irreversible warning; includes held copies. Existing live-work safeguards from 3fh remain (`:269` uses `onlyIfStillDeleted`). |
| Dismiss restore-failure message | “Couldn't Restore”, “OK” `Features/Library/RecentlyDeletedView.swift:243`, `:250` | “Couldn't Restore” `library/RecentlyDeletedScreen.kt:817` | **same** acknowledge failure; not a false success. |

## Reading Insights

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Period: This month / This year | “Picker(\"Period\")”, titles `Features/Library/ReadingInsightsView.swift:111`, `:44` | “Period”, period entries `library/ReadingStatisticsScreen.kt:204`, `:213` | **same** local period choice. |
| Pull to refresh | “reload()” `Features/Library/ReadingInsightsView.swift:118` | “viewModel.refresh()” `library/ReadingStatisticsScreen.kt:233` | **same**, local statistics reload. Other charts/figures/empty states here are read-only, not invented actions. |

## Work Detail — main page and overflow

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Read / Continue Reading | “read” `Features/WorkDetail/WorkDetailView.swift:288`, handler `:1044` | “onResumeClick” `works/WorkDetailScreen.kt:1181` | **different F06/F07** absent-file fetch does not auto-open and keeps a download; opening from existing reader duplicates it. Ordinary available-copy launch is correct. |
| Favorite / Unfavorite toolbar | “Favorite” `Features/WorkDetail/WorkDetailView.swift:441` | “onToggleFavorite” `works/WorkDetailScreen.kt:1066`, toolbar `:1247` | **same**, creates a local record when needed. |
| Expand/collapse summary | “Show More” / “Show Less” `Features/WorkDetail/WorkDetailOverviewSections.swift:61` | same `works/detail/WorkDetailSections.kt:96` | **same** action. Collapse threshold is 600 characters on Android (`:76`), iOS uses `summaryCollapses`; no visual claim made. |
| Open linked author | “WorkDetailIdentityHeader” `Features/WorkDetail/WorkDetailView.swift:248` → author navigation | “isLinked = state::hasAccount” `works/WorkDetailScreen.kt:1495` | **same** only names AO3 linked to accounts; no guessed imported-author route (3do fix present). |
| Tap AO3 tags (Warnings/Fandoms/Relationships/Characters/Additional) | “router.searchAO3(group.field, tag)” `Features/WorkDetail/WorkDetailSections.swift:94` | “searchTag(cluster.field, tag)” `works/detail/WorkDetailSections.kt:248` | **same** AO3 search by typed field/tag. |
| Add to Queue / Add to Collection menu | labels `Features/WorkDetail/WorkDetailOverviewSections.swift:108`, `:114` | “onAddToQueue”, “onAddToCollection” `works/WorkDetailScreen.kt:1280`, `:1288` | **same** entry; full picker tables apply, Work Detail queue removal is recorded additive-only. |
| Save for Later / Remove from Later | “WorkActionLabels.savedForLater” `Features/WorkDetail/WorkDetailOverviewSections.swift:118` | “Remove from Later” / “Save for Later” `works/WorkDetailScreen.kt:1293` | **same** local Later toggle, series prompt below. Removal notice “Removed from Saved for Later.” (`:248`); not an AO3 unmark. |
| Download / Remove Download / Kept Offline by… | “WorkDownload.label” `Features/WorkDetail/WorkDetailOverviewSections.swift:125` | “WorkDownloadSemantics.action” `works/WorkDetailScreen.kt:1302` | **same** ordinary AO3 work semantics; protected informational item disabled. Imported work's fallback Download menu row remains visible but no-ops (`:1309`–`:1318`), and iOS also has a fallback menu label but no operation when `WorkDownload.action` is nil (`Features/WorkDetail/WorkDetailView.swift:823`). This inert imported-work row is shared behavior, not a new Android-only finding. |
| Share | “ShareLink(item: ao3URL)” `Features/WorkDetail/WorkDetailOverviewSections.swift:133` | “shareWork” `works/WorkDetailScreen.kt:1327` | **same** native URL sharing for AO3 source. |
| Open on AO3 (menu and page button) | “router.open(ao3URL)” `Features/WorkDetail/WorkDetailOverviewSections.swift:137`; page `Features/WorkDetail/WorkDetailFactsSections.swift:193` | “onOpenAo3” `works/WorkDetailScreen.kt:1089`, menu `:1331`, page `works/detail/WorkDetailSections.kt:491` | **same** canonical AO3 route (via app URI routing). Android offers the same label for any nonblank source URL, including an external imported source: **different wording**, grouped with F25; “Open Source” would describe that destination. |
| Mark as Finished / Still Reading | “WorkDetailOutlineButton” `Features/WorkDetail/WorkDetailFactsSections.swift:186` | “finishedActionLabel” `works/detail/WorkDetailSections.kt:484` | **same** lifecycle toggle, no confirm/undo; can toggle back. |
| Comments count / All comments / menu Comments | “startViewingComments” `Features/WorkDetail/WorkDetailFactsSections.swift:153`; route `Features/WorkDetail/WorkDetailSections.swift:160` | “onComments” `works/WorkDetailScreen.kt:1617`, `:1626`, `:1350` | **same** ordinary work discussion entry. |
| Chapter comments | “focusesChapter: true” `Features/WorkDetail/WorkDetailSections.swift:169` | “onChapterComments = onComments” `works/WorkDetailScreen.kt:1627` | **different F08** loses focused chapter-picker entry. Android additionally shows row for `1/1` (`works/detail/WorkDetailSections.kt:413`); iOS excludes known one-chapter works. |
| Write a comment | “composes: true” `Features/WorkDetail/WorkDetailSections.swift:179` | “onWriteComment = onComments” `works/WorkDetailScreen.kt:1628` | **different F08**, no initial composer. Signed-out iOS does not auto-compose either; finding concerns signed-in flow. |
| Give Kudos / Subscribe-Unsubscribe / Bookmark / Mark for Later | “AO3WorkActionsMenu” `Features/WorkDetail/WorkDetailView.swift:457` | four menu writes `works/WorkDetailScreen.kt:1341`–`:1380` | **same** actions through native write repository; detail below. |
| Pull to refresh / refresh failure Try Again | “Try Again” `Features/WorkDetail/WorkDetailView.swift:350`, “refreshDetails” handler | “onRefreshMetadata” `works/WorkDetailScreen.kt:1105`, pull `:1472` | **different F13** requires local work on Android; a remote-only page cannot refresh. Result of `WorkMetadataRefresh.refresh` discarded, followed by `refreshLocal` clearing error (`:1108`–`:1113`, `:225`), so failed refresh lacks iOS's error/Try Again. |
| Open series from facts / View Full Series on AO3 | “router.open(url)” `Features/WorkDetail/WorkDetailOverviewSections.swift:209` | “onOpenSeries(seriesUrl)” `works/detail/WorkDetailSections.kt:307`, handler `works/WorkDetailScreen.kt:1654` | **same** full-series destination; native Android route rather than browser chrome is acceptable. |
| Open/reveal a local series sibling | “ForEach(seriesWorks)” `Features/WorkDetail/WorkDetailOverviewSections.swift:156` | “WorkDetailSeriesSection” receives no local works `works/WorkDetailScreen.kt:1648` | **missing F20** individual sibling links. |
| Download Whole Series | “Download Whole Series” `Features/WorkDetail/WorkDetailOverviewSections.swift:198` | “onDownloadSeries” `works/WorkDetailScreen.kt:1653`, menu “Download series” `:1429` | **same** explicit series download; progress/message on page. Android also offers it before a local anchor exists: **Android only** broader availability; no claim of confirmation absent on iOS. |
| My copy / Close | “showingMyCopy” `Features/WorkDetail/WorkDetailView.swift:417` | “onOpenMyCopy” `works/WorkDetailScreen.kt:1662` | **same** local sheet. |
| Rebuild / Refresh Metadata / Log in / Redownload EPUB menu extras | iOS local menu ends at “Open on AO3” `Features/WorkDetail/WorkDetailOverviewSections.swift:142` | labels `works/WorkDetailScreen.kt:1387`, `:1398`, `:1408`, `:1417` | **Android only** additional menu routes. Rebuild has F05. Redownload explicitly re-fetches; unlike Delete EPUB it does not intentionally delete first. |
| Delete EPUB | iOS menu uses “WorkDownload” keep semantics `Features/WorkDetail/WorkDetailOverviewSections.swift:125` | “Delete EPUB” `works/WorkDetailScreen.kt:1441` | **different/Android only F01**, immediate file deletion with no confirm, restore or warning; plain imported EPUB has no original archive (`works/WorkImporter.kt:297`). |
| Remove from Library | iOS main detail menu contains no Delete `Features/WorkDetail/WorkDetailOverviewSections.swift:104`–`:142`; shared card Delete `Features/Library/WorkCardActions.swift:443` | “Remove from Library” `works/WorkDetailScreen.kt:1453`, dialog `:623` | **Android only** useful soft-delete entry, honors confirmation preference and recovery; imported-work page dismisses after deletion (`:239`), correct. |

## My copy sheet and Downloaded date editor

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Download status / Saved for Later / Finished toggle | “myCopyToggleRow”, “savedForLaterRow” `Features/WorkDetail/WorkDetailSections.swift:240`, `:242`, `:254` | three toggle rows `works/detail/WorkDetailMyCopySheet.kt:348`, `:356`, `:364` | **same** local status operations; Download absent/informational for protected import as appropriate. |
| Retry Queue Preservation after failed/missing file | “Retry Queue Preservation” `Features/WorkDetail/WorkDetailSections.swift:248` | status section only download/Later/Finished `works/detail/WorkDetailMyCopySheet.kt:318` | **missing F19** targeted retry. |
| Add to queue / Add to collection | “Add to queue”, “Add to collection” `Features/WorkDetail/WorkDetailSections.swift:356`, `:401` | same `works/detail/WorkDetailMyCopySheet.kt:388`, `:421` | **same** shared membership pickers; displayed existing membership lines are not buttons on either app. |
| Tap Downloaded date / pick date / Save / Cancel | “showingDownloadedDateEditor” `Features/WorkDetail/WorkDetailSections.swift:444`; editor `:585`, `:593`, `:596` | “onEditDownloadedAt” `works/detail/WorkDetailMyCopySheet.kt:474`, editor `:280`, dialog `:518` | **same** date-only past/current selection writes on Save. |
| New local tag / Add | “Add a tag”, “Add” `Features/WorkDetail/WorkDetailSections.swift:504`, `:507` | same `works/detail/WorkDetailMyCopySheet.kt:703`, `:709` | **same** add; iOS also submits with keyboard Return, touch equivalent already present. |
| Tap suggested tag | “apply(named: name)” `Features/WorkDetail/WorkDetailSections.swift:520` | “onSuggestTag(suggestion)” `works/detail/WorkDetailMyCopySheet.kt:733` | **same** adds suggested local tag. |
| Remove local tag | “removeTag(tag)” `Features/WorkDetail/WorkDetailSections.swift:547` | “Remove tag $name” `works/detail/WorkDetailMyCopySheet.kt:779` | **same**, no confirm, can add again. |
| Tap local tag name to filter Library | “filterLibrary(.userTag…)” `Features/WorkDetail/WorkDetailSections.swift:542` | plain “Text(name)” `works/detail/WorkDetailMyCopySheet.kt:765` | **missing F19**. |
| Select/copy original source URL | “textSelection(.enabled)” `Features/WorkDetail/WorkProvenanceSections.swift:60` | “SelectionContainer” `works/detail/WorkDetailMyCopySheet.kt:569` | **same** selectable provenance source. |
| Rebuild from Original / cancel confirm / dismiss error | “Rebuild this work?” / “Couldn't Rebuild” `Features/WorkDetail/WorkProvenanceSections.swift:137`, `:150` | “Rebuild from Original” `works/detail/WorkDetailMyCopySheet.kt:610`, callback `works/WorkDetailScreen.kt:1045` | **different F05** no redundant confirmation/error; Android also omits post-success “Rebuilt with the current converter” (`Features/WorkDetail/WorkProvenanceSections.swift:97`). |
| Close sheet | “Close” `Features/WorkDetail/WorkDetailView.swift:426` | “Close” `works/detail/WorkDetailMyCopySheet.kt:179` | **same**, immediate local changes retained. |

## AO3 work actions (menu and signed-in chips)

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Give Kudos | “Give Kudos” `Features/WorkDetail/AO3WorkActionsMenu.swift:25` | “Give Kudos” `works/WorkDetailScreen.kt:1342`, callback `:1117` | **same** one explicit native write; result message. Reader remembers given state separately. No confirm/undo. |
| Subscribe / Unsubscribe | labels `Features/WorkDetail/AO3WorkActionsMenu.swift:52`, `:54` | labels `works/WorkDetailScreen.kt:1374`, callback `:1133` | **same** work subscription toggle; successful subscribe fetches missing copy only if configured and already local (`Features/WorkDetail/WorkDetailView.swift:1084`; Android `works/WorkDetailScreen.kt:565`). Neither work menu asks an unsubscribe confirm here; do not import account-list behavior. |
| Mark for Later on AO3 | “Mark for Later” `Features/WorkDetail/AO3WorkActionsMenu.swift:44` | “Mark for Later (AO3)” `works/WorkDetailScreen.kt:1365` | **same** AO3 write, distinct from device Saved for Later. |
| Open Bookmark/Edit Bookmark form | “startBookmark()” `Features/WorkDetail/AO3WorkActionsMenu.swift:36` | “onBookmark” `works/WorkDetailScreen.kt:1159` | **same** seeds known private/rec/notes/tags; opening does not itself write. |
| Comments / Open on AO3 | labels `Features/WorkDetail/AO3WorkActionsMenu.swift:33`, `:61` | labels `works/WorkDetailScreen.kt:1350`, `:1331` | **same**. |
| Signed-out access, errors, acknowledgment | AO3 alert “OK” `Features/WorkDetail/AO3WorkActionsModel.swift:174`; chip gating `Features/WorkDetail/WorkDetailOverviewSections.swift:84` | page message via “handleWriteResult” `works/WorkDetailScreen.kt:557`; chip host `:1570` | **different presentation only** alerts vs inline messages; native errors still surface. No live request made to verify remote outcomes. |

## Bookmark on AO3 form

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Edit Notes / comma-separated Tags | “Notes”, “Comma-separated tags” `Features/WorkDetail/AO3WorkActionsModel.swift:198`, `:206` | same `works/detail/WorkDetailForms.kt:140`, `:145` | **same** seeded input, no artificial local length cap. |
| Private / Recommend | toggles `Features/WorkDetail/AO3WorkActionsModel.swift:214`, `:215` | same `works/detail/WorkDetailForms.kt:149`, `:151` | **same**. |
| Save / Cancel | “Save”, “Cancel” `Features/WorkDetail/AO3WorkActionsModel.swift:240`, `:234` | “Save”, “Cancel” `works/detail/WorkDetailForms.kt:136`, `:133` | **same** explicit write; busy state blocks leaving and editing text; failed Save keeps form with error, success closes. Toggles are not disabled while sending on either source; no Android-only issue claimed. |

## Preserve Series? sheet / running status

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Auto-preserve small-series toggle | “prompt.autoPreserveLabel” `Features/WorkDetail/WorkDetailView.swift:1213` | “prompt.autoPreserveLabel” `works/detail/WorkDetailForms.kt:178` | **same** persisted setting/threshold; owner-approved restricted-work skip. |
| Preserve series / Only this work / close | preserve and cancel buttons `Features/WorkDetail/WorkDetailView.swift:1221`, `:1228` | “Preserve Entire Series”, “Only This Work” `works/detail/WorkDetailForms.kt:183` | **same** explicit fetch/preserve unless opted-in small-series auto rule, closes for only-this-work. |
| Cancel Series Preservation | “Cancel Series Preservation” `Features/WorkDetail/WorkDetailView.swift:364` | same `works/detail/WorkDetailForms.kt:261` | **same** cancels remaining batch, completed additions survive; page reports progress/result, not undo. |

## Readium reader — page, chrome, fan menu, errors

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Turn pages / scroll text | “EPUBNavigatorViewController” `Features/ReaderReadium/ReadiumReaderView.swift:1416` | “ReadiumNavigatorHost” `reader/ReaderScreen.kt:454` | **same** toolkit navigation under selected paged/scrolled preference; saved position bridge active. No device gestures exercised. |
| Tap content to show/hide chrome / dismiss open fan | “chromeHidden” `Features/ReaderReadium/ReadiumReaderView.swift:1449`; dismiss backdrop `:1013` | “chromeVisible = !chromeVisible”, close fan `reader/ReaderScreen.kt:464` | **same** ordinary chrome actions; F22 mini-player visibility exception. |
| Close reader / native Back / drag dismissal | “dismissReader” `Features/ReaderReadium/ReadiumReaderView.swift:997` | “onClose = onBack” `reader/ReaderScreen.kt:538`; top-edge drag `:503` | **same** exit action, progress close handler (`reader/ReaderViewModel.kt:193`). Android drag limited to top edge is native interaction choice, not a missing exit. |
| Tap title/author capsule → Work Detail | “showingWorkDetail = true” `Features/ReaderReadium/ReadiumReaderView.swift:998` | “onOpenWorkDetail” `reader/ReaderScreen.kt:539` | **same** opening; Continue Reading from there has F07. |
| Open/close More fan and outside-tap dismiss | “ReaderFanMenu” `Features/ReaderReadium/ReadiumReaderView.swift:1018` | same `reader/ReaderScreen.kt:655`, backdrop `:520` | **same**; shape/glass/animation excluded as chrome choices. |
| Contents | “Contents” `Features/ReaderReadium/ReadiumReaderView.swift:1906` | “readerFanPills…onContents” `reader/ReaderScreen.kt:553`, `:558` | **same** opens Contents segment. |
| Bookmarks & Highlights | label `Features/ReaderReadium/ReadiumReaderView.swift:1910` | “onContents…tab” `reader/ReaderScreen.kt:558` with `reader/ReaderFanMenu.kt` pills | **same** opens Bookmarks segment. |
| Find in Work | label `Features/ReaderReadium/ReadiumReaderView.swift:1915` | “onFind” `reader/ReaderScreen.kt:562` | **same**, disabled for unavailable search service. |
| Comments for current story chapter | “showingComments = true” `Features/ReaderReadium/ReadiumReaderView.swift:1928`, current chapter context in reader | “sections.commentsChapter” `reader/ReaderScreen.kt:557`, callback `:563` | **same** AO3-only chapter-aware discussion; front/back matter fallback to chapter 1 is already fixed (3fl). |
| Themes & Settings | label `Features/ReaderReadium/ReadiumReaderView.swift:1938` | “onSettings” `reader/ReaderScreen.kt:564` | **same** opens Display & Themes; missing controls listed below. |
| Rebuild stale conversion from inside reader | “Rebuild from Original” `Features/ReaderReadium/ReadiumReaderView.swift:1933` | fan pills have no rebuild callback `reader/ReaderScreen.kt:553` | **missing — recorded**, 2026-10-05 menu decision leaves this out because Android has no converter-staleness capability; original/re-share were later added, but reader rebuild still absent. Not a new priority item. |
| Share source or EPUB | “shareURL” source/EPUB fallback `Features/ReaderReadium/ReadiumReaderView.swift:1961` | “canShare” `reader/ReaderScreen.kt:222`, Share callback `:574` | **same** AO3 → other source URL → EPUB fallback; Android now has this older deferred feature (`reader/ReaderWorkActions.kt`). |
| View original converted file | “previewingOriginal = original” `Features/ReaderReadium/ReadiumReaderView.swift:1260` | “readerOriginalAction” / “openOriginal” `reader/ReaderScreen.kt:584` | **same** archive-original access. iOS Quick Look vs Android file-viewer intent is platform navigation. |
| Give kudos | “Give kudos” `Features/ReaderReadium/ReadiumReaderView.swift:1238` | “readerKudosAction” `reader/ReaderScreen.kt:577` | **same** AO3 only, busy/given disabled, success persisted; iOS AO3/OK alert (`:354`), Android transient snackbar with OK (`reader/ReaderScreen.kt:729`, clears after 3.5s `:294`). **different feedback duration**, no undo on either. |
| Read aloud / Stop reading aloud | labels `Features/ReaderReadium/ReadiumReaderView.swift:1277`, action `:1285` | same labels/action `reader/ReaderScreen.kt:593`–`:608` | **same** basic toggle/system fallback; specific transport/sheet gaps below. |
| Long-press Read Aloud for settings | “withLongPress…showingSpeechSettings” `Features/ReaderReadium/ReadiumReaderView.swift:1292` | “longPressAction = { showDisplaySheet = true }” `reader/ReaderScreen.kt:611` | **different — recorded** Android opens combined Display sheet, dedicated speech sheet withheld under owner question 12. |
| Lock / Unlock rotation | labels `Features/ReaderReadium/ReadiumReaderView.swift:1305` | labels `reader/ReaderScreen.kt:620` | **same** session-only orientation lock; Android restores on leaving (`:277`). |
| Add / Remove current-page bookmark | “locations.position == position” `Features/ReaderReadium/ReadiumReaderView.swift:1570` | “readerIsBookmarked” `reader/ReaderScreen.kt:551` → `reader/ReaderFanMenu.kt:161` | **different F02** nearest-within-2%-of-work matching can remove another page's bookmark. Find-result bookmark dedup also differs: exact stored locator (`reader/AnnotationRepository.kt:77`) vs iOS position, so same page can gain duplicates via different entry routes. |
| Scrub within current chapter / return thumb to origin | “ReaderChapterScrub” `Features/ReaderReadium/ReadiumReaderView.swift:1849` | “seekInChapter” `reader/ReaderScreen.kt:395`; commit `:685` | **same** chapter-local visual-page seek and live preview, flush on close; no separate undo button. Spread completion precision remains recorded A61 #9, not rediscovered here. |
| Tap AO3 work/tag/author link; other web link | “router.openAO3Link(url)” `Features/ReaderReadium/ReadiumReaderView.swift:1410` | “linkHandler.classify” `reader/ReaderScreen.kt:479` | **same** native/in-app AO3 destination or external URL, native chrome may differ. |
| Error-state Back / Retry / Remove offline copy | iOS “Couldn't open this EPUB” read-only error `Features/ReaderReadium/ReadiumReaderView.swift:473`; reader close still exists | “Back”, “Retry”, “Remove offline copy” `reader/ReaderScreen.kt:1272`, `:1273`, `:1276` | **Android only**, helpful recovery. Remove offline copy only when file is already missing (`:196`), not destructive F01. Recorded 2026-10-11 empty-state decision explicitly accepts these extras. |

## Reader Contents sheet — Contents segment

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Switch Contents / Bookmarks / Highlights | titles `Features/ReaderReadium/ReaderContentsSheet.swift:33`–`:35`, Picker `:68` | “tabs = listOf” `reader/ReaderContentsSheet.kt:75` | **same**. |
| Tap chapter / Go full swipe | “onSelectChapter” `Features/ReaderReadium/ReaderContentsSheet.swift:105`, Go `:138` | “onSelectEntry(entry)” `reader/ReaderContentsSheet.kt:125`, navigation `reader/ReaderScreen.kt:848` | **same** effective jump/dismiss; Android tap replaces swipe Go without losing destination. |
| Bookmark chapter start | “Bookmark” `Features/ReaderReadium/ReaderContentsSheet.swift:154` | “onBookmarkEntry != null” `reader/ReaderContentsSheet.kt:148`; omitted by host `reader/ReaderScreen.kt:843` | **missing F09**, actual runtime callback absent, despite component containing button code. |
| Add Note at chapter start | “Add Note” `Features/ReaderReadium/ReaderContentsSheet.swift:161` | “onAddNoteToEntry != null” `reader/ReaderContentsSheet.kt:153`; omitted by host `reader/ReaderScreen.kt:843` | **missing F09**. iOS creates chapter bookmark then opens note editor after dismissing Contents (`Features/ReaderReadium/ReadiumReaderView.swift:1607`). |
| Done / dismiss | “readerSheetTitle” host toolbar `Features/ReaderReadium/ReadiumReaderView.swift:1644` | “Done” `reader/ReaderContentsSheet.kt:92` | **same** leaves location alone. |

## Reader Contents sheet — Bookmarks segment

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Switch segments | “segment” `Features/ReaderReadium/ReaderContentsSheet.swift:68` | “selectedTab” `reader/ReaderContentsSheet.kt:102` | **same**. |
| Tap bookmark to jump | “onSelectAnnotation” `Features/ReaderReadium/ReaderContentsSheet.swift:184` | “onSelectAnnotation(annotation)” `reader/ReaderContentsSheet.kt:189`, host `reader/ReaderScreen.kt:858` | **same** bookmark navigation, does not open highlight editor for plain bookmark. |
| Delete bookmark | “Delete” `Features/ReaderReadium/ReaderContentsSheet.swift:193` → immediate delete | “Delete” `reader/ReaderContentsSheet.kt:256` → confirm host `reader/ReaderScreen.kt:871` | **different F24** extra optional “Delete annotation?” confirmation; iOS no confirm/undo. |
| Done/dismiss; empty state | host toolbar `Features/ReaderReadium/ReadiumReaderView.swift:1644`; “No Bookmarks Yet” `Features/ReaderReadium/ReaderContentsSheet.swift:82` | “Done” `reader/ReaderContentsSheet.kt:92`; “No Bookmarks Yet” `:179` | **same**, empty state gives no direct Add button on either. |

## Reader Contents sheet — Highlights segment

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Switch segments | “segment” `Features/ReaderReadium/ReaderContentsSheet.swift:68` | “selectedTab” `reader/ReaderContentsSheet.kt:102` | **same**. |
| Tap highlight/note → jump + edit | “goToAnnotation” `Features/ReaderReadium/ReadiumReaderView.swift:841` | “go(locator)” then “openHighlight” `reader/ReaderScreen.kt:862`, `:868` | **same**. |
| Delete highlight | “onDeleteAnnotation” `Features/ReaderReadium/ReaderContentsSheet.swift:191` | “onDeleteAnnotation(annotation)” `reader/ReaderContentsSheet.kt:212` | **different F24** host asks extra confirmation, no undo. |
| Done/dismiss; empty state | “No Highlights Yet” `Features/ReaderReadium/ReaderContentsSheet.swift:89` | same `reader/ReaderContentsSheet.kt:201` | **same**, no empty-state Add control on either. |

## Reader text selection and highlight colour strip

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| System Copy/lookup/share selection items | “EditingAction.defaultActions” `Features/ReaderReadium/ReadiumBook.swift:74` | wraps “original” ActionMode callback `reader/readium/ReaderSelectionContainer.kt:62` | **same** platform system actions retained, exact platform menus deliberately differ. |
| Highlight selected passage | “createAnnotationFromSelection(withNote…)” `Features/ReaderReadium/ReadiumReaderView.swift:615` | “Highlight” menu `reader/readium/ReaderSelectionContainer.kt:96`, dialog `reader/ReaderScreen.kt:1239` | **different F23** iOS applies last-used colour immediately then exposes colour strip; Android opens confirm dialog, initial yellow, no persisted last colour. |
| Re-highlight same passage same colour / another colour | “deleteAnnotation(existing)” / “applyHighlightColor” `Features/ReaderReadium/ReadiumReaderView.swift:625`–`:629` | “existing.copy(colorRaw = color)” `reader/AnnotationRepository.kt:135` | **different F23** repeat never removes; recolour survives. |
| Add Note to selection | menu action `Features/ReaderReadium/ReadiumBook.swift:77`; editor `Features/ReaderReadium/ReadiumReaderView.swift:652` | “Add Note” `reader/readium/ReaderSelectionContainer.kt:101` | **same** ability to save a note; **different F03** Back loses new text; existing passage opens fresh dialog instead of seeded editor. |
| Select colour / Underline / close colour strip | “ReaderHighlightColorBar…onSelect/onDismiss” `Features/ReaderReadium/ReadiumReaderView.swift:1083` | “ReadingAnnotationColor.entries” `reader/ReaderScreen.kt:1196` | **same** resulting colour/underline choices; **different F23** modal confirmation instead of immediate-refine strip. Editor recolour is immediate on both. |
| Fix Pronunciation from selected word | “Fix Pronunciation” `Features/ReaderReadium/ReadiumBook.swift:79` | custom menu adds only “Highlight” and “Add Note” `reader/readium/ReaderSelectionContainer.kt:93`–`:102` | **missing — recorded**, pronunciation capability omitted in 3ak/2026-10-05; not a new priority. |
| Tap existing page highlight | “editingNote = annotation” `Features/ReaderReadium/ReadiumReaderView.swift:871` | “onHighlightTap = viewModel::openHighlight” `reader/ReaderScreen.kt:462` | **same** opens saved-note/colour editor. |

## Reader Note editor / initial Add note dialog

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Edit note text | “TextEditor(text: $draft)” `Features/ReaderReadium/ReaderNoteEditor.swift:39` | draft text field `reader/ReaderNoteEditor.kt:119`; initial dialog `reader/ReaderScreen.kt:1228` | **same** edit capability. Initial Add Note to an existing highlight is **different F23** — Android starts empty instead of showing its existing note (`:1173`; iOS `Features/ReaderReadium/ReadiumReaderView.swift:622`). |
| Pick colour / underline | “ReadingAnnotationColorPicker” `Features/ReaderReadium/ReaderNoteEditor.swift:45` | “ReadingAnnotationColor.entries” `reader/ReaderNoteEditor.kt:127` | **same** immediate recolour for saved marks. |
| Done/Save note | “keepDraft()” `Features/ReaderReadium/ReaderNoteEditor.swift:86` | “onDone(draft.trim())” `reader/ReaderNoteEditor.kt:96`; initial “Save note” `reader/ReaderScreen.kt:1240` | **same** trims/saves, closes; no success alert. |
| Cancel note editing | “colorOnOpen” rollback `Features/ReaderReadium/ReaderNoteEditor.swift:72` | “cancelNote” rollback `reader/ReaderScreen.kt:801` | **same** existing-note editor discards typed changes and restores opening colour. Initial Android dialog Cancel discards unsaved new mark, iOS mark already exists: **different F23** initial transaction shape. |
| Swipe down / Back / dismiss existing editor | “if !finished { keepDraft() }” `Features/ReaderReadium/ReaderNoteEditor.swift:100` | “onDispose…onKeep(draft.trim())” `reader/ReaderNoteEditor.kt:74` | **same**, keeps changed text/colour. |
| Back/dismiss initial Add note dialog | same iOS autosave `Features/ReaderReadium/ReaderNoteEditor.swift:100` | “onDismissRequest = onDismiss” `reader/ReaderScreen.kt:1176`, callback `:780` | **different F03** no write; typing disables outside-tap dismiss only (`:1178`), not Back. |
| Delete Highlight / Cancel confirmation | “Delete Highlight” `Features/ReaderReadium/ReaderNoteEditor.swift:61` | delete `reader/ReaderScreen.kt:822` → “Delete annotation?” `:317` | **different F24** extra optional confirmation. iOS deletes immediately and marks editor finished; Android closes editor then asks. |

## Find in Work sheet

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Type query / keyboard Search | “onChange…scheduleSearch”, “onSubmit” `Features/ReaderReadium/ReaderSearchView.swift:295`, `:296` | “model.search” `reader/ReaderSearchSheet.kt:165`, `:175` | **same** debounced incremental search, explicit submit reruns immediately. |
| Clear query | “Clear search” `Features/ReaderReadium/ReaderSearchView.swift:307` | same `reader/ReaderSearchSheet.kt:196` | **same**, resets results/focus. |
| Tap result / Go swipe/full swipe | “Go” `Features/ReaderReadium/ReaderSearchView.swift:425` | “onGo” `reader/ReaderSearchSheet.kt:235`, full-swipe row `:300` | **same**, navigates and dismisses sheet. |
| Bookmark result | “Bookmark” `Features/ReaderReadium/ReaderSearchView.swift:432` | same `reader/ReaderSearchSheet.kt:308`; host `reader/ReaderScreen.kt:763` | **same** create bookmark without moving/dismissing; exact-position dedup caveat F02. |
| Copy result passage | “Copy” `Features/ReaderReadium/ReaderSearchView.swift:439` | “copyText” `reader/ReaderSearchSheet.kt:291` | **same**, clipboard action, no bespoke iOS success alert; Android system clipboard feedback is native. |
| Done / dismiss; empty/error state query editing | host `Features/ReaderReadium/ReadiumReaderView.swift:1644`; idle/error `Features/ReaderReadium/ReaderSearchView.swift:321` | “Done” `reader/ReaderSearchSheet.kt:157`; empty/error `:203`–`:214` | **same**, cancels search on leave, errors require edit/retry query; no Retry button on either. |

## Display & Themes sheet

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Light / Sepia / Dark / OLED | “ReaderThemePicker” `Settings/SettingsView.swift:37` | “ReaderColorTheme.entries” `reader/ReaderScreen.kt:991` | **same** reader colour selection. |
| Customize Theme… | “showCustomize = true” `Settings/SettingsView.swift:40` | “showCustomize = !showCustomize” `reader/ReaderScreen.kt:1002` | **different F21**, opens full editor on iOS, reveals only three inline controls on Android. |
| Text Size | “TextSizeSlider” `Settings/SettingsView.swift:50` | “TextSizeSlider” `reader/ReaderScreen.kt:1033` | **same** size adjustment; percent versus points label is platform presentation. |
| Layout Scrolled / Paged | “Picker(\"Layout\")” `Settings/SettingsView.swift:118` | “Scrolled…Paged” `reader/ReaderScreen.kt:1056` | **same**. |
| Two-page spread (wide devices) | “Two-page spread” `Settings/SettingsView.swift:127` | same `reader/ReaderScreen.kt:1063` | **same** disabled in scroll, phone/wide-device availability appropriate to platform. |
| Keep screen awake | label `Settings/SettingsView.swift:135` | same `reader/ReaderScreen.kt:1075` | **same**. |
| Read Aloud voice / speed / pitch | “Voice”, “Speed”, “Pitch” `Features/ReaderReadium/ReaderSpeechSettingsSection.swift:135`, `:158`, `:171` | voice chips `reader/ReaderScreen.kt:1096`; “Speed”, “Pitch” `:1112`, `:1121` | **same** basic choice controls; engine capabilities and pitch persistence are separately limited, below. |
| Select built-in font | “fontOptions” `Settings/SettingsView.swift:164` | “ReaderFontCatalog.builtIns” `reader/ReaderScreen.kt:1142` | **same** built-in font action. |
| Choose imported font / Add Font / delete imported font | “CustomFont”, “Add Font…”, “onDelete” `Settings/SettingsView.swift:154`, `:185`, `:183` | only “builtIns” list `reader/ReaderScreen.kt:1142` | **missing F21** from this reader sheet, even though global Settings can manage fonts. |
| Done/dismiss | reader sheet toolbar `Features/ReaderReadium/ReadiumReaderView.swift:1644` | “Done” `reader/ReaderScreen.kt:981` | **same** immediate preferences retained. |

## Customize Theme screen

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Font / Bold Text | “Picker(\"Font\")”, “Bold Text” `Features/Reader/CustomizeThemeView.swift:63`, `:68` | “Bold Text” inline `reader/ReaderScreen.kt:1007`, built-in font list `:1142` | **same** ordinary effect through different placements. Custom font omission F21. |
| Customize on/off | “Toggle(\"Customize\")” `Features/Reader/CustomizeThemeView.swift:78` | no corresponding control, inline editor `reader/ReaderScreen.kt:1004` | **missing F21**, cannot restore comfortable layout defaults while retaining font/bold using this switch. |
| Line Spacing | label `Features/Reader/CustomizeThemeView.swift:81` | inline editor only letter/word `reader/ReaderScreen.kt:1011`, `:1020` | **missing F21**. |
| Character / Word Spacing | labels `Features/Reader/CustomizeThemeView.swift:84`, `:86` | “Letter spacing”, “Word spacing” `reader/ReaderScreen.kt:1012`, `:1021` | **same** adjustable, although Android always enables overrides. |
| Margins / Justify Text | labels `Features/Reader/CustomizeThemeView.swift:88`, `:90` | inline editor ends at word spacing `reader/ReaderScreen.kt:1028` | **missing F21**. |
| Reset Theme | “Reset Theme” `Features/Reader/CustomizeThemeView.swift:102` | no reset in `reader/ReaderScreen.kt:999`–`:1028` | **missing F21**. |
| Live preview / Done | “previewHeader” `Features/Reader/CustomizeThemeView.swift:108`, toolbar `:112` | inline on reader sheet `reader/ReaderScreen.kt:1004`, Done `:981` | **different F21** no dedicated preview; Done still exits parent sheet. |

## Read Aloud mini-player and speech settings entry

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Play/Pause | “controller.toggle(from: nil)” `Features/ReaderReadium/ReaderSpeechController.swift:886` | “onPlay”/“onPause” `reader/ReaderScreen.kt:695`, `:718` | **same** basic transport; available during shown chrome. |
| Stop | “onStop” `Features/ReaderReadium/ReadiumReaderView.swift:1103` | “onStopSpeech” `reader/ReaderScreen.kt:719` | **same**, removes active playback. |
| Previous chapter / Next chapter | labels `Features/ReaderReadium/ReaderSpeechController.swift:878`, `:902` | “Previous paragraph” `reader/ReaderPositionCard.kt:397`, callbacks `reader/ReaderScreen.kt:723` | **different F22**, paragraph queue step, not chapter restart/skip. |
| Hold Previous/Next to seek | “onHoldTick” `Features/ReaderReadium/ReaderSpeechController.swift:882`, `:906` | only “onClick = onSkipPrevious” `reader/ReaderPositionCard.kt:392` and Next | **missing — recorded A61 #21**, no Read Aloud position seek; no new priority beyond functional skip distinction F22. |
| Controls remain when page chrome hidden | “standaloneMiniPlayer” `Features/ReaderReadium/ReadiumReaderView.swift:1071` | parent “visible = chromeVisible” `reader/ReaderScreen.kt:665` | **different F22** Pause/Stop hidden until reader taps to show chrome again. |
| Waveform tap → speech settings | “Read-aloud settings” `Features/ReaderReadium/ReaderSpeechController.swift:962` | decorative Icon `reader/ReaderPositionCard.kt:379` | **missing — recorded reader-sheet deferral**, long press Read Aloud opens combined settings instead. |
| Mini-player background tap reveals full chrome | “onBackgroundTap” `Features/ReaderReadium/ReadiumReaderView.swift:1111` | mini-player lives only inside visible chrome `reader/ReaderScreen.kt:665` | **different F22** no independent background-tap route because it disappears. |
| System media Play/Pause/Next/Previous | Readium Now Playing controller in `Features/ReaderReadium/ReaderSpeechController.swift:720` | media callbacks `reader/speech/ReaderSpeechController.kt:71` | **same** basic transport route, but Next/Previous retain F22 paragraph behavior. Duration/time now present per 3fn, not reported missing. |

## Dedicated Read Aloud settings sheet / voice picker

The engine/model/pronunciation/developer omissions below are recorded capability decisions (2026-10-05 3ak); the reader-specific sheet and author-notes switch placement wait on owner question 12 (2026-10-14 3ee). They are inventoried, not promoted into new priority findings.

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Done | “Done” `Features/ReaderReadium/ReaderSpeechSettingsSheet.swift:37` | combined reader sheet “Done” `reader/ReaderScreen.kt:981` | **same** way to leave settings; dedicated sheet **missing, recorded**. |
| Engine: Automatic/System/Kokoro | “Picker(\"Engine\")” `Features/ReaderReadium/ReaderSpeechSettingsSection.swift:68` | automatic/system/Kokoro controller `reader/speech/ReaderSpeechController.kt:151`; no picker in `reader/ReaderScreen.kt:1080` | **missing, recorded** manual choice; Automatic fallback works. |
| Model / compute choices on supported pre-CoreML line | “Kokoro model”, “Kokoro compute” `Features/ReaderReadium/ReaderSpeechSettingsSection.swift:79`, `:85` | one voice pack row `reader/ReaderScreen.kt:1135` | **missing, recorded** platform engine capability. Do not require Apple Neural Engine controls on Android. |
| Read author's notes | toggle `Features/ReaderReadium/ReaderSpeechSettingsSection.swift:113` | consumed via global setting `reader/ReaderViewModel.kt:452`; absent from reader sheet `reader/ReaderScreen.kt:1080` | **missing here, recorded**; global Listening toggle exists and start playback consults it. |
| Voice → Automatic / choose available voice | “Voice”, “voicePicker” `Features/ReaderReadium/ReaderSpeechSettingsSection.swift:132` | “Automatic (best available)” / voice chips `reader/ReaderScreen.kt:1098`, `:1104` | **same** available platform voice selection, no fixed cross-platform voice-name requirement. |
| Speed / Pitch | sliders `Features/ReaderReadium/ReaderSpeechSettingsSection.swift:164`, `:177` | sliders `reader/ReaderScreen.kt:1111`, `:1120` | **same** controls; **different, recorded** Android reader pitch only updates live preference (`reader/ReaderViewModel.kt:462`), not persisted speech settings, consistent with earlier unsupported-pitch decision. |
| Reset Read Aloud | “Reset Read Aloud” `Features/ReaderReadium/ReaderSpeechSettingsSection.swift:182` | combined reader speech panel ends at pack row `reader/ReaderScreen.kt:1138` | **missing here**; reset is available in global Listening (3ak). Reader sheet withheld under question 12, recorded. |
| Pronunciations / Developer Settings | links `Features/ReaderReadium/ReaderSpeechSettingsSection.swift:138`, `:147` | no links in combined speech panel `reader/ReaderScreen.kt:1080`–`:1138` | **missing, recorded** capability. |
| Download pack / consent Download / Cancel / Retry Download | “Download”, “Cancel”, “Retry Download” `Features/ReaderReadium/ReaderSpeechSettingsSection.swift:253`, `:254`, `:292`; alternate pack `:326` | “Download Kokoro Voice Pack (about 45 MB)” `reader/ReaderScreen.kt:1135` → `onDownloadVoicePack` `:905` | **different** Android immediately enqueues without iOS's second download-confirmation, has progress row but no in-sheet Cancel. Pack/platform size differs intentionally; loss of consent/cancel is actionable **F29**. |

## Audition Voice (reachable from iOS Read Aloud settings)

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Choose Sample Text | “Sample Text” `Features/ReaderReadium/ReaderSpeechAuditionHarness.swift:42` | reader speech panel `reader/ReaderScreen.kt:1080` has voice/speed/pitch/pack only | **missing here — recorded** reader-sheet deferral; global Listening includes audition per 3ak. |
| Speed slider / 0.9×, 1.0×, 1.1× shortcuts | slider `Features/ReaderReadium/ReaderSpeechAuditionHarness.swift:61`, choices `:122` | reader “Speed” `reader/ReaderScreen.kt:1112`, no audition/shortcut row | **different here — recorded** main rate adjustable; audition shortcuts remain global Listening, not the reader. |
| Play Sample / Stop | “Play Sample”, “Stop” `Features/ReaderReadium/ReaderSpeechAuditionHarness.swift:101`, `:92` | no sample player in `reader/ReaderScreen.kt:1080` | **missing here — recorded**, available globally. Leaving iOS audition stops sample (`:110`). |

## Pronunciations screen (recorded unsupported Android capability)

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Scan this chapter | “Scan this chapter” `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:61` | no pronunciation/scan entry in speech panel `reader/ReaderScreen.kt:1080`–`:1138` | **missing — recorded**; conditional iOS control only if host supplied chapter scan callback. |
| Add Pronunciation | label `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:146` | same absent speech entries `reader/ReaderScreen.kt:1080` | **missing — recorded**. |
| Edit existing correction | “editing = entry” `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:89` | no correction editor `reader/ReaderScreen.kt:1080` | **missing — recorded**. |
| Delete correction | “onDelete(perform: delete)” `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:101` | no correction list `reader/ReaderScreen.kt:1080` | **missing — recorded**, iOS swipe deletion has no confirmation/undo. |
| Correct guessed word / dismiss guess | “editing = Entry(word: guess.word…)”, “dismissGuesses” `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:116`, `:126` | no guessed-word list `reader/ReaderScreen.kt:1080` | **missing — recorded**. |
| Paste Corrections / acknowledge Pasted Corrections | labels `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:154`, `:165` | no import control `reader/ReaderScreen.kt:1080` | **missing — recorded**. |
| Copy All | “Copy All” `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:157` | no export control `reader/ReaderScreen.kt:1080` | **missing — recorded**, disabled with no corrections on iOS. |

## Add/Edit Pronunciation sheet (recorded unsupported Android capability)

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Word / pronunciation respelling or IPA | “Word”, “her-MY-oh-nee” `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:367`, `:372` | no pronunciation editor from `reader/ReaderScreen.kt:1080` | **missing — recorded**. Phoneme preview is read-only. |
| Save / Cancel | “Save”, “Cancel” `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:404`, `:401` | no editor `reader/ReaderScreen.kt:1080` | **missing — recorded**; nonempty fields required, explicit commit; no confirmation/undo. |

## Read Aloud Developer Settings (recorded unsupported Android capability)

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Between chunks / Line break / Paragraph / Scene break / Chapter pause sliders | five “pause” calls `Features/ReaderReadium/ReaderSpeechDeveloperSettingsView.swift:53`–`:60` | no tuning entry in speech panel `reader/ReaderScreen.kt:1080`–`:1138` | **missing — recorded**; platform speech pipeline does not implement these settings. |
| Minimum / Maximum / Split above chunk size | three “phonemes” calls `Features/ReaderReadium/ReaderSpeechDeveloperSettingsView.swift:76`–`:78` | no tuning entry `reader/ReaderScreen.kt:1080` | **missing — recorded**. |
| Break at dialogue / Pause at line breaks | toggles `Features/ReaderReadium/ReaderSpeechDeveloperSettingsView.swift:91`, `:92` | no tuning entry `reader/ReaderScreen.kt:1080` | **missing — recorded**. |
| Reset to shipped defaults | label `Features/ReaderReadium/ReaderSpeechDeveloperSettingsView.swift:105` | no tuning entry `reader/ReaderScreen.kt:1080` | **missing — recorded**, iOS immediate reset, no separate confirm/undo. |

## iPad queue sidebar (ReadingQueueSwitcher extension)

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Pick another queue | “Button { select(queue) }” `Features/Library/ReadingQueueSwitcher.swift:30` | “onOpenQueue” `library/QueueOrganizerScreen.kt:255`; return to organizer `library/ReadingQueueBrowserScreen.kt:55` | **same** destination through Android navigation; no requirement for an iPad sidebar. |
| New Queue / Cancel | “NewReadingQueueSheet…onCreate/onCancel” `Features/Library/ReadingQueueSwitcher.swift:13` | “QueueEditorSheet” `library/QueueOrganizerScreen.kt:298` | **same** new-queue capability, full sheet inventoried above. iPhone bottom switcher intentionally removed on iOS. |

## Legacy Reader/ReaderView (macOS-only, not an additional iOS reader)

`Features/Reader/ReaderView.swift:8` is `#if os(macOS)`. Its separate toolbar and inspector are not reachable iOS screens and are not additional Android parity obligations. `CustomizeThemeView` and `TextSizeSlider` are shared with the iOS reader and are inventoried above.

| Legacy action | Apple quote · path:line | Android effective counterpart · path:line | Result |
|---|---|---|---|
| Chapters / tap chapter / Previous / Next | “Chapters” `Features/Reader/ReaderView.swift:151`; jump `:371`; “Previous”/“Next” `:310` | “onSelectEntry” `reader/ReaderScreen.kt:848`; Readium page navigation `:454` | **same** effective navigation; no finding for missing macOS inspector/buttons. |
| Display Options | label `Features/Reader/ReaderView.swift:154` | “showDisplaySheet = true” `reader/ReaderScreen.kt:564` | **same** settings destination; actual iOS controls compared above. |
| More AO3 actions | “AO3WorkActionsMenu” `Features/Reader/ReaderView.swift:160` | Android reader Comments/Kudos `reader/ReaderScreen.kt:563`, `:577`; full work actions through details `:539` | **different, platform-scoped** — macOS toolbar includes subscription/bookmark/mark-later writes; iOS fan also omits those, so not a new Android finding. |

## Decisions applied and coverage limits

- Reviewed the 2026-10-10 through 2026-10-16 decisions before classification. In particular: 3ck selection actions are present; 3fi collection candidates/queue removal/last-copy warnings and default layouts are present; 3fl chapter-comments fallback and imported-work dismissal are present; 3fn media duration is present. These are not repeated as missing.
- The recorded reader chrome decision (owner question 12) covers visual chrome and withheld dedicated speech sheet/section pills. No findings concern icon style, platform navigation bars, gesture-vs-button shape, or Apple-specific engine controls. Functional content/actions that disappear are still identified explicitly.
- Pronunciations, developer tuning, manual engine/model/compute, reader-only author-notes toggle, reader stale-rebuild capability and hold-position speech seek are recorded omissions. The 3bn Work Detail queue picker was explicitly required to be additive; its membership-removal difference is recorded rather than newly prioritized. The general Library/bulk picker omissions remain F15.
- Collection Details' Save/Cancel staging, tag-editor Remove omission, missing queue Add Works empty-state/Top/Bottom shortcuts, shortened confirmation messages and transient kudos feedback are shown as differences even where a nearby route still accomplishes the action. Priority list separates material fixes from these lower-impact paths.
- Helper-only files (`ReadingStatistics`, `ReadingAffinities`, grouping/filter/progress/style mappers, queue switcher/drop delegates, controller/installer implementations) were traced where they determine a reachable action, not invented as screens. Shared sensitive rows, cover cards, author navigation, swatches, deletion confirmations and bulk tags are included through their screen/menu tables. Deprecated/unopened standalone Android screens are not credited as live counterparts.
- This is a source audit, not a visual or runtime certification. No app build/test, emulator/simulator, live AO3, sign-in, network write, commit, push, branch change or source edit was performed. Only `docs/android-port/audits/A62-result.md` is written. Remaining manual verification: actual gestures/large text, process death, file-provider intents, OS voice availability and real authenticated AO3 results.

## Where Android is right

Android correctly distinguishes removing a download's keep flag from deleting a work in its shared download controls, protects queue/collection-kept copies, confirms permanent deletion independently of the everyday-delete preference, keeps existing-note edits on Back, gates mature reveals, supports all four Favorites scopes, and retains the completed work when cancelling series preservation. Its reader error Retry/Back actions are useful additions. The corresponding rows above provide the source evidence; these working paths should be preserved while fixing the priority items.

## Audit completion

Completed against the dispatch HEAD. The priority list contains 33 stable finding IDs (F01–F33); recorded omissions are separate. All inline source paths/line bounds were checked locally, and report table structure/whitespace were checked. Branch and HEAD remain `android/agent-codex-a62` / `24cf81c71a7abb31f8732f5d5af45f7c861f9d5f`. The sole working-tree addition is this report.
