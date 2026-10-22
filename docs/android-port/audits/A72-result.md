# A72: the final side-by-side check, all 65 screens

## Counts

- **Match:** 43
- **Minor:** 18
- **Differs:** 4
- **Capture problems:** 8 screens (`account`, `ao3colls`, `collections`, `more`, `s_library`, `chprompts`, `sec_downloaded`, `sec_finished`)

## Differs

- **`ao3coll`:** In all 5 columns, Android displays the maintainer subtitle `AO3_Reader, comod` below `Winter Exchange 2026` whereas iPhone omits it.
- **`browse`:** In Largest text (`big`), Android omits the `JUMP BACK IN` section completely (and in Dark, Light, Sepia, and OLED, Android places `2 downloaded` on the same line as `4 fandoms · ~636K works` instead of wrapping it onto a second line as on iPhone).
- **`history`:** In Dark, Light, Sepia, and OLED on Android, the `THIS MONTH 1` section is ordered after `EARLIER 1` (`THIS WEEK 1` → `EARLIER 1` → `THIS MONTH 1`).
- **`chprompts`:** In Largest text (`big`), Android stacks the `All / Unclaimed / Yours` picker vertically and the floating `New prompt` button overlaps the bottom of the first prompt card (while `iPhone big` captured the parent `Winter Exchange 2026` collection screen instead of `Prompts`).

## Minor

- **`account`:** In all columns, iPhone shows the AO3 logo on a white avatar circle whereas Android shows a generic person-in-circle icon on a tinted circle.
- **`bookmarks`:** In all columns, Android uses outlined `REC`/`PRIVATE` pills instead of iPhone's filled pills (with deeper pastel card washes in Light, Sepia, and Largest text, and `With notes` slightly clipped at the right edge in Largest text on Android).
- **`collections`:** In Largest text (`big`), Android reflows each collection card's 2×2 mini-cover grid into 4 stacked horizontal rows.
- **`dashboard`:** In Largest text (`big`), Android renders the 2×2 AO3 rating/warning symbol grid below the author line on `Two Voices at Dawn` whereas iPhone hides it.
- **`queues`:** In Largest text (`big`) on Android, the search placeholder `Search queues, tags and works` is clipped to `Search queues, tags and`.
- **`s_appearance`:** In all 5 columns, Android includes a 5th `System` option in the `Theme` picker (wrapping into 3 rows in Largest text) whereas iPhone shows 4 options (`Light`, `Sepia`, `Dark`, `OLED`).
- **`s_font`:** In all 5 columns, Android displays a `Built-in families plus fonts you import (.ttf / .otf).` footer caption below the card that iPhone omits.
- **`s_listening`:** In all columns, Android titles the second section `Kokoro Pack` (`Download Voice Pack`) instead of `Kokoro Neural Engine`, and in Largest text (`big`) Android renders the `0.9x / 1.0x (default) / 1.1x` speed presets as unboxed vertical text lines.
- **`works`:** In Dark, Light, Sepia, and OLED, Android includes a bottom-right `⋮` menu icon and 4-column stat bar (`KUDOS · COMMENTS · HITS · BOOKMARKS` vs `KUDOS · HITS`) inside the work card, and in Largest text (`big`) Android shows the 2×2 AO3 symbol grid below the author line.
- **`author`:** In all columns, iPhone shows the AO3 logo on a white avatar square and a hand-stop icon whereas Android shows a framed-person placeholder on a tinted square and a circle-slash icon (and in Largest text, Android wraps the 4-tab picker into a 2×2 grid).
- **`chassign`:** In Dark, Light, Sepia, and OLED, Android renders `Open on AO3` as plain accent text rather than a compass-icon pill button (with a `Load more defaulted assignments` card below), and in Largest text (`big`) Android renders the filter tabs as capsule pills (`Pinch hi` clipped at the right edge) and stacks the bottom action buttons vertically.
- **`chsignups`:** In Dark, Light, Sepia, and OLED, Android right-aligns the `MATCHED`/`UNMATCHED` pills and renders `Load page 2 of 2` as an outlined card button (and in Largest text uses capsule filter pills and vertically stacked bottom buttons).
- **`comments`:** In all columns, Android adds a `Reply` label next to each comment's reply arrow icon (and in Largest text truncates the `Newest` sort chip to `Newe...`).
- **`queue`:** In Largest text (`big`) on Android, the `WIP 3` filter chip is clipped at the right edge.
- **`sec_finished`:** In Dark and Light, Android orders the two finished works in reverse order (and in OLED omits `· most recently read first` from the subtitle while highlighting the sort button).
- **`synconb`:** In all columns, Android uses a leading checkbox for `Don't remind me again` instead of a trailing toggle switch, and in Largest text (`big`) scrolls the bottom action buttons below the fold instead of pinning them.
- **`welcome`:** In all columns, iPhone shows a red book icon on a white squircle whereas Android shows a white bookmark-heart cutout on a full-bleed red squircle, and in Largest text (`big`) Android scrolls the bottom action buttons below the fold instead of pinning them.
- **`workdetail`:** In Largest text (`big`) on Android, the fandom chip `呪術廻戦 | Jujutsu Kaisen (Manga)` truncates to `呪術廻戦 | Jujutsu Kaisen (M...` instead of wrapping.

