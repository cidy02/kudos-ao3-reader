# Brief 3z: a fandom's works and a series, as iOS draws them

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; don't change Room schemas or backup formats; don't edit `TASKS.md`. Your sandbox can't run
Gradle; Claude builds and tests afterwards, so make it compile by reading the real symbols you use.

Seen on the emulator on 2026-10-03 (the screens are under
`android/app/src/main/java/io/github/cidy02/kudos/`):

- `browse/FandomWorksScreen.kt` (the works of a fandom, opened from Browse) has a subject header,
  but the shell also draws a title bar reading "Works" above it, and the screen's filter, expand
  and select buttons sit inside the page instead of on the floating row.
- `app/SeriesWorksScreen.kt` (a series, opened from Work detail, the author pages and the
  dashboard) is still the old Material screen: a title bar and a plain list.
- `browse/TagWorksScreen.kt` and `author/AuthorWorksScreen.kt` are old Material screens too, and
  nothing navigates to them: `Routes.tagWorks` and `Routes.authorWorks` have no callers.

iOS (the lane is `/Users/cidy02/kudos-ios-polish`): `kudos-ao3-reader/Features/Browse/NativeBrowseView.swift`
and `kudos-ao3-reader/Features/Authors/AO3SeriesDetailView.swift`. iOS wins: same behaviour, iOS's
strings verbatim.

## Do this

1. **A fandom's works.** Make `FandomWorksScreen` match `NativeBrowseView`. Use the floating
   chrome as the other pushed subject screens do (`ProvidePushedShellChrome(hasSubjectHeader =
   true, trailingContent = …)`, the status-bar inset plus 56dp above `SubjectHeaderBlock`; read
   `account/AO3CollectionDetailScreen.kt` and `account/AccountWorksListScreen.kt`), with the
   buttons iOS has in its toolbar on that row, in iOS's order. Rows are the shared
   `SensitiveWorkRow`; paging is `KudosPaginationBar`.
2. **A series.** Make `SeriesWorksScreen` match `AO3SeriesDetailView`, the same way.
3. **Tags.** Read what iOS does when a tag is tapped on a work row or on Work detail. If it opens
   that tag's works in the same view as a fandom's, make Android do the same: one screen for both
   (don't keep a second copy), reached from the same taps iOS has. If iOS does something else,
   do that. Say which it was.
4. **An author's works.** Android's author profile has a Works tab. If that is where iOS shows an
   author's works too, `AuthorWorksScreen` is unused: leave it, and list it in the result as
   unused. Don't delete files.
5. Keep every string and callback these screens have today, unless iOS lacks it (then list it).

## Result

Write `docs/android-port/briefs/3z-result.md`: what changed on each screen; every user-visible
string before and after; every callback before and after; what a tag tap does on iOS and now on
Android; which screens are now unused; anything iOS has that you left out, and why.
