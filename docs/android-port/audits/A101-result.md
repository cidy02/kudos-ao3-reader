# A101 — owner decisions still present on Android

| Coverage at Android `7b2f69f4` | Present | Different | Absent | Waiting on an owner question | Excluded: iPhone only |
|---|---:|---:|---:|---:|---:|
| A77 W01–W16 | 15 | 0 | 0 | 1 | 0 |
| A77 C01–C46 | 45 | 0 | 0 | 1 | 0 |
| A77 D01–D20 | 19 | 0 | 0 | 0 | 1 |
| **All 82 A77 coverage entries** | **79** | **0** | **0** | **2** | **1** |
| Answered questions, rechecked separately (already included above) | 7 | 0 | 0 | 0 | 0 |

**No unparked implementation gap found in the enumerated owner decisions. All eight 3go fixes survive.** This supports part 2 of Android's Done at the source level, with the recorded Android replacements and open questions below. It does **not** verify the other four parts of Done, fresh test results, or rendering on a device.

Counts are coverage entries, not independent decisions. Of the 79 present entries, **75 have the required implementation and four use an accepted Android replacement**: C04/C05/C08 (buttons and menus, so no swiped comment or settling rails) and D03 (native Android chrome). These are explicitly labelled below. D17 is present: predictive Back is an Android requirement with an actual manifest setting. D18 is the expressly iPhone-only repair. This accounting replaces A77's original verdicts with its subsequent triage; it does not claim that swipe rails were implemented.

## Ranked items that are not present as literal iOS behaviour

There is **no actionable different/absent item** to fix from this recheck. The two parked items, ordered by ordinary screen exposure, are:

1. **Q12 / C02: the bottom navigation bar stays full size while scrolling.** `A:app/MainScaffold.kt:497` draws it whenever `showTabBar` is true; the scroll-direction rule at `A:app/ScrollAwayTopChrome.kt:16` controls top chrome. `docs/android-port/OWNER-DECISIONS-ANDROID.md:211` still leaves bar scrolling, Search as a tab, and reader controls open. **Fix only if the answer requests it:** drive the Material navigation bar's hide/return behaviour from the existing scroll state, retaining navigation and accessibility. Do not introduce an iOS glass/minimizing bar by assumption. This was already a documented Android replacement at A77, not a new regression.
2. **Q9 / W11: Backup retains extra technical notes and its duplicate pairing section.** `A:backup/BackupScreen.kt:265` and `:271` retain manifest/trust/CSRF/ZIP paragraphs; `:278` mounts `PairingCard`. The shared plain footer is still at `:214`. `docs/android-port/OWNER-DECISIONS-ANDROID.md:141` explicitly says to keep both until answered. **If A is chosen:** remove the two extra footnotes and Backup's pairing card; retain pairing on Sync Folder and retain all underlying validation. If B is chosen, no fix. The formerly missing no-tags copy is now present and is not waiting on Q9.

C04/C05/C08 and D03 need no fix: literal iOS interactions/visuals were replaced by Android's recorded equivalents. D18 is outside Android's requirements. Other open questions, including Q16, Q23, Q28 and Q32–34, have not been silently converted into missing approved features.

## Source identity and boundaries

- Android: `7b2f69f4c8eef0c4d6dd939cbdc0e7df5a06ceda`, branch `android/agent-codex-a101`. This exact branch already existed at that exact commit when the task began; no branch recreation/reset was necessary or performed. The pre-existing untracked `docs/android-port/briefs/A101-owner-decisions-recheck.md` was preserved.
- iOS committed reference: `1e5d3d445618db135555c0382940dffbb75755cc` in `/Users/cidy02/kudos-ios-polish`. Relevant iOS files were read using `git show HEAD:kudos-ao3-reader/<path>`; uncommitted Duo changes were not used as reference evidence.
- `A:` means `android/app/src/main/java/io/github/cidy02/kudos/` in this worktree. `I:` means `kudos-ao3-reader/` in the committed iOS reference. Unprefixed documentation paths are relative to this worktree, except `L:` below. Every numbered source reference is current to its stated snapshot.
- The requested `docs/android-port/LIVING-PROMPT.md` is absent here and is not tracked at `7b2f69f4`. I read the authoritative local lane copy, `/Users/cidy02/kudos-android-lane/docs/android-port/LIVING-PROMPT.md` (**`L:`** below), including all of §0 and §6. Its SHA-256 when read was `1912dc60bb07d0885329a4005493097ca815741d98e2ca8e0b0010aa13dc82dc`. Its later handover directive is therefore identified as local prompt evidence, not invented committed content of `7b2f69f4`.
- Method: reopen each A77 implementation, map moved lines to current code, inspect the changed call paths and the later decision entries, and compare the important iOS branches from committed source. A similarly named helper alone is insufficient: download observers, action callers, the wash consumer and the no-tags identity argument were traced too.
- Read only except this report. No code/task-board edits, commits, pushes, sign-in, AO3 contact, Gradle, builds, app launch or simulator work. The task's explicit single-file scope supersedes the usual task-board and commit workflow.

## The eight 3go fixes, checked through their current callers

