# A69: iPhone and Android, screen beside screen, in four themes and the largest text

## Differences worth fixing

1. `s_about`, `s_account`, `s_privacy` (all 5 columns: Dark, Light, Sepia, OLED, Largest text): Android shows the top-level `Settings` index screen instead of navigating into the `About`, `AO3 Account`, or `Privacy` sub-pages shown on iPhone.
2. `s_backup`, `s_import`, `s_library`, `s_preservation`, `s_queues`, `s_sync` (Largest text / `big` column): Android shows the top-level `Settings` index screen at the largest text size instead of the target Settings sub-page shown on iPhone.
3. `subs` (all 5 columns): iPhone shows 2 minimal stub cards (`A Study in Pink`, `Another Fic`) under `ALL WORKS 2` with only title, author, and greyed-out icons, whereas Android shows `3 works · 2 with new chapters`, splits into `NEW SINCE YOU LAST LOOKED 2` and `ALL WORKS 1` (`Paper Cranes`), and renders fandom headers, full stats lines (`words · chapters · comments · kudos · bookmarks · hits`), `Chapters 4–5 new` / `6–8 new` labels, and `Unsubscribe` buttons.
4. `works` (all 5 columns): Android shows a 4-column stats bar (`KUDOS · COMMENTS · HITS · BOOKMARKS`), a floating `⋮` button above each card, and a `3 works · 248,400 words · 3,812 kudos` subtitle without a `WORKS 3` section header, whereas iPhone shows a 2-column stats bar (`KUDOS · HITS`), no external `⋮` button, an `AO3_Reader` subtitle, a `WORKS 3` header, and stub cards for the 2nd and 3rd works.
5. `drafts` (all 5 columns): Android shows `page 1 of 2 · 1 expiring this week on this page` and draft cards with `29 DAYS LEFT` / `7 DAYS LEFT` pills and `Created <date>` footers (`Lanterns Above the Mill`, `Seven Quiet Windows`, `A Map Without a Date`), whereas iPhone shows `page 1 of 3` and generic work cards (`Two Voices at Dawn`, `A Name Withheld`, `An Orphaned Work`) without expiry pills or creation dates.
6. `s_backup` (Dark, Light, Sepia, OLED): Android adds two extra technical paragraphs (`Export writes ZIP packages at manifest v8…`, `AO3 passwords are never stored…`), a `Deletion signing` / `This device` key section, and a duplicate `← Backup` top bar with a sharp horizontal colour seam above the red wash, none of which appear on iPhone.
7. `s_sync` (Dark, Light, Sepia, OLED): In the Sync Folder card, Android omits the `Metadata: Ready` status row, the `Check Metadata` action row, and leading row icons (and renames `Last Checked` to `Last Synced`), while under `Deletion signing` Android shows `2 deletions skipped from an unpaired device` and a paired `Demo reading tablet` (`Rename` / `Revoke`) where iPhone shows `No other devices paired yet.`.
8. `s_appearance`, `s_backup`, `s_downloads`, `s_font`, `s_import`, `s_library`, `s_listening`, `s_preservation`, `s_queues`, `s_reader`, `s_sync` (Dark, Light, OLED): Android draws a red/burgundy accent gradient wash across the top of Settings sub-pages in Dark, Light, and OLED, whereas iPhone renders all Settings sub-pages on a neutral unwashed background (`#141416` dark grey, off-white, or pure black).
9. `s_appearance` (all 5 columns): Android adds a 5th `System` option to `Theme`, keeps `Light` highlighted in every theme column, and defaults `Match App & Reader Theme` to OFF (exposing an extra `Reader Theme` 4-segment picker and different footer text), whereas iPhone has 4 theme options (matching the active column) and `Match App & Reader Theme` ON.
10. `prefs` (all 5 columns): Under `ACCOUNT`, Android orders `Blocked Users` and `Muted Users` before `Change Username / Password / Email` and uses Title Case with `My` (`Edit My Profile`, `Manage My Pseuds`), whereas iPhone puts `Blocked users` and `Muted users` last and uses sentence case without `My`.
11. `insights` (all 5 columns): Android has `0.1 hours in October` logged in the demo dataset and shows `THIS MONTH 2` (bar chart), `WHERE THE HOURS WENT 2`, and `PACE AND FOLLOW-THROUGH` at the top, whereas iPhone has 0 hours logged and shows the `No reading logged this month` card followed by `YOUR LIBRARY 4` and `MOST-READ FANDOMS 5`.
12. `browse` (Largest text / `big` column): Android omits the entire `JUMP BACK IN` section at the largest text size, whereas iPhone still displays `JUMP BACK IN 3` at the top of `Browse`.
13. `ao3colls` (Largest text / `big` column): On iPhone, inside the first collection card, `YOU OWN` truncates to `YO…` and the `Revealed` and `Anonymous` badges stay on the same line and wrap character-by-character into narrow 3-line vertical columns (`Rev / eal / ed`, `Ano / nym / ous`), whereas Android wraps each badge onto its own horizontal line.
14. `home` (all 5 columns): In the `Winter Garden` hero card under `CONTINUE READING`, iPhone shows the chapter title `Chapter 2: Nine Minutes` next to the progress ring, whereas Android shows `Last opened` instead of the chapter title (and Android's demo state has 5 continue-reading items and 6 queues with a duplicate `Neon reread` vs iPhone's 2 and 4).
15. `bookmarks` (all 5 columns): Android shows `3 works · page 1 of 4` with a blurred `Tap to reveal` card at the top of the list, whereas iPhone shows `2 works · page 1 of 4` without the blurred card.
16. `collections`, `deleted`, `library`, `queues`, `search` (all 5 columns): Android's demo database contains extra/duplicate restored items compared to iPhone (`4 collections` with `(Restored)` duplicates vs `2`; `4` deleted items with duplicate `Lanterns Over Ba Sing Se` vs `3`; `READING NOW 5 / SAVED FOR LATER 6` vs `2 / 2` in Library; `7 QUEUES` with duplicate `Neon reread` and `Slow burns` vs `5`; `Demo: Doctor Who` saved search on `search`).
17. `later` (all 5 columns): Android places the `Unmark` pill button outside and below each work card on its own right-aligned row, whereas iPhone places `Unmark` inside the bottom-right corner of each card.
18. `ao3coll` (all 5 columns): Android shows the maintainer subtitle `AO3_Reader, comod` beneath `Winter Exchange 2026`, whereas iPhone does not show this line.
19. `account` (all 5 columns): Android shows a `6+` badge on both the `Subscriptions` shortcut tile and the `Subscriptions` row under `READING` (and uses a generic user icon + green dot), whereas iPhone shows no `6+` count (and uses the AO3 icon + green checkmark circle).
20. `history` (all 5 columns): Android displays the author line `Anonymous` inside each history cover card (`The Weight of Water`, `Salt and the Long Winter`), whereas iPhone omits the author name on those cover cards.
21. `s_font` (all 5 columns): Android shows an extra `Demo font` row (with a delete trash icon) and a `Built-in families plus fonts you import (.ttf / .otf).` footer caption, neither of which appears on iPhone.
22. `search` (all 5 columns): Android shows a trailing trash-can delete icon on each saved-search row and keeps the bottom navigation bar visible, whereas iPhone shows neither a delete icon nor the bottom tab bar.
23. `inbox` (Largest text / `big` column): Android displays an extra `User` badge beneath `• ReaderOne` at the largest text size that does not appear on iPhone or in Android's normal-text columns.
24. `inbox` (all 5 columns): On the first comment, iPhone styles `↩ Reply` as a filled pill button and has no badge on the top-right filter icon, whereas Android styles `↩ Reply` as plain accent text and shows a `1` badge on the top-right filter icon.
25. `dashboard` (all 5 columns): Under `RECENT SERIES`, the `The Dawn Cycle` (`STAR WARS`) card has a green fandom wash on iPhone, whereas on Android the series card has a plain neutral/grey surface with no fandom wash.
26. `s_queues` (Dark, Light, Sepia, OLED): On the disabled `Series limit: 5` stepper, the `−` and `+` symbols are clearly legible on iPhone but almost invisible (low-contrast grey-on-grey) on Android across all four themes.
27. `s_listening` (all 5 columns): iPhone titles the second section `Kokoro Neural Engine` (`Download Kokoro (Neural Engine)`), whereas Android titles it `Kokoro Pack` (`Download Voice Pack`); at the largest text size (`big`), iPhone middle-truncates `Plain…rration` and squashes the `1.0x` pill into `1.`, while Android flattens the `0.9x / 1.0x (default) / 1.1x` pills into unboxed vertical text rows.
28. `more`, `prefs` (Largest text / `big` column): On iPhone at the largest text size, leading row icons disappear on all `POST AND MANAGE` rows in `more` and on `Manage pseuds` / `Change username` in `prefs` (while remaining on `Edit profile`), whereas Android keeps leading row icons on all rows.
29. `ao3colls`, `bookmarks`, `inbox`, `subs` (all 5 columns): iPhone renders the pagination control as a centered pill with circular `<` / `>` buttons and a `Page X / Y ⌃` page-jumper chevron, whereas Android renders a full-width flat or outlined row (`<   Page X of Y   >`) without a page-picker chevron.
30. `settings` (Dark, Sepia, OLED, Largest text): The `Appearance` row's trailing value on iPhone updates to match the active theme (`Dark`, `Light`, `Sepia`, `OLED`, `Sepia`), whereas on Android it displays `Light` in every column.

