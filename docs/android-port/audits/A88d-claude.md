# A88d: 3ha's nine re-shot screens (Claude, 2026-10-23, partial)

Shot `list13-android.txt` 12:12–13:00 with Codex, Gemini and Claude-CLI working. About half the Android
columns are capture faults: "Kudos isn't responding" waiting 5 s for the window's first focus during app
start (logcat `am_anr … Waited 5000ms for FocusEvent`), or Home, or a screen still loading. These are
load, not app faults; the faulty columns are re-shot when the machine is quiet.

Usable columns, against the iPhone's:
- **privacydata** (Dark, Light, Sepia, OLED): match. 3ha's Account wash is there. "Imported fonts" is
  Android's decided extra. 2.0× showed Settings (capture).
- **availability** (Dark, Light, OLED, 2.0×): match. The orphan rule is gone (3ha). Sepia: capture.
- **recovery** (Dark, Light, 2.0×): match. Light is white as the iPhone's (3ha's sheet ground). Minor:
  Android's action rows are a little smaller and follow the text, where the iPhone pins them to the
  sheet's foot.
- **chapterform** (Sepia, OLED): match. 3ha's route opens Add chapter, as the iPhone's does. Its other
  columns caught the work form mid-load.
- **bulknames** (Light, OLED): 3ha's single "Collection name … Add" row matches. **Fixed after A88d:**
  Add looked enabled with the field empty (the forced accent overrode the disabled ink, as in queue
  tags).
- **authorbookmarks** (Dark, Sepia, OLED): 3ha's neutral cards, header and Load More card are there.
  - Android's extra first card (a blurred Ashfall at 63%) is demo routing: Android's demo serves
    `/users/AO3_Reader/bookmarks` from `ao3_demo_account_bookmarks` (three bookmarks), while iOS's demo
    serves every user's bookmarks from `ao3_author_bookmarks` (two).
  - Showing a library copy as its local card is Android's decided extra (DECISIONS, 3gx).
  - Minor: "BOOKMARKS" in small caps against the iPhone's "Bookmarks".
- **prefhelp** (Light): 3ha's white sheet matches. **Fixed after A88d:** the sheet had no close control
  where the iPhone has a ✓ beside its title (Android's reader sheets have one too), and its topics were
  grey glass on the white sheet where the iPhone's are white cards with a hairline (`cardRow()`).
- **seriesdetail** (Light only): 3ha's bookmarks, Restricted, date, zero figures and neutral cards are
  there. Minor:
  - the card's figures have no icons beside them;
  - the series byline is the fandom-green accent where the iPhone's is the app's;
  - the work cards' bylines are accent without "by" where the iPhone's are grey with "by";
  - the fandom line has no icon.
  The card dates differ by owner Q28.
- **chsettingsedit**: no usable Android column (Home, loading or ANR in all five). Re-shoot.

Still to do: re-shoot every faulty column, then judge seriesdetail's minors against iOS's code (which
ones the iPhone's real data would show) and chsettingsedit.