| Original A77 independent gap | Current verdict and Android evidence | Committed iOS reference |
|---|---|---|
| Account icon ink | **Present.** `A:ui/subject/SubjectComponents.kt:844` keeps the 16% exact-accent square; `:851` uses `tokens.theme.accentInk(accent)` for its glyph. Shortcuts and hub rows still share this component at `A:account/AccountScreen.kt:796` and `:835`. | `I:Features/Account/AccountComponents.swift:444` uses readable tint; `:448` uses the separate exact fill; `I:UIComponents/AccentInk.swift:5` lifts Dark/OLED ink. |
| Editor switches retain the picked colour | **Present.** `A:library/QueueEditorSheet.kt:216`, `A:library/CollectionEditorSheet.kt:326` and `:346` pass `palette.tint`, not hue-derived `accent`. Hex-first palette construction remains at Queue `:378` / Collection `:381`; `A:ui/subject/SubjectToggle.kt:47` uses its supplied colour unchanged. | `I:UIComponents/SubjectSurface.swift:76`, `I:Features/Library/NewCollectionSheet.swift:130`, `I:UIComponents/AccentInk.swift:58`: exact fill separated from readable control ink. |
| Real download fraction instead of a looping sweep | **Present.** `A:network/ao3/AO3Client.kt:413` reads content length and `:422` reports received bytes; `A:network/ao3/work/AO3EpubDownloader.kt:20` passes progress through. `A:works/DownloadQueue.kt:220` starts the creep, `:228` passes task progress, `:297` monotonically merges fractions, `:237` reaches 1 and holds 300 ms, `:241` marks failure. `A:ui/subject/SubjectWorkCoverCard.kt:106` observes only queued/downloading fractions; `A:ui/subject/WorkReadingRing.kt:21` substitutes that fraction. | `I:Services/DownloadQueue.swift:96` takes max(task progress, creep towards 90%); `:176` holds completion; `I:UIComponents/SubjectSurface.swift:1007` substitutes the ring. |
| Grey all named card/row surfaces | **Present.** `A:home/HomeResumeHero.kt:73`, `A:ui/subject/SubjectWorkCoverCard.kt:153`, `A:works/detail/WorkDetailIdentity.kt:348`, `A:ui/components/SensitiveWorkRow.kt:851`, `A:library/QueueChrome.kt:256` and `A:ui/subject/WorkLibraryComponents.kt:165` apply `downloadDimmed`. Saved rows obtain the shared queue through `A:ui/components/WorkRowActions.kt:71`, installed at `A:app/AppNavHost.kt:120`. Work Detail forwards its observed fraction at `A:works/WorkDetailScreen.kt:1619`. | `I:Features/Library/WorkRow.swift:91`, `I:UIComponents/SubjectSurface.swift:1037`. Android's documented RGB scaling approximates iOS brightness; the installing-state desaturation/dimming behaviour is present, not a claim of identical pixels. |
| Recently Deleted's “Downloaded work” | **Present.** `A:library/RecentlyDeletedScreen.kt:158` calls `recentlyDeletedWorkKicker`; `:1025` tests `work.isDownloaded`, not `hasEpub`. An un-kept reading copy says “Work”. | `I:Features/Library/RecentlyDeletedView.swift:465`; kept-copy derivation at `I:Models/Models.swift:482`. |
| Newest wash and sheet-owned controls | **Present.** `A:ui/subject/SubjectComponents.kt:178` takes `lastOrNull`; registration updates in place at `:180`, disposal removes at `:153`. `A:app/MainScaffold.kt:281` consumes it. `A:ui/subject/SubjectPaletteTheme.kt:9` installs sheet-local palette, exact accent and readable Material primary; Queue `:139` and Collection `:153` wrap their dialogs in it. A100's filter-only app-palette change did not remove these editor wrappers. | `I:UIComponents/SubjectSurface.swift:1298` picks newest; `I:App/ContentView.swift:89` installs it; `I:Features/Library/NewReadingQueueSheet.swift:154` installs the sheet tint. |
| Short fill for an existing file | **Present.** `A:works/DownloadQueue.kt:42` publishes an independent instant map with `elapsed / 700.0` at `:50`; Home `A:home/HomeWorkMenu.kt:196`, Library `A:library/LibraryViewModel.kt:397` (bulk `:269`) and Work Detail `A:works/WorkDetailScreen.kt:652` invoke it when the file exists. Observer `A:ui/subject/SubjectWorkCoverCard.kt:108` checks the instant map before queue items, so it reaches the same ring and dimming paths. | `I:Services/WorkDownload.swift:69` invokes the short path; `I:Services/DownloadQueue.swift:33` specifies 0.7 s and `:78` publishes it independently of queued downloads. |
| No-tags explanation | **Present.** `A:works/detail/WorkDetailSections.kt:216` now renders the empty case; `:276` supplies both exact iOS messages. `A:works/WorkDetailScreen.kt:1685` passes the actual AO3 identity, distinguishing an imported work from an AO3 work. | `I:Features/WorkDetail/WorkDetailSections.swift:44` supplies the same AO3-refresh and unlinked-import explanations. |

Existing regression coverage remains in source: `android/app/src/test/java/io/github/cidy02/kudos/library/OwnerDecisions3goTest.kt:14` (kicker), `:24` (wash precedence/restoration); `android/app/src/test/java/io/github/cidy02/kudos/ui/subject/OwnerDecisions3goComposeTest.kt:53`, `:72`, `:100`, `:128` (ink/fill, sheet controls, ring/dimming, empty tags); and `android/app/src/test/java/io/github/cidy02/kudos/works/DownloadQueueTest.kt:329`, `:337`, `:368` (creep, completion beat, existing-file action callers). **Inspected, not run.**

## Every A77 working-note entry