---

## Per-screen findings

### `account`
- **Missing or extra information (all columns):** Android shows a `6+` count on both the **Subscriptions** shortcut tile and the **Subscriptions** row under `READING`; iPhone shows no count on either.
- **Layout / icon (all columns):** iPhone shows the AO3 logo on a white circular avatar and a green checkmark badge next to `Signed in`; Android shows a generic person-in-circle icon on a tinted circle and a small green dot next to `Signed in`.

### `ao3coll`
- **Missing or extra information (all columns):** Android shows the maintainer line `AO3_Reader, comod` beneath the collection title `Winter Exchange 2026`; iPhone does not show this line.
- **Largest text (`big`):** On iPhone, the `Works / Bookmarks / People` segmented picker stays at default small text size instead of scaling; on Android it scales with the largest text size.

### `ao3colls`
- **Layout / control (all columns):** iPhone renders the top pagination control as a centered pill with circular `<` / `>` buttons and a `Page 1 / 3 ⌃` dropdown chevron; Android renders a full-width flat row `<   Page 1 of 3   >` without a pill background or page-picker chevron.
- **Largest text (`big`):** On iPhone, the `Your items` filter chip is clipped at the right edge of the screen, and inside the first collection card `YOU OWN` truncates to `YO…` while the `Revealed` and `Anonymous` pills stay on the same row and wrap character-by-character into narrow vertical stacks (`Rev / eal / ed`, `Ano / nym / ous`). Android wraps those pills onto separate lines cleanly.

