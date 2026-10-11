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
| A collection's tile drew its small cover | Android | `b0b90361` |
| A collection page's "Hidden mature work" card still showed fandom, author, words, chapters | Android | `b0b90361` |
| **Home › Reading Queues: a queue's card named its next work (fandom and title), in Hide mode too** | Android | lead 1, confirmed on the emulator, fixed |
| The same card | iOS | T-393 |

## Round two, 2026-10-11 (Hide mode looked at on both, `-matureContentMode hide` on iOS, Settings › Privacy on Android)

| Where | Platform | Result |
|---|---|---|
| **A collection's page showed a work Hide mode hides, in full** (title, author, fandoms, rating) | iOS | confirmed on the simulator; fixed, T-394 |
| The Library's filter lists (Fandoms, Characters, tags, Language) offered what only hidden works carry | iOS | confirmed on the simulator; fixed, T-394 |
| The same lists | Android | looked at in Hide mode: already right (`collectionMembers` has no hidden work) |
| A collection's Reorder drew hidden works | both | off while a work is hidden ("Show Mature to Reorder"), the queue page's rule: iOS T-394, Android this commit |
| Home's queue card, a collection's tile and page, in Hide mode | Android | looked at: right |

Blur mode's three open choices (the Reorder screen, a search or filter answering for a
blurred work, a blurred work's tags in lists) are **owner question 23**, not faults: the
2026-10-08 decision draws a matching blurred work blurred, and the iPhone's code marks the
Reorder screen as the owner's to decide.

## Round three, 2026-10-11: iPhone files that name a saved work and never mention the gate

Nine of thirty (`work.title` with no `gate`, `isHidden`, `SensitiveWorkRow`, `hideMature`).
The queue organizer's search was a fault (above). `RecentlyDeletedView` names a deleted
mature work in both modes, on both apps: owner question 23, item 4. The rest are fed an
open work or an already-filtered list (the reader, Work Details' parts, swipe actions'
confirmations, the remote-work bar, `StackedWorkCover`, `HomeCards`' plain card, which is
drawn through the blur wrapper in `MatureContent.swift`). **Not done the same way for
Android** (grep `\.title` in files with no `LibraryPrivacy` or `privacyVisibility`).

The same listing for Android (composable files that name a `SavedWork` title with no
`LibraryPrivacy`, `privacyVisibility`, `obscured`): ten of twenty-one. New from it:

- **Queue Storage** (`settings/QueueStorageScreen.kt`; iOS `ReadingQueueStorageView` in
  `ReadingQueues.swift`) names every work the queues keep, in both modes, on both apps. Not
  looked at on screen. Owner question 23, item 4, with Recently Deleted.
- `account/LocalLibraryListsScreen.kt` (local History and Favorites, by title, no privacy
  check at all) is **unreachable**: nothing navigates to `Routes.LocalHistory` or
  `Routes.LocalFavorites`. Dead code that would leak if a link to it came back. P3: delete
  it, or gate it, when the Account tab is next touched.
- The rest are fed an open work, a selection, or an already-filtered list.

**A limit of both listings:** they are per file. `ReadingQueues.swift` counted as "mentions
the gate" because of the card fixed in T-393, and hid `ReadingQueueStorageView` in the same
file. A pass per view (struct or composable function) would be surer.

## Round four, 2026-10-11: the pass view by view (both)

A script splits each file into its views (Swift top-level types; Kotlin composable
functions) and lists those that use a saved work's title with no privacy word in the view
itself. iPhone 16, Android 11. Two more faults, both seen on screen before fixing:

| Where | Platform | Result |
|---|---|---|
| A collection's row in the Library's **Ledger** layout drew a blurred work's miniature cover, title and author | iOS | fixed, T-396 (the tile's rule) |
| **The Library's Select mode listed an obscured work by title and author** | Android | fixed: the row says "Hidden mature work" and can still be selected (`LibraryPrivacy.shownTitle`) |

The rest of both lists: components whose caller checks (the cover cards, the resume hero's
body, the miniature and mosaic covers), an open work (the reader, Work Details), the
remote-work rows, and what owner question 23 holds (the Reorder screen, Queue Storage,
Recently Deleted). Android's `LocalWorkRow` is the unreachable screen noted above.
**Not done:** the same pass for views that show an author, a fandom or a summary without a
title; the iPhone's 13 Hide-only call sites looked at one by one in Blur mode.

## Leads, not confirmed (read only)

Android:
1. ~~Home › Reading Queues~~ **confirmed and fixed** (`HomeFacts.queueFace`): a hidden work
   is passed over, an obscured one is "Hidden mature work" with no fandom and no colour of
   its own. Seen on the emulator before, after, and after "Show mature".
2. ~~The Library filter panel~~: Hide mode right; Blur mode is owner question 23.
3. ~~A collection page's filter field~~: owner question 23 (a match is drawn obscured).
4. ~~The queue organizer's search~~ **fixed on both** (iOS T-395; Android
   `ReadingQueueFacts.matchesSearch(mayAnswer)`): in Hide mode a hidden work's title no
   longer finds the queue it is in. Seen on both in Hide mode after the fix.
5. Anything else that maps `collectionMembers` or a queue's works to names.

iOS:
6. (Two of these turned out to be missing the filter altogether, not in this list: a
   collection's page and the Library's filter panel. **Worth a second grep for works lists
   with no `gate` at all**, which a search for `isHidden(` cannot find.)
   The other 13 call sites that filter only `gate.isHidden` (grep `isHidden(`): Home and its
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
