# Brief 3m-detail-3: the AO3 collection page's leftovers

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; don't change Room schemas or backup formats. Your sandbox can't run Gradle; Claude builds
and tests afterwards, so make it compile by reading the real symbols you use.

`account/AO3CollectionDetailScreen.kt` landed without three things iOS's
`kudos-ao3-reader/Features/Account/AO3CollectionDetailView.swift` has (the iOS lane is
`/Users/cidy02/kudos-ios-polish`). Add them, and nothing else:

1. **The mature-content toggle in the top-right menu.** `account/AccountWorksListScreen.kt`
   already has this menu: a `ToolbarCircleButton` with a ⋮ and a dropdown holding "Hide Mature
   Content" / "Show Mature Content" (and Expand All). Read how that screen passes the choice to
   its rows, and do the same here through `ProvidePushedShellChrome(trailingContent = …)`. Match
   iOS's wording and what its toggle affects on this screen. If the choice should persist the way
   iOS's does (a setting rather than screen state), use the existing settings repository; change
   the screen's signature and its call in `app/AppNavHost.kt` if you must, and say so.
2. **Pull to refresh**, as the other pushed list screens do it (find one that uses Compose's
   pull-to-refresh and copy its pattern). It reloads the header and the selected segment.
3. **Leaving when the collection is gone.** Read what iOS does when the collection has been
   deleted while the page is open, and do the equivalent with what Android has. If Android has no
   such signal, say so in your result and leave it out; don't invent one.

Keep every existing string and callback. Write `docs/android-port/briefs/3m-detail-3-result.md`:
what you added, each new user-visible string, any signature change, anything left out and why.