### `bookmarks`
- **Missing or extra information (all columns):** Android shows `3 works · page 1 of 4` and displays a blurred work card (`Tap to reveal`) at the top of the list; iPhone shows `2 works · page 1 of 4` and does not show the blurred work card.
- **Layout / control (all columns):** iPhone uses a centered pill for pagination (`< Page 1 / 4 ⌃ >`); Android uses a full-width flat row (`<   Page 1 of 4   >`). Inside cards, `REC` and `PRIVATE` are filled rounded pills on iPhone vs outlined rectangular boxes on Android.
- **Largest text (`big`):** On iPhone, `THE LOCKED TOMB` truncates to `THE LOCKED T…` and the `REC` badge stays tiny; on Android, `THE LOCKED TOMB` shows in full and `REC` scales with the text.

### `browse`
- **Missing or extra information (`big`):** At the largest text size (`Android big`), the entire `JUMP BACK IN` section is missing on Android, whereas `iPhone big` shows `JUMP BACK IN 3`.
- **Missing or extra information (Dark, Light, Sepia, OLED):** iPhone shows `JUMP BACK IN 3` (`Doctor Who`, `Doctor Who (2005)`, `Sherlock`) and `2 downloaded` per category card; Android shows `JUMP BACK IN 4` (`Doctor Who (2005)`, `Doctor Who`, `Supernatural`, `Sherlock`) and `4 downloaded` per category card. Also, the `Supernatural 312K` pill has a leading vertical bar on Android (`| Supernatural 312K`) that is absent on iPhone.
- **Layout (Dark, Light, Sepia, OLED):** Inside each category card, iPhone wraps `2 downloaded` onto a second metadata line below `4 fandoms  ~636K works`, whereas Android places all three counts on one line.

