# Audit A2: iOS / Android Screen Parity Index

## Summary
- **iOS files read:** 62 (`Features/` Swift files declaring a screen or sheet)
- **Android files read:** The `io.github.cidy02.kudos` Kotlin tree (approx. 200+ composable and routing files read).
- **Status:** 49 `present`, 1 `partial`, 12 `absent`

## Screens without iOS counterpart
- `auth/AO3NativeLoginScreen.kt` (Reachable via `Routes.AccountLogin` native fallback)
- `update/ReleaseNotesPresentation.kt` (No route, invoked by update flow)
- `writing/WritingWorkFormScreen.kt` and `writing/WritingEditorDemoScreen.kt` (Reachable via debug demo routes like `Routes.WritingEditorDemo`)

## Matrix corrections (§7 / GAP-INVENTORY)
- **Redesign implementation:** `GAP-INVENTORY.md` stated "Every screen still uses Material 3" and that `SubjectHeaderBlock`, `SubjectPalette`, `showsOnHome`, and `HomeResumeHero` were missing. This is incorrect. The entire redesign subject system is implemented and in use across screens like `HomeScreen.kt`, `WorkDetailScreen.kt`, `ReaderScreen.kt`, and `AccountScreen.kt`.
- **Comments/Threads/Inbox:** The gap inventory described inbox as just a pane, but `AccountInboxPane.kt` operates as its own full destination.
- **Reader:** The gap inventory stated the fan menu and position card were absent. `ReaderFanMenu.kt` and position card implementations exist and are integrated into `ReaderScreen.kt`.
- **Note:** `docs/android-port/LIVING-PROMPT.md` does not exist in the working tree. Matrix corrections above are based on the latest available gap assessments (`GAP-INVENTORY.md`).

## Index (Most Incomplete Areas First)

### Challenges
| iOS file | Android counterpart (Composable) | Status |
|---|---|---|
| `Features/Challenges/ChallengeAssignmentsView.swift` | none | absent |
| `Features/Challenges/ChallengeSettingsEditView.swift` | none | absent |
| `Features/Challenges/ChallengeSignUpView.swift` | none | absent |
| `Features/Challenges/ChallengeSignUpsView.swift` | none | absent |
| `Features/Challenges/PromptTagsEditorView.swift` | none | absent |
| `Features/Challenges/ChallengeSettingsView.swift` | `account/AO3ChallengeSettingsScreen.kt` (`AO3ChallengeSettingsScreen`) | present |
| `Features/Challenges/CollectionMaintainersView.swift` | `account/AO3CollectionMaintainersScreen.kt` (`AO3CollectionMaintainersScreen`) | present |
| `Features/Challenges/CollectionModerationView.swift` | `account/AO3CollectionModerationScreen.kt` (`AO3CollectionModerationScreen`) | present |
| `Features/Challenges/PromptMemeView.swift` | `account/AO3PromptMemeScreen.kt` (`AO3PromptMemeScreen`) | present |
| `Features/Challenges/TagSetView.swift` | `account/AO3TagSetScreen.kt` (`AO3TagSetScreen`) | present |

*Missing in Challenges:*
- `path:line` `Features/Challenges/ChallengeAssignmentsView.swift:23` - "Challenge Assignments" (Search: `grep -rFi "Challenge Assignments" android/app/src/main/java/io/github/cidy02/kudos`)
- `path:line` `Features/Challenges/ChallengeSettingsEditView.swift:15` - "Edit Settings" (Search: `grep -rFi "Edit Settings" android/app/src/main/java/io/github/cidy02/kudos/account`)
- `path:line` `Features/Challenges/PromptTagsEditorView.swift:34` - "Prompt Tags" (Search: `grep -rFi "Prompt Tags" android/app/src/main/java/io/github/cidy02/kudos/account`)