| ID | Decision | Current verdict | Current implementation and one-line evidence |
|---|---|---|---|
| W01 | Edit Queue reuses New Queue | Present | `A:library/QueueEditorSheet.kt:75` seeds edit state, `:107` updates the existing id, `:157` titles Edit queue and `:168` says Save; `A:library/QueuePageScreen.kt:664` offers Edit Queue. |
| W02 | Store custom hex and hue exactly | Present | `A:ui/subject/SubjectForm.kt:308` returns both; `A:library/ReadingQueueRepository.kt:287` persists hex and `:328` updates it without deriving it from hue. |
| W03 | Queue hold menu: Edit, Pin/Unpin, Delete | Present | `A:library/QueueChrome.kt:390` opens the menu and `:395` begins those actions; `A:library/QueueOrganizerScreen.kt:486` installs it on rows. |
| W04 | Home's stacked queue deck | Present | `A:home/HomeQueueCard.kt:90` draws the 96 dp deck with 148×88 faces and offset back layers. |
| W05 | No queue-page bottom switcher | Present | `A:library/QueuePageScreen.kt:447` adds bottom actions only while selecting; normal actions remain in `:625`'s toolbar. |
| W06 | New Collection wash follows pick | Present | `A:library/CollectionEditorSheet.kt:79` derives the draft palette and `:161` paints it; `:381` prefers exact hex, falling back to the app palette before a pick. |
| W07 | One action control, filters/create in top chrome | Present | `A:library/LibraryShellChrome.kt:128` installs one create and one filter; `A:home/HomeShellChrome.kt:96` creates queues above the shelf at `A:home/HomeScreen.kt:262`. Other named surfaces are C09/C21/C24/C32/C35. |
| W08 | Select in overflow | Present | `A:library/RecentlyDeletedScreen.kt:405`, `A:account/AccountInboxPane.kt:532`, `A:home/HomeShellChrome.kt:119`, `A:library/LibraryShellChrome.kt:156` retain it; own Works keeps its shared iOS exception at `A:author/AuthorProfileScreen.kt:487`. |
| W09 | Exact picked control fill | Present, fixed since A77 | `A:library/QueueEditorSheet.kt:216` and `A:library/CollectionEditorSheet.kt:326`/`:346` now supply exact tint; readable ink is separate in `A:ui/subject/SubjectPaletteTheme.kt:11`. |
| W10 | Avoid known refused reads; owner-only schedule once/opening | Present | `A:account/AO3PromptMemeState.kt:30` requires owner, not attempted and no known date; `:108` records the attempt; actual ownership comes from `A:account/AO3CollectionDetailScreen.kt:248`. Kind-specific follow-up is N01 below. |
| W11 | Plain explanatory copy | Waiting: Q9; other A77 counterexample fixed | `A:backup/BackupScreen.kt:214` keeps the iOS footer but `:265` retains Q9's technical extras; `A:works/detail/WorkDetailSections.kt:216` now explains missing tags. This rechecks A77's concrete counterexamples, not every string in T-342. |
| W12 | Keep works you read | Present | `A:reader/ReaderRepository.kt:58` only keeps when enabled; `A:settings/SettingsPages.kt:213` binds the preference, whose default is false at `A:core/model/SettingsModels.kt:74`. |
| W13 | Downloaded means kept; Read is not Download | Present, fixed since A77 | `A:core/model/WorkDownloadSemantics.kt:16` derives kept/imported + file; Recently Deleted now uses it at `A:library/RecentlyDeletedScreen.kt:1025`; Read labels remain at `A:works/WorkDetailScreen.kt:1607`. |
| W14 | Download ring replaces reading ring; card greys | Present, fixed since A77 | `A:ui/subject/WorkReadingRing.kt:21` substitutes the observed fraction; resume `A:works/detail/WorkDetailIdentity.kt:348` and saved rows `A:ui/components/SensitiveWorkRow.kt:851` now dim too. See the full producer/observer trace above. |
| W15 | Remove Download only un-keeps | Present | `A:library/LibraryViewModel.kt:393` calls `setSaved(false)`; `A:works/WorkRepository.kt:347` updates flags without deleting the file. |
| W16 | Deleted/Finished-not-kept; 60-day hold | Present | `A:library/RecentlyDeletedScreen.kt:539` and `:579` retain the sections; `A:works/WorkRepository.kt:377` stamps the hold, `:440` sweeps it and `:1223` specifies 60 days; opening releases at `A:reader/ReaderRepository.kt:57`. |

## Every A77 owner-comment entry