### `collections`
- **Missing or extra information (all columns):** iPhone shows `2 collections` (`To recommend`, `Comfort reads`); Android shows `4 collections`, adding `To recommend (Restored)` and `Comfort reads (Restored)`.
- **Layout / largest text (`big`):** At the largest text size, iPhone keeps the 2×2 grid of vertical mini-covers inside the collection card (pushing the `To recommend` label off the bottom of the screen), whereas Android changes the collection preview into 4 stacked full-width horizontal rows inside the card.

### `dashboard`
- **Theme / card wash (all columns):** Under `RECENT SERIES`, the `The Dawn Cycle` (`STAR WARS`) card has a green fandom wash on iPhone (matching the `STAR WARS` work card above), whereas on Android the series card has a plain neutral/grey background with no fandom wash.
- **Largest text (`big`):** Inside the `Two Voices at Dawn` card at the largest text size, Android renders the 2×2 AO3 rating/warning icon grid on its own row below the author line, whereas iPhone hides the 2×2 icon grid at accessibility text size.

### `deleted`
- **Missing or extra information (all columns):** iPhone shows `3 items` (`DELETED 2`: `Lanterns Over Ba Sing Se` and `Summer 2025`; `FINISHED, NOT KEPT 1`: `Tea in the Jasmine Dragon`, plus `Delete All Permanently` visible at the bottom). Android shows `4 items` (`DELETED 3`, with `Lanterns Over Ba Sing Se` listed twice at `81d LEFT` and `86d LEFT`), pushing the `FINISHED, NOT KEPT` card and `Delete All Permanently` off the bottom of the viewport.

### `drafts`
- **Missing or extra information (all columns):**
  - Subtitle: iPhone shows `page 1 of 3`; Android shows `page 1 of 2 · 1 expiring this week on this page`.
  - Draft cards: Android shows draft-specific cards (`Lanterns Above the Mill`, `Seven Quiet Windows`, `A Map Without a Date`) with `29 DAYS LEFT` / `7 DAYS LEFT` expiry pills and `Created <date>` bottom-right labels; iPhone shows generic fixture works (`Two Voices at Dawn`, `A Name Withheld`, `An Orphaned Work`) without expiry pills or `Created <date>` labels, followed by a `< Page 1 / 3 ⌃ >` pagination pill.
- **Largest text (`big`):** On iPhone, the `ON AO3` section header stays tiny instead of scaling with the largest text size; on Android it scales.

### `history`
- **Missing or extra information (all columns):** Inside each work cover card (`The Weight of Water`, `Salt and the Long Winter`), Android shows the author line `Anonymous` above the 3-icon badge strip; iPhone does not show `Anonymous` on these cards.

### `home`
- **Missing or extra information (all columns):**
  - In the `Winter Garden` hero card under `CONTINUE READING`, iPhone displays the chapter title `Chapter 2: Nine Minutes` next to the progress ring; Android displays `Last opened` instead of the chapter title.
  - iPhone shows `CONTINUE READING 2` (1 mini-card below the hero card) and `READING QUEUES 4` (`Neon reread`, `Slow burns`, `Case…`); Android shows `CONTINUE READING 5` (3 mini-cards visible below the hero card: blurred card, `Sodium Lights`, `Winter…`) and `READING QUEUES 6` (with `Neon reread` listed twice).