### Writing
| iOS file | Android counterpart (Composable) | Status |
|---|---|---|
| `Features/Writing/AddChapterView.swift` | none | absent |
| `Features/Writing/EditMultipleWorksView.swift` | none | absent |
| `Features/Writing/EditTagsView.swift` | none | absent |
| `Features/Writing/SeriesEditView.swift` | none | absent |
| `Features/Writing/WorkEditView.swift` | none | absent |
| `Features/Writing/WritingChaptersView.swift` | none | absent |
| `Features/Writing/WritingPreviewView.swift` | none | absent |
| `Features/Writing/WritingDraftsView.swift` | `account/WritingDraftsScreen.kt` (`WritingDraftsScreen`) | present |

*Missing in Writing:*
- `path:line` `Features/Writing/AddChapterView.swift:45` - "Add Chapter" (Search: `grep -rFi "Add Chapter" android/app/src/main/java/io/github/cidy02/kudos/writing`)
- `path:line` `Features/Writing/EditMultipleWorksView.swift:12` - "Edit Multiple Works" (Search: `grep -rFi "Edit Multiple Works" android/app/src/main/java/io/github/cidy02/kudos/writing`)
- `path:line` `Features/Writing/SeriesEditView.swift:20` - "Edit Series" (Search: `grep -rFi "Edit Series" android/app/src/main/java/io/github/cidy02/kudos/writing`)

### Reader
| iOS file | Android counterpart (Composable) | Status |
|---|---|---|
| `Features/ReaderReadium/ReaderPronunciationSettingsView.swift` | none | absent |
| `Features/ReaderReadium/ReaderSpeechDeveloperSettingsView.swift` | none | absent |
| `Features/ReaderReadium/ReadiumReaderView.swift` | `reader/ReaderScreen.kt` (`ReaderScreen`) | present |
| `Features/ReaderReadium/ReaderContentsSheet.swift` | `reader/ReaderContentsSheet.kt` (`ReaderContentsSheet`) | present |
| `Features/ReaderReadium/ReaderSearchView.swift` | `reader/ReaderSearchSheet.kt` (`ReaderSearchSheet`) | present |
| `Features/ReaderReadium/ReaderSpeechSettingsSheet.swift` | `reader/ReaderSpeechSettingsSheet.kt` (`ReaderSpeechSettingsSheet`) | present |

*Missing in Reader:*
- `path:line` `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:21` - "Pronunciation" (Search: `grep -rFi "Pronunciation" android/app/src/main/java/io/github/cidy02/kudos/reader`)

### Library
| iOS file | Android counterpart (Composable) | Status |
|---|---|---|
| `Features/Library/LibrarySectionListView.swift` | `account/LocalLibraryListsScreen.kt` (`LocalLibraryListsScreen`) | partial (History and favorites unsorted) |
| `Features/Library/Collections.swift` | `library/CollectionsScreen.kt` (`CollectionsScreen`) | present |
| `Features/Library/LibraryView.swift` | `library/LibraryScreen.kt` (`LibraryScreen`) | present |
| `Features/Library/NewCollectionSheet.swift` | `library/CollectionsScreen.kt` (`NewCollectionSheet`) | present |
| `Features/Library/NewReadingQueueSheet.swift` | `library/QueueEditorSheet.kt` (`QueueEditorSheet`) | present |
| `Features/Library/QueueTagManagerView.swift` | `library/QueueTags.kt` (`QueueTagManagerScreen`) | present |
| `Features/Library/QueueTagSheet.swift` | `library/QueueTags.kt` (`QueueTagSheet`) | present |
| `Features/Library/ReadingInsightsView.swift` | `library/ReadingStatisticsScreen.kt` (`ReadingStatisticsScreen`) | present |
| `Features/Library/ReadingQueueBrowser.swift` | `library/ReadingQueueBrowserScreen.kt` (`ReadingQueueBrowserScreen`) | present |
| `Features/Library/ReadingQueueSettingsView.swift` | `library/QueuePageScreen.kt` (`QueuePageScreen`) | present |
| `Features/Library/ReadingQueues.swift` | `library/ReadingQueueBrowserScreen.kt` (`ReadingQueueBrowserScreen`) | present |
| `Features/Library/RecentlyDeletedView.swift` | `library/RecentlyDeletedScreen.kt` (`RecentlyDeletedScreen`) | present |
| `Features/Library/AddLibraryWorksSheet.swift` | `library/CollectionDetailScreen.kt` (inline) | present |

