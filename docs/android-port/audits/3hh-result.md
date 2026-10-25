# A102 / 3hh — destructive and error marks use iOS system red

Owner: Codex. Branch: `android/agent-codex-3he`. Base: `fd791da1` (3hg).
iOS reference: committed `HEAD` **`1e5d3d44`** at `/Users/cidy02/kudos-ios-polish`, read using `git show HEAD:<path>`; no uncommitted iOS changes used.
Android production references below are relative to `android/app/src/main/java/io/github/cidy02/kudos/`; test references are relative to `android/app/src/test/java/io/github/cidy02/kudos/`. iOS references are relative to `kudos-ao3-reader/` in the reference checkout.

## Implementation

`ui/subject/KudosTokens.kt:55`; `ui/subject/KudosTokens.kt:132`: `ReaderTheme.destructive` is the single source, exposed through `KudosTokens.destructive`. Light and Sepia use **#FF383C**; Dark and OLED use **#FF4245**. Neither accentInk nor scopePalette transforms it. `tokens.copy(accent = …)` in subject sheets preserves it.

`ui/theme/Theme.kt:43`; `ui/theme/Theme.kt:58`; `ui/theme/Theme.kt:73`; `ui/theme/Theme.kt:88`: all four Material schemes explicitly set `error` from the source and `onError = SubjectPalette.label(error)` (black for both reds). System mode already resolves through Light/Dark. The three collection-page local scheme overrides use the token and the same contrasting onError. Other local error overrides were checked: sign-up and collection form now use the token; Reader Note's explicit AO3-red override was removed.

All literal `fromHue(0.0, …)` production sites were replaced. On this base there are **32 matching lines**, plus the conditional shortcut-minus hue, rather than 33 literal calls. Whole Tag Set palettes use `fromColor(tokens.destructive, theme)`. A picked palette’s `accent`/`accentOnFill` remain hue-derived by design, so merely changing the palette constructor would leave text wrong: the Delete row and Reject spinner use `.tint`, and rejection chips explicitly use token text through the new optional `SubjectChip.contentColor`. Other chips retain their previous default text roles.

The audit additionally corrected inherited accents on queue menus, queue Delete/Remove confirmations, tag Remove/Merge, History Delete and subscription Unsubscribe chips; fixed red constants in Inbox and Recently Deleted; the shortcut minus, urgent draft-expiry badge, rejected collection approval badge, excluded-search summaries, failed-preferences banner and Clear All Filters menu. Reader Note Delete now inherits system red. Recovery’s Delete was already `destructive = true` on this base, but used the old hue-red; that lookup is replaced.

The iOS `.red` metadata marks also now use system red: `AO3StatusTint.forAppearance` resolves Explicit/F/F, `WorkStatRating.color` and `WorkWarningStatus.figureColor(theme)` resolve work-detail figures, and `SubjectWorkCoverCard.CategoryMark` uses the same red for Multi’s F/F quadrant. Other metadata colours are unchanged.

Comment action alerts contain both successful and failed messages. `comments/CommentsViewModel.kt` now carries `messageIsError` alongside the existing message and sets it explicitly on failures/uncertain verification, resetting it on clear and success. `comments/CommentsScreen.kt` uses that flag solely for text colour. Existing string messages, dispatch/session fences and writes are unchanged. Shared `ErrorStateCard` message text now uses Material error; its errorContainer and non-error states keep their existing fills/styles.

No schema, migration, backup keys/format/behavior, dependencies, signing or Apple project changes. No sign-in or AO3 traffic.

## Tests and verification

