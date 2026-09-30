AGY_USAGE {"status": "SUCCESS", "error": "", "usage": {"input": 204072, "output": 13023, "thinking": 7145, "cache_read": 654438, "total": 217095}, "conversation_id": "88ac2df8-5d3e-4c20-befd-9faad648efcc"}
- Extracted 86 distinct screen/sheet labels from the `docs/design/Final_Redesign_Spec.dc.html` spec HTML by scanning `<div class="dv-opt">` and `data-screen-label` attributes.
- Parsed actual app navigation routes by grepping for `TabView`, `navigationDestination`, `.sheet`, `.fullScreenCover`, and `.inspector` across `kudos-ao3-reader/`.
- Cross-referenced implemented Swift views against the redesign spec to identify gaps and missing alignments.

### Mapped Screens and Sheets

| Screen | Swift type (file) | How it is reached | Spec artboard id(s) + label(s) | Reachable offline? |
|--------|-------------------|-------------------|---------------------------------|--------------------|
| Home Tab | `HomeSectionListView` (`Features/Home/HomeSectionListView.swift`) | Tab selection | 1b \| Home — matched to Library | yes |
| Library Tab | `LibrarySectionListView` (`Features/Library/LibrarySectionListView.swift`) | Tab selection | 1c \| Library — all sections | yes |
| Browse Tab | `NativeBrowseView` (`Features/Browse/NativeBrowseView.swift`) | Tab selection | 1al \| Browse — entries, sibling families | no |
| Account Tab | `AccountView` (`Features/Account/AccountView.swift`) | Tab selection | 1m \| Account — hub | yes |
| AO3 Login | `AO3LoginView` (`Features/Account/AccountView.swift`) | `.sheet` | 1n \| Signed out — preview of the signed-in tab | no |
| Settings | `SettingsView` (`Settings/SettingsView.swift`) | `.navigationDestination` | 1ab \| Settings | yes |
| Privacy Settings | `SettingsPrivacyPage` (`Settings/SettingsAccountPages.swift`) | `NavigationLink` | 1ac \| Privacy and local data | yes |
| AO3 Preferences | `AO3PreferencesView` (`Features/Account/AO3PreferencesView.swift`) | `NavigationLink` | 1z \| AO3 Preferences | no |
| Inbox | `AccountInboxScreen` (`Features/Account/AccountInboxScreen.swift`) | `.navigationDestination` | 1l \| Inbox — settled shell | no |
| Work Detail | `WorkDetailView` (`Features/Account/AccountView.swift`) | `.navigationDestination` | 1u \| Works | yes |
| Queue Organizer | `ReadingQueueOrganizer` (`Features/Library/ReadingQueueOrganizer.swift`) | `NavigationLink` | 1i \| Queues — organizer | yes |
| New Queue | `ReadingQueueSwitcher` (`Features/Library/ReadingQueueSwitcher.swift`) | `.sheet` | 1j \| Queues — new queue | yes |
| Local Collection Form | `NewCollectionSheet` (`Features/Library/NewCollectionSheet.swift`) | `.sheet` | 1bk \| Local collection — new/edit | yes |
| AO3 Collection Form | `AO3CollectionsList` (`Features/Account/AO3CollectionsList.swift`) | `.navigationDestination` | 1bl \| AO3 collection — new/edit | no |
| Library Filter Panel | `LibraryFilterPanel` (`Features/Library/LibraryFilterPanel.swift`) | `.inspector` | 1an \| Browse — filter sheet | yes |
| Work Edit | `WorkEditView` (`Features/Writing/WorkEditView.swift`) | `.navigationDestination` | 1bo \| Work Edit | yes |
| Edit Tags | `EditTagsView` (`Features/Writing/EditTagsView.swift`) | `.navigationDestination` | 1bp \| Edit Tags | yes |
| Add Chapter | `AddChapterView` (`Features/Writing/AddChapterView.swift`) | `.navigationDestination` | 1bq \| Add Chapter | yes |
| Text Editor | `WritingTextEditor` (`Features/Writing/WritingTextEditor.swift`) | `.sheet` | 1bv \| Chapter text editor | yes |

### Unmatched Screens (Gaps)

| Item | Unmatched Reason | Note |
|------|------------------|------|
| **Spec: 1bz, 1ca-1cc** | No Swift Screen | Challenges, Assignments, Prompt Meme |
| **Spec: 1cd-1cg** | No Swift Screen | Collection moderation, rejection, and advanced settings |
| **Spec: 1ch** | No Swift Screen | Tag set |
| **Spec: 1bw, 1bx** | No Swift Screen | Collections and gifts, Moderated items |
| **Spec: 1bn** | No Swift Screen | Works — select mode, Edit Multiple Works |
| **Spec: 1br** | No Swift Screen | Series Edit / Reorder |
| **Spec: 1bs** | No Swift Screen | Draft editor / post / delete confirmation |
| **Spec: 1bg, 1bh** | No Swift Screen | Queue — select mode, tag manager |
| **Spec: 1bi, 1bj** | No Swift Screen | Reading Insights, Recently Deleted |
| **Spec: 1ba, 1be-1f** | No Swift Screen | Comments composer, redesign, formatting tray |
| **Spec: 1bc-1bd, 1aj-1ak** | No Swift Screen | Favorites (fandoms, tags, works, authors) |
| **Spec: 1ao-1aw** | No Swift Screen | Detailed standalone filters (status, tags, language) |
| **Spec: 1ax** | No Swift Screen | Save search |
| **Spec: 1t** | No Swift Screen | AO3 History |
| **Spec: 1p, 1ag** | No Swift Screen | Subscriptions |
| **Spec: 1x, 1y, 1aa** | No Swift Screen | Drafts, Dashboard, More on AO3 |
| **Spec: 1ah, 1ai** | No Swift Screen | Reading History (ledger states) |
| **Swift: `ReadiumReaderView`** | No Spec Artboard | The core reader UI logic is implemented but lacks a specific design artboard entry in the mapped spec |
| **Swift: `AboutView`** | No Spec Artboard | Reached via `.sheet` in Settings |
| **Swift: `BugReportView`** | No Spec Artboard | Reached via `.sheet` in Settings |
| **Swift: `ReaderPronunciationSettingsView`**| No Spec Artboard | Reached via `.sheet` in Reader |
| **Swift: `BackupImportSheet`** | No Spec Artboard | Reached via `.sheet` in Settings |

DIGEST: The app implements the primary navigational backbone for tabs, queue/collection creation, basic account settings, and writing views, but a significant portion of advanced AO3 features (challenges, deep moderation, specific comment composers, insights, and discrete list views like history and favorites) currently lack distinct Swift views.
