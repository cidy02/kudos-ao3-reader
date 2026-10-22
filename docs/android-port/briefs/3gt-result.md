# Brief 3gt result — debug screenshot routes

Implemented in this worktree on `android/agent-codex-shots`; uncommitted. This file was created before code edits. All 70 A82 names are mapped. The table describes the code paths; phone rendering has not been observed.

Launch with `adb shell am start -n io.github.cidy02.kudos/.MainActivity --es kudosDebugRoute shot:<name>`. No separate demo extra is needed: DEBUG `shot:` launches activate the existing fixture interceptor before startup requests, enter its local `AO3_Reader` fixture session, and wait for demo seeding before navigation. No real sign-in is performed. Warm launches also enter that local fixture session; repeat requests reopen dismissed screens.

One dispatcher (`app/DebugShots.kt`) selects an existing navigation route and the pages/sheets that consume a pending request. Each hook waits for its own data and a resumed page (so an exiting navigation entry cannot consume the next shot), acts once, and is inert without a request. Both launch dispatch and consumption are gated by `BuildConfig.DEBUG`; release routing is unchanged. No new dependency or presentation component.

`file:line` below is relative to `android/app/src/main/java/io/github/cidy02/kudos/` and points to the hook or existing page entry.

| name | what is on screen | file:line | notes |
| --- | --- | --- | --- |
| `libpicker` | Fandoms multi-select dialog over Library filters | `library/LibraryFilterPanel.kt:304` | Uses the demo library’s fandom options. |
| `queuesettings` | Neon reread queue details | `library/QueueSettingsScreen.kt:77` | Existing UI; request consumed once. |
| `newqueue` | New Queue editor over the organizer | `library/QueueOrganizerScreen.kt:117` | Existing UI; request consumed once. |
| `editqueue` | Edit Neon reread sheet | `library/QueuePageScreen.kt:141` | Existing UI; request consumed once. |
| `addworks` | Add works from library sheet over Neon reread | `library/QueuePageScreen.kt:142` | Existing UI; request consumed once. |
| `queuetag` | Shared queue-tag dialog over Neon reread details | `library/QueueSettingsScreen.kt:100` | Android equivalent: assign/remove queue tags; the existing QueueTagSheet. |
| `queuetags` | Neon reread tag manager | `library/QueueSettingsScreen.kt:100` | Manager replaces details inline. |
| `queuetagedit` | Rename Rereads dialog over the tag manager | `library/QueueTags.kt:270` | Existing QueueTagEditDialog; Android’s single-tag editor. |
| `bulktag` | Bulk work-tag dialog over selected Neon reread works | `library/QueuePageScreen.kt:143` | Selection uses demo work IDs; no tags are applied automatically. |
| `addtoqueue` | Sodium Lights Add to Queue form | `works/WorkDetailScreen.kt:333` | Current Android equivalent is WorkDetailQueueForm; existing memberships are checked. |
| `queuestorage` | Queue Storage page | `settings/QueueStorageScreen.kt:67` | Existing UI; request consumed once. |
| `collectiondetails` | Comfort reads collection editor sheet | `library/CollectionDetailScreen.kt:156` | Existing UI; request consumed once. |
| `newcollection` | New Collection sheet over Collections | `library/CollectionsScreen.kt:68` | Existing UI; request consumed once. |
| `collectionreorder` | Comfort reads reorder sheet | `library/CollectionDetailScreen.kt:156` | Uses the collection’s current demo works. |
| `addtocollection` | Sodium Lights collection-membership dialog | `works/WorkDetailScreen.kt:332` | Existing collections and membership load through the normal dialog effect. |
| `fandomlist` | TV Shows fandom list | `browse/FandomListScreen.kt:54` | Uses /media/TV Shows/fandoms fixture. |
| `fandomworks` | Doctor Who works | `browse/FandomWorksScreen.kt:70` | Existing UI; request consumed once. |
| `tagworks` | Star Wars tag works | `browse/FandomWorksScreen.kt:70` | Same screen with isTag = true. |
| `fandomfilter` | Fandom list filter sheet over TV Shows | `browse/FandomListScreen.kt:73` | Existing UI; request consumed once. |
| `savesearch` | Save Search sheet over Search filters | `search/SearchScreen.kt:193` | Seeds an unsaved Doctor Who filter and its default name; does not save it. |
| `pagejump` | Page scrubber over Doctor Who results | `ui/components/KudosPaginationBar.kt:85` | The existing fixture has three pages; no page change is submitted. |
| `languagepicker` | Language picker sheet over Search filters | `search/FilterLanguagePicker.kt:53` | Actual Android code has a nested picker sheet. Scrolls filters to Language and expands the parent. |
| `tagpicker` | Fandom include/exclude picker over Search filters | `search/FilterTagPicker.kt:71` | Actual Android code has a nested picker. Scrolls to Tags and expands the parent; no query is submitted. |
| `downloaddate` | Downloaded-date dialog over Sodium Lights → My copy | `works/detail/WorkDetailMyCopySheet.kt:125` | No date is saved automatically. |
| `seriespreserve` | Preserve Series? form for Sodium Lights / My Series | `works/WorkDetailScreen.kt:341` | A82’s missing-data note is stale here: DemoLibrary already links /series/999. Reads its existing fixture; does not add or preserve works. |
| `bookmarkform` | Sodium Lights AO3 bookmark composer | `works/WorkDetailScreen.kt:346` | Uses the existing advisory bookmark values; no bookmark is submitted. |
| `readercontents` | Contents sheet over The Long Way Down | `reader/ReaderScreen.kt:378` | Waits for the publication and a live position. |
| `readerfind` | Find in Work sheet over The Long Way Down | `reader/ReaderScreen.kt:378` | Waits for the publication and a live position. |
| `readerdisplay` | Reader display sheet over The Long Way Down | `reader/ReaderScreen.kt:378` | Waits for the publication and a live position. |
| `readernote` | Add Note editor with a demo passage highlighted over The Long Way Down | `reader/ReaderScreen.kt:378` | Waits for the publication and a live position. Creates/reuses a local highlight from this demo EPUB, then opens the normal note editor. |
| `pronunciations` | Pronunciations sheet over Listening | `settings/PronunciationSettings.kt:47` | Scrolls Listening to Read Aloud so the existing row is mounted; no playback. |
| `pronunciationedit` | Add Pronunciation editor over Pronunciations | `settings/PronunciationSettings.kt:68` | Blank existing editor; no pronunciation is saved. |
| `customizetheme` | Customize Theme sheet over Appearance | `settings/SettingsPages.kt:47` | Existing UI; request consumed once. |
| `formattingtray` | More formatting tray over a new comment composer | `comments/CommentComposerSheet.kt:87` | Comments fixture for work 12345; no comment is submitted. |
| `chapterpicker` | Browse Comments by Chapter sheet | `comments/CommentsScreen.kt:178` | Uses the same loadChaptersIfNeeded call as the By Chapter control, for work 12345. |
| `inboxfilter` | Inbox Filters sheet | `account/AccountInboxPane.kt:129` | Waits for the fixture filter form. |
| `authorabout` | AO3_Reader About page | `author/AuthorProfileScreen.kt:76` | Existing author-about route. |
| `seriesdetail` | The Dawn Cycle series page | `app/SeriesWorksScreen.kt:70` | Existing /series/321 fixture. |
| `seriesedit` | The Dawn Cycle series editor | `app/SeriesWorksScreen.kt:127` | Waits for the series and fixture creator permissions. |
| `seriesreorder` | The Dawn Cycle reorder works editor | `app/SeriesWorksScreen.kt:127` | Existing reorderOnly mode. |
| `seriesremove` | The Dawn Cycle Remove works editor | `writing/WritingSeriesScreen.kt:63` | No removal is confirmed. |
| `authorworksfilter` | AO3_Reader Works sort and filter sheet | `author/AuthorProfileScreen.kt:407` | Existing refine mode. |
| `colitems` | Winter Exchange collection items | `account/AO3CollectionItemsScreen.kt:84` | Existing collection-items route, not the all-user items route. |
| `colsfilter` | AO3 collections filter panel | `account/AO3CollectionsScreen.kt:98` | Existing UI; request consumed once. |
| `chsettingsedit` | Winter Exchange challenge settings editor | `app/AppNavHost.kt:792` | Existing route’s editor branch; no save. |
| `chsignupdetail` | First Winter Exchange participant’s sign-up details | `account/AO3ChallengeSignUpsScreen.kt:82` | Waits for fixture participants, then opens the existing inline detail page. |
| `prompttags` | First Winter Exchange request’s tags editor | `account/AO3ChallengeSignUpScreen.kt:66` | Existing SignUpTagsEditor, showing the prompt’s tag fields. |
| `tagset` | Winter Exchange Tags tag set | `account/AO3TagSetScreen.kt:39` | Tag set 42, moderator route flag. |
| `tagseteditor` | Winter Exchange Tags → Add tags editor | `account/AO3TagSetScreen.kt:59` | Android equivalent shows Fandoms, Characters, Relationships and Additional tags together. |
| `writingpreview` | AO3 preview for posted demo work 995006 | `writing/WritingWorkFormScreen.kt:111` | Uses the existing posted-work fixture. Calls the same fixture-only preview request as Preview on AO3; no post/update. |
| `chapters` | Chapters list for posted demo work 995006 | `writing/WritingWorkFormScreen.kt:112` | Uses the existing posted-work fixture. No edit is saved. |
| `chapterform` | Existing draft chapter editor for chapter 12311 | `writing/WritingChapterFormScreen.kt:30` | Existing writing-chapter-draft-demo route, work 995001. |
| `edittags` | Edit Tags page for posted demo work 995006 | `writing/WritingWorkFormScreen.kt:113` | Uses the existing posted-work fixture. No edit is saved. |
| `tagseditor` | Fandoms tags editor for posted demo work 995006 | `writing/WritingWorkFormScreen.kt:114` | Uses the existing posted-work fixture. No edit is saved. |
| `texteditor` | Chapter text editor | `writing/WritingTextEditorScreen.kt:117` | Existing editor demo; dismisses its recovery choice with Keep form text for this shot only. |
| `recovery` | Recover unfinished text? sheet over Chapter text | `writing/WritingTextEditorScreen.kt:117` | Reuses WritingEditorDemoScreen’s seeded recovery copy and waits for its read; no recovery action is chosen. |
| `seriespicker` | Series association picker for posted demo work 995006 | `writing/WritingWorkFormScreen.kt:115` | Uses the existing posted-work fixture. No edit is saved. |
| `collectionsgifts` | Collections and gifts editor for posted demo work 995006 | `writing/WritingWorkFormScreen.kt:116` | Uses the existing posted-work fixture. No edit is saved. |
| `creatorspicker` | Co-creators editor for posted demo work 995006 | `writing/WritingWorkFormScreen.kt:117` | Uses the existing posted-work fixture. No edit is saved. |
| `parentpicker` | Inspired by / parent-work editor for posted demo work 995006 | `writing/WritingWorkFormScreen.kt:118` | Uses the existing posted-work fixture. No edit is saved. |
| `bulkedit` | Bulk edit for the first two AO3_Reader demo works | `author/AuthorProfileScreen.kt:407` | Uses the same WritingBulkEditState as selecting those works manually. |
| `bulktagstate` | Archive warnings bulk state picker | `writing/WritingBulkEditScreen.kt:42` | Existing tri-state BulkOptionsScreen (unchanged / add / remove). |
| `bulknames` | Add to collections name-list editor | `writing/WritingBulkEditScreen.kt:42` | Current Android code has BulkOptionsScreen mode names, with its add-name field visible; no names are added. |
| `prefhelp` | Privacy Preferences help sheet | `account/AO3PreferencesScreen.kt:147` | Opens the first fixture section help using the existing loadHelp request. |
| `privacydata` | Privacy and local data page | `settings/SettingsScreen.kt:40` | Uses the demo’s existing local assets and data. |
| `availability` | Check Availability page | `settings/AvailabilitySweepScreen.kt:54` | Does not start a sweep. |
| `pairing` | Pair a Device sheet over Sync Folder | `backup/PairingSheet.kt:96` | Opens the existing pairing UI; does not trust an entered key. |
| `revokedevice` | Revoke Device reason dialog for Demo reading tablet | `backup/PairingSheet.kt:96` | Uses the demo peer already seeded by DemoLibrary. DEBUG-only seedShotDevice replaces that peer if previously revoked; no revoke is confirmed. |
| `backupimport` | Import Backup review sheet over Backup | `backup/BackupScreen.kt:75` | Prepares the existing android-export.kudosbackup copied to DEBUG assets with the normal parser/preview. No import or replace is executed. |
| `aboutkudos` | About Kudos page | `account/AboutScreen.kt:42` | Existing UI; request consumed once. |

