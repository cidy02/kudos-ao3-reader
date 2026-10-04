# Brief 3m-detail-2: finish the AO3 collection page (the screen is missing)

Same rules as `briefs/3m-ao3-collections.md`: this worktree only, don't commit, don't run git, the
demo never reaches AO3 (fixtures only), no stub files, no helper scripts or `.orig` files left
behind. You can't build here, so write carefully: every import present, every symbol real.

**State of this worktree.** Your earlier 3m-detail work is applied and staged: the model
(`network/ao3/account/AO3CollectionShow.kt`), the parser (`AO3CollectionParser.kt`), the repository
(`account/AO3CollectionDetailRepository.kt`), the container wiring, and the route in `app/Routes.kt`
and `app/AppNavHost.kt`. **It doesn't compile:** `AppNavHost.kt` calls
`io.github.cidy02.kudos.account.AO3CollectionDetailScreen(slug, title, repository, onOpenWork,
onOpenWebFallback)`, and that screen was never written.

**Do this, and only this:**

1. Write `account/AO3CollectionDetailScreen.kt` with exactly the signature `AppNavHost.kt` calls.
   Port iOS `kudos-ao3-reader/Features/Account/AO3CollectionDetailView.swift`. The iOS lane is now
   `/Users/cidy02/kudos-ios-polish` (local disk, fast). Your own breakdown is in
   `docs/android-port/briefs/3m-detail-result.md`: header (kicker, title, byline, summary), stats,
   the Works / Bookmarks / People segments with their empty states and the ANON badge, and the
   Manage actions.
2. Draw it as the other pushed subject screens do. Read `account/AccountInboxPane.kt` and
   `account/AO3CollectionsScreen.kt` first and reuse what they use: floating chrome
   (`ProvidePushedShellChrome(hasSubjectHeader = true, …)`), the status-bar inset plus 56dp,
   `SubjectHeaderBlock`, the scope wash, subject panels and rows. No Material `Scaffold` or
   `TopAppBar`.
3. Actions that write to AO3 have no native path: show them and open the web fallback through
   `onOpenWebFallback`, as your result notes say.
4. Add a parser unit test on the `ao3_collection_show` fixture
   (`app/src/test/java/io/github/cidy02/kudos/network/ao3/account/AO3CollectionParserTest.kt`),
   asserting the title, the counts, and at least one work and one person.
5. Don't touch any other screen. Don't rename or remove anything that exists.

Write `docs/android-port/briefs/3m-detail-2-result.md`: every user-visible string on the screen,
every callback and what it does, anything iOS has that you left out and why.
