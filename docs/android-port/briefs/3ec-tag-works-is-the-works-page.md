# 3ec: a tag's works page is the redesigned works page (Android)

Done 2026-10-14 by Claude, alone. Gate 2,658. Pictures: `shots/3ec/` (before, after).
Follows 3eb, which made a tag tapped in a work open this page.

iOS's `TagWorksView` is the same page as `FandomWorksView` (the results' head with its
figures and sort, pagers above and below, ledger rows) and says "tag" where the other
says "fandom". Android's `TagWorksScreen` was the old design (a plain bar, a refine field,
the old summary card), never reached until 3eb and never redesigned. Both load the same AO3
address (`/tags/<name>/works`). So the tag route opens `FandomWorksScreen` with
`isTag = true`, which words its empty states for a tag as iOS does, and `TagWorksScreen`
(370 lines) is gone. `Brief3caScreenTest`'s row 6 is two tests now, one per wording.

Lead: that test swapped the tag page for the fandom page in place, and the new page's Filter
button (shown through `PushedShellChrome`) then opened nothing. It looks like the departing
page's registration outliving it. Not seen in the app, where each page is its own
destination; worth a look if a chrome button ever stops answering.
