# Brief 3bm — work form's Chapters list

## Reads, counted first
- **One read** per opening and per refresh: the chapter index of that work (`/works/<id>/navigate`), using the existing authenticated client. Signed out reads nothing (handled by existing state/client patterns).
- No other reads.

## iOS contract read from code
Reference: `kudos-ao3-reader/Features/Writing/WritingChaptersView.swift` and `kudos-ao3-reader/Services/AO3Client+Comments.swift`.
- **Header and subtitle**: Kicker is "AO3 Account", title is "Chapters". Subtitle is the work title if count is unknown, or `<workTitle> · <N> chapter(s)` if count is present.
- **Each row**: Label is `chapter.displayName` (which is "Chapter <position> · <title>" or just "Chapter <position>"). Value is `chapter.dateText` (the parsed `span.datetime` without parentheses).
- **Draft chapter's mark**: The brief asks to report "a draft chapter's mark if any". **iOS's code (`AO3ChapterRef` and `WritingChaptersView`) has no draft mark logic and displays no draft mark.** Per the rule "When this brief and iOS's code disagree, iOS's code wins", I will not add or display a draft mark, nor extend the parser for it. I am noting this disagreement here.
- **What a row opens**: On iOS, it opens `WritingChapterDestination(workID, workTitle, chapterID, chapterCount)`. For Android, rows will open nothing yet, with no disclosure mark and no click action, as instructed.
- **States**:
  - Loading: `ProgressView("Loading chapters…")`.
  - Failure: `errorMessage` from `UserFacingError` and a button "Try Again" which increments the `reload` counter.
  - Empty: iOS parses `ol.chapter.index` `li` elements. If it yields an empty array, iOS just shows an empty `List` with the header. 
  - Signed-out state: If auth fails, it shows the error message ("Your AO3 session expired. Please log in again." or similar depending on `UserFacingError`).
- **Reloading**: The screen re-fetches when the `reload` counter increments (from the Try Again button or returning from a pushed screen) or when `sessionGeneration` changes.
- **The one request**: Authenticated GET to `AO3Client.chapterIndexURL(workID: workID)`.
- **Failure**: The screen shows the error message and a "Try Again" button.

## Android implementation
- `WritingChaptersScreen.kt` and `WritingChaptersState.kt` added.
- The Chapters row in `WritingWorkFormScreen` pushes this screen.
- Rows show the chapter's number/title and date, with no click action.
- Uses existing `AO3ChapterIndexParser` which already parses the needed data (position, title, dateText).
- Demo route `nav:writing-work-posted-demo` will provide a local answer for work 995006.

## Decided without asking
- The iOS code does not set `loadedGeneration` on a failed fetch, which would cause repeated retries on recomposition. To satisfy the standing rule "a best-effort read remembers that it was attempted", `WritingChaptersState` sets `loadedGeneration` and `loadedReload` on failure as well.
- The existing `AO3ChapterIndexRepository` caches globally for the app and fetches anonymously. To satisfy "through the existing authenticated client", `WritingChaptersState` bypasses the repository and uses `AO3AuthenticatedClient.getAuthenticated()` and `AO3ChapterIndexParser` directly.
- The "Chapters" row opens the screen by managing a boolean in `WritingWorkFormScreen` and pushing with `ProvidePushedShellChrome`, similar to the association pickers.
- `WritingChaptersScreenTest` and `WritingChaptersStateTest` added covering all cases without network reads.
- Re-used `WorkFormScreenClient` in `WritingChaptersStateTest` by wrapping it in `DefaultAO3AuthenticatedClient`.


## Open questions
- The brief asks for "a draft chapter's mark if any". iOS `WritingChaptersView` and `AO3ChapterRef` do not extract or display a draft mark for chapters. Since iOS's code wins over the brief, I have left it out and did not extend the parser for it. Should iOS be updated to display draft marks for chapters?
