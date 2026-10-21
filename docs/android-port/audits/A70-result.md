# A70: the iPhone and Android, screen beside screen, after A69's fixes

## Differences worth fixing

1. `works` (all 5 columns: Dark, Light, Sepia, OLED, Largest text): Android shows a `Loading...` spinner card below `AO3_Reader` instead of the filter chips, `WORKS 3` section header, and work cards shown on iPhone.
2. `bookmarks` (Dark, OLED), `history` (Dark, OLED), `prefs` (Sepia), `inbox` (Largest text / `big`), `later` (Largest text / `big`): Android shows a `Loading...` spinner card instead of the loaded screen shown on iPhone (and on `inbox` at largest text the `←` back arrow overlaps `AO3 ACCOUNT`).
3. `drafts` (Largest text / `big` column): On Android, the top-right `+` button, the `page 1 of 2…` subtitle, the `ON AO3` section header, and all draft cards are missing below the notice card, whereas iPhone displays the `+` button, subtitle, `ON AO3` header, and draft cards.
4. `library` (Dark column): On Android, the `Library` heading overlaps directly on top of the `All` and `Avatar: The Last Airbender` filter chips, the top-right `+`, filter, and `⋮` buttons are missing, and the top fandom wash is absent, whereas iPhone renders the full header, action buttons, and fandom wash above the filter chips.
5. `subs` (Dark, OLED): On Android, both the `NEW SINCE YOU LAST LOOKED` and `ALL WORKS` section headers are missing above the subscription cards (and in Dark all 3 cards omit fandom/stats while in OLED the 1st card omits fandom/stats and the 2nd–3rd show them), whereas iPhone shows the `ALL WORKS 2` section header.
6. `history` (Light, Sepia): On Android, the `THIS MONTH 1` section is ordered after `EARLIER 1` (`THIS WEEK 1` → `EARLIER 1` → `THIS MONTH 1`).
7. `settings` (Dark, Sepia, OLED, Largest text): On Android, the `Appearance` row's trailing value displays `Light` in every column, whereas iPhone updates it to match the active theme of each column (`Dark`, `Light`, `Sepia`, `OLED`, `Sepia`).
8. `ao3colls` (Largest text / `big` column): On iPhone, the `Your items` filter chip clips at the right edge, `YOU OWN` truncates to `YO…`, and the `Revealed` and `Anonymous` badges wrap character-by-character into 3-line vertical stacks (`Rev / eal / ed`, `Ano / nym / ous`), whereas Android fits `Your items` and wraps each badge onto its own horizontal line.
9. `collections` (Largest text / `big` column): On iPhone, each collection card keeps a 2×2 grid of vertical mini-covers (pushing the `To recommend` title off the bottom of the screen), whereas Android reflows the collection preview into 4 stacked full-width horizontal rows inside the card.
10. `queues` (Largest text / `big` column): On iPhone, the 4-stat summary card reflows into a 2×2 grid and the search placeholder fits in full, whereas Android keeps all 4 stats on a single horizontal row and clips `Search queues, tags and`.
11. `ao3coll` (all 5 columns): Android displays the maintainer subtitle `AO3_Reader, comod` beneath `Winter Exchange 2026`, whereas iPhone omits this line (and in `big`, iPhone keeps the `Works / Bookmarks / People` segmented picker at default small text size while Android scales it).
12. `account` (all 5 columns): iPhone displays the AO3 logo on a white circular avatar and a green checkmark circle next to `Signed in`, whereas Android displays a generic person-in-circle icon on a tinted circle and a small green dot.
13. `library` (all 5 columns): Top fandom filter chips (`All`, `Avatar: The Last Airbender`, `Doctor Who`) are rounded capsule pills on iPhone vs rectangular outlined boxes on Android (and in `big`, the progress ring label inside the first cover card stays small on iPhone vs scaling up on Android).
14. `bookmarks` (Light, Sepia, Largest text): Inside work cards, `REC` and `PRIVATE` are filled rounded pills on iPhone vs outlined rectangular boxes on Android; in `big`, iPhone truncates `THE LOCKED TOMB` to `THE LOCKED T…` and keeps `REC` tiny while Android shows both scaled in full (and Android's demo list includes a blurred `Tap to reveal` card at the top).
15. `more`, `prefs` (Largest text / `big` column): On iPhone, leading row icons disappear on all `POST AND MANAGE` rows in `more` and on `Manage pseuds` / `Change username` in `prefs` (and the `ACCOUNT` header in `prefs` stays tiny), whereas Android retains leading row icons on all rows and scales the `ACCOUNT` header.
16. `dashboard` (Largest text / `big` column): Inside the `Two Voices at Dawn` card, Android renders the 2×2 AO3 rating/warning symbol grid on its own row below the author line, whereas iPhone hides the 2×2 symbol grid at the largest text size.
17. `browse` (Dark, Light, Sepia, OLED): Inside each category card, iPhone wraps `2 downloaded` onto a second metadata line below `4 fandoms  ~636K works`, whereas Android places all three counts on one line (and Android's `JUMP BACK IN` strip is scrolled right so the first card is clipped at the left edge).
18. `subs` (Largest text / `big` column): On iPhone, the `Authors` and `× Reset` filter chips are clipped at the right edge (`Autho…`, `× Rese…`), whereas on Android they fit without clipping.
19. `search` (all 5 columns): The section header is `Saved Searches` (Title Case) on iPhone vs `SAVED SEARCHES` (ALL CAPS) on Android.

---

## Per-screen findings

### `account`
- **From A69:**
  - `6+` badge on the **Subscriptions** shortcut tile and the **Subscriptions** row under `READING` on Android vs no count on iPhone (all columns): **still there** (demo subscription count difference).
  - AO3 logo on a white avatar circle and green checkmark circle next to `Signed in` on iPhone vs generic person-in-circle icon on a tinted circle and small green dot on Android (all columns): **still there**.
- **New:** None.

### `ao3coll`
- **From A69:**
  - Maintainer subtitle `AO3_Reader, comod` shown beneath `Winter Exchange 2026` on Android, omitted on iPhone (all columns): **still there**.
  - `Works / Bookmarks / People` segmented picker stays at default small text size on iPhone vs scaling with the largest text size on Android (`big` column): **still there**.
- **New:** None.

### `ao3colls`
- **From A69:**
  - Largest text (`big` column): on iPhone, `Your items` is clipped at the right edge, `YOU OWN` truncates to `YO…`, and the `Revealed` and `Anonymous` badges wrap character-by-character into 3-line vertical stacks (`Rev / eal / ed`, `Ano / nym / ous`), whereas Android fits `Your items` and wraps each badge onto its own horizontal row: **still there**.
  - Pager control style (`< Page 1 / 3 ⌃ >` centered pill on iPhone vs `<   Page 1 of 3   >` row on Android): **still there** (decided; ignored).
- **New:** None.

### `bookmarks`
- **From A69:**
  - Android shows `3 works · page 1 of 4` with a blurred `Tap to reveal` card at the top vs iPhone showing `2 works · page 1 of 4` without the blurred card: **changed** — **still there** in Light, Sepia, and `big` (demo data / mature-work blur vs hide), while Dark and OLED on Android now show a loading spinner (see New).
  - `REC` and `PRIVATE` badges are filled rounded pills on iPhone vs outlined rectangular boxes on Android: **still there** (in Light, Sepia, `big`).
  - Largest text (`big` column): on iPhone, `THE LOCKED TOMB` truncates to `THE LOCKED T…` and the `REC` pill stays tiny, whereas Android shows `THE LOCKED TOMB` in full and scales `REC`: **still there**.
  - Pager control style: **still there** (decided; ignored).
- **New:**
  - **Missing information / loading state (Dark, OLED):** Android shows a `Loading My AO3 Bookmarks` spinner card instead of the loaded Bookmarks screen.

### `browse`
- **From A69:**
  - `JUMP BACK IN` section missing on Android at largest text size (`big` column): **gone** (Android `big` now shows `JUMP BACK IN`).
  - Category cards showing `4 downloaded` on Android vs `2 downloaded` on iPhone: **gone** (both now show `2 downloaded`).
  - `JUMP BACK IN 4` and leading bar on `| Supernatural 312K` on Android vs `JUMP BACK IN 3` and `Supernatural 312K` without a bar on iPhone: **still there** (demo library difference; in Dark, Light, Sepia, and OLED the `JUMP BACK IN` strip on Android is also scrolled right so the first card is clipped at the left edge).
  - Category card metadata (`4 fandoms · ~636K works · 2 downloaded`) on 1 line on Android vs wrapping `2 downloaded` onto a second line on iPhone (Dark, Light, Sepia, OLED): **still there**.
- **New:** None.

### `collections`
- **From A69:**
  - Extra `(Restored)` duplicate collections on Android (`4 collections` vs `2 collections` on iPhone): **gone** (both now show `2 collections`).
  - Largest text (`big` column): iPhone keeps the 2×2 grid of vertical mini-covers inside the collection card (pushing `To recommend` below the fold), whereas Android reflows the preview into 4 stacked horizontal rows inside the card: **still there**.
- **New:** None.

### `dashboard`
- **From A69:**
  - `The Dawn Cycle` (`STAR WARS`) card under `RECENT SERIES` missing its green fandom wash on Android (all columns): **gone** (Android now renders the green fandom wash on the series card).
  - Largest text (`big` column): inside the `Two Voices at Dawn` card, Android renders the 2×2 AO3 symbol grid on its own row below the author line, whereas iPhone hides the 2×2 grid at the largest text size: **still there**.
- **New:** None.

### `deleted`
- **From A69:**
  - Duplicate `Lanterns Over Ba Sing Se` row on Android (`4 items` / `DELETED 3` vs `3 items` / `DELETED 2` on iPhone): **gone** (both now show `3 items`, `DELETED 2`, and `FINISHED, NOT KEPT 1`).
- **New:** None (the same).

### `drafts`
- **From A69:**
  - Expiry pills, `Created` footers, and `expiring this week` subtitle line (Dark, Light, Sepia, OLED): **still there** (decided; demo drafts difference).
  - `ON AO3` section header scaling in `big`: **changed** — on iPhone `big`, `ON AO3` stays tiny, while on Android `big` the `ON AO3` section and all draft cards are now missing (see New).
- **New:**
  - **Missing information (`big` column):** On Android at the largest text size, the top-right `+` button, the `page 1 of 2…` subtitle, the `ON AO3` section header, and all draft cards are missing (only the `AO3 deletes an unposted draft…` banner is shown above blank space).

### `history`
- **From A69:**
  - Extra `Anonymous` author line inside each history cover card on Android (all columns): **gone** (Android now omits `Anonymous` on these cover cards, matching iPhone).
- **New:**
  - **Missing information / loading state (Dark, OLED):** Android shows a `Loading My AO3 History` spinner card instead of the loaded History screen.
  - **Order (Light, Sepia):** On Android, `THIS MONTH 1` (`Nine Hours in…`) is ordered **after** `EARLIER 1` (`THIS WEEK 1` → `EARLIER 1` → `THIS MONTH 1`).

### `home`
- **From A69:**
  - Duplicate `Neon reread` queue and extra restored items on Android (`CONTINUE READING 5` / `READING QUEUES 6`): **gone** (Android now shows `CONTINUE READING 3` and `READING QUEUES 3` with a single `Neon reread`).
  - Hero card showing `Last opened` on Android vs chapter title `Chapter 2: Nine Minutes` on iPhone: **changed / unsure** — Android's hero card in the fresh demo state is now `Sodium Lights` (`1/1`), which shows `Last opened`, while `Winter Garden` (`4/6`) is the second mini-card, so it is not visible from this capture whether a multi-chapter hero card on Android still shows `Last opened`.
- **New:** None (Sepia blank capture and OLED empty `Reading Queues` capture on Android ignored as known misses).

### `inbox`
- **From A69:**
  - `↩ Reply` styled as plain text on Android vs a filled pill button on iPhone (Dark, Light, Sepia, OLED): **gone** (Android now renders `↩ Reply` as a filled pill button).
  - `1` badge on the top-right filter icon on Android vs unbadged filter icon on iPhone (Dark, Light, Sepia, OLED): **gone** (Android no longer shows the `1` badge).
  - Extra `User` badge beneath `• ReaderOne` on Android in `big`: **changed / unsure** — `Android big` now shows a `Loading Inbox` spinner instead of the loaded comment list (see New).
  - Pager control style: **still there** (decided; ignored).
- **New:**
  - **Missing information / loading state and overlap (`big` column):** At the largest text size, Android shows a `Loading Inbox` spinner card instead of the loaded Inbox screen (with top-right filter/`⋮` buttons absent) and the top-left `←` back arrow overlaps `AO3 ACCOUNT`.

### `insights`
- **From A69:**
  - Android showing `0.1 hours in October` (`THIS MONTH 2`, `WHERE THE HOURS WENT 2`, `PACE AND FOLLOW-THROUGH`) vs iPhone's `No reading logged this month` + `YOUR LIBRARY 4` + `MOST-READ FANDOMS 5` (all columns): **gone** (both now show `No reading logged this month`, `YOUR LIBRARY 4`, and `MOST-READ FANDOMS 5`).
  - `Frozen (Disney Movies)` truncation in `WHERE THE HOURS WENT 2` on Android `big`: **gone**.
- **New:** None (the same).

### `later`
- **From A69:**
  - `Unmark` pill button placed outside and below each work card on Android vs inside the bottom-right corner of each card on iPhone (Dark, Light, Sepia, OLED): **gone** (Android now places `Unmark` inside the bottom-right corner of each card).
- **New:**
  - **Missing information / loading state (`big` column):** At the largest text size, Android shows a `Loading Marked for Later` spinner card (without the `AO3 ACCOUNT / Marked for Later` header or filter icon) instead of the loaded `Marked for Later` screen.

### `library`
- **From A69:**
  - Extra restored duplicates on Android (`READING NOW 5`, `SAVED FOR LATER 6` with `A suitor for you` / `A_suitor_for_you`, `FINISHED 4`): **gone** (both now show `SAVED FOR LATER 2` with `Paper Cranes` and `Stars Over Tatooine`, and top fandom chips starting `All`, `Avatar: The Last Airbender`, `Doctor Who`).
  - Largest text (`big` column): progress ring label inside the first `READING NOW` cover card stays small on iPhone (`50% READING`) vs scaling up on Android (`42% READING`): **still there**.
- **New:**
  - **Layout / overlap (Dark):** In the Dark column on Android, the `Library` heading overlaps directly on top of the `All` and `Avatar: The Last Airbender` filter chips, the top-right `+`, filter, and `⋮` buttons are missing, and the top fandom wash is absent.
  - **Layout (all columns):** The top fandom filter chips (`All`, `Avatar: The Last Airbender`, `Doctor Who`) are rounded capsule pills on iPhone vs rectangular outlined boxes on Android.

### `more`
- **From A69:**
  - Largest text (`big` column): leading row icons under `POST AND MANAGE` disappear on iPhone at the largest text size while remaining visible on Android: **still there**.
  - More compact vertical spacing on Android revealing `YOUR ACCOUNT` / `Profile` at the bottom of Dark, Light, Sepia, and OLED (below the fold on iPhone): **still there**.
- **New:** None.

### `prefs`
- **From A69:**
  - Row order under `ACCOUNT` (`Blocked Users` and `Muted Users` placed before `Change Username / Password / Email` on Android): **gone** (Android now matches iPhone's order in Dark, Light, OLED, and `big`).
  - Title Case and `My` in row labels (`Edit My Profile`, `Manage My Pseuds`, etc.) on Android vs sentence case without `My` on iPhone: **gone** (Android now uses sentence case without `My`).
  - Largest text (`big` column): `ACCOUNT` header stays tiny and leading icons disappear on `Manage pseuds` and `Change username` on iPhone vs scaled header and icons retained on all rows on Android: **still there**.
- **New:**
  - **Missing information / loading state (Sepia):** In the Sepia column on Android, a `Loading AO3 preferences...` spinner card is shown instead of the loaded AO3 Preferences screen.

### `queues`
- **From A69:**
  - Duplicate `Neon reread` and `Slow burns` queues on Android (`7 QUEUES` vs `5 QUEUES`): **gone** (duplicates removed; Android now shows `4 QUEUES` with `Saved for Later 2`, `Neon reread 5`, `Slow burns 4`, `Case fic pile 3`).
  - Largest text (`big` column): iPhone reflows the 4-stat summary card into a 2×2 grid and keeps the search bar placeholder unclipped, whereas Android keeps all 4 stats on 1 row and clips `Search queues, tags and`: **still there**.
- **New:** None.

### `search`
- **From A69:**
  - Extra second saved-search card and trailing trash-can delete icon on Android (all columns): **gone** (Android now shows 1 saved-search card with no trailing delete icon).
  - Bottom tab bar shown on Android vs hidden on iPhone (all columns): **gone** (bottom tab bar now hidden on Android too).
  - Section heading `Saved Searches` (Title Case) on iPhone vs `SAVED SEARCHES` (ALL CAPS) on Android (all columns): **still there**.
- **New:** None.

### `settings`
- **From A69:**
  - `Appearance` row trailing value showing `Light` in all 5 columns on Android vs matching the active column theme (`Dark`, `Light`, `Sepia`, `OLED`, `Sepia`) on iPhone: **still there**.
- **New:** None.

### `subs`
- **From A69:**
  - `NEW SINCE YOU LAST LOOKED` / `ALL WORKS` sections, stats lines, chapter ranges, and `Unsubscribe` buttons: **changed** — still present in Light, Sepia, and `big` (decided; sparser demo data on iPhone), but in **Dark** and **OLED** on Android the `2 with new chapters` count and **both** section headers (`NEW SINCE YOU LAST LOOKED` and `ALL WORKS`) are missing, leaving the work cards with no section header at all (while iPhone shows `ALL WORKS 2`).
  - Largest text (`big` column): `Authors` and `× Reset` chips are clipped at the right edge on iPhone vs fitting in full on Android: **still there**.
  - Pager control style: **still there** (decided; ignored).
- **New:**
  - **Missing information (Dark, OLED):** On Android in Dark and OLED, the `ALL WORKS` section header above the subscription cards is omitted (and in Dark all 3 cards render without fandom/stats while in OLED the 1st card renders without fandom/stats and the 2nd and 3rd render with fandom/stats).

### `works`
- **From A69:**
  - Subtitle under `Works` (`3 works · 248,400 words · 3,812 kudos` on Android vs `AO3_Reader` on iPhone): **gone** (Android now shows `AO3_Reader` under `Works` in all 5 columns).
  - Missing `WORKS 3` section header, floating `⋮` button above each card, 4-column stats bar (`KUDOS · COMMENTS · HITS · BOOKMARKS` vs `KUDOS · HITS`), and largest-text filter chip clipping (`Gifts` / `The Locked Tomb (3)`): **changed / unsure** — in all 5 columns, Android shows a `Loading...` spinner card below `AO3_Reader`, hiding the filter chips and work cards (see New).
- **New:**
  - **Missing information / loading state (all 5 columns):** Android shows a `Loading...` spinner card below `AO3_Reader` (and omits the checklist/select action icon in the top bar) instead of the loaded Works list in Dark, Light, Sepia, OLED, and `big`.