- Added **four** focused tests in `app/Parity3hhDestructiveTest.kt`: exact tokens + Material error/onError under KudosTheme in all four modes and under a purple subject theme; purple-subject Delete and Log Out confirmations; Reader Note Delete (catches the former `error = Ao3Red` override); actual recovery Delete text and bitmap pixels in Light/Sepia/Dark/OLED. The fixture uses a **teal app accent**, reads composition-set values only after idle, resets demo/cache/debug state, and creates only a local temporary recovery copy. It never invokes Delete or sends requests.
- The rendered recovery check composes the real `WritingRecoverySheet`/`EditorSheetAction`; only the window presenter is supplied in the activity, following `Brief3haContentTest`. It asserts exact TextLayoutResult colour and more than five native bitmap pixels within the Delete text bounds, within 0.012 per channel of the literal target. Restoring the old hue lookup yields #852525 / #7A3131 / #DB7272, so it fails both the style and pixel checks. This reversion sensitivity was verified **by reading**, not by running a mutated tree.
- Updated `app/Brief3hbContentTest.kt`, `giftRemovePaintsAFilledMinusCircleAndStillRemovesOnlyThatRecipient`: its sole old hue-0 colour assertion now expects `tokens.destructive`; its filled-minus and actual recipient-removal checks remain.
- Added `ui/components/AO3StatusTintTest.kt.redMetadataUsesTheSameSystemRedAsIosInEachTheme`, asserting Explicit, F/F and Archive Warnings in all four ReaderThemes. The existing teen-yellow check remains unchanged.
- Extended `comments/CommentsViewModelContextTest.kt`: definitive refusal/offline failure now asserts the error flag, clear resets it/message, and the delayed-success case asserts a non-error verdict. These use existing fake clients; no new network activity.
- **Passed:** `android/Scripts/check-invariants.sh`; `git diff --check`; direct Kotlin 2.3.21 compiler PSI syntax parsing of all **44** changed/new Kotlin files using cached jars and Android Studio’s JBR, without Gradle. PSI checks grammar only, not types, Compose rendering or tests.
- **Not run:** Gradle, builds, JVM/Compose tests, rendered test execution, emulator/device screenshots, adversarial review. No claim of visual verification or passing runtime tests. Claude-Code must run the focused tests above plus the full Android gate, inspect recovery/series minus, queue/tag Delete/Remove/Merge, Inbox, Recently Deleted, subscription/history chips and non-red-accent confirmation screenshots in all four themes; human screenshot approval remains outstanding.

## iOS → Android counterpart audit

This accounts for **158 grep matches** across the committed iOS tree (`role: .destructive` or a complete `.red` token), grouped below by source file with **every matching line listed**, including comments, metadata colours and iOS-only developer UI. “Existing error” means the call already reads Material error and follows the shared scheme change; it does not mean a runtime screenshot was checked. Neutral pre-confirm controls and non-destructive download/Saved-for-Later toggles were not converted just because their names include “remove”.

