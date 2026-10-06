# Brief 3be: a challenge's tag set, the read-only screen

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result, and if a question remains, ask it at once and stop rather than guess (put every open
question in your final summary, not only the first). Write
`docs/android-port/briefs/3be-result.md` as you go.

Read first: `briefs/3ba-result.md` and `briefs/3ay-result.md` with their landing notes (the
pattern for a challenge screen on Android and what was corrected on landing: the reads are
counted before anything else; no invented top buttons; no line heights added to shared
components; a demo fixture must not replace a page another screen reads; **one** demo answer
per AO3 address, shared with whatever screen already reads it; a new file's type names must
not repeat a name its package already has; a Compose screen test passes
`parseDispatcher = Dispatchers.Unconfined`; where iOS's words say something that is not true
on Android, leave those words out and list them), and `docs/AO3_NETWORKING_POLICY.md`.

## What is missing

On Challenge Settings (`account/AO3ChallengeSettingsScreen.kt`, brief 3ba) a tag set row opens
AO3's page in the in-app browser. iOS has the screen:
`Features/Challenges/TagSetView.swift` (artboard 1ch). This brief is that screen, **reading
only**: iOS's two writes there (`saveTagSetFields`, `reportRejectedTag`) are a later brief.

## Build

Start the result with what iOS has, read from the code: how the screen is addressed (a tag
set's own number, not the collection's name) and where that number comes from; the header and
its subtitle in each case; every section in order, with its header and the cases in which it
is shown or left out (owner, moderator, neither; nominations open or closed; visible or not);
every row and how its value is worded in each case; what each tappable thing opens; loading,
failure, signed-out and empty states and their words; **every request iOS makes for one
opening**, in order, for whom each is made, and what the screen shows when one of them fails;
and both writes (what is sent, when, and what the screen does after), so the next brief has
them.

Then build the screen on Android and make Challenge Settings' tag set rows open it.

- **Reading only.** Show every value iOS shows. Where iOS draws a control whose only purpose
  is one of the two writes (an editable field, a Save, a Reject), draw the value without the
  control, add no sentence in its place, and list each one in the result.
- **No browser detour inside the screen** beyond what iOS has: where iOS opens AO3's page,
  Android opens the same address in the in-app browser.

## Rules for the network

For one opening or refresh, the same reads iOS makes and no more, through the existing
authenticated client: the tag set's page, and the edit form and the nominations only for the
people iOS reads them for. Nothing in the background, nothing read ahead. **Count them in the
result before anything else.** If iOS walks page after page of anything here (tags,
nominations) without a cap the networking policy names, Android does not: read the first page
only, show what iOS shows for one page, and put the question in your summary (this is how
owner question 16 arose in 3ba). Say which policy rule allows each read. No writes at all.

## How it must be drawn

As 3ba's screen: the subject header, the challenge sections and rows already in
`account/AO3ChallengeSettingsScreen.kt` (reuse them; move one to a shared place only if both
screens then use it), the app's chips for tags. Palette `tokens.scopePalette`. Layout, content
and words are iOS's; the top row's buttons are the app's Material icon buttons. Tokens only: no
stock Material chips, cards or default Material colours. Light, Dark, Sepia and OLED; every
new text with a line height; nothing clipped at `isAccessibilityFontScale()`; a pushed screen
leaves `statusBars + 76dp` above its header.

## Demo and tests

- The demo answers the tag set pages locally (`network/ao3/DemoNetwork.kt`, fixtures under
  `app/src/debug/assets/fixtures/`, original filler only) for the two tag sets Winter Exchange
  2026 already links to and the one Summer Prompt Meme links to: one with tags of every kind
  and open nominations, one closed, one whose edit form is refused (a viewer who is not its
  owner). Say the route that opens each (`nav:` routes; Challenge Settings is reachable from
  `nav:ao3-collections`).
- Tests, none reaching the network: the parsers on each fixture; the reads made for one
  opening, counted, for an owner and for a viewer; one failing read leaving the rest of the
  screen intact, as iOS; the signed-out state reading nothing; Challenge Settings' row asking
  for this screen with the right number; nothing sent (a client whose POST throws). Compose
  tests here need a tall window for lazy lists, patient waits, and `@GraphicsMode(NATIVE)`
  when they ask about text.