## What could not be done, and why

- No screen was left unmapped. Android equivalents that differ from the inventory are called out in the table; existing screens were reused rather than adding parallel UI.
- Build, JVM test execution, installation and phone screenshots were not run: the brief reserves builds/tests for Claude and forbids Gradle. Runtime behavior and visual correctness remain unverified.

## Verification and handoff

- Added exactly one JVM test: `android/app/src/test/java/io/github/cidy02/kudos/app/DebugShotsTest.kt`, `everyA82NameIsKnownToTheDispatcher`. It reads A82 directly, so future inventory additions must resolve too. Not executed here.
- Static inventory comparison: 70 A82 names, 70 dispatcher names, no missing or extra names. All 39 requested hook owners have a consumer. `git diff --check` passes.
- Backup fixture bytes match `KudosTests/Fixtures/cross-platform/android-export.kudosbackup`; bundled only under `src/debug/assets`. The import hook prepares the review and performs no restore.
- Existing demo series links and editor recovery fixtures were sufficient. The only extra seed is a replacement demo pairing peer when that labelled peer is absent. The reader-note shot creates/reuses a local demo highlight to open Add Note.
- No Gradle, commit, push, branch switch, real sign-in, or AO3 contact performed. `TASKS.md` and the three pre-existing untracked brief/inventory files are untouched.
- Next: Claude builds the DEBUG and release targets, runs `DebugShotsTest`, and shoots each `shot:<name>` on the phone.
