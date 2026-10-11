# Brief 3cj: AO3 Preferences help opens a web page on Android; the iPhone shows it in a sheet

Found 2026-10-11 by comparing the two apps' empty states ("Couldn't load help" had no
counterpart). **Android only. P3.**

## What differs

On AO3 Preferences each group and some rows have a "?" that explains the setting. iOS
(`AO3PreferencesView.openHelp`, `:423`) reads AO3's help page and shows it in a sheet:
"Loading help…", then one card per topic (the page's `dl#help`: each `dt` a heading, its
`dd`s the text), a footer note, and on failure "Couldn't load help" with the reason and
"Try Again". Android's "?" (`account/AO3PreferencesScreen.kt:257`, `onOpenHelp`) opens the
help address in the web view (`app/AppNavHost.kt:1281`).

## What iOS does

- `AO3PreferencesActions.loadPreferenceHelp(ref)` (`Services/AO3PreferencesActions.swift:18`):
  one authenticated read of the help address the preferences page itself linked to.
- `AO3Client.parseHelpPage` (`Services/AO3Client+Preferences.swift:109`): title from the
  page's heading (or its `<title>` without " | Archive of Our Own", or "Help"); entries from
  `dl#help`; the paragraphs after the list as a footer; with no `dl#help`, the whole of
  `#main` as one entry.
- Models: `AO3PreferenceHelpRef` (title, url), `AO3PreferenceHelpContent` (title, entries,
  footer, sourceURL), `AO3PreferenceHelpEntry` (heading, body).

## What to build

1. The parser, beside Android's preferences parser, with iOS's fixture for it (look in
   `KudosTests/Fixtures` for the help page its tests use) copied into
   `app/src/debug/assets/fixtures/`.
2. A read in the preferences repository: only an address on AO3, only on the tap, in the
   session the page was read in.
3. A bottom sheet on `AO3PreferencesScreen`: loading, the cards, the footer, the failure with
   "Try Again". The web view stays as the fallback for a host without the repository.
4. The demo answers the help address so it can be seen.
5. `docs/AO3_NETWORKING_POLICY.md`: a user-triggered read of a help page (not a write).

Tests: the parser on the fixture (topics, footer, the no-list page); a failed read shows the
failure and "Try Again" reads again; an address off AO3 is refused.
