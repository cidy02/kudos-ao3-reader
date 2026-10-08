# Brief 3bl: a challenge sign-up, the form and Save

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
questions", and keep going to the end. Write `docs/android-port/briefs/3bl-result.md` as you go.

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

Read first: `briefs/3bi-result.md` and `briefs/3bk-result.md` **with their landing notes** (the
prompt meme screen, whose "New prompt" is this form, and how its two writes were built and
checked), `briefs/3bg-result.md` with its landing note (a challenge form with a Save: one
fresh token, one POST never retried, the screen changed only on AO3's confirmation, an
address taken from AO3's page used only when it is AO3's own host), `briefs/3bb-result.md`
with its landing note (a form kept whole: what AO3 served that the app does not understand
goes back as served), and `docs/AO3_NETWORKING_POLICY.md`: say which rule allows each read and
the write.

## What is missing

On a challenge collection, "Your Sign-up" (`account/AO3CollectionDetailScreen.kt`) and the
prompt meme's New prompt open AO3's page in the browser. iOS has the screen:
`Features/Challenges/ChallengeSignUpView.swift` (artboard 1ca), with
`AO3Client+Challenges.swift` (`challengeSignUpForm`, `ownChallengeSignUp`,
`parseChallengeSignUpForm`, `challengeSignUpParameters`) and
`AO3ChallengeActions.saveChallengeSignUp`. This brief is the form and its **Save**.
**Withdrawing a sign-up** (`withdrawSignUp`, `withdrawSignUpAfterClose`) is a later brief:
read both, set them out for it, build neither.

## Build

Start the result with what iOS has, read from the code: how the screen is reached and for
whom; the header and its words in each case (a new sign-up, an existing one, a gift exchange,
a prompt meme, sign-ups closed); every section in order; every field of a request and of an
offer (tags of each kind and where their choices come from, "any", the description, the URL,
anonymity, title) with its label, placeholder and limits; how prompts are added and removed
and the limits on their number; every validation iOS makes before sending, with its exact
words; **each read**, which address, when, and what the screen shows when it fails; **the
write**, line by line: the request or requests in order, every field name and value and where
each comes from, what is sent for a field left empty, what happens to fields AO3 served that
the form does not show, the headers, what counts as confirmation and as refusal, each
message word for word, what the screen does after, and what is never retried. Quote iOS's
code for the encoder and the verdict. Then both withdrawals, for the later brief.

Then build it on Android and make "Your Sign-up" and New prompt open it.

- **The form is kept whole**, as 3bb's work form is: every control AO3 served is kept;
  fields iOS sends go out iOS's way; anything else AO3 served goes back as served. If iOS's
  encoder drops something a browser would send, do what 3bb did and list each case in a
  table at the top of the result with whether it can change a sign-up the reader did not
  touch.
- **Reads:** the ones iOS makes for one opening and no more; count them first. Signed out
  reads nothing. If AO3 will refuse the viewer (sign-ups closed and no sign-up of their own),
  show what iOS shows and do not ask twice.
- **Save:** one fresh token read if iOS makes one, one POST, never retried; the screen
  changes only on AO3's confirmation; a refusal keeps everything typed and shows AO3's
  reasons as iOS does; validations before sending are iOS's, with iOS's words.
- **No withdrawal**: where iOS draws that control, leave it out and list it.

## How it must be drawn

Layout, content, order and words are iOS's (1ca). The challenge screens' sections and rows,
the collection form's text field row, the work form's tags editor components where a field
takes tags, `tokens.scopePalette`. The top row's buttons are the app's Material icon buttons;
Save is drawn as the collection form's primary action is. Tokens only: no stock Material
chips, cards, text-field decoration or default Material colours, and **no new colour token**:
a refusal uses `SubjectPalette.fromHue(0.0, tokens.theme).accent`, as the tag set screen
does. Light, Dark, Sepia and OLED; every new text with a line height; nothing clipped at
`isAccessibilityFontScale()`; `statusBars + 76dp` above the header; long lists lazy; fields
stay above the keyboard.

## Demo and tests

- The demo answers the form's reads and its Save locally (`network/ao3/DemoNetwork.kt`,
  fixtures under `app/src/debug/assets/fixtures/`, original filler only; one answer per
  address, shared with whatever already reads it): a new sign-up for Winter Exchange 2026
  (requests and offers, with tags from its tag sets), an existing sign-up there, and a new
  prompt for Summer Prompt Meme (requests only); a Save that succeeds and one AO3 refuses
  with reasons. Relaunching resets it. Say the routes (one argument each) and the taps.
- Tests, none reaching the network: the parser on each fixture; an untouched form encoded
  against what a browser would send, as 3bb's round trip (same three comparison rules, no
  others); each kind of change against iOS's encoder; each of iOS's validations with its
  words; the reads for one opening, counted; exactly one token read and one POST per Save;
  each verdict with iOS's words; the screen unchanged until confirmation; nothing sent on
  opening; both entry points opening the screen; no withdrawal control present.