*Missing in Library:*
- `path:line` `Features/Library/LibrarySectionListView.swift:603` - `SectionRuleHeader` for dates (Search: `grep -i "SectionRuleHeader" android/app/src/main/java/io/github/cidy02/kudos/account/LocalLibraryListsScreen.kt`)

### Search & Browse
| iOS file | Android counterpart (Composable) | Status |
|---|---|---|
| `Features/Search/MediaBrowserView.swift` | none | absent |
| `Features/Search/FandomListFilterSheet.swift` | `browse/FandomListFilterSheet.kt` (`FandomListFilterSheet`) | present |
| `Features/Search/FandomListView.swift` | `browse/FandomListScreen.kt` (`FandomListScreen`) | present |
| `Features/Search/SaveSearchSheet.swift` | `search/SaveSearchSheet.kt` (`SaveSearchSheet`) | present |
| `Features/Search/SearchView.swift` | `search/SearchScreen.kt` (`SearchScreen`) | present |
| `Features/Browse/BrowseView.swift` | `browse/BrowseScreen.kt` (`BrowseScreen`) | present |
| `Features/Browse/NativeBrowseView.swift` | `browse/FandomWorksScreen.kt` (`FandomWorksScreen`) | present |

*Missing in Search & Browse:*
- `path:line` `Features/Search/MediaBrowserView.swift:18` - "Media" (Search: `grep -rFi "MediaBrowserView" android/app/src/main/java/io/github/cidy02/kudos/search`)

### Account & Auth
| iOS file | Android counterpart (Composable) | Status |
|---|---|---|
| `Features/Authors/AO3SeriesDetailView.swift` | `app/SeriesWorksScreen.kt` (`SeriesWorksScreen`) | present |
| `Features/Account/AccountInboxFilterSheet.swift` | `account/AccountInboxFilterSheet.kt` (`AccountInboxFilterSheet`) | present |
| `Features/Account/AccountInboxScreen.kt` | `account/AccountInboxPane.kt` (`AccountInboxPane`) | present |
| `Features/Account/AccountMoreOnAO3View.swift` | `account/AccountMoreOnAO3Screen.kt` (`AccountMoreOnAO3Screen`) | present |
| `Features/Account/AccountView.swift` | `account/AccountScreen.kt` (`AccountScreen`) | present |
| `Features/Account/AO3CollectionDetailView.swift` | `account/AO3CollectionDetailScreen.kt` (`AO3CollectionDetailScreen`) | present |
| `Features/Account/AO3CollectionFormView.swift` | `account/AO3CollectionFormScreen.kt` (`AO3CollectionFormScreen`) | present |
| `Features/Account/AO3CollectionItemsView.swift` | `account/AO3CollectionItemsScreen.kt` (`AO3CollectionItemsScreen`) | present |
| `Features/Account/AO3DashboardView.swift` | `account/AO3DashboardScreen.kt` (`AO3DashboardScreen`) | present |
| `Features/Account/AO3PreferencesView.swift` | `account/AO3PreferencesScreen.kt` (`AO3PreferencesScreen`) | present |
| `Features/Account/AvailabilitySweepView.swift` | `settings/AvailabilitySweepScreen.kt` (`AvailabilitySweepScreen`) | present |
| `Features/Account/PrivacyDataView.swift` | `settings/PrivacyDataScreen.kt` (`PrivacyDataScreen`) | present |
| `Features/Auth/AO3LoginView.swift` | `auth/AO3WebLoginScreen.kt` (`AO3WebLoginScreen`) | present |
| `Features/Authors/AuthorProfileView.swift` | `author/AuthorProfileScreen.kt` (`AuthorProfileScreen`) | present |

