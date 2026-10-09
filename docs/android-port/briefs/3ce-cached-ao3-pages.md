# Brief 3ce: a page AO3 could not serve again is shown from memory, and says so

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result. Decide questions about demo fixtures, test data, file placement and naming yourself and
list them under "Decided without asking". Do not stop for a question: decide it the more
sparing way (fewer reads, nothing sent that iOS does not send), write it under "Open
questions", and keep going to the end. Write `docs/android-port/briefs/3ce-result.md` as you go.

**Standing rules from the owner and from earlier landings** (each cost a fix; follow them):
- A read AO3 will refuse is not made, and a "best-effort" read remembers that it was
  attempted, not only that it succeeded (owner, 2026-10-07).
- A screen reads what it draws from its collected state (`val state by x.collectAsState()`
  then `state.names`), never from a function that reads a flow's `.value`: the second does
  not redraw when the value changes (3bh).
- A screen that takes another's place inside one route gets the shell's top row back by
  itself; give it `ProvidePushedShellChrome` and nothing else.
- In tests: do not assert `hasVisualOverflow` on a short label (assert `!didOverflowHeight`
  and that the last line is not ellipsized); when several values share a panel, count the
  matches or match by the row; an API marked experimental needs its `@OptIn`; Compose tests
  need a tall window for lazy lists, patient waits and `@GraphicsMode(NATIVE)`.
- A brief's file name must not contain the word "prompt" (`.gitignore`).
- A list of rows is lazy, drawn with the form's own parts (`writingSuggestionPanel`, the
  form's failure and loading rows); no stock Material `Button`, progress ring colours or
  unstyled `Text` (3bm).
- A row with a long label shows a short value as its `trailing` content, not as `value`
  (3bm: the shared row gives a long label the width and the value one letter a line).
- A toolbar button handed to the shell must be absent **as a value** until it applies
  (`trailingContent = if (form == null) null else { … }`). Content that tests for the form
  inside itself stays empty when the form arrives after the screen: 3bo's Save was invisible
  until this was fixed on landing.
- In tests: a `waitUntil` on something that is not on screen (a request count) needs
  `compose.waitForIdle()` first; a test function's body returns `Unit`
  (`runBlocking<Unit> { … }`); never `runBlocking` in an `@After` on something that needs
  the main thread (it hung the whole suite); the theme is `KudosThemeMode.Oled`, not `OLED`;
  when two states share a title, wait for the sentence that differs.
- No line heights or other changes to shared components (`ui/subject/`, `settings/`) unless
  the brief names them.
- A reload or a refresh never clears what the writer is in the middle of (audit A22: a
  reload cleared a reply's target and the text went out as a new comment).
- Demo data must really produce what the brief asks to be seen: say which demo rows give
  each case, and check the rule that selects them against those rows.

- **A write that has been sent** (rules of 2026-10-09, each from an audit): in
  `AO3WriteRepository`, `requireCollectionSession` is called only **before** the POST; after
  it, `movedOnAfterWrite(expectedGeneration, response)?.let { return it }` and nothing that
  throws. A state class shows the repository's verdict as it is, clears its busy flag on
  every path out while it is active (a `finally`), and never puts "was not withdrawn" in front
  of `AO3CollectionFields.UNCONFIRMED`. The token and `_method` go in the body always.
- In tests: work done in `withContext(Dispatchers.Default)` is off the test clock, so wait in
  real time on its effect; never wait for text that is already on screen before the action
  (wait on the thing the action changes); a screen that reads on another thread outlives the
  test, so do not close its database or client in `@After`.

Read first:
- `audits/R6-result.md`, the section "Showing cached AO3 data": where iOS shows the banner.
  **A guide to where to look, not a specification.**
- iOS's code, line by line: `Services/AO3Client+Authors.swift` (`AO3AuthorPageCache`: its key,
  its two lifetimes, its size), `Services/AO3AuthorProfileService.swift` (`page(...)`,
  `bypassCache`, every `insert`, `removeValue`, `removeAuthorDashboards`, `removePages`),
  `Services/AO3AccountListCountsCache.swift` for the conventions it names, and the four
  places that show the banner: `Features/Account/AccountInboxViews.swift`,
  `Features/Account/AccountView.swift`, `Features/Authors/AuthorProfileView.swift`,
  `Features/Authors/AO3SeriesDetailView.swift`.