## Capture problems

- **`account` (Dark, Android):** System `Kudos isn't responding` ANR dialog over the screen.
- **`ao3colls` (Dark, Android):** System `Kudos isn't responding` ANR dialog over the screen.
- **`collections` (Dark, Android):** System `Kudos isn't responding` ANR dialog over the screen.
- **`more` (OLED, Android):** System `Kudos isn't responding` ANR dialog over the screen.
- **`s_library` (Dark, Android):** System `Kudos isn't responding` ANR dialog over the screen.
- **`chprompts` (Largest text / `big`, iPhone):** Captured the parent `Winter Exchange 2026` collection screen instead of `Prompts`.
- **`sec_downloaded` (Dark, Light, OLED, and Largest text / `big`, Android):** Captured a blank screen in 4 of the 5 columns (Sepia rendered normally).
- **`sec_finished` (Sepia and Largest text / `big`, Android):** Captured a blank white screen in Sepia and Largest text.

## Per-screen verdicts

- **`account` — minor (capture problem in Dark on Android):** In all columns, iPhone shows the AO3 logo on a white avatar circle whereas Android shows a generic person-in-circle icon on a tinted circle; in Dark, Android shows a system `Kudos isn't responding` dialog over the screen.
- **`ao3coll` — differs:** In all 5 columns, Android displays the maintainer subtitle `AO3_Reader, comod` below `Winter Exchange 2026` whereas iPhone omits it.
- **`ao3colls` — match (capture problem in Dark on Android):** Layout, content, order, and themes match across all columns; in Dark, Android shows a system `Kudos isn't responding` dialog over the screen.
- **`bookmarks` — minor:** In all columns, Android uses outlined `REC`/`PRIVATE` pills instead of iPhone's filled pills (with deeper pastel card washes in Light, Sepia, and Largest text, and `With notes` slightly clipped at the right edge in Largest text on Android).
- **`browse` — differs:** In Largest text (`big`), Android omits the `JUMP BACK IN` section completely (and in Dark, Light, Sepia, and OLED, Android places `2 downloaded` on the same line as `4 fandoms · ~636K works` instead of wrapping it onto a second line as on iPhone).
- **`collections` — minor (capture problem in Dark on Android):** In Largest text (`big`), Android reflows each collection card's 2×2 mini-cover grid into 4 stacked horizontal rows; in Dark, Android shows a system `Kudos isn't responding` dialog over the screen.
- **`dashboard` — minor:** In Largest text (`big`), Android renders the 2×2 AO3 rating/warning symbol grid below the author line on `Two Voices at Dawn` whereas iPhone hides it.
- **`deleted` — match:** Layout, content, order, and themes match across all 5 columns.
- **`drafts` — match:** Layout, content, order, and themes match across all 5 columns.
- **`history` — differs:** In Dark, Light, Sepia, and OLED on Android, the `THIS MONTH 1` section is ordered after `EARLIER 1` (`THIS WEEK 1` → `EARLIER 1` → `THIS MONTH 1`).
- **`home` — match:** Layout, content, order, and themes match across all 5 columns.
- **`inbox` — match:** Layout, content, order, and themes match across all 5 columns.
- **`insights` — match:** Layout, content, order, and themes match across all 5 columns.
- **`later` — match:** Layout, content, order, and themes match across all 5 columns.
- **`library` — match:** Layout, content, order, and themes match across all 5 columns.
- **`more` — match (capture problem in OLED on Android):** Layout, content, order, and themes match across all columns; in OLED, Android shows a system `Kudos isn't responding` dialog over the screen.
- **`prefs` — match:** Layout, content, order, and themes match across all 5 columns.
- **`queues` — minor:** In Largest text (`big`) on Android, the search placeholder `Search queues, tags and works` is clipped to `Search queues, tags and`.
- **`s_about` — match:** Layout, content, order, and themes match across all 5 columns.
- **`s_account` — match:** Layout, content, order, and themes match across all 5 columns.
- **`s_appearance` — minor:** In all 5 columns, Android includes a 5th `System` option in the `Theme` picker (wrapping into 3 rows in Largest text) whereas iPhone shows 4 options (`Light`, `Sepia`, `Dark`, `OLED`).
- **`s_backup` — match:** Layout, content, order, and themes match across all 5 columns.
- **`s_downloads` — match:** Layout, content, order, and themes match across all 5 columns.
- **`s_font` — minor:** In all 5 columns, Android displays a `Built-in families plus fonts you import (.ttf / .otf).` footer caption below the card that iPhone omits.
- **`s_import` — match:** Layout, content, order, and themes match across all 5 columns.
- **`s_library` — match (capture problem in Dark on Android):** Layout, content, order, and themes match across all columns; in Dark, Android shows a system `Kudos isn't responding` dialog over the screen.
- **`s_listening` — minor:** In all columns, Android titles the second section `Kokoro Pack` (`Download Voice Pack`) instead of `Kokoro Neural Engine`, and in Largest text (`big`) Android renders the `0.9x / 1.0x (default) / 1.1x` speed presets as unboxed vertical text lines.
- **`s_preservation` — match:** Layout, content, order, and themes match across all 5 columns.
- **`s_privacy` — match:** Layout, content, order, and themes match across all 5 columns.
- **`s_queues` — match:** Layout, content, order, and themes match across all 5 columns.
- **`s_reader` — match:** Layout, content, order, and themes match across all 5 columns.
- **`s_sync` — match:** Layout, content, order, and themes match across all 5 columns.
- **`search` — match:** Layout, content, order, and themes match across all 5 columns.
- **`settings` — match:** Layout, content, order, and themes match across all 5 columns.
- **`subs` — match:** Layout, content, order, and themes match across all 5 columns.
- **`works` — minor:** In Dark, Light, Sepia, and OLED, Android includes a bottom-right `⋮` menu icon and 4-column stat bar (`KUDOS · COMMENTS · HITS · BOOKMARKS` vs `KUDOS · HITS`) inside the work card, and in Largest text (`big`) Android shows the 2×2 AO3 symbol grid below the author line.
- **`author` — minor:** In all columns, iPhone shows the AO3 logo on a white avatar square and a hand-stop icon whereas Android shows a framed-person placeholder on a tinted square and a circle-slash icon (and in Largest text, Android wraps the 4-tab picker into a 2×2 grid).
- **`chassign` — minor:** In Dark, Light, Sepia, and OLED, Android renders `Open on AO3` as plain accent text rather than a compass-icon pill button (with a `Load more defaulted assignments` card below), and in Largest text (`big`) Android renders the filter tabs as capsule pills (`Pinch hi` clipped at the right edge) and stacks the bottom action buttons vertically.
- **`chmysignup` — match:** Layout, content, order, and themes match across all 5 columns.
- **`chprompts` — differs (capture problem in Largest text on iPhone):** In Largest text (`big`), Android stacks the `All / Unclaimed / Yours` picker vertically and the floating `New prompt` button overlaps the bottom of the first prompt card; `iPhone big` captured the parent `Winter Exchange 2026` collection screen instead of `Prompts`.
- **`chsettings` — match:** Layout, content, order, and themes match across all 5 columns.
- **`chsignups` — minor:** In Dark, Light, Sepia, and OLED, Android right-aligns the `MATCHED`/`UNMATCHED` pills and renders `Load page 2 of 2` as an outlined card button (and in Largest text uses capsule filter pills and vertically stacked bottom buttons).
- **`collection` — match:** Layout, content, order, and themes match across all 5 columns.
- **`colmaint` — match:** Layout, content, order, and themes match across all 5 columns.
- **`colmod` — match:** Layout, content, order, and themes match across all 5 columns.
- **`colsettings` — match:** Layout, content, order, and themes match across all 5 columns.
- **`comments` — minor:** In all columns, Android adds a `Reply` label next to each comment's reply arrow icon (and in Largest text truncates the `Newest` sort chip to `Newe...`).
- **`draftedit` — match:** Layout, content, order, and themes match across all 5 columns.
- **`hsec_reading` — match:** Layout, content, order, and themes match across all 5 columns.
- **`hsec_updated` — match:** Layout, content, order, and themes match across all 5 columns.
- **`mycopy` — match:** Layout, content, order, and themes match across all 5 columns.
- **`myseries` — match:** Layout, content, order, and themes match across all 5 columns.
- **`queue` — minor:** In Largest text (`big`) on Android, the `WIP 3` filter chip is clipped at the right edge.
- **`reader` — match:** Layout, content, order, and themes match across all 5 columns.
- **`sec_downloaded` — match (capture problem in Dark, Light, OLED, and Largest text on Android):** Layout, content, order, and theme match in Sepia; in Dark, Light, OLED, and Largest text (`big`), Android captured a blank screen.
- **`sec_favorites` — match:** Layout, content, order, and themes match across all 5 columns.
- **`sec_finished` — minor (capture problem in Sepia and Largest text on Android):** In Dark and Light, Android orders the two finished works in reverse order (and in OLED omits `· most recently read first` from the subtitle while highlighting the sort button); in Sepia and Largest text (`big`), Android captured a blank white screen.
- **`sec_history` — match:** Layout, content, order, and themes match across all 5 columns.
- **`sec_later` — match:** Layout, content, order, and themes match across all 5 columns.
- **`sec_reading` — match:** Layout, content, order, and themes match across all 5 columns.
- **`synconb` — minor:** In all columns, Android uses a leading checkbox for `Don't remind me again` instead of a trailing toggle switch, and in Largest text (`big`) scrolls the bottom action buttons below the fold instead of pinning them.
- **`welcome` — minor:** In all columns, iPhone shows a red book icon on a white squircle whereas Android shows a white bookmark-heart cutout on a full-bleed red squircle, and in Largest text (`big`) Android scrolls the bottom action buttons below the fold instead of pinning them.
- **`whatsnew` — match:** Layout, content, order, and themes match across all 5 columns.
- **`workdetail` — minor:** In Largest text (`big`) on Android, the fandom chip `呪術廻戦 | Jujutsu Kaisen (Manga)` truncates to `呪術廻戦 | Jujutsu Kaisen (M...` instead of wrapping.
- **`workedit` — match:** Layout, content, order, and themes match across all 5 columns.