| ID | Decision | Current verdict | Current implementation and one-line evidence |
|---|---|---|---|
| C01 | Shell/tab accent follows top screen wash | Present, fixed since A77 | `A:ui/subject/SubjectComponents.kt:178` selects newest; `A:app/MainScaffold.kt:281` reads it and `:287` installs its Material primary. |
| C02 | Bottom bar minimizes on scroll | Waiting: Q12 | `A:app/MainScaffold.kt:497` keeps the full Android bar; `docs/android-port/OWNER-DECISIONS-ANDROID.md:219` explicitly leaves this choice open. |
| C03 | Home creates queues from top + | Present | `A:home/HomeShellChrome.kt:96` supplies +; `A:home/HomeScreen.kt:262` renders queue cards without a create cell. |
| C04 | Hide swiped comment's rails | Present via accepted Android replacement | `A:comments/CommentThreadComponents.kt:665` renders button/menu actions, so no comment is swiped; triage explicitly accepts this at `docs/android-port/DECISIONS.md:2591`. Literal swipe-rail hiding remains inapplicable. |
| C05 | Restore rails 650 ms after swipe settles | Present via accepted Android replacement | `A:comments/CommentThreadComponents.kt:665` uses the same non-swiping action path; no settling timer is required under the replacement recorded at `docs/android-port/DECISIONS.md:2591`. |
| C06 | Comment byline aligns with avatar | Present | `A:comments/CommentThreadComponents.kt:460` aligns columns at top, `:578` gives normal byline avatar-height minimum, and `:562` separates name/metadata at large text. |
| C07 | Collapse target does not push root name down | Present | `A:comments/CommentThreadComponents.kt:544` keeps the compact clickable pill with text padding at `:557`, without adding an oversized layout height to the byline. |
| C08 | Swiped ancestor's descendant connector hides | Present via accepted Android replacement | `A:comments/CommentThreadComponents.kt:309` still has unused swipe scaffolding, but actions are buttons at `:665`; the accepted no-swipe decision at `docs/android-port/DECISIONS.md:2591` removes the triggering interaction. |
| C09 | Author Works filter in top chrome | Present | `A:author/AuthorProfileScreen.kt:475` places Sort and filter in pushed trailing chrome, outside the content's scope rail. |
| C10 | New Collection wash tracks selected colour | Present | `A:library/CollectionEditorSheet.kt:79` creates the palette and `:161` paints it; `:381` uses exact picked hex and `:384` keeps the fallback before picking. |
| C11 | Remove queue bottom switcher | Present | `A:library/QueuePageScreen.kt:447` limits bottom controls to selection; its ordinary queue toolbar remains at `:625`. |
| C12 | Queue drag enabled through explicit overflow mode | Present | `A:library/QueueOrganizerScreen.kt:114` defaults reordering false; `:388` offers Reorder and `:482` branches into reorder rows only in that mode. |
| C13 | Library New Collection top + | Present | `A:library/LibraryShellChrome.kt:128` renders create beside filter at `:132` and overflow; no new-collection grid cell is needed. |
| C14 | Downloaded shelf: kept, newest first | Present | `A:library/LibraryQuery.kt:183` filters `isDownloaded`, excludes queue-only records and sorts descending `dateAdded`; `A:library/LibrarySectionKind.kt:65` uses it. |
| C15 | Remote Download fetches the EPUB | Present | `A:ui/components/RemoteWorkSelection.kt:238` prepares a readable file before keeping; `A:works/WorkImporter.kt:199` downloads if the file is missing, rather than only toggling metadata. |
| C16 | Recently Deleted Select in overflow | Present | `A:library/RecentlyDeletedScreen.kt:398` opens More and `:405` supplies Select. |
| C17 | Deleted 90d / Finished-unkept 60d, soonest first | Present | `A:library/RecentlyDeletedScreen.kt:210`/`:213` sort displayed days; sections at `:539`/`:579`; `A:works/WorkRepository.kt:1223` fixes 60d and `A:KudosApplication.kt:77` calls the hold sweep at launch. |
| C18 | Jump Back In fixed-width carousel, ten max | Present | `A:browse/BrowseCategoryPanels.kt:77` uses a LazyRow with fixed cards; `A:browse/JumpBackIn.kt:39` sets ten, consumed at `A:browse/CategoryStats.kt:144`. |
| C19 | Jump Back In limit ten | Present | `A:browse/JumpBackIn.kt:39` defines `LIMIT = 10`; `:102` takes the limit after ranking. |
| C20 | Browse downloaded count uses kept copies | Present | `A:browse/JumpBackIn.kt:30` maps `isDownloaded` to `isOnDevice`; `A:browse/CategoryStats.kt:95` counts it. T-344 supersedes the older raw-file wording. |
| C21 | Fandom sort rail only sorts/grouping | Present | `A:browse/FandomListChrome.kt:130` holds sort/group controls; the funnel remains in top chrome at `A:browse/FandomListScreen.kt:166`. |
| C22 | Jump Back In ranks latest visit OR read | Present | `A:browse/JumpBackIn.kt:66` seeds reads, `:79` folds newer visits, `:91` sorts recency and `:102` caps the result. |
| C23 | Fandom “I have downloads from” uses kept copies | Present | `A:browse/FandomFamily.kt:294` indexes only `work.isDownloaded`, not every physical reading copy. |
| C24 | Fandom filter top right | Present | `A:browse/FandomListScreen.kt:163` supplies pushed chrome and `:166` installs its FilterButton. |
| C25 | My Copy: reading copy says Not downloaded | Present | `A:works/detail/WorkDetailMyCopySheet.kt:449` first checks `isDownloaded`, then reports raw `hasEpub` as Not downloaded at `:453`. |
| C26 | Read uses play glyph | Present | `A:works/detail/WorkDetailIdentity.kt:409` uses `Icons.Filled.PlayArrow`, independent of the separate Download action. |
| C27 | Read / Continue Reading / Opening… | Present | `A:works/WorkDetailScreen.kt:1607` selects those exact three labels, never download wording. |
| C28 | Marked for Later Downloaded means kept | Present | `A:account/AccountWorksListScreen.kt:588` filters `local.isDownloaded`; the size line at `:737` is likewise gated on the kept copy. |
| C29 | Inbox direct filter, Select in overflow | Present | `A:account/AccountInboxPane.kt:494` supplies the direct filter; `:531` opens the overflow containing Select. |
| C30 | Account gear fades on scroll down | Present | `A:app/MainScaffold.kt:410` animates visibility with `!chromeHidden`; `A:app/ScrollAwayTopChrome.kt:16` computes direction/threshold. |
| C31 | Shortcuts and hub rows share accent square | Present | `A:account/AccountScreen.kt:796`/`:835` share `AccentIconSquare`; `A:ui/subject/SubjectComponents.kt:844` preserves exact fill and `:851` now applies Q19 ink. |
| C32 | Draft New Work in top + | Present | `A:account/WritingDraftsScreen.kt:107` installs a top ToolbarAddButton with New Work at `:108`, without a body create row. |
| C33 | Local-only freedAt | Present | `A:core/model/SavedWork.kt:91` holds it and `A:works/WorkRepository.kt:377` sets it; `A:backup/BackupManifest.kt:51`'s BackupWork and `A:backup/BackupMappers.kt:122`'s export do not serialize it. |
| C34 | Derived Downloaded = file AND keep/import | Present | `A:core/model/WorkDownloadSemantics.kt:16` implements the expression; `A:core/model/SavedWork.kt:119` supplies actual saved/kept/AO3 flags. |
| C35 | Entity grids create from top + | Present | `A:library/CollectionsScreen.kt:74` installs New Collection in shell actions; `A:library/QueueOrganizerScreen.kt:373` installs New Queue, with entities in the grid/list. |
| C36 | Actual download fraction and completion beat | Present, fixed since A77 | `A:works/DownloadQueue.kt:228` forwards progress, `:237` holds 1.0 for 300 ms; `A:ui/subject/WorkReadingRing.kt:21` renders the supplied fraction instead of a repeating sweep. |
| C37 | Installing-style greying | Present, fixed since A77 | `A:ui/subject/WorkReadingRing.kt:47` desaturates/dims; formerly omitted Work Detail and saved rows now call it at `A:works/detail/WorkDetailIdentity.kt:348` and `A:ui/components/SensitiveWorkRow.kt:851`. |
| C38 | Wash precedence and restoration | Present, fixed since A77 | `A:ui/subject/SubjectComponents.kt:178` takes newest, `:153` unregisters on disposal; editor controls are scoped at `A:library/QueueEditorSheet.kt:139`, not inherited from the underlying page. |
| C39 | Down hides top chrome; up/top restores | Present | `A:app/ScrollAwayTopChrome.kt:16` keeps 44 / +1 / −6 thresholds; `A:app/MainScaffold.kt:449` applies the visibility. Bottom-bar choice is separately parked as C02. |
| C40 | Bulk remote Download fetches files | Present | `A:ui/components/RemoteWorkSelection.kt:234` iterates preparation then keep; `A:works/WorkImporter.kt:205` reaches `downloadExisting` for a missing copy. |
| C41 | Existing-file Download gets 0.7s fill | Present, fixed since A77 | `A:library/LibraryViewModel.kt:397` emits the instant event; `A:works/DownloadQueue.kt:50` advances it over 700 ms; `A:ui/subject/SubjectWorkCoverCard.kt:108` observes it. |
| C42 | Finished un-kept file held 60 days | Present | `A:works/WorkRepository.kt:377` holds unprotected files; `:440` sweeps using the 60-day constant at `:1223`. |
| C43 | Keep works you read defaults off, never un-keeps | Present | `A:core/model/SettingsModels.kt:74` defaults false; `A:reader/ReaderRepository.kt:58` only sets saved true, with setting bound at `A:settings/SettingsPages.kt:213`. |
| C44 | Privacy separates reading copies/downloads | Present | `A:settings/LocalDataFootprint.kt:70` totals file-present/un-kept copies separately and subtracts them from downloaded bytes; `A:settings/PrivacyDataScreen.kt:125` says Free up space. |
| C45 | Remove Download leaves EPUB | Present | `A:library/LibraryViewModel.kt:393` only un-keeps via `A:works/WorkRepository.kt:347`; imported works still have no Download action at `A:core/model/WorkDownloadSemantics.kt:24`. |
| C46 | Existing-file Download short-fill caller | Present, fixed since A77 | `A:home/HomeWorkMenu.kt:196` now emits the instant event, and `A:ui/subject/SubjectWorkCoverCard.kt:110` prioritizes it over queue fractions. Duplicate of C41's behaviour. |

