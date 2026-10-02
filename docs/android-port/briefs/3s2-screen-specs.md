# Brief 3s-2: porting specs for queues, collections, Recently Deleted and Browse

You may create or edit only `docs/android-port/specs/queues.md`, `collections.md`, `recently-deleted.md` and `browse.md`.
Do not touch code, git or the network.

These specs will be handed to another coding agent that rebuilds each Android screen as the iOS
app draws it. The rule (owner decision): **iOS code is the source of truth**. The design spec
(`docs/design/Final_Redesign_Spec.dc.html`, artboards `<div class="dv-opt" id="1b">` etc.) only
fills in details iOS leaves open. Android's design system already exists in
`android/app/src/main/java/io/github/cidy02/kudos/ui/subject/` (read `docs/android-port/briefs/1a-result.md`
for the iOS → Kotlin names).

For each area below:
- **Queues** (`queues.md`): iOS `kudos-ao3-reader/Features/Library/ReadingQueue*.swift`,
  `NewReadingQueueSheet.swift` (New and Edit Queue), `QueueCardMenu.swift`, `QueueTag*.swift`;
  artboards 1h, 1i, 1j, 1bg, 1bh.
- **Collections** (`collections.md`): `Collections.swift`, `NewCollectionSheet.swift`,
  `CollectionLedgerRow.swift`; artboards 1bk and 1c's collections section.
- **Recently Deleted** (`recently-deleted.md`): `RecentlyDeletedView.swift`; artboard 1bj. Note
  that Android already has the two sections' behaviour (commit 2d8d6290); spec the look.
- **Browse** (`browse.md`): `Features/Browse/*`, `Features/Search/MediaBrowserView.swift`,
  `MediaBrowserJumpBackIn.swift`, `FandomListView.swift`, `FandomFamilyRows.swift`; artboards 1g, 1al,
  1am, 1an.

write one spec each with these sections:

1. **Screen tree.** The top-down structure of the iOS screen: each section, in order, with the
   iOS view or file that draws it, and what it shows when empty, collapsed, or in select mode.
2. **Components.** Each iOS component used (`SubjectHeaderBlock`, `SectionRuleHeader`, cover cards,
   ledger rows, the queue deck card, the resume hero, chips, rings, and so on) with its key sizes,
   paddings, fonts, colours and opacities as the iOS code sets them, and the matching
   `ui/subject` Kotlin component (or "missing: build it").
3. **Data.** Where each section's data comes from on iOS (queries, sort order, limits, filters)
   and the closest Android repository or ViewModel source today
   (`android/app/src/main/java/io/github/cidy02/kudos/home/`, `library/`).
4. **Interactions.** Taps, long-press menus (each item, its label and action), swipe actions,
   See all, select mode and its bulk bar, the toolbar buttons (top right; at most four), and the
   pull-to-refresh behaviour.
5. **Strings.** Every user-visible string verbatim, including empty states and menu labels.
6. **Owner decisions** that shaped the iOS screen (search the iOS code for comments like
   "owner, 2026-" and TASKS.md rows): one line each.
7. **Android gaps.** What Android lacks to draw this, as a short list.

Cite iOS file:line for every non-obvious claim. Don't invent anything: if unsure, write "UNSURE"
and say what would settle it. About 1,500 to 2,500 words each.
