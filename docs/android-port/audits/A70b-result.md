# A70b: Settings pages (`s_*`), iPhone and Android, after A69's fixes

## Differences worth fixing

1. `s_downloads` (Sepia): Android exited Kudos and shows the Android system app launcher (`All apps` drawer) instead of the `Downloads` settings page shown on iPhone.
2. `s_listening` (Light, OLED): Android stays on the top-level `Settings` index screen instead of navigating into the `Listening` sub-page shown on iPhone.
3. `s_about`, `s_account`, `s_privacy` (Largest text / `big` column): Android shows the top-level `Settings` index screen at the largest text size instead of the `About`, `AO3 Account`, or `Privacy` sub-pages shown on iPhone.
4. `s_about` (Dark, Light, Sepia, OLED): Android adds a `SOFTWARE UPDATE` section (`Status` / `Up to date`, `Check Now`) and an alpha-status footer below the main card, and shows `Version 0.2.1` where iPhone shows `Version 1.0` without a software-update section.
5. `s_listening` (Dark, Sepia, Largest text): iPhone titles the second section `Kokoro Neural Engine` (`Download Kokoro (Neural Engine)`), styles `Play Sample`, the `0.9x / 1.0x (default) / 1.1x` preset pills, and `Plain Narration ⌃⌄` / `Automatic ⌃⌄` in the accent colour, and in `big` middle-truncates `Plain…rration` and squashes `1.0x` into `1.`, whereas Android titles the section `Kokoro Pack` (`Download Voice Pack`), styles `Play Sample`, the speed presets, and `Plain Narration >` / `Automatic >` in muted grey, and in `big` flattens the speed presets into unboxed vertical text lines.
6. `s_about`, `s_account`, `s_appearance`, `s_backup`, `s_downloads`, `s_font`, `s_import`, `s_library`, `s_preservation`, `s_privacy`, `s_queues`, `s_reader`, `s_sync` (Light): Android renders settings cards with a medium-grey surface fill against the light page background, whereas iPhone renders settings cards on a pure white surface.
7. `s_account` (Dark, Light, Sepia, OLED): On the `Signed In` row, iPhone shows a leading green checkmark-in-circle icon and green `Signed In` text, whereas Android omits the leading icon and renders `Signed In` in neutral text colour.
8. `s_appearance` (all 5 columns): Android includes a 5th `System` option in the `Theme` picker (`Light | Sepia | Dark | OLED | System`) and wraps the picker into 3 rows at the largest text size (`big`), whereas iPhone shows 4 options (`Light | Sepia | Dark | OLED`) on a single unscaled row in `big`.
9. `s_font` (all 5 columns): Android displays a `Built-in families plus fonts you import (.ttf / .otf).` footer caption below the font card that is absent on iPhone.
10. `s_queues` (Dark, Light, Sepia, OLED): On the disabled `Series limit: 5` stepper, Android's `−` and `+` symbols remain lower-contrast grey-on-grey compared to iPhone's high-contrast symbols.
11. `s_reader` (Largest text / `big` column): On iPhone, the `Scrolled / Paged` segmented control stays at default small text size instead of scaling, whereas on Android it scales with the largest text size.

---

## Per-screen findings

### `s_about`
- **A69 #1 (Android showed the top-level Settings index in all 5 columns):** **Changed** — fixed in Dark, Light, Sepia, and OLED (Android now opens the `About` sub-page), **still there in Largest text (`big`)**, where Android still shows the top-level `Settings` index screen (`DOWNLOADS & STORAGE`, `LIBRARY & SYNC`, `ACCOUNT & PRIVACY`) instead of `About`.
- **New — Missing or extra information (Dark, Light, Sepia, OLED):**
  - Android adds a `SOFTWARE UPDATE` section (`Status` / `Up to date`, `Check Now`) and footer (`Kudos Android is Alpha until it reaches iOS feature parity — expect rougher edges and more frequent updates.`) below the main card; iPhone does not have this section.
  - `Version` is `1.0` on iPhone vs `0.2.1` on Android.
- **New — Theme (Light):** On `Android light`, the card surfaces are tinted medium-grey instead of the white card surface used on `iPhone light`.