## Triage (Claude, 2026-10-22)

Each item checked in both apps' code or on a device before acting.

- **history, not a fault.** Both apps keep AO3's page order and start a new group where the order
  changes bucket (iOS `AO3HistoryVisitGrouping`); the demo page's order is this week, earlier, this
  month. The iPhone frame ends before its third group.
- **ao3coll, an iPhone bug, fixed (T-426, `c6b7423d`).** iOS looked for `a.owner` / `a.mod`; AO3's
  profile puts the class on the list item, so a real page named nobody. Seen on the simulator after.
- **browse at 2x, fixed on Android (`cd04b55a`).** A zero-height first list item counts as scrolled
  past, so Jump Back In grew above the top. The "2 downloaded" wrap is the same content.
- **chprompts:** the iPhone's big frame is retaken (it now shows Prompts); both apps float New prompt
  over the list with room to scroll past it.
- **Not app behaviour:** the account Works subtitle (iOS waits for its counts cache; decision
  2026-10-11), the demo libraries' sample data (Android's extra Ashfall bookmark, the Finished works'
  read dates and completion), the default user icon (both load AO3's image; Android's demo blocks it).
- **Kept as Android's (DECISIONS 2026-10-22):** the System theme, the Font page's footer, the sync
  setup's checkbox, the Welcome icon art, the paged assignments list (owner question 16).
- **Everything else** went to Codex 3gm and landed in `1bbefdfd`: wrapping chips and placeholder,
  the queue rail, Comments' sort chip and reply arrow, the Listening section's name and presets,
  the collection mosaic, the page capsule, the challenge screens' pills, badges and footers, the
  Block icon and the four-tab picker. Rec/Private pills and the 2×2 symbol grid at large text
  already matched (the iPhone draws the grid lower down).
- **Capture problems** (ANR frames, blank frames) are reshot in A76.
