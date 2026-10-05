# Brief 3aw: the collection's Moderation screen (the hub), and where its row leads

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result, and if a question remains, ask it at once and stop rather than guess. Write
`docs/android-port/briefs/3aw-result.md` as you go.

Read first: `briefs/3as-result.md` and `briefs/3at-result.md` with their landing notes (the
pattern for an AO3 screen with writes on Android, and what was corrected on landing), and
`docs/AO3_NETWORKING_POLICY.md`.

## What is wrong

On iOS a collection's Manage › Moderation opens `CollectionModerationView`
(`Features/Challenges/CollectionModerationView.swift`, artboard 1cd): everything AO3 gives a
maintainer in one scroll. On Android that row opens the collection items screen (brief 3as),
which on iOS is reached from inside the Moderation screen ("Recently decided") and from the
collections list. Android has no Moderation screen. That was Claude's brief's mistake, not
yours.

## Build

Start the result with what iOS has, read from the code: each section in order with its header
and count; each row's content; every action with its words; every confirmation dialog with its
exact text and buttons, and which actions have none; what the owner sees that another
maintainer does not (`viewerIsOwner`); the loading, empty and failure states and their words;
paging of the review queue; what each action reads and sends (`collectionModeration`,
and the writes in `AO3CollectionActions.swift`), and how success is recognised.

Then build it on Android as its own screen, and make Manage › Moderation open it. Its
"Recently decided" row opens the existing items screen on the tab iOS opens it on. The
maintainers summary row opens what iOS opens if Android has it; if Android has no maintainers
screen yet, the row opens AO3's page as the Manage row does today, and say so (the maintainers
screen is a later brief; do not build it here).

## Rules for the network

- Reads: what iOS reads when the screen opens, on pull-to-refresh, and for a page of the queue.
  Count the requests iOS makes for one opening and make the same ones, through the existing
  authenticated client and coordinator, nothing in the background.
- Writes: each action is one request, sent only by the reader's tap (after iOS's confirmation
  where iOS has one), through `AO3WriteRepository` on the path 3an, 3as and 3at use: the token
  from where iOS takes it, the session generation checked on entry and after any read, never
  retried, success recognised as iOS recognises it, AO3's refusal shown in its own words. A
  second tap while one is out sends nothing.
- If the policy forbids any read or write here, stop and say so at the top of the result.

## How it must be drawn

The subject header, `SectionRuleHeader`-style section headers with counts, the collection
panels and rows, `SubjectFormRow` and the settings action rows this app already has (read
`account/AO3CollectionItemsScreen.kt`, `account/AO3CollectionDetailScreen.kt`,
`settings/SettingsChrome.kt`). Layout, content and words are iOS's. Dialogs are the app's
existing themed `AlertDialog` use (see the collection form's delete dialog). The screen has no
top buttons unless iOS's has. Tokens only: no stock Material chips, cards or default Material
colours. Light, Dark, Sepia and OLED; every text with a line height; rows that reflow at
`isAccessibilityFontScale()`.

## Demo and tests

- The demo answers every read and write locally (`network/ao3/DemoNetwork.kt`, fixtures under
  `app/src/debug/assets/fixtures/`, original filler only) for Winter Exchange 2026: a review
  queue of two pages, two membership requests, a maintainers count, unrevealed and anonymous
  both on; one approve that succeeds and one that AO3 refuses; accept and decline; reveal.
  Say how to reach each on the emulator.
- Tests, none reaching the network: the parsers on the fixtures; each request built (address,
  fields, method override, token); one request per tap and none on Cancel or on a second tap;
  a refusal shown and nothing changed locally; a session that changes while a request is out
  does not touch the screen; the owner-only controls absent for a non-owner; the Moderation row
  opening this screen and "Recently decided" opening the items screen.
