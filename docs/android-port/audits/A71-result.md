# A71: iPhone and Android — Second Batch of Screens

## Differences worth fixing

1. `reader` (Dark, Sepia, OLED, Largest text / `big` columns): Android draws the reader with a white Light-theme background and black text in every column, whereas iPhone renders Dark (charcoal), Sepia/`big` (warm cream), and OLED (pure black).
2. `queue` (all 5 columns: Dark, Light, Sepia, OLED, Largest text): Capture problem — Android captured the `HOME › QUEUES › QUEUE DETAILS` edit/settings sub-screen (`DESCRIPTION`, `TAGS`, `DETAILS`), whereas iPhone captured the `HOME › QUEUES` reading queue screen (`UP NEXT`, `IN LINE 4` cover grid).
3. `chprompts` (Largest text / `big` column): Capture problem — iPhone captured the parent `COLLECTION / Winter Exchange 2026` overview screen instead of `Prompts`.
4. `sec_history` (Dark, Light, Sepia, OLED): iPhone renders compact single-row history cards with a leading circular progress ring (`0%`, `42% READING`, `20% READING`) and short `author · words · chapters` line (fitting `TODAY 3` and `YESTERDAY 3` on screen), whereas Android renders full-height cards without a progress ring, adding `by <author>`, summary text, full stats, a favorite star on `Sodium Lights`, and an expand chevron (pushing `YESTERDAY 3` off screen, with `12 works` vs `11 works`).
5. `sec_favorites` (Dark, Light, Sepia, OLED): iPhone renders compact cards with a leading circular progress ring (`42% READING`, `71% READING`) and single-line `author · words · chapters`, whereas Android renders full-height cards without a progress ring, adding `by <author>`, summary text, full stats, and an expand chevron.
6. `author` (all 5 columns): Android uses a cyan/teal-blue top wash in all 5 columns (including Sepia and Largest text, where the top half stays light blue instead of sepia) vs iPhone's burgundy/maroon wash (and warm tan in Sepia/`big`), replaces iPhone's `Scope: All Pseuds ⌄` row with inline pseud pills (`All Pseuds`, `Avery Writes`, `NightShift`), and adds an extra `Works / In collections / Gifts` pill row below the segmented tabs; in Largest text (`big`), iPhone stretches the `Subscribe` button into a giant vertical pillar without text (pushing everything below it off screen) while Android vertically clips the `Subscribe` label and clips `NightShift` / `The Locked Tomb (3)`.
7. `myseries` (all 5 columns): Below `Series`, Android omits the `AO3_Reader` subtitle and `SERIES 2` section header shown on iPhone and instead prints `5 works, 54,679 words in the 2 loaded series` twice in a row, and adds a `⋮` button on `The Dawn Cycle` card.
8. `welcome`, `synconb` (Largest text / `big` column): On iPhone, the scaled header and pinned bottom bar occupy the entire viewport, completely hiding all 4 feature/info rows in the middle of both screens (and truncating `Don't remin...` and `Choose S...` on `synconb`), whereas on Android the bottom action bar is pushed off the bottom of the screen instead of staying pinned.
9. `chsignups`, `chassign`, `chmysignup` (Largest text / `big` column): On iPhone, the bottom action buttons (`Your sign-up` / `Create sign-up`, `Report a default` / `Claim a pinch hit`, `Add request` / `Submit sign-up`) float without a solid bar background directly on top of the underlying list/card text; on Android, `All / Matched / Unmatched` (`chsignups`) and `Matched / Unmatched / Pinch hits` (`chassign`, where `Pinch hits` clips at the right edge) turn from a segmented bar into 3 separate pills.
10. `sec_history`, `sec_favorites`, `chprompts` (Largest text / `big` column): On Android, the multi-segment picker (`Time / State / Fandom / Flat`, `Works / Authors / Fandoms / Tags`, `All / Unclaimed / Yours`) stacks vertically into 3–4 full-width rows inside a card, whereas on iPhone it stays on a single horizontal row at small text size.
11. `sec_finished` (all 5 columns): The two cards under `FINISHED 2` are in opposite order (`Tea in the Jasmine Dragon` then `What the River Keeps` on iPhone vs `What the River Keeps` then `Tea in the Jasmine Dragon` on Android), and `Tea in the Jasmine Dragon` shows `🕒 WIP` with `💬 0 · ♥ 0 · 🔖 0 · 👁 0` on iPhone vs `✓ Complete` with only `♡ 0` on Android.
12. `collection`, `sec_downloaded`, `sec_favorites`, `sec_finished`, `sec_history`, `sec_later`, `sec_reading` (all 5 columns): In the bottom tab bar on all six `LIBRARY` section screens and `collection`, iPhone highlights `Library` as the active tab whereas Android highlights `Home` as the active tab.
13. `whatsnew` (all 5 columns): iPhone presents `What's New` (`Version 1.0`) as a full-height modal sheet with a centered title, whereas Android presents `What's New` (`Version 0.2.1`) as a short bottom sheet covering only the bottom quarter of the screen with a left-aligned title.
14. `mycopy` (Dark, Light, Sepia, OLED): Android uses much taller vertical row/section spacing without row dividers, pushing `ACTIVITY`, `ORIGIN`, and `MY TAGS` completely off the bottom of the screen (all visible on iPhone), and shows `— PROGRESS` instead of `0% PROGRESS`.
15. `workdetail` (all 5 columns): Inside the primary reading card, iPhone shows a progress ring, `Chapter 1: The Arcade`, and `25/26 minutes ago` next to the play button, whereas Android shows only `Read` and the play button (and in `big`, Android truncates `呪術廻戦 | Jujutsu Kaisen (Manga)`).
16. `comments` (all 5 columns): Header work title is `Sodium Lights` on iPhone vs `A Test Work` on Android; in Dark/Light/Sepia/OLED, Android shows a filled `↩ Reply` pill button instead of iPhone's icon-only `↩` arrow, adds a `Chapter 3` badge on `Calytrix Author`'s nested reply, and collapses `StarrySky`'s two paragraphs onto one line; in `big`, Android truncates `⇅ Newe...` while iPhone's floating `Write a comment` button overlaps `All comments ⌄`.
17. `chsignups`, `chassign`, `chmysignup`, `chsettings`, `colmaint`, `colmod`, `colsettings` (all 5 columns): Challenge and collection management screens display different demo fixture data/counts between iPhone and Android (plus `colsettings` on Android lacks iPhone's burgundy top wash in Dark/Light/OLED and clips `Tagline`, and `chassign` on Android adds a top-right `↻` button and styles `Open on AO3` as plain text instead of a pill button).
18. `collection`, `hsec_reading`, `hsec_updated`, `sec_downloaded`, `sec_finished`, `sec_later`, `sec_reading` (all 5 columns): On work cards, iPhone shows `by <author>` in muted grey and includes zero-count `💬 0` / `🔖 0` stats without an expand chevron, whereas Android omits `by ` (coloring the author name), hides zero-count stats, adds a bottom-right expand chevron (`⌄`), and uses noticeably more saturated pastel card fills in Light, Sepia, and `big` (plus brown-tinted cards in Dark/OLED on `sec_later`).
19. `workedit`, `draftedit` (Largest text / `big` column): On iPhone, the `Title *` field value truncates (`The Weight o...`, `Lanterns Abo...`), whereas Android shows the full title without truncation.

---

## Per-screen findings

### `author`
- **Theme (all 5 columns):** iPhone uses a burgundy/maroon header wash in Dark/Light/OLED and a warm tan header in Sepia/`big`, whereas Android uses a cool cyan/teal-blue top wash in all 5 columns (including Sepia and `big`, where the top half of the screen remains light blue instead of sepia). On the second work card (`A Name Withheld`), the card wash is neutral grey on iPhone vs teal-green on Android.
- **Missing or extra information (all 5 columns):**
  - iPhone shows a `Scope: All Pseuds ⌄` dropdown row, whereas Android shows inline horizontal chips (`All Pseuds`, `Avery Writes`, `NightShift`).
  - Android shows an extra sub-tab pill row (`Works`, `In collections`, `Gifts`) below the `Works / Series / Bookmarks / About` segmented bar that iPhone does not have.
  - iPhone shows the AO3 logo on a white avatar square and a raised-hand block button, whereas Android shows a generic person-in-box icon and a `⊘` icon.
  - On `Two Voices at Dawn`, iPhone shows `0 comments` and `0 bookmarks` (`07/09/2026`) whereas Android shows `8 comments` and `30 bookmarks` (`09 Jul 2026`). On `A Name Withheld`, iPhone shows grey placeholder badges in the 2×2 AO3 grid and no visible stats line, whereas Android shows colored badges and the full stats line (`English · 2,000 words · 1/? · 2 comments · 120 kudos · 10 bookmarks · 300 hits · 08 Jul 2026`).
- **Largest text (`big` column):**
  - On iPhone, `Avery_Archive` hyphenates across lines (`Av- / ery_Archive`) and the `Subscribe` pill stretches into a tall vertical column with only a bell icon (missing the `Subscribe` label), pushing `Scope`, tabs, and works completely off-screen.
  - On Android, the `Subscribe` label is vertically clipped inside a short pill, `NightShift` clips at the right edge (`Nig`), `The Locked Tomb (3)` clips at the right edge (`The Locke`), and the 4 segmented tabs (`Works / Series / Bookmarks / About`) wrap into a 2×2 grid.

### `collection`
- **Missing or extra information (all 5 columns):**
  - On each work card, iPhone shows `by poknn` / `by origamist` in muted grey, whereas Android omits `by ` (`poknn` / `origamist`) and colors the author in orange/brown.
  - On `Unanswered Is Not Unread`, the 4th badge is `? Unknown` on iPhone vs `🕒 WIP` on Android, and iPhone includes `💬 0` and `🔖 0` in the stats row whereas Android omits zero-count stats and adds a bottom-right expand chevron (`⌄`).
  - In the bottom tab bar, `Library` is selected on iPhone whereas `Home` is selected on Android.
- **Theme (Light, Sepia, `big`):**
  - The `Unanswered Is Not Unread` card fill is a much stronger periwinkle-blue on Android than the soft pale tint on iPhone.
- **Largest text (`big` column):**
  - On iPhone, the fandom line truncates on 1 line (`Avatar: The L...`) next to a large icon, whereas on Android it wraps across 2 lines (`Avatar: The Last / Airbender, The Legend ...`) next to a tiny icon.

### `colmaint`
- **Missing or extra information (all 5 columns):**
  - Subtitle and people list differ: iPhone shows `winter_exchange · 3 people` with owners `AO3_Reader`, `saltandsilver` and 1 moderator (`meridian`), whereas Android shows `winter_exchange · 4 people` with owners `AO3_Reader`, `frostledger` and 2 moderators (`emberpost`, `duskatlas`).
- **Theme (Dark, Light, Sepia, OLED):**
  - The `Invite as` value `Moderator ⌄` is tinted teal on iPhone vs red/brown on Android.

### `colmod`
- **Missing or extra information (all 5 columns):**
  - iPhone shows `2 works awaiting review · 2 membership requests` and `AWAITING REVIEW 2` (`Queued Work`, `Another Queued Work`, without submission dates), followed by `Recently decided`, `MEMBERSHIP REQUESTS 2` (`paperlanterns`, `quietharbour`), and `MAINTAINERS` (`Owners and moderators 3 >`).
  - Android shows `3 works awaiting review on this page · page 1 of 2 · 2 membership requests` and `AWAITING REVIEW 3` (`The Lantern Ledger`, `The Snowbound Post Office`, `A Map of Warm Windows`, each with `· submitted <date>`), followed by a `< Page 1 of 2 >` pager bar, which pushes `MEMBERSHIP REQUESTS 2` and `MAINTAINERS` below the fold.

### `colsettings`
- **Theme (Dark, Light, OLED):**
  - iPhone renders a burgundy/maroon top wash behind `Edit collection`, whereas Android uses a flat neutral background with no top wash.
- **Missing or extra information (all 5 columns):**
  - All form values differ between the two fixtures (`Winter Fest` / `fest` / `parent_fest` / `mod@example.com` / `Coastal fic, all fandoms` / `Closed to new items: ON` on iPhone vs `Winter Exchange 2026` / `winter_exchange` / `None` / `winterquill@example.invalid` / `A fictional exchange of warm l` (clipped) / `Closed to new items: OFF` on Android).

### `comments`
- **Missing or extra information:**
  - Work title in the header is `Sodium Lights` on iPhone vs `A Test Work` on Android (all 5 columns).
  - Under each comment (Dark, Light, Sepia, OLED), iPhone shows an icon-only reply arrow (`↩`), whereas Android shows a filled pill button with text (`↩ Reply`).
  - On the nested reply by `Calytrix Author` (Dark, Light, Sepia, OLED), Android shows a `Chapter 3` badge next to `Jul 8, 2026`, whereas iPhone shows only `Jul 8, 2026`.
- **Layout:**
  - In `StarrySky`'s comment (Dark, Light, Sepia, OLED), iPhone renders `That quiet thank you said everything.` and `Absolutely broke me.` as two separate paragraphs, whereas Android merges them onto one line.
- **Largest text (`big` column):**
  - On Android, the sort chip `⇅ Newest ⌄` truncates to `⇅ Newe...`.
  - On iPhone, the floating `Write a comment` button overlaps the `All comments ⌄` filter pill.

### `hsec_reading`
- **Missing or extra information (all 5 columns):**
  - On `Sodium Lights` (and `Winter Garden`), iPhone shows `by nine_of_wands` in muted grey and includes `💬 0` and `🔖 0` in the stats line, whereas Android omits `by ` (`nine_of_wands` in orange/brown), omits zero-count stats, and adds a bottom-right expand chevron (`⌄`).
- **Theme (Light, Sepia, `big`):**
  - The `Sodium Lights` card background is a more saturated lavender-purple (and `Winter Garden` a brighter mint green) on Android than the subtle pastel wash on iPhone.
- **Largest text (`big` column):**
  - On iPhone, `by nine_of_wands` clips at the right edge (`by nine_of_wan`).

### `hsec_updated`
- **Missing or extra information (Dark, Light, Sepia, OLED):**
  - On `Winter Garden`, iPhone shows `by frostbitten` in muted grey and includes `💬 0` and `🔖 0` in the stats row, whereas Android omits `by ` (`frostbitten` in orange/brown), omits zero-count stats, and adds a bottom-right expand chevron (`⌄`).
- **Theme (Light, Sepia):**
  - The `Winter Garden` card background is a more saturated green on Android than on iPhone.
- **Largest text (`big` column):**
  - On iPhone, the `Tap to reveal` button on the blurred card (`Ashfall`) is covered by the bottom tab bar, whereas on Android it is visible in the center of the blurred card.

### `mycopy`
- **Missing or extra information / Layout (Dark, Light, Sepia, OLED):**
  - Top-left stat cell reads `0% PROGRESS` on iPhone vs `— PROGRESS` on Android (all 5 columns).
  - Android uses much taller row heights and section gaps (with no horizontal row dividers) across `STATUS`, `QUEUES`, `COLLECTIONS`, and `STORAGE`, which pushes the `ACTIVITY`, `ORIGIN`, and `MY TAGS` sections completely below the fold (all three are visible on iPhone).

### `queue`
- **Capture problem / different screen (all 5 columns):**
  - iPhone shows the `HOME › QUEUES` reading queue screen (`Neon reread` with `UP NEXT` `Sodium Lights` card, `IN LINE 4` 2×2 cover grid, top-right `+`/filter/`⋯` buttons, and bottom tab bar), whereas Android captured the `HOME › QUEUES › QUEUE DETAILS` edit/settings sub-screen (`DESCRIPTION`, `TAGS`, `DETAILS: Colour / Keep works offline / Order / Last read`, `Manage all tags`).
  - Also on Android `big`, `HOME › QUEUES › QUEUE DETAILS` truncates to `HOME › QUEUES › QUEUE DETAI...` (and total size reads `14 KB` on Android vs `12 KB` on iPhone).

### `reader`
- **Theme (Dark, Sepia, OLED, Largest text / `big`):** On Android, all 5 columns render with the **Light** theme (pure white background and black text), ignoring `Dark`, `Sepia`, and `OLED`, whereas iPhone renders `Dark` (charcoal background), `Sepia` and `big` (warm cream background), and `OLED` (pure black background).

### `chassign`
- **Missing or extra information (all 5 columns):**
  - Android has a top-right refresh button (`↻`) that iPhone does not have.
  - iPhone shows `8 matched · 4 unmatched · works due Mar 1, 2026` and `UNMATCHED SIGN-UPS 4` (`Recipient and Bob`, `Casey and An anonymous sign-up`), whereas Android shows `5 matched · 3 unmatched · works due Mar 1, 2026` and `UNMATCHED SIGN-UPS 3` (`Harbor (AO3_Reader) and Lantern Watch`, `The Keeper of Every Letter Along the Snowbound Harbor`) plus a `Load more defaulted assignments` row below the second card.
- **Layout (Dark, Light, Sepia, OLED):**
  - Inside each card, `Open on AO3` is a filled pill button with a compass icon on iPhone vs plain teal text without an icon or pill on Android.
- **Largest text (`big` column):**
  - On iPhone, the bottom buttons (`Report a default`, `Claim a pinch hit`) float without a bar background directly on top of the first card's body text (`The givers for Recipient a...`), and the `Matched / Unmatched / Pinch hits` segmented control stays at tiny default text size.
  - On Android, `Matched / Unmatched / Pinch hits` renders as three separate pills and `Pinch hits` is clipped at the right edge (`Pinch hi`).

### `chmysignup`
- **Missing or extra information (all 5 columns):**
  - Subtitle is `1 request · 1 offer` on iPhone vs `Request 1 of 3 · Offer 1 of 2` on Android.
  - `REQUEST 1` rows show `Star Wars` and `Optional` on iPhone vs `The Lantern Archipelago` and `1 chosen` on Android.
  - The prompt card header is `PROMPT` (all caps) with `A request` (`9 / 1000`) and a 1-line footer on iPhone vs `Prompt` (Title Case) with `A letter reaches an island after the last boat has left.` (`56 / 1000`) and a 3-line requirements footer on Android (which pushes `Offer 1` behind the bottom bar on Android).
- **Layout (Dark, Light, Sepia, OLED):**
  - In the `Any of these is fine` row, iPhone places `Any relationship matches, not only the ones chosen` directly under the title to the left of the switch, whereas Android places it on a separate line below the switch with extra vertical padding.
- **Largest text (`big` column):**
  - On iPhone, the bottom buttons (`Add request`, `Submit sign-up`) float without a solid bar background directly on top of the `Characters / Optional / Additional tags` rows.

### `chprompts`
- **Capture problem (`big` column):**
  - On iPhone `big`, the tile captured the `COLLECTION / Winter Exchange 2026` overview screen instead of `Prompts`.
- **Layout (Dark, Light, Sepia, OLED):**
  - At the bottom of the third card (`HARRY POTTER claimed`), a `⊞ Fill it` pill is partially visible below the floating `New prompt` button on Android, whereas iPhone does not show it above the fold.
- **Largest text (`big` column on Android):**
  - On Android, the `All / Unclaimed / Yours` control stacks vertically into 3 rows inside a card, and the floating `New prompt` button overlaps the text of the first prompt card.

### `chsettings`
- **Missing or extra information (Dark, Light, Sepia, OLED):**
  - In the `Fandoms per request` row under `SIGN-UP REQUIREMENTS`, iPhone displays `0 to 0` whereas Android displays `1 to 3`.
- **Largest text (`big` column):**
  - On iPhone, the header and intro paragraph scale much larger, pushing the `TYPE` card (`Gift Exchange`, `Prompt Meme`) off the bottom of the screen (only `TYPE` is visible at the bottom edge), whereas Android fits the `TYPE` section on screen.

### `chsignups`
- **Missing or extra information (all 5 columns):**
  - iPhone shows `4 sign-ups · open until Feb 1, 2026` and `SIGN-UPS 2` (`Alice` and `Bob (bobby)`, both `UNMATCHED`, with `Good Omens (TV), Naruto` / `Any Fandom`), whereas Android shows `6 sign-ups · closed` and `SIGN-UPS 4` (`AO3_Reader` `MATCHED`, `Harbor (AO3_Reader)` `UNMATCHED`, `mapfold` `MATCHED`, `The Keeper of Every Lamp Along the Snowbound Harbor` `UNMATCHED`, all with `Cloudbound Courier, The Lantern Pier`).
- **Layout:**
  - In Dark, Light, Sepia, and OLED, iPhone places the `UNMATCHED` badge inline next to the username on the left, whereas Android right-aligns larger `MATCHED` / `UNMATCHED` badges next to the trailing chevron.
  - `Load page 2 of 2` is centered plain text on iPhone vs a full-width card row on Android that is partially covered by the pinned bottom action bar.
- **Largest text (`big` column):**
  - On iPhone, the `Your sign-up` button at the bottom overlaps directly on top of the `Bob (bobby)` row text, and the `All / Matched / Unmatched` segmented control stays at tiny default text size.
  - On Android, `All / Matched / Unmatched` changes from a segmented bar into three separate pills, and `Your sign-up` / `Create sign-up` stack vertically into two full-width rows.

### `draftedit`
- **Largest text (`big` column):**
  - On iPhone, the `Title *` field value `Lanterns Above the Mill` truncates to `Lanterns Abo...`, whereas Android shows `Lanterns Above the Mill` in full without truncation.

### `myseries`
- **Missing or extra information (all 5 columns):**
  - Below `Series`, iPhone shows the account subtitle `AO3_Reader` and the section header `SERIES 2`, whereas Android omits both and instead displays `5 works, 54,679 words in the 2 loaded series` **twice** in a row (duplicated subtitle and sub-header).
  - On `The Dawn Cycle` card, Android shows a `⋮` menu icon in the top-right corner, whereas iPhone does not.
- **Layout & Theme:**
  - On `The Dawn Cycle` card, `by Avery Writes` is red/burgundy on iPhone vs green on Android.
  - At the bottom (Dark, Light, Sepia, OLED), `Load More  Page 1 of 2` is inside a rounded card on iPhone vs plain text without a card background on Android.
- **Largest text (`big` column):**
  - On Android, the `STAR WARS`, `COMPLETE`, and `RESTRICTED` badges stack vertically onto three lines, whereas on iPhone they stay on one line at small size.

### `workedit`
- **Largest text (`big` column):**
  - On iPhone, the `Title *` field value `The Weight of Water` truncates to `The Weight o...`, whereas Android displays `The Weight of Water` in full.

### `sec_downloaded`
- **Missing or extra information (all 5 columns):**
  - In the bottom tab bar, `Library` is active on iPhone whereas `Home` is active on Android.
  - On `Sodium Lights` and `Winter Garden`, iPhone shows `by nine_of_wands` / `by frostbitten` in grey and includes `💬 0` and `🔖 0`, whereas Android omits `by ` (coloring the author name), omits zero-count stats, and adds a bottom-right expand chevron (`⌄`).
- **Theme (Light, Sepia, `big`):**
  - The lavender (`Sodium Lights`) and green (`Winter Garden`) card backgrounds are much more saturated on Android than on iPhone.
- **Largest text (`big` column):**
  - On iPhone, `by nine_of_wands` breaks mid-word across two lines (`by nine_of_wan / ds`) and `Doctor Who (2005), Doctor Who` truncates on 1 line (`Doctor Who...`), whereas Android keeps `nine_of_wands` on 1 line and wraps the fandom onto 2 lines.

### `sec_favorites`
- **Missing or extra information & Layout (Dark, Light, Sepia, OLED):**
  - In the bottom tab bar, `Library` is active on iPhone whereas `Home` is active on Android.
  - Under `FAVORITES 2`, iPhone renders compact cards with a leading circular progress ring (`42% READING`, `71% READING`) and single-line `author · words · chapters`, whereas Android renders full-height cards without a progress ring, showing `by <author>`, the summary paragraph, full stats (`comments`, `kudos`, `bookmarks`, `hits`), and a bottom-right expand chevron (`⌄`).
- **Theme (Light, Sepia, `big`):**
  - More saturated lavender and green card fills on Android than on iPhone.
- **Largest text (`big` column):**
  - On Android, the `Works / Authors / Fandoms / Tags` segmented bar stacks vertically into 4 rows inside a card, whereas on iPhone it stays on 1 horizontal row at small text size.

### `sec_finished`
- **Order (all 5 columns):**
  - The two cards under `FINISHED 2` are in opposite order: `Tea in the Jasmine Dragon` then `What the River Keeps` on iPhone vs `What the River Keeps` then `Tea in the Jasmine Dragon` on Android.
- **Missing or extra information (all 5 columns):**
  - In the bottom tab bar, `Library` is active on iPhone whereas `Home` is active on Android.
  - On `Tea in the Jasmine Dragon`, the 4th badge is `🕒 WIP` on iPhone vs `✓ Complete` on Android, and iPhone shows `💬 0 · ♥ 0 · 🔖 0 · 👁 0` whereas Android shows only `♡ 0`.
  - On both cards, iPhone shows `by <author>` in grey and includes `💬 0` and `🔖 0`, whereas Android omits `by ` (coloring the author name) and adds an expand chevron (`⌄`) on `What the River Keeps`.
- **Theme (all 5 columns):**
  - More saturated green and lavender-blue card fills on Android than on iPhone (including in Dark and OLED on `Tea in the Jasmine Dragon`).
- **Largest text (`big` column):**
  - On iPhone, `by uncle_iroh_fan` wraps mid-word as `by uncle_iroh_- / fan`.

### `sec_history`
- **Missing or extra information & Layout (Dark, Light, Sepia, OLED):**
  - In the bottom tab bar, `Library` is active on iPhone whereas `Home` is active on Android.
  - Subtitle count is `11 works` on iPhone vs `12 works` on Android.
  - Under `TODAY 3`, iPhone renders compact single-row cards with a leading circular progress ring (`0%`, `42% READING`, `20% READING`) and short `author · words · chapters` line (so `YESTERDAY 3` and two blurred cards also fit on screen), whereas Android renders full-height cards without a progress ring, adding `by <author>`, summary text, full stats, a yellow star (`★`) on `Sodium Lights`, and a bottom-right expand chevron (`⌄`) (pushing `YESTERDAY 3` off screen).
- **Theme (Light, Sepia, `big`):**
  - More saturated green, lavender, and blue card fills on Android than on iPhone.
- **Largest text (`big` column):**
  - On Android, the `Time / State / Fandom / Flat` segmented bar stacks vertically into 4 rows inside a card, whereas on iPhone it stays on 1 horizontal row at small text size.

### `sec_later`
- **Missing or extra information (all 5 columns):**
  - In the bottom tab bar, `Library` is active on iPhone whereas `Home` is active on Android.
  - On `Paper Cranes` and `Stars Over Tatooine`, iPhone prefixes the author with `by ` in grey and includes `💬 0` and `🔖 0` in the stats line, whereas Android omits `by ` (coloring the author name), omits zero-count stats, and shows an expand chevron (`⌄`) on `Paper Cranes`.
- **Theme (all 5 columns):**
  - In Dark and OLED, the work cards have neutral dark grey backgrounds on iPhone vs warm brown-tinted backgrounds on Android; in Light, Sepia, and `big`, the peach/amber card fills are more saturated on Android.

### `sec_reading`
- **Missing or extra information (all 5 columns):**
  - In the bottom tab bar, `Library` is active on iPhone whereas `Home` is active on Android.
  - Same card differences as `hsec_reading`: iPhone shows `by nine_of_wands` in grey and includes `💬 0` and `🔖 0`, whereas Android omits `by `, omits zero-count stats, and adds an expand chevron (`⌄`).
- **Theme (Light, Sepia, `big`):**
  - More saturated lavender and green card fills on Android than on iPhone.
- **Largest text (`big` column):**
  - On iPhone, `by nine_of_wands` clips at the right edge (`by nine_of_wan`).

### `synconb`
- **Missing or extra information & Layout (Dark, Light, Sepia, OLED):**
  - The top hero icon is a folder with a gear badge on iPhone vs a plain folder without a gear on Android, and the row icons for `Changes May Take Time` and `Using More Than One Device?` differ.
  - `Don't remind me again` uses a trailing toggle switch on iPhone vs a leading checkbox (`☐ Don't remind me again`) on Android.
- **Largest text (`big` column):**
  - On iPhone, the header (`Optional. You can set this up` cut off mid-sentence) and pinned bottom bar occupy the entire viewport, completely hiding all 4 informational rows (`Choose a Folder`, `Works Fully Offline`, `Changes May Take Time`, `Using More Than One Device?`), while `Don't remin...` and `Choose S...` truncate.
  - On Android, the bottom action bar (`Don't remind me again`, `Choose Sync Folder`, `Not Now`) is pushed off the bottom of the screen instead of staying pinned.

### `welcome`
- **Layout:**
  - The top app icon is a red book inside a white squircle tile on iPhone vs a full-bleed red squircle with a white bookmark-heart cutout on Android.
- **Largest text (`big` column):**
  - On iPhone, the header and pinned bottom bar (`</> View on GitHub`, `Continue`) fill the entire screen, completely hiding all 4 feature items (`Built for AO3 Readers`, `Your Privacy Matters`, `Community Built`, `Need Help?`).
  - On Android, the bottom bar (`</> View on GitHub`, `Continue`) is pushed off the bottom of the screen instead of staying pinned.

### `whatsnew`
- **Layout (all 5 columns):**
  - iPhone presents `What's New` (`Version 1.0`) as a full-height modal sheet with a centered title, whereas Android presents `What's New` (`Version 0.2.1`) as a short bottom sheet covering only the bottom quarter of the screen with a left-aligned title.

### `workdetail`
- **Missing or extra information (all 5 columns):**
  - Inside the primary reading action card, iPhone shows a progress ring, `Chapter 1: The Arcade`, and `25/26 minutes ago` next to the play button, whereas Android shows only `Read` and the play button (reflecting an unopened work state on Android).
- **Largest text (`big` column):**
  - On Android, the fandom pill `呪術廻戦 | Jujutsu Kaisen (Manga)` truncates to `呪術廻戦 | Jujutsu Kaisen (M...`. On iPhone, the title and `Chapter 1: The Arcade` card scale much larger, pushing `ARCHIVE WARNINGS` and `FANDOMS` below the fold.

