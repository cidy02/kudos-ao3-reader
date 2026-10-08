# Brief 3bk: a prompt meme's Claim and Release

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
questions", and keep going to the end. Write `docs/android-port/briefs/3bk-result.md` as you go.

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

Read first: `briefs/3bi-result.md` **with its landing note** (the Prompts screen as it stands:
`account/AO3PromptMemeScreen.kt`, `account/AO3PromptMemeState.kt`,
`network/ao3/account/AO3PromptMeme.kt`; both writes as you recorded them there; the owner's
rule for the close date), `briefs/3bg-result.md` with its landing note (how the tag set's two
writes were built, read against iOS and tested: one fresh token, one POST never retried, the
screen changed only on AO3's confirmation, the address posted to must be AO3's own host), and
`docs/AO3_NETWORKING_POLICY.md`: say which rule allows each write.

## What is missing

The Prompts screen reads and cannot act. iOS's `Features/Challenges/PromptMemeView.swift` has
two writes, Claim and Release (`AO3ChallengeActions.claimPrompt`, `releasePrompt`). This brief
is those two and nothing else. "New prompt" (the sign-up form) is a later brief.

## Build

Start the result by reading both writes again from iOS's code, line by line: who sees each
control and in which state of a prompt; the request or requests, in order, with every field
name and value and where each comes from; the headers; what counts as AO3's confirmation and
what as a refusal; each message, word for word; what the screen shows while it waits; what
iOS reads after a success and why; what is never retried. Quote iOS's code for the verdict.

Then build them on Android.

- **Claim** on an unclaimed prompt, **Release** on one the reader has claimed, drawn and
  worded as iOS. One fresh token read and one POST each, as iOS; the card changes only on
  AO3's confirmation; while one is in flight the others are disabled, as iOS; a refusal
  leaves the card as it was and shows iOS's sentence with AO3's reason.
- **After a success** iOS loads the current page again. Do the same: one read of that page.
  It must not ask for the close date again (`readsPromptMemeSchedule`: only for an owner,
  only until a date is known, once per opening or refresh).
- **Never** a retry, a second POST, or a write on opening or on a page turn.
- Through the app's existing authenticated client and write path, as 3bg did; no new HTTP
  code. Any address taken from AO3's page is used only when it is AO3's own host
  (`AO3RedirectCookieRelay.isTrustedUrl`).

## How it must be drawn

As the screen is today, with iOS's layout and words for the two controls. Tokens only: no
stock Material chips, cards or default Material colours. Light, Dark, Sepia and OLED; every
new text with a line height; nothing clipped at `isAccessibilityFontScale()`.

## Demo and tests

- The demo answers both writes locally for Summer Prompt Meme (`network/ao3/DemoNetwork.kt`):
  a Claim that succeeds and one AO3 refuses; a Release that succeeds; the page read after a
  success showing the new state. Relaunching resets it. Say the taps.
- Tests, none reaching the network: each request field for field against iOS's (a recording
  client); exactly one token read and one POST per write; each verdict (confirmed, refused
  with AO3's text, an unconfirmed 2xx, a failed token read, signed out) with iOS's words; the
  card unchanged until confirmation; other controls disabled while one is in flight; the one
  page read after a success and no schedule read with it, for an owner and for a participant;
  nothing sent on opening, on a page turn or on refresh.