### `inbox`
- **Missing or extra information (`big`):** At the largest text size on Android (`Android big`), an extra `User` badge appears beneath `• ReaderOne` that does not appear on iPhone or in Android's normal-text columns.
- **Layout / control (all columns):**
  - In the first comment (`ReaderOne`), iPhone renders `Reply` as a filled pill button (`↩ Reply`), whereas Android renders `↩ Reply` as plain text without a button background.
  - Android shows a `1` badge on the top-right filter icon while the `Unread` chip is active; iPhone does not badge the filter icon.
  - Bottom pagination is a centered pill (`< Page 1 / 2 ⌃ >`) on iPhone vs a full-width outlined bar (`<   Page 1 of 2   >`) on Android.

### `insights`
- **Missing or extra information / order (all columns):** iPhone has no logged reading time in the demo dataset and shows the `No reading logged this month` empty-state card followed by `YOUR LIBRARY 4` (`4 works opened`, `203K words read`, etc.) and `MOST-READ FANDOMS 5` (`Avatar: The Last Airbender`, `Doctor Who`). Android has `0.1 hours in October` logged and therefore shows `THIS MONTH 2` (bar chart), `WHERE THE HOURS WENT 2` (`Frozen (Disney Movies)`, `Doctor Who (2005)`), and `PACE AND FOLLOW-THROUGH` (`0 min median session`, `596,763 words per hour`, etc.) at the top of the screen, pushing `YOUR LIBRARY` below the fold.
- **Largest text (`big`):** On Android, `Frozen (Disney Movies)` in `WHERE THE HOURS WENT 2` is truncated to `Frozen (Disney Mov…`.

### `later`
- **Layout (all columns):** On iPhone, the `Unmark` pill button sits **inside** the bottom-right corner of each work card; on Android, `Unmark` is rendered **outside and below** each work card on its own right-aligned row.

### `library`
- **Missing or extra information (all columns):** The demo library datasets differ: iPhone shows `READING NOW 2`, `SAVED FOR LATER 2` (`Paper Cranes`, `Stars Over Tatooine`), and `FINISHED 3`, with top fandom chips starting `All`, `Avatar: The Last Airbender`, `Doctor Who`. Android shows `READING NOW 5`, `SAVED FOR LATER 6` (starting with `A suitor for you` and `A_suitor_for_you`), and `FINISHED 4`, with top fandom chips starting `All`, `Doctor Who`, `Doctor Who (2005)`.
- **Largest text (`big`):** Inside the `Winter Garden` cover card, the `50% READING` ring label stays small on iPhone instead of scaling, whereas `71% READING` scales up on Android.

### `more`
- **Largest text (`big`):** On iPhone (`iPhone big`), all leading row icons under `POST AND MANAGE` disappear at the largest text size; on Android (`Android big`), the leading row icons remain visible.
- **Layout (Dark, Light, Sepia, OLED):** Android's slightly more compact vertical spacing reveals the `YOUR ACCOUNT` section header and `Profile` row at the bottom of the screen, which are below the fold on iPhone.

### `prefs`
- **Order (all columns):** Under `ACCOUNT`, iPhone orders the rows `Edit profile`, `Manage pseuds`, `Change username`, `Change password`, `Change email`, `Blocked users`, `Muted users`. Android places `Blocked Users` and `Muted Users` third and fourth, before `Change Username`, `Change Password`, and `Change Email`.
- **Missing or extra information / wording (all columns):** iPhone uses sentence case and `Edit profile` / `Manage pseuds`; Android uses Title Case and adds `My` (`Edit My Profile`, `Manage My Pseuds`, `Blocked Users`, `Muted Users`, `Change Username`, `Change Password`, `Change Email`).
- **Largest text (`big`):** On iPhone (`iPhone big`), the `ACCOUNT` section header stays tiny instead of scaling, and the leading icons disappear on `Manage pseuds` and `Change username` (while remaining on `Edit profile`). On Android (`Android big`), the `ACCOUNT` header scales and all rows keep their leading icons.