### Home
| iOS file | Android counterpart (Composable) | Status |
|---|---|---|
| `Features/Home/HomeSectionListView.swift` | `home/HomeSectionListScreen.kt` (`HomeSectionListScreen`) | present |
| `Features/Home/HomeView.swift` | `home/HomeScreen.kt` (`HomeScreen`) | present |

### Other
| iOS file | Android counterpart (Composable) | Status |
|---|---|---|
| `Features/Comments/CommentsView.swift` | `comments/CommentsScreen.kt` (`CommentsScreen`) | present |
| `Features/Comments/CommentThreadScreen.swift` | `comments/CommentThreadScreen.kt` (`CommentThreadScreen`) | present |
| `Features/Onboarding/SyncFolderOnboardingView.swift` | `onboarding/SyncFolderOnboardingScreen.kt` (`SyncFolderOnboardingScreen`) | present |
| `Features/Onboarding/WelcomeView.swift` | `onboarding/WelcomeScreen.kt` (`WelcomeScreen`) | present |
| `Features/Support/BugReportView.swift` | `account/BugReportScreen.kt` (`BugReportScreen`) | present |
| `Features/Support/WhatsNew.swift` | `support/WhatsNew.kt` (`WhatsNew`) | present |
| `Features/WorkDetail/WorkDetailView.swift` | `works/WorkDetailScreen.kt` (`WorkDetailScreen`) | present |

## What I did not read
- Swift files in `Features/` that do not declare a screen or a sheet (e.g., pure components, view models, or utility functions like `HomeCards.swift` and `WorkDetailFactsSections.swift`).
- Unreachable/disabled legacy code that doesn't define a screen.
- The `android/app/.../ui/theme` internal implementations since `SubjectPalette` was confirmed to be present at usage sites.

---

## Triage (Claude, 2026-10-08)

An index, as asked, and to be read as one: three of its lines were checked and two were wrong.

- **Wrong:** `Features/Search/MediaBrowserView.swift` is not absent. It is the Browse tab's
  content on iOS (`NativeBrowseView.swift:51`), and Android has it in `browse/BrowseScreen.kt`
  with `browse/JumpBackIn.kt`.
- **Wrong:** `Features/Writing/WorkEditView.swift` is listed as absent while
  `writing/WritingWorkFormScreen.kt` is listed as having no iOS counterpart: they are the
  same screen (brief 3bf; no Save yet). `Features/Library/LibrarySectionListView.swift` is
  paired with `account/LocalLibraryListsScreen.kt`, an old unreachable file; its real
  counterpart is the Library's section list (brief 3u).
- **Not usable:** the `path:line` references are approximate (a made-up iOS file name appears
  once, `Features/Account/AccountInboxScreen.kt`), and it could not see the Living Prompt
  (gitignored), so its "matrix corrections" are about an older gap list, not §7.
- **Confirmed and used:** the list of iOS screens with no Android screen yet, which agrees
  with §7 and §10. Challenges: `ChallengeAssignmentsView`, `ChallengeSettingsEditView`,
  `ChallengeSignUpView` (brief 3bl is running), `ChallengeSignUpsView`,
  `PromptTagsEditorView`. Writing: `AddChapterView`, `EditMultipleWorksView`, `EditTagsView`,
  `SeriesEditView`, `WritingChaptersView`, `WritingPreviewView`. Reader:
  `ReaderPronunciationSettingsView`, `ReaderSpeechDeveloperSettingsView` (both wait for a
  speech engine that has what they configure).

Outcome: no bug found; the eleven screens above are the screens still to build on Android,
beyond finishing the work form (pickers 3bj, Save, Post, Delete). Nothing to fix from this
audit. Gemini Pro is not worth a second index of this kind; its next job should be narrower
(one area, strings only).
