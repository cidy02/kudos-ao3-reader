# 3cj result: AO3 Preferences help is a sheet on Android

Landed 2026-10-11 by Claude, alone (Codex and Gemini were out). Gate 2,595.

## What was built

- **Where the "?" is.** AO3 puts most of its help on a section's heading, some on a field's
  label. Android read only a link beside a checkbox, so "Privacy" and "Display" had no "?"
  at all. `AO3PreferencesParser` now reads a help link on a section (its heading, or its
  legend), a toggle, a select and a text field, each with the name AO3 gives the page
  (`aria-label`, then `title`, then the row's own words). iOS also falls back to any link in
  the section; that would lend one field's help to the whole section, so Android does not.
- **The help page.** `parseHelpPage` (iOS `parseHelpPage`): the page's heading as the title;
  `dl#help` as topics (each `dt` a heading, its `dd`s the text, paragraphs kept apart); what
  follows the list as a footer; a page with no list is one topic.
- **The read.** `AO3PreferencesRepository.loadHelp`: one read on the tap; an address that is
  not an AO3 `/help/` page is refused before asking.
- **The sheet.** `account/AO3PreferencesScreen.kt`: "Loading help…", a card for each topic,
  the footer, and on failure "Couldn't load help" with the reason, "Try Again" and "Open on
  AO3" (the web view, as before). A newer tap or a closed sheet drops a late answer.

## Two faults found on the way, both fixed

- **Section titles carried the "?" glyph** ("Privacy ?"): the heading's text was read with
  the help link inside it. A test had been written to match titles by prefix because of it.
- **Selects and text fields were shown under their raw field names** ("preference[skin_id]",
  "preference[time_zone]"): AO3's labels point at a control's id, and the parser asked by
  name. Seen on the emulator; they read "Your site skin", "Your time zone" and "Browser page
  title format" now.

## Tests

`AO3PreferencesParserTest` (+4): help on a section, a toggle and a text field, none lent to a
section without its own; the labels; the help page's topics and footer; a page without the
list, and an empty one. `PreferenceHelpReadTest` (3): one read; an address off AO3 or not a
help page is not read; a failed read and an unreadable page are failures to show.

## Seen on the emulator (demo)

"?" on Privacy opens the sheet with its three topics; "?" on Display and on "Browser page
title format" (pages the demo does not have) show "Couldn't load help / AO3 could not find
that page." with both buttons; "Try Again" asks again.

## Not done, and not checked

- A real AO3 help page was not read (no request is made to AO3, by rule). The parser follows
  iOS's on iOS's own fixture.
- iOS reads the help page without the session; Android's preferences repository has only the
  signed-in client and uses it. The page is public either way.
- No screen-level test of the sheet.
