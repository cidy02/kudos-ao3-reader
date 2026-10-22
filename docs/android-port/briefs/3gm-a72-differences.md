# Brief 3gm: the A72 side-by-side differences that remain on Android

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests, looks on the emulator and lands it. Do not edit
`TASKS.md`. Create `docs/android-port/briefs/3gm-result.md` FIRST and write each item into it as
you finish it: **fixed / matches already / intentional Android difference (why) / not
reproducible**, the Android `path:line`, the iOS `path:line` you followed, and the test.

Gemini compared all 65 screens on the iPhone and Android in Dark, Light, Sepia, OLED and the
largest text size (iPhone AX5, Android font scale 2.0). Its report is
`/Users/cidy02/kudos-agent-gemini/docs/android-port/audits/A72-result.md`; the images it compared
are `/Users/cidy02/kudos-tools/pairs/tiles-final/<name>.png` and `.../tiles2/<name>.png` (top row
iPhone, bottom row Android, columns Dark, Light, Sepia, OLED, largest text). Read the image for
each item before changing anything. iOS source: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`.

Rules: layout, content and order follow iOS; Android's own chrome (ripple, Material checkbox,
overflow menus, system back) stays. At the largest text size nothing may be cut off or end in
"…" where iOS shows it whole: wrap it, as iOS does. A horizontally scrolling rail whose last chip
runs off the edge is fine only where iOS's rail does the same at that size. Never hide
information Android shows today unless iOS shows the same information another way on that
screen. Fix the shared component when the defect is in one (grep its callers), not each screen.

Already handled (do not touch): `history` (both follow AO3's order; the iPhone frame ends before
the third group), `ao3coll` (an iPhone parsing bug, fixed on iOS), Browse's missing Jump Back In
at 2x (fixed in `cd04b55a`), the account Works subtitle (decision 2026-10-11), and differences
that come from the two demo libraries' sample data (which works, read dates, completion,
Android's extra demo bookmark), which are not app behaviour.

1. `comments`, largest text: the sort chip reads "Newe…". Also all sizes: Android shows a
   "Reply" word beside each comment's reply arrow; iOS shows the arrow only (check
   `Features/Comments/CommentsView.swift`). Match iOS, keeping the accessibility label.
2. `workdetail`, largest text: the fandom chip `呪術廻戦 | Jujutsu Kaisen (Manga)` ends in "…";
   iOS wraps it.
3. `queues`, largest text: the search field's placeholder `Search queues, tags and works` is cut
   to `Search queues, tags and`. `queue`, largest text: the `WIP 3` filter chip is cut at the
   right edge (check what iOS's queue filter row does at AX sizes).
4. `s_listening`: Android titles the second section `Kokoro Pack` / `Download Voice Pack`; iOS
   says `Kokoro Neural Engine` (`Features/ReaderReadium/ReaderSpeechSettingsSection.swift` and the
   Settings page that hosts it). At the largest size Android draws the `0.9x / 1.0x (default) /
   1.1x` speed presets as bare stacked text; iOS keeps them as a boxed control.
5. `collections`, largest text: each collection card's 2×2 mini-cover grid becomes four stacked
   rows; iOS keeps the 2×2 grid.
6. `bookmarks`: Android's `REC` / `PRIVATE` pills are outlined; iOS's are filled. Largest text:
   the `With notes` filter chip is cut at the right edge. Also compare the page control: iOS draws
   a capsule `‹ Page 1 / 4 ⌃ ›` (with its page menu) above and below the list; Android draws
   plain `‹ Page 1 of 4 ›`. If the capsule is a shared iOS component Android lacks, port it for
   every AO3 list that uses it on iOS.
7. `chassign`: `Open on AO3` is plain accent text on Android, a compass-icon pill on iOS; Android
   adds a `Load more defaulted assignments` card (check iOS). Largest text: filter tabs become
   capsule pills with `Pinch hi` cut off, and the bottom buttons stack.
8. `chsignups`: Android right-aligns the `MATCHED` / `UNMATCHED` pills and draws `Load page 2 of
   2` as an outlined card; check iOS's placement and button. Largest text: as 7.
9. `author`: iOS shows AO3's default icon (the AO3 logo on white) when an author has no icon of
   their own and a hand (stop) symbol for Block; Android shows a framed-person placeholder on a
   tinted square and a circle-slash. Largest text: Android wraps the four-tab picker into a 2×2
   grid. `account`: the same default-icon difference on the account header. If iOS ships the AO3
   default icon as an asset, add the same image to Android (it is AO3's default user icon, as
   AO3 itself serves it; say where iOS's copy came from).
10. `dashboard` and `works`, largest text: Android shows the 2×2 rating/warning symbol grid under
    the author line; iOS does not show it there. Find what iOS does with those four symbols at AX
    sizes in `Features/Search/AO3WorkRow.swift` (and the account dashboard's rows) and follow it,
    without losing the information (if iOS drops the grid at AX sizes but keeps the rating and
    warnings elsewhere on the card, do the same).
11. `s_appearance` (Android has a fifth `System` theme option), `s_font` (Android adds `Built-in
    families plus fonts you import (.ttf / .otf).` under the card), `synconb` (Android's `Don't
    remind me again` is a checkbox; iOS a switch), `welcome` (the icon art differs): do not
    change these; for each, say in the result whether iOS has the same capability elsewhere and
    whether it is Android chrome, so Claude can record it.

Tests: one per fix that has a rule (a chip that must wrap: its full text is displayed at font
scale 2; the collection grid keeps two columns; the section title; pill styles do not need one).
Structural Compose tests only: Robolectric's `captureToImage` times out here. Existing tests that
pin the old behaviour change with the fix; say which.
