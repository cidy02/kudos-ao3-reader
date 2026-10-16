# Priority list

1. **F16 · Different · Delete From Inbox skips iOS's mandatory confirmation when delete confirmation is off.** I `Features/Account/AccountInboxViews.swift:925`, `:949`; A `account/AccountInboxPane.kt:155` uses the setting for both single and bulk notification deletion. AO3 comments stay, but notifications have no undo.
2. **F01 · Different · Home bulk Delete can skip iOS's mandatory confirmation.** I `UIComponents/WorkBulkActionBar.swift:128` “Delete … works?”; A `home/HomeWorkMenu.kt:275` “confirmBeforeDelete = confirmBeforeDelete”, shared by single and bulk deletes. With that setting off a selection disappears into Recently Deleted immediately (90-day recovery remains).
3. **F30 · Different · Author Works/Dashboard and series works never pair a remote result with its local work.** I `Features/Authors/AuthorDashboardSections.swift:195` “SensitiveWorkRow(work: work…)”, `Features/Authors/AO3SeriesDetailView.swift:207`; A `author/AuthorProfileComponents.kt:171` accepts only `AO3WorkSummary`, `:184` renders the remote overload; `app/SeriesWorksScreen.kt:287` likewise. A locally blurred work is named/opened as a remote result instead of requiring its reveal, and the local Read/menu route is missing. Applies to Blur mode local matches; iOS deliberately excludes Hide-mode local matches before the merge and can still show their remote result.
4. **F07 · Missing while inside a thread · Reply, Edit and Delete do not present their UI.** I `Features/Comments/CommentThreadScreen.swift:75` supplies the same handlers while the parent hosts sheets; A `comments/CommentsScreen.kt:222` renders `CommentThreadScreen` then `return` at `:236`, before Delete dialog `:268` and composer `:334`. Those handlers only set pending/composer state (`:204`–`:206`); Back is needed before the requested UI can appear.
5. **F17 · Different · Remote bulk Download/Save stores metadata, not EPUBs.** I `UIComponents/RemoteWorkSelection.swift:71` “mode: .withEPUB”; A `ui/components/RemoteWorkSelection.kt:164` “saveMetadataOnly”. A newly selected work is unavailable offline after the apparent save. Applies to Search/Browse/author/series remote selection.
6. **F12 · Different · Search ignores bulk-action failures and exits selection.** I `UIComponents/RemoteWorkSelection.swift:241` “Action Failed”; A `search/SearchScreen.kt:513`, `:523` discards the returned status, then exits. A failed or partial save looks completed; Browse shows that status correctly.
7. **F10 · Missing · Remote-card menus/swipes lack Read, Comments, Download/Remove Download, Later, Queue, Finished, Collection and local Delete.** I `Features/Library/WorkCardActions.swift:560`, `:611`; A `ui/components/SensitiveWorkRow.kt:706` offers only “Open Work” and “Copy Link”; Home remote covers have only click (`home/HomeScreen.kt:606`). Applies across Search, Browse, account remote rows, author and series works.
8. **F05 · Missing · Remote selections in Search, fandom/tag results, author Works and series works lack Add to Collection and Add to Queue.** I `UIComponents/RemoteWorkSelection.swift:169`, `:178`; A `ui/components/RemoteWorkSelection.kt:140` “Save for Later”, `:143` “Save”, `:145` “Cancel”; callers `search/SearchScreen.kt:506`, `browse/FandomWorksScreen.kt:334` supply only the two save operations.
9. **F08 · Different · Search's local work matches open Work Detail and long press selects, losing the iOS reader destination, work menu and swipes; collection matches lose their menu too.** I `Features/Search/SearchLocalResultsList.swift:42` “SensitiveWorkRow”, `:51` “libraryWorkSwipeActions”, `:111` “collectionCardMenu”; A `search/SearchScreen.kt:383` “onOpenWork(it.toRemoteSummary())”, `:919` “onLongClick = { onSelect(work.id) }”, `:975` collection click only.
10. **F20 · Different · Account's matched local works open detail instead of reader and lack the Library work menu.** I `Features/Privacy/MatureContent.swift:231`, `:258`; A `account/AccountWorksListScreen.kt:1737` “onOpenWork(work.remote)” passes no long-click to the local row. Includes History/Bookmarks/Marked for Later/Subscriptions.
11. **F31 · Missing · AO3's own deep-thread cutoff disclosure cannot open the omitted comments.** I `Features/Comments/CommentThreadRow.swift:1171` “Link(destination: url)”; A `comments/CommentThreadComponents.kt:621`–`:644` draws the label/chevron without a click or URL handler. This is separate from Kudos's working Continue Thread control for already-loaded replies.
12. **F11 · Android only, broken · Remote-work Copy Link copies nothing.** I complete remote menu `Features/Library/WorkCardActions.swift:611`–`:686` offers no such item; A `ui/components/SensitiveWorkRow.kt:715` “Copy Link”, handler `:717` only sets `showMenu = false`. Comments' Copy Link does correctly write the clipboard.
13. **F32 · Missing · Fandom alphabet index has no screen-reader adjustment action.** I `Features/Search/FandomListView.swift:305` “accessibilityAdjustableAction” moves to the next/previous available letter; A `browse/FandomListChrome.kt:385` handles raw pointer drag only and `:407`–`:415` draws plain Text. The same index works by touch, but a TalkBack reader cannot invoke the equivalent letter jump.
14. **F02 · Different · Home's Add to Queue is add-only, one queue at a time; no create or series option.** I `Features/Library/ReadingQueues.swift:469` “Add”, `:503` “Also add works from this AO3 series”; A `home/HomeWorkMenu.kt:317` “Use + on Home to make one”, `:319` “onPick(queue)” closes the dialog. Existing membership cannot be removed there.
15. **F03 · Different · Home's Add to Collection is add-only rather than a membership editor.** I `Features/Library/Collections.swift:598` “AddToCollectionView”; A `home/HomeWorkMenu.kt:352` “onPick(collection.name)”, `:246` “addToCollection”. Cannot remove a selected work from a collection here.
16. **F04 · Missing · Home bulk Tag cannot show/toggle existing tags or remove a tag.** I `UIComponents/WorkBulkTagSheet.swift:73` “Button”, `:83` “some”; A `home/HomeWorkMenu.kt:375` “Tag name”, `:260` “addUserTag”. Typed-name Add/Cancel is all it offers.
17. **F06 · Missing · Search, fandom/tag results, author/dashboard and series menus omit Show/Hide Mature.** I `Features/Search/SearchView.swift:236`, `:246` and `Features/Browse/NativeBrowseView.swift:465`, `:623` “MatureRevealToggle”; A complete menus `search/SearchScreen.kt:689` and `browse/FandomWorksScreen.kt:176` have Select/Expand only. Local Search still obscures works and permits individual reveal; bulk reveal/hide requires leaving this screen.
18. **F14 · Missing · Downloading an EPUB in the in-app AO3 website does not import it into Library.** I `Features/Browse/BrowseView.swift:130` “model.onImport”; A WebView setup `web/AO3WebViewFallbackScreen.kt:144`–`:207` has no download listener/import callback.
19. **F13 · Missing · Web fallback lacks address/search, normal Reload, page Bookmark and immediate Done.** I `Features/Browse/BrowseView.swift:78`, `:85`, `:97`, `:107`; A complete header `web/AO3WebViewFallbackScreen.kt:99`–`:111` has Back/title/Browser; Reload exists only after an error (`:135`).
20. **F18 · Different · Author Works/Series/Bookmarks and series-detail works replace pages instead of Load More appending.** I `Features/Authors/AuthorProfileContentSections.swift:88` “Load More”; A `author/AuthorProfileScreen.kt:225`, `:234`, `:243` replaces each page, Previous/Next `:1126`, `:1128`. Earlier results/selection cannot remain in the same accumulated list.
21. **F21 · Missing · Shared page picker has no exact page-number entry; Inbox has no normal-size page picker at all.** I `Features/Search/SearchPaginationBar.swift:392` “TextField("Page")”; A `ui/components/KudosPaginationBar.kt:153`–`:260` supplies only slider, Nearby and First/Last. Reaching a known page among thousands requires slider approximation and nearby taps; Inbox instead offers Previous/Next (`account/AccountInboxPane.kt:1137`, `:1152`) against iOS’s full pager (`Features/Account/AccountInboxScreen.swift:84`).
22. **F19 · Missing · Dashboard fandom chips cannot open fandom works or expand/collapse the five-fandom preview.** I `Features/Authors/AuthorDashboardSections.swift:38`, `:54`; A `author/AuthorProfileScreen.kt:770` draws every fandom with a plain `SubjectChip` and no click.
23. **F26 · Missing · Author profile/dashboard has no Expand/Collapse All cards.** I `Features/Authors/AuthorProfileView.swift:883` “ExpandAllMenuItem”; A complete menu `author/AuthorProfileScreen.kt:469`–`:530` has modes but no expansion action; dashboard cards force `expandAll = false` (`:790`).
24. **F27 · Missing · Dashboard has no About action.** I `Features/Authors/AuthorProfileView.swift:888` “dashboardDestination = .about”; A dashboard hides the tab strip (`author/AuthorProfileScreen.kt:744`) and its full menu (`:477`–`:530`) has no About route. Opening Profile from Account remains a longer fallback.
25. **F29 · Different · Account's More on AO3 row opens an incomplete popup instead of its full page.** I `Features/Account/AccountView.swift:697` “Route.moreOnAO3”; A `account/AccountScreen.kt:352` “moreOnAo3MenuOpen = true”, ten entries `:358`–`:368`. The complete page (including Post, Import, Invitations and archive links) is only reached through a configured shortcut (`:254`).
26. **F22 · Missing · Tag picker lacks Popular in the selected fandom.** I `Features/Search/TagSelectField.swift:185` “Popular in …”, `:191` “tagRows(popular)”; A `search/FilterTagPicker.kt:93`–`:114` only offers typed/local/autocomplete names, no fandom context.
27. **F25 · Different · Thread/Parent Thread navigation replaces the isolated root instead of scrolling/highlighting or returning to the main list.** I `Features/Comments/CommentThreadScreen.swift:147`, `:164`; A `comments/CommentsScreen.kt:213` always assigns `pushedThreadRootId`, including handlers reused in the isolated thread (`:233`).
28. **F28 · Different · Author Open on AO3 opens the account profile, losing the selected pseud/dashboard destination.** I `Features/Authors/AuthorProfileView.swift:892` “model.route.dashboardURL”; A `author/AuthorProfileScreen.kt:515` “userProfileUrl(route.username)”. Share Profile correctly includes the pseud (`:518`).
29. **F24 · Different · Collection Items Submit adds an extra confirmation.** I `Features/Account/AO3CollectionItemsView.swift:188` calls `submit()` directly; A `account/AO3CollectionItemsScreen.kt:128` opens “Submit staged changes?” (`:160`). Staging and Discard are otherwise correctly present.
30. **F09 · Different · Removing a saved search adds a confirmation.** I `Features/Search/SearchView.swift:442` “onDelete”; A `search/SearchScreen.kt:282` “Delete saved search?”. iOS deletes immediately; neither offers undo or Recently Deleted for this item.
31. **F23 · Different · AO3 Preferences' save result stays in the page instead of iOS's transient overlay; failure lacks its Try Again action.** I `Features/Account/AO3PreferencesView.swift:512`, `:516`, `:529`; A `account/AO3PreferencesScreen.kt:157` “Saved successfully.” and `:218` inline text, no expiry/retry. Top Save remains a fallback on failure.

## Scope and evidence