| iOS reference (all matching lines) | Mark / action checked | Android counterpart and outcome |
|---|---|---|
| `Features/Account/AO3CollectionFormView.swift:104,340,367,377,443` | Delete on AO3 / Delete Collection, reveal caution and validation feedback | `account/AO3CollectionFormScreen.kt:70` — changed to token; all red feedback/confirmation uses share it. |
| `Features/Account/AO3CollectionItemsView.swift:401,723,813` | Save errors, Rejected state, Remove from collection | `account/AO3CollectionItemsScreen.kt:143`; `account/AO3CollectionItemsScreen.kt:341` — changed error, removal and rejected-chip text/fill. |
| `Features/Account/AO3PreferencesView.swift:547` | Failed save banner | `account/AO3PreferencesScreen.kt:432` — changed failure text; success keeps existing ink. |
| `Features/Account/AccountComponents.swift:230,275` | Expired session mark; Log Out | `account/AccountScreen.kt:493`; `account/AccountScreen.kt:731` — existing Material error follows theme; confirmation uses shared helper. |
| `Features/Account/AccountInboxViews.swift:257,492,730,883,931,954` | Delete From Inbox: toolbar, item menus and confirmations | `account/AccountInboxPane.kt:571`; `account/AccountInboxPane.kt:1025`; `account/AccountInboxPane.kt:145` — changed bulk icon/text and fixed-red menu; confirm follows shared helper. Android’s deliberate read/unread swipe has no delete counterpart; no swipe behavior added. |
| `Features/Account/AccountShortcuts.swift:186` | Chosen shortcut’s remove minus | `account/AccountShortcutsEditor.kt:118` — changed conditional hue-0 red; Add remains green. |
| `Features/Account/PrivacyDataView.swift:125,141,155,168` | Clear history/positions/cache; Free files | `settings/PrivacyDataScreen.kt:226` — existing Material error rows; existing shared destructive confirmations now red. |
| `Features/Auth/AO3LoginView.swift:136,194` | Login failure messages and warning | `auth/AO3NativeLoginScreen.kt:197` — changed. Android native login is the counterpart; no sign-in performed. |
| `Features/Authors/AuthorProfileContentSections.swift:397` | Own-work Delete menu | `author/OwnWorksControls.kt:93` — changed hue-0 menu to token. |
| `Features/Authors/AuthorProfileView.swift:102,162` | Delete on AO3 and Unsubscribe confirmations | `author/AuthorProfileScreen.kt:450`; `author/AuthorProfileScreen.kt:613` — delete changed; unsubscribe already Material error. |
| `Features/Authors/OwnWorksBulkBar.swift:20,59` | Own-works bulk Delete and confirmation | `author/OwnWorksControls.kt:71`; `author/AuthorProfileScreen.kt:450` — changed. |
| `Features/Bookmarks/AO3AccountWorksList.swift:326` | Clear History menu/confirmation | `account/AccountWorksListScreen.kt:338`; `account/AccountWorksListScreen.kt:242` — existing Material error + shared confirmation. |
| `Features/Bookmarks/AO3HistoryWorksBrowser.swift:141` | Delete from history | `account/AccountWorksListScreen.kt:1111`; `account/AccountWorksListScreen.kt:949` — changed neutral chip icon/text; shared confirmation already follows theme. |
| `Features/Bookmarks/AO3NamedSubscriptionsList.swift:205` | Named author/series subscription Unsubscribe | `account/AccountWorksListScreen.kt:1536`; `account/AccountWorksListScreen.kt:1201` — changed shared neutral chip icon/text; shared confirmation follows theme. |
| `Features/Bookmarks/AO3SubscriptionsWorksBrowser.swift:367` | Work subscription Unsubscribe | `account/AccountWorksListScreen.kt:1536` — same shared chip/confirmation as named subscriptions, changed. |
| `Features/Challenges/ChallengeAssignmentsView.swift:617,620` | Action error icon/message | `account/AO3ChallengeAssignmentsScreen.kt:123` — changed; default-confirm red also changed. DEFAULTED’s orange 0.08 palette stays. |
| `Features/Challenges/ChallengeSettingsEditView.swift:153,700,703` | Save and reveal confirmation; failed save | `account/AO3ChallengeSettingsEditScreen.kt:85`; `account/AO3ChallengeSettingsEditScreen.kt:356` — changed; iOS explicitly marks Save and reveal destructive. |
| `Features/Challenges/ChallengeSignUpView.swift:150,486,491,597,600` | Withdraw confirmation; Withdraw action icon/text; failed save | `account/AO3ChallengeSignUpScreen.kt:92`; `account/AO3ChallengeSignUpScreen.kt:263` — changed shared red; SettingsActionRow already uses local Material error. |
| `Features/Challenges/CollectionMaintainersView.swift:112,367,388,393,416` | Leave/Step Down confirmation and errors | `account/AO3CollectionMaintainersScreen.kt:57` — changed shared red and local onError contrast. Last-owner “OK” remains non-destructive. |
| `Features/Challenges/CollectionModerationView.swift:124,140,148,157,629,634,663,668,692,740,743` | Reject/Decline/Reveal/Remove Anonymity confirms; reveal icons/text; error feedback | `account/AO3CollectionModerationScreen.kt:68` — changed shared red and local onError. Existing action rows use error. Approve/Reject staging pills retain iOS’s neutral/prominent pre-confirm styling; the destructive confirmations use red. |
| `Features/Challenges/PromptMemeView.swift:509,512` | Refusal warning icon/text | `account/AO3PromptMemeScreen.kt:118` — changed. |
| `Features/Challenges/TagSetView.swift:499,524,528,536,537,658,661` | Rejected badge; Reject pill/spinner/fill/stroke; feedback | `account/AO3TagSetScreen.kt:213`; `account/AO3TagSetScreen.kt:197`; `account/AO3TagSetScreen.kt:283` — changed all three whole-red palettes to fromColor, exact red text/spinner and Delete tag set row. |
| `Features/Comments/CommentThreadRow.swift:1509,1925` | Delete Comment menus | `comments/CommentThreadComponents.kt:893` — existing Material error text/icon, used by both thread and list. |
| `Features/Comments/CommentsView.swift:337,1508,1651` | Delete confirm; over-limit counter; failed-post feedback | `comments/CommentsScreen.kt:248`; `comments/CommentComposerSheet.kt:335`; `comments/CommentsScreen.kt:264` — confirm/counter already Material error; failed-message alert now token red via explicit presentation flag (no string guessing). |
| `Features/Home/HomeSectionListView.swift:281` | Delete local work | `home/HomeWorkMenu.kt:275` — existing destructive MenuItem and shared confirmation follow theme. |
| `Features/Library/Collections.swift:307,358,509,822,843` | Discard details; remove works; delete collection menu/confirm | `library/CollectionDetailScreen.kt:502`; `library/CollectionDetailScreen.kt:487`; `library/CollectionsScreen.kt:217` — existing error menus; palette-bearing shared confirms fixed. Android details autosave and have no Discard Changes confirm; no new action invented. |
| `Features/Library/LibraryWorkSwipeActions.swift:104,110` | Scoped Remove and work Delete swipes | `library/LibraryScreen.kt:1155`; `library/LibraryScreen.kt:1165` — existing Material error follows theme. Saved-for-Later toggle/Remove Download remain their non-destructive colours. |
| `Features/Library/QueueCardMenu.swift:36,48` | Delete queue menu and confirmation | `library/QueueChrome.kt:401`; `library/QueueChrome.kt:410` — changed. |
| `Features/Library/QueueTagManagerView.swift:123,214,428,445` | Remove tag menu/confirm; Edit tag Remove; Merge confirm | `library/QueueTags.kt:431`; `library/QueueTags.kt:531`; `library/QueueTags.kt:691`; `library/QueueTags.kt:666` — menu, Remove and Merge confirms changed; editor Remove already error. Queue Cancel/Save keep queue tint. |
| `Features/Library/ReadingQueueBrowser.swift:254,353,861` | Queue delete menu/confirm and work removal | `library/QueuePageScreen.kt:541`; `library/QueuePageScreen.kt:553`; `library/QueuePageScreen.kt:671` — changed; ScopedSelectionBar and work swipes already error. |
| `Features/Library/ReadingQueueOrganizer.swift:351,427,460` | Queue bulk Delete, card menu Delete and swipe Delete | `library/QueueOrganizerScreen.kt:338`; `library/QueueOrganizerScreen.kt:372`; `library/QueueChrome.kt:418` — changed. |
| `Features/Library/ReadingQueues.swift:301,325,355` | Single and bulk queue removal; Queue Storage scoped removal | `library/QueuePageScreen.kt:553`; `library/ScopedSelectionBar.kt:150`; `settings/QueueStorageScreen.kt:268` — dialogs and Queue Storage menu icon/text changed; selection/swipe already error. |
| `Features/Library/RecentlyDeletedView.swift:98,110,129,180,290,292,630,642` | Delete/Remove Copy single, all, bulk, menu and swipe; red outlined button | `library/RecentlyDeletedScreen.kt:631`; `library/RecentlyDeletedScreen.kt:919`; `library/RecentlyDeletedScreen.kt:939` — all nine fixed-red sites changed, including border and swipe. |
| `Features/Library/WorkCardActions.swift:430,435,448,593,626` | Scoped Remove and Delete local/remote menu actions; one explanatory comment | `library/LibraryScreen.kt:2226`; `ui/components/WorkRowActions.kt:117`; `library/ScopedWorkActions.kt:68` — existing shared error menus/swipes/confirmations follow theme; comment is not an extra UI site. |
| `Features/Reader/CustomizeThemeView.swift:102` | Reset Theme | `reader/CustomizeThemeSheet.kt:264` — existing destructive SettingsActionRow follows theme. |
| `Features/ReaderReadium/ReaderContentsSheet.swift:191` | Delete annotation/bookmark | `reader/ReaderContentsSheet.kt:269` — existing Material error; note-delete path fixed below. |
| `Features/ReaderReadium/ReaderNoteEditor.swift:56` | Delete Highlight | `reader/ReaderNoteEditor.kt:128` — removed the local error = Ao3Red override; now inherits system red. |
| `Features/ReaderReadium/ReaderSpeechAuditionHarness.swift:104` | Developer audition Stop | No Android audition harness/counterpart (searched reader and speech settings); developer-only iOS UI, no action added. |
| `Features/ReaderReadium/ReaderSpeechDeveloperSettingsView.swift:108` | Developer Reset to shipped defaults | No matching Android developer speech-settings reset surface; iOS-only tooling, no action added. |
| `Features/ReaderReadium/ReaderSpeechSettingsSection.swift:294,388` | Voice pack install errors | `settings/ListeningSpeechSettings.kt:166` — existing Material error follows theme. |
| `Features/Search/SaveSearchSheet.swift:170,178,186` | Excluded-filter negative text/fill/stroke | `search/SaveSearchSheet.kt:189` — changed fixed red to theme token at the existing 0.15/0.35 alpha; included green unchanged. |
| `Features/WorkDetail/AO3WorkActionsModel.swift:221` | Bookmark error label/icon | `works/detail/WorkDetailForms.kt:105`; `works/detail/WorkDetailForms.kt:163` — changed error text/icon. |
| `Features/WorkDetail/WorkDetailView.swift:383` | Action/refresh error text | `works/WorkDetailScreen.kt:1636`; `ui/components/KudosUi.kt:294` — ErrorStateCard’s error message now uses Material error, retaining its container and actions. |
| `Features/Writing/SeriesEditView.swift:539,562` | Remove from series confirm and minus circle | `writing/WritingSeriesScreen.kt:167`; `writing/WritingSeriesScreen.kt:247` — changed both, plus error text. |
| `Features/Writing/WorkEditView.swift:237,789` | Delete on AO3 confirm; Delete draft row | `writing/WritingWorkFormScreen.kt:219`; `writing/WritingWorkFormScreen.kt:399` — existing Material error follows theme. |
| `Features/Writing/WritingDraftsView.swift:264` | Urgent expiry warning badge (≤3 days) | `account/WritingDraftsScreen.kt:294` — changed red tone only; orange/mint remain. |
| `Features/Writing/WritingTextEditor.swift:158,219,444` | Delete chapter menu/confirm; Delete this local copy | `writing/WritingTextEditorScreen.kt:143`; `writing/WritingTextEditorScreen.kt:220`; `writing/WritingTextEditorScreen.kt:320` — changed. Recovery was already flagged destructive; its colour was the old hue red, not app accent, in this base. |
| `Settings/BackupImportSheet.swift:98` | Replace Library… | `backup/BackupScreen.kt:561`; `backup/BackupScreen.kt:533` — both existing destructive SettingsActionRows follow theme; no backup logic/keys changed. |
| `Settings/PairingSheet.swift:201,254,374` | Revoke row and confirmation; pairing validation feedback | `backup/PairingSheet.kt:269`; `backup/PairingSheet.kt:526`; `backup/PairingSheet.kt:436` — existing error rows/feedback follow theme; no revocation behavior changed. |
| `Settings/SettingsAccountPages.swift:147` | Log Out | `ui/components/DeleteConfirmation.kt:71`; `account/AccountScreen.kt:731` — existing row follows theme; shared confirm fixed/tested. |
| `Settings/SettingsSyncFolderPage.swift:177` | Disconnect | `settings/SettingsPages2.kt:725` — existing destructive SettingsActionRow follows theme. |
| `Settings/SettingsView.swift:416,419,424,491` | Undo-copy failure/warning and armed Replace | `backup/BackupScreen.kt:258`; `backup/BackupScreen.kt:533` — existing Material error status + destructive action follow theme. Android intentionally has no unsafe override after a second failed safety copy; no backup behavior added. |
| `UIComponents/DeleteConfirmation.swift:22,34,67,80,108,115` | Shared Delete, typed/bulk/scoped confirms, plus documentation comment | `ui/components/DeleteConfirmation.kt:26` — changed confirm to tokens.destructive even with palette. Cancel retains previous subject colour. |
| `UIComponents/ScopedRemovalBulkActionBar.swift:135,181` | Scoped Remove bar and confirm | `library/ScopedSelectionBar.kt:150`; `library/ScopedSelectionBar.kt:216` — existing Material error follows theme. |
| `UIComponents/SemanticThemeColors.swift:5` | Documentation mentions .red | Comment only, no rendered counterpart to recolour. |
| `UIComponents/SubjectForm.swift:218,251` | isDestructive label, plus documentation comment | `settings/SettingsChrome.kt:297` — existing destructive row text/icon follows theme; Tag Set special row changed explicitly. |
| `UIComponents/WorkBulkActionBar.swift:45,136` | Bulk Delete entry and confirmation | `ui/components/WorkBulkActionBar.kt:186`; `ui/components/WorkBulkActionBar.kt:201` — existing error entry and shared confirm follow theme. |
| `UIComponents/WorkCardListControls.swift:99` | Clear All Filters long-press menu | `ui/subject/SubjectComponents.kt:1040` — changed neutral menu text to token. |
| `UIComponents/WorkStatLabel.swift:640,900,915,1027,1060` | F/F category, Explicit rating, Archive Warnings metadata | `ui/components/WorkStats.kt:158`; `works/detail/WorkDetailIdentity.kt:47`; `works/detail/WorkDetailIdentity.kt:82` — changed red metadata too because iOS uses system .red here: Explicit and F/F use forAppearance; warning figures take ReaderTheme; the Multi category’s F/F quadrant uses the token. These remain metadata roles, not Material errors. |

