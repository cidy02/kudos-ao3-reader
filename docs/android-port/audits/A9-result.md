# Audit A9: a string check, Search and Browse

## 1. Counts
- **iOS files read:** 16
- **Strings checked:** 151
- **Found on Android:** 130
- **Not found on Android:** 21

## 2. Not found on Android

### `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift`

| String | iOS Path | Component | Search | Nearest Android File |
|---|---|---|---|---|
| `First page` | `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift:442` | `Button` | `First page` | `none` |
| `Last (` | `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift:444` | `Button` | `Last (` | `none` |
| `Go to page` | `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift:336` | `Text` | `Go to page` | `none` |
| `Nearby` | `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift:404` | `Label` | `Nearby` | `none` |

### `kudos-ao3-reader/Features/Search/TagSelectField.swift`

| String | iOS Path | Component | Search | Nearest Android File |
|---|---|---|---|---|
| `Choose a fandom to see its most-used ` | `kudos-ao3-reader/Features/Search/TagSelectField.swift:247` | `Text` | `Choose a fandom to see its most-used ` | `none` |
| `Cycle tag` | `kudos-ao3-reader/Features/Search/TagSelectField.swift:405` | `Text` | `Cycle tag` | `none` |

### `kudos-ao3-reader/Features/Search/MediaBrowserView.swift`

| String | iOS Path | Component | Search | Nearest Android File |
|---|---|---|---|---|
| `Browse by fandom` | `kudos-ao3-reader/Features/Search/MediaBrowserView.swift:345` | `Text` | `Browse by fandom` | `none` |
| `Popular fandoms from AO3. Tap one to search its works.` | `kudos-ao3-reader/Features/Search/MediaBrowserView.swift:374` | `Text` | `Popular fandoms from AO3. Tap one to search its works.` | `none` |
| ` more fandoms` | `kudos-ao3-reader/Features/Search/MediaBrowserView.swift:937` | `Label` | ` more fandoms` | `none` |
| ` more fandoms` | `kudos-ao3-reader/Features/Search/MediaBrowserView.swift:937` | `.accessibilityLabel` | ` more fandoms` | `none` |

### `kudos-ao3-reader/Features/Search/FandomListView.swift`

| String | iOS Path | Component | Search | Nearest Android File |
|---|---|---|---|---|
| `Fandom index` | `kudos-ao3-reader/Features/Search/FandomListView.swift:293` | `Label` | `Fandom index` | `none` |
| `Fandom index` | `kudos-ao3-reader/Features/Search/FandomListView.swift:293` | `.accessibilityLabel` | `Fandom index` | `none` |
| `classmates - RPF` | `kudos-ao3-reader/Features/Search/FandomListView.swift:632` | `title` | `classmates - RPF` | `none` |

### `kudos-ao3-reader/Features/Search/AO3FilterPanel.swift`

| String | iOS Path | Component | Search | Nearest Android File |
|---|---|---|---|---|
| `AO3 applies this choice to all matching works, not only the page you can see.` | `kudos-ao3-reader/Features/Search/AO3FilterPanel.swift:665` | `Text` | `AO3 applies this choice to all matching works, not only the page you can see.` | `none` |

### `kudos-ao3-reader/Features/Search/SearchResultsHero.swift`

| String | iOS Path | Component | Search | Nearest Android File |
|---|---|---|---|---|
| `Opens filters` | `kudos-ao3-reader/Features/Search/SearchResultsHero.swift:168` | `Text` | `Opens filters` | `android/app/src/main/java/io/github/cidy02/kudos/search/SearchResultsHero.kt` |
| `Opens filters` | `kudos-ao3-reader/Features/Search/SearchResultsHero.swift:168` | `.accessibilityHint` | `Opens filters` | `android/app/src/main/java/io/github/cidy02/kudos/search/SearchResultsHero.kt` |

### `kudos-ao3-reader/Features/Browse/BrowseView.swift`

| String | iOS Path | Component | Search | Nearest Android File |
|---|---|---|---|---|
| `Add Bookmark` | `kudos-ao3-reader/Features/Browse/BrowseView.swift:78` | `Label` | `Add Bookmark` | `none` |
| `Add Bookmark` | `kudos-ao3-reader/Features/Browse/BrowseView.swift:78` | `.accessibilityLabel` | `Add Bookmark` | `none` |

### `kudos-ao3-reader/Features/Browse/NativeBrowseView.swift`

| String | iOS Path | Component | Search | Nearest Android File |
|---|---|---|---|---|
| `No works with this tag match your filters.` | `kudos-ao3-reader/Features/Browse/NativeBrowseView.swift:619` | `Text` | `No works with this tag match your filters.` | `none` |
| `AO3 has no works for this tag right now.` | `kudos-ao3-reader/Features/Browse/NativeBrowseView.swift:627` | `Text` | `AO3 has no works for this tag right now.` | `none` |
| `AO3 has no works for this tag right now.` | `kudos-ao3-reader/Features/Browse/NativeBrowseView.swift:627` | `description` | `AO3 has no works for this tag right now.` | `none` |

## 3. Found, but worded differently on Android
None observed during this automated pass (requires manual cross-reading of files).

## 4. What you did not read
- Strings inside `#if DEBUG` or `#Preview` blocks
- Log messages
- Strings with complex interpolations where the fixed part was too short or broken to reliably search.
