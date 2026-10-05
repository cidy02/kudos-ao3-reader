# Brief 3ba: Challenge Settings, the read-only screen

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result, and if a question remains, ask it at once and stop rather than guess (put every open
question in your final summary, not only the first). Write
`docs/android-port/briefs/3ba-result.md` as you go.

Read first: `briefs/3aw-result.md` and `briefs/3ay-result.md` with their landing notes (the
pattern for a collection screen on Android and what was corrected on landing: no invented top
buttons; no line heights added to shared components; a demo fixture must not replace a page
another screen reads; **one** demo answer per AO3 address, shared with whatever screen already
reads it; a Compose screen test passes `parseDispatcher = Dispatchers.Unconfined` to
`AO3CollectionDetailRepository`; where iOS's words say something that is not true on Android,
leave those words out and list them), and `docs/AO3_NETWORKING_POLICY.md`.

## What is missing

On a challenge collection, Manage › Challenge Settings opens AO3's page in the browser
(`account/AO3CollectionDetailScreen.kt`, `collectionManageActions`). iOS has the screen:
`Features/Challenges/ChallengeSettingsView.swift` (artboard 1by), a read-only inspection of the
collection's challenge in AO3's order. This brief is that screen and **only that**: it reads,
and sends nothing.

## Build

Start the result with what iOS has, read from the code: the header and its subtitle in each
case; every section in order with its header (and the cases in which a section or its header
differs: Gift Exchange or Prompt Meme, one tag set or several, owner or not); every row with
its label and how its value is worded in each case, including what a row says when its count
could not be read (iOS distinguishes "failed" from zero); every row that opens something and
what it opens; the "At AO3" section; loading, failure and signed-out states and their words;
**every request iOS makes for one opening**, in order, which are made together and which one
after another, and what happens to the screen when one of them fails.

Then build it on Android and make Manage › Challenge Settings open it.

- **Rows that open another screen.** iOS opens `ChallengeSettingsEditView`, `PromptMemeView`,
  `TagSetView`, `ChallengeSignUpsView` and `ChallengeAssignmentsView`. Android has none of them
  yet (later briefs, one each). Until then each such row opens that page on AO3 in the in-app
  browser, as other "not native yet" rows do. Keep those destinations in one place, named for
  the screen that will replace each, and list them in the result.
- **"Open on AO3" rows** (iOS's own escape hatches for matching) stay what they are on iOS.
- No editing, no matching, no write of any kind.

## Rules for the network

The same reads iOS makes for one opening and on pull-to-refresh, through the existing
authenticated client and coordinator, with iOS's ordering and no more than iOS's concurrency;
nothing in the background; a failed count leaves its row saying so and does not fail the
screen, as on iOS. Say which policy rules cover these reads (several pages are read for one
screen: say why that is within "No background or bulk scraping", or stop and say it is not).

## How it must be drawn

The subject header, section headers, collection panels and rows, `SubjectFormRow` and the
settings rows as the Moderation and Maintainers screens use them. The palette is the
collection's own, as on those screens. Layout, content and words are iOS's. No top buttons
unless iOS's screen has them. Tokens only: no stock Material chips, cards or default Material
colours. Light, Dark, Sepia and OLED; every new text with a line height; rows that reflow at
`isAccessibilityFontScale()`.

## Demo and tests

- The demo answers every read locally (`network/ao3/DemoNetwork.kt`, fixtures under
  `app/src/debug/assets/fixtures/`, original filler only; look at the challenge fixtures the
  demo already has before adding any, and reuse the address's existing answer where one
  exists): Winter Exchange 2026 as a Gift Exchange with dates, requirements, two tag sets and
  assignment tallies; Summer Prompt Meme as a Prompt Meme; one count that fails, to see its
  row. Say how to reach each on the emulator.
- Tests, none reaching the network: the parsers on the fixtures; the reads made for one
  opening, in order; a failed count shown as failed, not zero; Gift Exchange and Prompt Meme
  differences; owner and non-owner; each row's destination; the Manage row opening this screen;
  no write is ever sent.
