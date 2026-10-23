# A88b: the A82 screens again, after the fixes (an index; Claude checks)

**Read-only.** Create `/Users/cidy02/kudos-agent-flash/docs/android-port/audits/A88b-result.md`
FIRST; write each screen's verdict into it as you finish it. Change no other file.

The tiles are in `/Users/cidy02/kudos-tools/pairs/tiles-a88/`, one PNG per screen (top row iPhone, bottom
row Android; columns Dark, Light, Sepia, OLED, and Sepia at the largest text: iPhone AX5, Android font
scale 2.0, the smaller of the two). Both apps opened each screen by a debug route on their demo
libraries; neither contacted AO3. What each screen is on each app: `/Users/cidy02/kudos-android-lane/docs/android-port/audits/A82-shots.md`
(`readerspeech` is the reader's Read Aloud settings sheet; `authorbookmarks` is the author page opened on
its Bookmarks tab from the dashboard). The earlier verdicts on the same screens are
`/Users/cidy02/kudos-android-lane/docs/android-port/audits/A82a-result.md` and `A82b-result.md`; since
then both apps changed most of these screens to match.

**Your screens (36):** authorabout seriesdetail seriesedit seriesreorder seriesremove authorworksfilter colitems colsfilter chsettingsedit chsignupdetail prompttags tagset tagseteditor writingpreview chapters chapterform edittags tagseditor texteditor recovery seriespicker collectionsgifts creatorspicker parentpicker bulkedit bulktagstate bulknames prefhelp privacydata availability pairing revokedevice backupimport aboutkudos readerspeech authorbookmarks 

**Skip `readerspeech`:** its Android shots show Home (a capture fault, being re-shot); give it no verdict.

For **each screen**, one verdict: **match** (layout, content, order and theme drawing agree; only fonts,
chrome and demo data differ), **minor** (a difference a careful reader would notice but that loses
nothing), or **differs** (missing or extra information, a different order or layout, a theme drawn
wrongly, or text cut off or ending in "…" on one side only). For minor and differs, one line each:
what, in which column, which app. Flag **capture problems** separately (a spinner, a blank, the wrong
screen, a half-drawn screen, a sheet that did not open, a system dialog such as "isn't responding",
the launcher): they are not verdicts. Say for each screen A82 called differs or minor whether that
difference is gone.

Decided, not to report: Android's navigation and chrome (Material top bar, back arrow, icon buttons,
bottom sheets and their drag handle, dialogs, tab bar, sliders, switches, checkboxes, segmented
controls, dropdown and overflow ⋮ menus); fonts; the two apps' demo data (titles, counts, dates, which
works or tags are listed, reading positions, the books in the reader, the work a form edits, the order
of two demo collections made in the same instant); Android's own extra information (own-works totals,
verified author links, Backup's notes and Deletion signing, Software Update on About, local works in
Browse lists showing their progress, the reading-order contents when an EPUB has none, a multi-line
collection description, the scrollable theme preview, extra slider figures); Android's System theme
option; a sheet's accent following the wash of the screen under it (Android) where the iPhone's takes
the app accent; a full page on one app and a sheet or dialog on the other (compare what it shows); the
iPhone's larger largest size; a frame that ends before a list's last group; `colitems` (the iPhone's
demo opens the account-wide items page, Android one collection's page as its maintainer: both draw
Unrevealed/Anonymous as AO3 allows on that page); the iPhone's cut titles on `revokedevice` and
`addworks` (being fixed).

Report first the counts (match, minor, differs, capture problems), then "Differs", "Minor" and
"Capture problems" as one-line lists, then the per-screen verdicts.