## Every A77 answered-question / decision-record entry

| ID | Decision | Current verdict | Current implementation and one-line evidence |
|---|---|---|---|
| D01 | Last Read and Kudos sorts | Present | `A:library/LibrarySort.kt:13`/`:17` expose both; `A:library/LibraryQuery.kt:227` uses last-read comparison (never-read last) and `:244` sorts kudos descending. |
| D02 | Home/Library accent follows hero | Present | `A:app/MainScaffold.kt:262` chooses the hero hue, `:269` builds its palette and `:331`/`:334` installs it for page controls; shell precedence is D12. |
| D03 | Q11: native Android tabs/chrome | Present via accepted Android replacement | `A:app/MainScaffold.kt:600` uses Material ShortNavigationBar; `A:ui/subject/SubjectComponents.kt:881` uses FilledTonalIconButton (plain branch at `:891`). Q11 does not authorize dropping content or information order. |
| D04 | Owner-only prompt schedule once/opening | Present | `A:account/AO3PromptMemeState.kt:30` gates ownership/attempt/date; `:108` stamps before requesting; caller `A:account/AO3CollectionDetailScreen.kt:248` passes real ownership. |
| D05 | Q19: readable Dark/OLED ink, exact fills | Present, fixed since A77 | `A:ui/subject/KudosTokens.kt:147` computes ink, `A:ui/subject/SubjectColor.kt:86` enforces 4.5:1 by stepping toward white; Account now uses it at `A:ui/subject/SubjectComponents.kt:851`, while `:844` preserves fill. |
| D06 | Q24: own Works/Series as iPhone, retain totals | Present | `A:author/AuthorProfileScreen.kt:110` uses account header and `:111` omits profile tabs for own destinations; totals remain at `:732`, fandom chips at `:925`; `A:app/AppNavHost.kt:1013` routes My Works to it. |
| D07 | Q25: unfold control at card foot | Present, same iOS exception | `A:ui/components/SensitiveWorkRow.kt:444` puts AO3 detailed disclosure at the foot; `:320` retains saved detailed-card title disclosure, as committed `I:Features/Library/WorkRow.swift:214` does too. |
| D08 | Q25: account lists open Compact | Present, same recorded source conflict | `A:account/AccountWorksListScreen.kt:169` defaults Compact, matching `I:Features/Bookmarks/AO3AccountWorksList.swift:166`. Own-author Works/Series still default Ledger at `A:author/AuthorProfileScreen.kt:146`, matching `I:Features/Authors/AuthorProfileView.swift:15`; the broad Q25 shorthand still overstates both implementations. |
| D09 | Q27: words actually read per sitting | Present | `A:library/ReadingStatistics.kt:187` groups/chronologically orders sessions, counts positive progress delta × words and resets after finish; `:262` divides those words by hours, matching `I:Services/ReadingLogService.swift:309`. |
| D10 | Q29: Customize Theme opens typography sheet | Present | `A:settings/SettingsPages.kt:119` opens it; `A:reader/CustomizeThemeSheet.kt:161` renders the preview, `:188` four themes, `:220` font, `:224` Bold, `:233` Customize, `:239`–`:255` spacing/margins/justify and `:262` reset. |
| D11 | Q30: immediate last-colour Highlight; Add Note edits | Present | `A:reader/ReaderScreen.kt:260` restores last colour, `:508` submits it and `:548`/`:549` wire both actions; `A:reader/AnnotationRepository.kt:123` reuses/toggles/recolours; `A:reader/ReaderViewModel.kt:330` opens the note editor. |
| D12 | Top screen wash owns tab/chrome colour | Present, fixed since A77 | `A:ui/subject/SubjectComponents.kt:178` selects newest; shell reads it at `A:app/MainScaffold.kt:281`; sheets install local control roles at `A:ui/subject/SubjectPaletteTheme.kt:9`. |
| D13 | Reader buttons use app's placement/size | Present | `A:reader/ReaderChromeTopBar.kt:62` uses 4 dp horizontal / 6 dp top offsets, app-sized arrow at `:68` and 48 dp target at `:158`; shell matches offsets at `A:app/MainScaffold.kt:455`. |
| D14 | Converter staleness only on own version scale | Present | `A:works/WorkConversionRecord.kt:20` requires platform android; `A:works/WorkImporter.kt:367` applies it; `A:works/RebuildOriginalDialog.kt:50` auto-rebuilds only when stale, otherwise asking. Foreign stamps cannot trigger local-version rebuilds. |
| D15 | Document best-effort redesign; lose no information | Present for A77's identified omission | Inventory remains at `docs/android-port/REDESIGNED-WITHOUT-MOCKUP.md:46`; `A:works/detail/WorkDetailSections.kt:216`/`:276` now restores the concrete lost no-tags information. This is not a fresh visual certification of every inventory screen. |
| D16 | Immersive Android reader | Present | `A:reader/ReaderScreen.kt:271` mounts the effect with chrome/overlay flags; `A:reader/ReaderSystemBars.kt:30` restores on overlays/inactive lifecycle and `:34` hides otherwise, with disposal restoration. |
| D17 | Android predictive Back | Present | `android/app/src/main/AndroidManifest.xml:20` still opts in with `enableOnBackInvokedCallback="true"`; this Android requirement should count as implemented, even though A77 called it not applicable to an iOS port. |
| D18 | Fix iPhone's largest-text layouts | Excluded: iPhone only | This is explicitly the iPhone repair, not a missing Android port; Android's own large-text byline branch remains at `A:comments/CommentThreadComponents.kt:562`. No claim of device rendering is made. |
| D19 | Loading placeholders on AO3 lists | Present | `A:ui/subject/SubjectSkeletons.kt:118` renders shape/count-specific rows and all 13 A77 integrations remain mounted; current crosswalk below. |
| D20 | Hide excludes mature works from local Search | Present | `A:search/SearchScreen.kt:147` supplies the live privacy/reveal predicate; `A:search/SearchViewModel.kt:94` removes hidden works before computing matches. Open Blur choices do not supersede Hide. |

