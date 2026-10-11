# Audit A38: every place that names a work the privacy setting is keeping back

Opened 2026-10-11 by Claude after finding four such places in one sitting (below). Both
platforms. **Read, then look; fix only what is confirmed on screen.** P1 where a title or an
author is shown; P2 where only an aggregate (a fandom, a count, a search match) gives it away.

## The rule

iOS `PrivacyGate.isBlurred`: "until it is revealed, nothing may open it or name it." Hide mode
drops a work from lists; Blur / Obscure (the default on both) draws it as a blurred card or as
"Hidden mature work". A place with **no such card** (a picker row, a tile's small cover, a
deck's "up next" line, a search answer, a facet list) must leave the work out. iOS:
`PrivacyGate.isConcealed`; Android: `LibraryPrivacy.visibility(...) == Visible`,
`LibraryPrivacy.nameableWorks`, `AddLibraryWorks.eligible`.

## Fixed 2026-10-11

| Where | Platform | Commit |
|---|---|---|
| "Add Works" in a collection and in a queue named the work (title, author, search) | Android | `cf33b96a` |
| The same sheet, in Blur mode only | iOS | T-392 |
| A collection's tile drew its small cover (title, author) | iOS | T-392 |
| A collection's tile drew its small cover | Android | this commit |
| A collection page's "Hidden mature work" card still showed fandom, author, words, chapters | Android | this commit |

## Leads, not confirmed (read only)

Android:
1. **Home › Reading Queues.** The queue card names its "up next" work, title and fandom, from
   `repo.listWorks(queue.id)` with no privacy check (`home/HomeScreen.kt:132`,
   `home/HomeQueueCard.kt` `HomeFacts.upNext`). The first screen of the app.
2. The Library filter panel is given `state.collectionMembers`, obscured works included
   (`library/LibraryScreen.kt:596`): do its fandom and tag lists count them?
3. A collection page's filter field matches an obscured work by title and author
   (`library/CollectionDetailScreen.kt`, `visibleWorks`): typing a title leaves its card.
4. The queue organizer's "Search queues, tags and works" and the queue page's filters.
5. Anything else that maps `collectionMembers` or a queue's works to names.

iOS:
6. The other 13 call sites that filter only `gate.isHidden` (grep `isHidden(`): Home and its
   section lists, Library and its section lists, Search (`SearchView.swift:510`), series and
   author pages' "in your library" rows, Work Details' other works, the availability sweep,
   the reading-queue browser. By reading they hand works to cards that blur; none was looked
   at for this.
7. The reading-queue card on Home and in the browser: does its deck name the next work?

Both: the Collections list tile's count, and a queue's count, still count a concealed work.
That is deliberate (a count names nothing).

## Not part of this

A collection's picker on Android offers only kept works (`observeSavedWorks`), where iOS
offers every Library work that is not queue-only: a parity question, not a privacy one.
