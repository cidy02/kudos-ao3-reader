# Audit A8: String Check (Library and Home)

## 1. Counts
- **iOS files read:** 40
- **Strings checked:** 339
- **Found:** 307
- **Not found:** 32

## 2. Not found on Android
| String | iOS Path:Line | Type | Search Ran | Nearest Android File |
|---|---|---|---|---|
| `From AO3` | `kudos-ao3-reader/Features/Home/HomeCards.swift:283` | `.accessibilityLabel` | `From AO3` | `HomeQueueCard.kt / HomeDashboard.kt` |
| `Double-tap to \(isSelected ?` | `kudos-ao3-reader/Features/Home/HomeResumeHero.swift:51` | `.accessibilityHint` | `Double-tap to ` | `HomeResumeHero.kt` |
| `Double-tap to \(isSelected ?` | `kudos-ao3-reader/Features/Home/HomeResumeHero.swift:81` | `.accessibilityHint` | `Double-tap to ` | `HomeResumeHero.kt` |
| `Double-tap to \(selection.contains(work.id) ?` | `kudos-ao3-reader/Features/Library/AddLibraryWorksSheet.swift:151` | `.accessibilityHint` | `Double-tap to ` | `LibraryScreen.kt` |
| `Mature works are hidden` | `kudos-ao3-reader/Features/Library/AddLibraryWorksSheet.swift:65` | `Label` | `Mature works are hidden` | `LibraryScreen.kt` |
| `Hide Mature is hiding every work you can add here.` | `kudos-ao3-reader/Features/Library/AddLibraryWorksSheet.swift:67` | `Text` | `Hide Mature is hiding every work you can add here.` | `LibraryScreen.kt` |
| `No works to add` | `kudos-ao3-reader/Features/Library/AddLibraryWorksSheet.swift:73` | `Label` | `No works to add` | `LibraryScreen.kt` |
| `Your Library has no works you can add to this \(scopeName).` | `kudos-ao3-reader/Features/Library/AddLibraryWorksSheet.swift:75` | `Text` | `Your Library has no works you can add to this ` | `LibraryScreen.kt` |
| `Your Library has no works matching “\(query)”.` | `kudos-ao3-reader/Features/Library/AddLibraryWorksSheet.swift:88` | `Text` | `Your Library has no works matching “` | `LibraryScreen.kt` |
| `In this collection` | `kudos-ao3-reader/Features/Library/Collections.swift:624` | `.accessibilityLabel` | `In this collection` | `CollectionsScreen.kt` |
| `Open author page` | `kudos-ao3-reader/Features/Library/FavoriteAffinityRow.swift:89` | `Button` | `Open author page` | `LibrarySubjectComponents.kt` |
| `Open author page` | `kudos-ao3-reader/Features/Library/FavoriteAffinityRow.swift:141` | `.accessibilityLabel` | `Open author page` | `LibrarySubjectComponents.kt` |
| `In your library` | `kudos-ao3-reader/Features/Library/FavoriteAffinityRow.swift:150` | `Text` | `In your library` | `LibrarySubjectComponents.kt` |
| `Newest work` | `kudos-ao3-reader/Features/Library/FavoriteAffinityRow.swift:182` | `Text` | `Newest work` | `LibrarySubjectComponents.kt` |
| `UNREAD` | `kudos-ao3-reader/Features/Library/FavoriteAffinityRow.swift:199` | `Text` | `UNREAD` | `LibrarySubjectComponents.kt` |
| `Shows these works in your Library` | `kudos-ao3-reader/Features/Library/FavoriteAffinityRow.swift:61` | `.accessibilityHint` | `Shows these works in your Library` | `LibrarySubjectComponents.kt` |
| `Manage tags` | `kudos-ao3-reader/Features/Library/QueueTagManagerView.swift:91` | `.navigationTitle` | `Manage tags` | `QueueTags.kt` |
| `Move back to In progress` | `kudos-ao3-reader/Features/Library/ReadingHistoryFactsStrip.swift:14` | `Label` | `Move back to In progress` | `ReadingStatistics.kt` |
| `Words read includes finished works when AO3 provides a word count. Recent activity counts each` | `kudos-ao3-reader/Features/Library/ReadingInsightsView.swift:439` | `Text` | `Words read includes finished works when AO3 provides a word count. Recent activity counts each` | `ReadingStatisticsScreen.kt` |
| `Move Up` | `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift:716` | `Button` | `Move Up` | `ReadingQueueBrowserScreen.kt` |
| `Move Down` | `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift:717` | `Button` | `Move Down` | `ReadingQueueBrowserScreen.kt` |
| `Move to Top` | `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift:718` | `Button` | `Move to Top` | `ReadingQueueBrowserScreen.kt` |
| `Move to Bottom` | `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift:719` | `Button` | `Move to Bottom` | `ReadingQueueBrowserScreen.kt` |
| `Queue Details` | `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift:855` | `Label` | `Queue Details` | `ReadingQueueBrowserScreen.kt` |
| `Add a tag to this queue` | `kudos-ao3-reader/Features/Library/ReadingQueuePageParts.swift:199` | `.accessibilityLabel` | `Add a tag to this queue` | `QueuePageScreen.kt` |
| `Removing a work here takes it out of its queues. It stays in Kudos if you saved` | `kudos-ao3-reader/Features/Library/ReadingQueues.swift:322` | `Text` | `Removing a work here takes it out of its queues. It stays in Kudos if you saved` | `QueueSettingsScreen.kt / QueueDetailScreen.kt` |
| `A queue with Keep works offline turned on keeps its works downloaded for you.` | `kudos-ao3-reader/Features/Library/ReadingQueues.swift:484` | `Text` | `A queue with Keep works offline turned on keeps its works downloaded for you.` | `QueueSettingsScreen.kt / QueueDetailScreen.kt` |
| `Cancel Series Addition` | `kudos-ao3-reader/Features/Library/ReadingQueues.swift:519` | `Label` | `Cancel Series Addition` | `QueueSettingsScreen.kt / QueueDetailScreen.kt` |
| `Kudos adds series works only after you choose Add Series, one work at a time.` | `kudos-ao3-reader/Features/Library/ReadingQueues.swift:532` | `Text` | `Kudos adds series works only after you choose Add Series, one work at a time.` | `QueueSettingsScreen.kt / QueueDetailScreen.kt` |
| `Couldn't Open Reader` | `kudos-ao3-reader/Features/Library/WorkCardActions.swift:117` | `Label` | `Couldn't Open Reader` | `HomeWorkMenu.kt / LibraryScreen.kt` |
| `Couldn't Open Work` | `kudos-ao3-reader/Features/Library/WorkCardActions.swift:173` | `Label` | `Couldn't Open Work` | `HomeWorkMenu.kt / LibraryScreen.kt` |
| `This work already uses the latest version, so rebuilding probably won't change it.` | `kudos-ao3-reader/Features/Library/WorkCardActions.swift:467` | `Text` | `This work already uses the latest version, so rebuilding probably won't change it.` | `HomeWorkMenu.kt / LibraryScreen.kt` |

