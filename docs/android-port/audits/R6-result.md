# R6: four of R1's features, read in full

## Popular tags in the tag picker

1. **Where on iOS**: 
   - View: `Features/Search/TagSelectField.swift:150`
   - Service: `Services/AO3Client.swift:1599`
2. **How a reader gets there**: Tapping a tag kind field (e.g. Characters, Relationships, Additional Tags) inside the Search or Filter sheet, opening the tag picker.
3. **What is on screen**:
   - When no text is typed and no fandom is set: `Features/Search/TagSelectField.swift:246-247` `"Type above to search AO3 \(title.lowercased())."` and `"Choose a fandom to see its most-used \(title.lowercased()) here."`
   - When no text is typed but a fandom is set: `Features/Search/TagSelectField.swift:228` `"Type above to search AO3 \(title.lowercased())."`
   - While loading: 4 skeleton shimmer lines of widths 220.0, 160.0, 190.0, and 130.0.
   - On success: Rows of tags. An included tag shows a plus icon and `Features/Search/TagSelectField.swift:293` `"Include"`. An excluded tag shows a minus icon and `Features/Search/TagSelectField.swift:297` `"Exclude"`.
   - On failure: Fails silently (shows no tags and keeps the default empty prompt).
   - If typing a query yields nothing: `Features/Search/TagSelectField.swift:188` `"No tags found for “\(query)”."`
4. **What it reads and writes**:
   - **Request**: `GET https://archiveofourown.org/tags/<escaped_fandom>/works`
   - **Built by**:
     ```swift
     private func fandomWorksURL(_ fandom: String) -> URL? {
         guard let encoded = Self.tagPathSegment(fandom) else { return nil }
         return URL(string: "\(base)/tags/\(encoded)/works")
     }
     ```
   - **Headers**: Sent via `AO3Client.shared.getHTML`, using the anonymous `.ephemeral` session and `User-Agent`. No special headers.
   - **When**: On view appear (`.task { await loadPopular() }`).
   - **How often**: Once per picker open.
   - **What stops a repeat**: `guard popular.isEmpty`.
   - **Multiple fandoms**: `let fandom = fandomContext.first` — only the first fandom is queried.
   - **Validation**: Accepts any `200 ... 299` status code in `AO3Client.check`.
   - **Stored value**: The array is kept in `@State private var popular: [String]` for the view's lifetime (not in backup).
   - **Library**: No changes to the local library.
   - **Policy**: `docs/AO3_NETWORKING_POLICY.md` does not name `popularTags` explicitly, but applies the general "No parallel request fan-out outside `AO3RequestCoordinator.withSlot`" and pacing rules.
5. **Where it would go on Android**: `search/FilterTagPicker.kt` (the closest equivalent tag picker) alongside `network/ao3/search/AO3TagAutocompleteRepository.kt` to fetch the tags. Android currently has no most-used suggestions.
6. **Size**: Medium.

## "Showing cached AO3 data"

1. **Where on iOS**: 
   - Inbox: `Features/Account/AccountInboxViews.swift:713`
   - Account Profile: `Features/Account/AccountView.swift:747` and `753`
   - Author Profile: `Features/Authors/AuthorProfileView.swift:251`
   - Series: `Features/Authors/AO3SeriesDetailView.swift:60`
2. **How a reader gets there**: Viewing one of the four screens when a network load fails but a locally cached copy of the HTML exists.
3. **What is on screen**:
   - `Label("Showing cached AO3 data", systemImage: "wifi.slash")`
   - Condition: Displayed when `isShowingStaleCache` is true.
4. **What it reads and writes**:
   - **Source of cached copy**: `AO3AuthorPageCache.shared.value(for:)` or `staleValue(for:)` in `Services/AO3Client+Authors.swift`.
   - **Lifetime**: 5-minute fresh TTL (`ttl: 5 * 60`) and 24-hour stale TTL (`staleTTL: 24 * 60 * 60`).
   - **What sets the stale flag**: When a fetch fails, `AO3AuthorProfileFetcher.page()` catches the error and checks the cache: `return Page(html: stale, isStale: true)`. The view model then sets `isShowingStaleCache = cached.isStale`.
   - **What clears it**: A successful network load returns `isStale: false`, clearing the banner.
5. **Where it would go on Android**:
   - Android drops the stale copy and replaces the screen with an error card.
   - `account/AccountInboxPane.kt:166`: Displays an `AlertDialog` if `state.items.isNotEmpty()`, but if empty it drops the list at `265` for an `ErrorStateCard`.
   - `account/AccountScreen.kt:1025` and `1364`: Discards `AccountListUiState.Loaded` and replaces the list with an `ErrorStateCard`.
   - `author/AuthorProfileScreen.kt:386`: If `tabError != null && page == 1`, it hides the older works list and shows an `ErrorStateCard`.
   - `app/SeriesWorksScreen.kt:206`: Replaces the screen with an `ErrorStateCard` when `is SeriesWorksState.Error`.
