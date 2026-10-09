# R6: four of R1's features, read in full

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/R6-result.md`. No helper scripts or scratch files left behind.

iOS is at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only). Android is in this
worktree under `android/app/src/main/java/io/github/cidy02/kudos/`.

R1 (`docs/android-port/audits/R1-result.md`) read these in a few lines each. This is the same
reading **in full** for four of them, because each will be built from it. For **each**, write
one section in the result with exactly these parts, read from the code and quoted, never
from memory. "What is on screen" must list every string word for word and in order, each
with its `path:line` and the condition under which it appears. "What it reads and writes"
must quote the Swift that builds each request (the address, every query name and value, when
it is made, what stops it being made twice) and what is done with the answer.

- **Popular tags in the tag picker** (`Features/Search/TagSelectField.swift`; the service in
  `Services/AO3Client.swift` that reads a fandom's most-used tags; any cache of them and
  its lifetime). Exactly when the read is made (on opening the picker? on first focus?),
  for which tag kinds, how many times for one fandom, what is shown while it loads and when
  it fails, what `docs/AO3_NETWORKING_POLICY.md` says about it (quote the rule), and what
  happens with two or more fandoms chosen.
- **"Showing cached AO3 data"** (the banner on the Inbox, the Account profile, an author
  profile and a series): for each of the four, what sets its stale flag, where the cached
  copy comes from and how long it lives, exactly where the banner is drawn and with what
  words, and what clears it. Then what Android's four screens do today when a load fails and
  an older copy exists (`account/AccountInboxPane.kt`, `account/AccountScreen.kt`,
  `author/AuthorProfileScreen.kt`, `app/SeriesWorksScreen.kt` and their view models), with
  `path:line`.
- **"Open Chapter Comments" from the Inbox** (`Features/Account/AccountInboxViews.swift`,
  the destination in `Features/Account/AccountView.swift`, the address in
  `Services/AO3Client+Comments.swift`): when the item shows, its two labels, what it opens
  and with which arguments. Then Android's inbox row menu (`account/AccountInboxPane.kt`)
  and its comments route (`app/Routes.kt`, `Routes.comments`), with `path:line`: what an
  inbox item knows about its chapter there.
- **Read Aloud downloads on Privacy** (`Features/Account/PrivacyDataView.swift`): the
  section, word for word, and where it sits among the others. Then Android's
  `settings/PrivacyDataScreen.kt`: every section in order with its words, so the two can be
  laid side by side.

1. **Where on iOS**: the files and the lines of the view, its model and any service call.
2. **How a reader gets there**: every entry point (the row, button or menu item, in which
   screen, with its label and its `path:line`).
3. **What is on screen**: every section, row, button, menu item, placeholder, footnote, empty
   state, loading state, error and alert, **word for word**, in order, with the condition
   under which each appears.
4. **What it reads and writes**: every network request (method, address, when, how often,
   what stops a repeat), every stored value (the key or the model field, and whether it is in
   the backup), and anything it does to the reader's library.
5. **Where it would go on Android**: the nearest existing screen and file, the components
   already there that draw the same kind of thing (name them with `path:line`), and anything
   Android already has that covers part of it.
6. **Size**: small (a row or a menu item on an existing screen), medium (a sheet or a
   sub-screen), large (a screen with its own data).

If a screen turns out to exist on Android after all, say where, with `path:line`, and stop
there for that screen.

Exact files and lines only. Quote strings as they are written, with their punctuation. For
every request, quote the Swift that builds it (the field names, the values, the order, what
is sent for an empty value, the headers) and the Swift that decides whether AO3 accepted it
(the selectors and status codes), because a brief for a screen that writes to AO3 is built
on exactly those lines.
