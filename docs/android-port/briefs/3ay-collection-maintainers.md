# Brief 3ay: the collection's Maintainers screen

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result, and if a question remains, ask it at once and stop rather than guess. Write
`docs/android-port/briefs/3ay-result.md` as you go.

Read first: `briefs/3as-result.md`, `briefs/3at-result.md` and `briefs/3av-result.md` with their
landing notes (the pattern for an AO3 screen with writes on Android, and what was corrected on
landing: no invented top buttons, AO3's refusal said once, the text field row), and
`docs/AO3_NETWORKING_POLICY.md`. If `briefs/3aw-result.md` exists, read it too: the Moderation
screen has a row that should open this one.

## What is missing

On a collection the reader maintains, Manage › Maintainers opens AO3's page in the browser. iOS
has the screen: `Features/Challenges/CollectionMaintainersView.swift` (artboard 1bx): owners
and moderators, invitations, inviting an account by username as a moderator or an owner, and
stepping down, with the rule that the last owner cannot leave.

## Build

Start the result with what iOS has, read from the code: each section in order with its header;
each row's content and any action on it, with its words; the invite field, the role choice and
the button with its exact words in each state; every confirmation dialog with its exact text
and buttons; the last-owner rule and its words; what the owner sees that a moderator does not;
loading, empty and failure states; what each action reads and sends (find the reads in
`AO3Client+Collections.swift` and the writes in `AO3CollectionActions.swift`), and how success
is recognised.

Then build it on Android as its own screen and make Manage › Maintainers open it, and the
Moderation screen's maintainers row too if that screen has landed.

## Rules for the network

- Reads: what iOS reads when the screen opens and on pull-to-refresh, the same requests,
  through the existing authenticated client. Nothing in the background, no lookup of a
  username while it is being typed unless iOS makes one (say what iOS does).
- Writes: each action is one request sent only by the reader's tap (after iOS's confirmation
  where iOS has one), through `AO3WriteRepository` on the path 3an, 3as, 3at and 3av use: the
  token from where iOS takes it, the session generation checked on entry and after any read,
  never retried, success recognised as iOS recognises it, AO3's refusal shown once in its own
  words. A second tap while one is out sends nothing.
- If the policy forbids any read or write here, stop and say so at the top of the result.

## How it must be drawn

The subject header, section headers as the items and Moderation screens have them, the
collection panels and rows, `SubjectFormRow`, `SubjectTextFieldRow` (the invite field: read how
the collection form uses it) and the settings action rows (`settings/SettingsChrome.kt`).
Layout, content and words are iOS's. Dialogs are the app's themed `AlertDialog` use. No top
buttons unless iOS's screen has them. Tokens only: no stock Material chips, cards or default
Material colours. Light, Dark, Sepia and OLED; every text with a line height; rows that reflow
at `isAccessibilityFontScale()`.

## Demo and tests

- The demo answers every read and write locally (`network/ao3/DemoNetwork.kt`, fixtures under
  `app/src/debug/assets/fixtures/`, original filler only) for Winter Exchange 2026: two owners
  (the reader one of them), two moderators, one pending invitation; an invitation that
  succeeds and one AO3 refuses (an unknown username); stepping down allowed. A second
  collection where the reader is the only owner, to see the last-owner rule. Say how to reach
  each on the emulator.
- Tests, none reaching the network: the parser on the fixtures; each request built (address,
  fields, method override, token); one request per tap, none on Cancel or a second tap; a
  refusal shown once and nothing changed locally; the last-owner rule; a session that changes
  while a request is out does not touch the screen; the Manage row opening this screen.
