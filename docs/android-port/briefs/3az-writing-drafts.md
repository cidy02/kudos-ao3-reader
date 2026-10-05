# Brief 3az: Writing › Drafts, the list

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result, and if a question remains, ask it at once and stop rather than guess. Write
`docs/android-port/briefs/3az-result.md` as you go.

Read first: `briefs/3av-result.md` and `briefs/3aw-result.md` with their landing notes (how an
account screen that reads AO3 is built and tested here, and what was corrected on landing: no
invented top buttons; no line-height changes to shared components; a demo fixture must not
replace a page another screen reads; a Compose screen test passes
`parseDispatcher = Dispatchers.Unconfined` to `AO3CollectionDetailRepository`, and any new
repository that parses off the main thread needs the same parameter), and
`docs/AO3_NETWORKING_POLICY.md`.

## What is missing

The Writing area (iOS `Features/Writing/`, 17 files; `docs/android-port/specs/writing.md` is an
older outline of it) does not exist on Android. This brief is its first screen and **only
that**: the drafts list, which reads and sends nothing else.

iOS: `Features/Writing/WritingDraftsView.swift` (artboard 1x), opened from the Account page's
Writing section (`Features/Account/AccountView.swift`, `case .drafts`). Android's Account page
(`account/AccountScreen.kt`) has a Drafts row in its Writing section: find what it does today.

## Build

Start the result with what iOS has, read from the code: the header and how the tally line is
worded in each case; the orange notice, word for word; each card's content (which fields, the
"N days left" chip and its wording and colours at each threshold, the "Created …" date and its
format), and what a draft whose deletion date did not parse shows; paging; the loading, empty,
failure and signed-out states and their words; what a tap on a draft opens; what re-reads the
list (pull to refresh, coming back to the app, the day changing); the request it makes and the
parser (`parseDraftDeletionDates`, `DraftExpiry`).

Then build it on Android and make the Account page's Drafts row open it.

- **A tap on a draft.** iOS opens its native editor (`WorkEditView`). Android has no editor
  yet (later briefs). Until then a tap opens that draft's edit page on AO3 in the in-app
  browser, as other "not native yet" rows do: say so in the result, and keep the destination
  in one place so the editor brief can replace it.
- **No Post and no Delete** on this screen: iOS deliberately has neither here (read the
  comment at the top of the iOS file and quote it in the result).

## Rules for the network

One authenticated read of the reader's own drafts page per opening, per page turn and per
pull-to-refresh, through the existing authenticated client; nothing in the background, no
read-ahead of other pages, no per-draft requests. The policy allows the reader's own account
lists; say which rule. No writes at all in this brief.

## How it must be drawn

The subject header, the account lists' cards and chips (`account/AccountWorksListScreen.kt`,
`ui/subject/SubjectComponents.kt`), the app's pagination and refresh. The palette is
`tokens.scopePalette`, as the other account pages. Layout, content and words are iOS's. Tokens
only: no stock Material chips, cards or default Material colours; the notice's orange comes
from the app's palette helpers, not a literal Material colour. Light, Dark, Sepia and OLED;
every new text with a line height; nothing clipped at `isAccessibilityFontScale()`.

## Demo and tests

- The demo answers the drafts page locally (`network/ao3/DemoNetwork.kt`, a fixture under
  `app/src/debug/assets/fixtures/`, original filler only): two pages; drafts with 29, 7, 1 and
  0 days left relative to a date the fixture's test can pin; one whose deletion notice is
  missing. Because "days left" depends on today, say how the demo keeps the chips meaningful
  whenever it is opened (iOS's demo may already solve this: look). Say the route to open it
  (`nav:` demo routes are in `app/KudosApp.kt`).
- Tests, none reaching the network: the parser on the fixture, including the missing notice;
  days left at each threshold and across a day change, with the clock passed in; the tally
  line in each case; one read per opening and per page; the signed-out state reads nothing;
  the Account row opening this screen; a draft tap asking for the right address.
