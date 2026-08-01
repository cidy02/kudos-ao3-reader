
### App shell, navigation, tab structure

| Severity | File | Summary | Status |
|---|---|---|---|
| critical | `home/HomeScreen.kt` | When 'Hide mature content' (Blur mode) is turned on, blurred/hidden Mature or Explicit works on the Home tab are not actually protected: tapping the blurred card jumps straight into that work's full details page — tit... | ✅ Fixed this session |
| major | `app/KudosApp.kt` | The Settings screen has a normal-looking theme picker (Light / Sepia / Dark / OLED / System) that saves your choice but never actually changes how the app looks — the app is colored by a different, hidden control (a s... | 🔲 Not yet reviewed by a human |
| major | `app/AppNavHost.kt` | Ordinary browsing can leave you looking at the wrong work. Example: open a work from Home, tap its author to see their other works, then open a different work from that list. Now press back twice — instead of landing ... | 🔲 Not yet reviewed by a human |
| minor | `app/MainScaffold.kt` | If a work is downloading in the background and you open the reader to read something else, iOS keeps showing a small 'Downloading…' pill at the bottom of the screen; Android hides it completely while you're reading an... | 🔲 Not yet reviewed by a human |
| note | `app/NavigationRoutesTest.kt` | There are no automated tests covering how the app remembers which screen/tab is showing what, or whether the Settings theme picker actually changes the app's colors — the two most serious bugs found in this review bot... | 🔲 Not yet reviewed by a human |

### Home screen

| Severity | File | Summary | Status |
|---|---|---|---|
| critical | `home/HomeScreen.kt` | On the Home screen, a work you've told the app to blur for being Mature/Explicit shows the blurred cover with a 'Tap to reveal' label, but tapping it doesn't reveal it in place — it jumps straight to that work's full ... | ✅ Fixed this session |
| major | `works/WorkImporter.kt` | On iPhone, adding a work to a Reading Queue (like 'Saved for Later') without also explicitly saving it keeps that work out of your Library and Home dashboard until you choose to save or favorite it. On Android, simply... | 🔲 Not yet reviewed by a human |
| major | `home/HomeScreen.kt` | On iPhone, if you're subscribed to a work on AO3 that you've also saved in your Library, its Subscriptions card on Home shows your actual reading progress and tapping it jumps straight into the reader where you left o... | 🔲 Not yet reviewed by a human |
| major | `home/HomeScreen.kt` | On iPhone, every section on the Home screen (Continue Reading, Recently Updated, Favorites, Recently Opened) has a 'See all' button that opens the full list, so nothing is lost if you have more than a handful of items... | 🔲 Not yet reviewed by a human |
| minor | `works/WorkUpdateChecker.kt` | When the app can't check a work for new chapters (say the work was deleted on AO3, or there's a network hiccup), the iPhone app remembers not to try again for a few hours. The Android app forgets this and will keep re... | 🔲 Not yet reviewed by a human |
| minor | `home/HomeScreen.kt` | If a work you've favorited (or read before) also has new chapters waiting, opening it from the Favorites or Recently Opened row on Home doesn't clear its 'new chapters' flag the way opening it from Continue Reading or... | 🔲 Not yet reviewed by a human |
| minor | `home/HomeScreen.kt` | On the iPhone app, the Favorites row on Home never shows a reading-progress bar (it's a plain card), and Recently Opened shows only a small text note like a chapter number, not a progress bar. On Android, both of thos... | 🔲 Not yet reviewed by a human |
| note | `android/app/src/test/java/io/github/cidy02/kudos/home/HomeDashboardTest.kt` | There are tests for how the Home dashboard's lists get built, but none for the Home screen's view-model logic itself — like what happens when refreshing subscriptions fails, or what happens when you sign in or out. Th... | 🔲 Not yet reviewed by a human |

### Library screen: core list, filters, sort, bulk select, mature-content privacy

| Severity | File | Summary | Status |
|---|---|---|---|
| critical | `library/LibraryViewModel.kt` | On iOS, tapping the eye icon in the Library only temporarily shows mature works for the current session — the app still hides mature content by default the next time it's opened. On Android, tapping the same eye icon ... | ✅ Fixed this session |
| major | `works/WorkRepository.kt` | Every card in the Library has a menu item that toggles whether a work is 'Saved for Later.' On Android, turning that off doesn't just remove the work from the Saved for Later shelf like it does on iOS — it makes the w... | 🔲 Not yet reviewed by a human |
| major | `library/LibraryScreen.kt` | iOS shows a 'Favorites' row on the Library dashboard listing every work the user has starred. Android computes the same data internally but never displays it — there's no Favorites shelf on the Android Library screen ... | 🔲 Not yet reviewed by a human |
| major | `library/LibraryScreen.kt` | iOS lets you tap a chevron next to any Library shelf (Reading Now, Saved for Later, Finished, Downloaded, Reading History) to see the full list. Android caps every shelf at 12 items and provides no way to see the rest... | 🔲 Not yet reviewed by a human |
| major | `library/LibraryViewModel.kt` | iOS has a full Filters panel for the Library (sort order, rating, warnings, categories, completion status, language, word-count range, your own tags, collections) reachable from a Filter button in the toolbar. Android... | 🔲 Not yet reviewed by a human |
| minor | `library/LibraryScreen.kt` | When multiple works are selected in the Library, iOS lets you bulk Save, bulk Save-for-Later, bulk Add to Queue, and bulk Add to Collection in addition to Favorite/Finished/Delete. Android's selection toolbar only off... | 🔲 Not yet reviewed by a human |
| note | `android/app/src/test/java/io/github/cidy02/kudos/library/LibraryRepositoryTest.kt` | The automated test suite for the Library barely tests the repository layer (only one test, and it happens to encode the very bug about saved/unsaved works described above) and has no test at all for the mature-content... | 🔲 Not yet reviewed by a human |

### Download queue, download banner, work import, and series-download-via-queue

| Severity | File | Summary | Status |
|---|---|---|---|
| critical | `works/WorkImporter.kt` | If a user deletes a fic (it goes into 'Recently Deleted' for 90 days) and later finds and downloads that same work again — either by tapping Download on it directly or by downloading a whole series that includes it — ... | ✅ Fixed this session |
| major | `AndroidManifest.xml` | On iOS, a user can share or 'Open in Kudos' a fic file from Files, a browser download, a Discord/Reddit attachment, or AirDrop, and the app figures out what kind of file it is (EPUB, HTML, plain text, PDF, a zipped ch... | 🔲 Not yet reviewed by a human |
| note | `works/WorkImporter.kt` | The code that actually saves a downloaded fic into the library (WorkImporter/WorkMetadataMerger) has no automated tests at all, and the download-queue tests that do exist never check what happens when you re-download ... | 🔲 Not yet reviewed by a human |

### Reading statistics screen

| Severity | File | Summary | Status |
|---|---|---|---|
| critical | `library/ReadingStatisticsScreen.kt` | Turning on 'Hide Mature Content' hides adult works on the Library screen, but the Reading Insights screen ignores that setting entirely: a user's adult-rated works still count toward the totals, and their fandom names... | ✅ Fixed this session |
| major | `library/ReadingStatistics.kt` | If a work's reading progress comes from Android's Readium-based reader (or arrives via cross-device backup/sync) in a way that only sets the internal reader bookmark but not the 'last opened' timestamp, the Reading In... | 🔲 Not yet reviewed by a human |
| major | `library/ReadingStatistics.kt` | If a book's reading progress was restored from a backup in a way that only recorded the reader's internal bookmark (not a 'last read' timestamp), the Reading Insights screen will silently leave it out of 'Works Read,'... | 🔲 Not yet reviewed by a human |
| minor | `library/ReadingStatisticsScreen.kt` | If a heavy reader's total words-read count lands in a narrow band just under 1,000,000 (or similarly under 1,000 million), the 'Words Read' tile can briefly display a garbled number like "1000.0K" instead of rolling o... | 🔲 Not yet reviewed by a human |
| note | `src/test/java/io/github/cidy02/kudos/library/ReadingStatisticsTest.kt` | The Android tests don't cover the specific case (a work whose only reading evidence is the Readium reader's internal bookmark) that the iOS team added a dedicated test for after hitting this exact bug once already. | 🔲 Not yet reviewed by a human |
| note | `test/java/io/github/cidy02/kudos/library/ReadingStatisticsTest.kt` | The Android test suite is missing a safety-net test that iOS has, which checks that a work is still counted as 'started' even if its only progress signal is the reader's internal bookmark. That gap is likely why the A... | 🔲 Not yet reviewed by a human |

### Local collections management

| Severity | File | Summary | Status |
|---|---|---|---|
| critical | `library/CollectionDetailScreen.kt` | If you've turned on "hide mature content," mature works are blurred everywhere in the app — except inside Collections. Opening any collection that contains a mature work shows its full title, author, and a tappable Re... | ✅ Fixed this session |
| critical | `library/CollectionDetailScreen.kt` | Deleting a collection on Android is instant and permanent — there is no 90-day "Recently Deleted" safety net for it, even though the app's own Recently Deleted screen says deleted collections should stay recoverable f... | ✅ Fixed this session |
| major | `data/local/dao/CollectionDao.kt` | A work you've already deleted (moved to Recently Deleted) can still show up as a normal, fully usable item inside any collection it was in, and it's still counted in that collection's "N works" total — even though it ... | 🔲 Not yet reviewed by a human |
| major | `library/CollectionDetailScreen.kt` | There's no way to rename a collection on Android. If you misspell a collection's name or just want to change it, your only option is deleting it and starting over — which loses which works were in it. | 🔲 Not yet reviewed by a human |
| major | `library/CollectionDetailScreen.kt` | On iOS you can add works to a collection either from the work itself (picking from a checklist of your collections) or from inside the collection (browsing and multi-selecting your whole library). On Android, the only... | 🔲 Not yet reviewed by a human |
| minor | `library/CollectionDetailScreen.kt` | Tapping "Remove" on a work inside a collection removes it instantly with no "are you sure?" prompt, even though the app has a "confirm before delete" setting that iOS honors here. A stray tap silently drops a work fro... | 🔲 Not yet reviewed by a human |
| note | `data/local/RoomDaoTest.kt` | The automated tests barely touch collections — there's no dedicated test file, and nothing checks that deleting a collection, renaming, or filtering out already-deleted works actually behaves correctly. This is the ki... | 🔲 Not yet reviewed by a human |

### Recently Deleted / purge of expired soft-deletes

| Severity | File | Summary | Status |
|---|---|---|---|
| critical | `works/WorkDetailScreen.kt` | If you delete a work and then come across it again later (by tapping the same AO3 link or search result) and try to Save it, add it to a reading queue, or save it for later, the app acts like it worked — but the work ... | ✅ Fixed this session |
| major | `works/WorkMetadataMerger.kt` | When you delete a work and then re-save it later (not through the explicit Restore button), the app correctly brings it back into your Library on this device — but it leaves behind an internal 'this was deleted' marke... | 🔲 Not yet reviewed by a human |
| major | `works/WorkRepository.kt` | Deleting a work gives you 90 days to change your mind, same as on iPhone. But deleting a collection (a shelf you made to organize works) is instant and permanent on Android, with no way to undo it — even though the ap... | 🔲 Not yet reviewed by a human |

### Work Detail screen

| Severity | File | Summary | Status |
|---|---|---|---|
| major | `works/WorkUpdateChecker.kt` | When Kudos checks a saved in-progress story for new chapters and that check fails (locked story, deleted story, or just a network hiccup), the app is supposed to wait 6 hours before trying that story again. On Android... | 🔲 Not yet reviewed by a human |
| major | `works/WorkDetailScreen.kt` | On iOS, opening a saved story's detail page quietly re-checks AO3 for updated kudos, comments, hits, and tags every time, and you can also pull down to refresh. On Android, none of that happens — once you've saved a s... | 🔲 Not yet reviewed by a human |
| major | `works/WorkDetailScreen.kt` | In Work Detail's Discussion tab there are three separate buttons — 'All Comments', 'Chapter Comments', and 'Write a Comment' — that look like they do different things, but on Android they all just open the exact same ... | 🔲 Not yet reviewed by a human |
| minor | `works/WorkDetailScreen.kt` | For a story you've already finished and marked as Finished, the big 'Read' quick-action button on Android keeps saying 'Continue Reading' instead of switching back to plain 'Read', which is confusing since you're not ... | 🔲 Not yet reviewed by a human |
| minor | `works/WorkDetailScreen.kt` | iOS shows the other books in a series that you've already downloaded right on the Work Detail page, and lets you tap straight to any of them. Android only shows a plain text line like 'Series: Title #2' with no list o... | 🔲 Not yet reviewed by a human |
| minor | `works/WorkDetailScreen.kt` | If you've already bookmarked a story on AO3 and open the Bookmark dialog again from Android, it doesn't know that — the notes/tags fields are blank instead of showing what you already wrote, and the menu still says 'B... | 🔲 Not yet reviewed by a human |
| note | `works/WorkDetailScreen.kt` | The 'Subscribe' menu option never changes to 'Unsubscribe' even after you've subscribed, so there's no way to tell from the menu whether you're already subscribed to a story. Tapping it still works (it toggles), but t... | 🔲 Not yet reviewed by a human |
| note | `works/WorkTags.kt` | The code that pulls an AO3 story's numeric ID out of its URL and cleans up its tag lists has no automated tests on Android, even though the equivalent iOS code does. A regression here (e.g. a URL format that stops par... | 🔲 Not yet reviewed by a human |

### Account hub

| Severity | File | Summary | Status |
|---|---|---|---|
| major | `account/AccountScreen.kt` | On iPhone, Activity > Inbox is a real inbox: you can see AO3 comment notifications, reply, mark them read/unread, delete them, and filter them. On Android, tapping Activity > Inbox just shows a message saying it isn't... | 🔲 Not yet reviewed by a human |
| major | `account/AO3DashboardScreen.kt` | Tapping 'My Dashboard' on iPhone shows your actual AO3 profile — fandoms, works, series, bookmarks with real data. On Android, 'My Dashboard' just shows the exact same six shortcut links that are already on the Overvi... | 🔲 Not yet reviewed by a human |
| major | `app/AppNavHost.kt` | In the Account menu, 'Settings' and 'Privacy & Local Data' are two different options, but on Android they both open the exact same Settings screen — tapping 'Privacy & Local Data' shows nothing about privacy at all. O... | 🔲 Not yet reviewed by a human |
| minor | `account/AccountScreen.kt` | On iPhone, Writing > Drafts still gives you a working button that opens your AO3 drafts on the website. On Android, the same screen just says drafts aren't available yet with no button or link — there's no way to get ... | 🔲 Not yet reviewed by a human |
| minor | `account/AccountScreen.kt` | On iPhone, 'More on AO3' opens a menu of extra account pages — Pseuds, Skins, Statistics, Sign-ups, Gifts, and more. On Android, the same-named button just opens your own AO3 profile page instead, so those extra desti... | 🔲 Not yet reviewed by a human |
| minor | `account/AccountScreen.kt` | If you bookmark or subscribe to something new on the AO3 website and come back to the app, iPhone lets you pull down to refresh the list. On Android there's no way to manually refresh these lists at all — short of res... | 🔲 Not yet reviewed by a human |
| note | `account/AccountViewModel.kt` | The network/parsing code for the Account screen is tested, but the view-model logic that decides what the screen actually shows (loading, errors, needing to log in, fandom filtering) has no automated tests, so regress... | 🔲 Not yet reviewed by a human |

### Settings, including custom font import

| Severity | File | Summary | Status |
|---|---|---|---|
| major | `reader/readium/ReadiumSettingsAdapter.kt` | You can import a custom font in Settings, pick it, and see the checkmark next to it confirming it's selected — but the reader silently ignores it and keeps using the default font. The whole point of importing a font (... | 🔲 Not yet reviewed by a human |
| major | `settings/SettingsScreen.kt` | On iPhone, reporting a bug lets you describe what happened and shows you exactly what technical info will be attached, then opens a pre-filled GitHub issue you can review before submitting. On Android, tapping 'Report... | 🔲 Not yet reviewed by a human |
| major | `settings/SettingsScreen.kt` | On iPhone, Settings → Privacy has a whole page for clearing your local reading history and cached Browse data, useful for privacy on a shared device or just tidying up. That entire page and both of those actions are m... | 🔲 Not yet reviewed by a human |
| minor | `settings/SettingsScreen.kt` | On iPhone you can select several font files at once when importing. On Android you can only pick and import one font file per trip to the file picker — not a dealbreaker, just more taps to import multiple fonts. | 🔲 Not yet reviewed by a human |
| minor | `settings/SettingsScreen.kt` | The 'Reset settings to defaults' button wipes every app setting (theme, reader preferences, privacy options, etc.) the instant you tap it — no 'Are you sure?' prompt, and it sits right next to the backup buttons where... | 🔲 Not yet reviewed by a human |
| note | `settings/SettingsScreen.kt` | iPhone Settings has controls for automatically keeping small series downloaded, checking whether your saved works are still up on AO3, and a Queue Storage view — none of these are reachable from Android Settings, even... | 🔲 Not yet reviewed by a human |

### Search screen

| Severity | File | Summary | Status |
|---|---|---|---|
| major | `search/SearchScreen.kt` | On iPhone, typing a few letters into Search instantly shows matches from your own library (saved works, fandoms, tags, collections) before it ever touches the network — and tapping a tag anywhere in the app jumps stra... | 🔲 Not yet reviewed by a human |
| major | `search/SearchScreen.kt` | Tapping "Clear" on the Search screen removes the filter chips from view, but the work list underneath still shows the old, filtered results — it doesn't actually refresh. A user would reasonably think clearing filters... | 🔲 Not yet reviewed by a human |
| major | `search/SearchScreen.kt` | On iPhone, as soon as you start typing in Search you immediately see matches from your own downloaded library (works, fandoms, tags, collections) before any request even goes to AO3. On Android, typing does nothing un... | 🔲 Not yet reviewed by a human |
| major | `search/TagSuggestField.kt` | On iPhone, when you fill in a Fandom/Character/Relationship/Tag filter, you get a live search of all of AO3's tags plus a list of that fandom's most popular tags, so you can find the exact tag even if you've never dow... | 🔲 Not yet reviewed by a human |
| minor | `search/SearchScreen.kt` | On a search with many pages of results, iPhone lets you tap a page number to jump straight there, or long-press the arrow to jump to the very first or last page. Android only has Previous/Next, so getting from page 1 ... | 🔲 Not yet reviewed by a human |
| minor | `search/SearchScreen.kt` | Tapping the 'Clear' button or 'Clear all' chip on the Search screen resets the filter chips but leaves the old, filtered results list sitting on screen unchanged - so what you see no longer matches what the (now clear... | 🔲 Not yet reviewed by a human |
| note | `search/SearchScreen.kt` | On iPhone you can select multiple search results at once for bulk actions, and expand or collapse every result card in one tap. Android's search results can only be opened one at a time — there's no multi-select and n... | 🔲 Not yet reviewed by a human |
| note | `search/SearchScreen.kt` | The small helper functions for search filters are well tested, but the actual Search screen's logic for running a search, retrying, and clearing filters has no automated tests, which is how the 'Clear doesn't refresh ... | 🔲 Not yet reviewed by a human |

### Browse screen and in-app web browser

| Severity | File | Summary | Status |
|---|---|---|---|
| major | `browse/FandomListScreen.kt` | When you open a media category (e.g. TV Shows) to see its fandom list, iOS shows the most popular/largest fandoms first, making it easy to find well-known fandoms. Android instead shows them in plain alphabetical orde... | 🔲 Not yet reviewed by a human |
| major | `browse/FandomWorksScreen.kt` | On iOS, once you're browsing a fandom's works you can filter by rating, warnings, completion status, and change the sort order right there. On Android that same screen has no filter or sort controls whatsoever — you'r... | 🔲 Not yet reviewed by a human |
| major | `network/ao3/browse/AO3BrowseParser.kt` | Browsing a big category like 'TV Shows' or 'Anime & Manga' downloads a very large fandom list page. On iOS this used to crash the app from memory pressure, and was specifically fixed by scanning the page text directly... | 🔲 Not yet reviewed by a human |
| minor | `browse/FandomListScreen.kt` | Typing in the fandom filter box on a large category could feel laggy or janky on Android, because it re-scans the entire (potentially huge) fandom list on every keystroke with no delay — the exact typing freeze iOS sp... | 🔲 Not yet reviewed by a human |
| minor | `web/AO3WebViewFallbackScreen.kt` | If a user ends up on an actual AO3 page inside the in-app 'Open on AO3' fallback browser and taps a Download link there, nothing happens — no file, no error message, just silence. On iOS the same fallback browser catc... | 🔲 Not yet reviewed by a human |
| note | `android/app/src/test/java/io/github/cidy02/kudos/` | The rules for what links stay in the app vs. open a browser are well tested in isolation, but the actual screen that wires those rules into the live web view has no test coverage, so a regression there (e.g. a broken ... | 🔲 Not yet reviewed by a human |

### Reading queues (e.g. Saved for Later)

| Severity | File | Summary | Status |
|---|---|---|---|
| major | `works/WorkDetailScreen.kt` | On the iPhone app, tapping "Add to Saved for Later" on a work you haven't downloaded yet only queues it for offline reading — it does not add it to your permanent Library. On Android, doing the same thing quietly also... | 🔲 Not yet reviewed by a human |
| major | `library/ReadingQueueRepository.kt` | The whole point of a reading queue (like Saved for Later) is that the app should download a local copy so the story is available offline. On iOS, adding a work to a queue automatically starts that download in the back... | 🔲 Not yet reviewed by a human |
| major | `library/ReadingQueueRepository.kt` | On iOS you can rename a reading queue, delete one you no longer want (it goes to Recently Deleted, recoverable for 90 days), and drag to reorder the works inside it. On Android none of that exists — once you create a ... | 🔲 Not yet reviewed by a human |
| note | `android/app/src/test/java/io/github/cidy02/kudos/library/ReadingQueueRepositoryTest.kt` | The automated tests for reading queues only check the basics (add/remove a work, default Saved for Later queue). Creating a custom queue and its ordering logic aren't tested at all, so a regression there wouldn't be c... | 🔲 Not yet reviewed by a human |

### Author profile / author works

| Severity | File | Summary | Status |
|---|---|---|---|
| major | `author/AuthorWorksScreen.kt` | On iOS, tapping an author's name opens a real profile page: their bio, a Subscribe/Mute/Block button, and separate tabs for their Works, Series, and Bookmarks. On Android, tapping an author's name just runs an AO3 sea... | 🔲 Not yet reviewed by a human |
| note | `author/AuthorWorksScreen.kt` | The code that drives the author-works screen's loading, error, and page-navigation states isn't covered by any automated test, so a regression there (e.g. Retry loading the wrong page, or the Next button staying enabl... | 🔲 Not yet reviewed by a human |

### Reader: EPUB rendering, chrome, themes, TTS, customize panel, open/loading skeleton

| Severity | File | Summary | Status |
|---|---|---|---|
| major | `ui/components/ReaderPageSkeleton.kt` | If you pick a reader theme (say Sepia) that's different from your overall app theme (say Light), every time you open a book the screen will briefly flash the app's Light background before switching to the Sepia readin... | 🔲 Not yet reviewed by a human |
| minor | `ui/components/ReaderPageSkeleton.kt` | On many modern, tall phone screens the opening-book skeleton's placeholder text lines stop well short of the bottom of the screen, leaving an odd empty gap — the same look-broken symptom iOS just fixed. In a split-scr... | 🔲 Not yet reviewed by a human |
| minor | `reader/ReaderScreen.kt` | iOS shows the book's title and its author under the back button while reading. Android's reader header shows only the title — the author's name is missing. | 🔲 Not yet reviewed by a human |
| note | `reader/ReaderScreen.kt` | iOS can read a book aloud to you in the reader; Android has no read-aloud feature at all. This is already on the Android team's own to-do list, not a surprise bug, but it's worth confirming it's still the plan. | 🔲 Not yet reviewed by a human |
| note | `reader/ReaderScreen.kt` | iOS lets you fine-tune the reading page in detail — font, bold, line/letter/word spacing, margins, justified text, with a live preview and a reset button. Android's version only lets you change text size and the light... | 🔲 Not yet reviewed by a human |
| note | `ui/components/ReaderPageSkeleton.kt` | The logic that decides how many placeholder lines to draw while a book is opening has no automated test on Android, unlike iOS which specifically tests this after finding bugs in it. Worth adding a test once the fill ... | 🔲 Not yet reviewed by a human |

### Authentication / login

| Severity | File | Summary | Status |
|---|---|---|---|
| major | `auth/AO3WebLoginScreen.kt` | The login screen's check for 'is this still an AO3 page' can be tricked by a domain that simply ends with the letters 'archiveofourown.org' with nothing separating them, like 'evilarchiveofourown.org' — it isn't requi... | 🔲 Not yet reviewed by a human |
| major | `auth/AO3AuthRepository.kt` | If the saved-login file on disk is ever unreadable for a reason other than being garbled JSON — a permission glitch, a disk error, a half-written file from a previous crash — the Android app will crash every time it s... | 🔲 Not yet reviewed by a human |
| major | `auth/AO3WebLoginScreen.kt` | If AO3's page changes in a way that makes the app unable to read the username off the logged-in page, the Android login screen will just sit there forever after the user successfully logs in on AO3's own page — no err... | 🔲 Not yet reviewed by a human |
| note | `test/java/io/github/cidy02/kudos/auth/AO3AuthTest.kt` | The code path that actually finishes a login (after the user submits AO3's web form) and the code path that reacts to AO3 kicking the session out mid-session don't have their own automated tests, even though the surro... | 🔲 Not yet reviewed by a human |

### Comments: viewing, posting, threading

| Severity | File | Summary | Status |
|---|---|---|---|
| major | `comments/CommentsScreen.kt` | When you open Comments on Android, the screen never tells you which work you're looking at — no title, no author, no fandom — just "Comments" at the top and a bare list. On iOS the same screen shows a card with the wo... | 🔲 Not yet reviewed by a human |
| major | `comments/CommentsScreen.kt` | If posting a comment on Android times out or the connection drops partway through, the app just shows a generic error and lets you tap "Post Comment" again with the same text — but the first attempt may have actually ... | 🔲 Not yet reviewed by a human |
| major | `comments/CommentsScreen.kt` | You can see that comments are nested replies to each other (the indentation shows it), but there's no way to actually reply to a specific comment on Android — the only option is posting a brand-new top-level comment o... | 🔲 Not yet reviewed by a human |
| major | `network/ao3/comments/AO3CommentModels.kt` | Android only ever loads the first page of a work's comments and has no page controls, so on a work with a lot of comments you'll only ever see the first batch with no indication that more exist or any way to reach the... | 🔲 Not yet reviewed by a human |
| minor | `comments/CommentsScreen.kt` | Once you've posted a comment on Android, you can't edit or delete it from within the app — you'd have to go to the AO3 website. iOS lets you swipe on your own comment to edit or delete it directly. | 🔲 Not yet reviewed by a human |
| minor | `comments/CommentsScreen.kt` | Commenter names on Android are just plain text — tapping one does nothing, even though the app already knows the link to their profile. On iOS, tapping a commenter's name opens their AO3 profile. | 🔲 Not yet reviewed by a human |
| note | `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentRepositoryTest.kt` | The automated tests for Android's comment posting only check the happy path and one error page — there's no test coverage for what happens on a network timeout during posting, or for replies, editing, deleting, or mul... | 🔲 Not yet reviewed by a human |