6. **Size**: Small.

## "Open Chapter Comments" from the Inbox

1. **Where on iOS**: 
   - View: `Features/Account/AccountInboxViews.swift:757`
   - Destination: `Features/Account/AccountView.swift:898`
   - Address: `Services/AO3Client+Comments.swift:15`
2. **How a reader gets there**: Opening the Account -> Inbox. The item represents a comment on a specific multichapter work.
3. **What is on screen**:
   - `Features/Account/AccountInboxViews.swift:759`: `"on"`
   - `Features/Account/AccountInboxViews.swift:764`: `Text(chapter)` (a capsule chip showing e.g., "Chapter 3").
   - `Features/Account/AccountInboxViews.swift:774`: `"of \(item.workTitle)"`
   - Action item: `Features/Account/AccountInboxViews.swift:723` `"Open Chapter Comments"`
   - Condition: Drawn when `item.chapterIndicatorTitle != nil` and `item.chapterPosition != nil`.
4. **What it reads and writes**:
   - **Request**:
     ```swift
     static func commentsPageURL(workID: Int, chapterID: Int? = nil, page: Int = 1) -> URL {
         var components = URLComponents()
         components.scheme = "https"
         components.host = "archiveofourown.org"
         if let chapterID {
             components.path = "/works/\(workID)/chapters/\(chapterID)"
         } else {
             components.path = "/works/\(workID)"
         }
         var items = [
             URLQueryItem(name: "show_comments", value: "true"),
             URLQueryItem(name: "view_adult", value: "true")
         ]
         // ...
     }
     ```
   - Opens `CommentsView` with the `destination.chapterPosition` passed as `initialChapterPosition`. 
5. **Where it would go on Android**:
   - Android's Inbox item knows its chapter: `account/AccountInboxPane.kt:886` computes `val chapter = item.chapterIndicatorTitle` and renders the `"on"`, `SubjectChip(text = chapter)`, and `"of ${item.workTitle}"` labels.
   - Android's row menu: `account/AccountInboxPane.kt:978` offers `"Open Thread"`, which calls `onOpenWorkComments(it, item.id)` at `315`.
   - Android's route: `app/Routes.kt:113` defines `fun comments(workId: Long, focusedCommentId: Long? = null, chapterPosition: Int? = null, composes: Boolean = false)`.
   - The inbox row currently drops `item.chapterPosition` when navigating. It would require passing `item.chapterPosition` into `onOpenWorkComments`.
6. **Size**: Small.

## Read Aloud downloads on Privacy

1. **Where on iOS**: `Features/Account/PrivacyDataView.swift:348`
2. **How a reader gets there**: Navigating to Account -> Settings -> Privacy.
3. **What is on screen**:
   - `Features/Account/PrivacyDataView.swift:344`: `SectionRuleHeader(title: "Read Aloud downloads")`
   - `Features/Account/PrivacyDataView.swift:350`: `"Optional Voice Pack downloads stay separate from your reading data."`
   - `Features/Account/PrivacyDataView.swift:353`: `"Kudos never sends a work's text, spoken audio, your AO3 sign-in, saved works, reading history, usage information, or anything that identifies your account to the Voice Pack provider. The provider can see your IP address and basic details about the connection. Kudos tells you this before downloading a Voice Pack, and the installed voices stay on this device."`
   - Condition: Shown statically below the "AO3 session" section.
4. **What it reads and writes**: N/A. Static informative text.
5. **Where it would go on Android**: 
   - `settings/PrivacyDataScreen.kt`.
   - Android's current sections word for word in order:
     - `kicker = "AO3 Account › Settings"`, `title = "Privacy"`, `subtitle = "Your reading data stays on this device"`
     - `"No ads or tracking, and no separate Kudos account"`
     - `"Kudos connects to AO3. After you approve a Voice Pack download, it also connects to the service providing the pack. Your library, reading positions, tags, collections, and AO3 sign-in stay on this device."`
     - `SectionRuleHeader("Stored on this device")`
     - `"Reading copies"`, `"$readingCopies works"`
     - `"Caches"`, `"0 MB"` (or `"Unknown"`)
     - `"Reading positions"`, `"0"`
     - `"Local collections"`, `"0"`
     - `"Saved searches"`, `"0"`
     - `"Search history"`, `"Not recorded"`
     - `"Free up space"`, `"${freeableCopies.size} files"`
     - `"Clear reading positions"`, `"[N] works"`
     - `"Clear reading history"`, `"[N] works"`
     - `"Clear browse cache"` (or `"Browse Cache Cleared"`)
     - `"The sizes shown are measured on this device. Browse keeps fandom and category lists so it opens faster; it rebuilds them when needed, and your device may remove them to free space.\n\nEach option asks before it clears anything and tells you what will change on this device. Your AO3 reading history is separate; clear it from History or turn it off in AO3 Preferences."`
   - Android does not have the "AO3 session" or "Read Aloud downloads" sections. The new section would sit near the bottom.
6. **Size**: Small.
