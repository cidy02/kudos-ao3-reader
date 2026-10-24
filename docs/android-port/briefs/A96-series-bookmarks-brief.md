# A96 — the series page's and the author Bookmarks page's last differences

**Agent:** Codex. **Worktree:** `~/kudos-agent-codex`, branch `android/agent-codex-a96` (from the lane's
`67f02ddf`).

## Context

A88d (`docs/android-port/audits/A88d-claude.md`, the `seriesdetail` and `authorbookmarks` bullets)
compared Android's series page and an author's Bookmarks page with the iPhone's and left five minor
differences. Some may come from the demo data rather than the apps: in A94, the iPhone's grey bylines in
Add Works turned out to be its demo, which gives works no author identities (iOS `App/DemoLibrary.swift`
`:25`, `:126`; Android `DemoLibrary.kt:387` seeds a registered identity for every sample work), while iOS
tints a linked name (`UIComponents/AO3AuthorNavigation.swift:196`, `:219-223`).

For each item, decide from **iOS's code** what the iPhone shows with **real AO3 data**, then make
Android match where it differs.

## Items

1. The series card's figures (works, words, bookmarks, …) have no icons on Android; the iPhone's have.
2. The series byline is the fandom's green accent on Android, the app's accent on the iPhone.
3. The work cards' bylines are accent with no "by" on Android, grey with "by" on the iPhone. Check the
   demo-identity question above before changing anything.
4. The series card's fandom line has no icon on Android.
5. The author's Bookmarks page header reads "BOOKMARKS" in small caps on Android, "Bookmarks" on the
   iPhone.

**Not in scope:** card dates (owner question Q28), Android's extra first bookmark card (demo routing, and
showing a library copy as its local card is decided: `DECISIONS.md`, 3gx).

## Files

- iOS, read only (`~/kudos-ios-polish/kudos-ao3-reader/`): `Features/Authors/AO3SeriesDetailView.swift`,
  `Features/Authors/AuthorProfileContentSections.swift`, `Features/Authors/AuthorProfileView.swift`,
  `UIComponents/AO3AuthorNavigation.swift`, `App/DemoLibrary.swift`.
- Android (`android/app/src/main/java/io/github/cidy02/kudos/`): `app/SeriesWorksScreen.kt`,
  `author/AuthorProfileComponents.kt`, `author/AuthorProfileScreen.kt`, `works/detail/WorkDetailIdentity.kt`,
  and whatever they call for bylines and figures.
- Screenshots: `~/kudos-tools/pairs/shots/i_seriesdetail_*.png`, `a_seriesdetail_*.png`,
  `i_authorbookmarks_*.png`, `a_authorbookmarks_*.png`.

## Rules

- §1 of `docs/android-port/LIVING-PROMPT.md` (on this Mac: `~/kudos-android-lane/docs/android-port/`).
- Work only in this worktree. Do not commit, push, switch branches, run Gradle (your sandbox can't; Claude
  builds and tests), sign in, contact archiveofourown.org, or edit `TASKS.md`.
- Use the shared parts (`ui/subject/`) and existing helpers; no new components for one use.

## Output

Write `docs/android-port/briefs/A96-result.md` **first**, then keep it current:
- per item: the iOS evidence (`path:line`), your verdict (a real difference / the demo's / decided), and
  what you changed (`path:line`), or why nothing;
- per test: what it checks, and how it fails with its change reverted.

Add a Robolectric test for each real fix in
`android/app/src/test/java/io/github/cidy02/kudos/app/BriefA96ContentTest.kt`, in the style of
`Brief3hcContentTest.kt` in the same folder.
