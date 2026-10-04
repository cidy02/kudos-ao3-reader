# Brief 3ab: Home's "see all" lists, as iOS draws them

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; don't change Room schemas or backup formats; don't edit `TASKS.md`. Your sandbox can't run
Gradle; Claude builds and tests afterwards, so make it compile by reading the real symbols you use.

Tapping a section's header on Home (Continue Reading, Recently Updated, Favorites, Recently
Opened) opens `android/app/src/main/java/io/github/cidy02/kudos/home/HomeSectionListScreen.kt`. It
is still the old Material screen: a title bar that reads "Section", three loose icons, and a
two-column grid of plain cards (seen on the emulator on 2026-10-04). iOS's is
`kudos-ao3-reader/Features/Home/HomeSectionListView.swift` (the lane is
`/Users/cidy02/kudos-ios-polish`). iOS wins: same behaviour, iOS's strings verbatim.

## Do this, and only this

1. Redraw `HomeSectionListScreen` as `HomeSectionListView`: its header, subtitle, toolbar
   (what is on it, in iOS's order, under iOS's conditions), display modes, selection mode and
   bulk bar, the empty state.
2. The Library's section lists are already redesigned and are the model:
   `library/LibraryScreen.kt` draws them (route `LibrarySection`), with the floating chrome, the
   subject header, `SensitiveWorkRow` cards, the cover-card grid, the privacy blur, the filter
   button and the "…" menu. Read how iOS's two views relate (`HomeSectionListView` and the
   Library's section list) and share what they share: reuse the Library's composables rather than
   writing a second copy of a row, a grid or a toolbar.
3. Mature works: every row or card of a library work must go through the same privacy rule the
   Library's lists use (`LibraryPrivacy.visibility`, blurred or hidden, revealed by a tap or by
   Show mature). Check it; the old screen's handling may differ.
4. Keep the route and its arguments (`Routes.homeSection(id, selecting, selection)`): Home opens
   it in selection mode with works already selected. Keep every callback the screen has today.
5. Don't touch Home itself or any other screen.

## Result

Write `docs/android-port/briefs/3ab-result.md`: every user-visible string before and after; every
callback before and after; what you reused from the Library's lists; how each of the four
sections treats a Mature work in Blur and in Hide mode; anything iOS has that you left out, and
why.
