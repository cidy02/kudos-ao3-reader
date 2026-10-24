# A98 — A97's Android differences

**Agent:** Codex. **Worktree:** `~/kudos-agent-codex`, branch `android/agent-codex-a98` (from the lane's
`82626348`).

## Context

A97 compared 38 re-shot screen pairs (`~/kudos-tools/out/a97/A97-claude-notes.md`; tiles in
`~/kudos-tools/pairs/tiles-a97/<name>.png`, iPhone row above Android: Dark, Light, Sepia, OLED, largest).
Every earlier difference is gone; these are left. For each, first decide from **iOS's code** what the
iPhone does with real data (the demo data differ between the apps), then make Android match where it
really differs. iOS is read only, in `~/kudos-ios-polish/kudos-ao3-reader/`.

## Items

1. **`readerspeech`, the current speed's pill.** Android's "1.0x (default)" is faint grey on a pale fill in
   Light and Sepia. The iPhone fixed the same fault in T-441: the pill is drawn in primary ink on a neutral
   fill in every theme and stays disabled (`RatePillStyle`, `Features/ReaderReadium/ReaderSpeechAuditionHarness.swift`).
   Match it in the reader's speech sheet and on Settings › Listening.
2. **`readerspeech`, Sample Text's value** is the accent on Android, primary ink on the iPhone. Check iOS's
   code and match.
3. **`pagejump`, "Last (3)"** is the red accent in Light on Android; Sepia's is the page's tan, as the
   iPhone's pager uses the page's palette (`Features/Search/SearchPaginationBar.swift`). Light should take
   the page's palette too.
4. **`libraryfilters`, the ✓ and the menu values** take the section's palette on the iPhone (purple for
   Reading Now) and the app's red on Android (`Features/Library/LibraryFilterPanel.swift`,
   `LibraryFilters.swift`).
5. **`chsettingsedit`, the page's palette** is teal on the iPhone and red on Android. The iPhone's subtitle
   shows the slug ("winter_exchange · 4 sign-ups"), Android's the title. Find what each app hues the page
   from (`Features/Challenges/ChallengeSettingsView.swift`), and match iOS's source and subtitle. Keep it
   consistent with the other challenge pages (3hd's note on `AO3ChallengeSignUpsScreen.kt` hues from the
   title or slug).
6. **`recovery`**: Android's time has seconds ("Oct 22, 2026 10:57:49 PM"); the iPhone's has none. The
   iPhone also says "The text on the form has changed since this copy began. Review the copy before
   restoring it." when the form differs from the copy. Check Android says it in the same case (the demo may
   simply not differ on Android).
7. **`works` (My Works)**: the subtitle is the account name ("AO3_Reader") on the iPhone, totals
   ("3 works · 248,400 words · 3,812 kudos") on Android, and the toolbar order differs (iPhone: +, filter,
   select, more). Match iOS.
8. **`chapterpicker`**: the chapter rows' glyph is a filled book on Android, an outline book on the iPhone.
9. Small: `prefhelp`'s sheet title is regular weight on Android, semibold on the iPhone.

**Not in scope:** Material date fields (decided, A82), card dates (owner Q28), the iPhone's own faults,
anything `DECISIONS.md` or `audits/A88-triage.md` ("Decided, not changed") already settles.

## Rules

- §1 of `~/kudos-android-lane/docs/android-port/LIVING-PROMPT.md`. Work only in this worktree. Do not
  commit, push, switch branches, run Gradle (Claude builds and tests), sign in, contact
  archiveofourown.org, or edit `TASKS.md`.
- Use the shared parts (`ui/subject/`) and existing helpers.
- Tests: don't use `TextLayoutResult.hasVisualOverflow` to mean "cut": a one-line ellipsised `Text`
  reports it with nothing cut (A96). Check `isLineEllipsized` instead.

## Output

Write `docs/android-port/briefs/A98-result.md` **first**, then keep it current: per item, the iOS
evidence (`path:line`), your verdict (real / the demo's / decided), and what you changed (`path:line`) or
why nothing; per test, what it checks and how it fails with its change reverted. Tests go in
`android/app/src/test/java/io/github/cidy02/kudos/app/BriefA98ContentTest.kt`, in the style of
`BriefA96ContentTest.kt`.
