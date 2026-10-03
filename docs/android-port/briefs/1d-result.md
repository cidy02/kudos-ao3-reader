# Brief 1d result

Pushed screen chrome and floating tab-bar visibility now mirror iOS.

## Chrome & Tab Bar by Route

| Route Category | Routes | Chrome Style | Tab Bar | iOS Evidence |
|---|---|---|---|---|
| **Subject Screens** | `ReadingQueues`, `QueueDetail`, `Collections`, `LibrarySection` | Floating single-row chrome (glass back top-left + screen actions top-right; no title bar; scrolls away) | Visible (hidden in selection mode) | `SubjectScreen.swift` (`SubjectScreenScaffold` / `SubjectScreenChrome`), `ReadingQueueBrowser.swift:389` (`.toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)`), and `shots/ios/queue-neon-reread-dark.png` |
| **Tab-Bar Hidden** | `AO3Collections`, `SeriesWorks`, `AuthorProfile`, `Comments`, `BrowseFandoms`, `Settings` | Single-row title bar (back + title + trailing actions) | Hidden | Explicitly call `hidesFloatingTabBar()` (`AO3CollectionsList.swift`, `AO3SeriesDetailView.swift`, `AuthorProfileView.swift`, `CommentThreadScreen.swift`, `FandomListView.swift`, `SettingsHubView.swift`) |
| **Reader** | `Reader` | Reader chrome | Hidden | Fullscreen reader canvas |
| **Other Pushed** | `BrowseWorks`, `TagWorks`, `AuthorWorks`, `WorkDetail`, `HomeSection`, `LocalHistory`, `LocalFavorites`, `RecentlyDeleted`, `ReadingStatistics`, `AccountList`, `About`, `WebFallback`, etc. | Single-row title bar (back + title) | Visible | Keep floating tab bar on iOS; no `hidesFloatingTabBar()` |

## Implementation Details

- **`PushedShellChrome`**: Generalized chrome holder (`app/PushedShellChrome.kt`) allowing screens to supply trailing actions, back handlers, and selection tab-bar overrides.
- **Scroll-Away Chrome**: Floating back circle and screen action circles (`ToolbarCircleButton`, 44dp) sit at top-inset + 6dp, scrolling away via `ShellChromeState`. Content padding offsets start below the floating row (`topInset + 56.dp`).
- **Back Dispatcher**: System back gesture and glass back circle both pop or exit selection/reordering via `BackHandler`.
- **Follow-up**: Moved `ProvidePushedShellChrome` registration in `QueuePageScreen.kt` after all referenced local state and derived values exist (`activity`, `shownSettings`, `reveal`, `current`, `palette`, `narrowed`, `hidesMature`, `shown`, `reorderLabel`); audited other screens and verified clean build.
