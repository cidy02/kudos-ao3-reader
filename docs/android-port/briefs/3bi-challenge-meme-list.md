# Brief 3bi: a prompt meme's prompts, the reading screen

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result. Decide questions about demo fixtures, test data, file placement and naming yourself and
list them under "Decided without asking". Stop only for a question about what the app reads
from or sends to AO3, or what it does to the reader's stored data; even then finish everything
the question does not block first, and put every open question in your final summary. Write
`docs/android-port/briefs/3bi-result.md` as you go.

Read first: `briefs/3ba-result.md` and `briefs/3be-result.md` **with their landing notes** (how
a challenge screen is built and tested on Android: the reads are counted before anything
else; no invented top buttons; no line heights added to shared components; one demo answer
per AO3 address, shared with whatever already reads it; **a row or control whose only purpose
is a write that is not built yet shows its value and opens nothing**; a Compose screen test
passes `parseDispatcher = Dispatchers.Unconfined`), and `docs/AO3_NETWORKING_POLICY.md`.

## What is missing

On a Prompt Meme collection, Challenge Settings' Prompts row
(`account/AO3ChallengeSettingsScreen.kt`) opens AO3's page in the in-app browser. iOS has the
screen: `Features/Challenges/PromptMemeView.swift` (artboard 1cc). This brief is that screen,
**reading only**: iOS's two writes there (claim a prompt, release a claim) and "New prompt"
(the sign-up form) are later briefs.

## Build

Start the result with what iOS has, read from the code: how the screen is reached and from
where; the header and its subtitle in each case; any filter or segment and what each shows;
each prompt card (every field, how tags of each kind are worded, anonymous prompts, the claim
state and its words and colours in each case, what is cut short and how); paging; loading,
empty, failure and signed-out states and their words; what each tappable thing opens; **every
request iOS makes for one opening and for each further page**, in order, and what the screen
shows when one fails; and both writes and "New prompt" (what is sent, when, the words for each
verdict), so the next brief has them.

Then build the screen on Android and make Challenge Settings' Prompts row open it for a
prompt meme (a gift exchange keeps what it does today).

- **Reading only.** Where iOS draws a control whose only purpose is a write (Claim, Release,
  New prompt, Fill it if it writes), show the state without the control, add no sentence in
  its place, and list each one in the result.
- Where iOS opens AO3's page, Android opens the same address in the in-app browser.

## Rules for the network

For one opening, the reads iOS makes and no more, through the existing authenticated client;
one further read per "load more", made only when the reader asks, as iOS; nothing in the
background, nothing read ahead. **Count them in the result before anything else.** If iOS
walks page after page of anything without a cap the networking policy names, Android does
not: read the first page only, show what iOS shows for one page, and put the question in
your summary (owner question 16 arose this way). Say which policy rule allows each read. No
writes at all.

## How it must be drawn

As the other challenge screens: the subject header, the challenge sections and rows already
in `account/`, the app's chips for tags, `tokens.scopePalette`. Layout, content and words are
iOS's; the top row's buttons are the app's Material icon buttons. Tokens only: no stock
Material chips, cards or default Material colours. Light, Dark, Sepia and OLED; every new text
with a line height; nothing clipped at `isAccessibilityFontScale()`; `statusBars + 76dp` above
the header; the list lazy.

## Demo and tests

- The demo answers Summer Prompt Meme's prompts locally (`network/ao3/DemoNetwork.kt`,
  fixtures under `app/src/debug/assets/fixtures/`, original filler only): two pages; prompts
  that are unclaimed, claimed by the demo account, claimed by someone else and anonymous; one
  with tags of every kind and one with a long description. Say the `nav:` route (one argument:
  an `&` in a route is cut off by the device's shell) and the path from `nav:ao3-collections`.
- Tests, none reaching the network: the parser on each fixture; the reads for one opening and
  for one more page, counted; a failed read leaving what iOS leaves; signed out; Challenge
  Settings' row opening this screen for a prompt meme and not for a gift exchange; no write
  control present; nothing sent (a client whose POST throws). Compose tests here need a tall window for lazy
  lists, patient waits, and `@GraphicsMode(NATIVE)` when they ask about text. **Do not assert
  `hasVisualOverflow` on a short label**: a text narrower than its row reports a width
  overflow it does not have; assert `!didOverflowHeight` and that the last line is not
  ellipsized. When several values share a panel, a matcher by sibling finds all of them:
  count them, or match by the row.