### Literal hue-0 replacement inventory

Line numbers in this table identify the **base `fd791da1`** lookup sites (so the replacement list remains reproducible after imports shift). Each now reads the token directly, or uses it as a picked Tag Set palette. No literal hue-0 calls remain in production; the conditional shortcut minus and dynamic red draft/approval states are covered separately above.

| Android base file | Original lines | Meaning |
|---|---|---|
| `account/AO3ChallengeAssignmentsScreen.kt` | 98, 123, 125 | Default confirmation and action-error icon/text |
| `account/AO3ChallengeSettingsEditScreen.kt` | 85, 359 | Save and reveal; failed save |
| `account/AO3ChallengeSignUpScreen.kt` | 92, 266 | Withdraw and feedback |
| `account/AO3CollectionFormScreen.kt` | 70 | Delete and validation/reveal feedback |
| `account/AO3CollectionItemsScreen.kt` | 143, 232, 308 | Local Material error, failed save and remove action |
| `account/AO3CollectionMaintainersScreen.kt` | 57 | Leave/Step Down and errors |
| `account/AO3CollectionModerationScreen.kt` | 68 | Reject/Decline/Reveal/Unanon confirmations, errors and reveal actions |
| `account/AO3PromptMemeScreen.kt` | 119 | Refusal |
| `account/AO3TagSetScreen.kt` | 197, 223, 233, 286 | Delete tag set, Reject, Rejected, feedback |
| `auth/AO3NativeLoginScreen.kt` | 197 | Login error |
| `author/AuthorProfileScreen.kt` | 450 | Delete on AO3 confirmation |
| `author/OwnWorksControls.kt` | 71, 93 | Bulk Delete and menu Delete |
| `settings/SettingsChrome.kt` | 219 | Field validation text |
| `works/detail/WorkDetailForms.kt` | 108, 163 | Form error text and warning icon |
| `writing/WritingAssociationPickers.kt` | 168 | Gift recipient remove minus |
| `writing/WritingSeriesScreen.kt` | 167, 235, 247 | Series remove minus, error text, Remove confirmation |
| `writing/WritingTextEditorScreen.kt` | 144, 221, 324 | Delete chapter, Delete on AO3, recovery Delete |

