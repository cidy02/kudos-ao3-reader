# A70c: 15 Android screens retaken, checked against A70

## Still to fix

1. `history` (Dark, Light, Sepia, OLED): `THIS MONTH 1` is ordered after `EARLIER 1` (`THIS WEEK 1` → `EARLIER 1` → `THIS MONTH 1`) on Android, whereas iPhone orders sections chronologically.
2. `works` (all 5 columns): The subtitle under `Works` is `3 works · 248,400 words · 3,812 kudos` on Android vs `AO3_Reader` on iPhone.
3. `works` (Dark, Light, Sepia, OLED): Work cards on Android show a 4-column stats bar (`KUDOS · COMMENTS · HITS · BOOKMARKS`) and a bottom-right `⋮` button inside each card, whereas iPhone shows a 2-column stats bar (`KUDOS · HITS`) and no per-card `⋮` button.
4. `works` (Dark, OLED): The selected `Works` filter chip is filled with bright red with white text on Android, whereas iPhone (and Android's `All` fandom chip directly below) uses the theme's muted rose/pink chip fill with dark text.
5. `account` (all 5 columns): The account avatar circle shows a generic person-in-circle icon on a tinted background on Android vs the AO3 logo on a white circle on iPhone.
6. `browse` (Dark, Light, Sepia, OLED): Inside each category card, Android places `4 fandoms · ~636K works · 2 downloaded` on a single line and draws a leading vertical bar inside `| Supernatural 312K`, whereas iPhone wraps `2 downloaded` onto a second line and omits the leading bar on `Supernatural 312K`.
7. `queues` (Sepia at largest text / `big`): The search bar placeholder is clipped at the right edge (`Search queues, tags and`) on Android, whereas it fits in full on iPhone.
8. `works` (Sepia at largest text / `big`): On iPhone, the `Gifts` chip on the first filter row is pushed off-screen and `The Locked Tomb (3)` clips to `T…`, whereas on Android `Gifts` fits and `The Locked Tomb (3)` clips to `The Locke…`.
9. `subs` (Sepia at largest text / `big`): On iPhone, the `Authors` and `× Reset` filter chips are clipped at the right edge (`Autho…`, `× Rese…`), whereas on Android they fit in full.
10. `bookmarks` (Sepia at largest text / `big`): On iPhone, `THE LOCKED TOMB` truncates to `THE LOCKED T…` and the `REC` pill stays tiny, whereas Android shows `THE LOCKED TOMB` in full and scales `REC`.
11. `prefs` (Sepia at largest text / `big`): On iPhone, the `ACCOUNT` section header stays tiny and leading row icons disappear on `Manage pseuds` and `Change username`, whereas Android scales `ACCOUNT` and keeps leading icons on all rows.
12. `drafts` (Sepia at largest text / `big`): On iPhone, the `ON AO3` section header stays tiny instead of scaling with the largest text size, whereas on Android it scales.
13. `library` (Sepia at largest text / `big`): Inside the first `READING NOW` cover card, the progress ring label stays small on iPhone (`50% READING`) vs scaling up on Android (`42% READING`).
14. `dashboard`, `drafts`, `works` (Sepia at largest text / `big`): Inside work cards at the largest text size, Android renders the 2×2 AO3 rating/warning symbol grid on its own row below the title/author line, whereas iPhone hides the 2×2 symbol grid.

---

## Per-screen findings

### `account`
1. **Loading / blank / wrong screen:** None.
2. **A70 items:**
   - AO3 logo on a white circular avatar and green checkmark circle next to `Signed in` on iPhone vs generic person-in-circle icon on a tinted circle and small green dot on Android (all columns): **changed** — Android now shows a green checkmark-in-circle symbol next to `Signed in` (matching iPhone), while the avatar circle still shows a generic person-in-circle icon on a tinted circle on Android vs the AO3 logo on a white circle on iPhone.
   - `6+` badge on Subscriptions shortcut tile and row (demo data): **still there** (ignored).
3. **New:** None.

### `bookmarks`
1. **Loading / blank / wrong screen:** None (`Dark` and `OLED` now load cleanly).
2. **A70 items:**
   - `Loading My AO3 Bookmarks` spinner card in `Dark` and `OLED` on Android: **gone**.
   - `REC` and `PRIVATE` badges styled as outlined rectangular boxes on Android vs filled rounded pills on iPhone: **gone** (now rounded pills on Android in all 5 columns).
   - Largest text (`big` column): on iPhone, `THE LOCKED TOMB` truncates to `THE LOCKED T…` and `REC` stays tiny, whereas Android shows `THE LOCKED TOMB` in full and scales `REC`: **still there**.
   - `3 works` with a blurred `Tap to reveal` card on Android vs `2 works` on iPhone (demo data): **still there** in all 5 columns (ignored).
3. **New:** None.

### `browse`
1. **Loading / blank / wrong screen:** None.
2. **A70 items:**
   - `JUMP BACK IN` strip scrolled right with the first card clipped at the left edge on Android (`Dark`, `Light`, `Sepia`, `OLED`): **gone** (first card is now aligned cleanly at the left edge in all columns).
   - Category card metadata (`4 fandoms · ~636K works · 2 downloaded`) on one line on Android vs wrapping `2 downloaded` onto a second line on iPhone (`Dark`, `Light`, `Sepia`, `OLED`): **still there**.
   - Leading vertical bar on `| Supernatural 312K` on Android vs no leading bar on `Supernatural 312K` on iPhone (all columns): **still there**.
3. **New:** None.

### `dashboard`
1. **Loading / blank / wrong screen:** None.
2. **A70 items:**
   - Largest text (`big` column): inside `Two Voices at Dawn`, Android renders the 2×2 AO3 symbol grid on its own row below the author line, whereas iPhone hides the 2×2 symbol grid at the largest text size: **still there**.
3. **New:** None.

### `drafts`
1. **Loading / blank / wrong screen:** None (`big` now loads the full screen).
2. **A70 items:**
   - Missing `+` button, `page 1 of 2…` subtitle, `ON AO3` section header, and draft cards in `big` on Android: **gone** (all are now rendered in `big`).
   - `ON AO3` section header staying tiny on iPhone in `big` vs scaling on Android in `big`: **still there**.
   - Expiry pills, `Created` footers, and `expiring this week` subtitle line (decided): **still there** (ignored).
3. **New:**
   - Largest text (`big` column): inside the first draft card (`Lanterns Above the Mill`), Android renders the 2×2 AO3 symbol grid on its own row below the title, whereas iPhone hides the 2×2 symbol grid at the largest text size.

### `history`
1. **Loading / blank / wrong screen:** None (`Dark` and `OLED` now load cleanly).
2. **A70 items:**
   - `Loading My AO3 History` spinner card in `Dark` and `OLED` on Android: **gone**.
   - Section order (`THIS MONTH 1` ordered after `EARLIER 1` on Android): **still there** — and now visible across `Dark`, `Light`, `Sepia`, and `OLED` (`THIS WEEK 1` → `EARLIER 1` → `THIS MONTH 1`).
3. **New:** None.

### `home`
1. **Loading / blank / wrong screen:** None (`Sepia` and `OLED` now render the full Home screen matching the other columns).
2. **A70 items:**
   - Hero card showing `Last opened` on Android (`Sodium Lights`, `1/1`) vs chapter title `Chapter 2: Nine Minutes` on iPhone (`Winter Garden`, `4/6`): **still there / unsure** (demo hero work is single-chapter on Android).
   - Blank `Sepia` capture and empty `Reading Queues` in `OLED` on Android: **gone**.
3. **New:** None.

### `inbox`
1. **Loading / blank / wrong screen:** None (`big` now loads the full Inbox screen).
2. **A70 items:**
   - `Loading Inbox` spinner card, missing top-right filter/`⋮` buttons, and `←` overlapping `AO3 ACCOUNT` in `big` on Android: **gone**.
   - Extra `User` badge beneath `• ReaderOne` in `big` on Android (from A69, obscured by loading in A70): **gone** (`• ReaderOne` has no `User` badge in `big`).
3. **New:** None.

### `later`
1. **Loading / blank / wrong screen:** None (`big` now loads the full `Marked for Later` screen).
2. **A70 items:**
   - `Loading Marked for Later` spinner card (and missing header/filter icon) in `big` on Android: **gone**.
3. **New:** None.

### `library`
1. **Loading / blank / wrong screen:** None.
2. **A70 items:**
   - `Library` heading overlapping filter chips, missing `+`/filter/`⋮` buttons, and missing top fandom wash in `Dark` on Android: **gone**.
   - Top fandom filter chips (`All`, `Avatar: The Last Airbender`, `Doctor Who`) styled as rectangular outlined boxes on Android vs rounded capsule pills on iPhone (all columns): **gone** (now rounded capsule pills on Android in all 5 columns).
   - Largest text (`big` column): progress ring label inside the first `READING NOW` cover card stays small on iPhone (`50% READING`) vs scaling up on Android (`42% READING`): **still there**.
3. **New:** None.

### `prefs`
1. **Loading / blank / wrong screen:** None (`Sepia` now loads the full `AO3 Preferences` screen).
2. **A70 items:**
   - `Loading AO3 preferences...` spinner card in `Sepia` on Android: **gone**.
   - Largest text (`big` column): `ACCOUNT` header stays tiny and leading icons disappear on `Manage pseuds` and `Change username` on iPhone vs scaled header and leading icons retained on all rows on Android: **still there**.
3. **New:** None.

### `queues`
1. **Loading / blank / wrong screen:** None.
2. **A70 items:**
   - Largest text (`big` column): 4-stat summary card kept on 1 row and search bar placeholder clipped (`Search queues, tags and`) on Android vs 2×2 stat grid and unclipped placeholder on iPhone: **changed** — Android now reflows the 4-stat summary card into two rows of two (`QUEUES` / `WORKS` over `OFFLINE` / `STORAGE`, matching iPhone), while the search bar placeholder on Android in `big` is still clipped (`Search queues, tags and`).
3. **New:** None.

### `search`
1. **Loading / blank / wrong screen:** None.
2. **A70 items:**
   - Section heading `SAVED SEARCHES` (ALL CAPS) on Android vs `Saved Searches` (Title Case) on iPhone (all columns): **gone** (Android now uses `Saved Searches` in Title Case across all 5 columns, and the saved-search card matches iPhone's layout).
3. **New:** None.

### `subs`
1. **Loading / blank / wrong screen:** None (`Dark` and `OLED` now load the full Subscriptions list with headers and card stats).
2. **A70 items:**
   - Missing `2 with new chapters` count, missing `NEW SINCE YOU LAST LOOKED` and `ALL WORKS` section headers, and missing fandom/stats on cards in `Dark` and `OLED` on Android: **gone** (`Dark` and `OLED` now match `Light` and `Sepia` with full headers and stats).
   - Largest text (`big` column): `Authors` and `× Reset` filter chips clipped at the right edge on iPhone (`Autho…`, `× Rese…`) vs fitting in full on Android: **still there**.
3. **New:** None.

### `works`
1. **Loading / blank / wrong screen:** None (all 5 Android columns now load the full Works screen).
2. **A70 items:**
   - `Loading...` spinner card below `AO3_Reader` (and missing select icon in top bar) across all 5 columns on Android: **gone** (all 5 columns now show the loaded Works screen and top-bar select icon).
   - Subtitle under `Works`: **changed** — in A70, Android showed `AO3_Reader` while in the loading state; now that loading finishes, Android again shows `3 works · 248,400 words · 3,812 kudos` in all 5 columns vs `AO3_Reader` on iPhone.
   - Items from A69 that were obscured by the loading state in A70:
     - Missing `WORKS 3` section header on Android: **gone** (`WORKS 3` is now shown in all 5 columns).
     - Floating `⋮` button above each work card on Android: **changed** — the `⋮` button is no longer floating above the card, but is now placed inside the bottom-right corner of each card (`Dark`, `Light`, `Sepia`, `OLED`), whereas iPhone has no `⋮` button on the card.
     - 4-column stats bar (`80 KUDOS | 8 COMMENTS | 900 HITS | 30 BOOKMARKS`) on Android vs 2-column stats bar (`80 KUDOS | 900 HITS`) on iPhone (`Dark`, `Light`, `Sepia`, `OLED`): **still there**.
     - Largest text (`big` column) filter chip clipping (`Gifts` pushed off-screen and `The Locked Tomb (3)` clipped to `T…` on iPhone vs `Gifts` fitting and `The Locked Tomb (3)` clipped to `The Locke…` on Android): **still there**.
3. **New:**
   - **Theme (`Dark`, `OLED`):** On Android, the selected `Works` filter chip is filled with bright red with white text in `Dark` and `OLED`, whereas iPhone (and Android's own selected `All` fandom chip directly below it) uses the muted rose/pink fill (`#E5989B`) with dark text.
   - **Largest text (`big` column):** Inside the first work card (`The Cartographer's "Second" Tide & 星`), Android renders the 2×2 AO3 symbol grid on its own row below `by Writer`, whereas iPhone hides the 2×2 symbol grid at the largest text size.
