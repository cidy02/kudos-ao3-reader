# Brief 3gw (Android): what the first 35 side-by-side screens found

**Write code in this worktree only (`/Users/cidy02/kudos-agent-codex`, branch
`android/agent-codex-3gw`). Do not commit, push, switch branches, sign in, contact
archiveofourown.org, or run Gradle (Claude builds and tests).** Do not edit `TASKS.md`. Create
`docs/android-port/briefs/3gw-result.md` FIRST; for each item give `path:line`, what you changed,
and for each test what it does with the change reverted.

Two independent Gemini reviews of the same screenshots agree on these (both in
`docs/android-port/audits/A82a-result.md` and `A82a2-result.md`; the screens are named in
`audits/A82-shots.md`; the tiles, iPhone row above Android row, are
`/Users/cidy02/kudos-tools/pairs/tiles-a82/<name>.png`). iOS is the reference:
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`. For each item read the iOS view first; make
Android show the same content in the same order with Android's own Material chrome (owner rule).
Keep anything DECISIONS.md says Android keeps. If an item is wrong on reading the code, say so
and skip it.

1. `queuesettings`: at the largest text the breadcrumb ("HOME › QUEUES › QUEUE DETAILS") is cut
   with "…"; iOS wraps it. Let it wrap.
2. `queuetagedit` (edit one queue tag): iOS order is Name, MERGE INTO ANOTHER TAG, then a
   **REMOVE** section holding "Remove from this queue". Android puts Remove first with no header.
3. `bulktag` (tagging selected works): iOS `UIComponents/WorkBulkTagSheet.swift` is titled "Tag",
   says "Your changes apply to all N selected works.", and marks each tag with a leading
   selection mark; Android shows the queue-tag sheet's title, caption and a trailing "All ✓".
   Match iOS's sheet for a selection of works.
4. `addtoqueue`: iOS's rows have leading queue icons and the new-queue field and Add share one
   row; match. Android's extra "Series" section (Also add works from this AO3 series): keep it
   only if DECISIONS.md records it as Android's; otherwise report it, do not remove it.
5. `collectiondetails` (a collection's details sheet): iOS titles it with the collection's name
   and orders COLOUR above DESCRIPTION; match. Android's NAME field: if iOS renames a collection
   elsewhere, say where; do not remove a way to rename.
6. `fandomworks`, `tagworks`: at the largest text the "Date Updated" sort control is crushed into a
   one-letter-wide column beside the title; iOS moves it below. Lay it out the same way.
7. `fandomfilter`: iOS's sheet has a pinned bottom button "Show N tags"; add it (same effect as
   closing the sheet with the choices applied).
8. `pagejump`: iOS `Features/Search/SearchPaginationBar.swift` `PageJumpSheet`: title "Go to page",
   a PAGE NUMBER field, NEARBY page buttons, First page / Last (N). Android shows a large
   "1 / of 3" readout, a caption and a slider instead; make it iOS's sheet.
9. `tagpicker`: with nothing typed, iOS shows a **Selected** section (the chosen tags with their
   include/exclude state) and "Type above to search AO3 fandoms." under Results (popular tags only
   when there is fandom context); Android omits Selected and lists fandoms. Match.
10. `readercontents`: iOS `ReaderContentsSheet.swift:135-165` offers Go, Bookmark and Add Note as
    **swipe actions** on a chapter row (Bookmark and Add Note only once the chapter's position is
    known); Android draws Bookmark and Add Note as buttons on every row, which squeezes the titles
    to two letters at the largest text. Use the app's existing swipe-action component (as the
    Library's rows do) instead of inline buttons.
11. `pronunciations`: iOS centres "No corrections yet" and keeps Add Pronunciation, Paste
    Corrections and Copy All in the top-right ··· menu; Android lists them inline. Match, and keep
    Android's paragraph that the voice pack does not play corrections yet (true on Android).
12. `pronunciationedit`: Android shows each label above the field and again inside it; iOS uses
    section headers and placeholders ("Word", "her-MY-oh-nee"). Match.
13. `customizetheme`: iOS picks the theme with four round "Aa" swatches drawn in each theme's
    colours, and its preview card shows two paragraphs fading out; Android uses a text segmented
    bar and shows a third paragraph. Match.

Tests (Robolectric/JVM, as the suite's others) for 2, 3, 7, 8, 9 and 10 at least; each must fail
with its change reverted. Nothing else changes.