### `s_account`
- **A69 #1 (Android showed the top-level Settings index in all 5 columns):** **Changed** — fixed in Dark, Light, Sepia, and OLED (Android now opens the `AO3 Account` sub-page), **still there in Largest text (`big`)**, where Android still shows the top-level `Settings` index screen instead of `AO3 Account`.
- **New — Missing or extra information / theme (Dark, Light, Sepia, OLED):** On the `Signed In` row, iPhone shows a leading green checkmark circle icon and colours `Signed In` green; Android omits the leading icon and renders `Signed In` in standard neutral text colour.
- **New — Theme (Light):** On `Android light`, the card surface is medium-grey instead of white as on `iPhone light`.

### `s_appearance`
- **A69 #8 (top red/burgundy accent wash on Android in Dark, Light, OLED):** **Gone** — Android now uses a neutral unwashed background in Dark, Light, and OLED matching iPhone.
- **A69 #9 (5th `System` option, `Light` selected in all columns, `Match App & Reader Theme` OFF exposing `Reader Theme` picker and different footer):** **Changed** — `Match App & Reader Theme` now defaults to **ON** on Android (so the extra `Reader Theme` segmented picker is gone and the footer text matches iPhone), **but** Android **still** includes a 5th `System` option in the `Theme` picker (`Light | Sepia | Dark | OLED | System`) where iPhone has 4 (`Light | Sepia | Dark | OLED`). *(Stored `Light` highlight across session-theme columns is known.)*
- **A69 largest text (`big` segmented control wrapping):** **Changed** — with `Reader Theme` gone, only the `Theme` picker remains, which still wraps into a 3-row (`2 + 2 + 1`) grid on `Android big` while staying a single unscaled row on `iPhone big`.
- **New — Theme (Light):** On `Android light`, the card surface is medium-grey instead of white as on `iPhone light`.

### `s_backup`
- **A69 #2 (`Android big` showed top-level Settings index):** **Gone** — `Android big` now opens the `Backup` sub-page.
- **A69 #6 (duplicate `← Backup` top bar + seam, extra technical paragraphs, `Deletion signing` section):** **Changed** — the duplicate `← Backup` top bar and horizontal colour seam are **gone**. *(The extra technical notes and `Deletion signing` section with `Demo reading tablet` remain; decided / open owner question.)*
- **A69 #8 (top red/burgundy accent wash on Android in Dark, Light, OLED):** **Gone** — Android now uses a neutral unwashed background.
- **New — Theme (Light):** On `Android light`, the cards use a medium-grey fill instead of the white card surface on `iPhone light`.

### `s_downloads`
- **A69 #8 (top red/burgundy accent wash on Android in Dark, Light, OLED):** **Gone** — Android now uses a neutral unwashed background in Dark, Light, and OLED.
- **New — Wrong screen (Sepia):** In the `Sepia` column (`Android sepia`), Android shows the Android system app launcher (`All apps` drawer) instead of Kudos's `Downloads` page.
- **New — Theme (Light):** On `Android light`, the cards use a medium-grey fill instead of the white card surface on `iPhone light`.

### `s_font`
- **A69 #8 (top red/burgundy accent wash on Android in Dark, Light, OLED):** **Gone** — Android now uses a neutral unwashed background in Dark, Light, and OLED.
- **A69 #21 (extra `Demo font` row and `Built-in families plus fonts you import (.ttf / .otf).` footer caption on Android):** **Still there** — *(the `Demo font` row is known demo data; the `Built-in families plus fonts you import (.ttf / .otf).` footer caption below the card is still present on Android and absent on iPhone).*
- **New — Theme (Light):** On `Android light`, the card uses a medium-grey fill instead of the white card surface on `iPhone light`.

### `s_import`
- **A69 #2 (`Android big` showed top-level Settings index):** **Gone** — `Android big` now opens the `Import` sub-page.
- **A69 #8 (top red/burgundy accent wash on Android in Dark, Light, OLED):** **Gone** — Android now uses a neutral unwashed background in Dark, Light, and OLED.
- **New — Theme (Light):** On `Android light`, the card uses a medium-grey fill instead of the white card surface on `iPhone light`.

### `s_library`
- **A69 #2 (`Android big` showed top-level Settings index):** **Gone** — `Android big` now opens the `Library` sub-page.
- **A69 #8 (top red/burgundy accent wash on Android in Dark, Light, OLED):** **Gone** — Android now uses a neutral unwashed background in Dark, Light, and OLED.
- **New — Theme (Light):** On `Android light`, the card uses a medium-grey fill instead of the white card surface on `iPhone light`.

