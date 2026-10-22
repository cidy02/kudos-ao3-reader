# A80: four screens never put side by side before

## Counts

- **Match:** 1
- **Minor:** 1
- **Differs:** 2
- **Capture problems:** 0

## Differs

- **`login`:** In Dark, Light, Sepia, and OLED, Android shows an extra `Use alternative method` action below the footer that iPhone omits (and in Dark, Light, Sepia, and OLED, iPhone tints `Cancel`, the `Log In` icon, `Create an AO3 account`, and `Forgot your password?` purple/indigo instead of Android's red/Sepia-brown accent, while in Largest text on Android `Cancel` wraps onto a line below `Log In to AO3`).
- **`thread`:** In all 5 columns (`Dark`, `Light`, `Sepia`, `OLED`, `big`), Android displays extra `Chapter 3` and `Hide` pills on the root `StarrySky` comment header row that iPhone omits, and in Largest text (`big`) iPhone truncates that comment's second line to `Absolutely broke...` with a `Read more` button while Android shows it in full.

## Minor

- **`libraryfilters`:** In all 5 columns (`Dark`, `Light`, `Sepia`, `OLED`, `big`), Android presents `Filters` as a partial-height bottom sheet (leaving the `Reading Now` header visible behind it) with a red/Sepia-brown checkmark button and grey `Default >` / `Any rating >` rows, whereas iPhone presents a full-height sheet with a purple/indigo checkmark button and purple `Default` / `Any rating` menu pickers.

## Capture problems

- None.

## Per-screen verdicts

- **`searchfilters` — match:** Layout, content, order, and themes match across all 5 columns (`Filters` half-sheet header with reset and search buttons, `Sort by: Best Match`, `Rating: Any rating`, `Include Not Rated` toggle, and `WARNINGS` rows; Android's `Demo: Doctor Who` saved search behind the sheet and Material dropdown chevrons are in the excluded list).
- **`libraryfilters` — minor:** In all 5 columns (`Dark`, `Light`, `Sepia`, `OLED`, `big`), Android presents `Filters` as a partial-height bottom sheet over the `Reading Now` header with a red/Sepia-brown checkmark button and grey `Default >` / `Any rating >` rows, whereas iPhone presents a full-height sheet with a purple/indigo checkmark button and purple `Default` / `Any rating` menu pickers (`Sort by`, `Rating`, `WARNINGS`, and `CATEGORIES` content and order match).
- **`login` — differs:** In Dark, Light, Sepia, and OLED, Android shows an extra `Use alternative method` action below `These open AO3 in the Browse tab. Come back here to log in afterwards.` that iPhone omits; additionally, iPhone tints `Cancel` (in Dark/Light/OLED), the `Log In` icon (in Dark/Light/OLED), and `Create an AO3 account` / `Forgot your password?` (in Dark/Light/Sepia/OLED) purple/indigo instead of red/Sepia-brown, and in Largest text (`big`) Android wraps `Cancel` below the `Log In to AO3` title.
- **`thread` — differs:** In all 5 columns (`Dark`, `Light`, `Sepia`, `OLED`, `big`), Android adds `Chapter 3` and `Hide` pills next to `Jul 8, 2026` on the root `StarrySky` comment row whereas iPhone omits both pills, and in Largest text (`big`) iPhone collapses the end of that comment to `Absolutely broke...` with a `Read more` action whereas Android renders the full text (`SODIUM LIGHTS` vs `A TEST WORK` work title is demo data).

## Triage (Claude, 2026-10-22, each tile looked at)

- **thread, differs → fixed in the lane (uncommitted at triage):** the chapter badge and the fold
  pill on the root comment. iOS's thread screen passes `showChapterBadge: false` and `collapse: nil`
  (`CommentThreadScreen.swift`); Android now does the same (`CommentConversationRow(showChapterBadge
  = false)`, rows with `collapse = null`), test `CommentThreadScreenTest`. The same pair had already
  found the header under the back button (`0ddb694f`). **Read more at the largest text is not a
  fault:** both clamp a body at 5 lines (`CommentThreadGeometry.collapsedBodyLineLimit`, Android
  `CommentThreadComponents.kt:721`); the iPhone's narrower AX5 line wraps the comment to 5 lines,
  Android's 2.0× to 4. The kicker ("A Test Work") is demo data.
- **login, differs → decided, not changed:** (1) Android's "Use alternative method" opens AO3's own
  sign-in page by hand; iOS switches to it only automatically (A66 found it, Android kept it: an
  extra way in, it makes no request of its own). (2) The colour: both apps default to AO3 red; the
  iPhone's sign-in is a sheet and takes the colour of the screen under it (a purple wash in the shot),
  Android's is a page of its own and takes the app accent. (3) At 2.0× Android puts Cancel under the
  title rather than squeeze it (the large-text branch of the title row). Recorded in DECISIONS.md.
- **libraryfilters, minor:** the sheet's height → Android's is now full height as iOS's (the 520dp
  cap on its scroll area removed). The red checkmark is the decided "tab highlighted on Library
  sections": Android's section pages colour the chrome with the section's wash, iOS's keep
  Library's. The pickers' rows are Android's own chrome (Material).
- **searchfilters, match.**
