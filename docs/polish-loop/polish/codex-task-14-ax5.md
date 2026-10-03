
TASK 14: accessibility-size layout breaks, found on AX5 screenshots (Settings › Display & Text Size at its largest,
`xcrun simctl ui <sim> content_size accessibility-extra-extra-extra-large`). Fix each so nothing overlaps, clips, or breaks a
word mid-way at AX5, WITHOUT changing the default-size layout (the default look matches the spec — keep it pixel-identical;
branch on `@Environment(\.dynamicTypeSize).isAccessibilitySize` where a different arrangement is needed, or give text room
with `.fixedSize(horizontal: false, vertical: true)` / `minimumScaleFactor`). Don't hard-cap text at AX sizes unless the
text is a count or a single short word that genuinely cannot wrap (your known habit is over-capping — avoid it).
List changed files per item.

1. Account hub header (AccountView / its header block): the settings gear button overlaps the "AO3 ACCOUNT" kicker at AX5.
   Let the kicker/title column avoid the gear (e.g. trailing padding equal to the gear's width at AX sizes).
2. Account hub shortcut tiles: "Subscriptions" breaks mid-word ("Subscriptio / ns"). Scale the tile label down to fit
   (`minimumScaleFactor(0.7)` + `lineLimit(2)` is fine) or go to one column at AX sizes.
3. SubjectHeaderBlock (UIComponents): a long single-word title ("AO3_Reader") breaks mid-word. Allow the title to shrink
   (`minimumScaleFactor(0.6)`) so a single word never splits; multi-word titles keep wrapping.
4. Inbox rows (AccountInboxViews or its row component): the "Chapter 3" context chip wraps inside its capsule
   ("Chapt / er 3"). Chips never wrap: `.lineLimit(1).fixedSize()`; let the surrounding line wrap instead.
5. Queues list rows (ReadingQueueBrowser / queue row): at AX5 the tag chips ("LONG FIC", "REREADS") scale and overlap each
   other while the queue title stays small. Make title and chips consistent (both scale) and lay the chips out in a
   FlowLayout (UIComponents/FlowLayout.swift) so they wrap instead of overlapping.
6. Recently Deleted cards: the kicker scales ("DOWNLOADED…") but the title and meta line stay fixed. Scale the title/meta
   with @ScaledMetric like the kicker.
7. Home Continue Reading hero card (Home): the chapter line breaks mid-word ("Chap / ter 2: Nine Minutes") beside the
   progress ring at AX5. At accessibility sizes put the ring above the chapter text (or let the text take the full width).

Do not touch SubjectForm.swift (Claude changed it in L3-AX-5). You cannot run the simulator: Claude screenshots at AX5
and default size.
