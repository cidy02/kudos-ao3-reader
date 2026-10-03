# Brief 3m-detail: the AO3 collection page, ported from iOS

Same rules as `briefs/3m-ao3-collections.md`: worktree only, don't commit, offline Gradle gate,
emulator-5554, the demo never reaches AO3 (fixtures only), no stub files, no helper scripts or
`.orig` files left behind.

One screen only, done properly: iOS `Features/Account/AO3CollectionDetailView.swift` (iOS lane
`/Users/cidy02/Documents/AO3_App_OpenSource/.claude/worktrees/handoff-documentation-2151af/.claude/worktrees/polish`;
reads there can be slow because of iCloud).

1. Read the iOS view end to end: its header (kicker, name, title, badges, maintainers), the
   summary or intro, facts, the sections it links to (works and bookmarks, participants,
   challenge pages), and every action it offers. List them in your result before you start
   coding.
2. Android has no collection page yet; tapping a card on the list (`account/AO3CollectionsScreen.kt`)
   currently goes elsewhere. Add an `AO3CollectionDetail` route (`app/Routes.kt` and
   `app/AppNavHost.kt` are yours for this route only) and the screen, fed from the demo fixture
   `ao3_collection_show` through the existing AO3 client and parser (extend the parser if fields are
   missing, with a parser unit test on the fixture).
3. Use floating chrome (`ProvidePushedShellChrome(hasSubjectHeader = true, …)`), the status-bar
   inset plus 56dp, then `SubjectHeaderBlock`, the scope wash, and subject panels and rows. Hide the
   tab bar: add the route to `Routes.tabBarHiddenBases`, as iOS's `subjectScreenWash` does.
4. Any action that writes to AO3 (join, leave, edit) must go through the existing write paths and
   only ever hit the fixtures. If no write path exists, show the action and open it on the web
   fallback, as Android does for other unported AO3 actions. Say which in your result.
5. Wire the list's card tap to the new screen.

Save Dark shots to `docs/android-port/shots/3m-detail/`. Write `docs/android-port/briefs/3m-detail-result.md`.
