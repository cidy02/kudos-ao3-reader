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

## Landing note (Claude, 2026-10-08)

Gemini Pro wrote this brief while Codex was out of quota. Its reading of iOS above is right and
was kept, with its fixture, its demo address and its wiring of the form's Chapters row. Its
screen and state were replaced on landing, because they did not hold to the standing rules:

- **Two reads per opening, not one.** The state read in its `init` and the screen called
  `reload()` again from a `LaunchedEffect` on first composition.
- **A second path to AO3.** It took the authenticated client into the screen and built the
  address itself. The read is now `AO3WorkFormRepository.loadChapters` (the form's own
  repository, its session check, `AO3ChapterIndexParser` as before), reached through
  `WritingWorkFormState.loadChapters`, so the form's screen needs no new arguments.
- **Stock Material parts.** A default `Button`, a default `CircularProgressIndicator`, and
  texts with no colour or line height. The list is now built as the form's pickers are:
  `statusBars + 76dp`, the scope wash, the lazy panel rows, the form's own failure and
  loading rows.
- **Its two test files** tested the replaced state; one file replaces them
  (`WritingChaptersTest`): iOS's subtitle; one signed-in read of `/works/<id>/navigate` and
  nothing sent; one read per attempt and no retry; a new work or a signed-out reader reads
  nothing; the list after a failure and Try Again, with no click action on a row.

Found on the emulator and fixed: beside a long chapter title the date was one letter wide, a
letter to a line. `SubjectFormRow` gives a label its own width before the value. The date is
now the row's trailing content, which keeps its width while the title wraps (at accessibility
sizes the row stacks them, as before). The shared row still does this to any other row with a
long label and a value; none is known, and audit A6 looks for them.

Not built, as the brief says: a row opens nothing (iOS opens the chapter's edit form) and has
no disclosure mark. iOS has no draft mark on a chapter, so there is none here; the brief was
wrong to ask about one.

Gate: 1,975 tests, green. Seen on `emulator-5556` in airplane mode, Dark and Light:
`nav:writing-work-posted-demo` → Chapters → two rows with their dates, the long title on
three lines; Back returns to the form.

Also seen in this sitting: the earlier fix `5fc910ef` (a refused claim on a prompt meme
scrolls the reason into view) works from the bottom of the list.
