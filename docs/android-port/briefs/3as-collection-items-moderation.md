# Brief 3as: the AO3 collection's items (moderation) screen

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result. Write `docs/android-port/briefs/3as-result.md` as you go.

## The screen

On an AO3 collection a maintainer owns (`account/AO3CollectionDetailScreen.kt`, its Manage
section), Moderation is a row that leads nowhere useful on Android. iOS has the screen:
`AO3CollectionItemsView.swift` with `AO3CollectionItemStaging.swift` (find them under
`Features/`), and the client calls they use. As the earlier survey put it: it lists the
collection's items awaiting or holding a decision, lets the maintainer stage approve / reject /
remove (and whatever else iOS offers) for several items, and submits them in **one POST**.

Start the result with what iOS's screen holds: its sections and filters, each row's contents,
the choices per item and how a staged choice is shown, the submit and discard controls and
their words, the confirmations, the states (loading, empty, error, signed out, not a
maintainer), and paging. Then build that on Android.

## Rules for the network

- Reads: the collection's items page(s), asked for when the screen is opened, on a page change
  and on pull-to-refresh, through the paced client and the repository the collection screen
  already uses. Signed in only. Nothing in the background, no reading ahead of pages.
- The write: one POST per confirmed submit, carrying the form AO3 served (field names, the
  token, the method override if any) with the staged choices filled in, exactly as iOS builds
  it. Through Android's existing authenticated write path (read `AO3WriteRepository` and brief
  3an's `unsubscribe` there: the session check, the single unretried POST, how success is
  recognised). Never retried or sent without the maintainer's tap and confirmation. After it,
  the list shows what AO3 answered.
- Read `docs/AO3_NETWORKING_POLICY.md` and say which rules cover the reads and the write. If
  any forbids one, stop and say so at the top of the result.

## How it must be drawn

The page's and the collection screen's existing components and tokens: the subject header, the
panels and rows the collection screen uses, `SubjectChip` pills, the page's existing dialog
for a confirmation. Layout, content and words are iOS's. Navigation and chrome controls are
Android's own: the top buttons are the shared `ToolbarCircleButton` (a plain Material icon
button) and `ToolbarAddButton`. No stock Material chips, cards in default colours, or default
Material colours anywhere: tokens only. Light, Dark, Sepia and OLED; every text with a line
height; rows that reflow at `isAccessibilityFontScale()`.

## Demo and tests

- The demo must answer the reads and the POST locally (`network/ao3/DemoNetwork.kt`, fixtures
  under `app/src/debug/assets/fixtures/`, original filler only): the demo's collection (Winter
  Exchange 2026) with a handful of items in each state, a submit that succeeds, and one item
  whose decision AO3 refuses. Say how to reach it on the emulator.
- Tests, none reaching the network: the items parser on the fixture; the form built from the
  served page with staged choices; exactly one POST per confirmed submit and none on discard;
  success and refusal each leave the list as AO3 answered; states; a session that changes
  while the request is out does not touch the list.