### `queues`
- **Missing or extra information (all columns):** iPhone shows `5 QUEUES · 15 WORKS · 13 OFFLINE · 32 KB STORAGE` (`Saved for Later 2`, `Neon reread 5`, `Slow burns 4`, `Case fic pile 3`, `Late 1`); Android shows `7 QUEUES · 28 WORKS · 24 OFFLINE · 57 KB STORAGE` with `Saved for Later 4` and duplicate `Neon reread 5` and `Slow burns 4` cards.
- **Layout / largest text (`big`):** At the largest text size, iPhone reflows the 4-stat summary card into a 2×2 grid (`QUEUES` / `WORKS` over `OFFLINE` / `STORAGE`), whereas Android keeps all 4 stats on a single horizontal row; Android also truncates the scaled search bar placeholder (`Search queues, tags and…`) while iPhone keeps the placeholder at a smaller unclipped size.

### `s_about`
- **Missing or extra information / wrong screen (all columns):** iPhone shows the `SETTINGS → About` sub-page (`Version 1.0`, `Privacy and local data`, `About Kudos`, `Report a Bug`, `Source on GitHub`, and footer). Android shows the top-level `Settings` index screen (`READING`, `DOWNLOADS & STORAGE`, `LIBRARY & SYNC`) in all 5 columns instead of the `About` sub-page.

### `s_account`
- **Missing or extra information / wrong screen (all columns):** iPhone shows the `SETTINGS → AO3 Account` sub-page (`Signed In AO3_Reader`, `Log Out`, and footer). Android shows the top-level `Settings` index screen in all 5 columns instead of the `AO3 Account` sub-page.

