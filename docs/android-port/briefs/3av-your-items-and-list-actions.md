# Brief 3av: "Your items", and the collections list's per-collection actions

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result, and if a question remains, ask it at once and stop rather than guess. Write
`docs/android-port/briefs/3av-result.md` as you go.

This continues brief 3at. Its form landed (`42feabf2`); read the landing note at the top of
`briefs/3at-result.md` for what was corrected (no extra top buttons; AO3's refusal said once;
the text field row's alignment), and re-read the files on disk: they are not as you left them.
Read `briefs/3as-result.md`'s landing note too: `AO3CollectionItemsScreen` is the screen this
brief reuses.

## 1. "Your items"

On AO3 Collections (`account/AO3CollectionsScreen.kt`) the "Your items" chip does nothing. On
iOS it opens `AO3CollectionItemsDestination(slug: nil, title: "Your items")`: the same items
screen in account scope (`AO3CollectionsList.swift`, `AO3CollectionItemsView.swift`,
`updateUserCollectionItems` in `AO3CollectionActions.swift`). You described it at the end of
`3at-result.md`. Build it by giving the existing Android items screen its account scope, not
by writing a second screen: the same staging, the same Submit, what differs is what iOS makes
differ (the address read, the tabs and their defaults, which controls the reader may change as
a creator rather than a maintainer, the subtitle, the request each staged change sends). Start
the result with that list of differences as iOS's code has them.

The write follows the same rules as the collection scope: read `updateUserCollectionItems`
and match it (one request per staged item or one for all: say which, and do what iOS does),
through `AO3WriteRepository`, the session checked as there, never retried. Read
`docs/AO3_NETWORKING_POLICY.md` and say which rules cover it. Android keeps its question
before sending ("Submit N staged changes to AO3?") here too, as in the collection scope.

## 2. The list's per-collection actions

iOS's list offers actions on a collection's row (find them in `AO3CollectionsList.swift`:
`editDestination(for:)` and `itemsDestination(for:)`, and whatever shows them: swipe actions,
a context menu, which collections get which). Android's rows have none. Add them in Android's
own idiom for row actions (read how other lists in this app do it: a long-press menu or the
row's overflow; no iOS swipe-action look), under iOS's conditions, opening the edit form and
the collection's items screen that already exist.

## How it must be drawn

Nothing new to draw: the items screen, its cards and the shared menu components as they are.
Tokens only; no stock Material chips, cards or default Material colours.

## Demo and tests

- The demo answers the account-scope reads and writes locally (`network/ao3/DemoNetwork.kt`,
  fixtures under `app/src/debug/assets/fixtures/`, original filler only): a page of the
  reader's own items across two collections with at least one awaiting the reader's approval,
  one accepted change and one refused. Say how to reach it on the emulator.
- Tests, none reaching the network: the account-scope address and parser on the fixture; what
  a creator may and may not change; the request(s) built; exactly the requests iOS sends, in
  order, none after a refusal; the row actions' conditions.
