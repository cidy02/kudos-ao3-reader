# Brief 3bg: a challenge's tag set, its two writes (Add tags, Reject)

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
`docs/android-port/briefs/3bg-result.md` as you go.

Read first:
- `briefs/3be-result.md` **with its landing note**: the tag set screen as it stands
  (`account/AO3TagSetScreen.kt`, `account/AO3TagSetState.kt`,
  `network/ao3/account/AO3TagSet.kt`, `getTagSet` in
  `account/AO3CollectionDetailRepository.kt`), both iOS writes as you recorded them there, and
  why the four Tags rows open nothing today.
- `briefs/3an-result.md`, `briefs/3aw-result.md` and `briefs/3ay-result.md` with their landing
  notes: how a write to AO3 is built, confirmed and tested on Android (one fresh token, one
  POST never retried, the screen changed only on AO3's confirmation, iOS's exact words for
  each verdict; the demo answers a POST locally and the in-app browser cannot reach the
  network).
- `docs/AO3_NETWORKING_POLICY.md`: say which rule allows each write.

## What is missing

The tag set screen reads and cannot act. iOS's `Features/Challenges/TagSetView.swift` has two
writes: **Save tags** in its Add tags editor (`saveTagSetFields`) and **Reject** on a
nomination awaiting review (`reportRejectedTag`). This brief is those two and nothing else.

## Build

Start the result by reading both writes again from iOS's code, line by line, and setting them
out: who may see each control; the taps that lead to it; the request or requests made, in
order, with every field name and value and where each value comes from; what is sent when a
field is empty; the headers; what counts as AO3's confirmation and what as a refusal; each
message, word for word, in each case; what the screen shows while it waits and after; what is
never retried. Quote iOS's code for the verdict.

Then build them on Android.

- **Add tags.** The four Tags rows open iOS's Add tags screen: its header, the four fields
  with iOS's labels and placeholders, the footnote, **Save tags**. The fields are text rows of
  the kind the AO3 collection form already has (`account/`, brief 3at); do not make a new
  kind. The fields start with what AO3's edit form served (normally empty). Save is one fresh
  read of the edit page for its token and one POST, as iOS; the screen says "Tags saved."
  only on AO3's confirmation; a refusal keeps what was typed and shows AO3's reason.
  **Who gets the editor:** as iOS decides it, read from the code; if the edit form was refused
  on opening (the demo's tag set 44) say what iOS does and do the same.
- **Reject.** A nomination awaiting review has iOS's Reject control. One fresh read of the
  nominations page for its token and one POST, as iOS, with iOS's encoding of the tag's name
  (the bracket replacement included). The row becomes Rejected and the three counts change
  only on AO3's confirmation. While one is in flight the others are disabled, as iOS.
- **Never** a retry, a second POST, a write on opening, or a read after a successful write
  that iOS does not make.
- Both go through the app's existing authenticated client and write path. Find how 3aw and
  3ay did it and do it the same way; no new HTTP code.

## How it must be drawn

As the screen is today (`tokens.scopePalette`, the challenge sections and rows, the app's
chips), with iOS's layout and words for the two new parts. The top row's buttons are the app's
Material icon buttons; Save tags is drawn as the collection form's primary action is. Tokens
only: no stock Material chips, cards, text-field decoration or default Material colours.
Light, Dark, Sepia and OLED; every new text with a line height; nothing clipped at
`isAccessibilityFontScale()`; long lists lazy.

## Demo and tests

- The demo answers both writes locally (`network/ao3/DemoNetwork.kt`; today it refuses every
  POST to a tag set with 405: replace that for these two addresses only): tag set 42 accepts
  Save tags unless a field holds a name you choose for the purpose, which AO3's local answer
  refuses with a message naming the list it came from; Reject succeeds for one nomination
  and is refused for another. Relaunching the demo resets it. Say the routes and the taps.
- Tests, none reaching the network: each request field for field against iOS's (a recording
  client), including empty fields and a tag name with brackets; exactly one token read and one
  POST per write, never two; each verdict (confirmed, refused with AO3's text, an unconfirmed
  2xx, a failed token read, signed out) with iOS's words; the screen unchanged until
  confirmation and changed after; other Reject controls disabled while one is in flight;
  nothing sent on opening or refresh. Compose tests here need a tall window for lazy lists,
  patient waits, and `@GraphicsMode(NATIVE)` when they ask about text; the repository takes
  `parseDispatcher = Dispatchers.Unconfined` in them.
