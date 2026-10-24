# A97: the last re-shoot before §7's rows close (an index; Claude checks)

**Read-only.** Create `A97-gemini-result.md` in the folder you were started in FIRST, and write each
verdict into it as you go. Change no other file.

Tiles: `/Users/cidy02/kudos-tools/pairs/tiles-a97/<name>.png` (iPhone row above Android; Dark, Light, Sepia,
OLED, largest text). Android was re-shot on a quiet machine on 2026-10-23 after 3hb, 3hc2, 3hd and A88d's
fixes landed (lane `5455f869`); the iPhone shots are the newest for each screen (the four I15/I16/T-443
screens re-shot the same evening). The merged triage of the earlier passes is
`/Users/cidy02/kudos-android-lane/docs/android-port/audits/A88-triage.md`: read its "Decided, not changed"
list and don't report those. What each screen is: `A82-shots.md` in the same folder. What A88c and A88d
found for these screens: `A88c-cli-result.md`, `A88c-gemini-result.md`, `A88d-claude.md`, same folder.

**Your screens (38):** queuetags pagejump fandomworks tagworks readerdisplay readernote readerfind
pronunciations customizetheme backupimport tagseditor collectionsgifts texteditor newqueue addworks
newcollection collectiondetails collectionreorder chapterpicker seriesedit readercontents readerspeech
chsettingsedit bulknames prefhelp recovery availability privacydata chapterform fandomlist pairing
revokedevice formattingtray libraryfilters thread colmod ao3coll works

**Not to report:**
- Card dates ("09 Jul 2026" against "07/09/2026"): owner question Q28.
- A missing "by" before a work card's author on Android: fixed in A96, not yet in these shots.
- Android's Material navigation bar and icon buttons: decided (owner, 2026-10-04).

For **each screen**, one verdict: **match**, **minor** (noticeable, loses nothing) or **differs** (missing or
extra information, a different order or layout, a theme drawn wrongly, text cut or ending in "…" on one side
only), with one line saying what, in which column, which app; and **capture problems** separately. Say for
each screen whether A88c's or A88d's difference (if it had one) is gone. Report counts first, then the lists,
then the per-screen verdicts.