- `docs/AO3_NETWORKING_POLICY.md`: quote the rules on caches (what may be kept, for how long,
  scoped to whom) and say which allows each thing built here.
- On Android: `network/ao3/comments/CommentCache.kt` and
  `network/ao3/comments/AO3CommentRepository.kt` with the triage in `audits/A17-result.md`
  (A17-4) and `audits/A22-result.md` (A22-2): **the rule already settled here for showing an
  old copy**: only when AO3 could not be reached, only this viewer's own copy, never a page of
  another kind stored under the same key. And `network/ao3/chapters/AO3ChapterIndexRepository.kt`
  (a cache kept per session since 2026-10-09).

## What is missing

On iOS four screens (the Inbox, the Account tab's own profile, an author's profile, a series
page) keep the pages they have read in memory. Opening one again within a few minutes makes
no request; when AO3 cannot be reached, the last copy is shown with a line that says so:
"Showing cached AO3 data". On Android each of those screens asks AO3 every time, and a failed
load replaces what was on screen with an error card.

## Build

Start the result with what iOS has, read from the code: the cache's key and what "scope"
means in it; both lifetimes and the size limit; **every read that goes through it and every
one that does not**; what `bypassCache` is and which gestures set it; every place a write
removes entries, and which; exactly which failures fall back to the old copy (quote the
`catch`); what sets and clears the banner on each of the four screens, its words and its
symbol; what happens to the cache on sign-out, on a session change and on relaunch.

Then build it on Android, for the same four screens.

- **In memory only.** Never on disk, never in a backup, gone on relaunch. One cache, not four.
- **Scoped to the viewer.** A copy read in one session is never shown in another, signed-out
  included: key it as iOS does and say how that maps to Android's session generation. A
  sign-out or a session change must not leave a page readable.
- **A fresh copy saves the request** exactly where iOS's does, and nowhere else. Count, for
  each screen, the requests for a first opening, a second opening within the fresh lifetime,
  one after it, and a pull to refresh; they must equal iOS's. Nothing is read ahead and
  nothing is refreshed in the background.
- **The old copy is shown only when AO3 could not be reached** (no connection, a timeout, a
  5xx or "AO3 is busy"). **Never after AO3's own refusal** (sign-in required, 403, 404): that
  is AO3's answer, and what someone was allowed to see before is not shown in its place. If
  iOS falls back on more than that, Android does not: list the difference in the result.
- **The banner** with iOS's words, drawn with the app's tokens where iOS draws its own on
  each of the four screens; a successful load removes it. The screen keeps what the old copy
  gives it and stays usable; anything that would write to AO3 from an old copy behaves as it
  does today (say what that is, for each screen).
- **Writes remove what they change**, as iOS does: list each Android write that corresponds
  to one of iOS's removals and remove the same entries.
- Through the existing clients and repositories; no new HTTP code.

## How it must be drawn

The banner is one line with a symbol, in the screens' existing parts and
`tokens.scopePalette`; no stock Material chip, card or snackbar. Light, Dark, Sepia and OLED;
a line height; nothing clipped at `isAccessibilityFontScale()`.

## Demo and tests

- The demo needs a way to make one of these reads fail after it has succeeded once: say the
  debug route or the taps (for example a second opening in airplane mode already fails every
  read that is not answered locally: if the demo answers all four locally, add a local
  switch, debug builds only, and say how to flip it). Say which screen shows the banner and
  how to clear it.
- Tests, none reaching the network: the cache's lifetimes with a clock the test controls; the
  size limit; the key's scope (two sessions, a signed-out reader); for each screen the request
  counts above; the old copy shown for each failure that allows it and **not** for each
  refusal; the banner set and cleared; a sign-out and a session change leaving nothing
  readable; each write's removal; nothing written to disk (a temporary directory left empty).
