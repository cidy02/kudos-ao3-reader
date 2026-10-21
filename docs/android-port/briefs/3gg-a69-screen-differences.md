# Brief 3gg: A69's screen differences (Android against the iPhone)

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests, looks on the emulator and lands it. Do not edit
`TASKS.md`. Create `docs/android-port/briefs/3gg-result.md` first; write each item into it as
you finish it: **fixed / not real / left**, `path:line`, the iOS code followed
(`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`, read-only), the test added.

Rules: iOS is the source of truth for layout, content and order; Android's navigation and chrome
are its own (Material top bar and icon buttons, the tab bar, a pager's arrows may stay Material);
"visual and UX parity with no lost features or information" (owner, 2026-10-20): where Android
shows information iOS does not, keep it and say so in the result rather than removing it.

The images are tiles in `/Users/cidy02/kudos-tools/pairs/tiles/<screen>.png` (top row iPhone,
bottom row Android; columns Dark, Light, Sepia, OLED, Sepia at the largest text). Gemini's index
is `docs/android-port/audits/A69-result.md` (numbers below are its). Claude confirmed 1-4 by eye;
**check every other item in iOS's code before changing anything**.

1. **Settings › Backup (#6).** Reached in one tap since 3gb, Android's Backup screen draws its own
   Material top bar "← Backup" and a red wash band above the "SETTINGS / Backup" header, so the
   title shows twice with a colour seam. Make it a Settings page like the others (the pushed shell
   chrome, one header). Keep its extra notes and the Deletion signing section (owner question 9 is
   open: no information removed).
2. **Settings pages' wash (#8).** iOS draws the Settings sub-pages on the plain page colour; the
   wash is the hub's only (`Settings/SettingsView.swift`, `SettingsHeaderBlock.swift`). Android
   washes every sub-page. Match iOS in all four themes.
3. **Dashboard's series card (#25).** iOS gives "Recent series" cards their fandom wash
   (`Features/Authors/AuthorDashboardSections.swift` or the series card it uses); Android's is a
   plain grey card.
4. **Marked for Later's Unmark (#17)** sits inside each card's bottom-right on iOS
   (`Features/Bookmarks/AO3AccountWorksList.swift`); Android puts it on its own row under the card.
5. **Inbox (#24, #23).** iOS draws a comment's Reply as a filled pill with its icon; Android as plain
   accent text. iOS's filter button shows no badge for the Unread/Awaiting/Replied segment; Android
   shows "1". At the largest text Android adds a "User" badge under the name that the other columns
   don't show: find why.
6. **AO3 Preferences (#10):** the ACCOUNT rows' order and wording as iOS (`AO3PreferencesView.swift`).
7. **Sync Folder (#7):** iOS's card shows Metadata (Ready / Needs Retry), Last Checked and Check
   Metadata / Retry Metadata Prep, with leading icons (`Settings/SettingsSyncFolderPage.swift`).
   An earlier verifier called this "not real": check when iOS shows those rows and match it.
8. **Reading Queues settings (#26):** the disabled "Series limit" stepper's − and + are almost
   invisible on Android in every theme; use the disabled colour iOS uses.
9. **History's cover cards (#20):** Android prints the author ("Anonymous"); iOS omits it on those
   cards. Check iOS's rule (it may omit "Anonymous" only).
10. **Search (#22):** saved-search rows show a trash icon on Android; how does iOS delete one (swipe,
    edit mode)? Match iOS's way, keeping the action reachable. Also: iOS hides the tab bar on that
    screen in the tile; check whether that is iOS's rule there.
11. **Browse at the largest text (#12):** Android leaves out "Jump Back In"; iOS keeps it.
12. **Own Works, Drafts, Subscriptions (#4, #5, #3):** compare each with iOS's code (the own works
    card's figure strip and its "…" button; the drafts' expiry pills and "Created" footer; the
    Subscriptions sections). Change what differs from iOS; where Android shows information iOS
    lacks, keep it and list it.