### D19's complete integration crosswalk

| Surface | Current Android path:line and evidence |
|---|---|
| Series works | `A:app/SeriesWorksScreen.kt:223`: Loading renders four shared work skeletons. |
| Author works | `A:author/AuthorWorksScreen.kt:115`: Loading renders four work skeletons. |
| Fandom/tag works | `A:browse/FandomWorksScreen.kt:237`: Loading renders the default six work rows. |
| Fandom list | `A:browse/FandomListScreen.kt:186`: Loading selects ten fandom-shaped rows. |
| Browse categories | `A:browse/BrowseScreen.kt:152`: Loading selects eleven category panels. |
| Inbox | `A:account/AccountInboxPane.kt:278`: empty + loading renders three Inbox-shaped rows. |
| Account works lists | `A:account/AccountWorksListScreen.kt:408`: Loading renders shared work rows. |
| Subscriptions Works | `A:account/AccountWorksListScreen.kt:1284`: Loading renders work rows inside its existing list. |
| Author profile header | `A:author/AuthorProfileScreen.kt:679`: absent header + loading renders the profile skeleton at `:683`. |
| Author content tab | `A:author/AuthorProfileScreen.kt:890`: first page + no content + loading renders four work rows. |
| Existing Search | `A:search/SearchScreen.kt:398` invokes SearchSkeletonList, whose seven rows remain at `:801`. |
| Existing Comments | `A:comments/CommentsScreen.kt:577`: Loading wraps four CommentSkeletonRow instances at `:580`. |
| Existing Home subscription covers | `A:home/HomeScreen.kt:562` wraps six cover skeletons at `:570`; shared renderer is `A:ui/subject/SubjectWorkCoverCard.kt:302`. |

## Later owner-decision coverage

### Every question explicitly marked Answered

There are still exactly seven **Answered** entries; none was newly answered after A77. Each is rechecked rather than treated as a new requirement because its file changed later.