## 3. Found, but worded differently on Android
| iOS String | Android String | iOS Path:Line | Android Path:Line |
|---|---|---|---|
| `You have no collections yet. Create one above to group works together.` | `You have no collections yet. Create one from your Library to group works together.` | `kudos-ao3-reader/Features/Library/Collections.swift:606` | `android/app/src/main/java/io/github/cidy02/kudos/library/LibrarySectionKind.kt:22` |

## 4. What you did not read
- `#Preview` blocks
- `#if DEBUG` sections
- Multi-line comments (`/* ... */`) and single-line comments (`//`)
- Log messages (not extracted as UI elements)
- Interpolated variables (only the longest fixed string part was checked)
- Strings in `android/app/src/test/` (strictly searched `android/app/src/main/`)

## Triage (Claude, 2026-10-08)

Checked by search and by reading both sides. Two whole iOS features are missing on Android,
on screens the matrix had as built:

1. **Reading History has no grouping** (1ah, 1ai): no Time / State / Fandom / Flat strip, no
   Abandoned group, no "Move back to In progress" (`keepInProgressOverride` is stored and
   backed up, and nothing sets or reads it). **P2.** Brief `3bp`.
2. **Favorites has no scopes** (1ak, 1bc, 1bd): no Authors / Fandoms / Tags rows. **P2.** Brief `3bq`.

Smaller, not yet done: the queue's "Cancel Series Addition" (goes with 3bn); no accessible
alternative to dragging in a queue ("Move Up" and the rest); the rebuild confirmation's
message; the Add Works sheet's empty states; unselected highlight colour swatches have no
accessibility label (`reader/ReaderScreen.kt:1119`).