### Material error audit

The base contains **50 exact `colorScheme.error` uses**, plus `errorContainer` in StateCard (a prefix search counts 51). All exact uses were read in their UI context: session expiry, delete/remove/logout/unsubscribe/block confirmations or actions, validation/counter limits, request/install/import/pairing failures. **None encodes a subject accent, genre/category, positive state or unrelated meaning.** The baseline sites below inherit the new error; the palette-sensitive shared confirm was explicitly corrected. `onError` is used by saved-search and Queue Storage delete swipes and now contrasts with their fill. The general `SwipeActionRow.ActionButtons` draws the supplied action fill with fixed white icon/text; its destructive fills follow the new error value and its existing labels are unchanged.

| Android base file | Exact error-use lines | Meaning checked |
|---|---|---|
| `account/AccountScreen.kt` | 493, 633, 731, 737 | Expired session, logout rows/icons |
| `account/AccountWorksListScreen.kt` | 338, 341 | Clear History text/icon |
| `author/AuthorProfileScreen.kt` | 613, 634 | Unsubscribe and Block/Mute confirm (undo uses normal colour) |
| `backup/BackupScreen.kt` | 258 | Import/export failure status |
| `backup/PairingSheet.kt` | 436 | Key validation failure |
| `comments/CommentComposerSheet.kt` | 335 | Over-limit character count |
| `comments/CommentThreadComponents.kt` | 893, 895 | Delete Comment text/icon |
| `comments/CommentsScreen.kt` | 247 | Delete Comment confirmation |
| `home/HomeWorkMenu.kt` | 275 | Destructive Delete menu item |
| `library/CollectionDetailScreen.kt` | 487, 489, 918 | Delete Collection menu/icon; row destructive mark |
| `library/CollectionsScreen.kt` | 217, 219 | Delete Collection menu/icon |
| `library/LibraryScreen.kt` | 1155, 1160, 1165, 2227, 2238, 2372, 2374, 2573, 2574 | Scoped Remove, Delete, menus and bulk Delete icons/text |
| `library/QueuePageScreen.kt` | 737 | Remove work swipe |
| `library/QueueTags.kt` | 667 | Edit tag Remove action |
| `library/ScopedSelectionBar.kt` | 150, 154, 216 | Scoped Remove actions/confirmation |
| `reader/ReaderContentsSheet.kt` | 269 | Delete mark |
| `search/SearchScreen.kt` | 843 | Saved-search Delete swipe fill |
| `settings/ListeningSpeechSettings.kt` | 166 | Voice pack failure |
| `settings/PrivacyDataScreen.kt` | 226 | Destructive storage/privacy actions |
| `settings/QueueStorageScreen.kt` | 200 | Remove queue membership swipe |
| `settings/SettingsChrome.kt` | 297 | Shared destructive settings action text/icon |
| `settings/SettingsPages2.kt` | 625 | Font import failure status |
| `ui/components/DeleteConfirmation.kt` | 55 | Shared destructive confirm (subject-colour override removed) |
| `ui/components/WorkBulkActionBar.kt` | 186, 364 | Remove from Library and collection-membership error |
| `ui/components/WorkRowActions.kt` | 117, 206 | Local and resolved remote work Delete swipes |
| `web/AO3WebViewFallbackScreen.kt` | 218 | Web navigation error |
| `writing/WritingWorkFormScreen.kt` | 222, 399, 408 | Delete work/draft confirmation and action rows |

The work metadata reds (`AO3StatusTint`, `WorkStatRating`, `WorkWarningStatus`, including the Multi category’s F/F quadrant) now resolve to the same system red because the iOS references explicitly use `.red`. They do not consume Material error or acquire destructive semantics. The colour-picker rainbow’s `Color.Red` is a spectrum stop and remains unchanged. No non-destructive subject hue was changed, including assignment DEFAULTED at hue 0.08.

## Handoff

**Uncommitted and unpushed:** explicit-path staging of the 46 task files failed with `Unable to create '/Users/cidy02/AO3_App_OpenSource/.git/worktrees/kudos-agent-codex/index.lock': Operation not permitted`. The linked worktree’s shared index is outside the sandbox writable roots; approval is unavailable. No index changes were made. The pre-existing untracked `docs/android-port/briefs/3hh-destructive-red.md` remains untouched and was excluded from staging.

Runtime gate and human screenshot approval are pending. No other-branch port is required; this is Android-only. See TASKS.md for staging/commit status. Next: Claude-Code runs focused/full gates and adversarial review, checks the theme screenshots, then commits explicit task paths with `Co-Authored-By: Codex <noreply@openai.com>` and integrates the Android lane. No open product question.