### `s_appearance`
- **Theme (Dark, Light, OLED):** On iPhone, the `Appearance` page uses a neutral background with no top accent wash (`#141416` dark grey in Dark, off-white in Light, pure black in OLED). On Android, Dark, Light, and OLED all draw a strong red/burgundy accent wash across the top of the screen.
- **Missing or extra information (all columns):**
  - The `Theme` picker on iPhone has 4 options (`Light`, `Sepia`, `Dark`, `OLED`) with the active pill matching the column's theme; Android adds a 5th option (`System`) and highlights `Light` in every column.
  - `Match App & Reader Theme` is ON on iPhone and OFF on Android; because it is OFF on Android, Android shows an extra `Reader Theme` label and a second 4-option segmented control (`Light | Sepia | Dark | OLED`) plus different footer text (`You can choose different themes for Kudos and the reader…` vs iPhone's `Choose Light, Sepia, Dark, or OLED for Kudos and the reader…`).
- **Layout / largest text (`big`):** On iPhone, the segmented `Theme` control stays on 1 row at small unscaled text; on Android, both segmented controls scale up and wrap into multi-row grids (`2×2 + 1` and `2×2`).

### `s_backup`
- **Missing or extra information / wrong screen (`big`):** At the largest text size (`Android big`), Android shows the top-level `Settings` index screen instead of the `Backup` sub-page.
- **Missing or extra information (Dark, Light, Sepia, OLED):** Android displays two extra technical paragraphs beneath the first footer paragraph (`Export writes ZIP packages at manifest v8…` and `AO3 passwords are never stored…`) plus an entire `Deletion signing` section (`This device` and a hex public key) that are not shown on iPhone.
- **Theme / layout (Dark, Light, Sepia, OLED):** Android shows a duplicate `← Backup` top bar above the `SETTINGS / Backup` hero header, creating a sharp horizontal colour seam in Dark, Light, and OLED between the unwashed top bar and the red/burgundy gradient wash below it (whereas iPhone has no top wash at all).

### `s_downloads`
- **Theme (Dark, Light, OLED):** iPhone uses a neutral background with no top wash; Android draws a strong red/burgundy gradient wash across the top of the screen in Dark, Light, and OLED.
- **Missing or extra information (all columns):** `Storage used` is `2 MB` on iPhone vs `471 KB` on Android.

### `s_font`
- **Missing or extra information (all columns):**
  - Android includes an extra `Demo font` row (with a trash icon) between `Menlo` and `+ Add Font…`; iPhone does not have `Demo font`.
  - Android shows a footer caption `Built-in families plus fonts you import (.ttf / .otf).` below the font list card; iPhone has no footer caption on this page.
- **Theme (Dark, Light, OLED):** iPhone uses a neutral background with no top wash; Android draws a strong red/burgundy gradient wash across the top of Dark, Light, and OLED.

### `s_import`
- **Missing or extra information / wrong screen (`big`):** At the largest text size (`Android big`), Android shows the top-level `Settings` index screen instead of the `Import` sub-page.
- **Theme (Dark, Light, OLED):** iPhone uses a neutral background with no top wash; Android draws a strong red/burgundy gradient wash across the top of Dark, Light, and OLED.

### `s_library`
- **Missing or extra information / wrong screen (`big`):** At the largest text size (`Android big`), Android shows the top-level `Settings` index screen instead of the `Library` sub-page.
- **Theme (Dark, Light, OLED):** iPhone uses a neutral background with no top wash; Android draws a strong red/burgundy gradient wash across the top of Dark, Light, and OLED.

### `s_listening`
- **Theme (Dark, Light, OLED):** iPhone uses a neutral background with no top wash; Android draws a strong red/burgundy gradient wash across the top of Dark, Light, and OLED.
- **Missing or extra information / wording (all columns):**
  - Second section: iPhone shows `Kokoro Neural Engine` with button `Download Kokoro (Neural Engine)` and Neural Engine–specific footer copy; Android shows `Kokoro Pack` with button `Download Voice Pack` and `The Int8 Voice Pack…` footer copy.
  - Picker rows (`Sample Text`, `Engine`): iPhone styles the value (`Plain Narration ⌃⌄`, `Automatic ⌃⌄`) in the accent colour with a menu chevron; Android styles it in muted grey with a disclosure chevron (`Plain Narration >`, `Automatic >`).
- **Layout / largest text (`big`):**
  - On iPhone (`iPhone big`), `Plain Narration` truncates in the middle (`Plain…rration`) and the speed preset button below the slider is squashed into a narrow circle showing `1.` at the bottom edge.
  - On Android (`Android big`), the three speed preset pills (`0.9x`, `1.0x (default)`, `1.1x`) stack vertically as plain unboxed text lines instead of pill buttons.

### `s_preservation`
- **Missing or extra information / wrong screen (`big`):** At the largest text size (`Android big`), Android shows the top-level `Settings` index screen instead of the `Preservation` sub-page.
- **Theme (Dark, Light, OLED):** iPhone uses a neutral background with no top wash; Android draws a strong red/burgundy gradient wash across the top of Dark, Light, and OLED.

### `s_privacy`
- **Missing or extra information / wrong screen (all columns):** iPhone shows the `SETTINGS → Privacy` sub-page (`Hide mature content`, `Blur / Hide`, `Require Face ID to reveal`, `Privacy & Local Data`, and footer). Android shows the top-level `Settings` index screen in all 5 columns instead of the `Privacy` sub-page.

### `s_queues`
- **Missing or extra information / wrong screen (`big`):** At the largest text size (`Android big`), Android shows the top-level `Settings` index screen instead of the `Reading Queues` sub-page.
- **Theme / legibility (Dark, Light, Sepia, OLED):**
  - iPhone uses a neutral background with no top wash in Dark, Light, and OLED; Android draws a strong red/burgundy gradient wash across the top of Dark, Light, and OLED.
  - On the `Series limit: 5` row (while `Auto-preserve small series` is off), the `−` and `+` symbols in the stepper are clearly legible on iPhone, whereas on Android they are nearly invisible against the button background across all four themes.

### `s_reader`
- **Theme (Dark, Light, OLED):** iPhone uses a neutral background with no top wash; Android draws a strong red/burgundy gradient wash across the top of Dark, Light, and OLED.
- **Largest text (`big`):** On iPhone (`iPhone big`), the `Scrolled / Paged` segmented control stays at default small text size; on Android (`Android big`), it scales with the largest text size.

### `s_sync`
- **Missing or extra information / wrong screen (`big`):** At the largest text size (`Android big`), Android shows the top-level `Settings` index screen instead of the `Sync Folder` sub-page.
- **Missing or extra information (Dark, Light, Sepia, OLED):**
  - Under `Deletion signing`, iPhone shows `No other devices paired yet.` above `Pair a Device`; Android shows `2 deletions skipped from an unpaired device`, a paired `Demo reading tablet` (`d5af74a0…`), `Rename`, and `Revoke` above `Pair a Device`.
  - In the second card, iPhone has 4 rows (`Metadata: Ready`, `Choose Sync Folder`, `Last Checked: Oct 2, 2026 at 7:46 PM`, and `Check Metadata`, with leading icons); Android has only 2 rows (`Choose Sync Folder` and `Last Synced: Oct 16, 2026 at 6:15 PM`, with no leading icons), omitting both `Metadata: Ready` and `Check Metadata` and renaming `Last Checked` to `Last Synced`.
- **Theme (Dark, Light, OLED):** iPhone uses a neutral background with no top wash; Android draws a strong red/burgundy gradient wash across the top of Dark, Light, and OLED.

### `search`
- **Missing or extra information (all columns):**
  - iPhone shows 1 card (`Doctor Who` / `Doctor Who`) with no trailing delete button; Android shows 2 cards (`Doctor Who` and an extra `Demo: Doctor Who`) and renders a trailing trash-can delete button on each card.
  - Android shows the bottom tab bar (`Search` selected) on this screen; iPhone does not show the bottom tab bar.
  - Section title is `Saved Searches` (Title Case) on iPhone vs `SAVED SEARCHES` (ALL CAPS) on Android.

### `settings`
- **Missing or extra information (Dark, Sepia, OLED, `big`):** On iPhone, the `Appearance` row's trailing value reflects the active theme of each column (`Dark`, `Light`, `Sepia`, `OLED`, `Sepia`). On Android, the `Appearance` row shows `Light` in all 5 columns.

### `subs`
- **Missing or extra information (all columns):**
  - Subtitle: iPhone shows `2 works · page 1 of 3`; Android shows `3 works · 2 with new chapters · page 1 of 3`.
  - Sections & cards: iPhone shows only `ALL WORKS 2` (`A Study in Pink`, `Another Fic`) as compact 2-line stub cards (title, author, and greyed-out 3-icon badge box — no fandom label, no stats line, no new-chapter text, and no `Unsubscribe` button). Android splits the list into `NEW SINCE YOU LAST LOOKED 2` (`A Study in Pink`, `Another Fic`) and `ALL WORKS 1` (`Paper Cranes`), and each card shows the fandom header (`SHERLOCK`, `ORIGINAL WORK`, `HAIKYUU!!`), colored 2×2 AO3 symbols, full stats (`English · 12,400 words · 5/? · 0 comments · 0 kudos · 0 bookmarks · 0 hits`) with an expand chevron, plus a footer row below each card with `Chapters 4–5 new` / `Chapters 6–8 new` and an `Unsubscribe` button.
- **Layout / control (all columns):** iPhone uses a centered pill for pagination (`< Page 1 / 3 ⌃ >`, shortened to `< 1 / 3 ⌃ >` in `big`); Android uses a full-width flat row (`<   Page 1 of 3   >`).
- **Largest text (`big`):** On iPhone, `Authors` and `× Reset` are clipped at the right edge (`Autho…`, `× Rese…`); on Android they fit without clipping.

### `works`
- **Missing or extra information (all columns):**
  - Subtitle & section header: iPhone shows `AO3_Reader` as the subtitle under `Works` and a `WORKS 3` section header above the list; Android shows `3 works · 248,400 words · 3,812 kudos` as the subtitle and omits the `WORKS 3` section header.
  - Per-card menu button: Android renders a floating `⋮` button above the top-right corner of each work card; iPhone has no external `⋮` button.
  - Card stats bar: iPhone shows a 2-column stats box (`80 KUDOS | 900 HITS`) on the first card and stub cards (no summary, word count, or stats box) for the 2nd and 3rd works; Android shows a 4-column stats box (`80 KUDOS | 8 COMMENTS | 900 HITS | 30 BOOKMARKS`) and full metadata on every card.
- **Largest text (`big`):** On iPhone, the `Gifts` chip on the first filter row is pushed off-screen and `The Locked Tomb (3)` on the second row is clipped to `T…`; on Android, `Gifts` fits on the first row and `The Locked Tomb (3)` clips to `The Locke…`.