### `s_listening`
- **A69 #8 (top red/burgundy accent wash on Android in Dark, Light, OLED):** **Gone** in Dark (where the `Listening` sub-page is shown; Light and OLED show the top-level `Settings` index instead).
- **A69 #27 (`Kokoro Neural Engine` vs `Kokoro Pack` wording; picker value styling; `big` truncation on iPhone and unboxed vertical `0.9x / 1.0x (default) / 1.1x` rows on Android):** **Still there** — in Dark, Sepia, and `big`, Android still titles the second section `Kokoro Pack` (`Download Voice Pack`) vs iPhone's `Kokoro Neural Engine` (`Download Kokoro (Neural Engine)`), styles `Plain Narration >` / `Automatic >` in muted grey instead of accent text, and in `big` iPhone still truncates `Plain…rration` / `1.` while Android still flattens `0.9x / 1.0x (default) / 1.1x` into unboxed vertical text lines.
- **New — Wrong screen (Light, OLED):** In both `Light` (`Android light`) and `OLED` (`Android oled`), Android shows the top-level `Settings` index screen instead of navigating into the `Listening` sub-page.
- **New — Theme (Dark, Sepia, `big`):** On Android, `Play Sample` and the `0.9x` / `1.0x (default)` / `1.1x` preset buttons are rendered in muted grey instead of the accent colour used on iPhone.

### `s_preservation`
- **A69 #2 (`Android big` showed top-level Settings index):** **Gone** — `Android big` now opens the `Preservation` sub-page.
- **A69 #8 (top red/burgundy accent wash on Android in Dark, Light, OLED):** **Gone** — Android now uses a neutral unwashed background in Dark, Light, and OLED.
- **New — Theme (Light):** On `Android light`, the card uses a medium-grey fill instead of the white card surface on `iPhone light`.

### `s_privacy`
- **A69 #1 (Android showed the top-level Settings index in all 5 columns):** **Changed** — fixed in Dark, Light, Sepia, and OLED (Android now opens the `Privacy` sub-page), **still there in Largest text (`big`)**, where Android still shows the top-level `Settings` index screen instead of `Privacy`.
- **New — Theme (Light):** On `Android light`, the card surface is medium-grey (with a darker grey active `Blur` segment) instead of the white card surface and white active pill on `iPhone light`.
- **New — Wording (Dark, Light, Sepia, OLED):** iPhone labels the second toggle `Require Face ID to reveal`; Android labels it `Require biometric to reveal`.

### `s_queues`
- **A69 #2 (`Android big` showed top-level Settings index):** **Gone** — `Android big` now opens the `Reading Queues` sub-page.
- **A69 #8 (top red/burgundy accent wash on Android in Dark, Light, OLED):** **Gone** — Android now uses a neutral unwashed background in Dark, Light, and OLED.
- **A69 #26 (low-contrast `−` / `+` symbols on the disabled `Series limit: 5` stepper on Android):** **Changed** — the `−` and `+` symbols on Android are now visible (especially in `big`), though still lower-contrast grey-on-grey in Dark, Light, Sepia, and OLED than iPhone's high-contrast symbols.
- **New — Theme (Light):** On `Android light`, the card uses a medium-grey fill instead of the white card surface on `iPhone light`.

### `s_reader`
- **A69 #8 (top red/burgundy accent wash on Android in Dark, Light, OLED):** **Gone** — Android now uses a neutral unwashed background in Dark, Light, and OLED.
- **A69 largest text (`big` segmented control scaling):** **Still there** — on `iPhone big`, the `Scrolled / Paged` segmented control stays at default small text size, whereas on `Android big` it scales with the largest text size.
- **New — Theme (Light):** On `Android light`, the card surface is medium-grey (with a darker grey active `Scrolled` segment) instead of the white card surface and white active pill on `iPhone light`.

### `s_sync`
- **A69 #2 (`Android big` showed top-level Settings index):** **Gone** — `Android big` now opens the `Sync Folder` sub-page.
- **A69 #7 (missing `Metadata: Ready`, `Check Metadata`, leading row icons, `Last Synced` wording, and `2 deletions skipped` line):** **Gone** — Android's second card now shows `Metadata` / `Ready`, `Choose Sync Folder`, `Last Checked`, and `Check Metadata` with leading icons, and the `2 deletions skipped from an unpaired device` line is gone *(the paired `Demo reading tablet` row remains; known demo data).*
- **A69 #8 (top red/burgundy accent wash on Android in Dark, Light, OLED):** **Gone** — Android now uses a neutral unwashed background in Dark, Light, and OLED.
- **New — Theme (Light):** On `Android light`, the cards use a medium-grey fill instead of the white card surface on `iPhone light`.
