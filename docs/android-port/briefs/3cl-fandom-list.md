# Brief 3cl: a category's fandom list is not drawn as iOS draws it (Android)

Found 2026-10-11 while looking at the two apps' Browse screens at large text (iOS T-398).
Side by side at the ordinary size: `shots/3cl/fandom-list-android-left-ios-right.png`.
**Android only. P2** (content is lost in one place; the rest is the redesign not applied).
Brief 3d ported Browse; this screen kept an older form.

## What differs (iOS artboards 1al, 1am; `Features/Search/FandomListView.swift`, `FandomFamilyRows.swift`)

1. **A fandom's qualifier is not shown.** iOS draws "Sherlock" with "(TV)" under it
   (`FandomListRow`: `splitName.qualifier`), and a family's other names under its title. On
   Android "Sherlock (TV)" is just "Sherlock". With several fandoms of one name, that is the
   line that tells them apart. **Check first that the list really drops it** (the demo's
   catalogue is four fandoms): `browse/FandomListScreen.kt`.
2. **A titled top bar, "Fandoms", above the page's own header.** iOS has a back button and
   the filter button over the wash and no title: the header block ("BROWSE / Anime & Manga")
   is the title. Android's other redesigned pages do this through the shell chrome
   (`hasSubjectHeader`, `customTitle = null`).
3. **Rows are plain lines; iOS draws cards** (`.cardRow()`): one card for a single fandom,
   one for a family with its tags inside behind a rule.
4. **"Group variants" is a switch on its own row; iOS has a third chip** in the rail beside
   "A–Z" and "Most works".
5. **The search field is an outlined box at the top with an "Open on AO3" link under it;**
   iOS has a search bar floating at the bottom and no such link on the page. Android keeps
   Material's idiom where it has one: decide whether the field stays at the top (a Material
   search field in the header is fine) and where "Open on AO3" belongs (iOS: nowhere on
   this page).
6. The works count has no document glyph, and the count column is monospaced where iOS's is
   proportional digits. Small.

## What to build

In this order: 1 (content), then 2, 3 and 4 (the page's shape), then decide 5. Each row's
large-text form is in iOS T-398: at the accessibility sizes the name has its own line and
the figures go under it (Android's 2.0× was looked at and reads well as it is, with these
short names).

Look at it in the demo beside the iOS simulator's (`shot.sh browse`, then tap a category),
in Sepia and Dark, and save the pair to `shots/3cl/`.