| Question and answer source | Current verdict | Implementation |
|---|---|---|
| Q11, answered 2026-10-04, `docs/android-port/OWNER-DECISIONS-ANDROID.md:204` | Present: native Android replacement | D03; `A:app/MainScaffold.kt:600`, `A:ui/subject/SubjectComponents.kt:881`. |
| Q19, answered 2026-10-20 A, `docs/android-port/OWNER-DECISIONS-ANDROID.md:355` | Present | D05/W09; `A:ui/subject/SubjectComponents.kt:851`, `A:library/QueueEditorSheet.kt:216`. |
| Q24, answered 2026-10-20 B + totals, `docs/android-port/OWNER-DECISIONS-ANDROID.md:473` | Present | D06; `A:author/AuthorProfileScreen.kt:110`, `:732`. |
| Q25, answered 2026-10-20 B, `docs/android-port/OWNER-DECISIONS-ANDROID.md:481` | Present against committed iOS, with shared exceptions recorded | D07/D08; `A:ui/components/SensitiveWorkRow.kt:444`, `A:account/AccountWorksListScreen.kt:169`. |
| Q27, answered 2026-10-20 B, `docs/android-port/OWNER-DECISIONS-ANDROID.md:500` | Present | D09; `A:library/ReadingStatistics.kt:187`, `:262`. |
| Q29, answered 2026-10-20 B, `docs/android-port/OWNER-DECISIONS-ANDROID.md:517` | Present | D10; `A:settings/SettingsPages.kt:119`, `A:reader/CustomizeThemeSheet.kt:220`. |
| Q30, answered 2026-10-20 B, `docs/android-port/OWNER-DECISIONS-ANDROID.md:525` | Present | D11; `A:reader/ReaderScreen.kt:548`, `A:reader/ReaderViewModel.kt:330`. |

Q20 is withdrawn/resolved, not marked Answered; its existing rule is retained separately as D20. Q32–34 are still open (`OWNER-DECISIONS-ANDROID.md:540`, `:554`, `:574`) and create no new approved requirement here.

### DECISIONS entries citing the owner on/after 2026-10-22

The inclusive boundary below also catches 10-22 entries following A77. Entries after 10-22 that merely refer to an open owner question are identified but do not turn that question into an answer.

| Entry / owner rule | Current verdict | Current source evidence |
|---|---|---|
| 10-22 immersive reader / predictive Back, `docs/android-port/DECISIONS.md:2542` | Present; repeated A77 D16/D17 | `A:reader/ReaderScreen.kt:271`, `A:reader/ReaderSystemBars.kt:30`, `android/app/src/main/AndroidManifest.xml:20`. The unlanded leave-confirmation assumption remains parked as Q32. |
| 10-22 loading placeholders, `docs/android-port/DECISIONS.md:2549` | Present; repeated D19 | All thirteen current call sites above, including `A:account/AccountInboxPane.kt:278` and `A:author/AuthorProfileScreen.kt:890`. |
| 10-22 A77/3go, `docs/android-port/DECISIONS.md:2584` | Present except retained Q9 | All eight fix traces above. This entry records repairs to prior decisions, not eight new owner approvals. |
| **N01 — 10-22 known challenge kind avoids a predictably refused form read**, citing owner 10-07, `docs/android-port/DECISIONS.md:2615` | Present | `A:account/AO3CollectionDetailScreen.kt:246`/`:248`/`:249`/`:250` passes the known kind to settings, prompts, sign-ups and assignments; repository `A:account/AO3CollectionDetailRepository.kt:295` reads only that kind. `:300` retains the documented gift-first fallback only when kind is unknown. |
| **N02 — 10-23 A82/3gx, no lost features/information**, `docs/android-port/DECISIONS.md:2656` and owner attribution `:2664` | Present in the enumerated retained features; concrete checks below | The extras were retained rather than deleted to copy a screenshot. The tag-rename and membership reversals also match iOS at `A:library/ReadingQueueRepository.kt:510` and `A:works/WorkDetailScreen.kt:964`. |
| 10-23 A88b/3ha references “owner decision 16”, `docs/android-port/DECISIONS.md:2683` | Parked Q16; no new owner answer | `A:account/AO3CollectionDetailRepository.kt:146` only treats a one-page sign-up count as a total; `A:account/AO3ChallengeSettingsEditScreen.kt:145` shows a known total without an extra read. The open assignment-walk choice is excluded from missing requirements. |
| 10-23 A88c/3hc/3hd references Q28, `docs/android-port/DECISIONS.md:2711` | Parked Q28; no new owner answer | Dates remain the platform's existing forms. This record explicitly leaves that difference unchanged, rather than requiring a new date-format port. |
| 10-23 D7/D8 accepted platform differences, `docs/android-port/DECISIONS.md:2738` and `:2771` | Recorded agent judgements, not fresh owner instructions | Their reversal clauses mention the owner, but the entries attribute their decisions to Claude-CLI. They do not authorize losing an owner-required field or behaviour. None removes the eight repaired paths checked above. |
| 10-24 Readium resize decision, `docs/android-port/DECISIONS.md:2803` | Excluded: iPhone Duo only | Expressly governs iOS T-449/Duo5c's resize layer; it does not request a new Android reader-position layer. |
| 10-24 Duo design direction, `docs/android-port/DECISIONS.md:2811` | Excluded: iPhone Duo only | System TabView, Duo splits, Book pose and six Duo rounds are the iOS redesign instructions. |

N02's retained-feature check (one umbrella owner rule, not additional count inflation):