Read-only action parity audit on `android/agent-codex-a63`, Android HEAD `f875ed5f`. iOS source: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/{Home,Search,Browse,Account,Bookmarks,Comments,Authors}` and shared components. Only this report is written. No build, commit, push, branch switch, sign-in or AO3 contact. Recorded decisions from 2026-10-10 onward are checked before classifying differences.

## Coverage status

Completed static action inventory of the requested screen families and their shared controls. iOS HEAD `c3eb0bc8`; Android HEAD `f875ed5f`. No runtime or visual verification is claimed. The priority list has 31 confirmed action differences; IDs remain stable and are deliberately not in numeric order. Form destinations outside the requested folders are traced to their route, not re-audited internally. No build/tests or network requests were run. F15 was withdrawn from priorities after finding the explicit 2026-10-09 decision preserving Android’s Privacy confirmation preference; its four differences remain documented below.

## How to read the evidence

I = paths relative to `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`; A = paths relative to `android/app/src/main/java/io/github/cidy02/kudos/`. Quotes are source labels/handler excerpts. **same** means the ordinary action matches in source; it does not certify runtime, gestures, visuals or every race. Unless stated, no confirmation, undo or success message is supplied. Repeating a toggle reverses it. Work deletion recovers through Recently Deleted for 90 days, not an immediate Undo. A missing action cites the actual counterpart or complete menu, rather than an ungrounded search absence. Shared tables apply wherever explicitly referenced.

Recorded decisions applied: Android owns navigation/chrome; account Compact default is now implemented; native History/Unmark/author writes and five-minute comment cache are present; author-write success is deliberately stricter on Android (2026-10-16); Privacy & Data pull-to-remeasure is recorded left on 2026-10-11, and its confirmation preference is explicitly retained in the 2026-10-09 Privacy entry (`docs/android-port/DECISIONS.md:1188`). Mac-only media-browser panels are excluded. Old A62 findings are not assumed still present: its latest fixes are in this HEAD.

## Home dashboard — HomeView

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Resume hero / tap another local cover | “LocalWorkDestination.reader” `Features/Home/HomeResumeHero.swift:101`; `Features/Home/HomeView.swift:419` | “onOpen(work)” `home/HomeWorkMenu.kt:105` | **same** ordinary local reader route. |
| Reveal an obscured hero/card | “gate.reveal(work)” `Features/Home/HomeResumeHero.swift:55` | “obscured -> onReveal(work)” `home/HomeWorkMenu.kt:104` | **same**, privacy gate. |
| Browse AO3 / Open Library when empty | “Browse AO3”, “Open Library” `Features/Home/HomeView.swift:344`, `:350` | “ContinueReadingActions” `home/HomeScreen.kt:453` | **same** routes. |
| Collapse/expand Continue Reading strip; See All beyond five works | “stripCollapsed.toggle”, “readingNow.count > 5” `Features/Home/HomeView.swift:375`, `:381` | “onToggleCollapse”, “works.size > 5” `home/HomeScreen.kt:445`, `:446` | **same**, hero remains visible. |
| Open queue / See All queues / fold queues | “AllReadingQueuesDestination”, “QueueCardMenu” `Features/Home/HomeView.swift:464`, `:468` | “onOpenQueue”, “onOpenQueues” `home/HomeScreen.kt:265`, `:277` | **same** routes. Queue Edit/Pin/Delete menu below. |
| New Queue | “New Queue” `Features/Home/HomeView.swift:276` | “onNewQueue” `home/HomeScreen.kt:155` → editor `:182` | **same** new-queue sheet entry; underlying common queue editor is A62 scope. |
| Open collection shelf work / collection See All / fold shelf | “NavigationLink”, “localWorkContextMenu” `Features/Home/HomeCollectionShelves.swift:43`, `:47` | “onOpenCollection”, “onToggleCollapse” `home/HomeScreen.kt:303`, `:304`; local card `:320` | **same** navigation; Home local-menu differences below apply. |
| Recently Updated See All / fold / open work | “localWorkContextMenu” `Features/Home/HomeView.swift:495`, reader `:505` | “onSeeAll”, “onToggleCollapse”, “onOpen” `home/HomeScreen.kt:335`, `:336`, `:360` | **same**, opens section and local reader. |
| Subscription See All / fold / tap local or remote cover | “remoteWorkContextMenu” `Features/Home/HomeCards.swift:227`; canonical destination `Features/Home/CanonicalWorkCoverCard.swift:57` | “onSeeAll”, “onToggle”, “onOpenRemote” `home/HomeScreen.kt:380`, `:393`, `:606` | **same** ordinary detail/local-reader routes; **missing F10/F11** remote-cover actions below. |
| Show/Hide mature; Select; Select All/Deselect All; toggle selected work; Done | “MatureRevealToggle”, “SelectAllButton”, “Select” `Features/Home/HomeView.swift:249`, `:283`, `:289` | “onTogglePrivacy”, “onSelectAll”, “onEnterSelect” `home/HomeScreen.kt:156`, `:159`, `:160`; “Done” `home/HomeBulkBar.kt:125` | **same** selection and gated session reveal. |
| Pull to refresh | “WorkMetadataRefresh.refresh(visibleHomeWorks)” `Features/Home/HomeView.swift:608`; prefixes `:614` | “refreshVisibleMetadata”, “loadSubscriptions” `home/HomeViewModel.kt:145`, `:147`; same 12+12 candidates `:157` | **same** visible local metadata and subscriptions refreshed. |
| Queue long-press Edit / Pin-Unpin / Delete | “QueueCardMenu” `Features/Home/HomeView.swift:468` | “onEdit”, “onPin”, “onDelete” `home/HomeScreen.kt:278`, `:279`, `:285` | **same** entry points; mandatory Delete/Cancel and recovery documented in the additional shared-action table. |

## Home local card menu and Home-only sheets

Applies to hero, strip, Recently Updated, collection-shelf covers and local Subscription covers. Home section lists instead use Library's shared local controls (next table).

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Read; Comments; Select; Work Details | “Read”, “Comments”, “Select”, “Work Details” `Features/Library/WorkCardActions.swift:349`, `:357`, `:362`, `:424` | same labels `home/HomeWorkMenu.kt:116`, `:121`, `:127`, `:176` | **same**, AO3 comments only when ID exists; Select only where parent permits. |
| Download / Remove Download / Kept Offline by… | “WorkDownloadButton” `Features/Library/WorkCardActions.swift:372` | “downloadAction”, “applyDownload” `home/HomeWorkMenu.kt:132`, `:140`, `:207` | **same** keep semantics; protected keep is disabled, imported original has no download action. |
| Favorite / Unfavorite; Later add/remove; Finished / Still Reading | “favorite”, “savedForLater”, “finished” `Features/Library/WorkCardActions.swift:378`, `:386`, `:401` | same operations `home/HomeWorkMenu.kt:143`, `:147`, `:162` | **same** state toggles. |
| Rebuild from Original | “Rebuild from Original” `Features/Library/WorkCardActions.swift:419` | “RebuildOriginalDialog” `home/HomeWorkMenu.kt:82`, menu `:171` | **same** action with confirmation/error presentation (Android always asks per recorded A62 fix). |
| Delete one work; Cancel | “Delete” + confirmation `Features/Library/WorkCardActions.swift:443`, `:460` | “Delete” `home/HomeWorkMenu.kt:180`, shared confirmation `:266` | **same** setting-controlled ask, unavailable-copy warning via `workDeletionMessage`, 90-day recovery. |
| Add to Queue: toggle membership, create, include series, dismiss | “AddToQueueView” `Features/Library/ReadingQueues.swift:438`; “Add” `:469`; series toggle `:503` | “QueueDialog” `home/HomeWorkMenu.kt:222`; “onPick” `:225`; “Close” `:326` | **different F02** add-only; closes after one queue, cannot remove, create in place, or include series. |
| Add to Collection: create / toggle memberships / dismiss | “AddToCollectionView”, “Add” `Features/Library/Collections.swift:598`, `:626` | “CollectionDialog”, “addToCollection”, “Add”, “Cancel” `home/HomeWorkMenu.kt:238`, `:246`, `:359`, `:361` | **different F03** can type/create and add to an existing collection, but no checked membership/removal or continuing through multiple collections. |
| Bulk Delete / Cancel | “confirmationDialog” `UIComponents/WorkBulkActionBar.swift:128` | “controller.deleteTargets = selectedWorks” `home/HomeBulkBar.kt:60`; setting applied `home/HomeWorkMenu.kt:275` | **different F01**, skips mandatory iOS bulk ask when setting off. |
| Bulk Download / Remove Download; Favorite/Unfavorite; Later add/remove; Finished/Still Reading | “WorkDownload.bulkAction”, “bulkFavorite”, “bulkToggleSavedForLater”, “bulkToggleFinished” `UIComponents/WorkBulkActionBar.swift:55`, `:66`, `:71`, `:97` | explicit actions `home/HomeBulkBar.kt:69`, `:75`, `:81`, `:85`, `:89`, `:96`, `:115`, `:119` | **same** achievable mutations; Android lists both directions instead of iOS's selection-aware single action. |
| Bulk Add to Queue / Collection | “AddToQueueView(works:)”, “AddToCollectionView(works:)” `UIComponents/WorkBulkActionBar.swift:120`, `:123` | “queueTargets = selectedWorks”, “collectionTargets = selectedWorks” `home/HomeBulkBar.kt:105`, `:109` | **different F02/F03**, same restricted Home dialogs. |
| Bulk Tag: type Add, existing tag toggle/all-some-none, Done | “addTypedTag”, “some”, tag button `UIComponents/WorkBulkTagSheet.swift:34`, `:73`, `:83` | “Tag name”, “Add”, “addUserTag” `home/HomeWorkMenu.kt:375`, `:381`, `:260` | **missing F04** existing tag states/removal. Typed Add/Cancel work. |

## Home section list — Reading Now / Recently Updated

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Filter; long-press Clear All Filters; Reset/Apply | “FilterButton…onClearFilters” `Features/Home/HomeSectionListView.swift:185` | “FilterButton…onClearFilters” `home/HomeSectionListScreen.kt:277`, `:281`; panel `:523` | **same**, shared Library panel. |
| Quick Recently Updated pill / Show All when no matches | “Show All” `Features/Home/HomeSectionListView.swift:306` | “onUpdatePillChange” `home/HomeSectionListScreen.kt:386` | **same** local narrowing and reset. |
| Show/Hide Mature, Select, Layout, Expand/Collapse All | “MatureRevealToggle”, “DisplayModeMenuPicker”, “ExpandAllMenuItem” `Features/Home/HomeSectionListView.swift:193`, `:201`, `:204` | menu and layout `home/HomeSectionListScreen.kt:291`, `:329` | **same** Compact/Detailed/Ledger and detailed expansion. |
| Select All/Deselect All; per-work select; bulk actions; Done | “SelectAllButton”, “WorkBulkActionBar” `Features/Home/HomeSectionListView.swift:160`, `:164` | “WorkBulkActionBar” `home/HomeSectionListScreen.kt:480`; selection chrome `:268` | **same** uses the corrected Library bulk bar, not Home dashboard's restricted one. |
| Work tap; local menu; Download/Favorite leading swipe, Delete trailing swipe | “localWorkContextMenu”, “WorkDownloadButton”, “Delete” `Features/Home/HomeSectionListView.swift:448`, `:267`, `:290` | “LibrarySubjectLedgerRow”, shared `cardActions` `home/HomeSectionListScreen.kt:439`, `:442` | **same** shared Library actions; individual deletion asks according to preference. |
| Pull refresh | “WorkMetadataRefresh.refresh(visibleItems)” `Features/Home/HomeSectionListView.swift:139` | “visibleItems.forEach…refresh” `home/HomeSectionListScreen.kt:369`, `:396` | **same**, corrected at this HEAD. |

## Search — idle and local matches

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Type query / clear / submit AO3 search | “GlassFieldBar”, “Clear search” `Features/Search/SearchView.swift:611`, `:620` | “onQueryChange”, “onClearQuery”, “onSubmit” `search/SearchScreen.kt:314`–`:316` | **same** local-first, explicit submit. |
| Back through search history / leave Search | “goBack” `Features/Search/SearchView.swift:214` | “onBack = ::goBack” `search/SearchScreen.kt:317` | **same** explicit back handler; native Android back is its chrome. |
| Run saved search | “runSaved(saved)” `Features/Search/SearchView.swift:428` | “onRun” `search/SearchScreen.kt:477` | **same** saved filters/query run. |
| Delete saved search | “onDelete” `Features/Search/SearchView.swift:442` | “Delete saved search?” `search/SearchScreen.kt:282` | **different F09**, additional permanent-delete confirmation. |
| Search AO3 for query; tap AO3 fandom; Library fandom; local tag; collection | “onSearchAO3”, “onSearchFandom”, “filterLibrary”, “NavigationLink” `Features/Search/SearchLocalResultsList.swift:31`, `:76`, `:66`, `:97`, `:107` | callbacks `search/SearchScreen.kt:902`, `:947`, `:932`, `:961`, `:975` | **same** destinations. Collection long-press menu is absent (**F08**). |
| Open local work / work context menu and swipes | “SensitiveWorkRow”, “libraryWorkSwipeActions” `Features/Search/SearchLocalResultsList.swift:42`, `:51` | “onOpenWork(it.toRemoteSummary())” `search/SearchScreen.kt:383`; “onLongClick…onSelect” `:919` | **different F08** detail instead of reader; long press selects rather than offering Read/Comments/Download/Favorite/Later/Queue/Finished/Collection/Rebuild/Details/Delete. No corresponding swipes here. |
| Reveal obscured local work | “SensitiveWorkRow” `Features/Search/SearchLocalResultsList.swift:42` | “onReveal” `search/SearchScreen.kt:917` | **same** single-work gate. |
| Select local matches / select all / toggle selection / bulk / Done | “isSelectingLocal”, “WorkBulkActionBar”, “SelectAllButton” `Features/Search/SearchView.swift:183`, `:196`, `:189` | “localSelecting”, “onToggleSelectAll”, “WorkBulkActionBar” `search/SearchScreen.kt:330`, `:352`, `:489` | **same** shared Library bulk actions. |
| Show/Hide Mature from More | “MatureRevealToggle” `Features/Search/SearchView.swift:246` | More menu `search/SearchScreen.kt:689` only Select/Expand | **missing F06**. |
| Paste URL and submit | “onSubmit: runSearch” `Features/Search/SearchView.swift:611` (no address diversion here) | “url != null…onOpenUrl” `search/SearchScreen.kt:263` | **Android only** direct URL entry shortcut. |

## Search — AO3 results

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Tap work, byline, fandom/tag, expand card | “cardNavigation”, “router.searchAO3”, “expandButton” `UIComponents/RemoteWorkSelection.swift:220`; `Features/Search/AO3WorkRow.swift:149`, `:516`, `:577` | “onOpenWork”, “onTagClick”, “onSortSelected” `search/SearchScreen.kt:432`, `:437`, `:441`; shared row `ui/components/SensitiveWorkRow.kt:196` | **same** ordinary detail/search/expand actions; shared bylines use author identities. |
| Result context menu and swipes | “remoteWorkContextMenu” `Features/Search/AO3WorkRow.swift:64` | shared row “showMenu” `ui/components/SensitiveWorkRow.kt:703` | **missing F10** full remote actions; **different F11** inert Copy Link. Shared table below. |
| Sort; filter-summary edit; Filter; long-press clear; pull refresh; retry | “Picker(\"Sort\")”, “onEditFilters” `Features/Search/SearchResultsHero.swift:132`, `:164`; “refreshCurrentResults”, “Try Again” `Features/Search/SearchView.swift:399`, `:676` | “onSortSelected”, “onOpenFilters”, “onClearFilters”, “onRefresh”, “onRetry” `search/SearchScreen.kt:318`, `:319`, `:441`, `:447`, `:462` | **same** search operations. Shared filter/paging tables below. |
| Select / tap-toggle / Done | “RemoteWorkSelectionToolbar” `Features/Search/SearchView.swift:180` | “RemoteWorkSelectionBar” `search/SearchScreen.kt:506` | **same** selection; Android Cancel ends it without undoing completed saves. iOS remote toolbar has no Select All; Android also has a Select All shortcut. |
| Bulk Download/Save for Later | “bulkSave”, “bulkSaveForLater” `UIComponents/RemoteWorkSelection.swift:143`, `:155` | “saveToLibrary”, “saveForLater” `search/SearchScreen.kt:513`, `:523` | **same** Later queue action; **different F17** Download stores metadata only. Failure reporting also differs (**F12**). |
| Bulk Add to Collection / Add to Queue | same labels `UIComponents/RemoteWorkSelection.swift:169`, `:178` | bar callers only `onSaveToLibrary`/`onSaveForLater` `search/SearchScreen.kt:509`, `:518` | **missing F05**. |
| Show/Hide Mature | “MatureRevealToggle” `Features/Search/SearchView.swift:236` | menu `search/SearchScreen.kt:689` | **missing F06**. |

## Shared remote work menu — Search, Browse works, Account remote rows, author works, series works

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Read; Comments | “Read”, “Comments” `Features/Library/WorkCardActions.swift:615`, `:622` | complete menu “Open Work”, “Copy Link” `ui/components/SensitiveWorkRow.kt:706`–`:719` | **missing F10** direct reader/comments actions. Opening Work Detail is a fallback, not action parity. |
| Download/Remove Download/Kept Offline by…; Later add/remove | “WorkDownloadButton”, “toggleSavedForLater” `Features/Library/WorkCardActions.swift:638`, `:652`; leading swipe `:560` | same complete two-item menu `ui/components/SensitiveWorkRow.kt:706` | **missing F10** context and swipe actions; shared row supplies neither. |
| Add to Queue; Finished/Still Reading; Add to Collection | corresponding labels/handlers `Features/Library/WorkCardActions.swift:664`, `:669`, `:679` | same two-item menu `ui/components/SensitiveWorkRow.kt:706` | **missing F10**. |
| Delete locally saved work / Cancel | “existingLocalWork.isSaved”, “Delete” `Features/Library/WorkCardActions.swift:625`, `:633`; setting-controlled ask `:627` | menu `ui/components/SensitiveWorkRow.kt:706` | **missing F10** local removal at result; iOS uses Recently Deleted, never deletes AO3 work. |
| Work Details | “Work Details” `Features/Library/WorkCardActions.swift:684` | “Open Work” `ui/components/SensitiveWorkRow.kt:708` | **same** destination, different label. |
| Copy Link | full iOS menu ends at Work Details `Features/Library/WorkCardActions.swift:683`–`:686` | “Copy Link” handler only `showMenu = false` `ui/components/SensitiveWorkRow.kt:715`–`:718` | **Android only, broken F11** — no clipboard write, no message. |

## AO3 filter sheet — Search, fandom/tag works and account/author refine variants

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Sort by / Order | “Sort by”, “Order” `Features/Search/AO3FilterPanel.swift:251`, `:262` | same `search/SearchFilterSheet.kt:145`, `:153` | **same**, relevance constrained on Browse. |
| Rating / Match / Include Not Rated | same labels `Features/Search/AO3FilterPanel.swift:268`, `:286`, `:294` | same `search/SearchFilterSheet.kt:168`, `:173`, `:178` | **same** controls. |
| Cycle each warning/category include → exclude → clear | “toggle”, “Include”, “Exclude” `Features/Search/AO3FilterPanel.swift:549`, `:559`, `:563` | “cycleWarning”, “cycleCategory” `search/SearchFilterSheet.kt:190`, `:200` | **same** tri-state. |
| Crossovers; Completion; Chapters; Updated | pickers `Features/Search/AO3FilterPanel.swift:320`, `:325`, `:332`, `:351` | choices `search/SearchFilterSheet.kt:208`, `:214`, `:219`, `:227` | **same** full search; refine intentionally limits server-only fields on both sides. |
| After/Before enable and date selection; Language picker | “DatePicker”, “FilterLanguagePicker” `Features/Search/AO3FilterPanel.swift:537`, `:362` | “FilterDateRow”, “FilterLanguageRow” `search/SearchFilterSheet.kt:231`, `:233`, `:236` | **same** controls. |
| Fandom / Character / Relationship / Additional Tags picker; search suggestions; include/exclude/clear; cycle chip; Done | “TagSelectField”, “selectionLabel”, “Done” `Features/Search/TagSelectField.swift:228`, `:291`, `:309`; tags group `Features/Search/AO3FilterPanel.swift:505` | “FilterTagRow” `search/SearchFilterSheet.kt:242`, `:248`, `:253`, `:258`; `search/FilterTagPicker.kt:138` | **same** tag field entry points; per-field selection mechanics inventoried below (chips cycle rather than having a separate remove cross). |
| Title / Creator; Words / Hits / Kudos / Comments / Bookmarks ranges, exact entry | same fields `Features/Search/AO3FilterPanel.swift:413`, `:414`, `:431`, `:448`, `:457`, `:466`, `:475` | same `search/SearchFilterSheet.kt:266`, `:268`, `:273`, `:281`, `:286`, `:291`, `:296` | **same** search controls and supported bounds. |
| Reset; Apply/Search; dismiss unapplied draft; Save Search | “Reset filters”, “confirm”, “Save Search…” `Features/Search/AO3FilterPanel.swift:192`, `:195`, `:384`; close restore `Features/Search/SearchView.swift:271` | reset/confirm `search/SearchFilterSheet.kt:108`, `:117`; save `:301`; close discard `search/SearchScreen.kt:548` | **same** intended draft/apply behavior; Android also offers Close row. |

## Save Search sheet

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Name; Cancel; Save after reviewing query/filters | “Name”, “Cancel”, “Save” `Features/Search/SaveSearchSheet.swift:37`, `:92`, `:95` | “onNameChange”, “onSave”, “onDismiss” `search/SearchScreen.kt:567`–`:569` → Cancel/Save/name field `search/SaveSearchSheet.kt:79`, `:91`, `:102` | **same** entry, review and storage. Opens above filter panel at this HEAD per 3ey; no confirmation/undo. |

## Shared page navigator — Search, fandom/tag results, account lists and collections

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Previous/Next; first/last via long-press | “navButton”, “endLabel” `Features/Search/SearchPaginationBar.swift:185`, `:233` | previous/next `ui/components/KudosPaginationBar.kt:85`, `:107`; first/last `:82`, `:110` | **same** destinations; Android provides explicit first/last buttons. |
| Open page picker; drag range; exact number; nearby page; First/Last preset; Go/Cancel | page label `Features/Search/SearchPaginationBar.swift:63`; exact `:392`; nearby `:427`; First/Last `:465`, `:467`; Cancel/confirm `:355`, `:363` | picker `ui/components/KudosPaginationBar.kt:93`, slider `:176`, presets `:234`, `:241`, Cancel/Go `:249`, `:260` | **same** picker/slider/Nearby/presets/Go/Cancel; **missing F21** typed exact page number. Android nearby tiles are `ui/components/KudosPaginationBar.kt:210`. |

## Browse root — NativeBrowseView / MediaBrowserView

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Category → fandom list; featured fandom chip; Jump Back In → fandom works | “NavigationLink(value: category)”, “onSelectFandom” `Features/Search/MediaBrowserView.swift:158`, `:354`; jump `:256` | “onOpenCategory(category)”, “onOpenFandom” `browse/BrowseScreen.kt:193`, `:194`; Jump Back In `:184` | **same** native destinations. |
| Reload catalog by pull; retry failed catalog | “refreshable”, “Try Again” `Features/Search/MediaBrowserView.swift:184`, `:122` | “KudosRefreshBox…loadNow” `browse/BrowseScreen.kt:146` | **same** refresh; failures retain local context. |
| Open AO3 Website | browser button `Features/Search/MediaBrowserView.swift:193` | “onOpenWebFallback(AO3BrowseUrls.mediaIndexUrl())” `browse/BrowseScreen.kt:202` | **same** fallback entry, restricted fallback capabilities below. |

## Fandom list — category, single tags and grouped families

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Search; clear search; A–Z/Most Works sort; Group variants | “searchable”, “sort = option”, “groupsVariants.toggle” `Features/Search/FandomListView.swift:244`; `Features/Search/FandomFamilyRows.swift:246`, `:258` | “onSort”, “onGroupsVariants” `browse/FandomListScreen.kt:192`, `:193`; search `:199` | **same** actions; stars/downloaded/read marks are indicators, not favorite buttons. |
| Tap individual fandom / family union / family member | “onSelect([member.originalName])”, “family.includedFilterNames” `Features/Search/FandomListView.swift:364`, `:381`, `:384` | “onOpenFamily(family)” `browse/FandomListChrome.kt:280`; member rows `:322` | **same**, family union now resolves all member IDs (recorded A58 fix). |
| Alphabet index tap/drag; screen-reader next/previous letter | “Fandom index” `Features/Search/FandomListView.swift:303` | “scrollToItem(index)” `browse/FandomListScreen.kt:269`; gesture `browse/FandomListChrome.kt:385` | **same** letter tap/drag scroll navigation; **missing F32** screen-reader next/previous available-letter action (iOS `Features/Search/FandomListView.swift:305`, no corresponding Android semantic action). |
| Filter / long-press reset / Clear Search and Filters when empty / pull refresh | “onClearFilters”, “Clear Search and Filters”, “refreshable” `Features/Search/FandomListView.swift:254`, `:201`, `:240` | “onClearFilters”, empty clear, “loadNow” `browse/FandomListScreen.kt:157`, `:228`, `:162` | **same** recovery actions. |

## Fandom-list filter sheet

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Minimum works; hide RPF / All Media Types / Related Fandoms; favorites only; downloads only; multi-tag only | groups `Features/Search/FandomListFilterSheet.swift:39`, `:58`, `:71`, `:116` | “Minimum works”, six toggles `browse/FandomListChrome.kt:452`, `:474`, `:477`, `:480`, `:485`, `:488`, `:493` | **same** options, multi-tag requires Group variants. |
| Reset; Apply “Show N tags”; dismiss without apply | “Reset”, “onApply” `Features/Search/FandomListFilterSheet.swift:107`, `:172`; draft apply `Features/Search/FandomListView.swift:141` | “Reset”, “onApply(draft)” `browse/FandomListChrome.kt:450`, `:506`; caller `browse/FandomListScreen.kt:287` | **same** staged changes. |

## Fandom works / tag works

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Work tap; byline/tag links; expand; context menu; swipes | “SelectableAO3WorkRow” `Features/Browse/NativeBrowseView.swift:208`; tag equivalent `:565` | “SensitiveWorkRow” `browse/FandomWorksScreen.kt:311` | **same** basic detail/links/expand; **F10/F11** shared remote-menu gaps. |
| Filter/edit summary/sort; Clear Filters; retry; page navigation; pull refresh | “Clear Filters”, “Try Again”, “refreshable” `Features/Browse/NativeBrowseView.swift:288`, `:302`, `:223`; tag `:664`, `:678`, `:580` | “onClearFilters”, “onRefresh”, shared pagination `browse/FandomWorksScreen.kt:166`, `:252`, `:321` | **same**, shared search filter and pager tables apply. |
| Select; tap toggle; Download/Save for Later; Done | “RemoteWorkSelectionToolbar” `Features/Browse/NativeBrowseView.swift:454`, `:613`; “Select” `:468`, `:626` | “Select”, “RemoteWorkSelectionBar” `browse/FandomWorksScreen.kt:179`, `:334` | **same** basic selection/Later; **different F17** Download stores metadata only. Status dialog `:362` correctly reports returned batch results. |
| Add selected works to Queue/Collection | “RemoteWorkBulkActionBar” `UIComponents/RemoteWorkSelection.swift:166`, `:175` | only two save callbacks `browse/FandomWorksScreen.kt:337`, `:346` | **missing F05**. |
| Show/Hide Mature | “MatureRevealToggle” `Features/Browse/NativeBrowseView.swift:465`, `:623` | complete menu `browse/FandomWorksScreen.kt:176` | **missing F06**. |

## AO3 website fallback — AO3WebBrowserView

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Back through web history | “model.goBack()” `Features/Browse/BrowseView.swift:54` | “wv.goBack()” `web/AO3WebViewFallbackScreen.kt:101` | **same**. |
| Done closes browser regardless of web history | “dismiss()” `Features/Browse/BrowseView.swift:82` | only Back/history `web/AO3WebViewFallbackScreen.kt:99` | **missing F13** direct close; repeated Back needed after several pages. |
| Address/search entry; Reload | “loadFromAddressBar”, “Reload” `Features/Browse/BrowseView.swift:97`, `:107` | title-only header `web/AO3WebViewFallbackScreen.kt:103`; reload only error Retry `:135` | **missing F13** normal-page address/search/reload actions. |
| Bookmark current AO3 page | “Add Bookmark”, “Bookmarked …” `Features/Browse/BrowseView.swift:78`, `:147` | complete header `web/AO3WebViewFallbackScreen.kt:99`–`:111` | **missing F13** saved AO3 link creation and banner. |
| Capture EPUB download into Library | “onImport”, “Saved … to Library”, “Couldn't save EPUB.” `Features/Browse/BrowseView.swift:130`, `:135`, `:137` | WebView creation ends after client/theme/load, no download listener `web/AO3WebViewFallbackScreen.kt:144`–`:207` | **missing F14** web EPUB acquisition path and result message. |
| Open current page in external Browser; error Retry | no equivalent external-browser header item `Features/Browse/BrowseView.swift:51` | “Browser”, “Retry” `web/AO3WebViewFallbackScreen.kt:110`, `:136` | **Android only** useful escape/retry; does not supply the missing native import/bookmark actions. |

## Tag picker / Language picker / numeric range editor

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Search AO3 tags; tap selected/result to include, exclude, clear; Done | “Results”, “cycle(tag)”, “Done” `Features/Search/TagSelectField.swift:195`, `:176`, `:228` | autocomplete `search/FilterTagPicker.kt:101`, selected/result cycle `:138`, `:159`, Done `:128` | **same** tri-state changes. Android also offers typed freeform names/local candidates (`:110`–`:114`). |
| Choose from Popular in current fandom without typing | “Popular in …”, “tagRows(popular)” `Features/Search/TagSelectField.swift:185`, `:191` | complete suggestion pipeline is typed + local + remote autocomplete `search/FilterTagPicker.kt:93`–`:114` | **missing F22** contextual popular suggestions to tap. |
| Cycle a selected chip outside picker | “onTapGesture(perform: onCycle)” `Features/Search/TagSelectField.swift:414` | “FilterTagCapsule…cycle” `search/FilterTagPicker.kt:84`, `:199` | **same**; tap cycles, not a dedicated remove cross. |
| Language selection / search; range slider / exact lower-upper entries | “FilterLanguagePicker”, “FilterRangeSlider” `Features/Search/AO3FilterPanel.swift:362`, `:432` | “FilterLanguageRow”, “FilterRangeSlider” `search/SearchFilterSheet.kt:236`, `:273` | **same**: I language search/selection `Features/Search/FilterLanguagePicker.swift:17`, `:43`, numeric fields `Features/Search/FilterRangeSlider.swift:68`, `:79`; A language search/selection `search/FilterLanguagePicker.kt:75`, `:83`, range/fields `search/FilterRangeSlider.kt:65`, `:110`. |

## Comments list — CommentsView

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Pull to refresh / Try Again on failure | “refreshable”, “Try Again” `Features/Comments/CommentsView.swift:193`, `:682` | “viewModel.refresh”, “viewModel.retry” `comments/CommentsScreen.kt:382`, `:579` | **same**, cached data is marked as cached rather than presented as fresh. |
| Browse by chapter; pick All Comments/chapter; close picker | “Browse comments by chapter”, “All Comments”, chapter row `Features/Comments/CommentsView.swift:603`, `:931`, `:961` | “onSelectAll”, “onSelectChapter”, “onDismiss” `comments/CommentsScreen.kt:322`, `:326`, `:330` | **same** scope route. |
| Oldest First / Newest First | same labels `Features/Comments/CommentsView.swift:615`, `:624` | same `comments/CommentsScreen.kt:541`, `:551` | **same**, newest initially (recorded 3df). |
| Previous / Next page | same labels `Features/Comments/CommentsView.swift:787`, `:800` | same `comments/CommentsScreen.kt:651`, `:668` | **same** paging, no arbitrary-page picker on either comments screen. |
| Write a comment / Log in to comment; restricted-page login | “Write a comment”, “Log in to comment” `Features/Comments/CommentsView.swift:850` | same `comments/CommentsScreen.kt:703`; restricted login `:590` | **same** composer/login entry, not exercised with a real account. |
| Close; expand modal comments to full screen | “Close”, “Expand to full screen” `Features/Comments/CommentsView.swift:322`, `:331` | “onBack”, “onRequestExpand” `comments/CommentsScreen.kt:247`, `:255` | **same** entry actions where presented modally. |
| Expand nested replies; collapse/expand root; Continue Thread | “expandRepliesButton”, “onToggleCollapse”, “continueThreadButton” `Features/Comments/CommentThreadRow.swift:837`, `:1301`, `:844` | “onExpand”, “onToggleCollapse”, “onContinueThread” `comments/CommentsScreen.kt:638`–`:640` | **same** list controls, isolated-thread behavior below. |
| View linked commenter profile (name/avatar) | “CommentAuthorAvatarButton”, “View … profile” `Features/Comments/CommentThreadRow.swift:1328`, `:1725` | “onOpenAuthor” handler `comments/CommentsScreen.kt:216`; name/avatar callbacks `comments/CommentThreadComponents.kt:464`, `:500` | **same** linked-account route, guest text is not a guessed account; ordinary comment bodies have no hyperlink action on either platform. |
| Reply / Log in to Reply (button, overflow, leading swipe) | labels `Features/Comments/CommentThreadRow.swift:1466`, `:1487`, `:1900` | same menu `comments/CommentThreadComponents.kt:821`, `:832`; handler `comments/CommentsScreen.kt:204` | **same** from main comments list, opens reply composer after login as applicable. |
| Edit Comment (overflow/trailing swipe) | “Edit Comment”, “Edit” `Features/Comments/CommentThreadRow.swift:1492`, `:1919` | “Edit Comment” `comments/CommentThreadComponents.kt:845`; handler `comments/CommentsScreen.kt:205` | **same** own editable comments only, prefilled editor. |
| Copy Link (overflow/trailing swipe) | “Copy Link” `Features/Comments/CommentThreadRow.swift:1496`, `:1911` | “Copy Link” `comments/CommentThreadComponents.kt:857`; actual clipboard write `comments/CommentsScreen.kt:210` | **same** — this Copy Link works, unlike remote work cards. Android system clipboard supplies feedback (recorded 2026-10-11). |
| Thread / Parent Thread | same labels `Features/Comments/CommentThreadRow.swift:1500`, `:1505` | same `comments/CommentThreadComponents.kt:869`, `:883`; “pushedThreadRootId = commentId” `comments/CommentsScreen.kt:213` | **different F25** navigation target changes instead of iOS's within-thread scroll/highlight; isolated-thread table below. |
| Delete Comment (overflow/trailing swipe); Cancel | “Delete Comment”, “Delete this comment?”, “Cancel” `Features/Comments/CommentThreadRow.swift:1510`; `Features/Comments/CommentsView.swift:300`–`:302` | “Delete Comment”, “Delete this comment?”, “Cancel” `comments/CommentThreadComponents.kt:896`; `comments/CommentsScreen.kt:270`, `:285` | **same** mandatory ask; “cannot be undone” `:271`; success “Comment deleted.” `comments/CommentsViewModel.kt:771`, errors in AO3 alert. |

## Isolated Comment Thread — CommentThreadScreen

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Back to full Comments; read every nested reply | “rows(for: root)”, fully expanded `Features/Comments/CommentThreadScreen.swift:128`–`:133` | “BackHandler”, “Int.MAX_VALUE” `comments/CommentThreadScreen.kt:35`, `:61`, `:62` | **same** full subtree; no intended collapse control here. |
| Reply; Edit; Delete + confirmation; action-result alert | “commentSwipeActions”, “commentThreadHandlers” `Features/Comments/CommentThreadScreen.swift:72`, `:75`; parent-hosted composer/alert `Features/Comments/CommentsView.swift:300` | handlers set model/pending state `comments/CommentsScreen.kt:204`–`:206`, but thread branch returns at `:236`, before dialog `:268` and composer `:334` | **missing F07** while thread is shown. Back allows pending UI to render; this is not a source claim that drafts/posts are lost. |
| Copy Link; linked author | “commentSwipeActions” `Features/Comments/CommentThreadScreen.swift:72` | shared handlers passed `comments/CommentsScreen.kt:233` | **same**, callbacks act immediately and do not depend on a later-rendered sheet. |
| Thread/Parent Thread within subtree / above root | “proxy.scrollTo(commentID)”, outside-root dismiss `Features/Comments/CommentThreadScreen.swift:151`, `:164` | same handler “pushedThreadRootId = commentId” `comments/CommentsScreen.kt:213`, reused `:233` | **different F25** replaces root instead of scrolling/highlighting within it or popping to parent Comments for an outside ancestor. Back returns to full Comments rather than a previous subtree. |

## Comment / Reply / Edit composer

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Type/edit text; Post new/reply; Save edit | “TextEditor”, “submit”, “canPost” `Features/Comments/CommentsView.swift:1390`, `:1334`, `:1444` | “BasicTextField”, “onSubmit”, “canPost”, Post/Save `comments/CommentComposerSheet.kt:249`, `:159`, `:101`, `:112` | **same** nonblank, signed-in, character-budget gate, read-only while sending; shared one-shot/verification guard present. |
| Cancel / Back / sheet dismiss keeps draft | “saveDraft”, on-disappear save `Features/Comments/CommentsView.swift:1327`, `:1364` | “closeComposer…saveDraft” `comments/CommentsViewModel.kt:646`, `:647`; dismiss `comments/CommentComposerSheet.kt:115` | **same** ordinary comment/reply drafts; edit drafts intentionally excluded on both sides. No “discard draft” confirmation. |
| Tap parent author in reply quote | “View … profile” `Features/Comments/CommentsView.swift:1505` | “onOpenAuthor” `comments/CommentComposerSheet.kt:211` | **same** linked profile route; draft persists through close. |
| Check Again after ambiguous post; dismiss result/error | “Check Again”, “Posted.” `Features/Comments/CommentsView.swift:1553`, `:1563` | “Check Again”, “OK” alert `comments/CommentsScreen.kt:301`, `:305`; “Posted.” / “Comment updated.” `comments/CommentsViewModel.kt:844` | **same** operation rechecks rather than reposts. Android uses an alert over the composer instead of iOS inline status; no duplicate post is implied. |
| Open quick formatting / full tray | “CommentFormatBar”, “CommentFormattingTray” `Features/Comments/CommentsView.swift:1310`, `:1320` | “CommentFormatBar”, “CommentFormattingTray” `comments/CommentComposerSheet.kt:308`, `:316` | **same** edits local text/selection. |

## Comment formatting tray and quick bar

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Bold, Italic, Underline, Strike, Superscript, Subscript, Small, Code | cases `Features/Comments/CommentMarkup.swift:32`; quick/tray buttons `:278`, `:465` | entries `comments/CommentMarkup.kt:75`–`:82`; apply `:294` | **same** selectable tag actions. |
| Quote, Bullets, Numbers, Heading, Divider, Link, Spoiler | cases `Features/Comments/CommentMarkup.swift:34` | entries `comments/CommentMarkup.kt:85`–`:91` | **same** tag vocabulary and insertion entry point. |
| Choose heading level h1–h6 / re-level | “headingLevels”, “headingLevel: level” `Features/Comments/CommentMarkup.swift:476`, `:479` | “headingLevels”, “applyTag…level” `comments/CommentMarkup.kt:325`, `:329` | **same** action; no extra AO3 write until Post. |
| Done / dismiss tray | “Done” `Features/Comments/CommentMarkup.swift:418` | “onDismissRequest = onDismiss” `comments/CommentMarkup.kt:256`; most tags close `:295` | **same** close action via Android sheet dismissal; Android navigation chrome is allowed to differ. |

## Account hub — AccountView / AccountComponents

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Log In / Log In Again when signed out/expired | “onLogin” `Features/Account/AccountComponents.swift:328` | “onLogin” `account/AccountScreen.kt:668` | **same** login entry only; never signed in during audit. Preview reading/writing/activity rows are informational on both sides. |
| View Profile via avatar/header | “View Profile” `Features/Account/AccountComponents.swift:72` | “onOpenAuthorProfile” `account/AccountScreen.kt:478` | **same** native author route through `native:profile`. |
| Posting as: Account Default / choose pseud | “Posting as” `Features/Account/AccountComponents.swift:152`; choices `:119`, `:128` | “Account Default” and pseud choices `account/AccountScreen.kt:563`, `:578` | **same** posting identity selection. |
| Verify Session; Open on AO3 | “Verify Session”, “Open on AO3” `Features/Account/AccountComponents.swift:258`, `:269` | same menu `account/AccountScreen.kt:730`, `:736` | **same** requested verification/web route. |
| Log Out; Cancel / confirm | “Log Out”, “logOutConfirmation” `Features/Account/AccountComponents.swift:278`, `:291` | “Log Out”, confirmation `account/AccountScreen.kt:748`, `:765` | **same** mandatory logout confirmation and local session removal. |
| Reading: Marked for Later, Bookmarks, Collections, Subscriptions | routes `Features/Account/AccountView.swift:669`–`:672` (also hub rows) | corresponding callbacks `account/AccountScreen.kt:268`, `:275`, `:282`, `:289` | **same** native screens. |
| Writing: Works, Series, Drafts; Activity: History, Inbox | routes `Features/Account/AccountView.swift:673`–`:677` | callbacks `account/AccountScreen.kt:302`, `:309`, drafts row `:315`, History/Inbox `:325`, `:331` | **same** native screen entry points. |
| Preferences; More on AO3 | native rows `Features/Account/AccountView.swift:689`, `:695` | Preferences `account/AccountScreen.kt:343`; More popup routes `:376`; dedicated page via shortcut `:254` | **same** Preferences; **different F29** More on AO3 hub row opens the subset popup, not the full page. |
| Open any configured shortcut; edit shortcuts | “openShortcut”, Shortcuts “onSeeAll” `Features/Account/AccountView.swift:666`, `:660` | grid “onOpen”, edit “onSeeAll” `account/AccountScreen.kt:929`, `:912` | **same** direct destination (not just old scope tab). |
| Pull refresh account | “refreshCurrentTab” `Features/Account/AccountView.swift:297` | “viewModel.refreshProfile” `account/AccountScreen.kt:213` | **same** requested profile refresh. |

## Account shortcut editor

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Add/remove shortcut; reorder chosen grid | “Add … / Remove …”, selected section move `Features/Account/AccountShortcuts.swift:192`, `:128` | “remove”, move earlier/later `account/AccountShortcutsEditor.kt:56`, `:63`, `:67`; available `:89` | **same** mutation with Android arrow ordering instead of drag chrome. |
| Reset to Default; Done | same labels `Features/Account/AccountShortcuts.swift:151`, `:166` | same `account/AccountShortcutsEditor.kt:102`, `:45` | **same** live persisted choices; dismissal is not undo. |

## Account lists — shared AO3AccountWorksList controls

Applies to the individual History, Bookmarks, Marked for Later and Subscriptions screens below. Own Works routes to the author screen, not this generic renderer.

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Log In; retry first/later page; page navigator; pull refresh | “Log In to AO3”, “Try Again”, “refreshable” `Features/Bookmarks/AO3AccountWorksList.swift:917`, `:484`, `:723` | “Log In Again”, “Retry”, “onLoadPage” `account/AccountWorksListScreen.kt:413`, `:423`, `:457`; refresh wrappers in each browser | **same** entry/recovery, shared pager lacks exact entry (**F21**). |
| Filter/refine currently loaded page; Clear Filters; Apply/close | “FilterButton”, “Clear Filters” `Features/Bookmarks/AO3AccountWorksList.swift:299`, `:719` | “FilterButton”, refine sheet `account/AccountWorksListScreen.kt:257`, `:515` | **same** client-side refinement; not a claim to filter unloaded AO3 pages. |
| Show/Hide Mature | “MatureRevealToggle” `Features/Bookmarks/AO3AccountWorksList.swift:305` | same gated toggle `account/AccountWorksListScreen.kt:283`–`:295` | **same** — Android is right here; the omission is specific to Search/Browse/author menus. |
| Compact / Detailed / Ledger; Expand/Collapse All | “DisplayModeMenuPicker” `Features/Bookmarks/AO3AccountWorksList.swift:315` | “Layout”, “Expand All” `account/AccountWorksListScreen.kt:303`, `:311`; Compact default `:166` | **same** available list modes, with fixed ledger-only Marked for Later/Subscriptions on both sides. |
| Open local matched work; local work menu | “SensitiveWorkRow” `Features/Bookmarks/AO3AccountWorksList.swift:661`; reader destination and menu `Features/Privacy/MatureContent.swift:231`, `:258` | “PairedWorkRow”, “onOpenWork(work.remote)” `account/AccountWorksListScreen.kt:1716`, `:1737`; local overload just passes nullable long-click `ui/components/SensitiveWorkRow.kt:776` | **different F20** opens detail instead of reader; no local context menu (Read/Comments/Download/Favorite/Later/Queue/Finished/Collection/Rebuild/Details/Delete). Reveal still works. |
| Open remote work; remote menu/swipes; byline/tag; card expansion | “EnrichingAO3WorkRow” `Features/Bookmarks/AO3AccountWorksList.swift:1179` | “EnrichingWorkRow” → “SensitiveWorkRow” `account/AccountWorksListScreen.kt:1749`, `:1774` | **same** basic detail/links/expand; **missing F10**, inert Copy Link **F11**. |

## AO3 History — AO3HistoryWorksBrowser

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Everything / In progress / Finished; Reset; empty Reset | “AO3HistoryFilterRail”, “Reset” `Features/Bookmarks/AO3HistoryWorksBrowser.swift:200`, `:224`; empty `:125` | same pills `account/AccountWorksListScreen.kt:1016`–`:1018`; browser filter `:931` | **same** page-local progress filtering. |
| Delete from history; Cancel; dismiss failure | “Delete from history” `Features/Bookmarks/AO3HistoryWorksBrowser.swift:145`; confirm/error `Features/Bookmarks/AO3AccountWorksList.swift:390`, `:413` | same confirm, true gate, writer call/error `account/AccountWorksListScreen.kt:944`, `:951`, `:960`, `:972` | **same** AO3 reading entry only, leaves work; Android button substitutes iOS swipe. No undo. |
| Clear entire history; Cancel; failure OK | “Clear your entire history?”, “Clear History” `Features/Bookmarks/AO3AccountWorksList.swift:407`–`:410` | identical copy and mandatory ask `account/AccountWorksListScreen.kt:240`–`:246` | **same** native clear write, visible list emptied only on confirmed result. |
| Work cards, layout, paging, refresh, filters | shared browser `Features/Bookmarks/AO3AccountWorksList.swift:563` | History dispatch `account/AccountWorksListScreen.kt:484` | Shared account-list table applies, including **F20/F10/F11/F21**. |

## AO3 Bookmarks — AO3BookmarksWorksBrowser

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| All / Recs / Private / With notes; Reset / empty Reset | enum labels `Features/Bookmarks/AO3BookmarksWorksBrowser.swift:31`–`:36`; reset `:355`, `:243` | same pills `account/AccountWorksListScreen.kt:842`–`:844`; filtering `:801` | **same** narrows fetched page; no native bookmark-edit action offered by either list. |
| Open work; linked fandom/author/tags; local or remote context menu; expand | “AO3BookmarksWorksBrowser” `Features/Bookmarks/AO3AccountWorksList.swift:598` | bookmark row `account/AccountWorksListScreen.kt:874` | Basic card actions **same**; **F20/F10/F11** shared-menu/read-route differences. Notes/private/rec are information, not toggles on this screen. |
| Layout, filters, paging, refresh | shared controls `Features/Bookmarks/AO3AccountWorksList.swift:299`, `:315`, `:723` | same shared screen `account/AccountWorksListScreen.kt:257`, `:303` | Shared account-list table applies; **F21** exact-page omission. |

## AO3 Marked for Later — AO3MarkedForLaterWorksBrowser

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| All / Updated / Downloaded; Reset; empty Reset | labels `Features/Bookmarks/AO3MarkedForLaterWorksBrowser.swift:14`–`:18`; reset `:456`, `:323` | same pills `account/AccountWorksListScreen.kt:639`, `:640`; grouping `:703` | **same** uses kept-copy Downloaded, not any reading copy. |
| Unmark; failure OK | “Unmark” `Features/Bookmarks/AO3MarkedForLaterWorksBrowser.swift:403`; “No confirm” and native write `Features/Bookmarks/AO3AccountWorksList.swift:1095`, `:1112` | “onUnmark”, writer/error `account/AccountWorksListScreen.kt:771`, `:559` | **same** removes AO3 mark on confirmed write; does not simply hide row or delete local copy. Re-mark from work page reverses it; no Undo. |
| Open cover / ledger row; reveal; context menu; filters; refresh; paging | “AccountWorksCompactGrid” `Features/Bookmarks/AO3MarkedForLaterWorksBrowser.swift:338`; ledger `:361` | compact/ledger rows `account/AccountWorksListScreen.kt:676`, `:737` | **F20/F10/F11/F21** apply; ordinary remote detail and individual privacy reveal work. |

## AO3 Subscriptions — works, series, authors

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Switch Works / Series / Authors | scope selection `Features/Bookmarks/AO3AccountWorksList.swift:626`; named browser `Features/Bookmarks/AO3NamedSubscriptionsList.swift:13` | “onScopeChange” `account/AccountWorksListScreen.kt:383` | **same** separate requested lists. |
| Works: All / Updated; Reset / empty Reset | “All”, “Updated”, “Reset” `Features/Bookmarks/AO3SubscriptionsWorksBrowser.swift:16`, `:459`, `:324` | same rail `account/AccountWorksListScreen.kt:1298`, `:1307` | **same** page-local narrowing by chapter watermark. |
| Mark All as Seen | same label `Features/Bookmarks/AO3AccountWorksList.swift:322` | same `account/AccountWorksListScreen.kt:320`, writes watermark `:324` | **same** clears new-chapter status, not unsubscribe, no confirmation/undo. |
| Unsubscribe work / series / author; Cancel; error OK | work swipe `Features/Bookmarks/AO3SubscriptionsWorksBrowser.swift:370`; named `Features/Bookmarks/AO3NamedSubscriptionsList.swift:210`; confirmation `Features/Bookmarks/AO3AccountWorksList.swift:425` | mandatory confirm `account/AccountWorksListScreen.kt:1190`, `:1202`; named row `:1401`; error `:1221` | **same** native unsubscribe with work/series/author-specific notice; no Undo. |
| Tap named series / author | native links `Features/Bookmarks/AO3NamedSubscriptionsList.swift:198`, `:200` | “NamedSubscriptionRow” `account/AccountWorksListScreen.kt:1463`; callbacks `:1391`–`:1401` | **same** native destinations. |
| Works card actions, filter, refresh, paging; named failure retry | work browser `Features/Bookmarks/AO3AccountWorksList.swift:613`; named “Try Again” `Features/Bookmarks/AO3NamedSubscriptionsList.swift:176` | work row `account/AccountWorksListScreen.kt:1499`; named retry `:1432`; named refresh `:1444` | **same** reload/retry; shared **F20/F10/F11/F21** work-card/pager gaps. |

## Inbox — AccountInboxScreen / AccountInboxViews

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| All/read/unread/replied quick pills; filters sheet; choose AO3-provided option; Done | quick pills `Features/Account/AccountInboxScreen.swift:138`; filter choice/Done `Features/Account/AccountInboxFilterSheet.swift:30`, `:70` | quick rail `account/AccountInboxPane.kt:237`; choice `:675`, Done/close `:651` | **same**, options come from the loaded AO3 form, not invented fields. |
| Open comment / work-context notification / Chapter Comments | “onOpen”, “Open Chapter Comments” `Features/Account/AccountInboxViews.swift:193`, `:247` | “onOpen”, “onOpenChapter” `account/AccountInboxPane.kt:341`, `:348`; overflow `:1077` | **same** native comments, chapter scope when known; unknown work falls back to AO3. |
| Reply | “Reply” `Features/Account/AccountInboxViews.swift:250`, `:227` | reply chip `account/AccountInboxPane.kt:817`; callback `:345` | **same** requests reply to that exact comment; only when the item has work/comment IDs. |
| Copy Link; Open Comment overflow | “Copy Link”, “onOpen” `Features/Account/AccountInboxViews.swift:480`, `:469` | same overflow + clipboard `account/AccountInboxPane.kt:1060`, `:1068` | **same**, actual clipboard write here. iOS reports copied link in Inbox alert; Android relies on platform clipboard feedback (recorded decision). |
| Mark Read / Mark Unread (overflow/swipe) | same labels `Features/Account/AccountInboxViews.swift:254`, `:720` | same menu `account/AccountInboxPane.kt:1086`, `:1095` | **same** native Inbox writes. No confirmation; mark opposite reverses. |
| Delete From Inbox (overflow/swipe); Cancel | “inboxDeleteConfirmation” `Features/Account/AccountInboxViews.swift:949` | shared confirmation `account/AccountInboxPane.kt:141`, setting `:155` | **different F16** mandatory iOS ask can be skipped; notice wording correctly says comment stays on AO3. No undo. |
| Select; per-item toggle; Select All/Deselect All; Done | “beginSelection”, “SelectAllButton” `Features/Account/AccountInboxScreen.swift:230`, `:202`; Done `Features/Account/AccountInboxViews.swift:923` | selection callbacks `account/AccountInboxPane.kt:217`, `:218`, `:351`; Done `:607` | **same** selection over current page. |
| Bulk Mark Read / Mark Unread / Delete | labels `Features/Account/AccountInboxViews.swift:900`, `:911`, `:886`; delete confirmation `:925` | bar `account/AccountInboxPane.kt:581`, `:592`, `:601` → confirmation `:141` | **same** mark operations; **different F16** Delete may skip ask. |
| Previous/Next; retry failed page; pull refresh; dismiss notices/error | “SearchPaginationBar”, “goToPage” `Features/Account/AccountInboxScreen.swift:84`, `:88`; error OK `:115` | page `account/AccountInboxPane.kt:1137`, `:1152`, retry `:372`, refresh `:194`, notice OK `:267`, error OK `:189` | **same** previous/next/retry/refresh/OK; **missing F21** Inbox has no normal-size page picker, exact jump, first/last or nearby controls (only Previous/Next). Loaded rows survive later-page failure. |

## AO3 Collections list — AO3CollectionsList

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| New Collection; Log In; retry initial/index/page failure | “New Collection”, “Log In to AO3…”, “Try Again” `Features/Account/AO3CollectionsList.swift:89`, `:402`, `:189`, `:201` | New `account/AO3CollectionsScreen.kt:143`, login `:208`, retries `:217`, `:228`; page error OK `:133` | **same** native creation and recovery. |
| Open collection; open linked maintainer | “cardNavigation”, `Features/Account/AO3CollectionsList.swift:267`; card creator link `:688` | “onOpenCollection”, maintainer `account/AO3CollectionsScreen.kt:264`, `:306` | **same** native routes. |
| Edit Collection (context menu/trailing swipe); Manage Items | labels `Features/Account/AO3CollectionsList.swift:276`, `:279`, `:286` | menu row actions `account/AO3CollectionsScreen.kt:294`, `:312` | **same** destination via long-press menu; Android need not implement iOS's exact swipe chrome. |
| Your items (account-wide collection items) | “Your items” `Features/Account/AO3CollectionsList.swift:322` | “onYourItems” `account/AO3CollectionsScreen.kt:181` | **same** native account-wide items, not a local collection count. |
| Filter / long-press clear; empty Clear Filters; refresh; pagination | “FilterButton”, “Clear Filters”, “refreshable” `Features/Account/AO3CollectionsList.swift:95`, `:363`, `:248` | filter `account/AO3CollectionsScreen.kt:152`, clear `:153`, `:257`, refresh `:163`, pager `:237` | **same** except shared exact-page omission **F21**. |

## AO3 Collections sort/filter panel

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Order by; Direction | “Order by” `Features/Account/AO3CollectionsFilterPanel.swift:81`; sort block `:75` | “Order by”, “Direction” `account/AO3CollectionsFilterPanel.kt:96`, `:119` | **same** stored draft, applicable order choices. |
| Open to new works / Has works / Moderated / Unrevealed | all four toggles `Features/Account/AO3CollectionsFilterPanel.swift:120`, `:122`, `:124`, `:126` | same `account/AO3CollectionsFilterPanel.kt:139`, `:143`, `:147`, `:151` | **same** AND narrowing; role filters absent on both because AO3 does not supply roles on index. |
| Reset; Apply; Cancel; swipe/Back discard | “Reset”, “Apply”, “Cancel” `Features/Account/AO3CollectionsFilterPanel.swift:161`, `:64`, `:56` | “Resolution.Cancel”, “Resolution.Apply”, reset `account/AO3CollectionsFilterPanel.kt:61`, `:79`, `:162` | **same** staged filter resolution. |

## AO3 Collection detail — works / bookmarks / people

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Switch Works / Bookmarks / People | “Segment.allCases” `Features/Account/AO3CollectionDetailView.swift:205` | segmented strip `account/AO3CollectionDetailScreen.kt:273` | **same** independent lists. |
| Tap work / remote menu / expand / author/tag links | “EnrichingAO3WorkRow” `Features/Account/AO3CollectionDetailView.swift:247` | “SensitiveWorkRow” `account/AO3CollectionDetailScreen.kt:465` | Basic navigation **same**; **F10/F11** shared remote-menu differences. |
| People rows | “Text(person.identity.displayName)” `Features/Account/AO3CollectionDetailView.swift:646` | same plain name `account/AO3CollectionDetailScreen.kt:544` | **same** display-only on both sides; no tap action to inventory. |
| Show/Hide Mature | “MatureRevealToggle” `Features/Account/AO3CollectionDetailView.swift:126` | gated reveal menu `account/AO3CollectionDetailScreen.kt:216` | **same**, present here. |
| Maintainers / Moderation / Collection Settings | “manageRow” `Features/Account/AO3CollectionDetailView.swift:342`, `:345`, `:354` | dispatch `account/AO3CollectionDetailScreen.kt:394`–`:396` | **same** native destination; owner/maintainer gating retained by manage-row construction. These destination forms are outside the requested iOS folders. |
| Sign-ups / Assignments / Prompts / Your Sign-up / Challenge Settings | same manage labels `Features/Account/AO3CollectionDetailView.swift:364`, `:369`, `:379`, `:389`, `:399` | dispatch `account/AO3CollectionDetailScreen.kt:397`–`:401` | **same** native destinations, with owner-only Challenge Settings and participant Your Sign-up; no audit expansion into `Features/Challenges`. |
| Retry; pull refresh; page navigation | “Try Again”, “refreshable”, “paginationBar” `Features/Account/AO3CollectionDetailView.swift:441`, `:146`, `:113` | “Try Again”, refresh, pager `account/AO3CollectionDetailScreen.kt:599`, `:230`, `:369` | **same** recovery; **F21** pager exact entry missing. |

## New/Edit AO3 Collection — AO3CollectionFormView

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Display title; new collection name with availability; parent; email; tagline | text fields `Features/Account/AO3CollectionFormView.swift:138`, `:141`, `:143`, `:146`, `:149`; status `:337` | same field list and availability `account/AO3CollectionFormScreen.kt:104`–`:125` | **same** editable name only when creating; validation messages shown. |
| Header image URL / alt; icon alt / comment | fields `Features/Account/AO3CollectionFormView.swift:154`, `:157`, `:160`, `:163` | corresponding rows `account/AO3CollectionFormScreen.kt:132` | **same** text actions. |
| Closed / Moderated / Unrevealed / Anonymous / Email new items | toggles `Features/Account/AO3CollectionFormView.swift:168`–`:178` | same list/toggles `account/AO3CollectionFormScreen.kt:143`, `:148` | **same** staged form flags; do not submit just by toggling. |
| Set up a challenge; Introduction / FAQ / Rules | “Picker”, fields `Features/Account/AO3CollectionFormView.swift:188`, `:204`, `:207`, `:210` | choices `account/AO3CollectionFormScreen.kt:157`–`:166`; profile rows `:175`–`:179` | **same** supplied choice list and multiline profile input. |
| Create / Save; retry form load; return/cancel | “saveButton”, “Try Again” `Features/Account/AO3CollectionFormView.swift:399`, `:86` | primary action `account/AO3CollectionFormScreen.kt:183`; retry `:89`; back `:77` | **same** explicit submit, field/general failures remain visible; no undo of a confirmed AO3 save. |
| Open Collection Settings on AO3 | same label `Features/Account/AO3CollectionFormView.swift:431` | same `account/AO3CollectionFormScreen.kt:192` | **same** web fallback. |
| Delete Collection → type name → Delete on AO3 / Cancel | “TextField(deletionName)”, “Delete on AO3” `Features/Account/AO3CollectionFormView.swift:101`, `:104` | typed field, validation, Delete/Cancel `account/AO3CollectionFormScreen.kt:205`, `:208`, `:211`, `:213` | **same** typed-name protection, works stay on AO3, no undo. Android's ambiguous write message is deliberately stricter per recorded 3en. |

## Collection Items — per collection and Your items

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Switch item tabs; Reset | “tab = option”, “defaultTab” `Features/Account/AO3CollectionItemsView.swift:272`, `:284` | same tab/reset actions `account/AO3CollectionItemsScreen.kt:194`, `:199` | **same**, staged changes retained across tabs/pages and leaving/returning at this HEAD (recorded A61 fix). |
| Approved by creators/moderators: Awaiting / Approved / Rejected | “approvalRow”, three choices `Features/Account/AO3CollectionItemsView.swift:642`, `:650`, `:687` | creator/moderator approval `account/AO3CollectionItemsScreen.kt:303`, `:306`; choice dialog `:375` | **same** tri-state and permission-sensitive editability, not a Boolean toggle. |
| Unrevealed / Anonymous switches | “flagRow” `Features/Account/AO3CollectionItemsView.swift:659`, `:666` | same `account/AO3CollectionItemsScreen.kt:309`, `:313` | **same**, staged only when editable; otherwise read-only. |
| Remove from collection / Keep | “isRemoved ? Keep : Remove from collection” `Features/Account/AO3CollectionItemsView.swift:800` | remove/keep button `account/AO3CollectionItemsScreen.kt:324` | **same** staged removal; notice says work stays on AO3. Keep reverses before submit. |
| Discard all staged changes | “staging.clearAll()” `Features/Account/AO3CollectionItemsView.swift:200` | “model.discard()” `account/AO3CollectionItemsScreen.kt:122` | **same** immediate local discard, no confirm or undo on either. |
| Submit staged changes | “Task { await submit() }” `Features/Account/AO3CollectionItemsView.swift:189` | “confirming = true”, “Submit staged changes?”, Submit/Cancel `account/AO3CollectionItemsScreen.kt:128`, `:160`, `:166`, `:169` | **different F24** adds a confirmation. Failure keeps staged changes; no rollback/undo for a successful AO3 change. |
| Retry failed read; pull refresh; page navigator | “Try Again”, “refreshable”, pager `Features/Account/AO3CollectionItemsView.swift:383`, `:228`, `:306` | “Try Again”, refresh, pager `account/AO3CollectionItemsScreen.kt:217`, `:173`, `:238` | **same**, shared **F21** exact-page omission. |

## AO3 Preferences and help sheet

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Expand/collapse preference section | “Expand … / Collapse …” `Features/Account/AO3PreferencesView.swift:220` | same description `account/AO3PreferencesScreen.kt:280` | **same** visit-local presentation choice. |
| Toggle each AO3-provided preference; choose each supplied select; edit supplied text fields | “preferenceToggleRow”, “Picker”, “TextField” `Features/Account/AO3PreferencesView.swift:121`, `:148`, `:172` | supplied toggles/selects/texts `account/AO3PreferencesScreen.kt:292`, `:329`, `:379` | **same** form-driven choices/fields; no invented missing controls. |
| Save; retry load | “Save”, “Try Again” `Features/Account/AO3PreferencesView.swift:90`, `:66` | same `account/AO3PreferencesScreen.kt:177`, `:194` | **same** ordinary native save and disabled Save without edits. |
| Save feedback / retry failed save | “toastOverlay”, “Try Again”, clears after 3 seconds `Features/Account/AO3PreferencesView.swift:512`, `:516`, `:529` | “Saved successfully.” `account/AO3PreferencesScreen.kt:157`; status text `:218` | **different F23** permanent inline feedback, no inline Try Again; top Save can retry failure. |
| Open section/field help; retry help; Open on AO3; Done | “helpButton”, “Try Again”, “Open on AO3”, “Done” `Features/Account/AO3PreferencesView.swift:242`, `:272`, `:273`, `:286` | `openHelp` `account/AO3PreferencesScreen.kt:105`; help sheet `:411`, retry/web `:467`, `:469` | **same** requested one-page help fetch and native sheet; Android deliberately gets section help only from its heading (recorded 3cj). |
| Edit profile; Manage pseuds; Change username/password/email; Blocked users; Muted users | seven external rows `Features/Account/AO3PreferencesView.swift:602`, `:609`, `:616`, `:623`, `:630`, `:637`, `:644` | parsed “snap.webLinks” `account/AO3PreferencesScreen.kt:229`, click `:246` | **same** supplied account web routes, gated by AO3 form. |

## More on AO3 — dedicated screen and hub entry

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Post new work; Import work; Edit works in bulk; Manage collection items; Related works; Drafts | rows `Features/Account/AccountMoreOnAO3View.swift:149`, `:156`, `:163`, `:170`, `:177`, `:184` | same six paths `account/AccountMoreOnAO3Screen.kt:155`–`:160` | **same** dedicated page, web destinations (including correct `?import=true` and GET `show_multiple`). |
| Sign-ups; Assignments; Claims; Gifts given and received | rows `Features/Account/AccountMoreOnAO3View.swift:259`, `:266`, `:273`, `:280` | same `account/AccountMoreOnAO3Screen.kt:168`–`:171` | **same** dedicated-page web routes. |
| Profile; Invitations; Skins and site styles; Pseuds; Co-Creator Requests; Statistics | rows `Features/Account/AccountMoreOnAO3View.swift:205`, `:212`, `:219`, `:226`, `:233`, `:240` | same `account/AccountMoreOnAO3Screen.kt:177`–`:182` | **same** dedicated-page user routes, disabled without username. |
| Support and feedback; Report abuse; Terms; Content policy; Privacy policy; FAQs; Donate | “AO3ArchivePage.allCases” `Features/Account/AccountMoreOnAO3View.swift:291`; labels/paths `:5`–`:25` | seven paths `account/AccountMoreOnAO3Screen.kt:188`–`:194` | **same** dedicated-page site-wide routes; no sign-in required. |
| Open More on AO3 from Account's Account group | “value: Route.moreOnAO3” `Features/Account/AccountView.swift:697` | “moreOnAo3MenuOpen = true” `account/AccountScreen.kt:352`; only ten entries `:358`–`:368` | **different F29** hub row opens a truncated popup; Post/Import/Bulk Edit/Manage Items/Profile/Invitations/archive links absent there. Dedicated correct page is reachable only through configured More on AO3 shortcut (`:254`). |

## Privacy & local data — PrivacyDataView

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Free up space; Cancel/confirm number of files | “Free up space”; mandatory confirmation `Features/Account/PrivacyDataView.swift:335`, `:136` | action `settings/PrivacyDataScreen.kt:123`, confirmation `:164`, preference gate `:176` | **different, recorded decision** — the 2026-10-09 Privacy entry explicitly keeps the preference gate; may free finished un-kept copies without asking when delete confirmation is off. No immediate Undo; AO3-only copies can be fetched again. |
| Clear reading positions; Cancel/confirm count | “Clear reading positions”, unconditional dialog `Features/Account/PrivacyDataView.swift:345`, `:150` | action `settings/PrivacyDataScreen.kt:126`, clear handler `:182`, preference gate `:176` | **different, recorded decision** — the 2026-10-09 Privacy entry explicitly keeps the preference gate; may reset every reading position without the iOS ask; no undo. |
| Clear reading history; Cancel/confirm works | same label/dialog `Features/Account/PrivacyDataView.swift:355`, `:120` | action `settings/PrivacyDataScreen.kt:129`; “softDeleteHistoryOnly” `:183` | **different, recorded decision** — the 2026-10-09 Privacy entry explicitly keeps the preference gate; no mandatory ask when setting off; same 90-day Recently Deleted recovery, distinct from AO3 History. |
| Clear Browse cache; Cancel/confirm bytes; “Browse cache cleared” | label/dialog `Features/Account/PrivacyDataView.swift:365`, `:163` | cache action `settings/PrivacyDataScreen.kt:134`; `cache.clear(); browseCacheCleared = true` `:184` | **different, recorded decision** — the 2026-10-09 Privacy entry explicitly keeps this confirmation bypass; post-clear disabled row correctly present. |
| Remove AO3 session; confirm/cancel | “Remove AO3 session”, “confirmingLogOut” `Features/Account/PrivacyDataView.swift:396`, `:399` | same and logout dialog `settings/PrivacyDataScreen.kt:144`, `:190` | **same** mandatory logout confirmation. |
| Pull to remeasure local storage figures | “refreshable { await measure() }” `Features/Account/PrivacyDataView.swift:119` | measurements occur on entry/action `settings/PrivacyDataScreen.kt:186`; no refresh wrapper | **different, recorded left** on 2026-10-11; not a new priority. Reopening remeasures. |

## Check AO3 availability — AvailabilitySweepView

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Check Now; Stop; Done/Back | “Check Now”, “Stop”, “Done” `Features/Account/AvailabilitySweepView.swift:194`, `:50`, `:54` | “Check Now”, “Stop” `settings/AvailabilitySweepScreen.kt:242`, `:249`; native page Back | **same** user-started bounded check/cancel; no automatic deletion. |
| Open unavailable work / reveal obscured work | “NavigationLink”, “Hidden mature work. Activate to reveal.” `Features/Account/AvailabilitySweepView.swift:86`, `:83` | “onOpenWork”, gate reveal `settings/AvailabilitySweepScreen.kt:210`, `:204` | **same** local details/reveal, not a new AO3 fetch by this audit. |

## Author profile — shared header, actions, scope and About

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Switch Works / Series / Bookmarks / About | selected-tab switch `Features/Authors/AuthorProfileView.swift:440`; content sections `Features/Authors/AuthorProfileContentSections.swift:7` | “AuthorTab.entries”, “tab = it” `author/AuthorProfileScreen.kt:747`, `:750` | **same** native content tabs; hidden for Dashboard on both sides. |
| All Pseuds / choose pseud; About pseud link | “All Pseuds”, “model.select…” `Features/Authors/AuthorProfileView.swift:405`, `:496` | pseud chips `author/AuthorProfileScreen.kt:730`, `:737`; About pseud `:1047` | **same** account/pseud route. |
| Subscribe; Unsubscribe / Cancel | subscription button `Features/Authors/AuthorProfileComponents.swift:65`; ask `Features/Authors/AuthorProfileView.swift:154`, `:159` | subscription callback `author/AuthorProfileScreen.kt:703`; mandatory unsubscribe ask `:556`, `:559`, `:564` | **same** native writes, full-account unsubscribe warning, result dialog. Android's stricter success evidence is an explicit recorded decision (2026-10-16), not a priority. |
| Mute/Unmute; Block/Unblock; confirm AO3's own labels / Cancel | moderation buttons `Features/Authors/AuthorProfileComponents.swift:92`, `:95`; AO3 form labels `Features/Authors/AuthorProfileView.swift:167`–`:179` | `pendingModeration` dialog `author/AuthorProfileScreen.kt:570`, submit/cancel `:579`, `:585` | **same** requested confirmation form, no guessed write endpoint. |
| Dismiss action error/success with OK; retry failed header; unavailable Open on AO3 | “AO3 Profile”, “OK”, “Open on AO3” `Features/Authors/AuthorProfileView.swift:122`, `:123`, `:723` | same message/OK `author/AuthorProfileScreen.kt:592`, `:595`; retry `:658`; unavailable web `:640` | **same** recovery entry points. |
| Layout Ledger / Detailed | “DisplayModeMenuPicker…[.ledger, .detailed]” `Features/Authors/AuthorProfileView.swift:880` | “Ledger Mode”, “Detailed Mode” `author/AuthorProfileScreen.kt:505`, `:509` | **same**, stored choice, ledger initially. |
| Expand/Collapse All | “ExpandAllMenuItem” `Features/Authors/AuthorProfileView.swift:883` | complete menu `author/AuthorProfileScreen.kt:469`–`:530`; cards pass false `:923` | **missing F26**. Individual detailed card expansion is still available. |
| Show/Hide Mature | “MatureRevealToggle” `Features/Authors/AuthorProfileView.swift:871` | complete menu `author/AuthorProfileScreen.kt:469`–`:530` | **missing F06** author/dashboard variant too; local-match reveal difference **F30** below. |
| Open on AO3 | “router.open(model.route.dashboardURL)” `Features/Authors/AuthorProfileView.swift:892` | “userProfileUrl(route.username)” `author/AuthorProfileScreen.kt:515` | **different F28**, profile page instead of dashboard/current pseud. |
| Share Profile | “ShareLink(item: model.route.dashboardURL)” `Features/Authors/AuthorProfileView.swift:895` | “userDashboardUrl(route.username, route.pseud)” `author/AuthorProfileScreen.kt:518` | **same** share target includes pseud. |
| Bio hyperlinks; choose About pseud | About section `Features/Authors/AuthorProfileView.swift:478`–`:503` | “AO3RichTextContent”, pseud click `author/AuthorProfileScreen.kt:1035`, `:1047` | **same** safe linked bio and pseud route. |
| Pull refresh | “model.refresh(auth:)” `Features/Authors/AuthorProfileView.swift:286` | refresh block `author/AuthorProfileScreen.kt:601` | **same** requested header/current-list reload. |

## Author Works — own works and another author's works

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Works / In collections / Gifts scope | scope choices `Features/Authors/WorksScopeAndSort.swift:27` | “scopeState = scopeVal; loadTab” `author/AuthorProfileScreen.kt:868` | **same** server list scope. |
| All fandoms / choose one author's fandom | “selectFandom(nil)”, “selectFandom(fandom)” `Features/Authors/AuthorProfileContentSections.swift:169`, `:188` | same `author/AuthorProfileScreen.kt:884`, `:892` | **same** plain Works only, newly implemented 3eq. |
| Sort and filter; sort column/direction; completion; local refine; Reset/Apply | “worksFilterButton”, works sort controls `Features/Authors/AuthorProfileView.swift:825`; `Features/Search/AO3FilterPanel.swift:635`, `:655`, `:665` | “SearchFilterSheet”, “worksSort = worksSort” `author/AuthorProfileScreen.kt:538`, `:548`; `author/AuthorWorksSortFields.kt:35`, `:64`, `:75` | **same** choices and action entry points; shared filter table applies. |
| Work tap, local Read, local privacy Reveal, local context menu | local canonical card `Features/Authors/AuthorDashboardSections.swift:193`, `:195`; entries merge `Features/Authors/AuthorProfileContentSections.swift:365` | “AO3AuthorWorkCard(work…)” `author/AuthorProfileScreen.kt:923`; remote-only parameter `author/AuthorProfileComponents.kt:171`, shared remote row `:184` | **different F30** no local pairing: opens detail, shows an obscured local work as a remote result, no local reveal/menu. Remote context **F10/F11** also applies. |
| Select Works; toggle row; Select All/Deselect All; Done | “Select Works”, “Select All”, “onToggleSelection” `Features/Authors/AuthorProfileView.swift:862`, `:786`, `:448` | “Select Works”, select all, toggle, Done `author/AuthorProfileScreen.kt:457`, `:438`, `:910`, `:442` | **same** current loaded selection; pagination differs **F18**. |
| Another author's selected works: Download / Later / Queue / Collection | “RemoteWorkSelectionToolbar” `Features/Authors/AuthorProfileView.swift:797`; four actions `UIComponents/RemoteWorkSelection.swift:143`–`:178` | two-action bar `author/AuthorProfileScreen.kt:1085` | **different F17** Download is metadata only; **missing F05** Queue/Collection. Later enqueues preservation through queue service. |
| New Work (own Works) | “New Work” `Features/Authors/AuthorProfileView.swift:804` | “New Work” `author/AuthorProfileScreen.kt:453` | **same** native writing form entry (form internals outside this audit's folders). |
| Own-work Delete; Chapter when unfinished; Tags; Edit (swipe/menu) | corresponding labels `Features/Authors/AuthorProfileContentSections.swift:394`, `:401`, `:409`, `:416` | exact four labels and chapter gate `author/OwnWorksControls.kt:91`, `:92`; route dispatch `author/AuthorProfileScreen.kt:919` | **same** native own-work forms; Delete has mandatory “Delete on AO3”/Cancel, permanent loss text and error OK (`author/AuthorProfileScreen.kt:419`–`:430`; I `Features/Authors/AuthorProfileView.swift:94`–`:112`). No undo. |
| Own-work bulk Edit N / Collections / Visibility / Delete | same labels `Features/Authors/OwnWorksBulkBar.swift:14`, `:16`, `:18`, `:20` | same `author/OwnWorksControls.kt:68`–`:72` | **same** bulk form focus; Delete always asks, names selected works, removes on AO3, no undo. |
| Load More; Try Loading More / retry initial list | “Load More”, “Try Loading More” `Features/Authors/AuthorProfileContentSections.swift:91`, `:83`; append calls `Services/AO3AuthorProfileService.swift:378` | “Previous”, “Next”, “Try Loading More” `author/AuthorProfileScreen.kt:1126`, `:1128`, `:1110`; replaces `:225` | **different F18** paged replacement instead of appended loaded list. |

## Author Series list

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Open series; linked creator | series row navigation `Features/Authors/AuthorProfileContentSections.swift:535`; series creator byline `Features/Authors/AuthorProfileComponents.swift:268` | “AO3SeriesRow…onOpenSeries…onOpenAuthor” `author/AuthorProfileScreen.kt:972`, `:973` | **same** native series/creator routes (pseud route fix already landed). |
| Own series Edit / Reorder (swipe) | labels `Features/Authors/AuthorProfileContentSections.swift:588`, `:581` | same menu `author/AuthorProfileScreen.kt:964`, `:966` | **same** native series editor/reorder entry. |
| New series on AO3 when own empty series | “New series on AO3”, `/series/new` `Features/Authors/AuthorProfileContentSections.swift:502`, `:506` | same URL and explanation `author/AuthorProfileScreen.kt:944`, `:945` | **same** web creation route (neither app creates the series here). |
| Load More/retry; Layout; Mature toggle; refresh | “AO3AuthorPaginationRows”, profile menu `Features/Authors/AuthorProfileContentSections.swift:545`; `Features/Authors/AuthorProfileView.swift:871`, `:880` | pager `author/AuthorProfileScreen.kt:980`; complete menu `:469` | **different F18**, **missing F06**; layout/refresh **same**. |

## Author Bookmarks list

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Open bookmarked work; author/tag/fandom links; work menu; card expansion | “AO3AuthorBookmarksSection” `Features/Authors/AuthorProfileView.swift:471`; shared bookmark card `Features/Authors/AuthorProfileComponents.swift:406` | “AO3AuthorWorkCard…bookmark” `author/AuthorProfileScreen.kt:998`–`:1003` | Basic remote detail/links/expand **same**; **F10/F11** work menu. Author Bookmarks uses remote rows on both sides; F30 does not apply there. No Edit/Delete Bookmark action in either author bookmark list. |
| Load More/retry; Layout; Mature toggle; refresh | “AO3AuthorPaginationRows” `Features/Authors/AuthorProfileContentSections.swift:666`; profile menu `Features/Authors/AuthorProfileView.swift:871`, `:880` | pager `author/AuthorProfileScreen.kt:1012`; complete menu `:469` | **different F18**, **missing F06**; layout/refresh **same**. |

## Dashboard — AO3DashboardView / AO3DashboardSections

`Features/Account/AO3DashboardView.swift:22` wraps the own `AuthorProfileView`; Android `account/AO3DashboardScreen.kt:41` wraps `AuthorProfileScreen(isDashboard = true)`. The shared author-header/action table also applies.

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Recent work / series / bookmark → native destination | “AO3AuthorWorkCard”, series/bookmark “cardNavigation” `Features/Authors/AuthorDashboardSections.swift:72`, `:97`, `:120` | work callback `author/AuthorProfileScreen.kt:793`; series `:816`; bookmark `:839` | **same** remote destinations; local recent work lacks pairing/reveal/reader **F30**. |
| See all works / series / bookmarks | “seeAll(.works/.series/.bookmarks)” `Features/Authors/AuthorDashboardSections.swift:82`, `:103`, `:128` | See All callbacks `author/AuthorProfileScreen.kt:800`, `:821`, `:844` | **same** full native lists, including when empty or failed. |
| Fandom → works; Expand/Collapse fandom preview | “router.open(url)”, “expandsFandoms.toggle” `Features/Authors/AuthorDashboardSections.swift:39`, `:54` | plain, unclickable “SubjectChip” `author/AuthorProfileScreen.kt:772` | **missing F19** both fandom navigation and preview toggle. |
| New Work; Layout; Expand/Collapse All; Show/Hide Mature | new/menu `Features/Authors/AuthorProfileView.swift:804`, `:871`, `:880`, `:883` | New `author/AuthorProfileScreen.kt:453`; modes `:505`, `:509`; complete menu `:469` | New/layout **same**; **F26** expansion, **F06** mature toggle absent. |
| About | “dashboardDestination = .about” `Features/Authors/AuthorProfileView.swift:888` | tab strip excluded for dashboard `author/AuthorProfileScreen.kt:744`; complete menu `:477` | **missing F27**. |
| Additional My Works / Collections / Bookmarks / Subscriptions / Marked for Later / History menu routes | iOS dashboard menu instead has About, Open on AO3, Share and AO3-supplied web actions `Features/Authors/AuthorProfileView.swift:887`–`:900` | six extra routes `author/AuthorProfileScreen.kt:479`–`:500` | **Android only** useful shortcuts to already-available account destinations. |

## Series detail — AO3SeriesDetailView

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Tap series creator; tap work; reveal local work; work menu | series header card `Features/Authors/AO3SeriesDetailView.swift:56`; local/remote work rows `:207`, `:210` | creator callback `app/SeriesWorksScreen.kt:266`; work row `:289` | Basic remote detail/creator routes **same**; local resolution/reveal **F30** variant and remote menu **F10/F11**. |
| Show/Hide Mature | “MatureRevealToggle” `Features/Authors/AO3SeriesDetailView.swift:95` | complete menu starts with Select `app/SeriesWorksScreen.kt:145`–`:196` | **missing F06**: no privacy item. |
| Select works; toggle selection; Download/Later; Done | “Select”, “RemoteWorkSelectionToolbar” `Features/Authors/AO3SeriesDetailView.swift:99`; shared `UIComponents/RemoteWorkSelection.swift:108` | “Select”, bar `app/SeriesWorksScreen.kt:148`, `:310` | Selection/Later **same**; Download **different F17**; selected Queue/Collection **missing F05**. |
| Own series Reorder; Edit series | labels `Features/Authors/AO3SeriesDetailView.swift:104`, `:113` | same `app/SeriesWorksScreen.kt:174`, `:172` | **same** native writing editor/reorder-only mode. |
| Open on AO3; Share Series | same labels `Features/Authors/AO3SeriesDetailView.swift:117`, `:120` | same `app/SeriesWorksScreen.kt:177`, `:185` | **same** series URL/share. |
| Pull refresh; retry first or later page; page navigator | “refreshable”, pagination/failure rows `Features/Authors/AO3SeriesDetailView.swift:134` | refresh `app/SeriesWorksScreen.kt:200`; retries `:222`, `:234`; pager `:276` | **same** recoverable reads and rows kept on later failure; **different F18** iOS appends through Load More (`Features/Authors/AO3SeriesDetailView.swift:221`), Android replaces with a page. iOS has no arbitrary-page picker on this screen, so F21 does not apply here. |


## Additional shared actions and reachability checks

| Action | iOS quote · path:line | Android quote · path:line | Result |
|---|---|---|---|
| Account → Settings | “Settings” `Features/Account/AccountInboxViews.swift:123` | “Settings”, route `app/MainScaffold.kt:385`, `:383` | **same** shell entry. |
| Read more / Show less on long comments (list and isolated thread) | “Show less” / “Read more” `Features/Comments/CommentThreadRow.swift:1577` | same labels/click `comments/CommentThreadComponents.kt:740`, `:745` | **same** local text expansion. Ordinary comment bodies are plain text on both sides; no rich-body link action is asserted. |
| Follow AO3's own deep-thread cutoff URL | “Link(destination: url)” `Features/Comments/CommentThreadRow.swift:1171` | plain cutoff row `comments/CommentThreadComponents.kt:625`–`:644` | **missing F31**, chevron suggests an action but none is wired. Kudos's separate “Continue thread” for loaded replies does work and was recorded in W3; it does not repair this server cutoff. |
| Home queue Delete confirmation / Cancel | “confirmationDialog”, “Delete”, “Cancel” `Features/Library/QueueCardMenu.swift:43`, `:48`, `:51` | mandatory dialog “Delete”/“Cancel” `library/QueueChrome.kt:402`, `:407`, `:409` | **same**, queue-only members may also enter Recently Deleted under the shared queue lifecycle; 90-day recovery, no immediate Undo. |
| Series Expand/Collapse All | iOS complete menu `Features/Authors/AO3SeriesDetailView.swift:93`–`:122` has no expansion item | “Expand All”/“Collapse All” `app/SeriesWorksScreen.kt:158` | **Android only** useful shared-card expansion. |

`AccountInboxSeeAllRow` (“See All Comments”, `Features/Account/AccountInboxViews.swift:768`) is not offered by the actual Inbox screen: its `AccountInboxRows` initialization supplies no `onSeeAll` (`Features/Account/AccountInboxScreen.swift:187`–`:195`). It is not counted as a missing action. No `.keyboardShortcut` occurs in the seven requested iOS feature folders; touch-equivalent actions in shared components are inventoried above. Parser/catalog/cache/model/helper files in those folders add no independent screen. `Browse/WebBrowser.swift` implements browser callbacks rather than a second browser screen.


## Completion and limits

The inventory above contains 249 action/comparison rows, including shared rows referenced by each consuming screen. Each requested folder was searched for buttons, menus, navigation links, sheet controls, swipes, tap/long-press gestures, list delete/move, refresh and keyboard shortcuts; reachable handlers were traced for the findings. Non-screen catalog/parser/state files were checked as dependencies rather than given fictitious screen tables. Shared Library queue/collection/editor internals already covered by A62 are referenced where their entry points recur here.

Android is correctly native for History clearing/removal, AO3 Marked for Later Unmark, subscription removal, author subscribe/mute/block confirmations, Inbox mark/read/reply routes, preference help, collection ownership gates, staged collection-item edits, and own-work/series editing entry points. The table statuses distinguish those working actions from unrelated missing controls.

Verification was source-only: no app build, tests, emulator/browser interaction, sign-in, or AO3 contact. No claim is made about actual server responses, gesture quality, rendering, accessibility service execution, timing races or process-death behavior. Only `docs/android-port/audits/A63-result.md` was created/modified; `TASKS.md`, source, branch and HEAD remain unchanged. No commit or push was made.
