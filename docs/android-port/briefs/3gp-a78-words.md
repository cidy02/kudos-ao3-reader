# Brief 3gp: the word and content gaps A78 found against iOS

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests, looks on the emulator and lands it. Do not edit
`TASKS.md`. Create `docs/android-port/briefs/3gp-result.md` FIRST and write each item into it as
you finish it: **fixed / already right / intentional difference (why)**, Android `path:line`, the
iOS `path:line` you followed, and the test.

Your own audit `docs/android-port/audits/A78-result.md` lists 27 remaining findings ("Remaining
'still differs' items", with IDs and both-side evidence above it). Re-read each item's code before
changing it. iOS source: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`. Use iOS's words
exactly; Android chrome stays (a TalkBack click label is a verb phrase: TalkBack says "Double-tap
to" before it, so iOS's hint "Opens X" becomes "open X").

1. **Visible content first (orders 1–2, O8-01–03, O9-01–02).** Library History rows and Favorites'
   Works rows show what iOS shows under each work: the reading time, "Read ×N" and "N new
   chapter(s)", with iOS's conditions and formatting. Use data Android already stores; if a figure
   is not stored on Android, say so in the result and stop for that figure (no new database column
   without Claude).
2. **Menus (orders 3–5).** History's and Favorites' More menus use iOS's words: "Layout" with
   iOS's option names (and "Compact" on Favorites Works if iOS offers it there), "Collapse All
   Cards" / "Expand All Cards", "Hide mature" / "Show mature" exactly as iOS words them.
3. **Series and forms (orders 6–10).** The series removal control as iOS draws it (keep the spoken
   title-specific label); Preserve Series gets iOS's Cancel; Reorder's loading and error header says
   "Reorder series"; Series' extra "Loading…" / "Saving…" captions go if iOS shows none there (keep a
   spoken status if Android needs one); the chapter list's unavailable-authentication sentence is
   iOS's.
4. **Spoken only (orders 11–19).** Each to iOS's wording: the favourite's newest-work link names the
   work; the favourite card's description; "In this queue" on a queue member checkmark; facet
   states "Included" / "Excluded"; the word-count range's single "lower to upper" value; the author
   sort button's help and "active" count; History and Favorites filter buttons' help; and remove the
   Android-only group descriptions ("History grouping", "Favorites scope", "Favorites order") unless
   TalkBack needs them to name an otherwise unnamed control (say which).

Tests: one per visible rule (the History and Favorites row lines with their conditions; menu
words; Reorder's header; the sentence) and one covering the spoken labels. Structural Compose or
JVM tests only (no `captureToImage`). Existing tests that pin the old words change with the fix;
say which.