| Retained feature or parity resolution | Current Android evidence |
|---|---|
| Local Browse work keeps progress and reader routing | `A:ui/components/SensitiveWorkRow.kt:718` substitutes the saved-work row; `:772` invokes RemoteWorkActionFrame, whose environment supplies reader routing at `A:ui/components/WorkRowActions.kt:71`. |
| Multi-work series preservation | `A:library/WorkMembershipDialogs.kt:176` accepts a work list; `:248` iterates distinct series, preserving from a complete preview at `:253` or the series repository at `:257`. |
| Typed and library suggestions, plus AO3 suggestions in Refine | `A:search/FilterTagPicker.kt:131` combines typed and library candidates; `A:search/SearchFilterSheet.kt:254`/`:261` supplies the autocomplete repository in the shared filter sheet. |
| Reading-order TOC fallback and nesting | `A:reader/ReaderTocBuilder.kt:35` falls back to reading order; `:55` recursively flattens children while retaining depth. |
| Multi-line collection description | `A:library/CollectionEditorSheet.kt:253` keeps an editable description with `minLines = 2` at `:258`. |
| Scrollable theme preview | `A:reader/CustomizeThemeSheet.kt:163` mounts the preview WebView; `:181` gives it bounded height while the form independently scrolls at `:217`. |
| Extra slider figures | `A:reader/CustomizeThemeSheet.kt:274` retains each slider's formatted numerical value. |
| Tag removal's scope | `A:library/QueueTags.kt:646` keeps scoped removal wording, distinguishing unused queue tags from tags on N works; explicit merge remains separate at `:624`. |
| Stop after refused challenge write | `A:account/AO3ChallengeSettingsEditState.kt:96` marks forbidden/authentication failures terminal; `:80` blocks subsequent submits. |
| Refuse colliding rename; explicit Merge remains separate | `A:library/ReadingQueueRepository.kt:510` compares other tags case-insensitively, `:521` refuses a collision; `A:library/QueueTags.kt:588` disables Save while conflicting and `:617` explains why. |
| Work Detail checked-queue toggle removes membership only | `A:works/WorkDetailScreen.kt:964` calls `removeWork`, removes that queue id and refreshes, without deleting the work. |

### LIVING-PROMPT §0 owner quotes dated 2026-10-22 or later

These later quotes concern the **work process**, not new Android UI/data features. Calling them absent in Kotlin would invent a product requirement. Their Android implications and evidence are listed individually; A101 does not pretend to perform the full workflow they require.

| Quote and location in local lane prompt | Android-relevant disposition and evidence |
|---|---|
| 10-23 18:19: latest Gemini; newest Sonnet only through agy, `L:124` | Model-routing instruction to the orchestrator; no Android feature to reproduce. No delegation or agy invocation was made by A101. |
| 10-23 18:22: temporary orchestrator hands back to Claude-Code, `L:113` | Handover instruction, not an app requirement. The exact owner-decision check handed to this task is this report; no claim that the external handover has occurred. |
| 10-23 18:33: Android Done precedes Duo effort, `L:102` (priority spelled out at `L:106`) | Parity-first sequencing; this report checks part 2 against source. It cannot certify builds, data round trips or the screenshot matrix, and authorizes no Duo code work. |
| 10-23 22:20: remain focused until parity; make it efficient, `L:86` | No new feature: fix mismatches, retain parked questions, close fixed/recorded minor differences. The dated acceptance records exist at `docs/android-port/DECISIONS.md:2738`, `:2771`, `:2794`; code-level owner behaviours are checked above. Existing accepted differences are not treated as new owner approvals. |
| 10-24 21:38: verify Android completion before Duo, `L:62` | Latest instruction supersedes the earlier “Android is done” assumption at `L:80`. **Part 2 source check supplied here; full Done remains for the orchestrator**: the five required evidence classes are enumerated at `L:67`, including a fresh Gradle gate forbidden in A101. Do not interpret this report as permission to bypass that verification. |
| 10-24 11:55: whole-app Apple-inspired ideas go to a separate file for owner approval, `L:83` | **Present as a proposal-only record:** `docs/android-port/FEATURE-IDEAS.md:1` and `:8` state the scope and approval condition; its three ideas are Proposed. They are not approved missing Android features. The Duo-only portion of the quote is excluded. |

The 10-24 10:50 and 11:50 quotes (`L:79`, `L:82`) direct the iPhone Duo redesign and delegate its design calls; they are skipped as requested. The 10-23 22:25 team-use quote is in the prompt's preamble (`L:13`), **outside §0**, and is likewise an orchestration instruction, not an Android behaviour. There are no additional 10-22 owner quotes inside §0. Older §0 product instructions are covered by A77/D03/D15 rather than recounted as post-A77 approvals.

## Verification and handoff

- Reconciled **all 82 A77 IDs**, all thirteen D19 integration rows and all seven explicitly answered questions. The eight independently triaged 3go fixes were checked through current producer/caller/consumer code, not accepted solely from `8c80b3b7`'s commit message.
- Read the later commit/decision history through `7b2f69f4`, especially editor, filter, card, reader-sheet and challenge changes. No new approved Android feature was discovered in the post-A77 §0 quotes; their parity-first and proposal-only instructions are preserved explicitly above.
- Checked report IDs, totals and cited file/line bounds locally. Android HEAD and branch remain the requested ones. The only file written by A101 is this report; the pre-existing brief remains untouched.
- **Next step:** the orchestrator can use this as part 2's source evidence. Keep Q9/Q12 parked, preserve the accepted Android replacements and finish the other Done checks before proceeding with Duo. No code repair or new owner question is proposed by this audit.
- **Not checked:** runtime behaviour, new screenshots, test execution, data round trips, sign-in, live AO3 or iOS's uncommitted Duo work. Source presence is the conclusion; observed visual correctness and full Android Done are not.
